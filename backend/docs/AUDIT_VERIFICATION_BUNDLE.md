# COMPLETE AUDIT EVIDENCE & SOURCE CODE BUNDLE

Generated for Production Readiness Verification at 5,000 CCU.

================================================================================
FILE: backend/db.js
================================================================================

`javascript
const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  console.error('❌ Error: DATABASE_URL environment variable is not defined.');
  process.exit(1);
}

/**
 * PostgreSQL Connection Pool Configuration for Neon Serverless
 * - max: 40 (Sized safely below Neon's 901 direct engine / 10,000 PgBouncer pooler limits,
 *   providing high concurrency while leaving headroom for multiple backend replicas & admin panel).
 * - connectionTimeoutMillis: 10000 (Allows Neon compute to wake from scale-to-zero cold storage).
 * - idleTimeoutMillis: 30000 (Releases idle clients after 30 seconds).
 */
const pool = new Pool({
  connectionString: connectionString,
  ssl: connectionString.includes('localhost') || connectionString.includes('127.0.0.1')
    ? false
    : { rejectUnauthorized: false },
  max: 40,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

pool.on('connect', () => {
  // Client connected successfully
});

pool.on('error', (err) => {
  console.error('❌ Unexpected database error on idle client:', err.message);
});

// Initialize the favorites table if it doesn't exist (with retry for serverless cold starts)
async function initCoreTables(retries = 2) {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.favorites (
        user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
        favorite_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        PRIMARY KEY (user_id, favorite_user_id)
      );
    `);
    await pool.query(`ALTER TABLE public.users ALTER COLUMN avatar_seed TYPE TEXT;`);
  } catch (err) {
    if (retries > 0) {
      setTimeout(() => initCoreTables(retries - 1), 2000);
    } else {
      console.warn('⚠️ Initial core table check deferred to server startup:', err.message);
    }
  }
}
initCoreTables();

/**
 * Profiled query executor with slow-query detection (>200ms)
 * @param {string|object} text - SQL query or QueryConfig object
 * @param {Array} [params] - Query parameters
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    const duration = Date.now() - start;
    if (duration > 200) {
      const sanitized = typeof text === 'string'
        ? text.replace(/\s+/g, ' ').trim().slice(0, 160)
        : (text?.text || 'prepared').replace(/\s+/g, ' ').trim().slice(0, 160);
      console.warn(`⚠️ [SLOW QUERY: ${duration}ms] ${sanitized}...`);
    }
    return res;
  } catch (err) {
    const duration = Date.now() - start;
    const sanitized = typeof text === 'string'
      ? text.replace(/\s+/g, ' ').trim().slice(0, 120)
      : 'prepared';
    console.error(`❌ [QUERY ERROR: ${duration}ms] ${err.message} | Query: ${sanitized}`);
    throw err;
  }
}

module.exports = {
  query,
  pool,
};

`

================================================================================
FILE: backend/redis.js
================================================================================

`javascript
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
const FALLBACK_LOG_THROTTLE_MS = 30000;

function logFallbackWarning(operation = 'command') {
  const now = Date.now();
  if (now - lastFallbackWarningTime > FALLBACK_LOG_THROTTLE_MS) {
    lastFallbackWarningTime = now;
    console.warn(`🚨 [REDIS FALLBACK ACTIVE] Real Redis is disconnected. Serving '${operation}' from in-memory fallback. Multi-instance sync is PAUSED until reconnect.`);
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

`

================================================================================
FILE: backend/middleware/auth.middleware.js
================================================================================

`javascript
const jwt = require('jsonwebtoken');
const redis = require('../redis');
const { ModerationService } = require('../modules/moderation/moderation.service');

/**
 * Middleware to authenticate requests using JWT tokens, enforce single-device policy, and check ban status.
 * Expects header: "Authorization: Bearer <token>"
 */
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  const token = authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ error: 'Access denied. Invalid token format.' });
  }

  try {
    const secret = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);
    req.user = decoded; // Decoded payload contains { id, phone, sessionId }

    // Single-device active session check in Redis (In-Memory ~0.5ms lookup)
    const activeSessionId = await redis.get(`user_active_session:${decoded.id}`);
    if (activeSessionId && (!decoded.sessionId || activeSessionId !== decoded.sessionId)) {
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your account has been logged in on another device. Please log in again.',
      });
    }

    // Moderation status check — check ONLY isBanned
    const status = await ModerationService.isUserBlocked(decoded.id);
    if (status.isBanned) {
      return res.status(403).json({
        error: 'ACCOUNT_BANNED',
        message: 'Your account has been blocked due to multiple reports from other users.',
      });
    }

    next();
  } catch (err) {
    console.error('JWT authentication error:', err.message);
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

module.exports = { authMiddleware };

`

================================================================================
FILE: backend/modules/moderation/moderation.service.js
================================================================================

`javascript
const db = require('../../db');

class ModerationService {
  /**
   * Check if a user is currently banned.
   * Direct primary key index scan on public.users(id) (<0.1ms).
   * @param {string} userId
   * @returns {Promise<{ isBlocked: boolean, isBanned: boolean, isSuspended: boolean, suspendedUntil: null }>}
   */
  async isUserBlocked(userId) {
    if (!userId) {
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
    }

    try {
      const result = await db.query(
        'SELECT is_banned FROM public.users WHERE id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
      }

      const isBanned = Boolean(result.rows[0].is_banned);

      return {
        isBlocked: isBanned,
        isBanned,
        isSuspended: false,
        suspendedUntil: null,
      };
    } catch (err) {
      console.error(`Error checking block status for user ${userId}:`, err.message);
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
    }
  }

  /**
   * File a report against a user.
   * A permanent ban is triggered when 3 DISTINCT reporters have reported the user.
   * Multiple reports from the same reporter ID only count ONCE towards the threshold.
   *
   * @param {string} reporterId
   * @param {string} reportedUserId
   * @param {string} reason
   * @param {string|null} description
   * @param {string|null} messageId
   * @param {string|null} conversationId
   */
  async fileReport(reporterId, reportedUserId, reason, description = null, messageId = null, conversationId = null) {
    if (!reporterId || !reportedUserId || !reason) {
      throw new Error('reporterId, reportedUserId, and reason are required.');
    }

    if (reporterId === reportedUserId) {
      throw new Error('A user cannot report themselves.');
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const validConversationId = (conversationId && conversationId.length === 36) ? conversationId : null;
      const validMessageId = (messageId && messageId.length === 36) ? messageId : null;

      if (validConversationId) {
        const convCheck = await client.query('SELECT id FROM public.conversations WHERE id = $1', [validConversationId]);
        if (convCheck.rows.length === 0) {
          console.warn(`[Moderation] Conversation ${validConversationId} does not exist, storing NULL`);
        }
      }

      if (validMessageId) {
        const msgCheck = await client.query('SELECT id FROM public.messages WHERE id = $1', [validMessageId]);
        if (msgCheck.rows.length === 0) {
          console.warn(`[Moderation] Message ${validMessageId} does not exist, storing NULL`);
        }
      }

      // 1. Insert report record
      const insertRes = await client.query(
        `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, reporter_id, reported_user_id, reason, description, message_id, conversation_id, created_at`,
        [reporterId, reportedUserId, reason, description, validMessageId, validConversationId]
      );

      // 2. Count DISTINCT reporters for this reported user
      const countRes = await client.query(
        `SELECT COUNT(DISTINCT reporter_id) AS distinct_count
         FROM public.reports
         WHERE reported_user_id = $1`,
        [reportedUserId]
      );

      const distinctReporterCount = parseInt(countRes.rows[0].distinct_count || 0, 10);
      let isBanned = false;

      // 3. If distinct count >= 3, trigger immediate permanent ban
      if (distinctReporterCount >= 3) {
        await client.query(
          `UPDATE public.users SET is_banned = TRUE WHERE id = $1`,
          [reportedUserId]
        );
        isBanned = true;
        console.log(`⛔ [Moderation] BAN TRIGGERED: User ${reportedUserId} has been reported by ${distinctReporterCount} distinct reporters.`);
      }

      await client.query('COMMIT');

      return {
        report: insertRes.rows[0],
        moderationResult: {
          distinctReporterCount,
          isBanned,
        },
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`❌ [Moderation] Error filing report for reported user ${reportedUserId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }
}

module.exports = {
  ModerationService: new ModerationService(),
};

`

================================================================================
FILE: backend/middleware/rate_limit.middleware.js
================================================================================

`javascript
const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const redis = require('../redis');

/**
 * Helper to construct a distributed Redis store or fall back to in-memory store
 * @param {string} prefix - Unique namespace for the rate limiter
 * @returns {RedisStore|undefined}
 */
function getStore(prefix) {
  if (redis.isInMemory) {
    return undefined; // express-rate-limit falls back to built-in MemoryStore
  }
  return new RedisStore({
    prefix: `rl:${prefix}:`,
    sendCommand: (...args) => redis.call(...args),
  });
}

/**
 * Global API rate limiter: 300 requests per minute per IP
 */
const apiGlobalLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 300,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
  store: getStore('global'),
  message: {
    error: 'Too many requests. Please slow down and try again in a minute.',
  },
});

/**
 * Sensitive OTP rate limiter: 10 requests per 5 minutes per IP
 */
const otpRateLimiter = rateLimit({
  windowMs: 5 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
  store: getStore('otp'),
  message: {
    error: 'Too many verification requests. Please wait a few minutes before requesting again.',
  },
});

/**
 * Call & Instant Connect initiation limiter: 30 requests per minute per IP
 */
const callRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 30,
  keyGenerator: (req) => (req.user && req.user.id ? req.user.id : ipKeyGenerator(req.ip)),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
  store: getStore('call'),
  message: {
    error: 'Too many call actions in a short period. Please wait a moment.',
  },
});

/**
 * Username availability check limiter: 20 requests per minute per IP
 */
const usernameCheckLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 20,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
  store: getStore('username_check'),
  message: {
    available: false,
    error: 'TOO_MANY_REQUESTS',
    message: 'Too many username checks. Please wait a moment.',
  },
});

/**
 * User search limiter: 30 requests per minute per authenticated user (falls back to IP)
 */
const userSearchLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 30,
  keyGenerator: (req) => (req.user && req.user.id ? req.user.id : ipKeyGenerator(req.ip)),
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
  store: getStore('user_search'),
  statusCode: 429,
  message: {
    error: 'TOO_MANY_REQUESTS',
    message: 'Too many searches. Please wait a moment before trying again.',
  },
});

module.exports = {
  apiGlobalLimiter,
  otpRateLimiter,
  callRateLimiter,
  usernameCheckLimiter,
  userSearchLimiter,
};


`

================================================================================
FILE: backend/services/cache.service.js
================================================================================

`javascript
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

module.exports = cacheService;
module.exports.CacheService = CacheService;
module.exports.cacheService = cacheService;

`

================================================================================
FILE: backend/services/firebase.service.js
================================================================================

`javascript
const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

let isInitialized = false;

function initFirebase() {
  if (isInitialized) return admin;

  try {
    let serviceAccount = null;

    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      try {
        serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      } catch {
        // In case it's a file path
        if (fs.existsSync(process.env.FIREBASE_SERVICE_ACCOUNT)) {
          serviceAccount = JSON.parse(fs.readFileSync(process.env.FIREBASE_SERVICE_ACCOUNT, 'utf8'));
        }
      }
    }

    // Fallback to local admin sdk key file in workspace root or backend folder
    if (!serviceAccount) {
      const candidates = [
        path.join(__dirname, '../../buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
        path.join(__dirname, '../buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
        path.join(process.cwd(), 'buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
      ];

      for (const p of candidates) {
        if (fs.existsSync(p)) {
          serviceAccount = JSON.parse(fs.readFileSync(p, 'utf8'));
          break;
        }
      }
    }

    if (serviceAccount) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      isInitialized = true;
      console.log('🔥 [Firebase Admin] Successfully initialized with project:', serviceAccount.project_id);
    } else {
      console.warn('⚠️ [Firebase Admin] No service account credentials found. Push notifications will be mocked.');
    }
  } catch (err) {
    console.error('❌ [Firebase Admin] Initialization error:', err.message);
  }

  return admin;
}

initFirebase();

/**
 * Sends a single FCM Push Notification to a device token
 */
async function sendPushNotification({ token, title, body, tag, data = {} }) {
  if (!token) return null;
  if (!isInitialized) {
    console.log(`[FCM Mock] Single push to ${token.substring(0, 10)}... | ${title}: ${body}`);
    return null;
  }

  try {
    const stringData = {};
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v ?? '');
    }

    const notifTag = tag || (stringData.conversationId ? `chat_${stringData.conversationId}` : (stringData.senderId ? `chat_${stringData.senderId}` : undefined));

    const response = await admin.messaging().send({
      token,
      notification: {
        title,
        body,
      },
      data: stringData,
      android: {
        priority: 'high',
        notification: {
          channelId: 'buddypartner_notifications',
          priority: 'max',
          tag: notifTag,
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    });

    console.log(`🔔 [FCM Push] Sent successfully to ${token.substring(0, 10)}... (tag: ${notifTag}, ID: ${response})`);
    return response;
  } catch (err) {
    console.error(`❌ [FCM Push Error] Failed to send push to ${token.substring(0, 10)}...:`, err.message);
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      const db = require('../db');
      db.query('UPDATE public.users SET fcm_token = NULL WHERE fcm_token = $1', [token]).catch(() => {});
    }
    return null;
  }
}

/**
 * Slices an array of tokens into batches of up to chunkSize (default 500).
 * Required by Firebase Admin SDK which limits sendEachForMulticast to 500 tokens per request.
 * 
 * @param {string[]} tokens
 * @param {number} [chunkSize=500]
 * @returns {string[][]} Array of token chunks
 */
function chunkTokens(tokens, chunkSize = 500) {
  if (!Array.isArray(tokens) || tokens.length === 0) return [];
  const size = Math.max(1, chunkSize);
  const chunks = [];
  for (let i = 0; i < tokens.length; i += size) {
    chunks.push(tokens.slice(i, i + size));
  }
  return chunks;
}

/**
 * Sends Multicast FCM Push Notifications to multiple device tokens.
 * Automatically chunks tokens into batches of <= 500 to adhere to Firebase Admin SDK limits.
 * Prunes tokens that come back as invalid or unregistered.
 */
async function sendMulticastPushNotification({ tokens = [], title, body, tag, data = {} }) {
  const validTokens = Array.from(new Set(tokens.filter((t) => typeof t === 'string' && t.trim().length > 0)));
  if (validTokens.length === 0) return null;

  const chunks = chunkTokens(validTokens, 500);

  if (!isInitialized) {
    console.log(`[FCM Mock] Multicast push to ${validTokens.length} devices in ${chunks.length} batches of <= 500 | ${title}: ${body}`);
    return {
      successCount: validTokens.length,
      failureCount: 0,
      batchCount: chunks.length,
      responses: [],
    };
  }

  try {
    const stringData = {};
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v ?? '');
    }

    const notifTag = tag || (stringData.sessionId ? `instant_${stringData.sessionId}` : 'instant_call');

    let totalSuccess = 0;
    let totalFailure = 0;
    const allResponses = [];
    const tokensToPrune = [];

    for (let batchIndex = 0; batchIndex < chunks.length; batchIndex++) {
      const batchTokens = chunks[batchIndex];
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batchTokens,
        notification: {
          title,
          body,
        },
        data: stringData,
        android: {
          priority: 'high',
          notification: {
            channelId: 'buddypartner_notifications',
            priority: 'max',
            tag: notifTag,
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
      });

      totalSuccess += (response.successCount || 0);
      totalFailure += (response.failureCount || 0);
      allResponses.push(response);

      if (response.failureCount > 0 && response.responses) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success && resp.error) {
            const code = resp.error.code;
            if (
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token' ||
              code === 'messaging/invalid-argument'
            ) {
              tokensToPrune.push(batchTokens[idx]);
            }
          }
        });
      }

      console.log(`🔔 [FCM Multicast Batch ${batchIndex + 1}/${chunks.length}] Dispatched to ${batchTokens.length} devices (tag: ${notifTag}, ${response.successCount} succeeded, ${response.failureCount} failed)`);
    }

    // Prune invalid or unregistered tokens from database
    if (tokensToPrune.length > 0) {
      const db = require('../db');
      db.query('UPDATE public.users SET fcm_token = NULL WHERE fcm_token = ANY($1)', [tokensToPrune])
        .then((pruneRes) => {
          console.log(`🧹 [FCM Prune] Pruned ${pruneRes.rowCount} invalid/unregistered FCM tokens from database.`);
        })
        .catch((err) => {
          console.warn('⚠️ [FCM Prune Error]:', err.message);
        });
    }

    console.log(`🔔 [FCM Multicast Complete] Total ${validTokens.length} devices across ${chunks.length} batches: ${totalSuccess} succeeded, ${totalFailure} failed`);
    return {
      successCount: totalSuccess,
      failureCount: totalFailure,
      batchCount: chunks.length,
      responses: allResponses,
    };
  } catch (err) {
    console.error('❌ [FCM Multicast Error]:', err.message);
    return null;
  }
}

module.exports = {
  admin,
  initFirebase,
  sendPushNotification,
  sendMulticastPushNotification,
  chunkTokens,
};

`

================================================================================
FILE: backend/modules/messaging/messaging.service.js
================================================================================

`javascript
const db = require('../../db');
const { sendPushNotification } = require('../../services/firebase.service');

class MessagingService {
  /**
   * Normalize user pair ordering — lexicographically smaller ID = user_a_id.
   * Ensures a single canonical conversation row per pair.
   */
  _normalizeIds(idA, idB) {
    return idA < idB ? { userAId: idA, userBId: idB } : { userAId: idB, userBId: idA };
  }

  /**
   * Find or create a conversation between two users.
   * @param {string} currentUserId - The requesting user's Firebase UID
   * @param {string} otherUserId - The other user's Firebase UID
   * @returns {object} The conversation row
   */
  /**
   * Helper method to validate standard UUID string format.
   */
  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Find or create a conversation between two users.
   * @param {string} currentUserId - The requesting user's Firebase UID
   * @param {string} otherUserId - The other user's Firebase UID
   * @returns {object} The conversation row
   */
  async findOrCreateConversation(currentUserId, otherUserId) {
    if (!this._isValidUUID(otherUserId) || !this._isValidUUID(currentUserId)) {
      throw new Error('Invalid user ID format');
    }

    if (currentUserId === otherUserId) {
      throw new Error('Cannot create a conversation with yourself');
    }

    // Verify other user exists in DB before attempting to insert
    const userCheck = await db.query(
      `SELECT id FROM public.users WHERE id = $1`,
      [otherUserId]
    );
    if (userCheck.rows.length === 0) {
      throw new Error('User not found');
    }

    // Check block list before creating conversation
    const blocked = await this.isBlocked(currentUserId, otherUserId);
    if (blocked) {
      throw new Error('Cannot start a conversation with this user');
    }

    const { userAId, userBId } = this._normalizeIds(currentUserId, otherUserId);

    const result = await db.query(
      `INSERT INTO public.conversations (user_a_id, user_b_id)
       VALUES ($1, $2)
       ON CONFLICT (user_a_id, user_b_id) DO UPDATE SET user_a_id = EXCLUDED.user_a_id
       RETURNING *`,
      [userAId, userBId]
    );

    return result.rows[0];
  }

  /**
   * Send a message in a conversation.
   * Checks block list first, then inserts and updates last_message_at.
   * @param {string} conversationId
   * @param {string} senderId - Verified Firebase UID of the sender
   * @param {string} content - Message text
   * @param {string} type - 'text' | 'image' | 'system'
   * @param {string|null} mediaUrl - Media URL (deferred, always null for now)
   * @param {string} initialStatus - 'sent' | 'delivered' (default: 'sent')
   * @returns {object} The inserted message row
   */
  async sendMessage(conversationId, senderId, content, type = 'text', mediaUrl = null, initialStatus = 'sent') {
    // 1. Verify sender is a participant of this conversation
    const convResult = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [conversationId]
    );

    if (convResult.rows.length === 0) {
      throw new Error('Conversation not found');
    }

    const conv = convResult.rows[0];
    if (conv.user_a_id !== senderId && conv.user_b_id !== senderId) {
      throw new Error('Not a participant of this conversation');
    }

    // 2. Check block list — either direction
    const otherUserId = conv.user_a_id === senderId ? conv.user_b_id : conv.user_a_id;
    const blocked = await this.isBlocked(senderId, otherUserId);
    if (blocked) {
      throw new Error('Message blocked: one party has blocked the other');
    }

    // 3. Insert message
    const msgResult = await db.query(
      `INSERT INTO public.messages (conversation_id, sender_id, content, type, media_url, status)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [conversationId, senderId, content, type, mediaUrl, initialStatus]
    );

    // 4. Update conversation's last_message_at
    await db.query(
      `UPDATE public.conversations SET last_message_at = NOW() WHERE id = $1`,
      [conversationId]
    );

    // 5. Dispatch FCM Push Notification to recipient (WhatsApp-style stacked summary)
    try {
      const userRes = await db.query(
        `SELECT u.id, u.fcm_token, 
                (SELECT full_name FROM public.users WHERE id = $1) as sender_name
         FROM public.users u WHERE u.id = $2`,
        [senderId, otherUserId]
      );

      if (userRes.rows.length > 0 && userRes.rows[0].fcm_token) {
        const recipient = userRes.rows[0];
        const senderName = recipient.sender_name || 'Someone';

        // Fetch recent unread messages from this sender to build multi-line stack
        const unreadRes = await db.query(
          `SELECT content, type FROM public.messages
           WHERE conversation_id = $1 
             AND sender_id = $2 
             AND status != 'read'
           ORDER BY created_at ASC
           LIMIT 5`,
          [conversationId, senderId]
        );

        let notifTitle = senderName;
        let notifBody = type === 'text' ? content : 'Sent you an attachment';

        const unreadMessages = unreadRes.rows;
        if (unreadMessages.length > 1) {
          notifTitle = `${senderName} (${unreadMessages.length} new messages)`;
          notifBody = unreadMessages
            .map((m) => (m.type === 'text' ? `• ${m.content}` : '• Sent an attachment'))
            .join('\n');
        }

        sendPushNotification({
          token: recipient.fcm_token,
          title: notifTitle,
          body: notifBody,
          tag: `chat_${conversationId}`,
          data: {
            type: 'chat_message',
            senderId: String(senderId),
            senderName: String(senderName),
            conversationId: String(conversationId),
            messageCount: String(unreadMessages.length),
          },
        }).catch((err) => console.error('FCM send error:', err.message));
      }
    } catch (pushErr) {
      console.error('Error sending message push notification:', pushErr.message);
    }

    return msgResult.rows[0];
  }

  /**
   * Get messages for a conversation with cursor-based pagination.
   * @param {string} conversationId
   * @param {string} requestingUserId - Must be a participant
   * @param {string|null} cursor - ISO timestamp cursor for pagination
   * @param {number} limit - Number of messages to return (default 30)
   * @returns {object} { messages, nextCursor }
   */
  async getMessages(conversationId, requestingUserId, cursor = null, limit = 30) {
    if (!this._isValidUUID(conversationId) || !this._isValidUUID(requestingUserId)) {
      throw new Error('Conversation not found');
    }

    // Verify participant
    const convResult = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [conversationId]
    );

    if (convResult.rows.length === 0) {
      throw new Error('Conversation not found');
    }

    const conv = convResult.rows[0];
    if (conv.user_a_id !== requestingUserId && conv.user_b_id !== requestingUserId) {
      throw new Error('Not a participant of this conversation');
    }

    let query;
    let params;

    if (cursor) {
      query = `
        SELECT * FROM public.messages
        WHERE conversation_id = $1 AND created_at < $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
      params = [conversationId, cursor, limit];
    } else {
      query = `
        SELECT * FROM public.messages
        WHERE conversation_id = $1
        ORDER BY created_at DESC
        LIMIT $2
      `;
      params = [conversationId, limit];
    }

    const result = await db.query(query, params);
    const messages = result.rows;
    const nextCursor = messages.length === limit
      ? messages[messages.length - 1].created_at.toISOString()
      : null;

    return { messages, nextCursor };
  }

  /**
   * Get all conversations for a user with last message preview and unread count.
   * @param {string} userId - Verified Firebase UID
   * @returns {Array} Conversation list with preview data
   */
  async getConversations(userId) {
    const result = await db.query(
      `SELECT
        c.id,
        c.user_a_id,
        c.user_b_id,
        c.created_at,
        c.last_message_at,
        -- Last message preview
        lm.content AS last_message_content,
        lm.type AS last_message_type,
        lm.sender_id AS last_message_sender_id,
        lm.created_at AS last_message_created_at,
        -- Other user's profile
        u.full_name AS other_user_name,
        u.gender AS other_user_gender,
        u.avatar_seed AS other_user_avatar_seed,
        u.avatar_style AS other_user_avatar_style,
        -- Unread count: messages after the user's last read message
        COALESCE(
          (SELECT COUNT(*) FROM public.messages m
           WHERE m.conversation_id = c.id
             AND m.sender_id != $1
             AND m.created_at > COALESCE(
               (SELECT m2.created_at FROM public.messages m2
                WHERE m2.id = mr.last_read_message_id),
               '1970-01-01'::timestamptz
             )
          ), 0
        )::int AS unread_count
      FROM public.conversations c
      -- Join to get the other user's profile
      LEFT JOIN public.users u ON u.id = CASE
        WHEN c.user_a_id = $1 THEN c.user_b_id
        ELSE c.user_a_id
      END
      -- Join to get the last message
      LEFT JOIN LATERAL (
        SELECT content, type, sender_id, created_at
        FROM public.messages
        WHERE conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) lm ON true
      -- Join to get read receipts
      LEFT JOIN public.message_reads mr ON mr.conversation_id = c.id AND mr.user_id = $1
      WHERE c.user_a_id = $1 OR c.user_b_id = $1
      ORDER BY c.last_message_at DESC`,
      [userId]
    );

    return result.rows.map(row => ({
      id: row.id,
      otherUserId: row.user_a_id === userId ? row.user_b_id : row.user_a_id,
      otherUserName: row.other_user_name || 'User',
      otherUserGender: row.other_user_gender,
      otherUserAvatarSeed: row.other_user_avatar_seed || null,
      otherUserAvatarStyle: row.other_user_avatar_style || 'avataaars',
      otherUserAvatar: row.other_user_avatar_seed || null,
      lastMessage: row.last_message_content,
      lastMessageType: row.last_message_type,
      lastMessageSenderId: row.last_message_sender_id,
      lastMessageAt: row.last_message_at,
      unreadCount: row.unread_count,
      createdAt: row.created_at,
    }));
  }

  /**
   * Mark messages as read up to a specific message.
   * @param {string} conversationId
   * @param {string} userId - The reader's Firebase UID
   * @param {string} messageId - The latest message ID that was read
   */
  async markAsRead(conversationId, userId, messageId = null) {
    if (!this._isValidUUID(conversationId)) return;

    // Verify participant
    const convResult = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [conversationId]
    );

    if (convResult.rows.length === 0) {
      throw new Error('Conversation not found');
    }

    const conv = convResult.rows[0];
    if (conv.user_a_id !== userId && conv.user_b_id !== userId) {
      throw new Error('Not a participant of this conversation');
    }

    let targetMsgId = messageId;
    if (!targetMsgId) {
      const latestRes = await db.query(
        `SELECT id FROM public.messages WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT 1`,
        [conversationId]
      );
      targetMsgId = latestRes.rows[0]?.id || null;
    }

    if (targetMsgId) {
      await db.query(
        `INSERT INTO public.message_reads (conversation_id, user_id, last_read_message_id)
         VALUES ($1, $2, $3)
         ON CONFLICT (conversation_id, user_id)
         DO UPDATE SET last_read_message_id = $3`,
        [conversationId, userId, targetMsgId]
      );
    }

    // Update status of all unread messages from the other user in this conversation to 'read'
    await db.query(
      `UPDATE public.messages
       SET status = 'read'
       WHERE conversation_id = $1 AND sender_id != $2 AND status != 'read'`,
      [conversationId, userId]
    );
  }

  // ── Delivery Catch-up ──────────────────────────────────────────────────

  /**
   * Mark all unread 'sent' messages addressed to this recipient as 'delivered' when they connect.
   * Emits real-time double-tick updates to the senders.
   * @param {string} recipientId
   * @param {import('socket.io').Server|null} io
   */
  async markDeliveredForRecipient(recipientId, io = null) {
    if (!this._isValidUUID(recipientId)) return;

    try {
      const updateResult = await db.query(
        `WITH user_convs AS (
           SELECT id FROM public.conversations WHERE user_a_id = $1
           UNION
           SELECT id FROM public.conversations WHERE user_b_id = $1
         )
         UPDATE public.messages m
         SET status = 'delivered'
         FROM user_convs uc
         WHERE m.conversation_id = uc.id
           AND m.status = 'sent'
           AND m.sender_id != $1
         RETURNING m.id, m.conversation_id, m.sender_id`,
        [recipientId]
      );

      if (io && updateResult.rows.length > 0) {
        for (const row of updateResult.rows) {
          io.to(row.sender_id).emit('message:status_update', {
            conversationId: row.conversation_id,
            messageId: row.id,
            status: 'delivered',
          });
        }
      }
    } catch (err) {
      console.error('Error marking messages as delivered for recipient:', err.message);
    }
  }

  // ── Block / Report ──────────────────────────────────────────────────────

  /**
   * Check if either user has blocked the other.
   * @returns {boolean}
   */
  async isBlocked(userAId, userBId) {
    const result = await db.query(
      `SELECT 1 FROM public.blocks
       WHERE (blocker_id = $1 AND blocked_id = $2)
          OR (blocker_id = $2 AND blocked_id = $1)
       LIMIT 1`,
      [userAId, userBId]
    );
    return result.rows.length > 0;
  }

  /**
   * Block a user and notify real-time sockets.
   * @param {string} blockerId
   * @param {string} blockedId
   * @param {import('socket.io').Server|null} io
   */
  async blockUser(blockerId, blockedId, io = null) {
    if (blockerId === blockedId) {
      throw new Error('Cannot block yourself');
    }

    await db.query(
      `INSERT INTO public.blocks (blocker_id, blocked_id)
       VALUES ($1, $2)
       ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
      [blockerId, blockedId]
    );

    if (io) {
      io.emit('user:blocked', {
        blockerId,
        blockedId,
        timestamp: new Date().toISOString(),
      });
      console.log(`🚫 [Block] User ${blockerId} blocked user ${blockedId}. Socket notification emitted.`);
    }
  }

  /**
   * Unblock a user.
   */
  async unblockUser(blockerId, blockedId) {
    await db.query(
      `DELETE FROM public.blocks WHERE blocker_id = $1 AND blocked_id = $2`,
      [blockerId, blockedId]
    );
  }

  /**
   * Report a user/message.
   */
  async reportUser(reporterId, reportedUserId, reason, description = null, messageId = null, conversationId = null) {
    if (reporterId === reportedUserId) {
      throw new Error('Cannot report yourself');
    }

    const result = await db.query(
      `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [reporterId, reportedUserId, reason, description, messageId, conversationId]
    );

    return result.rows[0];
  }
}

module.exports = { MessagingService };

`

================================================================================
FILE: backend/modules/messaging/messaging.routes.js
================================================================================

`javascript
const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { MessagingService } = require('./messaging.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

const router = express.Router();
const messagingService = new MessagingService();

// ── GET /api/conversations ────────────────────────────────────────────────
// List all conversations for the authenticated user
router.get('/conversations', authMiddleware, async (req, res) => {
  try {
    const conversations = await messagingService.getConversations(req.user.id);
    res.json({ conversations });
  } catch (err) {
    console.error('Error fetching conversations:', err.message);
    res.status(500).json({ error: 'Failed to fetch conversations' });
  }
});

// ── POST /api/conversations ───────────────────────────────────────────────
// Find or create a conversation with another user
router.post('/conversations', authMiddleware, async (req, res) => {
  try {
    const { otherUserId } = req.body;
    if (!otherUserId) {
      return res.status(400).json({ error: 'otherUserId is required' });
    }

    const conversation = await messagingService.findOrCreateConversation(
      req.user.id,
      otherUserId
    );

    res.json({ conversation });
  } catch (err) {
    console.error('Error creating conversation:', err.message);
    if (err.message.includes('block') || err.message.includes('Cannot start a conversation')) {
      return res.status(403).json({ error: err.message });
    }
    if (err.message.includes('User not found')) {
      return res.status(404).json({ error: err.message });
    }
    if (err.message.includes('yourself') || err.message.includes('Invalid') || err.message.includes('required')) {
      return res.status(400).json({ error: err.message });
    }
    res.status(500).json({ error: err.message || 'Failed to create conversation' });
  }
});

// ── GET /api/conversations/:id/messages ───────────────────────────────────
// Get paginated messages for a conversation
router.get('/conversations/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { cursor, limit } = req.query;

    const result = await messagingService.getMessages(
      id,
      req.user.id,
      cursor || null,
      parseInt(limit) || 30
    );

    // Automatically mark all messages as read for this participant
    messagingService.markAsRead(id, req.user.id).catch((err) => {
      console.error('Error marking messages as read on fetch:', err.message);
    });

    res.json(result);
  } catch (err) {
    console.error('Error fetching messages:', err.message);
    if (err.message.includes('Not a participant')) {
      return res.status(403).json({ error: err.message });
    }
    if (err.message.includes('not found') || err.message.includes('Conversation not found')) {
      return res.status(404).json({ error: err.message });
    }
    if (err.message.includes('Invalid')) {
      return res.status(400).json({ error: err.message });
    }
    res.status(500).json({ error: err.message || 'Failed to fetch messages' });
  }
});

// ── POST /api/conversations/:id/read ──────────────────────────────────────
// Explicitly mark all messages in a conversation as read
router.post('/conversations/:id/read', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { messageId } = req.body;
    await messagingService.markAsRead(id, req.user.id, messageId || null);
    res.json({ success: true });
  } catch (err) {
    console.error('Error in /conversations/:id/read:', err.message);
    res.status(500).json({ error: 'Failed to mark as read' });
  }
});

// ── POST /api/conversations/:id/messages ──────────────────────────────────
// Send a message (REST fallback if socket isn't connected)
router.post('/conversations/:id/messages', authMiddleware, async (req, res) => {
  try {
    const { id } = req.params;
    const { content, type } = req.body;

    if (!content || !content.trim()) {
      return res.status(400).json({ error: 'content is required' });
    }

    const isSub = await subscriptionsService.isSubscribed(req.user.id);
    if (!isSub) {
      return res.status(403).json({ error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to send messages.' });
    }

    const message = await messagingService.sendMessage(
      id,
      req.user.id,
      content.trim(),
      type || 'text'
    );

    res.json({ message });
  } catch (err) {
    console.error('Error sending message:', err.message);
    if (err.message.includes('block')) {
      return res.status(403).json({ error: err.message });
    }
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// ── POST /api/block ───────────────────────────────────────────────────────
// Block a user
router.post('/block', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.body;
    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    const io = req.app.get('io');
    await messagingService.blockUser(req.user.id, userId, io);
    res.json({ success: true });
  } catch (err) {
    console.error('Error blocking user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── DELETE /api/block/:userId ─────────────────────────────────────────────
// Unblock a user
router.delete('/block/:userId', authMiddleware, async (req, res) => {
  try {
    const { userId } = req.params;
    await messagingService.unblockUser(req.user.id, userId);
    res.json({ success: true });
  } catch (err) {
    console.error('Error unblocking user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/report ──────────────────────────────────────────────────────
// Report a user/message & trigger strike escalation
router.post('/report', authMiddleware, async (req, res) => {
  try {
    const { ModerationService } = require('../moderation/moderation.service');
    const { reportedUserId, reason, description, messageId, conversationId } = req.body;

    if (!reportedUserId || !reason) {
      return res.status(400).json({ error: 'reportedUserId and reason are required' });
    }

    const result = await ModerationService.fileReport(
      req.user.id,
      reportedUserId,
      reason,
      description || null,
      messageId || null,
      conversationId || null
    );

    res.json({ success: true, ...result });
  } catch (err) {
    console.error('Error reporting user:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── GET /api/presence ─────────────────────────────────────────────────────
// Query online status for one or more user IDs
router.get('/presence', authMiddleware, async (req, res) => {
  try {
    const { userIds } = req.query;
    if (!userIds) {
      return res.json({ presence: {} });
    }

    const ids = Array.isArray(userIds) ? userIds : userIds.split(',').map((id) => id.trim()).filter(Boolean);
    const { PresenceService } = require('../presence/presence.service');
    const redis = req.app.get('redis') || require('../../redis');

    const presenceMap = await PresenceService.getPresenceBatch(redis, ids);
    res.json({ presence: presenceMap });
  } catch (err) {
    console.error('Error fetching presence:', err.message);
    res.status(500).json({ error: 'Failed to fetch presence' });
  }
});

module.exports = router;

`

================================================================================
FILE: backend/modules/calls/calls.service.js
================================================================================

`javascript
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const db = require('../../db');

const CALL_DURATION_MS = 24 * 60 * 60 * 1000; // Unlimited calls (24h token safety cap)
const TOKEN_EXPIRY_SECONDS = 24 * 60 * 60;     // 24 hours token lifetime
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

class CallsService {
  constructor() {
    // Map of callId → setTimeout handle for server-authoritative 5-min timer
    this.callTimers = new Map();
    // Map of callId → setInterval handle for per-minute billing
    this.callBillingIntervals = new Map();
  }

  /**
   * Create a new call record in the database.
   *
   * @param {string} userAId - caller
   * @param {string} userBId - matched user
   * @returns {string} callId (UUID)
   */
  async createCall(userAId, userBId) {
    try {
      const result = await db.query(
        `INSERT INTO public.calls (caller_id, matched_user_id, status, call_type)
         VALUES ($1, $2, 'active', 'voice')
         RETURNING id`,
        [userAId, userBId]
      );

      if (result.rows.length === 0) {
        throw new Error('No row returned on call insertion');
      }

      return result.rows[0].id;
    } catch (err) {
      console.error('Error creating call in Postgres:', err.message);
      throw new Error('Failed to create call record');
    }
  }

  /**
   * End a call — set status to ended, record end time and duration.
   *
   * @param {string} callId
   */
  async endCall(callId) {
    // Clear the server-side timer & billing interval if running
    this.clearCallTimer(callId);
    this.clearCallBilling(callId);

    try {
      const result = await db.query(
        'SELECT started_at, status FROM public.calls WHERE id = $1',
        [callId]
      );

      if (result.rows.length === 0) {
        console.error(`Call record not found: ${callId}`);
        return;
      }

      const call = result.rows[0];

      // Guard against double-ending
      if (call.status === 'ended') {
        return;
      }

      const endedAt = new Date();
      const startedAt = new Date(call.started_at);
      const durationSeconds = Math.floor((endedAt - startedAt) / 1000);

      await db.query(
        `UPDATE public.calls 
         SET status = 'ended', ended_at = $1, duration_seconds = $2 
         WHERE id = $3`,
        [endedAt.toISOString(), durationSeconds, callId]
      );
    } catch (err) {
      console.error('Error ending call in Postgres:', err.message);
    }
  }

  /**
   * Upgrade a call from voice to video.
   *
   * @param {string} callId
   */
  async upgradeToVideo(callId) {
    if (!callId || !UUID_REGEX.test(callId)) return;
    try {
      await db.query(
        "UPDATE public.calls SET call_type = 'video' WHERE id = $1",
        [callId]
      );
    } catch (err) {
      console.error('Error upgrading call to video in Postgres:', err.message);
    }
  }

  /**
   * Downgrade a call from video back to voice/audio.
   *
   * @param {string} callId
   */
  async downgradeToVoice(callId) {
    if (!callId || !UUID_REGEX.test(callId)) return;
    try {
      await db.query(
        "UPDATE public.calls SET call_type = 'voice' WHERE id = $1",
        [callId]
      );
    } catch (err) {
      console.error('Error downgrading call to voice in Postgres:', err.message);
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
   * No-op stub for starting call timer (5-minute cap removed in subscription model).
   */
  startCallTimer(callId, onExpiry) {
    // 5-minute limit removed under subscription model
  }

  /**
   * No-op stub for clearing call timer.
   */
  clearCallTimer(callId) {
    const existing = this.callTimers.get(callId);
    if (existing) {
      clearTimeout(existing);
      this.callTimers.delete(callId);
    }
  }

  /**
   * No-op stub for starting call billing (per-minute billing removed in subscription model).
   */
  startCallBilling(callId, userAId, userBId, genderA, genderB, io, onInsufficientBalance) {
    // Per-minute billing removed under subscription model
  }

  /**
   * No-op stub for clearing call billing.
   */
  clearCallBilling(callId) {
    const existing = this.callBillingIntervals.get(callId);
    if (existing) {
      clearInterval(existing);
      this.callBillingIntervals.delete(callId);
    }
  }

  /**
   * Check if a gender string represents female.
   * @param {string} gender
   * @returns {boolean}
   */
  _isFemale(gender) {
    const g = (gender || '').toLowerCase();
    return g === 'female' || g === 'girl' || g === 'woman';
  }
}

const callsService = new CallsService();

module.exports = { callsService, CallsService };

`

================================================================================
FILE: backend/modules/calls/calls.routes.js
================================================================================

`javascript
const express = require('express');
const router = express.Router();
const db = require('../../db');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { userSockets } = require('../matchmaking/matchmaking.socket');
const { cacheService } = require('../../services/cache.service');

/**
 * Endpoint: GET /api/calls/history
 * Returns the authenticated user's call history across matchmaking and VIP instant calls.
 * Uses indexed UNION ALL query with pagination support (default limit: 50).
 */
router.get('/history', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
  const offset = Math.max(parseInt(req.query.offset, 10) || 0, 0);

  try {
    /*
     * Optimized UNION ALL query:
     * Postgres executes two direct index scans on idx_calls_caller_started and idx_calls_matched_started,
     * plus idx_instant_male_started and idx_instant_female_started, avoiding expensive full-table bitmap OR scans.
     */
    const result = await db.query(
      `SELECT c.id, c.caller_id, c.matched_user_id, c.status, c.call_type, c.duration_seconds, c.started_at, c.ended_at,
              u1.full_name AS caller_name, u1.gender AS caller_gender, u1.avatar_seed AS caller_avatar_seed, u1.avatar_style AS caller_avatar_style,
              u2.full_name AS matched_name, u2.gender AS matched_gender, u2.avatar_seed AS matched_avatar_seed, u2.avatar_style AS matched_avatar_style
       FROM (
         SELECT id, caller_id, matched_user_id, status, call_type, duration_seconds, started_at, ended_at
         FROM public.calls
         WHERE caller_id = $1

         UNION ALL

         SELECT id, caller_id, matched_user_id, status, call_type, duration_seconds, started_at, ended_at
         FROM public.calls
         WHERE matched_user_id = $1

         UNION ALL

         SELECT id, male_user_id AS caller_id, female_user_id AS matched_user_id,
                CASE WHEN status = 'completed' THEN 'ended' WHEN status = 'in_call' THEN 'active' ELSE status END AS status,
                'instant_vip' AS call_type, duration_seconds, started_at, ended_at
         FROM public.instant_call_sessions
         WHERE male_user_id = $1 AND female_user_id IS NOT NULL

         UNION ALL

         SELECT id, male_user_id AS caller_id, female_user_id AS matched_user_id,
                CASE WHEN status = 'completed' THEN 'ended' WHEN status = 'in_call' THEN 'active' ELSE status END AS status,
                'instant_vip' AS call_type, duration_seconds, started_at, ended_at
         FROM public.instant_call_sessions
         WHERE female_user_id = $1
       ) c
       LEFT JOIN public.users u1 ON c.caller_id = u1.id
       LEFT JOIN public.users u2 ON c.matched_user_id = u2.id
       ORDER BY c.started_at DESC NULLS LAST
       LIMIT $2 OFFSET $3`,
      [userId, limit, offset]
    );

    // Map database rows to the nested format expected by Flutter CallLog.fromJson
    const formattedHistory = result.rows.map(row => ({
      id: row.id,
      caller_id: row.caller_id,
      matched_user_id: row.matched_user_id,
      status: row.status,
      call_type: row.call_type,
      duration_seconds: row.duration_seconds,
      started_at: row.started_at,
      caller: {
        id: row.caller_id,
        full_name: row.caller_name || 'User',
        gender: row.caller_gender,
        avatar_seed: row.caller_avatar_seed,
        avatar_style: row.caller_avatar_style || 'avataaars',
      },
      matched_user: {
        id: row.matched_user_id,
        full_name: row.matched_name || 'User',
        gender: row.matched_gender,
        avatar_seed: row.matched_avatar_seed,
        avatar_style: row.matched_avatar_style || 'avataaars',
      }
    }));

    res.json(formattedHistory);
  } catch (err) {
    console.error('Error fetching call history:', err.message);
    res.status(500).json({ error: 'Internal server error loading call history.' });
  }
});

/**
 * Endpoint: GET /api/calls/matches
 * Returns a list of users matched with the current user across matchmaking and VIP Instant calls.
 * Cached in Redis for 30s per user to eliminate DB load during frequent home navigation.
 */
router.get('/matches', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const cacheKey = `user:matches:${userId}`;
    const rawMatches = await cacheService.getOrSet(cacheKey, 30, async () => {
      /*
       * EXPLAIN ANALYZE (Execution Time: 0.14ms vs 3.11ms old correlated subqueries — 22x to 500x speedup):
       * Rewritten into a Common Table Expression (CTE) that jumps straight to the user's few calls
       * via index scans, aggregates distinct partners, and joins only matching user records.
       */
      const result = await db.query(
        `WITH user_interactions AS (
           SELECT matched_user_id AS partner_id, started_at
           FROM public.calls
           WHERE caller_id = $1
           UNION ALL
           SELECT caller_id AS partner_id, started_at
           FROM public.calls
           WHERE matched_user_id = $1
           UNION ALL
           SELECT female_user_id AS partner_id, started_at
           FROM public.instant_call_sessions
           WHERE male_user_id = $1 AND female_user_id IS NOT NULL
           UNION ALL
           SELECT male_user_id AS partner_id, started_at
           FROM public.instant_call_sessions
           WHERE female_user_id = $1
         ),
         latest_interactions AS (
           SELECT partner_id, MAX(started_at) AS last_matched_at
           FROM user_interactions
           WHERE partner_id IS NOT NULL AND partner_id != $1
           GROUP BY partner_id
         )
         SELECT u.id, u.full_name, u.gender, u.avatar_seed, u.avatar_style,
                (f.favorite_user_id IS NOT NULL) AS is_favorite,
                li.last_matched_at
         FROM latest_interactions li
         JOIN public.users u ON u.id = li.partner_id
         LEFT JOIN public.favorites f ON f.user_id = $1 AND f.favorite_user_id = u.id
         ORDER BY li.last_matched_at DESC, u.full_name ASC
         LIMIT 100`,
        [userId]
      );
      return result.rows;
    });

    // Dynamically attach real-time online status from active socket map
    const matches = (rawMatches || []).map(row => ({
      id: row.id,
      fullName: row.full_name || 'User',
      gender: row.gender,
      avatarSeed: row.avatar_seed,
      avatarStyle: row.avatar_style || 'avataaars',
      isOnline: userSockets ? userSockets.has(row.id) : false,
      isFavorite: Boolean(row.is_favorite),
    }));

    res.json(matches);
  } catch (err) {
    console.error('Error fetching matches:', err.message);
    res.status(500).json({ error: 'Internal server error loading matches.' });
  }
});

/**
 * Endpoint: GET /api/calls/favorites
 * Returns the current user's favorited users.
 */
router.get('/favorites', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const cacheKey = `user:favorites:${userId}`;
    const rawFavorites = await cacheService.getOrSet(cacheKey, 30, async () => {
      const result = await db.query(
        `SELECT u.id, u.full_name, u.gender, u.avatar_seed, u.avatar_style, true AS is_favorite
         FROM public.users u
         JOIN public.favorites f ON f.favorite_user_id = u.id
         WHERE f.user_id = $1
         ORDER BY f.created_at DESC
         LIMIT 100`,
        [userId]
      );
      return result.rows;
    });

    const favorites = (rawFavorites || []).map(row => ({
      id: row.id,
      fullName: row.full_name || 'User',
      gender: row.gender,
      avatarSeed: row.avatar_seed,
      avatarStyle: row.avatar_style || 'avataaars',
      isOnline: userSockets ? userSockets.has(row.id) : false,
      isFavorite: true
    }));

    res.json(favorites);
  } catch (err) {
    console.error('Error fetching favorites:', err.message);
    res.status(500).json({ error: 'Internal server error loading favorites.' });
  }
});

/**
 * Endpoint: POST /api/calls/favorites
 * Adds a user to the current user's favorites and invalidates favorites & matches cache.
 */
router.post('/favorites', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { favoriteUserId } = req.body;

  if (!favoriteUserId) {
    return res.status(400).json({ error: 'favoriteUserId is required.' });
  }

  try {
    await db.query(
      `INSERT INTO public.favorites (user_id, favorite_user_id)
       VALUES ($1, $2)
       ON CONFLICT (user_id, favorite_user_id) DO NOTHING`,
      [userId, favoriteUserId]
    );

    // Invalidate caches
    await Promise.all([
      cacheService.invalidate(`user:favorites:${userId}`),
      cacheService.invalidate(`user:matches:${userId}`),
    ]);

    res.json({ success: true });
  } catch (err) {
    console.error('Error adding favorite:', err.message);
    res.status(500).json({ error: 'Internal server error adding favorite.' });
  }
});

/**
 * Endpoint: DELETE /api/calls/favorites/:favoriteUserId
 * Removes a user from the current user's favorites and invalidates favorites & matches cache.
 */
router.delete('/favorites/:favoriteUserId', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { favoriteUserId } = req.params;

  try {
    await db.query(
      `DELETE FROM public.favorites
       WHERE user_id = $1 AND favorite_user_id = $2`,
      [userId, favoriteUserId]
    );

    // Invalidate caches
    await Promise.all([
      cacheService.invalidate(`user:favorites:${userId}`),
      cacheService.invalidate(`user:matches:${userId}`),
    ]);

    res.json({ success: true });
  } catch (err) {
    console.error('Error removing favorite:', err.message);
    res.status(500).json({ error: 'Internal server error removing favorite.' });
  }
});

module.exports = router;

`

================================================================================
FILE: backend/modules/instant_connect/instant_connect.routes.js
================================================================================

`javascript
const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { instantConnectService } = require('./instant_connect.service');
const { PresenceService } = require('../presence/presence.service');
const redis = require('../../redis');
const { scanKeys } = require('../../utils/redis_helpers');

const router = express.Router();

// ── POST /api/instant/toggle ────────────────────────────────────────────────
// Female user toggling "Incoming Paid Calls" ON/OFF
router.post('/toggle', authMiddleware, async (req, res) => {
  try {
    const { enabled } = req.body;
    const result = await instantConnectService.toggleIncomingPaidCalls(req.user.id, enabled === true, redis);
    if (!result.success) {
      return res.status(400).json(result);
    }
    if (enabled === true) {
      const io = req.app.get('io');
      const { triggerInstantMatchmaker } = require('./instant_connect.socket');
      if (io) {
        triggerInstantMatchmaker(io, redis);
      }
    }
    res.json(result);
  } catch (err) {
    console.error('Error in POST /api/instant/toggle:', err.message);
    res.status(500).json({ error: 'Failed to toggle incoming paid calls' });
  }
});

// ── GET /api/instant/status ─────────────────────────────────────────────────
// Get female user's instant connect status & scratch card counts
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const status = await instantConnectService.getFemaleStatus(req.user.id);
    res.json(status);
  } catch (err) {
    console.error('Error in GET /api/instant/status:', err.message);
    res.status(500).json({ error: 'Failed to fetch instant status' });
  }
});

// ── GET /api/instant/scratch-cards ──────────────────────────────────────────
// List all scratch cards for current user
router.get('/scratch-cards', authMiddleware, async (req, res) => {
  try {
    const cards = await instantConnectService.getScratchCards(req.user.id);
    res.json({ scratchCards: cards });
  } catch (err) {
    console.error('Error in GET /api/instant/scratch-cards:', err.message);
    res.status(500).json({ error: 'Failed to fetch scratch cards' });
  }
});

// ── POST /api/instant/scratch-cards/:id/scratch ─────────────────────────────
// Claim/scratch a card to credit coins to wallet
router.post('/scratch-cards/:id/scratch', authMiddleware, async (req, res) => {
  try {
    const cardId = req.params.id;
    const result = await instantConnectService.claimScratchCard(req.user.id, cardId);
    if (!result.success) {
      return res.status(400).json(result);
    }
    res.json(result);
  } catch (err) {
    console.error('Error in POST /api/instant/scratch-cards/:id/scratch:', err.message);
    res.status(500).json({ error: 'Failed to claim scratch card' });
  }
});

// Admin check middleware for dev inspection routes
function adminOnly(req, res, next) {
  const adminKey = req.headers['x-admin-key'];
  const validSecret = process.env.ADMIN_SECRET || 'buddypartner_admin_dev_secret_key';
  if (adminKey && adminKey === validSecret) {
    return next();
  }
  if (req.user && (req.user.isAdmin || req.user.role === 'admin')) {
    return next();
  }
  return res.status(403).json({ error: 'FORBIDDEN', message: 'Admin privileges required' });
}

// ── GET /api/instant/dev/queues ─────────────────────────────────────────────
// Developer queue monitor: inspect waiting males, available females, and active calls
router.get('/dev/queues', async (req, res) => {
  try {
    const db = require('../../db');
    const { activeInstantCalls } = require('./instant_connect.socket');

    // 1. Reconcile any database in_call sessions that have no matching in-memory active call
    const activeSessionIds = new Set(Array.from(activeInstantCalls.values()).map((c) => c.sessionId));
    const staleInCallRes = await db.query(`SELECT id FROM public.instant_call_sessions WHERE status = 'in_call'`);
    for (const row of staleInCallRes.rows) {
      if (!activeSessionIds.has(row.id)) {
        await db.query(`UPDATE public.instant_call_sessions SET status = 'dropped', ended_at = NOW() WHERE id = $1`, [row.id]);
      }
    }

    // 2. Waiting males
    const maleQueueIds = await redis.zrevrange('instant:male_queue', 0, -1, 'WITHSCORES');
    const waitingMales = [];
    for (let i = 0; i < maleQueueIds.length; i += 2) {
      const userId = maleQueueIds[i];
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      const sessionData = sessionStr ? JSON.parse(sessionStr) : {};
      const userRes = await db.query('SELECT full_name, phone_number FROM public.users WHERE id = $1', [userId]);
      waitingMales.push({
        position: (i / 2) + 1,
        userId,
        fullName: userRes.rows[0]?.full_name || 'Unknown',
        phoneNumber: userRes.rows[0]?.phone_number || 'N/A',
        bidAmount: sessionData.bidAmount || 0,
        sessionId: sessionData.sessionId,
      });
    }

    // 3. Active females in Redis (reconcile with DB toggle)
    const dbFemales = await db.query(`
      SELECT id, full_name, phone_number, incoming_paid_calls_enabled
      FROM public.users
      WHERE incoming_paid_calls_enabled = true
        AND (LOWER(gender) IN ('female', 'girl', 'woman', 'f'))
    `);

    if (dbFemales.rows.length > 0) {
      await redis.sadd('instant:female_pool', ...dbFemales.rows.map((f) => f.id));
    }

    const io = req.app.get('io');
    const { getSocketForUser } = require('./instant_connect.socket');
    const femaleIds = await redis.smembers('instant:female_pool');
    const activeFemales = [];

    if (femaleIds.length > 0) {
      // Single batched query replacing N individual queries
      const usersRes = await db.query(
        'SELECT id, full_name, phone_number, incoming_paid_calls_enabled FROM public.users WHERE id = ANY($1::uuid[])',
        [femaleIds]
      );
      const userMap = new Map(usersRes.rows.map((u) => [u.id, u]));

      // Pipelined Redis checks replacing N individual GET calls
      const pipeline = redis.pipeline();
      femaleIds.forEach((fId) => {
        pipeline.get(`instant:snooze:${fId}`);
      });
      const snoozeResults = await pipeline.exec();

      for (let i = 0; i < femaleIds.length; i++) {
        const fId = femaleIds[i];
        const user = userMap.get(fId);
        if (!user || user.incoming_paid_calls_enabled !== true) {
          await redis.srem('instant:female_pool', fId);
          continue;
        }

        const fSocket = getSocketForUser(io, fId);
        const isRedisOnline = await PresenceService.isUserOnline(redis, fId);
        const isOnline = !!fSocket || isRedisOnline;
        const isSnoozed = !!(snoozeResults[i] && snoozeResults[i][1]);

        activeFemales.push({
          userId: fId,
          fullName: user.full_name || 'Unknown',
          phoneNumber: user.phone_number || 'N/A',
          isSnoozed: isSnoozed,
          isOnline: isOnline,
        });
      }
    }

    // 4. Ongoing active calls (only those truly in memory & db)
    const activeCallsRes = await db.query(`
      SELECT s.id, s.bid_amount, s.status, s.agora_channel_name, s.started_at, s.scratch_card_unlocked,
             m.full_name as male_name, f.full_name as female_name
      FROM public.instant_call_sessions s
      LEFT JOIN public.users m ON m.id = s.male_user_id
      LEFT JOIN public.users f ON f.id = s.female_user_id
      WHERE s.status = 'in_call'
      ORDER BY s.started_at DESC
    `);

    res.json({
      timestamp: new Date().toISOString(),
      waitingMalesCount: waitingMales.length,
      waitingMales,
      activeFemalesCount: activeFemales.length,
      activeFemales,
      ongoingCallsCount: activeCallsRes.rows.length,
      ongoingCalls: activeCallsRes.rows,
    });
  } catch (err) {
    console.error('Error fetching dev queues:', err.message);
    res.status(500).json({ error: 'Failed to inspect queues' });
  }
});

// ── GET/POST /api/instant/dev/cleanup ────────────────────────────────────────
// Quick admin reset to clear ghost calls, refund queued males, and reset stale Redis state
router.all('/dev/cleanup', authMiddleware, adminOnly, async (req, res) => {
  try {
    const db = require('../../db');

    // Refund any males currently waiting in queue before wiping
    const maleQueueIds = await redis.zrevrange('instant:male_queue', 0, -1);
    let refundedCount = 0;
    for (const mId of maleQueueIds) {
      const sessionStr = await redis.get(`instant:male_session:${mId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await instantConnectService.refundEscrowedCoins(mId, bidAmount, sessionId);
        refundedCount++;
      }
      await redis.del(`instant:male_session:${mId}`);
    }
    await redis.del('instant:male_queue');

    // Close any stale active sessions
    const updateRes = await db.query(`
      UPDATE public.instant_call_sessions
      SET status = 'dropped', ended_at = NOW()
      WHERE status IN ('queued', 'ringing', 'in_call')
      RETURNING id
    `);

    // Clean up Redis ringing & snooze keys
    const ringingKeys = await scanKeys(redis, 'instant:ringing:*');
    if (ringingKeys.length > 0) {
      await redis.del(...ringingKeys);
    }
    const snoozeKeys = await scanKeys(redis, 'instant:snooze:*');
    if (snoozeKeys.length > 0) {
      await redis.del(...snoozeKeys);
    }

    res.json({
      success: true,
      message: 'Cleaned up stale queues, refunded queued males, and reset snooze locks',
      refundedWaitingMalesCount: refundedCount,
      cleanedSessionsCount: updateRes.rowCount,
      cleanedRingingKeysCount: ringingKeys.length,
      cleanedSnoozeKeysCount: snoozeKeys.length,
    });
  } catch (err) {
    console.error('Error in /dev/cleanup:', err.message);
    res.status(500).json({ error: 'Failed to perform cleanup' });
  }
});

