'use strict';

const redis = require('../../redis');
const https = require('https');
const http = require('http');

// ── Constants ───────────────────────────────────────────────────────────────
const CACHE_TTL_SECONDS = 86400; // 24 hours — geo data is effectively static
const COUNTRIES_NOW_BASE = 'https://countriesnow.space/api/v0.1';

// CountriesNow uses country full names, not ISO codes. Map ISO → full name.
const ISO_TO_COUNTRY_NAME = {
  IN: 'India',
  US: 'United States',
  GB: 'United Kingdom',
  CA: 'Canada',
  AU: 'Australia',
  AE: 'United Arab Emirates',
  SA: 'Saudi Arabia',
  SG: 'Singapore',
  DE: 'Germany',
  FR: 'France',
  JP: 'Japan',
  KR: 'South Korea',
  IT: 'Italy',
  ES: 'Spain',
  BR: 'Brazil',
  MX: 'Mexico',
  ID: 'Indonesia',
  MY: 'Malaysia',
  PH: 'Philippines',
  TH: 'Thailand',
  VN: 'Vietnam',
  NP: 'Nepal',
  BD: 'Bangladesh',
  LK: 'Sri Lanka',
  QA: 'Qatar',
  KW: 'Kuwait',
  BH: 'Bahrain',
  OM: 'Oman',
  ZA: 'South Africa',
  NG: 'Nigeria',
  KE: 'Kenya',
  GH: 'Ghana',
  EG: 'Egypt',
  AR: 'Argentina',
  CO: 'Colombia',
  PK: 'Pakistan',
  TR: 'Turkey',
  RU: 'Russia',
  NL: 'Netherlands',
  SE: 'Sweden',
  NO: 'Norway',
  DK: 'Denmark',
  FI: 'Finland',
  CH: 'Switzerland',
  AT: 'Austria',
  BE: 'Belgium',
  PL: 'Poland',
  PT: 'Portugal',
  NZ: 'New Zealand',
  HK: 'Hong Kong',
  TW: 'Taiwan',
  MM: 'Myanmar',
  KH: 'Cambodia',
  LK: 'Sri Lanka',
};

