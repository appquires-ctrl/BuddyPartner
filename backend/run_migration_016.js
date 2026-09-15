require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  const client = await db.pool.connect();
  try {
    const sqlPath = path.join(__dirname, 'migrations', '016_dual_balance_and_corrected_buddy.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('🚀 Executing migration 016_dual_balance_and_corrected_buddy.sql...');
    
    await client.query('BEGIN');
    await client.query(sql);
    await client.query('COMMIT');
    
    console.log('✅ Migration 016 executed successfully!');
    
    // Verify tables
    const checkRes = await client.query(`
      SELECT table_name, column_name, data_type 
      FROM information_schema.columns 
      WHERE table_schema = 'public' 
        AND table_name IN ('wallets', 'wallet_transactions', 'buddy_requests', 'withdrawals')
      ORDER BY table_name, ordinal_position;
    `);
    
    console.log('📊 Schema verification summary:');
    const tables = {};
    for (const r of checkRes.rows) {
      if (!tables[r.table_name]) tables[r.table_name] = [];
      tables[r.table_name].push(`${r.column_name} (${r.data_type})`);
    }
    for (const [t, cols] of Object.entries(tables)) {
      console.log(`  Table [${t}]: ${cols.join(', ')}`);
    }
    
    process.exit(0);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('❌ Migration 016 failed:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

runMigration();
