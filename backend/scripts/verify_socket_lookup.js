require('dotenv').config();
const { getSocketForUser: getMM } = require('../modules/matchmaking/matchmaking.socket');
const { getSocketForUser: getIC } = require('../modules/instant_connect/instant_connect.socket');

async function testGetSocketForUser() {
  console.log('--- 1.7 getSocketForUser O(1) Room Lookup Verification ---');

  // Construct mock IO with rooms and socket map
  const mockSocket = { id: 'sock_123', userId: 'user_456', connected: true };
  const mockSocketsMap = new Map([['sock_123', mockSocket]]);

  const restrictedSockets = {
    get(id) {
      return mockSocketsMap.get(id);
    },
    [Symbol.iterator]() {
      throw new Error('❌ FORBIDDEN O(N) SCAN: io.sockets.sockets iterator was invoked!');
    },
  };

  const mockIo = {
    sockets: {
      sockets: restrictedSockets,
      adapter: {
        rooms: new Map([
          ['user_456', new Set(['sock_123'])],
        ]),
      },
    },
  };

  // Test Matchmaking getSocketForUser
  const s1 = getMM(mockIo, 'user_456');
  console.log('[Matchmaking getSocketForUser] Found socket:', s1?.id);
  if (s1?.id !== 'sock_123') {
    throw new Error('Matchmaking getSocketForUser failed to resolve socket via room');
  }

  // Test Instant Connect getSocketForUser
  const s2 = getIC(mockIo, 'user_456');
  console.log('[Instant Connect getSocketForUser] Found socket:', s2?.id);
  if (s2?.id !== 'sock_123') {
    throw new Error('Instant Connect getSocketForUser failed to resolve socket via room');
  }

  // Test non-existent user - must return null without invoking forbidden iterator
  const s3 = getMM(mockIo, 'user_nonexistent');
  const s4 = getIC(mockIo, 'user_nonexistent');
  console.log('Non-existent lookups:', s3, s4);

  console.log('✅ PASSED: getSocketForUser resolves via O(1) room lookup and never executes O(N) scan!');
  process.exit(0);
}

testGetSocketForUser().catch((err) => {
  console.error('❌ Error:', err.message);
  process.exit(1);
});
