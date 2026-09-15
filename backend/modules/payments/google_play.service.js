const { google } = require('googleapis');
const db = require('../../db');
const { subscriptionsService, SUBSCRIPTION_PLANS } = require('../subscriptions/subscriptions.service');
const { cacheService } = require('../../services/cache.service');

const ANDROID_PACKAGE_NAME = process.env.ANDROID_PACKAGE_NAME || 'com.buddypartner.app';

// Google Play In-App Product Catalog (Coin Packs: Option B with 18% GST included in Google Play Console)
const GOOGLE_PLAY_COIN_PRODUCTS = {
  // Active pricing tiers (Base price + 18% GST = Customer price in Google Play)
  plan_49: { id: 'plan_49', coins: 49, bonusCoins: 0, basePriceRupees: 49, gstRupees: 9, priceRupees: 58, type: 'inapp' },
  plan_99: { id: 'plan_99', coins: 99, bonusCoins: 0, basePriceRupees: 99, gstRupees: 18, priceRupees: 117, type: 'inapp' },
  plan_199: { id: 'plan_199', coins: 199, bonusCoins: 0, basePriceRupees: 199, gstRupees: 36, priceRupees: 235, type: 'inapp' },
  plan_499: { id: 'plan_499', coins: 499, bonusCoins: 50, basePriceRupees: 499, gstRupees: 90, priceRupees: 589, type: 'inapp' },
  plan_999: { id: 'plan_999', coins: 999, bonusCoins: 100, basePriceRupees: 999, gstRupees: 180, priceRupees: 1179, type: 'inapp' },

  // Legacy tiers maintained for backward compatibility with in-flight transactions
  plan_20: { id: 'plan_20', coins: 20, bonusCoins: 0, priceRupees: 20, type: 'inapp' },
  plan_50: { id: 'plan_50', coins: 50, bonusCoins: 0, priceRupees: 50, type: 'inapp' },
  plan_100: { id: 'plan_100', coins: 100, bonusCoins: 10, priceRupees: 100, type: 'inapp' },
  plan_200: { id: 'plan_200', coins: 200, bonusCoins: 30, priceRupees: 200, type: 'inapp' },
  plan_500: { id: 'plan_500', coins: 500, bonusCoins: 100, priceRupees: 500, type: 'inapp' },
  plan_1000: { id: 'plan_1000', coins: 1000, bonusCoins: 300, priceRupees: 1000, type: 'inapp' },
  plan_2000: { id: 'plan_2000', coins: 2000, bonusCoins: 800, priceRupees: 2000, type: 'inapp' },
};

