require('dotenv').config();
const db = require('../db');

async function applyMigration021() {
  console.log('--- 1.9 Applying Migration 021 (Username varchar_pattern_ops Index) ---');
  const client = await db.pool.connect();
  try {
    console.log('Executing: CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_lower_pattern ON public.users (LOWER(user_name) varchar_pattern_ops);');
    await client.query('CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_lower_pattern ON public.users (LOWER(user_name) varchar_pattern_ops);');
    console.log('✅ Index created successfully.');

    // Now re-run EXPLAIN ANALYZE
    console.log('\n--- Re-running EXPLAIN ANALYZE ---');
    const q = `
      EXPLAIN ANALYZE 
      SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller 
      FROM public.users 
      WHERE LOWER(user_name) LIKE 'tes%' 
        AND (is_banned IS NOT TRUE) 
      ORDER BY LOWER(user_name) ASC 
      LIMIT 20;
    `;
    const res = await client.query(q);
    console.log(res.rows.map(r => r['QUERY PLAN']).join('\n'));
    console.log('---------------------------------');
  } catch (err) {
    console.error('Error applying migration 021:', err);
    process.exit(1);
  } finally {
    client.release();
    process.exit(0);
  }
}

applyMigration021();
