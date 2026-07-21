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

app.use('/api/auth', authRoutes);
app.use('/api/calls', callsRoutes);
app.use('/api', messagingRoutes);

const server = http.createServer(app);

// ── Redis client ────────────────────────────────────────────────────────────
const redis = new Redis(process.env.REDIS_URL, {
  maxRetriesPerRequest: 3,
  retryStrategy(times) {
    if (times > 5) return null; // Stop retrying after 5 attempts
    return Math.min(times * 200, 2000);
  },
});

redis.on('connect', () => console.log('✅ Redis connected'));
redis.on('error', (err) => console.error('❌ Redis error:', err.message));

// ── Socket.io setup ─────────────────────────────────────────────────────────
const io = new Server(server, {
  cors: {
    origin: '*', // Tighten in production
    methods: ['GET', 'POST'],
  },
  pingTimeout: 30000,
  pingInterval: 10000,
});

// Socket.io authentication middleware — validates custom JWT session
io.use(async (socket, next) => {
  const token = socket.handshake.auth?.token;
  if (!token) {
    return next(new Error('Authentication error: no token provided'));
  }

  try {
    const secret = process.env.JWT_SECRET || 'loopcall_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);

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
  registerMatchmakingHandlers(io, socket, redis);
  registerMessagingHandlers(io, socket, redis);

  socket.on('disconnect', (reason) => {
    console.log(`🔌 User disconnected: ${socket.userId} — ${reason}`);
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
