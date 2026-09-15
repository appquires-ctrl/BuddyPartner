const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const db = require('../db');

async function setupAccounts() {
  console.log('Seeding / resetting 3 test accounts for Buddy Feature live test...');

  // Account A (Initiator, Male)
  await db.query(`
    INSERT INTO public.users (id, phone_number, full_name, user_name, gender, city, is_banned, avatar_seed, avatar_style)
    VALUES (
      'fa4c162e-877d-4d08-9eac-4f80f02123e7',
      '+919999999999',
      'Aarav Sharma',
      'aarav_initiator',
      'male',
      'mumbai',
      FALSE,
      'aarav_seed',
      'avataaars'
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = 'Aarav Sharma',
      gender = 'male',
      city = 'mumbai',
      is_banned = FALSE;
  `);

  await db.query(`
    INSERT INTO public.wallets (user_id, balance)
    VALUES ('fa4c162e-877d-4d08-9eac-4f80f02123e7', 250)
    ON CONFLICT (user_id) DO UPDATE SET balance = 250;
  `);

  // Active VIP subscription for Account A
  await db.query(`
    DELETE FROM public.subscriptions WHERE user_id = 'fa4c162e-877d-4d08-9eac-4f80f02123e7';
  `);
  await db.query(`
    INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at)
    VALUES ('fa4c162e-877d-4d08-9eac-4f80f02123e7', 30, 235, NOW(), NOW() + INTERVAL '30 days');
  `);

  // Account B (Accepter, Female)
  const userBRes = await db.query(`
    INSERT INTO public.users (id, phone_number, full_name, user_name, gender, city, is_banned, avatar_seed, avatar_style)
    VALUES (
      'b2222222-2222-2222-2222-222222222222',
      '+918888888888',
      'Ananya Verma',
      'ananya_accepter',
      'female',
      'mumbai',
      FALSE,
      'ananya_seed',
      'avataaars'
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = 'Ananya Verma',
      gender = 'female',
      city = 'mumbai',
      is_banned = FALSE
    RETURNING id;
  `);

  await db.query(`
    INSERT INTO public.wallets (user_id, balance)
    VALUES ('b2222222-2222-2222-2222-222222222222', 20)
    ON CONFLICT (user_id) DO UPDATE SET balance = 20;
  `);

  // Account C (Third User, Female)
  await db.query(`
    INSERT INTO public.users (id, phone_number, full_name, user_name, gender, city, is_banned, avatar_seed, avatar_style)
    VALUES (
      'c3333333-3333-3333-3333-333333333333',
      '+917777777777',
      'Pooja Patel',
      'pooja_third',
      'female',
      'mumbai',
      FALSE,
      'pooja_seed',
      'avataaars'
    )
    ON CONFLICT (id) DO UPDATE SET
      full_name = 'Pooja Patel',
      gender = 'female',
      city = 'mumbai',
      is_banned = FALSE;
  `);

  await db.query(`
    INSERT INTO public.wallets (user_id, balance)
    VALUES ('c3333333-3333-3333-3333-333333333333', 10)
    ON CONFLICT (user_id) DO UPDATE SET balance = 10;
  `);

  // Clean any lingering buddy requests from previous tests
  await db.query(`
    DELETE FROM public.buddy_requests
    WHERE initiator_id IN ('fa4c162e-877d-4d08-9eac-4f80f02123e7', 'b2222222-2222-2222-2222-222222222222', 'c3333333-3333-3333-3333-333333333333');
  `);

  console.log('✅ Accounts seeded:');
  console.log('- Account A (fa4c162e-877d-4d08-9eac-4f80f02123e7): +919999999999 | Aarav Sharma (male, mumbai) | Sub: Active | Balance: 250');
  console.log('- Account B (b2222222-2222-2222-2222-222222222222): +918888888888 | Ananya Verma (female, mumbai) | Balance: 20');
  console.log('- Account C (c3333333-3333-3333-3333-333333333333): +917777777777 | Pooja Patel (female, mumbai) | Balance: 10');
  process.exit(0);
}

setupAccounts().catch(e => { console.error(e); process.exit(1); });
