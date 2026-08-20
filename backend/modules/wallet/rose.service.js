const db = require('../../db');

// Rose earning rates per minute
const ROSE_RATES = Object.freeze({
  voice: 1,   // 1 rose/minute for voice calls
  video: 3,   // 3 roses/minute for video calls
});

class RoseService {
  /**
   * Get current rose balance for a user.
   *
   * @param {string} userId
   * @returns {Promise<number>}
   */
  async getRoseBalance(userId) {
    try {
      const result = await db.query(
        'SELECT balance FROM public.wallets WHERE user_id = $1',
        [userId]
      );
      if (result.rows.length === 0) {
        return 0;
      }
      return result.rows[0].balance;
    } catch (err) {
      console.error(`Error fetching wallet balance for user ${userId}:`, err.message);
      return 0;
    }
  }

  /**
   * Credit coins for a call minute. Atomically increments balance and logs transaction.
   *
   * @param {string} userId
   * @param {string} callId
   * @param {string} callType - 'voice' or 'video'
   * @returns {Promise<{ success: boolean, newBalance: number|null }>}
   */
  async creditRoseForCallMinute(userId, callId, callType) {
    // Check if female user is an active Telecaller
    const userCheck = await db.query('SELECT is_telecaller FROM public.users WHERE id = $1', [userId]);
    if (userCheck.rows.length === 0 || userCheck.rows[0].is_telecaller !== true) {
      return { success: false, skipped: true, newBalance: null };
    }

    const amount = callType === 'video' ? ROSE_RATES.video : ROSE_RATES.voice;
    const reason = callType === 'video' ? 'call_minute_video' : 'call_minute_voice';

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // Ensure wallets row exists (upsert)
      await client.query(
        `INSERT INTO public.wallets (user_id, balance)
         VALUES ($1, 0)
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      // Atomically increment balance
      const updateRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance + $1
         WHERE user_id = $2
         RETURNING balance`,
        [amount, userId]
      );

      const newBalance = updateRes.rows[0].balance;

      // Log transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, type, amount, reason, reference_id)
         VALUES ($1, 'credit', $2, $3, $4)`,
        [userId, amount, reason, callId]
      );

      await client.query('COMMIT');
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error crediting for user ${userId}: ${err.message}`);
      return { success: false, newBalance: null };
    } finally {
      client.release();
    }
  }

  /**
   * Debit coins for a withdrawal request. Atomic, never goes negative.
   *
   * @param {string} userId
   * @param {number} amount
   * @param {string} withdrawalId - UUID of the withdrawal request
   * @returns {Promise<{ success: boolean, newBalance: number|null }>}
   */
  async debitRosesForWithdrawal(userId, amount, withdrawalId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const updateRes = await client.query(
        `UPDATE public.wallets
         SET balance = balance - $1
         WHERE user_id = $2 AND balance >= $1
         RETURNING balance`,
        [amount, userId]
      );

      if (updateRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, newBalance: null };
      }

      const newBalance = updateRes.rows[0].balance;

      // Log transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, type, amount, reason, reference_id)
         VALUES ($1, 'debit', $2, 'withdrawal_request', $3)`,
        [userId, amount, withdrawalId]
      );

      await client.query('COMMIT');
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error debiting for user ${userId}: ${err.message}`);
      return { success: false, newBalance: null };
    } finally {
      client.release();
    }
  }

  /**
   * Get paginated wallet transactions for a user.
   * Scoped strictly to the specified userId.
   *
   * @param {string} userId
   * @param {string|null} cursor - ISO timestamp string
   * @param {number} limit
   * @returns {Promise<{ transactions: Array, nextCursor: string|null }>}
   */
  async getTransactions(userId, cursor = null, limit = 20) {
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);

    let query;
    let params;

    if (cursor) {
      query = `
        SELECT id, amount, type, reason, reference_id, created_at
        FROM public.wallet_transactions
        WHERE user_id = $1 AND created_at < $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
      params = [userId, cursor, parsedLimit];
    } else {
      query = `
        SELECT id, amount, type, reason, reference_id, created_at
        FROM public.wallet_transactions
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2
      `;
      params = [userId, parsedLimit];
    }

    const result = await db.query(query, params);
    const rows = result.rows;

    const reasonLabels = {
      call_minute_voice: 'Voice Call Earnings',
      call_minute_video: 'Video Call Earnings',
      instant_call_scratch_reward: 'Instant Call Scratch Card Reward',
      withdrawal_request: 'Withdrawal Request',
      wallet_recharge: 'Wallet Recharge',
      recharge: 'Wallet Recharge',
    };

    const transactions = rows.map((row) => ({
      id: row.id,
      amount: row.amount,
      type: row.type,
      reason: row.reason,
      reasonLabel: reasonLabels[row.reason] || row.reason.replace(/_/g, ' '),
      referenceId: row.reference_id,
      createdAt: row.created_at,
    }));

    const nextCursor = rows.length === parsedLimit
      ? rows[rows.length - 1].created_at.toISOString()
      : null;

    return { transactions, nextCursor };
  }
}

module.exports = {
  RoseService: new RoseService(),
  ROSE_RATES,
};
