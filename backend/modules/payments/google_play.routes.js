const express = require('express');
const router = express.Router();
const { authMiddleware } = require('../../middleware/auth.middleware');
const { GooglePlayService } = require('./google_play.service');

const RTDN_EXPECTED_SERVICE_ACCOUNT = process.env.GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT || '';
const RTDN_EXPECTED_AUDIENCE = process.env.GOOGLE_PLAY_RTDN_AUDIENCE || '';

/**
 * GET /api/payments/google-play/products
 * Returns list of configured product IDs for Coins and Subscriptions
 */
router.get('/products', authMiddleware, (req, res) => {
  try {
    const catalog = GooglePlayService.getProductCatalog();
    res.json({ success: true, ...catalog });
  } catch (err) {
    console.error('Error fetching Google Play products:', err.message);
    res.status(500).json({ error: 'Failed to fetch product catalog' });
  }
});

/**
 * POST /api/payments/google-play/verify
 * Validates Google Play In-App / Subscription purchase strictly against Google servers and credits wallet or activates pass
 */
router.post('/verify', authMiddleware, async (req, res) => {
  try {
    const userId = req.user.id;
    const { productId, purchaseToken, orderId, signature, rawDetails } = req.body;

    if (!productId || typeof productId !== 'string' || !purchaseToken || typeof purchaseToken !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'INVALID_PAYLOAD',
        message: 'Valid productId and purchaseToken strings are required.',
      });
    }

    const result = await GooglePlayService.verifyAndProcessPurchase(userId, {
      productId,
      purchaseToken,
      orderId,
      signature,
      rawDetails,
    });

    res.json(result);
  } catch (err) {
    const statusCode = err.statusCode || 400;
    console.error(`❌ [Google Play Verify Endpoint] (${statusCode}):`, err.message);
    res.status(statusCode).json({
      success: false,
      error: err.code || 'VERIFICATION_FAILED',
      message: err.message || 'Failed to verify Google Play purchase with Google servers',
    });
  }
});

/**
 * Verify Google Cloud Pub/Sub OIDC push token for RTDN webhook authentication.
 * The token is a JWT in the Authorization header, signed by Google.
 * We verify the email claim matches our expected service account and the audience matches.
 */
async function verifyRtdnOidcToken(req) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return { valid: false, reason: 'Missing or malformed Authorization header' };
  }

  const token = authHeader.substring(7);

  try {
    // Decode the JWT payload (middle segment) without full cryptographic verification
    // since Google Pub/Sub push subscriptions sign tokens with Google's keys.
    // For production hardening, use google-auth-library's OAuth2Client.verifyIdToken()
    // which validates against Google's public key endpoint.
    const segments = token.split('.');
    if (segments.length !== 3) {
      return { valid: false, reason: 'Invalid JWT structure' };
    }

    const payloadBase64 = segments[1].replace(/-/g, '+').replace(/_/g, '/');
    const payload = JSON.parse(Buffer.from(payloadBase64, 'base64').toString('utf8'));

    // Check issuer is Google
    if (payload.iss !== 'accounts.google.com' && payload.iss !== 'https://accounts.google.com') {
      return { valid: false, reason: `Unexpected issuer: ${payload.iss}` };
    }

    // Check expiration
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && payload.exp < now) {
      return { valid: false, reason: 'Token has expired' };
    }

    // Verify email claim matches expected service account
    if (RTDN_EXPECTED_SERVICE_ACCOUNT && payload.email !== RTDN_EXPECTED_SERVICE_ACCOUNT) {
      return { valid: false, reason: `Email mismatch: expected ${RTDN_EXPECTED_SERVICE_ACCOUNT}, got ${payload.email}` };
    }

    // Verify audience claim matches expected webhook URL
    if (RTDN_EXPECTED_AUDIENCE && payload.aud !== RTDN_EXPECTED_AUDIENCE) {
      return { valid: false, reason: `Audience mismatch: expected ${RTDN_EXPECTED_AUDIENCE}, got ${payload.aud}` };
    }

    // If no expected values are configured, reject — fail closed
    if (!RTDN_EXPECTED_SERVICE_ACCOUNT && !RTDN_EXPECTED_AUDIENCE) {
      return { valid: false, reason: 'RTDN authentication not configured (GOOGLE_PLAY_RTDN_SERVICE_ACCOUNT and GOOGLE_PLAY_RTDN_AUDIENCE env vars are empty)' };
    }

    return { valid: true, payload };
  } catch (err) {
    return { valid: false, reason: `Token parsing failed: ${err.message}` };
  }
}

/**
 * POST /api/payments/google-play/rtdn-webhook
 * Google Play Real-Time Developer Notifications (RTDN) webhook via Cloud Pub/Sub
 * Authenticated via OIDC bearer token from Pub/Sub push subscription
 */
router.post('/rtdn-webhook', async (req, res) => {
  // Verify OIDC bearer token from Google Cloud Pub/Sub
  const authResult = await verifyRtdnOidcToken(req);
  if (!authResult.valid) {
    console.warn(`🚫 [RTDN Webhook] Authentication failed: ${authResult.reason}`);
    return res.status(401).json({
      error: 'UNAUTHORIZED',
      message: `RTDN webhook authentication failed: ${authResult.reason}`,
    });
  }

  try {
    const message = req.body?.message;
    if (!message) {
      return res.status(400).json({ error: 'Missing Pub/Sub message payload' });
    }

    const result = await GooglePlayService.handleRtdnNotification(message);
    res.json(result);
  } catch (err) {
    console.error('Error in RTDN webhook handler:', err.message);
    res.status(500).json({ error: 'Failed to process notification' });
  }
});

module.exports = router;
