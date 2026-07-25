const fs = require('fs');
const path = require('path');
const https = require('https');

const maleDir = path.join(__dirname, '../assets/avatars/male');
const femaleDir = path.join(__dirname, '../assets/avatars/female');

fs.mkdirSync(maleDir, { recursive: true });
fs.mkdirSync(femaleDir, { recursive: true });

const newMaleSeeds = [
  'AriaNewMale', 'BraveNewMale', 'CosmoNewMale', 'DuneNewMale', 'EchoNewMale',
  'FalconNewMale', 'GriffinNewMale', 'HawkNewMale', 'IndieNewMale', 'JasperNewMale'
];

const newFemaleSeeds = [
  'AuroraNewFem', 'BlossomNewFem', 'CelesteNewFem', 'DahliaNewFem', 'EdenNewFem',
  'FloraNewFem', 'HazelNewFem', 'IrisNewFem', 'JadeNewFem', 'LunaNewFem'
];

function fetchSvg(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode !== 200) {
        reject(new Error(`Failed to download: ${res.statusCode} ${res.statusMessage}`));
        return;
      }
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(data));
    }).on('error', err => reject(err));
  });
}

async function generateNew() {
  console.log('Downloading 10 new Male and 10 new Female DiceBear Avataaars & Toon Head avatars ending with _new.svg...');

  // 10 New Male Avatars ending with _new.svg
  for (let i = 0; i < newMaleSeeds.length; i++) {
    const seed = newMaleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const url = `https://api.dicebear.com/9.x/${style}/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_male_${index}_new.svg`;
      fs.writeFileSync(path.join(maleDir, fileName), svg);
      console.log(` Saved ${fileName} (${style} - ${seed})`);
    } catch (e) {
      console.error(`❌ Failed male ${index}:`, e.message);
    }
  }

  // 10 New Female Avatars ending with _new.svg
  for (let i = 0; i < newFemaleSeeds.length; i++) {
    const seed = newFemaleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const url = `https://api.dicebear.com/9.x/${style}/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_female_${index}_new.svg`;
      fs.writeFileSync(path.join(femaleDir, fileName), svg);
      console.log(` Saved ${fileName} (${style} - ${seed})`);
    } catch (e) {
      console.error(`❌ Failed female ${index}:`, e.message);
    }
  }

  console.log('✅ Generated 10 new male and 10 new female SVG avatars ending with _new.svg successfully!');
}

generateNew();
