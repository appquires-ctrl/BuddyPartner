const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');

async function testIndexExplain() {
  console.log('🔬 Testing EXPLAIN ANALYZE against realistic data volume (5,000+ users)...\n');

  try {
    // 1. Check initial row count
    const initialCountRes = await db.query('SELECT count(*) FROM public.users');
    console.log(`Initial user count in DB: ${initialCountRes.rows[0].count}`);

    // 2. Insert 5,000 dummy users in a single statement
    console.log('▶ Inserting 5,000 dummy users...');
    const startTime = Date.now();
    await db.query(`
      INSERT INTO public.users (country_code, mobile, phone_number, full_name, user_name)
      SELECT 
        '91',
        '99988' || LPAD(i::text, 5, '0'),
        '+9199988' || LPAD(i::text, 5, '0'),
        'Perf Test User ' || i,
        'perfuser_' || LPAD(i::text, 5, '0')
      FROM generate_series(1, 5000) AS i
    `);
    console.log(`  ✅ 5,000 dummy users inserted in ${Date.now() - startTime}ms.`);

    // 3. Run ANALYZE to update PostgreSQL optimizer statistics
    console.log('▶ Running ANALYZE public.users...');
    await db.query('ANALYZE public.users');
    console.log('  ✅ PostgreSQL statistics analyzed and refreshed.');

    const newCountRes = await db.query('SELECT count(*) FROM public.users');
    console.log(`Total users in table during test: ${newCountRes.rows[0].count}`);

    // 4. Run EXPLAIN (ANALYZE, BUFFERS)
    console.log('\n▶ Running EXPLAIN (ANALYZE, BUFFERS) query for prefix search:');
    const explainQuery = `
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller
      FROM public.users
      WHERE LOWER(user_name) LIKE 'perfuser_001%'
        AND (is_banned IS NOT TRUE)
        AND id != '00000000-0000-0000-0000-000000000000'
      ORDER BY LOWER(user_name) ASC
      LIMIT 20;
    `;
    const explainRes = await db.query(explainQuery);
    const planLines = explainRes.rows.map((r) => r['QUERY PLAN']);
    console.log('\n================ EXPLAIN ANALYZE OUTPUT ================');
    console.log(planLines.join('\n'));
    console.log('========================================================\n');

    const usesIndex = planLines.some((line) => line.includes('idx_users_user_name_lower'));
    if (usesIndex) {
      console.log(' CONFIRMED: Query Planner used Index Scan on idx_users_user_name_lower against 5,000+ rows!');
    } else {
      console.warn('⚠️ Query did not use idx_users_user_name_lower.');
    }

  } catch (err) {
    console.error('❌ Error during EXPLAIN ANALYZE test:', err);
  } finally {
    console.log('\n🧹 Cleaning up 5,000 dummy records...');
    const delRes = await db.query("DELETE FROM public.users WHERE mobile LIKE '99988%'");
    console.log(`  ✅ Deleted ${delRes.rowCount} dummy users.`);
    await db.query('ANALYZE public.users');
    console.log('  ✅ Restored table statistics.');
    process.exit(0);
  }
}

testIndexExplain();
