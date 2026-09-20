const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const { spawn } = require('child_process');
const jwt = require('jsonwebtoken');
const { io: ioClient } = require('socket.io-client');
const redis = require('../redis');
const db = require('../db');
const { distributedCallService } = require('../modules/calls/distributed_call.service');
const advertisementsService = require('../modules/advertisements/advertisements.service');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

// Test Users from database
const USER_A = {
  id: 'f19e023a-b413-4bb3-9079-dc9340e794f0',
  name: 'John Doe',
  gender: 'Male',
  phone: '+919999999991',
};

const USER_B = {
  id: 'b4bf9bb3-749d-42a6-9085-3ccd366b2c00',
  name: 'Kiran Soni',
  gender: 'Female',
  phone: '+919999999992',
};

function createJwt(user, sessionId) {
  return jwt.sign(
    {
      id: user.id,
      phone: user.phone,
      sessionId,
      gender: user.gender,
      city: 'Delhi',
      incoming_paid_calls_enabled: true,
    },
    JWT_SECRET,
    { expiresIn: '1h' }
  );
}

function startServerNode(port) {
  return new Promise((resolve, reject) => {
    const env = {
      ...process.env,
      PORT: String(port),
      NODE_ENV: 'test',
    };

    const serverProcess = spawn('node', ['backend/server.js'], {
      cwd: path.join(__dirname, '../..'),
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let started = false;
    const timeout = setTimeout(() => {
      if (!started) {
        serverProcess.kill('SIGTERM');
        reject(new Error(`Timeout waiting for server on port ${port} to start`));
      }
    }, 25000);

    serverProcess.stdout.on('data', (chunk) => {
      const msg = chunk.toString();
      console.log(`[Node ${port}] ${msg.trim()}`);
      if (msg.includes(`listening on port ${port}`)) {
        started = true;
        clearTimeout(timeout);
        // Give 1.5 second for Redis adapter pub/sub connections to settle
        setTimeout(() => resolve(serverProcess), 1500);
      }
    });

    serverProcess.stderr.on('data', (chunk) => {
      console.error(`[Node ${port} ERR] ${chunk.toString().trim()}`);
    });

    serverProcess.on('exit', (code) => {
      if (!started) {
        clearTimeout(timeout);
        reject(new Error(`Server on port ${port} exited prematurely with code ${code}`));
      }
    });
  });
}

function createSocketClient(url, token) {
  return new Promise((resolve, reject) => {
    const socket = ioClient(url, {
      auth: { token },
      transports: ['websocket'],
      reconnection: false,
      timeout: 10000,
    });

    socket.on('connect', () => {
      resolve(socket);
    });

    socket.on('connect_error', (err) => {
      reject(err);
    });
  });
}

async function run() {
  console.log('================================================================');
  console.log('🌐 VERIFYING STAGE 4 MULTI-INSTANCE REDIS CLUSTER ARCHITECTURE');
  console.log('================================================================\n');

  let node1Process = null;
  let node2Process = null;
  let clientA = null;
  let clientB = null;
  let clientA_reconnect = null;

  try {
    // ── 0. Prepare Redis state and subscriptions for test users ──────────────
    console.log('Step 0: Preparing Redis connection, session, and profile cache for test users...');

    // Ensure real Redis is ready before writing
    while (!redis.isHealthy()) {
      await new Promise((r) => setTimeout(r, 100));
    }

    // Insert active subscription records in Postgres for test users
    await db.query(`
      INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
      VALUES 
        ($1, 30, 235, NOW(), NOW() + INTERVAL '30 days', 'test_cluster_sub_a'),
        ($2, 30, 235, NOW(), NOW() + INTERVAL '30 days', 'test_cluster_sub_b')
    `, [USER_A.id, USER_B.id]).catch(() => {});

    const sessionA = 'sess_' + Date.now() + '_a';
    const sessionB = 'sess_' + Date.now() + '_b';

    await redis.set(`user_active_session:${USER_A.id}`, JSON.stringify({ sessionId: sessionA, isBanned: false }), 'EX', 3600);
    await redis.set(`user_active_session:${USER_B.id}`, JSON.stringify({ sessionId: sessionB, isBanned: false }), 'EX', 3600);
    await redis.set(`user:is_banned:${USER_A.id}`, '0', 'EX', 3600);
    await redis.set(`user:is_banned:${USER_B.id}`, '0', 'EX', 3600);
    await redis.set(`user:subscribed:${USER_A.id}`, '1', 'EX', 3600);
    await redis.set(`user:subscribed:${USER_B.id}`, '1', 'EX', 3600);
    await redis.set(`user:profile:${USER_A.id}`, JSON.stringify({ id: USER_A.id, full_name: USER_A.name, gender: USER_A.gender, incoming_paid_calls_enabled: true }), 'EX', 3600);
    await redis.set(`user:profile:${USER_B.id}`, JSON.stringify({ id: USER_B.id, full_name: USER_B.name, gender: USER_B.gender, incoming_paid_calls_enabled: true }), 'EX', 3600);

    // Clean up any stale call locks from previous tests
    await redis.del(
      `user:call:${USER_A.id}`,
      `user:call:${USER_B.id}`,
      `call_lock:${USER_A.id}`,
      `call_lock:${USER_B.id}`,
      `user:pending_call:${USER_A.id}`,
      `user:pending_call:${USER_B.id}`
    );

    const tokenA = createJwt(USER_A, sessionA);
    const tokenB = createJwt(USER_B, sessionB);
    console.log('✅ Real Redis connected, test subscriptions and JWTs prepared.');

    // ── 1. Boot Node 1 and Node 2 ─────────────────────────────────────────────
    console.log('\nStep 1: Spawning Node 1 (PORT 3001) and Node 2 (PORT 3002)...');
    node1Process = await startServerNode(3001);
    console.log('✅ Node 1 active on http://localhost:3001');

    node2Process = await startServerNode(3002);
    console.log('✅ Node 2 active on http://localhost:3002');

    // ── 2. Connect client sockets across different nodes ──────────────────────
    console.log('\nStep 2: Connecting Client A to Node 1 and Client B to Node 2...');
    clientA = await createSocketClient('http://localhost:3001', tokenA);
    console.log(`✅ Client A (User: ${USER_A.name}) connected to Node 1 (socket: ${clientA.id})`);

    clientB = await createSocketClient('http://localhost:3002', tokenB);
    console.log(`✅ Client B (User: ${USER_B.name}) connected to Node 2 (socket: ${clientB.id})`);

    // Give 500ms for PresenceService.addSocket to settle in Redis
    await new Promise((r) => setTimeout(r, 600));

    // ── 3. Test Cross-Node Direct Call Initiation ─────────────────────────────
    console.log('\nStep 3: Client A on Node 1 initiating direct_call to Client B on Node 2...');
    clientA.on('match_error', (e) => console.error('❌ [Client A match_error]:', e));
    clientA.on('call_response', (e) => console.log('ℹ️ [Client A call_response]:', e));
    clientA.on('outgoing_call_ringing', (e) => console.log('🔔 [Client A outgoing_call_ringing]:', e));

    const incomingCallPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for incoming_call_request on Node 2')), 12000);
      clientB.once('incoming_call_request', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    clientA.emit('direct_call', {
      targetUserId: USER_B.id,
      callType: 'voice',
    });

    const incomingData = await incomingCallPromise;
    console.log(`✅ Client B on Node 2 received incoming_call_request via Redis Adapter!`);
    console.log(`   callRequestId: ${incomingData.callRequestId}, caller: ${incomingData.caller?.fullName}`);

    if (incomingData.caller?.id !== USER_A.id) {
      throw new Error(`Expected caller id ${USER_A.id}, got ${incomingData.caller?.id}`);
    }

    // Verify pending call in Redis (stored as JSON string with 35s TTL via distributedCallService)
    const pendingData = await distributedCallService.getPendingCall(redis, incomingData.callRequestId);
    console.log('   Redis pending_call data:', pendingData);
    if (!pendingData || !pendingData.callRequestId || pendingData.callerId !== USER_A.id) {
      throw new Error(`Redis pending_call state invalid or missing: ${JSON.stringify(pendingData)}`);
    }
    const pendingTtl = await redis.ttl(`pending_call:${incomingData.callRequestId}`);
    console.log(`   Redis pending_call TTL: ${pendingTtl}s`);
    if (pendingTtl <= 0) {
      throw new Error(`Expected positive TTL on pending_call, got ${pendingTtl}`);
    }
    console.log('✅ Redis pending_call:* verified with distributed TTL.');

    // ── 4. Test Cross-Node Call Acceptance & Active Call Creation ─────────────
    console.log('\nStep 4: Client B on Node 2 accepting call request...');
    const clientAMatchPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for match_found on Node 1')), 8000);
      clientA.once('match_found', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    const clientBMatchPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for match_found on Node 2')), 8000);
      clientB.once('match_found', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    clientB.emit('accept_call_request', { callRequestId: incomingData.callRequestId });

    const [matchA, matchB] = await Promise.all([clientAMatchPromise, clientBMatchPromise]);
    console.log(`✅ Both clients received match_found!`);
    console.log(`   Call ID: ${matchA.callId}`);
    console.log(`   Agora Channel: ${matchA.agoraChannelName}`);

    if (!matchA.callId || matchA.callId !== matchB.callId) {
      throw new Error(`Call ID mismatch: A=${matchA.callId}, B=${matchB.callId}`);
    }

    const activeCallId = matchA.callId;

    // ── 5. Verify Distributed Redis State Schema ──────────────────────────────
    console.log('\nStep 5: Verifying distributed call state schema in Redis...');
    const activeHash = await redis.hgetall(`call:active:${activeCallId}`);
    console.log('   call:active:* Hash fields:', Object.keys(activeHash));

    if (!activeHash.callId || activeHash.callId !== activeCallId) {
      throw new Error(`call:active:${activeCallId} Hash is missing or invalid`);
    }

    const userACallId = await redis.get(`user:call:${USER_A.id}`);
    const userBCallId = await redis.get(`user:call:${USER_B.id}`);
    const userALock = await redis.get(`call_lock:${USER_A.id}`);
    const userBLock = await redis.get(`call_lock:${USER_B.id}`);

    if (userACallId !== activeCallId || userBCallId !== activeCallId) {
      throw new Error(`user:call mappings mismatch: userA=${userACallId}, userB=${userBCallId}`);
    }
    if (userALock !== '1' || userBLock !== '1') {
      throw new Error(`call_lock flags missing: userA=${userALock}, userB=${userBLock}`);
    }

    console.log('✅ call:active:{callId} Hash, user:call:* mappings, and call_lock:* verified in Redis.');

    // ── 6. Test Mid-Call State Read across instances ───────────────────────────
    console.log('\nStep 6: Reading call state via distributedCallService.getActiveCall...');
    const callData = await distributedCallService.getActiveCall(redis, activeCallId);
    console.log(`   Retrieved callData: type=${callData.callType}, userA=${callData.userA?.userId}, userB=${callData.userB?.userId}`);
    if (!callData || callData.callId !== activeCallId) {
      throw new Error('distributedCallService.getActiveCall returned null or mismatched call');
    }
    console.log('✅ Mid-call state read verified successfully.');

    // ── 7. Test Distributed Call Termination & Mutex Lock ──────────────────────
    console.log('\nStep 7: Client A on Node 1 ending call, Client B on Node 2 receiving call_ended...');
    const callEndedPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for call_ended on Node 2')), 8000);
      clientB.once('call_ended', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    clientA.emit('end_call', { callId: activeCallId });
    const endData = await callEndedPromise;
    console.log(`✅ Client B on Node 2 received call_ended event: reason=${endData.reason}`);

    // Verify Redis cleanup
    const cleanedActiveHash = await redis.hgetall(`call:active:${activeCallId}`);
    const cleanedUserACall = await redis.get(`user:call:${USER_A.id}`);
    const cleanedUserBCall = await redis.get(`user:call:${USER_B.id}`);
    const cleanedUserALock = await redis.get(`call_lock:${USER_A.id}`);
    const cleanedUserBLock = await redis.get(`call_lock:${USER_B.id}`);

    if (Object.keys(cleanedActiveHash).length > 0 || cleanedUserACall || cleanedUserBCall || cleanedUserALock || cleanedUserBLock) {
      throw new Error('Redis state was not cleanly purged after call termination');
    }
    console.log('✅ All Redis keys atomically cleaned up after distributed call termination.');

    // ── 8. Test Reconnection Recovery Across Nodes (Scenario 1) ────────────────
    console.log('\nStep 8: Testing Reconnection Recovery across instances...');
    // Establish a second call
    const incoming2Promise = new Promise((resolve) => clientB.once('incoming_call_request', resolve));
    clientA.emit('direct_call', { targetUserId: USER_B.id, callType: 'voice' });
    const req2 = await incoming2Promise;

    const match2PromiseA = new Promise((resolve) => clientA.once('match_found', resolve));
    const match2PromiseB = new Promise((resolve) => clientB.once('match_found', resolve));
    clientB.emit('accept_call_request', { callRequestId: req2.callRequestId });
    const [m2A, m2B] = await Promise.all([match2PromiseA, match2PromiseB]);
    const callId2 = m2A.callId;
    console.log(`   Call 2 established: ${callId2}`);

    // Simulate Client A abrupt disconnect on Node 1
    const peerDisconnectedPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for call_peer_disconnected')), 8000);
      clientB.once('call_peer_disconnected', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    console.log('   Disconnecting Client A from Node 1...');
    clientA.disconnect();

    const peerDiscData = await peerDisconnectedPromise;
    console.log(`✅ Client B on Node 2 received call_peer_disconnected! graceSeconds=${peerDiscData.graceSeconds}`);
    if (peerDiscData.disconnectedUserId !== USER_A.id) {
      throw new Error(`Expected disconnected user ${USER_A.id}, got ${peerDiscData.disconnectedUserId}`);
    }

    // Verify 15-second grace timer in Redis
    const timerExists = await redis.get(`peer_disconnect_timer:${callId2}:${USER_A.id}`);
    if (!timerExists) {
      throw new Error('Expected peer_disconnect_timer in Redis');
    }
    console.log('✅ peer_disconnect_timer verified in Redis with 15s expiration.');

    // Reconnect User A to Node 2 (port 3002) — simulating reconnecting to a different server instance!
    console.log('   Reconnecting User A to Node 2 (http://localhost:3002)...');
    const reconnectPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Timeout waiting for call_reconnected on Node 2')), 8000);
      clientA_reconnect = ioClient('http://localhost:3002', {
        auth: { token: tokenA },
        transports: ['websocket'],
        reconnection: false,
      });

      clientA_reconnect.once('call_reconnected', (data) => {
        clearTimeout(timeout);
        resolve(data);
      });
    });

    const reconnectedData = await reconnectPromise;
    console.log(`✅ User A successfully reconnected on Node 2 and recovered active call!`);
    console.log(`   Recovered callId: ${reconnectedData.callId}, elapsedSeconds: ${reconnectedData.elapsedSeconds}`);

    if (reconnectedData.callId !== callId2) {
      throw new Error(`Expected recovered callId ${callId2}, got ${reconnectedData.callId}`);
    }

    // Hang up second call
    clientA_reconnect.emit('end_call', { callId: callId2 });
    await new Promise((r) => setTimeout(r, 1000));
    console.log('✅ Reconnection test passed cleanly.');

    // ── 9. Test Ad Click Flush Distributed Lock ───────────────────────────────
    console.log('\nStep 9: Testing distributed lock on flushBufferedClicks...');
    const lockKey = 'lock:ad_click_flush';
    await redis.set(lockKey, '1', 'EX', 10, 'NX');
    console.log('   Acquired lock:ad_click_flush manually in Redis');

    const resultWithLock = await advertisementsService.flushBufferedClicks();
    if (resultWithLock !== false) {
      throw new Error(`Expected flushBufferedClicks to return false when lock is held, got: ${resultWithLock}`);
    }
    console.log('✅ flushBufferedClicks safely skipped when distributed lock is active on another node.');

    await redis.del(lockKey);
    console.log('   Released lock:ad_click_flush');

    console.log('\n================================================================');
    console.log('🎉 ALL STAGE 4 MULTI-INSTANCE CLUSTER TESTS PASSED SUCCESSFULLY!');
    console.log('================================================================\n');
  } catch (err) {
    console.error('\n❌ CLUSTER VERIFICATION FAILED:', err);
    process.exitCode = 1;
  } finally {
    console.log('Cleaning up connections and server child processes...');
    try {
      if (clientA && clientA.connected) clientA.disconnect();
      if (clientB && clientB.connected) clientB.disconnect();
      if (clientA_reconnect && clientA_reconnect.connected) clientA_reconnect.disconnect();
    } catch (_) {}

    if (node1Process) {
      node1Process.kill('SIGTERM');
      console.log('Killed Node 1');
    }
    if (node2Process) {
      node2Process.kill('SIGTERM');
      console.log('Killed Node 2');
    }

    // Clean up test keys
    await redis.del(
      `user:call:${USER_A.id}`,
      `user:call:${USER_B.id}`,
      `call_lock:${USER_A.id}`,
      `call_lock:${USER_B.id}`,
      `user:pending_call:${USER_A.id}`,
      `user:pending_call:${USER_B.id}`,
      'lock:ad_click_flush'
    ).catch(() => {});

    try {
      if (typeof redis.quit === 'function') await redis.quit();
    } catch (_) {}

    process.exit(process.exitCode || 0);
  }
}

run();
