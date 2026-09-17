require('dotenv').config();
const db = require('../db');

async function runExplainSendMessage() {
  console.log('================================================================');
  console.log(' 1.5 DEEP DIVE: SENDMESSAGE REAL SCHEMA & CTE EXPLAIN ANALYZE');
  console.log('================================================================\n');

  // 1. Inspect real messages columns from information_schema
  console.log('--- 1. INFORMATION_SCHEMA COLUMNS FOR public.messages ---');
  const colsRes = await db.query(`
    SELECT column_name, data_type, is_nullable, column_default
    FROM information_schema.columns
    WHERE table_name = 'messages' AND table_schema = 'public'
    ORDER BY ordinal_position;
  `);
  console.table(colsRes.rows);

  // 2. Proof of what happens if someone tries the fake columns (recipient_id, is_read)
  console.log('\n--- 2. PROVING THAT FAKE COLUMNS FAIL AS REPORTED ---');
  try {
    await db.query(`
      INSERT INTO public.messages (conversation_id, sender_id, recipient_id, content, type, status, media_url, is_read)
      VALUES ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-000000000000', 'test', 'text', 'sent', null, false)
    `);
    console.log('UNEXPECTED: query succeeded?');
  } catch (err) {
    console.log('EXPECTED ERROR DEMONSTRATED:');
    console.log(`❌ ${err.message}`);
  }

  // 3. Get real conversation and sender to run EXPLAIN ANALYZE on the ACTUAL working CTE
  const convRes = await db.query(`SELECT id, user_a_id, user_b_id FROM public.conversations LIMIT 1`);
  if (convRes.rows.length === 0) {
    console.log('No conversation found in DB to test.');
    process.exit(1);
  }
  const conv = convRes.rows[0];
  const conversationId = conv.id;
  const senderId = conv.user_a_id;
  const content = 'Audit verification test message';
  const type = 'text';
  const mediaUrl = null;
  const initialStatus = 'delivered'; // Preserves presence-aware status!

  console.log(`\n--- 3. EXPLAIN ANALYZE ON THE REAL CTE IN messaging.service.js ---`);
  console.log(`Parameters: conversationId=${conversationId}, senderId=${senderId}, initialStatus=${initialStatus}`);

  const explainRes = await db.query(`
    EXPLAIN ANALYZE
    WITH inserted_msg AS (
      INSERT INTO public.messages (conversation_id, sender_id, content, type, media_url, status)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    ),
    updated_conv AS (
      UPDATE public.conversations
      SET last_message_at = NOW()
      WHERE id = $1
    )
    SELECT * FROM inserted_msg;
  `, [conversationId, senderId, content, type, mediaUrl, initialStatus]);

  console.log('\nActual PostgreSQL Execution Plan:');
  explainRes.rows.forEach(r => console.log('  ' + r['QUERY PLAN']));

  console.log('\n================================================================');
  console.log(' REAL SENDMESSAGE CTE VERIFIED ON ACTUAL NEON DATABASE');
  console.log('================================================================');
  process.exit(0);
}

runExplainSendMessage().catch((err) => {
  console.error('Fatal error:', err);
  process.exit(1);
});
