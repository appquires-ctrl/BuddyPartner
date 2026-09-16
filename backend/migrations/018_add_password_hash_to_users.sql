-- Migration 018: Add password_hash column to public.users
--
-- Description:
-- Adds password_hash VARCHAR(255) to support username/phone + password authentication.
-- Existing users will have NULL, allowing them to log in via WhatsApp OTP and migrate to a password.

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
