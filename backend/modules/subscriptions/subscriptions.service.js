const db = require('../../db');
const { cacheService } = require('../../services/cache.service');

const SUBSCRIPTION_PLANS = [
  { id: '1_month', durationDays: 30, basePrice: 199, gstAmount: 36, amountPaid: 235, label: '1 Month Membership' },
  { id: '6_months', durationDays: 180, basePrice: 399, gstAmount: 72, amountPaid: 471, label: '6 Months Membership' },
  { id: '1_year', durationDays: 365, basePrice: 699, gstAmount: 126, amountPaid: 825, label: '1 Year Membership' },
];

class SubscriptionsService {
  /**
   * Check if user has already claimed the one-time ₹9 1-day introductory offer
   * @param {string} userId
   * @returns {Promise<boolean>}
   */
  async hasClaimedIntroOffer(userId) {
    try {
      const userRes = await db.query(
        `SELECT has_claimed_intro_offer FROM public.users WHERE id = $1`,
        [userId]
      );
      if (userRes.rows[0]?.has_claimed_intro_offer) {
        return true;
      }

      // Fallback check against subscriptions history table.
      // NOTE (Tech Debt): (plan_duration_days = 1 OR amount_paid = 9) is a heuristic proxy tied
      // to current pricing (₹9 / 1-day). Revisit if pricing changes or add is_intro_offer column.
      const subRes = await db.query(
        `SELECT id FROM public.subscriptions 
         WHERE user_id = $1 AND (plan_duration_days = 1 OR amount_paid = 9) 
         LIMIT 1`,
        [userId]
      );
      return subRes.rows.length > 0;
    } catch (err) {
      console.error('Error checking hasClaimedIntroOffer:', err.message);
      return false;
    }
  }

  /**
   * Fetch current active subscription for user where expires_at > NOW()
   * @param {string} userId
   * @returns {Promise<Object|null>}
   */
  async getActiveSubscription(userId) {
    try {
      const result = await db.query(
        `SELECT id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at
         FROM public.subscriptions
         WHERE user_id = $1 AND expires_at > NOW()
         ORDER BY expires_at DESC
         LIMIT 1`,
        [userId]
      );
      return result.rows[0] || null;
    } catch (err) {
      console.error('Error in getActiveSubscription:', err.message);
      return null;
    }
  }

  /**
   * Fetch subscription history for user ordered by created_at DESC
   * @param {string} userId
   * @returns {Promise<Array>}
   */
  async getSubscriptionHistory(userId) {
    try {
      const result = await db.query(
        `SELECT id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at
         FROM public.subscriptions
         WHERE user_id = $1
         ORDER BY created_at DESC`,
        [userId]
      );
      return result.rows;
    } catch (err) {
      console.error('Error in getSubscriptionHistory:', err.message);
      return [];
    }
  }

  /**
   * Check if user is currently subscribed
   * @param {string} userId
   * @returns {Promise<boolean>}
   */
  async isSubscribed(userId) {
    const activeSub = await this.getActiveSubscription(userId);
    return activeSub !== null;
  }

  /**
   * Create a new subscription row for user
   * @param {string} userId
   * @param {number} planDurationDays
   * @param {number} amountPaid
   * @param {string} [paymentReference]
   * @returns {Promise<Object>}
   */
  async createSubscription(userId, planDurationDays, amountPaid, paymentReference = null) {
    // Server-side enforcement for 1-day ₹9 introductory offer.
    // NOTE (Tech Debt): (plan_duration_days = 1 OR amount_paid = 9) is a heuristic proxy tied
    // to current pricing (₹9 / 1-day). If pricing changes or a separate 1-day promo is introduced,
    // add an explicit is_intro_offer column to public.subscriptions.
    const isIntroPlan = planDurationDays === 1 || amountPaid === 9;
    if (isIntroPlan) {
      const alreadyClaimed = await this.hasClaimedIntroOffer(userId);
      if (alreadyClaimed) {
        throw new Error('The ₹9 introductory offer can only be claimed once per user.');
      }
    }

    try {
      const expiresAt = new Date(Date.now() + planDurationDays * 24 * 60 * 60 * 1000);
      const result = await db.query(
        `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
         VALUES ($1, $2, $3, NOW(), $4, $5)
         RETURNING id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at`,
        [userId, planDurationDays, amountPaid, expiresAt.toISOString(), paymentReference]
      );

      // Permanently mark intro offer as claimed on user record
      if (isIntroPlan) {
        await db.query(
          `UPDATE public.users SET has_claimed_intro_offer = TRUE WHERE id = $1`,
          [userId]
        );
      }

      // Invalidate Redis cache for user's subscription status
      await cacheService.invalidate(`subscription_status:${userId}`);

      return result.rows[0];
    } catch (err) {
      console.error('Error creating subscription:', err.message);
      throw err;
    }
  }

