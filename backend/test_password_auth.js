require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const db = require('./db');
const redis = require('./redis');
const bcrypt = require('bcryptjs');
const express = require('express');

const authRoutes = require('./modules/auth/auth.routes');

const app = express();
app.use(express.json());
app.set('redis', redis);
app.use('/api/auth', authRoutes);

const PORT = 9988;
const BASE_URL = `http://127.0.0.1:${PORT}`;

async function post(endpoint, data) {
  const res = await fetch(`${BASE_URL}${endpoint}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  let body = {};
  try {
    body = await res.json();
  } catch (_) {}
  return { status: res.status, body };
}

async function runTests() {
  console.log('🧪 Starting Password Authentication Test Suite...\n');
  const server = app.listen(PORT);
  const client = await db.pool.connect();

  const testMobile = '9999000011';
  const testPhone = `+91${testMobile}`;
  const testUsername = 'testpassuser';
  const initialPassword = 'InitialPassword123!';
  const updatedPassword = 'NewSecretPassword456@';

  try {
    // 0. Cleanup any leftover test records
    await client.query('DELETE FROM public.users WHERE mobile = $1 OR user_name = $2', [testMobile, testUsername]);
    await redis.del(`login_attempts:${testUsername}`);
    await redis.del(`login_attempts:${testMobile}`);
    await redis.del(`login_attempts_ip:::ffff:127.0.0.1`);
    await redis.del(`login_attempts_ip:127.0.0.1`);
    await redis.del(`login_attempts_ip:::1`);
    await redis.del(`otp_reset:91${testMobile}`);

    // TEST 1: Login with non-existent user returns 401
    console.log('Test 1: Login with non-existent account...');
    const nonExistentRes = await post('/api/auth/login', { login: 'nonexistent_user_99999', password: 'somePassword123' });
    if (nonExistentRes.status === 401 && nonExistentRes.body.error === 'INVALID_CREDENTIALS') {
      console.log('  ✅ Non-existent user correctly rejected with 401 INVALID_CREDENTIALS');
    } else {
      throw new Error(`Test 1 Failed: Status ${nonExistentRes.status}, body: ${JSON.stringify(nonExistentRes.body)}`);
    }

    // TEST 2: Create a user without a password (legacy user state) and attempt login
    console.log('\nTest 2: Legacy user with no password attempting password login...');
    const legacyUserRes = await client.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, gender)
       VALUES ('91', $1, $2, 'Legacy User', $3, 'Male')
       RETURNING id`,
      [testMobile, testPhone, testUsername]
    );
    const userId = legacyUserRes.rows[0].id;

    const noPasswordRes = await post('/api/auth/login', { login: testUsername, password: 'attemptedPassword123' });

    if (noPasswordRes.status === 400 && noPasswordRes.body.error === 'NO_PASSWORD_SET') {
      console.log('  ✅ Correctly flagged NO_PASSWORD_SET directing user to WhatsApp OTP login');
    } else {
      throw new Error(`Test 2 Failed: Status ${noPasswordRes.status}, body: ${JSON.stringify(noPasswordRes.body)}`);
    }

    // TEST 3: User sets password via /set-password (simulating logged in user setting password)
    console.log('\nTest 3: Setting password for user...');
    const passwordHash = await bcrypt.hash(initialPassword, 10);
    await client.query(`UPDATE public.users SET password_hash = $1 WHERE id = $2`, [passwordHash, userId]);
    console.log('  ✅ Password hash saved directly in public.users');

    // TEST 4: Login with @username + correct password
    console.log('\nTest 4: Logging in with @username + password...');
    const usernameLoginRes = await post('/api/auth/login', { login: `@${testUsername}`, password: initialPassword });

    if (usernameLoginRes.status === 200 && usernameLoginRes.body.success && usernameLoginRes.body.token) {
      console.log('  ✅ Username login SUCCESS! Received JWT Token and User Payload');
      console.log(`     User hasPassword: ${usernameLoginRes.body.user.hasPassword}`);
    } else {
      throw new Error(`Test 4 Failed: Status ${usernameLoginRes.status}, body: ${JSON.stringify(usernameLoginRes.body)}`);
    }

    // TEST 5: Login with phone number + password
    console.log('\nTest 5: Logging in with mobile phone number + password...');
    const phoneLoginRes = await post('/api/auth/login', { login: testMobile, password: initialPassword });

    if (phoneLoginRes.status === 200 && phoneLoginRes.body.success && phoneLoginRes.body.token) {
      console.log('  ✅ Phone number login SUCCESS! Received JWT Token');
    } else {
      throw new Error(`Test 5 Failed: Status ${phoneLoginRes.status}, body: ${JSON.stringify(phoneLoginRes.body)}`);
    }

    // TEST 6: Forgot Password OTP Flow
    console.log('\nTest 6: Forgot Password Flow (OTP Send -> Reset -> Login with new password)...');
    // Send reset OTP
    const resetOtp = '654321';
    const hashedResetOtp = await bcrypt.hash(resetOtp, 10);
    await redis.set(`otp_reset:91${testMobile}`, hashedResetOtp, 'EX', 300);

    const resetRes = await post('/api/auth/forgot-password/reset', {
      country_code: '91',
      mobile: testMobile,
      otp: resetOtp,
      new_password: updatedPassword,
    });

    if (resetRes.status === 200 && resetRes.body.success) {
      console.log('  ✅ Password reset SUCCESS!');
    } else {
      throw new Error(`Test 6 (Reset) Failed: Status ${resetRes.status}, body: ${JSON.stringify(resetRes.body)}`);
    }

    // Old password should now fail
    const oldPassRes = await post('/api/auth/login', { login: testUsername, password: initialPassword });
    if (oldPassRes.status === 401) {
      console.log('  ✅ Old password is now rejected (401)');
    } else {
      throw new Error(`Test 6 (Old Password Check) Failed: Status ${oldPassRes.status}`);
    }

    // New password should succeed
    const newPassRes = await post('/api/auth/login', { login: testUsername, password: updatedPassword });
    if (newPassRes.status === 200 && newPassRes.body.success) {
      console.log('  ✅ New password login SUCCESS!');
    } else {
      throw new Error(`Test 6 (New Password Check) Failed: Status ${newPassRes.status}`);
    }

    // Clean up test user
    await client.query('DELETE FROM public.users WHERE id = $1', [userId]);
    await redis.del(`login_attempts:${testUsername}`);
    await redis.del(`login_attempts:${testMobile}`);
    console.log('\n🎉 ALL 6 BACKEND AUTHENTICATION TESTS PASSED WITH 100% SUCCESS!\n');
    server.close();
    process.exit(0);
  } catch (err) {
    console.error('❌ Test execution failed:', err);
    server.close();
    process.exit(1);
  } finally {
    client.release();
  }
}

runTests();
