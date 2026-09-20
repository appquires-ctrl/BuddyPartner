const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const fs = require('fs');
const db = require('../db');

async function runSqlFile(filename) {
  const filePath = path.join(__dirname, '..', 'migrations', filename);
  const sql = fs.readFileSync(filePath, 'utf8');
  console.log(`\n🚀 Executing ${filename}...`);

  // Remove comment lines first
  const cleanSql = sql.replace(/--.*$/gm, '');
  const statements = cleanSql
    .split(';')
    .map(s => s.trim())
    .filter(s => s.length > 0);

  for (const stmt of statements) {
    const preview = stmt.replace(/\s+/g, ' ').slice(0, 80);
    process.stdout.write(`  ⏳ Running: ${preview}... `);
    try {
      await db.query(stmt);
      console.log('✅');
    } catch (err) {
      console.log(`⚠️ ${err.message}`);
    }
  }
}

async function main() {
  try {
    await runSqlFile('025_add_users_login_indexes.sql');
    await runSqlFile('026_core_tables_and_buddy_feed_indexes.sql');

    // Verify index existence
    const res = await db.query(`
      SELECT tablename, indexname 
      FROM pg_indexes 
      WHERE tablename IN ('users', 'buddy_requests', 'google_play_purchases')
        AND indexname IN (
          'idx_users_mobile',
          'idx_users_phone_number',
          'idx_users_lower_username_btree',
          'idx_buddy_requests_open_feed',
          'idx_gp_purchases_token'
        )
      ORDER BY tablename, indexname;
    `);

    console.log('\n🔍 Verification of Newly Created Indexes:');
    res.rows.forEach(r => console.log(`✅ [${r.tablename}] ${r.indexname}`));
  } catch (err) {
    console.error('Fatal error:', err.message);
  } finally {
    await db.pool.end();
  }
}

main();