  /**
   * Immediately expire any active subscriptions for testing (Dev only)
   * @param {string} userId
   */
  async expireSubscription(userId) {
    try {
      await db.query(
        `UPDATE public.subscriptions
         SET expires_at = NOW() - INTERVAL '1 second'
         WHERE user_id = $1 AND expires_at > NOW()`,
        [userId]
      );

      // Invalidate Redis cache for user's subscription status
      await cacheService.invalidate(`subscription_status:${userId}`);

      return true;
    } catch (err) {
      console.error('Error expiring subscription:', err.message);
      throw new Error('Failed to expire subscription');
    }
  }

  /**
   * Combined query: returns active subscription duration/label and intro-offer claimed flag in 1 DB round trip.
   * @param {string} userId
   * @returns {Promise<Object>}
   */
  async getSubscriptionStatus(userId) {
    try {
      const result = await db.query(
        `SELECT 
           u.has_claimed_intro_offer,
           sub.id AS sub_id,
           sub.plan_duration_days,
           sub.amount_paid,
           sub.started_at,
           sub.expires_at,
           sub.payment_reference
         FROM public.users u
         LEFT JOIN LATERAL (
           SELECT id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference
           FROM public.subscriptions
           WHERE user_id = u.id AND expires_at > NOW()
           ORDER BY expires_at DESC
           LIMIT 1
         ) sub ON true
         WHERE u.id = $1`,
        [userId]
      );

      const row = result.rows[0];
      const hasClaimedIntroOffer = row ? (row.has_claimed_intro_offer === true) : false;

      if (!row || !row.sub_id || !row.expires_at) {
        return {
          isSubscribed: false,
          expiresAt: null,
          remainingSeconds: 0,
          remainingHours: 0,
          remainingDays: 0,
          formattedLabel: 'Not Subscribed',
          hasClaimedIntroOffer,
        };
      }

      const now = new Date();
      const expiresAt = new Date(row.expires_at);
      const diffMs = expiresAt.getTime() - now.getTime();

      if (diffMs <= 0) {
        return {
          isSubscribed: false,
          expiresAt: row.expires_at,
          remainingSeconds: 0,
          remainingHours: 0,
          remainingDays: 0,
          formattedLabel: 'Expired',
          hasClaimedIntroOffer,
        };
      }

      const remainingSeconds = Math.floor(diffMs / 1000);
      const remainingHours = Math.ceil(remainingSeconds / 3600);
      const remainingDays = Math.ceil(remainingHours / 24);

      let formattedLabel = '';
      if (remainingHours <= 24) {
        const hrs = Math.max(1, remainingHours);
        formattedLabel = `${hrs} hour${hrs === 1 ? '' : 's'} left`;
      } else {
        const days = Math.max(1, remainingDays);
        formattedLabel = `${days} day${days === 1 ? '' : 's'} left`;
      }

      return {
        isSubscribed: true,
        expiresAt: row.expires_at,
        planDurationDays: row.plan_duration_days,
        remainingSeconds,
        remainingHours,
        remainingDays,
        formattedLabel,
        hasClaimedIntroOffer,
      };
    } catch (err) {
      console.error('Error in getSubscriptionStatus:', err.message);
      return {
        isSubscribed: false,
        expiresAt: null,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Not Subscribed',
        hasClaimedIntroOffer: false,
      };
    }
  }

  /**
   * Return remaining duration & pre-formatted label for app bar
   * @param {string} userId
   */
  async getTimeRemaining(userId) {
    const sub = await this.getActiveSubscription(userId);
    if (!sub) {
      return {
        isSubscribed: false,
        expiresAt: null,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Not Subscribed',
      };
    }

    const now = new Date();
    const expiresAt = new Date(sub.expires_at);
    const diffMs = expiresAt.getTime() - now.getTime();

    if (diffMs <= 0) {
      return {
        isSubscribed: false,
        expiresAt: sub.expires_at,
        remainingSeconds: 0,
        remainingHours: 0,
        remainingDays: 0,
        formattedLabel: 'Expired',
      };
    }

    const remainingSeconds = Math.floor(diffMs / 1000);
    const remainingHours = Math.ceil(remainingSeconds / 3600);
    const remainingDays = Math.ceil(remainingHours / 24);

    let formattedLabel = '';
    if (remainingHours <= 24) {
      const hrs = Math.max(1, remainingHours);
      formattedLabel = `${hrs} hour${hrs === 1 ? '' : 's'} left`;
    } else {
      const days = Math.max(1, remainingDays);
      formattedLabel = `${days} day${days === 1 ? '' : 's'} left`;
    }

    return {
      isSubscribed: true,
      expiresAt: sub.expires_at,
      planDurationDays: sub.plan_duration_days,
      remainingSeconds,
      remainingHours,
      remainingDays,
      formattedLabel,
    };
  }
}

const subscriptionsService = new SubscriptionsService();

module.exports = {
  subscriptionsService,
  SubscriptionsService,
  SUBSCRIPTION_PLANS,
};
