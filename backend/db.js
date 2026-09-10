const { Pool } = require('pg');

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  console.error('❌ Error: DATABASE_URL environment variable is not defined.');
  process.exit(1);
}

/**
 * PostgreSQL Connection Pool Configuration for Neon Serverless
 * - max: 20 (Keeps connection footprint below Neon compute limits per instance).
 *   NOTE: For horizontal scaling with multiple instances, use Neon's built-in PgBouncer
 *   by appending '-pooler' to the host in DATABASE_URL (e.g. ep-xyz-pooler.region.neon.tech).
 * - connectionTimeoutMillis: 10000 (Allows Neon compute to wake from scale-to-zero cold storage).
 * - idleTimeoutMillis: 30000 (Releases idle clients after 30 seconds).
 */
const pool = new Pool({
  connectionString: connectionString,
  ssl: connectionString.includes('localhost') || connectionString.includes('127.0.0.1')
    ? false
    : { rejectUnauthorized: false },
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 10000,
});

pool.on('connect', () => {
  // Client connected successfully
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
  return pool.query(`ALTER TABLE public.users ALTER COLUMN avatar_seed TYPE TEXT;`);
}).catch((err) => {
  console.error('❌ Failed to initialize database schemas:', err.message);
});

/**
 * Profiled query executor with slow-query detection (>200ms)
 * @param {string|object} text - SQL query or QueryConfig object
 * @param {Array} [params] - Query parameters
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    const duration = Date.now() - start;
    if (duration > 200) {
      const sanitized = typeof text === 'string'
        ? text.replace(/\s+/g, ' ').trim().slice(0, 160)
        : (text?.text || 'prepared').replace(/\s+/g, ' ').trim().slice(0, 160);
      console.warn(`⚠️ [SLOW QUERY: ${duration}ms] ${sanitized}...`);
    }
    return res;
  } catch (err) {
    const duration = Date.now() - start;
    const sanitized = typeof text === 'string'
      ? text.replace(/\s+/g, ' ').trim().slice(0, 120)
      : 'prepared';
    console.error(`❌ [QUERY ERROR: ${duration}ms] ${err.message} | Query: ${sanitized}`);
    throw err;
  }
}

module.exports = {
  query,
  pool,
};
