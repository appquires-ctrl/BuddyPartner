const { google } = require('googleapis');
const db = require('../../db');
const { subscriptionsService, SUBSCRIPTION_PLANS } = require('../subscriptions/subscriptions.service');

const ANDROID_PACKAGE_NAME = process.env.ANDROID_PACKAGE_NAME || 'com.buddypartner.app';

// Google Play In-App Product Catalog (Coin Packs: 1 INR = 1 Coin base rate + bonuses)
const GOOGLE_PLAY_COIN_PRODUCTS = {
  plan_20: { id: 'plan_20', coins: 20, bonusCoins: 0, priceRupees: 20, type: 'inapp' },
  plan_50: { id: 'plan_50', coins: 50, bonusCoins: 0, priceRupees: 50, type: 'inapp' },
  plan_100: { id: 'plan_100', coins: 100, bonusCoins: 10, priceRupees: 100, type: 'inapp' },
  plan_200: { id: 'plan_200', coins: 200, bonusCoins: 30, priceRupees: 200, type: 'inapp' },
  plan_500: { id: 'plan_500', coins: 500, bonusCoins: 100, priceRupees: 500, type: 'inapp' },
  plan_1000: { id: 'plan_1000', coins: 1000, bonusCoins: 300, priceRupees: 1000, type: 'inapp' },
  plan_2000: { id: 'plan_2000', coins: 2000, bonusCoins: 800, priceRupees: 2000, type: 'inapp' },
};

// Google Play Subscription / Pass Catalog
const GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS = {
  pass_1_day: { id: 'pass_1_day', planId: '1_day', durationDays: 1, priceRupees: 9, type: 'subs' },
  pass_7_days: { id: 'pass_7_days', planId: '7_days', durationDays: 7, priceRupees: 59, type: 'subs' },
  pass_1_month: { id: 'pass_1_month', planId: '1_month', durationDays: 30, priceRupees: 199, type: 'subs' },
  pass_1_year: { id: 'pass_1_year', planId: '1_year', durationDays: 365, priceRupees: 1999, type: 'subs' },
};

class GooglePlayService {
  static _publisherClientOverride = null;

  /**
   * For unit testing: override the Google Android Publisher API client instance
   */
  static setPublisherClientOverride(client) {
    this._publisherClientOverride = client;
  }

  /**
   * Instantiate or return the Google Android Publisher API client
   */
  static getPublisherClient() {
    if (this._publisherClientOverride) {
      return this._publisherClientOverride;
    }

    let credentials;
    if (process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON) {
      try {
        credentials = typeof process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON === 'string'
          ? JSON.parse(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON)
          : process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
      } catch (err) {
        console.error('❌ Failed to parse GOOGLE_PLAY_SERVICE_ACCOUNT_JSON:', err.message);
      }
    }

    const auth = new google.auth.GoogleAuth({
      credentials,
      keyFile: process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE,
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    });

    return google.androidpublisher({ version: 'v3', auth });
  }

  /**
   * Initialize table for storing verified Google Play purchases to prevent replay attacks
   */
  static async initTable() {
    try {
      await db.query(`
        CREATE TABLE IF NOT EXISTS public.google_play_purchases (
          id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
          user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
          product_id TEXT NOT NULL,
          purchase_token TEXT UNIQUE NOT NULL,
          order_id TEXT,
          purchase_type TEXT NOT NULL,
          amount_paid NUMERIC(10, 2) NOT NULL,
          coins_credited INTEGER DEFAULT 0,
          raw_payload JSONB,
          created_at TIMESTAMPTZ DEFAULT NOW()
        );
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_token ON public.google_play_purchases(purchase_token);
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_user ON public.google_play_purchases(user_id);
      `);
      console.log('✅ Google Play purchases table initialized.');
    } catch (err) {
      console.error('❌ Failed to initialize Google Play purchases table:', err.message);
    }
  }

