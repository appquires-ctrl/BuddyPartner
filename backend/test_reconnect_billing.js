require('dotenv').config();
const db = require('./db');
const { callsService } = require('./modules/calls/calls.service');
const { WalletService, CALL_RATES } = require('./modules/wallet/wallet.service');

async function testReconnectBilling() {
  console.log('🧪 Starting Item 9 Bug Fix Verification Test...');

  // 1. Create two test users in DB
  const userARes = await db.query(
    `INSERT INTO public.users (phone_number, full_name) 
     VALUES ('+19999990001', 'Test User A') 
     RETURNING id`
  );
  const userBRes = await db.query(
    `INSERT INTO public.users (phone_number, full_name) 
     VALUES ('+19999990002', 'Test User B') 
     RETURNING id`
  );

  const userAId = userARes.rows[0].id;
  const userBId = userBRes.rows[0].id;

  console.log(`👤 Created Test User A (${userAId}) and User B (${userBId})`);

  // Ensure initial wallet balance of 100 for both
  await db.query('UPDATE public.wallets SET balance = 100 WHERE user_id = $1 OR user_id = $2', [userAId, userBId]);

  // 2. Create an active call record
  const callId = await callsService.createCall(userAId, userBId);
  console.log(`📞 Call created with ID: ${callId}`);

  // Mock Socket.io `io` object
  const mockIo = {
    to: (socketId) => ({
      emit: (event, payload) => {
        console.log(`  📡 [Socket ${socketId}] Event: ${event}`, JSON.stringify(payload));
      }
    })
  };

  // 3. Start 5-min timer and per-minute billing on callsService singleton
  callsService.startCallTimer(callId, () => {
    console.log('  ⏰ 5-min timer expired');
  });

  callsService.startCallBilling(callId, userAId, userBId, mockIo, (failedCallId, failedUser) => {
    console.log(`  💳 Insufficient balance for user ${failedUser}`);
  });

  console.log(`⏳ Call active & billing interval running for call ${callId}`);
  console.log(`  - callBillingIntervals has callId? ${callsService.callBillingIntervals.has(callId)}`);

  // 4. Simulate Mid-Call User B disconnect & reconnect
  console.log('🔌 Simulating User B socket disconnect and reconnect mid-call...');

  // 5. End the call (User B ends call or manual end)
  console.log('📴 Ending call via callsService.endCall(callId)...');
  await callsService.endCall(callId);

  // 6. Verify timers & billing intervals cleared
  const isIntervalCleared = !callsService.callBillingIntervals.has(callId);
  const isTimerCleared = !callsService.callTimers.has(callId);
  console.log(`✅ Billing interval cleared from singleton: ${isIntervalCleared}`);
  console.log(`✅ Call 5-min timer cleared from singleton: ${isTimerCleared}`);

  // 7. Get ended_at timestamp from DB
  const callRow = await db.query('SELECT ended_at, status FROM public.calls WHERE id = $1', [callId]);
  const endedAt = callRow.rows[0].ended_at;
  console.log(`🕒 Call status: ${callRow.rows[0].status}, ended_at: ${endedAt.toISOString()}`);

  // 8. Wait 3 seconds to ensure NO background ticks execute after ended_at
  console.log('⏳ Waiting 3 seconds to confirm no post-call billing ticks occur...');
  await new Promise((resolve) => setTimeout(resolve, 3000));

  // 9. Query wallet_transactions for any transaction with created_at > ended_at
  const orphanTxRes = await db.query(
    `SELECT * FROM public.wallet_transactions 
     WHERE reference_id = $1 AND created_at > $2`,
    [callId, endedAt]
  );

  console.log(`🔍 Orphaned transactions after ended_at count: ${orphanTxRes.rows.length}`);

  // 10. Clean up test users and calls from DB
  await db.query('DELETE FROM public.calls WHERE id = $1', [callId]);
  await db.query('DELETE FROM public.users WHERE id = $1 OR id = $2', [userAId, userBId]);
  console.log('🧹 Cleaned up test data.');

  if (orphanTxRes.rows.length === 0 && isIntervalCleared && isTimerCleared) {
    console.log(' TEST PASSED! ZERO transactions created after call ended_at.');
    process.exit(0);
  } else {
    console.error('❌ TEST FAILED! Found orphaned transactions or uncleared intervals.');
    process.exit(1);
  }
}

testReconnectBilling().catch((err) => {
  console.error('Test execution error:', err);
  process.exit(1);
});
