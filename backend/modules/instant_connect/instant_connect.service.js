const db = require('../../db');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

class InstantConnectService {
  /**
   * Toggle female user's "Incoming Paid Calls" status
   * Requires an active subscription.
   * @param {string} userId
   * @param {boolean} enabled
   * @param {import('ioredis').Redis} [redis]
   * @returns {Promise<{ success: boolean, enabled: boolean, error?: string }>}
   */
  async toggleIncomingPaidCalls(userId, enabled, redis) {
    try {
      await db.query(
        `UPDATE public.users SET incoming_paid_calls_enabled = $1 WHERE id = $2`,
        [enabled, userId]
      );

      if (redis) {
        if (enabled) {
          await redis.sadd('instant:female_pool', userId);
          await redis.del(`instant:snooze:${userId}`);
        } else {
          await redis.srem('instant:female_pool', userId);
        }
      }

      return { success: true, enabled };
    } catch (err) {
      console.error(`Error toggling incoming paid calls for ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Get female user's instant connect status & scratch card counts
   * @param {string} userId
   * @returns {Promise<Object>}
   */
  async getFemaleStatus(userId) {
    try {
      const userRes = await db.query(
        `SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`,
        [userId]
      );

      const isEnabled = userRes.rows[0]?.incoming_paid_calls_enabled === true;

      // Count unscratched cards
      const scratchRes = await db.query(
        `SELECT COUNT(*) as unscratched_count, COALESCE(SUM(coin_reward), 0) as pending_coins
         FROM public.scratch_cards
         WHERE female_user_id = $1 AND is_scratched = FALSE`,
        [userId]
      );

      // Total earnings from scratch cards
      const earningsRes = await db.query(
        `SELECT COALESCE(SUM(coin_reward), 0) as total_scratched_coins, COUNT(*) as total_scratched_cards
         FROM public.scratch_cards
         WHERE female_user_id = $1 AND is_scratched = TRUE`,
        [userId]
      );

      return {
        incomingPaidCallsEnabled: isEnabled,
        unscratchedCount: parseInt(scratchRes.rows[0]?.unscratched_count || '0', 10),
        pendingCoins: parseInt(scratchRes.rows[0]?.pending_coins || '0', 10),
        totalScratchedCoins: parseInt(earningsRes.rows[0]?.total_scratched_coins || '0', 10),
        totalScratchedCards: parseInt(earningsRes.rows[0]?.total_scratched_cards || '0', 10),
      };
    } catch (err) {
      console.error(`Error getting female instant status for ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Fetch all scratch cards for female user
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getScratchCards(userId) {
    try {
      const res = await db.query(
        `SELECT id, session_id, coin_reward, is_scratched, scratched_at, created_at
         FROM public.scratch_cards
         WHERE female_user_id = $1
         ORDER BY created_at DESC`,
        [userId]
      );
      return res.rows.map((row) => ({
        id: row.id,
        sessionId: row.session_id,
        coinReward: row.coin_reward,
        isScratched: row.is_scratched,
        scratchedAt: row.scratched_at,
        createdAt: row.created_at,
      }));
    } catch (err) {
      console.error(`Error fetching scratch cards for ${userId}:`, err.message);
      return [];
    }
  }

  /**
   * Scratch/claim a scratch card and credit coins directly to female wallet
   * @param {string} userId
   * @param {string} cardId
   * @returns {Promise<{ success: boolean, coinReward: number, newBalance: number, error?: string }>}
   */
  async claimScratchCard(userId, cardId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const cardRes = await client.query(
        `SELECT id, coin_reward, is_scratched 
         FROM public.scratch_cards 
         WHERE id = $1 AND female_user_id = $2
         FOR UPDATE`,
        [cardId, userId]
      );

      if (cardRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'CARD_NOT_FOUND', message: 'Scratch card not found' };
      }

      const card = cardRes.rows[0];
      if (card.is_scratched) {
        await client.query('ROLLBACK');
        return { success: false, error: 'ALREADY_SCRATCHED', message: 'This card is already claimed.' };
      }

      const reward = card.coin_reward;

      // Update card status
      await client.query(
        `UPDATE public.scratch_cards 
         SET is_scratched = TRUE, scratched_at = NOW() 
         WHERE id = $1`,
        [cardId]
      );

      // Credit wallet
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, balance)
         VALUES ($1, $2)
         ON CONFLICT (user_id) 
         DO UPDATE SET balance = public.wallets.balance + $2
         RETURNING balance`,
        [userId, reward]
      );

      const newBalance = walletRes.rows[0].balance;

      // Log wallet credit transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', 'instant_call_scratch_reward', $3)`,
        [userId, reward, cardId]
      );

      await client.query('COMMIT');
      return { success: true, coinReward: reward, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error claiming scratch card ${cardId} for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Escrow coins from male wallet for Instant Connect queue
   * @param {string} userId
   * @param {number} amount
   * @returns {Promise<{ success: boolean, newBalance?: number, error?: string, message?: string }>}
   */
  async escrowMaleCoins(userId, amount) {
    if (!amount || amount < 10) {
      return { success: false, error: 'INVALID_AMOUNT', message: 'Minimum bid amount is 10 coins.' };
    }

    const isSub = await subscriptionsService.isSubscribed(userId);
    if (!isSub) {
      return {
        success: false,
        error: 'SUBSCRIPTION_REQUIRED',
        message: 'An active subscription is required to use Instant Connect.',
      };
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const walletRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance - $1
         WHERE user_id = $2 AND balance >= $1
         RETURNING balance`,
        [amount, userId]
      );

      if (walletRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: 'INSUFFICIENT_BALANCE',
          message: 'Insufficient coins in your wallet. Please recharge to continue.',
        };
      }

      const newBalance = walletRes.rows[0].balance;

      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason)
         VALUES ($1, $2, 'debit', 'instant_call_escrow')`,
        [userId, amount]
      );

      await client.query('COMMIT');
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error escrowing coins for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Refund escrowed coins when male cancels before call connects
   * @param {string} userId
   * @param {number} amount
   * @param {string} [sessionId]
   * @returns {Promise<{ success: boolean, newBalance: number }>}
   */
  async refundEscrowedCoins(userId, amount, sessionId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const walletRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance + $1
         WHERE user_id = $2
         RETURNING balance`,
        [amount, userId]
      );

      const newBalance = walletRes.rows[0]?.balance || 0;

      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', 'instant_call_refund', $3)`,
        [userId, amount, sessionId || null]
      );

      if (sessionId) {
        await client.query(
          `UPDATE public.instant_call_sessions 
           SET status = 'cancelled', ended_at = NOW() 
           WHERE id = $1`,
          [sessionId]
        );
      }

      await client.query('COMMIT');
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error refunding escrow for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Create an instant call session
   * @param {string} maleUserId
   * @param {number} bidAmount
   * @returns {Promise<Object>}
   */
  async createSession(maleUserId, bidAmount) {
    const res = await db.query(
      `INSERT INTO public.instant_call_sessions (male_user_id, bid_amount, status)
       VALUES ($1, $2, 'queued')
       RETURNING id, male_user_id, bid_amount, status, created_at`,
      [maleUserId, bidAmount]
    );
    return res.rows[0];
  }

  /**
   * Assign matched female to the session and start call
   * @param {string} sessionId
   * @param {string} femaleUserId
   * @param {string} agoraChannelName
   * @returns {Promise<Object>}
   */
  async startCallSession(sessionId, femaleUserId, agoraChannelName) {
    const res = await db.query(
      `UPDATE public.instant_call_sessions
       SET female_user_id = $1, agora_channel_name = $2, status = 'in_call', started_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [femaleUserId, agoraChannelName, sessionId]
    );
    return res.rows[0];
  }

  /**
   * Trigger 10-Minute Milestone and generate Scratch Card for Female
   * Margin calculation: 35% to 65% of bidAmount awarded to female, rest retained as app margin
   * @param {string} sessionId
   * @returns {Promise<Object|null>} generated scratch card
   */
  async trigger10MinuteMilestone(sessionId) {
    try {
      const sessRes = await db.query(
        `SELECT id, male_user_id, female_user_id, bid_amount, scratch_card_unlocked 
         FROM public.instant_call_sessions 
         WHERE id = $1`,
        [sessionId]
      );

      if (sessRes.rows.length === 0) return null;
      const session = sessRes.rows[0];

      if (session.scratch_card_unlocked || !session.female_user_id) {
        return null; // Already unlocked or invalid
      }

      // Calculate reward: between 30% and 50% of bid_amount (min 1 coin)
      const bid = session.bid_amount;
      const minReward = Math.max(1, Math.floor(bid * 0.30));
      const maxReward = Math.max(minReward + 1, Math.floor(bid * 0.50));
      const coinReward = Math.floor(Math.random() * (maxReward - minReward + 1)) + minReward;

      // Update session milestone
      await db.query(
        `UPDATE public.instant_call_sessions 
         SET milestone_10m_at = NOW(), scratch_card_unlocked = TRUE 
         WHERE id = $1`,
        [sessionId]
      );

      // Create scratch card row
      const cardRes = await db.query(
        `INSERT INTO public.scratch_cards (session_id, female_user_id, coin_reward)
         VALUES ($1, $2, $3)
         RETURNING id, session_id, female_user_id, coin_reward, is_scratched, created_at`,
        [sessionId, session.female_user_id, coinReward]
      );

      return cardRes.rows[0];
    } catch (err) {
      console.error(`Error in trigger10MinuteMilestone for session ${sessionId}:`, err.message);
      return null;
    }
  }

  /**
   * End an instant call session and record final duration
   * @param {string} sessionId
   * @param {string} finalStatus - 'completed' | 'dropped' | 'cancelled'
   * @param {number} durationSeconds
   */
  async endCallSession(sessionId, finalStatus, durationSeconds) {
    try {
      await db.query(
        `UPDATE public.instant_call_sessions 
         SET status = $1, ended_at = NOW(), duration_seconds = $2
         WHERE id = $3`,
        [finalStatus, durationSeconds, sessionId]
      );
    } catch (err) {
      console.error(`Error ending instant call session ${sessionId}:`, err.message);
    }
  }

  /**
   * Find a batch of eligible female users for 1:10 FCM surge when available socket pool is empty
   * @param {string[]} excludeUserIds
   * @param {number} count
   * @returns {Promise<Array<{ id: string, fcm_token: string|null, full_name: string }>>}
   */
  async getSurgeEligibleFemales(excludeUserIds = [], count = 10) {
    try {
      const excludeClause = excludeUserIds.length > 0
        ? `AND u.id NOT IN (${excludeUserIds.map((_, i) => `$${i + 2}`).join(', ')})`
        : '';
      const params = [count, ...excludeUserIds];

      const res = await db.query(
        `SELECT u.id, u.fcm_token, u.full_name
         FROM public.users u
         WHERE (LOWER(u.gender) IN ('female', 'girl', 'woman', 'f'))
           AND u.incoming_paid_calls_enabled = true
           AND u.fcm_token IS NOT NULL
           ${excludeClause}
         ORDER BY RANDOM()
         LIMIT $1`,
        params
      );
      console.log(`🔍 [Surge Check] Found ${res.rows.length} surge-eligible females with FCM tokens`);
      return res.rows;
    } catch (err) {
      console.error('Error finding surge eligible females:', err.message);
      return [];
    }
  }
}

const instantConnectService = new InstantConnectService();

module.exports = {
  InstantConnectService,
  instantConnectService,
};