// ── Built-in Fast Fallback Seed ─────────────────────────────────────────────
// Guaranteed instant response for primary markets even on cold cache or if CountriesNow is down
const FALLBACK_POPULAR_CITIES = {
  IN: [
    { city: 'Agra', state: 'Uttar Pradesh' },
    { city: 'Ahmedabad', state: 'Gujarat' },
    { city: 'Allahabad', state: 'Uttar Pradesh' },
    { city: 'Amritsar', state: 'Punjab' },
    { city: 'Aurangabad', state: 'Maharashtra' },
    { city: 'Aurangabad', state: 'Bihar' },
    { city: 'Bangalore', state: 'Karnataka' },
    { city: 'Bareilly', state: 'Uttar Pradesh' },
    { city: 'Bhopal', state: 'Madhya Pradesh' },
    { city: 'Bhubaneswar', state: 'Odisha' },
    { city: 'Chandigarh', state: 'Chandigarh' },
    { city: 'Chennai', state: 'Tamil Nadu' },
    { city: 'Coimbatore', state: 'Tamil Nadu' },
    { city: 'Dehradun', state: 'Uttarakhand' },
    { city: 'Delhi', state: 'Delhi' },
    { city: 'Dhanbad', state: 'Jharkhand' },
    { city: 'Faridabad', state: 'Haryana' },
    { city: 'Ghaziabad', state: 'Uttar Pradesh' },
    { city: 'Gurgaon', state: 'Haryana' },
    { city: 'Guwahati', state: 'Assam' },
    { city: 'Gwalior', state: 'Madhya Pradesh' },
    { city: 'Howrah', state: 'West Bengal' },
    { city: 'Hubli', state: 'Karnataka' },
    { city: 'Hyderabad', state: 'Telangana' },
    { city: 'Indore', state: 'Madhya Pradesh' },
    { city: 'Jabalpur', state: 'Madhya Pradesh' },
    { city: 'Jaipur', state: 'Rajasthan' },
    { city: 'Jodhpur', state: 'Rajasthan' },
    { city: 'Kanpur', state: 'Uttar Pradesh' },
    { city: 'Kochi', state: 'Kerala' },
    { city: 'Kolkata', state: 'West Bengal' },
    { city: 'Kota', state: 'Rajasthan' },
    { city: 'Lucknow', state: 'Uttar Pradesh' },
    { city: 'Ludhiana', state: 'Punjab' },
    { city: 'Madurai', state: 'Tamil Nadu' },
    { city: 'Meerut', state: 'Uttar Pradesh' },
    { city: 'Moradabad', state: 'Uttar Pradesh' },
    { city: 'Mumbai', state: 'Maharashtra' },
    { city: 'Mysore', state: 'Karnataka' },
    { city: 'Nagpur', state: 'Maharashtra' },
    { city: 'Nashik', state: 'Maharashtra' },
    { city: 'Navi Mumbai', state: 'Maharashtra' },
    { city: 'Noida', state: 'Uttar Pradesh' },
    { city: 'Patna', state: 'Bihar' },
    { city: 'Pune', state: 'Maharashtra' },
    { city: 'Raipur', state: 'Chhattisgarh' },
    { city: 'Rajkot', state: 'Gujarat' },
    { city: 'Ranchi', state: 'Jharkhand' },
    { city: 'Solapur', state: 'Maharashtra' },
    { city: 'Srinagar', state: 'Jammu and Kashmir' },
    { city: 'Surat', state: 'Gujarat' },
    { city: 'Thane', state: 'Maharashtra' },
    { city: 'Vadodara', state: 'Gujarat' },
    { city: 'Varanasi', state: 'Uttar Pradesh' },
    { city: 'Vijayawada', state: 'Andhra Pradesh' },
    { city: 'Visakhapatnam', state: 'Andhra Pradesh' },
  ],
  US: [
    { city: 'Albuquerque', state: 'New Mexico' },
    { city: 'Atlanta', state: 'Georgia' },
    { city: 'Austin', state: 'Texas' },
    { city: 'Baltimore', state: 'Maryland' },
    { city: 'Boston', state: 'Massachusetts' },
    { city: 'Charlotte', state: 'North Carolina' },
    { city: 'Chicago', state: 'Illinois' },
    { city: 'Columbus', state: 'Ohio' },
    { city: 'Dallas', state: 'Texas' },
    { city: 'Denver', state: 'Colorado' },
    { city: 'Detroit', state: 'Michigan' },
    { city: 'El Paso', state: 'Texas' },
    { city: 'Fort Worth', state: 'Texas' },
    { city: 'Houston', state: 'Texas' },
    { city: 'Indianapolis', state: 'Indiana' },
    { city: 'Jacksonville', state: 'Florida' },
    { city: 'Kansas City', state: 'Missouri' },
    { city: 'Las Vegas', state: 'Nevada' },
    { city: 'Los Angeles', state: 'California' },
    { city: 'Louisville', state: 'Kentucky' },
    { city: 'Memphis', state: 'Tennessee' },
    { city: 'Miami', state: 'Florida' },
    { city: 'Milwaukee', state: 'Wisconsin' },
    { city: 'Nashville', state: 'Tennessee' },
    { city: 'New York', state: 'New York' },
    { city: 'Oklahoma City', state: 'Oklahoma' },
    { city: 'Philadelphia', state: 'Pennsylvania' },
    { city: 'Phoenix', state: 'Arizona' },
    { city: 'Portland', state: 'Oregon' },
    { city: 'Raleigh', state: 'North Carolina' },
    { city: 'Sacramento', state: 'California' },
    { city: 'San Antonio', state: 'Texas' },
    { city: 'San Diego', state: 'California' },
    { city: 'San Francisco', state: 'California' },
    { city: 'San Jose', state: 'California' },
    { city: 'Seattle', state: 'Washington' },
    { city: 'Tucson', state: 'Arizona' },
    { city: 'Washington', state: 'District of Columbia' },
  ],
  GB: [
    { city: 'Birmingham', state: 'England' },
    { city: 'Bristol', state: 'England' },
    { city: 'Edinburgh', state: 'Scotland' },
    { city: 'Glasgow', state: 'Scotland' },
    { city: 'Leeds', state: 'England' },
    { city: 'Liverpool', state: 'England' },
    { city: 'London', state: 'England' },
    { city: 'Manchester', state: 'England' },
    { city: 'Newcastle', state: 'England' },
    { city: 'Sheffield', state: 'England' },
  ],
  AE: [
    { city: 'Abu Dhabi', state: 'Abu Dhabi' },
    { city: 'Ajman', state: 'Ajman' },
    { city: 'Al Ain', state: 'Abu Dhabi' },
    { city: 'Dubai', state: 'Dubai' },
    { city: 'Fujairah', state: 'Fujairah' },
    { city: 'Ras Al Khaimah', state: 'Ras Al Khaimah' },
    { city: 'Sharjah', state: 'Sharjah' },
  ],
  SG: [
    { city: 'Singapore', state: '' },
    { city: 'Sentosa', state: '' },
  ],
  CA: [
    { city: 'Calgary', state: 'Alberta' },
    { city: 'Edmonton', state: 'Alberta' },
    { city: 'Montreal', state: 'Quebec' },
    { city: 'Ottawa', state: 'Ontario' },
    { city: 'Quebec City', state: 'Quebec' },
    { city: 'Toronto', state: 'Ontario' },
    { city: 'Vancouver', state: 'British Columbia' },
    { city: 'Winnipeg', state: 'Manitoba' },
  ],
  AU: [
    { city: 'Adelaide', state: 'South Australia' },
    { city: 'Brisbane', state: 'Queensland' },
    { city: 'Canberra', state: 'Australian Capital Territory' },
    { city: 'Gold Coast', state: 'Queensland' },
    { city: 'Melbourne', state: 'Victoria' },
    { city: 'Perth', state: 'Western Australia' },
    { city: 'Sydney', state: 'New South Wales' },
  ],
};

