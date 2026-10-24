// Exports the animation bank's designs for facegen.py, which runs this:
// every design's SVG, made by the bank's own generator
// (characters/pixel/design/boop-sound-bank-v4/runtime/), into DIR/svg/, and
// its catalogue entry, with its voice window, into DIR/designs.json. DIR is
// ignored by git; the bank is the designs' only source.
//
//     node characters/pixel/tools/facegen/bank.mjs --out DIR
import fs from 'node:fs';
import path from 'node:path';

import {catalog} from '../../design/boop-sound-bank-v4/runtime/catalog.mjs';
import {makeScene} from '../../design/boop-sound-bank-v4/runtime/bank.mjs';
import {voiceStart} from '../../design/boop-sound-bank-v4/runtime/mood-art.mjs';

const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--out') {
  console.error('usage: node characters/pixel/tools/facegen/bank.mjs --out DIR');
  process.exit(2);
}
const out = path.resolve(args[1]);
fs.rmSync(path.join(out, 'svg'), {recursive: true, force: true});

// The bank's three kinds of SVG: V2, the first pack (no renderer); V3, the
// older moods' newer states; V4, the new moods' flip-books, and every
// mood's wake_up, comedy, occasions, gestures and notices (comedy-art.mjs,
// occasion-art.mjs, gesture-art.mjs, notice-art.mjs), drawn the same way.
const dialects = {undefined: 'v2', 'state-v3': 'v3', 'mood-v4': 'v4', 'wake-v1': 'v4', 'comedy-v1': 'v4', 'occasion-v1': 'v4', 'gesture-v1': 'v4',
  'notice-v1': 'v4'};

// A design's voice window: when a line over it may start, in ms, by the
// bank's rule (mood-art.mjs voiceStart). The bank's own voiceWindows gives
// it for the new moods' designs; the older ones follow the same rule on
// their own timelines.
function voiceMs(state, score) {
  return Math.round(Number(voiceStart(state, score).toFixed(6)) * 1000);
}

const designs = catalog.map(a => {
  const file = path.join('svg', a.mood, a.state, `${a.id}.svg`);
  fs.mkdirSync(path.join(out, path.dirname(file)), {recursive: true});
  const scene = makeScene(a.id);
  fs.writeFileSync(path.join(out, file), scene.svg);
  return {
    id: a.id, mood: a.mood, state: a.state, variation: a.variation, name: a.name, seconds: a.seconds,
    ...(a.outcome ? {outcome: a.outcome} : {}), ...(a.startContext ? {ctx: a.startContext} : {}),
    ...(a.when ? {when: a.when} : {}), ...(a.after ? {after: a.after} : {}),
    voiceMs: voiceMs(a.state, scene.score), dialect: dialects[a.renderer], svg: file,
  };
});
fs.writeFileSync(path.join(out, 'designs.json'), JSON.stringify(designs, null, 1) + '\n');
console.log(`bank: ${designs.length} designs into ${out}`);
