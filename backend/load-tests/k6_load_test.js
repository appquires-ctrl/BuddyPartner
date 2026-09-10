import http from 'k6/http';
import { check, sleep } from 'k6';

// k6 Load Test Script for BuddyPartner Backend
// Run with: k6 run load-tests/k6_load_test.js

export const options = {
  stages: [
    { duration: '30s', target: 100 },   // Warm up to 100 virtual users
    { duration: '1m', target: 500 },    // Ramp up to 500 virtual users
    { duration: '1m', target: 1000 },   // Peak load: 1,000 virtual users
    { duration: '30s', target: 2500 },  // Stress test: 2,500 virtual users
    { duration: '30s', target: 0 },     // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<300'],   // 95% of requests should complete within 300ms
    http_req_failed: ['rate<0.01'],     // Less than 1% errors
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
let authToken = null;

export function setup() {
  // Obtain JWT token using demo reviewer account
  const res = http.post(
    `${BASE_URL}/api/auth/otp/verify`,
    JSON.stringify({
      country_code: '91',
      mobile: '9999999999',
      otp: '123456',
    }),
    { headers: { 'Content-Type': 'application/json' } }
  );

  const body = JSON.parse(res.body);
  return { token: body.token };
}

export default function (data) {
  const params = {
    headers: {
      Authorization: `Bearer ${data.token}`,
      'Content-Type': 'application/json',
    },
  };

  // 1. Fetch user matches
  const matchesRes = http.get(`${BASE_URL}/api/calls/matches`, params);
  check(matchesRes, {
    'matches status is 200': (r) => r.status === 200,
  });

  // 2. Fetch call history
  const historyRes = http.get(`${BASE_URL}/api/calls/history?limit=20`, params);
  check(historyRes, {
    'history status is 200': (r) => r.status === 200,
  });

  // 3. Fetch wallet balance
  const balanceRes = http.get(`${BASE_URL}/api/wallet/balance`, params);
  check(balanceRes, {
    'balance status is 200': (r) => r.status === 200,
  });

  sleep(1);
}
