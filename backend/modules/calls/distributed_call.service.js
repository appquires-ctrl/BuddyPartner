const crypto = require('crypto');
const { callsService } = require('./calls.service');
const { callQuotaService } = require('./call_quota.service');
const { cacheService } = require('../../services/cache.service');

const NODE_INSTANCE_ID = process.env.RENDER_INSTANCE_ID || process.env.NODE_INSTANCE_ID || `node_${process.pid}`;

class DistributedCallService {
  constructor() {
    this.instanceId = NODE_INSTANCE_ID;
  }

  // ── Pending Call Requests (TTL 35s) ───────────────────────────────────────

  async savePendingCall(redis, callRequestId, data) {
    if (!redis || !callRequestId || !data) return;
    const { timer, ...serializable } = data;
    await redis.set(`pending_call:${callRequestId}`, JSON.stringify(serializable), 'EX', 35);
  }

  async getPendingCall(redis, callRequestId) {
    if (!redis || !callRequestId) return null;
    try {
      const raw = await redis.get(`pending_call:${callRequestId}`);
      if (!raw) return null;
      return JSON.parse(raw);
    } catch (err) {
      console.warn(`[DistributedCall] Error reading pending call ${callRequestId}:`, err.message);
      return null;
    }
  }

  async deletePendingCall(redis, callRequestId) {
    if (!redis || !callRequestId) return;
    await redis.del(`pending_call:${callRequestId}`).catch(() => {});
  }

  // ── Direct & Matchmaking Active Calls (Hash, TTL 7200s) ───────────────────

  async saveActiveCall(redis, callId, data) {
    if (!redis || !callId || !data) return null;
    const now = Date.now();

    const userAId = String(data.userA?.userId || data.userA_id);
    const userAGender = String(data.userA?.gender || data.userA_gender || 'unknown');
    const userBId = String(data.userB?.userId || data.userB_id);
    const userBGender = String(data.userB?.gender || data.userB_gender || 'unknown');
    const agoraChannelName = String(data.channelName || data.agoraChannelName || '');
    const callType = String(data.callType || 'voice');
    const startedAt = String(data.startedAt || now);
    const voiceStartedAt = String(data.voiceStartedAt !== undefined && data.voiceStartedAt !== null ? data.voiceStartedAt : (callType === 'voice' ? now : ''));
    const videoStartedAt = String(data.videoStartedAt !== undefined && data.videoStartedAt !== null ? data.videoStartedAt : (callType === 'video' ? now : ''));
    const totalAudioSeconds = String(data.totalAudioSeconds || 0);
    const totalVideoSeconds = String(data.totalVideoSeconds || 0);
    const maxAllowedSeconds = String(data.maxAllowedSeconds || 12000);

    const fields = {
      callId: String(callId),
      userA_id: userAId,
      userA_gender: userAGender,
      userB_id: userBId,
      userB_gender: userBGender,
      agoraChannelName,
      callType,
      startedAt,
      voiceStartedAt,
      videoStartedAt,
      totalAudioSeconds,
      totalVideoSeconds,
      maxAllowedSeconds,
      originNodeId: this.instanceId,
    };

    const pipeline = redis.pipeline();
    pipeline.hset(`call:active:${callId}`, fields);
    pipeline.expire(`call:active:${callId}`, 7200);
    pipeline.set(`user:call:${userAId}`, callId, 'EX', 7200);
    pipeline.set(`user:call:${userBId}`, callId, 'EX', 7200);
    pipeline.set(`call_lock:${userAId}`, '1', 'EX', 7200);
    pipeline.set(`call_lock:${userBId}`, '1', 'EX', 7200);
    // Backward compatibility for existing checks:
    pipeline.set(`user_active_call:${userAId}`, callId, 'EX', 7200);
    pipeline.set(`user_active_call:${userBId}`, callId, 'EX', 7200);
    await pipeline.exec();

    return fields;
  }

