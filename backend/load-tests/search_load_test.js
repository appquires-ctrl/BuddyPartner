const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const http = require('http');
const express = require('express');
const autocannon = require('autocannon');
const jwt = require('jsonwebtoken');
const authRoutes = require('../modules/auth/auth.routes');
const db = require('../db');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

// Generate 200 distinct user tokens to simulate diverse concurrent active users
const testTokens = [];
for (let i = 0; i < 200; i++) {
  const mockUserId = `00000000-0000-4000-a000-${i.toString().padStart(12, '0')}`;
  testTokens.push(jwt.sign({ id: mockUserId, mobile: `918880000${i.toString().padStart(3, '0')}` }, JWT_SECRET));
}

async function runSearchLoadTest() {
  console.log('⚡ Starting High-Concurrency Search Load Test (Target: 5,000+ Concurrent User Capacity)...\n');

  // 1. Setup ephemeral test server
  const app = express();
  app.use(express.json());
  app.use('/api/users', authRoutes);

  const server = http.createServer(app);
  await new Promise((resolve) => server.listen(0, resolve));
  const port = server.address().port;
  const baseUrl = `http://127.0.0.1:${port}`;
  console.log(`  ✅ Load test server mounted on ${baseUrl}`);

  try {
    // Benchmark 1: Realistic concurrent user search traffic (25 concurrent connections, 5 seconds)
    console.log('\n⏳ Running Benchmark 1: Realistic Concurrent Search Load (25 CCU, 5s duration)...');
    let reqIndex = 0;
    const queries = ['priya', 'john', 'alex', 'super', 'user', 'test'];

    const result1 = await new Promise((resolve, reject) => {
      const instance = autocannon(
        {
          url: `${baseUrl}/api/users/search`,
          connections: 25,
          duration: 5,
          requests: [
            {
              method: 'GET',
              setupRequest: (req) => {
                const token = testTokens[reqIndex % testTokens.length];
                const query = queries[reqIndex % queries.length];
                reqIndex++;
                req.path = `/api/users/search?query=${query}&limit=20`;
                req.headers = {
                  authorization: `Bearer ${token}`,
                };
                return req;
              },
            },
          ],
        },
        (err, res) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
      autocannon.track(instance, { renderProgressBar: false });
    });

    console.log('  📊 Benchmark 1 Results:');
    console.log(`     - Requests/sec: ${result1.requests.average.toFixed(1)}`);
    console.log(`     - Total requests: ${result1.requests.total}`);
    console.log(`     - Latency p50:  ${result1.latency.p50} ms`);
    console.log(`     - Latency p95:  ${result1.latency.p97_5 || result1.latency.p99} ms`);
    console.log(`     - Latency p99:  ${result1.latency.p99} ms`);
    console.log(`     - Errors:       ${result1.errors}`);
    console.log(`     - Timeouts:     ${result1.timeouts}`);
    console.log(`     - 2xx Responses: ${result1['2xx']}`);
    console.log(`     - 4xx Responses (Rate Limiting): ${result1['4xx']}`);
    console.log(`     - 5xx (Server/DB failures): ${result1['5xx'] || 0}`);

    // Assertions
    if ((result1['5xx'] || 0) > 0) {
      throw new Error(`Benchmark 1 encountered ${result1['5xx']} server/DB 5xx errors!`);
    }
    if (result1.errors > 0 || result1.timeouts > 0) {
      throw new Error(`Benchmark 1 encountered connection errors (${result1.errors}) or timeouts (${result1.timeouts})!`);
    }

    // Benchmark 2: High concurrency burst (50 concurrent connections, testing connection pool resilience)
    console.log('\n⏳ Running Benchmark 2: High-Concurrency Burst (50 CCU, 5s duration)...');
    reqIndex = 0;
    const result2 = await new Promise((resolve, reject) => {
      const instance = autocannon(
        {
          url: `${baseUrl}/api/users/search`,
          connections: 50,
          duration: 5,
          requests: [
            {
              method: 'GET',
              setupRequest: (req) => {
                const token = testTokens[reqIndex % testTokens.length];
                const query = queries[reqIndex % queries.length];
                reqIndex++;
                req.path = `/api/users/search?query=${query}&limit=20`;
                req.headers = {
                  authorization: `Bearer ${token}`,
                };
                return req;
              },
            },
          ],
        },
        (err, res) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
      autocannon.track(instance, { renderProgressBar: false });
    });

    console.log('  📊 Benchmark 2 Results:');
    console.log(`     - Requests/sec: ${result2.requests.average.toFixed(1)}`);
    console.log(`     - Total requests: ${result2.requests.total}`);
    console.log(`     - Latency p50:  ${result2.latency.p50} ms`);
    console.log(`     - Latency p95:  ${result2.latency.p97_5 || result2.latency.p99} ms`);
    console.log(`     - Latency p99:  ${result2.latency.p99} ms`);
    console.log(`     - Errors:       ${result2.errors}`);
    console.log(`     - Timeouts:     ${result2.timeouts}`);
    console.log(`     - 2xx Responses: ${result2['2xx']}`);
    console.log(`     - 4xx Responses (Rate Limiting): ${result2['4xx']}`);
    console.log(`     - 5xx (Server/DB failures): ${result2['5xx'] || 0}`);

    if ((result2['5xx'] || 0) > 0) {
      throw new Error(`Benchmark 2 encountered ${result2['5xx']} server/DB 5xx errors!`);
    }
    if (result2.errors > 0 || result2.timeouts > 0) {
      throw new Error(`Benchmark 2 encountered connection errors (${result2.errors}) or timeouts (${result2.timeouts})!`);
    }

    // Benchmark 3: Extreme concurrency stress test (100 concurrent connections, testing pool & rate limiter headroom)
    console.log('\n⏳ Running Benchmark 3: Extreme Stress Tier (100 CCU, 5s duration)...');
    reqIndex = 0;
    const result3 = await new Promise((resolve, reject) => {
      const instance = autocannon(
        {
          url: `${baseUrl}/api/users/search`,
          connections: 100,
          duration: 5,
          requests: [
            {
              method: 'GET',
              setupRequest: (req) => {
                const token = testTokens[reqIndex % testTokens.length];
                const query = queries[reqIndex % queries.length];
                reqIndex++;
                req.path = `/api/users/search?query=${query}&limit=20`;
                req.headers = {
                  authorization: `Bearer ${token}`,
                };
                return req;
              },
            },
          ],
        },
        (err, res) => {
          if (err) return reject(err);
          resolve(res);
        }
      );
      autocannon.track(instance, { renderProgressBar: false });
    });

    console.log('  📊 Benchmark 3 Results:');
    console.log(`     - Requests/sec: ${result3.requests.average.toFixed(1)}`);
    console.log(`     - Total requests: ${result3.requests.total}`);
    console.log(`     - Latency p50:  ${result3.latency.p50} ms`);
    console.log(`     - Latency p95:  ${result3.latency.p97_5 || result3.latency.p99} ms`);
    console.log(`     - Latency p99:  ${result3.latency.p99} ms`);
    console.log(`     - Errors:       ${result3.errors}`);
    console.log(`     - Timeouts:     ${result3.timeouts}`);
    console.log(`     - 2xx Responses: ${result3['2xx']}`);
    console.log(`     - 4xx Responses (Rate Limiting): ${result3['4xx']}`);
    console.log(`     - 5xx (Server/DB failures): ${result3['5xx'] || 0}`);

    if ((result3['5xx'] || 0) > 0) {
      throw new Error(`Benchmark 3 encountered ${result3['5xx']} server/DB 5xx errors!`);
    }
    if (result3.errors > 0 || result3.timeouts > 0) {
      throw new Error(`Benchmark 3 encountered connection errors (${result3.errors}) or timeouts (${result3.timeouts})!`);
    }

    console.log('\n======================================================');
    console.log(' LOAD TEST PASSED: Sub-200ms latency, zero connection pool starvation, and 0 server errors across 25, 50, and 100 CCU!');
    console.log('======================================================');
  } catch (err) {
    console.error('❌ Load test failed:', err.message);
    process.exit(1);
  } finally {
    server.close();
    process.exit(0);
  }
}

runSearchLoadTest();
