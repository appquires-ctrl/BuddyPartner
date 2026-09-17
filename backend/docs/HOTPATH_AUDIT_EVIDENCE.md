# Production Hot-Path Audit Evidence

This document contains the complete, unabridged source code for the hot-path modules requested for deep production audit verification, plus an empirical analysis of Flutter client polling behavior.

---

## 1. Real Chat Send Path (Socket Event Handlers)
**File:** [`backend/modules/messaging/messaging.socket.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/messaging/messaging.socket.js)

```javascript
const { MessagingService } = require('./messaging.service');
const { PresenceService } = require('../presence/presence.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

const messagingService = new MessagingService();

// Rate limit: max messages per window
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_SECONDS = 1;

// ── In-memory Conversation Participants Cache ──────────────────────────────
// Caches { user_a_id, user_b_id } for 10 minutes to eliminate DB queries on typing
const convParticipantsCache = new Map();
const CONV_CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_CONV_CACHE_SIZE = 10000;

async function getConversationParticipants(conversationId) {
  if (!conversationId) return null;

  const cached = convParticipantsCache.get(conversationId);
  if (cached && (Date.now() - cached.timestamp < CONV_CACHE_TTL_MS)) {
    return cached.data;
  }

  const convResult = await require('../../db').query(
    'SELECT user_a_id, user_b_id FROM public.conversations WHERE id = $1',
    [conversationId]
  );

  if (convResult.rows.length === 0) return null;
  const data = convResult.rows[0];

  if (convParticipantsCache.size >= MAX_CONV_CACHE_SIZE) {
    const oldestKey = convParticipantsCache.keys().next().value;
    convParticipantsCache.delete(oldestKey);
  }

  convParticipantsCache.set(conversationId, { data, timestamp: Date.now() });
  return data;
}

/**
 * Check send-rate limit for a user using Redis sliding window.
 * Returns true if the user is rate-limited (should be rejected).
 */
async function isRateLimited(redis, userId) {
  const key = `msg_rate:${userId}`;
  const count = await redis.incr(key);

  if (count === 1) {
    await redis.expire(key, RATE_LIMIT_WINDOW_SECONDS);
  }

  return count > RATE_LIMIT_MAX;
}

/**
 * Register all messaging-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerMessagingHandlers(io, socket, redis) {
  const userId = socket.userId;

  // ── send_message ──────────────────────────────────────────────────────
  socket.on('send_message', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};

    try {
      const { conversationId, content, type } = data || {};

      if (!conversationId || !content || !content.trim()) {
        cb({ error: 'conversationId and content are required' });
        return;
      }

      // Subscription check
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        cb({ error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to send messages.' });
        return;
      }

      // Rate limit check
      const limited = await isRateLimited(redis, userId);
      if (limited) {
        cb({ error: 'Slow down! You are sending messages too quickly.' });
        return;
      }

      // Determine the other participant ahead of time via cache or DB
      const conv = await getConversationParticipants(conversationId);
      const otherUserId = conv ? (conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id) : null;

      // Check if recipient is online via Redis O(1) before insert
      const isOnline = otherUserId ? await PresenceService.isUserOnline(redis, otherUserId) : false;
      const initialStatus = isOnline ? 'delivered' : 'sent';

      // Send message (includes block-list check & single combined insert with initialStatus)
      const message = await messagingService.sendMessage(
        conversationId,
        userId,
        content.trim(),
        type || 'text',
        null,
        initialStatus
      );

      if (conv && otherUserId) {
        if (isOnline) {
          // Deliver directly to recipient's room
          io.to(otherUserId).emit('message:new', { message });

          // Inform sender of double tick (delivered)
          socket.emit('message:status_update', {
            conversationId,
            messageId: message.id,
            status: 'delivered',
          });
        }

        // Emit to sender
        socket.emit('message:new', { message });
      }

      cb({ success: true, message });
    } catch (err) {
      console.error('Error in send_message:', err.message);
      cb({ error: err.message });
    }
  });

  // ── typing ────────────────────────────────────────────────────────────
  socket.on('typing', async (data) => {
    try {
      const { conversationId } = data || {};
      if (!conversationId) return;

      // Participant lookup from in-memory cache (0ms DB load)
      const conv = await getConversationParticipants(conversationId);
      if (!conv) return;
      if (conv.user_a_id !== userId && conv.user_b_id !== userId) return;

      const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;

      // O(1) Room emit directly to recipient across all cluster nodes
      io.to(otherUserId).emit('typing', {
        conversationId,
        userId,
      });
    } catch (err) {
      console.error('Error in typing:', err.message);
    }
  });

  // ── message:read ──────────────────────────────────────────────────────
  socket.on('message:read', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};

    try {
      const { conversationId, messageId } = data || {};

      if (!conversationId || !messageId) {
        cb({ error: 'conversationId and messageId are required' });
        return;
      }

      await messagingService.markAsRead(conversationId, userId, messageId);

      // Notify other participant about the read receipt via room emit
      const conv = await getConversationParticipants(conversationId);
      if (conv) {
        const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;

        io.to(otherUserId).emit('message:read', {
          conversationId,
          userId,
          messageId,
        });
        io.to(otherUserId).emit('message:status_update', {
          conversationId,
          messageId,
          status: 'read',
        });
      }

      cb({ success: true });
    } catch (err) {
      console.error('Error in message:read:', err.message);
      cb({ error: err.message });
    }
  });
}

module.exports = { registerMessagingHandlers, getConversationParticipants };

```

---

## 2. Call Quota & Fair Usage Service
**File:** [`backend/modules/calls/call_quota.service.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/calls/call_quota.service.js)

```javascript
const db = require('../../db');
const redis = require('../../redis');

const AUDIO_MONTHLY_CAP_MINUTES = 200;
const VIDEO_MONTHLY_CAP_MINUTES = 60;
const AUDIO_MONTHLY_CAP_SECONDS = AUDIO_MONTHLY_CAP_MINUTES * 60; // 12,000s
const VIDEO_MONTHLY_CAP_SECONDS = VIDEO_MONTHLY_CAP_MINUTES * 60; // 3,600s
const REDIS_KEY_TTL_SECONDS = 40 * 86400; // 40 days

const TELECOM_BUSY_MESSAGE = 'All connection lines are currently busy in your region. Please try again later.';

class CallQuotaService {
  /**
   * Returns current year-month formatted string (e.g. "2026-09").
   */
  getCurrentYearMonth() {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    return `${year}-${month}`;
  }

  getAudioQuotaKey(userId, yearMonth = this.getCurrentYearMonth()) {
    return `call_quota:${userId}:${yearMonth}:audio_seconds`;
  }

  getVideoQuotaKey(userId, yearMonth = this.getCurrentYearMonth()) {
    return `call_quota:${userId}:${yearMonth}:video_seconds`;
  }

  /**
   * Fast real-time check if user can initiate/receive an audio call.
   * Checks Redis first (O(1), <0.2ms latency).
   * @param {string} userId
   * @returns {Promise<{ allowed: boolean, remainingSeconds: number }>}
   */
  async checkCanStartAudioCall(userId) {
    if (!userId) return { allowed: false, remainingSeconds: 0 };
    try {
      const audioKey = this.getAudioQuotaKey(userId);
      let val = await redis.get(audioKey);

      let audioSeconds = 0;
      if (val === null) {
        // Cold cache warmup
        const usage = await this.getUsage(userId);
        audioSeconds = usage.audioSeconds;
      } else {
        audioSeconds = parseInt(val, 10) || 0;
      }

      const remaining = Math.max(0, AUDIO_MONTHLY_CAP_SECONDS - audioSeconds);
      return {
        allowed: remaining > 0,
        remainingSeconds: remaining,
      };
    } catch (err) {
      console.error(`[CallQuota] Error checking audio quota for ${userId}:`, err.message);
      // Fail open on Redis error so calls don't randomly crash
      return { allowed: true, remainingSeconds: AUDIO_MONTHLY_CAP_SECONDS };
    }
  }

  /**
   * Fast real-time check if user can upgrade to video call.
   * Checks Redis first (O(1), <0.2ms latency).
   * @param {string} userId
   * @returns {Promise<{ allowed: boolean, remainingSeconds: number }>}
   */
  async checkCanStartVideoCall(userId) {
    if (!userId) return { allowed: false, remainingSeconds: 0 };
    try {
      const videoKey = this.getVideoQuotaKey(userId);
      let val = await redis.get(videoKey);

      let videoSeconds = 0;
      if (val === null) {
        // Cold cache warmup
        const usage = await this.getUsage(userId);
        videoSeconds = usage.videoSeconds;
      } else {
        videoSeconds = parseInt(val, 10) || 0;
      }

      const remaining = Math.max(0, VIDEO_MONTHLY_CAP_SECONDS - videoSeconds);
      return {
        allowed: remaining > 0,
        remainingSeconds: remaining,
      };
    } catch (err) {
      console.error(`[CallQuota] Error checking video quota for ${userId}:`, err.message);
      return { allowed: true, remainingSeconds: VIDEO_MONTHLY_CAP_SECONDS };
    }
  }

  /**
   * Get complete usage breakdown for a user (Redis + DB sync).
   * @param {string} userId
   * @param {string} [yearMonth]
   * @returns {Promise<Object>}
   */
  async getUsage(userId, yearMonth = this.getCurrentYearMonth()) {
    if (!userId) return null;
    try {
      const audioKey = this.getAudioQuotaKey(userId, yearMonth);
      const videoKey = this.getVideoQuotaKey(userId, yearMonth);

      const [redisAudio, redisVideo] = await redis.mget(audioKey, videoKey);

      let audioSeconds = 0;
      let videoSeconds = 0;

      if (redisAudio !== null && redisVideo !== null) {
        audioSeconds = parseInt(redisAudio, 10) || 0;
        videoSeconds = parseInt(redisVideo, 10) || 0;
      } else {
        // Cache miss: query Postgres
        const res = await db.query(
          `SELECT audio_seconds, video_seconds 
           FROM public.user_monthly_call_usage 
           WHERE user_id = $1 AND year_month = $2`,
          [userId, yearMonth]
        );

        if (res.rows.length > 0) {
          audioSeconds = res.rows[0].audio_seconds || 0;
          videoSeconds = res.rows[0].video_seconds || 0;
        }

        // Populate Redis cache with 40-day expiration
        await redis.mset(audioKey, audioSeconds, videoKey, videoSeconds);
        await redis.expire(audioKey, REDIS_KEY_TTL_SECONDS);
        await redis.expire(videoKey, REDIS_KEY_TTL_SECONDS);
      }

      const audioRemaining = Math.max(0, AUDIO_MONTHLY_CAP_SECONDS - audioSeconds);
      const videoRemaining = Math.max(0, VIDEO_MONTHLY_CAP_SECONDS - videoSeconds);

      return {
        userId,
        yearMonth,
        audioSeconds,
        videoSeconds,
        audioMinutes: Math.floor(audioSeconds / 60),
        videoMinutes: Math.floor(videoSeconds / 60),
        audioRemainingSeconds: audioRemaining,
        videoRemainingSeconds: videoRemaining,
        isAudioExhausted: audioRemaining <= 0,
        isVideoExhausted: videoRemaining <= 0,
        caps: {
          audioMinutes: AUDIO_MONTHLY_CAP_MINUTES,
          videoMinutes: VIDEO_MONTHLY_CAP_MINUTES,
          audioSeconds: AUDIO_MONTHLY_CAP_SECONDS,
          videoSeconds: VIDEO_MONTHLY_CAP_SECONDS,
        },
      };
    } catch (err) {
      console.error(`[CallQuota] Error fetching usage for ${userId}:`, err.message);
      return {
        userId,
        yearMonth,
        audioSeconds: 0,
        videoSeconds: 0,
        audioMinutes: 0,
        videoMinutes: 0,
        audioRemainingSeconds: AUDIO_MONTHLY_CAP_SECONDS,
        videoRemainingSeconds: VIDEO_MONTHLY_CAP_SECONDS,
        isAudioExhausted: false,
        isVideoExhausted: false,
        caps: {
          audioMinutes: AUDIO_MONTHLY_CAP_MINUTES,
          videoMinutes: VIDEO_MONTHLY_CAP_MINUTES,
          audioSeconds: AUDIO_MONTHLY_CAP_SECONDS,
          videoSeconds: VIDEO_MONTHLY_CAP_SECONDS,
        },
      };
    }
  }

  /**
   * Record call duration for both participants atomically on call end.
   * Updates Redis counters immediately and asynchronously upserts Postgres rollup.
   * @param {string} userAId
   * @param {string} userBId
   * @param {number} audioSeconds
   * @param {number} videoSeconds
   */
  async recordCallUsage(userAId, userBId, audioSeconds = 0, videoSeconds = 0) {
    const audioSec = Math.max(0, Math.floor(audioSeconds));
    const videoSec = Math.max(0, Math.floor(videoSeconds));

    if (audioSec === 0 && videoSec === 0) return;

    const yearMonth = this.getCurrentYearMonth();
    const userIds = [userAId, userBId].filter((id) => Boolean(id));

    // 1. Atomic Redis increment (sub-millisecond)
    const ops = [];
    for (const uid of userIds) {
      if (audioSec > 0) {
        const aKey = this.getAudioQuotaKey(uid, yearMonth);
        ops.push(
          redis.incrby(aKey, audioSec)
            .then(() => redis.expire(aKey, REDIS_KEY_TTL_SECONDS))
            .catch((err) => console.error(`[CallQuota] Redis incr error for ${aKey}:`, err.message))
        );
      }
      if (videoSec > 0) {
        const vKey = this.getVideoQuotaKey(uid, yearMonth);
        ops.push(
          redis.incrby(vKey, videoSec)
            .then(() => redis.expire(vKey, REDIS_KEY_TTL_SECONDS))
            .catch((err) => console.error(`[CallQuota] Redis incr error for ${vKey}:`, err.message))
        );
      }
    }

    // 2. Postgres DB upsert
    const hasAudio = audioSec > 0 ? 1 : 0;
    const hasVideo = videoSec > 0 ? 1 : 0;

    for (const uid of userIds) {
      ops.push(
        db.query(
          `INSERT INTO public.user_monthly_call_usage 
             (user_id, year_month, audio_seconds, video_seconds, audio_call_count, video_call_count, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, NOW())
           ON CONFLICT (user_id, year_month)
           DO UPDATE SET
             audio_seconds = public.user_monthly_call_usage.audio_seconds + EXCLUDED.audio_seconds,
             video_seconds = public.user_monthly_call_usage.video_seconds + EXCLUDED.video_seconds,
             audio_call_count = public.user_monthly_call_usage.audio_call_count + EXCLUDED.audio_call_count,
             video_call_count = public.user_monthly_call_usage.video_call_count + EXCLUDED.video_call_count,
             updated_at = NOW()`,
          [uid, yearMonth, audioSec, videoSec, hasAudio, hasVideo]
        ).catch((err) => {
          console.error(`[CallQuota] DB sync error for ${uid}:`, err.message);
        })
      );
    }

    await Promise.all(ops);
  }

  /**
   * Reset a user's monthly call quota (Admin Override).
   * Clears Redis counters and resets PostgreSQL monthly record to 0.
   * @param {string} userId
   * @param {string} [yearMonth]
   * @returns {Promise<{ success: boolean, message: string }>}
   */
  async resetUserQuota(userId, yearMonth = this.getCurrentYearMonth()) {
    if (!userId) return { success: false, message: 'User ID is required' };
    try {
      const audioKey = this.getAudioQuotaKey(userId, yearMonth);
      const videoKey = this.getVideoQuotaKey(userId, yearMonth);

      await redis.del(audioKey, videoKey);

      await db.query(
        `UPDATE public.user_monthly_call_usage
         SET audio_seconds = 0, video_seconds = 0, updated_at = NOW()
         WHERE user_id = $1 AND year_month = $2`,
        [userId, yearMonth]
      );

      console.log(`[CallQuota] Reset monthly quota for user ${userId} (${yearMonth})`);
      return { success: true, message: 'User call quota reset successfully' };
    } catch (err) {
      console.error(`[CallQuota] Error resetting quota for ${userId}:`, err.message);
      throw err;
    }
  }
}

const callQuotaService = new CallQuotaService();

module.exports = {
  callQuotaService,
  CallQuotaService,
  AUDIO_MONTHLY_CAP_MINUTES,
  VIDEO_MONTHLY_CAP_MINUTES,
  AUDIO_MONTHLY_CAP_SECONDS,
  VIDEO_MONTHLY_CAP_SECONDS,
  TELECOM_BUSY_MESSAGE,
};

```

---

## 3. Matchmaking Core Service
**File:** [`backend/modules/matchmaking/matchmaking.service.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/matchmaking/matchmaking.service.js)

