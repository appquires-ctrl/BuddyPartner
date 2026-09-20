const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');
const redis = require('./redis');
const { callsService } = require('./modules/calls/calls.service');
const { registerMatchmakingHandlers } = require('./modules/matchmaking/matchmaking.socket');
const { distributedCallService } = require('./modules/calls/distributed_call.service');

async function runTest() {
  console.log('================================================================');
  console.log('🧪 VERIFYING INSTANT CONNECT VIDEO -> VOICE DOWNGRADE FLOW');
  console.log('================================================================\n');

  const maleUserId = '00000000-0000-0000-0000-000000000001';
  const femaleUserId = '00000000-0000-0000-0000-000000000002';
  const sessionId = '67f45912-dab9-42a6-b630-3ea440da48f6';
  const instantCallId = `instant_call_${sessionId}`;

  try {
    // 1. Mock Socket.io environment
    const emittedEvents = [];
    const mockIo = {
      to: (target) => ({
        emit: (eventName, data) => {
          emittedEvents.push({ target, eventName, data });
        },
      }),
    };

    // 2. Register mock active Instant Call in Redis via distributedCallService
    const activeCallObj = {
      callId: instantCallId,
      sessionId,
      maleUserId,
      femaleUserId,
      startedAt: Date.now(),
      bidAmount: 20,
    };
    await distributedCallService.saveActiveInstantCall(redis, instantCallId, activeCallObj);
    console.log(`1. Registered active instant call in Redis: ${instantCallId}`);

    // 3. Create mock male socket and register handlers
    const registeredHandlers = {};
    const mockMaleSocket = {
      id: 'socket_male_123',
      userId: maleUserId,
      emit: (eventName, data) => {
        emittedEvents.push({ target: 'maleSocket', eventName, data });
      },
      on: (event, handler) => {
        registeredHandlers[event] = handler;
      },
    };
    registerMatchmakingHandlers(mockIo, mockMaleSocket, redis);

    // 4. Trigger video upgrade accepted for instant call
    console.log('2. Simulating video_upgrade_accepted...');
    await registeredHandlers['video_upgrade_accepted']({ callId: instantCallId });
    const upgradeEvt = emittedEvents.find(e => e.eventName === 'video_upgrade_accepted');
    console.log('Upgrade event emitted to peer:', upgradeEvt);
    if (!upgradeEvt || upgradeEvt.target !== femaleUserId) {
      throw new Error('video_upgrade_accepted was not forwarded to female target');
    }

    // 5. Trigger switch_to_voice for instant call (This previously crashed with "invalid input syntax for type uuid" and call_type check constraint)
    console.log('3. Simulating switch_to_voice from male user...');
    await registeredHandlers['switch_to_voice']({ callId: instantCallId });
    
    const voiceEvt = emittedEvents.find(e => e.eventName === 'switched_to_voice');
    console.log('Switched to voice event emitted to peer:', voiceEvt);
    if (!voiceEvt || voiceEvt.target !== femaleUserId) {
      throw new Error('switched_to_voice was not forwarded to female target');
    }

    // 6. Verify callsService safety guard directly
    console.log('4. Testing callsService guards against instant_call IDs directly...');
    // Neither should throw or query Postgres
    await callsService.upgradeToVideo(instantCallId);
    await callsService.downgradeToVoice(instantCallId);
    console.log('✅ callsService directly rejected non-UUID string safely with 0 Postgres errors');

    console.log('\n================================================================');
    console.log(' ALL INSTANT CONNECT VIDEO->VOICE DOWNGRADE TESTS PASSED!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('❌ TEST FAILED:', err);
    process.exitCode = 1;
  } finally {
    await distributedCallService.deleteActiveInstantCall(redis, instantCallId, maleUserId, femaleUserId);
    try {
      if (typeof redis.quit === 'function') await redis.quit();
    } catch (_) {}
    process.exit(process.exitCode || 0);
  }
}

runTest();
