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
    .select('id, full_name, avatar_url')
    .eq('id', userId)
    .single();

  if (error || !data) {
    return { id: userId, fullName: 'User', avatarUrl: null };
  }

  return {
    id: data.id,
    fullName: data.full_name || 'User',
    avatarUrl: data.avatar_url || null,
  };
}

module.exports = { registerMatchmakingHandlers };
