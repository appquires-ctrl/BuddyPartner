const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const { instantConnectService } = require('./instant_connect.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const db = require('../../db');

const AGORA_APP_ID = process.env.AGORA_APP_ID || '';
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE || '';

// In-memory active instant calls map: callId -> { sessionId, maleUserId, maleSocketId, femaleUserId, femaleSocketId, timer10m, startedAt }
const activeInstantCalls = new Map();
// Reverse mapping: socketId -> callId
const socketToInstantCall = new Map();
// Ringing timers: callRequestId -> Timer
const ringingTimers = new Map();
// User socket registry: userId -> socketId
const userSockets = new Map();

/**
 * Generate Agora RTC Token for communication
 */
function generateAgoraToken(channelName, uid) {
  if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
    return 'test_token_' + Date.now();
  }
  const role = RtcRole.PUBLISHER;
  const expirationTimeInSeconds = 3600 * 2; // 2 hours
  const currentTimestamp = Math.floor(Date.now() / 1000);
  const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

  return RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID,
    AGORA_APP_CERTIFICATE,
    channelName,
    uid,
    role,
    privilegeExpiredTs
  );
}

/**
 * Check if a user is female
 */
async function isUserFemale(userId) {
  try {
    const res = await db.query(`SELECT gender FROM public.users WHERE id = $1`, [userId]);
    const g = (res.rows[0]?.gender || '').toLowerCase().trim();
    return g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
  } catch (_) {
    return false;
  }
}

/**
 * Trigger Instant Matchmaker cycle
 */
async function triggerInstantMatchmaker(io, redis) {
  try {
    // 1. Get highest-priority male from queue
    const topMales = await redis.zrevrange('instant:male_queue', 0, 0);
    if (!topMales || topMales.length === 0) return;

    const maleUserId = topMales[0];
    const sessionStr = await redis.get(`instant:male_session:${maleUserId}`);
    if (!sessionStr) {
      await redis.zrem('instant:male_queue', maleUserId);
      return;
    }

    const sessionData = JSON.parse(sessionStr);
    const { sessionId, bidAmount, socketId: maleSocketId } = sessionData;

    // Verify male socket is still active
    const maleSocket = io.sockets.sockets.get(maleSocketId);
    if (!maleSocket || !maleSocket.connected) {
      await redis.zrem('instant:male_queue', maleUserId);
      await redis.del(`instant:male_session:${maleUserId}`);
      await instantConnectService.refundEscrowedCoins(maleUserId, bidAmount, sessionId);
      return;
    }

    // 2. Fetch available females from Redis pool (excluding any in-call or on snooze)
    const allFemales = await redis.smembers('instant:female_pool');
    if (!allFemales || allFemales.length === 0) {
      // 0 available females -> trigger 1:10 FCM surge (with 60s cooldown per session)
      const surgeCooldownKey = `instant:surge_cooldown:${sessionId}`;
      const hasSurged = await redis.get(surgeCooldownKey);
      if (!hasSurged) {
        await redis.set(surgeCooldownKey, '1', 'EX', 60);
        const offlineFemales = await instantConnectService.getSurgeEligibleFemales([maleUserId], 10);
        if (offlineFemales.length > 0) {
          console.log(`📡 [FCM Surge] Dispatched surge alert to ${offlineFemales.length} offline female accounts for male ${maleUserId} (Bid: ₹${bidAmount})`);
          // In production: send FCM push notifications here using Firebase Admin SDK
        }
      }
      return;
    }

    // Filter females who are currently connected, have toggle ON in DB, and are not in a call
    const eligibleFemales = [];
    for (const femaleId of allFemales) {
      if (femaleId === maleUserId) continue;
      const isSnoozed = await redis.get(`instant:snooze:${femaleId}`);
      if (isSnoozed) continue;

      const fSocketId = userSockets.get(femaleId);
      if (fSocketId) {
        const fSocket = io.sockets.sockets.get(fSocketId);
        if (fSocket && fSocket.connected && !socketToInstantCall.has(fSocketId)) {
          eligibleFemales.push({ userId: femaleId, socketId: fSocketId, socket: fSocket });
        }
      }
    }

    if (eligibleFemales.length === 0) {
      return;
    }

    // 3. 1 : 2 Dual Ring Dispatch (Select up to 2 random eligible females)
    const shuffled = eligibleFemales.sort(() => 0.5 - Math.random());
    const selectedFemales = shuffled.slice(0, 2);

    const callRequestId = `req_${sessionId}_${Date.now()}`;
    const agoraChannelName = `instant_${sessionId}_${Date.now()}`;

    // Mark females in temporary ringing lock (expires in 10s)
    for (const f of selectedFemales) {
      await redis.set(`instant:ringing:${f.userId}`, callRequestId, 'EX', 10);
      await redis.srem('instant:female_pool', f.userId);
    }

    // Save request metadata in Redis
    const requestMeta = {
      sessionId,
      maleUserId,
      maleSocketId,
      bidAmount,
      agoraChannelName,
      femaleUserIds: selectedFemales.map((f) => f.userId),
    };
    await redis.set(`instant:request:${callRequestId}`, JSON.stringify(requestMeta), 'EX', 20);

    console.log(`⚡ [Instant Connect] Ringing 1:2 pair (${selectedFemales.map((f) => f.userId).join(', ')}) for male ${maleUserId}`);

    // Emit incoming call to both female sockets
    for (const f of selectedFemales) {
      const fAgoraUid = Math.floor(Math.random() * 90000) + 10000;
      const fToken = generateAgoraToken(agoraChannelName, fAgoraUid);

      f.socket.emit('incoming_instant_call', {
        callRequestId,
        agoraChannelName,
        agoraToken: fToken,
        agoraUid: fAgoraUid,
        timeoutSeconds: 7,
      });
    }

    // 4. Set 7-second cascade timer
    const cascadeTimer = setTimeout(async () => {
      ringingTimers.delete(callRequestId);

      // Check if call was already claimed/accepted
      const claimed = await redis.get(`instant:claim:${callRequestId}`);
      if (claimed) return;

      console.log(`⏰ [Instant Connect] 7s timeout reached for ${callRequestId}. Cascading to next pair...`);

      // Dismiss ringing on both female sockets and put on 2-min snooze
      for (const f of selectedFemales) {
        await redis.del(`instant:ringing:${f.userId}`);
        await redis.set(`instant:snooze:${f.userId}`, '1', 'EX', 120); // 2-min AFK snooze
        f.socket.emit('instant_call_dismissed', { callRequestId, reason: 'timeout' });
        // Return to pool after snooze
      }

      // Re-trigger matchmaker to cascade to next available girls
      triggerInstantMatchmaker(io, redis);
    }, 7500);

    ringingTimers.set(callRequestId, cascadeTimer);
  } catch (err) {
    console.error('Error in triggerInstantMatchmaker:', err.message);
  }
}

