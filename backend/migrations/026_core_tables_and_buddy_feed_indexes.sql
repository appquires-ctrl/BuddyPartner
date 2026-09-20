-- Migration 026: Core Tables Migration & Buddy Feed Performance Index
-- Moves runtime DDL out of service startup and ensures scale indexes exist

CREATE TABLE IF NOT EXISTS public.admin_config (
  id INTEGER PRIMARY KEY DEFAULT 1,
  password_hash TEXT NOT NULL,
  CONSTRAINT single_row CHECK (id = 1)
);

CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

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
CREATE INDEX IF NOT EXISTS idx_gp_purchases_order_id ON public.google_play_purchases(order_id);
CREATE INDEX IF NOT EXISTS idx_gp_purchases_status ON public.google_play_purchases(status);

-- Buddy Feed Scale Index: covers city + target_gender with pre-sorted created_at DESC for open requests
CREATE INDEX IF NOT EXISTS idx_buddy_requests_open_feed 
  ON public.buddy_requests (city, target_gender, created_at DESC) 
  WHERE status = 'open';
