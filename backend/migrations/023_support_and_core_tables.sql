-- Migration 023: Support and core tables (favorites, bug_reports, account_deletion_surveys)
-- Migrates DDL out of runtime server.js and db.js into standard migration.

CREATE TABLE IF NOT EXISTS public.favorites (
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  favorite_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, favorite_user_id)
);

ALTER TABLE public.users ALTER COLUMN avatar_seed TYPE TEXT;

CREATE TABLE IF NOT EXISTS public.bug_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  category TEXT NOT NULL,
  description TEXT NOT NULL,
  app_version TEXT,
  platform TEXT,
  device_info TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_bug_reports_user ON public.bug_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_bug_reports_date ON public.bug_reports(created_at DESC);

CREATE TABLE IF NOT EXISTS public.account_deletion_surveys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT,
  phone_number TEXT,
  reason TEXT NOT NULL,
  feedback TEXT,
  deleted_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_deletion_surveys_date ON public.account_deletion_surveys(deleted_at DESC);

CREATE TABLE IF NOT EXISTS public.google_play_purchases (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  product_id TEXT NOT NULL,
  purchase_token TEXT UNIQUE NOT NULL,
  order_id TEXT,
  purchase_type TEXT NOT NULL,
  amount_paid NUMERIC(10, 2) NOT NULL,
  coins_credited INTEGER DEFAULT 0,
  status TEXT DEFAULT 'COMPLETED',
  voided_at TIMESTAMPTZ,
  void_reason TEXT,
  raw_payload JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_gp_purchases_token ON public.google_play_purchases(purchase_token);
CREATE INDEX IF NOT EXISTS idx_gp_purchases_user ON public.google_play_purchases(user_id);

