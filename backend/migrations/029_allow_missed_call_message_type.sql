-- Migration 029: Allow 'missed_call' in messages type check constraint
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_type_check CHECK (type IN ('text', 'image', 'system', 'missed_call'));
