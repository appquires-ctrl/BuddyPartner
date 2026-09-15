const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WalletService } = require('./wallet.service');
const { cacheService } = require('../../services/cache.service');

/**
 * GET /api/wallet/balance
 * Returns the current dual coin balance for the authenticated user.
 * Cached in Redis for 15s to support rapid polling/home refresh without DB spikes.
 */
router.get('/wallet/balance', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const balanceData = await cacheService.getOrSet(`user:balance:${userId}`, 15, async () => {
      return await WalletService.getBalance(userId);
    });

    res.json({
      success: true,
      spendableBalance: balanceData.spendableBalance || 0,
      earnedBalance: balanceData.earnedBalance || 0,
      balance: balanceData.balance || 0,
    });
  } catch (err) {
    console.error('❌ Error fetching wallet balance:', err.message);
    res.json({
      success: true,
      spendableBalance: 0,
      earnedBalance: 0,
      balance: 0,
    });
  }
});

/**
 * GET /api/wallet/transactions?cursor=&limit=
 * Reads from wallet_transactions for authenticated user, cursor-paginated.
 */
router.get('/wallet/transactions', authMiddleware, async (req, res) => {
  try {
    const { cursor, limit } = req.query;
    const result = await WalletService.getTransactions(req.user.id, cursor || null, limit || 20);
    res.json(result);
  } catch (err) {
    console.error('❌ Error fetching wallet transactions:', err.message);
    res.status(500).json({ error: 'Failed to fetch wallet transactions' });
  }
});

/**
 * POST /api/wallet/recharge
 * Credits coins to user's spendable_balance (purchased coins are non-withdrawable).
 * Supports idempotencyKey via body or x-idempotency-key header.
 */
router.post('/wallet/recharge', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const amount = parseInt(req.body.amount, 10);
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Valid amount is required.' });
    }

    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;
    const paymentReference = req.body.paymentReference ? String(req.body.paymentReference) : null;

    const result = await WalletService.creditCoins({
      userId,
      spendable: amount,
      earned: 0,
      reason: 'recharge',
      referenceId: paymentReference,
      idempotencyKey,
    });

    res.json({
      success: true,
      amount,
      spendableBalance: result.spendableBalance,
      earnedBalance: result.earnedBalance,
      balance: result.balance,
      paymentReference,
    });
  } catch (err) {
    console.error('❌ Error in POST /api/wallet/recharge:', err.message);
    res.status(500).json({ error: 'Failed to recharge wallet: ' + err.message });
  }
});

module.exports = router;
