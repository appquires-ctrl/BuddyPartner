require('dotenv').config();
const db = require('./db');
const { ModerationService } = require('./modules/moderation/moderation.service');
const jwt = require('jsonwebtoken');
const expressApp = require('./server').app;

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

async function runDistinctReporterBanTests() {
  console.log('🚀 Running 3-Distinct-Reporter Ban Automation Test Suite...\n');

  let testPort = 3998;
  let serverInstance;

  try {
    // ────────────────────────────────────────────────────────────────────────
    // SETUP: Provision Test Users
    // ────────────────────────────────────────────────────────────────────────
    const targetPhone = '+919888877770';
    const reporterAPhone = '+919888877771';
    const reporterBPhone = '+919888877772';
    const reporterCPhone = '+919888877773';

    // Target User
    const targetRes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender, is_banned)
      VALUES ($1, 'Target Account', 'male', FALSE)
      ON CONFLICT (phone_number) DO UPDATE SET is_banned = FALSE
      RETURNING id;
    `, [targetPhone]);
    const targetId = targetRes.rows[0].id;

    // Reporter A
    const reporterARes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender)
      VALUES ($1, 'Reporter A', 'female')
      ON CONFLICT (phone_number) DO UPDATE SET full_name = EXCLUDED.full_name
      RETURNING id;
    `, [reporterAPhone]);
    const reporterAId = reporterARes.rows[0].id;

    // Reporter B
    const reporterBRes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender)
      VALUES ($1, 'Reporter B', 'male')
      ON CONFLICT (phone_number) DO UPDATE SET full_name = EXCLUDED.full_name
      RETURNING id;
    `, [reporterBPhone]);
    const reporterBId = reporterBRes.rows[0].id;

    // Reporter C
    const reporterCRes = await db.query(`
      INSERT INTO public.users (phone_number, full_name, gender)
      VALUES ($1, 'Reporter C', 'female')
      ON CONFLICT (phone_number) DO UPDATE SET full_name = EXCLUDED.full_name
      RETURNING id;
    `, [reporterCPhone]);
    const reporterCId = reporterCRes.rows[0].id;

    // Clean old reports for target user
    await db.query('DELETE FROM public.reports WHERE reported_user_id = $1', [targetId]);

    console.log(`Target User ID: ${targetId}`);
    console.log(`Reporter A ID:  ${reporterAId}`);
    console.log(`Reporter B ID:  ${reporterBId}`);
    console.log(`Reporter C ID:  ${reporterCId}\n`);

    // Start local server instance for API testing
    serverInstance = expressApp.listen(testPort);

    // ────────────────────────────────────────────────────────────────────────
    // TEST 1: Same person reporting 3 times does NOT trigger a ban
    // ────────────────────────────────────────────────────────────────────────
    console.log('====================================================');
    console.log('--- TEST 1: Same Reporter Filing 3 Separate Reports ---');
    console.log('====================================================');

    console.log('\n[Report 1] Reporter A files report 1 against Target User...');
    const r1 = await ModerationService.fileReport(reporterAId, targetId, 'Spam');
    console.log('Report 1 Result:', r1.moderationResult);

    console.log('\n[Report 2] Reporter A files report 2 against Target User...');
    const r2 = await ModerationService.fileReport(reporterAId, targetId, 'Inappropriate messages');
    console.log('Report 2 Result:', r2.moderationResult);

    console.log('\n[Report 3] Reporter A files report 3 against Target User...');
    const r3 = await ModerationService.fileReport(reporterAId, targetId, 'Harassment');
    console.log('Report 3 Result:', r3.moderationResult);

    // Verify DB status
    const status1 = await ModerationService.isUserBlocked(targetId);
    console.log('\nUser status after 3 reports from SAME reporter:', status1);

    if (r3.moderationResult.distinctReporterCount !== 1) {
      throw new Error(`Expected distinct count = 1, but got ${r3.moderationResult.distinctReporterCount}`);
    }
    if (status1.isBanned) {
      throw new Error('FAIL: Target User was banned by reports from a single reporter!');
    }
    console.log('✅ TEST 1 PASSED: 3 reports from the same reporter produced distinct_count = 1 and did NOT ban the user.');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 2: Reports from 3 DISTINCT reporters trigger permanent ban
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n====================================================');
    console.log('--- TEST 2: 3 DISTINCT Reporters Trigger Permanent Ban ---');
    console.log('====================================================');

    console.log('\n[Report 4] Reporter B (2nd distinct person) files report against Target User...');
    const r4 = await ModerationService.fileReport(reporterBId, targetId, 'Abusive content');
    console.log('Report 4 Result:', r4.moderationResult);

    if (r4.moderationResult.distinctReporterCount !== 2 || r4.moderationResult.isBanned !== false) {
      throw new Error(`Expected distinct count = 2 and isBanned = false on 2nd distinct reporter`);
    }
    console.log('✅ Distinct count is now 2. User remains unbanned.');

    console.log('\n[Report 5] Reporter C (3rd distinct person) files report against Target User...');
    const r5 = await ModerationService.fileReport(reporterCId, targetId, 'Fraud');
    console.log('Report 5 Result:', r5.moderationResult);

    if (r5.moderationResult.distinctReporterCount !== 3 || r5.moderationResult.isBanned !== true) {
      throw new Error(`Expected distinct count = 3 and isBanned = true on 3rd distinct reporter!`);
    }

    const status2 = await ModerationService.isUserBlocked(targetId);
    console.log('\nUser status after 3 DISTINCT reporters:', status2);
    if (!status2.isBanned) {
      throw new Error('FAIL: Target User is not marked is_banned in database after 3 distinct reporters!');
    }
    console.log('✅ TEST 2 PASSED: 3 distinct reporters successfully triggered an immediate permanent ban!');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 3: Auth middleware rejection for Banned User
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n====================================================');
    console.log('--- TEST 3: HTTP Auth Middleware Rejection Test ---');
    console.log('====================================================');

    const token = jwt.sign({ id: targetId, phone: targetPhone }, JWT_SECRET, { expiresIn: '1h' });

    const authRes = await fetch(`http://localhost:${testPort}/api/auth/me`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const authBody = await authRes.json();

    console.log(`HTTP Response Status Code: ${authRes.status}`);
    console.log('HTTP Response Body:', JSON.stringify(authBody, null, 2));

    if (authRes.status !== 403) {
      throw new Error(`Expected HTTP 403 Forbidden, but received HTTP ${authRes.status}`);
    }
    if (authBody.error !== 'ACCOUNT_BANNED') {
      throw new Error(`Expected error 'ACCOUNT_BANNED', but got ${authBody.error}`);
    }
    if (authBody.suspended_until) {
      throw new Error('Old suspended_until property should NOT be present in response');
    }
    console.log('✅ TEST 3 PASSED: Banned user is rejected with HTTP 403 ACCOUNT_BANNED and no suspension timing.');

    // ────────────────────────────────────────────────────────────────────────
    // TEST 4: Manual Admin Unban & Report History Clear
    // ────────────────────────────────────────────────────────────────────────
    console.log('\n====================================================');
    console.log('--- TEST 4: Manual Admin Unban SQL Walkthrough ---');
    console.log('====================================================');

    console.log('\nExecuting manual Admin Unban SQL...');
    await db.query(`UPDATE public.users SET is_banned = false WHERE id = $1`, [targetId]);
    await db.query(`DELETE FROM public.reports WHERE reported_user_id = $1`, [targetId]);

    const statusAfterUnban = await ModerationService.isUserBlocked(targetId);
    const reportsAfterUnban = await db.query(
      'SELECT COUNT(*)::int AS count FROM public.reports WHERE reported_user_id = $1',
      [targetId]
    );

    console.log('Target User status after manual unban:', statusAfterUnban);
    console.log(`Remaining report rows for user in DB: ${reportsAfterUnban.rows[0].count}`);

    if (statusAfterUnban.isBanned) {
      throw new Error('FAIL: Target User should be unbanned after manual SQL execution');
    }
    if (reportsAfterUnban.rows[0].count !== 0) {
      throw new Error('FAIL: Report history was not cleared on manual unban');
    }

    // Verify user can log in / call API again
    const unbanAuthRes = await fetch(`http://localhost:${testPort}/api/auth/me`, {
      headers: { 'Authorization': `Bearer ${token}` }
    });
    const unbanAuthBody = await unbanAuthRes.json();
    console.log('\nAPI Access after manual unban status:', unbanAuthRes.status);
    console.log('User profile response:', JSON.stringify(unbanAuthBody.user?.fullName));

    if (unbanAuthRes.status !== 200 || !unbanAuthBody.success) {
      throw new Error(`Expected HTTP 200 after unban, got HTTP ${unbanAuthRes.status}`);
    }

    console.log('✅ TEST 4 PASSED: Manual admin unban SQL successfully cleared ban status & report history, restoring API access!');

    console.log('\n====================================================');
    console.log(' ALL DISTINCT REPORTER BAN VERIFICATION TESTS PASSED!');
    console.log('====================================================\n');

  } catch (err) {
    console.error('❌ Test failed:', err);
  } finally {
    if (serverInstance) serverInstance.close();
    process.exit(0);
  }
}

runDistinctReporterBanTests();
