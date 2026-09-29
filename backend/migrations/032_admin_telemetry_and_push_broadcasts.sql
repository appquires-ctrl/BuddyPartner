-- Migration 032: Admin Telemetry, Push Broadcasts, and Device Blacklisting
-- Supports 5,000 CCU infrastructure and targeted marketing/safety operations

-- 1. Push Broadcast Logs Table
CREATE TABLE IF NOT EXISTS public.push_broadcast_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    image_url TEXT,
    target_segment TEXT NOT NULL DEFAULT 'all',
    target_city TEXT,
    target_gender TEXT,
    deep_link TEXT DEFAULT '/home',
    recipient_count INT DEFAULT 0,
    success_count INT DEFAULT 0,
    failure_count INT DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'sent',
    created_by TEXT DEFAULT 'admin',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_broadcast_created ON public.push_broadcast_logs(created_at DESC);

-- 2. Hardware / Device Blacklisting Table
CREATE TABLE IF NOT EXISTS public.banned_devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id TEXT NOT NULL UNIQUE,
    reason TEXT,
    banned_by TEXT DEFAULT 'admin',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_banned_devices_lookup ON public.banned_devices(device_id);

-- 3. Add device_id and last_active_at columns and indexes on users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS device_id TEXT;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_users_device_id ON public.users(device_id) WHERE device_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_fcm_token_active ON public.users(fcm_token) WHERE fcm_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_last_active_at ON public.users(last_active_at DESC) WHERE last_active_at IS NOT NULL;
