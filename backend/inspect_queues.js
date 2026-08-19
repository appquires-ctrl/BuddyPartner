require('dotenv').config();
const db = require('./db');
const redis = require('./redis');

async function inspectQueues() {
  console.log('🔍 ═══════════ BUDDYPARTNER INSTANT CONNECT LIVE DASHBOARD ═══════════\n');

  try {
    // 1. Male Priority Queue from Redis
    const maleQueueIds = await redis.zrevrange('instant:male_queue', 0, -1, 'WITHSCORES');
    console.log(`👨 MALE PRIORITY QUEUE (Waiting in Redis): ${maleQueueIds.length / 2} User(s)`);
    console.log('─'.repeat(70));

    if (maleQueueIds.length === 0) {
      console.log('   (No male users currently in queue)\n');
    } else {
      for (let i = 0; i < maleQueueIds.length; i += 2) {
        const userId = maleQueueIds[i];
        const score = maleQueueIds[i + 1];
        const sessionStr = await redis.get(`instant:male_session:${userId}`);
        const sessionData = sessionStr ? JSON.parse(sessionStr) : {};

        // Fetch user name from DB
        const userRes = await db.query('SELECT full_name, phone_number FROM public.users WHERE id = $1', [userId]);
        const user = userRes.rows[0] || {};

        console.log(`   [#${(i / 2) + 1}] Name: ${user.full_name || 'Unknown'} | Phone: ${user.phone_number || 'N/A'}`);
        console.log(`        Bid Amount: ₹${sessionData.bidAmount || 'N/A'} Coins | Session ID: ${sessionData.sessionId || 'N/A'}`);
        console.log(`        User ID: ${userId} | Redis Score: ${score}\n`);
      }
    }

    // 2. Female Pool from Redis
    const femaleIds = await redis.smembers('instant:female_pool');
    console.log(`👩 FEMALE ACTIVE POOL (Online & Ready with Toggle ON in Redis): ${femaleIds.length} User(s)`);
    console.log('─'.repeat(70));

    if (femaleIds.length === 0) {
      console.log('   (No female users currently in active pool)\n');
    } else {
      for (let i = 0; i < femaleIds.length; i++) {
        const userId = femaleIds[i];
        const isSnoozed = await redis.get(`instant:snooze:${userId}`);
        const userRes = await db.query(
          'SELECT full_name, phone_number, incoming_paid_calls_enabled FROM public.users WHERE id = $1',
          [userId]
        );
        const user = userRes.rows[0] || {};

        console.log(`   [${i + 1}] Name: ${user.full_name || 'Unknown'} | Phone: ${user.phone_number || 'N/A'}`);
        console.log(`       User ID: ${userId} | Status: ${isSnoozed ? '⚠️ Snoozed (AFK)' : '✅ Active & Available'}\n`);
      }
    }

    // 3. Active Instant Calls from Database
    const activeCallsRes = await db.query(`
      SELECT s.id, s.bid_amount, s.status, s.agora_channel_name, s.started_at, s.scratch_card_unlocked,
             m.full_name as male_name, m.phone_number as male_phone,
             f.full_name as female_name, f.phone_number as female_phone
      FROM public.instant_call_sessions s
      LEFT JOIN public.users m ON m.id = s.male_user_id
      LEFT JOIN public.users f ON f.id = s.female_user_id
      WHERE s.status = 'in_call'
      ORDER BY s.started_at DESC
    `);

    console.log(`📞 ONGOING ACTIVE INSTANT CALLS: ${activeCallsRes.rows.length} Call(s)`);
    console.log('─'.repeat(70));

    if (activeCallsRes.rows.length === 0) {
      console.log('   (No active instant calls in progress right now)\n');
    } else {
      for (const call of activeCallsRes.rows) {
        const elapsedSecs = Math.floor((Date.now() - new Date(call.started_at).getTime()) / 1000);
        console.log(`   [Call ID: ${call.id}] Channel: ${call.agora_channel_name}`);
        console.log(`       Male: ${call.male_name} (${call.male_phone}) ──► Female: ${call.female_name} (${call.female_phone})`);
        console.log(`       Bid: ₹${call.bid_amount} Coins | Duration: ${Math.floor(elapsedSecs / 60)}m ${elapsedSecs % 60}s | 10m Milestone: ${call.scratch_card_unlocked ? '🎁 Unlocked' : '⏳ In Progress'}\n`);
      }
    }

    // 4. All Females with Toggle ON in DB
    const allToggledFemalesRes = await db.query(`
      SELECT id, full_name, phone_number 
      FROM public.users 
      WHERE incoming_paid_calls_enabled = TRUE
    `);
    console.log(`📋 TOTAL FEMALE ACCOUNTS WITH TOGGLE ON (DB): ${allToggledFemalesRes.rows.length}`);
    console.log('═'.repeat(70));
    console.log('\n✅ Inspection complete.');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error inspecting queues:', err.message);
    process.exit(1);
  }
}

inspectQueues();
