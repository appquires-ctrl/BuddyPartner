require('dotenv').config();
const fs = require('fs');
const path = require('path');
const db = require('./db');

async function runMigration() {
  try {
    const sqlPath = path.join(__dirname, 'migrations', '004_create_rose_tables.sql');
    const sql = fs.readFileSync(sqlPath, 'utf8');
    console.log('Executing migration 004_create_rose_tables.sql...');
    await db.query(sql);
    console.log('✅ Migration 004_create_rose_tables.sql completed successfully.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Migration failed:', err.message);
    process.exit(1);
  }
}

runMigration();
