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
    { city: 'Agartala', state: 'Tripura' },
    { city: 'Agra', state: 'Uttar Pradesh' },
    { city: 'Ahmedabad', state: 'Gujarat' },
    { city: 'Ahmednagar', state: 'Maharashtra' },
    { city: 'Aizawl', state: 'Mizoram' },
    { city: 'Ajmer', state: 'Rajasthan' },
    { city: 'Akola', state: 'Maharashtra' },
    { city: 'Aligarh', state: 'Uttar Pradesh' },
    { city: 'Allahabad', state: 'Uttar Pradesh' },
    { city: 'Alwar', state: 'Rajasthan' },
    { city: 'Ambala', state: 'Haryana' },
    { city: 'Amravati', state: 'Maharashtra' },
    { city: 'Amritsar', state: 'Punjab' },
    { city: 'Anand', state: 'Gujarat' },
    { city: 'Anantapur', state: 'Andhra Pradesh' },
    { city: 'Asansol', state: 'West Bengal' },
    { city: 'Aurangabad', state: 'Bihar' },
    { city: 'Aurangabad', state: 'Maharashtra' },
    { city: 'Ayodhya', state: 'Uttar Pradesh' },
    { city: 'Balasore', state: 'Odisha' },
    { city: 'Bangalore', state: 'Karnataka' },
    { city: 'Bareilly', state: 'Uttar Pradesh' },
    { city: 'Bathinda', state: 'Punjab' },
    { city: 'Belgaum', state: 'Karnataka' },
    { city: 'Bellary', state: 'Karnataka' },
    { city: 'Bengaluru', state: 'Karnataka' },
    { city: 'Berhampur', state: 'Odisha' },
    { city: 'Bhagalpur', state: 'Bihar' },
    { city: 'Bharatpur', state: 'Rajasthan' },
    { city: 'Bharuch', state: 'Gujarat' },
    { city: 'Bhavnagar', state: 'Gujarat' },
    { city: 'Bhilai', state: 'Chhattisgarh' },
    { city: 'Bhilwara', state: 'Rajasthan' },
    { city: 'Bhopal', state: 'Madhya Pradesh' },
    { city: 'Bhubaneswar', state: 'Odisha' },
    { city: 'Bhuj', state: 'Gujarat' },
    { city: 'Bikaner', state: 'Rajasthan' },
    { city: 'Bilaspur', state: 'Chhattisgarh' },
    { city: 'Bokaro', state: 'Jharkhand' },
    { city: 'Chandigarh', state: 'Chandigarh' },
    { city: 'Chandrapur', state: 'Maharashtra' },
    { city: 'Chennai', state: 'Tamil Nadu' },
    { city: 'Chhatrapati Sambhajinagar', state: 'Maharashtra' },
    { city: 'Coimbatore', state: 'Tamil Nadu' },
    { city: 'Cuttack', state: 'Odisha' },
    { city: 'Daman', state: 'Dadra and Nagar Haveli and Daman and Diu' },
    { city: 'Darbhanga', state: 'Bihar' },
    { city: 'Darjeeling', state: 'West Bengal' },
    { city: 'Dehradun', state: 'Uttarakhand' },
    { city: 'Delhi', state: 'Delhi' },
    { city: 'Deoghar', state: 'Jharkhand' },
    { city: 'Dhanbad', state: 'Jharkhand' },
    { city: 'Dharamshala', state: 'Himachal Pradesh' },
    { city: 'Dibrugarh', state: 'Assam' },
    { city: 'Dimapur', state: 'Nagaland' },
    { city: 'Dispur', state: 'Assam' },
    { city: 'Diu', state: 'Dadra and Nagar Haveli and Daman and Diu' },
    { city: 'Durgapur', state: 'West Bengal' },
    { city: 'Faridabad', state: 'Haryana' },
    { city: 'Firozabad', state: 'Uttar Pradesh' },
    { city: 'Gandhidham', state: 'Gujarat' },
    { city: 'Gandhinagar', state: 'Gujarat' },
    { city: 'Gangtok', state: 'Sikkim' },
    { city: 'Gaya', state: 'Bihar' },
    { city: 'Ghaziabad', state: 'Uttar Pradesh' },
    { city: 'Godhra', state: 'Gujarat' },
    { city: 'Gorakhpur', state: 'Uttar Pradesh' },
    { city: 'Greater Noida', state: 'Uttar Pradesh' },
    { city: 'Gulbarga', state: 'Karnataka' },
    { city: 'Guntur', state: 'Andhra Pradesh' },
    { city: 'Gurgaon', state: 'Haryana' },
    { city: 'Guwahati', state: 'Assam' },
    { city: 'Gwalior', state: 'Madhya Pradesh' },
    { city: 'Haldwani', state: 'Uttarakhand' },
    { city: 'Haridwar', state: 'Uttarakhand' },
    { city: 'Hazaribagh', state: 'Jharkhand' },
    { city: 'Hisar', state: 'Haryana' },
    { city: 'Howrah', state: 'West Bengal' },
    { city: 'Hubli', state: 'Karnataka' },
    { city: 'Hyderabad', state: 'Telangana' },
    { city: 'Imphal', state: 'Manipur' },
    { city: 'Indore', state: 'Madhya Pradesh' },
    { city: 'Itanagar', state: 'Arunachal Pradesh' },
    { city: 'Jabalpur', state: 'Madhya Pradesh' },
    { city: 'Jaipur', state: 'Rajasthan' },
    { city: 'Jaisalmer', state: 'Rajasthan' },
    { city: 'Jalandhar', state: 'Punjab' },
    { city: 'Jalgaon', state: 'Maharashtra' },
    { city: 'Jammu', state: 'Jammu and Kashmir' },
    { city: 'Jamnagar', state: 'Gujarat' },
    { city: 'Jamshedpur', state: 'Jharkhand' },
    { city: 'Jhansi', state: 'Uttar Pradesh' },
    { city: 'Jodhpur', state: 'Rajasthan' },
    { city: 'Junagadh', state: 'Gujarat' },
    { city: 'Kakinada', state: 'Andhra Pradesh' },
    { city: 'Kalyan', state: 'Maharashtra' },
    { city: 'Kannur', state: 'Kerala' },
    { city: 'Kanpur', state: 'Uttar Pradesh' },
    { city: 'Karnal', state: 'Haryana' },
    { city: 'Kharagpur', state: 'West Bengal' },
    { city: 'Kochi', state: 'Kerala' },
    { city: 'Kohima', state: 'Nagaland' },
    { city: 'Kolhapur', state: 'Maharashtra' },
    { city: 'Kolkata', state: 'West Bengal' },
    { city: 'Kollam', state: 'Kerala' },
    { city: 'Korba', state: 'Chhattisgarh' },
    { city: 'Kota', state: 'Rajasthan' },
    { city: 'Kottayam', state: 'Kerala' },
    { city: 'Kozhikode', state: 'Kerala' },
    { city: 'Kullu', state: 'Himachal Pradesh' },
    { city: 'Kurnool', state: 'Andhra Pradesh' },
    { city: 'Latur', state: 'Maharashtra' },
    { city: 'Leh', state: 'Ladakh' },
    { city: 'Lucknow', state: 'Uttar Pradesh' },
    { city: 'Ludhiana', state: 'Punjab' },
    { city: 'Madurai', state: 'Tamil Nadu' },
    { city: 'Malegaon', state: 'Maharashtra' },
    { city: 'Manali', state: 'Himachal Pradesh' },
    { city: 'Mangalore', state: 'Karnataka' },
    { city: 'Mangaluru', state: 'Karnataka' },
    { city: 'Mathura', state: 'Uttar Pradesh' },
    { city: 'Meerut', state: 'Uttar Pradesh' },
    { city: 'Mehsana', state: 'Gujarat' },
    { city: 'Mira-Bhayandar', state: 'Maharashtra' },
    { city: 'Mohali', state: 'Punjab' },
    { city: 'Moradabad', state: 'Uttar Pradesh' },
    { city: 'Morbi', state: 'Gujarat' },
    { city: 'Mount Abu', state: 'Rajasthan' },
    { city: 'Mumbai', state: 'Maharashtra' },
    { city: 'Muzaffarnagar', state: 'Uttar Pradesh' },
    { city: 'Muzaffarpur', state: 'Bihar' },
    { city: 'Mysore', state: 'Karnataka' },
    { city: 'Mysuru', state: 'Karnataka' },
    { city: 'Nadiad', state: 'Gujarat' },
    { city: 'Nagpur', state: 'Maharashtra' },
    { city: 'Nainital', state: 'Uttarakhand' },
    { city: 'Nanded', state: 'Maharashtra' },
    { city: 'Nashik', state: 'Maharashtra' },
    { city: 'Navi Mumbai', state: 'Maharashtra' },
    { city: 'Navsari', state: 'Gujarat' },
    { city: 'Nellore', state: 'Andhra Pradesh' },
    { city: 'New Delhi', state: 'Delhi' },
    { city: 'Nizamabad', state: 'Telangana' },
    { city: 'Noida', state: 'Uttar Pradesh' },
    { city: 'Panaji', state: 'Goa' },
    { city: 'Panchkula', state: 'Haryana' },
    { city: 'Panipat', state: 'Haryana' },
    { city: 'Panvel', state: 'Maharashtra' },
    { city: 'Patan', state: 'Gujarat' },
    { city: 'Pathankot', state: 'Punjab' },
    { city: 'Patiala', state: 'Punjab' },
    { city: 'Patna', state: 'Bihar' },
    { city: 'Porbandar', state: 'Gujarat' },
    { city: 'Port Blair', state: 'Andaman and Nicobar Islands' },
    { city: 'Prayagraj', state: 'Uttar Pradesh' },
    { city: 'Puducherry', state: 'Puducherry' },
    { city: 'Pune', state: 'Maharashtra' },
    { city: 'Puri', state: 'Odisha' },
    { city: 'Purnia', state: 'Bihar' },
    { city: 'Raipur', state: 'Chhattisgarh' },
    { city: 'Rajahmundry', state: 'Andhra Pradesh' },
    { city: 'Rajkot', state: 'Gujarat' },
    { city: 'Ranchi', state: 'Jharkhand' },
    { city: 'Rishikesh', state: 'Uttarakhand' },
    { city: 'Rohtak', state: 'Haryana' },
    { city: 'Roorkee', state: 'Uttarakhand' },
    { city: 'Rourkela', state: 'Odisha' },
    { city: 'Saharanpur', state: 'Uttar Pradesh' },
    { city: 'Salem', state: 'Tamil Nadu' },
    { city: 'Sambalpur', state: 'Odisha' },
    { city: 'Sangli', state: 'Maharashtra' },
    { city: 'Secunderabad', state: 'Telangana' },
    { city: 'Shillong', state: 'Meghalaya' },
    { city: 'Shimla', state: 'Himachal Pradesh' },
    { city: 'Silchar', state: 'Assam' },
    { city: 'Siliguri', state: 'West Bengal' },
    { city: 'Silvassa', state: 'Dadra and Nagar Haveli and Daman and Diu' },
    { city: 'Solapur', state: 'Maharashtra' },
    { city: 'Sonipat', state: 'Haryana' },
    { city: 'Srinagar', state: 'Jammu and Kashmir' },
    { city: 'Surat', state: 'Gujarat' },
    { city: 'Surendranagar', state: 'Gujarat' },
    { city: 'Thane', state: 'Maharashtra' },
    { city: 'Thanjavur', state: 'Tamil Nadu' },
    { city: 'Thiruvananthapuram', state: 'Kerala' },
    { city: 'Thrissur', state: 'Kerala' },
    { city: 'Tiruchirappalli', state: 'Tamil Nadu' },
    { city: 'Tirunelveli', state: 'Tamil Nadu' },
    { city: 'Tirupati', state: 'Andhra Pradesh' },
    { city: 'Tiruppur', state: 'Tamil Nadu' },
    { city: 'Udaipur', state: 'Rajasthan' },
    { city: 'Ujjain', state: 'Madhya Pradesh' },
    { city: 'Vadodara', state: 'Gujarat' },
    { city: 'Valsad', state: 'Gujarat' },
    { city: 'Vapi', state: 'Gujarat' },
    { city: 'Varanasi', state: 'Uttar Pradesh' },
    { city: 'Vasai-Virar', state: 'Maharashtra' },
    { city: 'Vellore', state: 'Tamil Nadu' },
    { city: 'Vijayawada', state: 'Andhra Pradesh' },
    { city: 'Visakhapatnam', state: 'Andhra Pradesh' },
    { city: 'Warangal', state: 'Telangana' },
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
 * Makes an HTTP request to CountriesNow API with automatic redirect following.
 * Returns parsed JSON body or throws an Error.
 */
