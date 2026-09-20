const db = require('../../db');
const redis = require('../../redis');
const cacheService = require('../../services/cache.service');

class AdvertisementsService {
  constructor() {
    // Flush buffered clicks to Postgres every 5 minutes
    this.flushTimer = setInterval(() => {
      this.flushBufferedClicks().catch(() => {});
    }, 5 * 60 * 1000);
    if (this.flushTimer.unref) this.flushTimer.unref();
  }

  /**
   * Get all active advertisements ordered by display_order.
   * Cached in Redis with 10-minute (600s) TTL; invalidated on admin ad mutations.
   */
  async getActiveAds() {
    return cacheService.getOrSet('ads:active', 600, async () => {
      const res = await db.query(`
        SELECT id, image_url AS "imageUrl", click_url AS "clickUrl", display_order AS "displayOrder"
        FROM public.advertisements
        WHERE is_active = TRUE
        ORDER BY display_order ASC, created_at DESC
      `);
      return res.rows;
    });
  }

  /**
   * Get all advertisements (active + inactive) for Admin Panel.
   * Merges real-time buffered click counts from Redis with persisted DB counts.
   */
  async getAllAds() {
    const res = await db.query(`
      SELECT 
        id, 
        image_url AS "imageUrl", 
        click_url AS "clickUrl", 
        is_active AS "isActive", 
        display_order AS "displayOrder",
        click_count AS "clickCount",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM public.advertisements
      ORDER BY display_order ASC, created_at DESC
    `);

    let buffered = {};
    try {
      buffered = await redis.hgetall('ad:clicks') || {};
    } catch (_) {}

    return res.rows.map(row => ({
      ...row,
      clickCount: (parseInt(row.clickCount, 10) || 0) + (parseInt(buffered[row.id], 10) || 0),
    }));
  }

  /**
   * Create a new advertisement and invalidate active ads cache.
   */
  async createAd({ imageUrl, clickUrl, isActive = true, displayOrder = 0, createdBy = null }) {
    const res = await db.query(`
      INSERT INTO public.advertisements (image_url, click_url, is_active, display_order, created_by)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING 
        id, 
        image_url AS "imageUrl", 
        click_url AS "clickUrl", 
        is_active AS "isActive", 
        display_order AS "displayOrder",
        click_count AS "clickCount",
        created_at AS "createdAt"
    `, [imageUrl, clickUrl, isActive, displayOrder, createdBy]);

    await cacheService.invalidate('ads:active').catch(() => {});
    return res.rows[0];
  }

  /**
   * Update an existing advertisement and invalidate active ads cache.
   */
  async updateAd(id, { imageUrl, clickUrl, isActive, displayOrder }) {
    const updates = [];
    const values = [];
    let idx = 1;

    if (imageUrl !== undefined) {
      updates.push(`image_url = $${idx++}`);
      values.push(imageUrl);
    }
    if (clickUrl !== undefined) {
      updates.push(`click_url = $${idx++}`);
      values.push(clickUrl);
    }
    if (isActive !== undefined) {
      updates.push(`is_active = $${idx++}`);
      values.push(isActive);
    }
    if (displayOrder !== undefined) {
      updates.push(`display_order = $${idx++}`);
      values.push(displayOrder);
    }

    if (updates.length === 0) return null;

    updates.push(`updated_at = NOW()`);
    values.push(id);

    const res = await db.query(`
      UPDATE public.advertisements
      SET ${updates.join(', ')}
      WHERE id = $${idx}
      RETURNING 
        id, 
        image_url AS "imageUrl", 
        click_url AS "clickUrl", 
        is_active AS "isActive", 
        display_order AS "displayOrder",
        click_count AS "clickCount",
        updated_at AS "updatedAt"
    `, values);

    await cacheService.invalidate('ads:active').catch(() => {});
    return res.rows[0] || null;
  }

  /**
   * Delete an advertisement and invalidate active ads cache.
   */
  async deleteAd(id) {
    const res = await db.query(`
      DELETE FROM public.advertisements
      WHERE id = $1
      RETURNING id
    `, [id]);

    await cacheService.invalidate('ads:active').catch(() => {});
    return res.rowCount > 0;
  }

  /**
   * Increment click count: buffers increments in Redis (HINCRBY ad:clicks <id> 1).
   * Avoids high-frequency direct database UPDATEs per click under 5,000 CCU.
   */
  async incrementClickCount(id) {
    if (!id) return true;
    try {
      await redis.hincrby('ad:clicks', String(id), 1);
    } catch (err) {
      // Fallback directly to Postgres if Redis is partitioned
      await db.query(`
        UPDATE public.advertisements
        SET click_count = click_count + 1
        WHERE id = $1
      `, [id]).catch(() => {});
    }
    return true;
  }

  /**
   * Periodically flush buffered click counts from Redis to PostgreSQL.
   * Uses distributed lock to prevent multi-instance race conditions.
   */
  async flushBufferedClicks() {
    const lockKey = 'lock:ad_click_flush';
    let acquired = false;
    try {
      const lockRes = await redis.set(lockKey, '1', 'EX', 30, 'NX').catch(() => null);
      if (!lockRes) return false;
      acquired = true;

      let clicks = null;
      try {
        clicks = await redis.hgetall('ad:clicks');
      } catch (_) {
        return;
      }
      if (!clicks || Object.keys(clicks).length === 0) return;

      for (const [adId, countStr] of Object.entries(clicks)) {
        const count = parseInt(countStr, 10);
        if (count > 0) {
          // Decrement in Redis by the batch size being flushed
          await redis.hincrby('ad:clicks', adId, -count).catch(() => {});
          await db.query(
            `UPDATE public.advertisements SET click_count = click_count + $1 WHERE id = $2`,
            [count, adId]
          );
        }
      }
    } catch (err) {
      console.error('Error flushing buffered ad clicks to Postgres:', err.message);
    } finally {
      if (acquired) {
        await redis.del(lockKey).catch(() => {});
      }
    }
  }
}

module.exports = new AdvertisementsService();
