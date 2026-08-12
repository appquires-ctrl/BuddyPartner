require('dotenv').config();
const db = require('./db');
const { RoseService } = require('./modules/wallet/rose.service');
const jwt = require('jsonwebtoken');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

async function runTelecallerVerificationTests() {
  console.log('🚀 Running Telecaller Opt-In Automated Verification Suite...\n');

  try {
    // ────────────────────────────────────────────────────────────────────────
    // SETUP: Provision Test Users
    // ────────────────────────────────────────────────────────────────────────
    const femalePhone = '+919999900001';
    const malePhone = '+919999900002';

    const femaleRes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender, is_telecaller)
      VALUES ($1, 'Priya Telecaller Test', 'female', TRUE)
      ON CONFLICT (phone_number) 
      DO UPDATE SET full_name = EXCLUDED.full_name, gender = 'female', is_telecaller = TRUE
      RETURNING id, phone_number, full_name, gender, is_telecaller;
    `, [femalePhone]);

    const maleRes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender)
      VALUES ($1, 'Rahul Boy Test', 'male')
      ON CONFLICT (phone_number) 
      DO UPDATE SET full_name = EXCLUDED.full_name, gender = 'male'
      RETURNING id;
    `, [malePhone]);

    const femaleUser = femaleRes.rows[0];
    const femaleId = femaleUser.id;
    const maleId = maleRes.rows[0].id;

    console.log(`👤 Female Test User: ${femaleId} (${femaleUser.full_name}) — Initial is_telecaller: ${femaleUser.is_telecaller}`);
    console.log(`👤 Male Test User:   ${maleId}\n`);

    // Clean old transactions for this test user to have a clean ledger for output
    await db.query('DELETE FROM public.rose_transactions WHERE user_id = $1', [femaleId]);
    await db.query('DELETE FROM public.rose_balances WHERE user_id = $1', [femaleId]);

    // Create a mock call record
    const callRes = await db.query(`
      INSERT INTO public.calls (caller_id, matched_user_id, status, call_type)
      VALUES ($1, $2, 'active', 'voice')
      RETURNING id;
    `, [maleId, femaleId]);
    const callId = callRes.rows[0].id;

    console.log(`====================================================`);
    console.log(`--- TEST 1: Mid-Call Telecaller Toggle Verification ---`);
    console.log(`====================================================`);

    // Tick 1 (Minute 1): Telecaller Mode is ON -> Should credit 1 rose
    console.log('\n[Tick 1] Call Minute 1 (is_telecaller = TRUE)...');
    const tick1 = await RoseService.creditRoseForCallMinute(femaleId, callId, 'voice');
    console.log('Tick 1 Result:', tick1);

    // Short delay to ensure distinct SQL timestamps
    await new Promise((resolve) => setTimeout(resolve, 1000));

    // Tick 2 (Minute 2): Telecaller Mode is STILL ON -> Should credit 1 rose
    console.log('\n[Tick 2] Call Minute 2 (is_telecaller = TRUE)...');
    const tick2 = await RoseService.creditRoseForCallMinute(femaleId, callId, 'voice');
    console.log('Tick 2 Result:', tick2);

    // Inspect Rose ledger mid-call
    let ledgerMidCall = await db.query(
      'SELECT id, amount, type, reason, reference_id, created_at FROM public.rose_transactions WHERE user_id = $1 ORDER BY created_at ASC',
      [femaleId]
    );
    console.log(`\n📊 Rose Transactions BEFORE toggle (${ledgerMidCall.rows.length} rows):`);
    console.table(ledgerMidCall.rows.map(r => ({
      id: r.id.substring(0, 8) + '...',
      amount: r.amount,
      type: r.type,
      reason: r.reason,
      createdAt: r.created_at.toISOString()
    })));

    // MID-CALL TOGGLE: Female user toggles Telecaller Mode OFF in Settings
    console.log('\n⚡ MID-CALL TOGGLE: User switches Telecaller Mode to OFF (is_telecaller = FALSE)...');
    await db.query('UPDATE public.users SET is_telecaller = FALSE WHERE id = $1', [femaleId]);
    console.log('✅ Updated users.is_telecaller = FALSE in DB');

    // Tick 3 (Minute 3): Call is still active, but Telecaller Mode is now OFF -> Must SKIP rose credit!
    console.log('\n[Tick 3] Call Minute 3 (is_telecaller = FALSE)...');
    const tick3 = await RoseService.creditRoseForCallMinute(femaleId, callId, 'voice');
    console.log('Tick 3 Result:', tick3);

    // Tick 4 (Minute 4): Call is still active, Telecaller Mode is still OFF -> Must SKIP rose credit!
    console.log('\n[Tick 4] Call Minute 4 (is_telecaller = FALSE)...');
    const tick4 = await RoseService.creditRoseForCallMinute(femaleId, callId, 'voice');
    console.log('Tick 4 Result:', tick4);

    // Fetch final Rose Transactions ledger
    let ledgerFinal = await db.query(
      'SELECT id, amount, type, reason, reference_id, created_at FROM public.rose_transactions WHERE user_id = $1 ORDER BY created_at ASC',
      [femaleId]
    );
    const finalBalance = await RoseService.getRoseBalance(femaleId);

    console.log(`\n📊 Rose Transactions AFTER toggle (${ledgerFinal.rows.length} rows total):`);
    console.table(ledgerFinal.rows.map(r => ({
      id: r.id.substring(0, 8) + '...',
      amount: r.amount,
      type: r.type,
      reason: r.reason,
      createdAt: r.created_at.toISOString()
    })));
    console.log(`Final Rose Balance in DB: ${finalBalance} roses.`);

    if (ledgerFinal.rows.length !== 2) {
      throw new Error(`Expected exactly 2 transactions in ledger, but found ${ledgerFinal.rows.length}`);
    }
    if (finalBalance !== 2) {
      throw new Error(`Expected final balance to remain 2, but got ${finalBalance}`);
    }
    console.log('\n✅ MID-CALL TOGGLE VERIFICATION PASSED SUCCESSFULLY!');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 2: Direct API Withdrawal Rejection Test (HTTP 403 Server-Side)
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n====================================================');
    console.log('--- TEST 2: Direct API POST /withdrawals Rejection ---');
    console.log('====================================================');

    // Sign JWT token for the non-telecaller female user
    const token = jwt.sign({ id: femaleId, phone: femalePhone }, JWT_SECRET, { expiresIn: '1h' });

    console.log(`Sending direct HTTP POST /api/withdrawals request as non-telecaller user (${femaleId})...`);

    // Start temporary local HTTP server for testing
    const serverApp = require('./server').app;
    const testPort = 3999;
    const serverInstance = serverApp.listen(testPort);

    try {
      const response = await fetch(`http://localhost:${testPort}/api/withdrawals`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ roseAmount: 1 })
      });

      const responseBody = await response.json();

      console.log(`\nHTTP Response Status Code: ${response.status}`);
      console.log(`HTTP Response Body:`, JSON.stringify(responseBody, null, 2));

      if (response.status !== 403) {
        throw new Error(`Expected HTTP 403 Forbidden, but received HTTP ${response.status}`);
      }
      if (!responseBody.error || !responseBody.error.includes('Telecaller mode must be active')) {
        throw new Error(`Unexpected error response message: ${responseBody.error}`);
      }

      console.log('\n✅ BACKEND REJECTION VERIFICATION PASSED SUCCESSFULLY!');
    } finally {
      serverInstance.close();
    }

    console.log('\n====================================================');
    console.log('🎉 ALL AUTOMATED TELECALLER VERIFICATIONS PASSED!');
    console.log('====================================================\n');

  } catch (err) {
    console.error('❌ Verification test failed:', err);
  } finally {
    process.exit(0);
  }
}

runTelecallerVerificationTests();
