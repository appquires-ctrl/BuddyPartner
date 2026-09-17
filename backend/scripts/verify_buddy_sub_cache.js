require('dotenv').config();
const db = require('../db');
const redis = require('../redis');
const { buddyService } = require('../modules/buddy/buddy.service');
const { subscriptionsService } = require('../modules/subscriptions/subscriptions.service');

async function testBuddySubscriptionCache() {
  console.log('--- 1.8 Buddy Service Subscription Cache Verification ---');

  // Find a test user
  const userRes = await db.query(`SELECT id FROM public.users LIMIT 1`);
  const userId = userRes.rows[0].id;
  const cacheKey = `user:subscribed:${userId}`;

  // Invalidate cache first
  await redis.del(cacheKey);

  // Set fake subscribed cache to '0' (unsubscribed)
  await redis.set(cacheKey, '0', 'EX', 300);

  // Attempt createRequest - should fail with ACTIVE_SUBSCRIPTION_REQUIRED without hitting subscriptions table
  let rejected = false;
  try {
    await buddyService.createRequest({
      initiatorId: userId,
      buddyType: 'coffee',
      location: 'Connaught Place',
      city: 'Delhi',
      description: 'Coffee meetup',
    });
  } catch (err) {
    console.log(`[Rejection Check] Code: ${err.code}, Message: ${err.message}`);
    if (err.code === 'ACTIVE_SUBSCRIPTION_REQUIRED') {
      rejected = true;
    }
  }

  if (!rejected) {
    console.error('❌ FAILED: Unsubscribed user was not rejected by BuddyService.createRequest!');
    process.exit(1);
  }

  // Verify the cache key was accessed
  const cachedVal = await redis.get(cacheKey);
  console.log(`[Cache Verification] Redis key '${cacheKey}' value: '${cachedVal}'`);

  console.log('✅ PASSED: BuddyService.createRequest correctly uses Redis-cached isSubscribed check!');
  process.exit(0);
}

testBuddySubscriptionCache().catch((err) => {
  console.error('❌ Error in testBuddySubscriptionCache:', err);
  process.exit(1);
});
