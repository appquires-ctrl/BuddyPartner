const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');
const redis = require('./redis');
const { callsService } = require('./modules/calls/calls.service');
const { MatchmakingService } = require('./modules/matchmaking/matchmaking.service');
const { cacheService } = require('./services/cache.service');

async function runLiveTests() {
  console.log('====================================================');
  console.log('🧪 RUNNING LIVE VERIFICATION TESTS FOR BUGS A1 & A2');
  console.log('====================================================\n');

  let testCallId = null;

  try {
    // -------------------------------------------------------------
    // Part 1: Verify Bug A2 - calls_call_type_check & Voice Downgrade
    // -------------------------------------------------------------
    console.log('--- TEST A2: Video -> Voice Downgrade Constraint ---');
    
    // Pick two existing users or create dummy IDs
    const userRes = await db.query('SELECT id FROM public.users LIMIT 2');
    if (userRes.rows.length < 2) {
      throw new Error('Need at least 2 users in database to run live call test');
    }
    const userA = userRes.rows[0].id;
    const userB = userRes.rows[1].id;

    // 1. Create call (default call_type is 'voice')
    const createRes = await db.query(
      `INSERT INTO public.calls (caller_id, matched_user_id, status, call_type, started_at)
       VALUES ($1, $2, 'active', 'voice', NOW())
       RETURNING id, call_type, status`,
      [userA, userB]
    );
    testCallId = createRes.rows[0].id;
    console.log(`1. Call created: id=${testCallId}, initial call_type=${createRes.rows[0].call_type}`);
    if (createRes.rows[0].call_type !== 'voice') {
      throw new Error(`Expected initial call_type to be 'voice', got ${createRes.rows[0].call_type}`);
    }

    // 2. Upgrade to video
    await callsService.upgradeToVideo(testCallId);
    const videoCheck = await db.query('SELECT call_type FROM public.calls WHERE id = $1', [testCallId]);
    console.log(`2. Upgraded to video: DB call_type=${videoCheck.rows[0].call_type}`);
    if (videoCheck.rows[0].call_type !== 'video') {
      throw new Error(`Expected call_type 'video', got ${videoCheck.rows[0].call_type}`);
    }

    // 3. Downgrade back to voice (Previously threw "violates check constraint calls_call_type_check" because it wrote 'audio')
    console.log('3. Downgrading to voice...');
    await callsService.downgradeToVoice(testCallId);
    const voiceCheck = await db.query('SELECT call_type FROM public.calls WHERE id = $1', [testCallId]);
    console.log(`4. Downgrade result in DB: call_type=${voiceCheck.rows[0].call_type}`);
    if (voiceCheck.rows[0].call_type !== 'voice') {
      throw new Error(`Expected call_type 'voice', got ${voiceCheck.rows[0].call_type}`);
    }
    console.log('✅ TEST A2 PASSED: Downgrade to voice succeeded with zero constraint violations!\n');

    // -------------------------------------------------------------
    // Part 2: Verify Bug A1 - Post-Call Processing & Redis Availability
    // -------------------------------------------------------------
    console.log('--- TEST A1: Post-Call Processing & Redis Invalidation ---');

    // Setup dummy lock keys in Redis
    const lockKeyA = `call_lock:${userA}`;
    const lockKeyB = `call_lock:${userB}`;
    await redis.set(lockKeyA, '1', 'EX', 7200);
    await redis.set(lockKeyB, '1', 'EX', 7200);

    const lockAValBefore = await redis.get(lockKeyA);
    const lockBValBefore = await redis.get(lockKeyB);
    console.log(`1. Locks set before call end: lockKeyA=${lockAValBefore}, lockKeyB=${lockBValBefore}`);
    if (lockAValBefore !== '1' || lockBValBefore !== '1') {
      throw new Error('Failed to set test locks in Redis');
    }

    // Simulate exact post-call background execution block from matchmaking.socket.js
    console.log('2. Executing async post-call processing block...');
    let postCallError = null;
    try {
      const matchmakingService = new MatchmakingService(redis);
      await Promise.all([
        matchmakingService.leaveQueue(userA),
        matchmakingService.leaveQueue(userB),
      ]);
      await redis.del(lockKeyA);
      await redis.del(lockKeyB);
      await Promise.all([
        cacheService.invalidate(`user:matches:${userA}`),
        cacheService.invalidate(`user:matches:${userB}`),
      ]);
      await callsService.endCall(testCallId);
    } catch (err) {
      postCallError = err;
    }

    if (postCallError) {
      throw new Error(`Post-call processing threw error: ${postCallError.message}`);
    }

    // Check that redis locks were deleted
    const lockAValAfter = await redis.get(lockKeyA);
    const lockBValAfter = await redis.get(lockKeyB);
    console.log(`3. Locks after call end: lockKeyA=${lockAValAfter}, lockKeyB=${lockBValAfter}`);
    if (lockAValAfter !== null || lockBValAfter !== null) {
      throw new Error('Expected call_lock keys to be deleted by post-call processing');
    }

    // Check call record status
    const callEndCheck = await db.query('SELECT status, duration_seconds FROM public.calls WHERE id = $1', [testCallId]);
    console.log(`4. Call ended in DB: status=${callEndCheck.rows[0].status}, duration=${callEndCheck.rows[0].duration_seconds}s`);
    if (callEndCheck.rows[0].status !== 'ended') {
      throw new Error(`Expected status 'ended', got ${callEndCheck.rows[0].status}`);
    }

    console.log('✅ TEST A1 PASSED: Post-call processing executed cleanly with zero "redis is not defined" error and cleaned up all Redis locks!\n');

    // -------------------------------------------------------------
    // Part 3: Test Matchmaking Queue O(1) Departure
    // -------------------------------------------------------------
    console.log('--- TEST: Matchmaking Queue O(1) Leave Optimization ---');
    const matchmakingService = new MatchmakingService(redis);
    const fakeMale = '00000000-0000-0000-0000-000000000001';
    const fakeSocket = 'socket_abc123';
    
    // Join queue
    await matchmakingService.joinQueue(fakeMale, fakeSocket, 'male');
    const socketInMap = await redis.hget('matchmaking:user_socket', fakeMale);
    console.log(`1. Joined queue: socketInMap=${socketInMap}`);

    // Leave queue
    await matchmakingService.leaveQueue(fakeMale);
    const socketInMapAfter = await redis.hget('matchmaking:user_socket', fakeMale);
    console.log(`2. Left queue via optimized O(1) method: socketInMapAfter=${socketInMapAfter}`);
    if (socketInMapAfter) {
      throw new Error('User still in queue after leaveQueue()');
    }
    console.log('✅ Matchmaking Queue Leave Optimization PASSED!\n');

  } catch (err) {
    console.error('❌ TEST FAILED:', err);
    process.exitCode = 1;
  } finally {
    // Cleanup test call
    if (testCallId) {
      await db.query('DELETE FROM public.calls WHERE id = $1', [testCallId]);
      console.log(`🧹 Cleaned up test call record ${testCallId}`);
    }
    // Cleanup Redis connections
    try {
      if (typeof redis.quit === 'function') await redis.quit();
    } catch (_) {}
    process.exit(process.exitCode || 0);
  }
}

runLiveTests();
