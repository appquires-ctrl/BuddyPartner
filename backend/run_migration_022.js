require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  const client = await db.pool.connect();
  try {
    const sqlPath = path.join(__dirname, 'migrations', '022_add_garba_buddy_type.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('🚀 Executing migration 022_add_garba_buddy_type.sql...');

    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');

    console.log('✅ Migration 022 executed successfully!');

    const checkRes = await client.query(`
      SELECT conname, pg_get_constraintdef(oid) as def
      FROM pg_constraint
      WHERE conrelid = 'public.buddy_requests'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%buddy_type%';
    `);

    console.log('📊 Verified constraint in public.buddy_requests:');
    for (const r of checkRes.rows) {
      console.log(`  ${r.conname}: ${r.def}`);
    }

    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration 022 failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runMigration();
