const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const db = require('../db');

/**
 * Migration 019 Standalone Concurrent Runner:
 * Executes CREATE INDEX CONCURRENTLY outside of any transaction block.
 * Verifies validity via pg_index.indisvalid and reports status.
 */
async function runConcurrentIndex019() {
  console.log('🚀 [Migration 019] Starting non-blocking index creation...');
  console.log('   Statement: CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_city_lower_trim ON public.users (LOWER(TRIM(city)));\n');

  const startTime = Date.now();

  try {
    // 1. Run raw CREATE INDEX CONCURRENTLY outside any transaction
    await db.pool.query(`
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_city_lower_trim 
      ON public.users (LOWER(TRIM(city)));
    `);

    const duration = Date.now() - startTime;
    console.log(`⏱️ Index creation completed in ${duration}ms. Verifying index validity...`);

    // 2. Query pg_index joined with pg_class to check 'indisvalid'
    const checkRes = await db.pool.query(`
      SELECT 
        c.relname AS indexname,
        pg_get_indexdef(c.oid) AS indexdef,
        i.indisvalid
      FROM pg_class c
      JOIN pg_index i ON i.indexrelid = c.oid
      WHERE c.relname = 'idx_users_city_lower_trim';
    `);

    if (checkRes.rows.length === 0) {
      console.error('❌ Error: Index idx_users_city_lower_trim was not found in PostgreSQL catalog.');
      process.exit(1);
    }

    const { indexname, indexdef, indisvalid } = checkRes.rows[0];

    if (indisvalid === true) {
      console.log('✅ SUCCESS: Index is VALID and active for production queries!');
      console.log(`   Name:       ${indexname}`);
      console.log(`   Definition: ${indexdef}`);
      console.log(`   Valid:      ${indisvalid}`);
      process.exit(0);
    } else {
      console.error('⚠️ WARNING: Index creation finished but the index is marked INVALID (indisvalid = false)!');
      console.error('   This occurs if a concurrent lock or timeout interrupted the build.');
      console.error('   To clean up the invalid index before retrying, execute:');
      console.error('     DROP INDEX CONCURRENTLY IF EXISTS idx_users_city_lower_trim;');
      console.error('   Then re-run this script.');
      process.exit(1);
    }
  } catch (err) {
    console.error('❌ Migration execution failed:', err.message);
    console.error('\nIf the index was partially created and failed, clean up using:');
    console.error('  DROP INDEX CONCURRENTLY IF EXISTS idx_users_city_lower_trim;');
    process.exit(1);
  } finally {
    await db.pool.end();
  }
}

runConcurrentIndex019();
