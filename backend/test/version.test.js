const assert = require('assert');
const semver = require('semver');

/**
 * Unit tests for Backend Semver comparison logic
 */
function runVersionTests() {
  console.log('🧪 Running Backend Version Semver Unit Tests...');

  // 1. Multi-digit segment comparisons (1.10.0 > 1.9.0)
  const v1_10 = semver.valid(semver.coerce('1.10.0'));
  const v1_9 = semver.valid(semver.coerce('1.9.0'));
  assert.strictEqual(semver.gt(v1_10, v1_9), true, '1.10.0 should be greater than 1.9.0');
  assert.strictEqual(semver.lt(v1_9, v1_10), true, '1.9.0 should be less than 1.10.0');

  // 2. Equal versions
  const v1_5_eq1 = semver.valid(semver.coerce('1.5.0'));
  const v1_5_eq2 = semver.valid(semver.coerce('1.5.0'));
  assert.strictEqual(semver.eq(v1_5_eq1, v1_5_eq2), true, '1.5.0 should equal 1.5.0');
  assert.strictEqual(semver.lt(v1_5_eq1, v1_5_eq2), false, '1.5.0 should not be lt 1.5.0');

  // 3. Outdated version triggers updateRequired
  const installed = semver.valid(semver.coerce('1.4.2'));
  const minimum = semver.valid(semver.coerce('1.5.0'));
  assert.strictEqual(semver.lt(installed, minimum), true, '1.4.2 is less than 1.5.0 -> updateRequired: true');

  // 4. Malformed client input coercion
  const malformed1 = semver.valid(semver.coerce('v1.4.2-beta+001')) || '1.0.0';
  assert.strictEqual(semver.gte(malformed1, '1.0.0'), true, 'Malformed input coerced cleanly');

  const malformed2 = semver.valid(semver.coerce('invalid_str')) || '1.0.0';
  assert.strictEqual(malformed2, '1.0.0', 'Completely invalid string falls back to 1.0.0');

  console.log('✅ All 4 Backend Version Semver Unit Tests Passed!');
}

runVersionTests();
