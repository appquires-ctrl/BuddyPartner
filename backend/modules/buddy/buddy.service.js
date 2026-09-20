const crypto = require('crypto');
const db = require('../../db');
const redis = require('../../redis');
const { cacheService } = require('../../services/cache.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { MessagingService } = require('../messaging/messaging.service');
const messagingService = new MessagingService();
const { ModerationService } = require('../moderation/moderation.service');
const { WalletService } = require('../wallet/wallet.service');
const { BUDDY_TYPES, BUDDY_PRICING, BUDDY_LIMITS, BUDDY_STATUSES } = require('./buddy.config');

function getPepper() {
  return process.env.BUDDY_OTP_PEPPER || 'buddypartner_otp_secret_pepper_2026';
}

function hashOtp(otp) {
  return crypto.createHmac('sha256', getPepper()).update(String(otp).trim()).digest('hex');
}

const BUDDY_AES_KEY = crypto.scryptSync(getPepper(), 'buddy_salt_2026', 32);

function encryptOtp(otp) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', BUDDY_AES_KEY, iv);
  let encrypted = cipher.update(String(otp).trim(), 'utf8', 'hex');
  encrypted += cipher.final('hex');
  const tag = cipher.getAuthTag().toString('hex');
  return `${iv.toString('hex')}:${tag}:${encrypted}`;
}

