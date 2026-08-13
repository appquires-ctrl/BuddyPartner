require('dotenv').config();
const db = require('../db');

async function runMigration() {
  try {
    console.log('🚀 Running advertisements table migration...');
    
    await db.query(`
      CREATE TABLE IF NOT EXISTS public.advertisements (
        id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
        image_url TEXT NOT NULL,
        click_url TEXT NOT NULL,
        is_active BOOLEAN DEFAULT TRUE,
        display_order INTEGER DEFAULT 0,
        click_count INTEGER DEFAULT 0,
        created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );

      CREATE INDEX IF NOT EXISTS idx_advertisements_is_active ON public.advertisements(is_active);
      CREATE INDEX IF NOT EXISTS idx_advertisements_display_order ON public.advertisements(display_order);
    `);

    console.log('✅ Advertisements table and indexes created successfully!');
    process.exit(0);
  } catch (err) {
    console.error('❌ Error running advertisements table migration:', err.message);
    process.exit(1);
  }
}

runMigration();
