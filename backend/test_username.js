const assert = require('assert');
const path = require('path');
const http = require('http');
const express = require('express');
const jwt = require('jsonwebtoken');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');
const axios = require('axios');
const authRoutes = require('./modules/auth/auth.routes');

async function runTests() {
  console.log('🧪 Starting Unique Username Backend Unit & Integration Tests...\n');

  const testUsernameAvailable = 'avail_' + Date.now().toString().slice(-6);
  const testUsernameTaken = 'taken_' + Date.now().toString().slice(-6);
  const testMobile1 = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobile2 = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobile3 = '88888' + Math.floor(10000 + Math.random() * 90000);

  let server;
  let baseUrl;
  let testUserId1;
  let testUserId2;
  let authToken1;
  let authToken2;

  try {
    // 1. Direct DB insertion of a user with testUsernameTaken
    console.log('▶ Test 1: Seed a test user with a specific username');
    const seedRes1 = await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
       VALUES ('91', $1, $2, 'Taken User', $3) 
       RETURNING id, user_name`,
      [testMobile1, `+91${testMobile1}`, testUsernameTaken]
    );
    testUserId1 = seedRes1.rows[0].id;
    console.log(`  ✅ Seeded user ${testUserId1} with username: ${testUsernameTaken}`);

    const seedRes2 = await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name) 
       VALUES ('91', $1, $2, 'Second User') 
       RETURNING id`,
      [testMobile2, `+91${testMobile2}`]
    );
    testUserId2 = seedRes2.rows[0].id;
    console.log(`  ✅ Seeded user ${testUserId2} without username`);

    // 2. Test DB Unique Constraint on LOWER(user_name)
    console.log('\n▶ Test 2: Case-insensitive unique index collision in PostgreSQL (23505)');
    let collisionCaught = false;
    try {
      await db.query(
        `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
         VALUES ('91', $1, $2, 'Collision User', $3)`,
        [testMobile3, `+91${testMobile3}`, testUsernameTaken.toUpperCase()]
      );
    } catch (dbErr) {
      if (dbErr.code === '23505' && (dbErr.constraint === 'idx_users_user_name_lower' || (dbErr.detail && dbErr.detail.includes('user_name')))) {
        collisionCaught = true;
        console.log(`  ✅ Caught unique constraint violation 23505 specifically on index idx_users_user_name_lower`);
      } else {
        throw dbErr;
      }
    }
    assert.strictEqual(collisionCaught, true, 'Unique constraint should reject case-insensitive duplicate username');

    // 3. Setup Express test server for real HTTP endpoint testing
    console.log('\n▶ Test 3: Spin up HTTP server & test Express endpoints');
    const app = express();
    app.use(express.json());
    app.use('/api/auth', authRoutes);

    server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const port = server.address().port;
    baseUrl = `http://127.0.0.1:${port}`;
    console.log(`  ✅ Ephemeral test server listening on ${baseUrl}`);

    const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    authToken1 = jwt.sign({ id: testUserId1, mobile: testMobile1 }, JWT_SECRET);
    authToken2 = jwt.sign({ id: testUserId2, mobile: testMobile2 }, JWT_SECRET);

    // 4. Test GET /api/auth/username-available
    console.log('\n▶ Test 4: HTTP GET /api/auth/username-available');
    
    // 4a. Available username
    const resAvail = await axios.get(`${baseUrl}/api/auth/username-available`, {
      params: { user_name: testUsernameAvailable },
    });
    assert.strictEqual(resAvail.status, 200);
    assert.strictEqual(resAvail.data.available, true);
    console.log(`  ✅ Available username "${testUsernameAvailable}" -> available: true`);

    // 4b. Taken username (case-insensitive)
    const resTaken = await axios.get(`${baseUrl}/api/auth/username-available`, {
      params: { user_name: testUsernameTaken.toUpperCase() },
    });
    assert.strictEqual(resTaken.status, 200);
    assert.strictEqual(resTaken.data.available, false);
    assert.strictEqual(resTaken.data.message, 'it already exist fix it');
    console.log(`  ✅ Taken username "${testUsernameTaken.toUpperCase()}" -> available: false ("it already exist fix it")`);

    // 4c. Reserved word check
    const resReserved = await axios.get(`${baseUrl}/api/auth/username-available`, {
      params: { user_name: 'admin' },
    });
    assert.strictEqual(resReserved.status, 200);
    assert.strictEqual(resReserved.data.available, false);
    assert.strictEqual(resReserved.data.message, 'it already exist fix it');
    console.log('  ✅ Reserved word "admin" -> available: false ("it already exist fix it")');

    // 4d. Invalid format (too short)
    try {
      await axios.get(`${baseUrl}/api/auth/username-available`, {
        params: { user_name: 'ab' },
      });
      assert.fail('Expected 400 for short username');
    } catch (err) {
      assert.strictEqual(err.response.status, 400);
      assert.strictEqual(err.response.data.error, 'INVALID_FORMAT');
      console.log('  ✅ Short username "ab" -> 400 INVALID_FORMAT');
    }

    // 4e. Invalid characters
    try {
      await axios.get(`${baseUrl}/api/auth/username-available`, {
        params: { user_name: 'user@name' },
      });
      assert.fail('Expected 400 for invalid characters');
    } catch (err) {
      assert.strictEqual(err.response.status, 400);
      assert.strictEqual(err.response.data.error, 'INVALID_FORMAT');
      console.log('  ✅ Invalid characters "user@name" -> 400 INVALID_FORMAT');
    }

    // 5. Test POST /api/auth/profile
    console.log('\n▶ Test 5: HTTP POST /api/auth/profile registration handling');

    // 5a. Profile update with already taken username -> 409
    try {
      await axios.post(
        `${baseUrl}/api/auth/profile`,
        {
          fullName: 'Second User',
          userName: testUsernameTaken,
          dob: '2000-01-01',
          gender: 'Male',
          language: 'English',
        },
        {
          headers: { Authorization: `Bearer ${authToken2}` },
        }
      );
      assert.fail('Expected 409 for taken username');
    } catch (err) {
      assert.strictEqual(err.response.status, 409);
      assert.strictEqual(err.response.data.error, 'USERNAME_TAKEN');
      assert.strictEqual(err.response.data.message, 'it already exist fix it');
      console.log('  ✅ Setting taken username returns 409 { error: "USERNAME_TAKEN", message: "it already exist fix it" }');
    }

    // 5b. Profile update with valid unique username -> 200 and returns user object
    const resProfile = await axios.post(
      `${baseUrl}/api/auth/profile`,
      {
        fullName: 'Second User',
        userName: testUsernameAvailable,
        dob: '2000-01-01',
        gender: 'Male',
        language: 'English',
      },
      {
        headers: { Authorization: `Bearer ${authToken2}` },
      }
    );
    assert.strictEqual(resProfile.status, 200);
    assert.strictEqual(resProfile.data.success, true);
    assert.ok(resProfile.data.user, 'Profile response must contain user object');
    assert.strictEqual(resProfile.data.user.userName, testUsernameAvailable);
    console.log(`  ✅ Successfully updated profile with username "${testUsernameAvailable}" and received user object`);

    // 5c. Test GET /api/auth/me returns user_name
    console.log('\n▶ Test 6: HTTP GET /api/auth/me returns userName');
    const resMe = await axios.get(`${baseUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${authToken2}` },
    });
    assert.strictEqual(resMe.status, 200);
    assert.strictEqual(resMe.data.user.userName, testUsernameAvailable);
    console.log(`  ✅ GET /api/auth/me returned userName: ${resMe.data.user.userName}`);

    console.log('\n=========================================');
    console.log(' ALL USERNAME DATABASE, HTTP & ROUTE TESTS PASSED!');
    console.log('=========================================');
  } catch (err) {
    console.error('❌ Test failed:', err.response?.data || err.message);
    process.exit(1);
  } finally {
    if (server) {
      server.close();
    }
    console.log('\n🧹 Cleaning up test database records...');
    if (testMobile1 && testMobile2) {
      await db.query(`DELETE FROM public.users WHERE mobile IN ($1, $2, $3)`, [testMobile1, testMobile2, testMobile3]);
    }
    console.log('  ✅ Test records cleaned up.');
    process.exit(0);
  }
}

runTests();
