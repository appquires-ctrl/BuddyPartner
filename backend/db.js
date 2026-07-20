const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  console.error('❌ Error: DATABASE_URL environment variable is not defined.');
  process.exit(1);
}

const pool = new Pool({
  connectionString: connectionString,
  ssl: connectionString.includes('localhost') || connectionString.includes('127.0.0.1')
    ? false
    : { rejectUnauthorized: false }, // Required for secure Neon connections
  max: 20, // Maximum pool size
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('connect', () => {
  console.log('✅ Connected to PostgreSQL Database (Neon)');
});

pool.on('error', (err) => {
  console.error('❌ Unexpected database error on idle client:', err.message);
});

// Initialize the favorites table if it doesn't exist
pool.query(`
  CREATE TABLE IF NOT EXISTS public.favorites (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    favorite_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, favorite_user_id)
  );
`).then(() => {
  console.log('✅ Favorites table checked/initialized in database.');
}).catch((err) => {
  console.error('❌ Failed to initialize favorites table:', err.message);
});

module.exports = {
  query: (text, params) => pool.query(text, params),
  pool,
};
