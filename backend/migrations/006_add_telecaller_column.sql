-- Migration 006: Add is_telecaller column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_telecaller BOOLEAN;

-- Backfill existing female users to default is_telecaller = TRUE
UPDATE public.users 
SET is_telecaller = TRUE 
WHERE LOWER(gender) IN ('female', 'girl', 'woman') AND is_telecaller IS NULL;
