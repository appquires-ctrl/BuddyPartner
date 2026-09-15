const assert = require('assert');

// 1. Mock DB and Redis modules in require cache so test runs instantly without network
const mockDb = {
  wallets: new Map(),
  transactions: [],
  purchases: new Map(),
};

const mockDbModule = {
  query: async (sql, params = []) => {
    if (sql.includes('SELECT id, product_id, created_at FROM public.google_play_purchases WHERE purchase_token = $1')) {
      const token = params[0];
      const found = mockDb.purchases.get(token);
      return { rows: found ? [found] : [] };
    }
    return { rows: [] };
  },
  pool: {
    connect: async () => ({
      query: async (sql, params = []) => {
        if (sql.includes('INSERT INTO public.wallets')) {
          const userId = params[0];
          const amount = params[1];
          const current = mockDb.wallets.get(userId) || 0;
          const updated = current + amount;
          mockDb.wallets.set(userId, updated);
          return { rows: [{ balance: updated }] };
        }
        if (sql.includes('INSERT INTO public.wallet_transactions')) {
          mockDb.transactions.push({
            userId: params[0],
            amount: params[1],
            type: params[2],
            reason: params[3],
            ref: params[4],
          });
          return { rows: [] };
        }
        if (sql.includes('INSERT INTO public.google_play_purchases')) {
          const record = {
            id: 'mock_purch_' + Date.now(),
            user_id: params[0],
            product_id: params[1],
            purchase_token: params[2],
            order_id: params[3],
            amount_paid: params[5],
            coins_credited: params[6],
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

const { GooglePlayService, GOOGLE_PLAY_COIN_PRODUCTS } = require('./modules/payments/google_play.service');

async function testPricingTiers() {
  console.log('====================================================');
  console.log('🧪 VERIFYING WALLET PRICING TIERS (BACKEND)');
  console.log('====================================================\n');

  // Expected tiers mapping (Option B: customer pays base + 18% GST in Google Play)
  const expectedTiers = [
    { id: 'plan_49', basePriceRupees: 49, gstRupees: 9, priceRupees: 58, expectedCoins: 49, bonusCoins: 0 },
    { id: 'plan_99', basePriceRupees: 99, gstRupees: 18, priceRupees: 117, expectedCoins: 99, bonusCoins: 0 },
    { id: 'plan_199', basePriceRupees: 199, gstRupees: 36, priceRupees: 235, expectedCoins: 199, bonusCoins: 0 },
    { id: 'plan_499', basePriceRupees: 499, gstRupees: 90, priceRupees: 589, expectedCoins: 549, bonusCoins: 50 },
    { id: 'plan_999', basePriceRupees: 999, gstRupees: 180, priceRupees: 1179, expectedCoins: 1099, bonusCoins: 100 },
  ];

  for (const tier of expectedTiers) {
    const product = GOOGLE_PLAY_COIN_PRODUCTS[tier.id];
    assert(product, `Product ${tier.id} must exist in GOOGLE_PLAY_COIN_PRODUCTS`);
    assert.strictEqual(product.basePriceRupees, tier.basePriceRupees, `${tier.id} basePriceRupees must be ${tier.basePriceRupees}`);
    assert.strictEqual(product.gstRupees, tier.gstRupees, `${tier.id} gstRupees must be ${tier.gstRupees}`);
    assert.strictEqual(product.priceRupees, tier.priceRupees, `${tier.id} priceRupees must be ${tier.priceRupees}`);
    const totalCoins = product.coins + product.bonusCoins;
    assert.strictEqual(totalCoins, tier.expectedCoins, `${tier.id} total coins must be ${tier.expectedCoins}`);
    console.log(`  ✅ Tier ${tier.id}: Base ₹${tier.basePriceRupees} + ₹${tier.gstRupees} GST = ₹${tier.priceRupees} -> ${totalCoins} coins (${product.coins} base + ${product.bonusCoins} bonus) verified`);
  }

  // Verify catalog export
  const catalog = GooglePlayService.getProductCatalog();
  for (const tier of expectedTiers) {
    assert(catalog.allProductIds.includes(tier.id), `Catalog must include ${tier.id}`);
  }
  console.log('\n  ✅ Product catalog export verified for all 5 new tiers');

  // Test purchase verification credits exact coins
  for (const tier of expectedTiers) {
    const mockPublisher = {
      purchases: {
        products: {
          get: async () => ({
            data: {
              purchaseState: 0,
              consumptionState: 0,
              acknowledgementState: 0,
              orderId: `GPA.${Date.now()}-${tier.id}`,
            },
          }),
          acknowledge: async () => {},
        },
        subscriptionsv2: {
          get: async () => { throw new Error('Not a subscription'); },
        },
      },
    };
    GooglePlayService.setPublisherClientOverride(mockPublisher);

    const testUserId = `user_${tier.id}`;
    const token = `token_${tier.id}_${Date.now()}`;
    const result = await GooglePlayService.verifyAndProcessPurchase(testUserId, {
      productId: tier.id,
      purchaseToken: token,
      orderId: `GPA.${Date.now()}-${tier.id}`,
    });

    assert.strictEqual(result.success, true);
    assert.strictEqual(result.coinsCredited, tier.expectedCoins, `Must credit ${tier.expectedCoins} coins for ${tier.id}`);
    assert.strictEqual(mockDb.wallets.get(testUserId), tier.expectedCoins, `Wallet balance must equal ${tier.expectedCoins}`);
    console.log(`  ✅ Purchase flow for ${tier.id}: successfully credited ${result.coinsCredited} coins to wallet`);
  }

  GooglePlayService.setPublisherClientOverride(null);

  console.log('\n====================================================');
  console.log(' ALL PRICING VERIFICATION CHECKS PASSED!');
  console.log('====================================================');
}

testPricingTiers().catch((err) => {
  console.error('❌ Test failed:', err);
  process.exit(1);
});
