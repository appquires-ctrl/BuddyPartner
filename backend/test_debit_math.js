require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const db = require('./db');

async function testCteDebit() {
  const client = await db.pool.connect();
  try {
    const userRes = await client.query('SELECT id FROM public.users LIMIT 1');
    const testUserId = userRes.rows[0].id;
    
    // Set 40 spendable, 200 earned
    await client.query(`
      UPDATE public.wallets 
      SET spendable_balance = 40, earned_balance = 200 
      WHERE user_id = $1
    `, [testUserId]);

    const amount = 100;

    const res = await client.query(`
      WITH prev AS (
        SELECT user_id, spendable_balance, earned_balance
        FROM public.wallets
        WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
      )
      UPDATE public.wallets w
      SET 
        spendable_balance = w.spendable_balance - LEAST(prev.spendable_balance, $1::bigint),
        earned_balance = w.earned_balance - ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)),
        updated_at = NOW()
      FROM prev
      WHERE w.user_id = prev.user_id
      RETURNING 
        w.spendable_balance, 
        w.earned_balance,
        LEAST(prev.spendable_balance, $1::bigint) AS spendable_deducted,
        ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)) AS earned_deducted;
    `, [amount, testUserId]);

    console.log('CTE Update result:', res.rows);

    // Test case 2: user has 150 spendable, 50 earned, spend 100
    await client.query(`
      UPDATE public.wallets 
      SET spendable_balance = 150, earned_balance = 50 
      WHERE user_id = $1
    `, [testUserId]);

    const res2 = await client.query(`
      WITH prev AS (
        SELECT user_id, spendable_balance, earned_balance
        FROM public.wallets
        WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
      )
      UPDATE public.wallets w
      SET 
        spendable_balance = w.spendable_balance - LEAST(prev.spendable_balance, $1::bigint),
        earned_balance = w.earned_balance - ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)),
        updated_at = NOW()
      FROM prev
      WHERE w.user_id = prev.user_id
      RETURNING 
        w.spendable_balance, 
        w.earned_balance,
        LEAST(prev.spendable_balance, $1::bigint) AS spendable_deducted,
        ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)) AS earned_deducted;
    `, [amount, testUserId]);

    console.log('CTE Update result 2:', res2.rows);

    // Test case 3: insufficient balance (total 50 < 100)
    await client.query(`
      UPDATE public.wallets 
      SET spendable_balance = 30, earned_balance = 20 
      WHERE user_id = $1
    `, [testUserId]);

    const res3 = await client.query(`
      WITH prev AS (
        SELECT user_id, spendable_balance, earned_balance
        FROM public.wallets
        WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
      )
      UPDATE public.wallets w
      SET 
        spendable_balance = w.spendable_balance - LEAST(prev.spendable_balance, $1::bigint),
        earned_balance = w.earned_balance - ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)),
        updated_at = NOW()
      FROM prev
      WHERE w.user_id = prev.user_id
      RETURNING 
        w.spendable_balance, 
        w.earned_balance,
        LEAST(prev.spendable_balance, $1::bigint) AS spendable_deducted,
        ($1::bigint - LEAST(prev.spendable_balance, $1::bigint)) AS earned_deducted;
    `, [amount, testUserId]);

    console.log('CTE Update result 3 (insufficient):', res3.rows);

    // Reset
    await client.query(`
      UPDATE public.wallets 
      SET spendable_balance = 0, earned_balance = 0 
      WHERE user_id = $1
    `, [testUserId]);

    process.exit(0);
  } catch (err) {
    console.error('Error:', err);
    process.exit(1);
  } finally {
    client.release();
  }
}

testCteDebit();