// ── HTTP Helper ─────────────────────────────────────────────────────────────
/**
 * Makes a POST request to CountriesNow API.
 * Returns parsed JSON body or throws an Error.
 */
function postJson(url, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const isHttps = url.startsWith('https');
    const lib = isHttps ? https : http;

    const urlObj = new URL(url);
    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || (isHttps ? 443 : 80),
      path: urlObj.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(payload),
        'User-Agent': 'BuddyPartner/1.0',
      },
      timeout: 8000,
    };

    const req = lib.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          reject(new Error('CountriesNow: invalid JSON response'));
        }
      });
    });

    req.on('timeout', () => {
      req.destroy();
      reject(new Error('CountriesNow: request timed out'));
    });
    req.on('error', (err) => reject(err));
    req.write(payload);
    req.end();
  });
}

// ── GeoService ───────────────────────────────────────────────────────────────
class GeoService {
  /**
   * Returns cities for a given ISO country code, scoped by optional query string.
   * Flow: Redis cache → CountriesNow API → Fallback Seed → Redis set (24h TTL).
   *
   * @param {string} countryIso - ISO 3166-1 alpha-2 code (e.g. 'IN', 'US')
   * @param {string} [q=''] - Search query to filter cities (case-insensitive)
   * @param {number} [limit=20] - Max results to return
   * @returns {Promise<Array<{city: string, state: string}>>}
   */
  async searchCities({ countryIso, q = '', limit = 20 }) {
    const iso = (countryIso || 'IN').toUpperCase().trim();
    const countryName = ISO_TO_COUNTRY_NAME[iso];

    if (!countryName) {
      // Unknown ISO — return empty list gracefully
      return [];
    }

    const cacheKey = `geo:cities:${iso}`;
    let cities = await this._getCached(cacheKey);

    if (!cities || cities.length === 0) {
      cities = await this._fetchFromCountriesNow(countryName, iso);
      if (!cities || cities.length === 0) {
        // Fallback seed prevents empty screen on cold cache / network latency
        cities = FALLBACK_POPULAR_CITIES[iso] || [];
      }
      if (cities.length > 0) {
        await this._setCache(cacheKey, cities, CACHE_TTL_SECONDS);
      }
    }

    return this._filter(cities, q, limit);
  }