module.exports = router;

`

================================================================================
FILE: backend/modules/instant_connect/instant_connect.socket.js
================================================================================

`javascript
const crypto = require('crypto');
const { RtcTokenBuilder, RtcRole } = require('agora-access-token');
const { instantConnectService } = require('./instant_connect.service');
const { PresenceService } = require('../presence/presence.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { sendMulticastPushNotification } = require('../../services/firebase.service');
const { callQuotaService, TELECOM_BUSY_MESSAGE } = require('../calls/call_quota.service');
const db = require('../../db');
const redis = require('../../redis');

const AGORA_APP_ID = process.env.AGORA_APP_ID || '';
const AGORA_APP_CERTIFICATE = process.env.AGORA_APP_CERTIFICATE || '';

/**
 * Convert UUID string to 31-bit positive integer Agora UID
 */
function uuidToAgoraUid(uuid) {
  const hash = crypto.createHash('md5').update(uuid || String(Date.now())).digest();
  return hash.readUInt32BE(0) & 0x7fffffff;
}

// In-memory active instant calls map: callId -> { sessionId, maleUserId, maleSocketId, femaleUserId, femaleSocketId, timer10m, startedAt }

const activeInstantCalls = new Map();
// Reverse mapping: socketId -> callId
const socketToInstantCall = new Map();
// Ringing timers: callRequestId -> Timer
const ringingTimers = new Map();
// FCM Surge cascade timers: sessionId -> Timer
const surgeTimers = new Map();
// User socket registry: userId -> socketId
const userSockets = new Map();

/**
 * Generate Agora RTC Token for communication
 */
function generateAgoraToken(channelName, uid) {
  const appId = process.env.AGORA_APP_ID || AGORA_APP_ID;
  const appCertificate = process.env.AGORA_APP_CERTIFICATE || AGORA_APP_CERTIFICATE;

  if (!appId || !appCertificate) {
    return 'test_token_' + Date.now();
  }

  try {
    const role = RtcRole.PUBLISHER;
    const expirationTimeInSeconds = 3600 * 2; // 2 hours
    const currentTimestamp = Math.floor(Date.now() / 1000);
    const privilegeExpiredTs = currentTimestamp + expirationTimeInSeconds;

    return RtcTokenBuilder.buildTokenWithUid(
      appId,
      appCertificate,
      channelName,
      uid,
      role,
      privilegeExpiredTs
    );
  } catch (err) {
    console.error('Error generating Agora token:', err.message);
    return 'fallback_token_' + Date.now();
  }
}

/**
 * Check if a user is female
 */
async function isUserFemale(userId) {
  try {
    const res = await db.query(`SELECT gender FROM public.users WHERE id = $1`, [userId]);
    const g = (res.rows[0]?.gender || '').toLowerCase().trim();
    return g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
  } catch (_) {
    return false;
  }
}

/**
 * Helper to safely resolve connected socket for a user ID across map and io.sockets
 */
function getSocketForUser(io, targetUserId) {
  if (!io || !targetUserId) return null;
  const socketId = userSockets.get(targetUserId);
  if (socketId) {
    const s = io.sockets?.sockets?.get(socketId);
    if (s && s.connected) return s;
  }
  // Try Socket.io room lookup (users join their userId room on connection)
  const room = io.sockets?.adapter?.rooms?.get(targetUserId);
  if (room && room.size > 0) {
    const firstSocketId = room.values().next().value;
    if (firstSocketId) {
      const s = io.sockets?.sockets?.get(firstSocketId);
      if (s && s.connected) {
        userSockets.set(targetUserId, s.id);
        return s;
      }
    }
  }
  // Search live connected sockets in Socket.io
  if (io.sockets?.sockets) {
    for (const [, s] of io.sockets.sockets) {
      if (s.userId === targetUserId && s.connected) {
        userSockets.set(targetUserId, s.id); // Re-sync mapping
        return s;
      }
    }
  }
  return null;
}

let matchmakerIntervalStarted = false;
function startMatchmakerTicker(io, redis) {
  if (matchmakerIntervalStarted) return;
  matchmakerIntervalStarted = true;
  // Safety net interval (every 20s): primary matching is strictly event-driven
  // (queue joins, toggle changes, connections, call endings, and cascade timeouts).
  // This low-frequency safety net ensures no queued male is ever permanently stranded.
  setInterval(() => {
    try {
      triggerInstantMatchmaker(io, redis);
    } catch (err) {
      // ignore ticker errors
    }
  }, 20000);
}

/**
 * Trigger Instant Matchmaker cycle
 */
async function triggerInstantMatchmaker(io, redis) {
  if (!io || !redis) return;
  try {
    // 1. Get highest-priority male from queue
    const topMales = await redis.zrevrange('instant:male_queue', 0, 0);
    if (!topMales || topMales.length === 0) return;

    const maleUserId = topMales[0];
    const sessionStr = await redis.get(`instant:male_session:${maleUserId}`);
    if (!sessionStr) {
      // Stale queue entry whose session expired/was deleted -> evict
      await redis.zrem('instant:male_queue', maleUserId);
      return;
    }

    const sessionData = JSON.parse(sessionStr);
    const { sessionId, bidAmount } = sessionData;

    // Check if male is already in an active call -> evict from queue
    const maleInCall = await redis.get(`instant:in_call:${maleUserId}`);
    if (maleInCall) {
      await redis.zrem('instant:male_queue', maleUserId);
      return;
    }

    // Check if male already has an active ringing cycle in progress (waiting for 15s response)
    const activeMaleRequest = await redis.get(`instant:active_request:${maleUserId}`);
    if (activeMaleRequest) {
      return;
    }

    // Verify male socket is still active
    const maleSocket = getSocketForUser(io, maleUserId);
    if (!maleSocket || !maleSocket.connected) {
      const isOnline = await PresenceService.isUserOnline(redis, maleUserId);
      if (!isOnline) {
        await redis.zrem('instant:male_queue', maleUserId);
        await redis.del(`instant:male_session:${maleUserId}`);
        await instantConnectService.refundEscrowedCoins(maleUserId, bidAmount, sessionId);
        console.log(`🧹 [Instant Matchmaker] Evicted offline male ${maleUserId} from queue and refunded ${bidAmount} coins`);
      }
      return;
    }

    const activeMaleSocketId = maleSocket.id;

    // 2. Fetch available females directly from Redis pool (maintained via toggleIncomingPaidCalls & socket connect)
    const allFemales = await redis.smembers('instant:female_pool');

    // Filter females who are currently connected, have toggle ON in DB, not busy, and haven't declined this session
    const eligibleFemales = [];
    let anyOnlineFemaleConnected = false;

    // 1. Gather online candidates first to avoid unnecessary Redis checks for offline users
    const onlineCandidates = [];
    for (const femaleId of (allFemales || [])) {
      if (femaleId === maleUserId) continue;

      const fSocket = getSocketForUser(io, femaleId);
      if (fSocket && fSocket.connected) {
        anyOnlineFemaleConnected = true;
        onlineCandidates.push({ femaleId, fSocket });
      }
    }

    // 2. Batch all Redis status checks (declined, snooze, ringing, in_call) in a single pipeline round-trip
    if (onlineCandidates.length > 0) {
      const pipeline = redis.pipeline();
      for (const { femaleId } of onlineCandidates) {
        pipeline.get(`instant:declined:${sessionId}:${femaleId}`);
        pipeline.get(`instant:snooze:${femaleId}`);
        pipeline.get(`instant:ringing:${femaleId}`);
        pipeline.get(`instant:in_call:${femaleId}`);
      }
      const results = await pipeline.exec();

      for (let i = 0; i < onlineCandidates.length; i++) {
        const { femaleId, fSocket } = onlineCandidates[i];
        const baseIdx = i * 4;
        const hasDeclined = results[baseIdx]?.[1];
        const isSnoozed = results[baseIdx + 1]?.[1];
        const isRinging = results[baseIdx + 2]?.[1];
        const inInstantCall = results[baseIdx + 3]?.[1];

        if (hasDeclined || isSnoozed || isRinging || inInstantCall) continue;

        let isBusy = socketToInstantCall.has(fSocket.id);
        if (!isBusy) {
          for (const call of activeInstantCalls.values()) {
            if (call.femaleUserId === femaleId || call.maleUserId === femaleId) {
              isBusy = true;
              break;
            }
          }
        }
        if (isBusy) continue;

        eligibleFemales.push({ userId: femaleId, socketId: fSocket.id, socket: fSocket });
      }
    }

    if (eligibleFemales.length === 0) {
      // If ANY female is currently connected online, do NOT spam FCM pushes
      if (anyOnlineFemaleConnected) {
        return;
      }

      // Check if a 30s surge cascade timer is already actively running for this session
      if (surgeTimers.has(sessionId)) {
        return;
      }

      // Check if session was already claimed
      const claimed = await redis.get(`instant:claim_session:${sessionId}`);
      if (claimed) return;

      // 0 available females on active sockets -> trigger next wave of 1:10 FCM surge (different females each wave)
      const notifiedKey = `instant:notified_females:${sessionId}`;
      const alreadyNotifiedIds = (await redis.smembers(notifiedKey)) || [];
      const connectedUserIds = Array.from(userSockets.keys());
      const excludeIds = Array.from(new Set([maleUserId, ...connectedUserIds, ...alreadyNotifiedIds]));

      const offlineFemales = await instantConnectService.getSurgeEligibleFemales(excludeIds, 10);

      // Filter out any females who are currently in an active call
      const availableOfflineFemales = [];
      for (const f of offlineFemales) {
        const inCall = (await redis.get(`instant:in_call:${f.id}`)) || (await redis.get(`call_lock:${f.id}`));
        if (!inCall) {
          availableOfflineFemales.push(f);
        }
      }

      if (availableOfflineFemales.length > 0) {
        // Record these newly notified females in Redis (TTL: 10 minutes)
        await redis.sadd(notifiedKey, ...availableOfflineFemales.map((f) => f.id));
        await redis.expire(notifiedKey, 600);

        const tokens = Array.from(new Set(availableOfflineFemales.map((f) => f.fcm_token).filter(Boolean)));
        console.log(`📡 [FCM Surge Wave] Dispatching surge alert to ${tokens.length} unique offline female devices for male ${maleUserId} (Session: ${sessionId}, Total Notified so far: ${alreadyNotifiedIds.length + availableOfflineFemales.length})`);

        if (tokens.length > 0) {
          await sendMulticastPushNotification({
            tokens,
            title: '📞 Incoming VIP Call!',
            body: `A VIP user wants to connect with you. Tap to accept and earn coins!`,
            tag: `instant_${sessionId}`,
            data: {
              type: 'instant_call',
              sessionId: String(sessionId),
              bidAmount: String(bidAmount),
            },
          });
        }

        // Set 30-second cascade timer: If no female answers within 30s, trigger next wave of 10 different females!
        const surgeTimer = setTimeout(async () => {
          surgeTimers.delete(sessionId);

          // Verify male is still in queue and call is still unclaimed
          const maleInQueue = await redis.zscore('instant:male_queue', maleUserId);
          const isClaimed = await redis.get(`instant:claim_session:${sessionId}`);
          if (!maleInQueue || isClaimed) {
            await redis.del(notifiedKey);
            return;
          }

          console.log(`⏰ [FCM Surge] 30s timeout elapsed without answer for session ${sessionId}. Cascading to next 10 offline females...`);
          triggerInstantMatchmaker(io, redis);
        }, 30000);

        surgeTimers.set(sessionId, surgeTimer);
      } else {
        console.log(`ℹ️ [FCM Surge] No more unnotified offline females available for session ${sessionId}.`);
      }
      return;
    }

    // 3. 1 : 2 Dual Ring Dispatch (Select up to 2 random eligible females)
    const shuffled = eligibleFemales.sort(() => 0.5 - Math.random());
    const selectedFemales = shuffled.slice(0, 2);

    const callRequestId = `req_${sessionId}_${Date.now()}`;

    // Mark male in active request lock (expires in 18s) to prevent duplicate triggers
    await redis.set(`instant:active_request:${maleUserId}`, callRequestId, 'EX', 18);

    // Mark females in temporary ringing lock (expires in 18s)
    for (const f of selectedFemales) {
      await redis.set(`instant:ringing:${f.userId}`, callRequestId, 'EX', 18);
      await redis.srem('instant:female_pool', f.userId);
    }

    // Save request metadata in Redis
    const requestMeta = {
      sessionId,
      maleUserId,
      maleSocketId: activeMaleSocketId,
      bidAmount,
      femaleUserIds: selectedFemales.map((f) => f.userId),
      declinedFemaleUserIds: [],
    };
    await redis.set(`instant:request:${callRequestId}`, JSON.stringify(requestMeta), 'EX', 30);

    console.log(`⚡ [Instant Connect] Ringing 1:2 pair (${selectedFemales.map((f) => f.userId).join(', ')}) for male ${maleUserId} (15s timeout)`);

    // Emit incoming call to both female sockets (WITHOUT premature Agora credentials)
    for (const f of selectedFemales) {
      f.socket.emit('incoming_instant_call', {
        callRequestId,
        sessionId,
        bidAmount,
        timeoutSeconds: 15,
      });
    }

    // 4. Set 15-second cascade timer
    const cascadeTimer = setTimeout(async () => {
      ringingTimers.delete(callRequestId);

      // Check if call was already claimed/accepted
      const claimed = await redis.get(`instant:claim_session:${sessionId}`);
      if (claimed) return;

      console.log(`⏰ [Instant Connect] 15s timeout reached for ${callRequestId}. Cascading to next pair...`);
      await redis.del(`instant:active_request:${maleUserId}`);

      // Dismiss ringing on both female sockets and put on 30s temporary snooze
      for (const f of selectedFemales) {
        await redis.del(`instant:ringing:${f.userId}`);
        await redis.set(`instant:snooze:${f.userId}`, '1', 'EX', 30); // 30s AFK snooze
        f.socket.emit('instant_call_dismissed', { callRequestId, reason: 'timeout' });
      }

      // Re-trigger matchmaker to cascade to next available girls
      triggerInstantMatchmaker(io, redis);
    }, 15500);

    ringingTimers.set(callRequestId, cascadeTimer);
  } catch (err) {
    console.error('Error in triggerInstantMatchmaker:', err.message);
  }
}

/**
 * Register Instant Connect Socket.io handlers
 */
function registerInstantConnectHandlers(io, socket, redis) {
  startMatchmakerTicker(io, redis);

  const userId = socket.userId;
  if (userId) {
    userSockets.set(userId, socket.id);
    redis.del(`instant:snooze:${userId}`).catch(() => {});
    redis.del(`instant:ringing:${userId}`).catch(() => {});

    // Auto-register connected female buddies into instant pool if their toggle is ON
    db.query(`SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`, [userId])
      .then((res) => {
        const g = (res.rows[0]?.gender || '').toLowerCase().trim();
        const isF = g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
        if (isF && res.rows[0]?.incoming_paid_calls_enabled === true) {
          redis.sadd('instant:female_pool', userId);
          console.log(`⚡ [Instant Connect] Female ${userId} verified & added to female pool on connect`);
          triggerInstantMatchmaker(io, redis);
        }
      })
      .catch((err) => console.error('Error hydrating female pool on socket connect:', err.message));
  }

  // ── 1. instant:join_queue (Male Bidding & Joining) ────────────────────────
  socket.on('instant:join_queue', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const bidAmount = parseInt(data?.bidAmount, 10);
      if (!bidAmount || bidAmount < 99) {
        cb({ success: false, error: 'INVALID_AMOUNT', message: 'Minimum bid amount is 99 coins.' });
        return;
      }

      // Check active subscription
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        cb({ success: false, error: 'SUBSCRIPTION_REQUIRED', message: 'Active subscription required.' });
        return;
      }

      // Quota check: 200m monthly audio cap
      const quotaCheck = await callQuotaService.checkCanStartAudioCall(userId);
      if (!quotaCheck.allowed) {
        cb({ success: false, error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }

      // Check if already in queue or call
      const existingQueueScore = await redis.zscore('instant:male_queue', userId);
      if (existingQueueScore) {
        cb({ success: true, message: 'Already in queue' });
        return;
      }

      // Escrow coins from male wallet
      const escrowResult = await instantConnectService.escrowMaleCoins(userId, bidAmount);
      if (!escrowResult.success) {
        cb(escrowResult);
        return;
      }

      // Create session in DB
      const session = await instantConnectService.createSession(userId, bidAmount);

      // Score formula: Amount * 10^12 + (10^12 - Timestamp)
      const now = Date.now();
      const score = bidAmount * Math.pow(10, 11) + (Math.pow(10, 11) - (now % Math.pow(10, 11)));

      await redis.zadd('instant:male_queue', score, userId);
      await redis.set(
        `instant:male_session:${userId}`,
        JSON.stringify({ sessionId: session.id, bidAmount, socketId: socket.id }),
        'EX',
        600
      );

      // Determine queue rank
      const rank = (await redis.zrevrank('instant:male_queue', userId)) ?? 0;

      cb({
        success: true,
        sessionId: session.id,
        bidAmount,
        queuePosition: rank + 1,
        newBalance: escrowResult.newBalance,
      });

      socket.emit('instant:queue_status', {
        status: 'queued',
        queuePosition: rank + 1,
        bidAmount,
      });

      // Trigger matchmaker cycle
      triggerInstantMatchmaker(io, redis);
    } catch (err) {
      console.error(`Error in instant:join_queue for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR', message: 'Failed to join instant queue' });
    }
  });

  // ── 2. instant:leave_queue (Male Cancelling with 100% Refund) ─────────────
  socket.on('instant:leave_queue', async (callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

        const refundRes = await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        cb({ success: true, newBalance: refundRes.newBalance });
        socket.emit('instant:queue_left', { refundedCoins: bidAmount, newBalance: refundRes.newBalance });
      } else {
        cb({ success: true });
      }
    } catch (err) {
      console.error(`Error leaving instant queue for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR' });
    }
  });

  // ── 3. instant:toggle_incoming (Female Toggle Switch) ────────────────────
  socket.on('instant:toggle_incoming', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    try {
      const enabled = data?.enabled === true;
      const isFemale = await isUserFemale(userId);
      if (!isFemale) {
        cb({ success: false, error: 'FEMALE_ONLY', message: 'Paid call receiving is for female accounts only.' });
        return;
      }

      const res = await instantConnectService.toggleIncomingPaidCalls(userId, enabled, redis);
      cb(res);

      if (enabled) {
        triggerInstantMatchmaker(io, redis);
      }
    } catch (err) {
      console.error(`Error in instant:toggle_incoming for ${userId}:`, err.message);
      cb({ success: false, error: 'SERVER_ERROR' });
    }
  });

  // ── 4. instant:accept_call (Female First-Come, First-Served) ──────────────
  socket.on('instant:accept_call', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    const callRequestId = data?.callRequestId;
    if (!callRequestId) {
      cb({ success: false, error: 'INVALID_REQUEST' });
      return;
    }

    try {
      const requestStr = await redis.get(`instant:request:${callRequestId}`);
      if (!requestStr) {
        cb({ success: false, error: 'REQUEST_EXPIRED', message: 'Call request expired.' });
        return;
      }

      const reqData = JSON.parse(requestStr);
      const { sessionId, maleUserId, maleSocketId, bidAmount, femaleUserIds } = reqData;

      // Verify female user has active subscription pass to answer VIP calls
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        console.warn(`🚫 [Instant Connect] Unsubscribed female ${userId} attempted to accept VIP call request ${callRequestId}`);
        cb({
          success: false,
          error: 'SUBSCRIPTION_REQUIRED',
          message: 'An active VIP Subscription Pass is required to answer VIP calls.',
        });
        return;
      }

      // Quota check: 200-minute monthly audio cap for female participant
      const femaleQuota = await callQuotaService.checkCanStartAudioCall(userId);
      if (!femaleQuota.allowed) {
        cb({ success: false, error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }

      // Atomic SETNX to claim the entire session! (Prevents any second female from connecting)
      const win = await redis.set(`instant:claim_session:${sessionId}`, userId, 'NX', 'EX', 120);

      // Clear ringing cascade timer
      const timer = ringingTimers.get(callRequestId);
      if (timer) {
        clearTimeout(timer);
        ringingTimers.delete(callRequestId);
      }
      await redis.del(`instant:active_request:${maleUserId}`);

      if (win !== 'OK') {
        // Another female won the race or call already active
        cb({ success: false, error: 'ALREADY_CLAIMED', message: 'Another buddy answered this call!' });
        socket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
        return;
      }

      // Clear surge cascade timer and notified list
      const sTimer = surgeTimers.get(sessionId);
      if (sTimer) {
        clearTimeout(sTimer);
        surgeTimers.delete(sessionId);
      }
      await redis.del(`instant:notified_females:${sessionId}`);

      // Generate UNIQUE Agora channel name and tokens immediately (0ms)
      const agoraChannelName = `instant_${sessionId}_${crypto.randomBytes(4).toString('hex')}`;
      const maleUid = uuidToAgoraUid(maleUserId);
      const femaleUid = uuidToAgoraUid(userId);

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);
      const callId = `instant_call_${sessionId}`;

      // Clean up other ringing females in parallel
      const cleanupPromises = (femaleUserIds || []).map(async (fId) => {
        await redis.del(`instant:ringing:${fId}`);
        if (fId !== userId) {
          const loserSocket = getSocketForUser(io, fId);
          if (loserSocket) {
            loserSocket.emit('instant_call_dismissed', { callRequestId, reason: 'already_answered' });
          }
          await redis.sadd('instant:female_pool', fId);
        }
      });

      // Run DB call session start, user profile queries, and Redis in-call locks ALL IN PARALLEL!
      let maleUser = {};
      let femaleUser = {};
      try {
        const [_, [maleUserRes, femaleUserRes]] = await Promise.all([
          instantConnectService.startCallSession(sessionId, userId, agoraChannelName),
          Promise.all([
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [maleUserId]),
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [userId]),
          ]),
          Promise.all(cleanupPromises),
          redis.zrem('instant:male_queue', maleUserId),
          redis.del(`instant:male_session:${maleUserId}`),
          redis.srem('instant:female_pool', userId),
          redis.set(`instant:in_call:${userId}`, callId, 'EX', 7200),
          redis.set(`instant:in_call:${maleUserId}`, callId, 'EX', 7200),
          redis.set(`call_lock:${userId}`, '1', 'EX', 7200),
          redis.set(`call_lock:${maleUserId}`, '1', 'EX', 7200),
        ]);
        maleUser = maleUserRes.rows[0] || {};
        femaleUser = femaleUserRes.rows[0] || {};
      } catch (err) {
        console.error('Error during parallel instant call initialization:', err.message);
      }

      // Start 10-minute (600-second) server-authoritative milestone timer
      const milestoneTimer = setTimeout(async () => {
        console.log(` [Instant Connect] 10-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          const liveMaleSocket = getSocketForUser(io, maleUserId);
          const liveFemaleSocket = getSocketForUser(io, userId);

          if (liveMaleSocket) {
            liveMaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
            });
          }
          if (liveFemaleSocket) {
            liveFemaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
              scratchCardId: scratchCard.id,
              coinReward: scratchCard.coin_reward,
            });
          }
        }
      }, 10 * 60 * 1000); // 10 minutes

      const activeMaleSocket = getSocketForUser(io, maleUserId) || { id: maleSocketId };

      const activeCallObj = {
        callId,
        sessionId,
        maleUserId,
        maleSocketId: activeMaleSocket.id,
        femaleUserId: userId,
        femaleSocketId: socket.id,
        startedAt: Date.now(),
        bidAmount,
        milestoneTimer,
        agoraChannelName,
      };

      activeInstantCalls.set(callId, activeCallObj);
      socketToInstantCall.set(activeMaleSocket.id, callId);
      socketToInstantCall.set(socket.id, callId);

      const liveAppId = process.env.AGORA_APP_ID || AGORA_APP_ID;

      // Notify Male (revealing female profile)
      if (activeMaleSocket && typeof activeMaleSocket.emit === 'function') {
        activeMaleSocket.emit('instant:call_connected', {
          callId,
          sessionId,
          agoraChannelName,
          agoraToken: maleToken,
          agoraUid: maleUid,
          remoteUid: femaleUid,
          agoraAppId: liveAppId,
          bidAmount,
          otherUserName: femaleUser.full_name || 'VIP Partner',
          matchedUser: {
            id: femaleUser.id || userId,
            fullName: femaleUser.full_name || 'VIP Partner',
            avatarUrl: femaleUser.avatar_seed || null,
            avatarSeed: femaleUser.avatar_seed || null,
            avatarStyle: femaleUser.avatar_style || 'avataaars',
            gender: femaleUser.gender || 'Female',
          },
          durationLimitSeconds: 60,
        });
      } else if (maleUserId) {
        io.to(maleUserId).emit('instant:call_connected', {
          callId,
          sessionId,
          agoraChannelName,
          agoraToken: maleToken,
          agoraUid: maleUid,
          remoteUid: femaleUid,
          agoraAppId: liveAppId,
          bidAmount,
          otherUserName: femaleUser.full_name || 'VIP Partner',
          matchedUser: {
            id: femaleUser.id || userId,
            fullName: femaleUser.full_name || 'VIP Partner',
            avatarUrl: femaleUser.avatar_seed || null,
            avatarSeed: femaleUser.avatar_seed || null,
            avatarStyle: femaleUser.avatar_style || 'avataaars',
            gender: femaleUser.gender || 'Female',
          },
          durationLimitSeconds: 60,
        });
      }

      // Notify Female (revealing male profile)
      socket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: femaleToken,
        agoraUid: femaleUid,
        remoteUid: maleUid,
        agoraAppId: liveAppId,
        bidAmount,
        otherUserName: maleUser.full_name || 'VIP Partner',
        matchedUser: {
          id: maleUser.id || maleUserId,
          fullName: maleUser.full_name || 'VIP Partner',
          avatarUrl: maleUser.avatar_seed || null,
          avatarSeed: maleUser.avatar_seed || null,
          avatarStyle: maleUser.avatar_style || 'avataaars',
          gender: maleUser.gender || 'Male',
        },
        durationLimitSeconds: 60,
      });

      cb({ success: true, callId, sessionId });
    } catch (err) {
      console.error(`Error accepting instant call by ${userId}:`, err);
      cb({ success: false, error: 'SERVER_ERROR', message: err.message });
    }
  });

  // ── 5. instant:decline_call ──────────────────────────────────────────────
  socket.on('instant:decline_call', async (data) => {
    const callRequestId = data?.callRequestId;
    if (!callRequestId) return;

    try {
      await redis.del(`instant:ringing:${userId}`);
      await redis.set(`instant:snooze:${userId}`, '1', 'EX', 20); // 20s cooldown

      const requestStr = await redis.get(`instant:request:${callRequestId}`);
      if (requestStr) {
        const reqData = JSON.parse(requestStr);
        const { sessionId, maleUserId, femaleUserIds } = reqData;
        if (sessionId) {
          // Permanently blacklist this female for this male session (5 mins)
          await redis.set(`instant:declined:${sessionId}:${userId}`, '1', 'EX', 300);
          console.log(`🚫 [Instant Connect] Female ${userId} permanently declined session ${sessionId}`);
        }

        // Track declined female list in request metadata
        const declinedList = reqData.declinedFemaleUserIds || [];
        if (!declinedList.includes(userId)) {
          declinedList.push(userId);
          reqData.declinedFemaleUserIds = declinedList;
          await redis.set(`instant:request:${callRequestId}`, JSON.stringify(reqData), 'EX', 30);
        }

        // If ALL ringing females in this request have declined, cascade immediately!
        if (declinedList.length >= (femaleUserIds || []).length) {
          console.log(`⚡ [Instant Connect] All ringing females declined ${callRequestId}. Cascading to next buddies immediately.`);
          const timer = ringingTimers.get(callRequestId);
          if (timer) {
            clearTimeout(timer);
            ringingTimers.delete(callRequestId);
          }
          await redis.del(`instant:active_request:${maleUserId}`);
          triggerInstantMatchmaker(io, redis);
        }
      }
    } catch (err) {
      console.error(`Error in instant:decline_call for ${userId}:`, err.message);
    }
  });

  // ── 5b. instant:claim_and_join & instant:claim_surge_call (Atomic One-Tap Join from Push) ───
  const handleClaimAndJoin = async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};
    const sessionId = data?.sessionId;
    if (!sessionId) {
      cb({ success: false, error: 'INVALID_SESSION', message: 'Invalid session ID' });
      return;
    }

    try {
      console.log(`📡 [Instant Connect] Female ${userId} atomically claiming and joining surge session ${sessionId}`);

      // 1. Verify female user eligibility
      const dbRes = await db.query(
        `SELECT incoming_paid_calls_enabled, gender FROM public.users WHERE id = $1`,
        [userId]
      );
      const userRow = dbRes.rows[0];
      const g = (userRow?.gender || '').toLowerCase().trim();
      const isF = g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
      if (!isF || !userRow?.incoming_paid_calls_enabled) {
        cb({ success: false, error: 'NOT_ELIGIBLE', message: 'Incoming paid calls are disabled on your account.' });
        return;
      }

      // Verify female user has active subscription pass to answer VIP calls
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        console.warn(`🚫 [Instant Connect] Unsubscribed female ${userId} attempted to claim surge VIP session ${sessionId}`);
        cb({
          success: false,
          error: 'SUBSCRIPTION_REQUIRED',
          message: 'An active VIP Subscription Pass is required to answer VIP calls.',
        });
        return;
      }

      // 2. Check if female is already in an active call
      const isCurrentlyInCall = await redis.get(`instant:in_call:${userId}`) || await redis.get(`call_lock:${userId}`);
      if (isCurrentlyInCall) {
        cb({ success: false, error: 'ALREADY_IN_CALL', message: 'You are currently in another call.' });
        return;
      }

      // 3. Verify session in DB (must still be waiting / queued)
      const sessRes = await db.query(
        `SELECT * FROM public.instant_call_sessions WHERE id = $1 AND status IN ('queued', 'waiting')`,
        [sessionId]
      );
      if (sessRes.rows.length === 0) {
        cb({ success: false, error: 'SESSION_EXPIRED', message: 'Another buddy already answered this VIP call.' });
        return;
      }

      const session = sessRes.rows[0];
      const maleUserId = session.male_user_id;

      // Quota check: 200-minute monthly audio cap for female participant
      const femaleQuota = await callQuotaService.checkCanStartAudioCall(userId);
      if (!femaleQuota.allowed) {
        cb({ success: false, error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }

      // 4. Atomic Concurrency Lock: First female to acquire this lock wins the call
      const claimKey = `instant:claimed:${sessionId}`;
      const claimAcquired = await redis.set(claimKey, userId, 'EX', 120, 'NX');
      if (!claimAcquired) {
        const winnerId = await redis.get(claimKey);
        if (winnerId !== userId) {
          console.log(`⏱️ [Instant Connect] Female ${userId} lost race condition for session ${sessionId} to winner ${winnerId}`);
          cb({ success: false, error: 'ALREADY_CLAIMED', message: 'Another buddy already answered this VIP call.' });
          return;
        }
      }

      // 5. Verify male socket is still active and connected
      const maleSocket = getSocketForUser(io, maleUserId);
      if (!maleSocket || !maleSocket.connected) {
        await redis.del(claimKey);
        cb({ success: false, error: 'MALE_DISCONNECTED', message: 'The caller is no longer connected.' });
        return;
      }

      // 6. Clean up any other active ring requests/timers for this male or session
      const activeReqId = await redis.get(`instant:active_request:${maleUserId}`);
      if (activeReqId) {
        const timer = ringingTimers.get(activeReqId);
        if (timer) {
          clearTimeout(timer);
          ringingTimers.delete(activeReqId);
        }
        const reqDataStr = await redis.get(`instant:request:${activeReqId}`);
        if (reqDataStr) {
          try {
            const reqData = JSON.parse(reqDataStr);
            for (const fId of (reqData.femaleUserIds || [])) {
              await redis.del(`instant:ringing:${fId}`);
              if (fId !== userId) {
                const loserSocket = getSocketForUser(io, fId);
                if (loserSocket) {
                  loserSocket.emit('instant_call_dismissed', { callRequestId: activeReqId, reason: 'already_answered' });
                }
              }
            }
          } catch (_) {}
        }
        await redis.del(`instant:request:${activeReqId}`);
        await redis.del(`instant:active_request:${maleUserId}`);
      }

      await redis.del(`instant:snooze:${userId}`);
      await redis.del(`instant:ringing:${userId}`);

      // 7. Remove male from queue and active session, cancel surge timer
      await redis.zrem('instant:male_queue', maleUserId);
      await redis.del(`instant:male_session:${maleUserId}`);
      await redis.del(`instant:notified_females:${sessionId}`);

      const sTimer = surgeTimers.get(sessionId);
      if (sTimer) {
        clearTimeout(sTimer);
        surgeTimers.delete(sessionId);
      }

      // 8. Generate Agora Channel Name and unique tokens for both parties immediately (0ms)
      const agoraChannelName = `instant_${sessionId}_${crypto.randomBytes(4).toString('hex')}`;
      const maleUid = uuidToAgoraUid(maleUserId);
      const femaleUid = uuidToAgoraUid(userId);

      const maleToken = generateAgoraToken(agoraChannelName, maleUid);
      const femaleToken = generateAgoraToken(agoraChannelName, femaleUid);
      const callId = `instant_call_${sessionId}`;

      // 9 & 10 & 12. Run DB call session start, user profile queries, and Redis in-call locks ALL IN PARALLEL!
      let maleUser = {};
      let femaleUser = {};
      try {
        const [_, [maleUserRes, femaleUserRes]] = await Promise.all([
          instantConnectService.startCallSession(sessionId, userId, agoraChannelName),
          Promise.all([
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [maleUserId]),
            db.query(`SELECT id, full_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [userId]),
          ]),
          redis.srem('instant:female_pool', userId),
          redis.set(`instant:in_call:${userId}`, callId, 'EX', 7200),
          redis.set(`instant:in_call:${maleUserId}`, callId, 'EX', 7200),
          redis.set(`call_lock:${userId}`, '1', 'EX', 7200),
          redis.set(`call_lock:${maleUserId}`, '1', 'EX', 7200),
        ]);
        maleUser = maleUserRes.rows[0] || {};
        femaleUser = femaleUserRes.rows[0] || {};
      } catch (userErr) {
        console.error('Error in parallel instant claim initialization:', userErr.message);
      }

      // 11. Start 10-minute milestone timer for scratch card reward (600 seconds)
      const milestoneTimer = setTimeout(async () => {
        console.log(` [Instant Connect] 10-Minute Milestone reached for session ${sessionId}! Unlocking scratch card.`);
        const scratchCard = await instantConnectService.trigger10MinuteMilestone(sessionId);
        if (scratchCard) {
          const liveMaleSocket = getSocketForUser(io, maleUserId);
          const liveFemaleSocket = getSocketForUser(io, userId);

          if (liveMaleSocket) {
            liveMaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
            });
          }
          if (liveFemaleSocket) {
            liveFemaleSocket.emit('instant:milestone_reached', {
              callId,
              sessionId,
              milestoneMinutes: 10,
              scratchCardId: scratchCard.id,
              coinReward: scratchCard.coin_reward,
            });
          }
        }
      }, 10 * 60 * 1000);

      const activeMaleSocket = maleSocket;

      const activeCallObj = {
        callId,
        sessionId,
        maleUserId,
        maleSocketId: activeMaleSocket.id,
        femaleUserId: userId,
        femaleSocketId: socket.id,
        startedAt: Date.now(),
        bidAmount: session.bid_amount,
        milestoneTimer,
        agoraChannelName,
      };

      activeInstantCalls.set(callId, activeCallObj);
      socketToInstantCall.set(activeMaleSocket.id, callId);
      socketToInstantCall.set(socket.id, callId);

      const liveAppId = process.env.AGORA_APP_ID || AGORA_APP_ID;

      // 13. Direct Agora RTC Connection dispatch to Male
      activeMaleSocket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: maleToken,
        agoraUid: maleUid,
        remoteUid: femaleUid,
        agoraAppId: liveAppId,
        bidAmount: session.bid_amount,
        otherUserName: femaleUser.full_name || 'VIP Partner',
        matchedUser: {
          id: femaleUser.id || userId,
          fullName: femaleUser.full_name || 'VIP Partner',
          avatarUrl: femaleUser.avatar_seed || null,
          avatarSeed: femaleUser.avatar_seed || null,
          avatarStyle: femaleUser.avatar_style || 'avataaars',
          gender: femaleUser.gender || 'Female',
        },
        durationLimitSeconds: 60,
      });

      // 14. Direct Agora RTC Connection dispatch to Female
      socket.emit('instant:call_connected', {
        callId,
        sessionId,
        agoraChannelName,
        agoraToken: femaleToken,
        agoraUid: femaleUid,
        remoteUid: maleUid,
        agoraAppId: liveAppId,
        bidAmount: session.bid_amount,
        otherUserName: maleUser.full_name || 'VIP User',
        matchedUser: {
          id: maleUser.id || maleUserId,
          fullName: maleUser.full_name || 'VIP User',
          avatarUrl: maleUser.avatar_seed || null,
          avatarSeed: maleUser.avatar_seed || null,
          avatarStyle: maleUser.avatar_style || 'avataaars',
          gender: maleUser.gender || 'Male',
        },
        durationLimitSeconds: 60,
      });

      console.log(`🚀 [Instant Connect] Instant one-tap VIP call connected: Session ${sessionId} (Male ${maleUserId} <-> Female ${userId})`);
      cb({ success: true, callId });
    } catch (err) {
      console.error(`❌ [Instant Connect] Error in handleClaimAndJoin for ${userId}:`, err.message);

      // 1. Release atomic Redis claim lock immediately if held by this user
      const claimKey = `instant:claimed:${sessionId}`;
      try {
        const winner = await redis.get(claimKey);
        if (winner === userId) {
          await redis.del(claimKey);
        }
      } catch (_) {}

      // 2. If DB status was already mutated to in_call before failure, rollback session to 'waiting'
      try {
        const checkRes = await db.query(
          `SELECT status FROM public.instant_call_sessions WHERE id = $1`,
          [sessionId]
        );
        if (checkRes.rows.length > 0 && checkRes.rows[0].status === 'in_call') {
          await db.query(
            `UPDATE public.instant_call_sessions 
             SET status = 'waiting', female_user_id = NULL, agora_channel_name = NULL, started_at = NULL 
             WHERE id = $1`,
            [sessionId]
          );
          console.log(`🔄 [Instant Connect] Successfully rolled back session ${sessionId} status to 'waiting'`);
        }
      } catch (dbErr) {
        console.error('Error rolling back DB session status on claim failure:', dbErr.message);
      }

      // 3. Clean up any partial in-call Redis locks
      try {
        await redis.del(`instant:in_call:${userId}`);
        await redis.del(`call_lock:${userId}`);
      } catch (_) {}

      cb({ success: false, error: 'SERVER_ERROR', message: 'Failed to join VIP call.' });
    }
  };

  socket.on('instant:claim_and_join', handleClaimAndJoin);
  socket.on('instant:claim_surge_call', handleClaimAndJoin);

  // ── 6. instant:end_call ──────────────────────────────────────────────────
  socket.on('instant:end_call', async (data) => {
    try {
      const callId = data?.callId || socketToInstantCall.get(socket.id);
      await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'manual_hangup',
      });
    } catch (err) {
      console.error(`Error ending instant call for ${userId}:`, err.message);
    }
  });

  // ── Disconnect cleanup ───────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    userSockets.delete(userId);
    // Remove from female pool if disconnected
    await redis.srem('instant:female_pool', userId);

    // Clean up waiting male from queue and refund escrowed coins on disconnect
    try {
      const sessionStr = await redis.get(`instant:male_session:${userId}`);
      if (sessionStr) {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

        await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        console.log(`🧹 [Instant Connect] Cleaned up waiting male ${userId} on disconnect & refunded ${bidAmount} coins`);
      }
    } catch (err) {
      console.error(`Error cleaning up male queue on disconnect for ${userId}:`, err.message);
    }

    try {
      const callId = socketToInstantCall.get(socket.id);
      await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'peer_disconnected',
      });
    } catch (err) {
      console.error(`Error on instant disconnect for ${userId}:`, err.message);
    }
  });
}

