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
  async requestWithdrawal(userId, amount) {
    if (!amount || amount <= 0) {
      return { success: false, error: 'Invalid withdrawal amount.' };
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // Check wallet balance first (where scratch card earnings are stored)
      const walletRes = await client.query('SELECT balance FROM public.wallets WHERE user_id = $1', [userId]);
      const currentWallet = walletRes.rows[0]?.balance || 0;

      // Check rose balance as fallback
      const roseRes = await client.query('SELECT balance FROM public.rose_balances WHERE user_id = $1', [userId]);
      const currentRoses = roseRes.rows[0]?.balance || 0;

      if (currentWallet < amount && currentRoses < amount) {
        await client.query('ROLLBACK');
        return { success: false, error: `Insufficient balance. You have ${Math.max(currentWallet, currentRoses)} coins/roses but requested ${amount}.` };
      }

      // Create withdrawal request
      const rupeeAmount = amount; // 1 Coin / 1 Rose = ₹1
      const insertRes = await client.query(
        `INSERT INTO public.withdrawal_requests (user_id, rose_amount, rupee_amount, status)
         VALUES ($1, $2, $3, 'pending')
         RETURNING id, rose_amount, rupee_amount, status, requested_at`,
        [userId, amount, rupeeAmount]
      );

      const withdrawalId = insertRes.rows[0].id;

      // Atomically debit from wallets table if wallet has balance
      if (currentWallet >= amount) {
        await client.query(
          `UPDATE public.wallets SET balance = balance - $1 WHERE user_id = $2`,
          [amount, userId]
        );
        await client.query(
          `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
           VALUES ($1, $2, 'debit', 'withdrawal_request', $3)`,
          [userId, amount, withdrawalId]
        );
      } else {
        await RoseService.debitRosesForWithdrawal(userId, amount, withdrawalId);
      }

      await client.query('COMMIT');

      return {
        success: true,
        withdrawal: insertRes.rows[0],
        newBalance: currentWallet >= amount ? (currentWallet - amount) : 0,
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