  async getActiveCall(redis, callId) {
    if (!redis || !callId) return null;
    try {
      const raw = await redis.hgetall(`call:active:${callId}`);
      if (!raw || Object.keys(raw).length === 0 || !raw.callId) return null;

      return {
        callId: raw.callId,
        userA: {
          userId: raw.userA_id,
          gender: raw.userA_gender,
        },
        userB: {
          userId: raw.userB_id,
          gender: raw.userB_gender,
        },
        userA_id: raw.userA_id,
        userA_gender: raw.userA_gender,
        userB_id: raw.userB_id,
        userB_gender: raw.userB_gender,
        agoraChannelName: raw.agoraChannelName,
        channelName: raw.agoraChannelName,
        callType: raw.callType,
        startedAt: parseInt(raw.startedAt, 10) || Date.now(),
        voiceStartedAt: raw.voiceStartedAt ? parseInt(raw.voiceStartedAt, 10) : null,
        videoStartedAt: raw.videoStartedAt ? parseInt(raw.videoStartedAt, 10) : null,
        totalAudioSeconds: parseInt(raw.totalAudioSeconds, 10) || 0,
        totalVideoSeconds: parseInt(raw.totalVideoSeconds, 10) || 0,
        maxAllowedSeconds: parseInt(raw.maxAllowedSeconds, 10) || 12000,
        originNodeId: raw.originNodeId,
      };
    } catch (err) {
      console.warn(`[DistributedCall] Error fetching call:active:${callId}:`, err.message);
      return null;
    }
  }

  async updateActiveCall(redis, callId, updates) {
    if (!redis || !callId || !updates) return;
    try {
      const fields = {};
      for (const [k, v] of Object.entries(updates)) {
        fields[k] = (v === null || v === undefined) ? '' : String(v);
      }
      await redis.hset(`call:active:${callId}`, fields);
    } catch (err) {
      console.warn(`[DistributedCall] Error updating call:active:${callId}:`, err.message);
    }
  }

  // ── Instant Connect Active Calls (Hash, TTL 7200s) ────────────────────────

  async saveActiveInstantCall(redis, callId, data) {
    if (!redis || !callId || !data) return null;
    const now = Date.now();

    const maleUserId = String(data.maleUserId);
    const femaleUserId = String(data.femaleUserId);
    const agoraChannelName = String(data.agoraChannelName || data.channelName || '');
    const callType = String(data.callType || 'voice');
    const startedAt = String(data.startedAt || now);
    const voiceStartedAt = String(data.voiceStartedAt !== undefined && data.voiceStartedAt !== null ? data.voiceStartedAt : (callType === 'voice' ? now : ''));
    const videoStartedAt = String(data.videoStartedAt !== undefined && data.videoStartedAt !== null ? data.videoStartedAt : (callType === 'video' ? now : ''));
    const totalAudioSeconds = String(data.totalAudioSeconds || 0);
    const totalVideoSeconds = String(data.totalVideoSeconds || 0);
    const milestoneReached = String(data.milestoneReached ? '1' : '0');

    const fields = {
      callId: String(callId),
      sessionId: String(data.sessionId),
      maleUserId,
      femaleUserId,
      bidAmount: String(data.bidAmount || 0),
      agoraChannelName,
      callType,
      startedAt,
      voiceStartedAt,
      videoStartedAt,
      totalAudioSeconds,
      totalVideoSeconds,
      milestoneReached,
      originNodeId: this.instanceId,
    };

    const pipeline = redis.pipeline();
    pipeline.hset(`instant:active:${callId}`, fields);
    pipeline.expire(`instant:active:${callId}`, 7200);
    pipeline.set(`user:call:${maleUserId}`, callId, 'EX', 7200);
    pipeline.set(`user:call:${femaleUserId}`, callId, 'EX', 7200);
    pipeline.set(`instant:in_call:${maleUserId}`, '1', 'EX', 7200);
    pipeline.set(`instant:in_call:${femaleUserId}`, '1', 'EX', 7200);
    pipeline.set(`call_lock:${maleUserId}`, '1', 'EX', 7200);
    pipeline.set(`call_lock:${femaleUserId}`, '1', 'EX', 7200);
    // Backward compatibility:
    pipeline.set(`instant:active_call:${callId}`, JSON.stringify(fields), 'EX', 7200);
    pipeline.set(`instant:user_call:${maleUserId}`, callId, 'EX', 7200);
    pipeline.set(`instant:user_call:${femaleUserId}`, callId, 'EX', 7200);
    await pipeline.exec();

    return fields;
  }

