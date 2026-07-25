const fs = require('fs');
const path = require('path');
const https = require('https');

const maleDir = path.join(__dirname, '../assets/avatars/male');
const femaleDir = path.join(__dirname, '../assets/avatars/female');

// Clean existing contents to ensure clean gender separation
if (fs.existsSync(maleDir)) fs.rmSync(maleDir, { recursive: true, force: true });
if (fs.existsSync(femaleDir)) fs.rmSync(femaleDir, { recursive: true, force: true });

fs.mkdirSync(maleDir, { recursive: true });
fs.mkdirSync(femaleDir, { recursive: true });

// Seeds for standard 20 avatars
const maleSeeds = [
  'Alexander', 'Benjamin', 'Christopher', 'Daniel', 'Ethan',
  'Felix', 'Gabriel', 'Henry', 'Julian', 'Leo',
  'Marcus', 'Nicholas', 'Oliver', 'Philip', 'Ryan',
  'Sebastian', 'Thomas', 'Victor', 'William', 'Xavier'
];

const femaleSeeds = [
  'Amelia', 'Bella', 'Charlotte', 'Diana', 'Emma',
  'Fiona', 'Grace', 'Hannah', 'Isabella', 'Julia',
  'Katherine', 'Lily', 'Maya', 'Nora', 'Olivia',
  'Penelope', 'Rose', 'Sophia', 'Victoria', 'Zoe'
];

// Seeds for 10 _new.svg avatars
const newMaleSeeds = [
  'AriaNewMale', 'BraveNewMale', 'CosmoNewMale', 'DuneNewMale', 'EchoNewMale',
  'FalconNewMale', 'GriffinNewMale', 'HawkNewMale', 'IndieNewMale', 'JasperNewMale'
];

const newFemaleSeeds = [
  'AuroraNewFem', 'BlossomNewFem', 'CelesteNewFem', 'DahliaNewFem', 'EdenNewFem',
  'FloraNewFem', 'HazelNewFem', 'IrisNewFem', 'JadeNewFem', 'LunaNewFem'
];

const femaleTops = ['bigHair', 'bob', 'bun', 'curly', 'curvy', 'dreads', 'frida', 'fro', 'froBand', 'longButNotTooLong', 'miaWallace', 'straight1', 'straightAndStrand'];
const maleTops = ['shortHair', 'sides', 'theCaesar', 'theCaesarAndSideburns', 'shortFlat', 'shortRound', 'shortWaved', 'beret', 'turban'];

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

async function generateAll() {
  console.log('Downloading all 30 Male and 30 Female DiceBear Avataaars & Toon Head SVG avatars...');

  // 1. Download 10 New Male Avatars (avatar_male_1_new.svg .. avatar_male_10_new.svg)
  for (let i = 0; i < newMaleSeeds.length; i++) {
    const seed = newMaleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const top = maleTops[i % maleTops.length];
    const url = (style === 'avataaars')
      ? `https://api.dicebear.com/9.x/avataaars/svg?seed=${encodeURIComponent(seed)}&top=${top}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`
      : `https://api.dicebear.com/9.x/toon-head/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_male_${index}_new.svg`;
      fs.writeFileSync(path.join(maleDir, fileName), svg);
      console.log(` Saved ${fileName} in male/ (${style})`);
    } catch (e) {
      console.error(`❌ Failed male new ${index}:`, e.message);
    }
  }

  // 2. Download 20 Standard Male Avatars (avatar_male_1.svg .. avatar_male_20.svg)
  for (let i = 0; i < maleSeeds.length; i++) {
    const seed = maleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const top = maleTops[i % maleTops.length];
    const url = (style === 'avataaars')
      ? `https://api.dicebear.com/9.x/avataaars/svg?seed=${encodeURIComponent(seed)}&top=${top}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`
      : `https://api.dicebear.com/9.x/toon-head/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_male_${index}.svg`;
      fs.writeFileSync(path.join(maleDir, fileName), svg);
      console.log(` Saved ${fileName} in male/ (${style})`);
    } catch (e) {
      console.error(`❌ Failed male ${index}:`, e.message);
    }
  }

  // 3. Download 10 New Female Avatars (avatar_female_1_new.svg .. avatar_female_10_new.svg)
  for (let i = 0; i < newFemaleSeeds.length; i++) {
    const seed = newFemaleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const top = femaleTops[i % femaleTops.length];
    const url = (style === 'avataaars')
      ? `https://api.dicebear.com/9.x/avataaars/svg?seed=${encodeURIComponent(seed)}&top=${top}&facialHairProbability=0&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`
      : `https://api.dicebear.com/9.x/toon-head/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_female_${index}_new.svg`;
      fs.writeFileSync(path.join(femaleDir, fileName), svg);
      console.log(` Saved ${fileName} in female/ (${style})`);
    } catch (e) {
      console.error(`❌ Failed female new ${index}:`, e.message);
    }
  }

  // 4. Download 20 Standard Female Avatars (avatar_female_1.svg .. avatar_female_20.svg)
  for (let i = 0; i < femaleSeeds.length; i++) {
    const seed = femaleSeeds[i];
    const index = i + 1;
    const style = (i % 2 === 0) ? 'avataaars' : 'toon-head';
    const top = femaleTops[i % femaleTops.length];
    const url = (style === 'avataaars')
      ? `https://api.dicebear.com/9.x/avataaars/svg?seed=${encodeURIComponent(seed)}&top=${top}&facialHairProbability=0&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`
      : `https://api.dicebear.com/9.x/toon-head/svg?seed=${encodeURIComponent(seed)}&backgroundColor=b6e3f4,c0aede,d1d4f9,ffd5dc,ffdfbf`;

    try {
      const svg = await fetchSvg(url);
      const fileName = `avatar_female_${index}.svg`;
      fs.writeFileSync(path.join(femaleDir, fileName), svg);
      console.log(` Saved ${fileName} in female/ (${style})`);
    } catch (e) {
      console.error(`❌ Failed female ${index}:`, e.message);
    }
  }

  console.log('✅ Generated ALL 30 male and 30 female SVG avatars into correct directories!');
}

generateAll();
