require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
  connectionTimeoutMillis: 15000,
});

async function runMigration() {
  const migrationPath = path.join(__dirname, 'migrations', '011_production_scalability_indexes.sql');
  const sql = fs.readFileSync(migrationPath, 'utf8');

  console.log('🚀 Executing Migration 011: Production Scalability Indexes on Neon PostgreSQL...');
  const startTime = Date.now();

  try {
    // Split on statements so individual CREATE INDEX commands run with clear feedback
    const statements = sql
      .split(';')
      .map(s => s.trim())
      .filter(s => s.length > 0 && !s.startsWith('--'));

    for (const stmt of statements) {
      const match = stmt.match(/CREATE INDEX (?:CONCURRENTLY )?IF NOT EXISTS (\w+)/i);
      const indexName = match ? match[1] : 'index';
      process.stdout.write(`  ⏳ Creating ${indexName}... `);
      await pool.query(stmt);
      console.log('✅');
    }

    const duration = Date.now() - startTime;
    console.log(`\n Migration 011 completed successfully in ${duration}ms!`);
  } catch (err) {
    console.error('\n❌ Migration 011 failed:', err.message);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

runMigration();
