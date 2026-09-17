require('dotenv').config();
const db = require('../db');
const redis = require('../redis');
const { ModerationService } = require('../modules/moderation/moderation.service');
const adminService = require('../modules/admin/admin.service');

async function verifyBanCache() {
  console.log('--- 1.3 Moderation is_banned Redis Cache & Invalidation Verification ---');

  // Find a test user or insert one
  const userRes = await db.query(`SELECT id FROM public.users LIMIT 1`);
  if (userRes.rows.length === 0) {
    console.error('No users found in database to test.');
    process.exit(1);
  }
  const testUserId = userRes.rows[0].id;
  const cacheKey = `user:is_banned:${testUserId}`;

  // Ensure clean initial state
  await redis.del(cacheKey);

  // 1. First call: Cache Miss -> DB Query -> Cached in Redis
  console.log(`Testing first lookup for user ${testUserId}...`);
  const status1 = await ModerationService.isUserBlocked(testUserId);
  console.log('Lookup 1 result:', status1);

  const cachedVal1 = await redis.get(cacheKey);
  console.log(`[Cache Verification] Redis key '${cacheKey}' value: '${cachedVal1}'`);
  if (cachedVal1 === null) {
    console.error('❌ FAILED: Ban status was not cached in Redis!');
    process.exit(1);
  }

  // 2. Second call: Cache Hit
  console.log(`Testing second lookup (should hit Redis cache)...`);
  const status2 = await ModerationService.isUserBlocked(testUserId);
  console.log('Lookup 2 result:', status2);
  if (status1.isBanned !== status2.isBanned) {
    console.error('❌ FAILED: Inconsistent ban status between miss and hit!');
    process.exit(1);
  }

  // 3. Admin Ban -> Invalidation check
  console.log(`Simulating Admin Ban for user ${testUserId}...`);
  await adminService.setBanStatus(testUserId, true);
  const cacheAfterBan = await redis.get(cacheKey);
  console.log(`[Invalidation Verification] Redis key after admin ban: '${cacheAfterBan}' (expected null)`);
  if (cacheAfterBan !== null) {
    console.error('❌ FAILED: Redis cache was NOT invalidated upon admin ban!');
    process.exit(1);
  }

  // 4. Lookup immediately after ban -> fresh DB read -> cached '1'
  const status3 = await ModerationService.isUserBlocked(testUserId);
  console.log('Lookup 3 result (after ban):', status3);
  if (!status3.isBanned) {
    console.error('❌ FAILED: User was banned, but isUserBlocked reported false!');
    process.exit(1);
  }
  const cachedVal3 = await redis.get(cacheKey);
  console.log(`[Cache Verification] Redis key '${cacheKey}' value after ban: '${cachedVal3}' (expected '1')`);

  // 5. Unban cleanup
  console.log(`Unbanning test user ${testUserId}...`);
  await adminService.setBanStatus(testUserId, false);
  const finalStatus = await ModerationService.isUserBlocked(testUserId);
  console.log('Final status (after unban):', finalStatus);

  console.log('✅ PASSED: Moderation is_banned Redis caching and two-way invalidation are verified!');
  process.exit(0);
}

verifyBanCache().catch((err) => {
  console.error('❌ Error during ban cache verification:', err);
  process.exit(1);
});
