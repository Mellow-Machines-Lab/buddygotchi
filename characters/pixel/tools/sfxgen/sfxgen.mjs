// Builds Boop's sound effects as C arrays, from the
// animation bank's procedural sounds (characters/pixel/design/boop-sound-bank-v4/):
// its synthesiser and recipes (runtime/audio/, unchanged) and each design's
// timeline, which the bank's makeScene gives in its voice-first mix. The
// designs, in the device's order, are the ones facegen lists
// (characters/pixel/tools/facegen/design/manifest.json), so run facegen first. The
// output, the Pixel pack's characters/pixel/firmware/include/sfx.h, is checked in; rerun this when the bank
// changes:
//
//     node characters/pixel/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]
//
// Each effect the timelines use is rendered once, at the bank's 44.1 kHz,
// then filtered and cut down to 8-bit samples at 11.025 kHz, the voice's
// format. All effects share one scale, so their levels keep the bank's
// balance. The device resamples a clip for an event's pitch
// (firmware/src/voice/effects.cpp).
//
// The mix leaves most of a routine design's contacts out and picks, afresh
// each loop, which few sound, never moving one off its frame. The device
// has no bank to ask, so this bakes the bank's picks (routineEvents, seed
// 53) for loops 0 to 7, and the device plays loop n's as n % 8.
//
// `--wav-dir` also writes every clip as a WAV, for listening.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

import {effects} from '../../design/boop-sound-bank-v4/runtime/audio/effects.mjs';
import {renderRecipe, SAMPLE_RATE} from '../../design/boop-sound-bank-v4/runtime/audio/synth.mjs';
import {makeScene} from '../../design/boop-sound-bank-v4/runtime/bank.mjs';
import {catalog} from '../../design/boop-sound-bank-v4/runtime/catalog.mjs';
import {protectedSoundStates, routineEvents} from '../../design/boop-sound-bank-v4/runtime/quiet-mix.mjs';
import {cycleHasSound} from '../../design/boop-sound-bank-v4/runtime/score.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const bank = path.join(root, 'characters/pixel/design/boop-sound-bank-v4');
const manifestFile = path.join(root, 'characters/pixel/tools/facegen/design/manifest.json');
const out = path.join(root, 'characters/pixel/firmware/include/sfx.h');

const policies = ['silent', 'loop', 'entry', 'sparse'];
const LOOPS = 8;  // the loops of a routine design whose picks are baked
const SEED = 53;  // the bank's default seed for those picks
const RATE = 11025;
const DOWN = SAMPLE_RATE / RATE;  // 4
const PEAK = 0.70;  // the synthesiser's output stage never goes past this
// An event's loudness is its clip's level times its gain. The bank spans
// about 40 dB, and an 8-bit speaker loses the quiet end in its hiss, so
// the square root squeezes the range and keeps the order: the loudest event
// plays as loud as the voice, and the quietest about a tenth as loud.
const SQUEEZE = 0.5;

// A windowed-sinc low-pass just under the new Nyquist, so noise and bells
// don't fold back as whistles when every fourth sample is kept.
function lowpass(x) {
  const taps = 63, mid = (taps - 1) / 2, fc = 0.45 / DOWN;
  const h = [];
  for (let i = 0; i < taps; i++) {
    const n = i - mid;
    const sinc = n === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * n) / (Math.PI * n);
    h.push(sinc * (0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (taps - 1))));
  }
  const y = new Float32Array(Math.ceil(x.length / DOWN));
  for (let j = 0; j < y.length; j++) {
    let acc = 0;
    for (let i = 0; i < taps; i++) {
      const k = j * DOWN + i - mid;
      if (k >= 0 && k < x.length) acc += x[k] * h[i];
    }
    y[j] = acc;
  }
  return y;
}

// A clip at full scale, as the voice's clips are, and how loud it was
// before: the loudness goes into its events' gains instead (below).
function clip(name) {
  const y = lowpass(renderRecipe(effects[name], 1, SAMPLE_RATE));
  const peak = y.reduce((m, v) => Math.max(m, Math.abs(v)), 0) || 1;
  const q = Array.from(y, v => Math.round((v / peak) * 127));
  let end = q.length;
  while (end > 0 && q[end - 1] === 0) end--;  // trailing silence
  return {data: Uint8Array.from(q.slice(0, end), v => 128 + v), level: peak / PEAK};
}

