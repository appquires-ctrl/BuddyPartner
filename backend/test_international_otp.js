require('dotenv').config();
const { sanitizePhoneInputs } = require('./modules/auth/otpService');

function testInternationalOtp() {
  console.log('🧪 Testing International Country Codes & Phone Number Parsing...');

  const testCases = [
    { countryCode: '+91', mobile: '9876543210', expectedCC: '91', expectedMobile: '9876543210' },
    { countryCode: '+1', mobile: '2025550143', expectedCC: '1', expectedMobile: '2025550143' },
    { countryCode: '+44', mobile: '7911123456', expectedCC: '44', expectedMobile: '7911123456' },
    { countryCode: '+971', mobile: '501234567', expectedCC: '971', expectedMobile: '501234567' },
    { countryCode: '+61', mobile: '412345678', expectedCC: '61', expectedMobile: '412345678' },
    { countryCode: '+49', mobile: '15123456789', expectedCC: '49', expectedMobile: '15123456789' },
    { countryCode: '+65', mobile: '91234567', expectedCC: '65', expectedMobile: '91234567' },
  ];

  for (const tc of testCases) {
    const { cleanCountryCode, cleanMobile } = sanitizePhoneInputs(tc.countryCode, tc.mobile);
    console.log(`Checking ${tc.countryCode} ${tc.mobile} -> CC: ${cleanCountryCode}, Mobile: ${cleanMobile}`);

    if (cleanCountryCode !== tc.expectedCC || cleanMobile !== tc.expectedMobile) {
      throw new Error(`Sanitization mismatch for ${tc.countryCode} ${tc.mobile}! Got CC=${cleanCountryCode}, Mobile=${cleanMobile}`);
    }
  }

  console.log('🎉 All International Country Code Tests Passed Successfully!');
  process.exit(0);
}

testInternationalOtp();
