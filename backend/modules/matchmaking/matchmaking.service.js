const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const QUEUE_KEY = 'matchmaking:queue';
const USER_SOCKET_MAP_KEY = 'matchmaking:user_socket'; // hash: userId → socketId
const MATCH_LUA_SCRIPT = fs.readFileSync(
  path.join(__dirname, 'match.lua'),
  'utf-8',
);

class MatchmakingService {
  constructor(redis) {
    this.redis = redis;
  }

  /**
   * Add a user to the matchmaking queue.
   * Uses a sorted set with timestamp as score for FIFO fairness.
   * Guards against duplicate entries.
   *
   * @param {string} userId
   * @param {string} socketId
   * @returns {boolean} true if added, false if already in queue
   */
  async joinQueue(userId, socketId) {
    // Check if user is already in the queue
    const existingScore = await this.redis.zscore(QUEUE_KEY, `${userId}:${socketId}`);
    if (existingScore !== null) {
      return false; // Already queued
    }

    // Also check if this userId has any existing entry (different socket)
    const existingSocketId = await this.redis.hget(USER_SOCKET_MAP_KEY, userId);
    if (existingSocketId) {
      // Remove stale entry
      const members = await this.redis.zrangebyscore(QUEUE_KEY, '-inf', '+inf');
      for (const member of members) {
        if (member.startsWith(`${userId}:`)) {
          await this.redis.zrem(QUEUE_KEY, member);
          break;
        }
      }
    }

    const score = Date.now();
    await this.redis.zadd(QUEUE_KEY, score, `${userId}:${socketId}`);
    await this.redis.hset(USER_SOCKET_MAP_KEY, userId, socketId);

    return true;
  }

  /**
   * Remove a user from the matchmaking queue.
   *
   * @param {string} userId
   */
  async leaveQueue(userId) {
    const socketId = await this.redis.hget(USER_SOCKET_MAP_KEY, userId);
    if (socketId) {
      await this.redis.zrem(QUEUE_KEY, `${userId}:${socketId}`);
      await this.redis.hdel(USER_SOCKET_MAP_KEY, userId);
    }

    // Fallback: scan and remove any entries for this userId
    const members = await this.redis.zrangebyscore(QUEUE_KEY, '-inf', '+inf');
    for (const member of members) {
      if (member.startsWith(`${userId}:`)) {
        await this.redis.zrem(QUEUE_KEY, member);
      }
    }
  }

  /**
   * Attempt to match two users atomically using the Lua script.
   * Returns the matched pair or null if fewer than 2 users are queued.
   *
   * @returns {{ userA: { userId, socketId }, userB: { userId, socketId } } | null}
   */
  async tryMatch() {
    const result = await this.redis.eval(MATCH_LUA_SCRIPT, 1, QUEUE_KEY);

    if (!result || result.length < 2) {
      return null;
    }

    // Each result member is "userId:socketId"
    const [memberA, memberB] = result;
    const [userIdA, socketIdA] = this._parseMember(memberA);
    const [userIdB, socketIdB] = this._parseMember(memberB);

    // Clean up the user→socket mapping
    await this.redis.hdel(USER_SOCKET_MAP_KEY, userIdA);
    await this.redis.hdel(USER_SOCKET_MAP_KEY, userIdB);

    return {
      userA: { userId: userIdA, socketId: socketIdA },
      userB: { userId: userIdB, socketId: socketIdB },
    };
  }

  /**
   * Generate a unique Agora channel name for a call.
   *
   * @returns {string}
   */
  generateChannelName() {
    return `loopcall_${crypto.randomBytes(8).toString('hex')}`;
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

  /**
   * Parse a "userId:socketId" member string.
   * Handles UUIDs that contain colons (they don't, but defensive coding).
   *
   * @param {string} member
   * @returns {[string, string]} [userId, socketId]
   */
  _parseMember(member) {
    // UUID is 36 chars (8-4-4-4-12), socketId follows after first ':'
    // But UUID doesn't contain ':', so simple split works
    const colonIdx = member.indexOf(':');
    return [member.substring(0, colonIdx), member.substring(colonIdx + 1)];
  }
}

module.exports = { MatchmakingService, QUEUE_KEY };