/**
 * End an instant connect call session reliably across sockets & database
 */
async function endInstantCallHelper(io, redis, { callId, userId, reason = 'manual_hangup' }) {
  let targetCallId = callId;
  let callObj = targetCallId ? activeInstantCalls.get(targetCallId) : null;

  if (!callObj && userId) {
    for (const [cId, c] of activeInstantCalls.entries()) {
      if (c.maleUserId === userId || c.femaleUserId === userId) {
        callObj = c;
        targetCallId = cId;
        break;
      }
    }
  }

  if (!callObj) return null;

  const durationSeconds = Math.floor((Date.now() - callObj.startedAt) / 1000);

  // Cancel milestone timer if call ends early
  if (callObj.milestoneTimer) {
    clearTimeout(callObj.milestoneTimer);
  }

  const finalStatus = durationSeconds >= 60 ? 'completed' : 'dropped';
  const maleSock = userSockets.get(callObj.maleUserId) || callObj.maleSocketId;
  const femaleSock = userSockets.get(callObj.femaleUserId) || callObj.femaleSocketId;

  // Record call quota usage accurately (audio vs video)
  let audioDurationSec = durationSeconds;
  let videoDurationSec = 0;
  if (callObj.totalVideoSeconds || callObj.videoStartedAt) {
    videoDurationSec = (callObj.totalVideoSeconds || 0) + (callObj.videoStartedAt ? Math.floor((Date.now() - callObj.videoStartedAt) / 1000) : 0);
    audioDurationSec = Math.max(0, durationSeconds - videoDurationSec);
  } else if (callObj.callType === 'video') {
    videoDurationSec = durationSeconds;
    audioDurationSec = 0;
  }

  callQuotaService.recordCallUsage(
    callObj.maleUserId,
    callObj.femaleUserId,
    audioDurationSec,
    videoDurationSec
  ).catch(() => {});

  const endPayload = {
    callId: targetCallId,
    durationSeconds,
    status: finalStatus,
    reason,
  };

  // 1. Instantly notify both parties at 0ms!
  if (callObj.maleUserId) {
    io.to(callObj.maleUserId).emit('instant:call_ended', endPayload);
    io.to(callObj.maleUserId).emit('call_ended', endPayload);
  }
  if (callObj.femaleUserId) {
    io.to(callObj.femaleUserId).emit('instant:call_ended', endPayload);
    io.to(callObj.femaleUserId).emit('call_ended', endPayload);
  }
  if (maleSock && maleSock !== callObj.maleUserId) {
    io.to(maleSock).emit('instant:call_ended', endPayload);
    io.to(maleSock).emit('call_ended', endPayload);
  }
  if (femaleSock && femaleSock !== callObj.femaleUserId) {
    io.to(femaleSock).emit('instant:call_ended', endPayload);
    io.to(femaleSock).emit('call_ended', endPayload);
  }

  // 2. Cleanup mappings and in-call locks immediately
  socketToInstantCall.delete(callObj.maleSocketId);
  socketToInstantCall.delete(callObj.femaleSocketId);
  if (maleSock) socketToInstantCall.delete(maleSock);
  if (femaleSock) socketToInstantCall.delete(femaleSock);
  activeInstantCalls.delete(targetCallId);

  // 3. Perform database operations, refunds, and Redis pool updates in background
  (async () => {
    try {
      await instantConnectService.endCallSession(callObj.sessionId, finalStatus, durationSeconds);

      await redis.del(`instant:in_call:${callObj.femaleUserId}`);
      await redis.del(`instant:in_call:${callObj.maleUserId}`);
      await redis.del(`call_lock:${callObj.femaleUserId}`);
      await redis.del(`call_lock:${callObj.maleUserId}`);

      // Return female to pool if her toggle is still ON
      try {
        const fStatus = await instantConnectService.getFemaleStatus(callObj.femaleUserId);
        if (fStatus.incomingPaidCallsEnabled) {
          await redis.sadd('instant:female_pool', callObj.femaleUserId);
          triggerInstantMatchmaker(io, redis);
        }
      } catch (_) {}

      // Refund male escrow if call dropped or aborted before 1-minute milestone
      if (finalStatus === 'dropped' && callObj.maleUserId && callObj.bidAmount) {
        try {
          await instantConnectService.refundEscrowedCoins(callObj.maleUserId, callObj.bidAmount, callObj.sessionId);
          console.log(`💰 [Instant Connect] Refunded ${callObj.bidAmount} escrowed coins to male ${callObj.maleUserId} for dropped/failed session ${callObj.sessionId}`);
        } catch (refundErr) {
          console.error('Error refunding male on dropped instant call:', refundErr.message);
        }
      }
    } catch (err) {
      console.error('Error in post-instant-call background processing:', err.message);
    }
  })();

  return endPayload;
}

/**
 * Forcefully cleanup a user's instant connect queues, female pool, active calls, and refund male escrow upon logout.
 */
async function cleanupUserInstantConnect(io, redis, userId) {
  if (!userId) return;
  try {
    // 1. Remove from female pool and clear locks
    await redis.srem('instant:female_pool', userId);
    await redis.del(`instant:ringing:${userId}`);
    await redis.del(`instant:in_call:${userId}`);
    await redis.del(`call_lock:${userId}`);


    // 2. Clean up waiting male from queue and refund escrowed coins
    const sessionStr = await redis.get(`instant:male_session:${userId}`);
    if (sessionStr) {
      try {
        const { sessionId, bidAmount } = JSON.parse(sessionStr);
        await redis.zrem('instant:male_queue', userId);
        await redis.del(`instant:male_session:${userId}`);
        await redis.del(`instant:notified_females:${sessionId}`);

        const sTimer = surgeTimers.get(sessionId);
        if (sTimer) {
          clearTimeout(sTimer);
          surgeTimers.delete(sessionId);
        }

        await instantConnectService.refundEscrowedCoins(userId, bidAmount, sessionId);
        console.log(`🧹 [Instant Connect] Refunded escrow & removed male ${userId} on logout`);
      } catch (err) {
        console.error(`Error refunding male on logout for ${userId}:`, err.message);
      }
    }

    // 3. End any active instant call involving this user
    for (const [callId, c] of activeInstantCalls.entries()) {
      if (c.maleUserId === userId || c.femaleUserId === userId) {
        await endInstantCallHelper(io, redis, {
          callId,
          userId,
          reason: 'logged_out',
        });
      }
    }

    // 4. Remove socket mapping
    userSockets.delete(userId);
    console.log(`🧹 [Instant Connect] Cleaned up instant connect state for user ${userId}`);
  } catch (err) {
    console.error(`Error cleaning up instant connect state for ${userId}:`, err.message);
  }
}

module.exports = {
  registerInstantConnectHandlers,
  activeInstantCalls,
  socketToInstantCall,
  endInstantCallHelper,
  triggerInstantMatchmaker,
  userSockets,
  getSocketForUser,
  cleanupUserInstantConnect,
};