// Google Play Subscription / Membership Catalog (Customer-facing tax-inclusive prices set in Google Play Console)
const GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS = {
  // Active membership plans (Option B: ₹199 + 18% GST = ₹235, ₹399 + 18% GST = ₹471, ₹699 + 18% GST = ₹825)
  membership_1_month: { id: 'membership_1_month', planId: '1_month', durationDays: 30, basePriceRupees: 199, gstRupees: 36, priceRupees: 235, type: 'subs' },
  membership_6_months: { id: 'membership_6_months', planId: '6_months', durationDays: 180, basePriceRupees: 399, gstRupees: 72, priceRupees: 471, type: 'subs' },
  membership_1_year: { id: 'membership_1_year', planId: '1_year', durationDays: 365, basePriceRupees: 699, gstRupees: 126, priceRupees: 825, type: 'subs' },

  // Pass aliases / direct planId mapping
  pass_1_month: { id: 'pass_1_month', planId: '1_month', durationDays: 30, basePriceRupees: 199, gstRupees: 36, priceRupees: 235, type: 'subs' },
  pass_6_months: { id: 'pass_6_months', planId: '6_months', durationDays: 180, basePriceRupees: 399, gstRupees: 72, priceRupees: 471, type: 'subs' },
  pass_1_year: { id: 'pass_1_year', planId: '1_year', durationDays: 365, basePriceRupees: 699, gstRupees: 126, priceRupees: 825, type: 'subs' },

  '1_month': { id: '1_month', planId: '1_month', durationDays: 30, basePriceRupees: 199, gstRupees: 36, priceRupees: 235, type: 'subs' },
  '6_months': { id: '6_months', planId: '6_months', durationDays: 180, basePriceRupees: 399, gstRupees: 72, priceRupees: 471, type: 'subs' },
  '1_year': { id: '1_year', planId: '1_year', durationDays: 365, basePriceRupees: 699, gstRupees: 126, priceRupees: 825, type: 'subs' },

  // Legacy tiers maintained for backward compatibility with in-flight transactions
  pass_1_day: { id: 'pass_1_day', planId: '1_day', durationDays: 1, basePriceRupees: 9, gstRupees: 0, priceRupees: 9, type: 'subs' },
  pass_7_days: { id: 'pass_7_days', planId: '7_days', durationDays: 7, basePriceRupees: 59, gstRupees: 0, priceRupees: 59, type: 'subs' },
  '1_day': { id: '1_day', planId: '1_day', durationDays: 1, basePriceRupees: 9, gstRupees: 0, priceRupees: 9, type: 'subs' },
  '7_days': { id: '7_days', planId: '7_days', durationDays: 7, basePriceRupees: 59, gstRupees: 0, priceRupees: 59, type: 'subs' },
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
    const rawJson = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
    const rawFile = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_FILE;

    // Check if JSON content is in GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
    if (rawJson) {
      try {
        credentials = typeof rawJson === 'string' && rawJson.trim().startsWith('{')
          ? JSON.parse(rawJson)
          : rawJson;
      } catch (err) {
        console.error('❌ Failed to parse GOOGLE_PLAY_SERVICE_ACCOUNT_JSON:', err.message);
      }
    }

    // Check if JSON content was pasted into GOOGLE_PLAY_SERVICE_ACCOUNT_FILE
    if (!credentials && rawFile && typeof rawFile === 'string' && rawFile.trim().startsWith('{')) {
      try {
        credentials = JSON.parse(rawFile);
      } catch (err) {
        console.error('❌ Failed to parse JSON from GOOGLE_PLAY_SERVICE_ACCOUNT_FILE:', err.message);
      }
    }

    const authOptions = {
      scopes: ['https://www.googleapis.com/auth/androidpublisher'],
    };

    if (credentials) {
      authOptions.credentials = credentials;
    } else if (rawFile && typeof rawFile === 'string' && !rawFile.trim().startsWith('{')) {
      authOptions.keyFile = rawFile;
    }

    const auth = new google.auth.GoogleAuth(authOptions);

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
          status TEXT DEFAULT 'COMPLETED',
          voided_at TIMESTAMPTZ,
          void_reason TEXT,
          raw_payload JSONB,
          created_at TIMESTAMPTZ DEFAULT NOW()
        );
        ALTER TABLE public.google_play_purchases 
          ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'COMPLETED',
          ADD COLUMN IF NOT EXISTS voided_at TIMESTAMPTZ,
          ADD COLUMN IF NOT EXISTS void_reason TEXT;
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_token ON public.google_play_purchases(purchase_token);
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_user ON public.google_play_purchases(user_id);
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_order_id ON public.google_play_purchases(order_id);
        CREATE INDEX IF NOT EXISTS idx_gp_purchases_status ON public.google_play_purchases(status);
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
      const err = new Error(`Google Play verification failed: ${apiErr.message || 'Purchase token is invalid or fraudulent.'}`);
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

      // 1. Credit wallet spendable_balance (purchased coins are non-withdrawable)
      const walletRes = await client.query(
        `INSERT INTO public.wallets (user_id, spendable_balance, earned_balance)
         VALUES ($1, $2, 0)
         ON CONFLICT (user_id)
         DO UPDATE SET 
           spendable_balance = public.wallets.spendable_balance + $2,
           updated_at = NOW()
         RETURNING spendable_balance, earned_balance`,
        [userId, totalCoins]
      );
      const sBal = Number(walletRes.rows[0].spendable_balance);
      const eBal = Number(walletRes.rows[0].earned_balance);
      const newBalance = sBal + eBal;

      // 2. Insert wallet transaction with idempotency key
      await client.query(
        `INSERT INTO public.wallet_transactions (user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id)
         VALUES ($1, $2, 0, $3, 'iap_purchase', $4)`,
        [userId, totalCoins, `gp_${purchaseToken}`, resolvedOrderId]
      );

      // 3. Record in google_play_purchases to guarantee anti-replay integrity
      await client.query(
        `INSERT INTO public.google_play_purchases (
           user_id, product_id, purchase_token, order_id, purchase_type, amount_paid, coins_credited, status, raw_payload
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          userId,
          coinProduct.id,
          purchaseToken,
          resolvedOrderId,
          'inapp',
          coinProduct.priceRupees,
          totalCoins,
          'COMPLETED',
          JSON.stringify({ ...rawDetails, googlePurchase }),
        ]
      );

      await client.query('COMMIT');

      console.log(` [Google Play Verified & Credited] ${totalCoins} coins (₹${coinProduct.priceRupees}) credited to user ${userId}. New balance: ${newBalance}`);

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
      const err = new Error(`Google Play subscription verification failed: ${apiErr.message || 'Subscription token is invalid.'}`);
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

    // Compare verified productId against client-claimed subProduct (accept exact match or equivalent plan alias)
    const verifiedProductDef = GOOGLE_PLAY_SUBSCRIPTION_PRODUCTS[verifiedProductId];
    const isPlanMatch = verifiedProductDef && (verifiedProductDef.planId === subProduct.planId);
    if (verifiedProductId !== subProduct.id && !isPlanMatch) {
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
           user_id, product_id, purchase_token, order_id, purchase_type, amount_paid, coins_credited, status, raw_payload
         ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
        [
          userId,
          verifiedProductId,
          purchaseToken,
          resolvedOrderId,
          'subs',
          subProduct.priceRupees,
          0,
          'COMPLETED',
          JSON.stringify({ ...rawDetails, subData }),
        ]
      );

      await client.query('COMMIT');

      const status = await subscriptionsService.getTimeRemaining(userId);

      console.log(` [Google Play Verified & Activated] ${subProduct.durationDays}-day pass (${verifiedProductId}) activated for user ${userId}`);

      return {
        success: true,
        purchaseType: 'subs',
        productId: verifiedProductId,
        durationDays: subProduct.durationDays,
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
   * Revoke/void a purchase (debit coins or deactivate subscription) upon refund or chargeback
   * Idempotent: safe to call multiple times for the same token or orderId
   * @param {object} params - { purchaseToken, orderId, reason, refundType }
   */
  static async revokePurchase({ purchaseToken, orderId, reason, refundType } = {}) {
    if (!purchaseToken && !orderId) {
      throw new Error('Either purchaseToken or orderId is required to revoke a purchase.');
    }

    let purchase = null;
    if (purchaseToken) {
      const res = await db.query(
        `SELECT * FROM public.google_play_purchases WHERE purchase_token = $1`,
        [purchaseToken.trim()]
      );
      purchase = res.rows[0];
    }

    if (!purchase && orderId) {
      const res = await db.query(
        `SELECT * FROM public.google_play_purchases WHERE order_id = $1`,
        [orderId.trim()]
      );
      purchase = res.rows[0];
    }

    if (!purchase) {
      console.warn(`⚠️ [Google Play Revocation] No matching purchase found in database for token: ${purchaseToken || 'N/A'}, orderId: ${orderId || 'N/A'}`);
      return { success: false, reason: 'PURCHASE_NOT_FOUND' };
    }

    // Idempotency: If already voided, do not double-debit or revoke again
    if (purchase.status === 'VOIDED' || purchase.status === 'REFUNDED') {
      console.log(`ℹ️ [Google Play Revocation] Purchase ${purchase.id} (Order: ${purchase.order_id}) was already voided on ${purchase.voided_at}`);
      return {
        success: true,
        alreadyVoided: true,
        purchaseId: purchase.id,
        orderId: purchase.order_id,
        userId: purchase.user_id,
      };
    }

    const resolvedReason = reason || 'CHARGEBACK_REFUND';
    const client = await db.pool.connect();

    try {
      await client.query('BEGIN');

      if (purchase.purchase_type === 'inapp') {
        const coinsToDeduct = parseInt(purchase.coins_credited, 10) || 0;
        let newBalance = 0;

        if (coinsToDeduct > 0) {
          // Deduct from spendable_balance (clamped to 0)
          const walletRes = await client.query(
            `UPDATE public.wallets 
             SET spendable_balance = GREATEST(0, spendable_balance - $1),
                 updated_at = NOW()
             WHERE user_id = $2 
             RETURNING spendable_balance, earned_balance`,
            [coinsToDeduct, purchase.user_id]
          );
          const sBal = Number(walletRes.rows[0]?.spendable_balance ?? 0);
          const eBal = Number(walletRes.rows[0]?.earned_balance ?? 0);
          newBalance = sBal + eBal;

          // Insert debit entry in wallet_transactions for audit history
          await client.query(
            `INSERT INTO public.wallet_transactions (user_id, spendable_delta, earned_delta, idempotency_key, reason, reference_id)
             VALUES ($1, $2, 0, $3, 'iap_purchase', $4)`,
            [purchase.user_id, -coinsToDeduct, `rev_${purchase.order_id || purchase.id}`, purchase.order_id || purchase.id]
          );
        }

        // Update purchase record to VOIDED
        await client.query(
          `UPDATE public.google_play_purchases 
           SET status = 'VOIDED', voided_at = NOW(), void_reason = $1 
           WHERE id = $2`,
          [resolvedReason, purchase.id]
        );

        await client.query('COMMIT');
        console.log(`🚫 [Google Play Revoked] Deducted ${coinsToDeduct} coins from user ${purchase.user_id} (Order: ${purchase.order_id}). New balance: ${newBalance}`);

        return {
          success: true,
          revoked: true,
          purchaseType: 'inapp',
          userId: purchase.user_id,
          orderId: purchase.order_id,
          coinsDeducted: coinsToDeduct,
          newBalance,
        };
      } else if (purchase.purchase_type === 'subs') {
        // Immediately expire the active subscription
        await client.query(
          `UPDATE public.subscriptions 
           SET expires_at = NOW() - INTERVAL '1 second' 
           WHERE user_id = $1 AND (payment_reference = $2 OR payment_reference = $3)`,
          [purchase.user_id, purchase.order_id, purchase.purchase_token]
        );

        // Update purchase record to VOIDED
        await client.query(
          `UPDATE public.google_play_purchases 
           SET status = 'VOIDED', voided_at = NOW(), void_reason = $1 
           WHERE id = $2`,
          [resolvedReason, purchase.id]
        );

        await client.query('COMMIT');
        console.log(`🚫 [Google Play Revoked] Deactivated subscription for user ${purchase.user_id} (Order: ${purchase.order_id})`);

        // Invalidate Redis cache for user's subscription status
        await cacheService.invalidate(`subscription_status:${purchase.user_id}`);

        return {
          success: true,
          revoked: true,
          purchaseType: 'subs',
          userId: purchase.user_id,
          orderId: purchase.order_id,
        };
      } else {
        await client.query('COMMIT');
        return { success: true, revoked: false, reason: `Unknown purchase_type: ${purchase.purchase_type}` };
      }
    } catch (err) {
      await client.query('ROLLBACK');
      console.error('❌ Error during purchase revocation transaction:', err.message);
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Handle Google Play Real-Time Developer Notifications (RTDN) for refunds, chargebacks, and cancellations
   */
  static async handleRtdnNotification(messageData) {
    try {
      let payload;
      if (messageData && messageData.data) {
        const decoded = Buffer.from(messageData.data, 'base64').toString('utf8');
        payload = JSON.parse(decoded);
      } else if (messageData && typeof messageData === 'object') {
        payload = messageData;
      } else {
        throw new Error('Missing or invalid Pub/Sub message data.');
      }

      console.log('📡 [RTDN Webhook] Decoded notification payload:', JSON.stringify(payload));

      // 1. Handle Test Notification from Google Play Console
      if (payload.testNotification) {
        console.log('🧪 [RTDN Webhook] Successfully received and acknowledged Google Play test notification.');
        return { success: true, type: 'testNotification', acknowledged: true };
      }

      // 2. Handle Voided Purchase Notification (Refunds, Chargebacks)
      if (payload.voidedPurchaseNotification) {
        const { purchaseToken, orderId, refundType } = payload.voidedPurchaseNotification;
        console.log(`📡 [RTDN Webhook] Voided purchase received for order ${orderId || 'N/A'}, token: ${purchaseToken ? purchaseToken.substring(0, 10) + '...' : 'N/A'}`);
        
        const result = await this.revokePurchase({
          purchaseToken,
          orderId,
          reason: `RTDN_VOIDED_PURCHASE (refundType: ${refundType || 'standard'})`,
          refundType,
        });

        return { success: true, type: 'voidedPurchase', ...result };
      }

      // 3. Handle Subscription Notification (Renewals, Cancellations, Revocations)
      if (payload.subscriptionNotification) {
        const { notificationType, purchaseToken, subscriptionId } = payload.subscriptionNotification;
        console.log(`📡 [RTDN Webhook] Subscription notification (type ${notificationType}) for product: ${subscriptionId}`);

        // Notification type 12 = SUBSCRIPTION_REVOKED (user revoked/refunded before expiration)
        if (notificationType === 12) {
          const result = await this.revokePurchase({
            purchaseToken,
            reason: 'RTDN_SUBSCRIPTION_REVOKED',
          });
          return { success: true, type: 'subscriptionRevoked', ...result };
        }

        return { success: true, type: 'subscriptionNotification', notificationType, acknowledged: true };
      }

      // Other unhandled notification types (e.g. one-time product notifications)
      return { success: true, acknowledged: true, type: 'unknown_or_unhandled' };
    } catch (err) {
      console.error('❌ Error handling RTDN notification:', err.message);
      return { success: false, error: err.message };
    }
  }

  /**
   * Periodically query Google Play Voided Purchases API to reconcile refunds/chargebacks
   * Catches any refunds that occurred when webhooks were down or missed
   * @param {number|string} [startTimeMs] - Milliseconds timestamp to start query from (defaults to past 30 days)
   */
  static async syncVoidedPurchases(startTimeMs) {
    try {
      const publisher = this.getPublisherClient();
      // Google Play Developer API requires startTime to be strictly within 30 days.
      // Using 28 days avoids server clock-skew boundary rejection.
      const defaultStart = Date.now() - (28 * 24 * 60 * 60 * 1000);
      const start = startTimeMs ? String(startTimeMs) : String(defaultStart);

      console.log(`🔄 [Google Play Voided Sync] Querying voided purchases since ${new Date(parseInt(start, 10)).toISOString()}...`);

      const res = await publisher.purchases.voidedpurchases.list({
        packageName: ANDROID_PACKAGE_NAME,
        startTime: start,
      });

      const voidedList = res.data?.voidedPurchases || [];
      console.log(`📦 [Google Play Voided Sync] Found ${voidedList.length} voided purchase(s).`);

      const results = [];
      for (const item of voidedList) {
        const { purchaseToken, orderId, voidedReason } = item;
        const revokeRes = await this.revokePurchase({
          purchaseToken,
          orderId,
          reason: `VOIDED_API_SYNC (reason: ${voidedReason ?? 'unspecified'})`,
        });
        results.push({
          orderId,
          purchaseToken: purchaseToken ? `${purchaseToken.substring(0, 10)}...` : null,
          ...revokeRes,
        });
      }

      return {
        success: true,
        totalFound: voidedList.length,
        processed: results.length,
        results,
      };
    } catch (err) {
      console.error('❌ [Google Play Voided Sync Error]:', err.message);
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
