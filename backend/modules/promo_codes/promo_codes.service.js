const db = require('../../db');

class PromoCodesService {
  /**
   * List all promo codes for Admin Panel with usage metrics
   */
  static async listPromoCodes({ page = 1, limit = 50, search = '' }) {
    const offset = (Math.max(1, page) - 1) * limit;
    const params = [];
    let whereClause = 'WHERE 1=1';

    if (search && search.trim()) {
      params.push(`%${search.trim().toUpperCase()}%`);
      whereClause += ` AND (UPPER(code) LIKE $${params.length} OR UPPER(title) LIKE $${params.length})`;
    }

    const countRes = await db.query(
      `SELECT COUNT(*)::int as total FROM promo_codes ${whereClause}`,
      params
    );
    const total = countRes.rows[0]?.total || 0;

    params.push(limit);
    params.push(offset);
    const dataRes = await db.query(
      `SELECT * FROM promo_codes 
       ${whereClause} 
       ORDER BY created_at DESC 
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params
    );

    return {
      promoCodes: dataRes.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Create a new promo code
   */
  static async createPromoCode(data) {
    const {
      code,
      title,
      description = '',
      rewardType = 'GOOGLE_PLAY_OFFER',
      targetProductId = 'pass_1_month',
      googlePlayOfferId = '50-off',
      discountAmount = 50,
      coinsReward = 0,
      vipDaysReward = 0,
      maxUsesTotal = null,
      maxUsesPerUser = 1,
      startsAt = new Date(),
      expiresAt,
      isActive = true,
    } = data;

    if (!code || !code.trim()) {
      throw { statusCode: 400, message: 'Promo code is required.' };
    }
    if (!title || !title.trim()) {
      throw { statusCode: 400, message: 'Promo title is required.' };
    }
    if (!expiresAt) {
      throw { statusCode: 400, message: 'Expiration date is required.' };
    }

    const normalizedCode = code.trim().toUpperCase();

    const insertRes = await db.query(
      `INSERT INTO promo_codes (
        code, title, description, reward_type, 
        target_product_id, google_play_offer_id, discount_amount, 
        coins_reward, vip_days_reward, max_uses_total, max_uses_per_user, 
        starts_at, expires_at, is_active, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW())
      RETURNING *`,
      [
        normalizedCode,
        title.trim(),
        description || null,
        rewardType,
        targetProductId || null,
        googlePlayOfferId || null,
        discountAmount || 0,
        coinsReward || 0,
        vipDaysReward || 0,
        maxUsesTotal ? parseInt(maxUsesTotal, 10) : null,
        maxUsesPerUser ? parseInt(maxUsesPerUser, 10) : 1,
        startsAt ? new Date(startsAt) : new Date(),
        new Date(expiresAt),
        isActive !== false,
      ]
    );

    return insertRes.rows[0];
  }

  /**
   * Update an existing promo code
   */
  static async updatePromoCode(id, data) {
    const fields = [];
    const values = [];

    if (data.code !== undefined) {
      values.push(data.code.trim().toUpperCase());
      fields.push(`code = $${values.length}`);
    }
    if (data.title !== undefined) {
      values.push(data.title.trim());
      fields.push(`title = $${values.length}`);
    }
    if (data.description !== undefined) {
      values.push(data.description);
      fields.push(`description = $${values.length}`);
    }
    if (data.rewardType !== undefined) {
      values.push(data.rewardType);
      fields.push(`reward_type = $${values.length}`);
    }
    if (data.targetProductId !== undefined) {
      values.push(data.targetProductId);
      fields.push(`target_product_id = $${values.length}`);
    }
    if (data.googlePlayOfferId !== undefined) {
      values.push(data.googlePlayOfferId);
      fields.push(`google_play_offer_id = $${values.length}`);
    }
    if (data.discountAmount !== undefined) {
      values.push(data.discountAmount);
      fields.push(`discount_amount = $${values.length}`);
    }
    if (data.coinsReward !== undefined) {
      values.push(data.coinsReward);
      fields.push(`coins_reward = $${values.length}`);
    }
    if (data.vipDaysReward !== undefined) {
      values.push(data.vipDaysReward);
      fields.push(`vip_days_reward = $${values.length}`);
    }
    if (data.maxUsesTotal !== undefined) {
      values.push(data.maxUsesTotal ? parseInt(data.maxUsesTotal, 10) : null);
      fields.push(`max_uses_total = $${values.length}`);
    }
    if (data.maxUsesPerUser !== undefined) {
      values.push(data.maxUsesPerUser ? parseInt(data.maxUsesPerUser, 10) : 1);
      fields.push(`max_uses_per_user = $${values.length}`);
    }
    if (data.startsAt !== undefined) {
      values.push(new Date(data.startsAt));
      fields.push(`starts_at = $${values.length}`);
    }
    if (data.expiresAt !== undefined) {
      values.push(new Date(data.expiresAt));
      fields.push(`expires_at = $${values.length}`);
    }
    if (data.isActive !== undefined) {
      values.push(Boolean(data.isActive));
      fields.push(`is_active = $${values.length}`);
    }

    if (fields.length === 0) {
      const existing = await db.query('SELECT * FROM promo_codes WHERE id = $1', [id]);
      return existing.rows[0];
    }

    fields.push('updated_at = NOW()');
    values.push(id);

    const updateRes = await db.query(
      `UPDATE promo_codes SET ${fields.join(', ')} WHERE id = $${values.length} RETURNING *`,
      values
    );

    if (updateRes.rows.length === 0) {
      throw { statusCode: 404, message: 'Promo code not found.' };
    }
    return updateRes.rows[0];
  }

  /**
   * Delete a promo code
   */
  static async deletePromoCode(id) {
    const res = await db.query('DELETE FROM promo_codes WHERE id = $1 RETURNING id', [id]);
    if (res.rows.length === 0) {
      throw { statusCode: 404, message: 'Promo code not found.' };
    }
    return { success: true, deletedId: id };
  }

  /**
   * Validate promo code for subscription purchases
   */
  static async validateSubscriptionPromo(userId, { code, productId }) {
    if (!code || !code.trim()) {
      throw { statusCode: 400, message: 'Please enter a promo code.' };
    }
    const normalizedCode = code.trim().toUpperCase();

    const promoRes = await db.query(
      `SELECT * FROM promo_codes 
       WHERE code = $1 AND is_active = TRUE`,
      [normalizedCode]
    );

    if (promoRes.rows.length === 0) {
      throw { statusCode: 404, message: 'Invalid or inactive promo code.' };
    }
    const promo = promoRes.rows[0];

    const now = new Date();
    if (new Date(promo.starts_at) > now) {
      throw { statusCode: 400, message: 'This promo code is not active yet.' };
    }
    if (new Date(promo.expires_at) < now) {
      throw { statusCode: 400, message: 'This promo code has expired.' };
    }

    if (promo.max_uses_total !== null && promo.times_redeemed >= promo.max_uses_total) {
      throw { statusCode: 400, message: 'This promo code has reached its maximum redemptions.' };
    }

    // Check user redemption limit
    if (userId) {
      const redemptionsRes = await db.query(
        `SELECT COUNT(*)::int as count FROM promo_code_redemptions 
         WHERE promo_code_id = $1 AND user_id = $2`,
        [promo.id, userId]
      );
      if (redemptionsRes.rows[0]?.count >= promo.max_uses_per_user) {
        throw { statusCode: 400, message: 'You have already used this promo code.' };
      }
    }

    // Verify product compatibility if specified
    if (promo.reward_type === 'GOOGLE_PLAY_OFFER' && promo.target_product_id && productId) {
      const cleanTarget = promo.target_product_id.replace(/^membership_|^pass_/, '');
      const cleanIncoming = productId.replace(/^membership_|^pass_/, '');
      const isTargetAll = cleanTarget === 'all' || promo.target_product_id === 'all';
      const isDirectMatch = promo.target_product_id === productId;
      const isCleanMatch = cleanTarget === cleanIncoming;

      if (!isTargetAll && !isDirectMatch && !isCleanMatch) {
        throw {
          statusCode: 400,
          message: `This promo code is only valid for the ${promo.target_product_id} plan/pack.`,
        };
      }
    }

    return {
      valid: true,
      code: promo.code,
      title: promo.title,
      rewardType: promo.reward_type,
      googlePlayOfferId: promo.google_play_offer_id,
      discountAmount: Number(promo.discount_amount) || 0,
      targetProductId: promo.target_product_id,
      message: `Promo code ${promo.code} applied successfully!`,
    };
  }

  /**
   * Redeem direct rewards (free coins or free VIP pass)
   */
  static async redeemDirectPromo(userId, { code, ipAddress = null }) {
    if (!code || !code.trim()) {
      throw { statusCode: 400, message: 'Please enter a promo code.' };
    }
    const normalizedCode = code.trim().toUpperCase();

    const client = await db.pool.connect();
    try {
      await client.query('BEGIN');

      const promoRes = await client.query(
        `SELECT * FROM promo_codes 
         WHERE code = $1 AND is_active = TRUE 
         FOR UPDATE`,
        [normalizedCode]
      );

      if (promoRes.rows.length === 0) {
        throw { statusCode: 404, message: 'Invalid or inactive promo code.' };
      }
      const promo = promoRes.rows[0];

      const now = new Date();
      if (new Date(promo.starts_at) > now) {
        throw { statusCode: 400, message: 'This promo code is not active yet.' };
      }
      if (new Date(promo.expires_at) < now) {
        throw { statusCode: 400, message: 'This promo code has expired.' };
      }

      if (promo.max_uses_total !== null && promo.times_redeemed >= promo.max_uses_total) {
        throw { statusCode: 400, message: 'This promo code has reached its maximum redemptions.' };
      }

      const redemptionsRes = await client.query(
        `SELECT COUNT(*)::int as count FROM promo_code_redemptions 
         WHERE promo_code_id = $1 AND user_id = $2`,
        [promo.id, userId]
      );
      if (redemptionsRes.rows[0]?.count >= promo.max_uses_per_user) {
        throw { statusCode: 400, message: 'You have already redeemed this promo code.' };
      }

      let successMessage = 'Promo code redeemed successfully!';

      if (promo.reward_type === 'FREE_COINS') {
        const coins = parseInt(promo.coins_reward, 10);
        if (coins <= 0) throw { statusCode: 400, message: 'Invalid coin reward configuration.' };

        // Dual-balance ledger: Strictly credit spendable_balance (non-withdrawable)
        await client.query(
          `UPDATE wallets 
           SET spendable_balance = spendable_balance + $1, updated_at = NOW() 
           WHERE user_id = $2`,
          [coins, userId]
        );

        await client.query(
          `INSERT INTO wallet_transactions 
           (user_id, spendable_delta, earned_delta, reason, reference_id) 
           VALUES ($1, $2, 0, 'admin_grant', $3)`,
          [userId, coins, `promo_${promo.code}`]
        );

        successMessage = `🎉 Success! ${coins} coins have been added to your wallet.`;
      } else if (promo.reward_type === 'FREE_VIP') {
        const days = parseInt(promo.vip_days_reward, 10);
        if (days <= 0) throw { statusCode: 400, message: 'Invalid VIP duration configuration.' };

        await client.query(
          `INSERT INTO user_subscriptions (user_id, plan_id, status, starts_at, expires_at)
           VALUES ($1, 'promo_vip', 'active', NOW(), NOW() + ($2 || ' days')::INTERVAL)
           ON CONFLICT (user_id) DO UPDATE SET
             status = 'active',
             expires_at = GREATEST(user_subscriptions.expires_at, NOW()) + ($2 || ' days')::INTERVAL,
             updated_at = NOW()`,
          [userId, days]
        );

        successMessage = `👑 Awesome! ${days} days of VIP Membership unlocked.`;
      } else {
        throw {
          statusCode: 400,
          message: 'This promo code is designed for subscription checkout discounts, not direct redemption.',
        };
      }

      // Record redemption and increment counter
      await client.query(
        `INSERT INTO promo_code_redemptions (
          promo_code_id, user_id, reward_type, discount_amount, coins_reward, vip_days_reward
        ) VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          promo.id,
          userId,
          promo.reward_type,
          promo.discount_amount || 0,
          promo.coins_reward || 0,
          promo.vip_days_reward || 0,
        ]
      );

