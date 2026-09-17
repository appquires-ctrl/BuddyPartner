const db = require('../../db');
const redis = require('../../redis');
const { sendPushNotification } = require('../../services/firebase.service');

class MessagingService {
  /**
   * Normalize user pair ordering — lexicographically smaller ID = user_a_id.
   * Ensures a single canonical conversation row per pair.
   */
  _normalizeIds(idA, idB) {
    return idA < idB ? { userAId: idA, userBId: idB } : { userAId: idB, userBId: idA };
  }

  /**
   * Find or create a conversation between two users.
   * @param {string} currentUserId - The requesting user's Firebase UID
   * @param {string} otherUserId - The other user's Firebase UID
   * @returns {object} The conversation row
   */
  /**
   * Helper method to validate standard UUID string format.
   */
  _isValidUUID(uuid) {
    return typeof uuid === 'string' && /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(uuid);
  }

  /**
   * Find or create a conversation between two users.
   * @param {string} currentUserId - The requesting user's Firebase UID
   * @param {string} otherUserId - The other user's Firebase UID
   * @returns {object} The conversation row
   */
  async findOrCreateConversation(currentUserId, otherUserId) {
    if (!this._isValidUUID(otherUserId) || !this._isValidUUID(currentUserId)) {
      throw new Error('Invalid user ID format');
    }

    if (currentUserId === otherUserId) {
      throw new Error('Cannot create a conversation with yourself');
    }

    // Verify other user exists in DB before attempting to insert
    const userCheck = await db.query(
      `SELECT id FROM public.users WHERE id = $1`,
      [otherUserId]
    );
    if (userCheck.rows.length === 0) {
      throw new Error('User not found');
    }

    // Check block list before creating conversation
    const blocked = await this.isBlocked(currentUserId, otherUserId);
    if (blocked) {
      throw new Error('Cannot start a conversation with this user');
    }

    const { userAId, userBId } = this._normalizeIds(currentUserId, otherUserId);

    const result = await db.query(
      `INSERT INTO public.conversations (user_a_id, user_b_id)
       VALUES ($1, $2)
       ON CONFLICT (user_a_id, user_b_id) DO UPDATE SET user_a_id = EXCLUDED.user_a_id
       RETURNING *`,
      [userAId, userBId]
    );

    return result.rows[0];
  }

  /**
   * Send a message in a conversation.
   * Checks block list first, then inserts and updates last_message_at.
   * @param {string} conversationId
   * @param {string} senderId - Verified Firebase UID of the sender
   * @param {string} content - Message text
   * @param {string} type - 'text' | 'image' | 'system'
   * @param {string|null} mediaUrl - Media URL (deferred, always null for now)
   * @param {string} initialStatus - 'sent' | 'delivered' (default: 'sent')
   * @returns {object} The inserted message row
   */
  async sendMessage(conversationId, senderId, content, type = 'text', mediaUrl = null, initialStatus = 'sent', preFetchedConv = null) {
    // 1. Verify sender is a participant of this conversation (skip DB read if already pre-fetched)
    let conv = preFetchedConv;
    if (!conv) {
      const convResult = await db.query(
        `SELECT * FROM public.conversations WHERE id = $1`,
        [conversationId]
      );

      if (convResult.rows.length === 0) {
        throw new Error('Conversation not found');
      }
      conv = convResult.rows[0];
    }

    if (conv.user_a_id !== senderId && conv.user_b_id !== senderId) {
      throw new Error('Not a participant of this conversation');
    }

    // 2. Check block list (Redis cached for 60s)
    const otherUserId = conv.user_a_id === senderId ? conv.user_b_id : conv.user_a_id;
    const blocked = await this.isBlocked(senderId, otherUserId);
    if (blocked) {
      throw new Error('Message blocked: one party has blocked the other');
    }

    // 3 & 4. Combined CTE: Insert message AND Update conversations last_message_at in 1 DB round trip
    const msgResult = await db.query(
      `WITH inserted_msg AS (
         INSERT INTO public.messages (conversation_id, sender_id, content, type, media_url, status)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *
       ),
       updated_conv AS (
         UPDATE public.conversations
         SET last_message_at = NOW()
         WHERE id = $1
       )
       SELECT * FROM inserted_msg`,
      [conversationId, senderId, content, type, mediaUrl, initialStatus]
    );

    const message = msgResult.rows[0];

    // 5. Dispatch FCM Push Notification ONLY if recipient is offline (not already delivered via WebSocket)
    if (initialStatus !== 'delivered') {
      try {
        const userRes = await db.query(
          `SELECT u.id, u.fcm_token, 
                  (SELECT full_name FROM public.users WHERE id = $1) as sender_name
           FROM public.users u WHERE u.id = $2`,
          [senderId, otherUserId]
        );

        if (userRes.rows.length > 0 && userRes.rows[0].fcm_token) {
          const recipient = userRes.rows[0];
          const senderName = recipient.sender_name || 'Someone';

          let notifTitle = senderName;
          let notifBody = type === 'text' ? content : 'Sent you an attachment';

          sendPushNotification({
            token: recipient.fcm_token,
            title: notifTitle,
            body: notifBody,
            tag: `chat_${conversationId}`,
            data: {
              type: 'chat_message',
              senderId: String(senderId),
              senderName: String(senderName),
              conversationId: String(conversationId),
            },
          }).catch((err) => console.error('FCM send error:', err.message));
        }
      } catch (pushErr) {
        console.error('Error sending message push notification:', pushErr.message);
      }
    }

    return message;
  }

