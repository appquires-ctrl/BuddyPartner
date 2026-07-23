const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WithdrawalsService } = require('./withdrawals.service');
const db = require('../../db');

/**
 * POST /api/withdrawals
 * Request a withdrawal (girl-only).
 * Body: { roseAmount: number }
 */
router.post('/withdrawals', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;

    // Check gender — withdrawals are girl-only
    const userResult = await db.query(
      'SELECT gender FROM public.users WHERE id = $1',
      [userId]
    );

    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }

    const gender = (userResult.rows[0].gender || '').toLowerCase();
    if (gender !== 'female' && gender !== 'girl' && gender !== 'woman') {
      return res.status(403).json({ error: 'Withdrawals are only available for female users.' });
    }

    const { roseAmount } = req.body;
    if (!roseAmount || typeof roseAmount !== 'number' || roseAmount <= 0) {
      return res.status(400).json({ error: 'Invalid roseAmount. Must be a positive number.' });
    }

    const result = await WithdrawalsService.requestWithdrawal(userId, roseAmount);

    if (!result.success) {
      return res.status(400).json({ error: result.error });
    }

    res.json({
      success: true,
      withdrawal: result.withdrawal,
      newBalance: result.newBalance,
    });
  } catch (err) {
    console.error('Error in POST /withdrawals:', err.message);
    res.status(500).json({ error: 'Internal server error.' });
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
    console.error('Error in GET /withdrawals:', err.message);
    res.status(500).json({ error: 'Internal server error.' });
  }
});

module.exports = router;
