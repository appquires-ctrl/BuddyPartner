const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const db = require('./db');

async function resetAllWallets() {
  console.log('🔄 Starting reset of all wallets and initial balance defaults to 0...');

  try {
    // 1. Alter the default value for wallets balance column to 0
    await db.query('ALTER TABLE public.wallets ALTER COLUMN balance SET DEFAULT 0;');
    console.log('✅ Altered column default: public.wallets.balance DEFAULT 0');

    // 2. Update trigger function for new user wallet creation
    await db.query(`
      CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
      RETURNS TRIGGER AS $$
      BEGIN
        INSERT INTO public.wallets (user_id, balance)
        VALUES (NEW.id, 0)
        ON CONFLICT (user_id) DO NOTHING;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    `);
    console.log('✅ Updated create_wallet_for_new_user trigger function (balance = 0)');

    // 3. Reset all existing account balances to 0
    const updateResult = await db.query('UPDATE public.wallets SET balance = 0;');
    console.log(`✅ Updated ${updateResult.rowCount} existing wallet record(s) to balance = 0.`);

    // 4. Verify all wallets
    const checkResult = await db.query('SELECT count(*) as total, count(*) FILTER (WHERE balance != 0) as non_zero FROM public.wallets;');
    console.log(`📊 Verification: Total wallets = ${checkResult.rows[0].total}, Non-zero wallets = ${checkResult.rows[0].non_zero}`);

    if (parseInt(checkResult.rows[0].non_zero, 10) === 0) {
      console.log('🎉 All user wallets have been successfully verified as 0 coins!');
    } else {
      console.error('⚠️ Warning: Some wallets still have non-zero balance.');
    }
  } catch (err) {
    console.error('❌ Error resetting wallets:', err.message);
  } finally {
    await db.pool.end();
  }
}

resetAllWallets();
