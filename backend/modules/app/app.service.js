const db = require('../../db');
const semver = require('semver');

const redis = require('../../redis');
const cacheService = require('../../services/cache.service');

const DEFAULT_CONFIGS = {
  minimum_supported_version_android: '1.0.0',
  minimum_supported_version_ios: '1.0.0',
  store_url_android: 'https://play.google.com/store/apps/details?id=com.buddypartner.app',
  store_url_ios: 'https://apps.apple.com/app/id6400000000',
};

class AppService {
  constructor() {
    this.inMemoryConfig = { ...DEFAULT_CONFIGS };
    this.refreshInterval = null;
  }

  /**
   * Refresh in-memory config from Redis (with DB fallback if Redis key is missing).
   * Safe fallback: on any error (e.g. Redis unavailable), keep last known cached values.
   */
  async refreshCache() {
    for (const key of Object.keys(DEFAULT_CONFIGS)) {
      try {
        let val = await redis.get(`app_config:${key}`);
        if (val === null || val === undefined) {
          const res = await db.query('SELECT value FROM public.app_config WHERE key = $1', [key]);
          val = res.rows[0]?.value || DEFAULT_CONFIGS[key] || null;
          if (val !== null) {
            await redis.set(`app_config:${key}`, val, 'EX', 86400).catch(() => {});
          }
        }
        if (val !== null && val !== undefined) {
          this.inMemoryConfig[key] = val;
        }
      } catch (err) {
        console.warn(
          `[AppConfig Cache] Failed to refresh ${key} from Redis, keeping last known value (${this.inMemoryConfig[key]}):`,
          err.message
        );
      }
    }
  }

  /**
   * Ensure app_config table exists, default keys are seeded, and in-memory cache is primed
   */
  async initAppConfig() {
    try {
      await db.query(`
        CREATE TABLE IF NOT EXISTS public.app_config (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at TIMESTAMPTZ DEFAULT NOW()
        );
      `);

      for (const [key, value] of Object.entries(DEFAULT_CONFIGS)) {
        await db.query(
          `INSERT INTO public.app_config (key, value)
           VALUES ($1, $2)
           ON CONFLICT (key) DO NOTHING`,
          [key, value]
        );
      }
      console.log('✅ App config table and version keys initialized.');
    } catch (err) {
      console.error('❌ Error initializing app config:', err.message);
    }

    // Populate in-memory cache on process startup before serving traffic
    await this.refreshCache();

    // Periodically refresh in-memory cache from Redis every 60 seconds
    if (!this.refreshInterval) {
      this.refreshInterval = setInterval(() => {
        this.refreshCache().catch((err) => {
          console.warn('[AppConfig Cache] Periodic refresh error:', err.message);
        });
      }, 60000);
      if (this.refreshInterval.unref) {
        this.refreshInterval.unref();
      }
    }
  }

  /**
   * Stop background refresh interval (useful for tests and graceful shutdown)
   */
  stopRefreshInterval() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  /**
   * Get config value by key from in-memory cache.
   * Eliminates Redis calls and DB queries during live requests.
   * @param {string} key
   * @returns {Promise<string|null>}
   */
  async getConfig(key) {
    if (this.inMemoryConfig[key] !== undefined) {
      return this.inMemoryConfig[key];
    }
    return DEFAULT_CONFIGS[key] || null;
  }

  /**
   * Set config value by key in DB and Redis, updating in-memory cache immediately.
   * @param {string} key
   * @param {string} value
   */
  async setConfig(key, value) {
    try {
      await db.query(
        `INSERT INTO public.app_config (key, value, updated_at)
         VALUES ($1, $2, NOW())
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
        [key, value]
      );
      await redis.set(`app_config:${key}`, value, 'EX', 86400).catch(() => {});
      this.inMemoryConfig[key] = value;
      return true;
    } catch (err) {
      console.error(`Error setting config for ${key}:`, err.message);
      throw err;
    }
  }

  /**
   * Perform semver check for platform & current version
   * @param {string} platform - 'android' | 'ios'
   * @param {string} currentVersion - e.g. '1.4.2'
   * @returns {Promise<Object>}
   */
  async checkVersion(platform = 'android', currentVersion = '1.0.0') {
    const cleanPlatform = (platform || 'android').toLowerCase() === 'ios' ? 'ios' : 'android';
    const minVersionKey = `minimum_supported_version_${cleanPlatform}`;
    const storeUrlKey = `store_url_${cleanPlatform}`;

    const minVersion = (await this.getConfig(minVersionKey)) || '1.0.0';
    const storeUrl = (await this.getConfig(storeUrlKey)) || DEFAULT_CONFIGS[storeUrlKey];

    const validCurrent = semver.valid(semver.coerce(currentVersion)) || '1.0.0';
    const validMin = semver.valid(semver.coerce(minVersion)) || '1.0.0';

    // updateRequired if current version is strictly LESS THAN minimum supported version
    const updateRequired = semver.lt(validCurrent, validMin);

    return {
      platform: cleanPlatform,
      minimumSupportedVersion: minVersion,
      currentVersion: currentVersion,
      updateRequired,
      storeUrl,
    };
  }
}

const appService = new AppService();

module.exports = {
  appService,
  AppService,
};
