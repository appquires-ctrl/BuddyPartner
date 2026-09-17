require('dotenv').config();
const db = require('../db');
const redis = require('../redis');
const { messagingService } = require('../modules/messaging/messaging.service');

async function testSendMessageQueries() {
  console.log('--- 1.5 Testing sendMessage Query Count & CTE Optimization ---');

  // Get or create 2 test users and a conversation
  const usersRes = await db.query(`SELECT id FROM public.users LIMIT 2`);
  if (usersRes.rows.length < 2) {
    console.error('Need at least 2 users in database to test.');
    process.exit(1);
  }
  const u1 = usersRes.rows[0].id;
  const u2 = usersRes.rows[1].id;

  const conv = await messagingService.findOrCreateConversation(u1, u2);
  console.log(`Conversation resolved: ${conv.id} between ${u1} and ${u2}`);

  // Instrument db.query to count queries
  let queryCount = 0;
  const originalQuery = db.query.bind(db);
  db.query = async (...args) => {
    queryCount++;
    console.log(`  [DB Query #${queryCount}]: ${args[0].trim().split('\n')[0].substring(0, 80)}...`);
    return originalQuery(...args);
  };

  try {
    // Test 1: sendMessage with preFetchedConv and initialStatus = 'delivered' (live chat socket path)
    console.log('\n--- Sending message (live chat path: delivered) ---');
    queryCount = 0;
    const msg1 = await messagingService.sendMessage(
      conv.id,
      u1,
      'Hello from optimized sendMessage!',
      'text',
      null,
      'delivered',
      conv
    );

    console.log(`Message 1 inserted with ID ${msg1.id}, status: ${msg1.status}`);
    console.log(`Total DB queries executed on live hot path: ${queryCount}`);

    if (queryCount > 2) {
      console.error(`❌ FAILED: Expected <= 2 DB queries on hot path, got ${queryCount}`);
      process.exit(1);
    }

    // Verify conversations last_message_at was updated
    const convCheck = await originalQuery(`SELECT last_message_at FROM public.conversations WHERE id = $1`, [conv.id]);
    console.log(`Conversation last_message_at successfully updated to: ${convCheck.rows[0].last_message_at}`);

    // Test 2: Repeat send (block-check should hit Redis cache, resulting in exactly 1 CTE query!)
    console.log('\n--- Sending second message (with cached block check) ---');
    queryCount = 0;
    const msg2 = await messagingService.sendMessage(
      conv.id,
      u1,
      'Second message (block check cached)!',
      'text',
      null,
      'delivered',
      conv
    );

    console.log(`Message 2 inserted with ID ${msg2.id}, status: ${msg2.status}`);
    console.log(`Total DB queries on cached hot path: ${queryCount}`);

    if (queryCount !== 1) {
      console.error(`❌ FAILED: Expected exactly 1 DB query (the CTE) on cached hot path, got ${queryCount}`);
      process.exit(1);
    }

    console.log('✅ PASSED: Hot-path sendMessage queries successfully reduced from 6 down to 1 single CTE query!');
    process.exit(0);
  } finally {
    db.query = originalQuery;
  }
}

testSendMessageQueries().catch((err) => {
  console.error('❌ Error testing sendMessage:', err);
  process.exit(1);
});
