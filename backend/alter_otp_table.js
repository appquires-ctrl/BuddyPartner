require('dotenv').config();
const db = require('./db');

async function run() {
  try {
    console.log('Altering otp_code column length...');
    await db.query('ALTER TABLE public.otp_verifications ALTER COLUMN otp_code TYPE VARCHAR(100);');
    console.log('✅ Altered column successfully to VARCHAR(100).');
    process.exit(0);
  } catch (err) {
    console.error('❌ Failed to alter column:', err.message);
    process.exit(1);
  }
}

run();
