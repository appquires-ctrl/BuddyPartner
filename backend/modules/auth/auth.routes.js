const express = require('express');
const router = express.Router();
const jwt = require('jsonwebtoken');
const db = require('../../db');
const { authMiddleware } = require('../../middleware/auth.middleware');

const JWT_SECRET = process.env.JWT_SECRET || 'loopcall_fallback_jwt_secret_key_change_me_in_prod';
const OTP_EXPIRATION_MINUTES = 5;

// Cache for Google's public certificates
let googlePublicKeysCache = null;
let googlePublicKeysExpiresAt = 0;

async function getGooglePublicKeys() {
  if (googlePublicKeysCache && Date.now() < googlePublicKeysExpiresAt) {
    return googlePublicKeysCache;
  }
  const response = await fetch('https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com');
  if (!response.ok) {
    throw new Error('Failed to fetch Google public keys');
  }
  const keys = await response.json();
  const cacheControl = response.headers.get('cache-control');
  let maxAge = 3600;
  if (cacheControl) {
    const match = cacheControl.match(/max-age=(\d+)/);
    if (match) maxAge = parseInt(match[1], 10);
  }
  googlePublicKeysCache = keys;
  googlePublicKeysExpiresAt = Date.now() + (maxAge * 1000);
  return keys;
}

async function verifyFirebaseToken(idToken) {
  const decodedHeader = jwt.decode(idToken, { complete: true });
  if (!decodedHeader || !decodedHeader.header || !decodedHeader.header.kid) {
    throw new Error('Invalid token structure');
  }
  const kid = decodedHeader.header.kid;
  const publicKeys = await getGooglePublicKeys();
  const cert = publicKeys[kid];
  if (!cert) {
    throw new Error('Firebase public key expired or invalid');
  }
  const decoded = jwt.verify(idToken, cert, { algorithms: ['RS256'] });
  const projectId = decoded.aud;
  if (decoded.iss !== `https://securetoken.google.com/${projectId}`) {
    throw new Error('Invalid token issuer');
  }
  return decoded;
}

/**
 * Generate a random 6-digit verification code.
 */
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/**
 * Endpoint: POST /api/auth/send-otp
 * Generates and sends a temporary verification code to the phone number.
 */
router.post('/send-otp', async (req, res) => {
  const { phone } = req.body;

  if (!phone || typeof phone !== 'string' || phone.trim().length === 0) {
    return res.status(400).json({ error: 'Valid phone number is required.' });
  }

  const cleanPhone = phone.trim();
  let otpCode = generateOTP();
  const expiresAt = new Date(Date.now() + OTP_EXPIRATION_MINUTES * 60 * 1000);

  try {
    // Delete any old OTPs for this number to clean up
    await db.query(
      'DELETE FROM public.otp_verifications WHERE phone_number = $1',
      [cleanPhone]
    );

    // If MSG91 widget credentials are configured, attempt real-time Widget OTP delivery
    if (process.env.MSG91_AUTH_KEY && process.env.MSG91_WIDGET_ID) {
      try {
        console.log(`📱 Triggering MSG91 SendOTP Widget API for ${cleanPhone}...`);
        const response = await fetch('https://api.msg91.com/api/v5/widget/sendOtp', {
          method: 'POST',
          headers: {
            'authkey': process.env.MSG91_AUTH_KEY,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            widgetId: process.env.MSG91_WIDGET_ID,
            identifier: cleanPhone
          })
        });
        const data = await response.json();
        if (data.type === 'success') {
          // Store the MSG91 request ID inside the otp_code column
          otpCode = data.message;
          console.log(`✅ MSG91 SendOTP initiated. reqId: ${otpCode}`);
        } else {
          console.error('❌ MSG91 SendOTP widget returned error status:', data);
        }
      } catch (msg91Err) {
        console.error('❌ Failed to request MSG91 SendOTP widget:', msg91Err.message);
      }
    } else if (process.env.TWILIO_ACCOUNT_SID && process.env.TWILIO_AUTH_TOKEN && process.env.TWILIO_PHONE_NUMBER) {
      // If Twilio credentials are configured, attempt Twilio SMS delivery
      try {
        const twilio = require('twilio')(process.env.TWILIO_ACCOUNT_SID, process.env.TWILIO_AUTH_TOKEN);
        await twilio.messages.create({
          body: `Your LoopCall verification code is: ${otpCode}. It will expire in 5 minutes.`,
          from: process.env.TWILIO_PHONE_NUMBER,
          to: cleanPhone,
        });
        console.log(`📱 Real-time SMS OTP sent successfully via Twilio to ${cleanPhone}`);
      } catch (smsErr) {
        console.error('❌ Failed to send SMS via Twilio:', smsErr.message);
      }
    }

    // Insert new OTP (can be local 6-digit code or MSG91 reqId)
    await db.query(
      'INSERT INTO public.otp_verifications (phone_number, otp_code, expires_at) VALUES ($1, $2, $3)',
      [cleanPhone, otpCode, expiresAt]
    );

    // Console output fallback for development/test retrieval
    console.log(`\n========================================`);
    console.log(`[SMS OTP DEBUG]`);
    console.log(`To:   ${cleanPhone}`);
    console.log(`Code: ${otpCode}`);
    console.log(`Expires: ${expiresAt.toISOString()}`);
    console.log(`========================================\n`);

    res.json({ success: true, message: 'Verification code sent.' });
  } catch (err) {
    console.error('Error sending OTP:', err.message);
    res.status(500).json({ error: 'Internal server error during verification.' });
  }
});

