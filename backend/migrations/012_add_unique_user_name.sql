-- Migration 012: Add unique user_name column to users table
--
-- Description:
-- Adds a unique, case-insensitive user_name column to public.users.
-- Usernames are 3–20 characters, restricted to [a-z0-9._], and indexed uniquely by LOWER(user_name).
-- Existing users without a username will have NULL, which is permitted by PostgreSQL unique indexes.

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS user_name VARCHAR(30);

-- Case-insensitive unique index for fast lookup and collision prevention
CREATE UNIQUE INDEX IF NOT EXISTS idx_users_user_name_lower 
ON public.users (LOWER(user_name));