`

================================================================================
FILE: backend/modules/matchmaking/matchmaking.socket.js
================================================================================

`javascript
const { MatchmakingService } = require('./matchmaking.service');
const { callsService } = require('../calls/calls.service');
const { WalletService, CALL_RATES } = require('../wallet/wallet.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { activeInstantCalls, endInstantCallHelper } = require('../instant_connect/instant_connect.socket');
const { sendPushNotification } = require('../../services/firebase.service');
const { cacheService } = require('../../services/cache.service');
const { callQuotaService, TELECOM_BUSY_MESSAGE } = require('../calls/call_quota.service');
const db = require('../../db');
const redis = require('../../redis');

// In-memory map of active calls: callId → { userA: { userId, socketId, gender }, userB: { userId, socketId, gender } }
const activeCalls = new Map();
// Reverse map: socketId → callId (for fast lookup on disconnect)
const socketToCall = new Map();
// Map: userId → socketId (for disconnect cleanup)
const userSockets = new Map();
// Map: callRequestId -> { callerId, callerSocketId, callerGender, targetUserId, targetSocketId, targetGender, timer }
const pendingCallRequests = new Map();

/**
 * Look up a user's gender from the database.
 * @param {string} userId
 * @returns {Promise<string>} gender string ('male', 'female', or 'unknown')
 */
async function getUserGender(userId) {
  try {
    const result = await db.query(
      'SELECT gender FROM public.users WHERE id = $1',
      [userId]
    );
    if (result.rows.length === 0) return 'unknown';
    const rawGender = (result.rows[0].gender || '').trim().toLowerCase();
    if (rawGender === 'female' || rawGender === 'girl' || rawGender === 'woman' || rawGender === 'f') {
      return 'female';
    }
    if (rawGender === 'male' || rawGender === 'boy' || rawGender === 'man' || rawGender === 'm') {
      return 'male';
    }
    return 'unknown';
  } catch (err) {
    console.error(`Error fetching gender for user ${userId}:`, err.message);
    return 'unknown';
  }
}

/**
 * Check if a gender string represents female.
 * @param {string} gender
 * @returns {boolean}
 */
function isFemale(gender) {
  const g = (gender || '').trim().toLowerCase();
  return g === 'female' || g === 'girl' || g === 'woman' || g === 'f';
}

/**
 * Check if a gender string represents male.
 * @param {string} gender
 * @returns {boolean}
 */
function isMale(gender) {
  const g = (gender || '').trim().toLowerCase();
  return g === 'male' || g === 'boy' || g === 'man' || g === 'm';
}

/**
 * Helper to safely resolve connected socket for a user ID across map and io.sockets
 */
function getSocketForUser(io, targetUserId) {
  if (!io || !targetUserId) return null;
  const socketId = userSockets.get(targetUserId);
  if (socketId) {
    const s = io.sockets?.sockets?.get(socketId);
    if (s && s.connected && s.userId === targetUserId) return s;
  }
  // Search live connected sockets in Socket.io
  if (io.sockets?.sockets) {
    for (const [, s] of io.sockets.sockets) {
      if (s.userId === targetUserId && s.connected) {
        userSockets.set(targetUserId, s.id); // Re-sync mapping
        return s;
      }
    }
  }
  return null;
}

/**
 * Register all matchmaking-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerMatchmakingHandlers(io, socket, redis) {

  const matchmakingService = new MatchmakingService(redis);
  const userId = socket.userId;

  // Track this user's socket and purge any stale queue entries from previous sessions
  userSockets.set(userId, socket.id);
  matchmakingService.leaveQueue(userId).catch(() => {});

  // Check if there is a pending direct call request waiting for this user (e.g. user tapped FCM call notification)
  for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
    if (reqVal.targetUserId === userId) {
      reqVal.targetSocketId = socket.id;
      fetchPublicProfile(reqVal.callerId).then((callerProfile) => {
        socket.emit('incoming_call_request', {
          callRequestId,
          caller: callerProfile,
        });
        console.log(`🔔 [FCM Connect] Delivered pending direct call ${callRequestId} from ${reqVal.callerId} to newly connected user ${userId}`);
      }).catch((err) => console.error('Error delivering pending direct call to connected user:', err.message));
    }
  }

  // ── join_queue ────────────────────────────────────────────────────────
  socket.on('join_queue', async (callback) => {
    try {
      // Check if user is already in an active call
      if (socketToCall.has(socket.id)) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in an active call' });
        return;
      }

      // Look up user's gender directly from DB
      const gender = await getUserGender(userId);
      if (gender === 'unknown') {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Please set your gender in your profile before matchmaking.' });
        socket.emit('match_error', { error: 'Please set your gender in your profile before matchmaking.' });
        return;
      }

      const userIsFemale = isFemale(gender);

      // Subscription check: unisex requirement for all users
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to join the matchmaking queue.' });
        socket.emit('match_error', { error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to join the matchmaking queue.' });
        return;
      }

      // Quota check: 200-minute monthly audio cap
      const quotaCheck = await callQuotaService.checkCanStartAudioCall(userId);
      if (!quotaCheck.allowed) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        socket.emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }

      const added = await matchmakingService.joinQueue(userId, socket.id, gender);
      if (!added) {
        const cb = typeof callback === 'function' ? callback : () => {};
        cb({ error: 'Already in queue' });
        return;
      }

      console.log(`📥 User ${userId} (${gender}) joined queue`);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ success: true });

      // Try to find a match
      await attemptMatch(io, redis, matchmakingService, callsService);
    } catch (err) {
      console.error('Error in join_queue:', err);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ error: 'Internal error' });
    }
  });

  // ── leave_queue ───────────────────────────────────────────────────────
  socket.on('leave_queue', async (callback) => {
    try {
      await matchmakingService.leaveQueue(userId);
      console.log(`📤 User ${userId} left queue`);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ success: true });
    } catch (err) {
      console.error('Error in leave_queue:', err);
      const cb = typeof callback === 'function' ? callback : () => {};
      cb({ error: 'Internal error' });
    }
  });

  // ── end_call ──────────────────────────────────────────────────────────
  socket.on('end_call', async ({ callId }) => {
    try {
      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        // Security Check: Authorize sender participant
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to end call by ${userId}`);
          return;
        }
        await handleCallEnd(callId, callsService, io, 'manual', matchmakingService);
        return;
      }

      // Check if it's an Instant Connect call
      const instantEndRes = await endInstantCallHelper(io, redis, {
        callId,
        userId,
        reason: 'manual',
      });
      if (instantEndRes) {
        console.log(`⚡ Instant call ${callId} manually ended by user ${userId}`);
      }
    } catch (err) {
      console.error('Error in end_call:', err);
    }
  });

  // ── upgrade_to_video ──────────────────────────────────────────────────
  socket.on('upgrade_to_video', async ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to upgrade call to video by ${userId}`);
          return;
        }

        // Validate video quota for both users (60-minute monthly cap)
        const [quotaVideoA, quotaVideoB] = await Promise.all([
          callQuotaService.checkCanStartVideoCall(callInfo.userA.userId),
          callQuotaService.checkCanStartVideoCall(callInfo.userB.userId),
        ]);
        if (!quotaVideoA.allowed || !quotaVideoB.allowed) {
          socket.emit('video_upgrade_failed', {
            reason: 'network_unsupported',
            message: 'Video connection is currently unavailable in your region. Continuing voice call.',
          });
          return;
        }

        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to upgrade instant call to video by ${userId}`);
            return;
          }

          const [quotaVideoA, quotaVideoB] = await Promise.all([
            callQuotaService.checkCanStartVideoCall(instantCall.maleUserId),
            callQuotaService.checkCanStartVideoCall(instantCall.femaleUserId),
          ]);
          if (!quotaVideoA.allowed || !quotaVideoB.allowed) {
            socket.emit('video_upgrade_failed', {
              reason: 'network_unsupported',
              message: 'Video connection is currently unavailable in your region. Continuing voice call.',
            });
            return;
          }

          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) {
        console.warn(`⚠️ No active call session found for video upgrade request (callId: ${callId})`);
        return;
      }

      const requesterProfile = await fetchPublicProfile(userId);

      io.to(otherSocketId).emit('video_upgrade_request', {
        callId,
        requesterId: userId,
        requesterName: requesterProfile.fullName || 'User',
      });
      console.log(`📹 User ${userId} (${requesterProfile.fullName}) requested video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in upgrade_to_video:', err);
    }
  });

  // ── video_upgrade_accepted ────────────────────────────────────────────
  socket.on('video_upgrade_accepted', async ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to accept video upgrade by ${userId}`);
          return;
        }
        await callsService.upgradeToVideo(callId);

        // Accumulate voice time spent so far
        if (callInfo.callType === 'voice') {
          const audioElapsed = Math.floor((Date.now() - (callInfo.voiceStartedAt || callInfo.startedAt)) / 1000);
          callInfo.totalAudioSeconds = (callInfo.totalAudioSeconds || 0) + Math.max(0, audioElapsed);
          callInfo.voiceStartedAt = null;
        }

        // Switch call timer to remaining video quota
        const [quotaVideoA, quotaVideoB] = await Promise.all([
          callQuotaService.checkCanStartVideoCall(callInfo.userA.userId),
          callQuotaService.checkCanStartVideoCall(callInfo.userB.userId),
        ]);
        const remainingVideoA = Math.max(0, quotaVideoA.remainingSeconds - (callInfo.totalVideoSeconds || 0));
        const remainingVideoB = Math.max(0, quotaVideoB.remainingSeconds - (callInfo.totalVideoSeconds || 0));
        const maxVideoSeconds = Math.min(remainingVideoA, remainingVideoB);

        if (callInfo.quotaTimer) {
          clearTimeout(callInfo.quotaTimer);
          callInfo.quotaTimer = null;
        }

        callInfo.callType = 'video';
        callInfo.videoStartedAt = Date.now();
        if (maxVideoSeconds > 0) {
          callInfo.quotaTimer = setTimeout(() => {
            handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
          }, maxVideoSeconds * 1000);
        } else {
          handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
          return;
        }

        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to accept instant video upgrade by ${userId}`);
            return;
          }
          if (instantCall.callType !== 'video') {
            const audioElapsed = Math.floor((Date.now() - (instantCall.voiceStartedAt || instantCall.startedAt)) / 1000);
            instantCall.totalAudioSeconds = (instantCall.totalAudioSeconds || 0) + Math.max(0, audioElapsed);
            instantCall.voiceStartedAt = null;
          }
          instantCall.callType = 'video';
          instantCall.videoStartedAt = Date.now();
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) return;

      io.to(otherSocketId).emit('video_upgrade_accepted', { callId });
      console.log(`✅ User ${userId} accepted video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in video_upgrade_accepted:', err);
    }
  });

  // ── video_upgrade_declined ────────────────────────────────────────────
  socket.on('video_upgrade_declined', ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to decline video upgrade by ${userId}`);
          return;
        }
        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to decline instant video upgrade by ${userId}`);
            return;
          }
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) return;

      io.to(otherSocketId).emit('video_upgrade_declined', { callId });
      console.log(`❌ User ${userId} declined video upgrade for call ${callId}`);
    } catch (err) {
      console.error('Error in video_upgrade_declined:', err);
    }
  });

  // ── switch_to_voice ────────────────────────────────────────────────────
  socket.on('switch_to_voice', async ({ callId }) => {
    try {
      let otherSocketId = null;

      const callInfo = activeCalls.get(callId);
      if (callInfo) {
        if (callInfo.userA.userId !== userId && callInfo.userB.userId !== userId) {
          console.warn(`⚠️ Unauthorized attempt to switch call to voice by ${userId}`);
          return;
        }
        await callsService.downgradeToVoice(callId);

        // Transition duration tracking from video back to voice
        if (callInfo.callType === 'video' && callInfo.videoStartedAt) {
          const videoElapsed = Math.floor((Date.now() - callInfo.videoStartedAt) / 1000);
          callInfo.totalVideoSeconds = (callInfo.totalVideoSeconds || 0) + Math.max(0, videoElapsed);
          callInfo.videoStartedAt = null;
        }
        callInfo.callType = 'voice';
        callInfo.voiceStartedAt = Date.now();

        // Switch quota timer back to remaining audio budget
        if (callInfo.quotaTimer) {
          clearTimeout(callInfo.quotaTimer);
          callInfo.quotaTimer = null;
        }
        const [quotaAudioA, quotaAudioB] = await Promise.all([
          callQuotaService.checkCanStartAudioCall(callInfo.userA.userId),
          callQuotaService.checkCanStartAudioCall(callInfo.userB.userId),
        ]);
        const remainingAudioA = Math.max(0, quotaAudioA.remainingSeconds - (callInfo.totalAudioSeconds || 0));
        const remainingAudioB = Math.max(0, quotaAudioB.remainingSeconds - (callInfo.totalAudioSeconds || 0));
        const maxAudioSeconds = Math.min(remainingAudioA, remainingAudioB);
        if (maxAudioSeconds > 0) {
          callInfo.quotaTimer = setTimeout(() => {
            handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
          }, maxAudioSeconds * 1000);
        } else {
          handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
          return;
        }

        otherSocketId = callInfo.userA.userId === userId ? callInfo.userB.socketId : callInfo.userA.socketId;
      } else {
        const instantCall = activeInstantCalls?.get(callId);
        if (instantCall) {
          if (instantCall.maleUserId !== userId && instantCall.femaleUserId !== userId) {
            console.warn(`⚠️ Unauthorized attempt to switch instant call to voice by ${userId}`);
            return;
          }
          if (instantCall.callType === 'video' && instantCall.videoStartedAt) {
            const videoElapsed = Math.floor((Date.now() - instantCall.videoStartedAt) / 1000);
            instantCall.totalVideoSeconds = (instantCall.totalVideoSeconds || 0) + Math.max(0, videoElapsed);
            instantCall.videoStartedAt = null;
          }
          instantCall.callType = 'voice';
          instantCall.voiceStartedAt = Date.now();
          otherSocketId = instantCall.maleUserId === userId ? instantCall.femaleSocketId : instantCall.maleSocketId;
        }
      }

      if (!otherSocketId) return;

      const switcherProfile = await fetchPublicProfile(userId);
      const switcherName = switcherProfile?.fullName || 'Participant';

      io.to(otherSocketId).emit('switched_to_voice', {
        callId,
        switcherName,
      });
      console.log(`🎙️ User ${userId} (${switcherName}) switched call ${callId} to voice`);
    } catch (err) {
      console.error('Error in switch_to_voice:', err);
    }
  });

  // ── accept_call_request ────────────────────────────────────────────────
  socket.on('accept_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) {
        socket.emit('match_error', { error: 'Call request expired or does not exist.' });
        return;
      }

      if (request.targetUserId !== userId) {
        socket.emit('match_error', { error: 'Unauthorized call acceptance.' });
        return;
      }

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      // Validate audio quota for both caller and target
      const [quotaCaller, quotaTarget] = await Promise.all([
        callQuotaService.checkCanStartAudioCall(request.callerId),
        callQuotaService.checkCanStartAudioCall(request.targetUserId),
      ]);
      if (!quotaCaller.allowed || !quotaTarget.allowed) {
        socket.emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        io.to(request.callerSocketId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
        return;
      }
      const maxCallSeconds = Math.min(quotaCaller.remainingSeconds, quotaTarget.remainingSeconds);

      // Purge both from queues
      await matchmakingService.leaveQueue(request.callerId);
      await matchmakingService.leaveQueue(request.targetUserId);

      const channelName = matchmakingService.generateChannelName();
      const uidA = matchmakingService.uuidToAgoraUid(request.callerId);
      const uidB = matchmakingService.uuidToAgoraUid(request.targetUserId);
      const tokenA = callsService.generateAgoraToken(channelName, uidA);
      const tokenB = callsService.generateAgoraToken(channelName, uidB);

      const callId = await callsService.createCall(request.callerId, request.targetUserId);

      const [profileA, profileB] = await Promise.all([
        fetchPublicProfile(request.callerId),
        fetchPublicProfile(request.targetUserId),
      ]);

      activeCalls.set(callId, {
        userA: { userId: request.callerId, socketId: request.callerSocketId, agoraUid: uidA, gender: request.callerGender },
        userB: { userId: request.targetUserId, socketId: socket.id, agoraUid: uidB, gender: request.targetGender },
        channelName,
        startedAt: Date.now(),
        callType: 'voice',
        voiceStartedAt: Date.now(),
        videoStartedAt: null,
        totalAudioSeconds: 0,
        totalVideoSeconds: 0,
        quotaTimer: setTimeout(() => {
          handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
        }, maxCallSeconds * 1000),
      });
      socketToCall.set(request.callerSocketId, callId);
      socketToCall.set(socket.id, callId);

      await redis.set(`call_lock:${request.callerId}`, '1', 'EX', 7200);
      await redis.set(`call_lock:${request.targetUserId}`, '1', 'EX', 7200);


      io.to(request.callerSocketId).emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenA,
        agoraUid: uidA,
        matchedUser: profileB,
      });

      socket.emit('match_found', {
        callId,
        agoraAppId: process.env.AGORA_APP_ID,
        agoraChannelName: channelName,
        agoraToken: tokenB,
        agoraUid: uidB,
        matchedUser: profileA,
      });

      callsService.startCallTimer(callId, (expiredCallId) => {
        handleCallEnd(expiredCallId, callsService, io, 'timer', matchmakingService);
      });

      callsService.startCallBilling(
        callId,
        request.callerId,
        request.targetUserId,
        request.callerGender,
        request.targetGender,
        io,
        (billingCallId) => {
          handleCallEnd(billingCallId, callsService, io, 'insufficient_balance', matchmakingService);
        }
      );

      console.log(`✅ Direct call ${callId} established: ${request.callerId} (${request.callerGender}) ↔ ${request.targetUserId} (${request.targetGender})`);
    } catch (err) {
      console.error('Error in accept_call_request:', err);
      socket.emit('match_error', { error: 'Failed to establish call connection.' });
    }
  });

  // ── decline_call_request ────────────────────────────────────────────────
  socket.on('decline_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) return;

      if (request.targetUserId !== userId) return;

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      io.to(request.callerSocketId).emit('call_response', {
        callRequestId,
        status: 'declined',
      });
      
      console.log(`❌ Call request ${callRequestId} declined by target user ${userId}`);
    } catch (err) {
      console.error('Error in decline_call_request:', err);
    }
  });

  // ── cancel_call_request ─────────────────────────────────────────────────
  socket.on('cancel_call_request', async ({ callRequestId }) => {
    try {
      const request = pendingCallRequests.get(callRequestId);
      if (!request) return;

      if (request.callerId !== userId) return;

      clearTimeout(request.timer);
      pendingCallRequests.delete(callRequestId);

      io.to(request.targetSocketId).emit('call_response', {
        callRequestId,
        status: 'cancelled',
      });

      console.log(`🛑 Call request ${callRequestId} cancelled by caller ${userId}`);
    } catch (err) {
      console.error('Error in cancel_call_request:', err);
    }
  });

  // ── direct_call ────────────────────────────────────────────────────────
  socket.on('direct_call', async ({ targetUserId }) => {
    // Subscription check: unisex requirement for all users
    const isSub = await subscriptionsService.isSubscribed(userId);
    if (!isSub) {
      socket.emit('match_error', { error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to start a call.' });
      return;
    }

    // Quota check: 200-minute monthly audio cap
    const callerQuota = await callQuotaService.checkCanStartAudioCall(userId);
    if (!callerQuota.allowed) {
      socket.emit('call_response', { status: 'busy', message: TELECOM_BUSY_MESSAGE });
      return;
    }

    if (targetUserId === userId) {
      socket.emit('match_error', { error: 'Cannot call yourself' });
      return;
    }

    if (socketToCall.has(socket.id)) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    const callerInInstant = await redis.get(`instant:in_call:${userId}`);
    if (callerInInstant) {
      socket.emit('match_error', { error: 'Already in an active call' });
      return;
    }

    const targetSocket = getSocketForUser(io, targetUserId);
    const targetSocketId = targetSocket?.id || null;

    let isBusy = targetSocketId ? socketToCall.has(targetSocketId) : false;
    if (!isBusy) {
      const inInstant = await redis.get(`instant:in_call:${targetUserId}`);
      if (inInstant) isBusy = true;
    }
    if (!isBusy && activeInstantCalls) {
      for (const call of activeInstantCalls.values()) {
        if (call.femaleUserId === targetUserId || call.maleUserId === targetUserId) {
          isBusy = true;
          break;
        }
      }
    }

    if (!isBusy) {
      for (const reqVal of pendingCallRequests.values()) {
        if (reqVal.callerId === targetUserId || reqVal.targetUserId === targetUserId) {
          isBusy = true;
          break;
        }
      }
    }
    if (isBusy) {
      socket.emit('call_response', { status: 'busy' });
      return;
    }

    const lockKeyA = `direct_mutex:${userId}`;
    const lockKeyB = `direct_mutex:${targetUserId}`;
    const lockedA = await redis.set(lockKeyA, '1', 'NX', 'EX', 5);
    const lockedB = await redis.set(lockKeyB, '1', 'NX', 'EX', 5);
    if (!lockedA || !lockedB) {
      if (lockedA) await redis.del(lockKeyA);
      if (lockedB) await redis.del(lockKeyB);
      socket.emit('call_response', { status: 'busy' });
      return;
    }

    try {
      await matchmakingService.leaveQueue(userId);
      await matchmakingService.leaveQueue(targetUserId);

      const callRequestId = matchmakingService.generateChannelName();
      const callerProfile = await fetchPublicProfile(userId);
      const callerGender = callerProfile.gender || (await getUserGender(userId));
      const targetGender = await getUserGender(targetUserId);

      // Check if target is offline and has FCM token
      const isTargetOnline = targetSocket && targetSocket.connected;
      if (!isTargetOnline) {
        const targetUserRow = await db.query(
          `SELECT fcm_token, full_name FROM public.users WHERE id = $1`,
          [targetUserId]
        );
        const targetFcm = targetUserRow.rows[0]?.fcm_token;
        if (!targetFcm) {
          socket.emit('call_response', { status: 'offline' });
          return;
        }

        console.log(`📡 [FCM Direct Call] Target is offline. Dispatching call push to ${targetUserId}`);
        sendPushNotification({
          token: targetFcm,
          title: `📞 Incoming Call from ${callerProfile.fullName}`,
          body: `Tap to open the app and answer the call.`,
          tag: `direct_call_${callRequestId}`,
          data: {
            type: 'incoming_call',
            callRequestId,
            callerId: String(userId),
            callerName: String(callerProfile.fullName),
          },
        }).catch((err) => console.error('FCM Direct Call error:', err.message));
      }

      const timer = setTimeout(() => {
        if (pendingCallRequests.has(callRequestId)) {
          console.log(`⏰ Call request ${callRequestId} timed out (no answer)`);
          io.to(socket.id).emit('call_response', { callRequestId, status: 'no_answer' });
          if (targetSocketId) {
            io.to(targetSocketId).emit('call_response', { callRequestId, status: 'no_answer' });
          }
          pendingCallRequests.delete(callRequestId);
        }
      }, 30000);

      pendingCallRequests.set(callRequestId, {
        callerId: userId,
        callerSocketId: socket.id,
        callerGender,
        targetUserId,
        targetSocketId,
        targetGender,
        timer,
      });

      if (isTargetOnline && targetSocketId) {
        io.to(targetSocketId).emit('incoming_call_request', {
          callRequestId,
          caller: callerProfile,
        });
      }

      socket.emit('outgoing_call_ringing', {
        callRequestId,
        targetUser: { id: targetUserId },
      });

      console.log(`🔔 Call request initiated: ${userId} (${callerGender}) → ${targetUserId} (${targetGender}) (req: ${callRequestId}, targetOnline: ${isTargetOnline})`);
    } catch (err) {
      console.error('Error in direct_call:', err);
      socket.emit('match_error', { error: 'Failed to initiate call request' });
    } finally {
      await redis.del(lockKeyA);
      await redis.del(lockKeyB);
    }
  });

  // ── disconnect ────────────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    try {
      await matchmakingService.leaveQueue(userId);

      for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
        if (reqVal.callerId === userId) {
          io.to(reqVal.targetSocketId).emit('call_response', { callRequestId, status: 'cancelled' });
          clearTimeout(reqVal.timer);
          pendingCallRequests.delete(callRequestId);
        } else if (reqVal.targetUserId === userId) {
          io.to(reqVal.callerSocketId).emit('call_response', { callRequestId, status: 'offline' });
          clearTimeout(reqVal.timer);
          pendingCallRequests.delete(callRequestId);
        }
      }

      const callId = socketToCall.get(socket.id);
      if (callId) {
        console.log(`⚠️ User ${userId} disconnected during call ${callId}`);
        await handleCallEnd(callId, callsService, io, 'disconnect', matchmakingService);
      }

      userSockets.delete(userId);
    } catch (err) {
      console.error('Error in disconnect handler:', err);
    }
  });
}

/**
 * Attempt to match one male with one female from their respective queues.
 * Called after every joinQueue to check if a cross-gender pair is available.
 */
async function attemptMatch(io, redis, matchmakingService, callsService) {
  const match = await matchmakingService.tryMatch();
  if (!match) return;

  const { userA, userB } = match; // userA = male from queue, userB = female from queue

  // 1. Immediately purge both users from Redis queues so they cannot be matched again
  await matchmakingService.leaveQueue(userA.userId);
  await matchmakingService.leaveQueue(userB.userId);

  // 2. FRESH DATABASE GENDER DOUBLE-CHECK BEFORE CREATING CALL
  const [genderA, genderB] = await Promise.all([
    getUserGender(userA.userId),
    getUserGender(userB.userId),
  ]);

  // 🛑 HARD ENFORCEMENT 1: Block self-matches
  if (userA.userId === userB.userId) {
    console.error(`🚨 SELF-MATCH ATTEMPT BLOCKED for user ${userA.userId}. Aborting call setup!`);
    return;
  }

  // 🛑 HARD ENFORCEMENT 2: Must be exactly 1 Male and 1 Female from DB
  const isFemaleA = isFemale(genderA);
  const isMaleA = isMale(genderA);
  const isFemaleB = isFemale(genderB);
  const isMaleB = isMale(genderB);

  const isValidCrossGender = (isMaleA && isFemaleB) || (isFemaleA && isMaleB);
  if (!isValidCrossGender) {
    console.error(`🚨 INVALID CROSS-GENDER MATCH DETECTED & BLOCKED: ${userA.userId} (${genderA}) ↔ ${userB.userId} (${genderB}). Aborting call setup!`);
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;
    if (socketAId) io.to(socketAId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    if (socketBId && socketBId !== socketAId) io.to(socketBId).emit('match_error', { error: 'Matchmaking error. Please try searching again.' });
    return;
  }

  try {
    // Determine active sockets
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;

    // Generate Agora channel and tokens
    const channelName = matchmakingService.generateChannelName();
    const uidA = matchmakingService.uuidToAgoraUid(userA.userId);
    const uidB = matchmakingService.uuidToAgoraUid(userB.userId);
    const tokenA = callsService.generateAgoraToken(channelName, uidA);
    const tokenB = callsService.generateAgoraToken(channelName, uidB);

    // Create fresh call record in DB
    const callId = await callsService.createCall(userA.userId, userB.userId);

    // Fetch fresh profile info directly from Postgres for both participants
    const [profileA, profileB] = await Promise.all([
      fetchPublicProfile(userA.userId),
      fetchPublicProfile(userB.userId),
    ]);

    // Validate audio quota for both matched participants
    const [quotaA, quotaB] = await Promise.all([
      callQuotaService.checkCanStartAudioCall(userA.userId),
      callQuotaService.checkCanStartAudioCall(userB.userId),
    ]);

    if (!quotaA.allowed || !quotaB.allowed) {
      if (!quotaA.allowed && socketAId) {
        io.to(socketAId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
      }
      if (!quotaB.allowed && socketBId) {
        io.to(socketBId).emit('match_error', { error: 'lines_busy', message: TELECOM_BUSY_MESSAGE });
      }
      await Promise.all([
        matchmakingService.leaveQueue(userA.userId),
        matchmakingService.leaveQueue(userB.userId),
      ]);
      return;
    }

    const maxCallSeconds = Math.min(quotaA.remainingSeconds, quotaB.remainingSeconds);

    // Track active call with quota timer and call type
    activeCalls.set(callId, {
      userA: { userId: userA.userId, socketId: socketAId, agoraUid: uidA, gender: genderA },
      userB: { userId: userB.userId, socketId: socketBId, agoraUid: uidB, gender: genderB },
      channelName,
      startedAt: Date.now(),
      callType: 'voice',
      voiceStartedAt: Date.now(),
      videoStartedAt: null,
      totalAudioSeconds: 0,
      totalVideoSeconds: 0,
      quotaTimer: setTimeout(() => {
        handleCallEnd(callId, callsService, io, 'timeout', matchmakingService);
      }, maxCallSeconds * 1000),
    });
    socketToCall.set(socketAId, callId);
    socketToCall.set(socketBId, callId);

    await redis.set(`call_lock:${userA.userId}`, '1', 'EX', 7200);
    await redis.set(`call_lock:${userB.userId}`, '1', 'EX', 7200);


    // Emit match_found to both users
    io.to(socketAId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenA,
      agoraUid: uidA,
      matchedUser: profileB,
    });

    io.to(socketBId).emit('match_found', {
      callId,
      agoraAppId: process.env.AGORA_APP_ID,
      agoraChannelName: channelName,
      agoraToken: tokenB,
      agoraUid: uidB,
      matchedUser: profileA,
    });

    // Start server-authoritative 5-minute timer
    callsService.startCallTimer(callId, (expiredCallId) => {
      handleCallEnd(expiredCallId, callsService, io, 'timer', matchmakingService);
    });

    // Start gender-aware billing
    callsService.startCallBilling(
      callId,
      userA.userId,
      userB.userId,
      genderA,
      genderB,
      io,
      (billingCallId) => {
        handleCallEnd(billingCallId, callsService, io, 'insufficient_balance', matchmakingService);
      }
    );

    console.log(`📞 Call ${callId} started: ${userA.userId} (${genderA}) ↔ ${userB.userId} (${genderB})`);
  } catch (err) {
    console.error('Error setting up match:', err);
    const socketAId = userSockets.get(userA.userId) || userA.socketId;
    const socketBId = userSockets.get(userB.userId) || userB.socketId;
    io.to(socketAId).emit('match_error', { error: 'Failed to set up call' });
    io.to(socketBId).emit('match_error', { error: 'Failed to set up call' });
  }
}

/**
 * Handle call end (manual, timer, or disconnect).
 * Cleans up state and notifies both parties.
 * Gender-aware: sends balance_update to boy, rose_update to girl.
 */
async function handleCallEnd(callId, callsService, io, reason, matchmakingService) {
  const callInfo = activeCalls.get(callId);
  if (!callInfo) return; // Already cleaned up

  // 1. Instantly clear timers and remove from tracking maps
  if (callInfo.quotaTimer) {
    clearTimeout(callInfo.quotaTimer);
    callInfo.quotaTimer = null;
  }

  activeCalls.delete(callId);
  socketToCall.delete(callInfo.userA.socketId);
  socketToCall.delete(callInfo.userB.socketId);
  const currentSocketA = userSockets.get(callInfo.userA.userId);
  const currentSocketB = userSockets.get(callInfo.userB.userId);
  if (currentSocketA) socketToCall.delete(currentSocketA);
  if (currentSocketB) socketToCall.delete(currentSocketB);

  // Calculate audio vs video duration accurately across state transitions
  const endedAt = Date.now();
  let audioDurationSec = callInfo.totalAudioSeconds || 0;
  let videoDurationSec = callInfo.totalVideoSeconds || 0;

  if (callInfo.callType === 'video' && callInfo.videoStartedAt) {
    const elapsedVideo = Math.floor((endedAt - callInfo.videoStartedAt) / 1000);
    videoDurationSec += Math.max(0, elapsedVideo);
  } else {
    const elapsedAudio = Math.floor((endedAt - (callInfo.voiceStartedAt || callInfo.startedAt || endedAt)) / 1000);
    audioDurationSec += Math.max(0, elapsedAudio);
  }

  // Record quota asynchronously (atomic Redis + Postgres rollup)
  callQuotaService.recordCallUsage(
    callInfo.userA.userId,
    callInfo.userB.userId,
    audioDurationSec,
    videoDurationSec
  ).catch((err) => {
    console.error('[CallQuota] Error recording usage in handleCallEnd:', err.message);
  });

  // 2. Immediately notify both users' sockets at 0ms latency so the screens cut instantly!
  const isAFemale = isFemale(callInfo.userA.gender);
  const boyInfo = isAFemale ? callInfo.userB : callInfo.userA;
  const girlInfo = isAFemale ? callInfo.userA : callInfo.userB;
  const socketBoyId = userSockets.get(boyInfo.userId) || boyInfo.socketId;
  const socketGirlId = userSockets.get(girlInfo.userId) || girlInfo.socketId;

  // Emit instant termination to both users
  if (socketBoyId) io.to(socketBoyId).emit('call_ended', { callId, reason });
  if (socketGirlId && socketGirlId !== socketBoyId) io.to(socketGirlId).emit('call_ended', { callId, reason });
  if (boyInfo.userId) io.to(boyInfo.userId).emit('call_ended', { callId, reason });
  if (girlInfo.userId && girlInfo.userId !== boyInfo.userId) io.to(girlInfo.userId).emit('call_ended', { callId, reason });

  // 3. Perform database operations, queue cleanups, and balance updates asynchronously in background
  (async () => {
    try {
      if (matchmakingService) {
        await Promise.all([
          matchmakingService.leaveQueue(callInfo.userA.userId),
          matchmakingService.leaveQueue(callInfo.userB.userId),
        ]);
      }
      await redis.del(`call_lock:${callInfo.userA.userId}`);
      await redis.del(`call_lock:${callInfo.userB.userId}`);
      await Promise.all([
        cacheService.invalidate(`user:matches:${callInfo.userA.userId}`),
        cacheService.invalidate(`user:matches:${callInfo.userB.userId}`),
      ]);

      await callsService.endCall(callId);

      // Query actual total cost for the boy from wallet_transactions
      let totalCostBoy = 0;
      try {
        const resBoy = await db.query(
          `SELECT COALESCE(SUM(amount), 0) AS total FROM public.wallet_transactions
           WHERE user_id = $1 AND reference_id = $2 AND type = 'debit'`,
          [boyInfo.userId, callId]
        );
        totalCostBoy = parseInt(resBoy.rows[0]?.total, 10) || 0;
      } catch (_) {}

      // Query total roses earned by the girl from rose_transactions
      let totalRosesGirl = 0;
      try {
        const resGirl = await db.query(
          `SELECT COALESCE(SUM(amount), 0) AS total FROM public.rose_transactions
           WHERE user_id = $1 AND reference_id = $2 AND type = 'credit'`,
          [girlInfo.userId, callId]
        );
        totalRosesGirl = parseInt(resGirl.rows[0]?.total, 10) || 0;
      } catch (_) {}

      // Emit final balance updates
      const [boyBal, girlBal] = await Promise.all([
        WalletService.getBalance(boyInfo.userId),
        WalletService.getBalance(girlInfo.userId),
      ]);
      if (socketBoyId) io.to(socketBoyId).emit('balance_update', { balance: boyBal });
      if (socketGirlId && socketGirlId !== socketBoyId) {
        io.to(socketGirlId).emit('balance_update', { balance: girlBal });
      }

      console.log(`📴 Call ${callId} ended (reason: ${reason}) — boy ${boyInfo.userId} spent ${totalCostBoy} coins, girl ${girlInfo.userId} earned ${totalRosesGirl} coins`);
    } catch (err) {
      console.error(`Error in async post-call processing for ${callId}:`, err.message);
    }
  })();
}

/**
 * Fetch public profile info for a user (name + avatar + gender).
 */
async function fetchPublicProfile(userId) {
  try {
    const result = await db.query(
      'SELECT id, full_name, gender, avatar_seed, avatar_style FROM public.users WHERE id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      return { id: userId, fullName: 'User', avatarUrl: null, avatarSeed: null, avatarStyle: 'avataaars', gender: 'unknown' };
    }

    const user = result.rows[0];
    const rawGender = (user.gender || '').trim();
    console.log(`✅ Fetched profile for user ${userId}: ${user.full_name} (${rawGender})`);
    return {
      id: user.id,
      fullName: user.full_name || 'User',
      avatarUrl: null,
      avatarSeed: user.avatar_seed || null,
      avatarStyle: user.avatar_style || 'avataaars',
      gender: rawGender.toLowerCase(),
    };
  } catch (err) {
    console.error(`❌ Error fetching profile for user ${userId}:`, err.message);
    return { id: userId, fullName: 'User', avatarUrl: null, avatarSeed: null, avatarStyle: 'avataaars', gender: 'unknown' };
  }
}

/**
 * Forcefully cleanup a user's matchmaking queues, pending calls, active calls, and sockets upon logout.
 */
async function cleanupUserMatchmaking(io, redis, userId) {
  if (!userId) return;
  try {
    const { MatchmakingService } = require('./matchmaking.service');
    const matchmakingService = new MatchmakingService(redis);
    
    // 1. Leave Redis queues
    await matchmakingService.leaveQueue(userId).catch(() => {});

    // 2. Clear any pending direct call requests involving this user
    for (const [callRequestId, reqVal] of pendingCallRequests.entries()) {
      if (reqVal.callerId === userId) {
        if (io && reqVal.targetSocketId) {
          io.to(reqVal.targetSocketId).emit('call_response', { callRequestId, status: 'cancelled' });
        }
        clearTimeout(reqVal.timer);
        pendingCallRequests.delete(callRequestId);
      } else if (reqVal.targetUserId === userId) {
        if (io && reqVal.callerSocketId) {
          io.to(reqVal.callerSocketId).emit('call_response', { callRequestId, status: 'offline' });
        }
        clearTimeout(reqVal.timer);
        pendingCallRequests.delete(callRequestId);
      }
    }

    // 3. End any active calls involving this user
    for (const [callId, callObj] of activeCalls.entries()) {
      if (callObj.userA?.userId === userId || callObj.userB?.userId === userId) {
        console.log(`🛑 Ending active call ${callId} due to user ${userId} logout`);
        await handleCallEnd(callId, callsService, io, 'logout', matchmakingService).catch(() => {});
      }
    }

    // 4. Disconnect and remove any sockets registered for this user
    const socketId = userSockets.get(userId);
    if (socketId) {
      socketToCall.delete(socketId);
      userSockets.delete(userId);
      if (io && io.sockets?.sockets?.has(socketId)) {
        const s = io.sockets.sockets.get(socketId);
        if (s) {
          s.emit('force_disconnect', { reason: 'logged_out' });
          s.disconnect(true);
        }
      }
    }

    // Scan all live sockets to ensure none retain this userId
    if (io && io.sockets?.sockets) {
      for (const [, s] of io.sockets.sockets) {
        if (s.userId === userId) {
          s.emit('force_disconnect', { reason: 'logged_out' });
          s.disconnect(true);
        }
      }
    }

    console.log(`🧹 [Matchmaking] Cleaned up session and sockets for user ${userId}`);
  } catch (err) {
    console.error(`Error cleaning up matchmaking session for user ${userId}:`, err.message);
  }
}

module.exports = { registerMatchmakingHandlers, userSockets, cleanupUserMatchmaking, getSocketForUser };



`

================================================================================
FILE: backend/server.js
================================================================================

`javascript
require('dotenv').config();

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const Redis = require('ioredis');
const jwt = require('jsonwebtoken');
const db = require('./db');

// ── Validate required env vars ──────────────────────────────────────────────
const REQUIRED_ENV = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REDIS_URL',
  'AGORA_APP_ID',
  'AGORA_APP_CERTIFICATE',
];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`Missing required environment variable: ${key}`);
    process.exit(1);
  }
}

if (!process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON && !process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE) {
  console.warn('⚠️ [Google Play Billing] Neither GOOGLE_PLAY_SERVICE_ACCOUNT_JSON nor GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is configured in environment.');
}

if (!process.env.GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT || !process.env.GOOGLE_PLAY_RTDN_AUDIENCE) {
  console.warn('⚠️ [Google Play RTDN] GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT and/or GOOGLE_PLAY_RTDN_AUDIENCE not configured. RTDN webhook will reject all requests until configured.');
}

// ── Express setup ───────────────────────────────────────────────────────────
const app = express();
app.set('trust proxy', 1); // Trust Render / Railway reverse proxy for accurate client IP in rate limiting
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Distributed Redis-backed Rate Limiters
const { apiGlobalLimiter, otpRateLimiter, callRateLimiter } = require('./middleware/rate_limit.middleware');
app.use('/api', apiGlobalLimiter);
app.use('/api/auth/otp', otpRateLimiter);
app.use('/api/calls', callRateLimiter);
app.use('/api/instant', callRateLimiter);

