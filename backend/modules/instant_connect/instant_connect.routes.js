const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { instantConnectService } = require('./instant_connect.service');
const { PresenceService } = require('../presence/presence.service');
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
    if (enabled === true) {
      const io = req.app.get('io');
      const { triggerInstantMatchmaker } = require('./instant_connect.socket');
      if (io) {
        triggerInstantMatchmaker(io, redis);
      }
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

// Admin check middleware for dev inspection routes
function adminOnly(req, res, next) {
  const adminKey = req.headers['x-admin-key'];
  const validSecret = process.env.ADMIN_SECRET || 'buddypartner_admin_dev_secret_key';
  if (adminKey && adminKey === validSecret) {
    return next();
  }
  if (req.user && (req.user.isAdmin || req.user.role === 'admin')) {
    return next();
  }
  return res.status(403).json({ error: 'FORBIDDEN', message: 'Admin privileges required' });
}

// ── GET /api/instant/dev/queues ─────────────────────────────────────────────
// Developer queue monitor: inspect waiting males, available females, and active calls
router.get('/dev/queues', async (req, res) => {
  try {
    const db = require('../../db');
    const { activeInstantCalls } = require('./instant_connect.socket');

    // 1. Reconcile any database in_call sessions that have no matching in-memory active call
    const activeSessionIds = new Set(Array.from(activeInstantCalls.values()).map((c) => c.sessionId));
    const staleInCallRes = await db.query(`SELECT id FROM public.instant_call_sessions WHERE status = 'in_call'`);
    for (const row of staleInCallRes.rows) {
      if (!activeSessionIds.has(row.id)) {
        await db.query(`UPDATE public.instant_call_sessions SET status = 'dropped', ended_at = NOW() WHERE id = $1`, [row.id]);
      }
    }

    // 2. Waiting males
    const maleQueueIds = await redis.zrevrange('instant:male_queue', 0, -1, 'WITHSCORES');
    const waitingMales = [];
    for (let i = 0; i < maleQueueIds.length; i += 2) {
      const userId = maleQueueIds[i];
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      const sessionData = sessionStr ? JSON.parse(sessionStr) : {};
      const userRes = await db.query('SELECT full_name, phone_number FROM public.users WHERE id = $1', [userId]);
      waitingMales.push({
        position: (i / 2) + 1,
        userId,
        fullName: userRes.rows[0]?.full_name || 'Unknown',
        phoneNumber: userRes.rows[0]?.phone_number || 'N/A',
        bidAmount: sessionData.bidAmount || 0,
        sessionId: sessionData.sessionId,
      });
    }

    // 3. Active females in Redis (reconcile with DB toggle)
    const dbFemales = await db.query(`
      SELECT id, full_name, phone_number, incoming_paid_calls_enabled
      FROM public.users
      WHERE incoming_paid_calls_enabled = true
        AND (LOWER(gender) IN ('female', 'girl', 'woman', 'f'))
    `);

    for (const f of dbFemales.rows) {
      await redis.sadd('instant:female_pool', f.id);
    }

    const io = req.app.get('io');
    const { getSocketForUser } = require('./instant_connect.socket');
    const femaleIds = await redis.smembers('instant:female_pool');
    const activeFemales = [];

    for (const fId of femaleIds) {
      const userRes = await db.query('SELECT full_name, phone_number, incoming_paid_calls_enabled FROM public.users WHERE id = $1', [fId]);
      if (userRes.rows[0]?.incoming_paid_calls_enabled !== true) {
        await redis.srem('instant:female_pool', fId);
        continue;
      }

      const fSocket = getSocketForUser(io, fId);
      const isRedisOnline = await PresenceService.isUserOnline(redis, fId);
      const isOnline = !!fSocket || isRedisOnline;
      const isSnoozed = await redis.get(`instant:snooze:${fId}`);
      activeFemales.push({
        userId: fId,
        fullName: userRes.rows[0]?.full_name || 'Unknown',
        phoneNumber: userRes.rows[0]?.phone_number || 'N/A',
        isSnoozed: !!isSnoozed,
        isOnline: isOnline,
      });
    }

    // 4. Ongoing active calls (only those truly in memory & db)
    const activeCallsRes = await db.query(`
      SELECT s.id, s.bid_amount, s.status, s.agora_channel_name, s.started_at, s.scratch_card_unlocked,
             m.full_name as male_name, f.full_name as female_name
      FROM public.instant_call_sessions s
      LEFT JOIN public.users m ON m.id = s.male_user_id
      LEFT JOIN public.users f ON f.id = s.female_user_id
      WHERE s.status = 'in_call'
      ORDER BY s.started_at DESC
    `);

    res.json({
      timestamp: new Date().toISOString(),
      waitingMalesCount: waitingMales.length,
      waitingMales,
      activeFemalesCount: activeFemales.length,
      activeFemales,
      ongoingCallsCount: activeCallsRes.rows.length,
      ongoingCalls: activeCallsRes.rows,
    });
  } catch (err) {
    console.error('Error fetching dev queues:', err.message);
    res.status(500).json({ error: 'Failed to inspect queues' });
  }
});

// ── GET/POST /api/instant/dev/cleanup ────────────────────────────────────────
// Quick admin reset to clear ghost calls, refund queued males, and reset stale Redis state
router.all('/dev/cleanup', authMiddleware, adminOnly, async (req, res) => {
  try {
    const db = require('../../db');

    // Refund any males currently waiting in queue before wiping
    const maleQueueIds = await redis.zrevrange('instant:male_queue', 0, -1);
    let refundedCount = 0;
    for (const mId of maleQueueIds) {
      const sessionStr = await redis.get(`instant:male_session:${mId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await instantConnectService.refundEscrowedCoins(mId, bidAmount, sessionId);
        refundedCount++;
      }
      await redis.del(`instant:male_session:${mId}`);
    }
    await redis.del('instant:male_queue');

    // Close any stale active sessions
    const updateRes = await db.query(`
      UPDATE public.instant_call_sessions
      SET status = 'dropped', ended_at = NOW()
      WHERE status IN ('queued', 'ringing', 'in_call')
      RETURNING id
    `);

    // Clean up Redis ringing & snooze keys
    const ringingKeys = await redis.keys('instant:ringing:*');
    if (ringingKeys.length > 0) {
      await redis.del(...ringingKeys);
    }
    const snoozeKeys = await redis.keys('instant:snooze:*');
    if (snoozeKeys.length > 0) {
      await redis.del(...snoozeKeys);
    }

    res.json({
      success: true,
      message: 'Cleaned up stale queues, refunded queued males, and reset snooze locks',
      refundedWaitingMalesCount: refundedCount,
      cleanedSessionsCount: updateRes.rowCount,
      cleanedRingingKeysCount: ringingKeys.length,
      cleanedSnoozeKeysCount: snoozeKeys.length,
    });
  } catch (err) {
    console.error('Error in /dev/cleanup:', err.message);
    res.status(500).json({ error: 'Failed to perform cleanup' });
  }
});

module.exports = router;
