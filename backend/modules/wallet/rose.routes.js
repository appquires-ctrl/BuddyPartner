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

module.exports = router;
