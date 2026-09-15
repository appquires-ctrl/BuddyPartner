const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../../db');
const redis = require('../../redis');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { cacheService } = require('../../services/cache.service');
const { usernameCheckLimiter, userSearchLimiter } = require('../../middleware/rate_limit.middleware');
const { generateOTP, sanitizePhoneInputs, sendWhatsAppOtp } = require('./otpService');

const RESERVED_USERNAMES = new Set([
  'admin', 'administrator', 'support', 'help', 'buddypartner', 
  'official', 'null', 'undefined', 'system', 'root', 'moderator',
  'api', 'auth', 'user', 'users', 'me'
]);

/**
 * Validates username per Instagram-style format and reserved words
 * - 3–20 characters
 * - Letters, numbers, underscores, periods ([a-z0-9._])
 * - Must start and end with alphanumeric
 * - No consecutive periods or underscores
 */
function validateUsername(username) {
  if (!username || typeof username !== 'string') {
    return { valid: false, message: 'Username is required.' };
  }
  const normalized = username.trim().toLowerCase();
  if (normalized.length < 3 || normalized.length > 20) {
    return { valid: false, message: 'Username must be between 3 and 20 characters.' };
  }
  if (!/^[a-z0-9]/.test(normalized)) {
    return { valid: false, message: 'Username must start with a letter or number.' };
  }
  if (!/[a-z0-9]$/.test(normalized)) {
    return { valid: false, message: 'Username must end with a letter or number.' };
  }
  if (!/^[a-z0-9._]+$/.test(normalized)) {
    return { valid: false, message: 'Username can only contain letters, numbers, . and _' };
  }
  if (/[._]{2,}/.test(normalized)) {
    return { valid: false, message: 'Username cannot contain consecutive dots or underscores.' };
  }
  if (RESERVED_USERNAMES.has(normalized)) {
    return { valid: false, isReserved: true, message: 'it already exist fix it' };
  }
  return { valid: true, normalized };
}

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'buddypartner_fallback_jwt_refresh_secret_key';

// Rate limit constants
const OTP_TTL_SECONDS = 300; // 5 minutes
const SEND_LIMIT_MAX = 3; // Max 3 sends per 10 min
const SEND_LIMIT_WINDOW = 600; // 10 minutes
const VERIFY_ATTEMPTS_MAX = 5; // Max 5 wrong attempts before lockout
const VERIFY_LOCKOUT_WINDOW = 600; // 10 minutes lockout

/**
 * Endpoint: GET /api/auth/username-available?user_name=<value>
 * Checks if a requested username is valid and available.
 * Rate limited to 20 requests per minute per IP.
 */
router.get('/username-available', usernameCheckLimiter, async (req, res) => {
  const rawUserName = req.query.user_name || req.query.username;
  if (!rawUserName) {
    return res.status(400).json({ available: false, error: 'INVALID_FORMAT', message: 'Username is required.' });
  }

  const validation = validateUsername(rawUserName);
  if (!validation.valid) {
    if (validation.isReserved) {
      return res.json({ available: false, message: 'it already exist fix it' });
    }
    return res.status(400).json({ available: false, error: 'INVALID_FORMAT', message: validation.message });
  }

  try {
    const checkRes = await db.query(
      `SELECT 1 FROM public.users WHERE LOWER(user_name) = $1 LIMIT 1`,
      [validation.normalized]
    );

    if (checkRes.rows.length > 0) {
      return res.json({ available: false, message: 'it already exist fix it' });
    }

    return res.json({ available: true });
  } catch (err) {
    console.error('Error checking username availability:', err.message);
    return res.status(500).json({ available: false, error: 'SERVER_ERROR', message: 'Unable to check username availability.' });
  }
});

/**
 * Endpoint: GET /api/users/search?query=<partial_or_full_user_name>&limit=20
 * (Also accessible at /api/auth/search?query=...)
 * Auth-protected: requires valid JWT.
 * Rate limited to 30 requests per minute per authenticated user (keyed by user.id).
 * B-tree prefix search against idx_users_user_name_lower.
 * Excludes requesting user and banned users.
 * Minimal public fields only (never sensitive details like phone/email).
 * Cached in Redis with a 15-second TTL.
 */