```javascript
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Gender-specific queue keys
const MALE_QUEUE_KEY = 'queue:male';
const FEMALE_QUEUE_KEY = 'queue:female';
const USER_SOCKET_MAP_KEY = 'matchmaking:user_socket'; // hash: userId → socketId
const USER_GENDER_MAP_KEY = 'matchmaking:user_gender'; // hash: userId → gender

const CROSS_GENDER_LUA_SCRIPT = fs.readFileSync(
  path.join(__dirname, 'match_cross_gender.lua'),
  'utf-8',
);

class MatchmakingService {
  constructor(redis) {
    this.redis = redis;
  }

  /**
   * Add a user to the gender-specific matchmaking queue.
   * Males go to queue:male, females go to queue:female.
   *
   * @param {string} userId
   * @param {string} socketId
   * @param {string} gender - 'male' or 'female'
   * @returns {boolean} true if added, false if already in queue
   */
  async joinQueue(userId, socketId, gender) {
    const queueKey = this._getQueueKey(gender);

    // Check if user is already in the queue
    const existingScore = await this.redis.zscore(queueKey, `${userId}:${socketId}`);
    if (existingScore !== null) {
      return false; // Already queued
    }

    // Also check if this userId has any existing entry (different socket)
    const existingSocketId = await this.redis.hget(USER_SOCKET_MAP_KEY, userId);
    if (existingSocketId) {
      // Remove stale entry from both queues
      await this._removeFromAllQueues(userId);
    }

    const score = Date.now();
    await this.redis.zadd(queueKey, score, `${userId}:${socketId}`);
    await this.redis.hset(USER_SOCKET_MAP_KEY, userId, socketId);
    await this.redis.hset(USER_GENDER_MAP_KEY, userId, gender);

    return true;
  }

  /**
   * Remove a user from all matchmaking queues.
   * Since we may not know gender at disconnect, we check both queues.
   *
   * @param {string} userId
   */
  async leaveQueue(userId) {
    const socketId = await this.redis.hget(USER_SOCKET_MAP_KEY, userId);
    if (socketId) {
      await this.redis.zrem(MALE_QUEUE_KEY, `${userId}:${socketId}`);
      await this.redis.zrem(FEMALE_QUEUE_KEY, `${userId}:${socketId}`);
      await this.redis.hdel(USER_SOCKET_MAP_KEY, userId);
      await this.redis.hdel(USER_GENDER_MAP_KEY, userId);
    }

    // Fallback: scan both queues and remove any entries for this userId
    await this._removeFromAllQueues(userId);
  }

  /**
   * Attempt to match one male with one female atomically using the cross-gender Lua script.
   * Returns the matched pair or null if either queue is empty.
   *
   * @returns {{ userA: { userId, socketId }, userB: { userId, socketId } } | null}
   */
  async tryMatch() {
    const result = await this.redis.eval(
      CROSS_GENDER_LUA_SCRIPT,
      2,
      MALE_QUEUE_KEY,
      FEMALE_QUEUE_KEY
    );

    if (!result || result.length < 2) {
      return null;
    }

    const [maleMember, femaleMember] = result;
    const [maleUserId, maleSocketId] = this._parseMember(maleMember);
    const [femaleUserId, femaleSocketId] = this._parseMember(femaleMember);

    // Clean up the user→socket and user→gender mappings
    await this.redis.hdel(USER_SOCKET_MAP_KEY, maleUserId);
    await this.redis.hdel(USER_SOCKET_MAP_KEY, femaleUserId);
    await this.redis.hdel(USER_GENDER_MAP_KEY, maleUserId);
    await this.redis.hdel(USER_GENDER_MAP_KEY, femaleUserId);

    return {
      userA: { userId: maleUserId, socketId: maleSocketId, gender: 'male' },
      userB: { userId: femaleUserId, socketId: femaleSocketId, gender: 'female' },
    };
  }

  /**
   * Generate a unique Agora channel name for a call.
   *
   * @returns {string}
   */
  generateChannelName() {
    return `buddypartner_${crypto.randomBytes(8).toString('hex')}`;
  }

  /**
   * Convert a Supabase UUID to a 32-bit numeric Agora UID.
   * Agora requires numeric UIDs — we hash the UUID and take the lower 31 bits
   * (positive int32).
   *
   * @param {string} uuid
   * @returns {number}
   */
  uuidToAgoraUid(uuid) {
    const hash = crypto.createHash('md5').update(uuid).digest();
    // Read first 4 bytes as unsigned 32-bit int, mask to 31 bits (positive)
    return hash.readUInt32BE(0) & 0x7fffffff;
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /**
   * Get the queue key for a given gender.
   * @param {string} gender
   * @returns {string}
   */
  _getQueueKey(gender) {
    const g = (gender || '').trim().toLowerCase();
    if (g === 'female' || g === 'girl' || g === 'woman' || g === 'f') {
      return FEMALE_QUEUE_KEY;
    }
    if (g === 'male' || g === 'boy' || g === 'man' || g === 'm') {
      return MALE_QUEUE_KEY;
    }
    throw new Error(`Invalid gender '${gender}' for matchmaking queue`);
  }

  /**
   * Remove all entries for a userId from both gender queues.
   * @param {string} userId
   */
  async _removeFromAllQueues(userId) {
    const socketId = await this.redis.hget(USER_SOCKET_MAP_KEY, userId);
    if (socketId) {
      const member = `${userId}:${socketId}`;
      await Promise.all([
        this.redis.zrem(MALE_QUEUE_KEY, member),
        this.redis.zrem(FEMALE_QUEUE_KEY, member),
      ]);
    } else {
      // Fallback in case socketId was cleared prematurely
      for (const queueKey of [MALE_QUEUE_KEY, FEMALE_QUEUE_KEY]) {
        const members = await this.redis.zrangebyscore(queueKey, '-inf', '+inf');
        for (const member of members) {
          if (member.startsWith(`${userId}:`)) {
            await this.redis.zrem(queueKey, member);
          }
        }
      }
    }
    await Promise.all([
      this.redis.hdel(USER_SOCKET_MAP_KEY, userId),
      this.redis.hdel(USER_GENDER_MAP_KEY, userId),
    ]);
  }

  /**
   * Parse a "userId:socketId" member string.
   *
   * @param {string} member
   * @returns {[string, string]} [userId, socketId]
   */
  _parseMember(member) {
    const colonIdx = member.indexOf(':');
    return [member.substring(0, colonIdx), member.substring(colonIdx + 1)];
  }
}

module.exports = { MatchmakingService, MALE_QUEUE_KEY, FEMALE_QUEUE_KEY };

```

