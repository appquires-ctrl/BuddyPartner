const express = require('express');
const jwt = require('jsonwebtoken');
const { PromoCodesService } = require('./promo_codes.service');
const { authMiddleware } = require('../../middleware/auth.middleware');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

function adminAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Unauthorized: missing token' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (!decoded || !decoded.isAdmin) {
      return res.status(403).json({ success: false, message: 'Forbidden: admin access required' });
    }
    req.admin = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ success: false, message: 'Unauthorized: invalid token' });
  }
}

// ── Admin Router (/api/admin/promo-codes) ───────────────────────────────────
const adminRouter = express.Router();

adminRouter.get('/', adminAuth, async (req, res) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 50;
    const search = req.query.search || '';

    const data = await PromoCodesService.listPromoCodes({ page, limit, search });
    return res.json({ success: true, ...data });
  } catch (err) {
    console.error('Error fetching admin promo codes:', err.message);
    return res.status(500).json({ success: false, message: err.message || 'Failed to fetch promo codes' });
  }
});

adminRouter.post('/', adminAuth, async (req, res) => {
  try {
    const promo = await PromoCodesService.createPromoCode(req.body);
    return res.json({ success: true, promo, message: 'Promo code created successfully' });
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Failed to create promo code' });
  }
});

adminRouter.patch('/:id', adminAuth, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    const promo = await PromoCodesService.updatePromoCode(id, req.body);
    return res.json({ success: true, promo, message: 'Promo code updated successfully' });
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Failed to update promo code' });
  }
});

adminRouter.delete('/:id', adminAuth, async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    const result = await PromoCodesService.deletePromoCode(id);
    return res.json(result);
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Failed to delete promo code' });
  }
});

// ── User / Mobile Router (/api/subscriptions or /api/promos) ────────────────
const userRouter = express.Router();

// Validate code for checkout (subscriptions or coin packs)
userRouter.post('/validate-promo', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const { code, productId } = req.body;
    const result = await PromoCodesService.validateSubscriptionPromo(userId, { code, productId });
    return res.json({ success: true, ...result });
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Invalid promo code' });
  }
});

// Validate code for subscription purchase checkout (backward-compatibility)
userRouter.post('/validate-subscription-promo', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const { code, productId } = req.body;
    const result = await PromoCodesService.validateSubscriptionPromo(userId, { code, productId });
    return res.json({ success: true, ...result });
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Invalid promo code' });
  }
});

// Redeem direct rewards (free coins or VIP pass)
userRouter.post('/redeem-direct-promo', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const { code } = req.body;
    const ipAddress = req.headers['x-forwarded-for'] || req.socket.remoteAddress;
    const result = await PromoCodesService.redeemDirectPromo(userId, { code, ipAddress });
    return res.json(result);
  } catch (err) {
    const statusCode = err.statusCode || 400;
    return res.status(statusCode).json({ success: false, message: err.message || 'Failed to redeem promo code' });
  }
});

module.exports = {
  adminRouter,
  userRouter,
};
