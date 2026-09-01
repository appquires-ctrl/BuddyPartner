const path = require('path');
const assert = require('assert');

// 1. Mock DB In-Memory Store for fast, isolated unit testing without external database dependence
const mockDb = {
  wallets: new Map(), // userId -> balance
  transactions: [],
  purchases: new Map(), // purchase_token -> record
  subscriptions: [],
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
    connect: async () => {
      return {
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
            mockDb.transactions.push({ userId: params[0], amount: params[1], ref: params[4] });
            return { rows: [] };
          }
          if (sql.includes('INSERT INTO public.google_play_purchases')) {
            const purchaseRecord = {
              id: 'mock_purchase_id',
              userId: params[0],
              productId: params[1],
              purchase_token: params[2],
              orderId: params[3],
              created_at: new Date().toISOString(),
            };
            mockDb.purchases.set(params[2], purchaseRecord);
            return { rows: [purchaseRecord] };
          }
          return { rows: [] };
        },
        release: () => {},
      };
    },
  },
};

// Mock the db module in require cache before requiring services
const dbPath = require.resolve('../../db');
require.cache[dbPath] = {
  id: dbPath,
  filename: dbPath,
  loaded: true,
  exports: mockDbModule,
};

const { GooglePlayService, ANDROID_PACKAGE_NAME } = require('./google_play.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

async function runGooglePlaySecurityTests() {
  console.log('🧪 Starting Google Play Billing Security & Verification Unit Tests...\n');

  let testsPassed = 0;
  let testsTotal = 0;

  // Mock subscription service methods
  subscriptionsService.createSubscription = async (userId, durationDays, amountPaid, paymentRef) => {
    const sub = {
      id: 'mock_sub_id',
      userId,
      durationDays,
      amountPaid,
      paymentRef,
      expiresAt: new Date(Date.now() + durationDays * 86400000).toISOString(),
    };
    mockDb.subscriptions.push(sub);
    return sub;
  };

  subscriptionsService.getTimeRemaining = async (userId) => {
    return { isSubscribed: true, formattedLabel: 'Active Pass' };
  };

  try {
    // ──────────────────────────────────────────────────────────────────────────
    // Test 1: Valid Coin Purchase Token (passes Google verification & credits wallet)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 1: Valid coin purchase token verification');
    
    let acknowledged = false;
    const mockPublisherValidCoin = {
      purchases: {
        products: {
          get: async ({ packageName, productId, token }) => {
            if (packageName === ANDROID_PACKAGE_NAME && productId === 'plan_100' && token === 'valid_token_100') {
              return {
                data: {
                  packageName: ANDROID_PACKAGE_NAME,
                  productId: 'plan_100',
                  purchaseState: 0, // 0 = Purchased
                  consumptionState: 0,
                  acknowledgementState: 0,
                  orderId: 'GPA.1234-5678-9012',
                },
              };
            }
            throw new Error('404 Not Found: Invalid Token');
          },
          acknowledge: async ({ packageName, productId, token }) => {
            acknowledged = true;
          },
        },
        subscriptionsv2: {
          get: async () => { throw new Error('Not a subscription'); },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherValidCoin);

    const testUserA = 'user_test_valid_a';
    const result1 = await GooglePlayService.verifyAndProcessPurchase(testUserA, {
      productId: 'plan_100',
      purchaseToken: 'valid_token_100',
      orderId: 'GPA.1234-5678-9012',
    });

    assert.strictEqual(result1.success, true, 'Result success should be true');
    assert.strictEqual(result1.coinsCredited, 110, 'plan_100 should credit 100 + 10 = 110 coins');
    assert.strictEqual(mockDb.wallets.get(testUserA), 110, 'Wallet balance in database should be 110');
    assert.strictEqual(mockDb.purchases.has('valid_token_100'), true, 'Token must be recorded in google_play_purchases');
    assert.strictEqual(acknowledged, true, 'Purchase should be acknowledged with Google Play');

    console.log('  ✅ Test 1 Passed: Valid coin token verified, credited 110 coins, and acknowledged!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 2: Invalid / Fabricated Token (Google API rejects -> throws error & 0 DB changes)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 2: Fabricated fake token rejection');

    const testUserB = 'user_test_fake_b';
    const balanceBefore = mockDb.wallets.get(testUserB) || 0;
    let rejectedAsExpected = false;

    try {
      await GooglePlayService.verifyAndProcessPurchase(testUserB, {
        productId: 'plan_100',
        purchaseToken: 'fake_crafted_token_xyz',
      });
    } catch (err) {
      rejectedAsExpected = true;
      assert.strictEqual(err.statusCode, 400, 'Error status code must be 400');
      assert.strictEqual(err.code, 'INVALID_PURCHASE_TOKEN', 'Error code must be INVALID_PURCHASE_TOKEN');
    }

    assert.strictEqual(rejectedAsExpected, true, 'Fake token MUST be rejected');
    assert.strictEqual(mockDb.wallets.get(testUserB) || 0, balanceBefore, 'Wallet balance must NOT change');
    assert.strictEqual(mockDb.purchases.has('fake_crafted_token_xyz'), false, 'Fake token must NOT be recorded in DB');

    console.log('  ✅ Test 2 Passed: Fabricated token rejected with 400 error and 0 wallet changes!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 3: Duplicate Replay Attack Token (Already-processed token rejection)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 3: Replay attack duplicate token rejection');

    let duplicateRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase(testUserA, {
        productId: 'plan_100',
        purchaseToken: 'valid_token_100', // Already redeemed in Test 1
      });
    } catch (err) {
      duplicateRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Duplicate token must return 400');
      assert.strictEqual(err.code, 'ALREADY_REDEEMED', 'Error code must be ALREADY_REDEEMED');
    }

    assert.strictEqual(duplicateRejected, true, 'Duplicate token MUST be rejected');
    assert.strictEqual(mockDb.wallets.get(testUserA), 110, 'Wallet balance must remain 110 without double crediting');

    console.log('  ✅ Test 3 Passed: Replay token rejected and double-crediting prevented!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 4: Coin Pack — Package Name Mismatch Token
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 4: Coin pack — package name mismatch rejection');

    const mockPublisherWrongPackage = {
      purchases: {
        products: {
          get: async () => {
            return {
              data: {
                packageName: 'com.unauthorized.hacker.app',
                productId: 'plan_100',
                purchaseState: 0,
              },
            };
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherWrongPackage);

    let packageMismatchRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase('user_test_c', {
        productId: 'plan_100',
        purchaseToken: 'token_from_other_app',
      });
    } catch (err) {
      packageMismatchRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Package mismatch must return 400');
      assert.strictEqual(err.code, 'PACKAGE_MISMATCH', 'Error code must be PACKAGE_MISMATCH');
    }

    assert.strictEqual(packageMismatchRejected, true, 'Package mismatch MUST be rejected');

    console.log('  ✅ Test 4 Passed: Coin pack — unauthorized package token rejected with PACKAGE_MISMATCH!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 5: Valid Subscription Pass — matching lineItems productId
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 5: Valid subscription pass verification with matching lineItems');

    let subAcknowledged = false;
    const mockPublisherValidSub = {
      purchases: {
        subscriptionsv2: {
          get: async ({ packageName, token }) => {
            if (packageName === ANDROID_PACKAGE_NAME && token === 'valid_sub_token_7d') {
              return {
                data: {
                  subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
                  latestOrderId: 'GPA.9999-8888-7777',
                  lineItems: [{ productId: 'pass_7_days', offerDetails: { basePlanId: 'weekly' } }],
                  acknowledgementState: 'ACKNOWLEDGEMENT_STATE_PENDING',
                },
              };
            }
            throw new Error('404 Invalid Subscription Token');
          },
        },
        subscriptions: {
          acknowledge: async ({ packageName, subscriptionId, token }) => {
            subAcknowledged = true;
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherValidSub);

    const testUserSub = 'user_test_sub_d';
    const subResult = await GooglePlayService.verifyAndProcessPurchase(testUserSub, {
      productId: 'pass_7_days',
      purchaseToken: 'valid_sub_token_7d',
    });

    assert.strictEqual(subResult.success, true, 'Subscription verification should succeed');
    assert.strictEqual(subResult.purchaseType, 'subs', 'purchaseType should be subs');
    assert.strictEqual(subResult.productId, 'pass_7_days', 'productId in response should be the verified one from lineItems');
    assert.strictEqual(subResult.subscription.durationDays, 7, 'Duration should be 7 days');
    assert.strictEqual(mockDb.subscriptions.length, 1, 'Subscription record must be created');
    assert.strictEqual(mockDb.purchases.has('valid_sub_token_7d'), true, 'Token must be in google_play_purchases');
    // Verify audit trail uses Google-verified productId
    assert.strictEqual(mockDb.purchases.get('valid_sub_token_7d').productId, 'pass_7_days', 'Audit trail must record the Google-verified productId');
    assert.strictEqual(subAcknowledged, true, 'Subscription should be acknowledged with Google Play');

    console.log('  ✅ Test 5 Passed: Valid subscription pass verified, activated, and acknowledged!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 6: Subscription PRODUCT MISMATCH — valid token but client claims wrong productId
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 6: Subscription product mismatch — client claims pass_1_year but token is for pass_1_day');

    const subCountBefore = mockDb.subscriptions.length;
    const mockPublisherMismatchSub = {
      purchases: {
        subscriptionsv2: {
          get: async ({ packageName, token }) => {
            return {
              data: {
                subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
                latestOrderId: 'GPA.MISMATCH-001',
                lineItems: [{ productId: 'pass_1_day', offerDetails: { basePlanId: 'daily' } }],
              },
            };
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherMismatchSub);

    let productMismatchRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase('user_test_mismatch', {
        productId: 'pass_1_year',  // Client claims it's a yearly pass
        purchaseToken: 'mismatch_sub_token',
      });
    } catch (err) {
      productMismatchRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Product mismatch must return 400');
      assert.strictEqual(err.code, 'PRODUCT_MISMATCH', 'Error code must be PRODUCT_MISMATCH');
      assert.ok(err.message.includes('pass_1_day'), 'Error message should mention the actual product');
      assert.ok(err.message.includes('pass_1_year'), 'Error message should mention the claimed product');
    }

    assert.strictEqual(productMismatchRejected, true, 'Product mismatch MUST be rejected');
    assert.strictEqual(mockDb.subscriptions.length, subCountBefore, 'No subscription should be created');
    assert.strictEqual(mockDb.purchases.has('mismatch_sub_token'), false, 'Mismatch token must NOT be recorded');

    console.log('  ✅ Test 6 Passed: Product mismatch rejected — pass_1_day token cannot claim pass_1_year entitlement!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 7: Subscription with missing/empty lineItems → fail closed
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 7: Subscription with missing lineItems — fail closed');

    const subCountBefore7 = mockDb.subscriptions.length;
    const mockPublisherNoLineItems = {
      purchases: {
        subscriptionsv2: {
          get: async () => {
            return {
              data: {
                subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
                latestOrderId: 'GPA.NOLINES-001',
                // lineItems is missing entirely
              },
            };
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherNoLineItems);

    let noLineItemsRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase('user_test_nolines', {
        productId: 'pass_7_days',
        purchaseToken: 'nolines_sub_token',
      });
    } catch (err) {
      noLineItemsRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Missing lineItems must return 400');
      assert.strictEqual(err.code, 'INVALID_SUBSCRIPTION_RESPONSE', 'Error code must be INVALID_SUBSCRIPTION_RESPONSE');
    }

    assert.strictEqual(noLineItemsRejected, true, 'Missing lineItems MUST be rejected');
    assert.strictEqual(mockDb.subscriptions.length, subCountBefore7, 'No subscription should be created');
    assert.strictEqual(mockDb.purchases.has('nolines_sub_token'), false, 'Token must NOT be recorded');

    console.log('  ✅ Test 7 Passed: Missing lineItems → fail closed with INVALID_SUBSCRIPTION_RESPONSE!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 8: Subscription with empty lineItems array → fail closed
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 8: Subscription with empty lineItems array — fail closed');

    const subCountBefore8 = mockDb.subscriptions.length;
    const mockPublisherEmptyLineItems = {
      purchases: {
        subscriptionsv2: {
          get: async () => {
            return {
              data: {
                subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
                latestOrderId: 'GPA.EMPTY-001',
                lineItems: [], // Empty array
              },
            };
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherEmptyLineItems);

    let emptyLineItemsRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase('user_test_emptylines', {
        productId: 'pass_7_days',
        purchaseToken: 'emptylines_sub_token',
      });
    } catch (err) {
      emptyLineItemsRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Empty lineItems must return 400');
      assert.strictEqual(err.code, 'INVALID_SUBSCRIPTION_RESPONSE', 'Error code must be INVALID_SUBSCRIPTION_RESPONSE');
    }

    assert.strictEqual(emptyLineItemsRejected, true, 'Empty lineItems MUST be rejected');
    assert.strictEqual(mockDb.subscriptions.length, subCountBefore8, 'No subscription should be created');

    console.log('  ✅ Test 8 Passed: Empty lineItems → fail closed with INVALID_SUBSCRIPTION_RESPONSE!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 9: Subscription — Package Name Mismatch (mirrors coin pack test)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 9: Subscription — package name mismatch rejection');

    const subCountBefore9 = mockDb.subscriptions.length;
    const mockPublisherSubWrongPkg = {
      purchases: {
        subscriptionsv2: {
          get: async () => {
            return {
              data: {
                packageName: 'com.evil.fake.app',
                subscriptionState: 'SUBSCRIPTION_STATE_ACTIVE',
                latestOrderId: 'GPA.BADPKG-001',
                lineItems: [{ productId: 'pass_7_days' }],
              },
            };
          },
        },
      },
    };

    GooglePlayService.setPublisherClientOverride(mockPublisherSubWrongPkg);

    let subPkgMismatchRejected = false;
    try {
      await GooglePlayService.verifyAndProcessPurchase('user_test_subpkg', {
        productId: 'pass_7_days',
        purchaseToken: 'sub_wrong_pkg_token',
      });
    } catch (err) {
      subPkgMismatchRejected = true;
      assert.strictEqual(err.statusCode, 400, 'Package mismatch must return 400');
      assert.strictEqual(err.code, 'PACKAGE_MISMATCH', 'Error code must be PACKAGE_MISMATCH');
    }

    assert.strictEqual(subPkgMismatchRejected, true, 'Subscription package mismatch MUST be rejected');
    assert.strictEqual(mockDb.subscriptions.length, subCountBefore9, 'No subscription should be created');
    assert.strictEqual(mockDb.purchases.has('sub_wrong_pkg_token'), false, 'Token must NOT be recorded');

    console.log('  ✅ Test 9 Passed: Subscription package mismatch rejected with PACKAGE_MISMATCH!\n');
    testsPassed++;

  } finally {
    GooglePlayService.setPublisherClientOverride(null);
  }

  console.log(`=========================================`);
  console.log(`🎉 ALL ${testsPassed} / ${testsTotal} TESTS PASSED SUCCESSFULLY!`);
  console.log(`=========================================`);
}

runGooglePlaySecurityTests().then(() => {
  process.exit(0);
}).catch((err) => {
  console.error('❌ Test Suite Failed:', err);
  process.exit(1);
});
