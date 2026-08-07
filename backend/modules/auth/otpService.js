const crypto = require('crypto');
const axios = require('axios');

/**
 * Generates a cryptographically random 6-digit OTP string.
 * @returns {string} 6-digit numeric string
 */
function generateOTP() {
  return crypto.randomInt(100000, 1000000).toString();
}

/**
 * Cleans country code (removes leading '+') and mobile number (removes non-digits).
 * @param {string} countryCode 
 * @param {string} mobile 
 * @returns {{ cleanCountryCode: string, cleanMobile: string }}
 */
function sanitizePhoneInputs(countryCode, mobile) {
  const cleanCountryCode = (countryCode || '').toString().trim().replace(/^\+/, '');
  const cleanMobile = (mobile || '').toString().trim().replace(/\D/g, '');
  return { cleanCountryCode, cleanMobile };
}

/**
 * Sends a 6-digit OTP to the recipient's mobile number via Authkey WhatsApp OTP API.
 * 
 * Authkey API format:
 * GET https://api.authkey.io/request
 * Query Params: authkey, mobile, country_code, wid, 1 (OTP value)
 * 
 * @param {string} countryCode e.g. '91' or '+91'
 * @param {string} mobile e.g. '9876543210'
 * @param {string} otp 6-digit OTP string
 * @returns {Promise<{ success: boolean, message?: string }>}
 */
async function sendWhatsAppOtp(countryCode, mobile, otp) {
  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(countryCode, mobile);
  const apiKey = process.env.AUTHKEY_API_KEY;
  const wid = process.env.AUTHKEY_WID;

  if (!apiKey || !wid) {
    console.warn('⚠️ AUTHKEY_API_KEY or AUTHKEY_WID missing from environment variables.');
  }

  // Obfuscate mobile for secure logging (never log raw OTP)
  const maskedMobile = cleanMobile.length >= 4 
    ? '*'.repeat(cleanMobile.length - 4) + cleanMobile.slice(-4) 
    : '****';

  console.log(`📱 Triggering Authkey WhatsApp OTP delivery to country: +${cleanCountryCode}, mobile: ${maskedMobile}`);

  // In local test / dev mode when authkey credentials are empty or stubbed, log sanitized debug info
  if (!apiKey || apiKey === 'your_authkey_api_key_here' || apiKey === 'mock_authkey_key') {
    console.log(`[DEV MODE] Authkey API key not configured or mock key used. OTP generation successful for ${maskedMobile}.`);
    // Note: Never print the OTP in production logs. In local dev stub mode, you can inspect Redis if needed.
    return { success: true, message: 'OTP send simulated in dev environment.' };
  }

  try {
    const response = await axios.get('https://api.authkey.io/request', {
      params: {
        authkey: apiKey,
        mobile: cleanMobile,
        country_code: cleanCountryCode,
        wid: wid,
        '1': otp,
      },
      timeout: 10000,
    });

    if (response.status === 200) {
      console.log(`✅ Authkey WhatsApp OTP response received for ${maskedMobile}. Status: ${response.status}`);
      return { success: true };
    } else {
      const errMsg = response.data?.Message || response.data?.message || `Authkey API HTTP ${response.status}`;
      console.error(`❌ Authkey API non-200 response: HTTP ${response.status}`, response.data);

      // In non-production development mode, if Authkey fails due to invalid key or zero balance, simulate OTP so dev flow is unblocked
      if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
        console.warn(`⚠️ [DEV FALLBACK] Authkey error: "${errMsg}". Simulating OTP delivery for testing.`);
        return { success: true, message: `[DEV] Simulated OTP: ${otp}` };
      }

      return { success: false, message: errMsg };
    }
  } catch (err) {
    const errorData = err.response?.data;
    const errMsg = errorData?.Message || errorData?.message || err.message || 'WhatsApp OTP delivery service unavailable.';
    console.error(`❌ Error calling Authkey WhatsApp OTP API:`, errorData || err.message);

    if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
      console.warn(`⚠️ [DEV FALLBACK] Authkey call error: "${errMsg}". Simulating OTP delivery for testing.`);
      return { success: true, message: `[DEV] Simulated OTP: ${otp}` };
    }

    return { success: false, message: errMsg };
  }
}

module.exports = {
  generateOTP,
  sanitizePhoneInputs,
  sendWhatsAppOtp,
};