  /**
   * Verify and process a Google Play Purchase strictly against Google's servers
   * @param {string} userId - User ID
   * @param {object} payload - { productId, purchaseToken, orderId, signature, rawDetails }
   */
  static async verifyAndProcessPurchase(userId, { productId, purchaseToken, orderId, signature, rawDetails }) {
    if (!userId || typeof userId !== 'string') {
      throw new Error('Valid userId is required.');
    }
    if (!productId || typeof productId !== 'string') {
      throw new Error('Valid productId is required.');
    }
    if (!purchaseToken || typeof purchaseToken !== 'string' || purchaseToken.trim().length === 0) {
      throw new Error('Valid purchaseToken string is required.');
    }

    const cleanToken = purchaseToken.trim();
    const cleanProductId = productId.trim();

    // 1. Anti-Replay Check: Ensure purchaseToken was not already processed
    const existingCheck = await db.query(
      `SELECT id, product_id, created_at FROM public.google_play_purchases WHERE purchase_token = $1`,
      [cleanToken]
    );
    if (existingCheck.rows.length > 0) {
      console.warn(`⚠️ [Google Play] Purchase token ${cleanToken.substring(0, 15)}... was already redeemed on ${existingCheck.rows[0].created_at}`);
      const err = new Error('This purchase token has already been redeemed.');
      err.statusCode = 400;
      err.code = 'ALREADY_REDEEMED';
      throw err;
    }

    // 2. Identify Product Configuration
    const coinProduct = GOOGLE_PLAY_COIN_PRODUCTS[cleanProductId];
    let subProduct = GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS[cleanProductId];

    if (!coinProduct && !subProduct) {
      // Check direct subscription IDs (e.g. '1_day', '7_days', '1_month', '1_year')
      const directSub = SUBSCRIPTION_PLANS.find((p) => p.id === cleanProductId);
      if (directSub) {
        subProduct = {
          id: directSub.id,
          planId: directSub.id,
          durationDays: directSub.durationDays,
          priceRupees: directSub.amountPaid,
          type: 'subs',
        };
      } else {
        const err = new Error(`Unknown or unsupported Google Play product ID: ${cleanProductId}`);
        err.statusCode = 400;
        err.code = 'UNKNOWN_PRODUCT';
        throw err;
      }
    }

    const publisher = this.getPublisherClient();

    // 3. Process & Verify Consumable In-App Product (Coin Pack)
    if (coinProduct) {
      return await this._verifyAndProcessCoinPack(userId, coinProduct, cleanToken, orderId, rawDetails, publisher);
    }

    // 4. Process & Verify Subscription Pass
    if (subProduct) {
      return await this._verifyAndProcessSubscription(userId, subProduct, cleanToken, orderId, rawDetails, publisher);
    }
  }

