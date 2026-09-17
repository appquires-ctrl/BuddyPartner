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
