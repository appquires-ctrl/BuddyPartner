const db = require('../../db');

class ModerationService {
  /**
   * Check if a user is currently banned.
   * @param {string} userId
   * @returns {Promise<{ isBlocked: boolean, isBanned: boolean, isSuspended: boolean, suspendedUntil: null }>}
   */
  async isUserBlocked(userId) {
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
    if (reporterId === reportedUserId) {
      throw new Error('Cannot report yourself');
    }

    const cleanMessageId = (messageId && typeof messageId === 'string' && messageId.trim().length > 0) ? messageId.trim() : null;
    const cleanConversationId = (conversationId && typeof conversationId === 'string' && conversationId.trim().length > 0) ? conversationId.trim() : null;
    const cleanDescription = (description && typeof description === 'string' && description.trim().length > 0) ? description.trim() : null;

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Insert report record
      const insertRes = await client.query(
        `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING *`,
        [reporterId, reportedUserId, reason, cleanDescription, cleanMessageId, cleanConversationId]
      );

      // 2. Count DISTINCT reporters for this reported user
      const countRes = await client.query(
        `SELECT COUNT(DISTINCT reporter_id)::int AS distinct_count
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
