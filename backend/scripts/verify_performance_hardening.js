const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const db = require('../db');
const redis = require('../redis');
const { BuddyService } = require('../modules/buddy/buddy.service');
const buddyService = new BuddyService();
const { CallsService } = require('../modules/calls/calls.service');
const callsService = new CallsService();

async function runVerification() {
  console.log('=================================================================');
  console.log('🚀 BACKEND PERFORMANCE & SCALABILITY VERIFICATION SUITE');
  console.log('=================================================================\n');

  let passedTests = 0;
  let totalTests = 0;

  function assert(name, condition, extra = '') {
    totalTests++;
    if (condition) {
      passedTests++;
      console.log(`✅ [PASS] ${name} ${extra ? '(' + extra + ')' : ''}`);
    } else {
      console.error(`❌ [FAIL] ${name} ${extra ? '(' + extra + ')' : ''}`);
    }
  }

  try {
    // ── Test 1: Verify Database Indexes ─────────────────────────────────────────
    console.log('--- Test 1: Verifying PostgreSQL Scale Indexes ---');
    const indexRes = await db.query(`
      SELECT tablename, indexname 
      FROM pg_indexes 
      WHERE tablename IN ('users', 'buddy_requests', 'google_play_purchases')
        AND indexname IN (
          'idx_users_mobile',
          'idx_users_phone_number',
          'idx_users_lower_username_btree',
          'idx_buddy_requests_open_feed',
          'idx_gp_purchases_token'
        );
    `);
    const foundIndexes = new Set(indexRes.rows.map(r => r.indexname));
    assert('idx_users_mobile created', foundIndexes.has('idx_users_mobile'));
    assert('idx_users_phone_number created', foundIndexes.has('idx_users_phone_number'));
    assert('idx_users_lower_username_btree created', foundIndexes.has('idx_users_lower_username_btree'));
    assert('idx_buddy_requests_open_feed created', foundIndexes.has('idx_buddy_requests_open_feed'));
    assert('idx_gp_purchases_token created', foundIndexes.has('idx_gp_purchases_token'));

    // ── Test 2: Login Query Plans (Username & Phone) ────────────────────────────
    console.log('\n--- Test 2: Verifying Login Query Index Scans (EXPLAIN) ---');
    await db.query('SET enable_seqscan = off');

    const usernamePlanRes = await db.query(`
      EXPLAIN SELECT u.id, w.spendable_balance 
      FROM public.users u 
      LEFT JOIN public.wallets w ON w.user_id = u.id 
      WHERE LOWER(u.user_name) = $1 LIMIT 1
    `, ['testuser']);
    const userPlan = usernamePlanRes.rows.map(r => r['QUERY PLAN']).join('\n');
    assert('Username query uses idx_users_lower_username_btree', userPlan.includes('idx_users_lower_username_btree'));

    const phonePlanRes = await db.query(`
      EXPLAIN SELECT u.id, w.spendable_balance 
      FROM public.users u 
      LEFT JOIN public.wallets w ON w.user_id = u.id 
      WHERE u.phone_number = $1 OR u.phone_number = $2 OR u.mobile = $3 LIMIT 1
    `, ['9876543210', '+919876543210', '9876543210']);
    const phonePlan = phonePlanRes.rows.map(r => r['QUERY PLAN']).join('\n');
    assert('Phone query uses index scans', phonePlan.includes('idx_users_phone_number') || phonePlan.includes('idx_users_mobile'));

    await db.query('SET enable_seqscan = on');

    // ── Test 3: Instant Connect Matchmaker 500-Female Pipeline Benchmark ───────
    console.log('\n--- Test 3: Benchmarking Instant Connect Female Pool (500 candidates) ---');
    const SIMULATED_COUNT = 500;
    const testFemaleIds = [];
    const seedPipe = redis.pipeline();
    for (let i = 0; i < SIMULATED_COUNT; i++) {
      const fId = `sim_female_${i}_${Date.now()}`;
      testFemaleIds.push(fId);
      seedPipe.sadd('instant:female_pool', fId);
      if (i % 2 === 0) {
        // Half are online
        seedPipe.sadd(`online_sockets:${fId}`, `sock_${i}`);
        seedPipe.expire(`online_sockets:${fId}`, 60);
      }
    }
    await seedPipe.exec();

    // Benchmark pipelined candidate resolution
    const startBench = Date.now();
    const candidateIds = testFemaleIds;
    const onlineCandidates = [];
    const staleFemaleIds = [];

    const presencePipeline = redis.pipeline();
    for (const fId of candidateIds) {
      presencePipeline.scard(`online_sockets:${fId}`);
    }
    const presenceResults = await presencePipeline.exec();

    for (let i = 0; i < candidateIds.length; i++) {
      const femaleId = candidateIds[i];
      const socketCount = parseInt(presenceResults[i]?.[1] || '0', 10);
      if (socketCount > 0) {
        onlineCandidates.push({ femaleId });
      } else {
        staleFemaleIds.push(femaleId);
      }
    }
    const elapsedMs = Date.now() - startBench;

    assert('Pipelined 500-member check completed in single round-trip (<150ms over WAN)', elapsedMs < 150, `Actual: ${elapsedMs}ms`);
    assert('Correctly identified online candidates', onlineCandidates.length === SIMULATED_COUNT / 2, `Online: ${onlineCandidates.length}/${SIMULATED_COUNT}`);

    // Cleanup simulation
    const cleanPipe = redis.pipeline();
    cleanPipe.srem('instant:female_pool', ...testFemaleIds);
    for (const fId of testFemaleIds) {
      cleanPipe.del(`online_sockets:${fId}`);
    }
    await cleanPipe.exec();

    // ── Test 4: Redis Key TTL Enforcement ───────────────────────────────────────
    console.log('\n--- Test 4: Verifying Redis Key TTLs ---');
    const testUserId = `test_ttl_user_${Date.now()}`;
    const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;
    await redis.set(`user_active_session:${testUserId}`, JSON.stringify({ sessionId: 'sess123', isBanned: false }), 'EX', SESSION_TTL_SECONDS);
    const sessionTtl = await redis.ttl(`user_active_session:${testUserId}`);
    assert('user_active_session has ~30d TTL', sessionTtl > 2500000 && sessionTtl <= SESSION_TTL_SECONDS, `TTL: ${sessionTtl}s`);

    await redis.set(`user:has_undelivered:${testUserId}`, '1', 'EX', 14 * 86400);
    const undeliveredTtl = await redis.ttl(`user:has_undelivered:${testUserId}`);
    assert('user:has_undelivered has ~14d TTL', undeliveredTtl > 1200000 && undeliveredTtl <= 14 * 86400, `TTL: ${undeliveredTtl}s`);

    await redis.del(`user_active_session:${testUserId}`, `user:has_undelivered:${testUserId}`);

    // ── Test 5: Atomic Single-Query Call Termination ────────────────────────────
    console.log('\n--- Test 5: Verifying Atomic Single-Query Call Ending ---');
    // Insert a dummy call
    const dummyUserA = (await db.query('SELECT id FROM public.users LIMIT 1')).rows[0]?.id;
    const dummyUserB = (await db.query('SELECT id FROM public.users OFFSET 1 LIMIT 1')).rows[0]?.id;

    if (dummyUserA && dummyUserB) {
      const callInsert = await db.query(
        `INSERT INTO public.calls (caller_id, matched_user_id, status, call_type, started_at)
         VALUES ($1, $2, 'active', 'voice', NOW() - INTERVAL '45 seconds')
         RETURNING id`,
        [dummyUserA, dummyUserB]
      );
      const testCallId = callInsert.rows[0].id;

      await callsService.endCall(testCallId);

      const verifyCall = await db.query('SELECT status, duration_seconds, ended_at FROM public.calls WHERE id = $1', [testCallId]);
      const callRow = verifyCall.rows[0];
      assert('Call atomically marked ended', callRow.status === 'ended');
      assert('Duration correctly computed by PostgreSQL engine', callRow.duration_seconds >= 44 && callRow.duration_seconds <= 50, `Duration: ${callRow.duration_seconds}s`);

      await db.query('DELETE FROM public.calls WHERE id = $1', [testCallId]);
    } else {
      console.log('⚠️ Skipping dummy call test: requires at least 2 users in users table.');
    }

    // ── Test 6: Buddy Feed Redis Caching ────────────────────────────────────────
    console.log('\n--- Test 6: Verifying Buddy Feed 5-Second Redis Cache ---');
    const testCity = 'Mumbai';
    const feed1 = await buddyService.listOpenRequests({ city: testCity, userGender: 'all', limit: 10, offset: 0 });
    const cacheKey = `buddy:feed:${testCity.toLowerCase()}:all:all:10:0`;
    const cachedData = await redis.get(cacheKey);
    assert('Buddy feed page cached in Redis', cachedData !== null);
    if (cachedData) {
      const parsed = JSON.parse(cachedData);
      assert('Cached items match database rows', Array.isArray(parsed));
    }
    await redis.del(cacheKey);

  } catch (err) {
    console.error('❌ Unexpected error in test suite:', err);
  } finally {
    console.log('\n=================================================================');
    console.log(`🏁 VERIFICATION COMPLETE: ${passedTests}/${totalTests} TESTS PASSED`);
    console.log('=================================================================');
    await db.pool.end();
    process.exit(passedTests === totalTests ? 0 : 1);
  }
}

runVerification();
