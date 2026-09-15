/**
 * Test Suite: FCM Multicast 500-Token Batching Verification
 * 
 * Verifies that:
 * 1. Token chunking logic splits large token arrays into batches of <= 500.
 * 2. 1,200 tokens produce exactly 3 batches of [500, 500, 200].
 * 3. sendMulticastPushNotification dispatches each batch without oversized requests or silent truncation.
 * 4. Aggregated response accurately reports total success and batch count.
 */

const { chunkTokens, sendMulticastPushNotification, admin } = require('./services/firebase.service');

async function runFcmBatchingTests() {
  console.log('================================================================');
  console.log('🧪 RUNNING FCM MULTICAST 500-TOKEN BATCHING VERIFICATION');
  console.log('================================================================\n');

  try {
    // ── Test 1: Unit Test on chunkTokens with 1,200 tokens ────────────────────
    console.log('Test 1: Testing token chunking with 1,200 tokens...');
    const tokens1200 = Array.from({ length: 1200 }, (_, i) => `fcm_token_${i + 1}`);

    const chunks = chunkTokens(tokens1200, 500);
    console.log(`   Generated chunks count: ${chunks.length}`);
    chunks.forEach((chunk, idx) => {
      console.log(`   - Batch ${idx + 1}: ${chunk.length} tokens (Max <= 500: ${chunk.length <= 500})`);
    });

    if (chunks.length !== 3) {
      throw new Error(`Expected exactly 3 chunks for 1,200 tokens, got ${chunks.length}`);
    }
    if (chunks[0].length !== 500 || chunks[1].length !== 500 || chunks[2].length !== 200) {
      throw new Error(`Expected chunks of [500, 500, 200], got [${chunks.map(c => c.length).join(', ')}]`);
    }
    const flattened = chunks.flat();
    if (flattened.length !== 1200 || flattened[0] !== 'fcm_token_1' || flattened[1199] !== 'fcm_token_1200') {
      throw new Error('Flattened tokens do not match original sequence!');
    }
    console.log('✅ Unit test passed: 1,200 tokens split into [500, 500, 200] chunks.\n');

    // ── Test 2: Boundary conditions ──────────────────────────────────────────
    console.log('Test 2: Testing boundary conditions (0, 500, 501 tokens)...');
    const emptyChunks = chunkTokens([], 500);
    if (emptyChunks.length !== 0) throw new Error('Empty tokens should produce 0 chunks');

    const exact500 = Array.from({ length: 500 }, (_, i) => `token_${i}`);
    const chunks500 = chunkTokens(exact500, 500);
    if (chunks500.length !== 1 || chunks500[0].length !== 500) {
      throw new Error('500 tokens should produce exactly 1 chunk of 500');
    }

    const over500 = Array.from({ length: 501 }, (_, i) => `token_${i}`);
    const chunks501 = chunkTokens(over500, 500);
    if (chunks501.length !== 2 || chunks501[0].length !== 500 || chunks501[1].length !== 1) {
      throw new Error('501 tokens should produce 2 chunks: [500, 1]');
    }
    console.log('✅ Boundary conditions passed: [0 -> 0], [500 -> [500]], [501 -> [500, 1]].\n');

    // ── Test 3: Integration Dispatch with Mocked FCM Multicast ───────────────
    console.log('Test 3: Testing sendMulticastPushNotification with 1,200 tokens...');
    
    // Intercept/mock admin.messaging().sendEachForMulticast on the initialized messaging singleton
    const messagingInstance = admin.messaging();
    const originalSendEach = messagingInstance.sendEachForMulticast;
    const dispatchedBatches = [];

    messagingInstance.sendEachForMulticast = async (payload) => {
      dispatchedBatches.push(payload);
      if (payload.tokens.length > 500) {
        throw new Error(`Firebase Admin SDK Violation! Batch exceeded 500 tokens: ${payload.tokens.length}`);
      }
      return {
        successCount: payload.tokens.length,
        failureCount: 0,
        responses: payload.tokens.map(() => ({ success: true })),
      };
    };

    try {
      const result = await sendMulticastPushNotification({
        tokens: tokens1200,
        title: 'Movie Buddy in Mumbai',
        body: 'Join movie buddy session',
        tag: 'buddy_test_123',
        data: { test: 'true' },
      });

      console.log('   Multicast dispatch result:', {
        successCount: result.successCount,
        failureCount: result.failureCount,
        batchCount: result.batchCount,
      });

      if (dispatchedBatches.length !== 3) {
        throw new Error(`Expected exactly 3 dispatch calls to FCM, got ${dispatchedBatches.length}`);
      }

      dispatchedBatches.forEach((batch, i) => {
        console.log(`   - FCM Dispatch Call ${i + 1}: ${batch.tokens.length} tokens`);
        if (batch.tokens.length > 500) {
          throw new Error(`Batch ${i + 1} exceeded 500 tokens limit: ${batch.tokens.length}`);
        }
      });

      if (result.successCount !== 1200) {
        throw new Error(`Expected successCount 1200, got ${result.successCount}`);
      }

      if (result.batchCount !== 3) {
        throw new Error(`Expected batchCount 3, got ${result.batchCount}`);
      }

      console.log('✅ sendMulticastPushNotification successfully dispatched 1,200 tokens across 3 batches of <= 500!\n');
    } finally {
      // Restore original messaging
      messagingInstance.sendEachForMulticast = originalSendEach;
    }

    console.log('================================================================');
    console.log(' ALL FCM MULTICAST BATCHING TESTS PASSED!');
    console.log('================================================================');
    process.exit(0);
  } catch (err) {
    console.error('❌ FCM Multicast Batching Test Failed:', err);
    process.exit(1);
  }
}

runFcmBatchingTests();
