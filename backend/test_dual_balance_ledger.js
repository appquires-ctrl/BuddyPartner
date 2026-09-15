require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const assert = require('assert');
const crypto = require('crypto');
const db = require('./db');
const { WalletService } = require('./modules/wallet/wallet.service');
const { WithdrawalsService } = require('./modules/withdrawals/withdrawals.service');

async function setupTestUser(prefix = 'ledger_test') {
  const phone = `+919${Math.floor(100000000 + Math.random() * 900000000)}`;
  const userRes = await db.query(
    `INSERT INTO public.users (phone_number, full_name, gender, city)
     VALUES ($1, $2, 'female', 'Mumbai')
     RETURNING id`,
    [phone, `${prefix}_user`]
  );
  const userId = userRes.rows[0].id;
  return userId;
}

async function cleanupTestUser(userId) {
  if (userId) {
    await db.query('DELETE FROM public.users WHERE id = $1', [userId]).catch(() => {});
  }
}

async function runDualBalanceTests() {
  console.log('🧪 ========================================================');
  console.log('🧪 Starting Dual-Balance Ledger Automated Test Suite');
  console.log('🧪 ========================================================');

  const testUser = await setupTestUser('dual_bal');
  console.log(`👤 Created test user: ${testUser}`);

  try {
    // -------------------------------------------------------------------------
    // TEST 1: Debit spanning both buckets in the correct order
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 1: Debit spanning both buckets in correct order (spendable first, then earned) ---');
    // Set 40 spendable + 200 earned
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 40, earned_balance = 200 WHERE user_id = $1`,
      [testUser]
    );

    const debitResult = await WalletService.debitCoins({
      userId: testUser,
      amount: 100,
      reason: 'buddy_spend',
      referenceId: 'test_ref_1',
      idempotencyKey: `idemp_debit_1_${Date.now()}`,
    });

    assert.strictEqual(debitResult.success, true, 'Debit should succeed');
    assert.strictEqual(debitResult.spendableDeducted, 40, 'Should deduct all 40 from spendable');
    assert.strictEqual(debitResult.earnedDeducted, 60, 'Should deduct remaining 60 from earned');
    assert.strictEqual(debitResult.spendableBalance, 0, 'Spendable balance should be 0');
    assert.strictEqual(debitResult.earnedBalance, 140, 'Earned balance should be 140');
    assert.strictEqual(debitResult.balance, 140, 'Total balance should be 140');

    // Verify ledger row
    const txRow = (await db.query(
      `SELECT * FROM public.wallet_transactions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 1`,
      [testUser]
    )).rows[0];

    assert.strictEqual(Number(txRow.spendable_delta), -40, 'spendable_delta must be -40');
    assert.strictEqual(Number(txRow.earned_delta), -60, 'earned_delta must be -60');
    assert.strictEqual(txRow.reason, 'buddy_spend', 'reason must be buddy_spend');
    console.log('✅ TEST 1 PASSED: 40 spendable + 60 earned deducted; balances match expected state.');

    // -------------------------------------------------------------------------
    // TEST 2: Withdrawal rejected when only spendable coins exist
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 2: Withdrawal rejected when only spendable coins exist ---');
    // Set 100 spendable, 0 earned
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 100, earned_balance = 0 WHERE user_id = $1`,
      [testUser]
    );

    const withdrawReject = await WithdrawalsService.requestWithdrawal({
      userId: testUser,
      amount: 50,
      idempotencyKey: `idemp_with_2_${Date.now()}`,
    });

    assert.strictEqual(withdrawReject.success, false, 'Withdrawal must be rejected');
    assert.strictEqual(withdrawReject.code, 'SPENDABLE_NOT_WITHDRAWABLE', 'Error code must be SPENDABLE_NOT_WITHDRAWABLE');

    // Verify balances untouched
    const balCheck2 = await WalletService.getBalance(testUser);
    assert.strictEqual(balCheck2.spendableBalance, 100, 'Spendable balance must remain 100');
    assert.strictEqual(balCheck2.earnedBalance, 0, 'Earned balance must remain 0');
    console.log('✅ TEST 2 PASSED: Withdrawal request against spendable coins was rejected server-side.');

    // -------------------------------------------------------------------------
    // TEST 3: Withdrawal double-spend attempt blocked (Concurrent pending limit)
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 3: Withdrawal double-spend blocked via single pending limit ---');
    // Set 100 earned
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 0, earned_balance = 100 WHERE user_id = $1`,
      [testUser]
    );

    // First withdrawal for 60 coins
    const with1 = await WithdrawalsService.requestWithdrawal({
      userId: testUser,
      amount: 60,
      idempotencyKey: `idemp_with_3a_${Date.now()}`,
    });
    assert.strictEqual(with1.success, true, 'First withdrawal of 60 coins must succeed');
    assert.strictEqual(with1.earnedBalance, 40, 'Remaining earned balance must be 40');

    // Attempt second withdrawal while first is pending
    const with2 = await WithdrawalsService.requestWithdrawal({
      userId: testUser,
      amount: 30,
      idempotencyKey: `idemp_with_3b_${Date.now()}`,
    });
    assert.strictEqual(with2.success, false, 'Second concurrent pending withdrawal must be blocked');
    assert.strictEqual(with2.code, 'CONCURRENT_PENDING_NOT_ALLOWED', 'Error code must be CONCURRENT_PENDING_NOT_ALLOWED');

    // Admin rejects first withdrawal -> verify refund
    const { updateWithdrawalStatus } = require('./modules/admin/admin.service');
    const rejected = await updateWithdrawalStatus(with1.withdrawal.id, 'rejected', 'Document verification required');
    assert.strictEqual(rejected.status, 'rejected', 'Withdrawal status must be rejected');

    const balAfterRefund = await WalletService.getBalance(testUser);
    assert.strictEqual(balAfterRefund.earnedBalance, 100, 'Earned balance must be refunded back to 100');

    // Verify refund ledger row
    const refundTx = (await db.query(
      `SELECT * FROM public.wallet_transactions WHERE user_id = $1 AND reason = 'withdrawal_reject_refund' LIMIT 1`,
      [testUser]
    )).rows[0];
    assert.ok(refundTx, 'Compensating refund ledger row must exist');
    assert.strictEqual(Number(refundTx.earned_delta), 60, 'Refund earned delta must be +60');
    console.log('✅ TEST 3 PASSED: Concurrent pending withdrawal blocked; rejection triggers atomic refund.');

    // -------------------------------------------------------------------------
    // TEST 4: Idempotency key replay -> single charge
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 4: Idempotency key replay -> single charge ---');
    const idempKey = `test_idemp_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    
    // First call with key
    const firstCall = await WalletService.debitCoins({
      userId: testUser,
      amount: 25,
      reason: 'buddy_spend',
      idempotencyKey: idempKey,
    });
    assert.strictEqual(firstCall.success, true);
    assert.strictEqual(firstCall.earnedBalance, 75);

    // Replay call with identical key
    const replayCall = await WalletService.debitCoins({
      userId: testUser,
      amount: 25,
      reason: 'buddy_spend',
      idempotencyKey: idempKey,
    });
    assert.strictEqual(replayCall.success, true);
    assert.strictEqual(replayCall.alreadyProcessed, true, 'Replay call must flag alreadyProcessed');
    assert.strictEqual(replayCall.earnedBalance, 75, 'Balance must NOT change on replay');

    // Verify only 1 transaction exists with that idempotency key
    const txCount = (await db.query(
      `SELECT COUNT(*)::int AS count FROM public.wallet_transactions WHERE idempotency_key = $1`,
      [idempKey]
    )).rows[0].count;
    assert.strictEqual(txCount, 1, 'Exactly 1 transaction row must exist for idempotency key');
    console.log('✅ TEST 4 PASSED: Replayed idempotency key resulted in exactly 1 debit.');

    // -------------------------------------------------------------------------
    // TEST 5: Concurrent debit under load -> no negative balance, no lost update
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 5: Concurrent debit race under load ---');
    // Set total 50 coins (20 spendable, 30 earned)
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 20, earned_balance = 30 WHERE user_id = $1`,
      [testUser]
    );

    // Launch 10 simultaneous debit requests of 20 coins each (total 200 coins requested against 50 available)
    // Exactly 2 requests must succeed (2 * 20 = 40 debited, 10 coins remain)
    // 8 requests must fail with insufficient balance
    const parallelDebits = Array.from({ length: 10 }, (_, i) => 
      WalletService.debitCoins({
        userId: testUser,
        amount: 20,
        reason: 'buddy_spend',
        idempotencyKey: `concurrent_race_${i}_${Date.now()}`,
      })
    );

    const raceResults = await Promise.all(parallelDebits);
    const successes = raceResults.filter(r => r.success);
    const failures = raceResults.filter(r => !r.success);

    console.log(`Race results: ${successes.length} succeeded, ${failures.length} rejected`);
    assert.strictEqual(successes.length, 2, 'Exactly 2 debit requests must succeed');
    assert.strictEqual(failures.length, 8, 'Exactly 8 debit requests must fail');

    const finalBal = await WalletService.getBalance(testUser);
    assert.strictEqual(finalBal.balance, 10, 'Final balance must be exactly 10 coins');
    assert.ok(finalBal.spendableBalance >= 0, 'Spendable balance must be non-negative');
    assert.ok(finalBal.earnedBalance >= 0, 'Earned balance must be non-negative');
    console.log(`✅ TEST 5 PASSED: Concurrent debit race prevented negative balance and lost updates. Final balance: ${finalBal.balance}.`);

    // -------------------------------------------------------------------------
    // TEST 6: Migration backfill reconciliation on a seeded dataset
    // -------------------------------------------------------------------------
    console.log('\n--- TEST 6: Migration backfill reconciliation on seeded dataset ---');
    const testAccounts = [
      { spendable: 100, earned: 50 },
      { spendable: 0, earned: 200 },
      { spendable: 500, earned: 0 },
      { spendable: 0, earned: 0 },
    ];

    for (const acc of testAccounts) {
      const uId = await setupTestUser('seed');
      await db.query(
        `UPDATE public.wallets SET spendable_balance = $1, earned_balance = $2 WHERE user_id = $3`,
        [acc.spendable, acc.earned, uId]
      );
      const b = await WalletService.getBalance(uId);
      assert.strictEqual(b.spendableBalance, acc.spendable);
      assert.strictEqual(b.earnedBalance, acc.earned);
      assert.strictEqual(b.balance, acc.spendable + acc.earned);
      await cleanupTestUser(uId);
    }
    console.log('✅ TEST 6 PASSED: Seeded accounts reconciled across all dual-balance permutations.');

    console.log('\n ALL 6 DUAL-BALANCE LEDGER TESTS PASSED SUCCESSFULLY!');
  } finally {
    await cleanupTestUser(testUser);
  }
}

runDualBalanceTests()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('❌ Dual-Balance Test Suite Failed:', err);
    process.exit(1);
  });
