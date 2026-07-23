const db = require('../../db');
const { RoseService } = require('../wallet/rose.service');

class WithdrawalsService {
  /**
   * Request a withdrawal. Validates balance, atomically debits roses,
   * and creates a pending withdrawal request.
   *
   * @param {string} userId
   * @param {number} roseAmount
   * @returns {Promise<{ success: boolean, withdrawal?: object, error?: string }>}
   */
  async requestWithdrawal(userId, roseAmount) {
    if (!roseAmount || roseAmount <= 0) {
      return { success: false, error: 'Invalid withdrawal amount.' };
    }

    // Check current balance first
    const currentBalance = await RoseService.getRoseBalance(userId);
    if (currentBalance < roseAmount) {
      return { success: false, error: `Insufficient roses. You have ${currentBalance} roses but requested ${roseAmount}.` };
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // Create withdrawal request
      const rupeeAmount = roseAmount; // 1:1 conversion
      const insertRes = await client.query(
        `INSERT INTO public.withdrawal_requests (user_id, rose_amount, rupee_amount, status)
         VALUES ($1, $2, $3, 'pending')
         RETURNING id, rose_amount, rupee_amount, status, requested_at`,
        [userId, roseAmount, rupeeAmount]
      );

      const withdrawalId = insertRes.rows[0].id;

      // Atomically debit roses
      const debitRes = await RoseService.debitRosesForWithdrawal(userId, roseAmount, withdrawalId);
      if (!debitRes.success) {
        await client.query('ROLLBACK');
        return { success: false, error: 'Failed to debit roses — balance may have changed.' };
      }

      await client.query('COMMIT');

      return {
        success: true,
        withdrawal: insertRes.rows[0],
        newBalance: debitRes.newBalance,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error('Error creating withdrawal request:', err.message);
      return { success: false, error: 'Internal error processing withdrawal.' };
    } finally {
      client.release();
    }
  }

  /**
   * Get withdrawal history for a user.
   *
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getWithdrawals(userId) {
    try {
      const result = await db.query(
        `SELECT id, rose_amount, rupee_amount, status, requested_at, processed_at
         FROM public.withdrawal_requests
         WHERE user_id = $1
         ORDER BY requested_at DESC
         LIMIT 50`,
        [userId]
      );
      return result.rows;
    } catch (err) {
      console.error('Error fetching withdrawals:', err.message);
      return [];
    }
  }
}

module.exports = { WithdrawalsService: new WithdrawalsService() };
