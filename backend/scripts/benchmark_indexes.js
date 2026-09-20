require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

async function main() {
  const client = await pool.connect();
  try {
    console.log('🚀 Starting Benchmark on Neon PostgreSQL...\n');

    // 1. Ensure idx_buddy_requests_open_city_created exists (from Stage 3f)
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_buddy_requests_open_city_created
        ON public.buddy_requests (city, created_at DESC)
        WHERE status = 'open';
    `);
    console.log('✅ Ensured idx_buddy_requests_open_city_created exists.');

    // 2. Setup benchmark test users
    console.log('🌱 Setting up benchmark test accounts...');
    const userARes = await client.query(`
      INSERT INTO public.users (phone_number, full_name, gender, city)
      VALUES ('+99999000001', 'Benchmark Recipient', 'female', 'delhi')
      ON CONFLICT (phone_number) DO UPDATE SET city = 'delhi'
      RETURNING id;
    `);
    const recipientId = userARes.rows[0].id;

    const userBRes = await client.query(`
      INSERT INTO public.users (phone_number, full_name, gender, city)
      VALUES ('+99999000002', 'Benchmark Sender', 'male', 'delhi')
      ON CONFLICT (phone_number) DO UPDATE SET city = 'delhi'
      RETURNING id;
    `);
    const senderId = userBRes.rows[0].id;

    // 3. Create 500 partner users and 500 distinct conversations
    console.log('🌱 Creating 500 distinct partner users and conversations...');
    await client.query(`
      INSERT INTO public.users (phone_number, full_name, gender, city)
      SELECT 
        '+999' || lpad(i::text, 8, '0'),
        'Benchmark Partner ' || i,
        'male',
        'delhi'
      FROM generate_series(1, 500) AS s(i)
      ON CONFLICT (phone_number) DO NOTHING;
    `);

    // Clean old benchmark messages & conversations for recipient
    await client.query(`
      DELETE FROM public.messages 
      WHERE conversation_id IN (
        SELECT id FROM public.conversations WHERE user_a_id = $1 OR user_b_id = $1
      );
    `, [recipientId]);

    await client.query(`
      DELETE FROM public.conversations 
      WHERE user_a_id = $1 OR user_b_id = $1;
    `, [recipientId]);

    // Insert 500 distinct conversations
    const convsRes = await client.query(`
      INSERT INTO public.conversations (user_a_id, user_b_id, created_at, last_message_at)
      SELECT 
        LEAST($1::uuid, u.id), 
        GREATEST($1::uuid, u.id),
        NOW() - (u.rnum || ' minutes')::interval,
        NOW() - (u.rnum || ' minutes')::interval
      FROM (
        SELECT id, row_number() OVER () AS rnum 
        FROM public.users 
        WHERE phone_number LIKE '+9990%' 
        LIMIT 500
      ) u
      RETURNING id;
    `, [recipientId]);

    console.log(`✅ Created ${convsRes.rows.length} conversations.`);

    // 4. Seed 50,000 messages across these 500 conversations
    // 15% 'sent' status (~7,500 rows), 85% 'delivered' or 'read' (~42,500 rows)
    console.log('🌱 Seeding 50,000 messages across 500 conversations (15% sent, 85% delivered/read)...');
    const seedStart = Date.now();
    await client.query(`
      INSERT INTO public.messages (conversation_id, sender_id, content, type, status, created_at)
      SELECT 
        c.id,
        CASE WHEN c.user_a_id = $1 THEN c.user_b_id ELSE c.user_a_id END,
        'Benchmark message ' || s.i,
        'text',
        CASE 
          WHEN s.i % 7 = 0 THEN 'sent'
          WHEN s.i % 2 = 0 THEN 'delivered'
          ELSE 'read'
        END,
        NOW() - (s.i || ' seconds')::interval
      FROM public.conversations c
      CROSS JOIN generate_series(1, 100) AS s(i)
      WHERE c.user_a_id = $1 OR c.user_b_id = $1;
    `, [recipientId]);
    console.log(`✅ 50,000 messages seeded in ${Date.now() - seedStart}ms.`);

    // Check message counts
    const msgStats = await client.query(`
      SELECT status, COUNT(*) as count 
      FROM public.messages 
      WHERE sender_id = $1 
      GROUP BY status;
    `, [senderId]);
    console.log('📊 Message distribution:', msgStats.rows);

    // Run ANALYZE so query planner statistics are fresh
    await client.query('ANALYZE public.messages;');
    await client.query('ANALYZE public.conversations;');

    // 5. EXPLAIN ANALYZE for markDeliveredForRecipient
    console.log('\n================================================================');
    console.log('TEST 1: markDeliveredForRecipient WITH idx_messages_sent_status_partial (INDEX SCAN)');
    console.log('================================================================');
    await client.query('SET enable_seqscan = on;');
    await client.query('SET enable_indexscan = on;');
    await client.query('SET enable_bitmapscan = on;');

    const testQuery = `
      EXPLAIN (ANALYZE, BUFFERS)
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
      RETURNING m.id, m.conversation_id, m.sender_id;
    `;

    // Run in a transaction and rollback so data isn't consumed
    await client.query('BEGIN');
    const withIndexRes = await client.query(testQuery, [recipientId]);
    await client.query('ROLLBACK');

    console.log(withIndexRes.rows.map(r => r['QUERY PLAN']).join('\n'));

    console.log('\n================================================================');
    console.log('TEST 1 (BEFORE): markDeliveredForRecipient WITHOUT INDEX (FORCE SEQ SCAN)');
    console.log('================================================================');
    await client.query('BEGIN');
    await client.query('SET enable_indexscan = off;');
    await client.query('SET enable_bitmapscan = off;');
    const noIndexRes = await client.query(testQuery, [recipientId]);
    await client.query('ROLLBACK');

    console.log(noIndexRes.rows.map(r => r['QUERY PLAN']).join('\n'));

    // Reset planner settings
    await client.query('SET enable_seqscan = on;');
    await client.query('SET enable_indexscan = on;');
    await client.query('SET enable_bitmapscan = on;');

    // 6. Seed 5,000 buddy_requests across 20 distinct cities
    console.log('\n================================================================');
    console.log('SEEDING 5,000 BUDDY REQUESTS ACROSS 20 CITIES');
    console.log('================================================================');
    // Clean old benchmark requests
    await client.query(`
      DELETE FROM public.buddy_requests WHERE initiator_id = $1;
    `, [senderId]);

    const cities = [
      'delhi', 'mumbai', 'bengaluru', 'pune', 'hyderabad',
      'kolkata', 'chennai', 'ahmedabad', 'jaipur', 'lucknow',
      'surat', 'kanpur', 'nagpur', 'indore', 'bhopal',
      'patna', 'vadodara', 'ghaziabad', 'ludhiana', 'agra'
    ];

    const buddySeedStart = Date.now();
    await client.query(`
      INSERT INTO public.buddy_requests (
        initiator_id, buddy_type, city, target_gender, status, 
        otp_hash, initiator_coin_cost, accepter_coin_reward, created_at
      )
      SELECT 
        $1::uuid,
        'movie',
        ($2::text[])[1 + (s.i % 20)],
        'female',
        CASE WHEN s.i % 3 = 0 THEN 'open' WHEN s.i % 3 = 1 THEN 'completed' ELSE 'accepted' END,
        'benchmark_hash',
        100,
        50,
        NOW() - (s.i || ' minutes')::interval
      FROM generate_series(1, 5000) AS s(i);
    `, [senderId, cities]);

    console.log(`✅ 5,000 buddy requests seeded in ${Date.now() - buddySeedStart}ms.`);
    await client.query('ANALYZE public.buddy_requests;');

    const buddyQuery = `
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT r.id, r.initiator_id, r.buddy_type, r.city, r.status, r.created_at
      FROM public.buddy_requests r
      WHERE r.city = 'delhi' AND r.status = 'open'
      ORDER BY r.created_at DESC
      LIMIT 30 OFFSET 0;
    `;

    console.log('\n================================================================');
    console.log('TEST 2: Buddy Feed WITH idx_buddy_requests_open_city_created (INDEX SCAN)');
    console.log('================================================================');
    await client.query('SET enable_indexscan = on;');
    await client.query('SET enable_bitmapscan = on;');
    const buddyWithIdx = await client.query(buddyQuery);
    console.log(buddyWithIdx.rows.map(r => r['QUERY PLAN']).join('\n'));

    console.log('\n================================================================');
    console.log('TEST 2 (BEFORE): Buddy Feed WITHOUT idx_buddy_requests_open_city_created (HEAPSORT / SEQ SCAN)');
    console.log('================================================================');
    await client.query('SET enable_indexscan = off;');
    await client.query('SET enable_bitmapscan = off;');
    const buddyNoIdx = await client.query(buddyQuery);
    console.log(buddyNoIdx.rows.map(r => r['QUERY PLAN']).join('\n'));

    // Clean up benchmark data
    console.log('\n🧹 Cleaning up benchmark data from Neon DB...');
    await client.query(`DELETE FROM public.messages WHERE sender_id = $1;`, [senderId]);
    await client.query(`DELETE FROM public.conversations WHERE user_a_id = $1 OR user_b_id = $1;`, [senderId]);
    await client.query(`DELETE FROM public.buddy_requests WHERE initiator_id = $1;`, [senderId]);
    await client.query(`DELETE FROM public.users WHERE phone_number LIKE '+999%';`);
    console.log('✅ Benchmark cleanup complete. Database restored to clean state.');

  } catch (err) {
    console.error('Fatal error during benchmark:', err);
  } finally {
    client.release();
    await pool.end();
  }
}

main();
