-- 005_create_instant_connect_tables.sql

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS incoming_paid_calls_enabled BOOLEAN DEFAULT FALSE;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

CREATE TABLE IF NOT EXISTS public.instant_call_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  male_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  bid_amount INTEGER NOT NULL CHECK (bid_amount >= 10),
  status TEXT CHECK (status IN ('queued', 'ringing', 'in_call', 'completed', 'dropped', 'cancelled')) NOT NULL DEFAULT 'queued',
  agora_channel_name TEXT,
  started_at TIMESTAMPTZ,
  milestone_10m_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  duration_seconds INTEGER DEFAULT 0,
  scratch_card_unlocked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_instant_sess_male ON public.instant_call_sessions(male_user_id);
CREATE INDEX IF NOT EXISTS idx_instant_sess_female ON public.instant_call_sessions(female_user_id);

CREATE TABLE IF NOT EXISTS public.scratch_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID REFERENCES public.instant_call_sessions(id) ON DELETE SET NULL,
  female_user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  coin_reward INTEGER NOT NULL CHECK (coin_reward >= 1),
  is_scratched BOOLEAN DEFAULT FALSE,
  scratched_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_scratch_cards_female ON public.scratch_cards(female_user_id);
