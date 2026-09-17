const { MessagingService } = require('./messaging.service');
const { PresenceService } = require('../presence/presence.service');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

const messagingService = new MessagingService();

// Rate limit: max messages per window
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_SECONDS = 1;

// ── In-memory Conversation Participants Cache ──────────────────────────────
// Caches { user_a_id, user_b_id } for 10 minutes to eliminate DB queries on typing
const convParticipantsCache = new Map();
const CONV_CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_CONV_CACHE_SIZE = 10000;

async function getConversationParticipants(conversationId) {
  if (!conversationId) return null;

  const cached = convParticipantsCache.get(conversationId);
  if (cached && (Date.now() - cached.timestamp < CONV_CACHE_TTL_MS)) {
    return cached.data;
  }

  const convResult = await require('../../db').query(
    'SELECT user_a_id, user_b_id FROM public.conversations WHERE id = $1',
    [conversationId]
  );

  if (convResult.rows.length === 0) return null;
  const data = convResult.rows[0];

  if (convParticipantsCache.size >= MAX_CONV_CACHE_SIZE) {
    const oldestKey = convParticipantsCache.keys().next().value;
    convParticipantsCache.delete(oldestKey);
  }

  convParticipantsCache.set(conversationId, { data, timestamp: Date.now() });
  return data;
}

/**
 * Check send-rate limit for a user using Redis sliding window.
 * Returns true if the user is rate-limited (should be rejected).
 */
async function isRateLimited(redis, userId) {
  const key = `msg_rate:${userId}`;
  const count = await redis.incr(key);

  if (count === 1) {
    await redis.expire(key, RATE_LIMIT_WINDOW_SECONDS);
  }

  return count > RATE_LIMIT_MAX;
}

/**
 * Register all messaging-related Socket.io event handlers for a connected socket.
 *
 * @param {import('socket.io').Server} io
 * @param {import('socket.io').Socket} socket
 * @param {import('ioredis').Redis} redis
 */
function registerMessagingHandlers(io, socket, redis) {
  const userId = socket.userId;

  // ── send_message ──────────────────────────────────────────────────────
  socket.on('send_message', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};

    try {
      const { conversationId, content, type } = data || {};

      if (!conversationId || !content || !content.trim()) {
        cb({ error: 'conversationId and content are required' });
        return;
      }

      // Subscription check
      const isSub = await subscriptionsService.isSubscribed(userId);
      if (!isSub) {
        cb({ error: 'SUBSCRIPTION_REQUIRED', message: 'An active subscription is required to send messages.' });
        return;
      }

      // Rate limit check
      const limited = await isRateLimited(redis, userId);
      if (limited) {
        cb({ error: 'Slow down! You are sending messages too quickly.' });
        return;
      }

      // Determine the other participant ahead of time via cache or DB
      const conv = await getConversationParticipants(conversationId);
      const otherUserId = conv ? (conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id) : null;

      // Check if recipient is online via Redis O(1) before insert
      const isOnline = otherUserId ? await PresenceService.isUserOnline(redis, otherUserId) : false;
      const initialStatus = isOnline ? 'delivered' : 'sent';

      // Send message (includes block-list check & single combined CTE insert/update with initialStatus)
      const message = await messagingService.sendMessage(
        conversationId,
        userId,
        content.trim(),
        type || 'text',
        null,
        initialStatus,
        conv
      );

      if (conv && otherUserId) {
        if (isOnline) {
          // Deliver directly to recipient's room
          io.to(otherUserId).emit('message:new', { message });

          // Inform sender of double tick (delivered)
          socket.emit('message:status_update', {
            conversationId,
            messageId: message.id,
            status: 'delivered',
          });
        }

        // Emit to sender
        socket.emit('message:new', { message });
      }

      cb({ success: true, message });
    } catch (err) {
      console.error('Error in send_message:', err.message);
      cb({ error: err.message });
    }
  });

  // ── typing ────────────────────────────────────────────────────────────
  socket.on('typing', async (data) => {
    try {
      const { conversationId } = data || {};
      if (!conversationId) return;

      // Participant lookup from in-memory cache (0ms DB load)
      const conv = await getConversationParticipants(conversationId);
      if (!conv) return;
      if (conv.user_a_id !== userId && conv.user_b_id !== userId) return;

      const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;

      // O(1) Room emit directly to recipient across all cluster nodes
      io.to(otherUserId).emit('typing', {
        conversationId,
        userId,
      });
    } catch (err) {
      console.error('Error in typing:', err.message);
    }
  });

  // ── message:read ──────────────────────────────────────────────────────
  socket.on('message:read', async (data, callback) => {
    const cb = typeof callback === 'function' ? callback : () => {};

    try {
      const { conversationId, messageId } = data || {};

      if (!conversationId || !messageId) {
        cb({ error: 'conversationId and messageId are required' });
        return;
      }

      await messagingService.markAsRead(conversationId, userId, messageId);

      // Notify other participant about the read receipt via room emit
      const conv = await getConversationParticipants(conversationId);
      if (conv) {
        const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;

        io.to(otherUserId).emit('message:read', {
          conversationId,
          userId,
          messageId,
        });
        io.to(otherUserId).emit('message:status_update', {
          conversationId,
          messageId,
          status: 'read',
        });
      }

      cb({ success: true });
    } catch (err) {
      console.error('Error in message:read:', err.message);
      cb({ error: err.message });
    }
  });
}

module.exports = { registerMessagingHandlers, getConversationParticipants };
