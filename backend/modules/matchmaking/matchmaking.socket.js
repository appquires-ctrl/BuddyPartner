const { MatchmakingService } = require('./matchmaking.service');
const { callsService } = require('../calls/calls.service');
const { WalletService, CALL_RATES } = require('../wallet/wallet.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { activeInstantCalls, endInstantCallHelper } = require('../instant_connect/instant_connect.socket');
const { sendPushNotification } = require('../../services/firebase.service');
const db = require('../../db');

// In-memory map of active calls: callId → { userA: { userId, socketId, gender }, userB: { userId, socketId, gender } }
const activeCalls = new Map();
// Reverse map: socketId → callId (for fast lookup on disconnect)
const socketToCall = new Map();
// Map: userId → socketId (for disconnect cleanup)
const userSockets = new Map();
// Map: callRequestId -> { callerId, callerSocketId, callerGender, targetUserId, targetSocketId, targetGender, timer }
const pendingCallRequests = new Map();

/**
 * Look up a user's gender from the database.
 * @param {string} userId
 * @returns {Promise<string>} gender string ('male', 'female', or 'unknown')
 */
async function getUserGender(userId) {
  try {
    const result = await db.query(
      'SELECT gender FROM public.users WHERE id = $1',
      [userId]
    );
    if (result.rows.length === 0) return 'unknown';
    const rawGender = (result.rows[0].gender || '').trim().toLowerCase();
    if (rawGender === 'female' || rawGender === 'girl' || rawGender === 'woman' || rawGender === 'f') {
      return 'female';
    }
    if (rawGender === 'male' || rawGender === 'boy' || rawGender === 'man' || rawGender === 'm') {
      return 'male';
    }
    return 'unknown';
  } catch (err) {
    console.error(`Error fetching gender for user ${userId}:`, err.message);
    return 'unknown';
  }
}

/**
 * Check if a gender string represents female.
 * @param {string} gender
 * @returns {boolean}
 */
function isFemale(gender) {
  const g = (gender || '').trim().toLowerCase();
  return g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
}

/**
 * Check if a gender string represents male.
 * @param {string} gender
 * @returns {boolean}
 */
function isMale(gender) {
  const g = (gender || '').trim().toLowerCase();
  return g === 'male' || g === 'boy' || g === 'man' || g === 'm';
}

/**
 * Helper to safely resolve connected socket for a user ID across map and io.sockets
 */
function getSocketForUser(io, targetUserId) {
  if (!io || !targetUserId) return null;
  const socketId = userSockets.get(targetUserId);
  if (socketId) {
    const s = io.sockets?.sockets?.get(socketId);
    if (s && s.connected && s.userId === targetUserId) return s;
  }
  // Search live connected sockets in Socket.io
  if (io.sockets?.sockets) {
    for (const [, s] of io.sockets.sockets) {
      if (s.userId === targetUserId && s.connected) {
        userSockets.set(targetUserId, s.id); // Re-sync mapping
        return s;
      }
    }
  }
  return null;
}

/**
 * Register all matchmaking-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerMatchmakingHandlers(io, socket, redis) {

  const matchmakingService = new MatchmakingService(redis);
  const userId = socket.userId;

  // Track this user's socket and purge any stale queue entries from previous sessions
  userSockets.set(userId, socket.id);
  matchmakingService.leaveQueue(userId).catch(() => {});

  // Check if there is a pending direct call request waiting for this user (e.g. user tapped FCM call notification)
  for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
    if (reqVal.targetUserId === userId) {
      reqVal.targetSocketId = socket.id;
      fetchPublicProfile(reqVal.callerId).then((callerProfile) => {
        socket.emit('incoming_call_request', {
          callRequestId,
          caller: callerProfile,
        });
        console.log(`🔔 [FCM Connect] Delivered pending direct call ${callRequestId} from ${reqVal.callerId} to newly connected user ${userId}`);
      }).catch((err) => console.error('Error delivering pending direct call to connected user:', err.message));
    }
  }

  // ── join_queue ────────────────────────────────────────────────────────
  socket.on('join_queue', async (callback) => {
    try {
      // Check if user is already in an active call
      if (socketToCall.has(socket.id)) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in an active call' });
        return;
      }

      // Look up user's gender directly from DB
      const gender = await getUserGender(userId);
      if (gender === 'unknown') {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Please set your gender in your profile before matchmaking.' });
        socket.emit('match_error', { error: 'Please set your gender in your profile before matchmaking.' });
        return;
      }

      const userIsFemale = isFemale(gender);

      // Subscription check: unisex requirement for all users
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to join the matchmaking queue.' });
        socket.emit('match_error', { error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to join the matchmaking queue.' });
        return;
      }

      const added = await matchmakingService.joinQueue(userId, socket.id, gender);
      if (!added) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in queue' });
        return;
      }

      console.log(`📥 User ${userId} (${gender}) joined queue`);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ success: true });

      // Try to find a match
      await attemptMatch(io, redis, matchmakingService, callsService);
    } catch (err) {
      console.error('Error in join_queue:', err);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ error: 'Internal error' });
    }
  });

  // ── leave_queue ───────────────────────────────────────────────────────
  socket.on('leave_queue', async (callback) => {
    try {
      await matchmakingService.leaveQueue(userId);
      console.log(`📤 User ${userId} left queue`);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ success: true });
    } catch (err) {
      console.error('Error in leave_queue:', err);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ error: 'Internal error' });
    }
  });

  // ── end_call ──────────────────────────────────────────────────────────
  socket.on('end_call', async ({ callId }) => {
    try {
      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        // Security Check: Authorize sender participant
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to end call by ${userId}`);
          return;
        }
        await handleCallEnd(callId, callsService, io, 'manual', matchmakingService);
        return;
      }

      // Check if it's an Instant Connect call
      const instantEndRes = await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'manual',
      });
      if (instantEndRes) {
        console.log(`⚡ Instant call ${callId} manually ended by user ${userId}`);
      }
    } catch (err) {
      console.error('Error in end_call:', err);
    }
  });

  // ── upgrade_to_video ──────────────────────────────────────────────────
  socket.on('upgrade_to_video', async ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to upgrade call to video by ${userId}`);
          return;
        }
        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to upgrade instant call to video by ${userId}`);
            return;
          }
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) {
        console.warn(`⚠️ No active call session found for video upgrade request (callId: ${callId})`);
        return;
      }

      const requesterProfile = await fetchPublicProfile(userId);

      io.to(otherSocketId).emit('video_upgrade_request', {
        callId,
        requesterId: userId,
        requesterName: requesterProfile.fullName || 'User',
      });
      console.log(`📹 User ${userId} (${requesterProfile.fullName}) requested video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in upgrade_to_video:', err);
    }
  });

  // ── video_upgrade_accepted ────────────────────────────────────────────
  socket.on('video_upgrade_accepted', async ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to accept video upgrade by ${userId}`);
          return;
        }
        await callsService.upgradeToVideo(callId);
        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to accept instant video upgrade by ${userId}`);
            return;
          }
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) return;

      io.to(otherSocketId).emit('video_upgrade_accepted', { callId });
      console.log(`✅ User ${userId} accepted video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in video_upgrade_accepted:', err);
    }
  });

  // ── video_upgrade_declined ────────────────────────────────────────────
  socket.on('video_upgrade_declined', ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to decline video upgrade by ${userId}`);
          return;
        }
        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to decline instant video upgrade by ${userId}`);
            return;
          }
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) return;

      io.to(otherSocketId).emit('video_upgrade_declined', { callId });
      console.log(`❌ User ${userId} declined video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in video_upgrade_declined:', err);
    }
  });

  // ── accept_call_request ────────────────────────────────────────────────
  socket.on('accept_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) {
        socket.emit('match_error', { error: 'Call request expired or does not exist.' });
        return;
      }

      if (request.targetUserId !== userId) {
        socket.emit('match_error', { error: 'Unauthorized call acceptance.' });
        return;
      }

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      // Purge both from queues
      await matchmakingService.leaveQueue(request.callerId);
      await matchmakingService.leaveQueue(request.targetUserId);

      const channelName = matchmakingService.generateChannelName();
      const uidA = matchmakingService.uuidToAgoraUid(request.callerId);
      const uidB = matchmakingService.uuidToAgoraUid(request.targetUserId);
      const tokenA = callsService.generateAgoraToken(channelName, uidA);
      const tokenB = callsService.generateAgoraToken(channelName, uidB);

      const callId = await callsService.createCall(request.callerId, request.targetUserId);

      const [profileA, profileB] = await Promise.all([
        fetchPublicProfile(request.callerId),
        fetchPublicProfile(request.targetUserId),
      ]);

      activeCalls.set(callId, {
        userA: { userId: request.callerId, socketId: request.callerSocketId, agoraUid: uidA, gender: request.callerGender },
        userB: { userId: request.targetUserId, socketId: socket.id, agoraUid: uidB, gender: request.targetGender },
        channelName,
      });
      socketToCall.set(request.callerSocketId, callId);
      socketToCall.set(socket.id, callId);

      await redis.set(`call_lock:${request.callerId}`, '1', 'EX', 7200);
      await redis.set(`call_lock:${request.targetUserId}`, '1', 'EX', 7200);


      io.to(request.callerSocketId).emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenA,
        agoraUid: uidA,
        matchedUser: profileB,
      });

      socket.emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenB,
        agoraUid: uidB,
        matchedUser: profileA,
      });

      callsService.startCallTimer(callId, (expiredCallId) => {
        handleCallEnd(expiredCallId, callsService, io, 'timer', matchmakingService);
      });

      callsService.startCallBilling(
        callId,
        request.callerId,
        request.targetUserId,
        request.callerGender,
        request.targetGender,
        io,
        (billingCallId) => {
          handleCallEnd(billingCallId, callsService, io, 'insufficient_balance', matchmakingService);
        }
      );

      console.log(`✅ Direct call ${callId} established: ${request.callerId} (${request.callerGender}) ↔ ${request.targetUserId} (${request.targetGender})`);
    } catch (err) {
      console.error('Error in accept_call_request:', err);
      socket.emit('match_error', { error: 'Failed to establish call connection.' });
    }
  });

  // ── decline_call_request ────────────────────────────────────────────────
  socket.on('decline_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) return;

      if (request.targetUserId !== userId) return;

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      io.to(request.callerSocketId).emit('call_response', {
        callRequestId,
        status: 'declined',
      });
      
      console.log(`❌ Call request ${callRequestId} declined by target user ${userId}`);
    } catch (err) {
      console.error('Error in decline_call_request:', err);
    }
  });

  // ── cancel_call_request ─────────────────────────────────────────────────
  socket.on('cancel_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) return;

      if (request.callerId !== userId) return;

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      io.to(request.targetSocketId).emit('call_response', {
        callRequestId,
        status: 'cancelled',
      });

      console.log(`🛑 Call request ${callRequestId} cancelled by caller ${userId}`);
    } catch (err) {
      console.error('Error in cancel_call_request:', err);
    }
  });

  // ── direct_call ────────────────────────────────────────────────────────
  socket.on('direct_call', async ({ targetUserId }) => {
    // Subscription check: unisex requirement for all users
    const isSub = await subscriptionsService.isSubscribed(userId);
    if (!isSub) {
      socket.emit('match_error', { error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to start a call.' });
      return;
    }

    if (targetUserId === userId) {
      socket.emit('match_error', { error: 'Cannot call yourself' });
      return;
    }

    if (socketToCall.has(socket.id)) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    const callerInInstant = await redis.get(`instant:in_call:${userId}`);
    if (callerInInstant) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    const targetSocket = getSocketForUser(io, targetUserId);
    const targetSocketId = targetSocket?.id || null;

    let isBusy = targetSocketId ? socketToCall.has(targetSocketId) : false;
    if (!isBusy) {
      const inInstant = await redis.get(`instant:in_call:${targetUserId}`);
      if (inInstant) isBusy = true;
    }
    if (!isBusy && activeInstantCalls) {
      for (const call of activeInstantCalls.values()) {
        if (call.femaleUserId === targetUserId || call.maleUserId === targetUserId) {
          isBusy = true;
          break;
        }
      }
    }

    if (!isBusy) {
      for (const reqVal of pendingCallRequests.values()) {
        if (reqVal.callerId === targetUserId || reqVal.targetUserId === targetUserId) {
          isBusy = true;
          break;
        }
      }
    }
    if (isBusy) {
      socket.emit('call_response', { status: 'busy' });
      return;
    }

    const lockKeyA = `direct_mutex:${userId}`;
    const lockKeyB = `direct_mutex:${targetUserId}`;
    const lockedA = await redis.set(lockKeyA, '1', 'NX', 'EX', 5);
    const lockedB = await redis.set(lockKeyB, '1', 'NX', 'EX', 5);
    if (!lockedA || !lockedB) {
      if (lockedA) await redis.del(lockKeyA);
      if (lockedB) await redis.del(lockKeyB);
      socket.emit('call_response', { status: 'busy' });
      return;
    }

    try {
      await matchmakingService.leaveQueue(userId);
      await matchmakingService.leaveQueue(targetUserId);

      const callRequestId = matchmakingService.generateChannelName();
      const callerProfile = await fetchPublicProfile(userId);
      const callerGender = callerProfile.gender || (await getUserGender(userId));
      const targetGender = await getUserGender(targetUserId);

      // Check if target is offline and has FCM token
      const isTargetOnline = targetSocket && targetSocket.connected;
      if (!isTargetOnline) {
        const targetUserRow = await db.query(
          `SELECT fcm_token, full_name FROM public.users WHERE id = $1`,
          [targetUserId]
        );
        const targetFcm = targetUserRow.rows[0]?.fcm_token;
        if (!targetFcm) {
          socket.emit('call_response', { status: 'offline' });
          return;
        }

        console.log(`📡 [FCM Direct Call] Target is offline. Dispatching call push to ${targetUserId}`);
        sendPushNotification({
          token: targetFcm,
          title: `📞 Incoming Call from ${callerProfile.fullName}`,
          body: `Tap to open the app and answer the call.`,
          tag: `direct_call_${callRequestId}`,
          data: {
            type: 'incoming_call',
            callRequestId,
            callerId: String(userId),
            callerName: String(callerProfile.fullName),
          },
        }).catch((err) => console.error('FCM Direct Call error:', err.message));
      }

      const timer = setTimeout(() => {
        if (pendingCallRequests.has(callRequestId)) {
          console.log(`⏰ Call request ${callRequestId} timed out (no answer)`);
          io.to(socket.id).emit('call_response', { callRequestId, status: 'no_answer' });
          if (targetSocketId) {
            io.to(targetSocketId).emit('call_response', { callRequestId, status: 'no_answer' });
          }
          pendingCallRequests.delete(callRequestId);
        }
      }, 30000);

      pendingCallRequests.set(callRequestId, {
        callerId: userId,
        callerSocketId: socket.id,
        callerGender,
        targetUserId,
        targetSocketId,
        targetGender,
        timer,
      });

      if (isTargetOnline && targetSocketId) {
        io.to(targetSocketId).emit('incoming_call_request', {
          callRequestId,
          caller: callerProfile,
        });
      }

      socket.emit('outgoing_call_ringing', {
        callRequestId,
        targetUser: { id: targetUserId },
      });

      console.log(`🔔 Call request initiated: ${userId} (${callerGender}) → ${targetUserId} (${targetGender}) (req: ${callRequestId}, targetOnline: ${isTargetOnline})`);
    } catch (err) {
      console.error('Error in direct_call:', err);
      socket.emit('match_error', { error: 'Failed to initiate call request' });
    } finally {
      await redis.del(lockKeyA);
      await redis.del(lockKeyB);
    }
  });

  // ── disconnect ────────────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    try {
      await matchmakingService.leaveQueue(userId);

      for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
        if (reqVal.callerId === userId) {
          io.to(reqVal.targetSocketId).emit('call_response', { callRequestId, status: 'cancelled' });
          clearTimeout(reqVal.timer);
          pendingCallRequests.delete(callRequestId);
        } else if (reqVal.targetUserId === userId) {
          io.to(reqVal.callerSocketId).emit('call_response', { callRequestId, status: 'offline' });
          clearTimeout(reqVal.timer);
          pendingCallRequests.delete(callRequestId);
        }
      }

      const callId = socketToCall.get(socket.id);
      if (callId) {
        console.log(`⚠️ User ${userId} disconnected during call ${callId}`);
        await handleCallEnd(callId, callsService, io, 'disconnect', matchmakingService);
      }

      userSockets.delete(userId);
    } catch (err) {
      console.error('Error in disconnect handler:', err);
    }
  });
}

/**
 * Attempt to match one male with one female from their respective queues.
 * Called after every joinQueue to check if a cross-gender pair is available.
 */
async function attemptMatch(io, redis, matchmakingService, callsService) {
  const match = await matchmakingService.tryMatch();
  if (!match) return;

  const { userA, userB } = match; // userA = male from queue, userB = female from queue

  // 1. Immediately purge both users from Redis queues so they cannot be matched again
  await matchmakingService.leaveQueue(userA.userId);
  await matchmakingService.leaveQueue(userB.userId);

  // 2. FRESH DATABASE GENDER DOUBLE-CHECK BEFORE CREATING CALL
  const [genderA, genderB] = await Promise.all([
    getUserGender(userA.userId),
    getUserGender(userB.userId),
  ]);

  // 🛑 HARD ENFORCEMENT 1: Block self-matches
  if (userA.userId === userB.userId) {
    console.error(`🚨 SELF-MATCH ATTEMPT BLOCKED for user ${userA.userId}. Aborting call setup!`);
    return;
  }

  // 🛑 HARD ENFORCEMENT 2: Must be exactly 1 Male and 1 Female from DB
  const isFemaleA = isFemale(genderA);
  const isMaleA = isMale(genderA);
  const isFemaleB = isFemale(genderB);
  const isMaleB = isMale(genderB);

  const isValidCrossGender = (isMaleA && isFemaleB) || (isFemaleA && isMaleB);
  if (!isValidCrossGender) {
    console.error(`🚨 INVALID CROSS-GENDER MATCH DETECTED & BLOCKED: ${userA.userId} (${genderA}) ↔ ${userB.userId} (${genderB}). Aborting call setup!`);
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;
    if (socketAId) io.to(socketAId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    if (socketBId && socketBId !== socketAId) io.to(socketBId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    return;
  }

  try {
    // Determine active sockets
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;

    // Generate Agora channel and tokens
    const channelName = matchmakingService.generateChannelName();
    const uidA = matchmakingService.uuidToAgoraUid(userA.userId);
    const uidB = matchmakingService.uuidToAgoraUid(userB.userId);
    const tokenA = callsService.generateAgoraToken(channelName, uidA);
    const tokenB = callsService.generateAgoraToken(channelName, uidB);

    // Create fresh call record in DB
    const callId = await callsService.createCall(userA.userId, userB.userId);

    // Fetch fresh profile info directly from Postgres for both participants
    const [profileA, profileB] = await Promise.all([
      fetchPublicProfile(userA.userId),
      fetchPublicProfile(userB.userId),
    ]);

    // Track active call with gender info
    activeCalls.set(callId, {
      userA: { userId: userA.userId, socketId: socketAId, agoraUid: uidA, gender: genderA },
      userB: { userId: userB.userId, socketId: socketBId, agoraUid: uidB, gender: genderB },
      channelName,
    });
    socketToCall.set(socketAId, callId);
    socketToCall.set(socketBId, callId);

    await redis.set(`call_lock:${userA.userId}`, '1', 'EX', 7200);
    await redis.set(`call_lock:${userB.userId}`, '1', 'EX', 7200);


    // Emit match_found to both users
    io.to(socketAId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenA,
      agoraUid: uidA,
      matchedUser: profileB,
    });

    io.to(socketBId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenB,
      agoraUid: uidB,
      matchedUser: profileA,
    });

    // Start server-authoritative 5-minute timer
    callsService.startCallTimer(callId, (expiredCallId) => {
      handleCallEnd(expiredCallId, callsService, io, 'timer', matchmakingService);
    });

    // Start gender-aware billing
    callsService.startCallBilling(
      callId,
      userA.userId,
      userB.userId,
      genderA,
      genderB,
      io,
      (billingCallId) => {
        handleCallEnd(billingCallId, callsService, io, 'insufficient_balance', matchmakingService);
      }
    );

    console.log(`📞 Call ${callId} started: ${userA.userId} (${genderA}) ↔ ${userB.userId} (${genderB})`);
  } catch (err) {
    console.error('Error setting up match:', err);
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;
    io.to(socketAId).emit('match_error', { error: 'Failed to set up call' });
    io.to(socketBId).emit('match_error', { error: 'Failed to set up call' });
  }
}

/**
 * Handle call end (manual, timer, or disconnect).
 * Cleans up state and notifies both parties.
 * Gender-aware: sends balance_update to boy, rose_update to girl.
 */
async function handleCallEnd(callId, callsService, io, reason, matchmakingService) {
  const callInfo = activeCalls.get(callId);
  if (!callInfo) return; // Already cleaned up

  // Remove from tracking maps
  activeCalls.delete(callId);
  socketToCall.delete(callInfo.userA.socketId);
  socketToCall.delete(callInfo.userB.socketId);
  const currentSocketA = userSockets.get(callInfo.userA.userId);
  const currentSocketB = userSockets.get(callInfo.userB.userId);
  if (currentSocketA) socketToCall.delete(currentSocketA);
  if (currentSocketB) socketToCall.delete(currentSocketB);

  // ALWAYS PURGE BOTH USERS FROM ALL MATCHMAKING QUEUES AND LOCKS ON CALL END
  if (matchmakingService) {
    await Promise.all([
      matchmakingService.leaveQueue(callInfo.userA.userId),
      matchmakingService.leaveQueue(callInfo.userB.userId),
    ]);
  }

  await redis.del(`call_lock:${callInfo.userA.userId}`);
  await redis.del(`call_lock:${callInfo.userB.userId}`);


  // End call in DB
  await callsService.endCall(callId);

  // Determine boy/girl based on gender
  const isAFemale = isFemale(callInfo.userA.gender);
  const boyInfo = isAFemale ? callInfo.userB : callInfo.userA;
  const girlInfo = isAFemale ? callInfo.userA : callInfo.userB;

  // Query actual total cost for the boy from wallet_transactions
  let totalCostBoy = 0;
  try {
    const resBoy = await db.query(
      `SELECT COALESCE(SUM(amount), 0) AS total FROM public.wallet_transactions
       WHERE user_id = $1 AND reference_id = $2 AND type = 'debit'`,
      [boyInfo.userId, callId]
    );
    totalCostBoy = parseInt(resBoy.rows[0]?.total, 10) || 0;
  } catch (err) {
    console.error(`Error fetching boy's call costs for ${callId}:`, err.message);
  }

  // Query total roses earned by the girl from rose_transactions
  let totalRosesGirl = 0;
  try {
    const resGirl = await db.query(
      `SELECT COALESCE(SUM(amount), 0) AS total FROM public.rose_transactions
       WHERE user_id = $1 AND reference_id = $2 AND type = 'credit'`,
      [girlInfo.userId, callId]
    );
    totalRosesGirl = parseInt(resGirl.rows[0]?.total, 10) || 0;
  } catch (err) {
    console.error(`Error fetching girl's rose earnings for ${callId}:`, err.message);
  }

  // Notify both users using their latest connected socket ID
  const socketBoyId = userSockets.get(boyInfo.userId) || boyInfo.socketId;
  const socketGirlId = userSockets.get(girlInfo.userId) || girlInfo.socketId;

  // Boy gets totalCost (coins spent)
  io.to(socketBoyId).emit('call_ended', { callId, reason, totalCost: totalCostBoy });
  // Girl gets totalCoinsEarned
  if (socketGirlId !== socketBoyId) {
    io.to(socketGirlId).emit('call_ended', { callId, reason, totalCoinsEarned: totalRosesGirl });
  }

  // Emit final balance updates
  try {
    const [boyBal, girlBal] = await Promise.all([
      WalletService.getBalance(boyInfo.userId),
      WalletService.getBalance(girlInfo.userId),
    ]);
    if (socketBoyId) io.to(socketBoyId).emit('balance_update', { balance: boyBal });
    if (socketGirlId && socketGirlId !== socketBoyId) {
      io.to(socketGirlId).emit('balance_update', { balance: girlBal });
    }
  } catch (err) {
    console.error(`Error emitting final balance updates for call ${callId}:`, err.message);
  }

  console.log(`📴 Call ${callId} ended (reason: ${reason}) — boy ${boyInfo.userId} spent ${totalCostBoy} coins, girl ${girlInfo.userId} earned ${totalRosesGirl} coins`);
}

/**
 * Fetch public profile info for a user (name + avatar + gender).
 */
async function fetchPublicProfile(userId) {
  try {
    const result = await db.query(
      'SELECT id, full_name, gender, avatar_seed, avatar_style FROM public.users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return { id: userId, fullName: 'User', avatarUrl: null, avatarSeed: null, avatarStyle: 'avataaars', gender: 'unknown' };
    }

    const user = result.rows[0];
    const rawGender = (user.gender || '').trim();
    console.log(`✅ Fetched profile for user ${userId}: ${user.full_name} (${rawGender})`);
    return {
      id: user.id,
      fullName: user.full_name || 'User',
      avatarUrl: null,
      avatarSeed: user.avatar_seed || null,
      avatarStyle: user.avatar_style || 'avataaars',
      gender: rawGender.toLowerCase(),
    };
  } catch (err) {
    console.error(`❌ Error fetching profile for user ${userId}:`, err.message);
    return { id: userId, fullName: 'User', avatarUrl: null, avatarSeed: null, avatarStyle: 'avataaars', gender: 'unknown' };
  }
}

/**
 * Forcefully cleanup a user's matchmaking queues, pending calls, active calls, and sockets upon logout.
 */
async function cleanupUserMatchmaking(io, redis, userId) {
  if (!userId) return;
  try {
    const { MatchmakingService } = require('./matchmaking.service');
    const matchmakingService = new MatchmakingService(redis);
    
    // 1. Leave Redis queues
    await matchmakingService.leaveQueue(userId).catch(() => {});

    // 2. Clear any pending direct call requests involving this user
    for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
      if (reqVal.callerId === userId) {
        if (io && reqVal.targetSocketId) {
          io.to(reqVal.targetSocketId).emit('call_response', { callRequestId, status: 'cancelled' });
        }
        clearTimeout(reqVal.timer);
        pendingCallRequests.delete(callRequestId);
      } else if (reqVal.targetUserId === userId) {
        if (io && reqVal.callerSocketId) {
          io.to(reqVal.callerSocketId).emit('call_response', { callRequestId, status: 'offline' });
        }
        clearTimeout(reqVal.timer);
        pendingCallRequests.delete(callRequestId);
      }
    }

    // 3. End any active calls involving this user
    for (const [callId, callObj] of activeCalls.entries()) {
      if (callObj.userA?.userId === userId || callObj.userB?.userId === userId) {
        console.log(`🛑 Ending active call ${callId} due to user ${userId} logout`);
        await handleCallEnd(callId, callsService, io, 'logout', matchmakingService).catch(() => {});
      }
    }

    // 4. Disconnect and remove any sockets registered for this user
    const socketId = userSockets.get(userId);
    if (socketId) {
      socketToCall.delete(socketId);
      userSockets.delete(userId);
      if (io && io.sockets?.sockets?.has(socketId)) {
        const s = io.sockets.sockets.get(socketId);
        if (s) {
          s.emit('force_disconnect', { reason: 'logged_out' });
          s.disconnect(true);
        }
      }
    }

    // Scan all live sockets to ensure none retain this userId
    if (io && io.sockets?.sockets) {
      for (const [, s] of io.sockets.sockets) {
        if (s.userId === userId) {
          s.emit('force_disconnect', { reason: 'logged_out' });
          s.disconnect(true);
        }
      }
    }

    console.log(`🧹 [Matchmaking] Cleaned up session and sockets for user ${userId}`);
  } catch (err) {
    console.error(`Error cleaning up matchmaking session for user ${userId}:`, err.message);
  }
}

module.exports = { registerMatchmakingHandlers, userSockets, cleanupUserMatchmaking, getSocketForUser };