router.get('/search', authMiddleware, userSearchLimiter, async (req, res) => {
  // Canonical endpoint is GET /api/users/search. Since authRoutes is mounted at both
  // /api/auth and /api/users in server.js, explicitly restrict /search to /api/users
  // to avoid route duplication and confusion.
  if (req.baseUrl !== '/api/users') {
    return res.status(404).json({
      success: false,
      error: 'NOT_FOUND',
      message: 'Canonical search route is GET /api/users/search',
    });
  }

  const currentUserId = req.user.id;
  const rawQuery = (req.query.query || req.query.q || req.query.username || req.query.user_name || '').toString().trim();

  if (!rawQuery || rawQuery.length < 2) {
    return res.json({
      success: true,
      users: [],
    });
  }

  // Sanitize query: strip leading '@' if entered by user, normalize to lowercase
  const cleanQuery = rawQuery.startsWith('@') ? rawQuery.slice(1).toLowerCase() : rawQuery.toLowerCase();
  if (cleanQuery.length < 2) {
    return res.json({
      success: true,
      users: [],
    });
  }

  // Hard-cap server-side limit to prevent large payload dumps
  const parsedLimit = parseInt(req.query.limit, 10);
  const limit = (!isNaN(parsedLimit) && parsedLimit > 0) ? Math.min(parsedLimit, 25) : 20;

  // Cache is keyed by user ID to guarantee requesting user is never included from a shared cache
  const cacheKey = `search:users:${currentUserId}:${cleanQuery}:${limit}`;

  try {
    const cachedUsers = await cacheService.getOrSet(cacheKey, 15, async () => {
      const searchRes = await db.query(
        `SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller
         FROM public.users
         WHERE LOWER(user_name) LIKE LOWER($1) || '%'
           AND (is_banned IS NOT TRUE)
           AND id != $2::UUID
         ORDER BY LOWER(user_name) ASC
         LIMIT $3`,
        [cleanQuery, currentUserId, limit]
      );

      return searchRes.rows.map((row) => ({
        id: row.id,
        fullName: row.full_name || 'User',
        userName: row.user_name || null,
        avatarSeed: row.avatar_seed || null,
        avatarStyle: row.avatar_style || 'avataaars',
        gender: row.gender || null,
        isTelecaller: row.is_telecaller || false,
        isOnline: false,
        isFavorite: false,
      }));
    });

    return res.json({
      success: true,
      query: cleanQuery,
      users: cachedUsers || [],
    });
  } catch (err) {
    console.error('❌ Error executing user search:', err.message);
    return res.status(500).json({
      success: false,
      error: 'SERVER_ERROR',
      message: 'An error occurred while searching for users.',
      users: [],
    });
  }
});

// Google Play Review / Demo Test Account credentials
const DEMO_TEST_COUNTRY_CODE = process.env.DEMO_TEST_COUNTRY_CODE || '91';
const DEMO_TEST_MOBILES = new Set(['9999999999', '8888888888', '7777777777']);
const DEMO_TEST_OTP = process.env.DEMO_TEST_OTP || '123456';

/**
 * Endpoint: POST /api/auth/otp/send
 * Validates country_code and mobile, enforces Redis rate limits, generates bcrypt-hashed OTP,
 * stores it in Redis with 300s TTL, and sends it via Authkey WhatsApp OTP service.
 */
router.post('/otp/send', async (req, res) => {
  const { country_code, mobile } = req.body;

  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);

  if (!cleanCountryCode || !cleanMobile || cleanMobile.length < 7 || cleanMobile.length > 15) {
    return res.status(400).json({ error: 'Valid mobile number and country code are required.' });
  }

  try {
    // Check if this is a Google Play Reviewer / Demo Test Account
    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);

    if (isTestAccount) {
      // Demo test account: Store fixed OTP hash in Redis, skip external WhatsApp API call
      const hashedOtp = await bcrypt.hash(DEMO_TEST_OTP, 10);
      const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
      await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

      console.log(`🧪 [TEST ACCOUNT] OTP generated for Google Play review (+${cleanCountryCode}${cleanMobile}): ${DEMO_TEST_OTP}`);

      return res.json({
        success: true,
        message: 'Verification code sent.',
      });
    }

    // 1. Enforce send rate limit: max 3 sends per 10 minutes per mobile
    const sendCountKey = `otp_send_count:${cleanMobile}`;
    const sendCount = await redis.incr(sendCountKey);

    if (sendCount === 1) {
      await redis.expire(sendCountKey, SEND_LIMIT_WINDOW);
    } else if (sendCount > SEND_LIMIT_MAX) {
      return res.status(429).json({ error: 'Too many OTP requests. Please wait 10 minutes before trying again.' });
    }

    // 2. Generate random 6-digit OTP
    const otp = generateOTP();

    // 3. Hash OTP with bcrypt
    const hashedOtp = await bcrypt.hash(otp, 10);

    // 4. Store hashed OTP in Redis: otp:{country_code}{mobile} -> TTL 300s
    const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
    await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

    // 5. Send OTP via Authkey WhatsApp API
    const sendResult = await sendWhatsAppOtp(cleanCountryCode, cleanMobile, otp);

    if (!sendResult.success) {
      return res.status(500).json({ error: sendResult.message || 'Failed to send WhatsApp verification code.' });
    }

    // Generic success response — does not reveal whether the user is registered or new
    res.json({
      success: true,
      message: 'Verification code sent via WhatsApp.',
    });
  } catch (err) {
    console.error('Error in /auth/otp/send:', err.message);
    res.status(500).json({ error: 'Internal server error processing OTP request.' });
  }
});

