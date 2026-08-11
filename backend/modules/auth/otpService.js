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
 * Sends a 6-digit OTP to the recipient's mobile number via MSG91 WhatsApp Outbound Bulk API.
 * 
 * MSG91 API format:
 * POST https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/
 * Headers: authkey, Content-Type: application/json
 * Body: {
 *   integrated_number: "916006329803",
 *   content_type: "template",
 *   payload: {
 *     messaging_product: "whatsapp",
 *     type: "template",
 *     template: {
 *       name: "otp",
 *       language: { code: "en", policy: "deterministic" },
 *       namespace: null,
 *       to_and_components: [
 *         {
 *           to: ["919876543210"],
 *           components: { ... }
 *         }
 *       ]
 *     }
 *   }
 * }
 * 
 * @param {string} countryCode e.g. '91' or '+91'
 * @param {string} mobile e.g. '9876543210'
 * @param {string} otp 6-digit OTP string
 * @returns {Promise<{ success: boolean, message?: string }>}
 */
async function sendWhatsAppOtp(countryCode, mobile, otp) {
  const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(countryCode, mobile);
  const authKey = process.env.MSG91_AUTHKEY || process.env.AUTHKEY_API_KEY;
  const integratedNumber = process.env.MSG91_INTEGRATED_NUMBER || '916006329803';
  const templateName = process.env.MSG91_TEMPLATE_NAME || 'otp';

  if (!authKey) {
    console.warn('⚠️ MSG91_AUTHKEY / AUTHKEY_API_KEY missing from environment variables.');
  }

  // Obfuscate mobile for secure logging (never log raw OTP)
  const maskedMobile = cleanMobile.length >= 4 
    ? '*'.repeat(cleanMobile.length - 4) + cleanMobile.slice(-4) 
    : '****';
  const fullRecipientNumber = `${cleanCountryCode}${cleanMobile}`;

  console.log(`📱 Triggering MSG91 WhatsApp OTP delivery to country: +${cleanCountryCode}, mobile: ${maskedMobile}`);

  // In local test / dev mode when MSG91 credentials are empty or stubbed, log sanitized debug info
  if (!authKey || authKey === 'your_authkey_api_key_here' || authKey === 'mock_authkey_key' || authKey === 'your_msg91_authkey_here') {
    console.log(`[DEV MODE] MSG91 Authkey not configured or mock key used. OTP generation successful for ${maskedMobile}.`);
    return { success: true, message: 'OTP send simulated in dev environment.' };
  }

  const components = {
    body_1: {
      type: 'text',
      value: otp,
    },
    button_1: {
      subtype: 'url',
      type: 'text',
      value: otp,
    },
  };

  const payloadData = {
    integrated_number: integratedNumber,
    content_type: 'template',
    payload: {
      messaging_product: 'whatsapp',
      type: 'template',
      template: {
        name: templateName,
        language: {
          code: 'en',
          policy: 'deterministic',
        },
        namespace: null,
        to_and_components: [
          {
            to: [fullRecipientNumber],
            components: components,
          },
        ],
      },
    },
  };

  try {
    const response = await axios.post(
      'https://api.msg91.com/api/v5/whatsapp/whatsapp-outbound-message/bulk/',
      payloadData,
      {
        headers: {
          'Content-Type': 'application/json',
          authkey: authKey,
        },
        timeout: 10000,
      }
    );

    const isSuccessStatus = response.status >= 200 && response.status < 300;
    const hasNoErrorFlag = response.data?.hasError === false || response.data?.status === 'success' || response.data?.type === 'success';

    if (isSuccessStatus && (hasNoErrorFlag || !response.data?.hasError)) {
      console.log(`✅ MSG91 WhatsApp OTP response received for ${maskedMobile}. Status: ${response.status}`);
      return { success: true };
    } else {
      const errMsg = response.data?.message || response.data?.Message || response.data?.error || `MSG91 API HTTP ${response.status}`;
      console.error(`❌ MSG91 API non-success response: HTTP ${response.status}`, response.data);

      if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
        console.warn(`⚠️ [DEV FALLBACK] MSG91 error: "${errMsg}". Simulating OTP delivery for testing.`);
        return { success: true, message: `[DEV] Simulated OTP: ${otp}` };
      }

      return { success: false, message: errMsg };
    }
  } catch (err) {
    const errorData = err.response?.data;
    const errMsg = errorData?.message || errorData?.Message || errorData?.error || err.message || 'WhatsApp OTP delivery service unavailable.';
    console.error(`❌ Error calling MSG91 WhatsApp OTP API:`, errorData || err.message);

    if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_DEV_OTP_FALLBACK === 'true') {
      console.warn(`⚠️ [DEV FALLBACK] MSG91 call error: "${errMsg}". Simulating OTP delivery for testing.`);
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
