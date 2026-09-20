const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const db = require('../db');

async function benchmarkInbox() {
  try {
    console.log('🔍 Benchmarking Chat Inbox Query (Stage 3a)...');

    // Get a test user with conversations
    const userRes = await db.query(`
      SELECT user_a_id AS uid FROM public.conversations LIMIT 1
    `);
    if (userRes.rows.length === 0) {
      console.log('No conversations found, cannot benchmark.');
      process.exit(0);
    }
    const userId = userRes.rows[0].uid;
    console.log(`Using test user: ${userId}`);

    // Populate denormalized columns on existing conversations for fair test
    await db.query(`
      UPDATE public.conversations c
      SET last_message_content = 'Test message',
          last_message_sender_id = c.user_b_id,
          last_message_type = 'text'
      WHERE c.last_message_content IS NULL;
    `);

    // 1. OLD QUERY (with LEFT JOIN LATERAL, correlated subquery for unread, OR condition, no limit)
    console.log('\n--- 1. EXPLAIN ANALYZE: OLD QUERY (Pre-Stage 3a) ---');
    const oldSql = `
      EXPLAIN (ANALYZE, BUFFERS)
      SELECT 
        c.*,
        u.full_name as other_user_name,
        u.avatar_seed as other_user_avatar_seed,
        lm.content as last_message_content,
        lm.created_at as last_message_created_at,
        (
          SELECT COUNT(*)::int 
          FROM public.messages m 
          WHERE m.conversation_id = c.id 
            AND m.sender_id != $1 
            AND m.created_at > COALESCE(
              (SELECT created_at FROM public.messages WHERE id = mr.last_read_message_id),
              '1970-01-01'::timestamptz
            )
        ) as unread_count
      FROM public.conversations c
      JOIN public.users u ON u.id = CASE WHEN c.user_a_id = $1 THEN c.user_b_id ELSE c.user_a_id END
      LEFT JOIN public.message_reads mr ON mr.conversation_id = c.id AND mr.user_id = $1
      LEFT JOIN LATERAL (
        SELECT content, created_at
        FROM public.messages m
        WHERE m.conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) lm ON true
      WHERE c.user_a_id = $1 OR c.user_b_id = $1
      ORDER BY c.last_message_at DESC NULLS LAST;
    `;
    const oldRes = await db.query(oldSql, [userId]);
    oldRes.rows.forEach(r => console.log(r['QUERY PLAN']));

    // 2. NEW QUERY (with UNION ALL, denormalized last_message, O(1) unread_count, LIMIT/OFFSET)
    console.log('\n--- 2. EXPLAIN ANALYZE: NEW QUERY (Post-Stage 3a) ---');
    const newSql = `
      EXPLAIN (ANALYZE, BUFFERS)
      WITH user_convs AS (
        SELECT c.id, c.user_a_id, c.user_b_id, c.created_at, c.last_message_at,
               c.last_message_content, c.last_message_type, c.last_message_sender_id,
               c.user_b_id AS other_user_id
        FROM public.conversations c
        WHERE c.user_a_id = $1
        UNION ALL
        SELECT c.id, c.user_a_id, c.user_b_id, c.created_at, c.last_message_at,
               c.last_message_content, c.last_message_type, c.last_message_sender_id,
               c.user_a_id AS other_user_id
        FROM public.conversations c
        WHERE c.user_b_id = $1
      )
      SELECT
        uc.id,
        uc.user_a_id,
        uc.user_b_id,
        uc.created_at,
        uc.last_message_at,
        uc.last_message_content,
        uc.last_message_type,
        uc.last_message_sender_id,
        uc.other_user_id,
        u.full_name AS other_user_name,
        u.gender AS other_user_gender,
        u.avatar_seed AS other_user_avatar_seed,
        u.avatar_style AS other_user_avatar_style,
        COALESCE(mr.unread_count, 0)::int AS unread_count
      FROM user_convs uc
      LEFT JOIN public.users u ON u.id = uc.other_user_id
      LEFT JOIN public.message_reads mr ON mr.conversation_id = uc.id AND mr.user_id = $1
      ORDER BY uc.last_message_at DESC NULLS LAST
      LIMIT $2 OFFSET $3;
    `;
    const newRes = await db.query(newSql, [userId, 30, 0]);
    newRes.rows.forEach(r => console.log(r['QUERY PLAN']));

  } catch (err) {
    console.error('Benchmark error:', err);
  } finally {
    await db.pool.end();
  }
}

benchmarkInbox();
