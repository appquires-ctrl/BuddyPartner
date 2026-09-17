require('dotenv').config();
const db = require('../db');

async function compareSurgeSampling() {
  console.log('--- 1.6 Surge Sampling EXPLAIN ANALYZE Comparison ---');

  const beforeQuery = `
    EXPLAIN ANALYZE
    SELECT u.id, u.fcm_token, u.full_name
    FROM public.users u
    WHERE (LOWER(u.gender) IN ('female', 'girl', 'woman', 'f'))
      AND u.incoming_paid_calls_enabled = true
      AND u.fcm_token IS NOT NULL
    ORDER BY RANDOM()
    LIMIT 10
  `;

  console.log('--- BEFORE: ORDER BY RANDOM() ---');
  const resBefore = await db.query(beforeQuery);
  console.log(resBefore.rows.map(r => r['QUERY PLAN']).join('\n'));

  const afterQuery = `
    EXPLAIN ANALYZE
    SELECT u.id, u.fcm_token, u.full_name
    FROM public.users u
    WHERE (LOWER(u.gender) IN ('female', 'girl', 'woman', 'f'))
      AND u.incoming_paid_calls_enabled = true
      AND u.fcm_token IS NOT NULL
    OFFSET 0
    LIMIT 10
  `;

  console.log('\n--- AFTER: OFFSET / LIMIT (Random Offset) ---');
  const resAfter = await db.query(afterQuery);
  console.log(resAfter.rows.map(r => r['QUERY PLAN']).join('\n'));

  process.exit(0);
}

compareSurgeSampling().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