  /**
   * Get messages for a conversation with cursor-based pagination.
   * @param {string} conversationId
   * @param {string} requestingUserId - Must be a participant
   * @param {string|null} cursor - ISO timestamp cursor for pagination
   * @param {number} limit - Number of messages to return (default 30)
   * @returns {object} { messages, nextCursor }
   */
  async getMessages(conversationId, requestingUserId, cursor = null, limit = 30) {
    if (!this._isValidUUID(conversationId) || !this._isValidUUID(requestingUserId)) {
      throw new Error('Conversation not found');
    }

    // Verify participant
    const convResult = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [conversationId]
    );

    if (convResult.rows.length === 0) {
      throw new Error('Conversation not found');
    }

    const conv = convResult.rows[0];
    if (conv.user_a_id !== requestingUserId && conv.user_b_id !== requestingUserId) {
      throw new Error('Not a participant of this conversation');
    }

    let query;
    let params;

    if (cursor) {
      query = `
        SELECT * FROM public.messages
        WHERE conversation_id = $1 AND created_at < $2
        ORDER BY created_at DESC
        LIMIT $3
      `;
      params = [conversationId, cursor, limit];
    } else {
      query = `
        SELECT * FROM public.messages
        WHERE conversation_id = $1
        ORDER BY created_at DESC
        LIMIT $2
      `;
      params = [conversationId, limit];
    }

    const result = await db.query(query, params);
    const messages = result.rows;
    const nextCursor = messages.length === limit
      ? messages[messages.length - 1].created_at.toISOString()
      : null;

