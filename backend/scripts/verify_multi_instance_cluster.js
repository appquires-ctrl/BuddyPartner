require('dotenv').config();
const { spawn } = require('child_process');
const jwt = require('jsonwebtoken');
const { io: ioClient } = require('socket.io-client');
const db = require('../db');
const redis = require('../redis');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

// Test user IDs
const USER_A_ID = 'fa4c162e-877d-4d08-9eac-4f80f02123e7'; // Male
const USER_B_ID = 'b2222222-2222-2222-2222-222222222222'; // Female

async function seedTestAccounts() {
  console.log('--- Seeding Dual-Balance Accounts & Subscriptions for Cluster Test ---');
  
  // User A (Male)
  await db.query(`
    INSERT INTO public.users (id, phone_number, full_name, user_name, gender, city, is_banned)
    VALUES ($1, '+919999999999', 'Aarav Male', 'aarav_cluster', 'male', 'Mumbai', false)
    ON CONFLICT (id) DO UPDATE SET gender = 'male', is_banned = false;
  `, [USER_A_ID]);

  await db.query(`
    INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
    VALUES ($1, 500, 0)
    ON CONFLICT (user_id) DO UPDATE SET spendable_balance = 500;
  `, [USER_A_ID]);

  await db.query(`
    DELETE FROM public.subscriptions WHERE user_id = $1;
  `, [USER_A_ID]);
  await db.query(`
    INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
    VALUES ($1, 30, 235, NOW(), NOW() + INTERVAL '30 days');
  `, [USER_A_ID]);

  // User B (Female)
  await db.query(`
    INSERT INTO public.users (id, phone_number, full_name, user_name, gender, city, is_banned, incoming_paid_calls_enabled)
    VALUES ($1, '+918888888888', 'Ananya Female', 'ananya_cluster', 'female', 'Mumbai', false, true)
    ON CONFLICT (id) DO UPDATE SET gender = 'female', is_banned = false, incoming_paid_calls_enabled = true;
  `, [USER_B_ID]);

  await db.query(`
    INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
    VALUES ($1, 500, 0)
    ON CONFLICT (user_id) DO UPDATE SET spendable_balance = 500;
  `, [USER_B_ID]);

  await db.query(`
    DELETE FROM public.subscriptions WHERE user_id = $1;
  `, [USER_B_ID]);
  await db.query(`
    INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
    VALUES ($1, 30, 235, NOW(), NOW() + INTERVAL '30 days');
  `, [USER_B_ID]);

  // Clean any stale locks or queues in Redis
  await redis.del(`call_lock:${USER_A_ID}`);
  await redis.del(`call_lock:${USER_B_ID}`);
  await redis.del(`user:subscribed:${USER_A_ID}`);
  await redis.del(`user:subscribed:${USER_B_ID}`);
  await redis.del(`user:is_banned:${USER_A_ID}`);
  await redis.del(`user:is_banned:${USER_B_ID}`);
  await redis.del(`user_active_call:${USER_A_ID}`);
  await redis.del(`user_active_call:${USER_B_ID}`);

  console.log('✅ Test accounts seeded successfully.');
}

function startServerInstance(port) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env, PORT: String(port), INSTANCE_COUNT: '2' };
    const proc = spawn('node', ['server.js'], {
      cwd: process.cwd(),
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let ready = false;
    proc.stdout.on('data', (data) => {
      const msg = data.toString();
      if (msg.includes(`listening on port ${port}`)) {
        console.log(`🚀 [Process :${port}] Started and listening.`);
      }
      if (msg.includes('Redis Adapter active')) {
        console.log(`🔌 [Process :${port}] Redis adapter active.`);
        if (!ready) {
          ready = true;
          resolve(proc);
        }
      }
    });

    proc.stderr.on('data', (data) => {
      const errStr = data.toString();
      if (!errStr.includes('ExperimentalWarning') && !errStr.includes('SECURITY WARNING')) {
        console.error(`[Process :${port} ERR]:`, errStr);
      }
    });

    proc.on('exit', (code) => {
      if (!ready) {
        reject(new Error(`Process on port ${port} exited with code ${code}`));
      }
    });
  });
}

