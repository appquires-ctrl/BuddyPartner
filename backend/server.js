require('dotenv').config();

const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const cors = require('cors');
const helmet = require('helmet');
const Redis = require('ioredis');
const jwt = require('jsonwebtoken');
const db = require('./db');

// ── Validate required env vars ──────────────────────────────────────────────
const REQUIRED_ENV = [
  'DATABASE_URL',
  'JWT_SECRET',
  'REDIS_URL',
  'AGORA_APP_ID',
  'AGORA_APP_CERTIFICATE',
];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`Missing required environment variable: ${key}`);
    process.exit(1);
  }
}

if (!process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON && !process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE) {
  console.warn('⚠️ [Google Play Billing] Neither GOOGLE_PLAY_SERVICE_ACCOUNT_JSON nor GOOGLE_PLAY_SERVICE_ACCOUNT_FILE is configured in environment.');
}

if (!process.env.GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT || !process.env.GOOGLE_PLAY_RTDN_AUDIENCE) {
  console.warn('⚠️ [Google Play RTDN] GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT and/or GOOGLE_PLAY_RTDN_AUDIENCE not configured. RTDN webhook will reject all requests until configured.');
}

// ── Express setup ───────────────────────────────────────────────────────────
const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json());

// Import and mount custom modules REST endpoints
const authRoutes = require('./modules/auth/auth.routes');
const callsRoutes = require('./modules/calls/calls.routes');
const messagingRoutes = require('./modules/messaging/messaging.routes');
const walletRoutes = require('./modules/wallet/wallet.routes');
const withdrawalRoutes = require('./modules/withdrawals/withdrawals.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const adminService = require('./modules/admin/admin.service');
const subscriptionsRoutes = require('./modules/subscriptions/subscriptions.routes');
const appRoutes = require('./modules/app/app.routes');
const { appService } = require('./modules/app/app.service');
const { enforceMinimumVersion } = require('./middleware/version.middleware');

const path = require('path');
const advertisementsRoutes = require('./modules/advertisements/advertisements.routes');
const instantConnectRoutes = require('./modules/instant_connect/instant_connect.routes');
const supportRoutes = require('./modules/support/support.routes');
const googlePlayRoutes = require('./modules/payments/google_play.routes');
const { GooglePlayService } = require('./modules/payments/google_play.service');

// Serve uploaded images statically
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Public version routes mounted before middleware enforcement
app.use('/api/app', appRoutes);

// Apply HTTP 426 version enforcement middleware globally to all /api/* routes
app.use('/api', enforceMinimumVersion);

app.use('/api/auth', authRoutes);
app.use('/api/users', authRoutes);
app.use('/api/calls', callsRoutes);
app.use('/api', messagingRoutes);
app.use('/api', walletRoutes);
app.use('/api', withdrawalRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/subscriptions', subscriptionsRoutes);
app.use('/api/instant', instantConnectRoutes);
app.use('/api/advertisements', advertisementsRoutes);
app.use('/api/admin/advertisements', advertisementsRoutes);
app.use('/api/support', supportRoutes);
app.use('/api/app', supportRoutes);
app.use('/api/payments/google-play', googlePlayRoutes);

// Initialize Admin, App Config & Google Play tables
adminService.initAdminConfig();
appService.initAppConfig();
GooglePlayService.initTable();

// ── Auto-ensure subscriptions table exists ─────────────────────────────────
db.query(`
  CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    plan_duration_days INTEGER NOT NULL,
    amount_paid INTEGER NOT NULL,
    started_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    payment_reference TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_subscriptions_user_expires ON public.subscriptions(user_id, expires_at);
`).then(() => {
  console.log('✅ Subscriptions table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize subscriptions table:', err.message);
});

// ── Auto-ensure wallet_transactions and wallet defaults ────────────────────
db.query(`
  ALTER TABLE public.wallets ALTER COLUMN balance SET DEFAULT 0;
  CREATE OR REPLACE FUNCTION public.create_wallet_for_new_user()
  RETURNS TRIGGER AS $$
  BEGIN
    INSERT INTO public.wallets (user_id, balance)
    VALUES (NEW.id, 0)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
  END;
  $$ LANGUAGE plpgsql;

  CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    amount INTEGER NOT NULL,
    type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
    reason TEXT NOT NULL,
    reference_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  ALTER TABLE public.wallet_transactions ALTER COLUMN reference_id TYPE TEXT;
  CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id);
`).then(() => {
  console.log('✅ Wallets default (0) and wallet_transactions table checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize wallet_transactions table:', err.message);
});

// Auto-ensure user moderation and location columns exist
db.query(`
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS strike_count INTEGER DEFAULT 0;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS suspended_until TIMESTAMPTZ;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_banned BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_telecaller BOOLEAN;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS country VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS state VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS city VARCHAR(100);
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS has_claimed_intro_offer BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS incoming_paid_calls_enabled BOOLEAN DEFAULT FALSE;
  ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;
`).then(() => {
  console.log('✅ User moderation, telecaller, location, intro offer, and instant connect columns checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize user columns:', err.message);
});

// Auto-ensure instant connect sessions and scratch cards tables exist
db.query(`
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
`).then(() => {
  console.log('✅ Instant connect sessions and scratch cards tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize instant connect tables:', err.message);
});


// Auto-ensure withdrawal tables exist
db.query(`
  CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    rose_amount INTEGER NOT NULL,
    rupee_amount INTEGER NOT NULL,
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
  );
  CREATE INDEX IF NOT EXISTS idx_withdrawal_user ON public.withdrawal_requests(user_id);
`).then(() => {
  console.log('✅ Withdrawal tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize withdrawal tables:', err.message);
});

// Auto-ensure bug reports and account deletion survey tables exist
db.query(`
  CREATE TABLE IF NOT EXISTS public.bug_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    category TEXT NOT NULL,
    description TEXT NOT NULL,
    app_version TEXT,
    platform TEXT,
    device_info TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_bug_reports_user ON public.bug_reports(user_id);
  CREATE INDEX IF NOT EXISTS idx_bug_reports_date ON public.bug_reports(created_at DESC);

  CREATE TABLE IF NOT EXISTS public.account_deletion_surveys (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT,
    phone_number TEXT,
    reason TEXT NOT NULL,
    feedback TEXT,
    deleted_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_deletion_surveys_date ON public.account_deletion_surveys(deleted_at DESC);
`).then(() => {
  console.log('✅ Bug reports and account deletion survey tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize support/deletion tables:', err.message);
});


const server = http.createServer(app);

// ── Redis client ────────────────────────────────────────────────────────────
const redis = require('./redis');

// ── Socket.io setup ─────────────────────────────────────────────────────────
const io = new Server(server, {
  cors: {
    origin: '*', // Tighten in production
    methods: ['GET', 'POST'],
  },
  pingTimeout: 5000,
  pingInterval: 5000,
});
app.set('io', io);

const { ModerationService } = require('./modules/moderation/moderation.service');
const { PresenceService } = require('./modules/presence/presence.service');

// Socket.io authentication middleware — validates custom JWT session and moderation status
io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token;
  if (!token) {
    return next(new Error('Authentication error: no token provided'));
  }

  try {
    const secret = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);

    const modStatus = await ModerationService.isUserBlocked(decoded.id);
    if (modStatus.isBanned) {
      return next(new Error('ACCOUNT_BANNED'));
    }

    // Perform version check during socket handshake if appVersion header/payload provided
    const appVersion = socket.handshake.auth?.appVersion || socket.handshake.headers?.['x-app-version'];
    const platform = socket.handshake.auth?.platform || socket.handshake.headers?.['x-app-platform'] || 'android';

    if (appVersion) {
      const verResult = await appService.checkVersion(platform, appVersion);
      if (verResult.updateRequired) {
        return next(new Error('ACCOUNT_UPGRADE_REQUIRED'));
      }
    }

    // Enforce single-device active session for socket connections
    const activeSession = await redis.get(`user_active_session:${decoded.id}`);
    if (activeSession && (!decoded.sessionId || activeSession !== decoded.sessionId)) {
      return next(new Error('SESSION_TERMINATED'));
    }

    socket.userId = decoded.id;
    socket.userPhone = decoded.phone;
    socket.sessionId = decoded.sessionId;
    next();
  } catch (err) {
    console.error('Socket auth failed:', err.message);
    next(new Error('Authentication error: invalid token'));
  }
});

