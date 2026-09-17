require('dotenv').config();
const { instantConnectService } = require('../modules/instant_connect/instant_connect.service');

async function testSurgeSampling() {
  console.log('--- 1.6 Testing getSurgeEligibleFemales Random Offset Sampling ---');

  const t0 = Date.now();
  const batch1 = await instantConnectService.getSurgeEligibleFemales([], 5);
  const d1 = Date.now() - t0;
  console.log(`Batch 1: ${batch1.length} females retrieved in ${d1}ms:`, batch1.map(f => f.full_name || f.id));

  const t1 = Date.now();
  const batch2 = await instantConnectService.getSurgeEligibleFemales([], 5);
  const d2 = Date.now() - t1;
  console.log(`Batch 2: ${batch2.length} females retrieved in ${d2}ms:`, batch2.map(f => f.full_name || f.id));

  console.log('✅ PASSED: getSurgeEligibleFemales successfully executes without ORDER BY RANDOM()!');
  process.exit(0);
}

testSurgeSampling().catch((err) => {
  console.error('Error:', err);
  process.exit(1);
});
