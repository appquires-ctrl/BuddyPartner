const assert = require('assert');
const path = require('path');
const http = require('http');
const express = require('express');
const jwt = require('jsonwebtoken');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');
const axios = require('axios');
const authRoutes = require('./modules/auth/auth.routes');

async function runSearchTests() {
  console.log('🧪 Starting User Search Backend & Concurrency Test Suite...\n');

  const timestamp = Date.now().toString().slice(-6);
  const prefix = 'srch_' + timestamp;

  const testMobileSearcher = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobileUser1 = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobileUser2 = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobileBanned = '88888' + Math.floor(10000 + Math.random() * 90000);
  const testMobileOther = '88888' + Math.floor(10000 + Math.random() * 90000);

  const usernameSearcher = `${prefix}_self`;
  const username1 = `${prefix}_alex`;
  const username2 = `${prefix}_bob`;
  const usernameBanned = `${prefix}_banned`;
  const usernameOther = `diff_${timestamp}_dan`;

  let server;
  let baseUrl;
  let searcherId;
  let searcherToken;

  const allMobiles = [testMobileSearcher, testMobileUser1, testMobileUser2, testMobileBanned, testMobileOther];

  try {
    // 1. Seed Test Users
    console.log('▶ Step 1: Seeding test database records');
    const rSearcher = await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
       VALUES ('91', $1, $2, 'Searcher User', $3) RETURNING id`,
      [testMobileSearcher, `+91${testMobileSearcher}`, usernameSearcher]
    );
    searcherId = rSearcher.rows[0].id;

    await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, gender, avatar_seed, is_telecaller) 
       VALUES ('91', $1, $2, 'Alex Superstar', $3, 'Male', 'alex_seed', true)`,
      [testMobileUser1, `+91${testMobileUser1}`, username1]
    );

    await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, gender, avatar_seed, is_telecaller) 
       VALUES ('91', $1, $2, 'Bob Superstar', $3, 'Male', 'bob_seed', false)`,
      [testMobileUser2, `+91${testMobileUser2}`, username2]
    );

    await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name, is_banned) 
       VALUES ('91', $1, $2, 'Banned User', $3, TRUE)`,
      [testMobileBanned, `+91${testMobileBanned}`, usernameBanned]
    );

    await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
       VALUES ('91', $1, $2, 'Dan Different', $3)`,
      [testMobileOther, `+91${testMobileOther}`, usernameOther]
    );
    console.log('  ✅ Seeded searcher, target matching users, banned user, and distinct user.');

    // 2. Setup Server
    console.log('\n▶ Step 2: Spinning up ephemeral Express HTTP server');
    const app = express();
    app.use(express.json());
    app.use('/api/users', authRoutes);
    app.use('/api/auth', authRoutes);

    server = http.createServer(app);
    await new Promise((resolve) => server.listen(0, resolve));
    const port = server.address().port;
    baseUrl = `http://127.0.0.1:${port}`;
    console.log(`  ✅ Server listening on ${baseUrl}`);

    const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    searcherToken = jwt.sign({ id: searcherId, mobile: testMobileSearcher }, JWT_SECRET);

    // 3. Test Query Validation (< 2 characters)
    console.log('\n▶ Step 3: Query validation (minimum length)');
    try {
      await axios.get(`${baseUrl}/api/users/search`, {
        headers: { Authorization: `Bearer ${searcherToken}` },
        params: { query: 's' },
      });
      assert.fail('Expected 400 for query length < 2');
    } catch (err) {
      assert.strictEqual(err.response.status, 400);
      assert.strictEqual(err.response.data.error, 'INVALID_QUERY');
      console.log('  ✅ Single character query "s" correctly rejected with 400 INVALID_QUERY');
    }

    // 4. Test Prefix Matching & Exclusions
    console.log('\n▶ Step 4: Prefix matching & exclusions (banned & self excluded)');
    const resSearch = await axios.get(`${baseUrl}/api/users/search`, {
      headers: { Authorization: `Bearer ${searcherToken}` },
      params: { query: prefix },
    });
    assert.strictEqual(resSearch.status, 200);
    assert.strictEqual(resSearch.data.success, true);
    const users = resSearch.data.users;
    console.log(`  ✅ Query "${prefix}" returned ${users.length} users:`);
    users.forEach((u) => console.log(`     - @${u.userName} (${u.fullName})`));

    // Must find alex and bob
    const foundUsernames = users.map((u) => u.userName);
    assert.ok(foundUsernames.includes(username1), `Must include ${username1}`);
    assert.ok(foundUsernames.includes(username2), `Must include ${username2}`);

    // Must NOT find self (searcherId)
    assert.ok(!foundUsernames.includes(usernameSearcher), 'Must exclude self from search results');

    // Must NOT find banned user
    assert.ok(!foundUsernames.includes(usernameBanned), 'Must exclude banned users');

    // Must NOT find different prefix
    assert.ok(!foundUsernames.includes(usernameOther), 'Must exclude non-matching prefix');

    // 5. Test Sensitive Fields Omission
    console.log('\n▶ Step 5: Security audit — sensitive fields omission');
    users.forEach((u) => {
      assert.strictEqual(u.phoneNumber, undefined, 'Sensitive field phoneNumber must not be present');
      assert.strictEqual(u.mobile, undefined, 'Sensitive field mobile must not be present');
      assert.strictEqual(u.countryCode, undefined, 'Sensitive field countryCode must not be present');
      assert.strictEqual(u.balance, undefined, 'Sensitive field balance must not be present');
      assert.strictEqual(u.email, undefined, 'Sensitive field email must not be present');
      assert.ok(u.id && u.fullName && u.userName !== undefined, 'Public fields must be present');
    });
    console.log('  ✅ Verified: Zero sensitive fields exposed in search payload');

    // 6. Test Query with Leading '@'
    console.log('\n▶ Step 6: Handling leading "@" in search query');
    const resAt = await axios.get(`${baseUrl}/api/users/search`, {
      headers: { Authorization: `Bearer ${searcherToken}` },
      params: { query: `@${prefix}` },
    });
    assert.strictEqual(resAt.status, 200);
    assert.strictEqual(resAt.data.users.length, users.length);
    console.log('  ✅ Leading "@" stripped cleanly; returned matching results');

    // 7. Test Hard Limit Capping & Response Truncation
    console.log('\n▶ Step 7: Server-side limit capping & array truncation (max 25)');
    const capPrefix = 'cap_' + timestamp;
    const capMobiles = [];
    const capInserts = [];
    for (let i = 0; i < 30; i++) {
      const mob = '7777' + Math.floor(100000 + Math.random() * 900000);
      capMobiles.push(mob);
      allMobiles.push(mob);
      capInserts.push(
        db.query(
          `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
           VALUES ('91', $1, $2, $3, $4)`,
          [mob, `+91${mob}`, `Cap User ${i}`, `${capPrefix}_u${i}`]
        )
      );
    }
    await Promise.all(capInserts);

    const resCapped = await axios.get(`${baseUrl}/api/users/search`, {
      headers: { Authorization: `Bearer ${searcherToken}` },
      params: { query: capPrefix, limit: 100 },
    });
    assert.strictEqual(resCapped.status, 200);
    assert.strictEqual(resCapped.data.users.length, 25, 'Search response array MUST be hard capped at 25 results even when client requests limit=100');
    console.log(`  ✅ Requested limit 100 on 30 matching users; response strictly truncated to exactly 25 items (cap verified).`);

    // 7b. Test Canonical Route Enforcement
    console.log('\n▶ Step 7b: Canonical route enforcement (reject duplicate /api/auth/search)');
    try {
      await axios.get(`${baseUrl}/api/auth/search`, {
        headers: { Authorization: `Bearer ${searcherToken}` },
        params: { query: prefix },
      });
      assert.fail('Expected 404 for /api/auth/search');
    } catch (err) {
      assert.strictEqual(err.response?.status, 404);
      assert.strictEqual(err.response?.data?.error, 'NOT_FOUND');
      console.log('  ✅ /api/auth/search correctly rejected with 404 NOT_FOUND (canonical /api/users/search enforced)');
    }

    // 7c. Test User-Scoped Cache Isolation
    console.log('\n▶ Step 7c: User-scoped Redis cache isolation');
    const isoPrefix = 'iso_' + timestamp;
    const testMobileUserC = '88888' + Math.floor(10000 + Math.random() * 90000);
    const testMobileUserD = '88888' + Math.floor(10000 + Math.random() * 90000);
    allMobiles.push(testMobileUserC, testMobileUserD);

    const rUserC = await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
       VALUES ('91', $1, $2, 'User C', $3) RETURNING id`,
      [testMobileUserC, `+91${testMobileUserC}`, `${isoPrefix}_userc`]
    );
    const rUserD = await db.query(
      `INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name) 
       VALUES ('91', $1, $2, 'User D', $3) RETURNING id`,
      [testMobileUserD, `+91${testMobileUserD}`, `${isoPrefix}_userd`]
    );
    const userCToken = jwt.sign({ id: rUserC.rows[0].id, mobile: testMobileUserC }, JWT_SECRET);

    // Searcher searches for isoPrefix (caches under searcherId)
    const resSearcher = await axios.get(`${baseUrl}/api/users/search`, {
      headers: { Authorization: `Bearer ${searcherToken}` },
      params: { query: isoPrefix },
    });
    assert.ok(resSearcher.data.users.some((u) => u.userName === `${isoPrefix}_userc`), 'Searcher must see User C');
    assert.ok(resSearcher.data.users.some((u) => u.userName === `${isoPrefix}_userd`), 'Searcher must see User D');

    // User C searches for the exact same query within the cache window
    const resUserC = await axios.get(`${baseUrl}/api/users/search`, {
      headers: { Authorization: `Bearer ${userCToken}` },
      params: { query: isoPrefix },
    });
    assert.ok(resUserC.data.users.some((u) => u.userName === `${isoPrefix}_userd`), 'User C must see User D');
    assert.ok(
      !resUserC.data.users.some((u) => u.userName === `${isoPrefix}_userc`),
      'User C must NEVER see themselves in their own search results even if another user just cached identical query'
    );
    console.log('  ✅ User-scoped cache isolation verified: User C does NOT see themselves when searching identical query');

    // 8. Test Rate Limiter (30 requests/minute per user)
    console.log('\n▶ Step 8: Rate limiter stress test (30 requests/min limit)');
    let rateLimitTriggered = false;
    const burstRequests = [];
    for (let i = 0; i < 35; i++) {
      burstRequests.push(
        axios
          .get(`${baseUrl}/api/users/search`, {
            headers: { Authorization: `Bearer ${searcherToken}` },
            params: { query: `${prefix}_burst_${i}` },
          })
          .catch((err) => err.response)
      );
    }
    const burstResponses = await Promise.all(burstRequests);
    const statuses = burstResponses.map((r) => r.status);
    const count429 = statuses.filter((s) => s === 429).length;
    console.log(`  📊 Burst test: ${statuses.filter((s) => s === 200).length} OK, ${count429} Rate Limited (429)`);
    assert.ok(count429 > 0, 'Rate limiter must return HTTP 429 when burst exceeds 30 requests/min');
    console.log('  ✅ Rate limiter correctly kicked in and returned 429 under rapid requests');

    console.log('\n=========================================');
    console.log(' ALL USER SEARCH FUNCTIONAL & SECURITY TESTS PASSED!');
    console.log('=========================================');
  } catch (err) {
    console.error('❌ Search test suite failed:', err.response?.data || err);
    process.exit(1);
  } finally {
    if (server) {
      server.close();
    }
    console.log('\n🧹 Cleaning up test database records...');
    await db.query(`DELETE FROM public.users WHERE mobile = ANY($1::TEXT[])`, [allMobiles]);
    console.log('  ✅ Cleaned up all test records.');
    process.exit(0);
  }
}

runSearchTests();
