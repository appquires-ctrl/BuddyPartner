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

// ── Express setup ───────────────────────────────────────────────────────────
const app = express();
app.use(helmet());
app.use(cors());
app.use(express.json());

// Import and mount custom modules REST endpoints
const authRoutes = require('./modules/auth/auth.routes');
const callsRoutes = require('./modules/calls/calls.routes');
const messagingRoutes = require('./modules/messaging/messaging.routes');
const roseRoutes = require('./modules/wallet/rose.routes');
const withdrawalRoutes = require('./modules/withdrawals/withdrawals.routes');
const adminRoutes = require('./modules/admin/admin.routes');
const adminService = require('./modules/admin/admin.service');
const subscriptionsRoutes = require('./modules/subscriptions/subscriptions.routes');

app.use('/api/auth', authRoutes);
app.use('/api/users', authRoutes);
app.use('/api/calls', callsRoutes);
app.use('/api', messagingRoutes);
app.use('/api', roseRoutes);
app.use('/api', withdrawalRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/subscriptions', subscriptionsRoutes);

// Initialize Admin Config
adminService.initAdminConfig();

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

// ── Auto-ensure wallet_transactions table exists ────────────────────────────
db.query(`
  CREATE TABLE IF NOT EXISTS public.wallet_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    amount INTEGER NOT NULL,
    type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
    reason TEXT NOT NULL,
    reference_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE INDEX IF NOT EXISTS idx_wallet_tx_user ON public.wallet_transactions(user_id);
`).then(() => {
  console.log('✅ wallet_transactions table checked/initialized.');
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
`).then(() => {
  console.log('✅ User moderation, telecaller, and location columns checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize user columns:', err.message);
});


// Auto-ensure rose/withdrawal tables exist
db.query(`
  CREATE TABLE IF NOT EXISTS public.rose_balances (
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE PRIMARY KEY,
    balance INTEGER DEFAULT 0 CHECK (balance >= 0),
    updated_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS public.rose_transactions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    type TEXT CHECK (type IN ('credit', 'debit')) NOT NULL,
    amount INTEGER NOT NULL,
    reason TEXT NOT NULL,
    reference_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
  );
  CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
    rose_amount INTEGER NOT NULL,
    rupee_amount INTEGER NOT NULL,
    status TEXT CHECK (status IN ('pending', 'approved', 'rejected', 'paid')) NOT NULL DEFAULT 'pending',
    requested_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
  );
  CREATE INDEX IF NOT EXISTS idx_rose_tx_user ON public.rose_transactions(user_id);
  CREATE INDEX IF NOT EXISTS idx_withdrawal_user ON public.withdrawal_requests(user_id);
`).then(() => {
  console.log('✅ Rose/withdrawal tables checked/initialized.');
}).catch((err) => {
  console.error('❌ Failed to initialize rose/withdrawal tables:', err.message);
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
  pingTimeout: 30000,
  pingInterval: 10000,
});

const { ModerationService } = require('./modules/moderation/moderation.service');
const { PresenceService } = require('./modules/presence/presence.service');

// Socket.io authentication middleware — validates custom JWT session and moderation status
io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token;
  if (!token) {
    return next(new Error('Authentication error: no token provided'));
  }

  try {
    const secret = process.env.JWT_SECRET || 'loopcall_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);

    const modStatus = await ModerationService.isUserBlocked(decoded.id);
    if (modStatus.isBanned) {
      return next(new Error('ACCOUNT_BANNED'));
    }

    socket.userId = decoded.id;
    socket.userPhone = decoded.phone;
    next();
  } catch (err) {
    console.error('Socket auth failed:', err.message);
    next(new Error('Authentication error: invalid token'));
  }
});

// ── Register socket handlers ────────────────────────────────────────────────
const { registerMatchmakingHandlers } = require('./modules/matchmaking/matchmaking.socket');
const { registerMessagingHandlers } = require('./modules/messaging/messaging.socket');

io.on('connection', (socket) => {
  console.log(`🔌 User connected: ${socket.userId} (socket: ${socket.id})`);
  
  // Set user online in Redis and broadcast presence
  PresenceService.setPresence(redis, io, socket.userId, true);

  registerMatchmakingHandlers(io, socket, redis);
  registerMessagingHandlers(io, socket, redis);

  socket.on('disconnect', (reason) => {
    console.log(`🔌 User disconnected: ${socket.userId} — ${reason}`);
    // Set user offline in Redis and broadcast presence
    PresenceService.setPresence(redis, io, socket.userId, false);
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
server.listen(PORT, () => {
  console.log(`🚀 LoopCall server listening on port ${PORT}`);
});

module.exports = { app, server, io, redis, db };