/**
 * Endpoint: POST /api/auth/otp/verify
 * Verifies submitted OTP against bcrypt hash in Redis.
 * On success:
 * - Provisions user + wallet atomically if new
 * - Issues Access JWT (1d expiry) and rotating Refresh Token (stored in Redis with 30d TTL)
 * - Deletes Redis OTP key immediately
 */
router.post('/otp/verify', async (req, res) => {
  const { country_code, mobile, otp } = req.body;

  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);
  const cleanOtp = (otp || '').toString().trim();

  if (!cleanCountryCode || !cleanMobile || !cleanOtp || cleanOtp.length !== 6) {
    return res.status(400).json({ error: 'Valid country code, mobile number, and 6-digit verification code are required.' });
  }

  try {
    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
    const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
    const attemptsKey = `otp_verify_attempts:${cleanMobile}`;

    if (isTestAccount) {
      // Test account bypasses rate limits and matches static OTP
      if (cleanOtp !== DEMO_TEST_OTP) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    } else {
      // 1. Check attempt lockout counter
      const attempts = await redis.get(attemptsKey);
      if (attempts && parseInt(attempts, 10) >= VERIFY_ATTEMPTS_MAX) {
        return res.status(429).json({ error: 'Too many failed verification attempts. Please try again in 10 minutes.' });
      }

      // 2. Fetch stored hashed OTP from Redis
      const storedHash = await redis.get(otpRedisKey);

      if (!storedHash) {
        // Increment attempt counter
        const currentAttempts = await redis.incr(attemptsKey);
        if (currentAttempts === 1) await redis.expire(attemptsKey, VERIFY_LOCKOUT_WINDOW);
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }

      // 3. Compare submitted OTP against hash
      const isMatch = await bcrypt.compare(cleanOtp, storedHash);

      if (!isMatch) {
        const currentAttempts = await redis.incr(attemptsKey);
        if (currentAttempts === 1) await redis.expire(attemptsKey, VERIFY_LOCKOUT_WINDOW);
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    }

    // 4. Verification successful! Delete OTP key & clear attempt counter
    await redis.del(otpRedisKey);
    await redis.del(attemptsKey);

    // Form legacy phone format e.g. "+919876543210"
    const fullPhoneNumber = `+${cleanCountryCode}${cleanMobile}`;

    // 5. Query user or run atomic transaction to create user + wallet
    let userResult = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.dob, u.gender, u.language, 
              u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, 
              u.country, u.state, u.city, u.latitude, u.longitude, 
              w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE (u.country_code = $1 AND u.mobile = $2) OR u.phone_number = $3`,
      [cleanCountryCode, cleanMobile, fullPhoneNumber]
    );

    let user;

    if (userResult.rows.length === 0) {
      // Atomic Transaction: Create user + wallet
      const client = await db.pool.connect();
      try {
        await client.query('BEGIN');

        let insertUserRes;
        if (isTestAccount) {
          // Pre-populate reviewer profile so reviewer directly accesses app features
          insertUserRes = await client.query(
            `INSERT INTO public.users (
               country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, country, state, city
             ) 
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) 
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude`,
            [
              cleanCountryCode, cleanMobile, fullPhoneNumber,
              'Google Reviewer', 'googlereviewer', '1998-01-01', 'Male', 'English', 'male_2f', 'avataaars', 'India', 'Delhi', 'New Delhi'
            ]
          );
        } else {
          insertUserRes = await client.query(
            `INSERT INTO public.users (country_code, mobile, phone_number, avatar_seed, avatar_style) 
             VALUES ($1, $2, $3, 'male_2f', 'avataaars') 
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude`,
            [cleanCountryCode, cleanMobile, fullPhoneNumber]
          );
        }
        user = insertUserRes.rows[0];

        // Provision wallet (preloaded with 100 spendable coins for reviewer to test calls, 0 for standard users)
        const initialBalance = isTestAccount ? 100 : 0;
        await client.query(
          `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance) 
           VALUES ($1, $2, 0) 
           ON CONFLICT (user_id) DO UPDATE SET spendable_balance = GREATEST(wallets.spendable_balance, $2)`,
          [user.id, initialBalance]
        );

        await client.query('COMMIT');
        console.log(`🎉 New user created: ID ${user.id}, mobile +${cleanCountryCode}${cleanMobile}${isTestAccount ? ' [TEST ACCOUNT]' : ''}`);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } else {
      user = userResult.rows[0];

      // Ensure existing test reviewer account has complete profile and active balance
      if (isTestAccount) {
        if (!user.full_name) {
          await db.query(
            `UPDATE public.users SET full_name = $1, gender = $2, dob = $3, language = $4 WHERE id = $5`,
            ['Google Reviewer', 'Male', '1998-01-01', 'English', user.id]
          );
          user.full_name = 'Google Reviewer';
          user.gender = 'Male';
          user.dob = new Date('1998-01-01');
          user.language = 'English';
        }
        if ((parseFloat(user.balance) || 0) < 50) {
          await db.query(
            `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance) VALUES ($1, 100, 0) ON CONFLICT (user_id) DO UPDATE SET spendable_balance = 100`,
            [user.id]
          );
          user.spendable_balance = 100;
          user.balance = 100;
        }
      }

      // Backfill country_code / mobile if missing on existing record
      if (!user.country_code || !user.mobile) {
        await db.query(
          `UPDATE public.users SET country_code = $1, mobile = $2 WHERE id = $3`,
          [cleanCountryCode, cleanMobile, user.id]
        );
      }
    }

    // 6. Enforce Single-Device Policy: Invalidate previous sessions & generate new Session ID
    const sessionId = crypto.randomUUID();
    const io = req.app.get('io');
    if (io) {
      io.to(user.id).emit('session_terminated', {
        reason: 'Your account was logged in from another device.',
      });
      setTimeout(() => {
        try {
          io.in(user.id).disconnectSockets(true);
        } catch (_) {}
      }, 500);
    }

    // Invalidate all previous refresh tokens for this user in Redis
    try {
      const oldRefreshKeys = await redis.keys(`refresh:${user.id}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    // Store active session in Redis (no TTL or long TTL, valid until overwritten/logged out)
    await redis.set(`user_active_session:${user.id}`, sessionId);

    // 7. Generate Tokens
    const jti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
      sessionId,
    };

    // Short-lived Access Token (1 day)
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });

    // Refresh Token (30 days) with jti
    const refreshToken = jwt.sign({ id: user.id, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store Refresh Token status in Redis: refresh:{userId}:{jti} -> TTL 30 days (2,592,000s)
    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);

    const isProfileComplete = !!(user.full_name && user.full_name.trim().length > 0);

    res.json({
      success: true,
      token,
      refreshToken,
      isProfileComplete,
      user: {
        id: user.id,
        countryCode: user.country_code || cleanCountryCode,
        mobile: user.mobile || cleanMobile,
        phoneNumber: user.phone_number || fullPhoneNumber,
        fullName: user.full_name || '',
        userName: user.user_name || null,
        dob: user.dob ? user.dob.toISOString() : null,
        gender: user.gender || 'Male',
        language: user.language || 'English',
        avatarSeed: user.avatar_seed || null,
        avatarStyle: user.avatar_style || 'avataaars',
        isTelecaller: user.is_telecaller || false,
        hasClaimedIntroOffer: user.has_claimed_intro_offer || false,
        country: user.country || null,
        state: user.state || null,
        city: user.city || null,
        latitude: user.latitude ? parseFloat(user.latitude) : null,
        longitude: user.longitude ? parseFloat(user.longitude) : null,
        balance: user.balance ? parseInt(user.balance, 10) : 0,
      },
    });
  } catch (err) {
    console.error('Error in /auth/otp/verify:', err.message);
    res.status(500).json({ error: 'Internal server error during verification.' });
  }
});

