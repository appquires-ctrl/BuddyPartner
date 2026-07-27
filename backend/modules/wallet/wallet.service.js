const db = require('../../db');

const CALL_RATES = Object.freeze({
  voice: 10,
  video: 20,
});

class WalletService {
  /**
   * Reads current balance for a user.
   *
   * @param {string} userId
   * @returns {Promise<number>} balance
   */
  async getBalance(userId) {
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
      console.error(`Error fetching balance for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Checks if user has minimum required balance.
   *
   * @param {string} userId
   * @param {number} requiredAmount
   * @returns {Promise<boolean>}
   */
  async hasMinimumBalance(userId, requiredAmount) {
    const balance = await this.getBalance(userId);
    return balance >= requiredAmount;
  }

  /**
   * Atomically deducts coins for a call minute and logs transaction.
   * Uses conditional update to guarantee balance never drops below 0.
   *
   * @param {string} userId
   * @param {string} callId
   * @param {number} amount
   * @returns {Promise<{ success: boolean, newBalance: number|null }>}
   */
  async deductForCallMinute(userId, callId, amount) {
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
        console.log(`💰 [Deduct] FAILED for user ${userId} — insufficient balance or no wallet row`);
        return { success: false, newBalance: null };
      }

      const newBalance = updateRes.rows[0].balance;
      console.log(`💰 [Deduct] UPDATE OK for user ${userId} — newBalance: ${newBalance}`);

      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'debit', 'call_minute', $3)`,
        [userId, amount, callId]
      );

      await client.query('COMMIT');
      console.log(`💰 [Deduct] COMMITTED for user ${userId} — deducted ${amount}, newBalance: ${newBalance}`);
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`💰 [Deduct] ERROR for user ${userId}: ${err.message}`);
      return { success: false, newBalance: null };
    } finally {
      client.release();
    }
  }

  /**
   * Get paginated coin transactions for a user.
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
      call_minute: 'Voice Call',
      call_minute_voice: 'Voice Call',
      call_minute_video: 'Video Call',
      signup_bonus: 'Signup Bonus',
      recharge: 'Coins Recharge',
      withdrawal_request: 'Withdrawal Request',
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
  WalletService: new WalletService(),
  CALL_RATES,
};
