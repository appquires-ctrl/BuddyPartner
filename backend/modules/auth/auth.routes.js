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
const { scanKeys } = require('../../utils/redis_helpers');

const RESERVED_USERNAMES = new Set([
  'admin', 'administrator', 'support', 'help', 'buddypartner', 
  'official', 'null', 'undefined', 'system', 'root', 'moderator',
  'api', 'auth', 'user', 'users', 'me'
]);

// Session TTL matching JWT refresh token lifespan (30 days) to prevent Redis memory leaks
const SESSION_TTL_SECONDS = 30 * 24 * 60 * 60;

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
  if (/^\d+$/.test(normalized)) {
    return { valid: false, message: 'Username cannot consist solely of numbers.' };
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
 * Endpoint: POST /api/auth/login
 * Production username/phone + password authentication (Zero SMS gateway cost).
 * - Accepts { login, password }
 * - Resolves user by case-insensitive user_name or phone
 * - Enforces Redis brute-force rate limit: max 5 failed attempts per 15 minutes
 * - Enforces Single-Device Policy (invalidates old session & emits session_terminated)
 * - Issues Access Token (1d) and rotating Refresh Token (30d) in Redis
 */
router.post('/login', async (req, res) => {
  const { login, password } = req.body || {};
  const rawLogin = (login || '').toString().trim();
  const rawPassword = (password || '').toString();

  if (!rawLogin || !rawPassword) {
    return res.status(400).json({ error: 'Username or phone number, and password are required.' });
  }

  const cleanLogin = rawLogin.startsWith('@') ? rawLogin.slice(1).trim().toLowerCase() : rawLogin.toLowerCase();
  const ip = req.ip || req.headers['x-forwarded-for'] || req.socket.remoteAddress || 'unknown_ip';

  const lockoutWindow = 900; // 15 minutes
  const maxAttempts = 5;
  const loginAttemptsKey = `login_attempts:${cleanLogin}`;
  const ipAttemptsKey = `login_attempts_ip:${ip}`;

  try {
    // 1. Check brute-force lockout counters
    const [userAttempts, ipAttempts] = await Promise.all([
      redis.get(loginAttemptsKey),
      redis.get(ipAttemptsKey),
    ]);

    if ((userAttempts && parseInt(userAttempts, 10) >= maxAttempts) ||
        (ipAttempts && parseInt(ipAttempts, 10) >= maxAttempts * 3)) {
      return res.status(429).json({
        error: 'TOO_MANY_ATTEMPTS',
        message: 'Too many failed login attempts. Please wait 15 minutes or reset your password.',
      });
    }

    // 2. Identify and fetch user (check by phone or username with direct index scans)
    const phoneDigits = rawLogin.replace(/\D/g, '');
    const cleanUserName = cleanLogin.replace(/^@+/, '');
    const isExplicitUsername = rawLogin.startsWith('@') || /[a-zA-Z]/.test(rawLogin);
    const isExplicitPhone = rawLogin.startsWith('+');
    let userRes;

    const USER_SELECT_FIELDS = `
      u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash,
      u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, 
      u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, u.is_banned,
      u.incoming_paid_calls_enabled,
      w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance
    `;

    if (isExplicitUsername) {
      // Explicit username (starts with '@' or contains letters): direct index scan on LOWER(user_name)
      userRes = await db.query(
        `SELECT ${USER_SELECT_FIELDS}
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE LOWER(u.user_name) = $1
         LIMIT 1`,
        [cleanUserName]
      );
    } else if (isExplicitPhone) {
      // Explicit phone (starts with '+'): direct index scan on phone_number / mobile
      userRes = await db.query(
        `SELECT ${USER_SELECT_FIELDS}
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.phone_number = $1 
            OR u.phone_number = $2 
            OR u.mobile = $3
         LIMIT 1`,
        [rawLogin, phoneDigits, phoneDigits]
      );
    } else if (phoneDigits.length >= 7) {
      // Ambiguous numeric input: check phone lookup first
      userRes = await db.query(
        `SELECT ${USER_SELECT_FIELDS}
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.phone_number = $1 
            OR u.phone_number = $2 
            OR u.mobile = $3
         LIMIT 1`,
        [phoneDigits, `+${phoneDigits}`, phoneDigits]
      );

      // If phone found but password doesn't match, check if input also matches an all-numeric username
      if (userRes.rows.length > 0 && userRes.rows[0].password_hash) {
        const isPwValid = await bcrypt.compare(rawPassword, userRes.rows[0].password_hash);
        if (!isPwValid) {
          const usernameFallback = await db.query(
            `SELECT ${USER_SELECT_FIELDS}
             FROM public.users u
             LEFT JOIN public.wallets w ON w.user_id = u.id
             WHERE LOWER(u.user_name) = $1
             LIMIT 1`,
            [cleanLogin]
          );
          if (usernameFallback.rows.length > 0) {
            userRes = usernameFallback;
          }
        }
      } else if (userRes.rows.length === 0) {
        // No phone found; fallback to username lookup
        userRes = await db.query(
          `SELECT ${USER_SELECT_FIELDS}
           FROM public.users u
           LEFT JOIN public.wallets w ON w.user_id = u.id
           WHERE LOWER(u.user_name) = $1
           LIMIT 1`,
          [cleanLogin]
        );
      }
    } else {
      userRes = await db.query(
        `SELECT ${USER_SELECT_FIELDS}
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE LOWER(u.user_name) = $1
         LIMIT 1`,
        [cleanLogin]
      );
    }


    if (userRes.rows.length === 0) {
      const attempts = await redis.incr(loginAttemptsKey);
      if (attempts === 1) await redis.expire(loginAttemptsKey, lockoutWindow);
      await redis.incr(ipAttemptsKey);
      await redis.expire(ipAttemptsKey, lockoutWindow);

      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: 'Invalid username or password.' });
    }

    const user = userRes.rows[0];

    // 3. Check if account is banned
    if (user.is_banned === true) {
      return res.status(403).json({ error: 'ACCOUNT_BANNED', message: 'This account has been suspended or banned.' });
    }

    // 4. Check if password is set on this account
    if (!user.password_hash) {
      return res.status(400).json({
        error: 'NO_PASSWORD_SET',
        message: 'No password has been set for this account yet. Please log in using WhatsApp OTP once to create your password.',
        phoneHint: user.phone_number ? `...${user.phone_number.slice(-4)}` : null,
      });
    }

    // 5. Compare password hash
    const isPasswordValid = await bcrypt.compare(rawPassword, user.password_hash);
    if (!isPasswordValid) {
      const attempts = await redis.incr(loginAttemptsKey);
      if (attempts === 1) await redis.expire(loginAttemptsKey, lockoutWindow);
      await redis.incr(ipAttemptsKey);
      await redis.expire(ipAttemptsKey, lockoutWindow);

      return res.status(401).json({ error: 'INVALID_CREDENTIALS', message: 'Invalid username or password.' });
    }

    // 6. Login successful! Clear failed attempt keys
    await Promise.all([
      redis.del(loginAttemptsKey),
      redis.del(ipAttemptsKey),
    ]);

    // 7. Enforce Single-Device Policy
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

    try {
      const oldRefreshKeys = await scanKeys(redis, `refresh:${user.id}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    await redis.set(
      `user_active_session:${user.id}`,
      JSON.stringify({ sessionId, isBanned: Boolean(user.is_banned) }),
      'EX',
      SESSION_TTL_SECONDS
    );

    // 8. Generate Tokens
    const jti = crypto.randomUUID();
    const fullPhoneNumber = user.phone_number || `+${user.country_code}${user.mobile}`;
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: user.country_code,
      mobile: user.mobile,
      sessionId,
      gender: user.gender || null,
      city: user.city || null,
      incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
    };

    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const refreshToken = jwt.sign({ id: user.id, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);
    // Cache profile attributes in Redis for fast zero-DB socket connect lookups
    await redis.set(
      `user:profile:${user.id}`,
      JSON.stringify({
        id: user.id,
        full_name: user.full_name || '',
        city: user.city || null,
        gender: user.gender || null,
        incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
      }),
      'EX',
      7 * 24 * 60 * 60
    );

    const isProfileComplete = Boolean(user.full_name && user.full_name.trim().length > 0);
    const sBal = parseFloat(user.spendable_balance) || 0;
    const eBal = parseFloat(user.earned_balance) || 0;

    res.json({
      success: true,
      token,
      refreshToken,
      isProfileComplete,
      user: {
        id: user.id,
        countryCode: user.country_code || '',
        mobile: user.mobile || '',
        phoneNumber: fullPhoneNumber,
        fullName: user.full_name || '',
        userName: user.user_name || null,
        hasPassword: true,
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
        spendableBalance: sBal,
        earnedBalance: eBal,
        balance: sBal + eBal,
      },
    });
  } catch (err) {
    console.error('❌ Error during password login:', err.message);
    res.status(500).json({ error: 'Internal server error processing login.' });
  }
});

/**
 * Endpoint: POST /api/auth/set-password
 * Allows an authenticated user to set or update their account password.
 */
router.post('/set-password', authMiddleware, async (req, res) => {
  const userId = req.user?.id;
  const { password } = req.body || {};

  if (!password || typeof password !== 'string' || password.length < 8) {
    return res.status(400).json({
      error: 'INVALID_PASSWORD',
      message: 'Password must be at least 8 characters long.',
    });
  }

  try {
    const passwordHash = await bcrypt.hash(password, 10);
    await db.query(
      `UPDATE public.users SET password_hash = $1 WHERE id = $2`,
      [passwordHash, userId]
    );

    // Invalidate cached profile
    await cacheService.invalidate(`user:profile:${userId}`);
    await cacheService.invalidate(`user:me_profile:${userId}`);

    res.json({
      success: true,
      message: 'Password created successfully. You can now log in using your username and password.',
    });
  } catch (err) {
    console.error('❌ Error setting password:', err.message);
    res.status(500).json({ error: 'Failed to set password.' });
  }
});

/**
 * Endpoint: POST /api/auth/forgot-password/send-otp
 * Initiates password recovery by sending a 6-digit WhatsApp OTP to the user's verified phone.
 */
router.post('/forgot-password/send-otp', async (req, res) => {
  const { login, country_code, mobile } = req.body || {};
  let targetCountryCode = country_code;
  let targetMobile = mobile;

  try {
    if (login) {
      const cleanLogin = (login || '').toString().trim().replace(/^@/, '').toLowerCase();
      const phoneDigits = cleanLogin.replace(/\D/g, '');

      let userRes;
      if (phoneDigits.length >= 7) {
        userRes = await db.query(
          `SELECT id, country_code, mobile, phone_number FROM public.users 
           WHERE LOWER(user_name) = $1 OR mobile = $2 OR phone_number = $3 OR phone_number = $4 LIMIT 1`,
          [cleanLogin, phoneDigits, `+${phoneDigits}`, phoneDigits]
        );
      } else {
        userRes = await db.query(
          `SELECT id, country_code, mobile, phone_number FROM public.users WHERE LOWER(user_name) = $1 LIMIT 1`,
          [cleanLogin]
        );
      }

      if (userRes.rows.length === 0) {
        return res.status(404).json({ error: 'USER_NOT_FOUND', message: 'No account found with this username or phone number.' });
      }

      targetCountryCode = userRes.rows[0].country_code || '91';
      targetMobile = userRes.rows[0].mobile;
    }

    const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(targetCountryCode, targetMobile);
    if (!cleanCountryCode || !cleanMobile || cleanMobile.length < 7) {
      return res.status(400).json({ error: 'Valid country code and mobile number are required.' });
    }

    const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
    const otpRedisKey = `otp_reset:${cleanCountryCode}${cleanMobile}`;

    if (isTestAccount) {
      const hashedOtp = await bcrypt.hash(DEMO_TEST_OTP, 10);
      await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);
      return res.json({
        success: true,
        message: 'Password reset code sent.',
        countryCode: cleanCountryCode,
        mobile: cleanMobile,
        phoneHint: `...${cleanMobile.slice(-4)}`,
      });
    }

    // Rate limiting: max 3 reset OTPs per 10 minutes
    const sendCountKey = `otp_reset_send_count:${cleanMobile}`;
    const sendCount = await redis.incr(sendCountKey);
    if (sendCount === 1) await redis.expire(sendCountKey, SEND_LIMIT_WINDOW);
    else if (sendCount > SEND_LIMIT_MAX) {
      return res.status(429).json({ error: 'Too many OTP requests. Please wait 10 minutes before trying again.' });
    }

    const otp = generateOTP();
    const hashedOtp = await bcrypt.hash(otp, 10);
    await redis.set(otpRedisKey, hashedOtp, 'EX', OTP_TTL_SECONDS);

    const sendResult = await sendWhatsAppOtp(cleanCountryCode, cleanMobile, otp);
    if (!sendResult.success) {
      return res.status(500).json({ error: sendResult.message || 'Failed to send WhatsApp reset code.' });
    }

    res.json({
      success: true,
      message: 'Password reset code sent via WhatsApp.',
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
      phoneHint: `...${cleanMobile.slice(-4)}`,
    });
  } catch (err) {
    console.error('❌ Error in /forgot-password/send-otp:', err.message);
    res.status(500).json({ error: 'Failed to send reset code.' });
  }
});

/**
 * Endpoint: POST /api/auth/forgot-password/reset
 * Verifies the 6-digit WhatsApp OTP and sets the new password.
 */
router.post('/forgot-password/reset', async (req, res) => {
  const { country_code, mobile, otp, new_password } = req.body || {};
  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(country_code, mobile);
  const cleanOtp = (otp || '').toString().trim();
  const rawPassword = (new_password || '').toString();

  if (!cleanCountryCode || !cleanMobile || !cleanOtp || cleanOtp.length !== 6) {
    return res.status(400).json({ error: 'Valid mobile number and 6-digit verification code are required.' });
  }

  if (!rawPassword || rawPassword.length < 8) {
    return res.status(400).json({ error: 'New password must be at least 8 characters long.' });
  }

  const isTestAccount = (DEMO_TEST_MOBILES.has(cleanMobile) && cleanCountryCode === DEMO_TEST_COUNTRY_CODE);
  const otpRedisKey = `otp_reset:${cleanCountryCode}${cleanMobile}`;

  try {
    if (isTestAccount) {
      if (cleanOtp !== DEMO_TEST_OTP) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    } else {
      const storedHash = await redis.get(otpRedisKey);
      if (!storedHash) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }

      const isMatch = await bcrypt.compare(cleanOtp, storedHash);
      if (!isMatch) {
        return res.status(400).json({ error: 'Invalid or expired verification code.' });
      }
    }

    // OTP verified! Delete OTP key
    await redis.del(otpRedisKey);

    // Hash and persist new password
    const newHash = await bcrypt.hash(rawPassword, 10);
    const fullPhone = `+${cleanCountryCode}${cleanMobile}`;

    const updateRes = await db.query(
      `UPDATE public.users 
       SET password_hash = $1 
       WHERE (country_code = $2 AND mobile = $3) OR phone_number = $4
       RETURNING id`,
      [newHash, cleanCountryCode, cleanMobile, fullPhone]
    );

    if (updateRes.rows.length === 0) {
      return res.status(404).json({ error: 'User account not found.' });
    }

    const userId = updateRes.rows[0].id;

    // Purge cached profile & old sessions so user must log in fresh
    await cacheService.invalidate(`user:profile:${userId}`);
    await cacheService.invalidate(`user:me_profile:${userId}`);
    await redis.del(`user_active_session:${userId}`);
    try {
      const oldRefreshKeys = await scanKeys(redis, `refresh:${userId}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    res.json({
      success: true,
      message: 'Password reset successfully! You can now log in with your new password.',
    });
  } catch (err) {
    console.error('❌ Error in /forgot-password/reset:', err.message);
    res.status(500).json({ error: 'Failed to reset password.' });
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

  // Shared cache across all users: fetch limit + 1 from DB, cached for 60s
  const cacheKey = `search:users:${cleanQuery}:${limit}`;

  try {
    const cachedUsers = await cacheService.getOrSet(cacheKey, 60, async () => {
      const searchRes = await db.query(
        `SELECT id, full_name, user_name, avatar_seed, avatar_style, gender, is_telecaller
         FROM public.users
         WHERE LOWER(user_name) LIKE LOWER($1) || '%'
           AND (is_banned IS NOT TRUE)
         ORDER BY LOWER(user_name) ASC
         LIMIT $2`,
        [cleanQuery, limit + 1]
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

    // Filter out requesting user in Node memory after reading from shared cache
    const users = (cachedUsers || [])
      .filter((u) => u.id !== currentUserId)
      .slice(0, limit);

    return res.json({
      success: true,
      query: cleanQuery,
      users,
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
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, 
              u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, 
              u.country, u.state, u.city, u.latitude, u.longitude, u.incoming_paid_calls_enabled, u.is_banned,
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
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude, incoming_paid_calls_enabled`,
            [
              cleanCountryCode, cleanMobile, fullPhoneNumber,
              'Google Reviewer', 'googlereviewer', '1998-01-01', 'Male', 'English', 'male_2f', 'avataaars', 'India', 'Delhi', 'New Delhi'
            ]
          );
        } else {
          insertUserRes = await client.query(
            `INSERT INTO public.users (country_code, mobile, phone_number, avatar_seed, avatar_style) 
             VALUES ($1, $2, $3, 'male_2f', 'avataaars') 
             RETURNING id, country_code, mobile, phone_number, full_name, user_name, dob, gender, language, avatar_seed, avatar_style, is_telecaller, has_claimed_intro_offer, country, state, city, latitude, longitude, incoming_paid_calls_enabled`,
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
        console.log(` New user created: ID ${user.id}, mobile +${cleanCountryCode}${cleanMobile}${isTestAccount ? ' [TEST ACCOUNT]' : ''}`);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } else {
      user = userResult.rows[0];

      // Check if account is banned
      if (user.is_banned === true) {
        return res.status(403).json({
          error: 'ACCOUNT_BANNED',
          message: 'This account has been suspended or banned.',
        });
      }

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
      const oldRefreshKeys = await scanKeys(redis, `refresh:${user.id}:*`);
      if (oldRefreshKeys && oldRefreshKeys.length > 0) {
        await redis.del(...oldRefreshKeys);
      }
    } catch (_) {}

    // Store active session in Redis with 30-day TTL (includes isBanned flag for 1-GET auth checks)
    await redis.set(
      `user_active_session:${user.id}`,
      JSON.stringify({ sessionId, isBanned: Boolean(user.is_banned) }),
      'EX',
      SESSION_TTL_SECONDS
    );

    // 7. Generate Tokens
    const jti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
      sessionId,
      gender: user.gender || null,
      city: user.city || null,
      incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
    };

    // Short-lived Access Token (1 day)
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });

    // Refresh Token (30 days) with jti
    const refreshToken = jwt.sign({ id: user.id, jti, sessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store Refresh Token status in Redis: refresh:{userId}:{jti} -> TTL 30 days (2,592,000s)
    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);
    // Cache profile attributes in Redis for fast zero-DB socket connect lookups
    await redis.set(
      `user:profile:${user.id}`,
      JSON.stringify({
        id: user.id,
        full_name: user.full_name || '',
        city: user.city || null,
        gender: user.gender || null,
        incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
      }),
      'EX',
      7 * 24 * 60 * 60
    );

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
        hasPassword: Boolean(user.password_hash),
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
router.post(['/refresh', '/token/refresh'], async (req, res) => {
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
    const rawSession = await redis.get(`user_active_session:${id}`);
    let activeSessionId = rawSession;
    if (rawSession && rawSession.startsWith('{')) {
      try {
        const parsed = JSON.parse(rawSession);
        activeSessionId = parsed.sessionId;
      } catch (_) {}
    }
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
      `SELECT id, country_code, mobile, phone_number, full_name, city, gender, incoming_paid_calls_enabled, is_banned FROM public.users WHERE id = $1`,
      [id]
    );

    if (userRes.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const user = userRes.rows[0];

    if (user.is_banned === true) {
      return res.status(403).json({ error: 'ACCOUNT_BANNED', message: 'This account has been suspended or banned.' });
    }

    const currentSessionId = activeSessionId || sessionId || crypto.randomUUID();
    if (!activeSessionId) {
      await redis.set(
        `user_active_session:${id}`,
        JSON.stringify({ sessionId: currentSessionId, isBanned: Boolean(user.is_banned) }),
        'EX',
        SESSION_TTL_SECONDS
      );
    }

    // Issue new tokens
    const newJti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: user.phone_number || `+${user.country_code}${user.mobile}`,
      countryCode: user.country_code,
      mobile: user.mobile,
      sessionId: currentSessionId,
      gender: user.gender || null,
      city: user.city || null,
      incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
    };

    const newAccessToken = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const newRefreshToken = jwt.sign({ id: user.id, jti: newJti, sessionId: currentSessionId }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store new refresh token in Redis
    await redis.set(`refresh:${user.id}:${newJti}`, '1', 'EX', 30 * 24 * 60 * 60);
    // Refresh cached profile attributes in Redis
    await redis.set(
      `user:profile:${user.id}`,
      JSON.stringify({
        id: user.id,
        full_name: user.full_name || '',
        city: user.city || null,
        gender: user.gender || null,
        incoming_paid_calls_enabled: user.incoming_paid_calls_enabled === true,
      }),
      'EX',
      7 * 24 * 60 * 60
    );

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
    password,
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

    let cleanPasswordHash = null;
    if (password) {
      if (typeof password !== 'string' || password.length < 8) {
        return res.status(400).json({ error: 'INVALID_PASSWORD', message: 'Password must be at least 8 characters long.' });
      }
      cleanPasswordHash = await bcrypt.hash(password, 10);
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

    if (fullName || cleanUserName || cleanPasswordHash || avatarSeed || gender || language || dob) {
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
             user_name = COALESCE($8::VARCHAR, user_name),
             password_hash = COALESCE($9::VARCHAR, password_hash)
         WHERE id = $10::UUID`,
        [
          fullName || null, 
          dob || null, 
          gender || null, 
          language || null, 
          avatarSeed || null, 
          avatarStyle || 'avataaars', 
          telecallerVal, 
          cleanUserName,
          cleanPasswordHash,
          userId
        ]
      );
    }

    // Note: City changes take effect on next socket reconnect, not live;
    // this is an intentional design decision given normal mobile reconnect churn.
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
    await cacheService.invalidate(`user:me_profile:${userId}`);

    // Fetch and return the updated user object (including user_name and password_hash)
    const updatedUserRes = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, u.incoming_paid_calls_enabled,
              w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );

    const userRow = updatedUserRes.rows[0];
    if (userRow) {
      await redis.set(
        `user:profile:${userId}`,
        JSON.stringify({
          id: userRow.id,
          full_name: userRow.full_name || '',
          city: userRow.city || null,
          gender: userRow.gender || null,
          incoming_paid_calls_enabled: userRow.incoming_paid_calls_enabled === true,
        }),
        'EX',
        7 * 24 * 60 * 60
      );
    }
    const sBal = parseFloat(userRow?.spendable_balance) || 0;
    const eBal = parseFloat(userRow?.earned_balance) || 0;
    const userObj = userRow ? {
      id: userRow.id,
      countryCode: userRow.country_code || '',
      mobile: userRow.mobile || '',
      phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
      fullName: userRow.full_name || '',
      userName: userRow.user_name || null,
      hasPassword: Boolean(userRow.password_hash),
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
    let userRow = await cacheService.getOrSet(`user:me_profile:${userId}`, 60, async () => {
      const result = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.id = $1`,
        [userId]
      );
      return result.rows.length > 0 ? result.rows[0] : null;
    });

    // Guard against cache collision or partial object where full_name was missing
    if (!userRow || userRow.full_name === undefined) {
      const result = await db.query(
        `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.user_name, u.password_hash, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, 
                w.spendable_balance, w.earned_balance, (COALESCE(w.spendable_balance, 0) + COALESCE(w.earned_balance, 0)) AS balance 
         FROM public.users u
         LEFT JOIN public.wallets w ON w.user_id = u.id
         WHERE u.id = $1`,
        [userId]
      );
      userRow = result.rows.length > 0 ? result.rows[0] : null;
      if (userRow) {
        await cacheService.set(`user:me_profile:${userId}`, userRow, 60);
      }
    }

    if (!userRow) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const isProfileComplete = Boolean(userRow.full_name && userRow.full_name.trim().length > 0);
    const sBal = Number(userRow.spendable_balance) || 0;
    const eBal = Number(userRow.earned_balance) || 0;

    res.json({
      success: true,
      isProfileComplete,
      user: {
        id: userRow.id,
        isProfileComplete,
        countryCode: userRow.country_code || '',
        mobile: userRow.mobile || '',
        phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
        fullName: userRow.full_name || '',
        userName: userRow.user_name || null,
        hasPassword: Boolean(userRow.password_hash),
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
 * Deprecated: Telecaller mode was removed in the August 1, 2026 unisex subscription pivot.
 * Endpoints return success no-op for backward compatibility with any legacy client builds.
 */
router.patch(['/telecaller-status', '/me/telecaller-status'], authMiddleware, (req, res) => {
  res.json({ success: true, message: 'Telecaller mode is deprecated.' });
});

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
