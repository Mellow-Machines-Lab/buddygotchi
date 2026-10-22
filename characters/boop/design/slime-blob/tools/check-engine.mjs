#!/usr/bin/env node
// Phase 1 reference-engine checks. These do not claim state-scene, graph-edge,
// synchronized audio, firmware, or hardware coverage.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { root, STEP_MS, TRACE_DECIMALS, readScript, loadCatalog, loadEngine,
  applyEvent, runScript, serializeTrace, flatten } from './trace.mjs';
import { createSmoothness } from './smooth.mjs';

const SPEC = 'CONTINUITY.md';
const eps = 1e-12;
const read = name => JSON.parse(fs.readFileSync(path.join(root, name), 'utf8'));
function near(actual, expected, message) {
  assert.ok(Math.abs(actual - expected) <= eps, `${message}: ${actual} != ${expected}`);
}
function range(actual, low, high, message) {
  assert.ok(Number.isFinite(actual) && actual >= low - eps && actual <= high + eps,
    `${message}: ${actual} outside [${low}, ${high}]`);
}
function physical(state) {
  return structuredClone({ modes: state.modes, actorChannels: state.actorChannels,
    activityChannels: state.activityChannels, bridgeChannels: state.bridgeChannels,
    pull: state.grab.pull, pose: state.pose, life: state.life });
}
function walk(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? walk(path.join(directory, entry.name)) : [path.join(directory, entry.name)]);
}
function checkPureSource() {
  // CONTINUITY.md, "Proposed layer ownership": the host injects time and the
  // per-actor seed. Browser APIs belong to renderer/UI modules only.
  const forbidden = /\b(?:document|window|requestAnimationFrame|setTimeout|setInterval)\s*(?:\.|\()|\bperformance\s*\.\s*(?:now|timeOrigin|getEntries)\b|\b(?:Date\s*\.|new\s+Date\b)|\bMath\s*\.\s*random\s*\(/;
  for (const file of walk(path.join(root, 'engine')).filter(file => file.endsWith('.mjs'))) {
    const source = fs.readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, '');
    assert.ok(!forbidden.test(source), `${SPEC}, Proposed layer ownership: impure dependency in ${path.basename(file)}`);
    for (const match of source.matchAll(/\bfrom\s*['"]([^'"]+)['"]/g)) {
      const resolved = path.resolve(path.dirname(file), match[1]);
      assert.ok(match[1].startsWith('.') && resolved.startsWith(path.join(root, 'engine') + path.sep),
        `${SPEC}, Proposed layer ownership: engine import leaves pure engine: ${match[1]}`);
    }
  }
}

// The locked V1 integration of one free mode over one frame, written as the
// contract's equation, then clamped to its bounds.
function freeModeStep({ x, v }, { frequency, damping }, dt, motion) {
  let left = dt;
  while (left > 0) { const h = Math.min(left, 1 / 240); v += (-frequency * frequency * x - damping * v) * h; x += v * h; left -= h; }
  const [low, high] = motion.physics.bounds.displacement, [slow, fast] = motion.physics.bounds.velocity;
  return { x: Math.min(high, Math.max(low, x)), v: Math.min(fast, Math.max(slow, v)) };
}

function checkTraceNumber(value, inspection, at, before, motion) {
  flatten(value); // Every scalar must be finite/serializable.
  for (const [name, mode] of Object.entries(value.modes)) {
    range(mode.x, ...motion.physics.bounds.displacement, `${SPEC}, Keep the object; change its targets: ${name}.x at ${at}`);
    range(mode.v, ...motion.physics.bounds.velocity, `${SPEC}, Keep the object; change its targets: ${name}.v at ${at}`);
    // Keep the object; change its targets: a body mode moves only by its own
    // spring from the state just before this frame (an admitted impulse
    // changes velocity there, never position). No frame may teleport it.
    if (before) {
      const expected = freeModeStep(before.modes[name], motion.physics.modes[name], at ? STEP_MS / 1000 : 0, motion);
      near(mode.x, expected.x, `${SPEC}, Keep the object; change its targets: ${name}.x follows its spring at ${at}`);
      near(mode.v, expected.v, `${SPEC}, Keep the object; change its targets: ${name}.v follows its spring at ${at}`);
    }
  }
  range(value.blink, 0, 1, `${SPEC}, Keep the object; change its targets: blink`);
  range(value.gaze, -motion.physics.gaze.amplitude / 2, motion.physics.gaze.amplitude / 2,
    `${SPEC}, Keep the object; change its targets: gaze`);
  // CONTINUITY.md, "Phase 1 channel bounds": original additive audition
  // layers retain their limits; these are not new physics tuning values.
  // A gag's own channels (CONTINUITY.md, Comedy): the slide and the lids.
  for (const [name, channel] of Object.entries(value.actorChannels)) {
    const cap = { lift: 0.24, roll: 0.12, forward: 0.18, slide: 0.7, lids: 1 }[name] ?? 0.42;
    const speed = { lids: 20 }[name] ?? 5;
    range(channel.x, -cap, cap, `${SPEC}, Phase 1 channel bounds: ${name} displacement`);
    range(channel.v, -speed, speed, `${SPEC}, Phase 1 channel bounds: ${name} velocity`);
  }
  if ('slide' in value) range(value.slide, -0.7, 0.7, `${SPEC}, Comedy: composed slide`);
  range(value.face.blink, 0, 1, `${SPEC}, Comedy: a gag's lids close the eyes no further than a blink`);
  for (const [name, channel] of Object.entries(value.bridgeChannels ?? {})) {
    const cap = { lean: 0.06, squash: 0.05, forward: 0.04 }[name];
    range(channel.x, -cap, cap, `${SPEC}, Directed edge bridges: ${name} displacement`);
    range(channel.v, -1, 1, `${SPEC}, Directed edge bridges: ${name} velocity`);
  }
  for (const spring of inspection.grab.pull) {
    range(spring.x, -0.72, 0.72, `${SPEC}, Phase 1 channel bounds: drag displacement`);
    range(spring.v, -6, 6, `${SPEC}, Phase 1 channel bounds: drag velocity`);
  }
  range(Math.hypot(...value.grab.target), 0, 0.64, `${SPEC}, Phase 1 channel bounds: drag target length`);
  const poseBounds = value.scene ? [1.25, 1.32, 1.14, 0.72]
    : [0.72 + 0.42 + 0.026, 0.72 + 0.42 + 0.1 + 0.011, 0.72 + 0.42, 0.72];
  for (const [i, limit] of poseBounds.entries()) {
    range(value.pose[i], -limit, limit, `${SPEC}, Phase 1 channel bounds: composed pose ${i}`);
  }
  range(value.life[0], 0, 0.24, `${SPEC}, Phase 1 channel bounds: lift`);
  range(value.life[1], -0.12, 0.12, `${SPEC}, Phase 1 channel bounds: roll`);
  range(value.life[2], value.scene ? -0.23 : -0.18, value.scene ? 0.23 : 0.18, `${SPEC}, Phase 1 channel bounds: composed forward`);
}

async function checkSemanticFace(catalog) {
  const { createFace, faceTarget, faceTransition } = await import('../engine/face.mjs');
  // CONTINUITY.md, "Phase 1 channel bounds": the new semantic layer owns
  // these values; accepted spring/blink source remains byte-for-byte locked.
  assert.deepEqual(faceTransition, { durationSeconds: 0.18, frequency: 20, reducedFrequency: 30 },
    `${SPEC}, Phase 1 channel bounds: semantic face timing`);
  const profiles = catalog.expressions, ids = Object.keys(profiles);
  const presentation = face => { const { transition, ...rendered } = face; return rendered; };
  for (const [i, from] of ids.entries()) {
    const to = ids[(i + 1) % ids.length], start = faceTarget(profiles[from]), target = faceTarget(profiles[to]);
    const face = createFace({ profiles, initialEmotion: from, reduced: { matches: false } });
    const before = face.inspect();
    face.setMood(to);
    assert.deepEqual(presentation(face.inspect()), presentation(before), `${SPEC}, Proposed layer ownership: semantic face retarget preserves current controls`);
    let oldArt = from, artChanges = 0;
    for (let frame = 0; frame < 24; frame++) {
      face.advance(STEP_MS / 1000);
      const value = face.inspect();
      assert.ok([from, to].includes(value.artId), `${SPEC}, Proposed layer ownership: only one endpoint art primitive`);
      assert.equal(typeof value.art.eyes, 'string', `${SPEC}, Proposed layer ownership: one eye primitive`);
      assert.equal(typeof value.art.mouth, 'string', `${SPEC}, Proposed layer ownership: one mouth primitive`);
      assert.ok(!('weights' in value), `${SPEC}, Proposed layer ownership: no overlapping silhouette weights`);
      for (const key of Object.keys(start)) {
        range(value[key], Math.min(start[key], target[key]), Math.max(start[key], target[key]),
          `${SPEC}, Proposed layer ownership: convex semantic ${key} (${from} -> ${to})`);
      }
      for (const key of ['cheekAlpha', 'tearAmount', 'bridgeBlink', 'blink']) {
        range(value[key], 0, 1, `${SPEC}, Phase 1 channel bounds: ${key}`);
      }
      if (value.artId !== oldArt) {
        near(value.bridgeBlink, 1, `${SPEC}, Proposed layer ownership: discrete primitive changes only at full closure`);
        artChanges++; oldArt = value.artId;
      }
    }
    assert.equal(artChanges, 1, `${SPEC}, Proposed layer ownership: no double-faced frame`);
    near(face.inspect().bridgeBlink, 0, `${SPEC}, Phase 1 channel bounds: bridge ends after 180 ms`);
  }
  for (const reducedMotion of [false, true]) {
    const face = createFace({ profiles, initialEmotion: 'calm', reduced: { matches: reducedMotion } });
    const before = face.inspect(), target = faceTarget(profiles.frightened);
    face.setMood('frightened'); face.advance(STEP_MS / 1000);
    // Phase 1 channel bounds: a critically damped spring, 1/240 s substeps.
    const frequency = reducedMotion ? 30 : 20;
    const spring = (x, v, goal) => {
      let left = STEP_MS / 1000;
      while (left > 0) { const h = Math.min(left, 1 / 240); v += (frequency * frequency * (goal - x) - 2 * frequency * v) * h; x += v * h; left -= h; }
      return { x, v };
    };
    const first = spring(before.eyeOpen, 0, target.eyeOpen);
    near(face.inspect().eyeOpen, first.x, `${SPEC}, Phase 1 channel bounds: semantic spring frequency and damping`);
    near(face.inspect().velocity.eyeOpen, first.v, `${SPEC}, Phase 1 channel bounds: semantic spring velocity`);
    face.advance(STEP_MS / 1000);
    const interrupted = face.inspect();
    face.setMood('happy');
    assert.deepEqual(presentation(face.inspect()), presentation(interrupted), `${SPEC}, Proposed layer ownership: mid-bridge retarget does not reset controls`);
    // A retarget keeps each control's velocity: the next frame continues the
    // motion rather than starting again from rest.
    assert.ok(Math.abs(interrupted.velocity.eyeOpen) > 0.01, `${SPEC}, Phase 1 channel bounds: the face is moving when retargeted`);
    const next = spring(interrupted.eyeOpen, interrupted.velocity.eyeOpen, faceTarget(profiles.happy).eyeOpen);
    face.advance(STEP_MS / 1000);
    near(face.inspect().eyeOpen, next.x, `${SPEC}, Phase 1 channel bounds: a mid-bridge retarget keeps its velocity`);
  }
}

function checkDragAndPause(createSlime, catalog) {
  // CONTINUITY.md, "Phase 1 channel bounds" and "Alerts, taps and
  // interruption": inputs retarget bounded pull; release retains momentum.
  for (const reducedMotion of [false, true]) {
    const slime = createSlime({ catalog, seed: 53, reducedMotion });
    slime.step(0); slime.dragStart([2, -2]);
    assert.deepEqual(slime.inspect().grab.point, [1, -1], `${SPEC}, Phase 1 channel bounds: normalized drag point clamp`);
    slime.dragMove([4, -3, 2]);
    near(Math.hypot(...slime.inspect().grab.target), 0.64 * (reducedMotion ? 0.35 : 1),
      `${SPEC}, Phase 1 channel bounds: drag target and reduced motion scaling`);
    for (let at = STEP_MS; at <= 320; at += STEP_MS) slime.step(at);
    const held = physical(slime.inspect());
    slime.dragEnd();
    assert.deepEqual(physical(slime.inspect()), held, `${SPEC}, Alerts, taps and interruption: release keeps momentum`);
    assert.deepEqual(slime.inspect().grab.target, [0, 0, 0], `${SPEC}, Alerts, taps and interruption: release removes target`);
    range(slime.inspect().nextPerformance, slime.inspect().time + 3, Infinity,
      `${SPEC}, Phase 1 channel bounds: acting waits at least 3 seconds after release`);
    for (const [i, setter] of ['setPaused', 'setHidden'].entries()) {
      const before = physical(slime.inspect()), time = slime.inspect().time;
      slime[setter](true); slime.step(336 + i * STEP_MS);
      assert.deepEqual(physical(slime.inspect()), before, `${SPEC}, Proposed layer ownership: ${setter} preserves springs`);
      near(slime.inspect().time, time, `${SPEC}, Proposed layer ownership: ${setter} suspends presentation time`);
      slime[setter](false);
    }
  }
  const slime = createSlime({ catalog, seed: 53 });
  slime.step(0);
  near(slime.inspect().nextPerformance, 1, `${SPEC}, Phase 1 channel bounds: original initial recipe delay`);
  let previous;
  for (let i = 0; i < 30; i++) {
    slime.perform();
    const state = slime.inspect();
    assert.notEqual(state.performance.index, previous, `${SPEC}, Variability, without chaos: auto recipe does not immediately repeat`);
    range(state.nextPerformance - state.time - state.performance.duration, 7, 15,
      `${SPEC}, Phase 1 channel bounds: original quiet automatic recipe interval`);
    previous = state.performance.index;
  }
  slime.setMood('happy');
  near(slime.inspect().nextPerformance - slime.inspect().time, 0.4,
    `${SPEC}, Phase 1 channel bounds: retarget delays the next recipe`);
}

async function checkExtensionEquations(createSlime, catalog) {
  // CONTINUITY.md, "Phase 1 channel bounds": isolate a single unit impulse
  // from authored recipes to pin each imported spring coefficient and the
  // substep limit without a rendered-scene or timing assertion.
  const { createActing } = await import('../engine/acting.mjs');
  const names = ['lean', 'squash', 'ripple', 'lift', 'roll', 'forward'];
  const recipe = { duration: 1, label: 'coefficient fixture', type: 'fixture', cues: names.map(name => [0, name, 1]) };
  const profiles = { calm: { performances: [recipe, recipe, recipe] } };
  function springStep({ x, v }, duration, acceleration) {
    let left = duration;
    while (left > 0) {
      const h = Math.min(left, 1 / 240);
      v += acceleration(x, v) * h;
      x += v * h;
      left -= h;
    }
    return { x, v };
  }
  for (const reducedMotion of [false, true]) {
    const acting = createActing({ profiles, rand: () => 0.5, reduced: { matches: reducedMotion }, initialEmotion: 'calm' });
    acting.perform(0, 0);
    acting.advance(0, 0, true);
    const velocity = reducedMotion ? 0.18 : 1;
    for (const name of names) near(acting.channels[name].v, velocity,
      `${SPEC}, Phase 1 channel bounds: gesture impulse reduced to 18%`);
    acting.advance(STEP_MS / 1000, STEP_MS / 1000, true);
    for (const name of names) {
      const frequency = name === 'lift' ? 11 : name === 'roll' ? 10 : 9;
      const expected = springStep({ x: 0, v: velocity }, STEP_MS / 1000,
        (x, v) => -frequency * frequency * x - 6.4 * v);
      near(acting.channels[name].x, expected.x, `${SPEC}, Phase 1 channel bounds: ${name} frequency/damping/substep displacement`);
      near(acting.channels[name].v, expected.v, `${SPEC}, Phase 1 channel bounds: ${name} frequency/damping/substep velocity`);
    }
  }
  // Phase 1 channel bounds: mood posture weights are critically damped
  // springs. Proud squashes 0.05 and calm none, so one frame's posture is
  // 0.05 times one frame of a unit spring from rest.
  const { postureFilter } = await import('../engine/compose.mjs');
  assert.deepEqual(postureFilter, { frequency: 10, reducedFrequency: 25 }, `${SPEC}, Phase 1 channel bounds: mood posture filter`);
  for (const reducedMotion of [false, true]) {
    const posed = createSlime({ catalog, seed: 53, reducedMotion });
    posed.step(0); posed.setMood('proud'); posed.step(STEP_MS);
    const frequency = reducedMotion ? 25 : 10;
    const unit = springStep({ x: 0, v: 0 }, STEP_MS / 1000, (x, v) => frequency * frequency * (1 - x) - 2 * frequency * v);
    near(posed.inspect().posture[1], 0.05 * unit.x, `${SPEC}, Phase 1 channel bounds: mood posture starts from rest`);
  }
  // Directed edge bridges: drawn ratios saturate smoothly inside (0.75, 4/3).
  const { softRatio, faceRender } = await import('../engine/face.mjs');
  assert.deepEqual(faceRender, { ratioLow: 0.75, ratioHigh: 4 / 3, mouthDot: 0.8 }, `${SPEC}, Directed edge bridges: drawn ratio bounds`);
  near(softRatio(1), 1, `${SPEC}, Directed edge bridges: a settled face is drawn at its authored size`);
  range((softRatio(1 + 1e-7) - softRatio(1 - 1e-7)) / 2e-7, 1 - 1e-5, 1 + 1e-5, `${SPEC}, Directed edge bridges: unit slope at rest`);
  for (let value = 0; value <= 12; value += 0.01) {
    range(softRatio(value), 0.75, 4 / 3, `${SPEC}, Directed edge bridges: ratio ${value} saturates`);
    assert.ok(softRatio(value + 0.01) > softRatio(value), `${SPEC}, Directed edge bridges: saturation is monotonic`);
  }
  const slime = createSlime({ catalog, seed: 53 });
  slime.step(0); slime.dragStart(); slime.dragMove([0.2, 0, 0]); slime.step(STEP_MS);
  const expected = springStep({ x: 0, v: 0 }, STEP_MS / 1000, (x, v) => 256 * (0.2 - x) - 8 * v);
  near(slime.inspect().grab.pull[0].x, expected.x, `${SPEC}, Phase 1 channel bounds: grab stiffness/damping/substep displacement`);
  near(slime.inspect().grab.pull[0].v, expected.v, `${SPEC}, Phase 1 channel bounds: grab stiffness/damping/substep velocity`);
}

function checkLockedMagnitudes(createSlime, catalog, motion) {
  // CONTINUITY.md, "Keep the object; change its targets": magnitudes are
  // specified once in the hash-locked V1 contract. No extraction retuning.
  for (const reducedMotion of [false, true]) {
    const scale = reducedMotion ? motion.physics.reducedMotionImpulseMultiplier : 1;
    for (const [kind, x] of [['poke', -1], ['poke', 1], ['shake', 0]]) {
      const slime = createSlime({ seed: 53, catalog, reducedMotion });
      slime.step(0);
      const before = slime.inspect();
      if (kind === 'poke') slime.poke(x, 2); else slime.shake();
      const after = slime.inspect();
      assert.equal(after.mood, before.mood, `${SPEC}, Alerts, taps and interruption: input must never choose mood`);
      const target = kind === 'poke'
        ? [motion.physics.poke.leanVelocityBySide[x < 0 ? 0 : 1], motion.physics.poke.squashVelocity,
          motion.physics.poke.rippleVelocity, motion.physics.poke.dentVelocity]
        : [motion.physics.shake.leanVelocity, motion.physics.shake.squashVelocity,
          motion.physics.shake.rippleVelocity, motion.physics.shake.dentVelocity];
      for (const [i, name] of ['lean', 'squash', 'ripple', 'dent'].entries()) {
        near(after.modes[name].x, before.modes[name].x, `${SPEC}, Alerts, taps and interruption: ${kind} keeps position`);
        near(after.modes[name].v - before.modes[name].v, target[i] * scale,
          `${SPEC}, Keep the object; change its targets: ${kind}/${name} magnitude`);
      }
      if (kind === 'poke') {
        near(after.contact.x, x < 0 ? motion.physics.contactBounds.x[0] : motion.physics.contactBounds.x[1],
          `${SPEC}, Keep the object; change its targets: contact x clamp`);
        near(after.contact.y, motion.physics.contactBounds.y[1], `${SPEC}, Keep the object; change its targets: contact y clamp`);
      }
      for (let i = 0; i < 100; i++) slime.poke(x, -2);
      const burst = slime.inspect();
      for (const mode of Object.values(burst.modes)) {
        range(mode.v, ...motion.physics.bounds.impulseVelocity, `${SPEC}, Keep the object; change its targets: impulse cap`);
      }
      near(burst.contact.y, motion.physics.contactBounds.y[0], `${SPEC}, Keep the object; change its targets: lower contact y clamp`);
    }
  }
}

function checkClock(createSlime, catalog, motion) {
  // CONTINUITY.md, "Proposed layer ownership": one monotonic injected clock,
  // with the accepted V1 frame delta cap and no elapsed time in target setters.
  const slime = createSlime({ seed: 53, catalog });
  near(slime.step(1000).channels.time, 0, `${SPEC}, Headless reference traces: first step establishes origin`);
  near(slime.step(1016).channels.time, STEP_MS / 1000, `${SPEC}, Headless reference traces: 16 ms cadence`);
  near(slime.step(2016).channels.time, STEP_MS / 1000 + motion.physics.bounds.maximumFrameDeltaSeconds,
    `${SPEC}, Keep the object; change its targets: maximum frame delta`);
  const same = slime.step(2016).channels;
  near(same.time, STEP_MS / 1000 + motion.physics.bounds.maximumFrameDeltaSeconds,
    `${SPEC}, Proposed layer ownership: repeated time does not advance clock`);
  for (const time of [2015, -1, NaN, Infinity]) {
    assert.throws(() => slime.step(time), RangeError, `${SPEC}, Proposed layer ownership: invalid/backward time rejected`);
  }
}

function checkIndependentActors(createSlime, catalog, script) {
  // CONTINUITY.md, "Variability, without chaos": other actors' use of random
  // numbers must not perturb a seed's trace, even under interleaved stepping.
  const expected = runScript(createSlime, catalog, script, 53);
  const first = createSlime({ seed: 53, catalog }), second = createSlime({ seed: 8128, catalog });
  const actual = [];
  let cursor = 0;
  for (let at = 0; at <= script.durationMs; at += STEP_MS) {
    second.setMood(Object.keys(catalog.expressions)[(at / STEP_MS) % Object.keys(catalog.expressions).length]);
    second.poke(Math.sin(at), 0.2);
    second.step(at);
    while (cursor < script.events.length && script.events[cursor].at <= at) applyEvent(first, script.events[cursor++]);
    actual.push(structuredClone(first.step(at).channels));
  }
  assert.deepEqual(actual, expected.frames, `${SPEC}, Variability, without chaos: per-actor random state`);
  const different = runScript(createSlime, catalog, script, 54);
  assert.notDeepEqual(different.frames, expected.frames, `${SPEC}, Variability, without chaos: seed affects choreography`);
}

export async function checkEngine() {
  checkPureSource();
  const createSlime = await loadEngine(), catalog = loadCatalog(), motion = read('contracts/motion-v1.json');
  const scriptFiles = fs.readdirSync(path.join(root, 'scripts')).filter(file => file.endsWith('.jsonl')).sort();
  const baselineScripts = ['drag-release.jsonl', 'facts-mid-gesture.jsonl', 'idle-60s.jsonl', 'mood-mid-gesture.jsonl', 'poke-burst.jsonl'];
  for (const file of baselineScripts) assert.ok(scriptFiles.includes(file), `${SPEC}, Headless reference traces: retain Phase 1 ${file}`);
  assert.equal(STEP_MS, 16, `${SPEC}, Headless reference traces: fixed cadence`);
  assert.equal(TRACE_DECIMALS, 6, `${SPEC}, Headless reference traces: fixed serialization precision`);
  const originalRandom = Math.random, originalDateNow = Date.now;
  const originalPerformance = Object.getOwnPropertyDescriptor(globalThis, 'performance');
  Math.random = () => { throw new Error('engine used global Math.random'); };
  Date.now = () => { throw new Error('engine used wall-clock time'); };
  Object.defineProperty(globalThis, 'performance', { configurable: true, get() { throw new Error('engine used global performance'); } });
  let frameCount = 0, retargetCount = 0;
  const smoothness = {};
  try {
    checkLockedMagnitudes(createSlime, catalog, motion);
    checkClock(createSlime, catalog, motion);
    checkDragAndPause(createSlime, catalog);
    await checkSemanticFace(catalog);
    await checkExtensionEquations(createSlime, catalog);
    for (const file of scriptFiles) {
      const script = readScript(path.join(root, 'scripts', file));
      const smooth = createSmoothness(file), observe = smooth.run();
      let before, event = false;
      const a = runScript(createSlime, catalog, script, 53, observation => {
        if (observation.kind === 'event') {
          before = structuredClone(observation.after); event = true;
          if (['mood', 'facts', 'oneShot', 'linkTimedOut'].includes(observation.event.type)) {
            const before = physical(observation.before), after = physical(observation.after);
            const reflex = observation.event.type === 'oneShot' && ['poked', 'tap_spam'].includes(observation.event.moment.name);
            if (reflex) {
              for (const [name, mode] of Object.entries(after.modes)) {
                near(mode.x, before.modes[name].x, `${SPEC}, Alerts, taps and interruption: admitted touch preserves displacement`);
                range(mode.v, -8, 8, `${SPEC}, Alerts, taps and interruption: admitted touch uses the accepted impulse velocity cap`);
                mode.v = before.modes[name].v;
              }
            }
            assert.deepEqual(after, before,
              `${SPEC}, Proposed layer ownership: ${file}:${observation.at} ${observation.event.type} reset a spring`);
            near(observation.after.time, observation.before.time, `${SPEC}, Proposed layer ownership: setter changes clock`);
            retargetCount++;
          }
          return;
        }
        checkTraceNumber(observation.channels, observation.inspect, observation.at, before, motion);
        observe(observation.channels, event);
        before = structuredClone(observation.channels); event = false;
      });
      smooth.finish();
      for (const [family, ratio] of Object.entries(smooth.summary())) smoothness[family] = Math.max(smoothness[family] ?? 0, ratio);
      const b = runScript(createSlime, catalog, script, 53);
      assert.deepEqual(a, b, `${SPEC}, Headless reference traces: full precision deterministic replay: ${file}`);
      const encoded = serializeTrace(script, 53, a);
      assert.equal(encoded, serializeTrace(script, 53, b), `${SPEC}, Headless reference traces: byte-identical replay: ${file}`);
      const golden = path.join(root, 'traces', file.replace(/\.jsonl$/, '.json'));
      assert.ok(encoded === fs.readFileSync(golden, 'utf8'),
        `${SPEC}, Headless reference traces: stale golden ${path.basename(golden)}; review channel changes before regenerating`);
      const saved = JSON.parse(encoded);
      assert.equal(saved.frames.length, script.durationMs / STEP_MS + 1, `${SPEC}, Headless reference traces: keep every frame`);
      const timeColumn = saved.columns.indexOf('/time');
      assert.ok(timeColumn >= 0);
      for (let i = 0; i < saved.frames.length; i++) {
        near(saved.frames[i][timeColumn], i * STEP_MS / 1000, `${SPEC}, Headless reference traces: frame ${i} time`);
        const exact = flatten(a.frames[i]);
        for (const [column, key] of saved.columns.entries()) {
          if (typeof exact[key] === 'number') {
            assert.ok(Math.abs(saved.frames[i][column] - exact[key]) <= 0.5e-6 + eps,
              `${SPEC}, Headless reference traces: rounding error at frame ${i}, ${key}`);
          }
        }
      }
      frameCount += a.frames.length;
    }
    checkIndependentActors(createSlime, catalog, readScript(path.join(root, 'scripts/idle-60s.jsonl')));
  } finally {
    Math.random = originalRandom;
    Date.now = originalDateNow;
    if (originalPerformance) Object.defineProperty(globalThis, 'performance', originalPerformance);
    else delete globalThis.performance;
  }
  return { status: 'ENGINE TRACE PASS', scripts: scriptFiles.length, frames: frameCount, retargets: retargetCount, smoothness,
    determinism: 'full precision and byte-identical goldens', continuity: 'setters preserve every spring; body modes move only by their springs; drawn channels bounded',
    scope: 'Reference engine continuity; scene and edge coverage are checked separately; sound checked separately; no device claims' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  if (process.argv.length === 3 && process.argv[2] === '--help') {
    console.log('node tools/check-engine.mjs\nChecks the pure Phase 1 engine and every checked-in fixed-step golden trace. Writes no files.');
  } else if (process.argv.length > 2) {
    console.error('Unknown arguments; use --help'); process.exitCode = 1;
  } else {
    checkEngine().then(result => console.log(JSON.stringify(result))).catch(error => { console.error(error); process.exitCode = 1; });
  }
}
