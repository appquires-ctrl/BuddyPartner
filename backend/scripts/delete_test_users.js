require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const db = require('../db');

async function main() {
  const client = await db.pool.connect();
  try {
    const res = await client.query(`
      SELECT id, full_name, user_name, phone_number, gender, created_at
      FROM public.users
      ORDER BY created_at ASC
    `);

    const isTest = (u) => {
      const name = (u.full_name || '').trim().toLowerCase();
      const username = (u.user_name || '').trim().toLowerCase();
      const phone = (u.phone_number || '').trim();

      return (
        name.startsWith('accepter') ||
        name.startsWith('initiator') ||
        name.startsWith('test initiator') ||
        name.startsWith('cap user') ||
        name.startsWith('reporter') ||
        name.startsWith('reported') ||
        name.startsWith('target account') ||
        name.includes('superstar') ||
        name.startsWith('searcher') ||
        name.startsWith('banned user') ||
        name.startsWith('second user') ||
        name.startsWith('taken user') ||
        name.startsWith('dan different') ||
        name.includes('test user') ||
        name.startsWith('eve_intruder') ||
        name.startsWith('low balance user') ||
        name.startsWith('alice_initiator') ||
        name.startsWith('bob_accepter') ||
        name === 'user c' ||
        username.startsWith('accepter') ||
        username.startsWith('initiator') ||
        username.startsWith('cap_user') ||
        username.startsWith('taken_') ||
        username.startsWith('avail_') ||
        phone.startsWith('+100000') ||
        phone.startsWith('+917777') ||
        phone.startsWith('+9199999999') ||
        phone.startsWith('+9199999888') ||
        phone.startsWith('+9199999777') ||
        phone.startsWith('+9198888777')
      );
    };

    const toDelete = res.rows.filter(isTest);
    const toKeep = res.rows.filter(u => !isTest(u));

    console.log(`Preserving ${toKeep.length} real accounts.`);
    console.log(`Deleting ${toDelete.length} test accounts...`);

    if (toDelete.length === 0) {
      console.log('No test accounts to delete.');
      return;
    }

    const idsToDelete = toDelete.map(u => u.id);

    await client.query('BEGIN');
    const deleteRes = await client.query(
      'DELETE FROM public.users WHERE id = ANY($1::uuid[])',
      [idsToDelete]
    );
    await client.query('COMMIT');

    console.log(`✅ Successfully deleted ${deleteRes.rowCount} test users from database!`);

    const remainingRes = await client.query('SELECT COUNT(*)::int AS count FROM public.users');
    console.log(`Total users remaining in DB: ${remainingRes.rows[0].count}`);

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error deleting test users:', err);
  } finally {
    client.release();
    await db.pool.end();
  }
}

main();
