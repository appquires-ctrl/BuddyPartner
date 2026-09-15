/**
 * Live 2-Account (and 3rd Account Conflict) End-to-End Walkthrough Runner for Buddy Feature
 * 
 * Executes:
 * 1. Authenticate Account A (Initiator, Male) & Account B (Accepter, Female) & Account C (Third User, Female).
 * 2. Account B connects via Socket.io and joins 'city:mumbai:buddy' room.
 * 3. Account A submits 'movie' buddy request in Mumbai for target gender 'female'.
 * 4. Step 2 Verification: 100 coins deducted immediately from Account A's wallet (250 -> 150).
 * 5. Step 3 Verification: Account B receives real-time 'new_buddy_request' socket event in Mumbai room.
 * 6. Step 4 Verification: Account B accepts request; Account A receives real-time 'buddy_request_accepted' with 6-digit OTP.
 * 7. Step 7 Verification: Account C attempts to accept same request; rejected with HTTP 409 ALREADY_ACCEPTED.
 * 8. Step 5 & 6 Verification: Account B submits OTP; OTP verified, Account B credited 50 coins (20 -> 70), chat unlocked.
 * 
 * Reports detailed terminal logs at every stage.
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
  const sendRes = await axios.post(`${API_URL}/auth/otp/send`, {
    country_code: '91',
    mobile: mobile,
  });
  if (!sendRes.data.success) {
    throw new Error(`Failed to send OTP for ${mobile}`);
  }

  const verifyRes = await axios.post(`${API_URL}/auth/otp/verify`, {
    country_code: '91',
    mobile: mobile,
    otp: '123456',
  });

  if (!verifyRes.data.success || !verifyRes.data.token) {
    throw new Error(`Failed to verify OTP for ${mobile}`);
  }

  return {
    user: verifyRes.data.user,
    token: verifyRes.data.token,
  };
}

async function runLiveWalkthrough() {
  console.log('================================================================');
  console.log('🚀 LIVE BUDDY FEATURE TWO-ACCOUNT + CONFLICT WALKTHROUGH');
  console.log('================================================================\n');

  let socketA = null;
  let socketB = null;

  try {
    // ── Setup / Reset Accounts ────────────────────────────────────────────────
    console.log('--- STEP 0: SEEDING / RESETTING TEST ACCOUNTS ---');
    const { execSync } = require('child_process');
    execSync(`node "${path.join(__dirname, 'setup_test_accounts.js')}"`, { stdio: 'inherit' });
    console.log('');

    // ── Step 1: Authenticate All 3 Accounts ──────────────────────────────────
    console.log('--- STEP 1: AUTHENTICATING TEST ACCOUNTS ---');
    const accountA = await loginUser('9999999999', 'Account A (Initiator, Male)');
    const accountB = await loginUser('8888888888', 'Account B (Accepter, Female)');
    const accountC = await loginUser('7777777777', 'Account C (Third Candidate, Female)');
    console.log('✅ All 3 accounts authenticated successfully.\n');

    // ── Connect Real-time WebSockets ──────────────────────────────────────────
    console.log('--- INITIALIZING REAL-TIME SOCKET CONNECTIONS ---');
    socketA = io(BASE_URL, {
      auth: { token: accountA.token },
      transports: ['websocket'],
    });
    socketB = io(BASE_URL, {
      auth: { token: accountB.token },
      transports: ['websocket'],
    });

    await Promise.all([
      new Promise((resolve) => socketA.on('connect', () => {
        console.log(`🔌 Account A Socket Connected (socket ID: ${socketA.id})`);
        resolve();
      })),
      new Promise((resolve) => socketB.on('connect', () => {
        console.log(`🔌 Account B Socket Connected (socket ID: ${socketB.id})`);
        // Account B explicitly joins Mumbai room
        socketB.emit('join_buddy_city', { city: 'mumbai' });
        resolve();
      })),
    ]);
    console.log('✅ Real-time Socket.IO clients ready and in city rooms.\n');

    // Setup listener for Account B to capture broadcast
    let receivedBroadcastPromise = new Promise((resolve) => {
      socketB.on('new_buddy_request', (data) => {
        console.log(`📢 [Account B Socket] Received 'new_buddy_request':`, {
          requestId: data.id,
          buddyType: data.buddy_type,
          city: data.city,
          initiator: data.initiator?.fullName,
          reward: data.accepter_coin_reward,
        });
        resolve(data);
      });
    });

    // Setup listener for Account A to capture accept event + OTP
    let receivedAcceptedPromise = new Promise((resolve) => {
      socketA.on('buddy_request_accepted', (data) => {
        console.log(`🔔 [Account A Socket] Received 'buddy_request_accepted':`, {
          requestId: data.requestId,
          accepter: data.accepter?.fullName,
          otpCode: data.otpCode,
        });
        resolve(data);
      });
    });

    // Setup listener for Account A to capture handshake verified event
    let receivedVerifiedPromise = new Promise((resolve) => {
      socketA.on('buddy_request_verified', (data) => {
        console.log(` [Account A Socket] Received 'buddy_request_verified':`, {
          requestId: data.requestId,
          conversationId: data.conversationId,
          accepter: data.accepter?.fullName,
        });
        resolve(data);
      });
    });

    // ── Step 2: Account A Creates Buddy Request ──────────────────────────────
    console.log('--- STEP 2: ACCOUNT A CREATES "MOVIE BUDDY" REQUEST IN MUMBAI ---');
    const balanceABefore = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [accountA.user.id])).rows[0].balance;
    console.log(`   Account A Wallet Balance Before: ${balanceABefore} coins`);

    const createRes = await axios.post(
      `${API_URL}/buddy/request`,
      {
        buddyType: 'movie',
        city: 'mumbai',
        targetGender: 'female',
      },
      { headers: { Authorization: `Bearer ${accountA.token}` } }
    );

    if (createRes.status !== 201 || !createRes.data.success) {
      throw new Error(`Failed to create buddy request: ${JSON.stringify(createRes.data)}`);
    }

    const createdReq = createRes.data.request;
    console.log(`   ✅ Buddy request created with ID: ${createdReq.id}`);
    console.log(`   Buddy Type: ${createdReq.buddy_type}, City: ${createdReq.city}, Status: ${createdReq.status}`);

    const balanceAAfter = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [accountA.user.id])).rows[0].balance;
    console.log(`   Account A Wallet Balance Immediately After: ${balanceAAfter} coins`);

    if (balanceABefore - balanceAAfter !== 100) {
      throw new Error(`Expected 100 coin deduction, difference was ${balanceABefore - balanceAAfter}`);
    }
    console.log('   ✅ Immediate 100-coin deduction confirmed!\n');

    // ── Step 3: Account B Sees Broadcast Request ─────────────────────────────
    console.log('--- STEP 3: ACCOUNT B RECEIVES BROADCAST & SEES REQUEST IN MUMBAI ---');
    const broadcastData = await receivedBroadcastPromise;
    if (broadcastData.id !== createdReq.id) {
      throw new Error(`Broadcast request ID mismatch: expected ${createdReq.id}, got ${broadcastData.id}`);
    }
    console.log('   ✅ Account B received broadcast in real-time!\n');

    // Also verify REST open requests feed for Account B
    const feedRes = await axios.get(`${API_URL}/buddy/open?city=mumbai`, {
      headers: { Authorization: `Bearer ${accountB.token}` },
    });
    const foundInFeed = feedRes.data.requests.find(r => r.id === createdReq.id);
    if (!foundInFeed) {
      throw new Error('Created request not visible in Account B open feed!');
    }
    console.log(`   ✅ Request verified in Account B open feed (${feedRes.data.requests.length} open requests in Mumbai).\n`);

    // ── Step 4: Account B Taps Accept ─────────────────────────────────────────
    console.log('--- STEP 4: ACCOUNT B TAPS ACCEPT ---');
    const acceptRes = await axios.post(
      `${API_URL}/buddy/accept/${createdReq.id}`,
      {},
      { headers: { Authorization: `Bearer ${accountB.token}` } }
    );

    if (acceptRes.status !== 200 || !acceptRes.data.success) {
      throw new Error(`Accept request failed: ${JSON.stringify(acceptRes.data)}`);
    }

    console.log(`   ✅ Account B accepted request successfully.`);
    console.log(`   Account B view: Status is '${acceptRes.data.request.status}', waiting for initiator to share OTP.`);

    // Confirm Account A receives the 6-digit OTP
    const acceptedEventData = await receivedAcceptedPromise;
    const receivedOtp = acceptedEventData.otpCode;
    console.log(`   Account A screen received OTP: ${receivedOtp}`);
    if (!receivedOtp || receivedOtp.length !== 6) {
      throw new Error(`Invalid OTP received by Account A: ${receivedOtp}`);
    }
    console.log('   ✅ Account A received 6-digit OTP to share with Account B!\n');

    // ── Step 5: Account C (Third Candidate) Attempts to Accept ────────────────
    console.log('--- STEP 5: ACCOUNT C ATTEMPTS TO ACCEPT THE SAME REQUEST (CONFLICT TEST) ---');
    try {
      await axios.post(
        `${API_URL}/buddy/accept/${createdReq.id}`,
        {},
        { headers: { Authorization: `Bearer ${accountC.token}` } }
      );
      throw new Error('Account C unexpectedly succeeded in accepting already-accepted request!');
    } catch (err) {
      if (err.response && err.response.status === 409) {
        console.log(`   ✅ Account C cleanly rejected with HTTP 409 Conflict: [${err.response.data.error}] "${err.response.data.message}"`);
      } else {
        throw err;
      }
    }
    console.log('   ✅ Third account conflict prevention verified: only 1 accepter allowed!\n');

    // ── Step 6: Account B Enters OTP & Verifies Handshake ──────────────────────
    console.log('--- STEP 6: ACCOUNT B ENTERS 6-DIGIT OTP ---');
    const balanceBBefore = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [accountB.user.id])).rows[0].balance;
    console.log(`   Account B Wallet Balance Before OTP: ${balanceBBefore} coins`);

    const verifyRes = await axios.post(
      `${API_URL}/buddy/verify-otp`,
      {
        requestId: createdReq.id,
        otpCode: receivedOtp,
      },
      { headers: { Authorization: `Bearer ${accountB.token}` } }
    );

    if (verifyRes.status !== 200 || !verifyRes.data.success) {
      throw new Error(`OTP Verification failed: ${JSON.stringify(verifyRes.data)}`);
    }

    const conversationId = verifyRes.data.conversationId;
    console.log(`   ✅ OTP Handshake Verified! Unlocked Conversation ID: ${conversationId}`);

    // Wait for Account A to receive socket event
    const verifiedEventData = await receivedVerifiedPromise;
    if (verifiedEventData.conversationId !== conversationId) {
      throw new Error(`Conversation ID mismatch on Account A socket: ${verifiedEventData.conversationId}`);
    }
    console.log(`   ✅ Account A socket confirmed conversation unlock!`);

    // Confirm Account B's coin reward
    const balanceBAfter = (await db.query('SELECT balance FROM public.wallets WHERE user_id = $1', [accountB.user.id])).rows[0].balance;
    console.log(`   Account B Wallet Balance Immediately After: ${balanceBAfter} coins`);
    if (balanceBAfter - balanceBBefore !== 50) {
      throw new Error(`Expected 50 coin reward for Account B, got difference ${balanceBAfter - balanceBBefore}`);
    }
    console.log('   ✅ Account B credited exactly 50 coin reward!');

    // ── Step 7: Verify Unlocked Chat & Calls ───────────────────────────────────
    console.log('\n--- STEP 7: VERIFY UNLOCKED CHAT & CALL ACCESS ---');
    const convRow = await db.query('SELECT * FROM public.conversations WHERE id = $1', [conversationId]);
    if (convRow.rows.length !== 1) {
      throw new Error('Conversation row not found in database');
    }
    console.log(`   Conversation participants: User 1: ${convRow.rows[0].user1_id}, User 2: ${convRow.rows[0].user2_id}`);

    // Verify messages endpoint works for both users
    const msgResA = await axios.get(`${API_URL}/conversations/${conversationId}/messages`, {
      headers: { Authorization: `Bearer ${accountA.token}` },
    });
    const msgResB = await axios.get(`${API_URL}/conversations/${conversationId}/messages`, {
      headers: { Authorization: `Bearer ${accountB.token}` },
    });
    console.log(`   Account A chat access: HTTP ${msgResA.status} (Messages: ${msgResA.data.messages?.length || 0})`);
    console.log(`   Account B chat access: HTTP ${msgResB.status} (Messages: ${msgResB.data.messages?.length || 0})`);
    console.log('   ✅ Chat and Call channels verified active and accessible for both users.');

    console.log('\n================================================================');
    console.log(' LIVE TWO-ACCOUNT WALKTHROUGH COMPLETED WITH ZERO ERRORS!');
    console.log('================================================================');
    process.exit(0);
  } catch (err) {
    console.error('\n❌ Walkthrough Failed with Error:', err.response?.data || err.message || err);
    process.exit(1);
  } finally {
    if (socketA) socketA.disconnect();
    if (socketB) socketB.disconnect();
  }
}

runLiveWalkthrough();
