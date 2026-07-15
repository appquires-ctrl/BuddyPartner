const { RtcTokenBuilder, RtcRole } = require('agora-access-token');

const CALL_DURATION_MS = 5 * 60 * 1000; // 5 minutes
const TOKEN_EXPIRY_SECONDS = 6 * 60;     // 6 minutes (5 min call + 1 min buffer)

class CallsService {
  constructor(supabase) {
    this.supabase = supabase;
    // Map of callId → setTimeout handle for server-authoritative 5-min timer
    this.callTimers = new Map();
  }

  /**
   * Create a new call record in the database.
   *
   * @param {string} userAId - caller
   * @param {string} userBId - matched user
   * @returns {string} callId (UUID)
   */
  async createCall(userAId, userBId) {
    const { data, error } = await this.supabase
      .from('calls')
      .insert({
        caller_id: userAId,
        matched_user_id: userBId,
        status: 'active',
        call_type: 'voice',
      })
      .select('id')
      .single();

    if (error) {
      console.error('Error creating call:', error);
      throw new Error('Failed to create call record');
    }

    return data.id;
  }

  /**
   * End a call — set status to ended, record end time and duration.
   *
   * @param {string} callId
   */
  async endCall(callId) {
    // Clear the server-side timer if still running
    this.clearCallTimer(callId);

    const { data: call, error: fetchError } = await this.supabase
      .from('calls')
      .select('started_at, status')
      .eq('id', callId)
      .single();

    if (fetchError || !call) {
      console.error('Error fetching call for end:', fetchError);
      return;
    }

    // Guard against double-ending
    if (call.status === 'ended') {
      return;
    }

    const endedAt = new Date();
    const startedAt = new Date(call.started_at);
    const durationSeconds = Math.floor((endedAt - startedAt) / 1000);

    const { error: updateError } = await this.supabase
      .from('calls')
      .update({
        status: 'ended',
        ended_at: endedAt.toISOString(),
        duration_seconds: durationSeconds,
      })
      .eq('id', callId);

    if (updateError) {
      console.error('Error ending call:', updateError);
    }
  }

  /**
   * Upgrade a call from voice to video.
   *
   * @param {string} callId
   */
  async upgradeToVideo(callId) {
    const { error } = await this.supabase
      .from('calls')
      .update({ call_type: 'video' })
      .eq('id', callId);

    if (error) {
      console.error('Error upgrading call to video:', error);
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
}

module.exports = { CallsService, CALL_DURATION_MS };
