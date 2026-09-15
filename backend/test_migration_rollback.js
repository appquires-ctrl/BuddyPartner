require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function testRollbackAndReapply() {
  const client = await db.pool.connect();
  try {
    const downPath = path.join(__dirname, 'migrations', '016_dual_balance_and_corrected_buddy_down.sql');
    const downSql = fs.readFileSync(downPath, 'utf8');
    console.log('🔄 Testing rollback 016_dual_balance_and_corrected_buddy_down.sql...');
    await client.query('BEGIN');
    await client.query(downSql);
    await client.query('COMMIT');
    console.log('✅ Rollback executed successfully!');

    const upPath = path.join(__dirname, 'migrations', '016_dual_balance_and_corrected_buddy.sql');
    const upSql = fs.readFileSync(upPath, 'utf8');
    console.log('🚀 Re-applying 016_dual_balance_and_corrected_buddy.sql...');
    await client.query('BEGIN');
    await client.query(upSql);
    await client.query('COMMIT');
    console.log('✅ Re-application of Migration 016 executed successfully!');

    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Rollback / Reapply test failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

testRollbackAndReapply();