  /**
   * Verify and process consumable coin product with Google Android Publisher API
   */
  static async _verifyAndProcessCoinPack(userId, coinProduct, purchaseToken, orderId, rawDetails, publisher) {
    let googlePurchase;

    try {
      const res = await publisher.purchases.products.get({
        packageName: ANDROID_PACKAGE_NAME,
        productId: coinProduct.id,
        token: purchaseToken,
      });
      googlePurchase = res.data;
    } catch (apiErr) {
      console.error(`❌ [Google Play API Error] Product verification failed for ${coinProduct.id}:`, apiErr.message);
      const err = new Error('Google Play verification failed. Purchase token is invalid or fraudulent.');
      err.statusCode = 400;
      err.code = 'INVALID_PURCHASE_TOKEN';
      err.details = apiErr.message;
      throw err;
    }

    if (!googlePurchase) {
      const err = new Error('Google Play returned empty verification response.');
      err.statusCode = 400;
      throw err;
    }

    // Package Name Verification (Must match our app)
    if (googlePurchase.packageName && googlePurchase.packageName !== ANDROID_PACKAGE_NAME) {
      console.error(`❌ [Google Play Security] Package name mismatch! Expected: ${ANDROID_PACKAGE_NAME}, Got: ${googlePurchase.packageName}`);
      const err = new Error('Purchase receipt belongs to an unauthorized package.');
      err.statusCode = 400;
      err.code = 'PACKAGE_MISMATCH';
      throw err;
    }

    // Purchase State Check: 0 = Purchased, 1 = Canceled, 2 = Pending
    if (googlePurchase.purchaseState !== 0) {
      console.error(`❌ [Google Play Verification] Invalid purchaseState: ${googlePurchase.purchaseState}`);
      const err = new Error(`Purchase is not in a valid paid state (state: ${googlePurchase.purchaseState}).`);
      err.statusCode = 400;
      err.code = 'INVALID_PURCHASE_STATE';
      throw err;
    }

    // Consumption State Check: 0 = Yet to be consumed, 1 = Consumed
    // If acknowledgement is pending, we acknowledge it with Google
    if (googlePurchase.acknowledgementState === 0) {
      try {
        await publisher.purchases.products.acknowledge({
          packageName: ANDROID_PACKAGE_NAME,
          productId: coinProduct.id,
          token: purchaseToken,
          requestBody: {
            developerPayload: JSON.stringify({ userId, creditedAt: new Date().toISOString() }),
          },
        });
        console.log(`✅ [Google Play] Acknowledged purchase for product ${coinProduct.id} token ${purchaseToken.substring(0, 10)}...`);
      } catch (ackErr) {
        console.warn(`⚠️ [Google Play] Purchase acknowledgement notice:`, ackErr.message);
      }
    }

    // Perform atomic database transaction to credit coins and record purchase
    const totalCoins = coinProduct.coins + coinProduct.bonusCoins;
    const resolvedOrderId = googlePurchase.orderId || orderId || `GP_${purchaseToken.substring(0, 16)}`;
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Credit wallet
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, balance)
         VALUES ($1, $2)
         ON CONFLICT (user_id)
         DO UPDATE SET balance = public.wallets.balance + $2
         RETURNING balance`,
        [userId, totalCoins]
      );
      const newBalance = walletRes.rows[0].balance;

      // 2. Insert wallet transaction
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, amount, type, reason, reference_id)
         VALUES ($1, $2, 'credit', 'recharge', $3)`,
        [userId, totalCoins, resolvedOrderId]
      );

      // 3. Record in google_play_purchases to guarantee anti-replay integrity
      await client.query(
        `INSERT INTO public.google_play_purchases (
           user_id, product_id, purchase_token, order_id, purchase_type, amount_paid, coins_credited, raw_payload
         ) VALUES ($1, $2, $3, $4, 'inapp', $5, $6, $7)`,
        [
          userId,
          coinProduct.id,
          purchaseToken,
          resolvedOrderId,
          coinProduct.priceRupees,
          totalCoins,
          JSON.stringify({ ...rawDetails, googlePurchase }),
        ]
      );

      await client.query('COMMIT');

      console.log(`🎉 [Google Play Verified & Credited] ${totalCoins} coins (₹${coinProduct.priceRupees}) credited to user ${userId}. New balance: ${newBalance}`);

      return {
        success: true,
        purchaseType: 'inapp',
        productId: coinProduct.id,
        coinsCredited: totalCoins,
        newBalance,
        orderId: resolvedOrderId,
      };
    } catch (dbErr) {
      await client.query('ROLLBACK');
      console.error('❌ Database error during Google Play coin crediting:', dbErr.message);
      throw dbErr;
    } finally {
      client.release();
    }
  }

  /**
   * Verify and process subscription pass with Google Android Publisher API (subscriptionsv2)
   * Validates: token authenticity, subscription state, package name, and product identity binding via lineItems
   */
  static async _verifyAndProcessSubscription(userId, subProduct, purchaseToken, orderId, rawDetails, publisher) {
    let subData;

    try {
      const res = await publisher.purchases.subscriptionsv2.get({
        packageName: ANDROID_PACKAGE_NAME,
        token: purchaseToken,
      });
      subData = res.data;
    } catch (apiErr) {
      console.error(`❌ [Google Play API Error] Subscription verification failed for token ${purchaseToken.substring(0, 10)}...:`, apiErr.message);
      const err = new Error('Google Play subscription verification failed. Subscription token is invalid.');
      err.statusCode = 400;
      err.code = 'INVALID_SUBSCRIPTION_TOKEN';
      err.details = apiErr.message;
      throw err;
    }

    if (!subData) {
      const err = new Error('Google Play returned empty subscription response.');
      err.statusCode = 400;
      err.code = 'INVALID_SUBSCRIPTION_RESPONSE';
      throw err;
    }

    // Package Name Verification (Must match our app — mirrors coin pack behavior)
    if (subData.packageName && subData.packageName !== ANDROID_PACKAGE_NAME) {
      console.error(`❌ [Google Play Security] Subscription package name mismatch! Expected: ${ANDROID_PACKAGE_NAME}, Got: ${subData.packageName}`);
      const err = new Error('Subscription receipt belongs to an unauthorized package.');
      err.statusCode = 400;
      err.code = 'PACKAGE_MISMATCH';
      throw err;
    }

    // Subscription State Check: Must be active, in grace period, or auto-renewing
    const validStates = [
      'SUBSCRIPTION_STATE_ACTIVE',
      'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
      'SUBSCRIPTION_STATE_AUTO_RENEWING',
    ];
    const subState = subData.subscriptionState;

    if (!subState || !validStates.includes(subState)) {
      console.error(`❌ [Google Play Verification] Subscription state is not active: ${subState}`);
      const err = new Error(`Subscription is not active (state: ${subState || 'missing'}).`);
      err.statusCode = 400;
      err.code = 'SUBSCRIPTION_NOT_ACTIVE';
      throw err;
    }

    // Product Identity Binding: Extract actual productId from lineItems and compare against claimed productId
    const lineItems = subData.lineItems;
    if (!Array.isArray(lineItems) || lineItems.length === 0) {
      console.error(`❌ [Google Play Security] Subscription response missing or empty lineItems for token ${purchaseToken.substring(0, 10)}...`);
      const err = new Error('Google Play subscription response has missing or empty lineItems. Cannot verify product identity.');
      err.statusCode = 400;
      err.code = 'INVALID_SUBSCRIPTION_RESPONSE';
      throw err;
    }

    // Extract the verified productId from Google's response (use first line item)
    const verifiedLineItem = lineItems[0];
    const verifiedProductId = verifiedLineItem.productId;

    if (!verifiedProductId || typeof verifiedProductId !== 'string') {
      console.error(`❌ [Google Play Security] lineItems[0].productId is missing or invalid in subscription response`);
      const err = new Error('Google Play subscription lineItems does not contain a valid productId.');
      err.statusCode = 400;
      err.code = 'INVALID_SUBSCRIPTION_RESPONSE';
      throw err;
    }

    // Compare verified productId against the client-claimed subProduct.id
    if (verifiedProductId !== subProduct.id) {
      console.error(`❌ [Google Play Security] Product identity mismatch! Client claimed: ${subProduct.id}, Google verified: ${verifiedProductId}`);
      const err = new Error(`Product mismatch: token belongs to product "${verifiedProductId}" but client claimed "${subProduct.id}".`);
      err.statusCode = 400;
      err.code = 'PRODUCT_MISMATCH';
      throw err;
    }

    // Subscription Acknowledgement (Google auto-refunds unacknowledged subscriptions after ~3 days)
    if (subData.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING' || subData.acknowledgementState === undefined) {
      try {
        await publisher.purchases.subscriptions.acknowledge({
          packageName: ANDROID_PACKAGE_NAME,
          subscriptionId: verifiedProductId,
          token: purchaseToken,
          requestBody: {
            developerPayload: JSON.stringify({ userId, activatedAt: new Date().toISOString() }),
          },
        });
        console.log(`✅ [Google Play] Acknowledged subscription ${verifiedProductId} token ${purchaseToken.substring(0, 10)}...`);
      } catch (ackErr) {
        // Non-blocking: log but don't fail — the subscription is valid, acknowledgement can retry
        console.warn(`⚠️ [Google Play] Subscription acknowledgement notice:`, ackErr.message);
      }
    }

    // Perform atomic database transaction to activate subscription pass
    // Use verifiedProductId (from Google) for audit trail, not client-supplied productId
    const resolvedOrderId = subData.latestOrderId || orderId || `GP_SUB_${purchaseToken.substring(0, 16)}`;
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      // 1. Create subscription pass record
      const subscription = await subscriptionsService.createSubscription(
        userId,
        subProduct.durationDays,
        subProduct.priceRupees,
        resolvedOrderId
      );

      // 2. Record in google_play_purchases — use verifiedProductId for the audit trail
      await client.query(
        `INSERT INTO public.google_play_purchases (
           user_id, product_id, purchase_token, order_id, purchase_type, amount_paid, coins_credited, raw_payload
         ) VALUES ($1, $2, $3, $4, 'subs', $5, 0, $6)`,
        [
          userId,
          verifiedProductId,
          purchaseToken,
          resolvedOrderId,
          subProduct.priceRupees,
          JSON.stringify({ ...rawDetails, subData }),
        ]
      );

      await client.query('COMMIT');

      const status = await subscriptionsService.getTimeRemaining(userId);

      console.log(`🎉 [Google Play Verified & Activated] ${subProduct.durationDays}-day pass (${verifiedProductId}) activated for user ${userId}`);

      return {
        success: true,
        purchaseType: 'subs',
        productId: verifiedProductId,
        subscription,
        status,
        orderId: resolvedOrderId,
      };
    } catch (dbErr) {
      await client.query('ROLLBACK');
      console.error('❌ Database error during Google Play subscription activation:', dbErr.message);
      throw dbErr;
    } finally {
      client.release();
    }
  }

  /**
   * Handle Google Play Real-Time Developer Notifications (RTDN) for refunds, chargebacks, and cancellations
   */
  static async handleRtdnNotification(messageData) {
    try {
      console.log('📡 [RTDN Webhook] Received notification message:', JSON.stringify(messageData));
      
      // TODO: Decode Pub/Sub notification payload:
      // const payload = JSON.parse(Buffer.from(messageData.data, 'base64').toString('utf8'));
      // Handle voided purchases / refunds:
      // if (payload.voidedPurchaseNotification) {
      //   const { purchaseToken, orderId, refundType } = payload.voidedPurchaseNotification;
      //   // Look up purchase by purchaseToken and debit user wallet or deactivate subscription pass
      // }
      // if (payload.subscriptionNotification) {
      //   const { notificationType, purchaseToken, subscriptionId } = payload.subscriptionNotification;
      //   // Handle SUBSCRIPTION_REVOKED (12), SUBSCRIPTION_CANCELED (3), etc.
      // }
      return { success: true, acknowledged: true };
    } catch (err) {
      console.error('Error handling RTDN notification:', err.message);
      return { success: false, error: err.message };
    }
  }

  /**
   * Return list of all configured Google Play product IDs
   */
  static getProductCatalog() {
    return {
      coinProducts: Object.values(GOOGLE_PLAY_COIN_PRODUCTS),
      subscriptionProducts: Object.values(GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS),
      allProductIds: [
        ...Object.keys(GOOGLE_PLAY_COIN_PRODUCTS),
        ...Object.keys(GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS),
      ],
    };
  }
}

module.exports = {
  GooglePlayService,
  GOOGLE_PLAY_COIN_PRODUCTS,
  GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS,
  ANDROID_PACKAGE_NAME,
};
