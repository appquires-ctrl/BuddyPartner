require('dotenv').config();
const db = require('./db');
const redis = require('./redis');
const { buddyService } = require('./modules/buddy/buddy.service');
const { buddyGroupService } = require('./modules/buddy_group/buddy_group.service');
const buddyBannersService = require('./modules/buddy_banners/buddy_banners.service');
const cacheService = require('./services/cache.service');
const crypto = require('crypto');

async function runTests() {
  console.log('🧪 ========================================================');
  console.log('🧪 RUNNING VERIFICATION SUITE FOR AUDIT ACTION ITEMS');
  console.log('🧪 ========================================================');

  const testUserA = crypto.randomUUID();
  const testUserB = crypto.randomUUID();
  const phoneA = `+91999${crypto.randomInt(1000000, 9999999)}`;
  const phoneB = `+91999${crypto.randomInt(1000000, 9999999)}`;

  try {
    // 1. Setup test users
    await db.query(`
      INSERT INTO public.users (id, phone_number, full_name, gender, city)
      VALUES ($1, $3, 'Test User A', 'male', 'mumbai'),
             ($2, $4, 'Test User B', 'female', 'mumbai')
      ON CONFLICT (id) DO NOTHING;
    `, [testUserA, testUserB, phoneA, phoneB]);

    await db.query(`
      INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
      VALUES ($1, 2000, 0), ($2, 1000, 0)
      ON CONFLICT (user_id) DO UPDATE SET spendable_balance = 2000;
    `, [testUserA, testUserB]);

    // Give user A an active subscription so they can create a request
    await db.query(`
      INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
      VALUES ($1, 30, 235, NOW(), NOW() + INTERVAL '30 days')
      ON CONFLICT DO NOTHING;
    `, [testUserA]);
    await redis.set(`user:subscribed:${testUserA}`, '1', 'EX', 300);

    // Ensure User B does NOT have a subscription
    await db.query(`DELETE FROM public.subscriptions WHERE user_id = $1`, [testUserB]);
    await redis.del(`user:subscribed:${testUserB}`);

    console.log('✅ Test users and wallets created.');

    // ── Test 1: Subscribed user A creates request, unsubscribed user B attempts accept ──
    console.log('\n--- Test 1: Buddy Request Acceptance Subscription Check ---');
    const createdReq = await buddyService.createRequest({
      initiatorId: testUserA,
      buddyType: 'hangout',
      city: 'mumbai',
      targetGender: 'all',
    });
    console.log(`Created buddy request: ${createdReq.id}`);

    let caughtSubError = false;
    try {
      await buddyService.acceptRequest({
        requestId: createdReq.id,
        accepterId: testUserB,
      });
    } catch (err) {
      if (err.code === 'ACTIVE_SUBSCRIPTION_REQUIRED' || err.message.includes('subscription')) {
        caughtSubError = true;
        console.log(`✅ Unsubscribed accepter correctly rejected with: ${err.message} (code: ${err.code})`);
      } else {
        throw err;
      }
    }

    if (!caughtSubError) {
      throw new Error('❌ Test 1 Failed: Unsubscribed user was allowed to accept buddy request!');
    }

    // Now give user B a subscription and verify acceptance succeeds
    await redis.set(`user:subscribed:${testUserB}`, '1', 'EX', 300);
    const acceptedReq = await buddyService.acceptRequest({
      requestId: createdReq.id,
      accepterId: testUserB,
    });
    console.log(`✅ Subscribed accepter successfully accepted request! Status: ${acceptedReq.status}`);

    // ── Test 2: Buddy Group Idempotency ──
    console.log('\n--- Test 2: Buddy Group Idempotency Key ---');
    const testIdempotencyKey = `idemp_grp_${Date.now()}`;
    const group1 = await buddyGroupService.createGroupBroadcast({
      hostId: testUserA,
      city: 'mumbai',
      title: 'Garba Night Test',
      idempotencyKey: testIdempotencyKey,
    });
    console.log(`Created buddy group: ${group1.id}, title: ${group1.title}`);

    // Call again with identical idempotencyKey
    const group2 = await buddyGroupService.createGroupBroadcast({
      hostId: testUserA,
      city: 'mumbai',
      title: 'Garba Night Test',
      idempotencyKey: testIdempotencyKey,
    });
    console.log(`Re-called with same idempotency key, returned group ID: ${group2.id}`);

    if (group1.id !== group2.id) {
      throw new Error('❌ Test 2 Failed: Idempotency check did not return same group ID!');
    }
    console.log('✅ Idempotency confirmed: Identical group returned on duplicate request.');

    // ── Test 3: Seasonal Banners Redis Caching ──
    console.log('\n--- Test 3: Seasonal Banners Redis Caching & Invalidation ---');
    await cacheService.invalidate('buddy_banners:active');
    
    // First call: DB fetch and cache set
    const banners1 = await buddyBannersService.getActiveBanners();
    const cachedVal = await redis.get('buddy_banners:active');
    console.log(`Redis key buddy_banners:active exists: ${cachedVal !== null}`);

    if (!cachedVal) {
      throw new Error('❌ Test 3 Failed: buddy_banners:active key was not cached in Redis!');
    }
    console.log('✅ Seasonal banners successfully cached in Redis.');

    // Test invalidation
    await cacheService.invalidate('buddy_banners:active');
    const afterInvalidate = await redis.get('buddy_banners:active');
    if (afterInvalidate !== null) {
      throw new Error('❌ Test 3 Failed: buddy_banners:active key was not invalidated!');
    }
    console.log('✅ Cache invalidation verified.');

    // ── Clean up test data ──
    await db.query(`DELETE FROM public.buddy_group_messages WHERE sender_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.buddy_group_members WHERE user_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.buddy_groups WHERE initiator_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.buddy_requests WHERE initiator_id IN ($1, $2) OR accepter_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.wallet_transactions WHERE user_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.wallets WHERE user_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.subscriptions WHERE user_id IN ($1, $2)`, [testUserA, testUserB]);
    await db.query(`DELETE FROM public.users WHERE id IN ($1, $2)`, [testUserA, testUserB]);

    console.log('\n========================================================');
    console.log('🎉 ALL AUDIT ACTION ITEM TESTS PASSED PERFECTLY!');
    console.log('========================================================\n');
    process.exit(0);
  } catch (err) {
    console.error('❌ Test failed with error:', err);
    process.exit(1);
  }
}

runTests();
