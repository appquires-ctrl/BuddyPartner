const { MatchmakingService } = require('./matchmaking.service');
const { CallsService } = require('../calls/calls.service');

// In-memory map of active calls: callId → { userA: { userId, socketId }, userB: { userId, socketId } }
const activeCalls = new Map();
// Reverse map: socketId → callId (for fast lookup on disconnect)
const socketToCall = new Map();
// Map: userId → socketId (for disconnect cleanup)
const userSockets = new Map();

/**
 * Register all matchmaking-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase
 */
function registerMatchmakingHandlers(io, socket, redis, supabase) {
  const matchmakingService = new MatchmakingService(redis);
  const callsService = new CallsService(supabase);
  const userId = socket.userId;

  // Track this user's socket
  userSockets.set(userId, socket.id);

  // ── join_queue ────────────────────────────────────────────────────────
  socket.on('join_queue', async (callback) => {
    try {
      // Check if user is already in an active call
      if (socketToCall.has(socket.id)) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in an active call' });
        return;
      }

      const added = await matchmakingService.joinQueue(userId, socket.id);
      if (!added) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in queue' });
        return;
      }

      console.log(`📥 User ${userId} joined queue`);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ success: true });

      // Try to find a match
      await attemptMatch(io, redis, supabase, matchmakingService, callsService);
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
      if (!callInfo) return;

      // Security Check: Authorize sender participant
      if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
        console.warn(`⚠️ Unauthorized attempt to end call by ${userId}`);
        return;
      }

      await handleCallEnd(callId, callsService, io, 'manual');
    } catch (err) {
      console.error('Error in end_call:', err);
    }
  });

  // ── upgrade_to_video ──────────────────────────────────────────────────
  socket.on('upgrade_to_video', async ({ callId }) => {
    try {
      const callInfo = activeCalls.get(callId);
      if (!callInfo) return;

      // Security Check: Authorize sender participant
      if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
        console.warn(`⚠️ Unauthorized attempt to upgrade call to video by ${userId}`);
        return;
      }

      await callsService.upgradeToVideo(callId);

      // Determine the other user's socket and relay the upgrade
      const otherSocketId = callInfo.userA.userId === userId
        ? callInfo.userB.socketId
        : callInfo.userA.socketId;

      io.to(otherSocketId).emit('video_upgrade_request', { callId });
      console.log(`📹 User ${userId} requested video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in upgrade_to_video:', err);
    }
  });

  // ── video_upgrade_accepted ────────────────────────────────────────────
  socket.on('video_upgrade_accepted', ({ callId }) => {
    try {
      const callInfo = activeCalls.get(callId);
      if (!callInfo) return;

      // Security Check: Authorize sender participant
      if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
        console.warn(`⚠️ Unauthorized attempt to accept video upgrade by ${userId}`);
        return;
      }

      // Relay acceptance to the other party
      const otherSocketId = callInfo.userA.userId === userId
        ? callInfo.userB.socketId
        : callInfo.userA.socketId;

      io.to(otherSocketId).emit('video_upgrade_accepted', { callId });
      console.log(`✅ User ${userId} accepted video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in video_upgrade_accepted:', err);
    }
  });

  // ── direct_call ────────────────────────────────────────────────────────
  // Allows a user to call a specific person directly (e.g. from call history)
  // bypassing the matchmaking queue. Uses the same Agora + 5-min timer flow.
  socket.on('direct_call', async ({ targetUserId }) => {
    // 1. Prevent calling yourself
    if (targetUserId === userId) {
      socket.emit('match_error', { error: 'Cannot call yourself' });
      return;
    }

    // 2. Prevent calling if already in an active call
    if (socketToCall.has(socket.id)) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    // 3. Check if target user is online
    const targetSocketId = userSockets.get(targetUserId);
    if (!targetSocketId) {
      socket.emit('match_error', { error: 'User is currently offline' });
      return;
    }

    // 4. Check if target user is already in a call
    if (socketToCall.has(targetSocketId)) {
      socket.emit('match_error', { error: 'User is currently on another call' });
      return;
    }

    // 5. Prevent concurrent setup race condition with Redis locks
    const lockKeyA = `call_lock:${userId}`;
    const lockKeyB = `call_lock:${targetUserId}`;
    const lockedA = await redis.set(lockKeyA, '1', 'NX', 'EX', 10);
    const lockedB = await redis.set(lockKeyB, '1', 'NX', 'EX', 10);
    if (!lockedA || !lockedB) {
      if (lockedA) await redis.del(lockKeyA);
      if (lockedB) await redis.del(lockKeyB);
      socket.emit('match_error', { error: 'Line is busy. Please try again.' });
      return;
    }

    try {
      // Remove both users from the matchmaking queue if they were in it
      await matchmakingService.leaveQueue(userId);
      await matchmakingService.leaveQueue(targetUserId);

      // 6. Set up the call — same logic as attemptMatch
      const channelName = matchmakingService.generateChannelName();
      const uidA = matchmakingService.uuidToAgoraUid(userId);
      const uidB = matchmakingService.uuidToAgoraUid(targetUserId);
      const tokenA = callsService.generateAgoraToken(channelName, uidA);
      const tokenB = callsService.generateAgoraToken(channelName, uidB);

      // 7. Create call record in DB
      const callId = await callsService.createCall(userId, targetUserId);

      // 8. Fetch profiles for both users
      const [profileA, profileB] = await Promise.all([
        fetchPublicProfile(supabase, userId),
        fetchPublicProfile(supabase, targetUserId),
      ]);

      // 9. Track active call
      activeCalls.set(callId, {
        userA: { userId, socketId: socket.id, agoraUid: uidA },
        userB: { userId: targetUserId, socketId: targetSocketId, agoraUid: uidB },
        channelName,
      });
      socketToCall.set(socket.id, callId);
      socketToCall.set(targetSocketId, callId);

      // 10. Emit match_found to both users (same payload as random match)
      io.to(socket.id).emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenA,
        agoraUid: uidA,
        matchedUser: profileB,
      });

      io.to(targetSocketId).emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenB,
        agoraUid: uidB,
        matchedUser: profileA,
      });

      // 11. Start server-authoritative 5-minute timer
      callsService.startCallTimer(callId, (expiredCallId) => {
        handleCallEnd(expiredCallId, callsService, io, 'timer');
      });

      console.log(`📞 Direct call ${callId} started: ${userId} → ${targetUserId} on channel ${channelName}`);
    } catch (err) {
      console.error('Error in direct_call:', err);
      socket.emit('match_error', { error: 'Failed to set up direct call' });
    } finally {
      // Release locks
      await redis.del(lockKeyA);
      await redis.del(lockKeyB);
    }
  });

  // ── disconnect ────────────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    try {
      // Remove from queue if they were waiting
      await matchmakingService.leaveQueue(userId);

      // End active call if in one
      const callId = socketToCall.get(socket.id);
      if (callId) {
        console.log(`⚠️ User ${userId} disconnected during call ${callId}`);
        await handleCallEnd(callId, callsService, io, 'disconnect');
      }

      // Clean up socket tracking
      userSockets.delete(userId);
    } catch (err) {
      console.error('Error in disconnect handler:', err);
    }
  });
}

