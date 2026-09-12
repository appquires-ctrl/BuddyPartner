-- Migration 013: Backfill has_claimed_intro_offer flag for existing users
--
-- Description:
-- Marks users who have previously purchased an introductory subscription (₹9 / 1-day)
-- with has_claimed_intro_offer = TRUE so they cannot purchase it again.
--
-- Tech Debt Note (Heuristic Proxy):
-- This backfill identifies intro offer claims using (s.plan_duration_days = 1 OR s.amount_paid = 9).
-- This is a heuristic proxy tied to current pricing (₹9 / 1-day intro offer).
-- If pricing plans change or a different 1-day promo is introduced, this proxy may misclassify.
-- Future work: Introduce an explicit `is_intro_offer BOOLEAN` column on `subscriptions` set at purchase time.
--
-- Execution:
-- Run once manually via psql or the Neon / PostgreSQL database console:
--   psql $DATABASE_URL -f backend/migrations/013_backfill_intro_offer_flag.sql

ALTER TABLE public.users 
ADD COLUMN IF NOT EXISTS has_claimed_intro_offer BOOLEAN DEFAULT FALSE;

UPDATE public.users u 
SET has_claimed_intro_offer = TRUE 
WHERE has_claimed_intro_offer IS NOT TRUE 
  AND EXISTS (
    SELECT 1 FROM public.subscriptions s 
    WHERE s.user_id = u.id AND (s.plan_duration_days = 1 OR s.amount_paid = 9)
  );
