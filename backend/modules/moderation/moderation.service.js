const db = require('../../db');

class ModerationService {
  /**
   * Check if a user is currently suspended or permanently banned.
   * @param {string} userId
   * @returns {Promise<{ isBlocked: boolean, isBanned: boolean, isSuspended: boolean, suspendedUntil: Date|null }>}
   */
  async isUserBlocked(userId) {
    try {
      const result = await db.query(
        'SELECT strike_count, suspended_until, is_banned FROM public.users WHERE id = $1',
        [userId]
      );

      if (result.rows.length === 0) {
        return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
      }

      const user = result.rows[0];
      const now = new Date();
      const isBanned = Boolean(user.is_banned);
      const suspendedUntil = user.suspended_until ? new Date(user.suspended_until) : null;
      const isSuspended = Boolean(suspendedUntil && suspendedUntil > now);

      return {
        isBlocked: isBanned || isSuspended,
        isBanned,
        isSuspended,
        suspendedUntil,
      };
    } catch (err) {
      console.error(`Error checking block status for user ${userId}:`, err.message);
      return { isBlocked: false, isBanned: false, isSuspended: false, suspendedUntil: null };
    }
  }

  /**
   * Apply a strike to a user if eligible (i.e. not currently suspended or banned).
   * Exact Rule:
   * - 1st strike: account suspended for 24 hours
   * - 2nd strike: suspended for 48 hours
   * - 3rd strike: permanent ban
   * Reports filed while already suspended do NOT add a strike or extend timer.
   * 
   * @param {string} userId
   * @returns {Promise<{ strikeApplied: boolean, newStrikeCount: number, suspendedUntil: Date|null, isBanned: boolean }>}
   */
  async applyStrikeIfEligible(userId) {
    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const userRes = await client.query(
        'SELECT strike_count, suspended_until, is_banned FROM public.users WHERE id = $1 FOR UPDATE',
        [userId]
      );

      if (userRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { strikeApplied: false, newStrikeCount: 0, suspendedUntil: null, isBanned: false };
      }

      const user = userRes.rows[0];
      const now = new Date();
      const isBanned = Boolean(user.is_banned);
      const suspendedUntil = user.suspended_until ? new Date(user.suspended_until) : null;
      const isCurrentlySuspended = Boolean(suspendedUntil && suspendedUntil > now);

      // Rule check: A report filed while a user is already suspended/banned should not add a strike
      if (isBanned || isCurrentlySuspended) {
        await client.query('COMMIT');
        console.log(`🛡️ [Moderation] User ${userId} is already ${isBanned ? 'banned' : 'suspended'} — strike skipped.`);
        return {
          strikeApplied: false,
          newStrikeCount: user.strike_count || 0,
          suspendedUntil,
          isBanned,
        };
      }

      const currentStrikeCount = parseInt(user.strike_count || 0, 10);
      const newStrikeCount = currentStrikeCount + 1;
      let newSuspendedUntil = null;
      let newIsBanned = false;

      if (newStrikeCount === 1) {
        // 1st strike: 24 hours suspension
        newSuspendedUntil = new Date(now.getTime() + 24 * 60 * 60 * 1000);
      } else if (newStrikeCount === 2) {
        // 2nd strike: 48 hours suspension
        newSuspendedUntil = new Date(now.getTime() + 48 * 60 * 60 * 1000);
      } else if (newStrikeCount >= 3) {
        // 3rd strike: permanent ban
        newIsBanned = true;
      }

      await client.query(
        `UPDATE public.users
         SET strike_count = $1,
             suspended_until = $2,
             is_banned = $3
         WHERE id = $4`,
        [newStrikeCount, newSuspendedUntil, newIsBanned, userId]
      );

      await client.query('COMMIT');
      console.log(`⚠️ [Moderation] Applied strike ${newStrikeCount} to user ${userId}. Suspended until: ${newSuspendedUntil}, Banned: ${newIsBanned}`);

      return {
        strikeApplied: true,
        newStrikeCount,
        suspendedUntil: newSuspendedUntil,
        isBanned: newIsBanned,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`❌ [Moderation] Error applying strike to user ${userId}:`, err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * File a report against a user and trigger strike escalation.
   */
  async fileReport(reporterId, reportedUserId, reason, description = null, messageId = null, conversationId = null) {
    if (reporterId === reportedUserId) {
      throw new Error('Cannot report yourself');
    }

    // Insert into reports table
    const result = await db.query(
      `INSERT INTO public.reports (reporter_id, reported_user_id, reason, description, message_id, conversation_id)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [reporterId, reportedUserId, reason, description, messageId, conversationId]
    );

    // Apply strike escalation per rules
    const strikeResult = await this.applyStrikeIfEligible(reportedUserId);

    return {
      report: result.rows[0],
      moderationResult: strikeResult,
    };
  }
}

module.exports = {
  ModerationService: new ModerationService(),
};
