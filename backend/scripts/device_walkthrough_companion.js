/**
 * Device Walkthrough Companion
 * 
 * Runs in parallel with the live Flutter app running on the emulator.
 * When the user on the emulator submits the Buddy request:
 * 1. Account B receives the real-time broadcast in 'city:mumbai:buddy'.
 * 2. Account B accepts the request.
 * 3. Account C tries to accept and gets 409 Conflict.
 * 4. Account B submits the 6-digit OTP to verify and unlock chat.
 * 5. Account A on the emulator live updates into the unlocked chat screen with the Call button!
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '../.env') });
const axios = require('axios');
const io = require('socket.io-client');
const db = require('../db');

const BASE_URL = 'http://localhost:3000';
const API_URL = `${BASE_URL}/api`;

async function loginUser(mobile, name) {
  console.log(`🔑 Logging in ${name} (+91 ${mobile})...`);
  const verifyRes = await axios.post(`${API_URL}/auth/otp/verify`, {
    country_code: '91',
    mobile: mobile,
    otp: '123456',
  });
  return {
    user: verifyRes.data.user,
    token: verifyRes.data.token,
  };
}

async function startCompanion() {
  console.log('================================================================');
  console.log('📡 STARTING DEVICE WALKTHROUGH COMPANION (Account B & C)');
  console.log('================================================================\n');

  const accountB = await loginUser('8888888888', 'Account B (Ananya Verma)');
  const accountC = await loginUser('7777777777', 'Account C (Pooja Patel)');

  const socketB = io(BASE_URL, {
    auth: { token: accountB.token },
    transports: ['websocket'],
  });

  socketB.on('connect', () => {
    console.log(`🔌 [Account B Socket] Connected (ID: ${socketB.id})`);
    socketB.emit('join_buddy_city', { city: 'mumbai' });
    console.log(`📍 [Account B Socket] Joined room: city:mumbai:buddy`);
    console.log('⏳ Waiting for emulator to tap "Broadcast Request"...');
  });

  socketB.on('new_buddy_request', async (data) => {
    console.log('\n-------------------------------------------------------------');
    console.log('📢 [Account B Socket] RECEIVED LIVE BROADCAST FROM EMULATOR:');
    console.log(`   Request ID: ${data.id}`);
    console.log(`   Buddy Type: ${data.buddy_type}`);
    console.log(`   City: ${data.city}`);
    console.log(`   Initiator: ${data.initiator?.fullName}`);
    console.log(`   Accepter Reward: ${data.accepter_coin_reward} Coins`);
    console.log('-------------------------------------------------------------\n');

    // Wait 1.5 seconds for visual effect on initiator screen
    await new Promise(r => setTimeout(r, 1500));

    console.log(`🤝 [Account B] Tapping ACCEPT on request ${data.id}...`);
    const acceptRes = await axios.post(
      `${API_URL}/buddy/requests/${data.id}/accept`,
      {},
      { headers: { Authorization: `Bearer ${accountB.token}` } }
    );
    console.log(`   ✅ Account B accept response:`, acceptRes.data.message);

    // Test Account C conflict immediately
    console.log(`\n🚫 [Account C] Attempting to accept already-accepted request ${data.id}...`);
    try {
      await axios.post(
        `${API_URL}/buddy/requests/${data.id}/accept`,
        {},
        { headers: { Authorization: `Bearer ${accountC.token}` } }
      );
      console.error('❌ Account C accept should have failed!');
    } catch (err) {
      console.log(`   ✅ Account C cleanly rejected with HTTP ${err.response?.status}: [${err.response?.data?.error}] "${err.response?.data?.message}"`);
    }

    // Get the OTP generated in DB
    const reqRow = (await db.query('SELECT otp_code FROM public.buddy_requests WHERE id = $1', [data.id])).rows[0];
    const otpCode = reqRow.otp_code;
    console.log(`\n🔢 [Handshake] 6-digit OTP generated for Account A: ${otpCode}`);

    // Wait 2 seconds so initiator sees the OTP modal
    console.log('⏳ Waiting 2 seconds before entering OTP...');
    await new Promise(r => setTimeout(r, 2000));

    console.log(`\n✍️ [Account B] Entering OTP ${otpCode} to verify...`);
    const verifyRes = await axios.post(
      `${API_URL}/buddy/requests/${data.id}/verify-otp`,
      { otpCode },
      { headers: { Authorization: `Bearer ${accountB.token}` } }
    );
    console.log(`   ✅ OTP Verified! Conversation ID: ${verifyRes.data.conversationId}`);
    console.log(`   ✅ Account B Credited: ${verifyRes.data.rewardCoins} coins (New Balance: ${verifyRes.data.newBalance})`);
    console.log('\n Real-time Handshake complete! Check emulator for unlocked Chat & Call screen.');
    process.exit(0);
  });
}

startCompanion().catch(e => { console.error(e); process.exit(1); });