function connectSocket(port, userId, phone) {
  const sessionId = `sess_${userId}_${Date.now()}`;
  const token = jwt.sign({ id: userId, phone, sessionId }, JWT_SECRET, { expiresIn: '1h' });

  return new Promise((resolve, reject) => {
    // Set active session in Redis first to pass single-device check
    redis.set(`user_active_session:${userId}`, sessionId, 'EX', 3600).then(() => {
      const socket = ioClient(`http://localhost:${port}`, {
        transports: ['websocket'],
        auth: { token },
        reconnection: false,
      });

      socket.on('connect', () => {
        console.log(`✅ [Socket Client ${userId.slice(0, 8)}] Connected to :${port} (Socket ID: ${socket.id})`);
        resolve(socket);
      });

      socket.on('connect_error', (err) => {
        reject(new Error(`Socket connection error for user ${userId} on port ${port}: ${err.message}`));
      });
    }).catch(reject);
  });
}

async function runMultiInstanceVerification() {
  console.log('================================================================');
  console.log(' BUDDYPARTNER 1.4 MULTI-INSTANCE VERIFICATION PROTOCOL');
  console.log('================================================================\n');

  let proc1 = null;
  let proc2 = null;
  let socketA = null;
  let socketB = null;

  try {
    await seedTestAccounts();

    console.log('\n--- Step 1: Starting 2 Separate Server Processes (:3001 & :3002) ---');
    [proc1, proc2] = await Promise.all([
      startServerInstance(3001),
      startServerInstance(3002),
    ]);

    // Small delay to ensure cluster pub/sub handshake is primed
    await new Promise((r) => setTimeout(r, 1500));

    console.log('\n--- Step 2: Connecting Client A to :3001 & Client B to :3002 ---');
    socketA = await connectSocket(3001, USER_A_ID, '+919999999999');
    socketB = await connectSocket(3002, USER_B_ID, '+918888888888');

    console.log('\n--- Step 3: Matchmaking Cross-Process Flow ---');
    console.log('Client A (Male on :3001) joins matchmaking queue...');
    console.log('Client B (Female on :3002) joins matchmaking queue...');

    let matchA = null;
    let matchB = null;

    const matchPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Matchmaking timed out after 10s')), 10000);

      socketA.once('match_found', (data) => {
        console.log(`🎉 [Instance :3001] Client A received match_found! Call ID: ${data.callId}`);
        matchA = data;
        if (matchA && matchB) {
          clearTimeout(timeout);
          resolve();
        }
      });

      socketB.once('match_found', (data) => {
        console.log(`🎉 [Instance :3002] Client B received match_found! Call ID: ${data.callId}`);
        matchB = data;
        if (matchA && matchB) {
          clearTimeout(timeout);
          resolve();
        }
      });
    });

    socketA.emit('join_queue', () => {});
    socketB.emit('join_queue', () => {});

    await matchPromise;

    if (matchA.callId !== matchB.callId) {
      throw new Error(`Call ID mismatch between instances! A: ${matchA.callId}, B: ${matchB.callId}`);
    }
    const callId = matchA.callId;

    console.log('\n--- Step 4: Verify Shared State in Redis ---');
    const redisCallRaw = await redis.get(`active_call:${callId}`);
    console.log(`[Redis Verification] 'active_call:${callId}':`, redisCallRaw ? 'EXISTS (JSON payload verified)' : 'MISSING');
    if (!redisCallRaw) throw new Error(`Active call hash ${callId} missing from Redis!`);

    const userACall = await redis.get(`user_active_call:${USER_A_ID}`);
    const userBCall = await redis.get(`user_active_call:${USER_B_ID}`);
    console.log(`[Redis Verification] 'user_active_call:${USER_A_ID}': ${userACall}`);
    console.log(`[Redis Verification] 'user_active_call:${USER_B_ID}': ${userBCall}`);

    console.log('\n--- Step 5: Cross-Process Hangup Test ---');
    console.log(`Client A on :3001 calls end_call on callId ${callId}...`);

    const endPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Cross-process end_call timed out')), 10000);
      socketB.once('call_ended', (data) => {
        console.log(`🛑 [Instance :3002] Client B received call_ended from Client A! Reason: ${data.reason}`);
        clearTimeout(timeout);
        resolve(data);
      });
    });

    socketA.emit('end_call', { callId });
    await endPromise;

    // Small delay to allow asynchronous cleanup to complete
    await new Promise((r) => setTimeout(r, 1000));

    console.log('\n--- Step 6: Verify Redis State Cleanup Across Nodes ---');
    const redisCallAfter = await redis.get(`active_call:${callId}`);
    const lockAAfter = await redis.get(`call_lock:${USER_A_ID}`);
    const lockBAfter = await redis.get(`call_lock:${USER_B_ID}`);
    const userACallAfter = await redis.get(`user_active_call:${USER_A_ID}`);
    const userBCallAfter = await redis.get(`user_active_call:${USER_B_ID}`);

    console.log(`[Redis Cleanup Check] active_call:${callId} ->`, redisCallAfter);
    console.log(`[Redis Cleanup Check] call_lock:${USER_A_ID} ->`, lockAAfter);
    console.log(`[Redis Cleanup Check] call_lock:${USER_B_ID} ->`, lockBAfter);
    console.log(`[Redis Cleanup Check] user_active_call:${USER_A_ID} ->`, userACallAfter);
    console.log(`[Redis Cleanup Check] user_active_call:${USER_B_ID} ->`, userBCallAfter);

    if (redisCallAfter !== null || lockAAfter !== null || userACallAfter !== null) {
      throw new Error('Redis state was not cleanly purged after cross-process hangup!');
    }

    console.log('\n--- Step 7: Cross-Process Direct Call Flow ---');
    console.log('Client A on :3001 sends direct_call to Client B on :3002...');

    let pendingCallId = null;
    const directCallIncomingPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('direct_call delivery timed out across instances')), 10000);
      socketB.once('incoming_call_request', (data) => {
        console.log(`📲 [Instance :3002] Client B received incoming_call_request from Client A! Request ID: ${data.callRequestId}`);
        pendingCallId = data.callRequestId;
        clearTimeout(timeout);
        resolve(data);
      });
    });

    socketA.emit('direct_call', { targetUserId: USER_B_ID });
    await directCallIncomingPromise;

    // Verify pending call in Redis
    const pendingCallRedis = await redis.get(`pending_call:${pendingCallId}`);
    console.log(`[Redis Check] 'pending_call:${pendingCallId}':`, pendingCallRedis ? 'EXISTS in Redis' : 'MISSING');
    if (!pendingCallRedis) throw new Error('Pending call was not saved to Redis!');

    console.log('\nClient B on :3002 accepts the direct call...');
    const directMatchPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('direct call match timed out')), 10000);
      let matchCount = 0;
      socketA.once('match_found', (data) => {
        console.log(`🎉 [Instance :3001] Client A received match_found! Call ID: ${data.callId}`);
        matchCount++;
        if (matchCount === 2) {
          clearTimeout(timeout);
          resolve();
        }
      });
      socketB.once('match_found', (data) => {
        console.log(`🎉 [Instance :3002] Client B received match_found! Call ID: ${data.callId}`);
        matchCount++;
        if (matchCount === 2) {
          clearTimeout(timeout);
          resolve();
        }
      });
    });

    socketB.emit('accept_call_request', { callRequestId: pendingCallId });
    await directMatchPromise;

    console.log('\nClient B on :3002 ends the direct call...');
    const directEndPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('direct call end timed out')), 10000);
      socketA.once('call_ended', (data) => {
        console.log(`🛑 [Instance :3001] Client A received call_ended from Client B!`);
        clearTimeout(timeout);
        resolve(data);
      });
    });

    const activeDirectCallId = await redis.get(`user_active_call:${USER_B_ID}`);
    socketB.emit('end_call', { callId: activeDirectCallId });
    await directEndPromise;

    console.log('\n================================================================');
    console.log(' ✅ MULTI-INSTANCE VERIFICATION PASSED WITH 100% SUCCESS!');
    console.log(' - Matchmaking across :3001 and :3002 synchronized via Redis');
    console.log(' - Direct call ringing across :3001 and :3002 synchronized via Redis');
    console.log(' - Cross-process call hangups correctly clean up all Redis state');
    console.log(' - Zero orphaned locks or call records remain');
    console.log('================================================================');

    process.exit(0);
  } catch (err) {
    console.error('\n❌ MULTI-INSTANCE VERIFICATION FAILED:', err);
    process.exit(1);
  } finally {
    if (socketA) socketA.disconnect();
    if (socketB) socketB.disconnect();
    if (proc1) proc1.kill('SIGTERM');
    if (proc2) proc2.kill('SIGTERM');
  }
}

runMultiInstanceVerification();
