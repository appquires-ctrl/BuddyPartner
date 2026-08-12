const db = require('../../db');
const semver = require('semver');

const DEFAULT_CONFIGS = {
  minimum_supported_version_android: '1.0.0',
  minimum_supported_version_ios: '1.0.0',
  store_url_android: 'https://play.google.com/store/apps/details?id=com.buddypartner.app',
  store_url_ios: 'https://apps.apple.com/app/id6400000000',
};

class AppService {
  /**
   * Ensure app_config table exists and default keys are seeded
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
  }

  /**
   * Get config value by key
   * @param {string} key
   * @returns {Promise<string|null>}
   */
  async getConfig(key) {
    try {
      const res = await db.query(
        'SELECT value FROM public.app_config WHERE key = $1',
        [key]
      );
      return res.rows[0]?.value || DEFAULT_CONFIGS[key] || null;
    } catch (err) {
      console.error(`Error fetching config for ${key}:`, err.message);
      return DEFAULT_CONFIGS[key] || null;
    }
  }

  /**
   * Set config value by key
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
