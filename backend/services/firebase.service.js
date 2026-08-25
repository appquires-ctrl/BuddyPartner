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
async function sendPushNotification({ token, title, body, data = {} }) {
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
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    });

    console.log(`🔔 [FCM Push] Sent successfully to ${token.substring(0, 10)}... (ID: ${response})`);
    return response;
  } catch (err) {
    console.error(`❌ [FCM Push Error] Failed to send push to ${token.substring(0, 10)}...:`, err.message);
    return null;
  }
}

/**
 * Sends Multicast FCM Push Notifications to multiple device tokens (e.g. 1:10 instant call surge)
 */
async function sendMulticastPushNotification({ tokens = [], title, body, data = {} }) {
  const validTokens = tokens.filter((t) => typeof t === 'string' && t.trim().length > 0);
  if (validTokens.length === 0) return null;

  if (!isInitialized) {
    console.log(`[FCM Mock] Multicast push to ${validTokens.length} devices | ${title}: ${body}`);
    return null;
  }

  try {
    const stringData = {};
    for (const [k, v] of Object.entries(data)) {
      stringData[k] = String(v ?? '');
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens: validTokens,
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
          defaultSound: true,
          defaultVibrateTimings: true,
        },
      },
    });

    console.log(`🔔 [FCM Multicast] Dispatched to ${validTokens.length} devices (${response.successCount} succeeded, ${response.failureCount} failed)`);
    return response;
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
};
