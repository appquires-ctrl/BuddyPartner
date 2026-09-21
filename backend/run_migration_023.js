require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function run() {
  console.log('🚀 Running migration 023_add_festival_buddy_and_custom_title.sql...');
  const sql = fs.readFileSync(
    path.join(__dirname, 'migrations', '023_add_festival_buddy_and_custom_title.sql'),
    'utf-8'
  );

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
    console.log('✅ Migration 023 executed successfully!');

    const checkRes = await client.query(`
      SELECT conname, pg_get_constraintdef(oid) as def
      FROM pg_constraint
      WHERE conrelid = 'public.buddy_requests'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%buddy_type%';
    `);
    console.log('🔍 Active constraint definition:');
    console.log(checkRes.rows);

    const colsRes = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name = 'buddy_requests' 
        AND column_name IN ('custom_title', 'campaign_id');
    `);
    console.log('🔍 Added columns:');
    console.log(colsRes.rows);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Migration 023 failed:', err);
    process.exit(1);
  } finally {
    client.release();
    await db.pool.end();
  }
}

run();
