-- LoopCall Database Schema Setup for Neon PostgreSQL

-- 1. Users Table
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_number VARCHAR(20) UNIQUE NOT NULL,
  full_name VARCHAR(100),
  dob DATE,
  gender VARCHAR(20),
  language VARCHAR(50),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Wallets Table
CREATE TABLE IF NOT EXISTS public.wallets (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  balance INTEGER DEFAULT 100 NOT NULL
);

-- 3. Calls Table
CREATE TABLE IF NOT EXISTS public.calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  matched_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('active', 'ended')) NOT NULL DEFAULT 'active',
  call_type TEXT CHECK (call_type IN ('voice', 'video')) NOT NULL DEFAULT 'voice',
  duration_seconds INTEGER,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

-- 4. OTP Verifications Table
CREATE TABLE IF NOT EXISTS public.otp_verifications (
  id SERIAL PRIMARY KEY,
  phone_number VARCHAR(20) NOT NULL,
  otp_code VARCHAR(100) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── INDEXES FOR PERFORMANCE ──────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_otp_phone ON public.otp_verifications(phone_number);
CREATE INDEX IF NOT EXISTS idx_calls_caller ON public.calls(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_matched ON public.calls(matched_user_id);

-- ── TRIGGER FOR AUTO-CREATING WALLETS ON USER INSERT ───────────────────────
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 100)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_create_wallet ON public.users;
CREATE TRIGGER trigger_create_wallet
AFTER INSERT ON public.users
FOR EACH ROW
EXECUTE FUNCTION public.create_wallet_for_new_user();

-- ── CLEANUP CRON NOTE FOR EXPIRED OTPs ───────────────────────────────────────
-- To automate OTP cleanup at the database level, run this query in pg_cron (if enabled):
-- SELECT cron.schedule('cleanup-expired-otps', '0 * * * *', 'DELETE FROM public.otp_verifications WHERE expires_at < NOW()');
--
-- Alternatively, our Node.js backend handles this using a background interval query.
