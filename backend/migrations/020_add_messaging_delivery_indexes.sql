-- Migration 020: Add indexing for real-time message delivery updates
--
-- Description:
-- Adds non-blocking indexes to eliminate sequential scans when marking incoming
-- messages as 'delivered' on socket connection:
-- 1. Partial index on messages(conversation_id, status) for unread 'sent' messages.
-- 2. Direct single-column index on conversations(user_a_id) to optimize participant lookup.
-- 3. Direct single-column index on conversations(user_b_id) to optimize participant lookup.
--
-- Note: Uses CREATE INDEX CONCURRENTLY to prevent table write locks.
-- Must be run outside of a multi-statement transaction block.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_sent_status_partial 
  ON public.messages (conversation_id, status) 
  WHERE status = 'sent';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a 
  ON public.conversations (user_a_id);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b 
  ON public.conversations (user_b_id);
