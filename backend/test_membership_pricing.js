const assert = require('assert');

// 1. Mock DB and Redis modules in require cache so test runs instantly without external dependencies
const mockDb = {
  wallets: new Map(),
  subscriptions: [],
  purchases: new Map(),
};

const mockDbModule = {
  query: async (sql, params = []) => {
    if (sql.includes('SELECT id, product_id, created_at FROM public.google_play_purchases WHERE purchase_token = $1')) {
      const token = params[0];
      const found = mockDb.purchases.get(token);
      return { rows: found ? [found] : [] };
    }
    if (sql.includes('SELECT id, user_id, plan_duration_days, amount_paid, started_at, expires_at')) {
      return { rows: [] };
    }
    return { rows: [] };
  },
  pool: {
    connect: async () => ({
      query: async (sql, params = []) => {
        if (sql.includes('INSERT INTO public.subscriptions')) {
          const record = {
            id: 'mock_sub_' + Date.now(),
            user_id: params[0],
            plan_duration_days: params[1],
            amount_paid: params[2],
            expires_at: params[3],
            payment_reference: params[4],
          };
          mockDb.subscriptions.push(record);
          return { rows: [record] };
        }
        if (sql.includes('INSERT INTO public.google_play_purchases')) {
          const record = {
            id: 'mock_purch_' + Date.now(),
            user_id: params[0],
            product_id: params[1],
            purchase_token: params[2],
            order_id: params[3],
            amount_paid: params[5],
            status: params[7],
          };
          mockDb.purchases.set(params[2], record);
          return { rows: [record] };
        }
        return { rows: [] };
      },
      release: () => {},
    }),
  },
};

const dbPath = require.resolve('./db');
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: mockDbModule,
};

const redisPath = require.resolve('./redis');
require.cache[redisPath] = {
  id: redisPath,
  filename: redisPath,
  loaded: true,
  exports: {
    get: async () => null,
    set: async () => 'OK',
    del: async () => 1,
    quit: async () => 'OK',
    disconnect: () => {},
  },
};

const { GooglePlayService, GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS } = require('./modules/payments/google_play.service');
const { SUBSCRIPTION_PLANS, subscriptionsService } = require('./modules/subscriptions/subscriptions.service');