    return { messages, nextCursor };
  }

  /**
   * Get all conversations for a user with last message preview and unread count.
   * @param {string} userId - Verified Firebase UID
   * @returns {Array} Conversation list with preview data
   */
  async getConversations(userId) {
    const result = await db.query(
      `SELECT
        c.id,
        c.user_a_id,
        c.user_b_id,
        c.created_at,
        c.last_message_at,
        -- Last message preview
        lm.content AS last_message_content,
        lm.type AS last_message_type,
        lm.sender_id AS last_message_sender_id,
        lm.created_at AS last_message_created_at,
        -- Other user's profile
        u.full_name AS other_user_name,
        u.gender AS other_user_gender,
        u.avatar_seed AS other_user_avatar_seed,
        u.avatar_style AS other_user_avatar_style,
        -- Unread count: messages after the user's last read message
        COALESCE(
          (SELECT COUNT(*) FROM public.messages m
           WHERE m.conversation_id = c.id
             AND m.sender_id != $1
             AND m.created_at > COALESCE(
               (SELECT m2.created_at FROM public.messages m2
                WHERE m2.id = mr.last_read_message_id),
               '1970-01-01'::timestamptz
             )
          ), 0
        )::int AS unread_count
      FROM public.conversations c
      -- Join to get the other user's profile
      LEFT JOIN public.users u ON u.id = CASE
        WHEN c.user_a_id = $1 THEN c.user_b_id
        ELSE c.user_a_id
      END
      -- Join to get the last message
      LEFT JOIN LATERAL (
        SELECT content, type, sender_id, created_at
        FROM public.messages
        WHERE conversation_id = c.id
        ORDER BY created_at DESC
        LIMIT 1
      ) lm ON true
      -- Join to get read receipts
      LEFT JOIN public.message_reads mr ON mr.conversation_id = c.id AND mr.user_id = $1
      WHERE c.user_a_id = $1 OR c.user_b_id = $1
      ORDER BY c.last_message_at DESC`,
      [userId]
    );

    return result.rows.map(row => ({
      id: row.id,
      otherUserId: row.user_a_id === userId ? row.user_b_id : row.user_a_id,
      otherUserName: row.other_user_name || 'User',
      otherUserGender: row.other_user_gender,
      otherUserAvatarSeed: row.other_user_avatar_seed || null,
      otherUserAvatarStyle: row.other_user_avatar_style || 'avataaars',
      otherUserAvatar: row.other_user_avatar_seed || null,
      lastMessage: row.last_message_content,
      lastMessageType: row.last_message_type,
      lastMessageSenderId: row.last_message_sender_id,
      lastMessageAt: row.last_message_at,
      unreadCount: row.unread_count,
      createdAt: row.created_at,
    }));
  }

  /**
   * Mark messages as read up to a specific message.
   * @param {string} conversationId
   * @param {string} userId - The reader's Firebase UID
   * @param {string} messageId - The latest message ID that was read
   */
  async markAsRead(conversationId, userId, messageId = null) {
    if (!this._isValidUUID(conversationId)) return;

    // Verify participant
    const convResult = await db.query(
      `SELECT * FROM public.conversations WHERE id = $1`,
      [conversationId]
    );

    if (convResult.rows.length === 0) {
      throw new Error('Conversation not found');
    }

    const conv = convResult.rows[0];
    if (conv.user_a_id !== userId && conv.user_b_id !== userId) {
      throw new Error('Not a participant of this conversation');
    }

    let targetMsgId = messageId;
    if (!targetMsgId) {
      const latestRes = await db.query(
        `SELECT id FROM public.messages WHERE conversation_id = $1 ORDER BY created_at DESC LIMIT 1`,
        [conversationId]
      );
      targetMsgId = latestRes.rows[0]?.id || null;
    }

    if (targetMsgId) {
      await db.query(
        `INSERT INTO public.message_reads (conversation_id, user_id, last_read_message_id)
         VALUES ($1, $2, $3)
         ON CONFLICT (conversation_id, user_id)
         DO UPDATE SET last_read_message_id = $3`,
        [conversationId, userId, targetMsgId]
      );
    }

    // Update status of all unread messages from the other user in this conversation to 'read'
    await db.query(
      `UPDATE public.messages
       SET status = 'read'
       WHERE conversation_id = $1 AND sender_id != $2 AND status != 'read'`,
      [conversationId, userId]
    );
  }

  // ── Delivery Catch-up ──────────────────────────────────────────────────

  /**
   * Mark all unread 'sent' messages addressed to this recipient as 'delivered' when they connect.
   * Emits real-time double-tick updates to the senders.
   * @param {string} recipientId
   * @param {import('socket.io').Server|null} io
   */
  async markDeliveredForRecipient(recipientId, io = null) {
    if (!this._isValidUUID(recipientId)) return;

    try {
      const updateResult = await db.query(
        `WITH user_convs AS (
           SELECT id FROM public.conversations WHERE user_a_id = $1
           UNION
           SELECT id FROM public.conversations WHERE user_b_id = $1
         )
         UPDATE public.messages m
         SET status = 'delivered'
         FROM user_convs uc
         WHERE m.conversation_id = uc.id
           AND m.status = 'sent'
           AND m.sender_id != $1
         RETURNING m.id, m.conversation_id, m.sender_id`,
        [recipientId]
      );

      if (io && updateResult.rows.length > 0) {
        for (const row of updateResult.rows) {
          io.to(row.sender_id).emit('message:status_update', {
            conversationId: row.conversation_id,
            messageId: row.id,
            status: 'delivered',
          });
        }
      }
    } catch (err) {
      console.error('Error marking messages as delivered for recipient:', err.message);
    }
  }

  // ── Block / Report ──────────────────────────────────────────────────────

  /**
   * Check if either user has blocked the other.
   * Cached in Redis for 60s (key: block:normA:normB).
   * @returns {boolean}
   */
  async isBlocked(userAId, userBId) {
    const { userAId: id1, userBId: id2 } = this._normalizeIds(userAId, userBId);
    const cacheKey = `block:${id1}:${id2}`;
    try {
      const cached = await redis.get(cacheKey);
      if (cached !== null && cached !== undefined) {
        return cached === '1';
      }
    } catch (_) {}

    const result = await db.query(
      `SELECT 1 FROM public.blocks
       WHERE (blocker_id = $1 AND blocked_id = $2)
          OR (blocker_id = $2 AND blocked_id = $1)
       LIMIT 1`,
      [userAId, userBId]
    );
    const blocked = result.rows.length > 0;
    redis.set(cacheKey, blocked ? '1' : '0', 'EX', 60).catch(() => {});
    return blocked;
  }

  /**
   * Block a user and notify real-time sockets.
   * @param {string} blockerId
   * @param {string} blockedId
   * @param {import('socket.io').Server|null} io
   */
  async blockUser(blockerId, blockedId, io = null) {
    if (blockerId === blockedId) {
      throw new Error('Cannot block yourself');
    }

    await db.query(
      `INSERT INTO public.blocks (blocker_id, blocked_id)
       VALUES ($1, $2)
       ON CONFLICT (blocker_id, blocked_id) DO NOTHING`,
      [blockerId, blockedId]
    );

    const { userAId: id1, userBId: id2 } = this._normalizeIds(blockerId, blockedId);
    await redis.del(`block:${id1}:${id2}`).catch(() => {});

    if (io) {
      io.emit('user:blocked', {
        blockerId,
        blockedId,
        timestamp: new Date().toISOString(),
      });
      console.log(`🚫 [Block] User ${blockerId} blocked user ${blockedId}. Socket notification emitted.`);
    }
  }

  /**
   * Unblock a user.
   */
  async unblockUser(blockerId, blockedId) {
    await db.query(
      `DELETE FROM public.blocks WHERE blocker_id = $1 AND blocked_id = $2`,
      [blockerId, blockedId]
    );

    const { userAId: id1, userBId: id2 } = this._normalizeIds(blockerId, blockedId);
    await redis.del(`block:${id1}:${id2}`).catch(() => {});
  }

  /**
   * Report a user/message.
   */
  async reportUser(reporterId, reportedUserId, reason, description = null, messageId = null, conversationId = null) {
    if (reporterId === reportedUserId) {
      throw new Error('Cannot report yourself');
    }

    const result = await db.query(
      `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [reporterId, reportedUserId, reason, description, messageId, conversationId]
    );

    return result.rows[0];
  }
}

const messagingService = new MessagingService();

module.exports = {
  MessagingService,
  messagingService,
};
