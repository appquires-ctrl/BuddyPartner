-- Migration 021: Add varchar_pattern_ops index on LOWER(user_name) for efficient prefix searches (LIKE 'pattern%')
-- Without varchar_pattern_ops, PostgreSQL cannot use standard btree indexes for LIKE/pattern queries under non-C collations.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_username_lower_pattern
  ON public.users (LOWER(user_name) varchar_pattern_ops);
