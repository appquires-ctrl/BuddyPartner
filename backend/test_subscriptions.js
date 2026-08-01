require('dotenv').config();
const db = require('./db');
const { subscriptionsService } = require('./modules/subscriptions/subscriptions.service');

async function testSubscriptions() {
  console.log('🧪 Starting Subscription Service Verification Test...');
  try {
    // 1. Get sample user ID
    const userRes = await db.query('SELECT id FROM public.users LIMIT 1');
    if (userRes.rows.length === 0) {
      console.log('⚠️ No users found in database to test.');
      process.exit(0);
    }
    const testUserId = userRes.rows[0].id;
    console.log(`👤 Testing with user ID: ${testUserId}`);

    // 2. Initial status check
    const initialStatus = await subscriptionsService.getTimeRemaining(testUserId);
    console.log('📋 Initial subscription status:', initialStatus);

    // 3. Dev start subscription (1 day plan)
    const newSub = await subscriptionsService.createSubscription(testUserId, 1, 9, 'DEV_TEST_REF');
    console.log('✅ Created 1-day subscription:', newSub);

    // 4. Verify status after active subscription
    const activeStatus = await subscriptionsService.getTimeRemaining(testUserId);
    console.log('🟢 Active subscription status:', activeStatus);
    if (!activeStatus.isSubscribed || activeStatus.remainingHours < 20) {
      throw new Error('Subscription status failed to show active hours!');
    }

    // 5. Test dev expire subscription
    await subscriptionsService.expireSubscription(testUserId);
    console.log('⚡ Expired subscription...');

    // 6. Verify status after expiration
    const expiredStatus = await subscriptionsService.getTimeRemaining(testUserId);
    console.log('🔴 Post-expiration subscription status:', expiredStatus);
    if (expiredStatus.isSubscribed) {
      throw new Error('Subscription status still active after expireSubscription!');
    }

    console.log('🎉 Subscription Service Verification Test Passed Successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Subscription Service Verification Test Failed:', err);
    process.exit(1);
  }
}

testSubscriptions();
