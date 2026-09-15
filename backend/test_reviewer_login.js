const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '.env') });
const axios = require('axios');
const { app, server } = require('./server');

async function testReviewerLogin() {
  console.log('🧪 Testing Google Play Reviewer Test Account Login Flow...\n');
  
  const port = server.address()?.port || 3000;
  const baseUrl = `http://localhost:${port}/api/auth`;

  try {
    // 1. Send OTP to test mobile +91 9999999999
    console.log('Step 1: Sending OTP for +91 9999999999...');
    const sendRes = await axios.post(`${baseUrl}/otp/send`, {
      country_code: '91',
      mobile: '9999999999'
    });
    console.log('Send OTP Response:', sendRes.data);
    if (!sendRes.data.success) {
      throw new Error('Failed to send OTP to test account');
    }

    // 2. Verify with WRONG OTP (should fail)
    console.log('\nStep 2: Verifying with incorrect OTP 000000...');
    try {
      await axios.post(`${baseUrl}/otp/verify`, {
        country_code: '91',
        mobile: '9999999999',
        otp: '000000'
      });
      throw new Error('Wrong OTP unexpectedly succeeded!');
    } catch (err) {
      if (err.response && err.response.status === 400) {
        console.log('✅ Correctly rejected invalid OTP with 400 Bad Request');
      } else {
        throw err;
      }
    }

    // 3. Verify with CORRECT static OTP 123456 (should succeed)
    console.log('\nStep 3: Verifying with correct static test OTP 123456...');
    const verifyRes = await axios.post(`${baseUrl}/otp/verify`, {
      country_code: '91',
      mobile: '9999999999',
      otp: '123456'
    });
    console.log('Verify OTP Response:');
    console.log('- Success:', verifyRes.data.success);
    console.log('- User ID:', verifyRes.data.user.id);
    console.log('- Name:', verifyRes.data.user.fullName);
    console.log('- isProfileComplete:', verifyRes.data.isProfileComplete);
    console.log('- Token Present:', !!verifyRes.data.token);

    if (verifyRes.data.success && verifyRes.data.token && verifyRes.data.isProfileComplete) {
      console.log('\n ALL TESTS PASSED! Google Play reviewer can seamlessly log in.');
    } else {
      throw new Error('Verification response did not meet expectations');
    }
  } catch (error) {
    console.error('❌ Test failed:', error.response?.data || error.message);
  } finally {
    setTimeout(() => {
      process.exit(0);
    }, 500);
  }
}

// Wait for server to be listening
if (server.listening) {
  testReviewerLogin();
} else {
  server.on('listening', testReviewerLogin);
}