/**
 * Endpoint: POST /api/auth/verify-otp
 * Verifies code, provisions new user/wallet on-demand, and signs a JWT session.
 */
router.post('/verify-otp', async (req, res) => {
  const { phone, otp } = req.body;

  if (!phone || !otp) {
    return res.status(400).json({ error: 'Phone number and verification code are required.' });
  }

  const cleanPhone = phone.trim();
  const cleanOtp = otp.trim();

  try {
    // Fetch latest valid OTP record
    const result = await db.query(
      'SELECT * FROM public.otp_verifications WHERE phone_number = $1 AND expires_at > NOW() LIMIT 1',
      [cleanPhone]
    );

    if (result.rows.length === 0) {
      return res.status(400).json({ error: 'Invalid or expired verification code.' });
    }

    const record = result.rows[0];
    let isOtpValid = false;

    // Check if the record holds a standard local 6-digit code or a MSG91 request ID
    if (record.otp_code.length <= 6) {
      isOtpValid = (record.otp_code === cleanOtp);
    } else {
      // MSG91 verification
      if (process.env.MSG91_AUTH_KEY && process.env.MSG91_WIDGET_ID) {
        try {
          console.log(`📱 Verifying OTP with MSG91. reqId: ${record.otp_code}, code: ${cleanOtp}...`);
          const verifyRes = await fetch('https://api.msg91.com/api/v5/widget/verifyOtp', {
            method: 'POST',
            headers: {
              'authkey': process.env.MSG91_AUTH_KEY,
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              widgetId: process.env.MSG91_WIDGET_ID,
              reqId: record.otp_code,
              otp: cleanOtp
            })
          });
          const verifyData = await verifyRes.json();
          if (verifyData.type === 'success') {
            isOtpValid = true;
            console.log('✅ MSG91 OTP verified successfully.');
          } else {
            console.error('❌ MSG91 OTP verification failed:', verifyData);
          }
        } catch (msg91Err) {
          console.error('❌ Failed to call MSG91 verification API:', msg91Err.message);
        }
      }
    }

    if (!isOtpValid) {
      return res.status(400).json({ error: 'Invalid or expired verification code.' });
    }

    // OTP verified, consume it
    await db.query(
      'DELETE FROM public.otp_verifications WHERE phone_number = $1',
      [cleanPhone]
    );

    // Check if user already exists
    let userResult = await db.query(
      'SELECT id, phone_number, full_name FROM public.users WHERE phone_number = $1',
      [cleanPhone]
    );

    let user;

    if (userResult.rows.length === 0) {
      const insertUserRes = await db.query(
        'INSERT INTO public.users (phone_number) VALUES ($1) RETURNING id, phone_number, full_name',
        [cleanPhone]
      );
      user = insertUserRes.rows[0];
    } else {
      user = userResult.rows[0];
    }

    // Sign JWT
    const payload = { id: user.id, phone: user.phone_number };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

    res.json({
      success: true,
      token,
      isProfileComplete: !!user.full_name,
    });
  } catch (err) {
    console.error('Error verifying OTP:', err.message);
    res.status(500).json({ error: 'Internal server error verifying authentication.' });
  }
});

