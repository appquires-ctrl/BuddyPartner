const LEASE_TTL_SECONDS = 90; // 90s lease TTL (2x 45s refresh) for self-healing on crash / unclean disconnect
const DEBOUNCE_DISCONNECT_MS = 1500; // 1.5s grace period for mobile network handoffs

// In-memory timer map for debouncing rapid disconnect/reconnect cycles
const pendingDisconnects = new Map();

class PresenceService {
  /**
   * Broadcast presence update ONLY to targeted rooms (room for this user's subscribers & the user themselves).
   * High-scale fix: Global io.emit(...) removed to avoid O(N^2) socket packet flooding across instances.
   * @param {import('socket.io').Server} io
   * @param {string} userId
   * @param {boolean} isOnline
   */
  _broadcastPresence(io, userId, isOnline) {
    if (!io || !userId) return;

    const payload = {
      userId,
      isOnline,
      timestamp: new Date().toISOString(),
    };

    // 1. Broadcast to targeted presence room for subscribers/matches
    io.to(`presence_user:${userId}`).emit('presence:update', payload);

    // 2. Broadcast to personal user room
    io.to(userId).emit('presence:update', payload);

    // Global broadcast removed — scalable targeted room emits only
    console.log(`🌐 [Presence] User ${userId} is now ${isOnline ? 'ONLINE' : 'OFFLINE'} (targeted emit)`);
  }

  /**
   * Add a socket ID to the user's active socket set in Redis.
   * Emits 'online: true' if the user transitioned from offline (0 sockets) to online (1+ sockets).
   * Cancels any pending disconnect debouncer.
   * @param {import('ioredis').Redis} redis
   * @param {import('socket.io').Server} io
   * @param {string} userId
   * @param {string} socketId
   */
  async addSocket(redis, io, userId, socketId) {
    if (!userId || !socketId) return;

    // If there was a pending disconnect timer for this user, cancel it (user reconnected quickly)
    if (pendingDisconnects.has(userId)) {
      clearTimeout(pendingDisconnects.get(userId));
      pendingDisconnects.delete(userId);
    }

    try {
      const key = `online_sockets:${userId}`;

      // MULTI-INSTANCE RESILIENCE:
      // Do NOT check io.sockets.sockets.get(memberId) to prune "dead" sockets.
      // In multi-instance deployments, sockets belonging to other instances are not in this
      // process's local memory and would be erroneously deleted.
      // Sockets self-heal via LEASE_TTL_SECONDS (90s) and periodic 45s heartbeat refreshLease(),
      // while explicit disconnect removes individual sockets.
      const previousCount = await redis.scard(key);

      const pipeline = redis.pipeline();
      pipeline.sadd(key, socketId);
      pipeline.expire(key, LEASE_TTL_SECONDS);
      await pipeline.exec();

      // Only broadcast if transitioning from 0 -> 1 (newly online)
      if (previousCount === 0) {
        this._broadcastPresence(io, userId, true);
      }
    } catch (err) {
      console.error(`❌ [Presence] Error adding socket for user ${userId}:`, err.message);
    }
  }

  /**
   * Remove a socket ID from the user's active socket set in Redis.
   * Emits 'online: false' after a debounce grace period if no active sockets remain.
   * @param {import('ioredis').Redis} redis
   * @param {import('socket.io').Server} io
   * @param {string} userId
   * @param {string} socketId
   */
  async removeSocket(redis, io, userId, socketId) {
    if (!userId) return;

    try {
      const key = `online_sockets:${userId}`;

      if (socketId) {
        await redis.srem(key, socketId);
      }

      // MULTI-INSTANCE RESILIENCE:
      // Rely directly on Redis SCARD count. Avoid local socket checks that prune cross-instance sockets.
      const activeRemainingCount = await redis.scard(key);

      // If no active sockets remain, debounce the offline event
      if (activeRemainingCount === 0) {
        if (pendingDisconnects.has(userId)) {
          clearTimeout(pendingDisconnects.get(userId));
        }

        const timer = setTimeout(async () => {
          pendingDisconnects.delete(userId);
          // Re-verify that user hasn't reconnected during the debounce window
          const currentCount = await redis.scard(key);
          if (currentCount === 0) {
            await redis.del(key);
            this._broadcastPresence(io, userId, false);
          }
        }, DEBOUNCE_DISCONNECT_MS);

        pendingDisconnects.set(userId, timer);
      } else {
        // Refresh TTL for remaining active sockets
        await redis.expire(key, LEASE_TTL_SECONDS);
      }
    } catch (err) {
      console.error(`❌ [Presence] Error removing socket for user ${userId}:`, err.message);
    }
  }

