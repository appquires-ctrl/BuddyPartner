const express = require('express');
const { appService } = require('./app.service');

const router = express.Router();

// ── GET /api/app/version-check ──────────────────────────────────────────────
// Public endpoint callable before auth
router.get('/version-check', async (req, res) => {
  try {
    const platform = (req.query.platform || req.headers['x-app-platform'] || 'android').toString();
    const currentVersion = (req.query.currentVersion || req.headers['x-app-version'] || '1.0.0').toString();

    const result = await appService.checkVersion(platform, currentVersion);
    res.json(result);
  } catch (err) {
    console.error('Error in GET /api/app/version-check:', err.message);
    res.status(500).json({ error: 'Failed to perform version check' });
  }
});

module.exports = router;
