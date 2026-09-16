const db = require('../../db');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const { BUDDY_TYPES, BUDDY_LIMITS } = require('./buddy.config');

/**
 * Socket.IO module for real-time Buddy Activity Requests.
 * Designed for 5,000 CCU scalability:
 * - O(1) room broadcasting (buddy:city:{city}:{gender}) instead of iterating over individual sockets.
 * - Batched FCM multicast (500 tokens/batch) for offline users.
 */

function registerBuddyHandlers(io, socket, redis) {
  // Client explicitly joins city + gender rooms
  socket.on('join_buddy_city', async ({ city, gender }) => {
    if (city && typeof city === 'string') {
      const normalizedCity = city.trim().toLowerCase();
      const userGender = (gender || socket.userGender || 'all').trim().toLowerCase();
      
      const specificRoom = `buddy:city:${normalizedCity}:${userGender}`;
      const allRoom = `buddy:city:${normalizedCity}:all`;
      const legacyRoom = `city:${normalizedCity}:buddy`;

      socket.join(specificRoom);
      socket.join(allRoom);
      socket.join(legacyRoom);
      console.log(` Socket ${socket.id} (user ${socket.userId}) joined buddy rooms: ${specificRoom}, ${allRoom}`);
    }
  });

  socket.on('leave_buddy_city', ({ city, gender }) => {
    if (city && typeof city === 'string') {
      const normalizedCity = city.trim().toLowerCase();
      const userGender = (gender || socket.userGender || 'all').trim().toLowerCase();
      
      socket.leave(`buddy:city:${normalizedCity}:${userGender}`);
      socket.leave(`buddy:city:${normalizedCity}:all`);
      socket.leave(`city:${normalizedCity}:buddy`);
      console.log(` Socket ${socket.id} left buddy rooms for city: ${normalizedCity}`);
    }
  });
}

/**
 * Broadcast a newly created buddy request to matching online rooms and offline push tokens.
 * 
 * @param {Object} io - Socket.io Server instance
 * @param {Object} request - Created buddy request object with initiator details
 */
async function broadcastNewBuddyRequest(io, request) {
  if (!io || !request || !request.city) return;

  const normalizedCity = request.city.trim().toLowerCase();
  const targetGender = (request.target_gender || 'all').trim().toLowerCase();

  // 1. O(1) Real-time Socket.io Room Broadcast
  const targetRoom = `buddy:city:${normalizedCity}:${targetGender}`;
  const allRoom = `buddy:city:${normalizedCity}:all`;
  const legacyRoom = `city:${normalizedCity}:buddy`;

  io.to(targetRoom).emit('new_buddy_request', request);
  if (targetGender !== 'all') {
    io.to(allRoom).emit('new_buddy_request', request);
  }
  io.to(legacyRoom).emit('new_buddy_request', request);

  console.log(`📢 [Buddy Socket] Broadcasted new_${request.buddy_type} to room '${targetRoom}' and '${legacyRoom}'`);

  // 2. Batched FCM Multicast to Offline Users in Background
  setImmediate(async () => {
    try {
      const buddyInfo = BUDDY_TYPES[request.buddy_type] || { title: 'Buddy Activity' };

      const fcmQuery = `
        SELECT u.id, u.fcm_token
        FROM public.users u
        WHERE LOWER(TRIM(u.city)) = $1
          AND ($2 = 'all' OR LOWER(TRIM(u.gender)) = $2)
          AND u.id != $3
          AND (u.is_banned IS FALSE OR u.is_banned IS NULL)
          AND u.fcm_token IS NOT NULL
        LIMIT $4;
      `;

      const fcmRes = await db.query(fcmQuery, [
        normalizedCity,
        targetGender,
        request.initiator_id,
        BUDDY_LIMITS.MAX_FCM_RECIPIENTS,
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
 * Broadcasts that a request was accepted so other users' feeds update to 'taken'.
 */
function broadcastBuddyRequestTaken(io, { requestId, buddyType, city }) {
  if (!io || !city) return;
  const normalizedCity = city.trim().toLowerCase();
  io.to(`buddy:city:${normalizedCity}:all`).emit('buddy_request_taken', { requestId, buddyType });
  io.to(`buddy:city:${normalizedCity}:male`).emit('buddy_request_taken', { requestId, buddyType });
  io.to(`buddy:city:${normalizedCity}:female`).emit('buddy_request_taken', { requestId, buddyType });
  io.to(`city:${normalizedCity}:buddy`).emit('buddy_request_taken', { requestId, buddyType });
  console.log(`📢 [Buddy Socket] Broadcasted buddy_request_taken (${requestId}) to city rooms '${normalizedCity}'`);
}

/**
 * Directly alerts the initiator that someone has accepted their request, chat is open, and provides OTP.
 */
function notifyInitiatorAccepted(io, { initiatorId, requestId, conversationId, accepter, otpCode, buddyType }) {
  if (!io || !initiatorId) return;
  io.to(initiatorId).emit('buddy_request_accepted', {
    requestId,
    conversationId,
    accepter,
    otpCode,
    buddyType,
  });
  console.log(`🔔 [Buddy Socket] Notified initiator ${initiatorId} that request ${requestId} was accepted`);
}

/**
 * Directly alerts the initiator that OTP handshake was verified and reward was credited.
 */
function notifyInitiatorVerified(io, { initiatorId, requestId, conversationId, accepter }) {
  if (!io || !initiatorId) return;
  io.to(initiatorId).emit('buddy_request_verified', {
    requestId,
    conversationId,
    accepter,
  });
  console.log(` [Buddy Socket] Notified initiator ${initiatorId} that request ${requestId} is completed!`);
}

module.exports = {
  registerBuddyHandlers,
  broadcastNewBuddyRequest,
  broadcastBuddyRequestTaken,
  notifyInitiatorAccepted,
  notifyInitiatorVerified,
};
