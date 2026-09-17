require('dotenv').config();
const ioClient = require('socket.io-client');
const jwt = require('jsonwebtoken');
const { spawn } = require('child_process');
const path = require('path');
const db = require('../db');
const redis = require('../redis');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const USER_A_ID = 'fa4c162e-877d-4d08-9eac-4f80f02123e7'; // Male
const USER_B_ID = 'b2222222-2222-2222-2222-222222222222'; // Female

function startServerInstance(port) {
  return new Promise((resolve, reject) => {
    const env = { ...process.env, PORT: String(port), INSTANCE_COUNT: '2' };
    const proc = spawn('node', ['server.js'], {
      cwd: path.resolve(__dirname, '..'),
      env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });

    let ready = false;
    proc.stdout.on('data', (data) => {
      const msg = data.toString();
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
        // console.error(`[Process :${port} ERR]:`, errStr);
      }
    });

    proc.on('exit', (code) => {
      if (!ready) reject(new Error(`Process on port ${port} exited prematurely with code ${code}`));
    });
  });
}

function connectSocket(port, userId, phone) {
  const sessionId = `sess_${userId}_${Date.now()}`;
  const token = jwt.sign({ id: userId, phone, sessionId }, JWT_SECRET, { expiresIn: '1h' });

  return new Promise((resolve, reject) => {
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

async function runKillMidCallVerification() {
  console.log('================================================================');
  console.log(' BUDDYPARTNER 1.4: PROCESS KILL MID-CALL RESILIENCE TEST');
  console.log('================================================================\n');

  let proc1 = null;
  let proc2 = null;
  let socketA = null;
  let socketB = null;

  try {
    console.log('--- Step 1: Starting Instances :3001 & :3002 ---');
    [proc1, proc2] = await Promise.all([
      startServerInstance(3001),
      startServerInstance(3002),
    ]);
    await new Promise((r) => setTimeout(r, 1500));

    console.log('\n--- Step 2: Connecting Client A (:3001) & Client B (:3002) ---');
    socketA = await connectSocket(3001, USER_A_ID, '+919999999999');
    socketB = await connectSocket(3002, USER_B_ID, '+918888888888');

    console.log('\n--- Step 3: Establishing Call Between Instances ---');
    let callId = null;
    const matchPromise = new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Matchmaking timed out')), 10000);
      let matches = 0;
      const handler = (data) => {
        callId = data.callId;
        matches++;
        if (matches === 2) {
          clearTimeout(timeout);
          resolve();
        }
      };
      socketA.once('match_found', handler);
      socketB.once('match_found', handler);
    });

    socketA.emit('join_queue', () => {});
    socketB.emit('join_queue', () => {});
    await matchPromise;

    console.log(`🎉 Call established! Call ID: ${callId}`);
    const redisCallRaw = await redis.get(`active_call:${callId}`);
    console.log(`[Redis Check] 'active_call:${callId}' verified in Redis:`, !!redisCallRaw);

    console.log('\n--- Step 4: KILLING Instance 1 (:3001) MID-CALL (SIGKILL / Force Kill) ---');
    proc1.kill('SIGKILL');
    console.log('💥 Process :3001 forcefully terminated mid-call!');

    // Wait 1 second to ensure process 1 is fully gone
    await new Promise((r) => setTimeout(r, 1000));

    console.log('\n--- Step 5: Surviving Instance 2 (:3002) Processes Call End ---');
    console.log(`Client B on surviving Instance :3002 calls end_call on callId ${callId}...`);

    socketB.emit('end_call', { callId });

    // Wait 2 seconds for asynchronous DB & Redis cleanup on surviving instance
    await new Promise((r) => setTimeout(r, 2000));

    console.log('\n--- Step 6: Verifying Redis Cleanup on Surviving Instance ---');
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

    if (redisCallAfter === null && lockAAfter === null && lockBAfter === null) {
      console.log('\n================================================================');
      console.log(' ✅ PROCESS KILL MID-CALL RESILIENCE TEST PASSED 100%!');
      console.log(' Surviving instance cleanly recovered call state from Redis');
      console.log(' and purged all distributed locks without throwing!');
      console.log('================================================================');
      process.exit(0);
    } else {
      throw new Error('Redis state was not cleanly purged by surviving instance!');
    }
  } catch (err) {
    console.error('\n❌ KILL MID-CALL TEST FAILED:', err);
    process.exit(1);
  } finally {
    if (socketA) socketA.disconnect();
    if (socketB) socketB.disconnect();
    if (proc1) proc1.kill('SIGKILL');
    if (proc2) proc2.kill('SIGKILL');
  }
}

runKillMidCallVerification();
