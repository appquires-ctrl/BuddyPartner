-- Migration 033: Add state column to buddy_requests for city disambiguation
-- Allows precise matchmaking between cities with duplicate names across states
-- (e.g. "Aurangabad, Maharashtra" vs "Aurangabad, Bihar")

ALTER TABLE public.buddy_requests
  ADD COLUMN IF NOT EXISTS state TEXT;

-- Add state column to buddy_groups table too for consistency
ALTER TABLE public.buddy_groups
  ADD COLUMN IF NOT EXISTS state TEXT;

-- Index for state-scoped buddy feed queries
CREATE INDEX IF NOT EXISTS idx_buddy_requests_state
  ON public.buddy_requests (state)
  WHERE status = 'open';

COMMENT ON COLUMN public.buddy_requests.state IS 'State/province of the broadcast city — used for disambiguation (e.g. Maharashtra for Mumbai)';
COMMENT ON COLUMN public.buddy_groups.state IS 'State/province of the group host city';