function fetchJson(url, options = {}, maxRedirects = 3) {
  return new Promise((resolve, reject) => {
    if (maxRedirects <= 0) return reject(new Error('CountriesNow: too many redirects'));

    const urlObj = new URL(url);
    const isHttps = urlObj.protocol === 'https:';
    const lib = isHttps ? https : http;

    const method = options.method || (options.body ? 'POST' : 'GET');
    const payload = options.body ? JSON.stringify(options.body) : null;

    const reqOptions = {
      protocol: urlObj.protocol,
      hostname: urlObj.hostname,
      port: urlObj.port || (isHttps ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method,
      headers: {
        'User-Agent': 'BuddyPartner/1.0',
        'Accept': 'application/json',
        ...(payload
          ? {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(payload),
            }
          : {}),
      },
      timeout: 8000,
    };

    const req = lib.request(reqOptions, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        const nextUrl = new URL(res.headers.location, url).href;
        const nextOptions =
          res.statusCode === 303 || res.statusCode === 301 || res.statusCode === 302
            ? { method: 'GET' }
            : options;
        return resolve(fetchJson(nextUrl, nextOptions, maxRedirects - 1));
      }

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

    if (payload) {
      req.write(payload);
    }
    req.end();
  });
}

function postJson(url, body) {
  return fetchJson(url, { method: 'POST', body });
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
      // 1. Fetch flat cities via CountriesNow GET endpoint
      const flat = await this._fetchFlatCities(countryName);
      if (flat && flat.length > 0) {
        // Enrich flat cities with known states from fallback list
        const fallbackList = FALLBACK_POPULAR_CITIES[iso] || [];
        const stateMap = new Map();
        for (const item of fallbackList) {
          if (item.city && item.state) {
            stateMap.set(item.city.toLowerCase(), item.state);
          }
        }

        const enriched = flat.map((c) => {
          const knownState = stateMap.get(c.city.toLowerCase());
          return knownState ? { city: c.city, state: knownState } : c;
        });

        // Ensure all fallback cities (with full state accuracy) are present
        const seen = new Set(enriched.map((c) => c.city.toLowerCase()));
        for (const fb of fallbackList) {
          if (!seen.has(fb.city.toLowerCase())) {
            enriched.push(fb);
            seen.add(fb.city.toLowerCase());
          }
        }

        return enriched.sort((a, b) => a.city.localeCompare(b.city));
      }
    } catch (err) {
      console.error(`[GeoService] CountriesNow fetch failed for ${countryName}:`, err.message);
    }
    return [];
  }

  /** Fallback: flat list of cities without state info */
  async _fetchFlatCities(countryName) {
    try {
      const response = await fetchJson(
        `${COUNTRIES_NOW_BASE}/countries/cities/q?country=${encodeURIComponent(countryName)}`
      );

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
      const response = await fetchJson(
        `${COUNTRIES_NOW_BASE}/countries/states/q?country=${encodeURIComponent(countryName)}`
      );
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
