require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  const client = await db.pool.connect();
  try {
    const sqlPath = path.join(__dirname, 'migrations', '018_add_password_hash_to_users.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('🚀 Executing migration 018_add_password_hash_to_users.sql...');
    
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
    
    console.log('✅ Migration 018 executed successfully!');
    
    const checkRes = await client.query(`
      SELECT column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name = 'users'
        AND column_name IN ('user_name', 'password_hash')
      ORDER BY ordinal_position;
    `);
    
    console.log('📊 Verified columns in public.users:');
    for (const r of checkRes.rows) {
      console.log(`  ${r.column_name} (${r.data_type})`);
    }
    
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration 018 failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runMigration();
