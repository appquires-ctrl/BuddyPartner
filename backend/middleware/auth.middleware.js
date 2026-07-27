const jwt = require('jsonwebtoken');
const { ModerationService } = require('../modules/moderation/moderation.service');

/**
 * Middleware to authenticate requests using JWT tokens and enforce moderation suspensions/bans.
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
    const secret = process.env.JWT_SECRET || 'loopcall_fallback_jwt_secret_key_change_me_in_prod';
    const decoded = jwt.verify(token, secret);
    req.user = decoded; // Decoded payload contains { id, phone }

    // Moderation status check
    const status = await ModerationService.isUserBlocked(decoded.id);
    if (status.isBanned) {
      return res.status(403).json({
        error: 'ACCOUNT_BANNED',
        message: 'Your account has been permanently banned due to multiple terms of service violations.',
      });
    }

    if (status.isSuspended) {
      return res.status(403).json({
        error: 'ACCOUNT_SUSPENDED',
        message: 'Your account is temporarily suspended.',
        suspended_until: status.suspendedUntil ? status.suspendedUntil.toISOString() : null,
      });
    }

    next();
  } catch (err) {
    console.error('JWT authentication error:', err.message);
    return res.status(401).json({ error: 'Invalid or expired token.' });
  }
}

module.exports = { authMiddleware };

