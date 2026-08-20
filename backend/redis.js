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
  pipeline() {
    const operations = [];
    return {
      get(k) {
        operations.push(() => [null, getKv(k)]);
        return this;
      },
      async exec() {
        return operations.map((fn) => fn());
      },
    };
  },
};

// ── Hybrid Connection Manager ───────────────────────────────────────────────
let isConnected = false;

const realRedis = new Redis(redisUrl, {
  maxRetriesPerRequest: 1,
  retryStrategy(times) {
    if (times > 3) return null; // Stop retrying quickly to avoid blocking
    return 500;
  },
  lazyConnect: false,
});

realRedis.on('connect', () => {
  isConnected = true;
  console.log('✅ Redis client connected');
});

realRedis.on('error', (err) => {
  if (isConnected) {
    console.error('❌ Redis disconnected, switching to in-memory fallback:', err.message);
  }
  isConnected = false;
});

// Proxy handler to seamlessly route commands to real Redis if connected, or inMemoryClient
const redisProxy = new Proxy(realRedis, {
  get(target, prop) {
    if (prop === 'isInMemory') {
      return !isConnected;
    }
    if (typeof inMemoryClient[prop] === 'function') {
      return async function (...args) {
        if (isConnected) {
          try {
            return await target[prop](...args);
          } catch (err) {
            isConnected = false;
            return await inMemoryClient[prop](...args);
          }
        }
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
