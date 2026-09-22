const db = require('../../db');
const cacheService = require('../../services/cache.service');

class BuddyBannersService {
  /**
   * Get all active banners within valid date range for client apps.
   * Cached in Redis with 10-minute (600s) TTL; invalidated on admin banner mutations.
   */
  async getActiveBanners() {
    return cacheService.getOrSet('buddy_banners:active', 600, async () => {
      try {
        const res = await db.query(`
          SELECT 
            id,
            name,
            image_url AS "imageUrl",
            priority,
            start_date AS "startDate",
            end_date AS "endDate",
            is_active AS "isActive",
            sheet_config AS "sheetConfig",
            otp_reward AS "otpReward"
          FROM public.seasonal_banners
          WHERE is_active = TRUE
            AND (start_date IS NULL OR start_date <= (NOW() + interval '12 hours'))
            AND (end_date IS NULL OR (end_date + interval '1 day') >= NOW())
          ORDER BY priority ASC, created_at DESC
        `);

        return res.rows;
      } catch (err) {
        console.error('Error in getActiveBanners:', err.message);
        return [];
      }
    });
  }

  /**
   * Get all banners for Admin Panel.
   */
  async getAllBanners() {
    try {
      const res = await db.query(`
        SELECT 
          id,
          name,
          image_url AS "imageUrl",
          priority,
          start_date AS "startDate",
          end_date AS "endDate",
          is_active AS "isActive",
          sheet_config AS "sheetConfig",
          otp_reward AS "otpReward",
          created_at AS "createdAt",
          updated_at AS "updatedAt"
        FROM public.seasonal_banners
        ORDER BY priority ASC, created_at DESC
      `);

      return res.rows;
    } catch (err) {
      console.error('Error in getAllBanners:', err.message);
      return [];
    }
  }

  /**
   * Create a new seasonal buddy banner.
   */
  async createBanner({
    name,
    imageUrl,
    priority = 1,
    startDate = null,
    endDate = null,
    isActive = true,
    sheetConfig = {},
    otpReward = {},
  }) {
    const res = await db.query(`
      INSERT INTO public.seasonal_banners (
        name, image_url, priority, start_date, end_date, is_active, sheet_config, otp_reward
      )
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING 
        id,
        name,
        image_url AS "imageUrl",
        priority,
        start_date AS "startDate",
        end_date AS "endDate",
        is_active AS "isActive",
        sheet_config AS "sheetConfig",
        otp_reward AS "otpReward",
        created_at AS "createdAt"
    `, [
      name,
      imageUrl,
      priority,
      startDate ? new Date(startDate) : null,
      endDate ? new Date(endDate) : null,
      isActive,
      JSON.stringify(sheetConfig),
      JSON.stringify(otpReward),
    ]);

    await cacheService.invalidate('buddy_banners:active');
    return res.rows[0];
  }

  /**
   * Update an existing seasonal buddy banner.
   */
  async updateBanner(id, {
    name,
    imageUrl,
    priority,
    startDate,
    endDate,
    isActive,
    sheetConfig,
    otpReward,
  }) {
    const sets = [];
    const values = [];
    let idx = 1;

    if (name !== undefined) {
      sets.push(`name = $${idx++}`);
      values.push(name);
    }
    if (imageUrl !== undefined) {
      sets.push(`image_url = $${idx++}`);
      values.push(imageUrl);
    }
    if (priority !== undefined) {
      sets.push(`priority = $${idx++}`);
      values.push(priority);
    }
    if (startDate !== undefined) {
      sets.push(`start_date = $${idx++}`);
      values.push(startDate ? new Date(startDate) : null);
    }
    if (endDate !== undefined) {
      sets.push(`end_date = $${idx++}`);
      values.push(endDate ? new Date(endDate) : null);
    }
    if (isActive !== undefined) {
      sets.push(`is_active = $${idx++}`);
      values.push(isActive);
    }
    if (sheetConfig !== undefined) {
      sets.push(`sheet_config = $${idx++}`);
      values.push(JSON.stringify(sheetConfig));
    }
    if (otpReward !== undefined) {
      sets.push(`otp_reward = $${idx++}`);
      values.push(JSON.stringify(otpReward));
    }

    if (sets.length === 0) return null;

    sets.push(`updated_at = NOW()`);
    values.push(id);

    const res = await db.query(`
      UPDATE public.seasonal_banners
      SET ${sets.join(', ')}
      WHERE id = $${idx}
      RETURNING 
        id,
        name,
        image_url AS "imageUrl",
        priority,
        start_date AS "startDate",
        end_date AS "endDate",
        is_active AS "isActive",
        sheet_config AS "sheetConfig",
        otp_reward AS "otpReward",
        updated_at AS "updatedAt"
    `, values);

    await cacheService.invalidate('buddy_banners:active');
    return res.rows[0] || null;
  }

  /**
   * Delete a seasonal buddy banner.
   */
  async deleteBanner(id) {
    const res = await db.query(`
      DELETE FROM public.seasonal_banners
      WHERE id = $1
      RETURNING id
    `, [id]);

    await cacheService.invalidate('buddy_banners:active');
    return res.rowCount > 0;
  }
}

module.exports = new BuddyBannersService();