/**
 * Endpoint: POST /api/auth/refresh
 * Rotates the refresh token: verifies signature & Redis presence, invalidates old token, and issues new Access + Refresh tokens.
 */
router.post('/refresh', async (req, res) => {
  const { refreshToken } = req.body;

  if (!refreshToken || typeof refreshToken !== 'string') {
    return res.status(400).json({ error: 'Refresh token is required.' });
  }

  try {
    const decoded = jwt.verify(refreshToken, JWT_REFRESH_SECRET);
    const { id, jti, sessionId } = decoded;

    if (!id || !jti) {
      return res.status(401).json({ error: 'Invalid refresh token structure.' });
    }

    // Check Redis for active refresh token key
    const redisKey = `refresh:${id}:${jti}`;
    const exists = await redis.get(redisKey);

    if (!exists) {
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your session has been terminated because your account was logged in on another device.',
      });
    }

    // Check active session ID in Redis to ensure this refresh token belongs to current active device
    const activeSessionId = await redis.get(`user_active_session:${id}`);
    if (activeSessionId && (!sessionId || activeSessionId !== sessionId)) {
      await redis.del(redisKey);
      return res.status(401).json({
        error: 'SESSION_TERMINATED',
        message: 'Your account has been logged in on another device. Please log in again.',
      });
    }

    // Invalidate old refresh token key (rotation)
    await redis.del(redisKey);

    // Fetch user details
    const userRes = await db.query(
      `SELECT id, country_code, mobile, phone_number, full_name FROM public.users WHERE id = $1`,
      [id]
    );

    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const user = userRes.rows[0];

    const currentSessionId = activeSessionId || sessionId || crypto.randomUUID();
    if (!activeSessionId) {
      await redis.set(`user_active_session:${id}`, currentSessionId);
    }

    // Issue new tokens
    const newJti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: user.phone_number || `+${user.country_code}${user.mobile}`,
      countryCode: user.country_code,
      mobile: user.mobile,
      sessionId: currentSessionId,
    };

    const newAccessToken = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const newRefreshToken = jwt.sign({ id: user.id, jti: newJti, sessionId: currentSessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store new refresh token in Redis
    await redis.set(`refresh:${user.id}:${newJti}`, '1', 'EX', 30 * 24 * 60 * 60);

    res.json({
      success: true,
      token: newAccessToken,
      refreshToken: newRefreshToken,
    });
  } catch (err) {
    console.error('Error refreshing token:', err.message);
    res.status(401).json({ error: 'Invalid or expired refresh token.' });
  }
});

