const crypto = require('crypto');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const { instantConnectService } = require('./instant_connect.service');
const { PresenceService } = require('../presence/presence.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const db = require('../../db');
const redis = require('../../redis');

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
// FCM Surge cascade timers: sessionId -> Timer
const surgeTimers = new Map();
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
      const isOnline = await PresenceService.isUserOnline(redis, maleUserId);
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
    if (dbFemales.rows.length > 0) {
      await redis.sadd('instant:female_pool', ...dbFemales.rows.map((f) => f.id));
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

      // Check if a 30s surge cascade timer is already actively running for this session
      if (surgeTimers.has(sessionId)) {
        return;
      }

      // Check if session was already claimed
      const claimed = await redis.get(`instant:claim_session:${sessionId}`);
      if (claimed) return;

      // 0 available females on active sockets -> trigger next wave of 1:10 FCM surge (different females each wave)
      const notifiedKey = `instant:notified_females:${sessionId}`;
      const alreadyNotifiedIds = (await redis.smembers(notifiedKey)) || [];
      const connectedUserIds = Array.from(userSockets.keys());
      const excludeIds = Array.from(new Set([maleUserId, ...connectedUserIds, ...alreadyNotifiedIds]));

      const offlineFemales = await instantConnectService.getSurgeEligibleFemales(excludeIds, 10);

      // Filter out any females who are currently in an active call
      const availableOfflineFemales = [];
      for (const f of offlineFemales) {
        const inCall = (await redis.get(`instant:in_call:${f.id}`)) || (await redis.get(`call_lock:${f.id}`));
        if (!inCall) {
          availableOfflineFemales.push(f);
        }
      }

      if (availableOfflineFemales.length > 0) {
        // Record these newly notified females in Redis (TTL: 10 minutes)
        await redis.sadd(notifiedKey, ...availableOfflineFemales.map((f) => f.id));
        await redis.expire(notifiedKey, 600);

        const tokens = Array.from(new Set(availableOfflineFemales.map((f) => f.fcm_token).filter(Boolean)));
        console.log(`📡 [FCM Surge Wave] Dispatching surge alert to ${tokens.length} unique offline female devices for male ${maleUserId} (Session: ${sessionId}, Total Notified so far: ${alreadyNotifiedIds.length + availableOfflineFemales.length})`);

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

        // Set 30-second cascade timer: If no female answers within 30s, trigger next wave of 10 different females!
        const surgeTimer = setTimeout(async () => {
          surgeTimers.delete(sessionId);

          // Verify male is still in queue and call is still unclaimed
          const maleInQueue = await redis.zscore('instant:male_queue', maleUserId);
          const isClaimed = await redis.get(`instant:claim_session:${sessionId}`);
          if (!maleInQueue || isClaimed) {
            await redis.del(notifiedKey);
            return;
          }

          console.log(`⏰ [FCM Surge] 30s timeout elapsed without answer for session ${sessionId}. Cascading to next 10 offline females...`);
          triggerInstantMatchmaker(io, redis);
        }, 30000);

        surgeTimers.set(sessionId, surgeTimer);
      } else {
        console.log(`ℹ️ [FCM Surge] No more unnotified offline females available for session ${sessionId}.`);
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
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

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

      // Verify female user has active subscription pass to answer VIP calls
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        console.warn(`🚫 [Instant Connect] Unsubscribed female ${userId} attempted to accept VIP call request ${callRequestId}`);
        cb({
          success: false,
          error: 'SUBSCRIPTION_REQUIRED',
          message: 'An active VIP Subscription Pass is required to answer VIP calls.',
        });
        return;
      }

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

      // Clear surge cascade timer and notified list
      const sTimer = surgeTimers.get(sessionId);
      if (sTimer) {
        clearTimeout(sTimer);
        surgeTimers.delete(sessionId);
      }
      await redis.del(`instant:notified_females:${sessionId}`);

      // Generate UNIQUE Agora channel name and tokens immediately (0ms)
      const agoraChannelName = `instant_${sessionId}_${crypto.randomBytes(4).toString('hex')}`;
      const maleUid = uuidToAgoraUid(maleUserId);
      const femaleUid = uuidToAgoraUid(userId);

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);
      const callId = `instant_call_${sessionId}`;

      // Clean up other ringing females in parallel
      const cleanupPromises = (femaleUserIds || []).map(async (fId) => {
        await redis.del(`instant:ringing:${fId}`);
        if (fId !== userId) {
          const loserSocket = getSocketForUser(io, fId);
          if (loserSocket) {
            loserSocket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
          }
          await redis.sadd('instant:female_pool', fId);
        }
      });

      // Run DB call session start, user profile queries, and Redis in-call locks ALL IN PARALLEL!
      let maleUser = {};
      let femaleUser = {};
      try {
        const [_, [maleUserRes, femaleUserRes]] = await Promise.all([
          instantConnectService.startCallSession(sessionId, userId, agoraChannelName),
          Promise.all([
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [maleUserId]),
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [userId]),
          ]),
          Promise.all(cleanupPromises),
          redis.zrem('instant:male_queue', maleUserId),
          redis.del(`instant:male_session:${maleUserId}`),
          redis.srem('instant:female_pool', userId),
          redis.set(`instant:in_call:${userId}`, callId, 'EX', 7200),
          redis.set(`instant:in_call:${maleUserId}`, callId, 'EX', 7200),
          redis.set(`call_lock:${userId}`, '1', 'EX', 7200),
          redis.set(`call_lock:${maleUserId}`, '1', 'EX', 7200),
        ]);
        maleUser = maleUserRes.rows[0] || {};
        femaleUser = femaleUserRes.rows[0] || {};
      } catch (err) {
        console.error('Error during parallel instant call initialization:', err.message);
      }

      // Start 10-minute (600-second) server-authoritative milestone timer
      const milestoneTimer = setTimeout(async () => {
        console.log(` [Instant Connect] 10-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          const liveMaleSocket = getSocketForUser(io, maleUserId);
          const liveFemaleSocket = getSocketForUser(io, userId);

          if (liveMaleSocket) {
            liveMaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
            });
          }
          if (liveFemaleSocket) {
            liveFemaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
              scratchCardId: scratchCard.id,
              coinReward: scratchCard.coin_reward,
            });
          }
        }
      }, 10 * 60 * 1000); // 10 minutes

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

  // ── 5b. instant:claim_and_join & instant:claim_surge_call (Atomic One-Tap Join from Push) ───
  const handleClaimAndJoin = async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    const sessionId = data?.sessionId;
    if (!sessionId) {
      cb({ success: false, error: 'INVALID_SESSION', message: 'Invalid session ID' });
      return;
    }

    try {
      console.log(`📡 [Instant Connect] Female ${userId} atomically claiming and joining surge session ${sessionId}`);

      // 1. Verify female user eligibility
      const dbRes = await db.query(
        `SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`,
        [userId]
      );
      const userRow = dbRes.rows[0];
      const g = (userRow?.gender || '').toLowerCase().trim();
      const isF = g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
      if (!isF || !userRow?.incoming_paid_calls_enabled) {
        cb({ success: false, error: 'NOT_ELIGIBLE', message: 'Incoming paid calls are disabled on your account.' });
        return;
      }

      // Verify female user has active subscription pass to answer VIP calls
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        console.warn(`🚫 [Instant Connect] Unsubscribed female ${userId} attempted to claim surge VIP session ${sessionId}`);
        cb({
          success: false,
          error: 'SUBSCRIPTION_REQUIRED',
          message: 'An active VIP Subscription Pass is required to answer VIP calls.',
        });
        return;
      }

      // 2. Check if female is already in an active call
      const isCurrentlyInCall = await redis.get(`instant:in_call:${userId}`) || await redis.get(`call_lock:${userId}`);
      if (isCurrentlyInCall) {
        cb({ success: false, error: 'ALREADY_IN_CALL', message: 'You are currently in another call.' });
        return;
      }

      // 3. Verify session in DB (must still be waiting / queued)
      const sessRes = await db.query(
        `SELECT * FROM public.instant_call_sessions WHERE id = $1 AND status IN ('queued', 'waiting')`,
        [sessionId]
      );
      if (sessRes.rows.length === 0) {
        cb({ success: false, error: 'SESSION_EXPIRED', message: 'Another buddy already answered this VIP call.' });
        return;
      }

      const session = sessRes.rows[0];
      const maleUserId = session.male_user_id;

      // 4. Atomic Concurrency Lock: First female to acquire this lock wins the call
      const claimKey = `instant:claimed:${sessionId}`;
      const claimAcquired = await redis.set(claimKey, userId, 'EX', 120, 'NX');
      if (!claimAcquired) {
        const winnerId = await redis.get(claimKey);
        if (winnerId !== userId) {
          console.log(`⏱️ [Instant Connect] Female ${userId} lost race condition for session ${sessionId} to winner ${winnerId}`);
          cb({ success: false, error: 'ALREADY_CLAIMED', message: 'Another buddy already answered this VIP call.' });
          return;
        }
      }

      // 5. Verify male socket is still active and connected
      const maleSocket = getSocketForUser(io, maleUserId);
      if (!maleSocket || !maleSocket.connected) {
        await redis.del(claimKey);
        cb({ success: false, error: 'MALE_DISCONNECTED', message: 'The caller is no longer connected.' });
        return;
      }

      // 6. Clean up any other active ring requests/timers for this male or session
      const activeReqId = await redis.get(`instant:active_request:${maleUserId}`);
      if (activeReqId) {
        const timer = ringingTimers.get(activeReqId);
        if (timer) {
          clearTimeout(timer);
          ringingTimers.delete(activeReqId);
        }
        const reqDataStr = await redis.get(`instant:request:${activeReqId}`);
        if (reqDataStr) {
          try {
            const reqData = JSON.parse(reqDataStr);
            for (const fId of (reqData.femaleUserIds || [])) {
              await redis.del(`instant:ringing:${fId}`);
              if (fId !== userId) {
                const loserSocket = getSocketForUser(io, fId);
                if (loserSocket) {
                  loserSocket.emit('instant_call_dismissed', { callRequestId: activeReqId, reason: 'already_answered' });
                }
              }
            }
          } catch (_) {}
        }
        await redis.del(`instant:request:${activeReqId}`);
        await redis.del(`instant:active_request:${maleUserId}`);
      }

      await redis.del(`instant:snooze:${userId}`);
      await redis.del(`instant:ringing:${userId}`);

      // 7. Remove male from queue and active session, cancel surge timer
      await redis.zrem('instant:male_queue', maleUserId);
      await redis.del(`instant:male_session:${maleUserId}`);
      await redis.del(`instant:notified_females:${sessionId}`);

      const sTimer = surgeTimers.get(sessionId);
      if (sTimer) {
        clearTimeout(sTimer);
        surgeTimers.delete(sessionId);
      }

      // 8. Generate Agora Channel Name and unique tokens for both parties immediately (0ms)
      const agoraChannelName = `instant_${sessionId}_${crypto.randomBytes(4).toString('hex')}`;
      const maleUid = uuidToAgoraUid(maleUserId);
      const femaleUid = uuidToAgoraUid(userId);

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);
      const callId = `instant_call_${sessionId}`;

      // 9 & 10 & 12. Run DB call session start, user profile queries, and Redis in-call locks ALL IN PARALLEL!
      let maleUser = {};
      let femaleUser = {};
      try {
        const [_, [maleUserRes, femaleUserRes]] = await Promise.all([
          instantConnectService.startCallSession(sessionId, userId, agoraChannelName),
          Promise.all([
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [maleUserId]),
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [userId]),
          ]),
          redis.srem('instant:female_pool', userId),
          redis.set(`instant:in_call:${userId}`, callId, 'EX', 7200),
          redis.set(`instant:in_call:${maleUserId}`, callId, 'EX', 7200),
          redis.set(`call_lock:${userId}`, '1', 'EX', 7200),
          redis.set(`call_lock:${maleUserId}`, '1', 'EX', 7200),
        ]);
        maleUser = maleUserRes.rows[0] || {};
        femaleUser = femaleUserRes.rows[0] || {};
      } catch (userErr) {
        console.error('Error in parallel instant claim initialization:', userErr.message);
      }

      // 11. Start 10-minute milestone timer for scratch card reward (600 seconds)
      const milestoneTimer = setTimeout(async () => {
        console.log(` [Instant Connect] 10-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          const liveMaleSocket = getSocketForUser(io, maleUserId);
          const liveFemaleSocket = getSocketForUser(io, userId);

          if (liveMaleSocket) {
            liveMaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
            });
          }
          if (liveFemaleSocket) {
            liveFemaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
              scratchCardId: scratchCard.id,
              coinReward: scratchCard.coin_reward,
            });
          }
        }
      }, 10 * 60 * 1000);

      const activeMaleSocket = maleSocket;

      const activeCallObj = {
        callId,
        sessionId,
        maleUserId,
        maleSocketId: activeMaleSocket.id,
        femaleUserId: userId,
        femaleSocketId: socket.id,
        startedAt: Date.now(),
        bidAmount: session.bid_amount,
        milestoneTimer,
        agoraChannelName,
      };

      activeInstantCalls.set(callId, activeCallObj);
      socketToInstantCall.set(activeMaleSocket.id, callId);
      socketToInstantCall.set(socket.id, callId);

      const liveAppId = process.env.AGORA_APP_ID || AGORA_APP_ID;

      // 13. Direct Agora RTC Connection dispatch to Male
      activeMaleSocket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: maleToken,
        agoraUid: maleUid,
        remoteUid: femaleUid,
        agoraAppId: liveAppId,
        bidAmount: session.bid_amount,
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

      // 14. Direct Agora RTC Connection dispatch to Female
      socket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: femaleToken,
        agoraUid: femaleUid,
        remoteUid: maleUid,
        agoraAppId: liveAppId,
        bidAmount: session.bid_amount,
        otherUserName: maleUser.full_name || 'VIP User',
        matchedUser: {
          id: maleUser.id || maleUserId,
          fullName: maleUser.full_name || 'VIP User',
          avatarUrl: maleUser.avatar_seed || null,
          avatarSeed: maleUser.avatar_seed || null,
          avatarStyle: maleUser.avatar_style || 'avataaars',
          gender: maleUser.gender || 'Male',
        },
        durationLimitSeconds: 60,
      });

      console.log(`🚀 [Instant Connect] Instant one-tap VIP call connected: Session ${sessionId} (Male ${maleUserId} <-> Female ${userId})`);
      cb({ success: true, callId });
    } catch (err) {
      console.error(`❌ [Instant Connect] Error in handleClaimAndJoin for ${userId}:`, err.message);

      // 1. Release atomic Redis claim lock immediately if held by this user
      const claimKey = `instant:claimed:${sessionId}`;
      try {
        const winner = await redis.get(claimKey);
        if (winner === userId) {
          await redis.del(claimKey);
        }
      } catch (_) {}

      // 2. If DB status was already mutated to in_call before failure, rollback session to 'waiting'
      try {
        const checkRes = await db.query(
          `SELECT status FROM public.instant_call_sessions WHERE id = $1`,
          [sessionId]
        );
        if (checkRes.rows.length > 0 && checkRes.rows[0].status === 'in_call') {
          await db.query(
            `UPDATE public.instant_call_sessions 
             SET status = 'waiting', female_user_id = NULL, agora_channel_name = NULL, started_at = NULL 
             WHERE id = $1`,
            [sessionId]
          );
          console.log(`🔄 [Instant Connect] Successfully rolled back session ${sessionId} status to 'waiting'`);
        }
      } catch (dbErr) {
        console.error('Error rolling back DB session status on claim failure:', dbErr.message);
      }

      // 3. Clean up any partial in-call Redis locks
      try {
        await redis.del(`instant:in_call:${userId}`);
        await redis.del(`call_lock:${userId}`);
      } catch (_) {}

      cb({ success: false, error: 'SERVER_ERROR', message: 'Failed to join VIP call.' });
    }
  };

  socket.on('instant:claim_and_join', handleClaimAndJoin);
  socket.on('instant:claim_surge_call', handleClaimAndJoin);

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
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

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
  const maleSock = userSockets.get(callObj.maleUserId) || callObj.maleSocketId;
  const femaleSock = userSockets.get(callObj.femaleUserId) || callObj.femaleSocketId;

  const endPayload = {
    callId: targetCallId,
    durationSeconds,
    status: finalStatus,
    reason,
  };

  // 1. Instantly notify both parties at 0ms!
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

  // 2. Cleanup mappings and in-call locks immediately
  socketToInstantCall.delete(callObj.maleSocketId);
  socketToInstantCall.delete(callObj.femaleSocketId);
  if (maleSock) socketToInstantCall.delete(maleSock);
  if (femaleSock) socketToInstantCall.delete(femaleSock);
  activeInstantCalls.delete(targetCallId);

  // 3. Perform database operations, refunds, and Redis pool updates in background
  (async () => {
    try {
      await instantConnectService.endCallSession(callObj.sessionId, finalStatus, durationSeconds);

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

      // Refund male escrow if call dropped or aborted before 1-minute milestone
      if (finalStatus === 'dropped' && callObj.maleUserId && callObj.bidAmount) {
        try {
          await instantConnectService.refundEscrowedCoins(callObj.maleUserId, callObj.bidAmount, callObj.sessionId);
          console.log(`💰 [Instant Connect] Refunded ${callObj.bidAmount} escrowed coins to male ${callObj.maleUserId} for dropped/failed session ${callObj.sessionId}`);
        } catch (refundErr) {
          console.error('Error refunding male on dropped instant call:', refundErr.message);
        }
      }
    } catch (err) {
      console.error('Error in post-instant-call background processing:', err.message);
    }
  })();

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
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

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