// A design's timeline: its policy, its event lists (one, or LOOPS for a
// routine design whose picks change each loop), whether a line turns it
// down, and its voice window's start.
function timeline(d) {
  const {score} = makeScene(d.id);
  if (score.id !== d.id) throw new Error(`${d.id}: the bank made ${score.id}`);
  if (!policies.includes(score.policy)) throw new Error(`${d.id}: unknown policy ${score.policy}`);
  const routine = Boolean(score.mix?.gestures) && score.policy !== 'silent';
  if (routine && JSON.stringify(routineEvents(score, 0, SEED)) !== JSON.stringify(score.events)) {
    throw new Error(`${d.id}: the mix's first loop isn't its own events`);
  }
  const lists = score.policy === 'silent' ? [[]]
    : routine && score.policy !== 'entry' ? Array.from({length: LOOPS}, (_, n) => routineEvents(score, n, SEED))
    : [score.events];
  // Sparse: the loops that sound, as the bank's player counts them
  // (score.mjs cycleHasSound), must be 0, every, 2 × every…, as the device
  // counts them, for an `every` that fits its uint8_t.
  let every = 1;
  if (score.policy === 'sparse') {
    const sounds = Array.from({length: 256}, (_, n) => cycleHasSound(score, n));
    every = sounds.indexOf(true, 1);
    if (every < 1 || sounds.some((on, n) => on !== (n % every === 0))) {
      throw new Error(`${d.id}: the loops that sound aren't 0, every, 2 × every…`);
    }
  }
  const guarded = protectedSoundStates.includes(d.state);
  // The voice window, as facegen lists it (by the bank's rule, mood-art.mjs
  // voiceStart).
  const voiceMs = d.voiceMs;
  if (!Number.isInteger(voiceMs) || voiceMs < 0 || voiceMs >= 65536) {
    throw new Error(`${d.id}: no voice window in the manifest: run make -C internal faces first`);
  }
  return {id: d.id, policy: score.policy, every, duck: !guarded, voiceMs, lists};
}

function writeWav(file, data) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(RATE, 24); h.writeUInt32LE(RATE, 28); h.writeUInt16LE(1, 32); h.writeUInt16LE(8, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(file, Buffer.concat([h, Buffer.from(data)]));
}

