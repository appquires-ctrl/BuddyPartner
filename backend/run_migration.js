require('dotenv').config();
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  try {
    const sqlPath = path.join(__dirname, 'migrations', '006_add_telecaller_column.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('Executing migration 006_add_telecaller_column.sql...');
    await db.query(sql);
    console.log('✅ Migration 006_add_telecaller_column.sql completed successfully.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

runMigration();
