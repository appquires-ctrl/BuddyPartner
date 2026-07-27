const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { RoseService } = require('./rose.service');

/**
 * GET /api/roses/balance
 * Returns the current rose balance for the authenticated user.
 */
router.get('/roses/balance', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const balance = await RoseService.getRoseBalance(userId);
    res.json({ success: true, balance });
  } catch (err) {
    console.error('Error fetching rose balance:', err.message);
    res.status(500).json({ error: 'Failed to fetch rose balance.' });
  }
});

/**
 * GET /api/wallet/transactions?cursor=&limit=
 * Reads from wallet_transactions for male users, cursor-paginated.
 */
router.get('/wallet/transactions', authMiddleware, async (req, res) => {
  try {
    const { WalletService } = require('./wallet.service');
    const { cursor, limit } = req.query;
    const result = await WalletService.getTransactions(req.user.id, cursor || null, limit || 20);
    res.json(result);
  } catch (err) {
    console.error('Error fetching wallet transactions:', err.message);
    res.status(500).json({ error: 'Failed to fetch wallet transactions' });
  }
});

/**
 * GET /api/roses/transactions?cursor=&limit=
 * Reads from rose_transactions for female users, cursor-paginated.
 */
router.get('/roses/transactions', authMiddleware, async (req, res) => {
  try {
    const { cursor, limit } = req.query;
    const result = await RoseService.getTransactions(req.user.id, cursor || null, limit || 20);
    res.json(result);
  } catch (err) {
    console.error('Error fetching rose transactions:', err.message);
    res.status(500).json({ error: 'Failed to fetch rose transactions' });
  }
});

module.exports = router;
