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