// ── Register socket handlers ────────────────────────────────────────────────
const { registerMatchmakingHandlers } = require('./modules/matchmaking/matchmaking.socket');
const { registerMessagingHandlers } = require('./modules/messaging/messaging.socket');
const { registerInstantConnectHandlers } = require('./modules/instant_connect/instant_connect.socket');
const { registerPresenceHandlers } = require('./modules/presence/presence.socket');

io.on('connection', (socket) => {
  console.log(`🔌 User connected: ${socket.userId} (socket: ${socket.id})`);
  
  // Join the user's personal room for direct targeting and room broadcasts
  socket.join(socket.userId);

  // Add socket to user's active socket set in Redis and broadcast presence if newly online
  PresenceService.addSocket(redis, io, socket.userId, socket.id);

  registerMatchmakingHandlers(io, socket, redis);
  registerMessagingHandlers(io, socket, redis);
  registerInstantConnectHandlers(io, socket, redis);
  registerPresenceHandlers(io, socket, redis);

  socket.on('disconnect', (reason) => {
    console.log(`🔌 User disconnected: ${socket.userId} — ${reason}`);
    // Remove socket from user's active socket set in Redis and broadcast presence if offline
    PresenceService.removeSocket(redis, io, socket.userId, socket.id);
    
    // Clean up in-memory socket mapping
    try {
      const { userSockets } = require('./modules/matchmaking/matchmaking.socket');
      if (userSockets.get(socket.userId) === socket.id) {
        userSockets.delete(socket.userId);
      }
    } catch (_) {}
  });
});

// ── Health check endpoint ───────────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

// ── Periodically clean up expired OTPs (every 1 hour) ────────────────────────
setInterval(async () => {
  try {
    const result = await db.query('DELETE FROM public.otp_verifications WHERE expires_at < NOW()');
    if (result.rowCount > 0) {
      console.log(`🧹 Cleaned up ${result.rowCount} expired OTP verification records.`);
    }
  } catch (err) {
    console.error('❌ Error cleaning up expired OTPs:', err.message);
  }
}, 60 * 60 * 1000);

// ── Start server ────────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3000;
server.listen(PORT, async () => {
  console.log(`🚀 BuddyPartner server listening on port ${PORT}`);
  try {
    const res = await db.query(`
      UPDATE public.instant_call_sessions
      SET status = 'dropped', ended_at = NOW()
      WHERE status IN ('queued', 'ringing', 'in_call')
    `);
    if (res.rowCount > 0) {
      console.log(`🧹 Reconciled ${res.rowCount} stale instant call sessions on startup.`);
    }
  } catch (err) {
    console.error('Error reconciling instant call sessions on startup:', err.message);
  }
});

module.exports = { app, server, io, redis, db };
