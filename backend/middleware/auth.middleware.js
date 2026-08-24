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

    // Single-device active session check in Redis (In-Memory ~0.5ms lookup)
    if (decoded.sessionId) {
      const activeSessionId = await redis.get(`user_active_session:${decoded.id}`);
      if (activeSessionId && activeSessionId !== decoded.sessionId) {
        return res.status(401).json({
          error: 'SESSION_TERMINATED',
          message: 'Your account has been logged in on another device. Please log in again.',
        });
      }
    }

    // Moderation status check — check ONLY isBanned
    const status = await ModerationService.isUserBlocked(decoded.id);
    if (status.isBanned) {
      return res.status(403).json({
        error: 'ACCOUNT_BANNED',
        message: 'Your account has been blocked due to multiple reports from other users.',
      });
    }

    next();
  } catch (err) {
    console.error('JWT authentication error:', err.message);
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

module.exports = { authMiddleware };