/**
 * Endpoint: POST /api/auth/firebase-login
 * Verifies a Firebase ID token, registers/finds the user, and returns a custom signed JWT.
 */
router.post('/firebase-login', async (req, res) => {
  const { phone, idToken } = req.body;

  if (!phone || !idToken) {
    return res.status(400).json({ error: 'Phone number and Firebase ID Token are required.' });
  }

  const cleanPhone = phone.trim();

  try {
    // 1. Verify the Firebase ID Token
    let decoded;
    try {
      decoded = await verifyFirebaseToken(idToken);
    } catch (verifyErr) {
      console.error('Firebase token verification failed:', verifyErr.message);
      return res.status(401).json({ error: 'Invalid or expired authentication token.' });
    }

    // 2. Validate that the phone number in the verified token matches the one requested
    const tokenPhone = decoded.phone_number;
    if (!tokenPhone || tokenPhone.replace(/\s+/g, '') !== cleanPhone.replace(/\s+/g, '')) {
      return res.status(400).json({ error: 'Token phone number mismatch.' });
    }

    // 3. Check if user already exists
    let userResult = await db.query(
      'SELECT id, phone_number, full_name FROM public.users WHERE phone_number = $1',
      [cleanPhone]
    );

    let user;
    if (userResult.rows.length === 0) {
      // Create new user profile row
      const insertUserRes = await db.query(
        'INSERT INTO public.users (phone_number) VALUES ($1) RETURNING id, phone_number, full_name',
        [cleanPhone]
      );
      user = insertUserRes.rows[0];
    } else {
      user = userResult.rows[0];
    }

    // 4. Sign JWT session for our backend
    const payload = { id: user.id, phone: user.phone_number };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '30d' });

    res.json({
      success: true,
      token,
      isProfileComplete: !!user.full_name,
    });
  } catch (err) {
    console.error('Error in firebase-login:', err.message);
    res.status(500).json({ error: 'Internal server error verifying authentication.' });
  }
});

/**
 * Endpoint: POST /api/auth/profile
 * Updates authenticated user profile details.
 */
router.post('/profile', authMiddleware, async (req, res) => {
  const userId = req.user.id;
  const { fullName, dob, gender, language, avatarSeed, avatarStyle, isTelecaller, country, state, city, latitude, longitude } = req.body;

  try {
    if (fullName) {
      const cleanGender = (gender || '').toLowerCase();
      const isFemale = cleanGender === 'female' || cleanGender === 'girl' || cleanGender === 'woman';
      const telecallerVal = isFemale ? (typeof isTelecaller === 'boolean' ? isTelecaller : null) : null;

      await db.query(
        `UPDATE public.users 
         SET full_name = $1, dob = $2, gender = $3, language = $4, avatar_seed = $5, avatar_style = $6, is_telecaller = $7 
         WHERE id = $8`,
        [fullName, dob || null, gender || null, language || null, avatarSeed || null, avatarStyle || 'avataaars', telecallerVal, userId]
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
      `SELECT u.id, u.phone_number, u.full_name, u.dob, u.gender, u.language, u.avatar_seed, u.avatar_style, u.is_telecaller, u.country, u.state, u.city, u.latitude, u.longitude, w.balance 
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
        phoneNumber: userRow.phone_number,
        fullName: userRow.full_name || '',
        dob: userRow.dob || null,
        gender: userRow.gender || '',
        language: userRow.language || '',
        avatarSeed: userRow.avatar_seed || null,
        avatarStyle: userRow.avatar_style || 'avataaars',
        isTelecaller: userRow.is_telecaller ?? null,
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


module.exports = router;
