require('dotenv').config();
const db = require('./db');
const { subscriptionsService, SUBSCRIPTION_PLANS } = require('./modules/subscriptions/subscriptions.service');

async function testSubscriptions() {
  console.log('🧪 Starting Subscription Service & Intro Offer Verification Test...');
  try {
    // 1. Verify pricing structure
    console.log('📋 Verified Subscription Plans:', SUBSCRIPTION_PLANS);
    if (SUBSCRIPTION_PLANS.length !== 4) {
      throw new Error(`Expected 4 plans, found ${SUBSCRIPTION_PLANS.length}`);
    }

    const plan1Day = SUBSCRIPTION_PLANS.find(p => p.id === '1_day');
    const plan1Week = SUBSCRIPTION_PLANS.find(p => p.id === '7_days');
    const plan1Month = SUBSCRIPTION_PLANS.find(p => p.id === '1_month');
    const plan1Year = SUBSCRIPTION_PLANS.find(p => p.id === '1_year');

    if (plan1Day.amountPaid !== 9 || plan1Week.amountPaid !== 59 || plan1Month.amountPaid !== 199 || plan1Year.amountPaid !== 1999) {
      throw new Error('Subscription pricing mismatch!');
    }
    console.log('✅ Subscription pricing verified successfully (₹9, ₹59, ₹199, ₹1999).');

    // 2. Get test user or create dummy test user
    let userRes = await db.query("SELECT id FROM public.users WHERE mobile = '9999999999' LIMIT 1");
    let testUserId;
    if (userRes.rows.length === 0) {
      const newUser = await db.query(
        "INSERT INTO public.users (country_code, mobile, phone_number, full_name, has_claimed_intro_offer) VALUES ('91', '9999999999', '+919999999999', 'Intro Test User', FALSE) RETURNING id"
      );
      testUserId = newUser.rows[0].id;
    } else {
      testUserId = userRes.rows[0].id;
      // Reset intro offer flag for testing
      await db.query("UPDATE public.users SET has_claimed_intro_offer = FALSE WHERE id = $1", [testUserId]);
      await db.query("DELETE FROM public.subscriptions WHERE user_id = $1", [testUserId]);
    }
    console.log(`👤 Testing with user ID: ${testUserId}`);

    // 3. Verify intro offer is initially unclaimed
    let hasClaimed = await subscriptionsService.hasClaimedIntroOffer(testUserId);
    if (hasClaimed) {
      throw new Error('User should not have claimed intro offer initially!');
    }
    console.log('✅ Initial state: Intro offer unclaimed (hasClaimed = false)');

    // 4. Create 1-day ₹9 subscription for first time
    const sub = await subscriptionsService.createSubscription(testUserId, 1, 9, 'TEST_INTRO_REF');
    console.log('✅ First ₹9 sub created successfully:', sub.id);

    // 5. Verify hasClaimedIntroOffer is now TRUE
    hasClaimed = await subscriptionsService.hasClaimedIntroOffer(testUserId);
    if (!hasClaimed) {
      throw new Error('User should be marked as claimed after first activation!');
    }
    console.log('✅ Post-activation state: Intro offer marked as claimed (hasClaimed = true)');

    // 6. Attempt second activation of ₹9 intro offer -> Must throw error
    let errorThrown = false;
    try {
      await subscriptionsService.createSubscription(testUserId, 1, 9, 'TEST_RETRY_REF');
    } catch (err) {
      errorThrown = true;
      console.log('✅ Server-side rejection caught successfully:', err.message);
    }

    if (!errorThrown) {
      throw new Error('Server failed to block duplicate ₹9 offer claim!');
    }

    // Clean up test user subscriptions
    await subscriptionsService.expireSubscription(testUserId);
    console.log(' All Subscription & Intro Offer Enforcement Tests Passed Successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Subscription Test Failed:', err.message);
    process.exit(1);
  }
}

testSubscriptions();
