const Redis = require('ioredis');

const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';

// ── In-Memory Resilient Fallback Store ────────────────────────────────────────
const memKv = new Map(); // key -> { val, expiresAt }
const memSets = new Map(); // key -> Set
const memSortedSets = new Map(); // key -> Map(member -> score)

function getKv(key) {
  const item = memKv.get(key);
  if (!item) return null;
  if (item.expiresAt && Date.now() > item.expiresAt) {
    memKv.delete(key);
    return null;
  }
  return item.val;
}

function setKv(key, val, exSeconds, nx) {
  if (nx && getKv(key) !== null) {
    return null;
  }
  const expiresAt = exSeconds ? Date.now() + exSeconds * 1000 : null;
  memKv.set(key, { val: String(val), expiresAt });
  return 'OK';
}

function delKey(key) {
  let count = 0;
  if (memKv.delete(key)) count++;
  if (memSets.delete(key)) count++;
  if (memSortedSets.delete(key)) count++;
  return count;
}

const inMemoryClient = {
  isInMemory: true,
  async get(key) {
    return getKv(key);
  },
  async set(key, val, ...args) {
    let exSeconds = null;
    let nx = false;
    for (let i = 0; i < args.length; i++) {
      const arg = String(args[i]).toUpperCase();
      if (arg === 'EX' && i + 1 < args.length) {
        exSeconds = parseInt(args[i + 1], 10);
        i++;
      } else if (arg === 'NX') {
        nx = true;
      }
    }
    // Distributed lock safety: fail closed on cross-instance mutexes when Redis is partitioned
    if (nx && (key.startsWith('direct_mutex:') || key.startsWith('instant:claim_session:') || key.startsWith('instant:claimed:'))) {
      console.warn(`🔒 [REDIS LOCK FAIL-CLOSED] Refusing to grant distributed lock '${key}' from in-memory fallback during Redis partition.`);
      return null;
    }
    return setKv(key, val, exSeconds, nx);
  },
  async del(key) {
    return delKey(key);
  },
  async sadd(key, ...members) {
    if (!memSets.has(key)) memSets.set(key, new Set());
    const set = memSets.get(key);
    let added = 0;
    for (const m of members) {
      if (!set.has(String(m))) {
        set.add(String(m));
        added++;
      }
    }
    return added;
  },
  async srem(key, ...members) {
    const set = memSets.get(key);
    if (!set) return 0;
    let removed = 0;
    for (const m of members) {
      if (set.delete(String(m))) removed++;
    }
    return removed;
  },
  async smembers(key) {
    const set = memSets.get(key);
    return set ? Array.from(set) : [];
  },
  async scard(key) {
    const set = memSets.get(key);
    return set ? set.size : 0;
  },
  async expire(key, seconds) {
    return 1;
  },
  async zadd(key, score, member) {
    if (!memSortedSets.has(key)) memSortedSets.set(key, new Map());
    const zset = memSortedSets.get(key);
    zset.set(String(member), Number(score));
    return 1;
  },
  async zscore(key, member) {
    const zset = memSortedSets.get(key);
    if (!zset || !zset.has(String(member))) return null;
    return String(zset.get(String(member)));
  },
  async zrem(key, member) {
    const zset = memSortedSets.get(key);
    if (!zset) return 0;
    return zset.delete(String(member)) ? 1 : 0;
  },
  async zrevrank(key, member) {
    const zset = memSortedSets.get(key);
    if (!zset || !zset.has(String(member))) return null;
    const sorted = Array.from(zset.entries()).sort((a, b) => b[1] - a[1]);
    const idx = sorted.findIndex(([m]) => m === String(member));
    return idx === -1 ? null : idx;
  },
  async zrevrange(key, start, stop, withScores) {
    const zset = memSortedSets.get(key);
    if (!zset) return [];
    let sorted = Array.from(zset.entries()).sort((a, b) => b[1] - a[1]);
    const end = stop === -1 ? sorted.length : stop + 1;
    const slice = sorted.slice(start, end);
    if (String(withScores).toUpperCase() === 'WITHSCORES') {
      const flat = [];
      for (const [m, s] of slice) {
        flat.push(m, String(s));
      }
      return flat;
    }
    return slice.map(([m]) => m);
  },
  async scan(cursor, ...args) {
    let matchPattern = '*';
    for (let i = 0; i < args.length; i++) {
      if (String(args[i]).toUpperCase() === 'MATCH' && i + 1 < args.length) {
        matchPattern = String(args[i + 1]);
        i++;
      }
    }
    const regex = new RegExp('^' + matchPattern.replace(/\*/g, '.*') + '$');
    const matched = [];
    for (const key of memKv.keys()) {
      if (regex.test(key)) {
        matched.push(key);
      }
    }
    return ['0', matched];
  },
  pipeline() {
    const operations = [];
    return {
      get(k) {
        operations.push(() => [null, getKv(k)]);
        return this;
      },
      set(k, v, ...args) {
        operations.push(() => [null, setKv(k, v)]);
        return this;
      },
      del(k) {
        operations.push(() => [null, delKey(k)]);
        return this;
      },
      sadd(k, ...members) {
        operations.push(() => {
          if (!memSets.has(k)) memSets.set(k, new Set());
          const set = memSets.get(k);
          let added = 0;
          for (const m of members) {
            if (!set.has(String(m))) {
              set.add(String(m));
              added++;
            }
          }
          return [null, added];
        });
        return this;
      },
      srem(k, ...members) {
        operations.push(() => {
          const set = memSets.get(k);
          if (!set) return [null, 0];
          let removed = 0;
          for (const m of members) {
            if (set.delete(String(m))) removed++;
          }
          return [null, removed];
        });
        return this;
      },
      scard(k) {
        operations.push(() => {
          const set = memSets.get(k);
          return [null, set ? set.size : 0];
        });
        return this;
      },
      expire(k, sec) {
        operations.push(() => [null, 1]);
        return this;
      },
      async exec() {
        return operations.map((fn) => fn());
      },
    };
  },
};

