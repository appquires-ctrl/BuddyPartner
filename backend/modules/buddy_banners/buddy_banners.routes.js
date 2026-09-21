const express = require('express');
const jwt = require('jsonwebtoken');
const bannersService = require('./buddy_banners.service');

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

// ── Admin Router (/api/admin/buddy-banners) ──
const adminRouter = express.Router();

adminRouter.get('/', adminAuth, async (_req, res) => {
  try {
    const banners = await bannersService.getAllBanners();
    return res.json({ success: true, banners });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

adminRouter.post('/', adminAuth, async (req, res) => {
  try {
    const { name, imageUrl, priority, startDate, endDate, isActive, sheetConfig, otpReward } = req.body;
    if (!name || !imageUrl) {
      return res.status(400).json({ success: false, message: 'Name and imageUrl are required' });
    }

    const banner = await bannersService.createBanner({
      name,
      imageUrl,
      priority: priority || 1,
      startDate,
      endDate,
      isActive: isActive !== false,
      sheetConfig: sheetConfig || {},
      otpReward: otpReward || {},
    });

    return res.status(201).json({ success: true, banner });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

adminRouter.put('/:id', adminAuth, async (req, res) => {
  try {
    const banner = await bannersService.updateBanner(req.params.id, req.body);
    if (!banner) {
      return res.status(404).json({ success: false, message: 'Banner not found' });
    }
    return res.json({ success: true, banner });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

adminRouter.delete('/:id', adminAuth, async (req, res) => {
  try {
    const deleted = await bannersService.deleteBanner(req.params.id);
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Banner not found' });
    }
    return res.json({ success: true, message: 'Banner deleted successfully' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── Public Router (/api/banners/seasonal) ──
const publicRouter = express.Router();

publicRouter.get('/', async (_req, res) => {
  try {
    const banners = await bannersService.getActiveBanners();
    return res.json({ success: true, banners });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = {
  adminRouter,
  publicRouter,
};
