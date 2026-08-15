const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const db = require('../../db');
const redis = require('../../redis');
const { authMiddleware } = require('../../middleware/auth.middleware');
const { generateOTP, sanitizePhoneInputs, sendWhatsAppOtp } = require('./otpService');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'buddypartner_fallback_jwt_refresh_secret_key';

// Rate limit constants
const OTP_TTL_SECONDS = 300; // 5 minutes
const SEND_LIMIT_MAX = 3; // Max 3 sends per 10 min
const SEND_LIMIT_WINDOW = 600; // 10 minutes
const VERIFY_ATTEMPTS_MAX = 5; // Max 5 wrong attempts before lockout
const VERIFY_LOCKOUT_WINDOW = 600; // 10 minutes lockout

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
 * - Provisions user + wallet + wallet_transactions (welcome bonus 100) atomically if new
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
    // 1. Check attempt lockout counter
    const attemptsKey = `otp_verify_attempts:${cleanMobile}`;
    const attempts = await redis.get(attemptsKey);
    if (attempts && parseInt(attempts, 10) >= VERIFY_ATTEMPTS_MAX) {
      return res.status(429).json({ error: 'Too many failed verification attempts. Please try again in 10 minutes.' });
    }

    // 2. Fetch stored hashed OTP from Redis
    const otpRedisKey = `otp:${cleanCountryCode}${cleanMobile}`;
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

    // 4. Verification successful! Delete OTP key & clear attempt counter
    await redis.del(otpRedisKey);
    await redis.del(attemptsKey);

    // Form legacy phone format e.g. "+919876543210"
    const fullPhoneNumber = `+${cleanCountryCode}${cleanMobile}`;

    // 5. Query user or run atomic transaction to create user + wallet + welcome bonus
    let userResult = await db.query(
      `SELECT id, country_code, mobile, phone_number, full_name 
       FROM public.users 
       WHERE (country_code = $1 AND mobile = $2) OR phone_number = $3`,
      [cleanCountryCode, cleanMobile, fullPhoneNumber]
    );

    let user;

    if (userResult.rows.length === 0) {
      // Atomic Transaction: Create user + wallet + welcome bonus 100
      const client = await db.pool.connect();
      try {
        await client.query('BEGIN');

        const insertUserRes = await client.query(
          `INSERT INTO public.users (country_code, mobile, phone_number) 
           VALUES ($1, $2, $3) 
           RETURNING id, country_code, mobile, phone_number, full_name`,
          [cleanCountryCode, cleanMobile, fullPhoneNumber]
        );
        user = insertUserRes.rows[0];

        // Provision wallet with 100 balance
        await client.query(
          `INSERT INTO public.wallets (user_id, balance) 
           VALUES ($1, 100) 
           ON CONFLICT (user_id) DO NOTHING`,
          [user.id]
        );

        // Record welcome bonus transaction
        await client.query(
          `INSERT INTO public.wallet_transactions (user_id, amount, type, reason) 
           VALUES ($1, 100, 'credit', 'Welcome Bonus')`,
          [user.id]
        );

        await client.query('COMMIT');
        console.log(`🎉 New user created via Authkey WhatsApp OTP: ID ${user.id}, mobile +${cleanCountryCode}${cleanMobile}`);
      } catch (txErr) {
        await client.query('ROLLBACK');
        throw txErr;
      } finally {
        client.release();
      }
    } else {
      user = userResult.rows[0];

      // Backfill country_code / mobile if missing on existing record
      if (!user.country_code || !user.mobile) {
        await db.query(
          `UPDATE public.users SET country_code = $1, mobile = $2 WHERE id = $3`,
          [cleanCountryCode, cleanMobile, user.id]
        );
      }
    }

    // 6. Generate Tokens
    const jti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: fullPhoneNumber,
      countryCode: cleanCountryCode,
      mobile: cleanMobile,
    };

    // Short-lived Access Token (1 day)
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });

    // Refresh Token (30 days) with jti
    const refreshToken = jwt.sign({ id: user.id, jti }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

    // Store Refresh Token status in Redis: refresh:{userId}:{jti} -> TTL 30 days (2,592,000s)
    await redis.set(`refresh:${user.id}:${jti}`, '1', 'EX', 30 * 24 * 60 * 60);

    res.json({
      success: true,
      token,
      refreshToken,
      isProfileComplete: !!(user.full_name && user.full_name.trim().length > 0),
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
    const { id, jti } = decoded;

    if (!id || !jti) {
      return res.status(401).json({ error: 'Invalid refresh token structure.' });
    }

    // Check Redis for active refresh token key
    const redisKey = `refresh:${id}:${jti}`;
    const exists = await redis.get(redisKey);

    if (!exists) {
      return res.status(401).json({ error: 'Invalid or revoked refresh token.' });
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

    // Issue new tokens
    const newJti = crypto.randomUUID();
    const payload = {
      id: user.id,
      phone: user.phone_number || `+${user.country_code}${user.mobile}`,
      countryCode: user.country_code,
      mobile: user.mobile,
    };

    const newAccessToken = jwt.sign(payload, JWT_SECRET, { expiresIn: '1d' });
    const newRefreshToken = jwt.sign({ id: user.id, jti: newJti }, JWT_REFRESH_SECRET, { expiresIn: '30d' });

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
 * Invalidates the session by deleting the refresh token from Redis.
 */
router.post('/logout', async (req, res) => {
  const { refreshToken } = req.body;

  if (refreshToken && typeof refreshToken === 'string') {
    try {
      const decoded = jwt.decode(refreshToken);
      if (decoded && decoded.id && decoded.jti) {
        await redis.del(`refresh:${decoded.id}:${decoded.jti}`);
      }
    } catch (_) {
      // Ignore decode failures on logout
    }
  }

  res.json({ success: true, message: 'Logged out successfully.' });
});

/**
 * Endpoint: POST /api/auth/profile
 * Updates authenticated user profile details.
 */
router.post('/profile', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { fullName, dob, gender, language, avatarSeed, avatarStyle, isTelecaller, country, state, city, latitude, longitude } = req.body;

  try {
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

    if (fullName || avatarSeed || gender || language || dob) {
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
             is_telecaller = COALESCE($7::BOOLEAN, is_telecaller) 
         WHERE id = $8::UUID`,
        [fullName || null, dob || null, gender || null, language || null, avatarSeed || null, avatarStyle || 'avataaars', telecallerVal, userId]
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

    res.json({ success: true, message: 'Profile updated successfully.' });
  } catch (err) {
    console.error('Error updating profile:', err.message);
    res.status(500).json({ error: 'Failed to update user profile.' });
  }
});

/**
 * Endpoint: GET /api/auth/me
 * Retrieves current user's profile and wallet balance.
 */
router.get('/me', authMiddleware, async (req, res) => {
  const userId = req.user.id;

  try {
    const result = await db.query(
      `SELECT u.id, u.country_code, u.mobile, u.phone_number, u.full_name, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.has_claimed_intro_offer, u.country, u.state, u.city, u.latitude, u.longitude, w.balance 
       FROM public.users u
       LEFT JOIN public.wallets w ON w.user_id = u.id
       WHERE u.id = $1`,
      [userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User profile not found.' });
    }

    const userRow = result.rows[0];
    res.json({
      success: true,
      user: {
        id: userRow.id,
        countryCode: userRow.country_code || '',
        mobile: userRow.mobile || '',
        phoneNumber: userRow.phone_number || `+${userRow.country_code || ''}${userRow.mobile || ''}`,
        fullName: userRow.full_name || '',
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
        walletBalance: userRow.balance || 0,
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

router.post('/upload-avatar', (req, res) => {
  avatarUpload.single('file')(req, res, (err) => {
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
    return res.json({ success: true, imageUrl, url: imageUrl });
  });
});

module.exports = router;
