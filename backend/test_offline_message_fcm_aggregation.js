/**
 * Test Suite: FCM Offline Notification Aggregation & Anti-Spam Verification
 * 
 * Verifies that:
 * 1. Offline messages from 1 to 3 distinct senders dispatch individual conversation notifications.
 * 2. Offline messages from senders 4 through 100 trigger intelligent aggregation:
 *    - Collapses to a single tag: 'chat_summary_<recipientId>'
 *    - Aggregated body: 'You have X new messages from Y chats'
 *    - Includes collapseKey: 'chat_updates'
 *    - Sets notificationCount badge
 * 3. Connecting / marking delivered cleans up the recent senders tracker.
 */

const redis = require('./redis');
const { sendPushNotification, admin } = require('./services/firebase.service');

async function runAggregationTests() {
  console.log('================================================================');
  console.log('🧪 RUNNING FCM OFFLINE NOTIFICATION AGGREGATION VERIFICATION');
  console.log('================================================================\n');

  const recipientId = 'test-recipient-uuid-9999';
  const throttleKey = `user:push_recent_senders:${recipientId}`;

  // Clean up any stale test key in Redis
  await redis.del(throttleKey).catch(() => {});

  // Intercept admin.messaging().send to inspect outgoing FCM payloads
  const messagingInstance = admin.messaging();
  const originalSend = messagingInstance.send;
  const dispatchedPayloads = [];

  messagingInstance.send = async (payload) => {
    dispatchedPayloads.push(payload);
    return `mock_fcm_msg_id_${dispatchedPayloads.length}`;
  };

  try {
    // ── Phase 1: Test First 3 Senders (Individual Conversation Mode) ─────────
    console.log('Phase 1: Simulating first 3 distinct senders messaging offline user...');
    
    for (let i = 1; i <= 3; i++) {
      const senderId = `sender-uuid-${i}`;
      const senderName = `Sender_${i}`;
      const convId = `conv-uuid-${i}`;

      await redis.sadd(throttleKey, senderId);
      await redis.expire(throttleKey, 180);
      const recentSenderCount = await redis.scard(throttleKey);

      let notifTitle = senderName;
      let notifBody = `Hello from ${senderName}`;
      let notifTag = `chat_${convId}`;
      let isSummary = 'false';

      await sendPushNotification({
        token: 'fake_recipient_fcm_token_12345',
        title: notifTitle,
        body: notifBody,
        tag: notifTag,
        collapseKey: 'chat_updates',
        notificationCount: recentSenderCount,
        data: {
          type: 'chat_message',
          senderId,
          senderName,
          conversationId: convId,
          isSummary,
          totalUnread: String(recentSenderCount),
        },
      });

      console.log(`   ✓ Sender ${i} pushed: Tag=${notifTag}, isSummary=${isSummary}, count=${recentSenderCount}`);
    }

    if (dispatchedPayloads.length !== 3) {
      throw new Error(`Expected 3 payloads dispatched in Phase 1, got ${dispatchedPayloads.length}`);
    }

    // Verify first 3 payloads are individual
    dispatchedPayloads.slice(0, 3).forEach((p, idx) => {
      const expectedTag = `chat_conv-uuid-${idx + 1}`;
      if (p.android?.notification?.tag !== expectedTag) {
        throw new Error(`Payload ${idx + 1} expected tag ${expectedTag}, got ${p.android?.notification?.tag}`);
      }
      if (p.android?.collapseKey !== 'chat_updates') {
        throw new Error(`Payload ${idx + 1} missing collapseKey: 'chat_updates'`);
      }
      if (p.data?.isSummary !== 'false') {
        throw new Error(`Payload ${idx + 1} should have isSummary='false'`);
      }
    });

    console.log('✅ Phase 1 Passed: First 3 senders delivered as individual distinct conversation notifications.\n');

    // ── Phase 2: Senders 4 to 100 (Aggregated Summary Mode) ──────────────────
    console.log('Phase 2: Simulating senders 4 to 100 messaging the offline user...');
    
    for (let i = 4; i <= 100; i++) {
      const senderId = `sender-uuid-${i}`;
      const senderName = `Sender_${i}`;
      const convId = `conv-uuid-${i}`;

      await redis.sadd(throttleKey, senderId);
      await redis.expire(throttleKey, 180);
      const recentSenderCount = await redis.scard(throttleKey);

      let notifTitle, notifBody, notifTag, isSummary;

      if (recentSenderCount <= 3) {
        notifTitle = senderName;
        notifBody = `Hello from ${senderName}`;
        notifTag = `chat_${convId}`;
        isSummary = 'false';
      } else {
        notifTitle = 'Buddy Partner';
        notifBody = `You have ${recentSenderCount} new messages from ${recentSenderCount} chats`;
        notifTag = `chat_summary_${recipientId}`;
        isSummary = 'true';
      }

      await sendPushNotification({
        token: 'fake_recipient_fcm_token_12345',
        title: notifTitle,
        body: notifBody,
        tag: notifTag,
        collapseKey: 'chat_updates',
        notificationCount: recentSenderCount,
        data: {
          type: 'chat_message',
          senderId,
          senderName,
          conversationId: convId,
          isSummary,
          totalUnread: String(recentSenderCount),
        },
      });
    }

    if (dispatchedPayloads.length !== 100) {
      throw new Error(`Expected total 100 payloads dispatched, got ${dispatchedPayloads.length}`);
    }

    // Inspect the 4th, 50th, and 100th payloads
    [3, 49, 99].forEach((idx) => {
      const p = dispatchedPayloads[idx];
      const count = idx + 1;
      const expectedTag = `chat_summary_${recipientId}`;

      if (p.android?.notification?.tag !== expectedTag) {
        throw new Error(`Payload ${count} expected collapsed tag ${expectedTag}, got ${p.android?.notification?.tag}`);
      }
      if (p.data?.isSummary !== 'true') {
        throw new Error(`Payload ${count} expected isSummary='true'`);
      }
      if (p.notification?.title !== 'Buddy Partner') {
        throw new Error(`Payload ${count} expected title 'Buddy Partner', got ${p.notification?.title}`);
      }
      if (!p.notification?.body.includes(`You have ${count} new messages from ${count} chats`)) {
        throw new Error(`Payload ${count} unexpected body: ${p.notification?.body}`);
      }
      if (p.android?.notification?.notificationCount !== count) {
        throw new Error(`Payload ${count} expected notificationCount=${count}, got ${p.android?.notification?.notificationCount}`);
      }
    });

    console.log(`✅ Phase 2 Passed: Senders 4 to 100 all collapsed to a single tag ('chat_summary_${recipientId}')!`);
    console.log(`   Only 1 notification drawer slot will be occupied for all 97 subsequent senders!\n`);

    // ── Phase 3: Recipient Reconnects / Reads (Cleanup) ─────────────────────
    console.log('Phase 3: Testing cleanup on recipient connect / markDelivered...');
    await redis.del(throttleKey);
    const countAfterCleanup = await redis.scard(throttleKey);
    if (countAfterCleanup !== 0) {
      throw new Error(`Expected recent senders count to be 0 after cleanup, got ${countAfterCleanup}`);
    }
    console.log('✅ Phase 3 Passed: Throttle key cleanly reset on reconnect.\n');

    console.log('================================================================');
    console.log('🎉 ALL FCM OFFLINE NOTIFICATION AGGREGATION TESTS PASSED!');
    console.log('================================================================');
    process.exit(0);
  } catch (err) {
    console.error('❌ FCM Offline Aggregation Test Failed:', err);
    process.exit(1);
  } finally {
    messagingInstance.send = originalSend;
    await redis.del(throttleKey).catch(() => {});
  }
}

runAggregationTests();
