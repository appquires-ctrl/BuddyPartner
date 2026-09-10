require('dotenv').config();
const autocannon = require('autocannon');
const jwt = require('jsonwebtoken');
const Redis = require('ioredis');

const PORT = process.env.PORT || 3000;
const BASE_URL = `http://localhost:${PORT}`;
const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const TEST_USER_ID = 'fa4c162e-877d-4d08-9eac-4f80f02123e7';
const TEST_SESSION_ID = 'load-test-session-id';

// Generate a valid mock user JWT matching an active database user
const testUserToken = jwt.sign(
  {
    id: TEST_USER_ID,
    phone: '+919999999999',
    sessionId: TEST_SESSION_ID,
  },
  JWT_SECRET,
  { expiresIn: '1d' }
);

async function runBenchmark(title, endpoint, connections, durationSeconds = 5) {
  console.log(`\n⏳ Running [${title}] | Endpoint: ${endpoint} | Concurrency: ${connections} connections | Duration: ${durationSeconds}s...`);

  return new Promise((resolve, reject) => {
    const instance = autocannon(
      {
        url: `${BASE_URL}${endpoint}`,
        connections: connections,
        duration: durationSeconds,
        headers: {
          authorization: `Bearer ${testUserToken}`,
          'content-type': 'application/json',
        },
      },
      (err, result) => {
        if (err) return reject(err);

        const p95Val = result.latency.p97_5 || result.latency.p99;

        console.log(`  📊 Results for ${title} (${connections} CCU):`);
        console.log(`     - Requests/sec: ${result.requests.average.toFixed(1)}`);
        console.log(`     - Throughput:   ${(result.throughput.average / 1024 / 1024).toFixed(2)} MB/s`);
        console.log(`     - Latency p50:  ${result.latency.p50} ms`);
        console.log(`     - Latency p95:  ${p95Val} ms`);
        console.log(`     - Latency p99:  ${result.latency.p99} ms`);
        console.log(`     - Errors:       ${result.errors}`);
        console.log(`     - Timeouts:     ${result.timeouts}`);
        console.log(`     - Non-2xx:      ${result.non2xx}`);

        resolve({
          title,
          endpoint,
          connections,
          rps: result.requests.average,
          p50: result.latency.p50,
          p95: p95Val,
          p99: result.latency.p99,
          errors: result.errors,
          timeouts: result.timeouts,
          non2xx: result.non2xx,
        });
      }
    );

    autocannon.track(instance, { renderProgressBar: false });
  });
}

async function main() {
  console.log('====================================================');
  console.log('🚀 Starting Real Multi-Level Concurrency Benchmarks');
  console.log('====================================================');
  console.log(`Target: ${BASE_URL}\n`);

  const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
  const redis = new Redis(redisUrl, { maxRetriesPerRequest: 1 });
  try {
    await redis.set(`user_active_session:${TEST_USER_ID}`, TEST_SESSION_ID);
    console.log(`✅ Session active key synced in Redis for user ${TEST_USER_ID}`);
  } catch (err) {
    console.warn('⚠️ Could not sync Redis session key:', err.message);
  }

  const results = [];

  try {
    // 1. Level 100 Virtual Users
    results.push(await runBenchmark('Matches Endpoint', '/api/calls/matches', 100, 5));
    results.push(await runBenchmark('Call History Endpoint', '/api/calls/history?limit=20', 100, 5));
    results.push(await runBenchmark('Wallet Balance (Cached)', '/api/wallet/balance', 100, 5));

    // 2. Level 500 Virtual Users
    results.push(await runBenchmark('Matches Endpoint', '/api/calls/matches', 500, 5));
    results.push(await runBenchmark('Call History Endpoint', '/api/calls/history?limit=20', 500, 5));
    results.push(await runBenchmark('Wallet Balance (Cached)', '/api/wallet/balance', 500, 5));

    // 3. Level 1,000 Virtual Users
    results.push(await runBenchmark('Matches Endpoint', '/api/calls/matches', 1000, 5));
    results.push(await runBenchmark('Call History Endpoint', '/api/calls/history?limit=20', 1000, 5));
    results.push(await runBenchmark('Wallet Balance (Cached)', '/api/wallet/balance', 1000, 5));

    console.log('\n====================================================');
    console.log('📋 SUMMARY TABLE OF MEASURED BENCHMARKS');
    console.log('====================================================');
    console.table(
      results.map((r) => ({
        Endpoint: r.title,
        CCU: r.connections,
        'Req/sec': Math.round(r.rps),
        'p50 (ms)': r.p50,
        'p95 (ms)': r.p95,
        'p99 (ms)': r.p99,
        '2xx OK': r.rps * 5 - (r.errors + r.timeouts + r.non2xx),
        Errors: r.errors + r.timeouts + r.non2xx,
      }))
    );
  } catch (err) {
    console.error('Benchmark suite error:', err.message);
  } finally {
    try {
      await redis.quit();
    } catch (_) {}
  }
}

main();
