-- 005_alter_google_play_purchases_status.sql
-- Add status and voided tracking columns to google_play_purchases for chargeback and refund reconciliation

ALTER TABLE public.google_play_purchases 
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'COMPLETED',
  ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS void_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_gp_purchases_order_id ON public.google_play_purchases(order_id);
CREATE INDEX IF NOT EXISTS idx_gp_purchases_status ON public.google_play_purchases(status);
