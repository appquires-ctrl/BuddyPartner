const { appService } = require('../modules/app/app.service');

/**
 * Express middleware to enforce minimum supported app version per platform.
 * Expects headers: "X-App-Platform: android|ios" and "X-App-Version: 1.4.2"
 */
async function enforceMinimumVersion(req, res, next) {
  // Exclude public version check, admin routes, and exact health check endpoints
  const path = req.path;
  const originalUrl = (req.originalUrl || '').split('?')[0];
  if (
    path.startsWith('/app/version-check') ||
    path.startsWith('/admin') ||
    path === '/health' ||
    path === '/api/health' ||
    originalUrl === '/health' ||
    originalUrl === '/api/health'
  ) {
    return next();
  }

  const platformHeader = req.headers['x-app-platform'];
  const versionHeader = req.headers['x-app-version'];

  if (!versionHeader || versionHeader === 'unknown') {
    // Logging-only for rollout window or uninitialized/fallback clients
    return next();
  }

  try {
    const platform = (platformHeader || 'android').toString();
    const version = versionHeader.toString();

    const result = await appService.checkVersion(platform, version);

    if (result.updateRequired) {
      console.warn(
        `🚨 [HTTP 426] Blocked outdated client request. User ID: ${req.user?.id || 'anonymous'}, Version: ${version}, Platform: ${platform}, Path: ${req.originalUrl}`
      );
      return res.status(426).json({
        error: 'upgrade_required',
        minimumSupportedVersion: result.minimumSupportedVersion,
        storeUrl: result.storeUrl,
      });
    }

    next();
  } catch (err) {
    console.error('Error in enforceMinimumVersion middleware:', err.message);
    // Fail-open for request processing if internal version check errors
    next();
  }
}

module.exports = { enforceMinimumVersion };
