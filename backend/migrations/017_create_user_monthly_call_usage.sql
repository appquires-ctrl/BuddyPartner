-- 017_create_user_monthly_call_usage.sql
-- Tracks monthly aggregated audio and video call minutes per user for cost management.

CREATE TABLE IF NOT EXISTS public.user_monthly_call_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  year_month VARCHAR(7) NOT NULL, -- e.g. '2026-09'
  audio_seconds INTEGER DEFAULT 0 NOT NULL,
  video_seconds INTEGER DEFAULT 0 NOT NULL,
  audio_call_count INTEGER DEFAULT 0 NOT NULL,
  video_call_count INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_user_year_month UNIQUE (user_id, year_month)
);

CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_ym ON public.user_monthly_call_usage(year_month);
CREATE INDEX IF NOT EXISTS idx_user_monthly_call_usage_user ON public.user_monthly_call_usage(user_id);
