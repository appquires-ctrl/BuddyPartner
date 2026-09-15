require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const assert = require('assert');
const db = require('./db');
const redis = require('./redis');
const { buddyService } = require('./modules/buddy/buddy.service');
const { WalletService } = require('./modules/wallet/wallet.service');
const { WithdrawalsService } = require('./modules/withdrawals/withdrawals.service');

async function createTestUser(name, gender = 'female', city = 'Mumbai') {
  const phone = `+919${Math.floor(100000000 + Math.random() * 900000000)}`;
  const res = await db.query(
    `INSERT INTO public.users (phone_number, full_name, gender, city)
     VALUES ($1, $2, $3, $4)
     RETURNING id`,
    [phone, name, gender, city]
  );
  return res.rows[0].id;
}

async function cleanupUsers(userIds) {
  for (const id of userIds) {
    if (id) {
      await db.query('DELETE FROM public.users WHERE id = $1', [id]).catch(() => {});
    }
  }
}

async function runBuddyMeetupFlowTests() {
  console.log('🧪 ========================================================');
  console.log('🧪 Starting Buddy Meetup & Dual-Balance Flow Test Suite');
  console.log('🧪 ========================================================');

  const initiatorId = await createTestUser('Alice_Initiator', 'male', 'Mumbai');
  const accepterId = await createTestUser('Bob_Accepter', 'female', 'Mumbai');
  const intruderId = await createTestUser('Eve_Intruder', 'female', 'Mumbai');

  const allUsers = [initiatorId, accepterId, intruderId];

  try {
    // -----------------------------------------------------------------------
    // STEP 0: Grant active subscription to initiator
    // -----------------------------------------------------------------------
    await db.query(
      `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
       VALUES ($1, 30, 199, NOW(), NOW() + INTERVAL '30 days', 'TEST_SUB')`,
      [initiatorId]
    );

    // -----------------------------------------------------------------------
    // STEP 1: Fund initiator and create buddy request (100 coins)
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 1: Fund initiator and create buddy request (100 coins) ---');
    // Set 150 spendable coins for initiator
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 150, earned_balance = 0 WHERE user_id = $1`,
      [initiatorId]
    );

    const request = await buddyService.createRequest({
      initiatorId,
      buddyType: 'coffee',
      city: 'Mumbai',
      targetGender: 'all',
      idempotencyKey: `idemp_req_${Date.now()}`,
    });

    assert.ok(request.id, 'Request ID should be present');
    assert.strictEqual(request.status, 'open', 'Status must be open');
    assert.strictEqual(request.newBalance, 50, 'Initiator balance should be 50 after 100 deduction');

    const initBal = await WalletService.getBalance(initiatorId);
    assert.strictEqual(initBal.spendableBalance, 50, 'Spendable balance should be 50');
    assert.strictEqual(initBal.earnedBalance, 0, 'Earned balance should be 0');
    console.log('✅ STEP 1 PASSED: Buddy request created; 100 spendable coins deducted.');

    // -----------------------------------------------------------------------
    // STEP 2: Accepter accepts request -> immediate chat unlock + OTP generation
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 2: Accepter accepts request -> immediate chat unlock ---');
    const acceptRes = await buddyService.acceptRequest({
      requestId: request.id,
      accepterId,
    });

    assert.strictEqual(acceptRes.status, 'accepted', 'Status must be accepted');
    assert.ok(acceptRes.conversationId, 'Conversation ID must be created immediately');

    // Verify conversation exists in DB
    const convRow = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [acceptRes.conversationId]
    );
    assert.strictEqual(convRow.rows.length, 1, 'Conversation row must exist in DB');

    // Verify DB stores otp_hash and otp_encrypted (never plaintext)
    const dbReq = (await db.query(`SELECT * FROM public.buddy_requests WHERE id = $1`, [request.id])).rows[0];
    assert.ok(dbReq.otp_hash, 'otp_hash must be present');
    assert.ok(dbReq.otp_encrypted, 'otp_encrypted must be present');
    assert.strictEqual(dbReq.status, 'accepted');
    console.log('✅ STEP 2 PASSED: Request accepted; conversation created immediately; OTP securely hashed & encrypted.');

    // -----------------------------------------------------------------------
    // STEP 3: Initiator retrieves OTP via authenticated REST endpoint
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 3: Initiator retrieves OTP via REST (Auth authorization checks) ---');
    const initiatorOtpRes = await buddyService.getInitiatorOtp(request.id, initiatorId);
    assert.ok(initiatorOtpRes.otpCode, 'Initiator should get OTP code');
    assert.strictEqual(initiatorOtpRes.otpCode.length, 6, 'OTP must be 6 digits');
    console.log(`🔑 Initiator retrieved OTP: ${initiatorOtpRes.otpCode}`);

    // Accepter must NOT be able to view OTP
    let accepterBlocked = false;
    try {
      await buddyService.getInitiatorOtp(request.id, accepterId);
    } catch (err) {
      if (err.statusCode === 403) accepterBlocked = true;
    }
    assert.strictEqual(accepterBlocked, true, 'Accepter must receive 403 Forbidden when requesting OTP');

    // Intruder must NOT be able to view OTP
    let intruderBlocked = false;
    try {
      await buddyService.getInitiatorOtp(request.id, intruderId);
    } catch (err) {
      if (err.statusCode === 403) intruderBlocked = true;
    }
    assert.strictEqual(intruderBlocked, true, 'Intruder must receive 403 Forbidden when requesting OTP');
    console.log('✅ STEP 3 PASSED: Initiator successfully fetched OTP; unauthorized parties blocked with 403.');

    // -----------------------------------------------------------------------
    // STEP 4: Brute force rate limiting (5 failed attempts -> 15 min lockout)
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 4: Brute force rate limiting (5 failed attempts -> 15 min lockout) ---');
    const wrongOtp = '999999';

    for (let i = 1; i <= 4; i++) {
      try {
        await buddyService.completeRequest({
          requestId: request.id,
          accepterId,
          otpCode: wrongOtp,
        });
        assert.fail(`Attempt ${i} should have failed`);
      } catch (err) {
        assert.strictEqual(err.code, 'INVALID_OTP');
        assert.strictEqual(err.remainingAttempts, 5 - i);
      }
    }

    // 5th attempt triggers lockout
    try {
      await buddyService.completeRequest({
        requestId: request.id,
        accepterId,
        otpCode: wrongOtp,
      });
      assert.fail('5th attempt should have triggered lockout');
    } catch (err) {
      assert.strictEqual(err.code, 'TOO_MANY_ATTEMPTS');
      assert.strictEqual(err.statusCode, 429);
      console.log('🔒 5th failed attempt triggered 15-minute lockout as expected.');
    }

    // 6th attempt should be blocked immediately by lockout
    try {
      await buddyService.completeRequest({
        requestId: request.id,
        accepterId,
        otpCode: initiatorOtpRes.otpCode, // Even with correct OTP!
      });
      assert.fail('6th attempt should be blocked by lockout even with correct OTP');
    } catch (err) {
      assert.strictEqual(err.code, 'TOO_MANY_ATTEMPTS');
      assert.strictEqual(err.statusCode, 429);
      console.log('🔒 6th attempt correctly blocked by active lockout.');
    }
    console.log('✅ STEP 4 PASSED: Rate-limit lockout after 5 failed attempts verified.');

    // -----------------------------------------------------------------------
    // STEP 5: Clear lockout and successfully complete with correct OTP
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 5: Successful completion with correct OTP -> 50 earned coins ---');
    // Clear Redis lockout key to simulate lockout expiry
    await redis.del(`buddy:otp:lockout:${request.id}`);
    await redis.del(`buddy:otp:attempts:${request.id}`);

    const completeRes = await buddyService.completeRequest({
      requestId: request.id,
      accepterId,
      otpCode: initiatorOtpRes.otpCode,
    });

    assert.strictEqual(completeRes.success, true, 'Meetup completion must succeed');
    assert.strictEqual(completeRes.rewardCoins, 50, 'Reward must be 50 coins');
    assert.strictEqual(completeRes.earnedBalance, 50, 'Accepter earned balance must be 50');

    // Verify accepter can withdraw those 50 earned coins!
    const withdrawRes = await WithdrawalsService.requestWithdrawal({
      userId: accepterId,
      amount: 50,
      payoutMethod: 'upi',
      payoutDetails: { vpa: 'bob@upi' },
      idempotencyKey: `idemp_with_bob_${Date.now()}`,
    });

    assert.strictEqual(withdrawRes.success, true, 'Accepter must be able to withdraw earned reward coins');
    assert.strictEqual(withdrawRes.withdrawal.amount, '50', 'Withdrawal amount must be 50');
    console.log('✅ STEP 5 PASSED: Meetup verified; 50 earned coins credited and confirmed withdrawable.');

    // -----------------------------------------------------------------------
    // STEP 6: Admin cancellation strictly without refunds
    // -----------------------------------------------------------------------
    console.log('\n--- STEP 6: Admin cancellation strictly without refunds ---');
    // Fund initiator with 100 spendable coins
    await db.query(
      `UPDATE public.wallets SET spendable_balance = 100, earned_balance = 0 WHERE user_id = $1`,
      [initiatorId]
    );

    const req2 = await buddyService.createRequest({
      initiatorId,
      buddyType: 'movie',
      city: 'Mumbai',
      targetGender: 'all',
      idempotencyKey: `idemp_req_cancel_${Date.now()}`,
    });

    // Initiator now has 0 balance
    const initBalPreCancel = await WalletService.getBalance(initiatorId);
    assert.strictEqual(initBalPreCancel.balance, 0);

    // Admin cancels request
    const cancelRes = await buddyService.adminCancelRequest(req2.id, null, 'admin_test_cancellation');
    assert.strictEqual(cancelRes.status, 'cancelled');

    // Verify NO refund was given
    const initBalPostCancel = await WalletService.getBalance(initiatorId);
    assert.strictEqual(initBalPostCancel.balance, 0, 'Balance must remain 0: strictly NO refund on cancellation');
    console.log('✅ STEP 6 PASSED: Admin cancellation executed with zero refunds.');

    console.log('\n🎉 ALL BUDDY MEETUP FLOW TESTS PASSED SUCCESSFULLY!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Buddy Meetup Flow Test Failed:', err);
    process.exit(1);
  } finally {
    await cleanupUsers(allUsers);
  }
}

runBuddyMeetupFlowTests();