  /**
   * Returns states for a given ISO country code.
   * Flow: Redis cache → CountriesNow API → Redis set (24h TTL).
   *
   * @param {string} countryIso - ISO 3166-1 alpha-2 code
   * @returns {Promise<string[]>}
   */
  async getStates(countryIso) {
    const iso = (countryIso || 'IN').toUpperCase().trim();
    const countryName = ISO_TO_COUNTRY_NAME[iso];

    if (!countryName) return [];

    const cacheKey = `geo:states:${iso}`;
    let states = await this._getCached(cacheKey);

    if (!states) {
      states = await this._fetchStatesFromCountriesNow(countryName);
      await this._setCache(cacheKey, states, CACHE_TTL_SECONDS);
    }

    return states;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  async _getCached(key) {
    try {
      const raw = await redis.get(key);
      if (raw) return JSON.parse(raw);
    } catch {
      // Redis miss or parse error — fall through to API
    }
    return null;
  }

  async _setCache(key, value, ttl) {
    try {
      await redis.set(key, JSON.stringify(value), 'EX', ttl);
    } catch (err) {
      console.warn(`[GeoService] Failed to cache ${key}:`, err.message);
    }
  }

  /**
   * Fetches cities from CountriesNow and normalizes them into
   * an array of { city, state } objects sorted alphabetically.
   */
  async _fetchFromCountriesNow(countryName, iso) {
    try {
      // CountriesNow: POST /countries/state/cities returns cities grouped by state
      const statesResponse = await postJson(`${COUNTRIES_NOW_BASE}/countries/states`, {
        country: countryName,
      });

      if (!statesResponse.error && Array.isArray(statesResponse.data?.states)) {
        const cities = [];
        const stateList = statesResponse.data.states;

        // For each state, fetch its cities in parallel (up to 5 at a time)
        const batchSize = 5;
        for (let i = 0; i < stateList.length; i += batchSize) {
          const batch = stateList.slice(i, i + batchSize);
          const results = await Promise.allSettled(
            batch.map((s) =>
              postJson(`${COUNTRIES_NOW_BASE}/countries/state/cities`, {
                country: countryName,
                state: s.name,
              }).then((r) => ({ state: s.name, data: r }))
            )
          );

          for (const result of results) {
            if (result.status === 'fulfilled') {
              const { state, data } = result.value;
              if (!data.error && Array.isArray(data.data)) {
                for (const city of data.data) {
                  if (city && city.trim()) {
                    cities.push({ city: city.trim(), state: state.trim() });
                  }
                }
              }
            }
          }
        }

        if (cities.length > 0) {
          return cities.sort((a, b) => a.city.localeCompare(b.city));
        }
      }

      // Fallback: try the flat cities endpoint
      return await this._fetchFlatCities(countryName);
    } catch (err) {
      console.error(`[GeoService] CountriesNow fetch failed for ${countryName}:`, err.message);
      return [];
    }
  }

  /** Fallback: flat list of cities without state info */
  async _fetchFlatCities(countryName) {
    try {
      const response = await postJson(`${COUNTRIES_NOW_BASE}/countries/cities`, {
        country: countryName,
      });

      if (!response.error && Array.isArray(response.data)) {
        return response.data
          .filter((c) => c && c.trim())
          .map((c) => ({ city: c.trim(), state: '' }))
          .sort((a, b) => a.city.localeCompare(b.city));
      }
    } catch (err) {
      console.error(`[GeoService] Flat cities fetch failed for ${countryName}:`, err.message);
    }
    return [];
  }

  async _fetchStatesFromCountriesNow(countryName) {
    try {
      const response = await postJson(`${COUNTRIES_NOW_BASE}/countries/states`, {
        country: countryName,
      });
      if (!response.error && Array.isArray(response.data?.states)) {
        return response.data.states
          .map((s) => s.name)
          .filter(Boolean)
          .sort();
      }
    } catch (err) {
      console.error(`[GeoService] States fetch failed for ${countryName}:`, err.message);
    }
    return [];
  }

  /**
   * Filters city list by a search query string (case-insensitive prefix/substring match).
   */
  _filter(cities, q, limit) {
    if (!q || !q.trim()) {
      // No query — return popular cities first (first `limit` alphabetically)
      return cities.slice(0, limit);
    }

    const query = q.trim().toLowerCase();

    // Priority 1: starts-with match on city name
    const startsWith = cities.filter((c) => c.city.toLowerCase().startsWith(query));

    // Priority 2: substring match on city or state
    const contains = cities.filter(
      (c) =>
        !c.city.toLowerCase().startsWith(query) &&
        (c.city.toLowerCase().includes(query) || c.state.toLowerCase().includes(query))
    );

    return [...startsWith, ...contains].slice(0, limit);
  }
}

const geoService = new GeoService();
module.exports = { geoService, FALLBACK_POPULAR_CITIES };