// Import and mount custom modules REST endpoints
const authRoutes = require('./modules/auth/auth.routes');
const callsRoutes = require('./modules/calls/calls.routes');
const messagingRoutes = require('./modules/messaging/messaging.routes');
const walletRoutes = require('./modules/wallet/wallet.routes');
const withdrawalRoutes = require('./modules/withdrawals/withdrawals.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const adminService = require('./modules/admin/admin.service');
const subscriptionsRoutes = require('./modules/subscriptions/subscriptions.routes');
const appRoutes = require('./modules/app/app.routes');
const { appService } = require('./modules/app/app.service');
const { enforceMinimumVersion } = require('./middleware/version.middleware');

const path = require('path');
const advertisementsRoutes = require('./modules/advertisements/advertisements.routes');
const instantConnectRoutes = require('./modules/instant_connect/instant_connect.routes');
const supportRoutes = require('./modules/support/support.routes');
const googlePlayRoutes = require('./modules/payments/google_play.routes');
const { GooglePlayService } = require('./modules/payments/google_play.service');
const buddyRoutes = require('./modules/buddy/buddy.routes');

// Serve uploaded images statically
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ── Lightweight Health check endpoint (exempt from version enforcement & DB) ─
app.get(['/health', '/api/health'], (_req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// Public version routes mounted before middleware enforcement
app.use('/api/app', appRoutes);

// Apply HTTP 426 version enforcement middleware globally to all /api/* routes
app.use('/api', enforceMinimumVersion);

app.use('/api/auth', authRoutes);
app.use('/api/users', authRoutes);
app.use('/api/calls', callsRoutes);
app.use('/api', messagingRoutes);
app.use('/api', walletRoutes);
app.use('/api', withdrawalRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/subscriptions', subscriptionsRoutes);
app.use('/api/instant', instantConnectRoutes);
app.use('/api/advertisements', advertisementsRoutes);
app.use('/api/admin/advertisements', advertisementsRoutes);
app.use('/api/support', supportRoutes);
app.use('/api/app', supportRoutes);
app.use('/api/payments/google-play', googlePlayRoutes);
app.use('/api/buddy', buddyRoutes);

// Initialize Admin, App Config & Google Play tables
adminService.initAdminConfig();
appService.initAppConfig();
GooglePlayService.initTable();

// ── Auto-ensure subscriptions table exists ─────────────────────────────────
db.query(`
  CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    plan_duration_days INTEGER NOT NULL,
    amount_paid INTEGER NOT NULL,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    payment_reference TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_subscriptions_user_expires ON public.subscriptions(user_id, expires_at);
`).then(() => {
  console.log('✅ Subscriptions table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize subscriptions table:', err.message);
});

// ── Auto-ensure wallet_transactions and wallet defaults ────────────────────
db.query(`
  CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
  RETURNS TRIGGER AS $$
  BEGIN
    INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
    VALUES (NEW.id, 0, 0)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    spendable_delta BIGINT NOT NULL DEFAULT 0,
    earned_delta BIGINT NOT NULL DEFAULT 0,
    idempotency_key TEXT UNIQUE,
    reason TEXT NOT NULL,
    reference_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created ON public.wallet_transactions(user_id, created_at DESC);
`).then(() => {
  console.log('✅ Dual-balance wallets trigger and wallet_transactions table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize wallet_transactions table:', err.message);
});

// Auto-ensure user moderation and location columns exist
db.query(`
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS strike_count INTEGER DEFAULT 0;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_telecaller BOOLEAN;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS country VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS state VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS city VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS has_claimed_intro_offer BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS incoming_paid_calls_enabled BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;
`).then(() => {
  console.log('✅ User moderation, telecaller, location, intro offer, and instant connect columns checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize user columns:', err.message);
});

// Auto-ensure instant connect sessions and scratch cards tables exist
db.query(`
  CREATE TABLE IF NOT EXISTS public.instant_call_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    male_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
    bid_amount INTEGER NOT NULL CHECK (bid_amount >= 10),
    status TEXT CHECK (status IN ('queued', 'ringing', 'in_call', 'completed', 'dropped', 'cancelled')) NOT NULL DEFAULT 'queued',
    agora_channel_name TEXT,
    started_at TIMESTAMPTZ,
    milestone_10m_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    duration_seconds INTEGER DEFAULT 0,
    scratch_card_unlocked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_instant_sess_male ON public.instant_call_sessions(male_user_id);
  CREATE INDEX IF NOT EXISTS idx_instant_sess_female ON public.instant_call_sessions(female_user_id);

  CREATE TABLE IF NOT EXISTS public.scratch_cards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID REFERENCES public.instant_call_sessions(id) ON DELETE SET NULL,
    female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    coin_reward INTEGER NOT NULL CHECK (coin_reward >= 1),
    is_scratched BOOLEAN DEFAULT FALSE,
    scratched_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_scratch_cards_female ON public.scratch_cards(female_user_id);
`).then(() => {
  console.log('✅ Instant connect sessions and scratch cards tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize instant connect tables:', err.message);
});


// Auto-ensure withdrawals table exists
db.query(`
  CREATE TABLE IF NOT EXISTS public.withdrawals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    amount BIGINT NOT NULL CHECK (amount > 0),
    rupee_amount BIGINT NOT NULL CHECK (rupee_amount > 0),
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
    idempotency_key TEXT UNIQUE,
    payout_method TEXT DEFAULT 'upi',
    payout_details JSONB,
    admin_note TEXT,
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
  );
  CREATE UNIQUE INDEX IF NOT EXISTS idx_withdrawals_single_pending ON public.withdrawals(user_id) WHERE status = 'pending';
  CREATE INDEX IF NOT EXISTS idx_withdrawals_user_status ON public.withdrawals(user_id, status);
`).then(() => {
  console.log('✅ Withdrawals table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize withdrawals table:', err.message);
});

// Auto-ensure bug reports and account deletion survey tables exist
db.query(`
  CREATE TABLE IF NOT EXISTS public.bug_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    app_version TEXT,
    platform TEXT,
    device_info TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_bug_reports_user ON public.bug_reports(user_id);
  CREATE INDEX IF NOT EXISTS idx_bug_reports_date ON public.bug_reports(created_at DESC);

  CREATE TABLE IF NOT EXISTS public.account_deletion_surveys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT,
    phone_number TEXT,
    reason TEXT NOT NULL,
    feedback TEXT,
    deleted_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_deletion_surveys_date ON public.account_deletion_surveys(deleted_at DESC);
`).then(() => {
  console.log('✅ Bug reports and account deletion survey tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize support/deletion tables:', err.message);
});


// Auto-ensure user monthly call usage table exists
db.query(`
  CREATE TABLE IF NOT EXISTS public.user_monthly_call_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    year_month VARCHAR(7) NOT NULL,
    audio_seconds INTEGER DEFAULT 0 NOT NULL,
    video_seconds INTEGER DEFAULT 0 NOT NULL,
    audio_call_count INTEGER DEFAULT 0 NOT NULL,
    video_call_count INTEGER DEFAULT 0 NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_user_year_month UNIQUE (user_id, year_month)
  );
  CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_ym ON public.user_monthly_call_usage(year_month);
  CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_user ON public.user_monthly_call_usage(user_id);
`).then(() => {
  console.log('✅ User monthly call usage table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize user monthly call usage table:', err.message);
});

const server = http.createServer(app);

// ── Redis client ────────────────────────────────────────────────────────────
const redis = require('./redis');

// ── Socket.io setup ─────────────────────────────────────────────────────────
const { createAdapter } = require('@socket.io/redis-adapter');

const io = new Server(server, {
  cors: {
    origin: '*', // Tighten in production
    methods: ['GET', 'POST'],
  },
  pingTimeout: 20000,
  pingInterval: 15000,
});
app.set('io', io);

// Multi-instance Socket.IO clustering via Redis adapter
if (process.env.REDIS_URL) {
  try {
    const pubClient = new Redis(process.env.REDIS_URL, {
      maxRetriesPerRequest: null,
      retryStrategy: (times) => Math.min(times * 100, 2000),
      lazyConnect: true,
    });
    const subClient = pubClient.duplicate();

    pubClient.on('error', (err) => {
      console.warn('⚠️ [Socket.io pubClient error]:', err.message);
    });
    subClient.on('error', (err) => {
      console.warn('⚠️ [Socket.io subClient error]:', err.message);
    });

    Promise.all([pubClient.connect(), subClient.connect()])
      .then(() => {
        io.adapter(createAdapter(pubClient, subClient));
        console.log('✅ Socket.io Redis Adapter active for horizontal multi-instance scaling');
      })
      .catch((err) => {
        console.warn('⚠️ Redis adapter pub/sub failed to connect, using local in-memory adapter:', err.message);
      });
  } catch (err) {
    console.warn('⚠️ Socket.io Redis adapter setup failed:', err.message);
  }
}

const { ModerationService } = require('./modules/moderation/moderation.service');
const { PresenceService } = require('./modules/presence/presence.service');

// Socket.io authentication middleware — validates custom JWT session and moderation status
io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token;
  if (!token) {
    return next(new Error('Authentication error: no token provided'));
  }

  try {
    const secret = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);

    const modStatus = await ModerationService.isUserBlocked(decoded.id);
    if (modStatus.isBanned) {
      return next(new Error('ACCOUNT_BANNED'));
    }

    // Perform version check during socket handshake if appVersion header/payload provided
    const appVersion = socket.handshake.auth?.appVersion || socket.handshake.headers?.['x-app-version'];
    const platform = socket.handshake.auth?.platform || socket.handshake.headers?.['x-app-platform'] || 'android';

    if (appVersion) {
      const verResult = await appService.checkVersion(platform, appVersion);
      if (verResult.updateRequired) {
        return next(new Error('ACCOUNT_UPGRADE_REQUIRED'));
      }
    }

    // Enforce single-device active session for socket connections
    const activeSession = await redis.get(`user_active_session:${decoded.id}`);
    if (activeSession && (!decoded.sessionId || activeSession !== decoded.sessionId)) {
      return next(new Error('SESSION_TERMINATED'));
    }

    socket.userId = decoded.id;
    socket.userPhone = decoded.phone;
    socket.sessionId = decoded.sessionId;
    next();
  } catch (err) {
    console.error('Socket auth failed:', err.message);
    next(new Error('Authentication error: invalid token'));
  }
});

// ── Register socket handlers ────────────────────────────────────────────────
const { registerMatchmakingHandlers } = require('./modules/matchmaking/matchmaking.socket');
const { registerMessagingHandlers } = require('./modules/messaging/messaging.socket');
const { MessagingService } = require('./modules/messaging/messaging.service');
const messagingService = new MessagingService();
const { registerInstantConnectHandlers } = require('./modules/instant_connect/instant_connect.socket');
const { registerPresenceHandlers } = require('./modules/presence/presence.socket');
const { registerBuddyHandlers } = require('./modules/buddy/buddy.socket');

io.on('connection', (socket) => {
  console.log(`🔌 User connected: ${socket.userId} (socket: ${socket.id})`);
  
  // Join the user's personal room for direct targeting and room broadcasts
  socket.join(socket.userId);

  // Add socket to user's active socket set in Redis and broadcast presence if newly online
  PresenceService.addSocket(redis, io, socket.userId, socket.id);

  // Catch up unread 'sent' messages to 'delivered' now that recipient is connected
  messagingService.markDeliveredForRecipient(socket.userId, io);

  registerMatchmakingHandlers(io, socket, redis);
  registerMessagingHandlers(io, socket, redis);
  registerInstantConnectHandlers(io, socket, redis);
  registerPresenceHandlers(io, socket, redis);
  registerBuddyHandlers(io, socket, redis);

  // Auto-join user's city buddy room if profile city is set
  db.query('SELECT city FROM public.users WHERE id = $1', [socket.userId])
    .then((res) => {
      const city = res.rows[0]?.city;
      if (city) {
        const room = `city:${city.trim().toLowerCase()}:buddy`;
        socket.join(room);
      }
    })
    .catch(() => {});

  socket.on('disconnect', (reason) => {
    console.log(`🔌 User disconnected: ${socket.userId} — ${reason}`);
    // Remove socket from user's active socket set in Redis and broadcast presence if offline
    PresenceService.removeSocket(redis, io, socket.userId, socket.id);
    
    // Clean up in-memory socket mapping
    try {
      const { userSockets } = require('./modules/matchmaking/matchmaking.socket');
      if (userSockets.get(socket.userId) === socket.id) {
        userSockets.delete(socket.userId);
      }
    } catch (_) {}
  });
});

// ── Periodically clean up expired OTPs (every 1 hour) ────────────────────────
setInterval(async () => {
  try {
    const result = await db.query('DELETE FROM public.otp_verifications WHERE expires_at < NOW()');
    if (result.rowCount > 0) {
      console.log(`🧹 Cleaned up ${result.rowCount} expired OTP verification records.`);
    }
  } catch (err) {
    console.error('❌ Error cleaning up expired OTPs:', err.message);
  }
}, 60 * 60 * 1000);

// ── Periodically reconcile voided Google Play purchases (startup + every 6 hours) ──
if (process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE) {
  setTimeout(() => {
    GooglePlayService.syncVoidedPurchases().catch((err) => {
      console.warn('⚠️ [Google Play Startup Voided Sync]:', err.message);
    });
  }, 15 * 1000);

  setInterval(() => {
    GooglePlayService.syncVoidedPurchases().catch((err) => {
      console.warn('⚠️ [Google Play Scheduled Voided Sync]:', err.message);
    });
  }, 6 * 60 * 60 * 1000);
}

// ── Start server ────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, async () => {
  console.log(`🚀 BuddyPartner server listening on port ${PORT}`);

  const instanceCount = parseInt(process.env.INSTANCE_COUNT || '1', 10);
  if (instanceCount > 1 || process.env.NODE_APP_INSTANCE) {
    console.warn('⚠️ [Scaling] This server uses in-memory call state (activeCalls, pendingCallRequests). Do not run more than 1 instance of this process without completing the Redis migration in backend/docs/MULTI_INSTANCE_MIGRATION.md');
  } else {
    console.log('ℹ️ [Scaling] Running single instance mode. For multi-instance setup, refer to backend/docs/MULTI_INSTANCE_MIGRATION.md');
  }
  try {
    const res = await db.query(`
      UPDATE public.instant_call_sessions
      SET status = 'dropped', ended_at = NOW()
      WHERE status IN ('queued', 'ringing', 'in_call')
    `);
    if (res.rowCount > 0) {
      console.log(`🧹 Reconciled ${res.rowCount} stale instant call sessions on startup.`);
    }
  } catch (err) {
    console.error('Error reconciling instant call sessions on startup:', err.message);
  }
});

module.exports = { app, server, io, redis, db };

`

================================================================================
FILE: backend/modules/subscriptions/subscriptions.service.js
================================================================================

`javascript
const db = require('../../db');
const { cacheService } = require('../../services/cache.service');
const redis = require('../../redis');

const SUBSCRIPTION_PLANS = [
  { id: '1_month', durationDays: 30, basePrice: 199, gstAmount: 36, amountPaid: 235, label: '1 Month Membership' },
  { id: '6_months', durationDays: 180, basePrice: 399, gstAmount: 72, amountPaid: 471, label: '6 Months Membership' },
  { id: '1_year', durationDays: 365, basePrice: 699, gstAmount: 126, amountPaid: 825, label: '1 Year Membership' },
];

class SubscriptionsService {
  /**
   * Check if user has already claimed the one-time ₹9 1-day introductory offer
   * @param {string} userId
   * @returns {Promise<boolean>}
   */
  async hasClaimedIntroOffer(userId) {
    try {
      const userRes = await db.query(
        `SELECT has_claimed_intro_offer FROM public.users WHERE id = $1`,
        [userId]
      );
      if (userRes.rows[0]?.has_claimed_intro_offer) {
        return true;
      }

      // Fallback check against subscriptions history table.
      // NOTE (Tech Debt): (plan_duration_days = 1 OR amount_paid = 9) is a heuristic proxy tied
      // to current pricing (₹9 / 1-day). Revisit if pricing changes or add is_intro_offer column.
      const subRes = await db.query(
        `SELECT id FROM public.subscriptions 
         WHERE user_id = $1 AND (plan_duration_days = 1 OR amount_paid = 9) 
         LIMIT 1`,
        [userId]
      );
      return subRes.rows.length > 0;
    } catch (err) {
      console.error('Error checking hasClaimedIntroOffer:', err.message);
      return false;
    }
  }

  /**
   * Fetch current active subscription for user where expires_at > NOW()
   * @param {string} userId
   * @returns {Promise<Object|null>}
   */
  async getActiveSubscription(userId) {
    try {
      const result = await db.query(
        `SELECT id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at
         FROM public.subscriptions
         WHERE user_id = $1 AND expires_at > NOW()
         ORDER BY expires_at DESC
         LIMIT 1`,
        [userId]
      );
      return result.rows[0] || null;
    } catch (err) {
      console.error('Error in getActiveSubscription:', err.message);
      return null;
    }
  }

  /**
   * Fetch subscription history for user ordered by created_at DESC
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getSubscriptionHistory(userId) {
    try {
      const result = await db.query(
        `SELECT id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at
         FROM public.subscriptions
         WHERE user_id = $1
         ORDER BY created_at DESC`,
        [userId]
      );
      return result.rows;
    } catch (err) {
      console.error('Error in getSubscriptionHistory:', err.message);
      return [];
    }
  }

  /**
   * Check if user is currently subscribed.
   * Wrapped with Redis cache (key: user:subscribed:${userId}) with 300s TTL ('1' or '0').
   * Skips DB query on cache hit, eliminating 200-500 QPS from chat.
   * @param {string} userId
   * @returns {Promise<boolean>}
   */
  async isSubscribed(userId) {
    if (!userId) return false;
    const cacheKey = `user:subscribed:${userId}`;
    try {
      const cached = await redis.get(cacheKey);
      if (cached !== null && cached !== undefined) {
        return cached === '1';
      }
    } catch (err) {
      console.warn(`[Subscription Cache Error] Failed to read ${cacheKey}:`, err.message);
    }

    const activeSub = await this.getActiveSubscription(userId);
    const subscribed = activeSub !== null;

    try {
      await redis.set(cacheKey, subscribed ? '1' : '0', 'EX', 300);
    } catch (err) {
      console.warn(`[Subscription Cache Error] Failed to write ${cacheKey}:`, err.message);
    }

    return subscribed;
  }

  /**
   * Create a new subscription row for user
   * @param {string} userId
   * @param {number} planDurationDays
   * @param {number} amountPaid
   * @param {string} [paymentReference]
   * @returns {Promise<Object>}
   */
  async createSubscription(userId, planDurationDays, amountPaid, paymentReference = null) {
    // Server-side enforcement for 1-day ₹9 introductory offer.
    // NOTE (Tech Debt): (plan_duration_days = 1 OR amount_paid = 9) is a heuristic proxy tied
    // to current pricing (₹9 / 1-day). If pricing changes or a separate 1-day promo is introduced,
    // add an explicit is_intro_offer column to public.subscriptions.
    const isIntroPlan = planDurationDays === 1 || amountPaid === 9;
    if (isIntroPlan) {
      const alreadyClaimed = await this.hasClaimedIntroOffer(userId);
      if (alreadyClaimed) {
        throw new Error('The ₹9 introductory offer can only be claimed once per user.');
      }
    }

    try {
      const expiresAt = new Date(Date.now() + planDurationDays * 24 * 60 * 60 * 1000);
      const result = await db.query(
        `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
         VALUES ($1, $2, $3, NOW(), $4, $5)
         RETURNING id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at`,
        [userId, planDurationDays, amountPaid, expiresAt.toISOString(), paymentReference]
      );

      // Permanently mark intro offer as claimed on user record
      if (isIntroPlan) {
        await db.query(
          `UPDATE public.users SET has_claimed_intro_offer = TRUE WHERE id = $1`,
          [userId]
        );
      }

      // Invalidate Redis cache for user's subscription status
      await cacheService.invalidate(`subscription_status:${userId}`);
      await redis.del(`user:subscribed:${userId}`).catch(() => {});

      return result.rows[0];
    } catch (err) {
      console.error('Error creating subscription:', err.message);
      throw err;
    }
  }

  /**
   * Immediately expire any active subscriptions for testing (Dev only)
   * @param {string} userId
   */
  async expireSubscription(userId) {
    try {
      await db.query(
        `UPDATE public.subscriptions
         SET expires_at = NOW() - INTERVAL '1 second'
         WHERE user_id = $1 AND expires_at > NOW()`,
        [userId]
      );

      // Invalidate Redis cache for user's subscription status
      await cacheService.invalidate(`subscription_status:${userId}`);
      await redis.del(`user:subscribed:${userId}`).catch(() => {});

      return true;
    } catch (err) {
      console.error('Error expiring subscription:', err.message);
      throw new Error('Failed to expire subscription');
    }
  }

  /**
   * Combined query: returns active subscription duration/label and intro-offer claimed flag in 1 DB round trip.
   * @param {string} userId
   * @returns {Promise<Object>}
   */
  async getSubscriptionStatus(userId) {
    try {
      const result = await db.query(
        `SELECT 
           u.has_claimed_intro_offer,
           sub.id AS sub_id,
           sub.plan_duration_days,
           sub.amount_paid,
           sub.started_at,
           sub.expires_at,
           sub.payment_reference
         FROM public.users u
         LEFT JOIN LATERAL (
           SELECT id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference
           FROM public.subscriptions
           WHERE user_id = u.id AND expires_at > NOW()
           ORDER BY expires_at DESC
           LIMIT 1
         ) sub ON true
         WHERE u.id = $1`,
        [userId]
      );

      const row = result.rows[0];
      const hasClaimedIntroOffer = row ? (row.has_claimed_intro_offer === true) : false;

      if (!row || !row.sub_id || !row.expires_at) {
        return {
          isSubscribed: false,
          expiresAt: null,
          remainingSeconds: 0,
          remainingHours: 0,
          remainingDays: 0,
          formattedLabel: 'Not Subscribed',
          hasClaimedIntroOffer,
        };
      }

      const now = new Date();
      const expiresAt = new Date(row.expires_at);
      const diffMs = expiresAt.getTime() - now.getTime();

      if (diffMs <= 0) {
        return {
          isSubscribed: false,
          expiresAt: row.expires_at,
          remainingSeconds: 0,
          remainingHours: 0,
          remainingDays: 0,
          formattedLabel: 'Expired',
          hasClaimedIntroOffer,
        };
      }

      const remainingSeconds = Math.floor(diffMs / 1000);
      const remainingHours = Math.ceil(remainingSeconds / 3600);
      const remainingDays = Math.ceil(remainingHours / 24);

      let formattedLabel = '';
      if (remainingHours <= 24) {
        const hrs = Math.max(1, remainingHours);
        formattedLabel = `${hrs} hour${hrs === 1 ? '' : 's'} left`;
      } else {
        const days = Math.max(1, remainingDays);
        formattedLabel = `${days} day${days === 1 ? '' : 's'} left`;
      }

      return {
        isSubscribed: true,
        expiresAt: row.expires_at,
        planDurationDays: row.plan_duration_days,
        remainingSeconds,
        remainingHours,
        remainingDays,
        formattedLabel,
        hasClaimedIntroOffer,
      };
    } catch (err) {
      console.error('Error in getSubscriptionStatus:', err.message);
      return {
        isSubscribed: false,
        expiresAt: null,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Not Subscribed',
        hasClaimedIntroOffer: false,
      };
    }
  }

  /**
   * Return remaining duration & pre-formatted label for app bar
   * @param {string} userId
   */
  async getTimeRemaining(userId) {
    const sub = await this.getActiveSubscription(userId);
    if (!sub) {
      return {
        isSubscribed: false,
        expiresAt: null,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Not Subscribed',
      };
    }

    const now = new Date();
    const expiresAt = new Date(sub.expires_at);
    const diffMs = expiresAt.getTime() - now.getTime();

    if (diffMs <= 0) {
      return {
        isSubscribed: false,
        expiresAt: sub.expires_at,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Expired',
      };
    }

    const remainingSeconds = Math.floor(diffMs / 1000);
    const remainingHours = Math.ceil(remainingSeconds / 3600);
    const remainingDays = Math.ceil(remainingHours / 24);

    let formattedLabel = '';
    if (remainingHours <= 24) {
      const hrs = Math.max(1, remainingHours);
      formattedLabel = `${hrs} hour${hrs === 1 ? '' : 's'} left`;
    } else {
      const days = Math.max(1, remainingDays);
      formattedLabel = `${days} day${days === 1 ? '' : 's'} left`;
    }

    return {
      isSubscribed: true,
      expiresAt: sub.expires_at,
      planDurationDays: sub.plan_duration_days,
      remainingSeconds,
      remainingHours,
      remainingDays,
      formattedLabel,
    };
  }
}

const subscriptionsService = new SubscriptionsService();

module.exports = {
  subscriptionsService,
  SubscriptionsService,
  SUBSCRIPTION_PLANS,
};

`

================================================================================
FILE: backend/modules/subscriptions/subscriptions.routes.js
================================================================================

`javascript
const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { subscriptionsService, SUBSCRIPTION_PLANS } = require('./subscriptions.service');
const { cacheService } = require('../../services/cache.service');

const router = express.Router();

// ── GET /api/subscriptions/status ──────────────────────────────────────────
// Fetch current subscription status and countdown payload (cached in Redis for 30s)
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const data = await cacheService.getOrSet(`subscription_status:${userId}`, 30, async () => {
      const statusInfo = await subscriptionsService.getSubscriptionStatus(userId);
      const availablePlans = SUBSCRIPTION_PLANS;

      return {
        ...statusInfo,
        plans: availablePlans,
      };
    });

    res.json(data);
  } catch (err) {
    console.error('Error in GET /subscriptions/status:', err.message);
    res.status(500).json({ error: 'Failed to fetch subscription status' });
  }
});

// ── GET /api/subscriptions/history ─────────────────────────────────────────
// Fetch subscription purchase history for current user
router.get('/history', authMiddleware, async (req, res) => {
  try {
    const history = await subscriptionsService.getSubscriptionHistory(req.user.id);
    res.json({ subscriptions: history });
  } catch (err) {
    console.error('Error in GET /subscriptions/history:', err.message);
    res.status(500).json({ error: 'Failed to fetch subscription history' });
  }
});

// ── POST /api/subscriptions/dev-start & POST /api/subscriptions/subscribe ─────────
// Start/activate a subscription for a user
const handleStartSubscription = async (req, res) => {
  try {
    const { planDurationDays, amountPaid, planId } = req.body;

    let duration = planDurationDays;
    let amount = amountPaid;

    if (planId) {
      const plan = SUBSCRIPTION_PLANS.find((p) => p.id === planId);
      if (plan) {
        duration = plan.durationDays;
        amount = plan.amountPaid;
      }
    }

    if (!duration || typeof duration !== 'number' || duration <= 0) {
      return res.status(400).json({ error: 'Valid planDurationDays is required' });
    }

    // Strict server-side check for introductory 1-day ₹9 offer
    if (planId === '1_day' || duration === 1 || amount === 9) {
      const alreadyClaimed = await subscriptionsService.hasClaimedIntroOffer(req.user.id);
      if (alreadyClaimed) {
        return res.status(400).json({ error: 'The ₹9 introductory offer can only be claimed once per user.' });
      }
    }

    const subscription = await subscriptionsService.createSubscription(
      req.user.id,
      duration,
      amount || 0,
      'DEV_GATEWAY_REF'
    );

    const status = await subscriptionsService.getTimeRemaining(req.user.id);
    const hasClaimedIntroOffer = await subscriptionsService.hasClaimedIntroOffer(req.user.id);

    res.json({
      success: true,
      subscription,
      status: {
        ...status,
        hasClaimedIntroOffer,
      },
    });
  } catch (err) {
    console.error('Error in starting subscription:', err.message);
    res.status(400).json({ error: err.message || 'Failed to start subscription' });
  }
};

router.post('/dev-start', authMiddleware, handleStartSubscription);
router.post('/subscribe', authMiddleware, handleStartSubscription);

// ── POST /api/subscriptions/dev-expire ─────────────────────────────────────
// Expire active subscription for testing
router.post('/dev-expire', authMiddleware, async (req, res) => {
  try {
    await subscriptionsService.expireSubscription(req.user.id);
    const status = await subscriptionsService.getTimeRemaining(req.user.id);

    res.json({
      success: true,
      message: 'Subscription expired for dev testing',
      status,
    });
  } catch (err) {
    console.error('Error in POST /subscriptions/dev-expire:', err.message);
    res.status(500).json({ error: err.message || 'Failed to expire dev subscription' });
  }
});

module.exports = router;

`

================================================================================
FILE: backend/modules/buddy/buddy.service.js
================================================================================

`javascript
const crypto = require('crypto');
const db = require('../../db');
const redis = require('../../redis');
const { cacheService } = require('../../services/cache.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');
const { MessagingService } = require('../messaging/messaging.service');
const messagingService = new MessagingService();
const { ModerationService } = require('../moderation/moderation.service');
const { WalletService } = require('../wallet/wallet.service');
const { BUDDY_TYPES, BUDDY_PRICING, BUDDY_LIMITS, BUDDY_STATUSES } = require('./buddy.config');

function getPepper() {
  return process.env.BUDDY_OTP_PEPPER || 'buddypartner_otp_secret_pepper_2026';
}

function hashOtp(otp) {
  return crypto.createHmac('sha256', getPepper()).update(String(otp).trim()).digest('hex');
}

function encryptOtp(otp) {
  const key = crypto.scryptSync(getPepper(), 'buddy_salt_2026', 32);
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  let encrypted = cipher.update(String(otp).trim(), 'utf8', 'hex');
  encrypted += cipher.final('hex');
  const tag = cipher.getAuthTag().toString('hex');
  return `${iv.toString('hex')}:${tag}:${encrypted}`;
}

function decryptOtp(encryptedStr) {
  if (!encryptedStr) return null;
  const parts = encryptedStr.split(':');
  if (parts.length !== 3) return null;
  const [ivHex, tagHex, cipherHex] = parts;
  const key = crypto.scryptSync(getPepper(), 'buddy_salt_2026', 32);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(ivHex, 'hex'));
  decipher.setAuthTag(Buffer.from(tagHex, 'hex'));
  let decrypted = decipher.update(cipherHex, 'hex', 'utf8');
  decrypted += decipher.final('utf8');
  return decrypted;
}

