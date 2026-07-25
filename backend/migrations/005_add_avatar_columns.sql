-- Migration: Add avatar_seed and avatar_style columns to public.users
ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS avatar_seed VARCHAR(50),
ADD COLUMN IF NOT EXISTS avatar_style VARCHAR(50) DEFAULT 'avataaars';
