const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { buddyService } = require('./buddy.service');
const {
  broadcastNewBuddyRequest,
  broadcastBuddyRequestTaken,
  notifyInitiatorAccepted,
  notifyInitiatorVerified,
} = require('./buddy.socket');
const db = require('../../db');

const router = express.Router();

/**
 * POST /api/buddy/request
 * Create a new broadcast buddy request.
 * Requires active subscription. Deducts 100 coins immediately (spendable first, then earned).
 * Supports idempotencyKey via body or x-idempotency-key header.
 */
router.post('/request', authMiddleware, async (req, res) => {
  try {
    const { buddyType, city, targetGender } = req.body;
    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;

    // Default to user's registered profile city if omitted
    let targetCity = city;
    if (!targetCity) {
      const userRes = await db.query('SELECT city FROM public.users WHERE id = $1', [req.user.id]);
      targetCity = userRes.rows[0]?.city;
    }

    if (!targetCity) {
      return res.status(400).json({ error: 'City is required to post a buddy request' });
    }

    const request = await buddyService.createRequest({
      initiatorId: req.user.id,
      buddyType,
      city: targetCity,
      targetGender: targetGender || 'all',
      idempotencyKey,
    });

    // Broadcast in real-time to city room & queue FCM push to offline users
    const io = req.app.get('io');
    if (io) {
      broadcastNewBuddyRequest(io, request);
    }

    res.status(201).json({
      success: true,
      request,
    });
  } catch (err) {
    console.error('❌ Error in POST /api/buddy/request:', err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_CREATE_REQUEST',
      message: err.message || 'Failed to create buddy request',
    });
  }
});

/**
 * GET /api/buddy/requests & /api/buddy/open
 * List open buddy requests in a city visible to the user.
 * Query: ?city=&buddyType=&limit=&offset=
 */
router.get(['/requests', '/open'], authMiddleware, async (req, res) => {
  try {
    let { city, buddyType, limit, offset } = req.query;

    const userRes = await db.query('SELECT city, gender FROM public.users WHERE id = $1', [req.user.id]);
    const user = userRes.rows[0] || {};

    const targetCity = city || user.city;
    if (!targetCity) {
      return res.json({ success: true, requests: [] });
    }

    const requests = await buddyService.listOpenRequests({
      city: targetCity,
      userGender: user.gender,
      buddyType,
      userId: req.user.id,
      limit,
      offset,
    });

    res.json({
      success: true,
      requests,
    });
  } catch (err) {
    console.error('❌ Error in GET /api/buddy/requests:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_LIST_REQUESTS',
      message: err.message || 'Failed to list buddy requests',
    });
  }
});

/**
 * POST /api/buddy/requests/:id/accept & /api/buddy/accept/:id
 * Atomic accept by first responding user.
 * Immediately unlocks chat (creates conversation) and generates 6-digit OTP.
 */
router.post(['/requests/:id/accept', '/accept/:id'], authMiddleware, async (req, res) => {
  try {
    const requestId = req.params.id;
    const accepterId = req.user.id;

    const request = await buddyService.acceptRequest({
      requestId,
      accepterId,
    });

    const io = req.app.get('io');
    if (io) {
      // 1. Broadcast to city room that request is taken
      broadcastBuddyRequestTaken(io, {
        requestId: request.id,
        buddyType: request.buddy_type,
        city: request.city,
      });

      // 2. Alert initiator with 6-digit OTP convenience push
      notifyInitiatorAccepted(io, {
        initiatorId: request.initiator_id,
        requestId: request.id,
        conversationId: request.conversationId,
        accepter: request.accepter,
        otpCode: request.otpCode,
        buddyType: request.buddy_type,
      });
    }

    // Never return the OTP to the accepter
    const sanitizedRequest = {
      ...request,
      otpCode: undefined,
      otp_code: undefined,
      otp_hash: undefined,
      otp_encrypted: undefined,
    };

    res.json({
      success: true,
      request: sanitizedRequest,
      conversationId: request.conversationId,
      message: 'Request accepted! Chat is now unlocked. Meet in person and share your OTP.',
    });
  } catch (err) {
    console.error(`❌ Error in POST accept buddy request:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_ACCEPT_REQUEST',
      message: err.message || 'Failed to accept buddy request',
    });
  }
});

/**
 * GET /api/buddy/requests/:id/otp
 * Authenticated REST endpoint for the initiator to retrieve their 6-digit meetup OTP.
 * Source of truth if socket connection was dropped.
 */
router.get('/requests/:id/otp', authMiddleware, async (req, res) => {
  try {
    const requestId = req.params.id;
    const userId = req.user.id;

    const result = await buddyService.getInitiatorOtp(requestId, userId);
    res.json({
      success: true,
      otpCode: result.otpCode,
    });
  } catch (err) {
    console.error(`❌ Error in GET /api/buddy/requests/${req.params.id}/otp:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_FETCH_OTP',
      message: err.message || 'Failed to fetch meetup OTP',
    });
  }
});

/**
 * POST /api/buddy/requests/:id/complete & /api/buddy/requests/:id/verify-otp
 * Accepter submits the 6-digit in-person meetup OTP.
 * Rate limited to 5 attempts, then 15-minute lockout in Redis.
 * Atomically transitions to 'completed' and credits 50 coins to accepter's earned_balance.
 */
router.post(['/requests/:id/complete', '/requests/:id/verify-otp', '/verify-otp'], authMiddleware, async (req, res) => {
  try {
    const requestId = req.params.id || req.body.requestId;
    const accepterId = req.user.id;
    const { otpCode } = req.body;
    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;

    const result = await buddyService.completeRequest({
      requestId,
      accepterId,
      otpCode,
      idempotencyKey,
    });

    const io = req.app.get('io');
    if (io && result.success) {
      notifyInitiatorVerified(io, {
        initiatorId: result.request.initiator_id,
        requestId,
        conversationId: result.conversationId,
        accepter: result.accepter,
      });
    }

    res.json({
      success: true,
      conversationId: result.conversationId,
      otherUser: result.initiator,
      partner: result.initiator,
      rewardCoins: result.rewardCoins,
      earnedBalance: result.earnedBalance,
      spendableBalance: result.spendableBalance,
      balance: result.balance,
      message: 'Meetup verified successfully! 50 earned coins credited.',
    });
  } catch (err) {
    console.error(`❌ Error in POST complete buddy request:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_COMPLETE_REQUEST',
      message: err.message || 'Failed to complete buddy request',
      remainingAttempts: err.remainingAttempts,
    });
  }
});

/**
 * GET /api/buddy/requests/my & /api/buddy/my-requests
 * Paginated list of requests initiated or accepted by current user.
 * Query: ?page=1&limit=20&status=all
 */
router.get(['/requests/my', '/my-requests'], authMiddleware, async (req, res) => {
  try {
    const { page, limit, status } = req.query;
    const data = await buddyService.getUserRequests(req.user.id, { page, limit, status });
    res.json({
      success: true,
      ...data,
    });
  } catch (err) {
    console.error('❌ Error in GET /api/buddy/requests/my:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_FETCH_MY_REQUESTS',
      message: err.message || 'Failed to fetch user requests',
    });
  }
});

module.exports = router;