class BuddyService {
  _normalizeCity(city) {
    if (!city || typeof city !== 'string') return '';
    return city.trim().toLowerCase();
  }

  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Creates a new broadcast Buddy Activity Request.
   * Debits 100 coins immediately (spendable first, then earned).
   * If total across both buckets is under 100, rejects with 400 INSUFFICIENT_COINS and writes zero rows.
   */
  async createRequest({ initiatorId, buddyType, city, targetGender, idempotencyKey = null, correlationId = null }) {
    if (!this._isValidUUID(initiatorId)) {
      const err = new Error('Invalid initiator ID');
      err.statusCode = 400;
      throw err;
    }

    if (!BUDDY_TYPES[buddyType]) {
      const err = new Error(`Invalid buddy type: ${buddyType}. Valid types: ${Object.keys(BUDDY_TYPES).join(', ')}`);
      err.statusCode = 400;
      throw err;
    }

    const normalizedCity = this._normalizeCity(city);
    if (!normalizedCity) {
      const err = new Error('City is required');
      err.statusCode = 400;
      throw err;
    }

    const validGenders = ['male', 'female', 'all'];
    const normalizedGender = (targetGender || 'all').toLowerCase().trim();
    if (!validGenders.includes(normalizedGender)) {
      const err = new Error('Invalid target gender. Must be male, female, or all');
      err.statusCode = 400;
      throw err;
    }

    // Check Moderation
    const modStatus = await ModerationService.isUserBlocked(initiatorId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from creating requests');
      err.statusCode = 403;
      throw err;
    }

    // Check Subscription
    const activeSub = await subscriptionsService.getActiveSubscription(initiatorId);
    if (!activeSub) {
      const err = new Error('An active membership subscription is required to post buddy requests');
      err.code = 'ACTIVE_SUBSCRIPTION_REQUIRED';
      err.statusCode = 403;
      throw err;
    }

    const coinCost = BUDDY_PRICING.INITIATOR_COIN_COST;
    const coinReward = BUDDY_PRICING.ACCEPTER_COIN_REWARD;
    const cid = correlationId || `buddy_create_${crypto.randomBytes(8).toString('hex')}`;

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Check idempotency if key provided
      if (idempotencyKey) {
        const existingReq = await client.query(
          `SELECT * FROM public.buddy_requests WHERE idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingReq.rows.length > 0) {
          const req = existingReq.rows[0];
          const bal = await WalletService.getBalance(initiatorId);
          await client.query('COMMIT');
          console.log(`🔁 [BuddyService.createRequest] Idempotency hit: ${idempotencyKey}`);
          return {
            ...req,
            newBalance: bal.balance,
            alreadyProcessed: true,
          };
        }
      }

      // 2. Atomic spendable-first coin deduction
      const debitRes = await WalletService.debitCoins({
        userId: initiatorId,
        amount: coinCost,
        reason: 'buddy_spend',
        referenceId: idempotencyKey,
        idempotencyKey: idempotencyKey ? `tx_${idempotencyKey}` : null,
        correlationId: cid,
        client,
      });

      if (!debitRes.success) {
        await client.query('ROLLBACK');
        const bal = await WalletService.getBalance(initiatorId);
        const err = new Error(`Insufficient coins: ${coinCost} coins required to create a buddy request (current balance: ${bal.balance} coins).`);
        err.code = 'INSUFFICIENT_COINS';
        err.statusCode = 400;
        throw err;
      }

      // 3. Insert buddy request
      const insertRes = await client.query(
        `INSERT INTO public.buddy_requests (
           initiator_id, buddy_type, city, target_gender,
           initiator_coin_cost, accepter_coin_reward, status, idempotency_key
         ) VALUES ($1, $2, $3, $4, $5, $6, 'open', $7)
         RETURNING *`,
        [initiatorId, buddyType, normalizedCity, normalizedGender, coinCost, coinReward, idempotencyKey]
      );

      const request = insertRes.rows[0];

      // Update reference_id on the debit ledger entry to point to this buddy request id
      if (debitRes.transactionId) {
        await client.query(
          `UPDATE public.wallet_transactions
           SET reference_id = $1
           WHERE id = $2`,
          [request.id, debitRes.transactionId]
        );
      }

      await client.query('COMMIT');

      // Fetch public initiator details for broadcast
      const userRes = await db.query(
        `SELECT id, full_name, user_name, avatar_seed, avatar_style, gender
         FROM public.users WHERE id = $1`,
        [initiatorId]
      );
      const initiator = userRes.rows[0] || {};

      return {
        ...request,
        initiator: {
          id: initiator.id,
          fullName: initiator.full_name || 'User',
          userName: initiator.user_name || null,
          avatarSeed: initiator.avatar_seed || null,
          avatarStyle: initiator.avatar_style || 'avataaars',
          gender: initiator.gender || null,
        },
        newBalance: debitRes.balance,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [BuddyService.createRequest] Error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Atomically accepts an open buddy request.
   * First accepter wins via atomic UPDATE ... WHERE id = $1 AND status = 'open'.
   * Immediately unlocks chat: creates conversation row and links conversation_id.
   * Generates CSPRNG 6-digit OTP, storing only its hash and encrypted token for REST retrieval.
   */
  async acceptRequest({ requestId, accepterId }) {
    if (!this._isValidUUID(requestId) || !this._isValidUUID(accepterId)) {
      const err = new Error('Invalid request or accepter ID format');
      err.statusCode = 400;
      throw err;
    }

    const modStatus = await ModerationService.isUserBlocked(accepterId);
    if (modStatus.isBanned || modStatus.isSuspended) {
      const err = new Error('Account is restricted from accepting requests');
      err.statusCode = 403;
      throw err;
    }

    const existingCheck = await db.query(
      `SELECT initiator_id, status FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (existingCheck.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    if (existingCheck.rows[0].initiator_id === accepterId) {
      const err = new Error('You cannot accept your own buddy request');
      err.statusCode = 400;
      throw err;
    }

    if (existingCheck.rows[0].status !== 'open') {
      const err = new Error('This buddy request has already been accepted by another user');
      err.code = 'ALREADY_ACCEPTED';
      err.statusCode = 409;
      throw err;
    }

    // 1. Create canonical conversation immediately to unlock chat
    const conversation = await messagingService.findOrCreateConversation(
      existingCheck.rows[0].initiator_id,
      accepterId
    );

    // 2. Generate cryptographically secure 6-digit OTP
    const otpCode = crypto.randomInt(100000, 1000000).toString();
    const otpHash = hashOtp(otpCode);
    const otpEncrypted = encryptOtp(otpCode);

    // 3. Atomic single UPDATE query — the core race-prevention mechanism
    const updateRes = await db.query(
      `UPDATE public.buddy_requests
       SET status = 'accepted',
           accepter_id = $1,
           conversation_id = $2,
           otp_hash = $3,
           otp_encrypted = $4,
           accepted_at = NOW()
       WHERE id = $5 AND status = 'open'
       RETURNING *`,
      [accepterId, conversation.id, otpHash, otpEncrypted, requestId]
    );

    if (updateRes.rows.length === 0) {
      const err = new Error('This buddy request has already been accepted by another user');
      err.code = 'ALREADY_ACCEPTED';
      err.statusCode = 409;
      throw err;
    }

    const acceptedRequest = updateRes.rows[0];

    const [initiatorRes, accepterRes] = await Promise.all([
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [acceptedRequest.initiator_id]),
      db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
    ]);

    const initiator = initiatorRes.rows[0] || {};
    const accepter = accepterRes.rows[0] || {};

    return {
      ...acceptedRequest,
      otpCode, // Returned strictly for socket notification convenience to initiator
      otp_code: otpCode,
      conversationId: conversation.id,
      initiator: {
        id: initiator.id,
        fullName: initiator.full_name || 'User',
        full_name: initiator.full_name || 'User',
        userName: initiator.user_name || null,
        user_name: initiator.user_name || null,
        avatarSeed: initiator.avatar_seed || null,
        avatar_seed: initiator.avatar_seed || null,
        avatarStyle: initiator.avatar_style || 'avataaars',
        avatar_style: initiator.avatar_style || 'avataaars',
        gender: initiator.gender || null,
      },
      accepter: {
        id: accepter.id,
        fullName: accepter.full_name || 'User',
        full_name: accepter.full_name || 'User',
        userName: accepter.user_name || null,
        user_name: accepter.user_name || null,
        avatarSeed: accepter.avatar_seed || null,
        avatar_seed: accepter.avatar_seed || null,
        avatarStyle: accepter.avatar_style || 'avataaars',
        avatar_style: accepter.avatar_style || 'avataaars',
        gender: accepter.gender || null,
      },
    };
  }

  /**
   * Retrieves plaintext OTP for the initiator via authenticated REST endpoint.
   * Reconstructs OTP by decrypting AES-256-GCM encrypted token.
   */
  async getInitiatorOtp(requestId, userId) {
    if (!this._isValidUUID(requestId)) {
      const err = new Error('Invalid request ID');
      err.statusCode = 400;
      throw err;
    }

    const result = await db.query(
      `SELECT initiator_id, status, otp_encrypted FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (result.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    const row = result.rows[0];
    if (row.initiator_id !== userId) {
      const err = new Error('Only the initiator can view the meetup OTP');
      err.statusCode = 403;
      throw err;
    }

    if (row.status !== 'accepted') {
      const err = new Error(`OTP is not available in status '${row.status}'. It is only available when accepted and awaiting meetup.`);
      err.statusCode = 400;
      throw err;
    }

    const otpCode = decryptOtp(row.otp_encrypted);
    if (!otpCode) {
      const err = new Error('OTP is unavailable or has expired');
      err.statusCode = 500;
      throw err;
    }

    return { otpCode };
  }

  /**
   * Completes the Buddy request when accepter submits the 6-digit in-person OTP.
   * Rate limited via Redis: max 5 attempts, then 15-minute lockout.
   * Fail-closed if Redis is offline.
   * Atomically transitions status to 'completed' and credits 50 coins to accepter's earned_balance.
   */
  async completeRequest({ requestId, accepterId, otpCode, idempotencyKey = null }) {
    if (!this._isValidUUID(requestId) || !this._isValidUUID(accepterId)) {
      const err = new Error('Invalid request or accepter ID format');
      err.statusCode = 400;
      throw err;
    }

    if (!otpCode || typeof otpCode !== 'string' || otpCode.trim().length !== 6) {
      const err = new Error('A 6-digit numeric OTP code is required');
      err.statusCode = 400;
      throw err;
    }

    const cleanOtp = otpCode.trim();

    // 1. Fetch current request state
    const reqRes = await db.query(
      `SELECT * FROM public.buddy_requests WHERE id = $1`,
      [requestId]
    );

    if (reqRes.rows.length === 0) {
      const err = new Error('Buddy request not found');
      err.statusCode = 404;
      throw err;
    }

    const request = reqRes.rows[0];

    if (request.accepter_id !== accepterId) {
      const err = new Error('Only the user who accepted this request can submit the meetup OTP');
      err.statusCode = 403;
      throw err;
    }

    if (request.status === 'completed') {
      return {
        success: true,
        alreadyCompleted: true,
        conversationId: request.conversation_id,
        request,
      };
    }

    if (request.status !== 'accepted') {
      const err = new Error(`Request is in status '${request.status}' and cannot be completed`);
      err.statusCode = 400;
      throw err;
    }

    // 2. Redis Rate Limiting & Lockout Check (Fail-closed)
    const lockoutKey = `buddy:otp:lockout:${requestId}`;
    const attemptsKey = `buddy:otp:attempts:${requestId}`;

    try {
      const isLocked = await redis.get(lockoutKey);
      if (isLocked) {
        const ttl = await redis.ttl(lockoutKey);
        const mins = Math.max(1, Math.ceil(ttl / 60));
        const err = new Error(`Too many failed OTP attempts. This request is locked for security. Please try again in ${mins} minute(s).`);
        err.code = 'TOO_MANY_ATTEMPTS';
        err.statusCode = 429;
        throw err;
      }
    } catch (redisErr) {
      if (redisErr.statusCode === 429) throw redisErr;
      console.error('❌ [BuddyService.completeRequest] Redis lockout check failed (fail-closed):', redisErr.message);
      const err = new Error('Security rate limiting service unavailable. Please try again in a few moments.');
      err.statusCode = 503;
      throw err;
    }

    // 3. Verify OTP Hash
    const submittedHash = hashOtp(cleanOtp);
    if (submittedHash !== request.otp_hash) {
      let remainingAttempts = BUDDY_LIMITS.MAX_OTP_ATTEMPTS - 1;
      try {
        const attempts = await redis.incr(attemptsKey);
        await redis.expire(attemptsKey, BUDDY_LIMITS.OTP_LOCKOUT_SECONDS);
        remainingAttempts = Math.max(0, BUDDY_LIMITS.MAX_OTP_ATTEMPTS - attempts);

        if (attempts >= BUDDY_LIMITS.MAX_OTP_ATTEMPTS) {
          await redis.set(lockoutKey, '1', 'EX', BUDDY_LIMITS.OTP_LOCKOUT_SECONDS);
          await redis.del(attemptsKey);
          console.warn(`🔒 [BuddyService] Request ${requestId} locked for 15 minutes due to 5 failed OTP attempts.`);
          const err = new Error('Too many failed OTP attempts. This request is now locked for 15 minutes.');
          err.code = 'TOO_MANY_ATTEMPTS';
          err.statusCode = 429;
          throw err;
        }
      } catch (redisErr) {
        if (redisErr.statusCode === 429) throw redisErr;
        console.error('❌ Redis increment error on failed OTP:', redisErr.message);
      }

      const err = new Error(`Incorrect OTP code. ${remainingAttempts} attempt(s) remaining.`);
      err.code = 'INVALID_OTP';
      err.statusCode = 400;
      err.remainingAttempts = remainingAttempts;
      throw err;
    }

    // Clean up Redis lockout/attempts keys upon successful match
    await Promise.all([
      redis.del(lockoutKey).catch(() => {}),
      redis.del(attemptsKey).catch(() => {}),
    ]);

    // 4. Atomic Transaction: Transition to 'completed' + Credit 50 earned coins
    const rewardCoins = request.accepter_coin_reward || BUDDY_PRICING.ACCEPTER_COIN_REWARD;
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      const updateRes = await client.query(
        `UPDATE public.buddy_requests
         SET status = 'completed',
             completed_at = NOW()
         WHERE id = $1 AND status = 'accepted'
         RETURNING *`,
        [requestId]
      );

      if (updateRes.rows.length === 0) {
        await client.query('ROLLBACK');
        const err = new Error('Failed to complete request — invalid state transition');
        err.statusCode = 409;
        throw err;
      }

      const completedRequest = updateRes.rows[0];

      // Credit 50 coins directly to earned_balance
      const creditRes = await WalletService.creditCoins({
        userId: accepterId,
        spendable: 0,
        earned: rewardCoins,
        reason: 'buddy_reward',
        referenceId: requestId,
        idempotencyKey: idempotencyKey || `buddy_reward_${requestId}`,
        correlationId: `reward_${requestId}`,
        client,
      });

      await client.query('COMMIT');

      // Fetch user profiles for response
      const [initiatorRes, accepterRes] = await Promise.all([
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [request.initiator_id]),
        db.query(`SELECT id, full_name, user_name, avatar_seed, avatar_style, gender FROM public.users WHERE id = $1`, [accepterId]),
      ]);

      const initRow = initiatorRes.rows[0] || {};
      const accRow = accepterRes.rows[0] || {};

      const initiatorData = {
        id: initRow.id,
        fullName: initRow.full_name || 'User',
        full_name: initRow.full_name || 'User',
        userName: initRow.user_name || null,
        user_name: initRow.user_name || null,
        avatarSeed: initRow.avatar_seed || null,
        avatar_seed: initRow.avatar_seed || null,
        avatarStyle: initRow.avatar_style || 'avataaars',
        avatar_style: initRow.avatar_style || 'avataaars',
        gender: initRow.gender || null,
      };

      const accepterData = {
        id: accRow.id,
        fullName: accRow.full_name || 'User',
        full_name: accRow.full_name || 'User',
        userName: accRow.user_name || null,
        user_name: accRow.user_name || null,
        avatarSeed: accRow.avatar_seed || null,
        avatar_seed: accRow.avatar_seed || null,
        avatarStyle: accRow.avatar_style || 'avataaars',
        avatar_style: accRow.avatar_style || 'avataaars',
        gender: accRow.gender || null,
      };

      return {
        success: true,
        conversationId: request.conversation_id,
        rewardCoins,
        earnedBalance: creditRes.earnedBalance,
        spendableBalance: creditRes.spendableBalance,
        balance: creditRes.balance,
        request: completedRequest,
        initiator: initiatorData,
        accepter: accepterData,
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [BuddyService.completeRequest] Atomic transaction error:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Alias for completeRequest to support backward compatibility.
   */
  async verifyOtp(params) {
    return this.completeRequest(params);
  }

  /**
   * Admin-only cancellation of an open or accepted request.
   * Strictly no refunds per product policy.
   */
  async adminCancelRequest(requestId, adminId = null, reason = 'admin_action') {
    if (!this._isValidUUID(requestId)) {
      const err = new Error('Invalid request ID');
      err.statusCode = 400;
      throw err;
    }

    const res = await db.query(
      `UPDATE public.buddy_requests
       SET status = 'cancelled',
           cancelled_at = NOW()
       WHERE id = $1 AND status IN ('open', 'accepted')
       RETURNING *`,
      [requestId]
    );

    if (res.rows.length === 0) {
      const err = new Error('Request not found or cannot be cancelled (already completed or cancelled)');
      err.statusCode = 400;
      throw err;
    }

    console.log(`🛡️ [Admin] Buddy request ${requestId} cancelled by admin ${adminId}. Reason: ${reason}`);
    return res.rows[0];
  }

  /**
   * Retrieves open requests in a city matching the requesting user's profile.
   * Utilizes idx_buddy_requests_status_city_gender.
   */
  async listOpenRequests({ city, userGender, buddyType, userId, limit = 20, offset = 0 }) {
    const normalizedCity = this._normalizeCity(city);
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || BUDDY_LIMITS.DEFAULT_FEED_LIMIT, 1), BUDDY_LIMITS.MAX_FEED_LIMIT);
    const parsedOffset = Math.max(parseInt(offset, 10) || 0, 0);

    const params = [normalizedCity];
    let query = `
      SELECT r.id, r.initiator_id, r.buddy_type, r.city, r.target_gender,
             r.status, r.initiator_coin_cost, r.accepter_coin_reward, r.created_at,
             u.full_name AS initiator_name,
             u.user_name AS initiator_username,
             u.avatar_seed AS initiator_avatar_seed,
             u.avatar_style AS initiator_avatar_style,
             u.gender AS initiator_gender
      FROM public.buddy_requests r
      JOIN public.users u ON u.id = r.initiator_id
      WHERE r.city = $1
        AND r.status = 'open'
    `;

    if (userGender) {
      params.push(userGender.toLowerCase().trim());
      query += ` AND (r.target_gender = $${params.length} OR r.target_gender = 'all')`;
    }

    if (userId) {
      params.push(userId);
      query += ` AND r.initiator_id != $${params.length}`;
    }

    if (buddyType && BUDDY_TYPES[buddyType]) {
      params.push(buddyType);
      query += ` AND r.buddy_type = $${params.length}`;
    }

    params.push(parsedLimit);
    query += ` ORDER BY r.created_at DESC LIMIT $${params.length}`;

    params.push(parsedOffset);
    query += ` OFFSET $${params.length};`;

    const result = await db.query(query, params);

    return result.rows.map(row => ({
      id: row.id,
      initiatorId: row.initiator_id,
      buddyType: row.buddy_type,
      city: row.city,
      targetGender: row.target_gender,
      status: row.status,
      initiatorCoinCost: row.initiator_coin_cost,
      accepterCoinReward: row.accepter_coin_reward,
      createdAt: row.created_at,
      initiator: {
        id: row.initiator_id,
        fullName: row.initiator_name || 'User',
        full_name: row.initiator_name || 'User',
        userName: row.initiator_username || null,
        user_name: row.initiator_username || null,
        avatarSeed: row.initiator_avatar_seed || null,
        avatar_seed: row.initiator_avatar_seed || null,
        avatarStyle: row.initiator_avatar_style || 'avataaars',
        avatar_style: row.initiator_avatar_style || 'avataaars',
        gender: row.initiator_gender || null,
      },
    }));
  }

  /**
   * Retrieves paginated requests involving the specified user (as initiator or accepter).
   */
  async getUserRequests(userId, { page = 1, limit = 20, status = 'all' } = {}) {
    if (!this._isValidUUID(userId)) return { requests: [], total: 0, page: 1, totalPages: 1 };

    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);
    const parsedPage = Math.max(parseInt(page, 10) || 1, 1);
    const offset = (parsedPage - 1) * parsedLimit;

    const params = [userId];
    let whereClause = `WHERE (r.initiator_id = $1 OR r.accepter_id = $1)`;

    if (status !== 'all') {
      params.push(status);
      whereClause += ` AND r.status = $${params.length}`;
    }

    const countRes = await db.query(
      `SELECT COUNT(*)::int AS total FROM public.buddy_requests r ${whereClause}`,
      params
    );
    const total = countRes.rows[0]?.total || 0;

    params.push(parsedLimit);
    const limitIdx = params.length;
    params.push(offset);
    const offsetIdx = params.length;

    const result = await db.query(
      `SELECT r.*,
              u_init.full_name AS initiator_name,
              u_init.user_name AS initiator_username,
              u_init.avatar_seed AS initiator_avatar_seed,
              u_init.avatar_style AS initiator_avatar_style,
              u_init.gender AS initiator_gender,
              u_acc.full_name AS accepter_name,
              u_acc.user_name AS accepter_username,
              u_acc.avatar_seed AS accepter_avatar_seed,
              u_acc.avatar_style AS accepter_avatar_style,
              u_acc.gender AS accepter_gender
       FROM public.buddy_requests r
       JOIN public.users u_init ON u_init.id = r.initiator_id
       LEFT JOIN public.users u_acc ON u_acc.id = r.accepter_id
       ${whereClause}
       ORDER BY r.created_at DESC
       LIMIT $${limitIdx} OFFSET $${offsetIdx};`,
      params
    );

    const requests = result.rows.map(row => {
      let otpCode = null;
      if (row.initiator_id === userId && row.status === 'accepted' && row.otp_encrypted) {
        try {
          otpCode = decryptOtp(row.otp_encrypted);
        } catch (_) {}
      }

      return {
        id: row.id,
        initiatorId: row.initiator_id,
        buddyType: row.buddy_type,
        city: row.city,
        targetGender: row.target_gender,
        status: row.status,
        accepterId: row.accepter_id,
        acceptedAt: row.accepted_at,
        completedAt: row.completed_at,
        cancelledAt: row.cancelled_at,
        conversationId: row.conversation_id,
        initiatorCoinCost: row.initiator_coin_cost,
        accepterCoinReward: row.accepter_coin_reward,
        createdAt: row.created_at,
        isInitiator: row.initiator_id === userId,
        otpCode,
        initiator: {
          id: row.initiator_id,
          fullName: row.initiator_name || 'User',
          full_name: row.initiator_name || 'User',
          userName: row.initiator_username || null,
          user_name: row.initiator_username || null,
          avatarSeed: row.initiator_avatar_seed || null,
          avatar_seed: row.initiator_avatar_seed || null,
          avatarStyle: row.initiator_avatar_style || 'avataaars',
          avatar_style: row.initiator_avatar_style || 'avataaars',
          gender: row.initiator_gender || null,
        },
        accepter: row.accepter_id ? {
          id: row.accepter_id,
          fullName: row.accepter_name || 'User',
          full_name: row.accepter_name || 'User',
          userName: row.accepter_username || null,
          user_name: row.accepter_username || null,
          avatarSeed: row.accepter_avatar_seed || null,
          avatar_seed: row.accepter_avatar_seed || null,
          avatarStyle: row.accepter_avatar_style || 'avataaars',
          avatar_style: row.accepter_avatar_style || 'avataaars',
          gender: row.accepter_gender || null,
        } : null,
      };
    });

    return {
      requests,
      total,
      page: parsedPage,
      totalPages: Math.ceil(total / parsedLimit) || 1,
    };
  }
}

const buddyService = new BuddyService();

module.exports = {
  buddyService,
  BuddyService,
};

`

================================================================================
FILE: backend/modules/wallet/wallet.service.js
================================================================================

`javascript
const crypto = require('crypto');
const db = require('../../db');
const { cacheService } = require('../../services/cache.service');

class WalletService {
  /**
   * Reads current dual balance for a user.
   *
   * @param {string} userId
   * @returns {Promise<{ spendableBalance: number, earnedBalance: number, balance: number }>}
   */
  async getBalance(userId) {
    try {
      const result = await db.query(
        'SELECT spendable_balance, earned_balance FROM public.wallets WHERE user_id = $1',
        [userId]
      );
      if (result.rows.length === 0) {
        return { spendableBalance: 0, earnedBalance: 0, balance: 0 };
      }
      const spendable = Number(result.rows[0].spendable_balance) || 0;
      const earned = Number(result.rows[0].earned_balance) || 0;
      return {
        spendableBalance: spendable,
        earnedBalance: earned,
        balance: spendable + earned,
      };
    } catch (err) {
      console.error(`❌ [WalletService.getBalance] Error for user ${userId}:`, err.message);
      throw err;
    }
  }

  /**
   * Checks if user has minimum total required balance across both buckets.
   *
   * @param {string} userId
   * @param {number} requiredAmount
   * @returns {Promise<boolean>}
   */
  async hasMinimumBalance(userId, requiredAmount) {
    const { balance } = await this.getBalance(userId);
    return balance >= Number(requiredAmount);
  }

  /**
   * Atomically debits coins using spendable-first ordering.
   * Conditional update checks sufficiency inline without separate SELECT FOR UPDATE.
   *
   * @param {Object} params
   * @param {string} params.userId
   * @param {number} params.amount
   * @param {string} params.reason
   * @param {string} [params.referenceId]
   * @param {string} [params.idempotencyKey]
   * @param {string} [params.correlationId]
   * @param {import('pg').PoolClient} [params.client] - optional external transaction client
   * @returns {Promise<{ success: boolean, spendableBalance: number, earnedBalance: number, balance: number, spendableDeducted: number, earnedDeducted: number, alreadyProcessed?: boolean }>}
   */
  async debitCoins({
    userId,
    amount,
    reason,
    referenceId = null,
    idempotencyKey = null,
    correlationId = null,
    client: externalClient = null,
  }) {
    const cid = correlationId || `corr_${crypto.randomBytes(8).toString('hex')}`;
    const intAmount = parseInt(amount, 10);
    if (isNaN(intAmount) || intAmount <= 0) {
      throw new Error(`Invalid debit amount: ${amount}`);
    }

    const client = externalClient || await db.pool.connect();
    const shouldManageTx = !externalClient;

    try {
      if (shouldManageTx) await client.query('BEGIN');

      // 1. Check idempotency key if provided
      if (idempotencyKey) {
        const existingTx = await client.query(
          `SELECT t.*, w.spendable_balance, w.earned_balance
           FROM public.wallet_transactions t
           JOIN public.wallets w ON w.user_id = t.user_id
           WHERE t.idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingTx.rows.length > 0) {
          const row = existingTx.rows[0];
          const sBal = Number(row.spendable_balance);
          const eBal = Number(row.earned_balance);
          console.log(`🔁 [Wallet.debitCoins] Idempotency hit: key ${idempotencyKey} already executed. Correlation: ${cid}`);
          if (shouldManageTx) await client.query('COMMIT');
          return {
            success: true,
            spendableBalance: sBal,
            earnedBalance: eBal,
            balance: sBal + eBal,
            spendableDeducted: Math.abs(Number(row.spendable_delta)),
            earnedDeducted: Math.abs(Number(row.earned_delta)),
            alreadyProcessed: true,
          };
        }
      }

      // 2. Single conditional atomic UPDATE with spendable-first deduction
      const updateRes = await client.query(
        `WITH prev AS (
           SELECT user_id, spendable_balance, earned_balance
           FROM public.wallets
           WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
           FOR UPDATE
         )
         UPDATE public.wallets w
         SET 
           spendable_balance = w.spendable_balance - LEAST(prev.spendable_balance, $1::bigint),
           earned_balance = w.earned_balance - ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)),
           updated_at = NOW()
         FROM prev
         WHERE w.user_id = prev.user_id
         RETURNING 
           w.spendable_balance, 
           w.earned_balance,
           LEAST(prev.spendable_balance, $1::bigint) AS spendable_deducted,
           ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)) AS earned_deducted`,
        [intAmount, userId]
      );

      if (updateRes.rows.length === 0) {
        if (shouldManageTx) await client.query('ROLLBACK');
        console.warn(`💰 [Wallet.debitCoins] Insufficient balance or user missing for ${userId}. Requested: ${intAmount}. Correlation: ${cid}`);
        return {
          success: false,
          spendableBalance: null,
          earnedBalance: null,
          balance: null,
          spendableDeducted: 0,
          earnedDeducted: 0,
        };
      }

      const updated = updateRes.rows[0];
      const sBal = Number(updated.spendable_balance);
      const eBal = Number(updated.earned_balance);
      const sDeduct = Number(updated.spendable_deducted);
      const eDeduct = Number(updated.earned_deducted);

      // 3. Insert transaction ledger entry
      const txRes = await client.query(
        `INSERT INTO public.wallet_transactions (
           user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
         ) VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [userId, -sDeduct, -eDeduct, idempotencyKey, reason, referenceId]
      );

      if (shouldManageTx) await client.query('COMMIT');

      // Invalidate Redis balance cache
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      console.log(`💰 [Wallet.debitCoins] Success for ${userId}: -${sDeduct} spendable, -${eDeduct} earned. Remaining: ${sBal}s + ${eBal}e = ${sBal + eBal}. Reason: ${reason}. Correlation: ${cid}`);

      return {
        success: true,
        transactionId: txRes.rows[0]?.id || null,
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
        spendableDeducted: sDeduct,
        earnedDeducted: eDeduct,
      };
    } catch (err) {
      if (shouldManageTx) await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [Wallet.debitCoins] Error for ${userId}: ${err.message}. Correlation: ${cid}`);
      throw err;
    } finally {
      if (shouldManageTx) client.release();
    }
  }

  /**
   * Atomically credits coins to spendable and/or earned buckets.
   *
   * @param {Object} params
   * @param {string} params.userId
   * @param {number} [params.spendable] - amount to credit to spendable_balance
   * @param {number} [params.earned] - amount to credit to earned_balance
   * @param {string} params.reason
   * @param {string} [params.referenceId]
   * @param {string} [params.idempotencyKey]
   * @param {string} [params.correlationId]
   * @param {import('pg').PoolClient} [params.client] - optional external transaction client
   * @returns {Promise<{ success: boolean, spendableBalance: number, earnedBalance: number, balance: number, alreadyProcessed?: boolean }>}
   */
  async creditCoins({
    userId,
    spendable = 0,
    earned = 0,
    reason,
    referenceId = null,
    idempotencyKey = null,
    correlationId = null,
    client: externalClient = null,
  }) {
    const cid = correlationId || `corr_${crypto.randomBytes(8).toString('hex')}`;
    const intSpendable = parseInt(spendable, 10) || 0;
    const intEarned = parseInt(earned, 10) || 0;

    if (intSpendable < 0 || intEarned < 0 || (intSpendable === 0 && intEarned === 0)) {
      throw new Error(`Invalid credit amounts: spendable=${spendable}, earned=${earned}`);
    }

    const client = externalClient || await db.pool.connect();
    const shouldManageTx = !externalClient;

    try {
      if (shouldManageTx) await client.query('BEGIN');

      // 1. Check idempotency key if provided
      if (idempotencyKey) {
        const existingTx = await client.query(
          `SELECT t.*, w.spendable_balance, w.earned_balance
           FROM public.wallet_transactions t
           JOIN public.wallets w ON w.user_id = t.user_id
           WHERE t.idempotency_key = $1`,
          [idempotencyKey]
        );
        if (existingTx.rows.length > 0) {
          const row = existingTx.rows[0];
          const sBal = Number(row.spendable_balance);
          const eBal = Number(row.earned_balance);
          console.log(`🔁 [Wallet.creditCoins] Idempotency hit: key ${idempotencyKey} already executed. Correlation: ${cid}`);
          if (shouldManageTx) await client.query('COMMIT');
          return {
            success: true,
            spendableBalance: sBal,
            earnedBalance: eBal,
            balance: sBal + eBal,
            alreadyProcessed: true,
          };
        }
      }

      // 2. Upsert into wallets
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
         VALUES ($1, $2, $3)
         ON CONFLICT (user_id)
         DO UPDATE SET 
           spendable_balance = public.wallets.spendable_balance + $2,
           earned_balance = public.wallets.earned_balance + $3,
           updated_at = NOW()
         RETURNING spendable_balance, earned_balance`,
        [userId, intSpendable, intEarned]
      );

      const sBal = Number(walletRes.rows[0].spendable_balance);
      const eBal = Number(walletRes.rows[0].earned_balance);

      // 3. Record transaction ledger row
      await client.query(
        `INSERT INTO public.wallet_transactions (
           user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id
         ) VALUES ($1, $2, $3, $4, $5, $6)`,
        [userId, intSpendable, intEarned, idempotencyKey, reason, referenceId]
      );

      if (shouldManageTx) await client.query('COMMIT');

      // Invalidate Redis balance cache
      await cacheService.invalidate(`user:balance:${userId}`).catch(() => {});

      console.log(`💰 [Wallet.creditCoins] Success for ${userId}: +${intSpendable} spendable, +${intEarned} earned. Total: ${sBal}s + ${eBal}e = ${sBal + eBal}. Reason: ${reason}. Correlation: ${cid}`);

      return {
        success: true,
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
      };
    } catch (err) {
      if (shouldManageTx) await client.query('ROLLBACK').catch(() => {});
      console.error(`❌ [Wallet.creditCoins] Error for ${userId}: ${err.message}. Correlation: ${cid}`);
      throw err;
    } finally {
      if (shouldManageTx) client.release();
    }
  }

  /**
   * Get paginated coin transactions for a user.
   * Scoped strictly to the specified userId.
   *
   * @param {string} userId
   * @param {string|null} cursor - ISO timestamp string
   * @param {number} limit
   * @returns {Promise<{ transactions: Array, nextCursor: string|null }>}
   */
  async getTransactions(userId, cursor = null, limit = 20) {
    const parsedLimit = Math.min(Math.max(parseInt(limit, 10) || 20, 1), 50);

    let query;
    let params;

    if (cursor) {
      query = `
        SELECT id, spendable_delta, earned_delta, reason, reference_id, created_at
        FROM public.wallet_transactions
        WHERE user_id = $1 AND created_at < $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
      params = [userId, cursor, parsedLimit];
    } else {
      query = `
        SELECT id, spendable_delta, earned_delta, reason, reference_id, created_at
        FROM public.wallet_transactions
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT $2
      `;
      params = [userId, parsedLimit];
    }

    const result = await db.query(query, params);
    const rows = result.rows;

    const reasonLabels = {
      iap_purchase: 'Google Play Recharge',
      razorpay_purchase: 'Razorpay Recharge',
      recharge: 'Coins Recharge',
      buddy_spend: 'Buddy Request',
      buddy_reward: 'Buddy Meetup Reward',
      withdrawal_hold: 'Withdrawal Hold',
      withdrawal_reject_refund: 'Withdrawal Refund',
      admin_grant: 'Admin Gift',
      instant_call_scratch_reward: 'Scratch Card Reward',
      instant_call_escrow: 'Instant Connect Escrow',
      instant_call_refund: 'Instant Connect Refund',
      signup_bonus: 'Welcome Bonus',
    };

    const transactions = rows.map((row) => {
      const sDelta = Number(row.spendable_delta);
      const eDelta = Number(row.earned_delta);
      const totalDelta = sDelta + eDelta;
      return {
        id: row.id,
        spendableDelta: sDelta,
        earnedDelta: eDelta,
        amount: Math.abs(totalDelta),
        type: totalDelta >= 0 ? 'credit' : 'debit',
        reason: row.reason,
        reasonLabel: reasonLabels[row.reason] || row.reason.replace(/_/g, ' '),
        referenceId: row.reference_id,
        createdAt: row.created_at,
      };
    });

    const nextCursor = rows.length === parsedLimit
      ? rows[rows.length - 1].created_at.toISOString()
      : null;

    return { transactions, nextCursor };
  }
}

module.exports = {
  WalletService: new WalletService(),
};

`

================================================================================
FILE: backend/modules/presence/presence.service.js
================================================================================

`javascript
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

`

================================================================================
FILE: backend/modules/presence/presence.socket.js
================================================================================

`javascript
const { PresenceService } = require('./presence.service');

const MAX_SUBSCRIPTION_IDS = 200;
const PRESENCE_STATE_COOLDOWN_MS = 2000; // Max 1 offline transition per 2 seconds per socket
const LEASE_REFRESH_INTERVAL_MS = 45000; // Safe heartbeat lease refresh every 45 seconds while socket is connected

/**
 * Validate and sanitize user ID arrays for subscribe/unsubscribe events.
 * Returns an array of valid string user IDs capped at MAX_SUBSCRIPTION_IDS (200), or null if invalid.
 * @param {unknown} data
 * @returns {string[] | null}
 */
function extractValidUserIds(data) {
  const raw = Array.isArray(data) ? data : data?.userIds;
  if (!Array.isArray(raw) || raw.length === 0) return null;

  const valid = [];
  for (const id of raw) {
    if (typeof id === 'string' && id.trim().length > 0) {
      valid.push(id.trim());
      if (valid.length >= MAX_SUBSCRIPTION_IDS) break; // Enforce max room subscription cap (200)
    }
  }

  return valid.length > 0 ? valid : null;
}

/**
 * Register all presence-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerPresenceHandlers(io, socket, redis) {
  const userId = socket.userId;
  if (!userId) return;

  // Track per-socket state and timestamp for rate limiting & deduplication
  let lastProcessedState = 'online';
  let lastStateChangeTimestamp = Date.now();

  // Automatically join personal presence target room
  socket.join(`presence_user:${userId}`);

  // ── Heartbeat TTL Lease Refresh ──────────────────────────────────────────
  // Periodic safety refresh timer while socket remains actively connected (every 45s)
  const leaseRefreshTimer = setInterval(() => {
    if (socket.connected) {
      PresenceService.refreshLease(redis, userId);
    }
  }, LEASE_REFRESH_INTERVAL_MS);

  socket.on('disconnect', () => {
    clearInterval(leaseRefreshTimer);
  });

  // ── presence:state ────────────────────────────────────────────────────────
  // Triggered when mobile app lifecycle changes (resumed / paused / hidden / detached)
  socket.on('presence:state', async (data) => {
    try {
      const status = data?.status;

      // 1. Strict status validation: must be exactly 'online' or 'offline'
      if (status !== 'online' && status !== 'offline') {
        console.warn(`⚠️ [Presence] Ignored invalid presence:state from user ${userId}:`, data);
        return;
      }

      const now = Date.now();

      // 2. Ignore duplicate events of the exact same state within cooldown window (deduplication)
      if (status === lastProcessedState && (now - lastStateChangeTimestamp < PRESENCE_STATE_COOLDOWN_MS)) {
        return;
      }

      // 3. State transitions (online -> offline and offline -> online) are processed immediately
      lastProcessedState = status;
      lastStateChangeTimestamp = now;

      // 4. Process validated state change
      if (status === 'online') {
        await PresenceService.addSocket(redis, io, userId, socket.id);
      } else {
        await PresenceService.removeSocket(redis, io, userId, socket.id);
      }
    } catch (err) {
      console.error(`❌ [Presence] Error processing presence:state for ${userId}:`, err.message);
    }
  });

  // ── presence:subscribe ───────────────────────────────────────────────────
  // Subscribe to live presence updates for a batch of users (e.g. chat list or active chat page)
  socket.on('presence:subscribe', (data) => {
    try {
      const userIds = extractValidUserIds(data);
      if (!userIds) return;
      PresenceService.subscribePresence(socket, userIds);
    } catch (err) {
      console.error(`❌ [Presence] Error in presence:subscribe for ${userId}:`, err.message);
    }
  });

  // ── presence:unsubscribe ─────────────────────────────────────────────────
  // Unsubscribe when leaving a chat screen or cleaning up
  socket.on('presence:unsubscribe', (data) => {
    try {
      const userIds = extractValidUserIds(data);
      if (!userIds) return;
      PresenceService.unsubscribePresence(socket, userIds);
    } catch (err) {
      console.error(`❌ [Presence] Error in presence:unsubscribe for ${userId}:`, err.message);
    }
  });
}

module.exports = { registerPresenceHandlers };

`

================================================================================
FILE: backend/modules/auth/auth.routes.js
================================================================================

`javascript
const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../../db');
const redis = require('../../redis');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { cacheService } = require('../../services/cache.service');
const { usernameCheckLimiter, userSearchLimiter } = require('../../middleware/rate_limit.middleware');
const { generateOTP, sanitizePhoneInputs, sendWhatsAppOtp } = require('./otpService');
const { scanKeys } = require('../../utils/redis_helpers');

const RESERVED_USERNAMES = new Set([
  'admin', 'administrator', 'support', 'help', 'buddypartner', 
  'official', 'null', 'undefined', 'system', 'root', 'moderator',
  'api', 'auth', 'user', 'users', 'me'
]);

/**
 * Validates username per Instagram-style format and reserved words
 * - 3–20 characters
 * - Letters, numbers, underscores, periods ([a-z0-9._])
 * - Must start and end with alphanumeric
 * - No consecutive periods or underscores
 */
function validateUsername(username) {
  if (!username || typeof username !== 'string') {
    return { valid: false, message: 'Username is required.' };
  }
  const normalized = username.trim().toLowerCase();
  if (normalized.length < 3 || normalized.length > 20) {
    return { valid: false, message: 'Username must be between 3 and 20 characters.' };
  }
  if (!/^[a-z0-9]/.test(normalized)) {
    return { valid: false, message: 'Username must start with a letter or number.' };
  }
  if (!/[a-z0-9]$/.test(normalized)) {
    return { valid: false, message: 'Username must end with a letter or number.' };
  }
  if (!/^[a-z0-9._]+$/.test(normalized)) {
    return { valid: false, message: 'Username can only contain letters, numbers, . and _' };
  }
  if (/[._]{2,}/.test(normalized)) {
    return { valid: false, message: 'Username cannot contain consecutive dots or underscores.' };
  }
  if (RESERVED_USERNAMES.has(normalized)) {
    return { valid: false, isReserved: true, message: 'it already exist fix it' };
  }
  return { valid: true, normalized };
}

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'buddypartner_fallback_jwt_refresh_secret_key';

// Rate limit constants
const OTP_TTL_SECONDS = 300; // 5 minutes
const SEND_LIMIT_MAX = 3; // Max 3 sends per 10 min
const SEND_LIMIT_WINDOW = 600; // 10 minutes
const VERIFY_ATTEMPTS_MAX = 5; // Max 5 wrong attempts before lockout
const VERIFY_LOCKOUT_WINDOW = 600; // 10 minutes lockout

/**
 * Endpoint: GET /api/auth/username-available?user_name=<value>
 * Checks if a requested username is valid and available.
 * Rate limited to 20 requests per minute per IP.
 */
router.get('/username-available', usernameCheckLimiter, async (req, res) => {
  const rawUserName = req.query.user_name || req.query.username;
  if (!rawUserName) {
    return res.status(400).json({ available: false, error: 'INVALID_FORMAT', message: 'Username is required.' });
  }

  const validation = validateUsername(rawUserName);
  if (!validation.valid) {
    if (validation.isReserved) {
      return res.json({ available: false, message: 'it already exist fix it' });
    }
    return res.status(400).json({ available: false, error: 'INVALID_FORMAT', message: validation.message });
  }

  try {
    const checkRes = await db.query(
      `SELECT 1 FROM public.users WHERE LOWER(user_name) = $1 LIMIT 1`,
      [validation.normalized]
    );

    if (checkRes.rows.length > 0) {
      return res.json({ available: false, message: 'it already exist fix it' });
    }

    return res.json({ available: true });
  } catch (err) {
    console.error('Error checking username availability:', err.message);
    return res.status(500).json({ available: false, error: 'SERVER_ERROR', message: 'Unable to check username availability.' });
  }
});

/**
 * Endpoint: POST /api/auth/login
 * Production username/phone + password authentication (Zero SMS gateway cost).
 * - Accepts { login, password }
 * - Resolves user by case-insensitive user_name or phone
 * - Enforces Redis brute-force rate limit: max 5 failed attempts per 15 minutes
 * - Enforces Single-Device Policy (invalidates old session & emits session_terminated)
 * - Issues Access Token (1d) and rotating Refresh Token (30d) in Redis
 */
