-- Migration 016: Dual-Balance Wallet + Corrected Buddy Meetup Flow + Payout Hardening
-- Reversible: See 016_dual_balance_and_corrected_buddy_down.sql

-- 1. DROP AND RECREATE public.wallets
DROP TABLE IF EXISTS public.wallets CASCADE;

CREATE TABLE public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  spendable_balance BIGINT NOT NULL DEFAULT 0,
  earned_balance BIGINT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT chk_wallets_spendable_balance_non_negative CHECK (spendable_balance >= 0),
  CONSTRAINT chk_wallets_earned_balance_non_negative CHECK (earned_balance >= 0)
);

CREATE INDEX IF NOT EXISTS idx_wallets_user ON public.wallets(user_id);

-- 2. DROP AND RECREATE public.wallet_transactions
DROP TABLE IF EXISTS public.wallet_transactions CASCADE;

CREATE TABLE public.wallet_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  spendable_delta BIGINT NOT NULL DEFAULT 0,
  earned_delta BIGINT NOT NULL DEFAULT 0,
  idempotency_key TEXT UNIQUE,
  reason TEXT NOT NULL CHECK (reason IN (
    'iap_purchase',
    'razorpay_purchase',
    'recharge',
    'buddy_spend',
    'buddy_reward',
    'call_spend',
    'call_earning',
    'withdrawal_hold',
    'withdrawal_reject_refund',
    'admin_grant',
    'instant_call_scratch_reward',
    'instant_call_escrow',
    'instant_call_refund',
    'signup_bonus'
  )),
  reference_id TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created 
  ON public.wallet_transactions(user_id, created_at DESC);

-- 3. DROP AND RECREATE public.buddy_requests
DROP TABLE IF EXISTS public.buddy_handshakes CASCADE;
DROP TABLE IF EXISTS public.buddy_requests CASCADE;

CREATE TABLE public.buddy_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  buddy_type TEXT NOT NULL CHECK (buddy_type IN (
    'movie', 'pizza', 'coffee', 'hangout', 'trip', 'cricket',
    'shopping', 'night_out', 'clubbing', 'long_drive'
  )),
  city TEXT NOT NULL,
  target_gender TEXT NOT NULL CHECK (target_gender IN ('male', 'female', 'all')),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open', 'accepted', 'completed', 'cancelled'
  )),
  accepter_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  otp_hash TEXT,
  otp_encrypted TEXT,
  initiator_coin_cost INTEGER NOT NULL DEFAULT 100,
  accepter_coin_reward INTEGER NOT NULL DEFAULT 50,
  idempotency_key TEXT UNIQUE,
  accepted_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Scale indexes for Buddy Requests
CREATE INDEX IF NOT EXISTS idx_buddy_requests_status_city_gender 
  ON public.buddy_requests(status, city, target_gender);

CREATE INDEX IF NOT EXISTS idx_buddy_requests_initiator_created 
  ON public.buddy_requests(initiator_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_buddy_requests_accepter_created 
  ON public.buddy_requests(accepter_id, created_at DESC);

-- 4. DROP AND RECREATE public.withdrawals
DROP TABLE IF EXISTS public.withdrawal_requests CASCADE;
DROP TABLE IF EXISTS public.withdrawals CASCADE;

CREATE TABLE public.withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount BIGINT NOT NULL CHECK (amount > 0),
  rupee_amount BIGINT NOT NULL CHECK (rupee_amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'paid')),
  idempotency_key TEXT UNIQUE,
  payout_method TEXT DEFAULT 'upi',
  payout_details JSONB,
  admin_note TEXT,
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- Enforce partial unique index: maximum 1 concurrent pending withdrawal per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_withdrawals_single_pending 
  ON public.withdrawals(user_id) WHERE status = 'pending';

-- Index for withdrawal lookups
CREATE INDEX IF NOT EXISTS idx_withdrawals_user_status 
  ON public.withdrawals(user_id, status);

CREATE INDEX IF NOT EXISTS idx_withdrawals_requested 
  ON public.withdrawals(requested_at DESC);

-- 5. UPDATE TRIGGER FOR NEW USER WALLET CREATION
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
  VALUES (NEW.id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_wallet ON public.users;
CREATE TRIGGER trigger_create_wallet
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_wallet_for_new_user();

-- Auto-provision dual wallets for all existing users
INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
SELECT id, 0, 0 FROM public.users
ON CONFLICT (user_id) DO NOTHING;

-- 6. UNIQUE CONSTRAINT ON GOOGLE PLAY PURCHASE TOKENS (REPLAY INTEGRITY)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'google_play_purchases') THEN
    CREATE UNIQUE INDEX IF NOT EXISTS idx_google_play_purchase_token 
      ON public.google_play_purchases(purchase_token);
  END IF;
END $$;
