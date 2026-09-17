require('dotenv').config();
const redis = require('../redis');

async function testRedisMetricsAndFailClosed() {
  console.log('================================================================');
  console.log(' 1.2 REAL EXECUTION: REDIS FALLBACK METRICS & FAIL-CLOSED TEST');
  console.log('================================================================\n');

  // Small delay for initial connection
  await new Promise((r) => setTimeout(r, 500));

  console.log('--- Step 1: Baseline Metrics & State ---');
  const initialMetrics = redis.getMetrics();
  console.log('Initial Redis metrics:', initialMetrics);
  console.log('redis.isHealthy():', redis.isHealthy());
  console.log('redis.isInMemory:', redis.isInMemory);

  console.log('\n--- Step 2: Simulate Redis Disconnect / Outage ---');
  // Disconnect the underlying ioredis client to force fallback state
  redis.disconnect();
  // Wait 200ms for close handler to flip isConnected = false
  await new Promise((r) => setTimeout(r, 200));

  console.log('After disconnect:');
  console.log('redis.isHealthy():', redis.isHealthy());
  console.log('redis.isInMemory:', redis.isInMemory);

  console.log('\n--- Step 3: Verify Normal Keys Work in Fallback Store ---');
  await redis.set('test_normal_key', 'value_123', 'EX', 60);
  const val = await redis.get('test_normal_key');
  console.log("Read 'test_normal_key' from fallback store:", val);
  if (val !== 'value_123') {
    throw new Error('Normal key failed in fallback store!');
  }

  console.log('\n--- Step 4: Verify Fail-Closed Distributed Locks ---');
  console.log("Attempting SETNX on 'direct_mutex:user_456' during partition...");
  const directMutexResult = await redis.set('direct_mutex:user_456', '1', 'NX', 'EX', 5);
  console.log('directMutexResult:', directMutexResult);

  console.log("Attempting SETNX on 'instant:claim_session:session_789' during partition...");
  const claimSessionResult = await redis.set('instant:claim_session:session_789', 'female_1', 'NX', 'EX', 120);
  console.log('claimSessionResult:', claimSessionResult);

  console.log("Attempting SETNX on 'instant:claimed:session_789' during partition...");
  const claimedResult = await redis.set('instant:claimed:session_789', 'female_1', 'NX', 'EX', 120);
  console.log('claimedResult:', claimedResult);

  if (directMutexResult !== null || claimSessionResult !== null || claimedResult !== null) {
    throw new Error('FAILED: Distributed lock was granted locally during Redis partition! Must be null.');
  }

  console.log('\n--- Step 5: Verify Fallback Metrics Counter ---');
  const finalMetrics = redis.getMetrics();
  console.log('Final Redis metrics:', finalMetrics);
  console.log('fallbackWarningCount:', redis.fallbackWarningCount);

  if (finalMetrics.fallbackWarningCount <= 0) {
    throw new Error('FAILED: fallbackWarningCount did not increment on fallback events!');
  }

  console.log('\n================================================================');
  console.log(' ✅ 1.2 TEST PASSED: Fail-closed lock returned null & metrics tracked');
  console.log('================================================================');
  process.exit(0);
}

testRedisMetricsAndFailClosed().catch((err) => {
  console.error('\n❌ TEST FAILED:', err);
  process.exit(1);
});
