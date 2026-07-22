require('dotenv').config();
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  try {
    const sqlPath = path.join(__dirname, 'migrations', '003_create_wallet_transactions_table.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('Executing migration 003_create_wallet_transactions_table.sql...');
    await db.query(sql);
    console.log('✅ Migration 003_create_wallet_transactions_table.sql completed successfully.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

runMigration();