/**
 * Endpoint: POST /api/auth/logout
 * Invalidates the session by deleting the refresh token from Redis,
 * deleting the active session key, evicting all queues, terminating active calls,
 * marking presence offline, and disconnecting any live sockets for this user.
 */
router.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;
  const io = req.app.get('io');
  let userId = null;

  if (refreshToken && typeof refreshToken === 'string') {
    try {
      const decoded = jwt.decode(refreshToken);
      if (decoded && decoded.id) {
        userId = decoded.id;
        if (decoded.jti) {
          await redis.del(`refresh:${decoded.id}:${decoded.jti}`);
        }
      }
    } catch (_) {
      // Ignore decode failures on logout
    }
  }

  if (!userId && req.headers.authorization) {
    try {
      const authHeader = req.headers.authorization;
      if (authHeader.startsWith('Bearer ')) {
        const token = authHeader.substring(7);
        const decoded = jwt.decode(token);
        if (decoded && decoded.id) {
          userId = decoded.id;
        }
      }
    } catch (_) {}
  }

  if (userId) {
    try {
      // Delete active session key from Redis
      await redis.del(`user_active_session:${userId}`);

      const { cleanupUserMatchmaking } = require('../matchmaking/matchmaking.socket');
      const { cleanupUserInstantConnect } = require('../instant_connect/instant_connect.socket');
      const { PresenceService } = require('../presence/presence.service');

      await Promise.all([
        cleanupUserMatchmaking(io, redis, userId),
        cleanupUserInstantConnect(io, redis, userId),
        PresenceService.setPresence(redis, io, userId, false),
      ]);
      console.log(`🔒 [Auth] Complete server-side logout & socket purge performed for user ${userId}`);
    } catch (cleanupErr) {
      console.error(`Error during server logout cleanup for user ${userId}:`, cleanupErr.message);
    }
  }

  res.json({ success: true, message: 'Logged out successfully.' });
});

/**
 * Endpoint: POST /api/auth/delete-account & DELETE /api/users/me
 * Permanently deletes user account, cascades DB records, and purges all socket/Redis state.
 */
