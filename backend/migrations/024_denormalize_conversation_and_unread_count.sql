-- Migration 024: Denormalize conversation last message and add unread_count to message_reads
-- Eliminates LEFT JOIN LATERAL and correlated subqueries on chat inbox query

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS last_message_content TEXT,
  ADD COLUMN IF NOT EXISTS last_message_sender_id UUID,
  ADD COLUMN IF NOT EXISTS last_message_type TEXT;

ALTER TABLE public.message_reads
  ADD COLUMN IF NOT EXISTS unread_count INTEGER DEFAULT 0;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a_last_msg
  ON public.conversations (user_a_id, last_message_at DESC NULLS LAST);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b_last_msg
  ON public.conversations (user_b_id, last_message_at DESC NULLS LAST);

-- Stage 3f: Composite index for open buddy feed ordered by created_at DESC
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_buddy_requests_open_city_created
  ON public.buddy_requests (city, created_at DESC)
  WHERE status = 'open';

