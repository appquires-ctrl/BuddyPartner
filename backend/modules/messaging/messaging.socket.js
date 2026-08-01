const { MessagingService } = require('./messaging.service');
const { userSockets } = require('../matchmaking/matchmaking.socket');
const { subscriptionsService } = require('../subscriptions/subscriptions.service');

const messagingService = new MessagingService();

// Rate limit: max messages per window
const RATE_LIMIT_MAX = 5;
const RATE_LIMIT_WINDOW_SECONDS = 1;

/**
 * Check send-rate limit for a user using Redis sliding window.
 * Returns true if the user is rate-limited (should be rejected).
 */
async function isRateLimited(redis, userId) {
  const key = `msg_rate:${userId}`;
  const count = await redis.incr(key);

  // Set expiry only on first increment (new window)
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

      // Send message (includes block-list check)
      const message = await messagingService.sendMessage(
        conversationId,
        userId,
        content.trim(),
        type || 'text'
      );

      // Determine the other participant
      const convResult = await require('../../db').query(
        'SELECT user_a_id, user_b_id FROM public.conversations WHERE id = $1',
        [conversationId]
      );

      if (convResult.rows.length > 0) {
        const conv = convResult.rows[0];
        const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;

        // Check if recipient socket is active
        const recipientSocketId = userSockets.get(otherUserId);
        if (recipientSocketId) {
          // Delivered! Update status in DB and emit to both parties
          message.status = 'delivered';
          await require('../../db').query(
            "UPDATE public.messages SET status = 'delivered' WHERE id = $1",
            [message.id]
          );

          io.to(recipientSocketId).emit('message:new', { message });
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

      // Verify participant and find other user
      const convResult = await require('../../db').query(
        'SELECT user_a_id, user_b_id FROM public.conversations WHERE id = $1',
        [conversationId]
      );

      if (convResult.rows.length === 0) return;

      const conv = convResult.rows[0];
      if (conv.user_a_id !== userId && conv.user_b_id !== userId) return;

      const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;
      const recipientSocketId = userSockets.get(otherUserId);

      if (recipientSocketId) {
        io.to(recipientSocketId).emit('typing', {
          conversationId,
          userId,
        });
      }
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

      // Notify the other participant about the read receipt
      const convResult = await require('../../db').query(
        'SELECT user_a_id, user_b_id FROM public.conversations WHERE id = $1',
        [conversationId]
      );

      if (convResult.rows.length > 0) {
        const conv = convResult.rows[0];
        const otherUserId = conv.user_a_id === userId ? conv.user_b_id : conv.user_a_id;
        const senderSocketId = userSockets.get(otherUserId);

        if (senderSocketId) {
          io.to(senderSocketId).emit('message:read', {
            conversationId,
            userId,
            messageId,
          });
          io.to(senderSocketId).emit('message:status_update', {
            conversationId,
            messageId,
            status: 'read',
          });
        }
      }

      cb({ success: true });
    } catch (err) {
      console.error('Error in message:read:', err.message);
      cb({ error: err.message });
    }
  });
}

module.exports = { registerMessagingHandlers };