function main() {
  const args = process.argv.slice(2);
  const wavDir = args[0] === '--wav-dir' ? args[1] : null;
  if (args.length && !wavDir) {
    console.error('usage: node characters/pixel/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]');
    process.exit(2);
  }

  const manifest = JSON.parse(fs.readFileSync(manifestFile, 'utf8'));
  const {moods, states, designs} = manifest;
  // The designs must be the bank's, as facegen last listed them, or the
  // sounds wouldn't line up with faces.h.
  const listed = new Map(designs.map(d => [d.id, d]));
  if (listed.size !== catalog.length ||
      catalog.some(a => listed.get(a.id)?.variation !== a.variation || listed.get(a.id)?.seconds !== a.seconds)) {
    throw new Error(`${path.relative(root, manifestFile)} isn't the bank's designs: run make -C internal faces first`);
  }
  const count = (m, s) => designs.filter(d => d.mood === m && d.state === s).length;
  const scores = designs.map(timeline);
  const events = scores.flatMap(s => s.lists.flat());
  const names = [...new Set(events.map(e => e.effect))].sort();
  const made = names.map(clip);
  const clips = made.map(c => c.data);

  const hash = crypto.createHash('sha256');
  const walk = d => fs.readdirSync(d, {withFileTypes: true}).sort((a, b) => a.name < b.name ? -1 : 1)
    .forEach(e => e.isDirectory() ? walk(path.join(d, e.name)) : hash.update(fs.readFileSync(path.join(d, e.name))));
  walk(path.join(bank, 'runtime'));
  hash.update(fs.readFileSync(manifestFile));
  hash.update(fs.readFileSync(fileURLToPath(import.meta.url)));
  const version = hash.digest('hex').slice(0, 12);

  const loud = e => made[names.indexOf(e.effect)].level * (e.gain ?? 1);
  const loudest = Math.max(...events.map(loud));
  // Each list's events, stored once however many loops and designs share them.
  const eventRows = [], spanRows = [], spanOf = new Map();
  const span = list => {
    const evs = list.map(e => ({
      at: Math.round(e.at * 1000), clip: names.indexOf(e.effect),
      gain: Math.max(1, Math.round(255 * Math.pow(loud(e) / loudest, SQUEEZE))), pitch: Math.round((e.pitch ?? 1) * 1000),
    })).sort((a, b) => a.at - b.at || a.clip - b.clip);
    if (evs.length > 255) throw new Error('too many events in a loop');
    const key = JSON.stringify(evs);
    if (!spanOf.has(key)) {
      spanOf.set(key, spanRows.length);
      spanRows.push(`{${eventRows.length}, ${evs.length}}`);
      eventRows.push(...evs.map(e => `{${e.at}, ${e.clip}, ${e.gain}, ${e.pitch}}`));
    }
    return spanOf.get(key);
  };
  const lists = [], scoreRows = [];
  for (const s of scores) {
    const first = lists.length;
    lists.push(...s.lists.map(span));
    scoreRows.push(`{k${s.policy[0].toUpperCase()}${s.policy.slice(1)}, ${s.every}, ${s.duck}, ${s.lists.length}, ` +
      `${first}, ${s.voiceMs}},  // ${s.id}`);
  }
  if (eventRows.length >= 65536 || lists.length >= 65536 || designs.length >= 65536) throw new Error('the tables outgrow their indexes');

  const bytes = clips.reduce((n, c) => n + c.length, 0);
  const L = [];
  L.push(`// Boop's sound effects: 8-bit unsigned samples at 11.025 kHz.`);
  L.push(`// Generated by characters/pixel/tools/sfxgen/sfxgen.mjs from the animation bank's sounds.`);
  L.push(`// Don't edit; rerun the tool. Include from one .cpp only (voice/effects.cpp).`);
  L.push('#pragma once', '#include <cstdint>', '', 'namespace sfx_assets {', '');
  L.push(`constexpr uint32_t kRate = ${RATE};`);
  L.push(`constexpr const char* kVersion = "${version}";`);
  L.push(`constexpr int kClips = ${clips.length};`);
  L.push(`constexpr uint32_t kBytes = ${bytes};`);
  L.push(`constexpr int kMoods = ${moods.length};`, `constexpr int kStates = ${states.length};`);
  L.push(`constexpr int kLoops = ${LOOPS};  // a routine design's baked loops: loop n plays list n % kLoops`, '');
  L.push('// Each mood and state\'s variations, as faces.h has them: kVariants[m][s]', '// scores from kScore[kFirst[m][s]] on.');
  L.push('static const uint8_t kVariants[kMoods][kStates] = {',
    ...moods.map(m => `    {${states.map(s => count(m, s)).join(', ')}},  // ${m}`), '};');
  let at = 0;
  L.push('static const uint16_t kFirst[kMoods][kStates] = {',
    ...moods.map(m => `    {${states.map(s => { const f = at; at += count(m, s); return f; }).join(', ')}},  // ${m}`), '};', '');
  L.push('struct Clip {', '  const char* name;', '  uint32_t at;   // offset into kSamples', '  uint16_t len;  // samples', '};', '');
  L.push('static const Clip kClip[] = {');
  at = 0;
  names.forEach((n, i) => { L.push(`    {"${n}", ${at}, ${clips[i].length}},`); at += clips[i].length; });
  L.push('};', '');
  L.push('// When a design\'s events play: never, every loop, its first loop only, or', '// every `every`th loop from its first.');
  L.push('enum Policy : uint8_t { kSilent, kLoop, kEntry, kSparse };', '');
  L.push('struct Event {', '  uint16_t atMs;   // into the design\'s loop', '  uint8_t clip;',
    '  uint8_t gain;    // 1–255: 255 plays the clip as loud as the voice', '  uint16_t pitch;  // permille: 1000 plays the clip as made', '};', '');
  L.push('// An event list: kEvent[first] on, n of them, by time.', 'struct List {', '  uint16_t first;', '  uint8_t n;', '};', '');
  L.push('struct Score {', '  Policy policy;', '  uint8_t every;     // sparse: the loops that sound are 0, every, 2 × every…',
    '  bool duck;         // a line turns it down: all but needs you\'s, the finish\'s and an error\'s',
    '  uint8_t lists;     // its loops\' event lists: 1, or kLoops for a routine design', '  uint16_t loop0;    // into kLoopList',
    '  uint16_t voiceMs;  // its voice window\'s start: a line over it starts no sooner', '};', '');
  L.push('// Every design\'s timeline, by mood, then state, then variation.');
  L.push('static const Score kScore[] = {', ...scoreRows.map(r => '    ' + r), '};', '');
  L.push('// Each score\'s loops\' lists, `lists` of them from its `loop0`, as indexes', '// into kList, which has each distinct list once.');
  L.push('static const uint16_t kLoopList[] = {');
  for (let i = 0; i < lists.length; i += 16) L.push('    ' + lists.slice(i, i + 16).join(', ') + ',');
  L.push('};', '');
  L.push('static const List kList[] = {');
  for (let i = 0; i < spanRows.length; i += 8) L.push('    ' + spanRows.slice(i, i + 8).join(', ') + ',');
  L.push('};', '');
  L.push('static const Event kEvent[] = {');
  for (let i = 0; i < eventRows.length; i += 6) L.push('    ' + eventRows.slice(i, i + 6).join(', ') + ',');
  L.push('};', '');
  const blob = Buffer.concat(clips.map(c => Buffer.from(c)));
  L.push('static const uint8_t kSamples[] = {');
  for (let i = 0; i < blob.length; i += 32) L.push('    ' + Array.from(blob.subarray(i, i + 32)).join(',') + ',');
  L.push('};', '', '}  // namespace sfx_assets', '');
  fs.writeFileSync(out, L.join('\n'));
  const tables = scoreRows.length * 8 + lists.length * 2 + spanRows.length * 4 + eventRows.length * 6;
  console.log(`sfxgen: ${clips.length} clips, ${(bytes / 1024).toFixed(0)} KB; ${scores.length} timelines, ` +
    `${spanRows.length} event lists, ${eventRows.length} events, ${(tables / 1024).toFixed(0)} KB of tables; version ${version}`);

  if (wavDir) {
    fs.mkdirSync(wavDir, {recursive: true});
    names.forEach((n, i) => writeWav(path.join(wavDir, `${n}.wav`), clips[i]));
  }
}

main();
