const db = require('../../db');

const SUBSCRIPTION_PLANS = [
  { id: '1_day', durationDays: 1, amountPaid: 9, label: '1 Day' },
  { id: '4_days', durationDays: 4, amountPaid: 30, label: '4 Days' },
  { id: '7_days', durationDays: 7, amountPaid: 50, label: '7 Days' },
  { id: '1_month', durationDays: 30, amountPaid: 250, label: '1 Month (30 Days)' },
  { id: '1_year', durationDays: 365, amountPaid: 2500, label: '1 Year (365 Days)' },
];

class SubscriptionsService {
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
    try {
      const expiresAt = new Date(Date.now() + planDurationDays * 24 * 60 * 60 * 1000);
      const result = await db.query(
        `INSERT INTO public.subscriptions (user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference)
         VALUES ($1, $2, $3, NOW(), $4, $5)
         RETURNING id, user_id, plan_duration_days, amount_paid, started_at, expires_at, payment_reference, created_at`,
        [userId, planDurationDays, amountPaid, expiresAt.toISOString(), paymentReference]
      );
      return result.rows[0];
    } catch (err) {
      console.error('Error creating subscription:', err.message);
      throw new Error('Failed to create subscription record');
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
    const remainingHours = Math.floor(remainingSeconds / 3600);
    const remainingDays = Math.floor(remainingHours / 24);

    let formattedLabel = '';
    if (remainingHours < 24) {
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
