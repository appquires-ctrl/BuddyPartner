const express = require('express');
const router = express.Router();
const db = require('../../db');
const { authMiddleware } = require('../../middleware/auth.middleware');

/**
 * Endpoint: POST /api/support/bug-report
 * Allows authenticated or unauthenticated users to file structured bug reports.
 */
router.post('/bug-report', async (req, res) => {
  // Optional auth: extract user if token provided
  let userId = null;
  const authHeader = req.headers.authorization;
  if (authHeader && authHeader.startsWith('Bearer ')) {
    try {
      const jwt = require('jsonwebtoken');
      const token = authHeader.split(' ')[1];
      const secret = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
      const decoded = jwt.verify(token, secret);
      userId = decoded.id;
    } catch (_) {}
  }

  const { category, description, appVersion, platform, deviceInfo } = req.body;

  if (!category || !description || !description.trim()) {
    return res.status(400).json({ error: 'Category and description are required.' });
  }

  try {
    const result = await db.query(
      `INSERT INTO public.bug_reports (user_id, category, description, app_version, platform, device_info)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id, category, description, created_at`,
      [
        userId,
        category.trim(),
        description.trim(),
        appVersion || null,
        platform || null,
        deviceInfo || null,
      ]
    );

    console.log(`🐛 [Support] Bug report #${result.rows[0].id} filed by user ${userId || 'guest'} [${category}]`);
    res.json({
      success: true,
      message: 'Thank you! Your bug report has been submitted.',
      reportId: result.rows[0].id,
    });
  } catch (err) {
    console.error('Error filing bug report:', err.message);
    res.status(500).json({ error: 'Failed to submit bug report. Please try again.' });
  }
});

module.exports = router;
