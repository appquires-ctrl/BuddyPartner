const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WalletService } = require('./wallet.service');
const db = require('../../db');

/**
 * GET /api/wallet/balance
 * Returns the current coin balance for the authenticated user.
 */
router.get('/wallet/balance', authMiddleware, async (req, res) => {
  try {
    const result = await db.query(
      'SELECT balance FROM public.wallets WHERE user_id = $1',
      [req.user.id]
    );
    const balance = result.rows.length > 0 ? result.rows[0].balance : 0;
    res.json({ success: true, balance });
  } catch (err) {
    console.error('Error fetching wallet balance:', err.message);
    // Return 0 balance on transient DB errors instead of 500
    res.json({ success: true, balance: 0 });
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
    console.error('Error fetching wallet transactions:', err.message);
    res.status(500).json({ error: 'Failed to fetch wallet transactions' });
  }
});

/**
 * POST /api/wallet/recharge
 * Credits coins to user's wallet (e.g. 50, 100, 200, 500 coins).
 */
router.post('/wallet/recharge', authMiddleware, async (req, res) => {
  try {
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
