require('dotenv').config();
const db = require('../db');

async function runMigration() {
  try {
    console.log('🚀 Running seasonal_banners table migration...');

    await db.query(`
      CREATE TABLE IF NOT EXISTS public.seasonal_banners (
        id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        image_url TEXT NOT NULL,
        priority INTEGER DEFAULT 1,
        start_date TIMESTAMPTZ,
        end_date TIMESTAMPTZ,
        is_active BOOLEAN DEFAULT TRUE,
        sheet_config JSONB NOT NULL DEFAULT '{}'::jsonb,
        otp_reward JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_seasonal_banners_is_active ON public.seasonal_banners(is_active);
      CREATE INDEX IF NOT EXISTS idx_seasonal_banners_priority ON public.seasonal_banners(priority);
    `);

    console.log('✅ seasonal_banners table and indexes created successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error running seasonal_banners table migration:', err.message);
    process.exit(1);
  }
}

runMigration();
