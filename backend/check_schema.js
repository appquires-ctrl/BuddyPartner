require('dotenv').config();
const db = require('./db');

async function checkUsersSchema() {
  const result = await db.query(`
    SELECT column_name, data_type 
    FROM information_schema.columns 
    WHERE table_name = 'users';
  `);
  console.log('Columns in public.users:', result.rows);
  db.pool.end();
}

checkUsersSchema();
