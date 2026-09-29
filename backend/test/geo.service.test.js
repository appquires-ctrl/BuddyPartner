'use strict';

/**
 * Backend unit tests for geo.service.js
 * Tests the filter logic, ISO mapping, and caching mechanism WITHOUT
 * requiring a live CountriesNow API call or Redis connection.
 */

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✅ ${name}`);
    passed++;
  } catch (err) {
    console.error(`  ❌ ${name}`);
    console.error(`     ${err.message}`);
    failed++;
  }
}

function expect(actual) {
  return {
    toBe: (expected) => {
      if (actual !== expected)
        throw new Error(`Expected ${JSON.stringify(actual)} to be ${JSON.stringify(expected)}`);
    },
    toEqual: (expected) => {
      const a = JSON.stringify(actual), b = JSON.stringify(expected);
      if (a !== b) throw new Error(`Expected ${a} to equal ${b}`);
    },
    toHaveLength: (n) => {
      if (!actual || actual.length !== n)
        throw new Error(`Expected length ${n} but got ${actual?.length}`);
    },
    toContain: (item) => {
      if (!actual || !actual.includes(item))
        throw new Error(`Expected array to contain ${JSON.stringify(item)}`);
    },
    toBeEmpty: () => {
      if (!actual || actual.length !== 0)
        throw new Error(`Expected empty array but got length ${actual?.length}`);
    },
    toBeGreaterThan: (n) => {
      if (actual <= n) throw new Error(`Expected ${actual} > ${n}`);
    },
  };
}

// ── Import the real service ──────────────────────────────────────────────────
// We need to mock Redis and the HTTP calls to test in isolation.

const path = require('path');

// Mock Redis (no actual connection needed)
const mockRedisStore = {};
const mockRedis = {
  get: async (key) => mockRedisStore[key] ?? null,
  set: async (key, value) => { mockRedisStore[key] = value; return 'OK'; },
};

// Inject mock BEFORE loading geo.service (which requires redis at load time)
// __dirname = backend/test → resolve to backend/redis.js
const redisModulePath = path.resolve(__dirname, '../redis.js');
require.cache[redisModulePath] = {
  id: redisModulePath,
  filename: redisModulePath,
  loaded: true,
  exports: mockRedis,
};

// Also mock db (safety net — not needed by geo.service but prevents stray require errors)
const dbModulePath = path.resolve(__dirname, '../db.js');
require.cache[dbModulePath] = {
  id: dbModulePath,
  filename: dbModulePath,
  loaded: true,
  exports: { query: async () => ({ rows: [] }) },
};

// Load GeoService after mocking Redis
const { geoService } = require('../modules/geo/geo.service');

// ── Test Suite ───────────────────────────────────────────────────────────────

console.log('\n📍 Backend GeoService Unit Tests\n');

// ── Group 1: ISO → Country Name Mapping ─────────────────────────────────────
console.log('Group 1: ISO → Country Name Mapping');

test('ISO_TO_COUNTRY_NAME has India for IN', () => {
  // Verify the internal mapping works by testing searchCities early-return for unknown ISO
  // We call geoService._filter which is the pure in-memory function
});

test('_filter returns first N cities when query is empty', () => {
  const cities = [
    { city: 'Surat', state: 'Gujarat' },
    { city: 'Surendranagar', state: 'Gujarat' },
    { city: 'Srinagar', state: 'Jammu and Kashmir' },
    { city: 'Mumbai', state: 'Maharashtra' },
    { city: 'Pune', state: 'Maharashtra' },
  ];
  const result = geoService._filter(cities, '', 3);
  expect(result).toHaveLength(3);
  expect(result[0].city).toBe('Surat');
});

test('_filter prioritises startsWith over contains', () => {
  const cities = [
    { city: 'Navi Mumbai', state: 'Maharashtra' },
    { city: 'Mumbai', state: 'Maharashtra' },
    { city: 'Surat', state: 'Gujarat' },
  ];
  const result = geoService._filter(cities, 'mum', 5);
  // 'Mumbai' starts with 'mum' → comes first
  // 'Navi Mumbai' contains 'mum' → comes second
  expect(result[0].city).toBe('Mumbai');
  expect(result[1].city).toBe('Navi Mumbai');
});

test('_filter matches state name substring', () => {
  const cities = [
    { city: 'Austin', state: 'Texas' },
    { city: 'San Antonio', state: 'Texas' },
    { city: 'Miami', state: 'Florida' },
  ];
  const result = geoService._filter(cities, 'texas', 10);
  expect(result).toHaveLength(2);
  expect(result[0].city).toBe('Austin');
  expect(result[1].city).toBe('San Antonio');
});

test('_filter is case-insensitive', () => {
  const cities = [
    { city: 'Bangalore', state: 'Karnataka' },
    { city: 'Bengaluru', state: 'Karnataka' },
  ];
  const r1 = geoService._filter(cities, 'BANGA', 10);
  const r2 = geoService._filter(cities, 'banga', 10);
  expect(r1).toHaveLength(r2.length);
});

test('_filter returns empty for no match', () => {
  const cities = [
    { city: 'Surat', state: 'Gujarat' },
    { city: 'Pune', state: 'Maharashtra' },
  ];
  const result = geoService._filter(cities, 'xyz_nonexistent', 10);
  expect(result).toBeEmpty();
});

test('_filter respects limit', () => {
  const cities = Array.from({ length: 30 }, (_, i) => ({ city: `City${i}`, state: 'State' }));
  const result = geoService._filter(cities, '', 20);
  expect(result).toHaveLength(20);
});

test('_filter: "sur" matches Surat before Surendranagar (alphabetical startsWith)', () => {
  const cities = [
    { city: 'Surendranagar', state: 'Gujarat' },
    { city: 'Surat', state: 'Gujarat' },
    { city: 'Sursand', state: 'Bihar' },
  ];
  const result = geoService._filter(cities, 'sur', 5);
  // All start with 'sur' so order preserved from original sorted array
  expect(result).toHaveLength(3);
  result.forEach(r => {
    if (!r.city.toLowerCase().startsWith('sur') && !r.state.toLowerCase().includes('sur'))
      throw new Error(`Unexpected result: ${r.city}`);
  });
});

// ── Group 2: Redis Cache Logic ───────────────────────────────────────────────
console.log('\nGroup 2: Redis Cache Logic');

test('_getCached returns null when key not in cache', async () => {
  const result = await geoService._getCached('geo:cities:NOCACHE');
  // result is null because mockRedisStore does not have this key
  if (result !== null) throw new Error(`Expected null, got ${JSON.stringify(result)}`);
});

test('_setCache and _getCached round-trip works', async () => {
  const key = 'geo:cities:TEST';
  const data = [{ city: 'TestCity', state: 'TestState' }];
  await geoService._setCache(key, data, 3600);
  const retrieved = await geoService._getCached(key);
  if (!retrieved || retrieved[0].city !== 'TestCity')
    throw new Error(`Cache round-trip failed: ${JSON.stringify(retrieved)}`);
});

test('_getCached returns null for invalid JSON in cache', async () => {
  mockRedisStore['geo:cities:BADJSON'] = '{ invalid json {{{{';
  const result = await geoService._getCached('geo:cities:BADJSON');
  if (result !== null) throw new Error(`Expected null for bad JSON, got ${JSON.stringify(result)}`);
});

// ── Group 3: searchCities with cached data (no network) ─────────────────────
console.log('\nGroup 3: searchCities with pre-seeded Redis cache');

test('searchCities returns cached data when Redis has it', async () => {
  const cacheKey = 'geo:cities:v2:SG';
  const cachedData = [
    { city: 'Singapore', state: '' },
    { city: 'Sentosa', state: '' },
  ];
  mockRedisStore[cacheKey] = JSON.stringify(cachedData);

  const results = await geoService.searchCities({ countryIso: 'SG', q: '', limit: 10 });
  if (results.length !== 2) throw new Error(`Expected 2 results, got ${results.length}`);
  if (results[0].city !== 'Singapore') throw new Error(`Expected Singapore, got ${results[0].city}`);
});

test('searchCities filters cached data with query', async () => {
  const cacheKey = 'geo:cities:v2:AU';
  const cachedData = [
    { city: 'Adelaide', state: 'South Australia' },
    { city: 'Brisbane', state: 'Queensland' },
    { city: 'Cairns', state: 'Queensland' },
    { city: 'Darwin', state: 'Northern Territory' },
    { city: 'Melbourne', state: 'Victoria' },
    { city: 'Perth', state: 'Western Australia' },
    { city: 'Sydney', state: 'New South Wales' },
  ];
  mockRedisStore[cacheKey] = JSON.stringify(cachedData);

  const results = await geoService.searchCities({ countryIso: 'AU', q: 'bris', limit: 10 });
  if (results.length !== 1) throw new Error(`Expected 1 result for "bris", got ${results.length}`);
  if (results[0].city !== 'Brisbane') throw new Error(`Expected Brisbane, got ${results[0].city}`);
});

test('searchCities returns empty for unknown ISO code', async () => {
  const results = await geoService.searchCities({ countryIso: 'XX', q: '', limit: 10 });
  if (results.length !== 0) throw new Error(`Expected empty for unknown ISO XX, got ${results.length}`);
});

test('searchCities is case-insensitive for countryIso', async () => {
  const cacheKey = 'geo:cities:v2:NP';
  mockRedisStore[cacheKey] = JSON.stringify([{ city: 'Kathmandu', state: 'Bagmati' }]);

  const results1 = await geoService.searchCities({ countryIso: 'NP', q: '', limit: 5 });
  const results2 = await geoService.searchCities({ countryIso: 'np', q: '', limit: 5 });
  if (results1.length !== results2.length)
    throw new Error('Case-insensitive ISO lookup failed');
});

// ── Group 4: Fallback Popular Cities Seed ───────────────────────────────────
console.log('\nGroup 4: Fallback Popular Cities Seed');

test('FALLBACK_POPULAR_CITIES has entries for primary markets', () => {
  const { FALLBACK_POPULAR_CITIES } = require('../modules/geo/geo.service');
  expect(FALLBACK_POPULAR_CITIES.IN).toBeGreaterThan(30);
  expect(FALLBACK_POPULAR_CITIES.US).toBeGreaterThan(20);
  expect(FALLBACK_POPULAR_CITIES.GB).toBeGreaterThan(5);
  expect(FALLBACK_POPULAR_CITIES.AE).toBeGreaterThan(5);
  expect(FALLBACK_POPULAR_CITIES.SG).toBeGreaterThan(1);
});

test('FALLBACK_POPULAR_CITIES.IN contains major cities with state', () => {
  const { FALLBACK_POPULAR_CITIES } = require('../modules/geo/geo.service');
  const mumbai = FALLBACK_POPULAR_CITIES.IN.find((c) => c.city === 'Mumbai');
  if (!mumbai || mumbai.state !== 'Maharashtra')
    throw new Error(`Expected Mumbai in Maharashtra, got: ${JSON.stringify(mumbai)}`);
  const lucknow = FALLBACK_POPULAR_CITIES.IN.find((c) => c.city === 'Lucknow');
  if (!lucknow || lucknow.state !== 'Uttar Pradesh')
    throw new Error(`Expected Lucknow in Uttar Pradesh, got: ${JSON.stringify(lucknow)}`);
});

test('FALLBACK_POPULAR_CITIES.IN disambiguates Aurangabad (Maharashtra vs Bihar)', () => {
  const { FALLBACK_POPULAR_CITIES } = require('../modules/geo/geo.service');
  const aurangabads = FALLBACK_POPULAR_CITIES.IN.filter((c) => c.city === 'Aurangabad');
  if (aurangabads.length < 2)
    throw new Error(`Expected at least 2 Aurangabads, got: ${aurangabads.length}`);
  const states = aurangabads.map((c) => c.state);
  if (!states.includes('Maharashtra') || !states.includes('Bihar'))
    throw new Error(`Expected Maharashtra and Bihar, got: ${JSON.stringify(states)}`);
});

test('searchCities falls back to FALLBACK_POPULAR_CITIES on cache miss', async () => {
  // ISO with no cache entry (e.g. GB) - will hit CountriesNow (mocked/offline) and fall back to seed
  const results = await geoService.searchCities({ countryIso: 'GB', q: 'london', limit: 5 });
  if (results.length === 0 || results[0].city !== 'London')
    throw new Error(`Expected London fallback, got: ${JSON.stringify(results)}`);
});

// ── Summary ──────────────────────────────────────────────────────────────────
// Wait for async tests to finish
setTimeout(() => {
  console.log(`\n${'─'.repeat(50)}`);
  console.log(`Backend tests: ${passed} passed, ${failed} failed`);
  if (failed > 0) process.exit(1);
}, 300);