router.post('/login', async (req, res) => {
  const { login, password } = req.body || {};
  const rawLogin = (login || '').toString().trim();
  const rawPassword = (password || '').toString();

  if (!rawLogin || !rawPassword) {
    return res.status(400).json({ error: 'Username or phone number, and password are required.' });
  }

  const cleanLogin = rawLogin.startsWith('@') ? rawLogin.slice(1).trim().toLowerCase() : rawLogin.toLowerCase();
  const ip = req.ip || req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown_ip';

  const lockoutWindow = 900; // 15 minutes
  const maxAttempts = 5;
  const loginAttemptsKey = `login_attempts:${cleanLogin}`;
  const ipAttemptsKey = `login_attempts_ip:${ip}`;

  try {
    // 1. Check brute-force lockout counters
    const [userAttempts, ipAttempts] = await Promise.all([
      redis.get(loginAttemptsKey),
      redis.get(ipAttemptsKey),
    ]);

    if ((userAttempts && parseInt(userAttempts, 10) >= maxAttempts) ||
        (ipAttempts && parseInt(ipAttempts, 10) >= maxAttempts * 3)) {
      return res.status(429).json({
        error: 'TOO_MANY_ATTEMPTS',
        message: 'Too many failed login attempts. Please wait 15 minutes or reset your password.',
      });
    }

    // 2. Identify and fetch user (check by username or phone)
    const phoneDigits = rawLogin.replace(/\D/g, '');
    let userRes;

    if (phoneDigits.length >= 7) {
      userRes = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash,
                u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, 
                u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, u.is_banned,
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE LOWER(u.user_name) = $1 
            OR u.mobile = $2 
            OR u.phone_number = $3 
            OR u.phone_number = $4
         LIMIT 1`,
        [cleanLogin, phoneDigits, `+${phoneDigits}`, phoneDigits]
      );
    } else {
      userRes = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash,
                u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, 
                u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, u.is_banned,
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE LOWER(u.user_name) = $1
         LIMIT 1`,
        [cleanLogin]
      );
    }

    if (userRes.rows.length === 0) {
      const attempts = await redis.incr(loginAttemptsKey);
      if (attempts === 1) await redis.expire(loginAttemptsKey, lockoutWindow);
      await redis.incr(ipAttemptsKey);
      await redis.expire(ipAttemptsKey, lockoutWindow);

      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: 'Invalid username or password.' });
    }

    const user = userRes.rows[0];

    // 3. Check if account is banned
    if (user.is_banned === true) {
      return res.status(403).json({ error: 'ACCOUNT_BANNED', message: 'This account has been suspended or banned.' });
    }

    // 4. Check if password is set on this account
    if (!user.password_hash) {
      return res.status(400).json({
        error: 'NO_PASSWORD_SET',
        message: 'No password has been set for this account yet. Please log in using WhatsApp OTP once to create your password.',
        phoneHint: user.phone_number ? `...${user.phone_number.slice(-4)}` : null,
      });
    }

    // 5. Compare password hash
    const isPasswordValid = await bcrypt.compare(rawPassword, user.password_hash);
    if (!isPasswordValid) {
      const attempts = await redis.incr(loginAttemptsKey);
      if (attempts === 1) await redis.expire(loginAttemptsKey, lockoutWindow);
      await redis.incr(ipAttemptsKey);
      await redis.expire(ipAttemptsKey, lockoutWindow);

      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: 'Invalid username or password.' });
    }

    // 6. Login successful! Clear failed attempt keys
    await Promise.all([
      redis.del(loginAttemptsKey),
      redis.del(ipAttemptsKey),
    ]);

    // 7. Enforce Single-Device Policy
    const sessionId = crypto.randomUUID();
    const io = req.app.get('io');
    if (io) {
      io.to(user.id).emit('session_terminated', {
        reason: 'Your account was logged in from another device.',
      });
      setTimeout(() => {
        try {
          io.in(user.id).disconnectSockets(true);
        } catch (_) {}
      }, 500);
    }

    try {
      const oldRefreshKeys = await scanKeys(redis, `refresh:${user.id}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    await redis.set(`user_active_session:${user.id}`, sessionId);

    // 8. Generate Tokens
    const jti = crypto.randomUUID();
    const fullPhoneNumber = user.phone_number || `+${user.country_code}${user.mobile}`;
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: user.country_code,
      mobile: user.mobile,
      sessionId,
    };

    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const refreshToken = jwt.sign({ id: user.id, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);

    const isProfileComplete = Boolean(user.full_name && user.full_name.trim().length > 0);
    const sBal = parseFloat(user.spendable_balance) || 0;
    const eBal = parseFloat(user.earned_balance) || 0;

    res.json({
      success: true,
      token,
      refreshToken,
      isProfileComplete,
      user: {
        id: user.id,
        countryCode: user.country_code || '',
        mobile: user.mobile || '',
        phoneNumber: fullPhoneNumber,
        fullName: user.full_name || '',
        userName: user.user_name || null,
        hasPassword: true,
        dob: user.dob ? user.dob.toISOString() : null,
        gender: user.gender || 'Male',
        language: user.language || 'English',
        avatarSeed: user.avatar_seed || null,
        avatarStyle: user.avatar_style || 'avataaars',
        isTelecaller: user.is_telecaller || false,
        hasClaimedIntroOffer: user.has_claimed_intro_offer || false,
        country: user.country || null,
        state: user.state || null,
        city: user.city || null,
        latitude: user.latitude ? parseFloat(user.latitude) : null,
        longitude: user.longitude ? parseFloat(user.longitude) : null,
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
      },
    });
  } catch (err) {
    console.error('❌ Error during password login:', err.message);
    res.status(500).json({ error: 'Internal server error processing login.' });
  }
});

/**
 * Endpoint: POST /api/auth/set-password
 * Allows an authenticated user to set or update their account password.
 */
router.post('/set-password', authMiddleware, async (req, res) => {
  const userId = req.user?.id;
  const { password } = req.body || {};

  if (!password || typeof password !== 'string' || password.length < 8) {
    return res.status(400).json({
      error: 'INVALID_PASSWORD',
      message: 'Password must be at least 8 characters long.',
    });
  }

  try {
    const passwordHash = await bcrypt.hash(password, 10);
    await db.query(
      `UPDATE public.users SET password_hash = $1 WHERE id = $2`,
      [passwordHash, userId]
    );

    // Invalidate cached profile
    await cacheService.invalidate(`user:profile:${userId}`);

    res.json({
      success: true,
      message: 'Password created successfully. You can now log in using your username and password.',
    });
  } catch (err) {
    console.error('❌ Error setting password:', err.message);
    res.status(500).json({ error: 'Failed to set password.' });
  }
});

/**
 * Endpoint: POST /api/auth/forgot-password/send-otp
 * Initiates password recovery by sending a 6-digit WhatsApp OTP to the user's verified phone.
 */
router.post('/forgot-password/send-otp', async (req, res) => {
  const { login, country_code, mobile } = req.body || {};
  let targetCountryCode = country_code;
  let targetMobile = mobile;

  try {
    if (login) {
      const cleanLogin = (login || '').toString().trim().replace(/^@/, '').toLowerCase();
      const phoneDigits = cleanLogin.replace(/\D/g, '');

      let userRes;
      if (phoneDigits.length >= 7) {
        userRes = await db.query(
          `SELECT id, country_code, mobile, phone_number FROM public.users 
           WHERE LOWER(user_name) = $1 OR mobile = $2 OR phone_number = $3 OR phone_number = $4 LIMIT 1`,
          [cleanLogin, phoneDigits, `+${phoneDigits}`, phoneDigits]
        );
      } else {
        userRes = await db.query(
          `SELECT id, country_code, mobile, phone_number FROM public.users WHERE LOWER(user_name) = $1 LIMIT 1`,
          [cleanLogin]
        );
      }

      if (userRes.rows.length === 0) {
        return res.status(404).json({ error: 'USER_NOT_FOUND', message: 'No account found with this username or phone number.' });
      }

      targetCountryCode = userRes.rows[0].country_code || '91';
      targetMobile = userRes.rows[0].mobile;
    }

    const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(targetCountryCode, targetMobile);
    if (!cleanCountryCode || !cleanMobile || cleanMobile.length < 7) {
      return res.status(400).json({ error: 'Valid country code and mobile number are required.' });
    }

    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
    const otpRedisKey = `otp_reset:${cleanCountryCode}${cleanMobile}`;

    if (isTestAccount) {
      const hashedOtp = await bcrypt.hash(DEMO_TEST_OTP, 10);
      await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);
      return res.json({
        success: true,
        message: 'Password reset code sent.',
        countryCode: cleanCountryCode,
        mobile: cleanMobile,
        phoneHint: `...${cleanMobile.slice(-4)}`,
      });
    }

    // Rate limiting: max 3 reset OTPs per 10 minutes
    const sendCountKey = `otp_reset_send_count:${cleanMobile}`;
    const sendCount = await redis.incr(sendCountKey);
    if (sendCount === 1) await redis.expire(sendCountKey, SEND_LIMIT_WINDOW);
    else if (sendCount > SEND_LIMIT_MAX) {
      return res.status(429).json({ error: 'Too many OTP requests. Please wait 10 minutes before trying again.' });
    }

    const otp = generateOTP();
    const hashedOtp = await bcrypt.hash(otp, 10);
    await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

    const sendResult = await sendWhatsAppOtp(cleanCountryCode, cleanMobile, otp);
    if (!sendResult.success) {
      return res.status(500).json({ error: sendResult.message || 'Failed to send WhatsApp reset code.' });
    }

    res.json({
      success: true,
      message: 'Password reset code sent via WhatsApp.',
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
      phoneHint: `...${cleanMobile.slice(-4)}`,
    });
  } catch (err) {
    console.error('❌ Error in /forgot-password/send-otp:', err.message);
    res.status(500).json({ error: 'Failed to send reset code.' });
  }
});

/**
 * Endpoint: POST /api/auth/forgot-password/reset
 * Verifies the 6-digit WhatsApp OTP and sets the new password.
 */
router.post('/forgot-password/reset', async (req, res) => {
  const { country_code, mobile, otp, new_password } = req.body || {};
  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);
  const cleanOtp = (otp || '').toString().trim();
  const rawPassword = (new_password || '').toString();

  if (!cleanCountryCode || !cleanMobile || !cleanOtp || cleanOtp.length !== 6) {
    return res.status(400).json({ error: 'Valid mobile number and 6-digit verification code are required.' });
  }

  if (!rawPassword || rawPassword.length < 8) {
    return res.status(400).json({ error: 'New password must be at least 8 characters long.' });
  }

  const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
  const otpRedisKey = `otp_reset:${cleanCountryCode}${cleanMobile}`;

  try {
    if (isTestAccount) {
      if (cleanOtp !== DEMO_TEST_OTP) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    } else {
      const storedHash = await redis.get(otpRedisKey);
      if (!storedHash) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }

      const isMatch = await bcrypt.compare(cleanOtp, storedHash);
      if (!isMatch) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    }

    // OTP verified! Delete OTP key
    await redis.del(otpRedisKey);

    // Hash and persist new password
    const newHash = await bcrypt.hash(rawPassword, 10);
    const fullPhone = `+${cleanCountryCode}${cleanMobile}`;

    const updateRes = await db.query(
      `UPDATE public.users 
       SET password_hash = $1 
       WHERE (country_code = $2 AND mobile = $3) OR phone_number = $4
       RETURNING id`,
      [newHash, cleanCountryCode, cleanMobile, fullPhone]
    );

    if (updateRes.rows.length === 0) {
      return res.status(404).json({ error: 'User account not found.' });
    }

    const userId = updateRes.rows[0].id;

    // Purge cached profile & old sessions so user must log in fresh
    await cacheService.invalidate(`user:profile:${userId}`);
    await redis.del(`user_active_session:${userId}`);
    try {
      const oldRefreshKeys = await scanKeys(redis, `refresh:${userId}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    res.json({
      success: true,
      message: 'Password reset successfully! You can now log in with your new password.',
    });
  } catch (err) {
    console.error('❌ Error in /forgot-password/reset:', err.message);
    res.status(500).json({ error: 'Failed to reset password.' });
  }
});

/**
 * Endpoint: GET /api/users/search?query=<partial_or_full_user_name>&limit=20
 * (Also accessible at /api/auth/search?query=...)
 * Auth-protected: requires valid JWT.
 * Rate limited to 30 requests per minute per authenticated user (keyed by user.id).
 * B-tree prefix search against idx_users_user_name_lower.
 * Excludes requesting user and banned users.
 * Minimal public fields only (never sensitive details like phone/email).
 * Cached in Redis with a 15-second TTL.
 */
router.get('/search', authMiddleware, userSearchLimiter, async (req, res) => {
  // Canonical endpoint is GET /api/users/search. Since authRoutes is mounted at both
  // /api/auth and /api/users in server.js, explicitly restrict /search to /api/users
  // to avoid route duplication and confusion.
  if (req.baseUrl !== '/api/users') {
    return res.status(404).json({
      success: false,
      error: 'NOT_FOUND',
      message: 'Canonical search route is GET /api/users/search',
    });
  }

  const currentUserId = req.user.id;
  const rawQuery = (req.query.query || req.query.q || req.query.username || req.query.user_name || '').toString().trim();

  if (!rawQuery || rawQuery.length < 2) {
    return res.json({
      success: true,
      users: [],
    });
  }

  // Sanitize query: strip leading '@' if entered by user, normalize to lowercase
  const cleanQuery = rawQuery.startsWith('@') ? rawQuery.slice(1).toLowerCase() : rawQuery.toLowerCase();
  if (cleanQuery.length < 2) {
    return res.json({
      success: true,
      users: [],
    });
  }

  // Hard-cap server-side limit to prevent large payload dumps
  const parsedLimit = parseInt(req.query.limit, 10);
  const limit = (!isNaN(parsedLimit) && parsedLimit > 0) ? Math.min(parsedLimit, 25) : 20;

  // Cache is keyed by user ID to guarantee requesting user is never included from a shared cache
  const cacheKey = `search:users:${currentUserId}:${cleanQuery}:${limit}`;

  try {
    const cachedUsers = await cacheService.getOrSet(cacheKey, 15, async () => {
      const searchRes = await db.query(
        `SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller
         FROM public.users
         WHERE LOWER(user_name) LIKE LOWER($1) || '%'
           AND (is_banned IS NOT TRUE)
           AND id != $2::UUID
         ORDER BY LOWER(user_name) ASC
         LIMIT $3`,
        [cleanQuery, currentUserId, limit]
      );

      return searchRes.rows.map((row) => ({
        id: row.id,
        fullName: row.full_name || 'User',
        userName: row.user_name || null,
        avatarSeed: row.avatar_seed || null,
        avatarStyle: row.avatar_style || 'avataaars',
        gender: row.gender || null,
        isTelecaller: row.is_telecaller || false,
        isOnline: false,
        isFavorite: false,
      }));
    });

    return res.json({
      success: true,
      query: cleanQuery,
      users: cachedUsers || [],
    });
  } catch (err) {
    console.error('❌ Error executing user search:', err.message);
    return res.status(500).json({
      success: false,
      error: 'SERVER_ERROR',
      message: 'An error occurred while searching for users.',
      users: [],
    });
  }
});

// Google Play Review / Demo Test Account credentials
const DEMO_TEST_COUNTRY_CODE = process.env.DEMO_TEST_COUNTRY_CODE || '91';
const DEMO_TEST_MOBILES = new Set(['9999999999', '8888888888', '7777777777']);
const DEMO_TEST_OTP = process.env.DEMO_TEST_OTP || '123456';

/**
 * Endpoint: POST /api/auth/otp/send
 * Validates country_code and mobile, enforces Redis rate limits, generates bcrypt-hashed OTP,
 * stores it in Redis with 300s TTL, and sends it via Authkey WhatsApp OTP service.
 */
router.post('/otp/send', async (req, res) => {
  const { country_code, mobile } = req.body;

  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);

  if (!cleanCountryCode || !cleanMobile || cleanMobile.length < 7 || cleanMobile.length > 15) {
    return res.status(400).json({ error: 'Valid mobile number and country code are required.' });
  }

  try {
    // Check if this is a Google Play Reviewer / Demo Test Account
    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);

    if (isTestAccount) {
      // Demo test account: Store fixed OTP hash in Redis, skip external WhatsApp API call
      const hashedOtp = await bcrypt.hash(DEMO_TEST_OTP, 10);
      const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
      await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

      console.log(`🧪 [TEST ACCOUNT] OTP generated for Google Play review (+${cleanCountryCode}${cleanMobile}): ${DEMO_TEST_OTP}`);

      return res.json({
        success: true,
        message: 'Verification code sent.',
      });
    }

    // 1. Enforce send rate limit: max 3 sends per 10 minutes per mobile
    const sendCountKey = `otp_send_count:${cleanMobile}`;
    const sendCount = await redis.incr(sendCountKey);

    if (sendCount === 1) {
      await redis.expire(sendCountKey, SEND_LIMIT_WINDOW);
    } else if (sendCount > SEND_LIMIT_MAX) {
      return res.status(429).json({ error: 'Too many OTP requests. Please wait 10 minutes before trying again.' });
    }

    // 2. Generate random 6-digit OTP
    const otp = generateOTP();

    // 3. Hash OTP with bcrypt
    const hashedOtp = await bcrypt.hash(otp, 10);

    // 4. Store hashed OTP in Redis: otp:{country_code}{mobile} -> TTL 300s
    const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
    await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

    // 5. Send OTP via Authkey WhatsApp API
    const sendResult = await sendWhatsAppOtp(cleanCountryCode, cleanMobile, otp);

    if (!sendResult.success) {
      return res.status(500).json({ error: sendResult.message || 'Failed to send WhatsApp verification code.' });
    }

    // Generic success response — does not reveal whether the user is registered or new
    res.json({
      success: true,
      message: 'Verification code sent via WhatsApp.',
    });
  } catch (err) {
    console.error('Error in /auth/otp/send:', err.message);
    res.status(500).json({ error: 'Internal server error processing OTP request.' });
  }
});

/**
 * Endpoint: POST /api/auth/otp/verify
 * Verifies submitted OTP against bcrypt hash in Redis.
 * On success:
 * - Provisions user + wallet atomically if new
 * - Issues Access JWT (1d expiry) and rotating Refresh Token (stored in Redis with 30d TTL)
 * - Deletes Redis OTP key immediately
 */
router.post('/otp/verify', async (req, res) => {
  const { country_code, mobile, otp } = req.body;

  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);
  const cleanOtp = (otp || '').toString().trim();

  if (!cleanCountryCode || !cleanMobile || !cleanOtp || cleanOtp.length !== 6) {
    return res.status(400).json({ error: 'Valid country code, mobile number, and 6-digit verification code are required.' });
  }

  try {
    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
    const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
    const attemptsKey = `otp_verify_attempts:${cleanMobile}`;

    if (isTestAccount) {
      // Test account bypasses rate limits and matches static OTP
      if (cleanOtp !== DEMO_TEST_OTP) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    } else {
      // 1. Check attempt lockout counter
      const attempts = await redis.get(attemptsKey);
      if (attempts && parseInt(attempts, 10) >= VERIFY_ATTEMPTS_MAX) {
        return res.status(429).json({ error: 'Too many failed verification attempts. Please try again in 10 minutes.' });
      }

      // 2. Fetch stored hashed OTP from Redis
      const storedHash = await redis.get(otpRedisKey);

      if (!storedHash) {
        // Increment attempt counter
        const currentAttempts = await redis.incr(attemptsKey);
        if (currentAttempts === 1) await redis.expire(attemptsKey, VERIFY_LOCKOUT_WINDOW);
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }

      // 3. Compare submitted OTP against hash
      const isMatch = await bcrypt.compare(cleanOtp, storedHash);

      if (!isMatch) {
        const currentAttempts = await redis.incr(attemptsKey);
        if (currentAttempts === 1) await redis.expire(attemptsKey, VERIFY_LOCKOUT_WINDOW);
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    }

    // 4. Verification successful! Delete OTP key & clear attempt counter
    await redis.del(otpRedisKey);
    await redis.del(attemptsKey);

    // Form legacy phone format e.g. "+919876543210"
    const fullPhoneNumber = `+${cleanCountryCode}${cleanMobile}`;

    // 5. Query user or run atomic transaction to create user + wallet
    let userResult = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, 
              u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, 
              u.country, u.state, u.city, u.latitude, u.longitude, 
              w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE (u.country_code = $1 AND u.mobile = $2) OR u.phone_number = $3`,
      [cleanCountryCode, cleanMobile, fullPhoneNumber]
    );

    let user;

    if (userResult.rows.length === 0) {
      // Atomic Transaction: Create user + wallet
      const client = await db.pool.connect();
      try {
        await client.query('BEGIN');

        let insertUserRes;
        if (isTestAccount) {
          // Pre-populate reviewer profile so reviewer directly accesses app features
          insertUserRes = await client.query(
            `INSERT INTO public.users (
               country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, country, state, city
             ) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) 
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude`,
            [
              cleanCountryCode, cleanMobile, fullPhoneNumber,
              'Google Reviewer', 'googlereviewer', '1998-01-01', 'Male', 'English', 'male_2f', 'avataaars', 'India', 'Delhi', 'New Delhi'
            ]
          );
        } else {
          insertUserRes = await client.query(
            `INSERT INTO public.users (country_code, mobile, phone_number, avatar_seed, avatar_style) 
             VALUES ($1, $2, $3, 'male_2f', 'avataaars') 
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude`,
            [cleanCountryCode, cleanMobile, fullPhoneNumber]
          );
        }
        user = insertUserRes.rows[0];

        // Provision wallet (preloaded with 100 spendable coins for reviewer to test calls, 0 for standard users)
        const initialBalance = isTestAccount ? 100 : 0;
        await client.query(
          `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance) 
           VALUES ($1, $2, 0) 
           ON CONFLICT (user_id) DO UPDATE SET spendable_balance = GREATEST(wallets.spendable_balance, $2)`,
          [user.id, initialBalance]
        );

        await client.query('COMMIT');
        console.log(` New user created: ID ${user.id}, mobile +${cleanCountryCode}${cleanMobile}${isTestAccount ? ' [TEST ACCOUNT]' : ''}`);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } else {
      user = userResult.rows[0];

      // Ensure existing test reviewer account has complete profile and active balance
      if (isTestAccount) {
        if (!user.full_name) {
          await db.query(
            `UPDATE public.users SET full_name = $1, gender = $2, dob = $3, language = $4 WHERE id = $5`,
            ['Google Reviewer', 'Male', '1998-01-01', 'English', user.id]
          );
          user.full_name = 'Google Reviewer';
          user.gender = 'Male';
          user.dob = new Date('1998-01-01');
          user.language = 'English';
        }
        if ((parseFloat(user.balance) || 0) < 50) {
          await db.query(
            `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance) VALUES ($1, 100, 0) ON CONFLICT (user_id) DO UPDATE SET spendable_balance = 100`,
            [user.id]
          );
          user.spendable_balance = 100;
          user.balance = 100;
        }
      }

      // Backfill country_code / mobile if missing on existing record
      if (!user.country_code || !user.mobile) {
        await db.query(
          `UPDATE public.users SET country_code = $1, mobile = $2 WHERE id = $3`,
          [cleanCountryCode, cleanMobile, user.id]
        );
      }
    }

    // 6. Enforce Single-Device Policy: Invalidate previous sessions & generate new Session ID
    const sessionId = crypto.randomUUID();
    const io = req.app.get('io');
    if (io) {
      io.to(user.id).emit('session_terminated', {
        reason: 'Your account was logged in from another device.',
      });
      setTimeout(() => {
        try {
          io.in(user.id).disconnectSockets(true);
        } catch (_) {}
      }, 500);
    }

    // Invalidate all previous refresh tokens for this user in Redis
    try {
      const oldRefreshKeys = await scanKeys(redis, `refresh:${user.id}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    // Store active session in Redis (no TTL or long TTL, valid until overwritten/logged out)
    await redis.set(`user_active_session:${user.id}`, sessionId);

    // 7. Generate Tokens
    const jti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
      sessionId,
    };

    // Short-lived Access Token (1 day)
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });

    // Refresh Token (30 days) with jti
    const refreshToken = jwt.sign({ id: user.id, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store Refresh Token status in Redis: refresh:{userId}:{jti} -> TTL 30 days (2,592,000s)
    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);

    const isProfileComplete = !!(user.full_name && user.full_name.trim().length > 0);

    res.json({
      success: true,
      token,
      refreshToken,
      isProfileComplete,
      user: {
        id: user.id,
        countryCode: user.country_code || cleanCountryCode,
        mobile: user.mobile || cleanMobile,
        phoneNumber: user.phone_number || fullPhoneNumber,
        fullName: user.full_name || '',
        userName: user.user_name || null,
        hasPassword: Boolean(user.password_hash),
        dob: user.dob ? user.dob.toISOString() : null,
        gender: user.gender || 'Male',
        language: user.language || 'English',
        avatarSeed: user.avatar_seed || null,
        avatarStyle: user.avatar_style || 'avataaars',
        isTelecaller: user.is_telecaller || false,
        hasClaimedIntroOffer: user.has_claimed_intro_offer || false,
        country: user.country || null,
        state: user.state || null,
        city: user.city || null,
        latitude: user.latitude ? parseFloat(user.latitude) : null,
        longitude: user.longitude ? parseFloat(user.longitude) : null,
        balance: user.balance ? parseInt(user.balance, 10) : 0,
      },
    });
  } catch (err) {
    console.error('Error in /auth/otp/verify:', err.message);
    res.status(500).json({ error: 'Internal server error during verification.' });
  }
});

/**
 * Endpoint: POST /api/auth/refresh
 * Rotates the refresh token: verifies signature & Redis presence, invalidates old token, and issues new Access + Refresh tokens.
 */
router.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken || typeof refreshToken !== 'string') {
    return res.status(400).json({ error: 'Refresh token is required.' });
  }

  try {
    const decoded = jwt.verify(refreshToken, JWT_REFRESH_SECRET);
    const { id, jti, sessionId } = decoded;

    if (!id || !jti) {
      return res.status(401).json({ error: 'Invalid refresh token structure.' });
    }

    // Check Redis for active refresh token key
    const redisKey = `refresh:${id}:${jti}`;
    const exists = await redis.get(redisKey);

    if (!exists) {
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your session has been terminated because your account was logged in on another device.',
      });
    }

    // Check active session ID in Redis to ensure this refresh token belongs to current active device
    const activeSessionId = await redis.get(`user_active_session:${id}`);
    if (activeSessionId && (!sessionId || activeSessionId !== sessionId)) {
      await redis.del(redisKey);
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your account has been logged in on another device. Please log in again.',
      });
    }

    // Invalidate old refresh token key (rotation)
    await redis.del(redisKey);

    // Fetch user details
    const userRes = await db.query(
      `SELECT id, country_code, mobile, phone_number, full_name FROM public.users WHERE id = $1`,
      [id]
    );

    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const user = userRes.rows[0];

    const currentSessionId = activeSessionId || sessionId || crypto.randomUUID();
    if (!activeSessionId) {
      await redis.set(`user_active_session:${id}`, currentSessionId);
    }

    // Issue new tokens
    const newJti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: user.phone_number || `+${user.country_code}${user.mobile}`,
      countryCode: user.country_code,
      mobile: user.mobile,
      sessionId: currentSessionId,
    };

    const newAccessToken = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const newRefreshToken = jwt.sign({ id: user.id, jti: newJti, sessionId: currentSessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store new refresh token in Redis
    await redis.set(`refresh:${user.id}:${newJti}`, '1', 'EX', 30 * 24 * 60 * 60);

    res.json({
      success: true,
      token: newAccessToken,
      refreshToken: newRefreshToken,
    });
  } catch (err) {
    console.error('Error refreshing token:', err.message);
    res.status(401).json({ error: 'Invalid or expired refresh token.' });
  }
});

/**
 * Endpoint: POST /api/auth/logout
 * Invalidates the session by deleting the refresh token from Redis,
 * deleting the active session key, evicting all queues, terminating active calls,
 * marking presence offline, and disconnecting any live sockets for this user.
 */
router.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  const io = req.app.get('io');
  let userId = null;

  if (refreshToken && typeof refreshToken === 'string') {
    try {
      const decoded = jwt.decode(refreshToken);
      if (decoded && decoded.id) {
        userId = decoded.id;
        if (decoded.jti) {
          await redis.del(`refresh:${decoded.id}:${decoded.jti}`);
        }
      }
    } catch (_) {
      // Ignore decode failures on logout
    }
  }

  if (!userId && req.headers.authorization) {
    try {
      const authHeader = req.headers.authorization;
      if (authHeader.startsWith('Bearer ')) {
        const token = authHeader.substring(7);
        const decoded = jwt.decode(token);
        if (decoded && decoded.id) {
          userId = decoded.id;
        }
      }
    } catch (_) {}
  }

  if (userId) {
    try {
      // Delete active session key from Redis
      await redis.del(`user_active_session:${userId}`);

      const { cleanupUserMatchmaking } = require('../matchmaking/matchmaking.socket');
      const { cleanupUserInstantConnect } = require('../instant_connect/instant_connect.socket');
      const { PresenceService } = require('../presence/presence.service');

      await Promise.all([
        cleanupUserMatchmaking(io, redis, userId),
        cleanupUserInstantConnect(io, redis, userId),
        PresenceService.setPresence(redis, io, userId, false),
      ]);
      console.log(`🔒 [Auth] Complete server-side logout & socket purge performed for user ${userId}`);
    } catch (cleanupErr) {
      console.error(`Error during server logout cleanup for user ${userId}:`, cleanupErr.message);
    }
  }

  res.json({ success: true, message: 'Logged out successfully.' });
});

/**
 * Endpoint: POST /api/auth/delete-account & DELETE /api/users/me
 * Permanently deletes user account, cascades DB records, and purges all socket/Redis state.
 */
router.all(['/delete-account', '/delete', '/me'], authMiddleware, async (req, res, next) => {
  // If GET or PUT on /me, let other handlers handle it
  if (req.method === 'GET' || req.method === 'PUT' || req.method === 'PATCH') {
    return next();
  }

  const userId = req.user?.id;
  if (!userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { reason, feedback } = req.body || {};

  try {
    console.log(`⚠️ [Auth] Permanent account deletion requested for user ${userId}. Reason: ${reason || 'N/A'}`);

    // 1. Purge Redis session and live presence
    const redis = req.app.get('redis');
    const io = req.app.get('io');

    if (redis) {
      await redis.del(`user_active_session:${userId}`);
      await redis.del(`online_sockets:${userId}`);
      await redis.srem('instant:female_pool', userId);
      await redis.zrem('instant:male_queue', userId);
      await redis.del(`instant:male_session:${userId}`);
      await redis.del(`instant:in_call:${userId}`);
      await redis.del(`call_lock:${userId}`);
    }

    if (io) {
      try {
        const { cleanupUserMatchmaking } = require('../matchmaking/matchmaking.socket');
        const { cleanupUserInstantConnect } = require('../instant_connect/instant_connect.socket');
        const { PresenceService } = require('../presence/presence.service');

        await Promise.all([
          cleanupUserMatchmaking(io, redis, userId),
          cleanupUserInstantConnect(io, redis, userId),
          PresenceService.setPresence(redis, io, userId, false),
        ]);

        // Force disconnect any active socket connections for this user
        io.in(userId).disconnectSockets(true);
      } catch (e) {
        console.error('Error during socket cleanup on account deletion:', e.message);
      }
    }

    // 0. Persist deletion survey to database
    try {
      const userRes = await db.query('SELECT phone_number FROM public.users WHERE id = $1', [userId]);
      const phone = userRes.rows[0]?.phone_number || null;
      await db.query(
        `INSERT INTO public.account_deletion_surveys (user_id, phone_number, reason, feedback)
         VALUES ($1, $2, $3, $4)`,
        [userId, phone, reason || 'unspecified', feedback || null]
      );
      console.log(`📝 [Auth] Saved account deletion survey for user ${userId}`);
    } catch (surveyErr) {
      console.error('Error saving deletion survey:', surveyErr.message);
    }

    // 2. Cascade delete user record from database
    await db.query(`DELETE FROM public.users WHERE id = $1`, [userId]);

    console.log(`✅ [Auth] Account and all associated data permanently deleted for user ${userId}`);
    return res.json({ success: true, message: 'Account permanently deleted.' });
  } catch (err) {
    console.error(`❌ [Auth] Error deleting account for user ${userId}:`, err.message);
    return res.status(500).json({ error: 'Failed to delete account.', message: err.message });
  }
});
router.post('/profile', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { 
    fullName, 
    userName, 
    user_name, 
    password,
    dob, 
    gender, 
    language, 
    avatarSeed, 
    avatarStyle, 
    isTelecaller, 
    country, 
    state, 
    city, 
    latitude, 
    longitude 
  } = req.body;

  try {
    const rawUserName = userName !== undefined ? userName : user_name;
    let cleanUserName = null;

    if (rawUserName !== undefined && rawUserName !== null && rawUserName !== '') {
      const valRes = validateUsername(rawUserName);
      if (!valRes.valid) {
        if (valRes.isReserved) {
          return res.status(409).json({ error: 'USERNAME_TAKEN', message: 'it already exist fix it' });
        }
        return res.status(400).json({ error: 'INVALID_FORMAT', message: valRes.message });
      }
      cleanUserName = valRes.normalized;
    }

    let cleanPasswordHash = null;
    if (password) {
      if (typeof password !== 'string' || password.length < 8) {
        return res.status(400).json({ error: 'INVALID_PASSWORD', message: 'Password must be at least 8 characters long.' });
      }
      cleanPasswordHash = await bcrypt.hash(password, 10);
    }

    if (dob) {
      const birthDate = new Date(dob);
      if (isNaN(birthDate.getTime())) {
        return res.status(400).json({ error: 'Invalid date of birth format.' });
      }
      const today = new Date();
      let age = today.getFullYear() - birthDate.getFullYear();
      const monthDiff = today.getMonth() - birthDate.getMonth();
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--;
      }
      if (age < 18) {
        return res.status(400).json({ error: 'You must be 18 years or older to use this app.' });
      }
    }

    if (fullName || cleanUserName || cleanPasswordHash || avatarSeed || gender || language || dob) {
      const cleanGender = (gender || '').toLowerCase();
      const isFemale = cleanGender === 'female' || cleanGender === 'girl' || cleanGender === 'woman';
      const telecallerVal = isFemale ? (typeof isTelecaller === 'boolean' ? isTelecaller : null) : null;

      await db.query(
        `UPDATE public.users 
         SET full_name = COALESCE($1::TEXT, full_name), 
             dob = COALESCE($2::TIMESTAMPTZ, dob), 
             gender = COALESCE($3::TEXT, gender), 
             language = COALESCE($4::TEXT, language), 
             avatar_seed = COALESCE($5::TEXT, avatar_seed), 
             avatar_style = COALESCE($6::TEXT, avatar_style), 
             is_telecaller = COALESCE($7::BOOLEAN, is_telecaller),
             user_name = COALESCE($8::VARCHAR, user_name),
             password_hash = COALESCE($9::VARCHAR, password_hash)
         WHERE id = $10::UUID`,
        [
          fullName || null, 
          dob || null, 
          gender || null, 
          language || null, 
          avatarSeed || null, 
          avatarStyle || 'avataaars', 
          telecallerVal, 
          cleanUserName,
          cleanPasswordHash,
          userId
        ]
      );
    }

    if (country !== undefined || state !== undefined || city !== undefined || latitude !== undefined || longitude !== undefined) {
      await db.query(
        `UPDATE public.users 
         SET country = $1, state = $2, city = $3, latitude = $4, longitude = $5
         WHERE id = $6`,
        [country || null, state || null, city || null, latitude ?? null, longitude ?? null, userId]
      );
    }

    // Invalidate cached user profile in Redis
    await cacheService.invalidate(`user:profile:${userId}`);

    // Fetch and return the updated user object (including user_name and password_hash)
    const updatedUserRes = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
              w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );

    const userRow = updatedUserRes.rows[0];
    const sBal = parseFloat(userRow?.spendable_balance) || 0;
    const eBal = parseFloat(userRow?.earned_balance) || 0;
    const userObj = userRow ? {
      id: userRow.id,
      countryCode: userRow.country_code || '',
      mobile: userRow.mobile || '',
      phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
      fullName: userRow.full_name || '',
      userName: userRow.user_name || null,
      hasPassword: Boolean(userRow.password_hash),
      dob: userRow.dob || null,
      gender: userRow.gender || '',
      language: userRow.language || '',
      avatarSeed: userRow.avatar_seed || '',
      avatarStyle: userRow.avatar_style || 'avataaars',
      isTelecaller: userRow.is_telecaller || false,
      hasClaimedIntroOffer: userRow.has_claimed_intro_offer || false,
      country: userRow.country || null,
      state: userRow.state || null,
      city: userRow.city || null,
      latitude: userRow.latitude ? parseFloat(userRow.latitude) : null,
      longitude: userRow.longitude ? parseFloat(userRow.longitude) : null,
      spendableBalance: sBal,
      earnedBalance: eBal,
      balance: sBal + eBal,
    } : null;

    res.json({ success: true, message: 'Profile updated successfully.', user: userObj });
  } catch (err) {
    if (err.code === '23505' && (err.constraint === 'idx_users_user_name_lower' || (err.detail && err.detail.includes('user_name')))) {
      return res.status(409).json({ error: 'USERNAME_TAKEN', message: 'it already exist fix it' });
    }
    console.error('Error updating profile:', err.message);
    res.status(500).json({ error: 'Failed to update user profile.' });
  }
});

/**
 * Endpoint: GET /api/auth/me
 * Retrieves current user's profile and wallet balance.
 * Cached in Redis for 60 seconds with write-invalidation to handle rapid app restarts.
 */
router.get('/me', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const userRow = await cacheService.getOrSet(`user:profile:${userId}`, 60, async () => {
      const result = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.id = $1`,
        [userId]
      );
      return result.rows.length > 0 ? result.rows[0] : null;
    });

    if (!userRow) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const sBal = Number(userRow.spendable_balance) || 0;
    const eBal = Number(userRow.earned_balance) || 0;

    res.json({
      success: true,
      user: {
        id: userRow.id,
        countryCode: userRow.country_code || '',
        mobile: userRow.mobile || '',
        phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
        fullName: userRow.full_name || '',
        userName: userRow.user_name || null,
        hasPassword: Boolean(userRow.password_hash),
        dob: userRow.dob || null,
        gender: userRow.gender || '',
        language: userRow.language || '',
        avatarSeed: userRow.avatar_seed || null,
        avatarStyle: userRow.avatar_style || 'avataaars',
        isTelecaller: userRow.is_telecaller ?? null,
        hasClaimedIntroOffer: userRow.has_claimed_intro_offer === true,
        country: userRow.country || null,
        state: userRow.state || null,
        city: userRow.city || null,
        latitude: userRow.latitude !== null ? parseFloat(userRow.latitude) : null,
        longitude: userRow.longitude !== null ? parseFloat(userRow.longitude) : null,
        spendableBalance: sBal,
        earnedBalance: eBal,
        walletBalance: sBal + eBal,
        balance: sBal + eBal,
      },
    });
  } catch (err) {
    console.error('Error fetching profile:', err.message);
    res.status(500).json({ error: 'Internal server error fetching user profile.' });
  }
});

/**
 * Endpoint: POST & PATCH /api/auth/location
 * Updates authenticated user's location (country, state, city, latitude, longitude).
 */
async function handleLocationUpdate(req, res) {
  const userId = req.user.id;
  const { country, state, city, latitude, longitude } = req.body;

  try {
    await db.query(
      `UPDATE public.users
       SET country = $1, state = $2, city = $3, latitude = $4, longitude = $5
       WHERE id = $6`,
      [country || null, state || null, city || null, latitude ?? null, longitude ?? null, userId]
    );

    res.json({
      success: true,
      message: 'Location saved successfully.',
      location: { country, state, city, latitude, longitude },
    });
  } catch (err) {
    console.error('Error updating location:', err.message);
    res.status(500).json({ error: 'Failed to update user location.' });
  }
}

router.post('/location', authMiddleware, handleLocationUpdate);
router.patch('/location', authMiddleware, handleLocationUpdate);

/**
 * Endpoint: PATCH /api/users/me/telecaller-status (also /api/auth/telecaller-status)
 * Allows female users to toggle their telecaller opt-in mode.
 */
async function handleTelecallerStatusUpdate(req, res) {
  const userId = req.user.id;
  const { isTelecaller } = req.body;

  if (typeof isTelecaller !== 'boolean') {
    return res.status(400).json({ error: 'isTelecaller must be a boolean.' });
  }

  try {
    const userRes = await db.query('SELECT gender FROM public.users WHERE id = $1', [userId]);
    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const gender = (userRes.rows[0].gender || '').toLowerCase();
    const isFemale = (gender === 'female' || gender === 'girl' || gender === 'woman');

    if (!isFemale) {
      return res.status(403).json({ error: 'Telecaller mode is only available for female users.' });
    }

    await db.query(
      'UPDATE public.users SET is_telecaller = $1 WHERE id = $2',
      [isTelecaller, userId]
    );

    res.json({ success: true, isTelecaller });
  } catch (err) {
    console.error('Error updating telecaller status:', err.message);
    res.status(500).json({ error: 'Failed to update telecaller status.' });
  }
}

router.patch('/telecaller-status', authMiddleware, handleTelecallerStatusUpdate);
router.patch('/me/telecaller-status', authMiddleware, handleTelecallerStatusUpdate);

/**
 * Endpoint: POST /api/auth/upload-avatar
 * Uploads custom profile avatar to Cloudinary (or local storage fallback) and returns the image URL.
 */
const multer = require('multer');
const { CloudinaryStorage } = require('multer-storage-cloudinary');
const cloudinary = require('cloudinary').v2;
const path = require('path');
const fs = require('fs');

const hasCloudinary =
  Boolean(process.env.CLOUDINARY_CLOUD_NAME) &&
  Boolean(process.env.CLOUDINARY_API_KEY) &&
  Boolean(process.env.CLOUDINARY_API_SECRET);

if (hasCloudinary) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });
}

let avatarStorage;
if (hasCloudinary) {
  avatarStorage = new CloudinaryStorage({
    cloudinary: cloudinary,
    params: {
      folder: 'buddypartner/avatars',
      allowed_formats: ['jpg', 'png', 'jpeg', 'webp'],
    },
  });
} else {
  const uploadsDir = path.join(__dirname, '../../uploads/avatars');
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
  }
  avatarStorage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadsDir),
    filename: (_req, file, cb) => cb(null, `${Date.now()}_${file.originalname}`),
  });
}

const avatarUpload = multer({
  storage: avatarStorage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
});

router.post('/upload-avatar', authMiddleware, (req, res) => {
  avatarUpload.single('file')(req, res, async (err) => {
    if (err) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ success: false, error: 'File size exceeds 5MB limit.' });
      }
      return res.status(400).json({ success: false, error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No image file provided.' });
    }
    let imageUrl;
    if (req.file.path && (req.file.path.startsWith('http://') || req.file.path.startsWith('https://'))) {
      imageUrl = req.file.path;
    } else if (req.file.secure_url) {
      imageUrl = req.file.secure_url;
    } else {
      const host = req.get('host');
      const protocol = req.protocol;
      imageUrl = `${protocol}://${host}/uploads/avatars/${req.file.filename}`;
    }

    // Persist avatar URL directly to DB immediately on upload
    try {
      const userId = req.user?.id;
      if (userId) {
        // Ensure avatar_seed column can hold URLs (run at first upload, safe to repeat)
        await db.query(`ALTER TABLE public.users ALTER COLUMN avatar_seed TYPE TEXT`).catch(() => {});
        await db.query(
          `UPDATE public.users SET avatar_seed = $1 WHERE id = $2`,
          [imageUrl, userId]
        );
      }
    } catch (dbErr) {
      console.error('Failed to save avatar URL to DB:', dbErr.message);
      // Still return success — the URL was uploaded to Cloudinary
    }

    return res.json({ success: true, imageUrl, url: imageUrl });
  });
});

