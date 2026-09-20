const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Gender-specific queue keys
const MALE_QUEUE_KEY = 'queue:male';
const FEMALE_QUEUE_KEY = 'queue:female';
const USER_SOCKET_MAP_KEY = 'matchmaking:user_socket'; // hash: userId → socketId
const USER_GENDER_MAP_KEY = 'matchmaking:user_gender'; // hash: userId → gender
const USER_QUEUE_MAP_KEY = 'matchmaking:user_queue'; // hash: userId → queueKey|member (O(1) reverse lookup)

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
    const member = `${userId}:${socketId}`;
    await this.redis.zadd(queueKey, score, member);
    await this.redis.hset(USER_SOCKET_MAP_KEY, userId, socketId);
    await this.redis.hset(USER_GENDER_MAP_KEY, userId, gender);
    await this.redis.hset(USER_QUEUE_MAP_KEY, userId, `${queueKey}|${member}`);

    return true;
  }

  /**
   * Remove a user from all matchmaking queues in O(1) time.
   *
   * @param {string} userId
   */
  async leaveQueue(userId) {
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

    // Clean up the user→socket, user→gender, and user→queue mappings
    await Promise.all([
      this.redis.hdel(USER_SOCKET_MAP_KEY, maleUserId),
      this.redis.hdel(USER_SOCKET_MAP_KEY, femaleUserId),
      this.redis.hdel(USER_GENDER_MAP_KEY, maleUserId),
      this.redis.hdel(USER_GENDER_MAP_KEY, femaleUserId),
      this.redis.hdel(USER_QUEUE_MAP_KEY, maleUserId),
      this.redis.hdel(USER_QUEUE_MAP_KEY, femaleUserId),
    ]);

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
    const [socketId, queueMapping] = await Promise.all([
      this.redis.hget(USER_SOCKET_MAP_KEY, userId),
      this.redis.hget(USER_QUEUE_MAP_KEY, userId),
    ]);

    const removals = [];

    // O(1) removal using reverse-lookup hash matchmaking:user_queue
    if (queueMapping) {
      const [queueKey, member] = queueMapping.split('|');
      if (queueKey && member) {
        removals.push(this.redis.zrem(queueKey, member));
      }
    }

    if (socketId) {
      const member = `${userId}:${socketId}`;
      removals.push(this.redis.zrem(MALE_QUEUE_KEY, member));
      removals.push(this.redis.zrem(FEMALE_QUEUE_KEY, member));
    }

    removals.push(this.redis.hdel(USER_SOCKET_MAP_KEY, userId));
    removals.push(this.redis.hdel(USER_GENDER_MAP_KEY, userId));
    removals.push(this.redis.hdel(USER_QUEUE_MAP_KEY, userId));

    await Promise.all(removals);
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
