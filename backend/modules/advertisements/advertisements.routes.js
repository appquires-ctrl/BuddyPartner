const express = require('express');
const path = require('path');
const fs = require('fs');
const multer = require('multer');
const jwt = require('jsonwebtoken');
const adsService = require('./advertisements.service');

const JWT_SECRET = process.env.JWT_SECRET || 'buddypartner_fallback_jwt_secret_key_change_me_in_prod';

const router = express.Router();

const cloudinary = require('cloudinary').v2;
const { CloudinaryStorage } = require('multer-storage-cloudinary');

// Ensure upload directory exists for local fallback
const uploadsDir = path.join(__dirname, '../../uploads/ads');
if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

// Check Cloudinary environment variables
const hasCloudinary =
  Boolean(process.env.CLOUDINARY_CLOUD_NAME) &&
  Boolean(process.env.CLOUDINARY_API_KEY) &&
  Boolean(process.env.CLOUDINARY_API_SECRET);

let storage;

if (hasCloudinary) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });

  storage = new CloudinaryStorage({
    cloudinary: cloudinary,
    params: {
      folder: 'buddypartner/ads',
      allowed_formats: ['jpg', 'png', 'jpeg', 'webp'],
    },
  });
  console.log('✅ Cloudinary storage engine configured for ad uploads.');
} else {
  storage = multer.diskStorage({
    destination: function (_req, _file, cb) {
      cb(null, uploadsDir);
    },
    filename: function (_req, file, cb) {
      const ext = path.extname(file.originalname).toLowerCase() || '.jpg';
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
      cb(null, `ad-${uniqueSuffix}${ext}`);
    },
  });
  console.log('ℹ️ Cloudinary credentials not found; using local disk storage fallback.');
}

// Multer File Filter & Limits
const upload = multer({
  storage: storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB max
  fileFilter: function (_req, file, cb) {
    const allowedTypes = ['image/jpeg', 'image/png', 'image/webp'];
    if (allowedTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only JPEG, PNG, and WebP images are allowed.'));
    }
  },
});

// Admin Auth Middleware
function adminAuth(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, message: 'Unauthorized: missing token' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    if (!decoded || !decoded.isAdmin) {
      return res.status(403).json({ success: false, message: 'Forbidden: admin access required' });
    }
    req.admin = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ success: false, message: 'Unauthorized: invalid token' });
  }
}

// Helper function to validate URL scheme
function isValidHttpUrl(stringUrl) {
  if (!stringUrl || typeof stringUrl !== 'string') return false;
  try {
    const parsed = new URL(stringUrl);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch (_) {
    return false;
  }
}

// ── 1. Public App Endpoints ──────────────────────────────────────────────────

// GET /api/advertisements/active
router.get('/active', async (_req, res) => {
  try {
    const ads = await adsService.getActiveAds();
    return res.json({ success: true, advertisements: ads });
  } catch (err) {
    console.error('Error fetching active advertisements:', err.message);
    return res.status(500).json({ success: false, message: 'Failed to fetch advertisements' });
  }
});

// POST /api/advertisements/:id/click
router.post('/:id/click', async (req, res) => {
  try {
    await adsService.incrementClickCount(req.params.id);
    return res.json({ success: true, message: 'Click recorded' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// ── 2. Admin Endpoints ───────────────────────────────────────────────────────

// POST /api/admin/advertisements/upload-image OR /api/advertisements/upload-image
router.post(['/upload-image', '/admin/upload-image'], adminAuth, (req, res) => {
  upload.single('image')(req, res, (err) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(400).json({ success: false, message: 'File too large. Maximum size is 5MB.' });
      }
      return res.status(400).json({ success: false, message: err.message });
    } else if (err) {
      return res.status(400).json({ success: false, message: err.message });
    }

    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No image file provided.' });
    }

    let imageUrl;
    if (req.file.path && (req.file.path.startsWith('http://') || req.file.path.startsWith('https://'))) {
      imageUrl = req.file.path;
    } else if (req.file.secure_url) {
      imageUrl = req.file.secure_url;
    } else {
      const host = req.get('host');
      const protocol = req.protocol;
      imageUrl = `${protocol}://${host}/uploads/ads/${req.file.filename}`;
    }

    return res.json({
      success: true,
      imageUrl,
      filename: req.file.filename || req.file.public_id,
    });
  });
});

// GET /api/admin/advertisements OR /api/admin/advertisements/list
router.get(['/', '/list', '/admin/list'], adminAuth, async (_req, res) => {
  try {
    const ads = await adsService.getAllAds();
    return res.json({ success: true, advertisements: ads });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// POST /api/admin/advertisements OR /api/admin/advertisements/create
router.post(['/', '/create', '/admin/create'], adminAuth, async (req, res) => {
  try {
    const { imageUrl, clickUrl, isActive = true, displayOrder = 0 } = req.body;

    if (!imageUrl || typeof imageUrl !== 'string') {
      return res.status(400).json({ success: false, message: 'Image URL is required' });
    }

    if (!isValidHttpUrl(clickUrl)) {
      return res.status(400).json({ success: false, message: 'Click URL must be a valid http:// or https:// URL' });
    }

    const ad = await adsService.createAd({
      imageUrl: imageUrl.trim(),
      clickUrl: clickUrl.trim(),
      isActive: Boolean(isActive),
      displayOrder: Number(displayOrder) || 0,
      createdBy: req.admin?.id || null,
    });

    return res.status(201).json({ success: true, advertisement: ad });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// PUT /api/admin/advertisements/:id
router.put(['/:id', '/admin/:id'], adminAuth, async (req, res) => {
  try {
    const { imageUrl, clickUrl, isActive, displayOrder } = req.body;

    if (clickUrl !== undefined && !isValidHttpUrl(clickUrl)) {
      return res.status(400).json({ success: false, message: 'Click URL must be a valid http:// or https:// URL' });
    }

    const updated = await adsService.updateAd(req.params.id, {
      imageUrl: imageUrl ? imageUrl.trim() : undefined,
      clickUrl: clickUrl ? clickUrl.trim() : undefined,
      isActive: isActive !== undefined ? Boolean(isActive) : undefined,
      displayOrder: displayOrder !== undefined ? Number(displayOrder) : undefined,
    });

    if (!updated) {
      return res.status(404).json({ success: false, message: 'Advertisement not found' });
    }

    return res.json({ success: true, advertisement: updated });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

// DELETE /api/admin/advertisements/:id
router.delete(['/:id', '/admin/:id'], adminAuth, async (req, res) => {
  try {
    const deleted = await adsService.deleteAd(req.params.id);
    if (!deleted) {
      return res.status(404).json({ success: false, message: 'Advertisement not found' });
    }
    return res.json({ success: true, message: 'Advertisement deleted successfully' });
  } catch (err) {
    return res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
