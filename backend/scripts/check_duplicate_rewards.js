require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function main() {
  try {
    const res = await pool.query(`
      SELECT reference_id, user_id, COUNT(*) as count, SUM(earned_delta) as total_reward
      FROM public.wallet_transactions
      WHERE reason = 'buddy_reward'
      GROUP BY reference_id, user_id
      HAVING COUNT(*) > 1;
    `);

    console.log('--- Duplicate buddy_reward rows in wallet_transactions ---');
    console.log('Duplicates count:', res.rows.length);
    if (res.rows.length > 0) {
      console.table(res.rows);
    } else {
      console.log('None found. Exactly 0 duplicate buddy_reward transactions exist.');
    }

    const allRewards = await pool.query(`
      SELECT COUNT(*) as total_buddy_rewards FROM public.wallet_transactions WHERE reason = 'buddy_reward';
    `);
    console.log('Total buddy_reward rows in wallet_transactions:', allRewards.rows[0].total_buddy_rewards);

    // Also check if there are any duplicate completed records across all reference_ids in wallet_transactions
    const allDuplicates = await pool.query(`
      SELECT reference_id, reason, COUNT(*) as count
      FROM public.wallet_transactions
      WHERE reference_id IS NOT NULL AND reason = 'buddy_reward'
      GROUP BY reference_id, reason
      HAVING COUNT(*) > 1;
    `);
    console.log('Cross-check reference_id duplicates:', allDuplicates.rows.length);

  } catch (err) {
    console.error('Error checking duplicates:', err.message);
  } finally {
    await pool.end();
  }
}

main();