  async getActiveInstantCall(redis, callId) {
    if (!redis || !callId) return null;
    try {
      const raw = await redis.hgetall(`instant:active:${callId}`);
      if (!raw || Object.keys(raw).length === 0 || !raw.callId) {
        // Fallback for transition compatibility
        const str = await redis.get(`instant:active_call:${callId}`).catch(() => null);
        if (str) {
          try {
            return JSON.parse(str);
          } catch (_) {}
        }
        return null;
      }

      return {
        callId: raw.callId,
        sessionId: raw.sessionId,
        maleUserId: raw.maleUserId,
        femaleUserId: raw.femaleUserId,
        bidAmount: parseInt(raw.bidAmount, 10) || 0,
        agoraChannelName: raw.agoraChannelName,
        channelName: raw.agoraChannelName,
        callType: raw.callType,
        startedAt: parseInt(raw.startedAt, 10) || Date.now(),
        voiceStartedAt: raw.voiceStartedAt ? parseInt(raw.voiceStartedAt, 10) : null,
        videoStartedAt: raw.videoStartedAt ? parseInt(raw.videoStartedAt, 10) : null,
        totalAudioSeconds: parseInt(raw.totalAudioSeconds, 10) || 0,
        totalVideoSeconds: parseInt(raw.totalVideoSeconds, 10) || 0,
        milestoneReached: raw.milestoneReached === '1',
        originNodeId: raw.originNodeId,
      };
    } catch (err) {
      console.warn(`[DistributedCall] Error fetching instant:active:${callId}:`, err.message);
      return null;
    }
  }

  async updateActiveInstantCall(redis, callId, updates) {
    if (!redis || !callId || !updates) return;
    try {
      const fields = {};
      for (const [k, v] of Object.entries(updates)) {
        fields[k] = (v === null || v === undefined) ? '' : String(v);
      }
      await redis.hset(`instant:active:${callId}`, fields);
    } catch (err) {
      console.warn(`[DistributedCall] Error updating instant:active:${callId}:`, err.message);
    }
  }

  async deleteActiveInstantCall(redis, callId, maleUserId = null, femaleUserId = null) {
    if (!redis || !callId) return;
    try {
      const pipeline = redis.pipeline();
      pipeline.del(`instant:active:${callId}`);
      pipeline.del(`instant:active_call:${callId}`);
      if (maleUserId) {
        pipeline.del(`user:call:${maleUserId}`);
        pipeline.del(`instant:user_call:${maleUserId}`);
        pipeline.del(`instant:in_call:${maleUserId}`);
        pipeline.del(`call_lock:${maleUserId}`);
      }
      if (femaleUserId) {
        pipeline.del(`user:call:${femaleUserId}`);
        pipeline.del(`instant:user_call:${femaleUserId}`);
        pipeline.del(`instant:in_call:${femaleUserId}`);
        pipeline.del(`call_lock:${femaleUserId}`);
      }
      await pipeline.exec();
    } catch (err) {
      console.warn(`[DistributedCall] Error deleting instant call ${callId}:`, err.message);
    }
  }

  // ── Global User Call Lookup ───────────────────────────────────────────────

  async getUserCallId(redis, userId) {
    if (!redis || !userId) return null;
    return await redis.get(`user:call:${userId}`).catch(() => null);
  }

  // ── Distributed Termination Mutex (10s NX) ────────────────────────────────

