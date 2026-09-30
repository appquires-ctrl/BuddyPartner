const jwt = require('jsonwebtoken');
const redis = require('../redis');
const { ModerationService } = require('../modules/moderation/moderation.service');

/**
 * Middleware to authenticate requests using JWT tokens, enforce single-device policy, and check ban status.
 * Expects header: "Authorization: Bearer <token>"
 */
async function authMiddleware(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Access denied. No token provided.' });
  }

  const token = authHeader.split(' ')[1];
  if (!token) {
    return res.status(401).json({ error: 'Access denied. Invalid token format.' });
  }

  try {
    const secret = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);
    req.user = decoded; // Decoded payload contains { id, phone, sessionId }

    // 1. Hardware device ban check
    const rawDeviceId = req.headers['x-device-id'] || req.headers['device-id'];
    const deviceId = rawDeviceId && typeof rawDeviceId === 'string' ? rawDeviceId.trim() : null;
    if (deviceId) {
      const isDeviceBanned = await redis.sismember('banned_devices_set', deviceId);
      if (isDeviceBanned) {
        return res.status(403).json({
          error: 'DEVICE_BANNED',
          message: 'This device has been permanently restricted from accessing BuddyPartner.',
        });
      }
    }

    // 2. Single-lookup active session & ban check in Redis (1 GET per request instead of 2)
    const rawSession = await redis.get(`user_active_session:${decoded.id}`);
    let activeSessionId = rawSession;
    let isBanned = false;

    if (rawSession) {
      if (rawSession.startsWith('{')) {
        try {
          const parsed = JSON.parse(rawSession);
          activeSessionId = parsed.sessionId;
          isBanned = Boolean(parsed.isBanned);
        } catch (_) {}
      }
    } else {
      // If session key is absent in Redis (e.g. key eviction or pre-login token), check ban from ModerationService
      const status = await ModerationService.isUserBlocked(decoded.id);
      isBanned = status.isBanned;
    }

    if (isBanned) {
      return res.status(403).json({
        error: 'ACCOUNT_BANNED',
        message: 'Your account has been blocked due to multiple reports from other users.',
      });
    }

    if (activeSessionId && (!decoded.sessionId || activeSessionId !== decoded.sessionId)) {
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your account has been logged in on another device. Please log in again.',
      });
    }

    // 3. Debounced user activity & device tracking (5-minute throttle per user)
    const activityKey = `user_activity_debounce:${decoded.id}`;
    const shouldUpdateActivity = await redis.set(activityKey, '1', 'EX', 300, 'NX');
    if (shouldUpdateActivity) {
      const db = require('../db');
      db.query(
        `UPDATE public.users 
         SET last_active_at = NOW(), 
             uninstalled_at = NULL,
             device_id = COALESCE($1, device_id)
         WHERE id = $2`,
        [deviceId, decoded.id]
      ).catch(() => {});
    }

    next();
  } catch (err) {
    console.error('JWT authentication error:', err.message);
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

module.exports = { authMiddleware };
