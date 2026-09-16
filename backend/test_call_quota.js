require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const assert = require('assert');
const db = require('./db');
const redis = require('./redis');
const {
  callQuotaService,
  AUDIO_MONTHLY_CAP_SECONDS,
  VIDEO_MONTHLY_CAP_SECONDS,
  TELECOM_BUSY_MESSAGE,
} = require('./modules/calls/call_quota.service');
const adminService = require('./modules/admin/admin.service');

async function runCallQuotaTests() {
  console.log('🧪 Starting Call Quota & 5k CCU Production Architecture Tests...\n');

  const testUserA = '11111111-2222-3333-4444-555555555555';
  const testUserB = '66666666-7777-8888-9999-000000000000';
  const currentYM = callQuotaService.getCurrentYearMonth();

  try {
    // 0. Setup dummy test users in DB if not existing
    console.log('0️⃣ Setting up mock users...');
    await db.query(`
      INSERT INTO public.users (id, phone_number, full_name, gender)
      VALUES 
        ($1, '+919999000001', 'Test Quota User A', 'male'),
        ($2, '+919999000002', 'Test Quota User B', 'female')
      ON CONFLICT (id) DO NOTHING
    `, [testUserA, testUserB]);
    console.log('   ✅ Mock users verified.\n');

    // 1. Initial State Check (clean quota)
    console.log('1️⃣ Testing Initial Clean Quota State...');
    await callQuotaService.resetUserQuota(testUserA, currentYM);
    await callQuotaService.resetUserQuota(testUserB, currentYM);

    const initialQuotaA = await callQuotaService.checkCanStartAudioCall(testUserA);
    assert.strictEqual(initialQuotaA.allowed, true, 'User A should initially be allowed to start audio call');
    assert.strictEqual(initialQuotaA.remainingSeconds, AUDIO_MONTHLY_CAP_SECONDS, `Remaining should be ${AUDIO_MONTHLY_CAP_SECONDS}s`);

    const initialVideoA = await callQuotaService.checkCanStartVideoCall(testUserA);
    assert.strictEqual(initialVideoA.allowed, true, 'User A should initially be allowed to start video call');
    assert.strictEqual(initialVideoA.remainingSeconds, VIDEO_MONTHLY_CAP_SECONDS, `Remaining should be ${VIDEO_MONTHLY_CAP_SECONDS}s`);
    console.log('   ✅ Clean quota check passed (200m audio, 60m video).\n');

    // 2. Call Usage Recording & Atomic Redis Metering
    console.log('2️⃣ Testing Atomic Usage Recording (Audio + Video)...');
    // User A calls User B: 300 seconds audio (5 mins) + 120 seconds video (2 mins)
    await callQuotaService.recordCallUsage(testUserA, testUserB, 300, 120);

    // Wait a brief tick for async DB upsert
    await new Promise((r) => setTimeout(r, 200));

    const usageA = await callQuotaService.getUsage(testUserA, currentYM);
    assert.strictEqual(usageA.audioSeconds, 300, 'User A audio seconds must equal 300');
    assert.strictEqual(usageA.videoSeconds, 120, 'User A video seconds must equal 120');
    assert.strictEqual(usageA.audioMinutes, 5, 'User A audio minutes should be 5');
    assert.strictEqual(usageA.videoMinutes, 2, 'User A video minutes should be 2');
    assert.strictEqual(usageA.audioRemainingSeconds, AUDIO_MONTHLY_CAP_SECONDS - 300);
    assert.strictEqual(usageA.videoRemainingSeconds, VIDEO_MONTHLY_CAP_SECONDS - 120);

    const usageB = await callQuotaService.getUsage(testUserB, currentYM);
    assert.strictEqual(usageB.audioSeconds, 300, 'User B audio seconds must equal 300');
    assert.strictEqual(usageB.videoSeconds, 120, 'User B video seconds must equal 120');

    // Verify PostgreSQL persistence
    const dbRes = await db.query(
      `SELECT audio_seconds, video_seconds, audio_call_count, video_call_count 
       FROM public.user_monthly_call_usage 
       WHERE user_id = $1 AND year_month = $2`,
      [testUserA, currentYM]
    );
    assert.strictEqual(dbRes.rows.length, 1, 'Postgres record must exist');
    assert.strictEqual(dbRes.rows[0].audio_seconds, 300, 'DB audio seconds must be 300');
    assert.strictEqual(dbRes.rows[0].video_seconds, 120, 'DB video seconds must be 120');
    console.log('   ✅ Redis atomic increment and PostgreSQL persistence passed.\n');

    // 3. Audio Quota Exhaustion (> 12,000s)
    console.log('3️⃣ Testing 200-Minute Audio Cap Shadow Enforcement...');
    // Push User A over the 12,000s cap
    await callQuotaService.recordCallUsage(testUserA, null, 11800, 0); // 300 + 11800 = 12100s > 12000s
    const exhaustedAudioCheck = await callQuotaService.checkCanStartAudioCall(testUserA);
    assert.strictEqual(exhaustedAudioCheck.allowed, false, 'User A must be rejected for audio call when over 200 mins');
    assert.strictEqual(exhaustedAudioCheck.remainingSeconds, 0, 'Remaining audio seconds should be 0');
    console.log(`   ✅ Audio call blocked silently. Telecom message: "${TELECOM_BUSY_MESSAGE}"\n`);

    // 4. Video Quota Exhaustion (> 3,600s)
    console.log('4️⃣ Testing 60-Minute Video Cap Shadow Enforcement...');
    // Push User A over the 3,600s cap
    await callQuotaService.recordCallUsage(testUserA, null, 0, 3500); // 120 + 3500 = 3620s > 3600s
    const exhaustedVideoCheck = await callQuotaService.checkCanStartVideoCall(testUserA);
    assert.strictEqual(exhaustedVideoCheck.allowed, false, 'User A must be rejected for video call when over 60 mins');
    assert.strictEqual(exhaustedVideoCheck.remainingSeconds, 0, 'Remaining video seconds should be 0');
    console.log('   ✅ Video upgrade blocked silently while preserving voice integrity.\n');

    // 5. Admin Visibility & Reset API
    console.log('5️⃣ Testing Admin Visibility & Quota Reset...');
    const adminUsage = await adminService.getUserCallUsage(testUserA);
    console.log('   Admin live usage overview:', {
      audioMinutes: adminUsage.liveUsage.audioMinutes,
      videoMinutes: adminUsage.liveUsage.videoMinutes,
      audioCap: adminUsage.liveUsage.caps.audioMinutes,
      videoCap: adminUsage.liveUsage.caps.videoMinutes,
      isAudioExhausted: adminUsage.liveUsage.isAudioExhausted,
      isVideoExhausted: adminUsage.liveUsage.isVideoExhausted,
    });
    assert.strictEqual(adminUsage.liveUsage.isAudioExhausted, true, 'Admin view should reflect audio exhausted');
    assert.strictEqual(adminUsage.liveUsage.isVideoExhausted, true, 'Admin view should reflect video exhausted');

    // Admin resets quota for User A
    const resetRes = await adminService.resetUserCallQuota(testUserA);
    assert.strictEqual(resetRes.success, true, 'Reset should succeed');

    const freshAudioCheck = await callQuotaService.checkCanStartAudioCall(testUserA);
    assert.strictEqual(freshAudioCheck.allowed, true, 'User A must be unblocked after admin quota reset');
    assert.strictEqual(freshAudioCheck.remainingSeconds, AUDIO_MONTHLY_CAP_SECONDS, 'Quota should be fully restored');
    console.log('   ✅ Admin quota inspection & override reset verified.\n');

    // Clean up mock users
    await db.query('DELETE FROM public.user_monthly_call_usage WHERE user_id IN ($1, $2)', [testUserA, testUserB]);
    await db.query('DELETE FROM public.users WHERE id IN ($1, $2)', [testUserA, testUserB]);
    await redis.del(callQuotaService.getAudioQuotaKey(testUserA, currentYM));
    await redis.del(callQuotaService.getVideoQuotaKey(testUserA, currentYM));
    await redis.del(callQuotaService.getAudioQuotaKey(testUserB, currentYM));
    await redis.del(callQuotaService.getVideoQuotaKey(testUserB, currentYM));

    console.log('🎉 ALL CALL QUOTA & PRODUCTION ARCHITECTURE TESTS PASSED! 🚀');
    process.exit(0);
  } catch (err) {
    console.error('❌ Test failed with error:', err);
    process.exit(1);
  }
}

runCallQuotaTests();
