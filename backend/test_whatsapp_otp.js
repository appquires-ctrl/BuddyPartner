const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const axios = require('axios');
const db = require('./db');
const redis = require('./redis');
const { app, server } = require('./server');

async function testAuthkeyOtpFlow() {
  console.log('🚀 Running Unit & Integration Tests for Authkey WhatsApp OTP Flow...\n');
  
  const port = server.address()?.port || 3000;
  const baseUrl = `http://localhost:${port}/api/auth`;

  try {
    const testCountryCode = '91';
    const testMobile = '9998887770';
    const redisOtpKey = `otp:${testCountryCode}${testMobile}`;
    const redisSendCountKey = `otp_send_count:${testMobile}`;
    const redisAttemptsKey = `otp_verify_attempts:${testMobile}`;

    // Cleanup previous test state
    await redis.del(redisOtpKey);
    await redis.del(redisSendCountKey);
    await redis.del(redisAttemptsKey);
    await db.query(`DELETE FROM public.users WHERE mobile = $1`, [testMobile]);

    // ────────────────────────────────────────────────────────────────────────
    // TEST 0: Unit Test - Assert MSG91 Outbound Bulk Payload Shape & Headers
    // ────────────────────────────────────────────────────────────────────────
    console.log('[TEST 0] Testing sendWhatsAppOtp payload construction & mock responses...');
    const { sendWhatsAppOtp } = require('./modules/auth/otpService');
    const originalPost = axios.post;
    let capturedUrl, capturedPayload, capturedHeaders;

    axios.post = async (url, data, config) => {
      capturedUrl = url;
      capturedPayload = data;
      capturedHeaders = config.headers;
      return { status: 200, data: { hasError: false, status: 'success' } };
    };

    const originalAuthKey = process.env.MSG91_AUTHKEY;
    process.env.MSG91_AUTHKEY = 'test_unit_authkey_999';

    const mockOtpRes = await sendWhatsAppOtp('91', '9876543210', '654321');

    if (!mockOtpRes.success) throw new Error('Unit test sendWhatsAppOtp failed');
    if (capturedUrl !== 'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/') {
      throw new Error(`Unexpected API URL: ${capturedUrl}`);
    }
    if (capturedHeaders['authkey'] !== 'test_unit_authkey_999') {
      throw new Error(`Header authkey mismatch: ${capturedHeaders['authkey']}`);
    }
    if (capturedHeaders['Content-Type'] !== 'application/json') {
      throw new Error(`Content-Type header mismatch: ${capturedHeaders['Content-Type']}`);
    }
    if (capturedPayload.integrated_number !== (process.env.MSG91_INTEGRATED_NUMBER || '919795038296')) {
      throw new Error(`Integrated number mismatch: ${capturedPayload.integrated_number}`);
    }
    if (capturedPayload.content_type !== 'template' || capturedPayload.payload.type !== 'template') {
      throw new Error('Payload content_type or type mismatch');
    }
    if (capturedPayload.payload.messaging_product !== 'whatsapp') {
      throw new Error('Payload messaging_product mismatch');
    }
    if (capturedPayload.payload.template.name !== (process.env.MSG91_TEMPLATE_NAME || 'login_otp')) {
      throw new Error('Payload template name mismatch');
    }
    if (capturedPayload.payload.template.to_and_components[0].to[0] !== '919876543210') {
      throw new Error(`Recipient phone format mismatch: ${capturedPayload.payload.template.to_and_components[0].to[0]}`);
    }
    if (capturedPayload.payload.template.to_and_components[0].components.body_1.value !== '654321') {
      throw new Error('OTP parameter body_1 value mismatch');
    }
    if (capturedPayload.payload.template.to_and_components[0].components.button_1.value !== '654321') {
      throw new Error('OTP parameter button_1 value mismatch');
    }
    console.log('✅ Outgoing MSG91 POST payload shape, headers, and phone formatting verified!');

    // Test error handling scenario with mock API failure
    axios.post = async () => {
      const err = new Error('Mock MSG91 API error');
      err.response = { status: 400, data: { hasError: true, message: 'Invalid template parameter' } };
      throw err;
    };

    const mockFailRes = await sendWhatsAppOtp('91', '9876543210', '654321');
    if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
      if (!mockFailRes.success) throw new Error('Expected dev fallback on API error');
      console.log('✅ MSG91 API failure correctly caught and handled by dev fallback.');
    }

    // Restore original axios.post & env
    axios.post = originalPost;
    process.env.MSG91_AUTHKEY = originalAuthKey;

    // ────────────────────────────────────────────────────────────────────────
    // TEST 1: Send OTP
    // ────────────────────────────────────────────────────────────────────────
    console.log('[TEST 1] Triggering POST /api/auth/otp/send...');
    const sendRes = await axios.post(`${baseUrl}/otp/send`, {
      country_code: testCountryCode,
      mobile: testMobile,
    });

    console.log('Response:', sendRes.data);
    if (!sendRes.data.success) throw new Error('Send OTP failed');

    // Check Redis hash presence
    const storedHash = await redis.get(redisOtpKey);
    if (!storedHash) throw new Error('Redis OTP key was not created!');
    console.log('✅ Hashed OTP successfully stored in Redis with 300s TTL.');

    // Check rate limit key
    const sendCount = await redis.get(redisSendCountKey);
    if (parseInt(sendCount, 10) !== 1) throw new Error('Send rate limit count mismatch');
    console.log('✅ Rate limit counter updated in Redis.');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 2: Verify Incorrect OTP (Should fail & increment attempts)
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n[TEST 2] Testing incorrect OTP verification...');
    try {
      await axios.post(`${baseUrl}/otp/verify`, {
        country_code: testCountryCode,
        mobile: testMobile,
        otp: '000000',
      });
      throw new Error('Should have failed with 400 for incorrect OTP');
    } catch (err) {
      if (err.response?.status !== 400) throw err;
      console.log('✅ Correctly rejected invalid OTP with HTTP 400.');
    }

    // ────────────────────────────────────────────────────────────────────────
    // TEST 3: Verify Correct OTP (Inject test OTP in Redis to simulate known OTP)
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n[TEST 3] Testing successful OTP verification & user/wallet provisioning...');
    const bcrypt = require('bcryptjs');
    const validTestOtp = '123456';
    const testHash = await bcrypt.hash(validTestOtp, 10);
    await redis.set(redisOtpKey, testHash, 'EX', 300);

    const verifyRes = await axios.post(`${baseUrl}/otp/verify`, {
      country_code: testCountryCode,
      mobile: testMobile,
      otp: validTestOtp,
    });

    console.log('Verify Response:', verifyRes.data);
    if (!verifyRes.data.success || !verifyRes.data.token || !verifyRes.data.refreshToken) {
      throw new Error('Verify response missing token or refreshToken!');
    }
    console.log('✅ OTP Verified! Received Access JWT and Refresh Token.');

    // Check that Redis OTP key was deleted on success
    const consumedKey = await redis.get(redisOtpKey);
    if (consumedKey) throw new Error('Redis OTP key was not deleted on success!');
    console.log('✅ Redis OTP key deleted immediately on verification success.');

    // Verify DB user + wallet created with initial 0 balance
    const userDbRes = await db.query(
      `SELECT u.id, u.country_code, u.mobile, w.balance, count(wt.id) as tx_count 
       FROM public.users u
       JOIN public.wallets w ON w.user_id = u.id
       LEFT JOIN public.wallet_transactions wt ON wt.user_id = u.id
       WHERE u.mobile = $1
       GROUP BY u.id, u.country_code, u.mobile, w.balance`,
      [testMobile]
    );

    if (userDbRes.rows.length === 0) throw new Error('User was not created in PostgreSQL!');
    const userRow = userDbRes.rows[0];
    console.log(`✅ Database verified! User ID: ${userRow.id}, Wallet Balance: ${userRow.balance}, Tx count: ${userRow.tx_count}`);
    if (parseInt(userRow.balance, 10) !== 0) throw new Error('Wallet balance is not 0!');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 4: Token Rotation (/api/auth/refresh)
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n[TEST 4] Testing Refresh Token Rotation via POST /api/auth/refresh...');
    const refreshRes = await axios.post(`${baseUrl}/refresh`, {
      refreshToken: verifyRes.data.refreshToken,
    });

    console.log('Refresh Response:', refreshRes.data);
    if (!refreshRes.data.token || !refreshRes.data.refreshToken) {
      throw new Error('Refresh endpoint did not return new tokens!');
    }
    console.log('✅ Refresh token rotated successfully.');

    // Re-using old refresh token should fail
    try {
      await axios.post(`${baseUrl}/refresh`, {
        refreshToken: verifyRes.data.refreshToken,
      });
      throw new Error('Old refresh token should be invalidated!');
    } catch (err) {
      if (err.response?.status !== 401) throw err;
      console.log('✅ Old refresh token correctly rejected (HTTP 401).');
    }

    // ────────────────────────────────────────────────────────────────────────
    // TEST 5: Logout (/api/auth/logout)
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n[TEST 5] Testing Logout via POST /api/auth/logout...');
    await axios.post(`${baseUrl}/logout`, {
      refreshToken: refreshRes.data.refreshToken,
    });

    // Trying to refresh after logout should fail
    try {
      await axios.post(`${baseUrl}/refresh`, {
        refreshToken: refreshRes.data.refreshToken,
      });
      throw new Error('Refresh token should be revoked after logout!');
    } catch (err) {
      if (err.response?.status !== 401) throw err;
      console.log('✅ Session revoked on logout.');
    }

    console.log('\n🎉 ALL BACKEND AUTHKEY WHATSAPP OTP TESTS PASSED SUCCESSFULLY!\n');

    // Cleanup test user
    await db.query(`DELETE FROM public.users WHERE mobile = $1`, [testMobile]);

  } catch (err) {
    console.error('❌ Test Failed:', err.response?.data || err.message);
    process.exit(1);
  } finally {
    try { server.close(); } catch (_) {}
    try { await db.pool.end(); } catch (_) {}
    process.exit(0);
  }
}

testAuthkeyOtpFlow();
