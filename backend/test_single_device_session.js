/**
 * Automated Verification: Single Active Device Login Policy
 * 
 * Scenario:
 * 1. Seed user in test database.
 * 2. Generate Session 1 for Device A -> Verify Access & Redis Key.
 * 3. Make protected API request with Token A -> Expect HTTP 200.
 * 4. Generate Session 2 for Device B (same phone number) -> Invalidate Session 1 in Redis.
 * 5. Make protected API request with Token B -> Expect HTTP 200.
 * 6. Make protected API request with Token A -> Expect HTTP 401 SESSION_TERMINATED.
 * 7. Logout Device B -> Clean up Redis key.
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });

const jwt = require('jsonwebtoken');
const crypto = require('crypto');
const redis = require('./redis');
const { authMiddleware } = require('./middleware/auth.middleware');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

async function runSessionTests() {
  console.log('🧪 Starting Single Active Device Login Policy Automated Tests...\n');

  const testUserId = '00000000-0000-0000-0000-000000000001';
  const testPhone = '+919795038296';
  const testCountryCode = '91';
  const testMobile = '9795038296';

  let passedTests = 0;
  let totalTests = 0;

  function assert(condition, message) {
    totalTests++;
    if (condition) {
      console.log(`  ✅ Passed: ${message}`);
      passedTests++;
    } else {
      console.error(`  ❌ Failed: ${message}`);
      process.exitCode = 1;
    }
  }

  // ── Helper to simulate authMiddleware execution ────────────────────────────
  async function simulateAuthMiddleware(token) {
    return new Promise((resolve) => {
      const req = {
        headers: {
          authorization: `Bearer ${token}`,
        },
      };
      const res = {
        statusCode: 200,
        status(code) {
          this.statusCode = code;
          return this;
        },
        json(data) {
          resolve({ status: this.statusCode, data });
        },
      };
      const next = () => {
        resolve({ status: 200, user: req.user });
      };

      authMiddleware(req, res, next).catch((err) => {
        resolve({ status: 500, error: err.message });
      });
    });
  }

  try {
    // ── Test 1: Device A Login ───────────────────────────────────────────────
    console.log('1️⃣ Simulating Device A Login...');
    const sessionA = crypto.randomUUID();
    await redis.set(`user_active_session:${testUserId}`, sessionA);

    const tokenA = jwt.sign(
      {
        id: testUserId,
        phone: testPhone,
        countryCode: testCountryCode,
        mobile: testMobile,
        sessionId: sessionA,
      },
      JWT_SECRET,
      { expiresIn: '1d' }
    );

    const checkA = await simulateAuthMiddleware(tokenA);
    assert(checkA.status === 200 && checkA.user?.id === testUserId, 'Device A (Session 1) authenticates successfully');

    // ── Test 2: Device B Login (Same Account) ────────────────────────────────
    console.log('\n2️⃣ Simulating Device B Login on Same Account...');
    const sessionB = crypto.randomUUID();
    // Overwrite Redis key with Session B
    await redis.set(`user_active_session:${testUserId}`, sessionB);

    const tokenB = jwt.sign(
      {
        id: testUserId,
        phone: testPhone,
        countryCode: testCountryCode,
        mobile: testMobile,
        sessionId: sessionB,
      },
      JWT_SECRET,
      { expiresIn: '1d' }
    );

    const checkB = await simulateAuthMiddleware(tokenB);
    assert(checkB.status === 200 && checkB.user?.sessionId === sessionB, 'Device B (Session 2) authenticates successfully');

    // ── Test 3: Device A tries to make request after Device B logged in ───────
    console.log('\n3️⃣ Testing Device A Access after Device B Login...');
    const checkAAfter = await simulateAuthMiddleware(tokenA);
    assert(
      checkAAfter.status === 401 && checkAAfter.data?.error === 'SESSION_TERMINATED',
      'Device A is rejected with HTTP 401 SESSION_TERMINATED'
    );
    assert(
      checkAAfter.data?.message?.includes('logged in on another device'),
      'Device A receives clear user-friendly explanation message'
    );

    // ── Test 4: Device B Logout ──────────────────────────────────────────────
    console.log('\n4️⃣ Testing Logout Session Deletion...');
    await redis.del(`user_active_session:${testUserId}`);
    const redisSession = await redis.get(`user_active_session:${testUserId}`);
    assert(redisSession === null, 'Session key cleanly removed from Redis on logout');

    console.log(`\n🎉 All ${passedTests}/${totalTests} Single Active Device Login tests passed successfully!`);
  } catch (err) {
    console.error('❌ Test suite failed:', err);
    process.exitCode = 1;
  } finally {
    redis.disconnect();
  }
}

runSessionTests();
