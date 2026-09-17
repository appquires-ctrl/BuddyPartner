const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const db = require('../db');

/**
 * Migration 020 Standalone Concurrent Runner:
 * Executes CREATE INDEX CONCURRENTLY statements outside of transactions.
 * Verifies validity via pg_index.indisvalid for each index.
 */
async function runConcurrentIndexes020() {
  console.log('🚀 [Migration 020] Starting non-blocking indexes creation for messaging delivery...\n');

  const statements = [
    {
      name: 'idx_messages_unread_status',
      sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_unread_status 
            ON public.messages (conversation_id, status) 
            WHERE status = 'sent'`,
    },
    {
      name: 'idx_conversations_user_a',
      sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a 
            ON public.conversations (user_a_id)`,
    },
    {
      name: 'idx_conversations_user_b',
      sql: `CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b 
            ON public.conversations (user_b_id)`,
    },
  ];

  try {
    for (const { name, sql } of statements) {
      console.log(`⏳ Creating ${name}...`);
      const startTime = Date.now();
      await db.pool.query(sql);
      const duration = Date.now() - startTime;
      console.log(`   Finished statement in ${duration}ms. Verifying index validity...`);

      const checkRes = await db.pool.query(`
        SELECT 
          c.relname AS indexname,
          pg_get_indexdef(c.oid) AS indexdef,
          i.indisvalid
        FROM pg_class c
        JOIN pg_index i ON i.indexrelid = c.oid
        WHERE c.relname = $1;
      `, [name]);

      if (checkRes.rows.length === 0) {
        console.error(`❌ Error: Index ${name} was not found in catalog.`);
        process.exit(1);
      }

      const { indexname, indisvalid } = checkRes.rows[0];
      if (indisvalid === true) {
        console.log(`   ✅ ${indexname} is VALID and active.\n`);
      } else {
        console.error(`   ⚠️ WARNING: ${indexname} is INVALID!`);
        console.error(`   Clean up using: DROP INDEX CONCURRENTLY IF EXISTS ${indexname};`);
        process.exit(1);
      }
    }

    console.log('🎉 Migration 020 completed successfully! All 3 indexes are active.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration 020 failed:', err.message);
    process.exit(1);
  } finally {
    await db.pool.end();
  }
}

runConcurrentIndexes020();
