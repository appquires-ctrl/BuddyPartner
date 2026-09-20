const db = require('../../db');
const redis = require('../../redis');

class ModerationService {
  /**
   * Check if a user is currently banned.
   * Redis cached with 300s TTL (user:is_banned:${userId}).
   * Falls back to primary key index scan on public.users(id) on cache miss.
   * @param {string} userId
   * @returns {Promise<{ isBlocked: boolean, isBanned: boolean, isSuspended: boolean, suspendedUntil: null }>}
   */
  async isUserBlocked(userId) {
    if (!userId) {
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
    }

    const cacheKey = `user:is_banned:${userId}`;
    try {
      const cached = await redis.get(cacheKey);
      if (cached !== null && cached !== undefined) {
        const isBanned = cached === '1';
        return {
          isBlocked: isBanned,
          isBanned,
          isSuspended: false,
          suspendedUntil: null,
        };
      }
    } catch (cacheErr) {
      console.warn(`[Moderation Cache] Redis get error for user ${userId}:`, cacheErr.message);
    }

    try {
      const result = await db.query(
        'SELECT is_banned FROM public.users WHERE id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
      }

      const isBanned = Boolean(result.rows[0].is_banned);

      // Cache for 300s (matching user:subscribed:${userId} pattern)
      redis.set(cacheKey, isBanned ? '1' : '0', 'EX', 300).catch((err) => {
        console.warn(`[Moderation Cache] Redis set error for user ${userId}:`, err.message);
      });

      return {
        isBlocked: isBanned,
        isBanned,
        isSuspended: false,
        suspendedUntil: null,
      };
    } catch (err) {
      console.error(`Error checking block status for user ${userId}:`, err.message);
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
    }
  }

  /**
   * File a report against a user.
   * A permanent ban is triggered when 3 DISTINCT reporters have reported the user.
   * Multiple reports from the same reporter ID only count ONCE towards the threshold.
   *
   * @param {string} reporterId
   * @param {string} reportedUserId
   * @param {string} reason
   * @param {string|null} description
   * @param {string|null} messageId
   * @param {string|null} conversationId
   */
  async fileReport(reporterId, reportedUserId, reason, description = null, messageId = null, conversationId = null) {
    if (!reporterId || !reportedUserId || !reason) {
      throw new Error('reporterId, reportedUserId, and reason are required.');
    }

    if (reporterId === reportedUserId) {
      throw new Error('A user cannot report themselves.');
    }

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const validConversationId = (conversationId && conversationId.length === 36) ? conversationId : null;
      const validMessageId = (messageId && messageId.length === 36) ? messageId : null;

      if (validConversationId) {
        const convCheck = await client.query('SELECT id FROM public.conversations WHERE id = $1', [validConversationId]);
        if (convCheck.rows.length === 0) {
          console.warn(`[Moderation] Conversation ${validConversationId} does not exist, storing NULL`);
        }
      }

      if (validMessageId) {
        const msgCheck = await client.query('SELECT id FROM public.messages WHERE id = $1', [validMessageId]);
        if (msgCheck.rows.length === 0) {
          console.warn(`[Moderation] Message ${validMessageId} does not exist, storing NULL`);
        }
      }

      // 1. Insert report record
      const insertRes = await client.query(
        `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, reporter_id, reported_user_id, reason, description, message_id, conversation_id, created_at`,
        [reporterId, reportedUserId, reason, description, validMessageId, validConversationId]
      );

      // 2. Count DISTINCT reporters for this reported user
      const countRes = await client.query(
        `SELECT COUNT(DISTINCT reporter_id) AS distinct_count
         FROM public.reports
         WHERE reported_user_id = $1`,
        [reportedUserId]
      );

      const distinctReporterCount = parseInt(countRes.rows[0].distinct_count || 0, 10);
      let isBanned = false;

      // 3. If distinct count >= 3, trigger immediate permanent ban
      if (distinctReporterCount >= 3) {
        await client.query(
          `UPDATE public.users SET is_banned = TRUE WHERE id = $1`,
          [reportedUserId]
        );
        isBanned = true;
        // Invalidate Redis ban cache and kill active session immediately
        await Promise.all([
          redis.del(`user:is_banned:${reportedUserId}`).catch(() => {}),
          redis.set(
            `user_active_session:${reportedUserId}`,
            JSON.stringify({ sessionId: null, isBanned: true }),
            'EX',
            30 * 24 * 60 * 60
          ).catch(() => {}),
        ]);
        console.log(`⛔ [Moderation] BAN TRIGGERED: User ${reportedUserId} has been reported by ${distinctReporterCount} distinct reporters.`);
      }

      await client.query('COMMIT');

      return {
        report: insertRes.rows[0],
        moderationResult: {
          distinctReporterCount,
          isBanned,
        },
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`❌ [Moderation] Error filing report for reported user ${reportedUserId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }
}

module.exports = {
  ModerationService: new ModerationService(),
};
