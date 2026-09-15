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
 * Requires active subscription. Deducts 100 coins immediately.
 */
router.post('/request', authMiddleware, async (req, res) => {
  try {
    const { buddyType, city, targetGender } = req.body;

    // If city is omitted in body, default to user's registered profile city
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
    console.error('Error in POST /api/buddy/request:', err.message);
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

    // Default to user's city and gender if not provided
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
    console.error('Error in GET /api/buddy/requests:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_LIST_REQUESTS',
      message: err.message || 'Failed to list buddy requests',
    });
  }
});

/**
 * POST /api/buddy/requests/:id/accept & /api/buddy/accept/:id
 * Atomic accept by first responding user.
 * Returns OTP challenge state or ALREADY_ACCEPTED 409 conflict.
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

      // 2. Alert initiator with 6-digit OTP
      notifyInitiatorAccepted(io, {
        initiatorId: request.initiator_id,
        requestId: request.id,
        accepter: request.accepter,
        otpCode: request.otp_code,
      });
    }

    // Do NOT return the plain OTP to the accepter (initiator holds the secret)
    const sanitizedRequest = {
      ...request,
      otp_code: undefined,
    };

    res.json({
      success: true,
      request: sanitizedRequest,
      message: 'Request accepted! Ask the initiator for their 6-digit verification OTP.',
    });
  } catch (err) {
    console.error(`Error in POST accept buddy request:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_ACCEPT_REQUEST',
      message: err.message || 'Failed to accept buddy request',
    });
  }
});

/**
 * POST /api/buddy/requests/:id/verify-otp & /api/buddy/verify-otp
 * Accepter submits the 6-digit handshake OTP.
 * On success, credits 50 coins to accepter and unlocks conversation.
 */
router.post(['/requests/:id/verify-otp', '/verify-otp'], authMiddleware, async (req, res) => {
  try {
    const requestId = req.params.id || req.body.requestId;
    const accepterId = req.user.id;
    const { otpCode } = req.body;

    const result = await buddyService.verifyOtp({
      requestId,
      accepterId,
      otpCode,
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
      rewardCoins: result.rewardCoins,
      newBalance: result.newBalance,
      message: 'OTP verified! Chat unlocked and 50 coins rewarded.',
    });
  } catch (err) {
    console.error(`Error in POST /api/buddy/requests/${req.params.id}/verify-otp:`, err.message);
    const status = err.statusCode || 500;
    res.status(status).json({
      error: err.code || 'FAILED_TO_VERIFY_OTP',
      message: err.message || 'Failed to verify OTP',
      remainingAttempts: err.remainingAttempts,
    });
  }
});

/**
 * GET /api/buddy/requests/my
 * Returns active and recent requests initiated or accepted by current user.
 */
router.get('/requests/my', authMiddleware, async (req, res) => {
  try {
    const requests = await buddyService.getUserRequests(req.user.id);
    res.json({
      success: true,
      requests,
    });
  } catch (err) {
    console.error('Error in GET /api/buddy/requests/my:', err.message);
    res.status(500).json({
      error: 'FAILED_TO_FETCH_MY_REQUESTS',
      message: err.message || 'Failed to fetch user requests',
    });
  }
});

module.exports = router;