      await client.query(
        `UPDATE promo_codes SET times_redeemed = times_redeemed + 1 WHERE id = $1`,
        [promo.id]
      );

      await client.query('COMMIT');

      return {
        success: true,
        code: promo.code,
        rewardType: promo.reward_type,
        coinsReward: promo.coins_reward,
        vipDaysReward: promo.vip_days_reward,
        message: successMessage,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Record redemption after successful Google Play payment verification
   */
  static async recordGooglePlayRedemption(userId, code, orderId) {
    if (!code || !userId) return;
    try {
      const normalizedCode = code.trim().toUpperCase();
      const promoRes = await db.query(
        `SELECT id, discount_amount, reward_type FROM promo_codes WHERE code = $1`,
        [normalizedCode]
      );
      if (promoRes.rows.length === 0) return;
      const promo = promoRes.rows[0];

      await db.query(
        `INSERT INTO promo_code_redemptions (
          promo_code_id, user_id, order_id, reward_type, discount_amount
        ) VALUES ($1, $2, $3, $4, $5)`,
        [promo.id, userId, orderId || null, promo.reward_type, promo.discount_amount || 0]
      );

      await db.query(
        `UPDATE promo_codes SET times_redeemed = times_redeemed + 1 WHERE id = $1`,
        [promo.id]
      );
    } catch (err) {
      console.warn('⚠️ [PromoCodes] Non-fatal redemption logging error:', err.message);
    }
  }
}

module.exports = { PromoCodesService };