function decryptOtp(encryptedStr) {
  if (!encryptedStr) return null;
  const parts = encryptedStr.split(':');
  if (parts.length !== 3) return null;
  const [ivHex, tagHex, cipherHex] = parts;
  const decipher = crypto.createDecipheriv('aes-256-gcm', BUDDY_AES_KEY, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  let decrypted = decipher.update(cipherHex, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

class BuddyService {
  _normalizeCity(city) {
    if (!city || typeof city !== 'string') return '';
    return city.trim().toLowerCase();
  }

  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Creates a new broadcast Buddy Activity Request.
   * Debits 100 coins immediately (spendable first, then earned).
   * If total across both buckets is under 100, rejects with 400 INSUFFICIENT_COINS and writes zero rows.
   */
  async createRequest({ initiatorId, buddyType, city, targetGender, idempotencyKey = null, correlationId = null }) {
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

    // Check Moderation
    const modStatus = await ModerationService.isUserBlocked(initiatorId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from creating requests');
      err.statusCode = 403;
      throw err;
    }

    // Check Subscription (Redis-cached with 300s TTL)
    const isSub = await subscriptionsService.isSubscribed(initiatorId);
    if (!isSub) {
      const err = new Error('An active membership subscription is required to post buddy requests');
      err.code = 'ACTIVE_SUBSCRIPTION_REQUIRED';
      err.statusCode = 403;
      throw err;
    }

    const coinCost = BUDDY_PRICING.TYPE_COIN_COSTS?.[buddyType] ?? BUDDY_PRICING.INITIATOR_COIN_COST;
    const rewardPct = normalizedGender === 'male'
      ? (BUDDY_PRICING.MALE_REWARD_PERCENTAGE || 0.20)
      : (BUDDY_PRICING.FEMALE_REWARD_PERCENTAGE || 0.40);
    const coinReward = Math.max(1, Math.round(coinCost * rewardPct));
    const cid = correlationId || `buddy_create_${crypto.randomBytes(8).toString('hex')}`;

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Check idempotency if key provided
      if (idempotencyKey) {
        const existingReq = await client.query(
          `SELECT * FROM public.buddy_requests WHERE idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingReq.rows.length > 0) {
          const req = existingReq.rows[0];
          const bal = await WalletService.getBalance(initiatorId);
          await client.query('COMMIT');
          console.log(`🔁 [BuddyService.createRequest] Idempotency hit: ${idempotencyKey}`);
          return {
            ...req,
            newBalance: bal.balance,
            alreadyProcessed: true,
          };
        }
      }

      // 2. Atomic spendable-first coin deduction
      const debitRes = await WalletService.debitCoins({
        userId: initiatorId,
        amount: coinCost,
        reason: 'buddy_spend',
        referenceId: idempotencyKey,
        idempotencyKey: idempotencyKey ? `tx_${idempotencyKey}` : null,
        correlationId: cid,
        client,
      });

      if (!debitRes.success) {
        await client.query('ROLLBACK');
        const bal = await WalletService.getBalance(initiatorId);
        const err = new Error(`Insufficient coins: ${coinCost} coins required to create a buddy request (current balance: ${bal.balance} coins).`);
        err.code = 'INSUFFICIENT_COINS';
        err.statusCode = 400;
        throw err;
      }

      // 3. Insert buddy request
      const insertRes = await client.query(
        `INSERT INTO public.buddy_requests (
           initiator_id, buddy_type, city, target_gender,
           initiator_coin_cost, accepter_coin_reward, status, idempotency_key
         ) VALUES ($1, $2, $3, $4, $5, $6, 'open', $7)
         RETURNING *`,
        [initiatorId, buddyType, normalizedCity, normalizedGender, coinCost, coinReward, idempotencyKey]
      );

      const request = insertRes.rows[0];

      // Update reference_id on the debit ledger entry to point to this buddy request id
      if (debitRes.transactionId) {
        await client.query(
          `UPDATE public.wallet_transactions
           SET reference_id = $1
           WHERE id = $2`,
          [request.id, debitRes.transactionId]
        );
      }

      await client.query('COMMIT');

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
        newBalance: debitRes.balance,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [BuddyService.createRequest] Error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Atomically accepts an open buddy request.
   * First accepter wins via atomic UPDATE ... WHERE id = $1 AND status = 'open'.
   * Immediately unlocks chat: creates conversation row and links conversation_id.
   * Generates CSPRNG 6-digit OTP, storing only its hash and encrypted token for REST retrieval.
   */
  async acceptRequest({ requestId, accepterId }) {
    if (!this._isValidUUID(requestId) || !this._isValidUUID(accepterId)) {
      const err = new Error('Invalid request or accepter ID format');
      err.statusCode = 400;
      throw err;
    }

    const modStatus = await ModerationService.isUserBlocked(accepterId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from accepting requests');
      err.statusCode = 403;
      throw err;
    }

    const existingCheck = await db.query(
      `SELECT initiator_id, status, initiator_coin_cost FROM public.buddy_requests WHERE id = $1`,
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

    // 1. Create canonical conversation immediately to unlock chat
    const conversation = await messagingService.findOrCreateConversation(
      existingCheck.rows[0].initiator_id,
      accepterId
    );

    // 2. Determine accepter's gender to calculate dynamic reward split (40% female / 20% male)
    const accepterGenderRes = await db.query(
      `SELECT gender FROM public.users WHERE id = $1`,
      [accepterId]
    );
    const accepterGender = (accepterGenderRes.rows[0]?.gender || '').toLowerCase().trim();
    const isFemaleAccepter = accepterGender === 'female';
    const rewardPercentage = isFemaleAccepter
      ? BUDDY_PRICING.FEMALE_REWARD_PERCENTAGE
      : BUDDY_PRICING.MALE_REWARD_PERCENTAGE;
    const initiatorCost = existingCheck.rows[0].initiator_coin_cost || BUDDY_PRICING.INITIATOR_COIN_COST;
    const dynamicReward = Math.max(1, Math.round(initiatorCost * rewardPercentage));

    // 3. Generate cryptographically secure 6-digit OTP
    const otpCode = crypto.randomInt(100000, 1000000).toString();
    const otpHash = hashOtp(otpCode);
    const otpEncrypted = encryptOtp(otpCode);

    // 4. Atomic single UPDATE query — the core race-prevention mechanism
    const updateRes = await db.query(
      `UPDATE public.buddy_requests
       SET status = 'accepted',
           accepter_id = $1,
           accepter_coin_reward = $2,
           conversation_id = $3,
           otp_hash = $4,
           otp_encrypted = $5,
           accepted_at = NOW()
       WHERE id = $6 AND status = 'open'
       RETURNING *`,
      [accepterId, dynamicReward, conversation.id, otpHash, otpEncrypted, requestId]
    );

    if (updateRes.rows.length === 0) {
      const err = new Error('This buddy request has already been accepted by another user');
      err.code = 'ALREADY_ACCEPTED';
      err.statusCode = 409;
      throw err;
    }

    const acceptedRequest = updateRes.rows[0];

    const [initiatorRes, accepterRes] = await Promise.all([
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [acceptedRequest.initiator_id]),
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
    ]);

    const initiator = initiatorRes.rows[0] || {};
    const accepter = accepterRes.rows[0] || {};

    return {
      ...acceptedRequest,
      otpCode, // Returned strictly for socket notification convenience to initiator
      otp_code: otpCode,
      conversationId: conversation.id,
      initiator: {
        id: initiator.id,
        fullName: initiator.full_name || 'User',
        full_name: initiator.full_name || 'User',
        userName: initiator.user_name || null,
        user_name: initiator.user_name || null,
        avatarSeed: initiator.avatar_seed || null,
        avatar_seed: initiator.avatar_seed || null,
        avatarStyle: initiator.avatar_style || 'avataaars',
        avatar_style: initiator.avatar_style || 'avataaars',
        gender: initiator.gender || null,
      },
      accepter: {
        id: accepter.id,
        fullName: accepter.full_name || 'User',
        full_name: accepter.full_name || 'User',
        userName: accepter.user_name || null,
        user_name: accepter.user_name || null,
        avatarSeed: accepter.avatar_seed || null,
        avatar_seed: accepter.avatar_seed || null,
        avatarStyle: accepter.avatar_style || 'avataaars',
        avatar_style: accepter.avatar_style || 'avataaars',
        gender: accepter.gender || null,
      },
    };
  }

  /**
   * Retrieves plaintext OTP for the initiator via authenticated REST endpoint.
   * Reconstructs OTP by decrypting AES-256-GCM encrypted token.
   */
  async getInitiatorOtp(requestId, userId) {
    if (!this._isValidUUID(requestId)) {
      const err = new Error('Invalid request ID');
      err.statusCode = 400;
      throw err;
    }

    const result = await db.query(
      `SELECT initiator_id, status, otp_encrypted FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (result.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    const row = result.rows[0];
    if (row.initiator_id !== userId) {
      const err = new Error('Only the initiator can view the meetup OTP');
      err.statusCode = 403;
      throw err;
    }

    if (row.status !== 'accepted') {
      const err = new Error(`OTP is not available in status '${row.status}'. It is only available when accepted and awaiting meetup.`);
      err.statusCode = 400;
      throw err;
    }

    const otpCode = decryptOtp(row.otp_encrypted);
    if (!otpCode) {
      const err = new Error('OTP is unavailable or has expired');
      err.statusCode = 500;
      throw err;
    }

    return { otpCode };
  }

  /**
   * Completes the Buddy request when accepter submits the 6-digit in-person OTP.
   * Rate limited via Redis: max 5 attempts, then 15-minute lockout.
   * Fail-closed if Redis is offline.
   * Atomically transitions status to 'completed' and credits 50 coins to accepter's earned_balance.
   */
  async completeRequest({ requestId, accepterId, otpCode, idempotencyKey = null }) {
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
      const err = new Error('Only the user who accepted this request can submit the meetup OTP');
      err.statusCode = 403;
      throw err;
    }

    if (request.status === 'completed') {
      return {
        success: true,
        alreadyCompleted: true,
        conversationId: request.conversation_id,
        request,
      };
    }

    if (request.status !== 'accepted') {
      const err = new Error(`Request is in status '${request.status}' and cannot be completed`);
      err.statusCode = 400;
      throw err;
    }

    // 2. Redis Rate Limiting & Lockout Check (Fail-closed)
    const lockoutKey = `buddy:otp:lockout:${requestId}`;
    const attemptsKey = `buddy:otp:attempts:${requestId}`;

    try {
      const isLocked = await redis.get(lockoutKey);
      if (isLocked) {
        const ttl = await redis.ttl(lockoutKey);
        const mins = Math.max(1, Math.ceil(ttl / 60));
        const err = new Error(`Too many failed OTP attempts. This request is locked for security. Please try again in ${mins} minute(s).`);
        err.code = 'TOO_MANY_ATTEMPTS';
        err.statusCode = 429;
        throw err;
      }
    } catch (redisErr) {
      if (redisErr.statusCode === 429) throw redisErr;
      console.error('❌ [BuddyService.completeRequest] Redis lockout check failed (fail-closed):', redisErr.message);
      const err = new Error('Security rate limiting service unavailable. Please try again in a few moments.');
      err.statusCode = 503;
      throw err;
    }

    // 3. Verify OTP Hash
    const submittedHash = hashOtp(cleanOtp);
    if (submittedHash !== request.otp_hash) {
      let remainingAttempts = BUDDY_LIMITS.MAX_OTP_ATTEMPTS - 1;
      try {
        const attempts = await redis.incr(attemptsKey);
        await redis.expire(attemptsKey, BUDDY_LIMITS.OTP_LOCKOUT_SECONDS);
        remainingAttempts = Math.max(0, BUDDY_LIMITS.MAX_OTP_ATTEMPTS - attempts);

        if (attempts >= BUDDY_LIMITS.MAX_OTP_ATTEMPTS) {
          await redis.set(lockoutKey, '1', 'EX', BUDDY_LIMITS.OTP_LOCKOUT_SECONDS);
          await redis.del(attemptsKey);
          console.warn(`🔒 [BuddyService] Request ${requestId} locked for 15 minutes due to 5 failed OTP attempts.`);
          const err = new Error('Too many failed OTP attempts. This request is now locked for 15 minutes.');
          err.code = 'TOO_MANY_ATTEMPTS';
          err.statusCode = 429;
          throw err;
        }
      } catch (redisErr) {
        if (redisErr.statusCode === 429) throw redisErr;
        console.error('❌ Redis increment error on failed OTP:', redisErr.message);
      }

      const err = new Error(`Incorrect OTP code. ${remainingAttempts} attempt(s) remaining.`);
      err.code = 'INVALID_OTP';
      err.statusCode = 400;
      err.remainingAttempts = remainingAttempts;
      throw err;
    }

    // Clean up Redis lockout/attempts keys upon successful match
    await Promise.all([
      redis.del(lockoutKey).catch(() => {}),
      redis.del(attemptsKey).catch(() => {}),
    ]);

    // 4. Atomic Transaction: Transition to 'completed' + Credit 50 earned coins
    const rewardCoins = request.accepter_coin_reward || BUDDY_PRICING.ACCEPTER_COIN_REWARD;
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      const updateRes = await client.query(
        `UPDATE public.buddy_requests
         SET status = 'completed',
             completed_at = NOW()
         WHERE id = $1 AND status = 'accepted'
         RETURNING *`,
        [requestId]
      );

      if (updateRes.rows.length === 0) {
        await client.query('ROLLBACK');
        const err = new Error('Failed to complete request — invalid state transition');
        err.statusCode = 409;
        throw err;
      }

      const completedRequest = updateRes.rows[0];

      // Credit 50 coins directly to earned_balance
      // Note: This deterministic fallback key (`buddy_reward_${requestId}`) assumes exactly one credit
      // per reference ID. Do not copy this pattern verbatim for any future endpoint where the same
      // reference ID could legitimately need multiple distinct credits (e.g. recurring rewards),
      // since the deterministic key would then wrongly block legitimate repeats.
      const creditRes = await WalletService.creditCoins({
        userId: accepterId,
        spendable: 0,
        earned: rewardCoins,
        reason: 'buddy_reward',
        referenceId: requestId,
        idempotencyKey: idempotencyKey || `buddy_reward_${requestId}`,
        correlationId: `reward_${requestId}`,
        client,
      });

      await client.query('COMMIT');

      // Fetch user profiles for response
      const [initiatorRes, accepterRes] = await Promise.all([
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [request.initiator_id]),
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
      ]);

      const initRow = initiatorRes.rows[0] || {};
      const accRow = accepterRes.rows[0] || {};

      const initiatorData = {
        id: initRow.id,
        fullName: initRow.full_name || 'User',
        full_name: initRow.full_name || 'User',
        userName: initRow.user_name || null,
        user_name: initRow.user_name || null,
        avatarSeed: initRow.avatar_seed || null,
        avatar_seed: initRow.avatar_seed || null,
        avatarStyle: initRow.avatar_style || 'avataaars',
        avatar_style: initRow.avatar_style || 'avataaars',
        gender: initRow.gender || null,
      };

      const accepterData = {
        id: accRow.id,
        fullName: accRow.full_name || 'User',
        full_name: accRow.full_name || 'User',
        userName: accRow.user_name || null,
        user_name: accRow.user_name || null,
        avatarSeed: accRow.avatar_seed || null,
        avatar_seed: accRow.avatar_seed || null,
        avatarStyle: accRow.avatar_style || 'avataaars',
        avatar_style: accRow.avatar_style || 'avataaars',
        gender: accRow.gender || null,
      };

      return {
        success: true,
        conversationId: request.conversation_id,
        rewardCoins,
        earnedBalance: creditRes.earnedBalance,
        spendableBalance: creditRes.spendableBalance,
        balance: creditRes.balance,
        request: completedRequest,
        initiator: initiatorData,
        accepter: accepterData,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [BuddyService.completeRequest] Atomic transaction error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Alias for completeRequest to support backward compatibility.
   */
  async verifyOtp(params) {
    return this.completeRequest(params);
  }

  /**
   * Admin-only cancellation of an open or accepted request.
   * Strictly no refunds per product policy.
   */
  async adminCancelRequest(requestId, adminId = null, reason = 'admin_action') {
    if (!this._isValidUUID(requestId)) {
      const err = new Error('Invalid request ID');
      err.statusCode = 400;
      throw err;
    }

    const res = await db.query(
      `UPDATE public.buddy_requests
       SET status = 'cancelled',
           cancelled_at = NOW()
       WHERE id = $1 AND status IN ('open', 'accepted')
       RETURNING *`,
      [requestId]
    );

    if (res.rows.length === 0) {
      const err = new Error('Request not found or cannot be cancelled (already completed or cancelled)');
      err.statusCode = 400;
      throw err;
    }

    console.log(`🛡️ [Admin] Buddy request ${requestId} cancelled by admin ${adminId}. Reason: ${reason}`);
    return res.rows[0];
  }

  /**
   * Retrieves open requests in a city matching the requesting user's profile.
   * Utilizes idx_buddy_requests_status_city_gender.
   */
  async listOpenRequests({ city, userGender, buddyType, userId, limit = 20, offset = 0 }) {
    const normalizedCity = this._normalizeCity(city);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || BUDDY_LIMITS.DEFAULT_FEED_LIMIT, 1), BUDDY_LIMITS.MAX_FEED_LIMIT);
    const parsedOffset = Math.max(parseInt(offset, 10) || 0, 0);
    const genderKey = (userGender || 'all').toLowerCase().trim();
    const typeKey = (buddyType || 'all').toLowerCase().trim();

    // Cache feed across users in same city/gender/type with 5-second TTL
    const cacheKey = `buddy:feed:${normalizedCity}:${genderKey}:${typeKey}:${parsedLimit}:${parsedOffset}`;

    const rawRows = await cacheService.getOrSet(cacheKey, 5, async () => {
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
        WHERE r.city = $1
          AND r.status = 'open'
      `;

      if (userGender) {
        params.push(userGender.toLowerCase().trim());
        query += ` AND (r.target_gender = $${params.length} OR r.target_gender = 'all')`;
      }

      if (buddyType && BUDDY_TYPES[buddyType]) {
        params.push(buddyType);
        query += ` AND r.buddy_type = $${params.length}`;
      }

      params.push(parsedLimit);
      query += ` ORDER BY r.created_at DESC LIMIT $${params.length}`;

      params.push(parsedOffset);
      query += ` OFFSET $${params.length};`;

      const result = await db.query(query, params);
      return result.rows;
    });

    const isFemaleViewer = (userGender || '').toLowerCase().trim() === 'female';
    const rewardPercentage = isFemaleViewer
      ? BUDDY_PRICING.FEMALE_REWARD_PERCENTAGE
      : BUDDY_PRICING.MALE_REWARD_PERCENTAGE;

    return (rawRows || [])
      .filter(row => !userId || row.initiator_id !== userId)
      .map(row => {
        const cost = row.initiator_coin_cost || BUDDY_PRICING.INITIATOR_COIN_COST;
        const potentialReward = Math.max(1, Math.round(cost * rewardPercentage));
      return {
        id: row.id,
        initiatorId: row.initiator_id,
        buddyType: row.buddy_type,
        city: row.city,
        targetGender: row.target_gender,
        status: row.status,
        initiatorCoinCost: cost,
        accepterCoinReward: row.status === 'open' ? potentialReward : (row.accepter_coin_reward || potentialReward),
        createdAt: row.created_at,
        initiator: {
          id: row.initiator_id,
          fullName: row.initiator_name || 'User',
          full_name: row.initiator_name || 'User',
          userName: row.initiator_username || null,
          user_name: row.initiator_username || null,
          avatarSeed: row.initiator_avatar_seed || null,
          avatar_seed: row.initiator_avatar_seed || null,
          avatarStyle: row.initiator_avatar_style || 'avataaars',
          avatar_style: row.initiator_avatar_style || 'avataaars',
          gender: row.initiator_gender || null,
        },
      };
    });
  }

  /**
   * Retrieves paginated requests involving the specified user (as initiator or accepter).
   */
  async getUserRequests(userId, { page = 1, limit = 20, status = 'all' } = {}) {
    if (!this._isValidUUID(userId)) return { requests: [], total: 0, page: 1, totalPages: 1 };

    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);
    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const offset = (parsedPage - 1) * parsedLimit;

    const params = [userId];
    let whereClause = `WHERE (r.initiator_id = $1 OR r.accepter_id = $1)`;

    if (status !== 'all') {
      params.push(status);
      whereClause += ` AND r.status = $${params.length}`;
    }

    const countRes = await db.query(
      `SELECT COUNT(*)::int AS total FROM public.buddy_requests r ${whereClause}`,
      params
    );
    const total = countRes.rows[0]?.total || 0;

    params.push(parsedLimit);
    const limitIdx = params.length;
    params.push(offset);
    const offsetIdx = params.length;

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
       ${whereClause}
       ORDER BY r.created_at DESC
       LIMIT $${limitIdx} OFFSET $${offsetIdx};`,
      params
    );

    const requests = result.rows.map(row => {
      let otpCode = null;
      if (row.initiator_id === userId && row.status === 'accepted' && row.otp_encrypted) {
        try {
          otpCode = decryptOtp(row.otp_encrypted);
        } catch (_) {}
      }

      return {
        id: row.id,
        initiatorId: row.initiator_id,
        buddyType: row.buddy_type,
        city: row.city,
        targetGender: row.target_gender,
        status: row.status,
        accepterId: row.accepter_id,
        acceptedAt: row.accepted_at,
        completedAt: row.completed_at,
        cancelledAt: row.cancelled_at,
        conversationId: row.conversation_id,
        initiatorCoinCost: row.initiator_coin_cost || BUDDY_PRICING.TYPE_COIN_COSTS?.[row.buddy_type] || BUDDY_PRICING.INITIATOR_COIN_COST,
        accepterCoinReward: row.accepter_coin_reward || Math.max(1, Math.round((row.initiator_coin_cost || BUDDY_PRICING.TYPE_COIN_COSTS?.[row.buddy_type] || 100) * (row.accepter_gender === 'female' ? BUDDY_PRICING.FEMALE_REWARD_PERCENTAGE : BUDDY_PRICING.MALE_REWARD_PERCENTAGE))),
        createdAt: row.created_at,
        isInitiator: row.initiator_id === userId,
        otpCode,
        initiator: {
          id: row.initiator_id,
          fullName: row.initiator_name || 'User',
          full_name: row.initiator_name || 'User',
          userName: row.initiator_username || null,
          user_name: row.initiator_username || null,
          avatarSeed: row.initiator_avatar_seed || null,
          avatar_seed: row.initiator_avatar_seed || null,
          avatarStyle: row.initiator_avatar_style || 'avataaars',
          avatar_style: row.initiator_avatar_style || 'avataaars',
          gender: row.initiator_gender || null,
        },
        accepter: row.accepter_id ? {
          id: row.accepter_id,
          fullName: row.accepter_name || 'User',
          full_name: row.accepter_name || 'User',
          userName: row.accepter_username || null,
          user_name: row.accepter_username || null,
          avatarSeed: row.accepter_avatar_seed || null,
          avatar_seed: row.accepter_avatar_seed || null,
          avatarStyle: row.accepter_avatar_style || 'avataaars',
          avatar_style: row.accepter_avatar_style || 'avataaars',
          gender: row.accepter_gender || null,
        } : null,
      };
    });

    return {
      requests,
      total,
      page: parsedPage,
      totalPages: Math.ceil(total / parsedLimit) || 1,
    };
  }
}

const buddyService = new BuddyService();

module.exports = {
  buddyService,
  BuddyService,
};
