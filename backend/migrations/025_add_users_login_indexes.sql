-- Migration 025: Scale Indexes for Users Login & Profile Retrieval
-- Enables direct Index Scan for phone_number, mobile, and functional LOWER(user_name)

CREATE INDEX IF NOT EXISTS idx_users_mobile 
  ON public.users(mobile);

CREATE INDEX IF NOT EXISTS idx_users_phone_number 
  ON public.users(phone_number);

CREATE INDEX IF NOT EXISTS idx_users_lower_username_btree 
  ON public.users(LOWER(user_name));
