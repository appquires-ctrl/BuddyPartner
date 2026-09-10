-- Rollback Migration 011: Drop Production Scalability Indexes

DROP INDEX IF EXISTS public.idx_conversations_user_b;
DROP INDEX IF EXISTS public.idx_conversations_user_a_last_msg;
DROP INDEX IF EXISTS public.idx_conversations_user_b_last_msg;

DROP INDEX IF EXISTS public.idx_calls_caller_started;
DROP INDEX IF EXISTS public.idx_calls_matched_started;
DROP INDEX IF EXISTS public.idx_calls_status;
DROP INDEX IF EXISTS public.idx_calls_pair_started;
DROP INDEX IF EXISTS public.idx_calls_pair_rev_started;

DROP INDEX IF EXISTS public.idx_instant_male_started;
DROP INDEX IF EXISTS public.idx_instant_female_started;
DROP INDEX IF EXISTS public.idx_instant_status;
DROP INDEX IF EXISTS public.idx_instant_pair_started;

DROP INDEX IF EXISTS public.idx_wallet_tx_user_created;
DROP INDEX IF EXISTS public.idx_rose_tx_user_created;

DROP INDEX IF EXISTS public.idx_scratch_cards_female_scratched;
DROP INDEX IF EXISTS public.idx_scratch_cards_female_created;

DROP INDEX IF EXISTS public.idx_favorites_favorite_user;

DROP INDEX IF EXISTS public.idx_messages_unread_status;
DROP INDEX IF EXISTS public.idx_messages_sender;

DROP INDEX IF EXISTS public.idx_otp_expires_at;

DROP INDEX IF EXISTS public.idx_users_is_banned;
DROP INDEX IF EXISTS public.idx_users_gender;
DROP INDEX IF EXISTS public.idx_users_incoming_paid;
DROP INDEX IF EXISTS public.idx_users_created_at;
