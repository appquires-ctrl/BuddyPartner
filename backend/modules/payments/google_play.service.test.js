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
    if (sql.includes('SELECT * FROM public.google_play_purchases WHERE purchase_token = $1')) {
      const token = params[0];
      const found = mockDb.purchases.get(token);
      return { rows: found ? [found] : [] };
    }
    if (sql.includes('SELECT * FROM public.google_play_purchases WHERE order_id = $1')) {
      const orderId = params[0];
      for (const record of mockDb.purchases.values()) {
        if (record.order_id === orderId || record.orderId === orderId) {
          return { rows: [record] };
        }
      }
      return { rows: [] };
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
          if (sql.includes('UPDATE public.wallets')) {
            const amount = params[0];
            const userId = params[1];
            const current = mockDb.wallets.get(userId) || 0;
            const updated = Math.max(0, current - amount);
            mockDb.wallets.set(userId, updated);
            return { rows: [{ balance: updated }] };
          }
          if (sql.includes('INSERT INTO public.wallet_transactions')) {
            mockDb.transactions.push({
              userId: params[0],
              amount: params[1],
              type: params[2] || 'credit',
              reason: params[3] || 'recharge',
              ref: params[4],
            });
            return { rows: [] };
          }
          if (sql.includes('INSERT INTO public.google_play_purchases')) {
            const purchaseRecord = {
              id: 'mock_purchase_id_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7),
              user_id: params[0],
              userId: params[0],
              product_id: params[1],
              productId: params[1],
              purchase_token: params[2],
              order_id: params[3],
              orderId: params[3],
              purchase_type: params[4] || 'inapp',
              amount_paid: params[5],
              coins_credited: params[6] || 0,
              status: params[7] || 'COMPLETED',
              created_at: new Date().toISOString(),
            };
            mockDb.purchases.set(params[2], purchaseRecord);
            return { rows: [purchaseRecord] };
          }
          if (sql.includes('UPDATE public.google_play_purchases')) {
            const reason = params[0];
            const id = params[1];
            for (const record of mockDb.purchases.values()) {
              if (record.id === id) {
                record.status = 'VOIDED';
                record.voided_at = new Date().toISOString();
                record.void_reason = reason;
                return { rows: [record] };
              }
            }
            return { rows: [] };
          }
          if (sql.includes('UPDATE public.subscriptions')) {
            const userId = params[0];
            const orderId = params[1];
            const token = params[2];
            for (const sub of mockDb.subscriptions) {
              if (sub.userId === userId && (sub.paymentRef === orderId || sub.paymentRef === token)) {
                sub.expiresAt = new Date(Date.now() - 1000).toISOString();
                sub.is_active = false;
              }
            }
            return { rows: [] };
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

    // ──────────────────────────────────────────────────────────────────────────
    // Test 10: RTDN voidedPurchaseNotification (Chargeback/Refund of Coin Pack)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 10: RTDN voided purchase notification revokes credited coins');

    // user_test_valid_a had 110 coins credited from Test 1 with valid_token_100
    const balanceBeforeVoid = mockDb.wallets.get('user_test_valid_a');
    assert.strictEqual(balanceBeforeVoid, 110, 'User should start with 110 coins');

    const voidPayload = {
      version: '1.0',
      packageName: ANDROID_PACKAGE_NAME,
      voidedPurchaseNotification: {
        purchaseToken: 'valid_token_100',
        orderId: 'GPA.3355-3527-8229-20563',
        productType: 1,
        refundType: 1,
      },
    };

    const rtdnMessage = {
      data: Buffer.from(JSON.stringify(voidPayload)).toString('base64'),
      messageId: 'rtdn_void_100',
    };

    const rtdnRes = await GooglePlayService.handleRtdnNotification(rtdnMessage);

    assert.strictEqual(rtdnRes.success, true, 'RTDN handler must succeed');
    assert.strictEqual(rtdnRes.revoked, true, 'Purchase must be revoked');
    assert.strictEqual(rtdnRes.coinsDeducted, 110, 'Must deduct 110 coins');
    assert.strictEqual(mockDb.wallets.get('user_test_valid_a'), 0, 'User balance must be 0 after chargeback');

    const lastTx = mockDb.transactions[mockDb.transactions.length - 1];
    assert.strictEqual(lastTx.type, 'debit', 'Must insert debit transaction');
    assert.strictEqual(lastTx.reason, 'chargeback_reversal', 'Reason must be chargeback_reversal');

    const purchaseRec = mockDb.purchases.get('valid_token_100');
    assert.strictEqual(purchaseRec.status, 'VOIDED', 'Purchase status must be VOIDED');

    console.log('  ✅ Test 10 Passed: RTDN voided notification debited 110 coins and set status VOIDED!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 11: RTDN Idempotency (Duplicate Voided Notification)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 11: RTDN idempotency prevents double-debiting on duplicate notification');

    const txCountBefore11 = mockDb.transactions.length;
    const rtdnDupRes = await GooglePlayService.handleRtdnNotification(rtdnMessage);

    assert.strictEqual(rtdnDupRes.success, true, 'Duplicate RTDN must succeed cleanly');
    assert.strictEqual(rtdnDupRes.alreadyVoided, true, 'Must report alreadyVoided: true');
    assert.strictEqual(mockDb.wallets.get('user_test_valid_a'), 0, 'User balance must remain 0 (no double-debit)');
    assert.strictEqual(mockDb.transactions.length, txCountBefore11, 'No new debit transaction should be added');

    console.log('  ✅ Test 11 Passed: Duplicate notification handled idempotently with 0 balance change!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 12: RTDN subscriptionNotification (SUBSCRIPTION_REVOKED type 12)
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 12: RTDN subscription revocation deactivates active pass');

    // user_test_sub_d had valid_sub_token_7d activated in Test 5
    const subRevokePayload = {
      version: '1.0',
      packageName: ANDROID_PACKAGE_NAME,
      subscriptionNotification: {
        version: '1.0',
        notificationType: 12, // SUBSCRIPTION_REVOKED
        purchaseToken: 'valid_sub_token_7d',
        subscriptionId: 'pass_7_days',
      },
    };

    const subRtdnMessage = {
      data: Buffer.from(JSON.stringify(subRevokePayload)).toString('base64'),
      messageId: 'rtdn_sub_revoke_12',
    };

    const subRtdnRes = await GooglePlayService.handleRtdnNotification(subRtdnMessage);

    assert.strictEqual(subRtdnRes.success, true, 'Subscription revocation must succeed');
    assert.strictEqual(subRtdnRes.revoked, true, 'Subscription must be revoked');
    assert.strictEqual(subRtdnRes.purchaseType, 'subs', 'Purchase type must be subs');

    const subPurchaseRec = mockDb.purchases.get('valid_sub_token_7d');
    assert.strictEqual(subPurchaseRec.status, 'VOIDED', 'Subscription purchase record status must be VOIDED');

    console.log('  ✅ Test 12 Passed: RTDN subscription revocation deactivated pass and marked VOIDED!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 13: RTDN testNotification ping from Google Play Console
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 13: RTDN test notification ping from Google Play Console');

    const testPingPayload = {
      version: '1.0',
      packageName: ANDROID_PACKAGE_NAME,
      testNotification: {
        version: '1.0',
      },
    };

    const pingMessage = {
      data: Buffer.from(JSON.stringify(testPingPayload)).toString('base64'),
    };

    const pingRes = await GooglePlayService.handleRtdnNotification(pingMessage);

    assert.strictEqual(pingRes.success, true, 'Test notification ping must succeed');
    assert.strictEqual(pingRes.type, 'testNotification', 'Type must be testNotification');
    assert.strictEqual(pingRes.acknowledged, true, 'Acknowledged must be true');

    console.log('  ✅ Test 13 Passed: Google Play test notification ping acknowledged successfully!\n');
    testsPassed++;

    // ──────────────────────────────────────────────────────────────────────────
    // Test 14: Voided Purchases API Reconciliation
    // ──────────────────────────────────────────────────────────────────────────
    testsTotal++;
    console.log('▶ Test 14: Voided Purchases API reconciliation catches missed chargebacks');

    // First, set up a coin purchase that was verified earlier
    const mockPublisherSyncSetup = {
      purchases: {
        products: {
          get: async () => ({
            data: {
              packageName: ANDROID_PACKAGE_NAME,
              purchaseState: 0,
              acknowledgementState: 1,
              orderId: 'GPA.sync.50.order',
            },
          }),
        },
      },
    };
    GooglePlayService.setPublisherClientOverride(mockPublisherSyncSetup);

    await GooglePlayService.verifyAndProcessPurchase('user_test_sync', {
      productId: 'plan_50',
      purchaseToken: 'sync_token_50',
      orderId: 'GPA.sync.50.order',
    });

    assert.strictEqual(mockDb.wallets.get('user_test_sync'), 50, 'User should have 50 coins');

    // Now mock the voidedpurchases API returning this purchase as voided
    const mockPublisherVoidedApi = {
      purchases: {
        voidedpurchases: {
          list: async ({ packageName, startTime }) => {
            assert.strictEqual(packageName, ANDROID_PACKAGE_NAME);
            return {
              data: {
                voidedPurchases: [
                  {
                    purchaseToken: 'sync_token_50',
                    orderId: 'GPA.sync.50.order',
                    voidedReason: 1,
                  },
                ],
              },
            };
          },
        },
      },
    };
    GooglePlayService.setPublisherClientOverride(mockPublisherVoidedApi);

    const syncResult = await GooglePlayService.syncVoidedPurchases();

    assert.strictEqual(syncResult.success, true, 'Sync must succeed');
    assert.strictEqual(syncResult.totalFound, 1, 'Must find 1 voided purchase');
    assert.strictEqual(mockDb.wallets.get('user_test_sync'), 0, 'User balance must be debited to 0');
    assert.strictEqual(mockDb.purchases.get('sync_token_50').status, 'VOIDED', 'Status must be VOIDED');

    console.log('  ✅ Test 14 Passed: Voided Purchases API reconciliation debited coins to 0!\n');
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
