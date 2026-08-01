const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const db = require('../../db');

const CALL_DURATION_MS = 5 * 60 * 1000; // 5 minutes
const TOKEN_EXPIRY_SECONDS = 6 * 60;     // 6 minutes (5 min call + 1 min buffer)

class CallsService {
  constructor() {
    // Map of callId → setTimeout handle for server-authoritative 5-min timer
    this.callTimers = new Map();
    // Map of callId → setInterval handle for per-minute billing
    this.callBillingIntervals = new Map();
  }

  /**
   * Create a new call record in the database.
   *
   * @param {string} userAId - caller
   * @param {string} userBId - matched user
   * @returns {string} callId (UUID)
   */
  async createCall(userAId, userBId) {
    try {
      const result = await db.query(
        `INSERT INTO public.calls (caller_id, matched_user_id, status, call_type)
         VALUES ($1, $2, 'active', 'voice')
         RETURNING id`,
        [userAId, userBId]
      );

      if (result.rows.length === 0) {
        throw new Error('No row returned on call insertion');
      }

      return result.rows[0].id;
    } catch (err) {
      console.error('Error creating call in Postgres:', err.message);
      throw new Error('Failed to create call record');
    }
  }

  /**
   * End a call — set status to ended, record end time and duration.
   *
   * @param {string} callId
   */
  async endCall(callId) {
    // Clear the server-side timer & billing interval if running
    this.clearCallTimer(callId);
    this.clearCallBilling(callId);

    try {
      const result = await db.query(
        'SELECT started_at, status FROM public.calls WHERE id = $1',
        [callId]
      );

      if (result.rows.length === 0) {
        console.error(`Call record not found: ${callId}`);
        return;
      }

      const call = result.rows[0];

      // Guard against double-ending
      if (call.status === 'ended') {
        return;
      }

      const endedAt = new Date();
      const startedAt = new Date(call.started_at);
      const durationSeconds = Math.floor((endedAt - startedAt) / 1000);

      await db.query(
        `UPDATE public.calls 
         SET status = 'ended', ended_at = $1, duration_seconds = $2 
         WHERE id = $3`,
        [endedAt.toISOString(), durationSeconds, callId]
      );
    } catch (err) {
      console.error('Error ending call in Postgres:', err.message);
    }
  }

  /**
   * Upgrade a call from voice to video.
   *
   * @param {string} callId
   */
  async upgradeToVideo(callId) {
    try {
      await db.query(
        "UPDATE public.calls SET call_type = 'video' WHERE id = $1",
        [callId]
      );
    } catch (err) {
      console.error('Error upgrading call to video in Postgres:', err.message);
    }
  }

  /**
   * Generate an Agora RTC token for a given channel and UID.
   *
   * @param {string} channelName
   * @param {number} uid - numeric Agora UID
   * @param {number} [expireSeconds] - token lifetime
   * @returns {string} Agora RTC token
   */
  generateAgoraToken(channelName, uid, expireSeconds = TOKEN_EXPIRY_SECONDS) {
    const appId = process.env.AGORA_APP_ID;
    const appCertificate = process.env.AGORA_APP_CERTIFICATE;

    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expireSeconds;

    return RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpiredTs,
    );
  }

  /**
   * No-op stub for starting call timer (5-minute cap removed in subscription model).
   */
  startCallTimer(callId, onExpiry) {
    // 5-minute limit removed under subscription model
  }

  /**
   * No-op stub for clearing call timer.
   */
  clearCallTimer(callId) {
    const existing = this.callTimers.get(callId);
    if (existing) {
      clearTimeout(existing);
      this.callTimers.delete(callId);
    }
  }

  /**
   * No-op stub for starting call billing (per-minute billing removed in subscription model).
   */
  startCallBilling(callId, userAId, userBId, genderA, genderB, io, onInsufficientBalance) {
    // Per-minute billing removed under subscription model
  }

  /**
   * No-op stub for clearing call billing.
   */
  clearCallBilling(callId) {
    const existing = this.callBillingIntervals.get(callId);
    if (existing) {
      clearInterval(existing);
      this.callBillingIntervals.delete(callId);
    }
  }

  /**
   * Check if a gender string represents female.
   * @param {string} gender
   * @returns {boolean}
   */
  _isFemale(gender) {
    const g = (gender || '').toLowerCase();
    return g === 'female' || g === 'girl' || g === 'woman';
  }
}

const callsService = new CallsService();

module.exports = { callsService, CallsService };