  /**
   * Explicitly purge all presence for a user (e.g. on logout or account deletion).
   * @param {import('ioredis').Redis} redis
   * @param {import('socket.io').Server} io
   * @param {string} userId
   */
  async clearUserPresence(redis, io, userId) {
    if (!userId) return;

    if (pendingDisconnects.has(userId)) {
      clearTimeout(pendingDisconnects.get(userId));
      pendingDisconnects.delete(userId);
    }

    try {
      const key = `online_sockets:${userId}`;
      await redis.del(key);
      this._broadcastPresence(io, userId, false);
    } catch (err) {
      console.error(`❌ [Presence] Error clearing presence for user ${userId}:`, err.message);
    }
  }

  /**
   * Refresh lease TTL for a user's active socket set (e.g. on heartbeat / ping).
   * @param {import('ioredis').Redis} redis
   * @param {string} userId
   */
  async refreshLease(redis, userId) {
    if (!userId) return;
    try {
      const key = `online_sockets:${userId}`;
      await redis.expire(key, LEASE_TTL_SECONDS);
    } catch (err) {
      console.error(`❌ [Presence] Error refreshing lease for user ${userId}:`, err.message);
    }
  }

  /**
   * Check if a specific user currently has at least one active socket.
   * @param {import('ioredis').Redis} redis
   * @param {string} userId
   * @returns {Promise<boolean>}
   */
  async isUserOnline(redis, userId) {
    if (!userId) return false;
    try {
      const count = await redis.scard(`online_sockets:${userId}`);
      return count > 0;
    } catch (err) {
      console.error(`❌ [Presence] Error checking isUserOnline for ${userId}:`, err.message);
      return false;
    }
  }

  /**
   * Legacy adapter for backward compatibility.
   * @param {import('ioredis').Redis} redis
   * @param {import('socket.io').Server} io
   * @param {string} userId
   * @param {boolean} isOnline
   * @param {string} [socketId]
   */
  async setPresence(redis, io, userId, isOnline, socketId) {
    if (!userId) return;
    if (isOnline) {
      await this.addSocket(redis, io, userId, socketId || 'legacy_socket');
    } else if (socketId) {
      await this.removeSocket(redis, io, userId, socketId);
    } else {
      await this.clearUserPresence(redis, io, userId);
    }
  }

  /**
   * Subscribe a socket to targeted presence updates for specific user IDs.
   * @param {import('socket.io').Socket} socket
   * @param {string[]} userIds
   */
  subscribePresence(socket, userIds) {
    if (!socket || !Array.isArray(userIds)) return;
    userIds.forEach((id) => {
      if (id && typeof id === 'string') {
        socket.join(`presence_user:${id}`);
      }
    });
  }

  /**
   * Unsubscribe a socket from targeted presence updates for specific user IDs.
   * @param {import('socket.io').Socket} socket
   * @param {string[]} userIds
   */
  unsubscribePresence(socket, userIds) {
    if (!socket || !Array.isArray(userIds)) return;
    userIds.forEach((id) => {
      if (id && typeof id === 'string') {
        socket.leave(`presence_user:${id}`);
      }
    });
  }

  /**
   * Batch check online status for multiple user IDs using SCARD on Redis Sets.
   * @param {import('ioredis').Redis} redis
   * @param {string[]} userIds
   * @returns {Promise<Record<string, boolean>>} Map of userId -> isOnline
   */
  async getPresenceBatch(redis, userIds) {
    if (!userIds || userIds.length === 0) return {};

    try {
      const pipeline = redis.pipeline();
      userIds.forEach((id) => pipeline.scard(`online_sockets:${id}`));
      const results = await pipeline.exec();

      const presenceMap = {};
      userIds.forEach((id, index) => {
        const [err, count] = results[index];
        presenceMap[id] = !err && typeof count === 'number' && count > 0;
      });

      return presenceMap;
    } catch (err) {
      console.error('❌ [Presence] Error fetching batch presence:', err.message);
      return {};
    }
  }
}

module.exports = {
  PresenceService: new PresenceService(),
};