/**
 * Attempt to match two users from the queue.
 * Called after every joinQueue to check if a pair is available.
 */
async function attemptMatch(io, redis, supabase, matchmakingService, callsService) {
  const match = await matchmakingService.tryMatch();
  if (!match) return;

  const { userA, userB } = match;
  console.log(`🎯 Match found: ${userA.userId} ↔ ${userB.userId}`);

  try {
    // Generate Agora channel and tokens
    const channelName = matchmakingService.generateChannelName();
    const uidA = matchmakingService.uuidToAgoraUid(userA.userId);
    const uidB = matchmakingService.uuidToAgoraUid(userB.userId);
    const tokenA = callsService.generateAgoraToken(channelName, uidA);
    const tokenB = callsService.generateAgoraToken(channelName, uidB);

    // Create call record in DB
    const callId = await callsService.createCall(userA.userId, userB.userId);

    // Fetch public user info for both users
    const [profileA, profileB] = await Promise.all([
      fetchPublicProfile(supabase, userA.userId),
      fetchPublicProfile(supabase, userB.userId),
    ]);

    // Track active call
    activeCalls.set(callId, {
      userA: { ...userA, agoraUid: uidA },
      userB: { ...userB, agoraUid: uidB },
      channelName,
    });
    socketToCall.set(userA.socketId, callId);
    socketToCall.set(userB.socketId, callId);

    // Emit match_found to both users
    io.to(userA.socketId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenA,
      agoraUid: uidA,
      matchedUser: profileB,
    });

    io.to(userB.socketId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenB,
      agoraUid: uidB,
      matchedUser: profileA,
    });

    // Start server-authoritative 5-minute timer
    callsService.startCallTimer(callId, (expiredCallId) => {
      handleCallEnd(expiredCallId, callsService, io, 'timer');
    });

    console.log(`📞 Call ${callId} started on channel ${channelName}`);
  } catch (err) {
    console.error('Error setting up match:', err);
    // If match setup fails, notify both users
    io.to(userA.socketId).emit('match_error', { error: 'Failed to set up call' });
    io.to(userB.socketId).emit('match_error', { error: 'Failed to set up call' });
  }
}

/**
 * Handle call end (manual, timer, or disconnect).
 * Cleans up state and notifies both parties.
 */
async function handleCallEnd(callId, callsService, io, reason) {
  const callInfo = activeCalls.get(callId);
  if (!callInfo) return; // Already cleaned up

  // Remove from tracking maps
  activeCalls.delete(callId);
  socketToCall.delete(callInfo.userA.socketId);
  socketToCall.delete(callInfo.userB.socketId);

  // End call in DB
  await callsService.endCall(callId);

  // Notify both users
  io.to(callInfo.userA.socketId).emit('call_ended', { callId, reason });
  io.to(callInfo.userB.socketId).emit('call_ended', { callId, reason });

  console.log(`📴 Call ${callId} ended (reason: ${reason})`);
}

/**
 * Fetch public profile info for a user (name + avatar only).
 */
async function fetchPublicProfile(supabase, userId) {
  const { data, error } = await supabase
    .from('users')
    .select('id, full_name')
    .eq('id', userId)
    .single();

  if (error || !data) {
    console.error(`❌ Error fetching profile for user ${userId}:`, error || 'No data found');
    return { id: userId, fullName: 'User', avatarUrl: null };
  }

  console.log(`✅ Fetched profile for user ${userId}: ${data.full_name}`);
  return {
    id: data.id,
    fullName: data.full_name || 'User',
    avatarUrl: null,
  };
}

module.exports = { registerMatchmakingHandlers };
