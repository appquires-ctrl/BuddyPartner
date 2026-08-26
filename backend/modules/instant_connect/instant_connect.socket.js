const crypto = require('crypto');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const { instantConnectService } = require('./instant_connect.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const db = require('../../db');

const AGORA_APP_ID = process.env.AGORA_APP_ID || '';
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE || '';

/**
 * Convert UUID string to 31-bit positive integer Agora UID
 */
function uuidToAgoraUid(uuid) {
  const hash = crypto.createHash('md5').update(uuid || String(Date.now())).digest();
  return hash.readUInt32BE(0) & 0x7fffffff;
}

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
  const appId = process.env.AGORA_APP_ID || AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE || AGORA_APP_CERTIFICATE;

  if (!appId || !appCertificate) {
    return 'test_token_' + Date.now();
  }

  try {
    const role = RtcRole.PUBLISHER;
    const expirationTimeInSeconds = 3600 * 2; // 2 hours
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    return RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      role,
      privilegeExpiredTs
    );
  } catch (err) {
    console.error('Error generating Agora token:', err.message);
    return 'fallback_token_' + Date.now();
  }
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
 * Helper to safely resolve connected socket for a user ID across map and io.sockets
 */
function getSocketForUser(io, targetUserId) {
  if (!io || !targetUserId) return null;
  const socketId = userSockets.get(targetUserId);
  if (socketId) {
    const s = io.sockets?.sockets?.get(socketId);
    if (s && s.connected) return s;
  }
  // Try Socket.io room lookup (users join their userId room on connection)
  const room = io.sockets?.adapter?.rooms?.get(targetUserId);
  if (room && room.size > 0) {
    const firstSocketId = room.values().next().value;
    if (firstSocketId) {
      const s = io.sockets?.sockets?.get(firstSocketId);
      if (s && s.connected) {
        userSockets.set(targetUserId, s.id);
        return s;
      }
    }
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

let matchmakerIntervalStarted = false;
function startMatchmakerTicker(io, redis) {
  if (matchmakerIntervalStarted) return;
  matchmakerIntervalStarted = true;
  setInterval(() => {
    try {
      triggerInstantMatchmaker(io, redis);
    } catch (err) {
      // ignore ticker errors
    }
  }, 2000);
}

/**
 * Trigger Instant Matchmaker cycle
 */
async function triggerInstantMatchmaker(io, redis) {
  if (!io || !redis) return;
  try {
    // 1. Get highest-priority male from queue
    const topMales = await redis.zrevrange('instant:male_queue', 0, 0);
    if (!topMales || topMales.length === 0) return;

    const maleUserId = topMales[0];
    const sessionStr = await redis.get(`instant:male_session:${maleUserId}`);
    if (!sessionStr) {
      // Stale queue entry whose session expired/was deleted -> evict
      await redis.zrem('instant:male_queue', maleUserId);
      return;
    }

    const sessionData = JSON.parse(sessionStr);
    const { sessionId, bidAmount } = sessionData;

    // Check if male is already in an active call -> evict from queue
    const maleInCall = await redis.get(`instant:in_call:${maleUserId}`);
    if (maleInCall) {
      await redis.zrem('instant:male_queue', maleUserId);
      return;
    }

    // Check if male already has an active ringing cycle in progress (waiting for 15s response)
    const activeMaleRequest = await redis.get(`instant:active_request:${maleUserId}`);
    if (activeMaleRequest) {
      return;
    }

    // Verify male socket is still active
    const maleSocket = getSocketForUser(io, maleUserId);
    if (!maleSocket || !maleSocket.connected) {
      const isOnline = await redis.get(`online:${maleUserId}`);
      if (!isOnline) {
        await redis.zrem('instant:male_queue', maleUserId);
        await redis.del(`instant:male_session:${maleUserId}`);
        await instantConnectService.refundEscrowedCoins(maleUserId, bidAmount, sessionId);
        console.log(`🧹 [Instant Matchmaker] Evicted offline male ${maleUserId} from queue and refunded ${bidAmount} coins`);
      }
      return;
    }

    const activeMaleSocketId = maleSocket.id;

    // 2. Fetch available females from DB & Redis pool
    const dbFemales = await db.query(`
      SELECT id FROM public.users
      WHERE incoming_paid_calls_enabled = true
        AND (LOWER(gender) IN ('female', 'girl', 'woman', 'f'))
    `);
    for (const f of dbFemales.rows) {
      await redis.sadd('instant:female_pool', f.id);
    }

    const allFemales = await redis.smembers('instant:female_pool');

    // Filter females who are currently connected, have toggle ON in DB, not busy, and haven't declined this session
    const eligibleFemales = [];
    let anyOnlineFemaleConnected = false;

    for (const femaleId of (allFemales || [])) {
      if (femaleId === maleUserId) continue;

      const fSocket = getSocketForUser(io, femaleId);
      if (fSocket && fSocket.connected) {
        anyOnlineFemaleConnected = true;
      } else {
        continue; // Skip offline females
      }

      // Check if female previously declined this specific male session
      const hasDeclined = await redis.get(`instant:declined:${sessionId}:${femaleId}`);
      if (hasDeclined) continue;

      // Check if female is on temporary snooze (e.g. AFK timeout or recent decline)
      const isSnoozed = await redis.get(`instant:snooze:${femaleId}`);
      if (isSnoozed) continue;

      const isRinging = await redis.get(`instant:ringing:${femaleId}`);
      if (isRinging) continue;
      const inInstantCall = await redis.get(`instant:in_call:${femaleId}`);
      if (inInstantCall) continue;

      let isBusy = socketToInstantCall.has(fSocket.id);
      if (!isBusy) {
        for (const call of activeInstantCalls.values()) {
          if (call.femaleUserId === femaleId || call.maleUserId === femaleId) {
            isBusy = true;
            break;
          }
        }
      }
      if (isBusy) continue;

      eligibleFemales.push({ userId: femaleId, socketId: fSocket.id, socket: fSocket });
    }

    if (eligibleFemales.length === 0) {
      // If ANY female is currently connected online, do NOT spam FCM pushes
      if (anyOnlineFemaleConnected) {
        return;
      }

      // 0 available females on active sockets anywhere -> trigger 1:10 FCM surge (EXACTLY ONCE per session)
      const surgeKey = `instant:surged:${sessionId}`;
      const alreadySurged = await redis.get(surgeKey);
      if (!alreadySurged) {
        await redis.set(surgeKey, '1', 'EX', 300); // 5 min TTL
        const connectedUserIds = Array.from(userSockets.keys());
        const excludeIds = [maleUserId, ...connectedUserIds];
        const offlineFemales = await instantConnectService.getSurgeEligibleFemales(excludeIds, 10);
        if (offlineFemales.length > 0) {
          const tokens = offlineFemales.map((f) => f.fcm_token).filter(Boolean);
          console.log(`📡 [FCM Surge] Dispatching surge alert to ${tokens.length} offline female devices for male ${maleUserId} (Bid: ₹${bidAmount})`);
          if (tokens.length > 0) {
            await sendMulticastPushNotification({
              tokens,
              title: '📞 Incoming VIP Call!',
              body: `A VIP user wants to connect with you. Tap to accept and earn coins!`,
              tag: `instant_${sessionId}`,
              data: {
                type: 'instant_call',
                sessionId: String(sessionId),
                bidAmount: String(bidAmount),
              },
            });
          }
        }
      }
      return;
    }

    // 3. 1 : 2 Dual Ring Dispatch (Select up to 2 random eligible females)
    const shuffled = eligibleFemales.sort(() => 0.5 - Math.random());
    const selectedFemales = shuffled.slice(0, 2);

    const callRequestId = `req_${sessionId}_${Date.now()}`;

    // Mark male in active request lock (expires in 18s) to prevent duplicate triggers
    await redis.set(`instant:active_request:${maleUserId}`, callRequestId, 'EX', 18);

    // Mark females in temporary ringing lock (expires in 18s)
    for (const f of selectedFemales) {
      await redis.set(`instant:ringing:${f.userId}`, callRequestId, 'EX', 18);
      await redis.srem('instant:female_pool', f.userId);
    }

    // Save request metadata in Redis
    const requestMeta = {
      sessionId,
      maleUserId,
      maleSocketId: activeMaleSocketId,
      bidAmount,
      femaleUserIds: selectedFemales.map((f) => f.userId),
      declinedFemaleUserIds: [],
    };
    await redis.set(`instant:request:${callRequestId}`, JSON.stringify(requestMeta), 'EX', 30);

    console.log(`⚡ [Instant Connect] Ringing 1:2 pair (${selectedFemales.map((f) => f.userId).join(', ')}) for male ${maleUserId} (15s timeout)`);

    // Emit incoming call to both female sockets (WITHOUT premature Agora credentials)
    for (const f of selectedFemales) {
      f.socket.emit('incoming_instant_call', {
        callRequestId,
        sessionId,
        bidAmount,
        timeoutSeconds: 15,
      });
    }

    // 4. Set 15-second cascade timer
    const cascadeTimer = setTimeout(async () => {
      ringingTimers.delete(callRequestId);

      // Check if call was already claimed/accepted
      const claimed = await redis.get(`instant:claim_session:${sessionId}`);
      if (claimed) return;

      console.log(`⏰ [Instant Connect] 15s timeout reached for ${callRequestId}. Cascading to next pair...`);
      await redis.del(`instant:active_request:${maleUserId}`);

      // Dismiss ringing on both female sockets and put on 30s temporary snooze
      for (const f of selectedFemales) {
        await redis.del(`instant:ringing:${f.userId}`);
        await redis.set(`instant:snooze:${f.userId}`, '1', 'EX', 30); // 30s AFK snooze
        f.socket.emit('instant_call_dismissed', { callRequestId, reason: 'timeout' });
      }

      // Re-trigger matchmaker to cascade to next available girls
      triggerInstantMatchmaker(io, redis);
    }, 15500);

    ringingTimers.set(callRequestId, cascadeTimer);
  } catch (err) {
    console.error('Error in triggerInstantMatchmaker:', err.message);
  }
}

/**
 * Register Instant Connect Socket.io handlers
 */
function registerInstantConnectHandlers(io, socket, redis) {
  startMatchmakerTicker(io, redis);

  const userId = socket.userId;
  if (userId) {
    userSockets.set(userId, socket.id);
    redis.del(`instant:snooze:${userId}`).catch(() => {});
    redis.del(`instant:ringing:${userId}`).catch(() => {});

    // Auto-register connected female buddies into instant pool if their toggle is ON
    db.query(`SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`, [userId])
      .then((res) => {
        const g = (res.rows[0]?.gender || '').toLowerCase().trim();
        const isF = g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
        if (isF && res.rows[0]?.incoming_paid_calls_enabled === true) {
          redis.sadd('instant:female_pool', userId);
          console.log(`⚡ [Instant Connect] Female ${userId} verified & added to female pool on connect`);
          triggerInstantMatchmaker(io, redis);
        }
      })
      .catch((err) => console.error('Error hydrating female pool on socket connect:', err.message));
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
        JSON.stringify({ sessionId: session.id, bidAmount, socketId: socket.id }),
        'EX',
        600
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
      const requestStr = await redis.get(`instant:request:${callRequestId}`);
      if (!requestStr) {
        cb({ success: false, error: 'REQUEST_EXPIRED', message: 'Call request expired.' });
        return;
      }

      const reqData = JSON.parse(requestStr);
      const { sessionId, maleUserId, maleSocketId, bidAmount, femaleUserIds } = reqData;

      // Atomic SETNX to claim the entire session! (Prevents any second female from connecting)
      const win = await redis.set(`instant:claim_session:${sessionId}`, userId, 'NX', 'EX', 120);

      // Clear ringing cascade timer
      const timer = ringingTimers.get(callRequestId);
      if (timer) {
        clearTimeout(timer);
        ringingTimers.delete(callRequestId);
      }
      await redis.del(`instant:active_request:${maleUserId}`);

      if (win !== 'OK') {
        // Another female won the race or call already active
        cb({ success: false, error: 'ALREADY_CLAIMED', message: 'Another buddy answered this call!' });
        socket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
        return;
      }

      // Winner! Clean up other ringing females immediately
      for (const fId of (femaleUserIds || [])) {
        await redis.del(`instant:ringing:${fId}`);
        if (fId !== userId) {
          const loserSocket = getSocketForUser(io, fId);
          if (loserSocket) {
            loserSocket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
          }
          // Return non-answering girl to pool if still eligible
          await redis.sadd('instant:female_pool', fId);
        }
      }

      // Remove male from queue and active session IMMEDIATELY
      await redis.zrem('instant:male_queue', maleUserId);
      await redis.del(`instant:male_session:${maleUserId}`);

      // Generate UNIQUE Agora channel name and tokens ONLY for the winner and male
      const agoraChannelName = `instant_${sessionId}_${crypto.randomBytes(4).toString('hex')}`;
      const maleUid = uuidToAgoraUid(maleUserId);
      const femaleUid = uuidToAgoraUid(userId);

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);

      // Start call in DB
      await instantConnectService.startCallSession(sessionId, userId, agoraChannelName);

      // Fetch user profile details to reveal to each other ONLY upon acceptance
      let maleUser = {};
      let femaleUser = {};
      try {
        const [maleUserRes, femaleUserRes] = await Promise.all([
          db.query(
            `SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`,
            [maleUserId]
          ),
          db.query(
            `SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`,
            [userId]
          ),
        ]);
        maleUser = maleUserRes.rows[0] || {};
        femaleUser = femaleUserRes.rows[0] || {};
      } catch (userErr) {
        console.error('Error fetching user profiles for instant call:', userErr.message);
      }

      const callId = `instant_call_${sessionId}`;

      // Start 60-second (1-minute) server-authoritative milestone timer
      const milestoneTimer = setTimeout(async () => {
        console.log(`🎉 [Instant Connect] 1-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          const liveMaleSocket = getSocketForUser(io, maleUserId);
          const liveFemaleSocket = getSocketForUser(io, userId);

          if (liveMaleSocket) {
            liveMaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 1,
            });
          }
          if (liveFemaleSocket) {
            liveFemaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 1,
              scratchCardId: scratchCard.id,
              coinReward: scratchCard.coin_reward,
            });
          }
        }
      }, 60 * 1000); // 1 minute

      const activeMaleSocket = getSocketForUser(io, maleUserId) || { id: maleSocketId };

      const activeCallObj = {
        callId,
        sessionId,
        maleUserId,
        maleSocketId: activeMaleSocket.id,
        femaleUserId: userId,
        femaleSocketId: socket.id,
        startedAt: Date.now(),
        bidAmount,
        milestoneTimer,
        agoraChannelName,
      };

      activeInstantCalls.set(callId, activeCallObj);
      socketToInstantCall.set(activeMaleSocket.id, callId);
      socketToInstantCall.set(socket.id, callId);

      // Explicitly lock both users in Redis so neither can be called or matched during the call
      await redis.srem('instant:female_pool', userId);
      await redis.set(`instant:in_call:${userId}`, callId, 'EX', 7200);
      await redis.set(`instant:in_call:${maleUserId}`, callId, 'EX', 7200);
      await redis.set(`call_lock:${userId}`, '1', 'EX', 7200);
      await redis.set(`call_lock:${maleUserId}`, '1', 'EX', 7200);

      const liveAppId = process.env.AGORA_APP_ID || AGORA_APP_ID;

      // Notify Male (revealing female profile)
      if (activeMaleSocket && typeof activeMaleSocket.emit === 'function') {
        activeMaleSocket.emit('instant:call_connected', {
          callId,
          sessionId,
          agoraChannelName,
          agoraToken: maleToken,
          agoraUid: maleUid,
          remoteUid: femaleUid,
          agoraAppId: liveAppId,
          bidAmount,
          otherUserName: femaleUser.full_name || 'VIP Partner',
          matchedUser: {
            id: femaleUser.id || userId,
            fullName: femaleUser.full_name || 'VIP Partner',
            avatarUrl: femaleUser.avatar_seed || null,
            avatarSeed: femaleUser.avatar_seed || null,
            avatarStyle: femaleUser.avatar_style || 'avataaars',
            gender: femaleUser.gender || 'Female',
          },
          durationLimitSeconds: 60,
        });
      } else if (maleUserId) {
        io.to(maleUserId).emit('instant:call_connected', {
          callId,
          sessionId,
          agoraChannelName,
          agoraToken: maleToken,
          agoraUid: maleUid,
          remoteUid: femaleUid,
          agoraAppId: liveAppId,
          bidAmount,
          otherUserName: femaleUser.full_name || 'VIP Partner',
          matchedUser: {
            id: femaleUser.id || userId,
            fullName: femaleUser.full_name || 'VIP Partner',
            avatarUrl: femaleUser.avatar_seed || null,
            avatarSeed: femaleUser.avatar_seed || null,
            avatarStyle: femaleUser.avatar_style || 'avataaars',
            gender: femaleUser.gender || 'Female',
          },
          durationLimitSeconds: 60,
        });
      }

      // Notify Female (revealing male profile)
      socket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: femaleToken,
        agoraUid: femaleUid,
        remoteUid: maleUid,
        agoraAppId: liveAppId,
        bidAmount,
        otherUserName: maleUser.full_name || 'VIP Partner',
        matchedUser: {
          id: maleUser.id || maleUserId,
          fullName: maleUser.full_name || 'VIP Partner',
          avatarUrl: maleUser.avatar_seed || null,
          avatarSeed: maleUser.avatar_seed || null,
          avatarStyle: maleUser.avatar_style || 'avataaars',
          gender: maleUser.gender || 'Male',
        },
        durationLimitSeconds: 60,
      });

      cb({ success: true, callId, sessionId });
    } catch (err) {
      console.error(`Error accepting instant call by ${userId}:`, err);
      cb({ success: false, error: 'SERVER_ERROR', message: err.message });
    }
  });

  // ── 5. instant:decline_call ──────────────────────────────────────────────
  socket.on('instant:decline_call', async (data) => {
    const callRequestId = data?.callRequestId;
    if (!callRequestId) return;

    try {
      await redis.del(`instant:ringing:${userId}`);
      await redis.set(`instant:snooze:${userId}`, '1', 'EX', 20); // 20s cooldown

      const requestStr = await redis.get(`instant:request:${callRequestId}`);
      if (requestStr) {
        const reqData = JSON.parse(requestStr);
        const { sessionId, maleUserId, femaleUserIds } = reqData;
        if (sessionId) {
          // Permanently blacklist this female for this male session (5 mins)
          await redis.set(`instant:declined:${sessionId}:${userId}`, '1', 'EX', 300);
          console.log(`🚫 [Instant Connect] Female ${userId} permanently declined session ${sessionId}`);
        }

        // Track declined female list in request metadata
        const declinedList = reqData.declinedFemaleUserIds || [];
        if (!declinedList.includes(userId)) {
          declinedList.push(userId);
          reqData.declinedFemaleUserIds = declinedList;
          await redis.set(`instant:request:${callRequestId}`, JSON.stringify(reqData), 'EX', 30);
        }

        // If ALL ringing females in this request have declined, cascade immediately!
        if (declinedList.length >= (femaleUserIds || []).length) {
          console.log(`⚡ [Instant Connect] All ringing females declined ${callRequestId}. Cascading to next buddies immediately.`);
          const timer = ringingTimers.get(callRequestId);
          if (timer) {
            clearTimeout(timer);
            ringingTimers.delete(callRequestId);
          }
          await redis.del(`instant:active_request:${maleUserId}`);
          triggerInstantMatchmaker(io, redis);
        }
      }
    } catch (err) {
      console.error(`Error in instant:decline_call for ${userId}:`, err.message);
    }
  });

  // ── 6. instant:end_call ──────────────────────────────────────────────────
  socket.on('instant:end_call', async (data) => {
    try {
      const callId = data?.callId || socketToInstantCall.get(socket.id);
      await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'manual_hangup',
      });
    } catch (err) {
      console.error(`Error ending instant call for ${userId}:`, err.message);
    }
  });

  // ── Disconnect cleanup ───────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    userSockets.delete(userId);
    // Remove from female pool if disconnected
    await redis.srem('instant:female_pool', userId);

    // Clean up waiting male from queue and refund escrowed coins on disconnect
    try {
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);
        await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        console.log(`🧹 [Instant Connect] Cleaned up waiting male ${userId} on disconnect & refunded ${bidAmount} coins`);
      }
    } catch (err) {
      console.error(`Error cleaning up male queue on disconnect for ${userId}:`, err.message);
    }

    try {
      const callId = socketToInstantCall.get(socket.id);
      await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'peer_disconnected',
      });
    } catch (err) {
      console.error(`Error on instant disconnect for ${userId}:`, err.message);
    }
  });
}

/**
 * End an instant connect call session reliably across sockets & database
 */
async function endInstantCallHelper(io, redis, { callId, userId, reason = 'manual_hangup' }) {
  let targetCallId = callId;
  let callObj = targetCallId ? activeInstantCalls.get(targetCallId) : null;

  if (!callObj && userId) {
    for (const [cId, c] of activeInstantCalls.entries()) {
      if (c.maleUserId === userId || c.femaleUserId === userId) {
        callObj = c;
        targetCallId = cId;
        break;
      }
    }
  }

  if (!callObj) return null;

  const durationSeconds = Math.floor((Date.now() - callObj.startedAt) / 1000);

  // Cancel milestone timer if call ends early
  if (callObj.milestoneTimer) {
    clearTimeout(callObj.milestoneTimer);
  }

  const finalStatus = durationSeconds >= 60 ? 'completed' : 'dropped';
  await instantConnectService.endCallSession(callObj.sessionId, finalStatus, durationSeconds);

  const maleSock = userSockets.get(callObj.maleUserId) || callObj.maleSocketId;
  const femaleSock = userSockets.get(callObj.femaleUserId) || callObj.femaleSocketId;

  const endPayload = {
    callId: targetCallId,
    durationSeconds,
    status: finalStatus,
    reason,
  };

  // Notify both parties on both instant:call_ended and call_ended channels (via rooms and direct sockets)
  if (callObj.maleUserId) {
    io.to(callObj.maleUserId).emit('instant:call_ended', endPayload);
    io.to(callObj.maleUserId).emit('call_ended', endPayload);
  }
  if (callObj.femaleUserId) {
    io.to(callObj.femaleUserId).emit('instant:call_ended', endPayload);
    io.to(callObj.femaleUserId).emit('call_ended', endPayload);
  }
  if (maleSock && maleSock !== callObj.maleUserId) {
    io.to(maleSock).emit('instant:call_ended', endPayload);
    io.to(maleSock).emit('call_ended', endPayload);
  }
  if (femaleSock && femaleSock !== callObj.femaleUserId) {
    io.to(femaleSock).emit('instant:call_ended', endPayload);
    io.to(femaleSock).emit('call_ended', endPayload);
  }

  // Cleanup mappings and in-call locks
  socketToInstantCall.delete(callObj.maleSocketId);
  socketToInstantCall.delete(callObj.femaleSocketId);
  if (maleSock) socketToInstantCall.delete(maleSock);
  if (femaleSock) socketToInstantCall.delete(femaleSock);
  activeInstantCalls.delete(targetCallId);

  await redis.del(`instant:in_call:${callObj.femaleUserId}`);
  await redis.del(`instant:in_call:${callObj.maleUserId}`);
  await redis.del(`call_lock:${callObj.femaleUserId}`);
  await redis.del(`call_lock:${callObj.maleUserId}`);

  // Return female to pool if her toggle is still ON
  try {
    const fStatus = await instantConnectService.getFemaleStatus(callObj.femaleUserId);
    if (fStatus.incomingPaidCallsEnabled) {
      await redis.sadd('instant:female_pool', callObj.femaleUserId);
    }
  } catch (_) {}

  return endPayload;
}

/**
 * Forcefully cleanup a user's instant connect queues, female pool, active calls, and refund male escrow upon logout.
 */
async function cleanupUserInstantConnect(io, redis, userId) {
  if (!userId) return;
  try {
    // 1. Remove from female pool and clear locks
    await redis.srem('instant:female_pool', userId);
    await redis.del(`instant:ringing:${userId}`);
    await redis.del(`instant:in_call:${userId}`);
    await redis.del(`call_lock:${userId}`);


    // 2. Clean up waiting male from queue and refund escrowed coins
    const sessionStr = await redis.get(`instant:male_session:${userId}`);
    if (sessionStr) {
      try {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);
        await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        console.log(`🧹 [Instant Connect] Refunded escrow & removed male ${userId} on logout`);
      } catch (err) {
        console.error(`Error refunding male on logout for ${userId}:`, err.message);
      }
    }

    // 3. End any active instant call involving this user
    for (const [callId, c] of activeInstantCalls.entries()) {
      if (c.maleUserId === userId || c.femaleUserId === userId) {
        await endInstantCallHelper(io, redis, {
          callId,
          userId,
          reason: 'logged_out',
        });
      }
    }

    // 4. Remove socket mapping
    userSockets.delete(userId);
    console.log(`🧹 [Instant Connect] Cleaned up instant connect state for user ${userId}`);
  } catch (err) {
    console.error(`Error cleaning up instant connect state for ${userId}:`, err.message);
  }
}

module.exports = {
  registerInstantConnectHandlers,
  activeInstantCalls,
  socketToInstantCall,
  endInstantCallHelper,
  triggerInstantMatchmaker,
  userSockets,
  getSocketForUser,
  cleanupUserInstantConnect,
};

