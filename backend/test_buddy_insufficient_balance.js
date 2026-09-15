/**
 * Test Suite: Insufficient Balance at Buddy Request Creation
 * 
 * Verifies that:
 * 1. An initiator with < 100 coins (e.g. 45 coins, 0 coins, 99 coins) is cleanly rejected with HTTP 400 & code INSUFFICIENT_COINS.
 * 2. Error message clearly states: "Insufficient balance: 100 coins required to create a buddy request (current balance: X coins)."
 * 3. NO orphaned rows are created in `public.buddy_requests`.
 * 4. NO audit entries are recorded in `public.wallet_transactions`.
 * 5. NO partial coin deductions occur (balance remains exactly intact).
 * 6. When the user has >= 100 coins, the request succeeds with exact transactional debit.
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const crypto = require('crypto');
const db = require('./db');
const { buddyService } = require('./modules/buddy/buddy.service');

async function runInsufficientBalanceTests() {
  console.log('================================================================');
  console.log('🧪 RUNNING INSUFFICIENT BALANCE AT REQUEST CREATION TESTS');
  console.log('================================================================\n');

  const testUserId = crypto.randomUUID();
  const testPhone = '+919' + Math.floor(100000000 + Math.random() * 900000000);

  try {
    // ── Setup Test User ────────────────────────────────────────────────────────
    console.log('1. Setting up test user with 45 coins & active subscription...');
    await db.query(`
      INSERT INTO public.users (id, phone_number, full_name, gender, city, is_banned)
      VALUES ($1, $2, 'Low Balance User', 'male', 'mumbai', FALSE)
      ON CONFLICT (id) DO NOTHING;
    `, [testUserId, testPhone]);

    await db.query(`
      INSERT INTO public.wallets (user_id, balance)
      VALUES ($1, 45)
      ON CONFLICT (user_id) DO UPDATE SET balance = 45;
    `, [testUserId]);

    // Active subscription so only coin balance is tested
    await db.query(`
      INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
      VALUES ($1, 30, 235, NOW(), NOW() + INTERVAL '30 days')
      ON CONFLICT DO NOTHING;
    `, [testUserId]);

    const initialWallet = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [testUserId])).rows[0].balance;
    console.log(`   Initial balance confirmed: ${initialWallet} coins\n`);

    // ── Test 1: Attempt creation with 45 coins ──────────────────────────────────
    console.log('2. Attempting to create buddy request with 45 coins...');
    let rejectedAsExpected = false;
    try {
      await buddyService.createRequest({
        initiatorId: testUserId,
        buddyType: 'movie',
        city: 'mumbai',
        targetGender: 'all',
      });
      throw new Error('Creation should have been REJECTED for balance < 100 coins!');
    } catch (err) {
      console.log(`   Caught expected rejection: [${err.code} ${err.statusCode}] "${err.message}"`);
      if (err.code !== 'INSUFFICIENT_COINS' || err.statusCode !== 400) {
        throw new Error(`Expected code INSUFFICIENT_COINS (400), got ${err.code} (${err.statusCode})`);
      }
      if (!err.message.includes('45 coins')) {
        throw new Error(`Expected error message to mention current balance 45 coins, got: ${err.message}`);
      }
      rejectedAsExpected = true;
    }

    if (!rejectedAsExpected) {
      throw new Error('Test failed to catch insufficient balance exception!');
    }

    // ── Verify DB Integrity ────────────────────────────────────────────────────
    console.log('3. Verifying strict database state integrity after rejection...');
    
    // Check 1: No orphaned buddy_requests row
    const orphanCheck = await db.query('SELECT * FROM public.buddy_requests WHERE initiator_id = $1', [testUserId]);
    console.log(`   buddy_requests rows found: ${orphanCheck.rows.length} (Expected: 0)`);
    if (orphanCheck.rows.length !== 0) {
      throw new Error(`Orphaned row found in buddy_requests! Count: ${orphanCheck.rows.length}`);
    }

    // Check 2: No wallet_transactions
    const txCheck = await db.query('SELECT * FROM public.wallet_transactions WHERE user_id = $1', [testUserId]);
    console.log(`   wallet_transactions rows found: ${txCheck.rows.length} (Expected: 0)`);
    if (txCheck.rows.length !== 0) {
      throw new Error(`Unexpected transaction record found! Count: ${txCheck.rows.length}`);
    }

    // Check 3: Balance unchanged
    const balanceAfter = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [testUserId])).rows[0].balance;
    console.log(`   Balance after failed attempt: ${balanceAfter} (Expected: 45)`);
    if (balanceAfter !== 45) {
      throw new Error(`Balance changed! Was 45, now ${balanceAfter}`);
    }
    console.log('✅ Integrity verified: 0 rows created, 0 audit rows, 0 coins deducted.\n');

    // ── Test 2: Boundary check at 99 coins ─────────────────────────────────────
    console.log('4. Testing boundary condition: 99 coins...');
    await db.query('UPDATE public.wallets SET balance = 99 WHERE user_id = $1', [testUserId]);

    try {
      await buddyService.createRequest({
        initiatorId: testUserId,
        buddyType: 'pizza',
        city: 'mumbai',
        targetGender: 'all',
      });
      throw new Error('Creation should have failed at 99 coins!');
    } catch (err) {
      if (err.code !== 'INSUFFICIENT_COINS') throw err;
      console.log(`   Rejection at 99 coins confirmed: "${err.message}"`);
    }

    const orphanCheck99 = await db.query('SELECT * FROM public.buddy_requests WHERE initiator_id = $1', [testUserId]);
    if (orphanCheck99.rows.length !== 0) throw new Error('Orphan row created at 99 coins!');
    console.log('✅ Boundary condition at 99 coins passed: cleanly rejected.\n');

    // ── Test 3: Success path when balance is 100 coins ──────────────────────────
    console.log('5. Testing success path when balance is exactly 100 coins...');
    await db.query('UPDATE public.wallets SET balance = 100 WHERE user_id = $1', [testUserId]);

    const createdReq = await buddyService.createRequest({
      initiatorId: testUserId,
      buddyType: 'coffee',
      city: 'mumbai',
      targetGender: 'all',
    });

    console.log(`   Successfully created request: ${createdReq.id}`);
    const balanceAfterSuccess = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [testUserId])).rows[0].balance;
    console.log(`   Balance after 100-coin deduction: ${balanceAfterSuccess} (Expected: 0)`);
    if (balanceAfterSuccess !== 0) {
      throw new Error(`Expected balance 0 after 100 coin deduction, got ${balanceAfterSuccess}`);
    }

    const txSuccess = await db.query('SELECT * FROM public.wallet_transactions WHERE reference_id = $1', [createdReq.id]);
    if (txSuccess.rows.length !== 1 || txSuccess.rows[0].amount !== 100 || txSuccess.rows[0].type !== 'debit') {
      throw new Error('Audit transaction mismatch on valid creation');
    }
    console.log('✅ Valid balance (100 coins) succeeded with exact 100 deduction and audit record.\n');

    // ── Clean up ───────────────────────────────────────────────────────────────
    console.log('6. Cleaning up test data...');
    await db.query('DELETE FROM public.buddy_requests WHERE id = $1', [createdReq.id]);
    await db.query('DELETE FROM public.users WHERE id = $1', [testUserId]);
    console.log('✅ Test data cleaned up.');

    console.log('\n================================================================');
    console.log('🎉 ALL INSUFFICIENT BALANCE TESTS PASSED!');
    console.log('================================================================');
    process.exit(0);
  } catch (err) {
    console.error('❌ Insufficient balance test failed:', err);
    process.exit(1);
  }
}

runInsufficientBalanceTests();