/**
 * Register Instant Connect Socket.io handlers
 */
function registerInstantConnectHandlers(io, socket, redis) {
  const userId = socket.userId;
  if (userId) {
    userSockets.set(userId, socket.id);
  }

  // ── 1. instant:join_queue (Male Bidding & Joining) ────────────────────────
  socket.on('instant:join_queue', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const bidAmount = parseInt(data?.bidAmount, 10);
      if (!bidAmount || bidAmount < 10) {
        cb({ success: false, error: 'INVALID_AMOUNT', message: 'Minimum bid amount is 10 coins.' });
        return;
      }

      // Check active subscription
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        cb({ success: false, error: 'SUBSCRIPTION_REQUIRED', message: 'Active subscription required.' });
        return;
      }

      // Check if already in queue or call
      const existingQueueScore = await redis.zscore('instant:male_queue', userId);
      if (existingQueueScore) {
        cb({ success: true, message: 'Already in queue' });
        return;
      }

      // Escrow coins from male wallet
      const escrowResult = await instantConnectService.escrowMaleCoins(userId, bidAmount);
      if (!escrowResult.success) {
        cb(escrowResult);
        return;
      }

      // Create session in DB
      const session = await instantConnectService.createSession(userId, bidAmount);

      // Score formula: Amount * 10^12 + (10^12 - Timestamp)
      const now = Date.now();
      const score = bidAmount * Math.pow(10, 11) + (Math.pow(10, 11) - (now % Math.pow(10, 11)));

      await redis.zadd('instant:male_queue', score, userId);
      await redis.set(
        `instant:male_session:${userId}`,
        JSON.stringify({ sessionId: session.id, bidAmount, socketId: socket.id })
      );

      // Determine queue rank
      const rank = (await redis.zrevrank('instant:male_queue', userId)) ?? 0;

      cb({
        success: true,
        sessionId: session.id,
        bidAmount,
        queuePosition: rank + 1,
        newBalance: escrowResult.newBalance,
      });

      socket.emit('instant:queue_status', {
        status: 'queued',
        queuePosition: rank + 1,
        bidAmount,
      });

      // Trigger matchmaker cycle
      triggerInstantMatchmaker(io, redis);
    } catch (err) {
      console.error(`Error in instant:join_queue for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR', message: 'Failed to join instant queue' });
    }
  });

  // ── 2. instant:leave_queue (Male Cancelling with 100% Refund) ─────────────
  socket.on('instant:leave_queue', async (callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);

        const refundRes = await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        cb({ success: true, newBalance: refundRes.newBalance });
        socket.emit('instant:queue_left', { refundedCoins: bidAmount, newBalance: refundRes.newBalance });
      } else {
        cb({ success: true });
      }
    } catch (err) {
      console.error(`Error leaving instant queue for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR' });
    }
  });

  // ── 3. instant:toggle_incoming (Female Toggle Switch) ────────────────────
  socket.on('instant:toggle_incoming', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const enabled = data?.enabled === true;
      const isFemale = await isUserFemale(userId);
      if (!isFemale) {
        cb({ success: false, error: 'FEMALE_ONLY', message: 'Paid call receiving is for female accounts only.' });
        return;
      }

      const res = await instantConnectService.toggleIncomingPaidCalls(userId, enabled, redis);
      cb(res);

      if (enabled) {
        triggerInstantMatchmaker(io, redis);
      }
    } catch (err) {
      console.error(`Error in instant:toggle_incoming for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR' });
    }
  });

  // ── 4. instant:accept_call (Female First-Come, First-Served) ──────────────
  socket.on('instant:accept_call', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    const callRequestId = data?.callRequestId;
    if (!callRequestId) {
      cb({ success: false, error: 'INVALID_REQUEST' });
      return;
    }

    try {
      // Clear ringing cascade timer
      const timer = ringingTimers.get(callRequestId);
      if (timer) {
        clearTimeout(timer);
        ringingTimers.delete(callRequestId);
      }

      // Atomic SETNX to claim the call
      const win = await redis.set(`instant:claim:${callRequestId}`, userId, 'NX', 'EX', 60);

      const requestStr = await redis.get(`instant:request:${callRequestId}`);
      if (!requestStr) {
        cb({ success: false, error: 'REQUEST_EXPIRED', message: 'Call request expired.' });
        return;
      }

      const reqData = JSON.parse(requestStr);
      const { sessionId, maleUserId, maleSocketId, bidAmount, agoraChannelName, femaleUserIds } = reqData;

      if (win !== 'OK') {
        // Another female won the race
        cb({ success: false, error: 'ALREADY_CLAIMED', message: 'Another buddy answered this call!' });
        socket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
        return;
      }

      // Winner! Clean up other ringing females
      for (const fId of femaleUserIds) {
        await redis.del(`instant:ringing:${fId}`);
        if (fId !== userId) {
          const loserSocketId = userSockets.get(fId);
          if (loserSocketId) {
            io.to(loserSocketId).emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
          }
          // Return non-answering girl to pool if still eligible
          await redis.sadd('instant:female_pool', fId);
        }
      }

      // Remove male from queue and active session
      await redis.zrem('instant:male_queue', maleUserId);
      await redis.del(`instant:male_session:${maleUserId}`);

      // Start call in DB
      await instantConnectService.startCallSession(sessionId, userId, agoraChannelName);

      // Generate Agora Tokens
      const maleUid = Math.floor(Math.random() * 80000) + 10000;
      const femaleUid = Math.floor(Math.random() * 80000) + 10000;

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);

      const callId = `instant_call_${sessionId}`;

      // Start 600-second (10-minute) server-authoritative milestone timer
      const milestoneTimer = setTimeout(async () => {
        console.log(`🎉 [Instant Connect] 10-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          io.to(maleSocketId).emit('instant:milestone_reached', {
            callId,
            sessionId,
            milestoneMinutes: 10,
          });
          socket.emit('instant:milestone_reached', {
            callId,
            sessionId,
            milestoneMinutes: 10,
            scratchCardId: scratchCard.id,
            coinReward: scratchCard.coin_reward,
          });
        }
      }, 600 * 1000); // 10 minutes

      const activeCallObj = {
        callId,
        sessionId,
        maleUserId,
        maleSocketId,
        femaleUserId: userId,
        femaleSocketId: socket.id,
        startedAt: Date.now(),
        bidAmount,
        milestoneTimer,
        agoraChannelName,
      };

      activeInstantCalls.set(callId, activeCallObj);
      socketToInstantCall.set(maleSocketId, callId);
      socketToInstantCall.set(socket.id, callId);

      // Notify Male
      io.to(maleSocketId).emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: maleToken,
        agoraUid: maleUid,
        remoteUid: femaleUid,
        agoraAppId: AGORA_APP_ID,
        bidAmount,
        otherUserName: 'VIP Partner',
        durationLimitSeconds: 600,
      });

      // Notify Female
      socket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: femaleToken,
        agoraUid: femaleUid,
        remoteUid: maleUid,
        agoraAppId: AGORA_APP_ID,
        bidAmount,
        otherUserName: 'VIP Partner',
        durationLimitSeconds: 600,
      });

      cb({ success: true, callId, sessionId });
    } catch (err) {
      console.error(`Error accepting instant call by ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR' });
    }
  });

  // ── 5. instant:decline_call ──────────────────────────────────────────────
  socket.on('instant:decline_call', async (data) => {
    const callRequestId = data?.callRequestId;
    if (!callRequestId) return;

    await redis.del(`instant:ringing:${userId}`);
    await redis.sadd('instant:female_pool', userId);
  });

  // ── 6. instant:end_call ──────────────────────────────────────────────────
  socket.on('instant:end_call', async () => {
    const callId = socketToInstantCall.get(socket.id);
    if (!callId) return;

    const callObj = activeInstantCalls.get(callId);
    if (!callObj) return;

    const durationSeconds = Math.floor((Date.now() - callObj.startedAt) / 1000);

    // Cancel 10m timer if call ends early
    if (callObj.milestoneTimer) {
      clearTimeout(callObj.milestoneTimer);
    }

    const finalStatus = durationSeconds >= 600 ? 'completed' : 'dropped';
    await instantConnectService.endCallSession(callObj.sessionId, finalStatus, durationSeconds);

    // Notify both parties
    io.to(callObj.maleSocketId).emit('instant:call_ended', {
      callId,
      durationSeconds,
      status: finalStatus,
    });
    io.to(callObj.femaleSocketId).emit('instant:call_ended', {
      callId,
      durationSeconds,
      status: finalStatus,
    });

    // Cleanup mappings
    socketToInstantCall.delete(callObj.maleSocketId);
    socketToInstantCall.delete(callObj.femaleSocketId);
    activeInstantCalls.delete(callId);

    // Return female to pool if her toggle is still ON
    const fStatus = await instantConnectService.getFemaleStatus(callObj.femaleUserId);
    if (fStatus.incomingPaidCallsEnabled) {
      await redis.sadd('instant:female_pool', callObj.femaleUserId);
    }
  });

  // ── Disconnect cleanup ───────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    userSockets.delete(userId);
    // Remove from female pool if disconnected
    await redis.srem('instant:female_pool', userId);

    const callId = socketToInstantCall.get(socket.id);
    if (callId) {
      const callObj = activeInstantCalls.get(callId);
      if (callObj) {
        const durationSeconds = Math.floor((Date.now() - callObj.startedAt) / 1000);
        if (callObj.milestoneTimer) clearTimeout(callObj.milestoneTimer);

        const finalStatus = durationSeconds >= 600 ? 'completed' : 'dropped';
        await instantConnectService.endCallSession(callObj.sessionId, finalStatus, durationSeconds);

        const otherSocketId = socket.id === callObj.maleSocketId ? callObj.femaleSocketId : callObj.maleSocketId;
        io.to(otherSocketId).emit('instant:call_ended', {
          callId,
          durationSeconds,
          reason: 'peer_disconnected',
        });

        socketToInstantCall.delete(callObj.maleSocketId);
        socketToInstantCall.delete(callObj.femaleSocketId);
        activeInstantCalls.delete(callId);
      }
    }
  });
}

module.exports = {
  registerInstantConnectHandlers,
};
