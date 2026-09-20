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

    // Single-lookup active session & ban check in Redis (1 GET per request instead of 2)
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

    next();
  } catch (err) {
    console.error('JWT authentication error:', err.message);
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

module.exports = { authMiddleware };
