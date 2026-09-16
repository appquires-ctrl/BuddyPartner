require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  const client = await db.pool.connect();
  try {
    const sqlPath = path.join(__dirname, 'migrations', '017_create_user_monthly_call_usage.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('🚀 Executing migration 017_create_user_monthly_call_usage.sql...');
    
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
    
    console.log('✅ Migration 017 executed successfully!');
    
    const checkRes = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = 'user_monthly_call_usage'
      ORDER BY ordinal_position;
    `);
    
    console.log('📊 Table user_monthly_call_usage columns:');
    for (const r of checkRes.rows) {
      console.log(`  ${r.column_name} (${r.data_type})`);
    }
    
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration 017 failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runMigration();
