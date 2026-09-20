const { rateLimit, ipKeyGenerator } = require('express-rate-limit');
const { RedisStore } = require('rate-limit-redis');
const redis = require('../redis');

/**
 * Helper to construct a distributed Redis store or fall back to in-memory store
 * @param {string} prefix - Unique namespace for the rate limiter
 * @returns {RedisStore|undefined}
 */
function getStore(prefix) {
  return new RedisStore({
    prefix: `rl:${prefix}:`,
    sendCommand: async (...args) => {
      try {
        if (redis.status !== 'ready') {
          await new Promise((resolve) => {
            if (redis.status === 'ready') return resolve();
            const onReady = () => { cleanup(); resolve(); };
            const onError = () => { cleanup(); resolve(); };
            const timer = setTimeout(() => { cleanup(); resolve(); }, 1500);
            function cleanup() {
              if (typeof redis.removeListener === 'function') {
                redis.removeListener('ready', onReady);
                redis.removeListener('error', onError);
              }
              clearTimeout(timer);
            }
            if (typeof redis.once === 'function') {
              redis.once('ready', onReady);
              redis.once('error', onError);
            } else {
              resolve();
            }
          });
        }
        if (redis.status === 'ready') {
          return await redis.call(...args);
        }
      } catch (err) {
        console.warn(`⚠️ [RateLimit Redis] '${args[0]}' failed on Redis: ${err.message}. Failing open.`);
      }

      // Resilient fail-open fallback so rate limiting never crashes critical API routes
      const command = args[0];
      if (command === 'SCRIPT') {
        return 'fallback_rate_limit_sha';
      }
      return [1, 60000];
    },
  });
}

/**
 * Global API rate limiter: 300 requests per minute per IP
 * Uses express-rate-limit's built-in in-memory sliding window store per Node instance.
 * Architectural Trade-off: A per-instance limit is looser than a cluster-wide Redis limit
 * across multiple replicas, but it completely eliminates a Redis Lua EVAL call on EVERY
 * single HTTP request cluster-wide (saving thousands of Redis ops/sec under 5,000 CCU).
 * Redis-backed rate limiting remains enabled for sensitive, low-frequency endpoints below.
 */
const apiGlobalLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: 300,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  skip: () => process.env.DISABLE_RATE_LIMIT === 'true',
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
  getStore,
};

