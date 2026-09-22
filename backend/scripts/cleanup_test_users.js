require('dotenv').config();
const db = require('../db');

/**
 * Permanently purges all fake/test user accounts and their cascading references.
 * Matches:
 *  - Names with 'joiner', 'test user', 'dummy'
 *  - Test phone patterns (+9198752..., +919999..., +910000...)
 */
async function cleanupTestUsers() {
  console.log('🔍 [cleanupTestUsers] Searching for test/fake users...');
  const searchSql = `
    SELECT id, full_name, phone_number, city, created_at 
    FROM public.users 
    WHERE full_name ILIKE '%joiner%' 
       OR full_name ILIKE '%test user%'
       OR full_name ILIKE '%fake%'
       OR phone_number LIKE '+9198752%'
       OR phone_number LIKE '+9199990%'
       OR phone_number LIKE '+9100000%'
    ORDER BY created_at DESC;
  `;

  const { rows } = await db.query(searchSql);
  if (rows.length === 0) {
    console.log('✅ No test or fake users found in database.');
    await db.pool.end();
    return;
  }

  console.log(`⚠️ Found ${rows.length} test user(s) to remove:`);
  console.table(rows.map(r => ({ id: r.id, name: r.full_name, phone: r.phone_number, city: r.city })));

  const userIds = rows.map(r => r.id);
  const client = await db.pool.connect();

  try {
    await client.query('BEGIN');

    // Discover all tables referencing public.users
    const fkQuery = `
      SELECT tc.table_name, kcu.column_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      JOIN information_schema.constraint_column_usage ccu
        ON ccu.constraint_name = tc.constraint_name
        AND ccu.table_schema = tc.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND ccu.table_name = 'users'
        AND ccu.column_name = 'id';
    `;
    const fks = await client.query(fkQuery);
    for (const fk of fks.rows) {
      try {
        await client.query(`DELETE FROM public."${fk.table_name}" WHERE "${fk.column_name}" = ANY($1)`, [userIds]);
      } catch (_) {}
    }

    const delResult = await client.query(
      `DELETE FROM public.users WHERE id = ANY($1) RETURNING id, full_name, phone_number`,
      [userIds]
    );

    await client.query('COMMIT');
    console.log(`🎉 Successfully purged ${delResult.rowCount} test users from database.`);
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('❌ Error during cleanup:', err.message);
  } finally {
    client.release();
    await db.pool.end();
  }
}

if (require.main === module) {
  cleanupTestUsers();
}

module.exports = { cleanupTestUsers };
