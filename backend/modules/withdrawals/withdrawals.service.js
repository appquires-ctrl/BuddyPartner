const db = require('../../db');
const { cacheService } = require('../../services/cache.service');

class WithdrawalsService {
  /**
   * Request a withdrawal.
   * Atomically debits earned_balance ONLY and creates a pending withdrawal row.
   * Rejects if only spendable_balance exists.
   * Enforces max 1 concurrent pending withdrawal per user.
   *
   * @param {Object} params
   * @param {string} params.userId
   * @param {number} params.amount
   * @param {string} [params.payoutMethod='upi']
   * @param {Object} [params.payoutDetails={}]
   * @param {string} [params.idempotencyKey=null]
   * @returns {Promise<{ success: boolean, withdrawal?: object, spendableBalance?: number, earnedBalance?: number, balance?: number, error?: string, code?: string }>}
   */
  async requestWithdrawal({
    userId,
    amount,
    payoutMethod = 'upi',
    payoutDetails = {},
    idempotencyKey = null,
  }) {
    const intAmount = parseInt(amount, 10);
    if (!intAmount || intAmount <= 0) {
      return { success: false, error: 'Invalid withdrawal amount. Must be a positive integer.', code: 'INVALID_AMOUNT' };
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Idempotency check
      if (idempotencyKey) {
        const existing = await client.query(
          'SELECT * FROM public.withdrawals WHERE idempotency_key = $1',
          [idempotencyKey]
        );
        if (existing.rows.length > 0) {
          const w = existing.rows[0];
          const walletRes = await client.query(
            'SELECT spendable_balance, earned_balance FROM public.wallets WHERE user_id = $1',
            [userId]
          );
          const sBal = Number(walletRes.rows[0]?.spendable_balance || 0);
          const eBal = Number(walletRes.rows[0]?.earned_balance || 0);
          await client.query('COMMIT');
          return {
            success: true,
            withdrawal: w,
            spendableBalance: sBal,
            earnedBalance: eBal,
            balance: sBal + eBal,
            alreadyProcessed: true,
          };
        }
      }

      // 2. Enforce max 1 concurrent pending withdrawal per user
      const pendingCheck = await client.query(
        `SELECT id FROM public.withdrawals WHERE user_id = $1 AND status = 'pending' LIMIT 1`,
        [userId]
      );
      if (pendingCheck.rows.length > 0) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: 'You already have a pending withdrawal request. Please wait for it to be processed.',
          code: 'CONCURRENT_PENDING_NOT_ALLOWED',
        };
      }

      // 3. Conditional atomic debit strictly from earned_balance
      const debitRes = await client.query(
        `UPDATE public.wallets
         SET earned_balance = earned_balance - $1::bigint,
             updated_at = NOW()
         WHERE user_id = $2 AND earned_balance >= $1::bigint
         RETURNING spendable_balance, earned_balance`,
        [intAmount, userId]
      );

      if (debitRes.rows.length === 0) {
        // Find current balances to provide helpful rejection reason
        const curWallet = await client.query(
          'SELECT spendable_balance, earned_balance FROM public.wallets WHERE user_id = $1',
          [userId]
        );
        await client.query('ROLLBACK');

        const currentEarned = Number(curWallet.rows[0]?.earned_balance || 0);
        const currentSpendable = Number(curWallet.rows[0]?.spendable_balance || 0);

        if (currentSpendable >= intAmount && currentEarned < intAmount) {
          return {
            success: false,
            error: `Purchased coins cannot be withdrawn. You have ${currentEarned} withdrawable earned coins, but requested ${intAmount}.`,
            code: 'SPENDABLE_NOT_WITHDRAWABLE',
          };
        }

        return {
          success: false,
          error: `Insufficient earned balance. Available withdrawable coins: ${currentEarned}.`,
          code: 'INSUFFICIENT_EARNED_BALANCE',
        };
      }

      const newSpendable = Number(debitRes.rows[0].spendable_balance);
      const newEarned = Number(debitRes.rows[0].earned_balance);
      const rupeeAmount = intAmount; // 1 Earned Coin = ₹1 INR

      // 4. Create pending withdrawal record
      const insertRes = await client.query(
        `INSERT INTO public.withdrawals (
           user_id, amount, rupee_amount, status, idempotency_key, payout_method, payout_details
         ) VALUES ($1, $2, $3, 'pending', $4, $5, $6)
         RETURNING id, user_id, amount, rupee_amount, status, payout_method, payout_details, requested_at`,
        [userId, intAmount, rupeeAmount, idempotencyKey, payoutMethod, JSON.stringify(payoutDetails)]
      );

      const withdrawal = insertRes.rows[0];

      // 5. Insert ledger audit entry (spendable_delta = 0, earned_delta = -amount)
      await client.query(
        `INSERT INTO public.wallet_transactions (
           user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
         ) VALUES ($1, 0, $2, $3, 'withdrawal_hold', $4)`,
        [userId, -intAmount, idempotencyKey ? `tx_${idempotencyKey}` : null, withdrawal.id]
      );

      await client.query('COMMIT');
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      console.log(`🏦 [Withdrawal] Request created for ${userId}: ${intAmount} coins held. Remaining earned: ${newEarned}`);

      return {
        success: true,
        withdrawal,
        spendableBalance: newSpendable,
        earnedBalance: newEarned,
        balance: newSpendable + newEarned,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      if (err.code === '23505' && err.constraint === 'idx_withdrawals_single_pending') {
        return {
          success: false,
          error: 'You already have a pending withdrawal request.',
          code: 'CONCURRENT_PENDING_NOT_ALLOWED',
        };
      }
      console.error(`❌ [WithdrawalsService.requestWithdrawal] Error:`, err.message);
      return { success: false, error: 'Internal server error processing withdrawal.', code: 'SERVER_ERROR' };
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
        `SELECT id, amount, rupee_amount, status, payout_method, payout_details, admin_note, requested_at, processed_at
         FROM public.withdrawals
         WHERE user_id = $1
         ORDER BY requested_at DESC
         LIMIT 50`,
        [userId]
      );
      return result.rows;
    } catch (err) {
      console.error(`❌ [WithdrawalsService.getWithdrawals] Error for ${userId}:`, err.message);
      return [];
    }
  }
}

module.exports = {
  WithdrawalsService: new WithdrawalsService(),
};
