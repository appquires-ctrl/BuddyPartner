-- Migration 023: Add 'festival' to buddy_type CHECK constraint, and add custom_title & campaign_id to buddy_requests

-- 1. Update buddy_type CHECK constraint on public.buddy_requests
DO $$
DECLARE
  con_name TEXT;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'public.buddy_requests'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%buddy_type%';

  IF con_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.buddy_requests DROP CONSTRAINT %I', con_name);
  END IF;
END $$;

ALTER TABLE public.buddy_requests
  ADD CONSTRAINT buddy_requests_buddy_type_check
  CHECK (buddy_type IN (
    'movie', 'pizza', 'coffee', 'hangout', 'trip', 'cricket',
    'shopping', 'night_out', 'clubbing', 'long_drive', 'garba', 'festival'
  ));

-- 2. Add custom_title and campaign_id columns to public.buddy_requests
ALTER TABLE public.buddy_requests
  ADD COLUMN IF NOT EXISTS custom_title TEXT,
  ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES public.seasonal_banners(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_buddy_requests_campaign_id
  ON public.buddy_requests(campaign_id);
