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
        'SELECT balance FROM public.rose_balances WHERE user_id = $1',
        [userId]
      );
      if (result.rows.length === 0) {
        return 0;
      }
      return result.rows[0].balance;
    } catch (err) {
      console.error(`Error fetching rose balance for user ${userId}:`, err.message);
      return 0;
    }
  }

  /**
   * Credit roses for a call minute. Atomically increments balance and logs transaction.
   *
   * @param {string} userId
   * @param {string} callId
   * @param {string} callType - 'voice' or 'video'
   * @returns {Promise<{ success: boolean, newBalance: number|null }>}
   */
  async creditRoseForCallMinute(userId, callId, callType) {
    const amount = callType === 'video' ? ROSE_RATES.video : ROSE_RATES.voice;
    const reason = callType === 'video' ? 'call_minute_video' : 'call_minute_voice';

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // Ensure rose_balances row exists (upsert)
      await client.query(
        `INSERT INTO public.rose_balances (user_id, balance, updated_at)
         VALUES ($1, 0, NOW())
         ON CONFLICT (user_id) DO NOTHING`,
        [userId]
      );

      // Atomically increment balance
      const updateRes = await client.query(
        `UPDATE public.rose_balances
         SET balance = balance + $1, updated_at = NOW()
         WHERE user_id = $2
         RETURNING balance`,
        [amount, userId]
      );

      const newBalance = updateRes.rows[0].balance;

      // Log transaction
      await client.query(
        `INSERT INTO public.rose_transactions (user_id, type, amount, reason, reference_id)
         VALUES ($1, 'credit', $2, $3, $4)`,
        [userId, amount, reason, callId]
      );

      await client.query('COMMIT');
      console.log(`🌹 [Rose] CREDITED ${amount} roses (${callType}) to user ${userId} — newBalance: ${newBalance}`);
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`🌹 [Rose] ERROR crediting for user ${userId}: ${err.message}`);
      return { success: false, newBalance: null };
    } finally {
      client.release();
    }
  }

  /**
   * Debit roses for a withdrawal request. Atomic, never goes negative.
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
        `UPDATE public.rose_balances
         SET balance = balance - $1, updated_at = NOW()
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
        `INSERT INTO public.rose_transactions (user_id, type, amount, reason, reference_id)
         VALUES ($1, 'debit', $2, 'withdrawal_request', $3)`,
        [userId, amount, withdrawalId]
      );

      await client.query('COMMIT');
      console.log(`🌹 [Rose] DEBITED ${amount} roses from user ${userId} for withdrawal ${withdrawalId} — newBalance: ${newBalance}`);
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`🌹 [Rose] ERROR debiting for user ${userId}: ${err.message}`);
      return { success: false, newBalance: null };
    } finally {
      client.release();
    }
  }
}

module.exports = {
  RoseService: new RoseService(),
  ROSE_RATES,
};
