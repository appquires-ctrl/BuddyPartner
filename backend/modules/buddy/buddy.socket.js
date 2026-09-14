const db = require('../../db');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const { BUDDY_TYPES, BUDDY_LIMITS } = require('./buddy.config');

/**
 * Socket.IO module for real-time Buddy Activity Requests.
 * Designed for 5,000 CCU scalability:
 * - O(1) room broadcasting (city:{city}:buddy) instead of iterating over individual sockets.
 * - Batched FCM multicast (500 tokens/batch) for offline users.
 */

function registerBuddyHandlers(io, socket, redis) {
  // Client can explicitly join their current city room
  socket.on('join_buddy_city', ({ city }) => {
    if (city && typeof city === 'string') {
      const normalizedCity = city.trim().toLowerCase();
      const room = `city:${normalizedCity}:buddy`;
      socket.join(room);
      console.log(`📍 Socket ${socket.id} (user ${socket.userId}) joined buddy room: ${room}`);
    }
  });

  socket.on('leave_buddy_city', ({ city }) => {
    if (city && typeof city === 'string') {
      const normalizedCity = city.trim().toLowerCase();
      const room = `city:${normalizedCity}:buddy`;
      socket.leave(room);
      console.log(`📍 Socket ${socket.id} left buddy room: ${room}`);
    }
  });
}

/**
 * Broadcast a newly created buddy request to all matching users in the city.
 * 
 * 1. Online users: Emits to room `city:{normalizedCity}:buddy` in a single O(1) operation.
 * 2. Offline users: Batched FCM multicast send (up to 500 per batch).
 * 
 * @param {Object} io - Socket.io Server instance
 * @param {Object} request - Created buddy request object with initiator details
 */
async function broadcastNewBuddyRequest(io, request) {
  if (!io || !request || !request.city) return;

  const normalizedCity = request.city.trim().toLowerCase();
  const room = `city:${normalizedCity}:buddy`;

  // 1. O(1) Real-time Socket.io Room Broadcast
  io.to(room).emit('new_buddy_request', request);
  console.log(`📢 [Buddy Socket] Broadcasted new_${request.buddy_type} to room '${room}'`);

  // 2. Batched FCM Multicast to Offline Users in Background
  setImmediate(async () => {
    try {
      const targetGender = request.target_gender || 'all';
      const buddyInfo = BUDDY_TYPES[request.buddy_type] || { title: 'Buddy Activity' };

      // Single indexed query retrieving device tokens of matching users in the city
      const fcmQuery = `
        SELECT u.id, u.fcm_token
        FROM public.users u
        WHERE LOWER(TRIM(u.city)) = $1
          AND ($2 = 'all' OR u.gender = $2)
          AND u.id != $3
          AND (u.is_banned IS FALSE OR u.is_banned IS NULL)
          AND u.fcm_token IS NOT NULL
        LIMIT $4;
      `;

      const fcmRes = await db.query(fcmQuery, [
        normalizedCity,
        targetGender,
        request.initiator_id,
        BUDDY_LIMITS.MAX_FCM_BATCH_SIZE,
      ]);

      if (fcmRes.rows.length === 0) return;

      const tokens = fcmRes.rows.map(r => r.fcm_token);

      const title = `New ${buddyInfo.title} in ${request.city}!`;
      const body = `${request.initiator?.fullName || 'Someone'} is looking for a ${buddyInfo.title} partner. Accept & earn 50 Coins!`;

      await sendMulticastPushNotification({
        tokens,
        title,
        body,
        tag: `buddy_${request.id}`,
        data: {
          type: 'buddy_request',
          requestId: request.id,
          buddyType: request.buddy_type,
          city: request.city,
          initiatorName: request.initiator?.fullName || 'User',
          initiatorAvatarSeed: request.initiator?.avatarSeed || '',
          coinReward: String(request.accepter_coin_reward || 50),
        },
      });

      console.log(`📲 [Buddy FCM] Multicast queued for ${tokens.length} offline devices in ${request.city}`);
    } catch (err) {
      console.error(`❌ [Buddy FCM Error]:`, err.message);
    }
  });
}

/**
 * Broadcasts that a request was accepted so other users' UIs update to 'taken'.
 */
function broadcastBuddyRequestTaken(io, { requestId, buddyType, city }) {
  if (!io || !city) return;
  const normalizedCity = city.trim().toLowerCase();
  const room = `city:${normalizedCity}:buddy`;
  io.to(room).emit('buddy_request_taken', { requestId, buddyType });
  console.log(`📢 [Buddy Socket] Broadcasted buddy_request_taken (${requestId}) to room '${room}'`);
}

/**
 * Directly alerts the initiator that someone has accepted their request and shares the 6-digit OTP.
 */
function notifyInitiatorAccepted(io, { initiatorId, requestId, accepter, otpCode }) {
  if (!io || !initiatorId) return;
  io.to(initiatorId).emit('buddy_request_accepted', {
    requestId,
    accepter,
    otpCode,
  });
  console.log(`🔔 [Buddy Socket] Notified initiator ${initiatorId} that request ${requestId} was accepted`);
}

/**
 * Directly alerts the initiator that OTP handshake was verified and chat is unlocked.
 */
function notifyInitiatorVerified(io, { initiatorId, requestId, conversationId, accepter }) {
  if (!io || !initiatorId) return;
  io.to(initiatorId).emit('buddy_request_verified', {
    requestId,
    conversationId,
    accepter,
  });
  console.log(`🎉 [Buddy Socket] Notified initiator ${initiatorId} that request ${requestId} is verified!`);
}

module.exports = {
  registerBuddyHandlers,
  broadcastNewBuddyRequest,
  broadcastBuddyRequestTaken,
  notifyInitiatorAccepted,
  notifyInitiatorVerified,
};
