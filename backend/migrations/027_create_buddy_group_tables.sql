-- Migration 027: Create Buddy Group Tables (Garba Buddy Group Feature)
-- Supports multi-user group broadcast (up to 6 members: 1 host + 5 joiners)
-- Host pays 509 coins, joiners pay 0 coins, zero OTP required.

-- 1. Buddy Group Broadcast Table
CREATE TABLE IF NOT EXISTS public.buddy_groups (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  initiator_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL DEFAULT 'Garba Buddy Group',
  buddy_type TEXT NOT NULL DEFAULT 'garba',
  city TEXT NOT NULL,
  target_gender TEXT NOT NULL DEFAULT 'all' CHECK (target_gender IN ('male', 'female', 'all')),
  host_coin_cost INT NOT NULL DEFAULT 509,
  max_members INT NOT NULL DEFAULT 6,
  member_count INT NOT NULL DEFAULT 1,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'full', 'archived', 'cancelled')),
  last_message_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_buddy_groups_city_status 
  ON public.buddy_groups (LOWER(TRIM(city)), status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_buddy_groups_initiator 
  ON public.buddy_groups (initiator_id);

-- 2. Buddy Group Members Table
CREATE TABLE IF NOT EXISTS public.buddy_group_members (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.buddy_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'member' CHECK (role IN ('host', 'member')),
  joined_at TIMESTAMPTZ DEFAULT NOW(),
  last_read_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_buddy_group_members_user 
  ON public.buddy_group_members (user_id, joined_at DESC);
CREATE INDEX IF NOT EXISTS idx_buddy_group_members_group 
  ON public.buddy_group_members (group_id);

-- 3. Buddy Group Messages Table
CREATE TABLE IF NOT EXISTS public.buddy_group_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id UUID NOT NULL REFERENCES public.buddy_groups(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'text' CHECK (type IN ('text', 'system', 'image')),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_buddy_group_messages_group_created 
  ON public.buddy_group_messages (group_id, created_at DESC);
