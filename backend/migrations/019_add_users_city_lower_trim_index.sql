-- Migration 019: Add functional index on public.users (LOWER(TRIM(city)))
--
-- Description:
-- Adds a non-blocking functional index on LOWER(TRIM(city)) for public.users.
-- Optimizes the Buddy FCM notification query in buddy.socket.js:
--   WHERE LOWER(TRIM(u.city)) = $1
--   AND ($2 = 'all' OR LOWER(TRIM(u.gender)) = $2)
--
-- Note: Uses CREATE INDEX CONCURRENTLY to prevent locking writes on public.users.
-- Must be run outside of a multi-statement transaction block.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_city_lower_trim 
  ON public.users (LOWER(TRIM(city)));