router.all(['/delete-account', '/delete', '/me'], authMiddleware, async (req, res, next) => {
  // If GET or PUT on /me, let other handlers handle it
  if (req.method === 'GET' || req.method === 'PUT' || req.method === 'PATCH') {
    return next();
  }

  const userId = req.user?.id;
  if (!userId) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { reason, feedback } = req.body || {};

  try {
    console.log(`⚠️ [Auth] Permanent account deletion requested for user ${userId}. Reason: ${reason || 'N/A'}`);

    // 1. Purge Redis session and live presence
    const redis = req.app.get('redis');
    const io = req.app.get('io');

    if (redis) {
      await redis.del(`user_active_session:${userId}`);
      await redis.del(`online_sockets:${userId}`);
      await redis.srem('instant:female_pool', userId);
      await redis.zrem('instant:male_queue', userId);
      await redis.del(`instant:male_session:${userId}`);
      await redis.del(`instant:in_call:${userId}`);
      await redis.del(`call_lock:${userId}`);
    }

    if (io) {
      try {
        const { cleanupUserMatchmaking } = require('../matchmaking/matchmaking.socket');
        const { cleanupUserInstantConnect } = require('../instant_connect/instant_connect.socket');
        const { PresenceService } = require('../presence/presence.service');

        await Promise.all([
          cleanupUserMatchmaking(io, redis, userId),
          cleanupUserInstantConnect(io, redis, userId),
          PresenceService.setPresence(redis, io, userId, false),
        ]);

        // Force disconnect any active socket connections for this user
        io.in(userId).disconnectSockets(true);
      } catch (e) {
        console.error('Error during socket cleanup on account deletion:', e.message);
      }
    }

    // 0. Persist deletion survey to database
    try {
      const userRes = await db.query('SELECT phone_number FROM public.users WHERE id = $1', [userId]);
      const phone = userRes.rows[0]?.phone_number || null;
      await db.query(
        `INSERT INTO public.account_deletion_surveys (user_id, phone_number, reason, feedback)
         VALUES ($1, $2, $3, $4)`,
        [userId, phone, reason || 'unspecified', feedback || null]
      );
      console.log(`📝 [Auth] Saved account deletion survey for user ${userId}`);
    } catch (surveyErr) {
      console.error('Error saving deletion survey:', surveyErr.message);
    }

    // 2. Cascade delete user record from database
    await db.query(`DELETE FROM public.users WHERE id = $1`, [userId]);

    console.log(`✅ [Auth] Account and all associated data permanently deleted for user ${userId}`);
    return res.json({ success: true, message: 'Account permanently deleted.' });
  } catch (err) {
    console.error(`❌ [Auth] Error deleting account for user ${userId}:`, err.message);
    return res.status(500).json({ error: 'Failed to delete account.', message: err.message });
  }
});
router.post('/profile', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { 
    fullName, 
    userName, 
    user_name, 
    dob, 
    gender, 
    language, 
    avatarSeed, 
    avatarStyle, 
    isTelecaller, 
    country, 
    state, 
    city, 
    latitude, 
    longitude 
  } = req.body;

  try {
    const rawUserName = userName !== undefined ? userName : user_name;
    let cleanUserName = null;

    if (rawUserName !== undefined && rawUserName !== null && rawUserName !== '') {
      const valRes = validateUsername(rawUserName);
      if (!valRes.valid) {
        if (valRes.isReserved) {
          return res.status(409).json({ error: 'USERNAME_TAKEN', message: 'it already exist fix it' });
        }
        return res.status(400).json({ error: 'INVALID_FORMAT', message: valRes.message });
      }
      cleanUserName = valRes.normalized;
    }

    if (dob) {
      const birthDate = new Date(dob);
      if (isNaN(birthDate.getTime())) {
        return res.status(400).json({ error: 'Invalid date of birth format.' });
      }
      const today = new Date();
      let age = today.getFullYear() - birthDate.getFullYear();
      const monthDiff = today.getMonth() - birthDate.getMonth();
      if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
        age--;
      }
      if (age < 18) {
        return res.status(400).json({ error: 'You must be 18 years or older to use this app.' });
      }
    }

    if (fullName || cleanUserName || avatarSeed || gender || language || dob) {
      const cleanGender = (gender || '').toLowerCase();
      const isFemale = cleanGender === 'female' || cleanGender === 'girl' || cleanGender === 'woman';
      const telecallerVal = isFemale ? (typeof isTelecaller === 'boolean' ? isTelecaller : null) : null;

      await db.query(
        `UPDATE public.users 
         SET full_name = COALESCE($1::TEXT, full_name), 
             dob = COALESCE($2::TIMESTAMPTZ, dob), 
             gender = COALESCE($3::TEXT, gender), 
             language = COALESCE($4::TEXT, language), 
             avatar_seed = COALESCE($5::TEXT, avatar_seed), 
             avatar_style = COALESCE($6::TEXT, avatar_style), 
             is_telecaller = COALESCE($7::BOOLEAN, is_telecaller),
             user_name = COALESCE($8::VARCHAR, user_name)
         WHERE id = $9::UUID`,
        [
          fullName || null, 
          dob || null, 
          gender || null, 
          language || null, 
          avatarSeed || null, 
          avatarStyle || 'avataaars', 
          telecallerVal, 
          cleanUserName, 
          userId
        ]
      );
    }

    if (country !== undefined || state !== undefined || city !== undefined || latitude !== undefined || longitude !== undefined) {
      await db.query(
        `UPDATE public.users 
         SET country = $1, state = $2, city = $3, latitude = $4, longitude = $5
         WHERE id = $6`,
        [country || null, state || null, city || null, latitude ?? null, longitude ?? null, userId]
      );
    }

    // Invalidate cached user profile in Redis
    await cacheService.invalidate(`user:profile:${userId}`);

    // Fetch and return the updated user object (including user_name)
    const updatedUserRes = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
              w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );

    const userRow = updatedUserRes.rows[0];
    const sBal = parseFloat(userRow?.spendable_balance) || 0;
    const eBal = parseFloat(userRow?.earned_balance) || 0;
    const userObj = userRow ? {
      id: userRow.id,
      countryCode: userRow.country_code || '',
      mobile: userRow.mobile || '',
      phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
      fullName: userRow.full_name || '',
      userName: userRow.user_name || null,
      dob: userRow.dob || null,
      gender: userRow.gender || '',
      language: userRow.language || '',
      avatarSeed: userRow.avatar_seed || '',
      avatarStyle: userRow.avatar_style || 'avataaars',
      isTelecaller: userRow.is_telecaller || false,
      hasClaimedIntroOffer: userRow.has_claimed_intro_offer || false,
      country: userRow.country || null,
      state: userRow.state || null,
      city: userRow.city || null,
      latitude: userRow.latitude ? parseFloat(userRow.latitude) : null,
      longitude: userRow.longitude ? parseFloat(userRow.longitude) : null,
      spendableBalance: sBal,
      earnedBalance: eBal,
      balance: sBal + eBal,
    } : null;

    res.json({ success: true, message: 'Profile updated successfully.', user: userObj });
  } catch (err) {
    if (err.code === '23505' && (err.constraint === 'idx_users_user_name_lower' || (err.detail && err.detail.includes('user_name')))) {
      return res.status(409).json({ error: 'USERNAME_TAKEN', message: 'it already exist fix it' });
    }
    console.error('Error updating profile:', err.message);
    res.status(500).json({ error: 'Failed to update user profile.' });
  }
});

