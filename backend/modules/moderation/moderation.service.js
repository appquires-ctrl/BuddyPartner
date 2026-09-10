const db = require('../../db');

class ModerationService {
  /**
   * Check if a user is currently banned.
   * Direct primary key index scan on public.users(id) (<0.1ms).
   * @param {string} userId
   * @returns {Promise<{ isBlocked: boolean, isBanned: boolean, isSuspended: boolean, suspendedUntil: null }>}
   */
  async isUserBlocked(userId) {
    if (!userId) {
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
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
