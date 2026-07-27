class PresenceService {
  /**
   * Set a user's online status in Redis and broadcast the update via Socket.io.
   * @param {import('ioredis').Redis} redis
   * @param {import('socket.io').Server} io
   * @param {string} userId
   * @param {boolean} isOnline
   */
  async setPresence(redis, io, userId, isOnline) {
    if (!userId) return;

    try {
      const key = `online:${userId}`;
      if (isOnline) {
        // Set online status in Redis with a 24-hour TTL
        await redis.set(key, '1', 'EX', 86400);
      } else {
        await redis.del(key);
      }

      // Broadcast presence update event to all connected sockets
      io.emit('presence:update', {
        userId,
        isOnline,
        timestamp: new Date().toISOString(),
      });
      console.log(`🌐 [Presence] User ${userId} is now ${isOnline ? 'ONLINE' : 'OFFLINE'}`);
    } catch (err) {
      console.error(`❌ [Presence] Error setting presence for user ${userId}:`, err.message);
    }
  }

  /**
   * Batch check online status for multiple user IDs.
   * @param {import('ioredis').Redis} redis
   * @param {string[]} userIds
   * @returns {Promise<Record<string, boolean>>} Map of userId -> isOnline
   */
  async getPresenceBatch(redis, userIds) {
    if (!userIds || userIds.length === 0) return {};

    try {
      const pipeline = redis.pipeline();
      userIds.forEach((id) => pipeline.get(`online:${id}`));
      const results = await pipeline.exec();

      const presenceMap = {};
      userIds.forEach((id, index) => {
        const [err, val] = results[index];
        presenceMap[id] = !err && val === '1';
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
