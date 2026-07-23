-- Migration 004: Rose balances, transactions, and withdrawal requests
-- Supports the gender-differentiated billing model:
--   Boys spend coins (existing wallets), Girls earn roses (new tables)

-- 1. Rose Balances — per-girl balance tracker
CREATE TABLE IF NOT EXISTS public.rose_balances (
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
  balance INTEGER DEFAULT 0 CHECK (balance >= 0),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Rose Transactions — credit/debit ledger
CREATE TABLE IF NOT EXISTS public.rose_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
  amount INTEGER NOT NULL,
  reason TEXT NOT NULL,          -- 'call_minute_voice' | 'call_minute_video' | 'withdrawal_request'
  reference_id UUID,             -- callId or withdrawal request id
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Withdrawal Requests — stub only, no real payout processing
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rose_amount INTEGER NOT NULL,
  rupee_amount INTEGER NOT NULL,  -- 1:1 conversion, stored explicitly
  status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

-- ── INDEXES ──────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_rose_tx_user ON public.rose_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_rose_tx_reference ON public.rose_transactions(reference_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_user ON public.withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_status ON public.withdrawal_requests(status);

-- ── TRIGGER: Auto-create rose_balances row for new female users ─────────────
CREATE OR REPLACE FUNCTION public.create_rose_balance_for_female_user()
RETURNS TRIGGER AS $$
BEGIN
  IF LOWER(COALESCE(NEW.gender, '')) IN ('female', 'girl', 'woman') THEN
    INSERT INTO public.rose_balances (user_id, balance)
    VALUES (NEW.id, 0)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_rose_balance ON public.users;
CREATE TRIGGER trigger_create_rose_balance
AFTER INSERT OR UPDATE ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_rose_balance_for_female_user();
