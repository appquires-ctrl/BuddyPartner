require('dotenv').config();
const path = require('path');
const fs = require('fs');
const db = require('../db');
const cloudinary = require('cloudinary').v2;

async function migrateAdsToCloudinary() {
  console.log('🚀 Starting Cloudinary Advertisement Image Migration...');

  const hasCloudinary =
    Boolean(process.env.CLOUDINARY_CLOUD_NAME) &&
    Boolean(process.env.CLOUDINARY_API_KEY) &&
    Boolean(process.env.CLOUDINARY_API_SECRET);

  if (hasCloudinary) {
    cloudinary.config({
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
      api_key: process.env.CLOUDINARY_API_KEY,
      api_secret: process.env.CLOUDINARY_API_SECRET,
    });
    console.log('✅ Cloudinary credentials configured.');
  } else {
    console.log('⚠️ CLOUDINARY credentials not set in environment.');
    console.log('ℹ️ Skipping remote upload; checking local files status...');
  }

  try {
    const res = await db.query(`
      SELECT id, image_url AS "imageUrl", click_url AS "clickUrl"
      FROM public.advertisements
    `);

    const ads = res.rows;
    console.log(`📋 Found ${ads.length} total advertisement record(s) in database.`);

    let migratedCount = 0;
    let missingCount = 0;
    let skippedCount = 0;

    const uploadsDir = path.join(__dirname, '../uploads/ads');

    for (const ad of ads) {
      const url = ad.imageUrl;

      // Skip if already a Cloudinary or external HTTPS URL (and not local /uploads/ads)
      if (url.includes('cloudinary.com') || (url.startsWith('https://') && !url.includes('/uploads/ads/'))) {
        console.log(`⏩ Ad [${ad.id}] already using CDN URL: ${url}`);
        skippedCount++;
        continue;
      }

      // Extract filename from local URL or path
      const filename = path.basename(url);
      const localFilePath = path.join(uploadsDir, filename);

      if (!fs.existsSync(localFilePath)) {
        console.warn(`⚠️ Ad [${ad.id}] local file not found on disk at: ${localFilePath}`);
        console.warn(`   ➜ Flagged: Admin must re-upload image from Admin Panel.`);
        missingCount++;
        continue;
      }

      if (!hasCloudinary) {
        console.log(`ℹ️ Ad [${ad.id}] has local file present (${filename}), but Cloudinary credentials are not set.`);
        skippedCount++;
        continue;
      }

      // Re-upload local file to Cloudinary
      try {
        console.log(`📤 Uploading local file for Ad [${ad.id}] (${filename}) to Cloudinary...`);
        const uploadRes = await cloudinary.uploader.upload(localFilePath, {
          folder: 'buddypartner/ads',
        });

        const newSecureUrl = uploadRes.secure_url;

        await db.query(
          `UPDATE public.advertisements SET image_url = $1, updated_at = NOW() WHERE id = $2`,
          [newSecureUrl, ad.id]
        );

        console.log(`✅ Ad [${ad.id}] successfully migrated to: ${newSecureUrl}`);
        migratedCount++;
      } catch (uploadErr) {
        console.error(`❌ Failed to upload Ad [${ad.id}] to Cloudinary:`, uploadErr.message);
      }
    }

    console.log('\n=================== MIGRATION SUMMARY ===================');
    console.log(`✅ Successfully Migrated: ${migratedCount}`);
    console.log(`⏩ Skipped / Already CDN: ${skippedCount}`);
    console.log(`⚠️ Missing Local Files: ${missingCount}`);
    console.log('=========================================================\n');

    process.exit(0);
  } catch (err) {
    console.error('❌ Error during Cloudinary ads migration:', err.message);
    process.exit(1);
  }
}

migrateAdsToCloudinary();
