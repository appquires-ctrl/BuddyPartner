const { MatchmakingService } = require('./matchmaking.service');
const { callsService } = require('../calls/calls.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { sendPushNotification } = require('../../services/firebase.service');
const { cacheService } = require('../../services/cache.service');
const { callQuotaService, TELECOM_BUSY_MESSAGE } = require('../calls/call_quota.service');
const { PresenceService } = require('../presence/presence.service');
const { distributedCallService } = require('../calls/distributed_call.service');
const db = require('../../db');
const redis = require('../../redis');

// ── Distributed Redis Call State Helpers ─────────────────────────────────────

async function saveActiveCall(callId, callInfo) {
  return await distributedCallService.saveActiveCall(redis, callId, callInfo);
}

async function getActiveCall(callId) {
  return await distributedCallService.getActiveCall(redis, callId);
}

async function deleteActiveCall(callId, userAId = null, userBId = null) {
  return await distributedCallService.endCallDistributed(null, redis, callId, 'manual');
}

async function savePendingCall(callRequestId, reqData) {
  return await distributedCallService.savePendingCall(redis, callRequestId, reqData);
}

async function getPendingCall(callRequestId) {
  return await distributedCallService.getPendingCall(redis, callRequestId);
}

async function deletePendingCall(callRequestId) {
  return await distributedCallService.deletePendingCall(redis, callRequestId);
}

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
 * Helper to safely resolve connected socket for a user ID on this local instance
 */
function getSocketForUser(io, targetUserId) {
  if (!io || !targetUserId) return null;
  // O(1) room lookup (all sockets join their own userId room on connect)
  const room = io.sockets?.adapter?.rooms?.get(targetUserId);
  if (room && room.size > 0) {
    const firstSocketId = room.values().next().value;
    if (firstSocketId) {
      const s = io.sockets?.sockets?.get(firstSocketId);
      if (s && s.connected && s.userId === targetUserId) {
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

  // Purge any stale queue entries from previous sessions
  matchmakingService.leaveQueue(userId).catch(() => {});

  // 1. Reconnection recovery: check if user has an active call in progress
  distributedCallService.handleReconnection(socket, io, redis).catch((err) => {
    console.error('[Matchmaking] Error recovering call on reconnect:', err.message);
  });

  // 2. Check if there is a pending direct call request waiting for this user in Redis
  redis.get(`user:pending_call:${userId}`).then(async (pendingReqId) => {
    if (pendingReqId) {
      const reqVal = await distributedCallService.getPendingCall(redis, pendingReqId);
      if (reqVal && reqVal.targetUserId === userId) {
        const callerProfile = await fetchPublicProfile(reqVal.callerId).catch(() => null);
        if (callerProfile) {
          socket.emit('incoming_call_request', {
            callRequestId: pendingReqId,
            caller: callerProfile,
          });
          console.log(`🔔 [FCM Connect] Delivered pending direct call ${pendingReqId} to newly connected user ${userId}`);
        }
      }
    }
  }).catch(() => {});

  // ── join_queue ────────────────────────────────────────────────────────
  socket.on('join_queue', async (callback) => {
    try {
      // Check if user is already in an active call
      const activeCallId = socket.activeCallId || (await distributedCallService.getUserCallId(redis, userId));
      if (activeCallId) {
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

      // Quota check: 200-minute monthly audio cap
      const quotaCheck = await callQuotaService.checkCanStartAudioCall(userId);
      if (!quotaCheck.allowed) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        socket.emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
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
      const targetCallId = callId || socket.activeCallId || (await distributedCallService.getUserCallId(redis, userId));
      if (!targetCallId) return;

      const callInfo = (await distributedCallService.getActiveCall(redis, targetCallId)) ||
                       (await distributedCallService.getActiveInstantCall(redis, targetCallId));
      if (callInfo) {
        const isUserA = callInfo.userA?.userId === userId || callInfo.maleUserId === userId;
        const isUserB = callInfo.userB?.userId === userId || callInfo.femaleUserId === userId;
        if (!isUserA && !isUserB) {
          console.warn(`⚠️ Unauthorized attempt to end call by ${userId}`);
          return;
        }
      }

      await distributedCallService.endCallDistributed(io, redis, targetCallId, 'manual');
      socket.activeCallId = null;
      socket.activeCallType = null;
    } catch (err) {
      console.error('Error in end_call:', err);
    }
  });

  // ── upgrade_to_video ──────────────────────────────────────────────────
  socket.on('upgrade_to_video', async ({ callId }) => {
    try {
      const targetCallId = callId || socket.activeCallId;
      if (!targetCallId) return;

      let otherUserId = null;
      const callInfo = await distributedCallService.getActiveCall(redis, targetCallId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to upgrade call to video by ${userId}`);
          return;
        }

        const [quotaVideoA, quotaVideoB] = await Promise.all([
          callQuotaService.checkCanStartVideoCall(callInfo.userA.userId),
          callQuotaService.checkCanStartVideoCall(callInfo.userB.userId),
        ]);
        if (!quotaVideoA.allowed || !quotaVideoB.allowed) {
          socket.emit('video_upgrade_failed', {
            reason: 'network_unsupported',
            message: 'Video connection is currently unavailable in your region. Continuing voice call.',
          });
          return;
        }

        otherUserId = callInfo.userA.userId === userId ? callInfo.userB.userId : callInfo.userA.userId;
      } else {
        const instantCall = await distributedCallService.getActiveInstantCall(redis, targetCallId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to upgrade instant call to video by ${userId}`);
            return;
          }

          const [quotaVideoA, quotaVideoB] = await Promise.all([
            callQuotaService.checkCanStartVideoCall(instantCall.maleUserId),
            callQuotaService.checkCanStartVideoCall(instantCall.femaleUserId),
          ]);
          if (!quotaVideoA.allowed || !quotaVideoB.allowed) {
            socket.emit('video_upgrade_failed', {
              reason: 'network_unsupported',
              message: 'Video connection is currently unavailable in your region. Continuing voice call.',
            });
            return;
          }

          otherUserId = instantCall.maleUserId === userId ? instantCall.femaleUserId : instantCall.maleUserId;
        }
      }

      if (!otherUserId) {
        console.warn(`⚠️ No active call session found for video upgrade request (callId: ${targetCallId})`);
        return;
      }

      const requesterProfile = await fetchPublicProfile(userId);

      io.to(otherUserId).emit('video_upgrade_request', {
        callId: targetCallId,
        requesterId: userId,
        requesterName: requesterProfile.fullName || 'User',
      });
      console.log(`📹 User ${userId} (${requesterProfile.fullName}) requested video upgrade for call ${targetCallId}`);
    } catch (err) {
      console.error('Error in upgrade_to_video:', err);
    }
  });

  // ── video_upgrade_accepted ────────────────────────────────────────────
  socket.on('video_upgrade_accepted', async ({ callId }) => {
    try {
      const targetCallId = callId || socket.activeCallId;
      if (!targetCallId) return;

      const callInfo = await distributedCallService.getActiveCall(redis, targetCallId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to accept video upgrade by ${userId}`);
          return;
        }
        await callsService.upgradeToVideo(targetCallId);

        let totalAudioSeconds = callInfo.totalAudioSeconds || 0;
        if (callInfo.callType === 'voice') {
          const audioElapsed = Math.floor((Date.now() - (callInfo.voiceStartedAt || callInfo.startedAt)) / 1000);
          totalAudioSeconds += Math.max(0, audioElapsed);
        }

        const [quotaVideoA, quotaVideoB] = await Promise.all([
          callQuotaService.checkCanStartVideoCall(callInfo.userA.userId),
          callQuotaService.checkCanStartVideoCall(callInfo.userB.userId),
        ]);
        const remainingVideoA = Math.max(0, quotaVideoA.remainingSeconds - (callInfo.totalVideoSeconds || 0));
        const remainingVideoB = Math.max(0, quotaVideoB.remainingSeconds - (callInfo.totalVideoSeconds || 0));
        const maxVideoSeconds = Math.min(remainingVideoA, remainingVideoB);

        await distributedCallService.updateActiveCall(redis, targetCallId, {
          callType: 'video',
          voiceStartedAt: '',
          videoStartedAt: Date.now(),
          totalAudioSeconds,
        });

        if (maxVideoSeconds <= 0) {
          await distributedCallService.endCallDistributed(io, redis, targetCallId, 'timeout');
          return;
        }

        const otherUserId = callInfo.userA.userId === userId ? callInfo.userB.userId : callInfo.userA.userId;
        io.to(otherUserId).emit('video_upgrade_accepted', { callId: targetCallId });
        socket.emit('video_upgrade_accepted', { callId: targetCallId });
      } else {
        const instantCall = await distributedCallService.getActiveInstantCall(redis, targetCallId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to accept instant video upgrade by ${userId}`);
            return;
          }
          let totalAudioSeconds = instantCall.totalAudioSeconds || 0;
          if (instantCall.callType !== 'video') {
            const audioElapsed = Math.floor((Date.now() - (instantCall.voiceStartedAt || instantCall.startedAt)) / 1000);
            totalAudioSeconds += Math.max(0, audioElapsed);
          }
          await distributedCallService.updateActiveInstantCall(redis, targetCallId, {
            callType: 'video',
            voiceStartedAt: '',
            videoStartedAt: Date.now(),
            totalAudioSeconds,
          });

          const otherUserId = instantCall.maleUserId === userId ? instantCall.femaleUserId : instantCall.maleUserId;
          io.to(otherUserId).emit('video_upgrade_accepted', { callId: targetCallId });
          socket.emit('video_upgrade_accepted', { callId: targetCallId });
        }
      }

      console.log(`✅ User ${userId} accepted video upgrade for call ${targetCallId}`);
    } catch (err) {
      console.error('Error in video_upgrade_accepted:', err);
    }
  });

  // ── video_upgrade_declined ────────────────────────────────────────────
  socket.on('video_upgrade_declined', async ({ callId }) => {
    try {
      const targetCallId = callId || socket.activeCallId;
      if (!targetCallId) return;

      const callInfo = await distributedCallService.getActiveCall(redis, targetCallId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) return;
        const otherUserId = callInfo.userA.userId === userId ? callInfo.userB.userId : callInfo.userA.userId;
        io.to(otherUserId).emit('video_upgrade_declined', { callId: targetCallId });
      } else {
        const instantCall = await distributedCallService.getActiveInstantCall(redis, targetCallId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) return;
          const otherUserId = instantCall.maleUserId === userId ? instantCall.femaleUserId : instantCall.maleUserId;
          io.to(otherUserId).emit('video_upgrade_declined', { callId: targetCallId });
        }
      }

      console.log(`❌ User ${userId} declined video upgrade for call ${targetCallId}`);
    } catch (err) {
      console.error('Error in video_upgrade_declined:', err);
    }
  });

  // ── switch_to_voice ────────────────────────────────────────────────────
  socket.on('switch_to_voice', async ({ callId }) => {
    try {
      const targetCallId = callId || socket.activeCallId;
      if (!targetCallId) return;

      let otherUserId = null;
      const callInfo = await distributedCallService.getActiveCall(redis, targetCallId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) return;
        await callsService.downgradeToVoice(targetCallId);

        let totalVideoSeconds = callInfo.totalVideoSeconds || 0;
        if (callInfo.callType === 'video' && callInfo.videoStartedAt) {
          const videoElapsed = Math.floor((Date.now() - callInfo.videoStartedAt) / 1000);
          totalVideoSeconds += Math.max(0, videoElapsed);
        }

        await distributedCallService.updateActiveCall(redis, targetCallId, {
          callType: 'voice',
          voiceStartedAt: Date.now(),
          videoStartedAt: '',
          totalVideoSeconds,
        });

        otherUserId = callInfo.userA.userId === userId ? callInfo.userB.userId : callInfo.userA.userId;
      } else {
        const instantCall = await distributedCallService.getActiveInstantCall(redis, targetCallId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) return;
          let totalVideoSeconds = instantCall.totalVideoSeconds || 0;
          if (instantCall.callType === 'video' && instantCall.videoStartedAt) {
            const videoElapsed = Math.floor((Date.now() - instantCall.videoStartedAt) / 1000);
            totalVideoSeconds += Math.max(0, videoElapsed);
          }
          await distributedCallService.updateActiveInstantCall(redis, targetCallId, {
            callType: 'voice',
            voiceStartedAt: Date.now(),
            videoStartedAt: '',
            totalVideoSeconds,
          });
          otherUserId = instantCall.maleUserId === userId ? instantCall.femaleUserId : instantCall.maleUserId;
        }
      }

      if (!otherUserId) return;

      const switcherProfile = await fetchPublicProfile(userId);
      const switcherName = switcherProfile?.fullName || 'Participant';

      io.to(otherUserId).emit('switched_to_voice', {
        callId: targetCallId,
        switcherName,
      });
      console.log(`🎙️ User ${userId} (${switcherName}) switched call ${targetCallId} to voice`);
    } catch (err) {
      console.error('Error in switch_to_voice:', err);
    }
  });

  // ── accept_call_request ────────────────────────────────────────────────
  socket.on('accept_call_request', async ({ callRequestId }) => {
    try {
      const request = await distributedCallService.getPendingCall(redis, callRequestId);
      if (!request) {
        socket.emit('match_error', { error: 'Call request expired or does not exist.' });
        return;
      }

      if (request.targetUserId !== userId) {
        socket.emit('match_error', { error: 'Unauthorized call acceptance.' });
        return;
      }

      await distributedCallService.deletePendingCall(redis, callRequestId);
      await redis.del(`user:pending_call:${userId}`);

      // Validate audio quota for both caller and target
      const [quotaCaller, quotaTarget] = await Promise.all([
        callQuotaService.checkCanStartAudioCall(request.callerId),
        callQuotaService.checkCanStartAudioCall(request.targetUserId),
      ]);
      if (!quotaCaller.allowed || !quotaTarget.allowed) {
        socket.emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        io.to(request.callerId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }
      const maxCallSeconds = Math.min(quotaCaller.remainingSeconds, quotaTarget.remainingSeconds);

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

      await distributedCallService.saveActiveCall(redis, callId, {
        userA: { userId: request.callerId, gender: request.callerGender },
        userB: { userId: request.targetUserId, gender: request.targetGender },
        channelName,
        startedAt: Date.now(),
        callType: 'voice',
        voiceStartedAt: Date.now(),
        videoStartedAt: null,
        totalAudioSeconds: 0,
        totalVideoSeconds: 0,
        maxAllowedSeconds: maxCallSeconds,
      });

      socket.activeCallId = callId;
      socket.activeCallType = 'direct';

      await redis.srem('instant:female_pool', request.callerId, request.targetUserId).catch(() => {});

      // Arm local timeout timer
      if (maxCallSeconds > 0) {
        setTimeout(() => {
          distributedCallService.endCallDistributed(io, redis, callId, 'timeout');
        }, maxCallSeconds * 1000);
      }

      // Notify Caller
      io.to(request.callerId).emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenA,
        agoraUid: uidA,
        matchedUser: profileB,
      });

      // Notify Target (current socket)
      socket.emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenB,
        agoraUid: uidB,
        matchedUser: profileA,
      });

      console.log(`✅ Direct call ${callId} established: ${request.callerId} (${request.callerGender}) ↔ ${request.targetUserId} (${request.targetGender})`);
    } catch (err) {
      console.error('Error in accept_call_request:', err);
      socket.emit('match_error', { error: 'Failed to establish call connection.' });
    }
  });

  // ── decline_call_request ────────────────────────────────────────────────
  socket.on('decline_call_request', async ({ callRequestId }) => {
    try {
      const request = await distributedCallService.getPendingCall(redis, callRequestId);
      if (!request || request.targetUserId !== userId) return;

      await distributedCallService.deletePendingCall(redis, callRequestId);
      await redis.del(`user:pending_call:${request.targetUserId}`);

      io.to(request.callerId).emit('call_response', {
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
      const request = await distributedCallService.getPendingCall(redis, callRequestId);
      if (!request || request.callerId !== userId) return;

      await distributedCallService.deletePendingCall(redis, callRequestId);
      await redis.del(`user:pending_call:${request.targetUserId}`);

      io.to(request.targetUserId).emit('call_response', {
        callRequestId,
        status: 'cancelled',
      });

      console.log(`🛑 Call request ${callRequestId} cancelled by caller ${userId}`);
    } catch (err) {
      console.error('Error in cancel_call_request:', err);
    }
  });

  // ── direct_call ────────────────────────────────────────────────────────
  socket.on('direct_call', async ({ targetUserId, callType = 'voice' } = {}) => {
    // Subscription check: unisex requirement for all users
    const isSub = await subscriptionsService.isSubscribed(userId);
    if (!isSub) {
      socket.emit('match_error', { error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to start a call.' });
      return;
    }

    // Quota check: 200-minute monthly audio cap
    const callerQuota = await callQuotaService.checkCanStartAudioCall(userId);
    if (!callerQuota.allowed) {
      socket.emit('call_response', { status: 'busy', message: TELECOM_BUSY_MESSAGE });
      return;
    }

    if (targetUserId === userId) {
      socket.emit('match_error', { error: 'Cannot call yourself' });
      return;
    }

    // Check if caller is already engaged in an active call
    const callerActive = socket.activeCallId || (await distributedCallService.getUserCallId(redis, userId));
    if (callerActive) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    // Check if target is busy or engaged in an active call via Redis O(1)
    const [targetActiveCall, targetInInstant, targetPending] = await Promise.all([
      distributedCallService.getUserCallId(redis, targetUserId),
      redis.get(`instant:in_call:${targetUserId}`).catch(() => null),
      redis.get(`user:pending_call:${targetUserId}`).catch(() => null),
    ]);

    if (targetActiveCall || targetInInstant || targetPending) {
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

      const isTargetOnline = await PresenceService.isUserOnline(redis, targetUserId);
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

      await distributedCallService.savePendingCall(redis, callRequestId, {
        callRequestId,
        callerId: userId,
        callerGender,
        targetUserId,
        targetGender,
        callType,
        createdAt: Date.now(),
      });
      await redis.set(`user:pending_call:${targetUserId}`, callRequestId, 'EX', 35);

      // Arm 30s timeout on caller node
      setTimeout(async () => {
        const req = await distributedCallService.getPendingCall(redis, callRequestId);
        if (req) {
          console.log(`⏰ Call request ${callRequestId} timed out (no answer)`);
          io.to(userId).emit('call_response', { callRequestId, status: 'no_answer' });
          io.to(targetUserId).emit('call_response', { callRequestId, status: 'no_answer' });
          await distributedCallService.deletePendingCall(redis, callRequestId);
          await redis.del(`user:pending_call:${targetUserId}`);
        }
      }, 30000);

      // Deliver incoming request cluster-wide to target's personal room
      if (isTargetOnline) {
        io.to(targetUserId).emit('incoming_call_request', {
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

      // Cancel any pending direct call requests involving this user
      const pendingReqId = await redis.get(`user:pending_call:${userId}`);
      if (pendingReqId) {
        const req = await distributedCallService.getPendingCall(redis, pendingReqId);
        if (req) {
          await distributedCallService.deletePendingCall(redis, pendingReqId);
          await redis.del(`user:pending_call:${userId}`);
          io.to(req.callerId).emit('call_response', { callRequestId: pendingReqId, status: 'cancelled' });
        }
      }

      // Check if user was in an active call
      const callId = socket.activeCallId || (await distributedCallService.getUserCallId(redis, userId));
      if (callId) {
        console.log(`⚠️ User ${userId} disconnected during call ${callId} — starting 15s grace period`);
        await distributedCallService.handlePeerDisconnect(io, redis, userId, callId);
      }
    } catch (err) {
      console.error('Error in matchmaking disconnect handler:', err);
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
    io.to(userA.userId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    io.to(userB.userId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    return;
  }

  try {
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

    // Validate audio quota for both matched participants
    const [quotaA, quotaB] = await Promise.all([
      callQuotaService.checkCanStartAudioCall(userA.userId),
      callQuotaService.checkCanStartAudioCall(userB.userId),
    ]);

    if (!quotaA.allowed || !quotaB.allowed) {
      if (!quotaA.allowed) io.to(userA.userId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
      if (!quotaB.allowed) io.to(userB.userId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
      await Promise.all([
        matchmakingService.leaveQueue(userA.userId),
        matchmakingService.leaveQueue(userB.userId),
      ]);
      return;
    }

    const maxCallSeconds = Math.min(quotaA.remainingSeconds, quotaB.remainingSeconds);

    // Track active call in Redis
    await distributedCallService.saveActiveCall(redis, callId, {
      userA: { userId: userA.userId, gender: genderA },
      userB: { userId: userB.userId, gender: genderB },
      channelName,
      startedAt: Date.now(),
      callType: 'voice',
      voiceStartedAt: Date.now(),
      videoStartedAt: null,
      totalAudioSeconds: 0,
      totalVideoSeconds: 0,
      maxAllowedSeconds: maxCallSeconds,
    });

    await redis.srem('instant:female_pool', userA.userId, userB.userId).catch(() => {});

    // Arm timeout safety timer on the matchmaking node
    if (maxCallSeconds > 0) {
      setTimeout(() => {
        distributedCallService.endCallDistributed(io, redis, callId, 'timeout');
      }, maxCallSeconds * 1000);
    }

    // Attach activeCallId to local sockets if present on this instance
    const localSocketA = getSocketForUser(io, userA.userId);
    const localSocketB = getSocketForUser(io, userB.userId);
    if (localSocketA) {
      localSocketA.activeCallId = callId;
      localSocketA.activeCallType = 'direct';
    }
    if (localSocketB) {
      localSocketB.activeCallId = callId;
      localSocketB.activeCallType = 'direct';
    }

    // Emit match_found to both users across cluster via personal rooms
    io.to(userA.userId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenA,
      agoraUid: uidA,
      matchedUser: profileB,
    });

    io.to(userB.userId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenB,
      agoraUid: uidB,
      matchedUser: profileA,
    });

    console.log(`📞 Call ${callId} started: ${userA.userId} (${genderA}) ↔ ${userB.userId} (${genderB})`);
  } catch (err) {
    console.error('Error setting up match:', err);
    io.to(userA.userId).emit('match_error', { error: 'Failed to set up call' });
    io.to(userB.userId).emit('match_error', { error: 'Failed to set up call' });
  }
}

/**
 * Handle call end (manual, timer, or disconnect).
 * Delegates directly to distributed call service.
 */
async function handleCallEnd(callId, callsService, io, reason, matchmakingService) {
  await distributedCallService.endCallDistributed(io, redis, callId, reason);
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
    const pendingReqId = await redis.get(`user:pending_call:${userId}`);
    if (pendingReqId) {
      await distributedCallService.deletePendingCall(redis, pendingReqId);
      await redis.del(`user:pending_call:${userId}`);
    }

    // 3. End any active calls involving this user
    const callId = await distributedCallService.getUserCallId(redis, userId);
    if (callId) {
      console.log(`🛑 Ending active call ${callId} due to user ${userId} logout`);
      await distributedCallService.endCallDistributed(io, redis, callId, 'logout').catch(() => {});
    }

    // 4. Scan all live sockets to ensure none retain this userId
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

module.exports = {
  registerMatchmakingHandlers,
  cleanupUserMatchmaking,
  getSocketForUser,
  saveActiveCall,
  getActiveCall,
  deleteActiveCall,
  savePendingCall,
  getPendingCall,
  deletePendingCall,
  handleCallEnd,
};


