const crypto = require('crypto');
const db = require('../../db');
const { cacheService } = require('../../services/cache.service');

class WalletService {
  /**
   * Reads current dual balance for a user.
   *
   * @param {string} userId
   * @returns {Promise<{ spendableBalance: number, earnedBalance: number, balance: number }>}
   */
  async getBalance(userId) {
    try {
      const result = await db.query(
        'SELECT spendable_balance, earned_balance FROM public.wallets WHERE user_id = $1',
        [userId]
      );
      if (result.rows.length === 0) {
        return { spendableBalance: 0, earnedBalance: 0, balance: 0 };
      }
      const spendable = Number(result.rows[0].spendable_balance) || 0;
      const earned = Number(result.rows[0].earned_balance) || 0;
      return {
        spendableBalance: spendable,
        earnedBalance: earned,
        balance: spendable + earned,
      };
    } catch (err) {
      console.error(`❌ [WalletService.getBalance] Error for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Checks if user has minimum total required balance across both buckets.
   *
   * @param {string} userId
   * @param {number} requiredAmount
   * @returns {Promise<boolean>}
   */
  async hasMinimumBalance(userId, requiredAmount) {
    const { balance } = await this.getBalance(userId);
    return balance >= Number(requiredAmount);
  }

  /**
   * Atomically debits coins using spendable-first ordering.
   * Conditional update checks sufficiency inline without separate SELECT FOR UPDATE.
   *
   * @param {Object} params
   * @param {string} params.userId
   * @param {number} params.amount
   * @param {string} params.reason
   * @param {string} [params.referenceId]
   * @param {string} [params.idempotencyKey]
   * @param {string} [params.correlationId]
   * @param {import('pg').PoolClient} [params.client] - optional external transaction client
   * @returns {Promise<{ success: boolean, spendableBalance: number, earnedBalance: number, balance: number, spendableDeducted: number, earnedDeducted: number, alreadyProcessed?: boolean }>}
   */
  async debitCoins({
    userId,
    amount,
    reason,
    referenceId = null,
    idempotencyKey = null,
    correlationId = null,
    client: externalClient = null,
  }) {
    const cid = correlationId || `corr_${crypto.randomBytes(8).toString('hex')}`;
    const intAmount = parseInt(amount, 10);
    if (isNaN(intAmount) || intAmount <= 0) {
      throw new Error(`Invalid debit amount: ${amount}`);
    }

    const client = externalClient || await db.pool.connect();
    const shouldManageTx = !externalClient;

    try {
      if (shouldManageTx) await client.query('BEGIN');

      // 1. Check idempotency key if provided
      if (idempotencyKey) {
        const existingTx = await client.query(
          `SELECT t.*, w.spendable_balance, w.earned_balance
           FROM public.wallet_transactions t
           JOIN public.wallets w ON w.user_id = t.user_id
           WHERE t.idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingTx.rows.length > 0) {
          const row = existingTx.rows[0];
          const sBal = Number(row.spendable_balance);
          const eBal = Number(row.earned_balance);
          console.log(`🔁 [Wallet.debitCoins] Idempotency hit: key ${idempotencyKey} already executed. Correlation: ${cid}`);
          if (shouldManageTx) await client.query('COMMIT');
          return {
            success: true,
            spendableBalance: sBal,
            earnedBalance: eBal,
            balance: sBal + eBal,
            spendableDeducted: Math.abs(Number(row.spendable_delta)),
            earnedDeducted: Math.abs(Number(row.earned_delta)),
            alreadyProcessed: true,
          };
        }
      }

      // 2. Single conditional atomic UPDATE with spendable-first deduction
      const updateRes = await client.query(
        `WITH prev AS (
           SELECT user_id, spendable_balance, earned_balance
           FROM public.wallets
           WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
           FOR UPDATE
         )
         UPDATE public.wallets w
         SET 
           spendable_balance = w.spendable_balance - LEAST(prev.spendable_balance, $1::bigint),
           earned_balance = w.earned_balance - ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)),
           updated_at = NOW()
         FROM prev
         WHERE w.user_id = prev.user_id
         RETURNING 
           w.spendable_balance, 
           w.earned_balance,
           LEAST(prev.spendable_balance, $1::bigint) AS spendable_deducted,
           ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)) AS earned_deducted`,
        [intAmount, userId]
      );

      if (updateRes.rows.length === 0) {
        if (shouldManageTx) await client.query('ROLLBACK');
        console.warn(`💰 [Wallet.debitCoins] Insufficient balance or user missing for ${userId}. Requested: ${intAmount}. Correlation: ${cid}`);
        return {
          success: false,
          spendableBalance: null,
          earnedBalance: null,
          balance: null,
          spendableDeducted: 0,
          earnedDeducted: 0,
        };
      }

      const updated = updateRes.rows[0];
      const sBal = Number(updated.spendable_balance);
      const eBal = Number(updated.earned_balance);
      const sDeduct = Number(updated.spendable_deducted);
      const eDeduct = Number(updated.earned_deducted);

      // 3. Insert transaction ledger entry
      const txRes = await client.query(
        `INSERT INTO public.wallet_transactions (
           user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
         ) VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [userId, -sDeduct, -eDeduct, idempotencyKey, reason, referenceId]
      );

      if (shouldManageTx) await client.query('COMMIT');

      // Invalidate Redis balance cache
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      console.log(`💰 [Wallet.debitCoins] Success for ${userId}: -${sDeduct} spendable, -${eDeduct} earned. Remaining: ${sBal}s + ${eBal}e = ${sBal + eBal}. Reason: ${reason}. Correlation: ${cid}`);

      return {
        success: true,
        transactionId: txRes.rows[0]?.id || null,
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
        spendableDeducted: sDeduct,
        earnedDeducted: eDeduct,
      };
    } catch (err) {
      if (shouldManageTx) await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [Wallet.debitCoins] Error for ${userId}: ${err.message}. Correlation: ${cid}`);
      throw err;
    } finally {
      if (shouldManageTx) client.release();
    }
  }

  /**
   * Atomically credits coins to spendable and/or earned buckets.
   *
   * @param {Object} params
   * @param {string} params.userId
   * @param {number} [params.spendable] - amount to credit to spendable_balance
   * @param {number} [params.earned] - amount to credit to earned_balance
   * @param {string} params.reason
   * @param {string} [params.referenceId]
   * @param {string} [params.idempotencyKey]
   * @param {string} [params.correlationId]
   * @param {import('pg').PoolClient} [params.client] - optional external transaction client
   * @returns {Promise<{ success: boolean, spendableBalance: number, earnedBalance: number, balance: number, alreadyProcessed?: boolean }>}
   */
  async creditCoins({
    userId,
    spendable = 0,
    earned = 0,
    reason,
    referenceId = null,
    idempotencyKey = null,
    correlationId = null,
    client: externalClient = null,
  }) {
    const cid = correlationId || `corr_${crypto.randomBytes(8).toString('hex')}`;
    const intSpendable = parseInt(spendable, 10) || 0;
    const intEarned = parseInt(earned, 10) || 0;

    if (intSpendable < 0 || intEarned < 0 || (intSpendable === 0 && intEarned === 0)) {
      throw new Error(`Invalid credit amounts: spendable=${spendable}, earned=${earned}`);
    }

    const client = externalClient || await db.pool.connect();
    const shouldManageTx = !externalClient;

    try {
      if (shouldManageTx) await client.query('BEGIN');

      // 1. Check idempotency key if provided
      if (idempotencyKey) {
        const existingTx = await client.query(
          `SELECT t.*, w.spendable_balance, w.earned_balance
           FROM public.wallet_transactions t
           JOIN public.wallets w ON w.user_id = t.user_id
           WHERE t.idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingTx.rows.length > 0) {
          const row = existingTx.rows[0];
          const sBal = Number(row.spendable_balance);
          const eBal = Number(row.earned_balance);
          console.log(`🔁 [Wallet.creditCoins] Idempotency hit: key ${idempotencyKey} already executed. Correlation: ${cid}`);
          if (shouldManageTx) await client.query('COMMIT');
          return {
            success: true,
            spendableBalance: sBal,
            earnedBalance: eBal,
            balance: sBal + eBal,
            alreadyProcessed: true,
          };
        }
      }

      // 2. Upsert into wallets
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id)
         DO UPDATE SET 
           spendable_balance = public.wallets.spendable_balance + $2,
           earned_balance = public.wallets.earned_balance + $3,
           updated_at = NOW()
         RETURNING spendable_balance, earned_balance`,
        [userId, intSpendable, intEarned]
      );

      const sBal = Number(walletRes.rows[0].spendable_balance);
      const eBal = Number(walletRes.rows[0].earned_balance);

      // 3. Record transaction ledger row
      await client.query(
        `INSERT INTO public.wallet_transactions (
           user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
         ) VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, intSpendable, intEarned, idempotencyKey, reason, referenceId]
      );

      if (shouldManageTx) await client.query('COMMIT');

      // Invalidate Redis balance cache
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      console.log(`💰 [Wallet.creditCoins] Success for ${userId}: +${intSpendable} spendable, +${intEarned} earned. Total: ${sBal}s + ${eBal}e = ${sBal + eBal}. Reason: ${reason}. Correlation: ${cid}`);

      return {
        success: true,
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
      };
    } catch (err) {
      if (shouldManageTx) await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [Wallet.creditCoins] Error for ${userId}: ${err.message}. Correlation: ${cid}`);
      throw err;
    } finally {
      if (shouldManageTx) client.release();
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
        SELECT id, spendable_delta, earned_delta, reason, reference_id, created_at
        FROM public.wallet_transactions
        WHERE user_id = $1 AND created_at < $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
      params = [userId, cursor, parsedLimit];
    } else {
      query = `
        SELECT id, spendable_delta, earned_delta, reason, reference_id, created_at
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
      iap_purchase: 'Google Play Recharge',
      razorpay_purchase: 'Razorpay Recharge',
      recharge: 'Coins Recharge',
      buddy_spend: 'Buddy Request',
      buddy_reward: 'Buddy Meetup Reward',
      withdrawal_hold: 'Withdrawal Hold',
      withdrawal_reject_refund: 'Withdrawal Refund',
      admin_grant: 'Admin Gift',
      instant_call_scratch_reward: 'Scratch Card Reward',
      instant_call_escrow: 'Instant Connect Escrow',
      instant_call_refund: 'Instant Connect Refund',
      signup_bonus: 'Welcome Bonus',
    };

    const transactions = rows.map((row) => {
      const sDelta = Number(row.spendable_delta);
      const eDelta = Number(row.earned_delta);
      const totalDelta = sDelta + eDelta;
      return {
        id: row.id,
        spendableDelta: sDelta,
        earnedDelta: eDelta,
        amount: Math.abs(totalDelta),
        type: totalDelta >= 0 ? 'credit' : 'debit',
        reason: row.reason,
        reasonLabel: reasonLabels[row.reason] || row.reason.replace(/_/g, ' '),
        referenceId: row.reference_id,
        createdAt: row.created_at,
      };
    });

    const nextCursor = rows.length === parsedLimit
      ? rows[rows.length - 1].created_at.toISOString()
      : null;

    return { transactions, nextCursor };
  }
}

module.exports = {
  WalletService: new WalletService(),
};