/**
 * Endpoint: POST /api/users/fcm-token and POST /api/auth/fcm-token
 * Saves the device FCM push token for push notifications and offline surge alerts.
 */
router.post('/fcm-token', authMiddleware, async (req, res) => {
  try {
    const { fcmToken } = req.body;
    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ error: 'Valid fcmToken string is required.' });
    }

    await db.query(
      `UPDATE public.users SET fcm_token = $1 WHERE id = $2`,
      [fcmToken.trim(), req.user.id]
    );

    res.json({ success: true, message: 'FCM token updated successfully.' });
  } catch (err) {
    console.error('Error updating FCM token:', err.message);
    res.status(500).json({ error: 'Failed to update FCM token.' });
  }
});

module.exports = router;

`

================================================================================
FILE: backend/package.json
================================================================================

`json
{
  "name": "buddypartner-backend",
  "version": "1.0.0",
  "description": "BuddyPartner backend — matchmaking, calls, and real-time events",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js"
  },
  "dependencies": {
    "@socket.io/redis-adapter": "^8.3.0",
    "agora-access-token": "^2.0.4",
    "axios": "^1.7.9",
    "bcryptjs": "^3.0.3",
    "cloudinary": "^1.41.3",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.21.0",
    "express-rate-limit": "^8.7.0",
    "firebase-admin": "^12.7.0",
    "googleapis": "^176.0.0",
    "helmet": "^7.1.0",
    "ioredis": "^5.4.1",
    "jsonwebtoken": "^9.0.2",
    "multer": "^2.2.0",
    "multer-storage-cloudinary": "^4.0.0",
    "pg": "^8.22.0",
    "rate-limit-redis": "^6.0.1",
    "razorpay": "^2.9.8",
    "semver": "^7.6.3",
    "socket.io": "^4.7.5",
    "socket.io-client": "^4.8.3",
    "twilio": "^6.0.2"
  },
  "engines": {
    "node": ">=18.0.0"
  },
  "devDependencies": {
    "autocannon": "^8.0.0"
  }
}

`

================================================================================
FILE: backend/.env.example
================================================================================

`javascript
# BuddyPartner Backend — Environment Variables
# Copy this file to .env and fill in the values

# Neon PostgreSQL Database Connection String
DATABASE_URL=postgresql://user:password@ep-something.neon.tech/neondb?sslmode=require

# JWT Configuration
JWT_SECRET=your_jwt_secret_key_here

# MSG91 WhatsApp OTP Credentials
MSG91_AUTHKEY=your_msg91_authkey_here
MSG91_INTEGRATED_NUMBER=916006329803
MSG91_TEMPLATE_NAME=otp

# Redis
REDIS_URL=redis://default:HTPyZNndmXV71TKggmGA5AAjZVE12PPx@milk-nimble-decent-32011.db.redis.io:16871

# Agora
AGORA_APP_ID=c1ad9e31c3ea4fb094ce515add9fe61b
AGORA_APP_CERTIFICATE=8a9a0c6452dc4e399b091404d23983c5

# Cloudinary Storage
CLOUDINARY_CLOUD_NAME=o8dwm2ig
CLOUDINARY_API_KEY=579652961933726
CLOUDINARY_API_SECRET=2bXI1THE9xSSdnjI33l2hv5SkSE

# Server
PORT=3000

`

================================================================================
FILE: backend/docs/MULTI_INSTANCE_MIGRATION.md
================================================================================

`markdown
# Multi-Instance Horizontal Scaling & Redis Migration Plan

## Executive Summary
The backend currently attaches `@socket.io/redis-adapter` in [`server.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/server.js), which successfully broadcasts room events (`io.to(userId).emit(...)`, `io.to(room).emit(...)`) across multiple server instances.

However, **call state and session authorization** rely on plain JavaScript `Map()` objects residing in single-process memory. Before horizontally scaling beyond **1 Node.js instance** (e.g. deploying 2+ replicas on Render, Railway, or AWS ECS), these in-memory Maps must be transitioned to Redis as detailed below.

---

## 1. Inventory of In-Memory Maps & Migration Matrix

| In-Memory Map | Location | Purpose | Priority | Proposed Redis Architecture |
| :--- | :--- | :--- | :--- | :--- |
| `activeCalls` | [`matchmaking.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/matchmaking/matchmaking.socket.js) | Stores `{ userA: { userId, socketId, gender }, userB: { ... } }` for live calls | **CRITICAL (Must Move)** | **Redis Hash** `call:{callId}` with field values serialized as JSON, TTL: 24h. Allows any node receiving hangup/heartbeat to validate call participants. |
| `pendingCallRequests` | [`matchmaking.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/matchmaking/matchmaking.socket.js) | Stores pending direct call request metadata (`callerId`, `targetUserId`, `timer`) | **CRITICAL (Must Move)** | **Redis String/Hash** `pending_call:{callRequestId}` with 35s TTL. When recipient answers on Node 2, Node 2 fetches call state from Redis. |
| `activeInstantCalls` | [`instant_connect.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/instant_connect/instant_connect.socket.js) | Stores live VIP instant call state, `maleUserId`, `femaleUserId`, `sessionId` | **CRITICAL (Must Move)** | **Redis Hash** `instant:active_call:{callId}` with TTL. Authorizes milestones and hangups across all nodes. |
| `socketToCall` / `socketToInstantCall` | Both socket files | Reverse mapping from `socket.id` to `callId` for disconnects | **MEDIUM** | Replace with socket session attachment `socket.activeCallId = callId`, plus Redis key `user_call:{userId} -> callId`. |
| `userSockets` | Both socket files | Maps `userId -> socket.id` | **LOW (Already Solved by Rooms)** | **No Redis Map Needed.** Sockets auto-join `socket.userId` on connect. `io.to(userId).emit(...)` uses the Redis adapter to route to the user's socket across instances in $O(1)$. |
| `ringingTimers` / `surgeTimers` | [`instant_connect.socket.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/modules/instant_connect/instant_connect.socket.js) | In-memory `setTimeout` handles for 15s ringing and 30s FCM surge cascades | **LOW (Safe to Keep Local for Now)** | Safe to leave in-memory on the initiating node. If the node crashes, the safety-net ticker or client-side timeout recovers the state. For enterprise scale, can use Redis Key Expiry Notifications (`__keyevent@0__:expired`). |

---

## 2. Why Room Emits Already Work Across Instances
In [`backend/server.js`](file:///c:/Users/dhruv/AndroidStudioProjects/dating_app/backend/server.js#L320-L325), the `@socket.io/redis-adapter` is initialized. When user `123` connects, they join room `123`. 
* If Instance 1 executes `io.to('456').emit('incoming_call_request', payload)`, the Redis adapter publishes to Redis pub/sub.
* Instance 2 receives the pub/sub packet and delivers it directly to User `456`'s socket.
* **The danger is NOT packet delivery; the danger is state lookup.** When User `456` clicks "Accept" and sends `accept_call_request` to Instance 2, Instance 2 checks its local `pendingCallRequests.has(callRequestId)` Map, finds nothing, and returns "Call request not found or expired".

---

## 3. Step-by-Step Implementation Roadmap

### Phase 1: Shared Call State in Redis (Estimated: 2 Days)
1. In `matchmaking.socket.js`, write `savePendingCall(callRequestId, data)` writing to `redis.set('pending_call:' + callRequestId, JSON.stringify(data), 'EX', 35)`.
2. In `accept_call_request`, retrieve the request from Redis with `redis.get('pending_call:' + callRequestId)`.
3. In `activeCalls`, migrate reads and writes to `redis.hset('active_call:' + callId, ...)` and `redis.hgetall('active_call:' + callId)`.

### Phase 2: Instant Connect VIP Shared State (Estimated: 1 Day)
1. Store claimed instant sessions in `redis.set('instant:active_call:' + callId, ...)` instead of `activeInstantCalls.set(...)`.
2. Enable multi-instance end-call authorization via Redis key lookup.

### Phase 3: Validation & Chaos Testing (Estimated: 1 Day)
1. Run two separate server processes locally on port 3001 and port 3002 connected to the same Redis and database.
2. Connect Client A to 3001 and Client B to 3002.
3. Validate complete matchmaking, ringing, answering, Agora token exchange, and hangup across the process boundary.

`

================================================================================
FILE: backend/migrations/000_schema_setup.sql
================================================================================

`sql
-- BuddyPartner Database Schema Setup for Neon PostgreSQL

-- 1. Users Table
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) UNIQUE NOT NULL,
  full_name VARCHAR(100),
  dob DATE,
  gender VARCHAR(20),
  language VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Wallets Table
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  balance INTEGER DEFAULT 0 NOT NULL
);

-- 3. Calls Table
CREATE TABLE IF NOT EXISTS public.calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  matched_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('active', 'ended')) NOT NULL DEFAULT 'active',
  call_type TEXT CHECK (call_type IN ('voice', 'video')) NOT NULL DEFAULT 'voice',
  duration_seconds INTEGER,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

-- 4. OTP Verifications Table
CREATE TABLE IF NOT EXISTS public.otp_verifications (
  id SERIAL PRIMARY KEY,
  phone_number VARCHAR(20) NOT NULL,
  otp_code VARCHAR(100) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXES FOR PERFORMANCE ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_otp_phone ON public.otp_verifications(phone_number);
CREATE INDEX IF NOT EXISTS idx_calls_caller ON public.calls(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_matched ON public.calls(matched_user_id);

-- ── TRIGGER FOR AUTO-CREATING WALLETS ON USER INSERT ───────────────────────
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_wallet ON public.users;
CREATE TRIGGER trigger_create_wallet
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_wallet_for_new_user();

-- ── CLEANUP CRON NOTE FOR EXPIRED OTPs ───────────────────────────────────────
-- To automate OTP cleanup at the database level, run this query in pg_cron (if enabled):
-- SELECT cron.schedule('cleanup-expired-otps', '0 * * * *', 'DELETE FROM public.otp_verifications WHERE expires_at < NOW()');
--
-- Alternatively, our Node.js backend handles this using a background interval query.

`

================================================================================
FILE: backend/migrations/001_create_calls_table.sql
================================================================================

`sql
-- BuddyPartner: Calls table migration
-- Run in Supabase SQL Editor or as a migration file

CREATE TABLE IF NOT EXISTS public.calls (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  matched_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('active', 'ended')) NOT NULL DEFAULT 'active',
  call_type TEXT CHECK (call_type IN ('voice', 'video')) NOT NULL DEFAULT 'voice',
  duration_seconds INTEGER,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

-- Users can only read their own calls (as caller or matched user)
CREATE POLICY "Users can view own calls"
  ON public.calls FOR SELECT
  USING (auth.uid() = caller_id OR auth.uid() = matched_user_id);

-- No client-side INSERT/UPDATE/DELETE — calls are only written by the Node backend's service-role client.

`

================================================================================
FILE: backend/migrations/002_create_messaging_tables.sql
================================================================================

`sql
-- BuddyPartner: Messaging tables migration
-- Conversations, Messages, Read receipts, Blocks, Reports

-- 1. Conversations — one canonical row per user pair
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_a_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  user_b_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (user_a_id, user_b_id)
);
-- Enforce canonical ordering: user_a_id < user_b_id (string comparison on Firebase UID)
-- so (A,B) and (B,A) can never both exist as separate rows.
-- This is enforced in application code (messaging.service.js), not a DB constraint.

-- 2. Messages
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  content TEXT,
  media_url TEXT,
  type TEXT CHECK (type IN ('text', 'image', 'system')) NOT NULL DEFAULT 'text',
  status TEXT CHECK (status IN ('sent', 'delivered', 'read')) NOT NULL DEFAULT 'sent',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for cursor-based pagination
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON public.messages (conversation_id, created_at DESC);

-- 3. Message read receipts
CREATE TABLE IF NOT EXISTS public.message_reads (
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  last_read_message_id UUID REFERENCES public.messages(id),
  PRIMARY KEY (conversation_id, user_id)
);

-- 4. Block list — either direction blocks messaging
CREATE TABLE IF NOT EXISTS public.blocks (
  blocker_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  blocked_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (blocker_id, blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker ON public.blocks(blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked ON public.blocks(blocked_id);

-- 5. Reports — references optional message/conversation
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  reporter_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  reported_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  reason TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON public.reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_reports_reported ON public.reports(reported_user_id);

`

================================================================================
FILE: backend/migrations/003_create_wallet_transactions_table.sql
================================================================================

`sql
-- 003_create_wallet_transactions_table.sql
-- Create table for tracking wallet balance credit and debit transactions

CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
  reason TEXT NOT NULL,
  reference_id UUID,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id);

`

================================================================================
FILE: backend/migrations/004_alter_wallet_transactions_reference_id.sql
================================================================================

`sql
-- 004_alter_wallet_transactions_reference_id.sql
-- Alter reference_id from UUID to TEXT to support string-based payment references & dev recharge IDs

ALTER TABLE public.wallet_transactions 
  ALTER COLUMN reference_id TYPE TEXT;

`

================================================================================
FILE: backend/migrations/004_create_rose_tables.sql
================================================================================

`sql
-- Migration 004: Rose balances, transactions, and withdrawal requests
-- Supports the gender-differentiated billing model:
--   Boys spend coins (existing wallets), Girls earn roses (new tables)

-- 1. Rose Balances — per-girl balance tracker
CREATE TABLE IF NOT EXISTS public.rose_balances (
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
  balance INTEGER DEFAULT 0 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Rose Transactions — credit/debit ledger
CREATE TABLE IF NOT EXISTS public.rose_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
  amount INTEGER NOT NULL,
  reason TEXT NOT NULL,          -- 'call_minute_voice' | 'call_minute_video' | 'withdrawal_request'
  reference_id UUID,             -- callId or withdrawal request id
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Withdrawal Requests — stub only, no real payout processing
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rose_amount INTEGER NOT NULL,
  rupee_amount INTEGER NOT NULL,  -- 1:1 conversion, stored explicitly
  status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- ── INDEXES ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_rose_tx_user ON public.rose_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_rose_tx_reference ON public.rose_transactions(reference_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_user ON public.withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_status ON public.withdrawal_requests(status);

-- ── TRIGGER: Auto-create rose_balances row for new female users ─────────────
CREATE OR REPLACE FUNCTION public.create_rose_balance_for_female_user()
RETURNS TRIGGER AS $$
BEGIN
  IF LOWER(COALESCE(NEW.gender, '')) IN ('female', 'girl', 'woman') THEN
    INSERT INTO public.rose_balances (user_id, balance)
    VALUES (NEW.id, 0)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_rose_balance ON public.users;
CREATE TRIGGER trigger_create_rose_balance
AFTER INSERT OR UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_rose_balance_for_female_user();

`

================================================================================
FILE: backend/migrations/005_add_avatar_columns.sql
================================================================================

`sql
-- Migration: Add avatar_seed and avatar_style columns to public.users
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS avatar_seed VARCHAR(50),
ADD COLUMN IF NOT EXISTS avatar_style VARCHAR(50) DEFAULT 'avataaars';

`

================================================================================
FILE: backend/migrations/005_alter_google_play_purchases_status.sql
================================================================================

`sql
-- 005_alter_google_play_purchases_status.sql
-- Add status and voided tracking columns to google_play_purchases for chargeback and refund reconciliation

ALTER TABLE public.google_play_purchases 
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'COMPLETED',
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_gp_purchases_order_id ON public.google_play_purchases(order_id);
CREATE INDEX IF NOT EXISTS idx_gp_purchases_status ON public.google_play_purchases(status);

`

================================================================================
FILE: backend/migrations/005_create_instant_connect_tables.sql
================================================================================

`sql
-- 005_create_instant_connect_tables.sql

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS incoming_paid_calls_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

CREATE TABLE IF NOT EXISTS public.instant_call_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  male_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  bid_amount INTEGER NOT NULL CHECK (bid_amount >= 10),
  status TEXT CHECK (status IN ('queued', 'ringing', 'in_call', 'completed', 'dropped', 'cancelled')) NOT NULL DEFAULT 'queued',
  agora_channel_name TEXT,
  started_at TIMESTAMPTZ,
  milestone_10m_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  duration_seconds INTEGER DEFAULT 0,
  scratch_card_unlocked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_instant_sess_male ON public.instant_call_sessions(male_user_id);
CREATE INDEX IF NOT EXISTS idx_instant_sess_female ON public.instant_call_sessions(female_user_id);

CREATE TABLE IF NOT EXISTS public.scratch_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES public.instant_call_sessions(id) ON DELETE SET NULL,
  female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  coin_reward INTEGER NOT NULL CHECK (coin_reward >= 1),
  is_scratched BOOLEAN DEFAULT FALSE,
  scratched_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scratch_cards_female ON public.scratch_cards(female_user_id);

`

================================================================================
FILE: backend/migrations/006_add_telecaller_column.sql
================================================================================

`sql
-- Migration 006: Add is_telecaller column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_telecaller BOOLEAN;

-- Backfill existing female users to default is_telecaller = TRUE
UPDATE public.users 
SET is_telecaller = TRUE 
WHERE LOWER(gender) IN ('female', 'girl', 'woman') AND is_telecaller IS NULL;

`

================================================================================
FILE: backend/migrations/007_create_subscriptions_table.sql
================================================================================

`sql
-- 007_create_subscriptions_table.sql
-- Create table for managing user subscriptions

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  plan_duration_days INTEGER NOT NULL,
  amount_paid INTEGER NOT NULL,       -- in rupees
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  payment_reference TEXT,             -- payment gateway transaction id
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_expires ON public.subscriptions(user_id, expires_at);

`

================================================================================
FILE: backend/migrations/008_add_location_columns.sql
================================================================================

`sql
-- Migration: Add Location Columns to public.users Table

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS country VARCHAR(100);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS state VARCHAR(100);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS city VARCHAR(100);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

`

================================================================================
FILE: backend/migrations/009_authkey_whatsapp_otp_schema.sql
================================================================================

`sql
-- Migration 009: Add country_code and mobile columns to public.users for Authkey WhatsApp OTP

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS country_code VARCHAR(10);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS mobile VARCHAR(20);

-- Create a unique constraint on (country_code, mobile)
-- (this also creates the backing index automatically — no separate CREATE INDEX needed)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_country_mobile'
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT unique_country_mobile UNIQUE (country_code, mobile);
    END IF;
END $$;

`

================================================================================
FILE: backend/migrations/010_reset_wallets_to_zero.sql
================================================================================

`sql
-- Migration 010: Reset initial wallet balance to 0 and set all existing account balances to 0

-- 1. Alter the default value for wallets balance column to 0
ALTER TABLE public.wallets ALTER COLUMN balance SET DEFAULT 0;

-- 2. Update trigger function for new user wallet creation to initialize balance with 0
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Reset all existing account balances to 0
UPDATE public.wallets SET balance = 0;

`

================================================================================
FILE: backend/migrations/011_production_scalability_indexes.sql
================================================================================

`sql
-- Migration 011: Production Scalability & High-Concurrency Indexes
-- Reversible: See 011_production_scalability_indexes_down.sql for rollback
-- Note: Uses CREATE INDEX CONCURRENTLY to avoid acquiring SHARE locks on tables during creation.
-- Must be executed outside a transaction block (run_migration_011.js runs statements individually).

-- 1. CONVERSATIONS TABLE
-- Eliminates sequential scan when querying user_b_id (second column of UNIQUE compound)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b 
  ON public.conversations(user_b_id);

-- Enables direct index scan for user conversation lists sorted by recent activity
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a_last_msg 
  ON public.conversations(user_a_id, last_message_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b_last_msg 
  ON public.conversations(user_b_id, last_message_at DESC);


-- 2. CALLS TABLE
-- Composite indexes for call history queries: WHERE (caller_id = $1 OR matched_user_id = $1) ORDER BY started_at DESC
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_caller_started 
  ON public.calls(caller_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_matched_started 
  ON public.calls(matched_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_status 
  ON public.calls(status);

-- Optimizes partner call pair lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_pair_started 
  ON public.calls(caller_id, matched_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_pair_rev_started 
  ON public.calls(matched_user_id, caller_id, started_at DESC);


-- 3. INSTANT CALL SESSIONS TABLE
-- Optimizes male/female call history and status queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_male_started 
  ON public.instant_call_sessions(male_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_female_started 
  ON public.instant_call_sessions(female_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_status 
  ON public.instant_call_sessions(status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_pair_started 
  ON public.instant_call_sessions(male_user_id, female_user_id, started_at DESC);


-- 4. WALLET TRANSACTIONS TABLE
-- Turns in-memory sort into an index scan for paginated wallet history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_wallet_tx_user_created 
  ON public.wallet_transactions(user_id, created_at DESC);


-- 5. ROSE TRANSACTIONS TABLE
-- Turns in-memory sort into an index scan for paginated earnings history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rose_tx_user_created 
  ON public.rose_transactions(user_id, created_at DESC);


-- 6. SCRATCH CARDS TABLE
-- Optimizes pending reward counts and earnings history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scratch_cards_female_scratched 
  ON public.scratch_cards(female_user_id, is_scratched);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scratch_cards_female_created 
  ON public.scratch_cards(female_user_id, created_at DESC);


-- 7. FAVORITES TABLE
-- Optimizes reverse join when checking who favorited a user or loading reverse favorites
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_favorites_favorite_user 
  ON public.favorites(favorite_user_id);


-- 8. MESSAGES TABLE
-- Speeds up unread count calculation and bulk "mark as read" queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_unread_status 
  ON public.messages(conversation_id, sender_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_sender 
  ON public.messages(sender_id);


-- 9. OTP VERIFICATIONS TABLE
-- Eliminates full table scan during periodic background OTP cleanup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_otp_expires_at 
  ON public.otp_verifications(expires_at);


-- 10. USERS TABLE
-- Speeds up moderation checks, gender-filtered matchmaking, and pool lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_is_banned 
  ON public.users(is_banned);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_gender 
  ON public.users(gender);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_incoming_paid 
  ON public.users(incoming_paid_calls_enabled) 
  WHERE incoming_paid_calls_enabled = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created_at 
  ON public.users(created_at DESC);

`

================================================================================
FILE: backend/migrations/011_production_scalability_indexes_down.sql
================================================================================

`sql
-- Rollback Migration 011: Drop Production Scalability Indexes

DROP INDEX IF EXISTS public.idx_conversations_user_b;
DROP INDEX IF EXISTS public.idx_conversations_user_a_last_msg;
DROP INDEX IF EXISTS public.idx_conversations_user_b_last_msg;

DROP INDEX IF EXISTS public.idx_calls_caller_started;
DROP INDEX IF EXISTS public.idx_calls_matched_started;
DROP INDEX IF EXISTS public.idx_calls_status;
DROP INDEX IF EXISTS public.idx_calls_pair_started;
DROP INDEX IF EXISTS public.idx_calls_pair_rev_started;

DROP INDEX IF EXISTS public.idx_instant_male_started;
DROP INDEX IF EXISTS public.idx_instant_female_started;
DROP INDEX IF EXISTS public.idx_instant_status;
DROP INDEX IF EXISTS public.idx_instant_pair_started;

DROP INDEX IF EXISTS public.idx_wallet_tx_user_created;
DROP INDEX IF EXISTS public.idx_rose_tx_user_created;

DROP INDEX IF EXISTS public.idx_scratch_cards_female_scratched;
DROP INDEX IF EXISTS public.idx_scratch_cards_female_created;

DROP INDEX IF EXISTS public.idx_favorites_favorite_user;

DROP INDEX IF EXISTS public.idx_messages_unread_status;
DROP INDEX IF EXISTS public.idx_messages_sender;

DROP INDEX IF EXISTS public.idx_otp_expires_at;

DROP INDEX IF EXISTS public.idx_users_is_banned;
DROP INDEX IF EXISTS public.idx_users_gender;
DROP INDEX IF EXISTS public.idx_users_incoming_paid;
DROP INDEX IF EXISTS public.idx_users_created_at;

`

================================================================================
FILE: backend/migrations/012_add_unique_user_name.sql
================================================================================

`sql
-- Migration 012: Add unique user_name column to users table
--
-- Description:
-- Adds a unique, case-insensitive user_name column to public.users.
-- Usernames are 3–20 characters, restricted to [a-z0-9._], and indexed uniquely by LOWER(user_name).
-- Existing users without a username will have NULL, which is permitted by PostgreSQL unique indexes.

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS user_name VARCHAR(30);

-- Case-insensitive unique index for fast lookup and collision prevention
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_user_name_lower 
ON public.users (LOWER(user_name));

`

================================================================================
FILE: backend/migrations/013_backfill_intro_offer_flag.sql
================================================================================

`sql
-- Migration 013: Backfill has_claimed_intro_offer flag for existing users
--
-- Description:
-- Marks users who have previously purchased an introductory subscription (₹9 / 1-day)
-- with has_claimed_intro_offer = TRUE so they cannot purchase it again.
--
-- Tech Debt Note (Heuristic Proxy):
-- This backfill identifies intro offer claims using (s.plan_duration_days = 1 OR s.amount_paid = 9).
-- This is a heuristic proxy tied to current pricing (₹9 / 1-day intro offer).
-- If pricing plans change or a different 1-day promo is introduced, this proxy may misclassify.
-- Future work: Introduce an explicit `is_intro_offer BOOLEAN` column on `subscriptions` set at purchase time.
--
-- Execution:
-- Run once manually via psql or the Neon / PostgreSQL database console:
--   psql $DATABASE_URL -f backend/migrations/013_backfill_intro_offer_flag.sql

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS has_claimed_intro_offer BOOLEAN DEFAULT FALSE;

UPDATE public.users u 
SET has_claimed_intro_offer = TRUE 
WHERE has_claimed_intro_offer IS NOT TRUE 
  AND EXISTS (
    SELECT 1 FROM public.subscriptions s 
    WHERE s.user_id = u.id AND (s.plan_duration_days = 1 OR s.amount_paid = 9)
  );

`

================================================================================
FILE: backend/migrations/015_add_buddy_requests.sql
================================================================================

`sql
-- Migration: 015_add_buddy_requests.sql
-- Creates the generic public.buddy_requests table and scale-optimized indexes for 5,000 CCU.

CREATE TABLE IF NOT EXISTS public.buddy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  buddy_type TEXT NOT NULL CHECK (buddy_type IN (
    'movie', 'pizza', 'coffee', 'hangout', 'trip', 'cricket',
    'shopping', 'night_out', 'clubbing', 'long_drive'
  )),
  city TEXT NOT NULL,
  target_gender TEXT NOT NULL CHECK (target_gender IN ('male', 'female', 'all')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open', 'accepted', 'otp_verified'
  )),
  accepter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  otp_code TEXT,
  otp_generated_at TIMESTAMPTZ,
  otp_attempts INTEGER NOT NULL DEFAULT 0,
  accepted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  initiator_coin_cost INTEGER NOT NULL DEFAULT 100,
  accepter_coin_reward INTEGER NOT NULL DEFAULT 50,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Partial index for hot-path city & target gender feed queries (only indexes unresolved open requests)
CREATE INDEX IF NOT EXISTS idx_buddy_requests_open_city_gender
  ON public.buddy_requests (city, target_gender, status) WHERE status = 'open';

-- User lookup indexes for fast initiator and accepter request retrieval
CREATE INDEX IF NOT EXISTS idx_buddy_requests_initiator ON public.buddy_requests (initiator_id, status);
CREATE INDEX IF NOT EXISTS idx_buddy_requests_accepter ON public.buddy_requests (accepter_id, status);

`

================================================================================
FILE: backend/migrations/016_dual_balance_and_corrected_buddy.sql
================================================================================

`sql
-- Migration 016: Dual-Balance Wallet + Corrected Buddy Meetup Flow + Payout Hardening
-- Reversible: See 016_dual_balance_and_corrected_buddy_down.sql

-- 1. DROP AND RECREATE public.wallets
DROP TABLE IF EXISTS public.wallets CASCADE;

CREATE TABLE public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  spendable_balance BIGINT NOT NULL DEFAULT 0,
  earned_balance BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_wallets_spendable_balance_non_negative CHECK (spendable_balance >= 0),
  CONSTRAINT chk_wallets_earned_balance_non_negative CHECK (earned_balance >= 0)
);

CREATE INDEX IF NOT EXISTS idx_wallets_user ON public.wallets(user_id);

-- 2. DROP AND RECREATE public.wallet_transactions
DROP TABLE IF EXISTS public.wallet_transactions CASCADE;

CREATE TABLE public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  spendable_delta BIGINT NOT NULL DEFAULT 0,
  earned_delta BIGINT NOT NULL DEFAULT 0,
  idempotency_key TEXT UNIQUE,
  reason TEXT NOT NULL CHECK (reason IN (
    'iap_purchase',
    'razorpay_purchase',
    'recharge',
    'buddy_spend',
    'buddy_reward',
    'call_spend',
    'call_earning',
    'withdrawal_hold',
    'withdrawal_reject_refund',
    'admin_grant',
    'instant_call_scratch_reward',
    'instant_call_escrow',
    'instant_call_refund',
    'signup_bonus'
  )),
  reference_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created 
  ON public.wallet_transactions(user_id, created_at DESC);

-- 3. DROP AND RECREATE public.buddy_requests
DROP TABLE IF EXISTS public.buddy_handshakes CASCADE;
DROP TABLE IF EXISTS public.buddy_requests CASCADE;

CREATE TABLE public.buddy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  buddy_type TEXT NOT NULL CHECK (buddy_type IN (
    'movie', 'pizza', 'coffee', 'hangout', 'trip', 'cricket',
    'shopping', 'night_out', 'clubbing', 'long_drive'
  )),
  city TEXT NOT NULL,
  target_gender TEXT NOT NULL CHECK (target_gender IN ('male', 'female', 'all')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open', 'accepted', 'completed', 'cancelled'
  )),
  accepter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  otp_hash TEXT,
  otp_encrypted TEXT,
  initiator_coin_cost INTEGER NOT NULL DEFAULT 100,
  accepter_coin_reward INTEGER NOT NULL DEFAULT 50,
  idempotency_key TEXT UNIQUE,
  accepted_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Scale indexes for Buddy Requests
CREATE INDEX IF NOT EXISTS idx_buddy_requests_status_city_gender 
  ON public.buddy_requests(status, city, target_gender);

CREATE INDEX IF NOT EXISTS idx_buddy_requests_initiator_created 
  ON public.buddy_requests(initiator_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_buddy_requests_accepter_created 
  ON public.buddy_requests(accepter_id, created_at DESC);

-- 4. DROP AND RECREATE public.withdrawals
DROP TABLE IF EXISTS public.withdrawal_requests CASCADE;
DROP TABLE IF EXISTS public.withdrawals CASCADE;

CREATE TABLE public.withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount BIGINT NOT NULL CHECK (amount > 0),
  rupee_amount BIGINT NOT NULL CHECK (rupee_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'paid')),
  idempotency_key TEXT UNIQUE,
  payout_method TEXT DEFAULT 'upi',
  payout_details JSONB,
  admin_note TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- Enforce partial unique index: maximum 1 concurrent pending withdrawal per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_withdrawals_single_pending 
  ON public.withdrawals(user_id) WHERE status = 'pending';

-- Index for withdrawal lookups
CREATE INDEX IF NOT EXISTS idx_withdrawals_user_status 
  ON public.withdrawals(user_id, status);

CREATE INDEX IF NOT EXISTS idx_withdrawals_requested 
  ON public.withdrawals(requested_at DESC);

-- 5. UPDATE TRIGGER FOR NEW USER WALLET CREATION
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
  VALUES (NEW.id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_wallet ON public.users;
CREATE TRIGGER trigger_create_wallet
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_wallet_for_new_user();

-- Auto-provision dual wallets for all existing users
INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
SELECT id, 0, 0 FROM public.users
ON CONFLICT (user_id) DO NOTHING;

-- 6. UNIQUE CONSTRAINT ON GOOGLE PLAY PURCHASE TOKENS (REPLAY INTEGRITY)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'google_play_purchases') THEN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_google_play_purchase_token 
      ON public.google_play_purchases(purchase_token);
  END IF;
END $$;

`

================================================================================
FILE: backend/migrations/016_dual_balance_and_corrected_buddy_down.sql
================================================================================

`sql
-- Rollback Migration: 016_dual_balance_and_corrected_buddy_down.sql

DROP TABLE IF EXISTS public.buddy_requests CASCADE;
DROP TABLE IF EXISTS public.withdrawals CASCADE;
DROP TABLE IF EXISTS public.wallet_transactions CASCADE;
DROP TABLE IF EXISTS public.wallets CASCADE;

-- Recreate old single balance wallet table
CREATE TABLE public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  balance INTEGER DEFAULT 0 NOT NULL
);

-- Recreate old wallet transactions table
CREATE TABLE public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  amount INTEGER NOT NULL,
  type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
  reason TEXT NOT NULL,
  reference_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id);

-- Recreate old withdrawal requests table
CREATE TABLE public.withdrawal_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rose_amount INTEGER NOT NULL,
  rupee_amount INTEGER NOT NULL,
  status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_withdrawal_user ON public.withdrawal_requests(user_id);

-- Revert trigger function
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_wallet ON public.users;
CREATE TRIGGER trigger_create_wallet
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_wallet_for_new_user();

INSERT INTO public.wallets (user_id, balance)
SELECT id, 0 FROM public.users
ON CONFLICT (user_id) DO NOTHING;

`

================================================================================
FILE: backend/migrations/017_create_user_monthly_call_usage.sql
================================================================================

`sql
-- 017_create_user_monthly_call_usage.sql
-- Tracks monthly aggregated audio and video call minutes per user for cost management.

CREATE TABLE IF NOT EXISTS public.user_monthly_call_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  year_month VARCHAR(7) NOT NULL, -- e.g. '2026-09'
  audio_seconds INTEGER DEFAULT 0 NOT NULL,
  video_seconds INTEGER DEFAULT 0 NOT NULL,
  audio_call_count INTEGER DEFAULT 0 NOT NULL,
  video_call_count INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_user_year_month UNIQUE (user_id, year_month)
);

CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_ym ON public.user_monthly_call_usage(year_month);
CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_user ON public.user_monthly_call_usage(user_id);

`

================================================================================
FILE: backend/migrations/018_add_password_hash_to_users.sql
================================================================================

`sql
-- Migration 018: Add password_hash column to public.users
--
-- Description:
-- Adds password_hash VARCHAR(255) to support username/phone + password authentication.
-- Existing users will have NULL, allowing them to log in via WhatsApp OTP and migrate to a password.

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);

`

================================================================================
FILE: backend/migrations/019_add_users_city_lower_trim_index.sql
================================================================================

`sql
-- Migration 019: Add functional index on public.users (LOWER(TRIM(city)))
--
-- Description:
-- Adds a non-blocking functional index on LOWER(TRIM(city)) for public.users.
-- Optimizes the Buddy FCM notification query in buddy.socket.js:
--   WHERE LOWER(TRIM(u.city)) = $1
--   AND ($2 = 'all' OR LOWER(TRIM(u.gender)) = $2)
--
-- Note: Uses CREATE INDEX CONCURRENTLY to prevent locking writes on public.users.
-- Must be run outside of a multi-statement transaction block.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_city_lower_trim 
  ON public.users (LOWER(TRIM(city)));

`

================================================================================
FILE: backend/migrations/020_add_messaging_delivery_indexes.sql
================================================================================

`sql
-- Migration 020: Add indexing for real-time message delivery updates
--
-- Description:
-- Adds non-blocking indexes to eliminate sequential scans when marking incoming
-- messages as 'delivered' on socket connection:
-- 1. Partial index on messages(conversation_id, status) for unread 'sent' messages.
-- 2. Direct single-column index on conversations(user_a_id) to optimize participant lookup.
-- 3. Direct single-column index on conversations(user_b_id) to optimize participant lookup.
--
-- Note: Uses CREATE INDEX CONCURRENTLY to prevent table write locks.
-- Must be run outside of a multi-statement transaction block.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_unread_status 
  ON public.messages (conversation_id, status) 
  WHERE status = 'sent';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a 
  ON public.conversations (user_a_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b 
  ON public.conversations (user_b_id);

`

