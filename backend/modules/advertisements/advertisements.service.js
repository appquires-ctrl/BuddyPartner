const db = require('../../db');

class AdvertisementsService {
  /**
   * Get all active advertisements ordered by display_order
   */
  async getActiveAds() {
    const res = await db.query(`
      SELECT id, image_url AS "imageUrl", click_url AS "clickUrl", display_order AS "displayOrder"
      FROM public.advertisements
      WHERE is_active = TRUE
      ORDER BY display_order ASC, created_at DESC
    `);
    return res.rows;
  }

  /**
   * Get all advertisements (active + inactive) for Admin Panel
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
    return res.rows;
  }

  /**
   * Create a new advertisement
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
    return res.rows[0];
  }

  /**
   * Update an existing advertisement
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

    return res.rows[0] || null;
  }

  /**
   * Delete an advertisement
   */
  async deleteAd(id) {
    const res = await db.query(`
      DELETE FROM public.advertisements
      WHERE id = $1
      RETURNING id
    `, [id]);
    return res.rowCount > 0;
  }

  /**
   * Increment click count (fire and forget)
   */
  async incrementClickCount(id) {
    await db.query(`
      UPDATE public.advertisements
      SET click_count = click_count + 1
      WHERE id = $1
    `, [id]);
    return true;
  }
}

module.exports = new AdvertisementsService();
