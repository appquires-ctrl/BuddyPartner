require('dotenv').config();
const db = require('../db');

async function runExplain() {
  const client = await db.pool.connect();
  try {
    await client.query('SET enable_seqscan = OFF;');
    const q = `
      EXPLAIN ANALYZE 
      SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller 
      FROM public.users 
      WHERE LOWER(user_name) LIKE 'tes%' 
        AND (is_banned IS NOT TRUE) 
      ORDER BY LOWER(user_name) ASC 
      LIMIT 20;
    `;
    const res = await client.query(q);
    console.log('--- EXPLAIN ANALYZE (with index forced) ---');
    console.log(res.rows.map(r => r['QUERY PLAN']).join('\n'));
    console.log('-------------------------------------------');
  } catch (err) {
    console.error('Error running explain:', err);
  } finally {
    process.exit(0);
  }
}

runExplain();
