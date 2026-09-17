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
  getStore,
};

