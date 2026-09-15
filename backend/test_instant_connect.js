require('dotenv').config();
const db = require('./db');
const redis = require('./redis');
const { instantConnectService } = require('./modules/instant_connect/instant_connect.service');
const { subscriptionsService } = require('./modules/subscriptions/subscriptions.service');

async function runTests() {
  console.log('🧪 Starting Instant Connect Backend Tests...\n');

  try {
    // 1. Schema check & initialization
    console.log('1️⃣ Ensuring Database Schema...');
    const fs = require('fs');
    const path = require('path');
    const sql = fs.readFileSync(path.join(__dirname, 'migrations', '005_create_instant_connect_tables.sql'), 'utf8');
    await db.query(sql);

    const tableRes = await db.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' AND table_name IN ('instant_call_sessions', 'scratch_cards', 'users', 'wallets')
    `);
    const tables = tableRes.rows.map((r) => r.table_name);
    console.log('   Tables found:', tables);
    if (!tables.includes('instant_call_sessions') || !tables.includes('scratch_cards')) {
      throw new Error('Instant connect tables are missing!');
    }
    console.log('   ✅ Schema tables verified.\n');

    // 2. Create Test Male and Female Users
    console.log('2️⃣ Setting up Test Users...');
    const malePhone = '+919999900001';
    const femalePhone = '+919999900002';

    // Cleanup existing test users if any
    await db.query(`DELETE FROM public.users WHERE phone_number IN ($1, $2)`, [malePhone, femalePhone]);

    const maleRes = await db.query(
      `INSERT INTO public.users (phone_number, full_name, gender)
       VALUES ($1, 'Test Male VIP', 'Male')
       RETURNING id`,
      [malePhone]
    );
    const maleId = maleRes.rows[0].id;

    const femaleRes = await db.query(
      `INSERT INTO public.users (phone_number, full_name, gender, incoming_paid_calls_enabled)
       VALUES ($1, 'Test Female Partner', 'Female', TRUE)
       RETURNING id`,
      [femalePhone]
    );
    const femaleId = femaleRes.rows[0].id;

    // Ensure wallets have coins
    await db.query(
      `INSERT INTO public.wallets (user_id, balance) VALUES ($1, 200)
       ON CONFLICT (user_id) DO UPDATE SET balance = 200`,
      [maleId]
    );
    await db.query(
      `INSERT INTO public.wallets (user_id, balance) VALUES ($1, 0)
       ON CONFLICT (user_id) DO UPDATE SET balance = 0`,
      [femaleId]
    );

    // Give both active subscriptions
    await db.query(
      `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
       VALUES ($1, 30, 199, NOW(), NOW() + INTERVAL '30 days'),
              ($2, 30, 199, NOW(), NOW() + INTERVAL '30 days')`,
      [maleId, femaleId]
    );
    console.log(`   ✅ Test users created. Male: ${maleId}, Female: ${femaleId}\n`);

    // 3. Test Male Coin Escrow & Minimum Amount Validation
    console.log('3️⃣ Testing Coin Escrow & Minimum Bid Validation...');
    // Under minimum (< 10)
    const lowBid = await instantConnectService.escrowMaleCoins(maleId, 5);
    console.log('   Low bid (<10) rejected correctly:', !lowBid.success && lowBid.error === 'INVALID_AMOUNT');

    // Valid bid (20 coins)
    const validEscrow = await instantConnectService.escrowMaleCoins(maleId, 20);
    console.log('   Valid bid (20 coins) escrowed. New balance:', validEscrow.newBalance);
    if (!validEscrow.success || validEscrow.newBalance !== 180) {
      throw new Error('Coin escrow balance check failed!');
    }
    console.log('   ✅ Coin escrow passed.\n');

    // 4. Test Queue Cancellation & 100% Refund
    console.log('4️⃣ Testing Queue Cancellation & 100% Refund...');
    const session = await instantConnectService.createSession(maleId, 20);
    const refund = await instantConnectService.refundEscrowedCoins(maleId, 20, session.id);
    console.log('   Refunded 20 coins. Restored balance:', refund.newBalance);
    if (refund.newBalance !== 200) {
      throw new Error('Refund balance mismatch!');
    }
    console.log('   ✅ 100% refund verification passed.\n');

    // 5. Test Call Session & 10-Minute Milestone Scratch Card Generation
    console.log('5️⃣ Testing 10-Minute Milestone & Scratch Card Reward...');
    // Re-escrow 50 coins
    await instantConnectService.escrowMaleCoins(maleId, 50);
    const callSession = await instantConnectService.createSession(maleId, 50);
    await instantConnectService.startCallSession(callSession.id, femaleId, 'test_channel_123');

    // Trigger milestone
    const scratchCard = await instantConnectService.trigger10MinuteMilestone(callSession.id);
    console.log('   Scratch Card generated:', scratchCard);

    // Bid was 50 -> reward should be between 35% (17) and 65% (32)
    if (!scratchCard || scratchCard.coin_reward < 17 || scratchCard.coin_reward > 33) {
      throw new Error(`Scratch card reward ${scratchCard?.coin_reward} outside expected margin range for bid 50!`);
    }
    console.log(`   ✅ Scratch Card generated with ${scratchCard.coin_reward} coins reward (App margin: ${50 - scratchCard.coin_reward} coins).\n`);

    // 6. Test Scratch Card Claiming & Female Wallet Credit
    console.log('6️⃣ Testing Scratch Card Claim & Wallet Credit...');
    const claimRes = await instantConnectService.claimScratchCard(femaleId, scratchCard.id);
    console.log('   Claim response:', claimRes);
    if (!claimRes.success || claimRes.newBalance !== scratchCard.coin_reward) {
      throw new Error('Scratch card wallet credit mismatch!');
    }

    // Try claiming same card again (should fail)
    const doubleClaim = await instantConnectService.claimScratchCard(femaleId, scratchCard.id);
    console.log('   Double claim prevented correctly:', !doubleClaim.success && doubleClaim.error === 'ALREADY_SCRATCHED');
    console.log('   ✅ Scratch Card claim passed.\n');

    // 7. Test Female Status & Scratch Card Counts
    console.log('7️⃣ Testing Female Status Query...');
    const femaleStatus = await instantConnectService.getFemaleStatus(femaleId);
    console.log('   Female status:', femaleStatus);
    if (femaleStatus.totalScratchedCards !== 1 || femaleStatus.totalScratchedCoins !== scratchCard.coin_reward) {
      throw new Error('Female status aggregations mismatch!');
    }
    console.log('   ✅ Female status check passed.\n');

    // 8. Test Redis Priority Queue Scoring
    console.log('8️⃣ Testing Redis Priority Queue Ordering...');
    const now = Date.now();
    // Male 1 bids 20
    const score1 = 20 * Math.pow(10, 11) + (Math.pow(10, 11) - (now % Math.pow(10, 11)));
    await redis.zadd('test:male_queue', score1, 'male_20');

    // Male 2 bids 100 later
    const score2 = 100 * Math.pow(10, 11) + (Math.pow(10, 11) - ((now + 5000) % Math.pow(10, 11)));
    await redis.zadd('test:male_queue', score2, 'male_100');

    // Male 3 bids 50 later
    const score3 = 50 * Math.pow(10, 11) + (Math.pow(10, 11) - ((now + 10000) % Math.pow(10, 11)));
    await redis.zadd('test:male_queue', score3, 'male_50');

    const topRanked = await redis.zrevrange('test:male_queue', 0, -1);
    console.log('   Queue ordered by bid amount descending:', topRanked);
    if (topRanked[0] !== 'male_100' || topRanked[1] !== 'male_50' || topRanked[2] !== 'male_20') {
      throw new Error('Redis priority queue ordering failed!');
    }
    await redis.del('test:male_queue');
    console.log('   ✅ Redis priority queue ordering passed.\n');

    // Cleanup test users
    await db.query(`DELETE FROM public.users WHERE phone_number IN ($1, $2)`, [malePhone, femalePhone]);

    console.log(' ALL INSTANT CONNECT BACKEND TESTS PASSED SUCCESSFULLY! 🚀');
    process.exit(0);
  } catch (err) {
    console.error('❌ Test failed with error:', err);
    process.exit(1);
  }
}

runTests();
