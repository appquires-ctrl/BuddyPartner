-- Migration 030: Allow 'missed', 'declined', 'cancelled' in calls status check constraint
ALTER TABLE public.calls DROP CONSTRAINT IF EXISTS calls_status_check;
ALTER TABLE public.calls ADD CONSTRAINT calls_status_check CHECK (status IN ('active', 'ended', 'missed', 'declined', 'cancelled'));
