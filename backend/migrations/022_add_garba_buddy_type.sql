-- Migration 022: Add 'garba' to buddy_type CHECK constraint

DO $$
DECLARE
  con_name TEXT;
BEGIN
  -- Find the check constraint name on buddy_type in public.buddy_requests
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
    'shopping', 'night_out', 'clubbing', 'long_drive', 'garba'
  ));
