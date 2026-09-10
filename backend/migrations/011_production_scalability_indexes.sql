-- Migration 011: Production Scalability & High-Concurrency Indexes
-- Reversible: See 011_production_scalability_indexes_down.sql for rollback
-- Note: Uses CREATE INDEX CONCURRENTLY to avoid acquiring SHARE locks on tables during creation.
-- Must be executed outside a transaction block (run_migration_011.js runs statements individually).

-- 1. CONVERSATIONS TABLE
-- Eliminates sequential scan when querying user_b_id (second column of UNIQUE compound)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b 
  ON public.conversations(user_b_id);

-- Enables direct index scan for user conversation lists sorted by recent activity
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_a_last_msg 
  ON public.conversations(user_a_id, last_message_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conversations_user_b_last_msg 
  ON public.conversations(user_b_id, last_message_at DESC);


-- 2. CALLS TABLE
-- Composite indexes for call history queries: WHERE (caller_id = $1 OR matched_user_id = $1) ORDER BY started_at DESC
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_caller_started 
  ON public.calls(caller_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_matched_started 
  ON public.calls(matched_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_status 
  ON public.calls(status);

-- Optimizes partner call pair lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_pair_started 
  ON public.calls(caller_id, matched_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_calls_pair_rev_started 
  ON public.calls(matched_user_id, caller_id, started_at DESC);


-- 3. INSTANT CALL SESSIONS TABLE
-- Optimizes male/female call history and status queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_male_started 
  ON public.instant_call_sessions(male_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_female_started 
  ON public.instant_call_sessions(female_user_id, started_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_status 
  ON public.instant_call_sessions(status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_instant_pair_started 
  ON public.instant_call_sessions(male_user_id, female_user_id, started_at DESC);


-- 4. WALLET TRANSACTIONS TABLE
-- Turns in-memory sort into an index scan for paginated wallet history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_wallet_tx_user_created 
  ON public.wallet_transactions(user_id, created_at DESC);


-- 5. ROSE TRANSACTIONS TABLE
-- Turns in-memory sort into an index scan for paginated earnings history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_rose_tx_user_created 
  ON public.rose_transactions(user_id, created_at DESC);


-- 6. SCRATCH CARDS TABLE
-- Optimizes pending reward counts and earnings history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scratch_cards_female_scratched 
  ON public.scratch_cards(female_user_id, is_scratched);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scratch_cards_female_created 
  ON public.scratch_cards(female_user_id, created_at DESC);


-- 7. FAVORITES TABLE
-- Optimizes reverse join when checking who favorited a user or loading reverse favorites
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_favorites_favorite_user 
  ON public.favorites(favorite_user_id);


-- 8. MESSAGES TABLE
-- Speeds up unread count calculation and bulk "mark as read" queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_unread_status 
  ON public.messages(conversation_id, sender_id, status);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_messages_sender 
  ON public.messages(sender_id);


-- 9. OTP VERIFICATIONS TABLE
-- Eliminates full table scan during periodic background OTP cleanup
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_otp_expires_at 
  ON public.otp_verifications(expires_at);


-- 10. USERS TABLE
-- Speeds up moderation checks, gender-filtered matchmaking, and pool lookups
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_is_banned 
  ON public.users(is_banned);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_gender 
  ON public.users(gender);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_incoming_paid 
  ON public.users(incoming_paid_calls_enabled) 
  WHERE incoming_paid_calls_enabled = true;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_created_at 
  ON public.users(created_at DESC);
