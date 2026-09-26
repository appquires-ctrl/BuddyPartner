-- Migration: 031_create_promo_codes_table.sql
-- Description: Create promo_codes and promo_code_redemptions tables for dynamic admin and in-app coupon management.

CREATE TABLE IF NOT EXISTS promo_codes (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) NOT NULL UNIQUE,
    title VARCHAR(100) NOT NULL,
    description TEXT,
    reward_type VARCHAR(30) NOT NULL, -- 'GOOGLE_PLAY_OFFER', 'FREE_COINS', 'FREE_VIP'
    
    -- Target subscription configuration for Google Play offers
    target_product_id VARCHAR(100),   -- e.g. 'pass_1_month', 'membership_1_month'
    google_play_offer_id VARCHAR(100), -- e.g. '50-off'
    discount_amount NUMERIC(10, 2) DEFAULT 0, -- e.g. 50.00 (rupees discount)
    
    -- Reward grants for in-app redemption
    coins_reward INT DEFAULT 0,
    vip_days_reward INT DEFAULT 0,
    
    -- Usage caps and limits
    max_uses_total INT DEFAULT NULL,   -- NULL indicates unlimited uses
    max_uses_per_user INT DEFAULT 1,   -- Maximum redemptions per user
    times_redeemed INT DEFAULT 0,
    
    -- Time limits
    starts_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for fast lookup and active date filtering
CREATE INDEX IF NOT EXISTS idx_promo_codes_code ON promo_codes (UPPER(code));
CREATE INDEX IF NOT EXISTS idx_promo_codes_active_window ON promo_codes (is_active, starts_at, expires_at);

-- Redemption log table
CREATE TABLE IF NOT EXISTS promo_code_redemptions (
    id SERIAL PRIMARY KEY,
    promo_code_id INT NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    order_id VARCHAR(150),
    reward_type VARCHAR(30) NOT NULL,
    discount_amount NUMERIC(10, 2) DEFAULT 0,
    coins_reward INT DEFAULT 0,
    vip_days_reward INT DEFAULT 0,
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for per-user redemption validation
CREATE INDEX IF NOT EXISTS idx_promo_code_redemptions_user ON promo_code_redemptions (promo_code_id, user_id);
CREATE INDEX IF NOT EXISTS idx_promo_code_redemptions_user_id ON promo_code_redemptions (user_id);