// ── Hybrid Connection Manager & Resilience Layer ────────────────────────────
/**
 * ARCHITECTURE & RESILIENCE TRADEOFF NOTE FOR ENGINEERS:
 * -------------------------------------------------------------------------
 * The inMemoryClient fallback below provides short-term resilience for brief
 * transient Redis outages (e.g. network blips of 1-3 seconds).
 *
 * CRITICAL WARNING:
 * 1. The in-memory fallback store is STRICTLY LOCAL to this Node.js process.
 *    In multi-instance deployments (e.g. horizontal clustering with 2+ replicas),
 *    instances CANNOT share in-memory state. Active sockets, call locks, presence,
 *    and instant queues will desynchronize across instances if real Redis stays down.
 * 2. In-memory data is completely wiped on any process restart or crash.
 * 3. Therefore, in-memory fallback is an emergency buffer to prevent immediate crashes,
 *    NOT a long-term operating mode or horizontal scaling solution.
 * 4. realRedis must continuously retry with capped backoff to re-establish the
 *    shared Redis connection as soon as Redis recovers.
 * -------------------------------------------------------------------------
 */
let isConnected = false;
let hadDisconnected = false;
let lastFallbackWarningTime = 0;
let fallbackWarningCount = 0;
const FALLBACK_LOG_THROTTLE_MS = 30000;

function logFallbackWarning(operation = 'command') {
  fallbackWarningCount++;
  const now = Date.now();
  if (now - lastFallbackWarningTime > FALLBACK_LOG_THROTTLE_MS) {
    lastFallbackWarningTime = now;
    console.warn(`🚨 [REDIS FALLBACK ACTIVE] Real Redis is disconnected. Serving '${operation}' from in-memory fallback (total incidents: ${fallbackWarningCount}). Multi-instance sync is PAUSED until reconnect.`);
  }
}

const realRedis = new Redis(redisUrl, {
  maxRetriesPerRequest: 20,
  enableOfflineQueue: true,
  retryStrategy(times) {
    const delay = Math.min(times * 200, 5000); // exponential-ish, capped at 5s
    return delay;
  },
  lazyConnect: false,
});

realRedis.on('connect', () => {
  if (hadDisconnected) {
    console.log('✅ [REDIS] Reconnected — resuming normal operation, in-memory fallback deactivated.');
    hadDisconnected = false;
  } else {
    console.log('✅ Redis client connected');
  }
  isConnected = true;
});

realRedis.on('ready', () => {
  if (hadDisconnected) {
    console.log('✅ [REDIS] Reconnected — resuming normal operation, in-memory fallback deactivated.');
    hadDisconnected = false;
  }
  isConnected = true;
});

realRedis.on('error', (err) => {
  if (isConnected) {
    console.error('❌ Redis disconnected, switching to in-memory fallback:', err.message);
    hadDisconnected = true;
  }
  isConnected = false;
});

realRedis.on('close', () => {
  if (isConnected) {
    console.warn('⚠️ [REDIS] Connection closed, switching to in-memory fallback.');
    hadDisconnected = true;
  }
  isConnected = false;
});

// Proxy handler to seamlessly route commands to real Redis if connected, or inMemoryClient
const redisProxy = new Proxy(realRedis, {
  get(target, prop) {
    if (prop === 'isHealthy') {
      return () => isConnected;
    }
    if (prop === 'isInMemory') {
      return !isConnected;
    }
    if (prop === 'getMetrics') {
      return () => ({
        isConnected,
        hadDisconnected,
        fallbackWarningCount,
        lastFallbackWarningTime,
      });
    }
    if (prop === 'fallbackWarningCount') {
      return fallbackWarningCount;
    }
    if (prop === 'pipeline') {
      return function (...args) {
        if (isConnected) {
          try {
            return target.pipeline(...args);
          } catch (err) {
            isConnected = false;
            hadDisconnected = true;
            logFallbackWarning('pipeline');
            return inMemoryClient.pipeline(...args);
          }
        }
        logFallbackWarning('pipeline');
        return inMemoryClient.pipeline(...args);
      };
    }
    if (typeof inMemoryClient[prop] === 'function') {
      return async function (...args) {
        if (isConnected) {
          try {
            return await target[prop](...args);
          } catch (err) {
            isConnected = false;
            hadDisconnected = true;
            logFallbackWarning(String(prop));
            return await inMemoryClient[prop](...args);
          }
        }
        logFallbackWarning(String(prop));
        return await inMemoryClient[prop](...args);
      };
    }
    if (typeof target[prop] === 'function') {
      return target[prop].bind(target);
    }
    return target[prop];
  },
});

module.exports = redisProxy;
