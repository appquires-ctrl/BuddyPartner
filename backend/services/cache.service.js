const redis = require('../redis');

class CacheService {
  /**
   * Get cached value or execute fetchFn and cache the result
   * @param {string} key - Cache key
   * @param {number} ttlSeconds - Time to live in seconds
   * @param {() => Promise<any>} fetchFn - Factory function called on cache miss
   * @returns {Promise<any>}
   */
  async getOrSet(key, ttlSeconds, fetchFn) {
    try {
      const cached = await redis.get(key);
      if (cached !== null && cached !== undefined) {
        try {
          return JSON.parse(cached);
        } catch {
          return cached;
        }
      }
    } catch (err) {
      console.warn(`[Cache Warning] Failed to read key ${key}:`, err.message);
    }

    // Cache miss or read failure: execute underlying query
    const freshData = await fetchFn();

    if (freshData !== undefined && freshData !== null) {
      try {
        const serialized = typeof freshData === 'string' ? freshData : JSON.stringify(freshData);
        await redis.set(key, serialized, 'EX', ttlSeconds);
      } catch (err) {
        console.warn(`[Cache Warning] Failed to write key ${key}:`, err.message);
      }
    }

    return freshData;
  }

  /**
   * Invalidate a single cache key
   * @param {string} key
   */
  async invalidate(key) {
    try {
      await redis.del(key);
    } catch (err) {
      console.warn(`[Cache Warning] Failed to delete key ${key}:`, err.message);
    }
  }

  /**
   * Invalidate multiple keys by pattern prefix
   * @param {string} prefix
   */
  async invalidatePrefix(prefix) {
    try {
      if (redis.isInMemory) {
        // Fallback for memory store
        await redis.del(prefix);
        return;
      }
      // Scan and delete in small batches to avoid blocking Redis
      let cursor = '0';
      do {
        const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', `${prefix}*`, 'COUNT', 100);
        cursor = nextCursor;
        if (keys && keys.length > 0) {
          await redis.del(...keys);
        }
      } while (cursor !== '0');
    } catch (err) {
      console.warn(`[Cache Warning] Failed to delete prefix ${prefix}:`, err.message);
    }
  }
}

const cacheService = new CacheService();

module.exports = {
  CacheService,
  cacheService,
};