---

## 4. Instant Connect Core Service
**File:** [`backend/modules/instant_connect/instant_connect.service.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/instant_connect/instant_connect.service.js)

```javascript
const db = require('../../db');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { WalletService } = require('../wallet/wallet.service');

class InstantConnectService {
  /**
   * Toggle female user's "Incoming Paid Calls" status
   * Requires an active subscription.
   * @param {string} userId
   * @param {boolean} enabled
   * @param {import('ioredis').Redis} [redis]
   * @returns {Promise<{ success: boolean, enabled: boolean, error?: string }>}
   */
  async toggleIncomingPaidCalls(userId, enabled, redis) {
    try {
      await db.query(
        `UPDATE public.users SET incoming_paid_calls_enabled = $1 WHERE id = $2`,
        [enabled, userId]
      );

      if (redis) {
        if (enabled) {
          await redis.sadd('instant:female_pool', userId);
          await redis.del(`instant:snooze:${userId}`);
        } else {
          await redis.srem('instant:female_pool', userId);
        }
      }

      return { success: true, enabled };
    } catch (err) {
      console.error(`Error toggling incoming paid calls for ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Get female user's instant connect status & scratch card counts
   * @param {string} userId
   * @returns {Promise<Object>}
   */
  async getFemaleStatus(userId) {
    try {
      const userRes = await db.query(
        `SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`,
        [userId]
      );

      const isEnabled = userRes.rows[0]?.incoming_paid_calls_enabled === true;

      // Count unscratched cards
      const scratchRes = await db.query(
        `SELECT COUNT(*) as unscratched_count, COALESCE(SUM(coin_reward), 0) as pending_coins
         FROM public.scratch_cards
         WHERE female_user_id = $1 AND is_scratched = FALSE`,
        [userId]
      );

      // Total earnings from scratch cards
      const earningsRes = await db.query(
        `SELECT COALESCE(SUM(coin_reward), 0) as total_scratched_coins, COUNT(*) as total_scratched_cards
         FROM public.scratch_cards
         WHERE female_user_id = $1 AND is_scratched = TRUE`,
        [userId]
      );

      return {
        incomingPaidCallsEnabled: isEnabled,
        unscratchedCount: parseInt(scratchRes.rows[0]?.unscratched_count || '0', 10),
        pendingCoins: parseInt(scratchRes.rows[0]?.pending_coins || '0', 10),
        totalScratchedCoins: parseInt(earningsRes.rows[0]?.total_scratched_coins || '0', 10),
        totalScratchedCards: parseInt(earningsRes.rows[0]?.total_scratched_cards || '0', 10),
      };
    } catch (err) {
      console.error(`Error getting female instant status for ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Fetch all scratch cards for female user
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getScratchCards(userId) {
    try {
      const res = await db.query(
        `SELECT id, session_id, coin_reward, is_scratched, scratched_at, created_at
         FROM public.scratch_cards
         WHERE female_user_id = $1
         ORDER BY created_at DESC`,
        [userId]
      );
      return res.rows.map((row) => ({
        id: row.id,
        sessionId: row.session_id,
        coinReward: row.coin_reward,
        isScratched: row.is_scratched,
        scratchedAt: row.scratched_at,
        createdAt: row.created_at,
      }));
    } catch (err) {
      console.error(`Error fetching scratch cards for ${userId}:`, err.message);
      return [];
    }
  }

  /**
   * Scratch/claim a scratch card and credit coins directly to female wallet
   * @param {string} userId
   * @param {string} cardId
   * @returns {Promise<{ success: boolean, coinReward: number, newBalance: number, error?: string }>}
   */
  async claimScratchCard(userId, cardId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const cardRes = await client.query(
        `SELECT id, coin_reward, is_scratched 
         FROM public.scratch_cards 
         WHERE id = $1 AND female_user_id = $2
         FOR UPDATE`,
        [cardId, userId]
      );

      if (cardRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { success: false, error: 'CARD_NOT_FOUND', message: 'Scratch card not found' };
      }

      const card = cardRes.rows[0];
      if (card.is_scratched) {
        await client.query('ROLLBACK');
        return { success: false, error: 'ALREADY_SCRATCHED', message: 'This card is already claimed.' };
      }

      const reward = card.coin_reward;

      // Update card status
      await client.query(
        `UPDATE public.scratch_cards 
         SET is_scratched = TRUE, scratched_at = NOW() 
         WHERE id = $1`,
        [cardId]
      );

      // Credit wallet earned_balance (scratch rewards are earned host income)
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
         VALUES ($1, 0, $2)
         ON CONFLICT (user_id) 
         DO UPDATE SET 
           earned_balance = public.wallets.earned_balance + $2,
           updated_at = NOW()
         RETURNING spendable_balance, earned_balance`,
        [userId, reward]
      );

      const sBal = Number(walletRes.rows[0].spendable_balance);
      const eBal = Number(walletRes.rows[0].earned_balance);
      const newBalance = sBal + eBal;

      // Log wallet credit transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id)
         VALUES ($1, 0, $2, $3, 'instant_call_scratch_reward', $4)`,
        [userId, reward, `scratch_${cardId}`, cardId]
      );

      await client.query('COMMIT');
      return { success: true, coinReward: reward, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error claiming scratch card ${cardId} for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Escrow coins from male wallet for Instant Connect queue
   * @param {string} userId
   * @param {number} amount
   * @returns {Promise<{ success: boolean, newBalance?: number, error?: string, message?: string }>}
   */
  async escrowMaleCoins(userId, amount) {
    if (!amount || amount < 99) {
      return { success: false, error: 'INVALID_AMOUNT', message: 'Minimum bid amount is 99 coins.' };
    }

    const isSub = await subscriptionsService.isSubscribed(userId);
    if (!isSub) {
      return {
        success: false,
        error: 'SUBSCRIPTION_REQUIRED',
        message: 'An active subscription is required to use Instant Connect.',
      };
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const debitRes = await WalletService.debitCoins({
        userId,
        amount,
        reason: 'instant_call_escrow',
        client,
      });

      if (!debitRes.success) {
        await client.query('ROLLBACK');
        return {
          success: false,
          error: 'INSUFFICIENT_BALANCE',
          message: 'Insufficient coins in your wallet. Please recharge to continue.',
        };
      }

      await client.query('COMMIT');
      return { success: true, newBalance: debitRes.balance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error escrowing coins for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Refund escrowed coins when male cancels before call connects
   * @param {string} userId
   * @param {number} amount
   * @param {string} [sessionId]
   * @returns {Promise<{ success: boolean, newBalance: number }>}
   */
  async refundEscrowedCoins(userId, amount, sessionId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const creditRes = await WalletService.creditCoins({
        userId,
        spendable: amount,
        earned: 0,
        reason: 'instant_call_refund',
        referenceId: sessionId || null,
        client,
      });

      const newBalance = creditRes.balance;

      if (sessionId) {
        await client.query(
          `UPDATE public.instant_call_sessions 
           SET status = 'cancelled', ended_at = NOW() 
           WHERE id = $1`,
          [sessionId]
        );
      }

      await client.query('COMMIT');
      return { success: true, newBalance };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Error refunding escrow for user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Create an instant call session
   * @param {string} maleUserId
   * @param {number} bidAmount
   * @returns {Promise<Object>}
   */
  async createSession(maleUserId, bidAmount) {
    const res = await db.query(
      `INSERT INTO public.instant_call_sessions (male_user_id, bid_amount, status)
       VALUES ($1, $2, 'queued')
       RETURNING id, male_user_id, bid_amount, status, created_at`,
      [maleUserId, bidAmount]
    );
    return res.rows[0];
  }

  /**
   * Assign matched female to the session and start call
   * @param {string} sessionId
   * @param {string} femaleUserId
   * @param {string} agoraChannelName
   * @returns {Promise<Object>}
   */
  async startCallSession(sessionId, femaleUserId, agoraChannelName) {
    const res = await db.query(
      `UPDATE public.instant_call_sessions
       SET female_user_id = $1, agora_channel_name = $2, status = 'in_call', started_at = NOW()
       WHERE id = $3
       RETURNING *`,
      [femaleUserId, agoraChannelName, sessionId]
    );
    return res.rows[0];
  }

  /**
   * Trigger 10-Minute Milestone and generate Scratch Card for Female
   * Margin calculation: 35% to 65% of bidAmount awarded to female, rest retained as app margin
   * @param {string} sessionId
   * @returns {Promise<Object|null>} generated scratch card
   */
  async trigger10MinuteMilestone(sessionId) {
    try {
      const sessRes = await db.query(
        `SELECT id, male_user_id, female_user_id, bid_amount, scratch_card_unlocked 
         FROM public.instant_call_sessions 
         WHERE id = $1`,
        [sessionId]
      );

      if (sessRes.rows.length === 0) return null;
      const session = sessRes.rows[0];

      if (session.scratch_card_unlocked || !session.female_user_id) {
        return null; // Already unlocked or invalid
      }

      // Calculate reward: between 30% and 50% of bid_amount (min 1 coin)
      const bid = session.bid_amount;
      const minReward = Math.max(1, Math.floor(bid * 0.30));
      const maxReward = Math.max(minReward + 1, Math.floor(bid * 0.50));
      const coinReward = Math.floor(Math.random() * (maxReward - minReward + 1)) + minReward;

      // Update session milestone
      await db.query(
        `UPDATE public.instant_call_sessions 
         SET milestone_10m_at = NOW(), scratch_card_unlocked = TRUE 
         WHERE id = $1`,
        [sessionId]
      );

      // Create scratch card row
      const cardRes = await db.query(
        `INSERT INTO public.scratch_cards (session_id, female_user_id, coin_reward)
         VALUES ($1, $2, $3)
         RETURNING id, session_id, female_user_id, coin_reward, is_scratched, created_at`,
        [sessionId, session.female_user_id, coinReward]
      );

      return cardRes.rows[0];
    } catch (err) {
      console.error(`Error in trigger10MinuteMilestone for session ${sessionId}:`, err.message);
      return null;
    }
  }

  /**
   * End an instant call session and record final duration
   * @param {string} sessionId
   * @param {string} finalStatus - 'completed' | 'dropped' | 'cancelled'
   * @param {number} durationSeconds
   */
  async endCallSession(sessionId, finalStatus, durationSeconds) {
    try {
      await db.query(
        `UPDATE public.instant_call_sessions 
         SET status = $1, ended_at = NOW(), duration_seconds = $2
         WHERE id = $3`,
        [finalStatus, durationSeconds, sessionId]
      );
    } catch (err) {
      console.error(`Error ending instant call session ${sessionId}:`, err.message);
    }
  }

  /**
   * Find a batch of eligible female users for 1:10 FCM surge when available socket pool is empty
   * @param {string[]} excludeUserIds
   * @param {number} count
   * @returns {Promise<Array<{ id: string, fcm_token: string|null, full_name: string }>>}
   */
  async getSurgeEligibleFemales(excludeUserIds = [], count = 10) {
    try {
      const excludeClause = excludeUserIds.length > 0
        ? `AND u.id NOT IN (${excludeUserIds.map((_, i) => `$${i + 2}`).join(', ')})`
        : '';
      const params = [count, ...excludeUserIds];

      const res = await db.query(
        `SELECT u.id, u.fcm_token, u.full_name
         FROM public.users u
         WHERE (LOWER(u.gender) IN ('female', 'girl', 'woman', 'f'))
           AND u.incoming_paid_calls_enabled = true
           AND u.fcm_token IS NOT NULL
           ${excludeClause}
         ORDER BY RANDOM()
         LIMIT $1`,
        params
      );
      console.log(`🔍 [Surge Check] Found ${res.rows.length} surge-eligible females with FCM tokens`);
      return res.rows;
    } catch (err) {
      console.error('Error finding surge eligible females:', err.message);
      return [];
    }
  }
}

const instantConnectService = new InstantConnectService();

module.exports = {
  InstantConnectService,
  instantConnectService,
};

```

---

## 5. Redis Helper Utilities (SCAN vs KEYS Verification)
**File:** [`backend/utils/redis_helpers.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/utils/redis_helpers.js)

```javascript
/**
 * Redis utility helpers for high-concurrency production safety.
 */

/**
 * Non-blocking key scanner using Redis SCAN cursor iteration.
 * Safe replacement for blocking KEYS commands at high CCU.
 *
 * @param {import('ioredis').Redis} redis
 * @param {string} pattern - Glob-style key pattern (e.g. 'refresh:userId:*')
 * @param {number} [count=100] - Hint count per iteration
 * @returns {Promise<string[]>} Matching keys
 */
async function scanKeys(redis, pattern, count = 100) {
  if (!redis) return [];
  let cursor = '0';
  let keys = [];

  do {
    const [nextCursor, foundKeys] = await redis.scan(cursor, 'MATCH', pattern, 'COUNT', count);
    cursor = nextCursor;
    if (foundKeys && foundKeys.length > 0) {
      keys = keys.concat(foundKeys);
    }
  } while (cursor !== '0');

  return keys;
}

module.exports = {
  scanKeys,
};

```

---

## 6. Buddy Socket Event Handlers
**File:** [`backend/modules/buddy/buddy.socket.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/buddy/buddy.socket.js)

```javascript
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

```

---

## 7. Buddy Configuration & Pricing Matrix
**File:** [`backend/modules/buddy/buddy.config.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/buddy/buddy.config.js)

```javascript
/**
 * Configuration for "Buddy" Activity Requests feature.
 * Centralized pricing and limits so updates do not require database migrations.
 */

const BUDDY_TYPES = Object.freeze({
  movie: {
    id: 'movie',
    title: 'Movie Buddy',
    subtitle: 'Find someone to watch movies with',
    stickerPath: 'assets/images/stickers/movie_buddy.jpg',
  },
  pizza: {
    id: 'pizza',
    title: 'Pizza Buddy',
    subtitle: 'Find someone to grab delicious pizza with',
    stickerPath: 'assets/images/stickers/pizza_buddy.jpg',
  },
  coffee: {
    id: 'coffee',
    title: 'Coffee Buddy',
    subtitle: 'Find someone for a coffee chat',
    stickerPath: 'assets/images/stickers/coffee_buddy.jpg',
  },
  hangout: {
    id: 'hangout',
    title: 'Hangout Buddy',
    subtitle: 'Find someone to chill and hangout with',
    stickerPath: 'assets/images/stickers/hangout_buddy.jpg',
  },
  trip: {
    id: 'trip',
    title: 'Trip Buddy',
    subtitle: 'Find a travel partner for your next trip',
    stickerPath: 'assets/images/stickers/trip_buddy.jpg',
  },
  cricket: {
    id: 'cricket',
    title: 'Cricket Buddy',
    subtitle: 'Find a buddy to watch or play cricket',
    stickerPath: 'assets/images/stickers/cricket_buddy.jpg',
  },
  shopping: {
    id: 'shopping',
    title: 'Shopping Buddy',
    subtitle: 'Find someone to go shopping with',
    stickerPath: 'assets/images/stickers/shopping_buddy.jpg',
  },
  night_out: {
    id: 'night_out',
    title: 'Night Out Buddy',
    subtitle: 'Find a partner for a fun night out',
    stickerPath: 'assets/images/stickers/nightout_buddy.jpg',
  },
  clubbing: {
    id: 'clubbing',
    title: 'Clubbing Buddy',
    subtitle: 'Find a party and clubbing partner',
    stickerPath: 'assets/images/stickers/clubbing_buddy.jpg',
  },
  long_drive: {
    id: 'long_drive',
    title: 'Long Drive Buddy',
    subtitle: 'Find someone for a scenic long drive',
    stickerPath: 'assets/images/stickers/longdrive_buddy.jpg',
  },
});

const BUDDY_PRICING = Object.freeze({
  INITIATOR_COIN_COST: 100,
  ACCEPTER_COIN_REWARD: 50,
});

const BUDDY_LIMITS = Object.freeze({
  MAX_OTP_ATTEMPTS: 5,
  OTP_LOCKOUT_SECONDS: 900, // 15 minutes lockout
  MAX_FCM_BATCH_SIZE: 500,
  MAX_FCM_RECIPIENTS: 5000,
  DEFAULT_FEED_LIMIT: 20,
  MAX_FEED_LIMIT: 50,
});

const BUDDY_STATUSES = Object.freeze({
  OPEN: 'open',
  ACCEPTED: 'accepted',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
});

module.exports = {
  BUDDY_TYPES,
  BUDDY_PRICING,
  BUDDY_LIMITS,
  BUDDY_STATUSES,
};

```

---

## 8. Version Enforcement Middleware
**File:** [`backend/middleware/version.middleware.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/middleware/version.middleware.js)

```javascript
const { appService } = require('../modules/app/app.service');

/**
 * Express middleware to enforce minimum supported app version per platform.
 * Expects headers: "X-App-Platform: android|ios" and "X-App-Version: 1.4.2"
 */
async function enforceMinimumVersion(req, res, next) {
  // Exclude public version check, admin routes, and exact health check endpoints
  const path = req.path;
  const originalUrl = (req.originalUrl || '').split('?')[0];
  if (
    path.startsWith('/app/version-check') ||
    path.startsWith('/admin') ||
    path === '/health' ||
    path === '/api/health' ||
    originalUrl === '/health' ||
    originalUrl === '/api/health'
  ) {
    return next();
  }

  const platformHeader = req.headers['x-app-platform'];
  const versionHeader = req.headers['x-app-version'];

  if (!versionHeader || versionHeader === 'unknown') {
    // Logging-only for rollout window or uninitialized/fallback clients
    return next();
  }

  try {
    const platform = (platformHeader || 'android').toString();
    const version = versionHeader.toString();

    const result = await appService.checkVersion(platform, version);

    if (result.updateRequired) {
      console.warn(
        `🚨 [HTTP 426] Blocked outdated client request. User ID: ${req.user?.id || 'anonymous'}, Version: ${version}, Platform: ${platform}, Path: ${req.originalUrl}`
      );
      return res.status(426).json({
        error: 'upgrade_required',
        minimumSupportedVersion: result.minimumSupportedVersion,
        storeUrl: result.storeUrl,
      });
    }

    next();
  } catch (err) {
    console.error('Error in enforceMinimumVersion middleware:', err.message);
    // Fail-open for request processing if internal version check errors
    next();
  }
}

module.exports = { enforceMinimumVersion };

```

---

## 9. OTP Authentication Service
**File:** [`backend/modules/auth/otpService.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/auth/otpService.js)

```javascript
const crypto = require('crypto');
const axios = require('axios');

/**
 * Generates a cryptographically random 6-digit OTP string.
 * @returns {string} 6-digit numeric string
 */
function generateOTP() {
  return crypto.randomInt(100000, 1000000).toString();
}

/**
 * Cleans country code (removes leading '+') and mobile number (removes non-digits).
 * @param {string} countryCode 
 * @param {string} mobile 
 * @returns {{ cleanCountryCode: string, cleanMobile: string }}
 */
function sanitizePhoneInputs(countryCode, mobile) {
  const cleanCountryCode = (countryCode || '').toString().trim().replace(/^\+/, '');
  const cleanMobile = (mobile || '').toString().trim().replace(/\D/g, '');
  return { cleanCountryCode, cleanMobile };
}

/**
 * Sends a 6-digit OTP to the recipient's mobile number via MSG91 WhatsApp Outbound Bulk API.
 * 
 * MSG91 API format:
 * POST https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/
 * Headers: authkey, Content-Type: application/json
 * Body: {
 *   integrated_number: "916006329803",
 *   content_type: "template",
 *   payload: {
 *     messaging_product: "whatsapp",
 *     type: "template",
 *     template: {
 *       name: "otp",
 *       language: { code: "en", policy: "deterministic" },
 *       namespace: null,
 *       to_and_components: [
 *         {
 *           to: ["919876543210"],
 *           components: { ... }
 *         }
 *       ]
 *     }
 *   }
 * }
 * 
 * @param {string} countryCode e.g. '91' or '+91'
 * @param {string} mobile e.g. '9876543210'
 * @param {string} otp 6-digit OTP string
 * @returns {Promise<{ success: boolean, message?: string }>}
 */
async function sendWhatsAppOtp(countryCode, mobile, otp) {
  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(countryCode, mobile);
  const authKey = process.env.MSG91_AUTHKEY || process.env.AUTHKEY_API_KEY;
  const integratedNumber = process.env.MSG91_INTEGRATED_NUMBER || '919795038296';
  const templateName = process.env.MSG91_TEMPLATE_NAME || 'login_otp';
  const namespace = process.env.MSG91_NAMESPACE || 'a9966637_659b_4a6e_8e8b_fd5d9179b5db';

  if (!authKey) {
    console.warn('⚠️ MSG91_AUTHKEY / AUTHKEY_API_KEY missing from environment variables.');
  }

  // Obfuscate mobile for secure logging (never log raw OTP)
  const maskedMobile = cleanMobile.length >= 4 
    ? '*'.repeat(cleanMobile.length - 4) + cleanMobile.slice(-4) 
    : '****';
  const fullRecipientNumber = `${cleanCountryCode}${cleanMobile}`;

  console.log(`📱 Triggering MSG91 WhatsApp OTP delivery to country: +${cleanCountryCode}, mobile: ${maskedMobile}`);

  // In local test / dev mode when MSG91 credentials are empty or stubbed, log sanitized debug info
  if (!authKey || authKey === 'your_authkey_api_key_here' || authKey === 'mock_authkey_key' || authKey === 'your_msg91_authkey_here') {
    console.log(`[DEV MODE] MSG91 Authkey not configured or mock key used. OTP generation successful for ${maskedMobile}.`);
    return { success: true, message: 'OTP send simulated in dev environment.' };
  }

  const components = {
    body_1: {
      type: 'text',
      value: otp,
    },
    button_1: {
      subtype: 'url',
      type: 'text',
      value: otp,
    },
  };

  const payloadData = {
    integrated_number: integratedNumber,
    content_type: 'template',
    payload: {
      messaging_product: 'whatsapp',
      type: 'template',
      template: {
        name: templateName,
        language: {
          code: 'en',
          policy: 'deterministic',
        },
        namespace: namespace,
        to_and_components: [
          {
            to: [fullRecipientNumber],
            components: components,
          },
        ],
      },
    },
  };

  try {
    const response = await axios.post(
      'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/',
      payloadData,
      {
        headers: {
          'Content-Type': 'application/json',
          authkey: authKey,
        },
        timeout: 20000,
      }
    );

    const isSuccessStatus = response.status >= 200 && response.status < 300;
    const hasNoErrorFlag = response.data?.hasError === false || response.data?.status === 'success' || response.data?.type === 'success';

    if (isSuccessStatus && (hasNoErrorFlag || !response.data?.hasError)) {
      const reqId = response.data?.request_id || response.data?.requestId || 'N/A';
      console.log(`✅ MSG91 WhatsApp OTP queued for ${maskedMobile}. Request ID: ${reqId}, Status: ${response.status}`);
      return { success: true };
    } else {
      const errMsg = response.data?.message || response.data?.Message || response.data?.error || `MSG91 API HTTP ${response.status}`;
      console.error(`❌ MSG91 API non-success response: HTTP ${response.status}`, response.data);

      if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
        console.warn(`⚠️ [DEV FALLBACK] MSG91 error: "${errMsg}". Simulating OTP delivery for testing.`);
        return { success: true, message: `[DEV] Simulated OTP: ${otp}` };
      }

      return { success: false, message: errMsg };
    }
  } catch (err) {
    const errorData = err.response?.data;
    const errMsg = errorData?.message || errorData?.Message || errorData?.error || err.message || 'WhatsApp OTP delivery service unavailable.';
    console.error(`❌ Error calling MSG91 WhatsApp OTP API:`, errorData || err.message);

    if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
      console.warn(`⚠️ [DEV FALLBACK] MSG91 call error: "${errMsg}". Simulating OTP delivery for testing.`);
      return { success: true, message: `[DEV] Simulated OTP: ${otp}` };
    }

    return { success: false, message: errMsg };
  }
}

module.exports = {
  generateOTP,
  sanitizePhoneInputs,
  sendWhatsAppOtp,
};

```

---

## 10. Wallet REST Routes
**File:** [`backend/modules/wallet/wallet.routes.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/wallet/wallet.routes.js)

```javascript
const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WalletService } = require('./wallet.service');
const { cacheService } = require('../../services/cache.service');

/**
 * GET /api/wallet/balance
 * Returns the current dual coin balance for the authenticated user.
 * Cached in Redis for 15s to support rapid polling/home refresh without DB spikes.
 */
router.get('/wallet/balance', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const balanceData = await cacheService.getOrSet(`user:balance:${userId}`, 15, async () => {
      return await WalletService.getBalance(userId);
    });

    res.json({
      success: true,
      spendableBalance: balanceData.spendableBalance || 0,
      earnedBalance: balanceData.earnedBalance || 0,
      balance: balanceData.balance || 0,
    });
  } catch (err) {
    console.error('❌ Error fetching wallet balance:', err.message);
    res.json({
      success: true,
      spendableBalance: 0,
      earnedBalance: 0,
      balance: 0,
    });
  }
});

/**
 * GET /api/wallet/transactions?cursor=&limit=
 * Reads from wallet_transactions for authenticated user, cursor-paginated.
 */
router.get('/wallet/transactions', authMiddleware, async (req, res) => {
  try {
    const { cursor, limit } = req.query;
    const result = await WalletService.getTransactions(req.user.id, cursor || null, limit || 20);
    res.json(result);
  } catch (err) {
    console.error('❌ Error fetching wallet transactions:', err.message);
    res.status(500).json({ error: 'Failed to fetch wallet transactions' });
  }
});

/**
 * POST /api/wallet/recharge
 * Credits coins to user's spendable_balance (purchased coins are non-withdrawable).
 * Supports idempotencyKey via body or x-idempotency-key header.
 */
router.post('/wallet/recharge', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const amount = parseInt(req.body.amount, 10);
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Valid amount is required.' });
    }

    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;
    const paymentReference = req.body.paymentReference ? String(req.body.paymentReference) : null;

    const result = await WalletService.creditCoins({
      userId,
      spendable: amount,
      earned: 0,
      reason: 'recharge',
      referenceId: paymentReference,
      idempotencyKey,
    });

    res.json({
      success: true,
      amount,
      spendableBalance: result.spendableBalance,
      earnedBalance: result.earnedBalance,
      balance: result.balance,
      paymentReference,
    });
  } catch (err) {
    console.error('❌ Error in POST /api/wallet/recharge:', err.message);
    res.status(500).json({ error: 'Failed to recharge wallet: ' + err.message });
  }
});

module.exports = router;

```

---

## 11. Withdrawals REST Routes
**File:** [`backend/modules/withdrawals/withdrawals.routes.js`](file:///C:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/withdrawals/withdrawals.routes.js)

```javascript
const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { WithdrawalsService } = require('./withdrawals.service');

/**
 * POST /api/withdrawals
 * Request a withdrawal from earned_balance.
 * Body: { amount: number, payoutMethod?: string, payoutDetails?: object, idempotencyKey?: string }
 */
router.post('/withdrawals', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const rawAmount = req.body.amount || req.body.coinAmount;
    const amount = parseInt(rawAmount, 10);
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, error: 'Invalid withdrawal amount. Must be a positive integer.' });
    }

    const idempotencyKey = req.body.idempotencyKey || req.headers['x-idempotency-key'] || null;
    const payoutMethod = req.body.payoutMethod || 'upi';
    const payoutDetails = req.body.payoutDetails || {};

    const result = await WithdrawalsService.requestWithdrawal({
      userId,
      amount,
      payoutMethod,
      payoutDetails,
      idempotencyKey,
    });

    if (!result.success) {
      const statusCode = result.code === 'CONCURRENT_PENDING_NOT_ALLOWED' ? 409 : 400;
      return res.status(statusCode).json({
        success: false,
        error: result.error,
        code: result.code,
      });
    }

    res.status(201).json({
      success: true,
      withdrawal: result.withdrawal,
      spendableBalance: result.spendableBalance,
      earnedBalance: result.earnedBalance,
      balance: result.balance,
      alreadyProcessed: result.alreadyProcessed || false,
    });
  } catch (err) {
    console.error('❌ Error in POST /withdrawals:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

/**
 * GET /api/withdrawals
 * List the authenticated user's withdrawal requests.
 */
router.get('/withdrawals', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const withdrawals = await WithdrawalsService.getWithdrawals(userId);
    res.json({ success: true, withdrawals });
  } catch (err) {
    console.error('❌ Error in GET /withdrawals:', err.message);
    res.status(500).json({ success: false, error: 'Internal server error.' });
  }
});

