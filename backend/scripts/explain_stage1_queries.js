require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function run() {
  const client = await pool.connect();
  try {
    const testUserId = '00000000-0000-0000-0000-000000000001';

    console.log('--- EXPLAIN ANALYZE: markDeliveredForRecipient with idx_messages_sent_status_partial ---');
    const res = await client.query(`
      EXPLAIN ANALYZE
      WITH user_convs AS (
        SELECT id FROM public.conversations WHERE user_a_id = $1
        UNION
        SELECT id FROM public.conversations WHERE user_b_id = $1
      )
      UPDATE public.messages m
      SET status = 'delivered'
      FROM user_convs uc
      WHERE m.conversation_id = uc.id
        AND m.status = 'sent'
        AND m.sender_id != $1
      RETURNING m.id, m.conversation_id, m.sender_id
    `, [testUserId]);

    res.rows.forEach(r => console.log(r['QUERY PLAN']));

  } catch (err) {
    console.error('Error running EXPLAIN:', err);
  } finally {
    client.release();
    await pool.end();
  }
}

run();
