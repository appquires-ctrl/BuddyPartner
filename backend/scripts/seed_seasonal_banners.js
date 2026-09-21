require('dotenv').config();
const db = require('../db');

async function seed() {
  try {
    const check = await db.query('SELECT count(*) FROM seasonal_banners');
    if (parseInt(check.rows[0].count, 10) === 0) {
      await db.query(`
        INSERT INTO seasonal_banners (
          name, image_url, priority, start_date, end_date, is_active, sheet_config, otp_reward
        ) VALUES (
          $1, $2, $3, $4, $5, $6, $7, $8
        )
      `, [
        'Find Your Garba Partner',
        'https://res.cloudinary.com/o8dwm2ig/image/upload/v1789916439/buddy_banners/jyreac8grrwdtnflsa6p.png',
        1,
        new Date(Date.now() - 2 * 86400000),
        new Date(Date.now() + 30 * 86400000),
        true,
        JSON.stringify({
          title: 'Garba Buddy 🪔',
          subtitle: 'Find someone who matches your Garba vibes',
          broadcastCoinCost: 1,
          buddyType: 'garba',
          accentColor: '#9333EA'
        }),
        JSON.stringify({
          type: 'STATIC',
          staticCoinAmount: 50,
          malePercentage: 40,
          femalePercentage: 20
        })
      ]);
      console.log('✅ Seeded default Garba Buddy seasonal banner!');
    } else {
      console.log('Banners already exist count:', check.rows[0].count);
    }
    process.exit(0);
  } catch (err) {
    console.error('Seed error:', err.message);
    process.exit(1);
  }
}

seed();
