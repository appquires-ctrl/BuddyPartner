const express = require('express');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { subscriptionsService, SUBSCRIPTION_PLANS } = require('./subscriptions.service');

const router = express.Router();

// ── GET /api/subscriptions/status ──────────────────────────────────────────
// Fetch current subscription status and countdown payload
router.get('/status', authMiddleware, async (req, res) => {
  try {
    const timeInfo = await subscriptionsService.getTimeRemaining(req.user.id);
    res.json({
      ...timeInfo,
      plans: SUBSCRIPTION_PLANS,
    });
  } catch (err) {
    console.error('Error in GET /subscriptions/status:', err.message);
    res.status(500).json({ error: 'Failed to fetch subscription status' });
  }
});

// ── GET /api/subscriptions/history ─────────────────────────────────────────
// Fetch subscription purchase history for current user
router.get('/history', authMiddleware, async (req, res) => {
  try {
    const history = await subscriptionsService.getSubscriptionHistory(req.user.id);
    res.json({ subscriptions: history });
  } catch (err) {
    console.error('Error in GET /subscriptions/history:', err.message);
    res.status(500).json({ error: 'Failed to fetch subscription history' });
  }
});

// ── POST /api/subscriptions/dev-start & POST /api/subscriptions/subscribe ─────────
// Start/activate a subscription for a user
const handleStartSubscription = async (req, res) => {
  try {
    const { planDurationDays, amountPaid, planId } = req.body;

    let duration = planDurationDays;
    let amount = amountPaid;

    if (planId) {
      const plan = SUBSCRIPTION_PLANS.find((p) => p.id === planId);
      if (plan) {
        duration = plan.durationDays;
        amount = plan.amountPaid;
      }
    }

    if (!duration || typeof duration !== 'number' || duration <= 0) {
      return res.status(400).json({ error: 'Valid planDurationDays is required' });
    }

    const subscription = await subscriptionsService.createSubscription(
      req.user.id,
      duration,
      amount || 0,
      'DEV_GATEWAY_REF'
    );

    const status = await subscriptionsService.getTimeRemaining(req.user.id);

    res.json({
      success: true,
      subscription,
      status,
    });
  } catch (err) {
    console.error('Error in starting subscription:', err.message);
    res.status(500).json({ error: err.message || 'Failed to start subscription' });
  }
};

router.post('/dev-start', authMiddleware, handleStartSubscription);
router.post('/subscribe', authMiddleware, handleStartSubscription);

// ── POST /api/subscriptions/dev-expire ─────────────────────────────────────
// Expire active subscription for testing
router.post('/dev-expire', authMiddleware, async (req, res) => {
  try {
    await subscriptionsService.expireSubscription(req.user.id);
    const status = await subscriptionsService.getTimeRemaining(req.user.id);

    res.json({
      success: true,
      message: 'Subscription expired for dev testing',
      status,
    });
  } catch (err) {
    console.error('Error in POST /subscriptions/dev-expire:', err.message);
    res.status(500).json({ error: err.message || 'Failed to expire dev subscription' });
  }
});

module.exports = router;