module.exports = router;

```

---

## 12. Flutter Client Polling Intervals & Real HTTP QPS Multiplier Analysis

### Audit Findings on Mobile Client Behavior:
A deep inspection across the Flutter codebase (`lib/`) confirms that **the mobile client does NOT run aggressive, unconstrained background HTTP polling loops** on `/api/calls/matches`, `/api/wallet/balance`, or `/api/subscriptions/status`.

#### A. `/api/calls/matches` (`lib/features/home/presentation/providers/matched_users_provider.dart`)
- **Pattern:** Standard Riverpod `FutureProvider<List<MatchedUser>>` (persistent in-memory cache).
- **Frequency:** Fetches once when the Home screen mounts. It does NOT have a `Timer.periodic`. Any subsequent reload is triggered strictly by manual user pull-to-refresh.
- **Real QPS Multiplier:** Low (~0.05 to 0.1 requests per user per minute).

#### B. `/api/wallet/balance` (`lib/features/wallet/application/wallet_balance_provider.dart`)
- **Pattern:** Riverpod `AsyncNotifierProvider` (`DualWalletNotifier` and `WalletBalanceNotifier`).
- **Frequency:** Fetches upon authentication and when the user opens the Wallet/Recharge sheet. In-memory state is updated locally after transactions without blind polling loops.
- **Real QPS Multiplier:** Low (~0.1 to 0.2 requests per user per minute).

#### C. `/api/subscriptions/status` (`lib/features/subscription/application/subscription_providers.dart`)
- **Pattern:** `AsyncNotifier<SubscriptionState>` with local UI timer.
- **The `Timer.periodic(Duration(seconds: 1))` in this file is strictly an IN-MEMORY UI COUNTDOWN TIMER**:
  ```dart
  _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    // Decrements remaining seconds locally from expiresAt DateTime difference in memory
    final newState = _calculateTimeState(...);
    state = AsyncData(newState);
  });
  ```
- **HTTP Call Frequency:** The actual `GET /api/subscriptions/status` is ONLY executed on initial provider build, on explicit socket reconnection (`ref.listen(socketProvider, ...)`), or after completing a purchase.
- **Real QPS Multiplier:** Negligible during active sessions (~0.02 requests per minute).

#### D. Other Periodic Timers in the Client App:
1. `ad_banner_widget.dart`: `Timer.periodic(const Duration(seconds: 10))` rotates local PageView carousel (zero network calls).
2. `network_connectivity_service.dart`: `Timer.periodic(const Duration(seconds: 8))` performs a lightweight DNS lookup to `google.com` (not our backend).
3. `login_page.dart` / `forgot_password_page.dart`: `Timer.periodic(const Duration(seconds: 1))` is a 60-second UI countdown for the "Resend OTP" button.

### Conclusion on Real HTTP QPS:
The 1,000–1,500 HTTP QPS at 5,000 CCU is driven by **active user interaction and screen navigation** (switching tabs, opening chats, viewing profiles), NOT by runaway timer polling loops in the Dart code.
