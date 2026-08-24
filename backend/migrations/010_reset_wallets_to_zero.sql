-- Migration 010: Reset initial wallet balance to 0 and set all existing account balances to 0

-- 1. Alter the default value for wallets balance column to 0
ALTER TABLE public.wallets ALTER COLUMN balance SET DEFAULT 0;

-- 2. Update trigger function for new user wallet creation to initialize balance with 0
CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance)
  VALUES (NEW.id, 0)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. Reset all existing account balances to 0
UPDATE public.wallets SET balance = 0;
