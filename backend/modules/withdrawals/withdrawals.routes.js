const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WithdrawalsService } = require('./withdrawals.service');

/**
 * POST /api/withdrawals
 * Request a withdrawal from earned_balance.
 * Body: { amount: number, payoutMethod?: string, payoutDetails?: object, idempotencyKey?: string }
 */
router.post('/withdrawals', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const rawAmount = req.body.amount || req.body.coinAmount;
    const amount = parseInt(rawAmount, 10);
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid withdrawal amount. Must be a positive integer.' });
    }

    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;
    const payoutMethod = req.body.payoutMethod || 'upi';
    const payoutDetails = req.body.payoutDetails || {};

    const result = await WithdrawalsService.requestWithdrawal({
      userId,
      amount,
      payoutMethod,
      payoutDetails,
      idempotencyKey,
    });

    if (!result.success) {
      const statusCode = result.code === 'CONCURRENT_PENDING_NOT_ALLOWED' ? 409 : 400;
      return res.status(statusCode).json({
        success: false,
        error: result.error,
        code: result.code,
      });
    }

    res.status(201).json({
      success: true,
      withdrawal: result.withdrawal,
      spendableBalance: result.spendableBalance,
      earnedBalance: result.earnedBalance,
      balance: result.balance,
      alreadyProcessed: result.alreadyProcessed || false,
    });
  } catch (err) {
    console.error('❌ Error in POST /withdrawals:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

/**
 * GET /api/withdrawals
 * List the authenticated user's withdrawal requests.
 */
router.get('/withdrawals', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const withdrawals = await WithdrawalsService.getWithdrawals(userId);
    res.json({ success: true, withdrawals });
  } catch (err) {
    console.error('❌ Error in GET /withdrawals:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

module.exports = router;
