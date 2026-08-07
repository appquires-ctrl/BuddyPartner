-- Migration 009: Add country_code and mobile columns to public.users for Authkey WhatsApp OTP

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS country_code VARCHAR(10);
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS mobile VARCHAR(20);

-- Create a unique constraint on (country_code, mobile)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'unique_country_mobile'
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT unique_country_mobile UNIQUE (country_code, mobile);
    END IF;
END $$;

-- Performance index for fast user lookup by country_code + mobile
CREATE INDEX IF NOT EXISTS idx_users_country_mobile ON public.users(country_code, mobile);