/**
 * Endpoint: GET /api/auth/me
 * Retrieves current user's profile and wallet balance.
 * Cached in Redis for 60 seconds with write-invalidation to handle rapid app restarts.
 */
router.get('/me', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const userRow = await cacheService.getOrSet(`user:profile:${userId}`, 60, async () => {
      const result = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.id = $1`,
        [userId]
      );
      return result.rows.length > 0 ? result.rows[0] : null;
    });

    if (!userRow) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const sBal = Number(userRow.spendable_balance) || 0;
    const eBal = Number(userRow.earned_balance) || 0;

    res.json({
      success: true,
      user: {
        id: userRow.id,
        countryCode: userRow.country_code || '',
        mobile: userRow.mobile || '',
        phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
        fullName: userRow.full_name || '',
        userName: userRow.user_name || null,
        dob: userRow.dob || null,
        gender: userRow.gender || '',
        language: userRow.language || '',
        avatarSeed: userRow.avatar_seed || null,
        avatarStyle: userRow.avatar_style || 'avataaars',
        isTelecaller: userRow.is_telecaller ?? null,
        hasClaimedIntroOffer: userRow.has_claimed_intro_offer === true,
        country: userRow.country || null,
        state: userRow.state || null,
        city: userRow.city || null,
        latitude: userRow.latitude !== null ? parseFloat(userRow.latitude) : null,
        longitude: userRow.longitude !== null ? parseFloat(userRow.longitude) : null,
        spendableBalance: sBal,
        earnedBalance: eBal,
        walletBalance: sBal + eBal,
        balance: sBal + eBal,
      },
    });
  } catch (err) {
    console.error('Error fetching profile:', err.message);
    res.status(500).json({ error: 'Internal server error fetching user profile.' });
  }
});

/**
 * Endpoint: POST & PATCH /api/auth/location
 * Updates authenticated user's location (country, state, city, latitude, longitude).
 */
async function handleLocationUpdate(req, res) {
  const userId = req.user.id;
  const { country, state, city, latitude, longitude } = req.body;

  try {
    await db.query(
      `UPDATE public.users
       SET country = $1, state = $2, city = $3, latitude = $4, longitude = $5
       WHERE id = $6`,
      [country || null, state || null, city || null, latitude ?? null, longitude ?? null, userId]
    );

    res.json({
      success: true,
      message: 'Location saved successfully.',
      location: { country, state, city, latitude, longitude },
    });
  } catch (err) {
    console.error('Error updating location:', err.message);
    res.status(500).json({ error: 'Failed to update user location.' });
  }
}

router.post('/location', authMiddleware, handleLocationUpdate);
router.patch('/location', authMiddleware, handleLocationUpdate);

/**
 * Endpoint: PATCH /api/users/me/telecaller-status (also /api/auth/telecaller-status)
 * Allows female users to toggle their telecaller opt-in mode.
 */
async function handleTelecallerStatusUpdate(req, res) {
  const userId = req.user.id;
  const { isTelecaller } = req.body;

  if (typeof isTelecaller !== 'boolean') {
    return res.status(400).json({ error: 'isTelecaller must be a boolean.' });
  }

  try {
    const userRes = await db.query('SELECT gender FROM public.users WHERE id = $1', [userId]);
    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const gender = (userRes.rows[0].gender || '').toLowerCase();
    const isFemale = (gender === 'female' || gender === 'girl' || gender === 'woman');

    if (!isFemale) {
      return res.status(403).json({ error: 'Telecaller mode is only available for female users.' });
    }

    await db.query(
      'UPDATE public.users SET is_telecaller = $1 WHERE id = $2',
      [isTelecaller, userId]
    );

    res.json({ success: true, isTelecaller });
  } catch (err) {
    console.error('Error updating telecaller status:', err.message);
    res.status(500).json({ error: 'Failed to update telecaller status.' });
  }
}

router.patch('/telecaller-status', authMiddleware, handleTelecallerStatusUpdate);
router.patch('/me/telecaller-status', authMiddleware, handleTelecallerStatusUpdate);

/**
 * Endpoint: POST /api/auth/upload-avatar
 * Uploads custom profile avatar to Cloudinary (or local storage fallback) and returns the image URL.
 */
const multer = require('multer');
const { CloudinaryStorage } = require('multer-storage-cloudinary');
const cloudinary = require('cloudinary').v2;
const path = require('path');
const fs = require('fs');

const hasCloudinary =
  Boolean(process.env.CLOUDINARY_CLOUD_NAME) &&
  Boolean(process.env.CLOUDINARY_API_KEY) &&
  Boolean(process.env.CLOUDINARY_API_SECRET);

if (hasCloudinary) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });
}

let avatarStorage;
if (hasCloudinary) {
  avatarStorage = new CloudinaryStorage({
    cloudinary: cloudinary,
    params: {
      folder: 'buddypartner/avatars',
      allowed_formats: ['jpg', 'png', 'jpeg', 'webp'],
    },
  });
} else {
  const uploadsDir = path.join(__dirname, '../../uploads/avatars');
  if (!fs.existsSync(uploadsDir)) {
    fs.mkdirSync(uploadsDir, { recursive: true });
  }
  avatarStorage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, uploadsDir),
    filename: (_req, file, cb) => cb(null, `${Date.now()}_${file.originalname}`),
  });
}

const avatarUpload = multer({
  storage: avatarStorage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
});

router.post('/upload-avatar', authMiddleware, (req, res) => {
  avatarUpload.single('file')(req, res, async (err) => {
    if (err) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ success: false, error: 'File size exceeds 5MB limit.' });
      }
      return res.status(400).json({ success: false, error: err.message });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, error: 'No image file provided.' });
    }
    let imageUrl;
    if (req.file.path && (req.file.path.startsWith('http://') || req.file.path.startsWith('https://'))) {
      imageUrl = req.file.path;
    } else if (req.file.secure_url) {
      imageUrl = req.file.secure_url;
    } else {
      const host = req.get('host');
      const protocol = req.protocol;
      imageUrl = `${protocol}://${host}/uploads/avatars/${req.file.filename}`;
    }

    // Persist avatar URL directly to DB immediately on upload
    try {
      const userId = req.user?.id;
      if (userId) {
        // Ensure avatar_seed column can hold URLs (run at first upload, safe to repeat)
        await db.query(`ALTER TABLE public.users ALTER COLUMN avatar_seed TYPE TEXT`).catch(() => {});
        await db.query(
          `UPDATE public.users SET avatar_seed = $1 WHERE id = $2`,
          [imageUrl, userId]
        );
      }
    } catch (dbErr) {
      console.error('Failed to save avatar URL to DB:', dbErr.message);
      // Still return success — the URL was uploaded to Cloudinary
    }

    return res.json({ success: true, imageUrl, url: imageUrl });
  });
});

/**
 * Endpoint: POST /api/users/fcm-token and POST /api/auth/fcm-token
 * Saves the device FCM push token for push notifications and offline surge alerts.
 */
router.post('/fcm-token', authMiddleware, async (req, res) => {
  try {
    const { fcmToken } = req.body;
    if (!fcmToken || typeof fcmToken !== 'string') {
      return res.status(400).json({ error: 'Valid fcmToken string is required.' });
    }

    await db.query(
      `UPDATE public.users SET fcm_token = $1 WHERE id = $2`,
      [fcmToken.trim(), req.user.id]
    );

    res.json({ success: true, message: 'FCM token updated successfully.' });
  } catch (err) {
    console.error('Error updating FCM token:', err.message);
    res.status(500).json({ error: 'Failed to update FCM token.' });
  }
});

module.exports = router;
