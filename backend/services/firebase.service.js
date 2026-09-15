const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

let isInitialized = false;

function initFirebase() {
  if (isInitialized) return admin;

  try {
    let serviceAccount = null;

    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      try {
        serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
      } catch {
        // In case it's a file path
        if (fs.existsSync(process.env.FIREBASE_SERVICE_ACCOUNT)) {
          serviceAccount = JSON.parse(fs.readFileSync(process.env.FIREBASE_SERVICE_ACCOUNT, 'utf8'));
        }
      }
    }

    // Fallback to local admin sdk key file in workspace root or backend folder
    if (!serviceAccount) {
      const candidates = [
        path.join(__dirname, '../../buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
        path.join(__dirname, '../buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
        path.join(process.cwd(), 'buddypartner-a7fc7-firebase-adminsdk-fbsvc-f324da7a32.json'),
      ];

      for (const p of candidates) {
        if (fs.existsSync(p)) {
          serviceAccount = JSON.parse(fs.readFileSync(p, 'utf8'));
          break;
        }
      }
    }

    if (serviceAccount) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      isInitialized = true;
      console.log('🔥 [Firebase Admin] Successfully initialized with project:', serviceAccount.project_id);
    } else {
      console.warn('⚠️ [Firebase Admin] No service account credentials found. Push notifications will be mocked.');
    }
  } catch (err) {
    console.error('❌ [Firebase Admin] Initialization error:', err.message);
  }

  return admin;
}

initFirebase();

/**
 * Sends a single FCM Push Notification to a device token
 */
async function sendPushNotification({ token, title, body, tag, data = {} }) {
  if (!token) return null;
  if (!isInitialized) {
    console.log(`[FCM Mock] Single push to ${token.substring(0, 10)}... | ${title}: ${body}`);
    return null;
  }

  try {
    const stringData = {};
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v ?? '');
    }

    const notifTag = tag || (stringData.conversationId ? `chat_${stringData.conversationId}` : (stringData.senderId ? `chat_${stringData.senderId}` : undefined));

    const response = await admin.messaging().send({
      token,
      notification: {
        title,
        body,
      },
      data: stringData,
      android: {
        priority: 'high',
        notification: {
          channelId: 'buddypartner_notifications',
          priority: 'max',
          tag: notifTag,
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    });

    console.log(`🔔 [FCM Push] Sent successfully to ${token.substring(0, 10)}... (tag: ${notifTag}, ID: ${response})`);
    return response;
  } catch (err) {
    console.error(`❌ [FCM Push Error] Failed to send push to ${token.substring(0, 10)}...:`, err.message);
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      const db = require('../db');
      db.query('UPDATE public.users SET fcm_token = NULL WHERE fcm_token = $1', [token]).catch(() => {});
    }
    return null;
  }
}

/**
 * Slices an array of tokens into batches of up to chunkSize (default 500).
 * Required by Firebase Admin SDK which limits sendEachForMulticast to 500 tokens per request.
 * 
 * @param {string[]} tokens
 * @param {number} [chunkSize=500]
 * @returns {string[][]} Array of token chunks
 */
function chunkTokens(tokens, chunkSize = 500) {
  if (!Array.isArray(tokens) || tokens.length === 0) return [];
  const size = Math.max(1, chunkSize);
  const chunks = [];
  for (let i = 0; i < tokens.length; i += size) {
    chunks.push(tokens.slice(i, i + size));
  }
  return chunks;
}

/**
 * Sends Multicast FCM Push Notifications to multiple device tokens.
 * Automatically chunks tokens into batches of <= 500 to adhere to Firebase Admin SDK limits.
 * Prunes tokens that come back as invalid or unregistered.
 */
async function sendMulticastPushNotification({ tokens = [], title, body, tag, data = {} }) {
  const validTokens = Array.from(new Set(tokens.filter((t) => typeof t === 'string' && t.trim().length > 0)));
  if (validTokens.length === 0) return null;

  const chunks = chunkTokens(validTokens, 500);

  if (!isInitialized) {
    console.log(`[FCM Mock] Multicast push to ${validTokens.length} devices in ${chunks.length} batches of <= 500 | ${title}: ${body}`);
    return {
      successCount: validTokens.length,
      failureCount: 0,
      batchCount: chunks.length,
      responses: [],
    };
  }

  try {
    const stringData = {};
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v ?? '');
    }

    const notifTag = tag || (stringData.sessionId ? `instant_${stringData.sessionId}` : 'instant_call');

    let totalSuccess = 0;
    let totalFailure = 0;
    const allResponses = [];
    const tokensToPrune = [];

    for (let batchIndex = 0; batchIndex < chunks.length; batchIndex++) {
      const batchTokens = chunks[batchIndex];
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batchTokens,
        notification: {
          title,
          body,
        },
        data: stringData,
        android: {
          priority: 'high',
          notification: {
            channelId: 'buddypartner_notifications',
            priority: 'max',
            tag: notifTag,
            defaultSound: true,
            defaultVibrateTimings: true,
          },
        },
      });

      totalSuccess += (response.successCount || 0);
      totalFailure += (response.failureCount || 0);
      allResponses.push(response);

      if (response.failureCount > 0 && response.responses) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success && resp.error) {
            const code = resp.error.code;
            if (
              code === 'messaging/registration-token-not-registered' ||
              code === 'messaging/invalid-registration-token' ||
              code === 'messaging/invalid-argument'
            ) {
              tokensToPrune.push(batchTokens[idx]);
            }
          }
        });
      }

      console.log(`🔔 [FCM Multicast Batch ${batchIndex + 1}/${chunks.length}] Dispatched to ${batchTokens.length} devices (tag: ${notifTag}, ${response.successCount} succeeded, ${response.failureCount} failed)`);
    }

    // Prune invalid or unregistered tokens from database
    if (tokensToPrune.length > 0) {
      const db = require('../db');
      db.query('UPDATE public.users SET fcm_token = NULL WHERE fcm_token = ANY($1)', [tokensToPrune])
        .then((pruneRes) => {
          console.log(`🧹 [FCM Prune] Pruned ${pruneRes.rowCount} invalid/unregistered FCM tokens from database.`);
        })
        .catch((err) => {
          console.warn('⚠️ [FCM Prune Error]:', err.message);
        });
    }

    console.log(`🔔 [FCM Multicast Complete] Total ${validTokens.length} devices across ${chunks.length} batches: ${totalSuccess} succeeded, ${totalFailure} failed`);
    return {
      successCount: totalSuccess,
      failureCount: totalFailure,
      batchCount: chunks.length,
      responses: allResponses,
    };
  } catch (err) {
    console.error('❌ [FCM Multicast Error]:', err.message);
    return null;
  }
}

module.exports = {
  admin,
  initFirebase,
  sendPushNotification,
  sendMulticastPushNotification,
  chunkTokens,
};
