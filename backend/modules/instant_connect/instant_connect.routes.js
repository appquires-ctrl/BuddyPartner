const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { instantConnectService } = require('./instant_connect.service');
const redis = require('../../redis');

const router = express.Router();

// ── POST /api/instant/toggle ────────────────────────────────────────────────
// Female user toggling "Incoming Paid Calls" ON/OFF
router.post('/toggle', authMiddleware, async (req, res) => {
  try {
    const { enabled } = req.body;
    const result = await instantConnectService.toggleIncomingPaidCalls(req.user.id, enabled === true, redis);
    if (!result.success) {
      return res.status(400).json(result);
    }
    res.json(result);
  } catch (err) {
    console.error('Error in POST /api/instant/toggle:', err.message);
    res.status(500).json({ error: 'Failed to toggle incoming paid calls' });
  }
});

// ── GET /api/instant/status ─────────────────────────────────────────────────
// Get female user's instant connect status & scratch card counts
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const status = await instantConnectService.getFemaleStatus(req.user.id);
    res.json(status);
  } catch (err) {
    console.error('Error in GET /api/instant/status:', err.message);
    res.status(500).json({ error: 'Failed to fetch instant status' });
  }
});

// ── GET /api/instant/scratch-cards ──────────────────────────────────────────
// List all scratch cards for current user
router.get('/scratch-cards', authMiddleware, async (req, res) => {
  try {
    const cards = await instantConnectService.getScratchCards(req.user.id);
    res.json({ scratchCards: cards });
  } catch (err) {
    console.error('Error in GET /api/instant/scratch-cards:', err.message);
    res.status(500).json({ error: 'Failed to fetch scratch cards' });
  }
});

// ── POST /api/instant/scratch-cards/:id/scratch ─────────────────────────────
// Claim/scratch a card to credit coins to wallet
router.post('/scratch-cards/:id/scratch', authMiddleware, async (req, res) => {
  try {
    const cardId = req.params.id;
    const result = await instantConnectService.claimScratchCard(req.user.id, cardId);
    if (!result.success) {
      return res.status(400).json(result);
    }
    res.json(result);
  } catch (err) {
    console.error('Error in POST /api/instant/scratch-cards/:id/scratch:', err.message);
    res.status(500).json({ error: 'Failed to claim scratch card' });
  }
});

module.exports = router;
