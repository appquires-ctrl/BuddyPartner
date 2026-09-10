require('dotenv').config();
const { io } = require('socket.io-client');
const jwt = require('jsonwebtoken');

const PORT = process.env.PORT || 3000;
const URL = `http://localhost:${PORT}`;
const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

function createToken(index) {
  return jwt.sign(
    {
      id: `00000000-0000-0000-0000-${String(index).padStart(12, '0')}`,
      phone: `+9190000${String(index).padStart(5, '0')}`,
      sessionId: `sess-${index}`,
    },
    JWT_SECRET,
    { expiresIn: '1h' }
  );
}

async function simulateSocketLoad(targetClients = 500, rampUpMs = 5000) {
  console.log(`\n🔌 Starting Socket.IO Concurrency Test: Target = ${targetClients} concurrent clients...`);

  const sockets = [];
  let connected = 0;
  let errors = 0;
  const connectTimes = [];

  const interval = rampUpMs / targetClients;

  for (let i = 1; i <= targetClients; i++) {
    const startTime = Date.now();
    const token = createToken(i);

    const s = io(URL, {
      transports: ['websocket'],
      auth: { token },
      reconnection: false,
      timeout: 5000,
    });

    s.on('connect', () => {
      connected++;
      connectTimes.push(Date.now() - startTime);

      // Subscribe to presence
      s.emit('presence:subscribe', [
        '00000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000002',
      ]);
    });

    s.on('connect_error', (err) => {
      errors++;
    });

    sockets.push(s);
    if (interval > 0) {
      await new Promise((r) => setTimeout(r, interval));
    }
  }

  // Wait 3 seconds for all connections to settle
  await new Promise((r) => setTimeout(r, 3000));

  // Compute statistics
  connectTimes.sort((a, b) => a - b);
  const p50 = connectTimes[Math.floor(connectTimes.length * 0.50)] || 0;
  const p95 = connectTimes[Math.floor(connectTimes.length * 0.95)] || 0;
  const p99 = connectTimes[Math.floor(connectTimes.length * 0.99)] || 0;

  console.log(`\n  📊 Socket Concurrency Results (${targetClients} Target Sockets):`);
  console.log(`     - Successfully Connected: ${connected} (${((connected / targetClients) * 100).toFixed(1)}%)`);
  console.log(`     - Failed / Errors:        ${errors}`);
  console.log(`     - Connect Latency p50:    ${p50} ms`);
  console.log(`     - Connect Latency p95:    ${p95} ms`);
  console.log(`     - Connect Latency p99:    ${p99} ms`);

  // Disconnect all sockets
  sockets.forEach((s) => s.disconnect());
  console.log(`  🧹 Disconnected all ${sockets.length} test sockets.`);

  return {
    target: targetClients,
    connected,
    errors,
    p50,
    p95,
    p99,
  };
}

async function main() {
  console.log('====================================================');
  console.log('🚀 Starting Real Socket.IO Concurrency Load Tests');
  console.log('====================================================');

  const levels = [100, 500, 1000];
  const summary = [];

  for (const level of levels) {
    const res = await simulateSocketLoad(level, 2000);
    summary.push(res);
    await new Promise((r) => setTimeout(r, 2000)); // Cool down
  }

  console.log('\n====================================================');
  console.log('📋 SUMMARY TABLE OF SOCKET LOAD BENCHMARKS');
  console.log('====================================================');
  console.table(
    summary.map((s) => ({
      'Target Sockets': s.target,
      Connected: s.connected,
      Errors: s.errors,
      'Connect p50 (ms)': s.p50,
      'Connect p95 (ms)': s.p95,
      'Connect p99 (ms)': s.p99,
    }))
  );
}

main();