  async endCallDistributed(io, redis, callId, reason = 'manual') {
    if (!redis || !callId) return false;
    const lockKey = `lock:call_end:${callId}`;
    const acquired = await redis.set(lockKey, '1', 'EX', 10, 'NX').catch(() => null);
    if (!acquired) {
      console.log(`🔒 [DistributedCall] Termination for ${callId} already in progress on another instance.`);
      return false;
    }

    try {
      // 1. Check if Direct / Matchmaking Call
      const callData = await this.getActiveCall(redis, callId);
      if (callData) {
        const endedAt = Date.now();
        let audioDurationSec = callData.totalAudioSeconds || 0;
        let videoDurationSec = callData.totalVideoSeconds || 0;

        if (callData.callType === 'video' && callData.videoStartedAt) {
          const elapsedVideo = Math.floor((endedAt - callData.videoStartedAt) / 1000);
          videoDurationSec += Math.max(0, elapsedVideo);
        } else {
          const voiceStart = callData.voiceStartedAt || callData.startedAt;
          const elapsedAudio = Math.floor((endedAt - voiceStart) / 1000);
          audioDurationSec += Math.max(0, elapsedAudio);
        }

        // Record monthly telecom fair-use quota
        callQuotaService.recordCallUsage(
          callData.userA.userId,
          callData.userB.userId,
          audioDurationSec,
          videoDurationSec
        ).catch((err) => console.error('[CallQuota] Error recording usage:', err.message));

        // Clean up Redis keys atomically
        const pipeline = redis.pipeline();
        pipeline.del(`call:active:${callId}`);
        pipeline.del(`active_call:${callId}`);
        pipeline.del(`user:call:${callData.userA.userId}`);
        pipeline.del(`user:call:${callData.userB.userId}`);
        pipeline.del(`user_active_call:${callData.userA.userId}`);
        pipeline.del(`user_active_call:${callData.userB.userId}`);
        pipeline.del(`call_lock:${callData.userA.userId}`);
        pipeline.del(`call_lock:${callData.userB.userId}`);
        pipeline.del(`peer_disconnect_timer:${callId}:${callData.userA.userId}`);
        pipeline.del(`peer_disconnect_timer:${callId}:${callData.userB.userId}`);
        await pipeline.exec();

        await Promise.all([
          cacheService.invalidate(`user:matches:${callData.userA.userId}`),
          cacheService.invalidate(`user:matches:${callData.userB.userId}`),
        ]).catch(() => {});

        // Instant cross-instance event dispatch via user rooms
        const endPayload = { callId, reason };
        if (io) {
          io.to(callData.userA.userId).emit('call_ended', endPayload);
          io.to(callData.userB.userId).emit('call_ended', endPayload);
        }

        // Persist to Postgres
        await callsService.endCall(callId).catch((err) => {
          console.error(`[Calls] DB endCall error for ${callId}:`, err.message);
        });

        console.log(`📴 [CallEnd] Distributed call ${callId} terminated: reason=${reason}`);
        return true;
      }

      // 2. Check if Instant Connect Call
      const instantData = await this.getActiveInstantCall(redis, callId);
      if (instantData) {
        const endedAt = Date.now();
        const durationSeconds = Math.floor((endedAt - instantData.startedAt) / 1000);

        let audioDurationSec = durationSeconds;
        let videoDurationSec = 0;
        if (instantData.totalVideoSeconds || instantData.videoStartedAt) {
          videoDurationSec = (instantData.totalVideoSeconds || 0) +
            (instantData.videoStartedAt ? Math.floor((endedAt - instantData.videoStartedAt) / 1000) : 0);
          audioDurationSec = Math.max(0, durationSeconds - videoDurationSec);
        } else if (instantData.callType === 'video') {
          videoDurationSec = durationSeconds;
          audioDurationSec = 0;
        }

        callQuotaService.recordCallUsage(
          instantData.maleUserId,
          instantData.femaleUserId,
          audioDurationSec,
          videoDurationSec
        ).catch(() => {});

        const finalStatus = durationSeconds >= 60 ? 'completed' : 'dropped';
        const endPayload = {
          callId,
          durationSeconds,
          status: finalStatus,
          reason,
        };

        const pipeline = redis.pipeline();
        pipeline.del(`instant:active:${callId}`);
        pipeline.del(`instant:active_call:${callId}`);
        pipeline.del(`user:call:${instantData.maleUserId}`);
        pipeline.del(`user:call:${instantData.femaleUserId}`);
        pipeline.del(`instant:user_call:${instantData.maleUserId}`);
        pipeline.del(`instant:user_call:${instantData.femaleUserId}`);
        pipeline.del(`instant:in_call:${instantData.femaleUserId}`);
        pipeline.del(`instant:in_call:${instantData.maleUserId}`);
        pipeline.del(`call_lock:${instantData.femaleUserId}`);
        pipeline.del(`call_lock:${instantData.maleUserId}`);
        pipeline.del(`peer_disconnect_timer:${callId}:${instantData.maleUserId}`);
        pipeline.del(`peer_disconnect_timer:${callId}:${instantData.femaleUserId}`);
        await pipeline.exec();

        if (io) {
          io.to(instantData.maleUserId).emit('instant:call_ended', endPayload);
          io.to(instantData.maleUserId).emit('call_ended', endPayload);
          io.to(instantData.femaleUserId).emit('instant:call_ended', endPayload);
          io.to(instantData.femaleUserId).emit('call_ended', endPayload);
        }

        const { instantConnectService } = require('../instant_connect/instant_connect.service');
        await instantConnectService.endCallSession(instantData.sessionId, finalStatus, durationSeconds).catch((err) => {
          console.error(`[Instant] DB endCallSession error for ${instantData.sessionId}:`, err.message);
        });

        // Refund male escrow if dropped before 1-minute milestone
        if (finalStatus === 'dropped' && instantData.maleUserId && instantData.bidAmount) {
          try {
            await instantConnectService.refundEscrowedCoins(instantData.maleUserId, instantData.bidAmount, instantData.sessionId);
          } catch (refundErr) {
            console.error('Error refunding male on dropped instant call:', refundErr.message);
          }
        }

        // Return female to pool if toggle is still ON
        try {
          const fStatus = await instantConnectService.getFemaleStatus(instantData.femaleUserId);
          if (fStatus && fStatus.incomingPaidCallsEnabled) {
            await redis.sadd('instant:female_pool', instantData.femaleUserId);
          }
        } catch (_) {}

        console.log(`⚡ [InstantEnd] Distributed instant call ${callId} terminated: reason=${reason}, status=${finalStatus}`);
        return true;
      }

      return false;
    } finally {
      await redis.del(lockKey).catch(() => {});
    }
  }