async function testMembershipPricing() {
  console.log('====================================================');
  console.log('🧪 VERIFYING MEMBERSHIP PRICING TIERS (BACKEND)');
  console.log('====================================================\n');

  // 1. Verify SUBSCRIPTION_PLANS has exactly the 3 requested membership plans
  assert.strictEqual(SUBSCRIPTION_PLANS.length, 3, 'Must have exactly 3 membership plans');
  console.log('  ✅ SUBSCRIPTION_PLANS length = 3');

  const plan1Month = SUBSCRIPTION_PLANS.find((p) => p.id === '1_month');
  assert(plan1Month, '1_month plan must exist');
  assert.strictEqual(plan1Month.basePrice, 199, '1_month base price must be ₹199');
  assert.strictEqual(plan1Month.gstAmount, 36, '1_month GST must be ₹36');
  assert.strictEqual(plan1Month.amountPaid, 235, '1_month total amount paid must be ₹235');
  assert.strictEqual(plan1Month.durationDays, 30, '1_month duration must be 30 days');
  console.log('  ✅ 1 Month Plan: Base ₹199 + ₹36 GST = ₹235, 30 days verified');

  const plan6Months = SUBSCRIPTION_PLANS.find((p) => p.id === '6_months');
  assert(plan6Months, '6_months plan must exist');
  assert.strictEqual(plan6Months.basePrice, 399, '6_months base price must be ₹399');
  assert.strictEqual(plan6Months.gstAmount, 72, '6_months GST must be ₹72');
  assert.strictEqual(plan6Months.amountPaid, 471, '6_months total amount paid must be ₹471');
  assert.strictEqual(plan6Months.durationDays, 180, '6_months duration must be 180 days');
  console.log('  ✅ 6 Months Plan: Base ₹399 + ₹72 GST = ₹471, 180 days verified');

  const plan1Year = SUBSCRIPTION_PLANS.find((p) => p.id === '1_year');
  assert(plan1Year, '1_year plan must exist');
  assert.strictEqual(plan1Year.basePrice, 699, '1_year base price must be ₹699');
  assert.strictEqual(plan1Year.gstAmount, 126, '1_year GST must be ₹126');
  assert.strictEqual(plan1Year.amountPaid, 825, '1_year total amount paid must be ₹825');
  assert.strictEqual(plan1Year.durationDays, 365, '1_year duration must be 365 days');
  console.log('  ✅ 1 Year Plan: Base ₹699 + ₹126 GST = ₹825, 365 days verified');

  // 2. Verify legacy 1_day and 7_days are removed from active SUBSCRIPTION_PLANS
  assert.strictEqual(SUBSCRIPTION_PLANS.some((p) => p.id === '1_day'), false, '1_day must not be in SUBSCRIPTION_PLANS');
  assert.strictEqual(SUBSCRIPTION_PLANS.some((p) => p.id === '7_days'), false, '7_days must not be in SUBSCRIPTION_PLANS');
  console.log('  ✅ Retired 1_day (₹9) and 7_days (₹59) plans confirmed absent');

  // 3. Verify GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS catalog
  const catalog = GooglePlayService.getProductCatalog();
  const activeProducts = ['membership_1_month', 'membership_6_months', 'membership_1_year'];
  for (const prodId of activeProducts) {
    assert(catalog.allProductIds.includes(prodId), `Catalog must include ${prodId}`);
    const prod = GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS[prodId];
    assert(prod, `Product ${prodId} must be defined`);
    if (prodId === 'membership_1_month') assert.strictEqual(prod.priceRupees, 235);
    if (prodId === 'membership_6_months') assert.strictEqual(prod.priceRupees, 471);
    if (prodId === 'membership_1_year') assert.strictEqual(prod.priceRupees, 825);
    console.log(`  ✅ Google Play subscription catalog has ${prodId} (₹${prod.priceRupees}, ${prod.durationDays} days)`);
  }

  // 4. Test Google Play subscription verification and activation flow
  for (const prodId of activeProducts) {
    const prod = GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS[prodId];
    const mockPublisher = {
      purchases: {
        products: {
          get: async () => { throw new Error('Not a product'); },
        },
        subscriptionsv2: {
          get: async () => ({
            data: {
              subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
              acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
              latestOrderId: `GPA.${Date.now()}-${prodId}`,
              lineItems: [{ productId: prodId }],
            },
          }),
        },
        subscriptions: {
          acknowledge: async () => {},
        },
      },
    };
    GooglePlayService.setPublisherClientOverride(mockPublisher);

    const testUserId = `user_${prodId}`;
    const token = `token_${prodId}_${Date.now()}`;
    const result = await GooglePlayService.verifyAndProcessPurchase(testUserId, {
      productId: prodId,
      purchaseToken: token,
      orderId: `GPA.${Date.now()}-${prodId}`,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.purchaseType, 'subs');
    assert.strictEqual(result.durationDays, prod.durationDays);
    console.log(`  ✅ Verified & activated subscription for ${prodId}: duration ${result.durationDays} days`);
  }

  // 5. Test alias resilience (e.g. client sends pass_1_month, Google lineItems has membership_1_month)
  const mockPublisherAlias = {
    purchases: {
      subscriptionsv2: {
        get: async () => ({
          data: {
            subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
            acknowledgementState: 'ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED',
            latestOrderId: 'GPA.ALIAS-TEST',
            lineItems: [{ productId: 'membership_1_month' }],
          },
        }),
      },
      subscriptions: { acknowledge: async () => {} },
    },
  };
  GooglePlayService.setPublisherClientOverride(mockPublisherAlias);
  const aliasResult = await GooglePlayService.verifyAndProcessPurchase('user_alias', {
    productId: 'pass_1_month',
    purchaseToken: 'token_alias_test',
    orderId: 'GPA.ALIAS-TEST',
  });
  assert.strictEqual(aliasResult.success, true);
  console.log('  ✅ Alias resilience test passed: pass_1_month client request successfully matched membership_1_month Google receipt');

  GooglePlayService.setPublisherClientOverride(null);

  console.log('\n====================================================');
  console.log('🎉 ALL BACKEND MEMBERSHIP PRICING TESTS PASSED!');
  console.log('====================================================');
}

testMembershipPricing().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
