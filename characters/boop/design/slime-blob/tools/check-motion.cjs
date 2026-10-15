// Validate the accepted engine motion without hashing changeable art/material.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
if(process.argv.includes('--help')){console.log('node tools/check-motion.cjs [source-file]\nChecks seven accepted V1 source blocks, defaulting to the packaged engine/motion-v1.mjs.');process.exit(0);}
const contract = JSON.parse(fs.readFileSync(path.join(__dirname, '../contracts/motion-v1.json'), 'utf8'));
const sourcePath = process.argv[2] || path.resolve(__dirname, '../contracts', contract.referenceSource);
const source = fs.readFileSync(sourcePath, 'utf8');
assert.equal(contract.status, 'USER-ACCEPTED MOTION BASELINE');
for (const [name, block] of Object.entries(contract.lockedBlocks)) {
  const start = source.indexOf('// BOOP_MOTION_V1_BEGIN ' + name + '\n');
  const end = source.indexOf('// BOOP_MOTION_V1_END ' + name, start);
  assert.ok(start >= 0 && end > start, 'Missing motion section: ' + name);
  const code = source.slice(start + ('// BOOP_MOTION_V1_BEGIN ' + name + '\n').length, end).trim();
  const digest = crypto.createHash('sha256').update(code).digest('hex');
  assert.equal(digest, block.sha256, 'Accepted motion changed: ' + name + '. Review and name a new motion revision.');
}
console.log(JSON.stringify({status:'ACCEPTED MOTION V1 UNCHANGED',blocks:Object.keys(contract.lockedBlocks).length,source:sourcePath,scope:'Motion only; material, faces, production policy and hardware validation are excluded.'}));
