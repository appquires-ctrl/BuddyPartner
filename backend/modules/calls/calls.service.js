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
   * Start the server-authoritative 5-minute timer for a call.
   * When it fires, the callback is invoked to force-end the call.
   *
   * @param {string} callId
   * @param {Function} onExpiry - callback invoked when 5 minutes elapses
   */
  startCallTimer(callId, onExpiry) {
    // Clear any existing timer for this call
    this.clearCallTimer(callId);

    const timer = setTimeout(async () => {
      console.log(`⏰ Call ${callId} reached 5-minute limit — force-ending`);
      this.callTimers.delete(callId);
      await this.endCall(callId);
      onExpiry(callId);
    }, CALL_DURATION_MS);

    this.callTimers.set(callId, timer);
  }

  /**
   * Clear the server-side timer for a call (e.g. on manual end).
   *
   * @param {string} callId
   */
  clearCallTimer(callId) {
    const existing = this.callTimers.get(callId);
    if (existing) {
      clearTimeout(existing);
      this.callTimers.delete(callId);
    }
  }

  /**
   * Start 60-second billing interval for a call.
   * Gender-aware: boys are debited coins, girls are credited roses.
   *
   * @param {string} callId
   * @param {string} userAId
   * @param {string} userBId
   * @param {string} genderA - 'male' or 'female'
   * @param {string} genderB - 'male' or 'female'
   * @param {import('socket.io').Server} io
   * @param {Function} onInsufficientBalance - callback (callId) when boy's balance is insufficient
   */
  startCallBilling(callId, userAId, userBId, genderA, genderB, io, onInsufficientBalance) {
    this.clearCallBilling(callId);
    const { WalletService, CALL_RATES } = require('../wallet/wallet.service');
    const { RoseService, ROSE_RATES } = require('../wallet/rose.service');

    // Determine who is the boy and who is the girl
    const isFemaleA = this._isFemale(genderA);
    const isFemaleB = this._isFemale(genderB);
    const boyId = isFemaleA ? userBId : userAId;
    const girlId = isFemaleA ? userAId : userBId;
    const hasBoy = !isFemaleA || !isFemaleB;
    const hasGirl = isFemaleA || isFemaleB;

    console.log(`💰 [Billing] Started gender-aware billing for call ${callId} — boy: ${boyId}, girl: ${girlId}`);

    const interval = setInterval(async () => {
      console.log(`💰 [Billing] Tick fired for call ${callId}`);
      try {
        // Query DB for current call status & type
        const res = await db.query(
          'SELECT status, call_type FROM public.calls WHERE id = $1',
          [callId]
        );

        if (res.rows.length === 0 || res.rows[0].status !== 'active') {
          this.clearCallBilling(callId);
          return;
        }

        const callType = res.rows[0].call_type || 'voice';
        const coinRate = callType === 'video' ? CALL_RATES.video : CALL_RATES.voice;

        const { userSockets } = require('../matchmaking/matchmaking.socket');

        // === BOY: Debit coins ===
        if (hasBoy) {
          console.log(`💰 [Billing] Deducting ${coinRate} coins (${callType}) from boy ${boyId}`);
          const deductRes = await WalletService.deductForCallMinute(boyId, callId, coinRate);
          console.log(`💰 [Billing] Boy deduction result: ${JSON.stringify(deductRes)}`);

          if (deductRes.success && deductRes.newBalance !== null) {
            const boySocketId = userSockets.get(boyId);
            if (boySocketId) {
              io.to(boySocketId).emit('balance_update', { balance: deductRes.newBalance });
            }
          }

          // If boy's balance is insufficient, end the call
          if (!deductRes.success) {
            console.log(`💳 Call ${callId} ended — boy ${boyId} has insufficient balance`);
            this.clearCallBilling(callId);
            onInsufficientBalance(callId, boyId);
            return; // Don't credit the girl for this failed minute
          }
        }

        // === GIRL: Credit roses ===
        if (hasGirl) {
          console.log(`🌹 [Billing] Crediting roses (${callType}) to girl ${girlId}`);
          const creditRes = await RoseService.creditRoseForCallMinute(girlId, callId, callType);
          console.log(`🌹 [Billing] Girl credit result: ${JSON.stringify(creditRes)}`);

          if (creditRes.success && creditRes.newBalance !== null) {
            const girlSocketId = userSockets.get(girlId);
            if (girlSocketId) {
              io.to(girlSocketId).emit('rose_update', { balance: creditRes.newBalance });
            }
          }
        }
      } catch (err) {
        console.error(`Error during per-minute billing for call ${callId}:`, err.message);
      }
    }, 60 * 1000); // 60 seconds interval

    this.callBillingIntervals.set(callId, interval);
  }

  /**
   * Clear the per-minute billing interval for a call.
   *
   * @param {string} callId
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

module.exports = { callsService, CallsService, CALL_DURATION_MS };
