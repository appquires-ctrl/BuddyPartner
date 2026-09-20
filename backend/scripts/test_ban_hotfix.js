const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const express = require('express');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const db = require('../db');
const redis = require('../redis');
const authRoutes = require('../modules/auth/auth.routes');

const app = express();
app.use(express.json());
app.use('/api/auth', authRoutes);

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'buddypartner_fallback_jwt_refresh_secret_key';

async function runHotfixTests() {
  console.log('🚀 Running Ban-Check Hotfix Verification Tests...\n');

  let server;
  try {
    await new Promise((resolve) => {
      server = app.listen(0, () => resolve());
    });
    const port = server.address().port;
    const baseUrl = `http://127.0.0.1:${port}`;

    // Wait for Redis connection to be ready if not already
    if (redis.status !== 'ready') {
      await new Promise((resolve) => {
        if (redis.status === 'ready') return resolve();
        redis.once('ready', resolve);
      });
    }

    // 1. Setup a banned test user
    const testBannedMobile = '9999988888';
    const testBannedCountryCode = '91';
    const testBannedPhone = `+${testBannedCountryCode}${testBannedMobile}`;
    const password = 'Password123!';
    const passwordHash = await bcrypt.hash(password, 10);

    const bannedUserRes = await db.query(`
      INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, password_hash, is_banned)
      VALUES ($1, $2, $3, 'Banned Test User', 'bannedtestuser', $4, TRUE)
      ON CONFLICT (phone_number) DO UPDATE SET is_banned = TRUE, password_hash = $4
      RETURNING id, is_banned;
    `, [testBannedCountryCode, testBannedMobile, testBannedPhone, passwordHash]);

    const bannedUserId = bannedUserRes.rows[0].id;
    console.log(`✅ Banned test user configured: ${bannedUserId} (is_banned: true)`);

    // 2. Setup an active (non-banned) test user
    const testActiveMobile = '9999977777';
    const testActiveCountryCode = '91';
    const testActivePhone = `+${testActiveCountryCode}${testActiveMobile}`;

    const activeUserRes = await db.query(`
      INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, password_hash, is_banned)
      VALUES ($1, $2, $3, 'Active Test User', 'activetestuser', $4, FALSE)
      ON CONFLICT (phone_number) DO UPDATE SET is_banned = FALSE, password_hash = $4
      RETURNING id, is_banned;
    `, [testActiveCountryCode, testActiveMobile, testActivePhone, passwordHash]);

    const activeUserId = activeUserRes.rows[0].id;
    console.log(`✅ Active test user configured: ${activeUserId} (is_banned: false)`);

    // --- TEST 1: Force Redis session eviction for banned user and test OTP Verify ---
    console.log('\n--- TEST 1: OTP Verify on Banned User with Evicted Redis Session ---');
    await redis.del(`user_active_session:${bannedUserId}`);
    await redis.del(`user:is_banned:${bannedUserId}`);

    // Mock an OTP in Redis for the banned user (key format: otp:${cleanCountryCode}${cleanMobile})
    const hashedOtp = await bcrypt.hash('123456', 10);
    await redis.set(`otp:${testBannedCountryCode}${testBannedMobile}`, hashedOtp, 'EX', 300);

    const otpRes = await fetch(`${baseUrl}/api/auth/otp/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        country_code: testBannedCountryCode,
        mobile: testBannedMobile,
        otp: '123456',
      }),
    });

    const otpBody = await otpRes.json();
    console.log(`HTTP Status: ${otpRes.status}`);
    console.log('Response Body:', otpBody);

    if (otpRes.status !== 403 || otpBody.error !== 'ACCOUNT_BANNED') {
      throw new Error(`FAIL: Expected 403 ACCOUNT_BANNED on OTP verify for banned user, got ${otpRes.status}`);
    }
    console.log('✅ TEST 1 PASSED: Banned user rejected with 403 ACCOUNT_BANNED on OTP verify after Redis eviction!');

    // --- TEST 2: Token Refresh on Banned User with Evicted Redis Session ---
    console.log('\n--- TEST 2: Token Refresh on Banned User with Evicted Redis Session ---');
    await redis.del(`user_active_session:${bannedUserId}`);
    await redis.del(`user:is_banned:${bannedUserId}`);

    const jti = 'test_jti_banned_' + Date.now();
    const sessionId = 'test_session_banned_' + Date.now();
    const bannedRefreshToken = jwt.sign({ id: bannedUserId, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '1h' });

    // Store active refresh token in Redis
    await redis.set(`refresh:${bannedUserId}:${jti}`, '1', 'EX', 3600);

    const refreshRes = await fetch(`${baseUrl}/api/auth/token/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        refreshToken: bannedRefreshToken,
      }),
    });

    const refreshBody = await refreshRes.json();
    console.log(`HTTP Status: ${refreshRes.status}`);
    console.log('Response Body:', refreshBody);

    if (refreshRes.status !== 403 || refreshBody.error !== 'ACCOUNT_BANNED') {
      throw new Error(`FAIL: Expected 403 ACCOUNT_BANNED on token refresh for banned user, got ${refreshRes.status}`);
    }
    console.log('✅ TEST 2 PASSED: Banned user rejected with 403 ACCOUNT_BANNED on token refresh!');

    // --- TEST 3: Password Login for Active User Unaffected ---
    console.log('\n--- TEST 3: Password Login for Active (Non-Banned) User ---');
    const loginRes = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        login: testActiveMobile,
        password: password,
      }),
    });

    const loginBody = await loginRes.json();
    console.log(`HTTP Status: ${loginRes.status}`);
    console.log('User fullName:', loginBody.user?.fullName);

    if (loginRes.status !== 200 || !loginBody.token) {
      throw new Error(`FAIL: Expected 200 with token for active user login, got ${loginRes.status}`);
    }
    console.log('✅ TEST 3 PASSED: Active user password login works normally!');

    // Mock an OTP in Redis for the active user (key format: otp:${cleanCountryCode}${cleanMobile})
    const activeHashedOtp = await bcrypt.hash('654321', 10);
    await redis.set(`otp:${testActiveCountryCode}${testActiveMobile}`, activeHashedOtp, 'EX', 300);

    const activeOtpRes = await fetch(`${baseUrl}/api/auth/otp/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        country_code: testActiveCountryCode,
        mobile: testActiveMobile,
        otp: '654321',
      }),
    });

    const activeOtpBody = await activeOtpRes.json();
    console.log(`HTTP Status: ${activeOtpRes.status}`);
    console.log('User fullName:', activeOtpBody.user?.fullName);

    if (activeOtpRes.status !== 200 || !activeOtpBody.token) {
      throw new Error(`FAIL: Expected 200 with token for active user OTP verify, got ${activeOtpRes.status}`);
    }
    console.log('✅ TEST 4 PASSED: Active user OTP verify works normally!');

    console.log('\n🎉 ALL BAN-CHECK HOTFIX TESTS PASSED 100%!');
  } catch (err) {
    console.error('❌ Test failed:', err.message);
    process.exit(1);
  } finally {
    if (server) server.close();
    await db.pool.end();
    process.exit(0);
  }
}

runHotfixTests();
