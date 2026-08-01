-- 007_create_subscriptions_table.sql
-- Create table for managing user subscriptions

CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  plan_duration_days INTEGER NOT NULL,
  amount_paid INTEGER NOT NULL,       -- in rupees
  started_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL,
  payment_reference TEXT,             -- payment gateway transaction id
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_expires ON public.subscriptions(user_id, expires_at);