  // ── Peer Disconnect & Reconnection Recovery (Scenario 1) ──────────────────

  async handlePeerDisconnect(io, redis, userId, callId) {
    if (!userId || !callId || !redis) return;

    const activeCall = await this.getActiveCall(redis, callId) || await this.getActiveInstantCall(redis, callId);
    if (!activeCall) return;

    const otherUserId = (activeCall.userA?.userId === userId || activeCall.maleUserId === userId)
      ? (activeCall.userB?.userId || activeCall.femaleUserId)
      : (activeCall.userA?.userId || activeCall.maleUserId);

    const timerKey = `peer_disconnect_timer:${callId}:${userId}`;
    await redis.set(timerKey, '1', 'EX', 15);

    if (otherUserId && io) {
      io.to(otherUserId).emit('call_peer_disconnected', {
        callId,
        disconnectedUserId: userId,
        graceSeconds: 15,
      });
    }

    setTimeout(async () => {
      try {
        const stillInGrace = await redis.get(timerKey);
        const currentCallId = await redis.get(`user:call:${userId}`);
        if (stillInGrace && currentCallId === callId) {
          console.log(`⏱️ [PeerTimeout] User ${userId} did not reconnect within 15s for call ${callId}. Ending call.`);
          await this.endCallDistributed(io, redis, callId, 'peer_timeout');
        }
      } catch (err) {
        console.error(`Error in peer disconnect grace timeout for call ${callId}:`, err.message);
      }
    }, 15000);
  }

  async handleReconnection(socket, io, redis) {
    const userId = socket.userId;
    if (!userId || !redis) return null;

    try {
      const callId = await redis.get(`user:call:${userId}`);
      if (!callId) return null;

      // 1. Direct / Matched Call
      const callData = await this.getActiveCall(redis, callId);
      if (callData) {
        const elapsedSeconds = Math.floor((Date.now() - callData.startedAt) / 1000);
        if (callData.maxAllowedSeconds && elapsedSeconds >= callData.maxAllowedSeconds) {
          console.log(`⚠️ Reconnecting user ${userId} found call ${callId} exceeded quota. Terminating.`);
          await this.endCallDistributed(io, redis, callId, 'timeout');
          return null;
        }

        // Cancel disconnect grace timer
        await redis.del(`peer_disconnect_timer:${callId}:${userId}`);

        socket.activeCallId = callId;
        socket.activeCallType = 'direct';

        const otherUserId = callData.userA.userId === userId ? callData.userB.userId : callData.userA.userId;

        socket.emit('call_reconnected', {
          callId,
          agoraChannelName: callData.agoraChannelName,
          callType: callData.callType,
          elapsedSeconds,
          maxAllowedSeconds: callData.maxAllowedSeconds,
        });

        if (otherUserId && io) {
          io.to(otherUserId).emit('call_peer_reconnected', {
            callId,
            reconnectedUserId: userId,
          });
        }

        console.log(`🔄 [Recovery] User ${userId} recovered active direct call ${callId}`);
        return { callId, type: 'direct', callData };
      }

      // 2. Instant Call
      const instantData = await this.getActiveInstantCall(redis, callId);
      if (instantData) {
        const elapsedSeconds = Math.floor((Date.now() - instantData.startedAt) / 1000);
        await redis.del(`peer_disconnect_timer:${callId}:${userId}`);

        socket.activeCallId = callId;
        socket.activeCallType = 'instant';

        const otherUserId = instantData.maleUserId === userId ? instantData.femaleUserId : instantData.maleUserId;

        socket.emit('call_reconnected', {
          callId,
          agoraChannelName: instantData.agoraChannelName,
          callType: instantData.callType,
          elapsedSeconds,
          isInstant: true,
        });

        if (otherUserId && io) {
          io.to(otherUserId).emit('call_peer_reconnected', {
            callId,
            reconnectedUserId: userId,
          });
        }

        console.log(`🔄 [Recovery] User ${userId} recovered active instant call ${callId}`);
        return { callId, type: 'instant', instantData };
      }

      // Stale user:call mapping without active call record: clean it up
      await redis.del(`user:call:${userId}`);
      return null;
    } catch (err) {
      console.error(`[Recovery] Error checking active call for ${userId}:`, err.message);
      return null;
    }
  }
}

const distributedCallService = new DistributedCallService();

module.exports = {
  distributedCallService,
  DistributedCallService,
  NODE_INSTANCE_ID,
};
