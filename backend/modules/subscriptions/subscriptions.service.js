const db = require('../../db');

const SUBSCRIPTION_PLANS = [
  { id: '1_day', durationDays: 1, amountPaid: 9, label: '1 Day Pass' },
  { id: '7_days', durationDays: 7, amountPaid: 59, label: '1 Week Pass' },
  { id: '1_month', durationDays: 30, amountPaid: 199, label: '1 Month Pass' },
  { id: '1_year', durationDays: 365, amountPaid: 1999, label: '1 Year VIP' },
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

      // Fallback check against subscriptions history table
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
    // Unlimited Access Mode: Return active VIP plan for all users (No payment required)
    return {
      id: 'unlimited_early_access',
      user_id: userId,
      plan_duration_days: 365,
      amount_paid: 0,
      started_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString(),
      payment_reference: 'EARLY_ACCESS_FREE_VIP',
      created_at: new Date().toISOString()
    };
    /* ORIGINAL LOGIC (PRESERVED):
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
    */
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
    // Server-side enforcement for 1-day ₹9 introductory offer
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
      return true;
    } catch (err) {
      console.error('Error expiring subscription:', err.message);
      throw new Error('Failed to expire subscription');
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
