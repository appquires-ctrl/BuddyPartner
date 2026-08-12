require('dotenv').config();
const db = require('./db');

function calculateAge(dobStr) {
  const birthDate = new Date(dobStr);
  if (isNaN(birthDate.getTime())) return null;
  const today = new Date();
  let age = today.getFullYear() - birthDate.getFullYear();
  const monthDiff = today.getMonth() - birthDate.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && today.getDate() < birthDate.getDate())) {
    age--;
  }
  return age;
}

function testDobValidation() {
  console.log('🧪 Testing DOB & Age Calculation Logic...');

  const today = new Date();
  
  // 1. Under 18 (17 years and 364 days old)
  const underageDob = new Date(today.getFullYear() - 17, today.getMonth(), today.getDate()).toISOString();
  const ageUnderage = calculateAge(underageDob);
  console.log(`Child DOB (${underageDob}): Age calculated = ${ageUnderage}`);
  if (ageUnderage >= 18) {
    throw new Error('Age calculation allowed 17-year-old as adult!');
  }

  // 2. Exactly 18 today
  const adultDob = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate()).toISOString();
  const ageAdult = calculateAge(adultDob);
  console.log(`Adult DOB (${adultDob}): Age calculated = ${ageAdult}`);
  if (ageAdult < 18) {
    throw new Error('Age calculation blocked 18-year-old adult!');
  }

  // 3. Yesterday 18th birthday
  const yesterday18 = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate() - 1).toISOString();
  const ageYesterday = calculateAge(yesterday18);
  console.log(`Yesterday 18th DOB (${yesterday18}): Age calculated = ${ageYesterday}`);
  if (ageYesterday < 18) {
    throw new Error('Age calculation blocked 18-year-old adult born yesterday!');
  }

  // 4. Tomorrow 18th birthday (17 years 364 days)
  const tomorrow18 = new Date(today.getFullYear() - 18, today.getMonth(), today.getDate() + 1).toISOString();
  const ageTomorrow = calculateAge(tomorrow18);
  console.log(`Tomorrow 18th DOB (${tomorrow18}): Age calculated = ${ageTomorrow}`);
  if (ageTomorrow >= 18) {
    throw new Error('Age calculation allowed person who turns 18 tomorrow!');
  }

  console.log('🎉 All DOB & 18+ Age Validation Tests Passed Successfully!');
  process.exit(0);
}

testDobValidation();
