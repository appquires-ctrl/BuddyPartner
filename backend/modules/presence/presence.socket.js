const { PresenceService } = require('./presence.service');

const MAX_SUBSCRIPTION_IDS = 200;
const PRESENCE_STATE_COOLDOWN_MS = 2000; // Max 1 offline transition per 2 seconds per socket
const LEASE_REFRESH_INTERVAL_MS = 20000; // Heartbeat lease refresh every 20 seconds while socket is connected

/**
 * Validate and sanitize user ID arrays for subscribe/unsubscribe events.
 * Returns an array of valid string user IDs capped at MAX_SUBSCRIPTION_IDS (200), or null if invalid.
 * @param {unknown} data
 * @returns {string[] | null}
 */
function extractValidUserIds(data) {
  const raw = Array.isArray(data) ? data : data?.userIds;
  if (!Array.isArray(raw) || raw.length === 0) return null;

  const valid = [];
  for (const id of raw) {
    if (typeof id === 'string' && id.trim().length > 0) {
      valid.push(id.trim());
      if (valid.length >= MAX_SUBSCRIPTION_IDS) break; // Enforce max room subscription cap (200)
    }
  }

  return valid.length > 0 ? valid : null;
}

/**
 * Register all presence-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerPresenceHandlers(io, socket, redis) {
  const userId = socket.userId;
  if (!userId) return;

  // Track per-socket state and timestamp for rate limiting & deduplication
  let lastProcessedState = 'online';
  let lastStateChangeTimestamp = Date.now();

  // Automatically join personal presence target room
  socket.join(`presence_user:${userId}`);

  // ── Heartbeat TTL Lease Refresh ──────────────────────────────────────────
  // 1. Refresh Redis lease on every incoming Engine.IO transport packet (ping/pong every 5s)
  if (socket.conn) {
    socket.conn.on('packet', (packet) => {
      if (packet && (packet.type === 'ping' || packet.type === 'pong')) {
        PresenceService.refreshLease(redis, userId);
      }
    });
  }

  // 2. Periodic safety refresh timer while socket remains actively connected
  const leaseRefreshTimer = setInterval(() => {
    if (socket.connected) {
      PresenceService.refreshLease(redis, userId);
    }
  }, LEASE_REFRESH_INTERVAL_MS);

  socket.on('disconnect', () => {
    clearInterval(leaseRefreshTimer);
  });

  // ── presence:state ────────────────────────────────────────────────────────
  // Triggered when mobile app lifecycle changes (resumed / paused / hidden / detached)
  socket.on('presence:state', async (data) => {
    try {
      const status = data?.status;

      // 1. Strict status validation: must be exactly 'online' or 'offline'
      if (status !== 'online' && status !== 'offline') {
        console.warn(`⚠️ [Presence] Ignored invalid presence:state from user ${userId}:`, data);
        return;
      }

      const now = Date.now();

      // 2. Ignore duplicate events of the exact same state within cooldown window (deduplication)
      if (status === lastProcessedState && (now - lastStateChangeTimestamp < PRESENCE_STATE_COOLDOWN_MS)) {
        return;
      }

      // 3. State transitions (online -> offline and offline -> online) are processed immediately
      lastProcessedState = status;
      lastStateChangeTimestamp = now;

      // 4. Process validated state change
      if (status === 'online') {
        await PresenceService.addSocket(redis, io, userId, socket.id);
      } else {
        await PresenceService.removeSocket(redis, io, userId, socket.id);
      }
    } catch (err) {
      console.error(`❌ [Presence] Error processing presence:state for ${userId}:`, err.message);
    }
  });

  // ── presence:subscribe ───────────────────────────────────────────────────
  // Subscribe to live presence updates for a batch of users (e.g. chat list or active chat page)
  socket.on('presence:subscribe', (data) => {
    try {
      const userIds = extractValidUserIds(data);
      if (!userIds) return;
      PresenceService.subscribePresence(socket, userIds);
    } catch (err) {
      console.error(`❌ [Presence] Error in presence:subscribe for ${userId}:`, err.message);
    }
  });

  // ── presence:unsubscribe ─────────────────────────────────────────────────
  // Unsubscribe when leaving a chat screen or cleaning up
  socket.on('presence:unsubscribe', (data) => {
    try {
      const userIds = extractValidUserIds(data);
      if (!userIds) return;
      PresenceService.unsubscribePresence(socket, userIds);
    } catch (err) {
      console.error(`❌ [Presence] Error in presence:unsubscribe for ${userId}:`, err.message);
    }
  });
}

module.exports = { registerPresenceHandlers };
