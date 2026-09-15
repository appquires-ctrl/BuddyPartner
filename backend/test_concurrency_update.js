require('dotenv').config({ path: require('path').join(__dirname, '.env') });
const db = require('./db');

async function test() {
  const client1 = await db.pool.connect();
  const client2 = await db.pool.connect();
  
  const phone = `+9199999${Math.floor(10000 + Math.random() * 90000)}`;
  const uRes = await db.query(
    "INSERT INTO public.users (phone_number, full_name, gender, city) VALUES ($1, 'Test', 'female', 'Mumbai') RETURNING id",
    [phone]
  );
  const u = uRes.rows[0].id;
  await db.query('UPDATE public.wallets SET spendable_balance = 20, earned_balance = 30 WHERE user_id = $1', [u]);

  const q = `
    WITH prev AS (
      SELECT user_id, spendable_balance, earned_balance
      FROM public.wallets
      WHERE user_id = $2 AND (spendable_balance + earned_balance) >= $1::bigint
      FOR UPDATE
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
  `;

  try {
    const p1 = client1.query('BEGIN')
      .then(() => client1.query(q, [20, u]))
      .then(async (r) => { await client1.query('COMMIT'); return r; });

    const p2 = client2.query('BEGIN')
      .then(() => client2.query(q, [20, u]))
      .then(async (r) => { await client2.query('COMMIT'); return r; });

    const [r1, r2] = await Promise.all([p1, p2]);
    console.log('R1 rows:', r1.rows);
    console.log('R2 rows:', r2.rows);

    const finalRow = (await db.query('SELECT * FROM public.wallets WHERE user_id = $1', [u])).rows[0];
    console.log('Final row:', finalRow);
  } catch (err) {
    console.error('Error during concurrent test:', err);
  } finally {
    await db.query('DELETE FROM public.users WHERE id = $1', [u]);
    client1.release();
    client2.release();
    process.exit(0);
  }
}

test();
