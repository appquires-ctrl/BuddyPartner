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
app.set('trust proxy', 1); // Trust Render / Railway reverse proxy for accurate client IP in rate limiting
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));

// Distributed Redis-backed Rate Limiters
const { apiGlobalLimiter, otpRateLimiter, callRateLimiter } = require('./middleware/rate_limit.middleware');
app.use('/api', apiGlobalLimiter);
app.use('/api/auth/otp', otpRateLimiter);
app.use('/api/calls', callRateLimiter);
app.use('/api/instant', callRateLimiter);

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
const buddyRoutes = require('./modules/buddy/buddy.routes');

// Serve uploaded images statically
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// ── Lightweight Health check endpoint (exempt from version enforcement & DB) ─
app.get(['/health', '/api/health'], (_req, res) => {
  res.json({ status: 'ok', uptime: process.uptime() });
});

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
app.use('/api/buddy', buddyRoutes);

// Festive / seasonal banner route fallback
app.get('/api/banners/seasonal', (_req, res) => {
  res.json({ success: true, banners: [] });
});

// Prime in-memory app config cache (schema managed via versioned migrations)
appService.refreshCache().catch((err) => {
  console.warn('⚠️ [AppConfig] Initial cache prime error:', err.message);
});

const server = http.createServer(app);

// ── Redis client ────────────────────────────────────────────────────────────
const redis = require('./redis');

// ── Socket.io setup ─────────────────────────────────────────────────────────
const { createAdapter } = require('@socket.io/redis-adapter');

const io = new Server(server, {
  transports: ['websocket'],
  cors: {
    origin: '*', // Tighten in production
    methods: ['GET', 'POST'],
  },
  pingTimeout: 20000,
  pingInterval: 15000,
});
app.set('io', io);

// Socket.IO Redis Adapter initialized in startServer() before server.listen()

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

    // Enforce single-device active session and fetch latest cached profile
    const [activeSession, cachedProfileStr] = await Promise.all([
      redis.get(`user_active_session:${decoded.id}`),
      redis.get(`user:profile:${decoded.id}`).catch(() => null),
    ]);

    let activeSessionId = activeSession;
    let isBanned = false;
    if (activeSession && activeSession.startsWith('{')) {
      try {
        const parsed = JSON.parse(activeSession);
        activeSessionId = parsed.sessionId;
        isBanned = Boolean(parsed.isBanned);
      } catch (_) {}
    }

    if (isBanned) {
      return next(new Error('ACCOUNT_BANNED'));
    }

    if (activeSessionId && (!decoded.sessionId || activeSessionId !== decoded.sessionId)) {
      return next(new Error('SESSION_TERMINATED'));
    }

    let profile = null;
    if (cachedProfileStr) {
      try {
        profile = JSON.parse(cachedProfileStr);
      } catch (_) {}
    }

    socket.userId = decoded.id;
    socket.userPhone = decoded.phone;
    socket.sessionId = decoded.sessionId;

    // Authoritative source: Redis profile is checked first; fallback to JWT claim on cache miss
    socket.city = profile?.city ?? decoded.city ?? null;
    socket.gender = profile?.gender ?? decoded.gender ?? null;
    socket.incomingPaidCallsEnabled = profile?.incoming_paid_calls_enabled ?? decoded.incoming_paid_calls_enabled ?? null;
    next();
  } catch (err) {
    console.error('Socket auth failed:', err.message);
    next(new Error('Authentication error: invalid token'));
  }
});

// ── Register socket handlers ────────────────────────────────────────────────
const { registerMatchmakingHandlers } = require('./modules/matchmaking/matchmaking.socket');
const { registerMessagingHandlers } = require('./modules/messaging/messaging.socket');
const { MessagingService } = require('./modules/messaging/messaging.service');
const messagingService = new MessagingService();
const { registerInstantConnectHandlers } = require('./modules/instant_connect/instant_connect.socket');
const { registerPresenceHandlers } = require('./modules/presence/presence.socket');
const { registerBuddyHandlers } = require('./modules/buddy/buddy.socket');

io.on('connection', (socket) => {
  console.log(`🔌 User connected: ${socket.userId} (socket: ${socket.id})`);
  
  // Join the user's personal room for direct targeting and room broadcasts
  socket.join(socket.userId);

  // Add socket to user's active socket set in Redis and broadcast presence if newly online
  PresenceService.addSocket(redis, io, socket.userId, socket.id);

  // Catch up unread 'sent' messages to 'delivered' now that recipient is connected
  messagingService.markDeliveredForRecipient(socket.userId, io);

  registerMatchmakingHandlers(io, socket, redis);
  registerMessagingHandlers(io, socket, redis);
  registerInstantConnectHandlers(io, socket, redis);
  registerPresenceHandlers(io, socket, redis);
  registerBuddyHandlers(io, socket, redis);

  // Auto-join user's city+gender buddy room without Postgres query (authoritative from Redis/JWT during handshake)
  if (socket.city && typeof socket.city === 'string' && socket.city.trim()) {
    const userGender = (socket.gender || 'male').trim().toLowerCase();
    const room = `buddy:city:${socket.city.trim().toLowerCase()}:${userGender}`;
    socket.join(room);
  }

  socket.on('disconnect', (reason) => {
    console.log(`🔌 User disconnected: ${socket.userId} — ${reason}`);
    // Remove socket from user's active socket set in Redis and broadcast presence if offline
    PresenceService.removeSocket(redis, io, socket.userId, socket.id);
  });
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

// ── Periodically reconcile voided Google Play purchases (startup + every 6 hours) ──
if (process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON || process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE) {
  setTimeout(() => {
    GooglePlayService.syncVoidedPurchases().catch((err) => {
      console.warn('⚠️ [Google Play Startup Voided Sync]:', err.message);
    });
  }, 15 * 1000);

  setInterval(() => {
    GooglePlayService.syncVoidedPurchases().catch((err) => {
      console.warn('⚠️ [Google Play Scheduled Voided Sync]:', err.message);
    });
  }, 6 * 60 * 60 * 1000);
}

// ── Start server (ensures Redis adapter is attached before accepting connections) ──
async function startServer() {
  if (process.env.REDIS_URL) {
    try {
      const pubClient = new Redis(process.env.REDIS_URL, {
        maxRetriesPerRequest: null,
        retryStrategy: (times) => Math.min(times * 100, 2000),
        lazyConnect: true,
      });
      const subClient = pubClient.duplicate();

      pubClient.on('error', (err) => {
        console.warn('⚠️ [Socket.io pubClient error]:', err.message);
      });
      subClient.on('error', (err) => {
        console.warn('⚠️ [Socket.io subClient error]:', err.message);
      });

      await Promise.all([pubClient.connect(), subClient.connect()]);
      io.adapter(createAdapter(pubClient, subClient));
      console.log('✅ Socket.io Redis Adapter active for horizontal multi-instance scaling');
    } catch (err) {
      console.warn('⚠️ Redis adapter pub/sub failed to connect, using local in-memory adapter:', err.message);
    }
  }

  const PORT = process.env.PORT || 3000;
  server.listen(PORT, () => {
    console.log(`🚀 BuddyPartner server listening on port ${PORT}`);
    console.log('✅ [Scaling] Multi-instance Redis cluster active: call state, matchmaking, and instant connect synchronized via Redis.');
  });
}

startServer();

module.exports = { app, server, io, redis, db };
