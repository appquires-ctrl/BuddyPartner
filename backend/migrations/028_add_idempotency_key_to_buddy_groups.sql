-- Migration 028: Add idempotency_key to public.buddy_groups
-- Standardizes idempotency handling and prevents false deduplication on repeated group names

ALTER TABLE public.buddy_groups
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_buddy_groups_idempotency_key
  ON public.buddy_groups (idempotency_key);
