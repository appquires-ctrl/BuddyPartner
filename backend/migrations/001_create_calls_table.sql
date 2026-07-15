-- LoopCall: Calls table migration
-- Run in Supabase SQL Editor or as a migration file

CREATE TABLE IF NOT EXISTS public.calls (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  caller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  matched_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT CHECK (status IN ('active', 'ended')) NOT NULL DEFAULT 'active',
  call_type TEXT CHECK (call_type IN ('voice', 'video')) NOT NULL DEFAULT 'voice',
  duration_seconds INTEGER,
  started_at TIMESTAMPTZ DEFAULT NOW(),
  ended_at TIMESTAMPTZ
);

ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;

-- Users can only read their own calls (as caller or matched user)
CREATE POLICY "Users can view own calls"
  ON public.calls FOR SELECT
  USING (auth.uid() = caller_id OR auth.uid() = matched_user_id);

-- No client-side INSERT/UPDATE/DELETE — calls are only written by the Node backend's service-role client.
