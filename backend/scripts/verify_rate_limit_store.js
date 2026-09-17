require('dotenv').config();
const { RedisStore } = require('rate-limit-redis');
const redis = require('../redis');
const {
  apiGlobalLimiter,
  otpRateLimiter,
  callRateLimiter,
  usernameCheckLimiter,
  userSearchLimiter,
  getStore,
} = require('../middleware/rate_limit.middleware');

async function testRateLimitStore() {
  console.log('--- 1.1 Express Rate Limiter Redis Store Verification ---');
  
  // 1. Verify getStore synchronously returns RedisStore without waiting for connect event
  const store = getStore('test_unit');
  const isRedisStore = store instanceof RedisStore;
  console.log(`[Store Type Check] getStore('test_unit') instanceof RedisStore: ${isRedisStore}`);
  if (!isRedisStore) {
    console.error('❌ FAILED: getStore did not return a RedisStore instance!');
    process.exit(1);
  }

  // 2. Fire request through apiGlobalLimiter and verify physical Redis write
  const testIp = '192.168.1.99';
  const req = {
    ip: testIp,
    headers: {},
    method: 'GET',
    url: '/api/test',
    app: { get: () => false },
  };
  const res = {
    setHeader: () => {},
    getHeader: () => null,
    status: () => res,
    send: () => res,
  };

  await new Promise((resolve) => {
    apiGlobalLimiter(req, res, () => {
      resolve();
    });
  });

  // Check Redis for the rate limit key
  const expectedKey = `rl:global:${testIp}`;
  const keyType = await redis.type(expectedKey);
  console.log(`[Redis Key Check] Key '${expectedKey}' exists in Redis with type: '${keyType}'`);

  if (keyType === 'none') {
    console.error(`❌ FAILED: Expected Redis key '${expectedKey}' not found in Redis!`);
    process.exit(1);
  }

  // Fetch hits/counter from Redis
  const val = await redis.get(expectedKey);
  console.log(`[Redis Counter Value] ${expectedKey} = ${val}`);

  // Cleanup
  await redis.del(expectedKey);
  console.log('✅ PASSED: Rate limiters are strictly writing to distributed Redis!');
  process.exit(0);
}

testRateLimitStore().catch((err) => {
  console.error('❌ Error during rate limiter verification:', err);
  process.exit(1);
});
