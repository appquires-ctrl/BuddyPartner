const crypto = require('crypto');
const db = require('../../db');
const { cacheService } = require('../../services/cache.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { MessagingService } = require('../messaging/messaging.service');
const messagingService = new MessagingService();
const { ModerationService } = require('../moderation/moderation.service');
const { BUDDY_TYPES, BUDDY_PRICING, BUDDY_LIMITS } = require('./buddy.config');

class BuddyService {
  /**
   * Normalizes city strings for consistent lookup.
   */
  _normalizeCity(city) {
    if (!city || typeof city !== 'string') return '';
    return city.trim().toLowerCase();
  }

  /**
   * Validates standard UUID string format.
   */
  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Creates a new broadcast Buddy Activity Request.
   * 
   * Transactional:
   * 1. Validates active subscription (initiator must be subscribed).
   * 2. Deducts 100 coins atomically from initiator's wallet.
   * 3. Inserts debit audit row into wallet_transactions.
   * 4. Inserts row into buddy_requests.
   * 
   * @param {Object} params
   * @param {string} params.initiatorId
   * @param {string} params.buddyType
   * @param {string} params.city
   * @param {string} params.targetGender
   * @returns {Promise<Object>} Created request row with initiator info
   */
  async createRequest({ initiatorId, buddyType, city, targetGender }) {
    if (!this._isValidUUID(initiatorId)) {
      const err = new Error('Invalid initiator ID');
      err.statusCode = 400;
      throw err;
    }

    if (!BUDDY_TYPES[buddyType]) {
      const err = new Error(`Invalid buddy type: ${buddyType}. Valid types: ${Object.keys(BUDDY_TYPES).join(', ')}`);
      err.statusCode = 400;
      throw err;
    }

    const normalizedCity = this._normalizeCity(city);
    if (!normalizedCity) {
      const err = new Error('City is required');
      err.statusCode = 400;
      throw err;
    }

    const validGenders = ['male', 'female', 'all'];
    const normalizedGender = (targetGender || 'all').toLowerCase().trim();
    if (!validGenders.includes(normalizedGender)) {
      const err = new Error('Invalid target gender. Must be male, female, or all');
      err.statusCode = 400;
      throw err;
    }

    // 1. Check Moderation (banned or suspended users cannot initiate requests)
    const modStatus = await ModerationService.isUserBlocked(initiatorId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from creating requests');
      err.statusCode = 403;
      throw err;
    }

    // 2. Check Subscription (initiator must have an active subscription)
    const activeSub = await subscriptionsService.getActiveSubscription(initiatorId);
    if (!activeSub) {
      const err = new Error('An active membership subscription is required to post buddy requests');
      err.code = 'ACTIVE_SUBSCRIPTION_REQUIRED';
      err.statusCode = 403;
      throw err;
    }

    const coinCost = BUDDY_PRICING.INITIATOR_COIN_COST;
    const coinReward = BUDDY_PRICING.ACCEPTER_COIN_REWARD;

    // 3. Transactional execution: Deduct coins + create request
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // Check current wallet balance with row-level lock
      const walletRes = await client.query(
        'SELECT balance FROM public.wallets WHERE user_id = $1 FOR UPDATE',
        [initiatorId]
      );
      const currentBalance = walletRes.rows[0] ? Number(walletRes.rows[0].balance) : 0;
      if (currentBalance < coinCost) {
        await client.query('ROLLBACK');
        const err = new Error(`Insufficient balance: ${coinCost} coins required to create a buddy request (current balance: ${currentBalance} coins).`);
        err.code = 'INSUFFICIENT_COINS';
        err.statusCode = 400;
        throw err;
      }

      // Deduct coins atomically from wallet
      const deductRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance - $1
         WHERE user_id = $2 AND balance >= $1
         RETURNING balance`,
        [coinCost, initiatorId]
      );

      if (deductRes.rows.length === 0) {
        await client.query('ROLLBACK');
        const err = new Error(`Insufficient balance: ${coinCost} coins required to create a buddy request.`);
        err.code = 'INSUFFICIENT_COINS';
        err.statusCode = 400;
        throw err;
      }

      const newBalance = deductRes.rows[0].balance;

      // Insert buddy request
      const insertRes = await client.query(
        `INSERT INTO public.buddy_requests (
           initiator_id, buddy_type, city, target_gender,
           initiator_coin_cost, accepter_coin_reward, status
         ) VALUES ($1, $2, $3, $4, $5, $6, 'open')
         RETURNING *`,
        [initiatorId, buddyType, normalizedCity, normalizedGender, coinCost, coinReward]
      );

      const request = insertRes.rows[0];

      // Record wallet transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'debit', 'buddy_request', $3)`,
        [initiatorId, coinCost, request.id]
      );

      await client.query('COMMIT');

      // Invalidate wallet cache
      await cacheService.invalidate(`user:balance:${initiatorId}`);

      // Fetch public initiator details for broadcast
      const userRes = await db.query(
        `SELECT id, full_name, user_name, avatar_seed, avatar_style, gender
         FROM public.users WHERE id = $1`,
        [initiatorId]
      );

      const initiator = userRes.rows[0] || {};

      return {
        ...request,
        initiator: {
          id: initiator.id,
          fullName: initiator.full_name || 'User',
          userName: initiator.user_name || null,
          avatarSeed: initiator.avatar_seed || null,
          avatarStyle: initiator.avatar_style || 'avataaars',
          gender: initiator.gender || null,
        },
        newBalance,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`❌ [BuddyService.createRequest] Error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Atomically accepts an open buddy request.
   * 
   * Single-query atomic update:
   * UPDATE ... WHERE id = $3 AND status = 'open' RETURNING *;
   * 
   * Guarantees that in a high-concurrency race condition with multiple
   * simultaneous accepters, exactly ONE succeeds and all others receive ALREADY_ACCEPTED.
   * 
   * @param {Object} params
   * @param {string} params.requestId
   * @param {string} params.accepterId
   * @returns {Promise<Object>} Updated request row with 6-digit OTP
   */
  async acceptRequest({ requestId, accepterId }) {
    if (!this._isValidUUID(requestId) || !this._isValidUUID(accepterId)) {
      const err = new Error('Invalid request or accepter ID format');
      err.statusCode = 400;
      throw err;
    }

    // 1. Check Moderation
    const modStatus = await ModerationService.isUserBlocked(accepterId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from accepting requests');
      err.statusCode = 403;
      throw err;
    }

    // 2. Fetch existing request to verify it's not the initiator accepting their own request
    const existingCheck = await db.query(
      `SELECT initiator_id, status FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (existingCheck.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    if (existingCheck.rows[0].initiator_id === accepterId) {
      const err = new Error('You cannot accept your own buddy request');
      err.statusCode = 400;
      throw err;
    }

    if (existingCheck.rows[0].status !== 'open') {
      const err = new Error('This buddy request has already been accepted by another user');
      err.code = 'ALREADY_ACCEPTED';
      err.statusCode = 409;
      throw err;
    }

    // 3. Generate secure 6-digit OTP (100000 - 999999)
    const otpCode = crypto.randomInt(100000, 1000000).toString();

    // 4. Atomic single UPDATE query — the core race-prevention mechanism
    const updateRes = await db.query(
      `UPDATE public.buddy_requests
       SET status = 'accepted',
           accepter_id = $1,
           accepted_at = NOW(),
           otp_code = $2,
           otp_generated_at = NOW(),
           otp_attempts = 0
       WHERE id = $3 AND status = 'open'
       RETURNING *`,
      [accepterId, otpCode, requestId]
    );

    if (updateRes.rows.length === 0) {
      // Another concurrent user won the atomic race milliseconds earlier
      const err = new Error('This buddy request has already been accepted by another user');
      err.code = 'ALREADY_ACCEPTED';
      err.statusCode = 409;
      throw err;
    }

    const acceptedRequest = updateRes.rows[0];

    // Fetch accepter & initiator profile info
    const [initiatorRes, accepterRes] = await Promise.all([
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [acceptedRequest.initiator_id]),
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
    ]);

    const initiator = initiatorRes.rows[0] || {};
    const accepter = accepterRes.rows[0] || {};

    return {
      ...acceptedRequest,
      initiator: {
        id: initiator.id,
        fullName: initiator.full_name || 'User',
        userName: initiator.user_name || null,
        avatarSeed: initiator.avatar_seed || null,
        avatarStyle: initiator.avatar_style || 'avataaars',
        gender: initiator.gender || null,
      },
      accepter: {
        id: accepter.id,
        fullName: accepter.full_name || 'User',
        userName: accepter.user_name || null,
        avatarSeed: accepter.avatar_seed || null,
        avatarStyle: accepter.avatar_style || 'avataaars',
        gender: accepter.gender || null,
      },
    };
  }

  /**
   * Verifies the 6-digit handshake OTP submitted by the accepter.
   * 
   * Security & Rate-limiting:
   * - Max 5 attempts per request before lockout (HTTP 429).
   * - Requires matching accepter_id and status = 'accepted'.
   * 
   * Transactional:
   * - Transitions request status to 'otp_verified'.
   * - Credits 50 coins to accepter's wallet.
   * - Records wallet_transactions credit audit row.
   * - Unlocks / creates conversation row via messagingService.findOrCreateConversation.
   * 
   * @param {Object} params
   * @param {string} params.requestId
   * @param {string} params.accepterId
   * @param {string} params.otpCode
   * @returns {Promise<Object>} Result with unlocked conversationId and updated request
   */
  async verifyOtp({ requestId, accepterId, otpCode }) {
    if (!this._isValidUUID(requestId) || !this._isValidUUID(accepterId)) {
      const err = new Error('Invalid request or accepter ID format');
      err.statusCode = 400;
      throw err;
    }

    if (!otpCode || typeof otpCode !== 'string' || otpCode.trim().length !== 6) {
      const err = new Error('A 6-digit numeric OTP code is required');
      err.statusCode = 400;
      throw err;
    }

    const cleanOtp = otpCode.trim();

    // 1. Fetch current request state
    const reqRes = await db.query(
      `SELECT * FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (reqRes.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    const request = reqRes.rows[0];

    if (request.accepter_id !== accepterId) {
      const err = new Error('Only the user who accepted this request can verify the OTP');
      err.statusCode = 403;
      throw err;
    }

    if (request.status === 'otp_verified') {
      // Already completed handshake: return existing conversation
      return {
        success: true,
        alreadyVerified: true,
        conversationId: request.conversation_id,
        request,
      };
    }

    if (request.status !== 'accepted') {
      const err = new Error(`Request is in status '${request.status}' and cannot be verified`);
      err.statusCode = 400;
      throw err;
    }

    // 2. Check 5-attempt rate-limiting lockout
    if (request.otp_attempts >= BUDDY_LIMITS.MAX_OTP_ATTEMPTS) {
      const err = new Error('Too many failed OTP attempts. This request has been locked for security.');
      err.code = 'TOO_MANY_ATTEMPTS';
      err.statusCode = 429;
      throw err;
    }

    // 3. Verify OTP Match
    if (request.otp_code !== cleanOtp) {
      // Increment attempt count
      const incRes = await db.query(
        `UPDATE public.buddy_requests
         SET otp_attempts = otp_attempts + 1
         WHERE id = $1
         RETURNING otp_attempts`,
        [requestId]
      );

      const attemptsUsed = incRes.rows[0].otp_attempts;
      const remainingAttempts = Math.max(0, BUDDY_LIMITS.MAX_OTP_ATTEMPTS - attemptsUsed);

      if (remainingAttempts === 0) {
        const err = new Error('Too many failed OTP attempts. This request is now locked.');
        err.code = 'TOO_MANY_ATTEMPTS';
        err.statusCode = 429;
        throw err;
      }

      const err = new Error(`Incorrect OTP code. ${remainingAttempts} attempts remaining.`);
      err.code = 'INVALID_OTP';
      err.statusCode = 400;
      err.remainingAttempts = remainingAttempts;
      throw err;
    }

    // 4. OTP Matches: Execute transactional unlock & reward
    const rewardCoins = request.accepter_coin_reward || BUDDY_PRICING.ACCEPTER_COIN_REWARD;
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      // Create or fetch canonical conversation between initiator and accepter
      const conversation = await messagingService.findOrCreateConversation(
        request.initiator_id,
        request.accepter_id
      );

      // Transition request status to otp_verified and link conversation
      const updateRes = await client.query(
        `UPDATE public.buddy_requests
         SET status = 'otp_verified',
             verified_at = NOW(),
             conversation_id = $1
         WHERE id = $2 AND status = 'accepted'
         RETURNING *`,
        [conversation.id, requestId]
      );

      if (updateRes.rows.length === 0) {
        await client.query('ROLLBACK');
        const err = new Error('Failed to verify request — invalid state transition');
        err.statusCode = 409;
        throw err;
      }

      const verifiedRequest = updateRes.rows[0];

      // Credit 50 reward coins to accepter's wallet
      const creditRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance + $1
         WHERE user_id = $2
         RETURNING balance`,
        [rewardCoins, accepterId]
      );

      const newAccepterBalance = creditRes.rows.length > 0 ? creditRes.rows[0].balance : 0;

      // Log reward transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', 'buddy_reward', $3)`,
        [accepterId, rewardCoins, requestId]
      );

      await client.query('COMMIT');

      // Invalidate accepter wallet cache
      await cacheService.invalidate(`user:balance:${accepterId}`);

      // Fetch other user profiles for client navigation
      const [initiatorRes, accepterRes] = await Promise.all([
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [request.initiator_id]),
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
      ]);

      const initiator = initiatorRes.rows[0] || {};
      const accepter = accepterRes.rows[0] || {};

      return {
        success: true,
        conversationId: conversation.id,
        rewardCoins,
        newBalance: newAccepterBalance,
        request: verifiedRequest,
        initiator: {
          id: initiator.id,
          fullName: initiator.full_name || 'User',
          userName: initiator.user_name || null,
          avatarSeed: initiator.avatar_seed || null,
          avatarStyle: initiator.avatar_style || 'avataaars',
          gender: initiator.gender || null,
        },
        accepter: {
          id: accepter.id,
          fullName: accepter.full_name || 'User',
          userName: accepter.user_name || null,
          avatarSeed: accepter.avatar_seed || null,
          avatarStyle: accepter.avatar_style || 'avataaars',
          gender: accepter.gender || null,
        },
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`❌ [BuddyService.verifyOtp] Error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Retrieves open requests in a city matching the requesting user's profile.
   * Utilizes the idx_buddy_requests_open_city_gender partial index.
   */
  async listOpenRequests({ city, userGender, buddyType, userId, limit = 20, offset = 0 }) {
    const normalizedCity = this._normalizeCity(city);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || BUDDY_LIMITS.DEFAULT_FEED_LIMIT, 1), BUDDY_LIMITS.MAX_FEED_LIMIT);
    const parsedOffset = Math.max(parseInt(offset, 10) || 0, 0);

    const params = [normalizedCity];
    let query = `
      SELECT r.id, r.initiator_id, r.buddy_type, r.city, r.target_gender,
             r.status, r.initiator_coin_cost, r.accepter_coin_reward, r.created_at,
             u.full_name AS initiator_name,
             u.user_name AS initiator_username,
             u.avatar_seed AS initiator_avatar_seed,
             u.avatar_style AS initiator_avatar_style,
             u.gender AS initiator_gender
      FROM public.buddy_requests r
      JOIN public.users u ON u.id = r.initiator_id
      WHERE LOWER(TRIM(r.city)) = $1
        AND r.status = 'open'
    `;

    // Filter by target gender if userGender provided
    if (userGender) {
      params.push(userGender.toLowerCase().trim());
      query += ` AND (r.target_gender = $${params.length} OR r.target_gender = 'all')`;
    }

    // Exclude initiator's own requests
    if (userId) {
      params.push(userId);
      query += ` AND r.initiator_id != $${params.length}`;
    }

    // Optional buddy_type filter
    if (buddyType && BUDDY_TYPES[buddyType]) {
      params.push(buddyType);
      query += ` AND r.buddy_type = $${params.length}`;
    }

    params.push(parsedLimit);
    query += ` ORDER BY r.created_at DESC LIMIT $${params.length}`;

    params.push(parsedOffset);
    query += ` OFFSET $${params.length};`;

    const result = await db.query(query, params);

    return result.rows.map(row => ({
      id: row.id,
      initiatorId: row.initiator_id,
      buddyType: row.buddy_type,
      city: row.city,
      targetGender: row.target_gender,
      status: row.status,
      initiatorCoinCost: row.initiator_coin_cost,
      accepterCoinReward: row.accepter_coin_reward,
      createdAt: row.created_at,
      initiator: {
        id: row.initiator_id,
        fullName: row.initiator_name || 'User',
        userName: row.initiator_username || null,
        avatarSeed: row.initiator_avatar_seed || null,
        avatarStyle: row.initiator_avatar_style || 'avataaars',
        gender: row.initiator_gender || null,
      },
    }));
  }

  /**
   * Retrieves all active or recent requests involving the specified user.
   */
  async getUserRequests(userId) {
    if (!this._isValidUUID(userId)) return [];

    const result = await db.query(
      `SELECT r.*,
              u_init.full_name AS initiator_name,
              u_init.user_name AS initiator_username,
              u_init.avatar_seed AS initiator_avatar_seed,
              u_init.avatar_style AS initiator_avatar_style,
              u_init.gender AS initiator_gender,
              u_acc.full_name AS accepter_name,
              u_acc.user_name AS accepter_username,
              u_acc.avatar_seed AS accepter_avatar_seed,
              u_acc.avatar_style AS accepter_avatar_style,
              u_acc.gender AS accepter_gender
       FROM public.buddy_requests r
       JOIN public.users u_init ON u_init.id = r.initiator_id
       LEFT JOIN public.users u_acc ON u_acc.id = r.accepter_id
       WHERE r.initiator_id = $1 OR r.accepter_id = $1
       ORDER BY r.created_at DESC
       LIMIT 30;`,
      [userId]
    );

    return result.rows.map(row => ({
      id: row.id,
      initiatorId: row.initiator_id,
      buddyType: row.buddy_type,
      city: row.city,
      targetGender: row.target_gender,
      status: row.status,
      accepterId: row.accepter_id,
      otpCode: row.initiator_id === userId ? row.otp_code : null, // Only initiator sees plain OTP
      otpAttempts: row.otp_attempts,
      acceptedAt: row.accepted_at,
      verifiedAt: row.verified_at,
      conversationId: row.conversation_id,
      initiatorCoinCost: row.initiator_coin_cost,
      accepterCoinReward: row.accepter_coin_reward,
      createdAt: row.created_at,
      isInitiator: row.initiator_id === userId,
      initiator: {
        id: row.initiator_id,
        fullName: row.initiator_name || 'User',
        userName: row.initiator_username || null,
        avatarSeed: row.initiator_avatar_seed || null,
        avatarStyle: row.initiator_avatar_style || 'avataaars',
        gender: row.initiator_gender || null,
      },
      accepter: row.accepter_id ? {
        id: row.accepter_id,
        fullName: row.accepter_name || 'User',
        userName: row.accepter_username || null,
        avatarSeed: row.accepter_avatar_seed || null,
        avatarStyle: row.accepter_avatar_style || 'avataaars',
        gender: row.accepter_gender || null,
      } : null,
    }));
  }
}

const buddyService = new BuddyService();

module.exports = {
  buddyService,
  BuddyService,
};
