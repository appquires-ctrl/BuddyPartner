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
 * GET /api/wallet/balance
 * Returns the current coin balance for the authenticated user.
 */
router.get('/wallet/balance', authMiddleware, async (req, res) => {
  try {
    const { WalletService } = require('./wallet.service');
    const walletService = new WalletService();
    const balance = await walletService.getBalance(req.user.id);
    res.json({ success: true, balance });
  } catch (err) {
    console.error('Error fetching wallet balance:', err.message);
    res.status(500).json({ error: 'Failed to fetch wallet balance.' });
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

/**
 * POST /api/wallet/recharge
 * Credits coins to user's wallet (e.g. 50, 100, 200, 500 coins).
 */
router.post('/wallet/recharge', authMiddleware, async (req, res) => {
  try {
    const db = require('../../db');
    const userId = req.user.id;
    const amount = parseInt(req.body.amount, 10);
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Valid amount is required.' });
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, balance)
         VALUES ($1, $2)
         ON CONFLICT (user_id)
         DO UPDATE SET balance = public.wallets.balance + $2
         RETURNING balance`,
        [userId, amount]
      );

      const newBalance = walletRes.rows[0].balance;

      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', 'recharge', $3)`,
        [userId, amount, req.body.paymentReference || 'manual_recharge']
      );

      await client.query('COMMIT');
      res.json({ success: true, amount, newBalance });
    } catch (dbErr) {
      await client.query('ROLLBACK');
      throw dbErr;
    } finally {
      client.release();
    }
  } catch (err) {
    console.error('Error in POST /api/wallet/recharge:', err.message);
    res.status(500).json({ error: 'Failed to recharge wallet.' });
  }
});

module.exports = router;
