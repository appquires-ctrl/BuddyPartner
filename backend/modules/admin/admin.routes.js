const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const adminService = require('./admin.service');

const JWT_SECRET = process.env.JWT_SECRET || 'loopcall_fallback_jwt_secret_key_change_me_in_prod';

// Admin JWT Verification Middleware
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

// ── 1. Admin Login ──────────────────────────────────────────────────────────
router.post('/login', async (req, res) => {
  try {
    const { password } = req.body;
    if (!password) {
      return res.status(400).json({ success: false, message: 'Password is required' });
    }

    const isValid = await adminService.verifyPassword(password);
    if (!isValid) {
      return res.status(401).json({ success: false, message: 'Wrong password' });
    }

    // Issue token valid for 24h
    const token = jwt.sign({ isAdmin: true, role: 'admin' }, JWT_SECRET, { expiresIn: '24h' });

    return res.json({
      success: true,
      message: 'Login successful',
      token,
    });
  } catch (err) {
    console.error('Error during admin login:', err);
    return res.status(500).json({ success: false, message: 'Server error during login' });
  }
});

// ── 2. Dashboard Stats ──────────────────────────────────────────────────────
router.get('/stats', adminAuth, async (_req, res) => {
  try {
    const stats = await adminService.getDashboardStats();
    return res.json({ success: true, stats });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── 3. User Management ──────────────────────────────────────────────────────
router.get('/users', adminAuth, async (req, res) => {
  try {
    const { search = '', gender = 'all', isBanned = 'all', page = 1, limit = 20 } = req.query;
    const data = await adminService.getUsers({
      search,
      gender,
      isBanned,
      page: Number(page),
      limit: Number(limit),
    });
    return res.json({ success: true, ...data });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.get('/users/:id/detail', adminAuth, async (req, res) => {
  try {
    const userDetail = await adminService.getUserDetail(req.params.id);
    if (!userDetail) {
      return res.status(404).json({ success: false, message: 'User not found' });
    }
    return res.json({ success: true, user: userDetail });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/users/:id/ban', adminAuth, async (req, res) => {
  try {
    const updated = await adminService.setBanStatus(req.params.id, true);
    return res.json({ success: true, message: 'User banned successfully', user: updated });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.post('/users/:id/unban', adminAuth, async (req, res) => {
  try {
    const updated = await adminService.setBanStatus(req.params.id, false);
    return res.json({ success: true, message: 'User unbanned successfully', user: updated });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── 4. Reports Queue ────────────────────────────────────────────────────────
router.get('/reports', adminAuth, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const data = await adminService.getReports({ page: Number(page), limit: Number(limit) });
    return res.json({ success: true, ...data });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── 5. Withdrawal Requests ──────────────────────────────────────────────────
router.get('/withdrawals', adminAuth, async (req, res) => {
  try {
    const { status = 'all', page = 1, limit = 20 } = req.query;
    const data = await adminService.getWithdrawals({
      status,
      page: Number(page),
      limit: Number(limit),
    });
    return res.json({ success: true, ...data });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

router.patch('/withdrawals/:id/status', adminAuth, async (req, res) => {
  try {
    const { status } = req.body;
    if (!status) {
      return res.status(400).json({ success: false, message: 'Status is required' });
    }
    const updated = await adminService.updateWithdrawalStatus(req.params.id, status);
    return res.json({ success: true, message: 'Withdrawal status updated', withdrawal: updated });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── 6. Transactions Log ─────────────────────────────────────────────────────
router.get('/transactions', adminAuth, async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const data = await adminService.getTransactions({ page: Number(page), limit: Number(limit) });
    return res.json({ success: true, ...data });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
