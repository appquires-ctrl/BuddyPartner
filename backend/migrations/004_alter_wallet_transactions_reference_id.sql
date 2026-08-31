-- 004_alter_wallet_transactions_reference_id.sql
-- Alter reference_id from UUID to TEXT to support string-based payment references & dev recharge IDs

ALTER TABLE public.wallet_transactions 
  ALTER COLUMN reference_id TYPE TEXT;
