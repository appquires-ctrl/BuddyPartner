require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function run() {
  console.log('🚀 Running migration 033_add_state_to_buddy_tables.sql...');
  const sql = fs.readFileSync(
    path.join(__dirname, 'migrations', '033_add_state_to_buddy_tables.sql'),
    'utf-8'
  );

  const client = await db.pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
    console.log('✅ Migration 033 executed successfully!');

    const colsRes = await client.query(`
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_name IN ('buddy_requests', 'buddy_groups') 
        AND column_name = 'state';
    `);
    console.log('🔍 Verified state columns in database:');
    console.log(colsRes.rows);

    const indexRes = await client.query(`
      SELECT indexname, indexdef 
      FROM pg_indexes 
      WHERE tablename = 'buddy_requests' 
        AND indexname = 'idx_buddy_requests_state';
    `);
    console.log('🔍 Verified partial index:');
    console.log(indexRes.rows);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration 033 failed:', err);
    process.exit(1);
  } finally {
    client.release();
    await db.pool.end();
  }
}

run();
