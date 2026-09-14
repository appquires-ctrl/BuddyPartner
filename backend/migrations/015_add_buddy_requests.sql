-- Migration: 015_add_buddy_requests.sql
-- Creates the generic public.buddy_requests table and scale-optimized indexes for 5,000 CCU.

CREATE TABLE IF NOT EXISTS public.buddy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  buddy_type TEXT NOT NULL CHECK (buddy_type IN (
    'movie', 'pizza', 'coffee', 'hangout', 'trip', 'cricket',
    'shopping', 'night_out', 'clubbing', 'long_drive'
  )),
  city TEXT NOT NULL,
  target_gender TEXT NOT NULL CHECK (target_gender IN ('male', 'female', 'all')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open', 'accepted', 'otp_verified'
  )),
  accepter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  otp_code TEXT,
  otp_generated_at TIMESTAMPTZ,
  otp_attempts INTEGER NOT NULL DEFAULT 0,
  accepted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  initiator_coin_cost INTEGER NOT NULL DEFAULT 100,
  accepter_coin_reward INTEGER NOT NULL DEFAULT 50,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Partial index for hot-path city & target gender feed queries (only indexes unresolved open requests)
CREATE INDEX IF NOT EXISTS idx_buddy_requests_open_city_gender
  ON public.buddy_requests (city, target_gender, status) WHERE status = 'open';

-- User lookup indexes for fast initiator and accepter request retrieval
CREATE INDEX IF NOT EXISTS idx_buddy_requests_initiator ON public.buddy_requests (initiator_id, status);
CREATE INDEX IF NOT EXISTS idx_buddy_requests_accepter ON public.buddy_requests (accepter_id, status);
