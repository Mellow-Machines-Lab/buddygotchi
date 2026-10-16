#!/usr/bin/env node
// Phase 2 engineering coverage. Owner review approves the representative art;
// each remaining mood/state cell earns coverage only after actual execution.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { root, STEP_MS, loadEngine, loadCatalog, readScript, runScript } from './trace.mjs';
import { createSmoothness, tracked } from './smooth.mjs';

const FULL_SPEC = 'CONTINUITY.md, Full activity scene matrix';
const graph = JSON.parse(fs.readFileSync(path.join(root, 'emotion-graph.json'), 'utf8'));
const plan = JSON.parse(fs.readFileSync(path.join(root, 'state-plan.json'), 'utf8'));
const canonicalMoods = Object.keys(graph.nodes);
const states = plan.states;
const quietStates = new Set(['asleep', 'no_app']);
const baseStates = new Set(['idle', 'working', 'asleep']);
const requestStates = new Set(states.filter(state => state.kind === 'one_shot').map(state => state.id));
export const fullMatrixCells = canonicalMoods.flatMap(mood => states.map(state => `${mood}.${state.id}`));

function factCases(state) {
  if (state === 'starting') return ['new_task', 'session', 'continuation', 'compacted'].map(ctx => ({ ctx }));
  if (state === 'task_complete') return ['success', 'failure'].map(outcome => ({ outcome }));
  return [{}];
}
async function checkProfileContract() {
  const { profileLimits, profileTraits, recoveryGesture } = await import('../engine/scenes/profile.mjs');
  const { sceneMoodTraits } = await import('../engine/scenes/mood.mjs');
  assert.deepEqual(profileLimits, { delayMs: 160, spacingMin: 0.88, spacingMax: 1.18, gainMin: 0.68,
    gainMax: 1.12, lean: 0.022, cueWindowSeconds: 0.48, recoveryGain: { lean: 0.025, squash: 0.018, forward: 0.015 } },
  `${FULL_SPEC}: catalogue-derived profile limits and recovery gains`);
  const synthetic = (duration, cues) => ({ mood: 'calm', performances: Array.from({ length: 3 }, () => ({ duration, cues })) });
  const normal = synthetic(3.3, [[0, 'lean', 1], [0, 'forward', -0.5], [0, 'squash', 1.5]]);
  const normalTraits = profileTraits(normal);
  for (const [key, expected] of Object.entries({ delayMs: 36, spacing: 1.03125, gain: 0.92, lean: 0.0075 })) {
    near(normalTraits[key], expected, `${FULL_SPEC}: mean duration/energy/directional intent formula ${key}`);
  }
  assert.deepEqual(profileTraits(synthetic(0, [[0, 'lean', -100]])),
    { delayMs: -160, spacing: 0.88, gain: 1.12, lean: -0.022 }, `${FULL_SPEC}: low duration and negative direction clamp`);
  assert.deepEqual(profileTraits(synthetic(10, [[0, 'lean', 100]])),
    { delayMs: 160, spacing: 1.18, gain: 1.12, lean: 0.022 }, `${FULL_SPEC}: high duration, energy and positive direction clamp`);
  assert.equal(profileTraits(synthetic(3, [])).gain, 0.68, `${FULL_SPEC}: quiet catalogue energy floor`);
  assert.deepEqual(profileTraits(null), { delayMs: 0, spacing: 1, gain: 1, lean: 0 }, `${FULL_SPEC}: missing profile is neutral`);
  for (const [mood, traits] of Object.entries(sceneMoodTraits)) {
    assert.deepEqual(profileTraits({ ...normal, mood }), traits, `${FULL_SPEC}: approved representative traits remain exact`);
    assert.deepEqual(recoveryGesture({ ...normal, mood }, 0, 0.5), { lean: 0, squash: 0, forward: 0 },
      `${FULL_SPEC}: representative body choreography remains unchanged`);
  }
  const pulse = synthetic(2, [[0.5, 'roll', 2], [0.5, 'lift', 3], [0.5, 'ripple', 4], [0.5, 'ignored', 100]]);
  const peak = recoveryGesture(pulse, 0, 0.37);
  for (const [key, expected] of Object.entries({ lean: 0.05, squash: 0.054, forward: 0.06 })) {
    near(peak[key], expected, `${FULL_SPEC}: mapped recovery cue peaks at half of the 0.48 second window`);
  }
  for (const progress of [-0.1, 0.24, 0.50, 1.1]) assert.deepEqual(recoveryGesture(pulse, 1, progress),
    { lean: 0, squash: 0, forward: 0 }, `${FULL_SPEC}: recovery cannot emit before/after its bounded cue window`);
  const allProfiles = loadCatalog().expressions;
  for (const mood of canonicalMoods) {
    const traits = profileTraits(allProfiles[mood]);
    assert.ok(Object.values(traits).every(Number.isFinite), `${FULL_SPEC}: ${mood} profile traits are finite`);
  }
}
async function checkFullFamilyConstants(createSlime, catalog) {
  const { deskRecipe } = await import('../engine/scenes/desk.mjs');
  const { helpersRecipe } = await import('../engine/scenes/helpers.mjs');
  const { listenRecipe } = await import('../engine/scenes/listen.mjs');
  const { startRecipe, wakeRecipe } = await import('../engine/scenes/start.mjs');
  const { touchRecipe } = await import('../engine/scenes/touch.mjs');
  const { createScenes } = await import('../engine/scenes/index.mjs');
  const { createRouter } = await import('../engine/router.mjs');
  const profiles = catalog.expressions;
  const rhythms = {
    planning: [[940], [620, 860], [760, 1560]], tool_use: [[520], [780, 1060], [620, 1460]],
    searching: [[620], [540, 760], [660, 1640]], analyzing: [[1020], [720, 1680], [1520]],
    testing: [[560], [480, 720], [740, 1840]], waiting: [[], [], []],
  };
  for (const [state, expected] of Object.entries(rhythms)) for (let variant = 0; variant < 3; variant++) {
    const recipe = deskRecipe(state, 'calm', variant, () => 0.5);
    assert.deepEqual(recipe.contacts.map(contact => contact.at), expected[variant], `${FULL_SPEC}: ${state} variant ${variant} authored contact rhythm`);
    assert.equal(recipe.focusCycles, variant + 1, `${FULL_SPEC}: desk focus cycles per variant`);
  }
  for (const mood of moods) for (const state of ['working', 'terminal']) for (let variant = 0; variant < 3; variant++) {
    assert.deepEqual(deskRecipe(state, mood, variant, () => 0.5, profiles[mood]), deskRecipe(state, mood, variant, () => 0.5),
      `${FULL_SPEC}: actual-profile ${mood}.${state} preserves the approved representative recipe`);
  }
  for (let variant = 0; variant < 3; variant++) {
    const crying = deskRecipe('working', 'crying', variant, () => 0.5, profiles.crying);
    assert.deepEqual(crying.contacts.map(contact => contact.at), [[760, 1780], [640, 2120], [1020, 2300]][variant],
      `${FULL_SPEC}: crying working pauses before continuing`);
    assert.ok(crying.contacts.every(contact => contact.strength === 0.55), `${FULL_SPEC}: crying work contact gain`);
    assert.equal(crying.lean, -0.024, `${FULL_SPEC}: crying work body bow`);
    assert.equal(deskRecipe('waiting', 'happy', variant, () => 0.5).lean, [0.006, 0.014, -0.010][variant],
      `${FULL_SPEC}: three silent waiting poses`);
    const listen = listenRecipe(variant);
    assert.deepEqual(listen.contacts, [], `${FULL_SPEC}: listening is silent`);
    assert.equal(listen.lean, [0.022, -0.012, 0.008][variant], `${FULL_SPEC}: listening pose targets`);
    assert.equal(listen.pulseCycles, [2, 1, 3][variant], `${FULL_SPEC}: listening pulse rhythms`);
    assert.equal(startRecipe('session', variant).contacts[0].at, [520, 820, 1080][variant], `${FULL_SPEC}: start reveal timings`);
    const wake = wakeRecipe(variant, 'calm');
    assert.deepEqual(wake.contacts.map(contact => [contact.at, contact.kind]), [[[560, 'start_reveal'], [1180, 'body_contact']],
      [[760, 'start_reveal'], [1240, 'body_contact'], [1420, 'body_contact']], [[900, 'start_reveal'], [1500, 'start_reveal']]][variant],
      `${FULL_SPEC}: wake_up stretches, then settles`);
    assert.equal(wake.label, undefined, `${FULL_SPEC}: wake_up shows no card`);
    for (const state of ['delegating', 'helper_return']) {
      const helpers = helpersRecipe(state, variant);
      assert.deepEqual(helpers.contacts.map(contact => contact.at), state === 'helper_return' ? [[680], [960], [1240]][variant]
        : [[660, 1040], [540, 880, 1220], [820, 1640]][variant], `${FULL_SPEC}: helper departure/return timings`);
      assert.equal(helpers.helperCount, state === 'helper_return' ? 1 : [2, 3, 2][variant], `${FULL_SPEC}: helper population`);
      assert.equal(helpers.helperDirection, variant === 2 ? -1 : 1, `${FULL_SPEC}: helper direction variation`);
    }
    for (const state of ['poked', 'tap_spam']) {
      const touch = touchRecipe(state, variant);
      assert.deepEqual(touch.contacts.map(contact => contact.at), state === 'poked' ? [[160], [200, 480], [160, 520]][variant]
        : [[160, 400], [160, 340, 520], [220, 620]][variant], `${FULL_SPEC}: authored touch contacts`);
      assert.equal(touch.lean, [0.008, -0.018, 0.012][variant], `${FULL_SPEC}: touch lean targets`);
      assert.ok(touch.contacts.every(contact => contact.strength === (state === 'poked' ? 0.6 : 0.9)), `${FULL_SPEC}: bounded touch gain`);
    }
  }
  function integrate(target) {
    let x = 0, v = 0, remaining = 0.016;
    while (remaining > 0) { const h = Math.min(remaining, 1 / 240); v += (144 * (target - x) - 10 * v) * h; x += v * h; remaining -= h; }
    return { x, v };
  }
  for (const reducedMotion of [false, true]) {
    const reduced = { matches: reducedMotion }, scenes = createScenes({ profiles, reduced, rand: () => 0.5 }), router = createRouter();
    router.setFacts({ base: 'working', act: 'waiting' }); scenes.setRoute(router.resolve(), 0, 'happy');
    const initial = scenes.inspect(0).scene, recipe = deskRecipe('waiting', 'happy', initial.variant, () => 0.5);
    scenes.advance(0.016, 400);
    const wave = 0.65 + 0.35 * Math.sin(400 / recipe.duration * Math.PI * 2 * recipe.focusCycles);
    const expected = integrate(recipe.lean * wave * (reducedMotion ? 0.18 : 1)), actual = scenes.inspect(400);
    near(actual.activityChannels.lean.x, expected.x, `${FULL_SPEC}: quiet activity wave and reduced-motion gain`);
    near(actual.activityChannels.lean.v, expected.v, `${FULL_SPEC}: quiet activity preserves spring integration`);
    near(actual.props.desk.focus, reducedMotion ? 0.5 : 0.5 + 0.5 * Math.sin(400 / recipe.duration * Math.PI * 2 * recipe.focusCycles),
      `${FULL_SPEC}: bounded focus pulse and reduced-motion static focus`);
  }
  for (const state of ['starting', 'helper_return', 'reply_ready', 'error', 'stopped']) {
    const scenes = createScenes({ profiles, reduced: { matches: false }, rand: () => 0.5 }), router = createRouter();
    router.oneShot({ id: 'numeric', name: state, args: { ctx: 'session' } }); scenes.setRoute(router.resolve(), 0, 'happy');
    const variant = scenes.inspect(0).scene.variant;
    const at = state === 'starting' ? [520, 820, 1080][variant] : [680, 960, 1240][variant];
    scenes.advance(0.016, at);
    const actual = scenes.inspect(at);
    near(actual.activityChannels.squash.x, integrate(0.018 * 1.05).x, `${FULL_SPEC}: neutral presentation squash amplitude`);
    near(actual.activityChannels.forward.x, integrate((state === 'error' ? -0.025 : 0.018) * 1.05).x,
      `${FULL_SPEC}: error recoils while neutral cards gently present`);
    if (state === 'helper_return') near(actual.props.helpers.progress, 1, `${FULL_SPEC}: helper reaches its destination at the actual reveal`);
  }
  const idle = driver(createSlime, catalog), automatic = [];
  let count = idle.channels.performanceCount;
  while (automatic.length < 12) {
    const frame = idle.step();
    if (frame.performanceCount === count) continue;
    count = frame.performanceCount; automatic.push(frame.performance.index);
    const gap = frame.nextPerformance - frame.time - frame.performance.duration;
    assert.ok(gap >= 7 && gap < 15, `${FULL_SPEC}: automatic idle retains the original quiet interval`);
  }
  for (let offset = 0; offset < automatic.length; offset += 3) assert.deepEqual(automatic.slice(offset, offset + 3).sort(), [0, 1, 2],
    `${FULL_SPEC}: automatic idle consumes all three gestures in each shuffle bag`);
  for (let index = 1; index < automatic.length; index++) assert.notEqual(automatic[index], automatic[index - 1],
    `${FULL_SPEC}: automatic idle never immediately repeats across bag boundaries`);
  for (const state of ['poked', 'tap_spam']) {
    const d = driver(createSlime, catalog), before = d.slime.inspect();
    const input = { id: `once-${state}`, name: state };
    assert.equal(d.slime.oneShot(input).accepted, true, `${FULL_SPEC}: an admitted touch starts once`);
    const after = d.slime.inspect();
    for (const [name, spring] of Object.entries(after.modes)) {
      near(spring.x, before.modes[name].x, `${FULL_SPEC}: a touch impulse preserves current displacement`);
      assert.ok(Math.abs(spring.v) <= 8, `${FULL_SPEC}: touch entry uses the existing impulse velocity limit`);
    }
    assert.equal(d.slime.oneShot(input).accepted, false, `${FULL_SPEC}: duplicate touch admission is refused`);
    assert.deepEqual(physical(d.slime), physical({ inspect: () => after }), `${FULL_SPEC}: duplicate touch cannot add another impulse`);
    d.slime.setFacts({ base: 'working', attn: { id: 42, agent: 'codex', project: 'matrix' } });
    const held = physical(d.slime);
    assert.equal(d.slime.oneShot({ id: `blocked-${state}`, name: state }).accepted, false, `${FULL_SPEC}: attention refuses decorative touch admission`);
    assert.deepEqual(physical(d.slime), held, `${FULL_SPEC}: refused touch cannot add an impulse behind attention`);
  }
}
function admitState(d, state, args, id) {
  d.slime.setLinkTimedOut(false);
  d.slime.oneShot({ id: `stop-${id}`, name: 'stop_listening' });
  d.slime.setFacts({ base: baseStates.has(state) ? state : 'working',
    ...(!baseStates.has(state) && !requestStates.has(state) && !['needs_you', 'listening', 'no_app'].includes(state) ? { act: state } : {}) });
  if (state === 'no_app') d.slime.setLinkTimedOut(true);
  else if (state === 'needs_you') d.slime.setFacts({ base: 'working', attn: { id, agent: 'codex', project: 'matrix' } });
  else if (state === 'listening' || requestStates.has(state)) {
    const admission = d.slime.oneShot({ id, name: state, args: { ...args, loops: 1 } });
    assert.equal(admission.accepted, true, `${FULL_SPEC}: admit ${state}`);
  }
  return route(d, state);
}
function validateMatrixFrame(frame, sample, context) {
  const { mood, state, args } = sample;
  assert.equal(frame.mood, mood, `${FULL_SPEC}: ${context} cannot change logical mood`);
  assert.equal(frame.props.lane.top, 0.8, `${FULL_SPEC}: ${context} reserves the bottom 20%`);
  assert.equal(frame.props.desk.id, 'desk-1', `${FULL_SPEC}: ${context} keeps the shared desk identity`);
  // A card fading out after its route ended still carries its own facts.
  if (frame.props.result.trophy) {
    assert.equal(frame.props.result.state, 'task_complete', `${FULL_SPEC}: only task completion can display a trophy`);
    assert.equal(frame.props.result.outcome, 'success', `${FULL_SPEC}: trophy requires explicit success`);
  }
  for (const [name, bound] of Object.entries({ lean: 0.08, squash: 0.06, forward: 0.05 })) {
    const spring = frame.activityChannels[name];
    assert.ok(Number.isFinite(spring.x) && Math.abs(spring.x) <= bound + 1e-12,
      `${FULL_SPEC}: ${context} ${name} displacement is bounded`);
    assert.ok(Number.isFinite(spring.v) && Math.abs(spring.v) <= 1.2 + 1e-12,
      `${FULL_SPEC}: ${context} ${name} velocity is bounded`);
  }
  for (const [index, bound] of [1.25, 1.32, 1.14, 0.72].entries()) {
    assert.ok(Number.isFinite(frame.pose[index]) && Math.abs(frame.pose[index]) <= bound + 1e-12,
      `${FULL_SPEC}: ${context} composed pose is bounded`);
  }
  for (const [name, value] of Object.entries(frame.face)) {
    if (typeof value === 'number') assert.ok(Number.isFinite(value), `${FULL_SPEC}: ${context} semantic face ${name} is finite`);
  }
  for (const key of ['cheekAlpha', 'tearAmount', 'bridgeBlink']) {
    assert.ok(frame.face[key] >= 0 && frame.face[key] <= 1, `${FULL_SPEC}: ${context} ${key} stays in [0,1]`);
  }
  assert.equal(typeof frame.face.artId, 'string', `${FULL_SPEC}: ${context} emits one semantic face identity`);
  if (frame.scene.state !== state) return;
  assert.equal(frame.scene.implemented, true, `${FULL_SPEC}: ${context} must have authored choreography`);
  if (state === 'starting') assert.equal(frame.scene.ctx, args.ctx, `${FULL_SPEC}: ${context} retains the actual start context`);
  if (state === 'task_complete') assert.equal(frame.scene.outcome, args.outcome, `${FULL_SPEC}: ${context} retains the factual outcome`);
  if (state === 'testing') assert.ok(!/\b(?:pass|fail|success|failure)\b/i.test(JSON.stringify(frame.props.desk)),
    `${FULL_SPEC}: ${context} cannot invent a test outcome`);
  if (['waiting', 'listening'].includes(state)) assert.equal(frame.contacts.length, 0,
    `${FULL_SPEC}: ${context} remains attentive without contact cues`);
  if (state === 'wake_up') assert.equal(frame.props.start.visible, 0, `${FULL_SPEC}: ${context} stretches without a start card`);
  if (state === 'starting' && frame.props.start.visible) assert.equal(frame.props.start.label,
    { new_task: 'NEW TASK', session: 'START', continuation: 'RESUME', compacted: 'COMPACTED' }[args.ctx], `${FULL_SPEC}: factual start card wording`);
  if (['reply_ready', 'error', 'stopped'].includes(state) && frame.props.result.visible) {
    assert.equal(frame.props.result.label, { reply_ready: 'READY', error: 'TOOL ERROR', stopped: 'STOPPED' }[state],
      `${FULL_SPEC}: ${context} has its own factual result wording`);
    assert.equal(frame.props.result.trophy, false, `${FULL_SPEC}: ${context} cannot invent a completed successful task`);
  }
  if (state === 'helper_return') assert.ok(!/\b(?:pass|fail|success|failure|complete)\b/i.test(JSON.stringify(frame.props.helpers)),
    `${FULL_SPEC}: ${context} reports return without presuming success`);
  if (quietStates.has(state)) {
    assert.equal(frame.scene.quiet, true, `${FULL_SPEC}: ${context} explicitly declares a quiet alias`);
    assert.equal(frame.contacts.length, 0, `${FULL_SPEC}: ${context} emits no contacts`);
    assert.equal(frame.performance, null, `${FULL_SPEC}: ${context} does not perform mood gestures`);
    if (frame.scene.ageMs >= 240) assert.equal(frame.face.sleeping, true, `${FULL_SPEC}: ${context} settles into the shared sleepy face`);
  }
}

export async function checkFullMatrix() {
  const createSlime = await loadEngine(), catalog = loadCatalog();
  await checkProfileContract();
  await checkFullFamilyConstants(createSlime, catalog);
  assert.equal(canonicalMoods.length, 42, `${FULL_SPEC}: canonical mood count`);
  assert.equal(states.length, 23, `${FULL_SPEC}: factual state count`);
  assert.equal(fullMatrixCells.length, 966, `${FULL_SPEC}: every canonical mood/state cell is required`);
  const { implementedStates } = await import('../engine/scenes/constants.mjs');
  assert.deepEqual([...implementedStates].sort(), states.map(state => state.id).sort(), `${FULL_SPEC}: all 23 scenes have implementations`);
  const verified = new Set();
  let frameCount = 0, variantsChecked = 0, factCasesChecked = 0, quietAliases = 0;
  for (const mood of canonicalMoods) for (const definition of states) {
    const state = definition.id;
    for (const args of factCases(state)) {
      const sample = { mood, state, args }, context = [mood, state, args.ctx, args.outcome].filter(Boolean).join('.');
      const d = driver(createSlime, catalog, mood), variants = new Set(), contactIds = new Set(), evidence = new Map();
      let activeFrames = 0, previous, lastVariant, lastIteration, idleVariant;
      const observe = frame => {
        frameCount++;
        validateMatrixFrame(frame, sample, context);
        if (frame.scene.state === state) {
          activeFrames++;
          if (!quietStates.has(state) && state !== 'idle') variants.add(frame.scene.variant);
          const variant = state === 'idle' ? idleVariant : frame.scene.variant;
          if (!quietStates.has(state) && variant !== undefined) {
            const token = state === 'idle' ? variant : `${frame.scene.requestId}:${frame.scene.iteration}`;
            if (!evidence.has(variant)) evidence.set(variant, { token, contacts: [], samples: Array(24).fill(null), visible: new Set(), peak: 0 });
            const item = evidence.get(variant), age = state === 'idle' ? frame.performance.age * 1000 : frame.scene.ageMs;
            if (item.token === token) {
              for (const key of ['start', 'result', 'helpers', 'listening', 'alert', 'desk']) {
                if (frame.props[key]?.visible > 0.5) item.visible.add(key);
              }
              for (const contact of frame.contacts) item.contacts.push([Math.round(age), contact.kind, contact.side, Number(contact.strength.toFixed(4))]);
              const physical = state === 'idle' ? Object.values(frame.actorChannels).map(spring => spring.x)
                : Object.values(frame.activityChannels).map(spring => spring.x);
              item.peak = Math.max(item.peak, ...physical.map(Math.abs));
              const duration = state === 'idle' ? frame.performance.duration * 1000 : frame.scene.loopDurationMs;
              const bin = Math.max(0, Math.min(23, Math.floor(age / duration * 24)));
              if (item.samples[bin] === null) item.samples[bin] = physical.map(value => Number(value.toFixed(4)));
            }
          }
        }
        for (const contact of frame.contacts) {
          assert.equal(contact.requestId, frame.scene.requestId, `${FULL_SPEC}: ${context} cannot emit an interrupted contact`);
          assert.ok(!contactIds.has(contact.id), `${FULL_SPEC}: ${context} cannot repeat a consumed contact`);
          contactIds.add(contact.id);
        }
        previous = frame;
      };
      const entered = admitState(d, state, args, `${context}-0`); observe(entered);
      if (quietStates.has(state)) {
        d.advance(3200, observe); quietAliases++;
        assert.equal(d.channels.mood, mood, `${FULL_SPEC}: quiet alias retains mood for later wake`);
      } else if (state === 'idle') {
        for (let index = 0; index < 3; index++) {
          idleVariant = index;
          d.slime.perform(index);
          const performance = d.slime.inspect().performance;
          assert.equal(performance.index, index, `${FULL_SPEC}: ${context} authored gesture index ${index}`);
          variants.add(performance.index);
          const duration = Math.ceil((performance.duration * 1000 + 160) / STEP_MS) * STEP_MS;
          d.advance(duration, observe);
        }
      } else if (definition.kind === 'persistent') {
        d.advance(16000, frame => {
          if (frame.scene.iteration !== lastIteration) {
            if (lastIteration !== undefined) {
              assert.notEqual(frame.scene.variant, lastVariant, `${FULL_SPEC}: ${context} cannot immediately repeat a variation`);
              assert.equal(previous.scene.phase, 'sustain', `${FULL_SPEC}: ${context} changes variation only after recovery`);
            }
            lastIteration = frame.scene.iteration; lastVariant = frame.scene.variant;
          }
          observe(frame);
        });
        if (state === 'listening') {
          assert.equal(d.channels.scene.state, state, `${FULL_SPEC}: ${context} waits for real stop/reply input`);
          d.slime.oneShot({ id: `end-${context}`, name: 'stop_listening' });
          route(d, 'working', `${context} ends only on actual stop input`);
        }
      } else {
        for (let activation = 0; activation < 3; activation++) {
          const started = activation === 0 ? entered : admitState(d, state, args, `${context}-${activation}`);
          variants.add(started.scene.variant);
          if (activation) observe(started);
          const requestId = started.scene.requestId;
          let reveals = 0;
          if (requestStates.has(state)) d.slime.setFacts({ base: 'working', act: 'terminal' });
          const duration = Math.ceil((started.scene.loopDurationMs + 80) / STEP_MS) * STEP_MS;
          d.advance(duration, frame => {
            reveals += frame.contacts.filter(contact => contact.requestId === requestId && contact.kind.endsWith('_reveal')).length;
            observe(frame);
          });
          if (state === 'needs_you' || ['starting', 'helper_return', 'reply_ready', 'task_complete', 'error', 'stopped'].includes(state)) {
            assert.equal(reveals, 1, `${FULL_SPEC}: ${context} variant ${started.scene.variant} has exactly one factual reveal`);
          }
          if (requestStates.has(state)) assert.equal(d.channels.scene.state, 'terminal', `${FULL_SPEC}: ${context} returns to the latest facts`);
          if (state === 'listening') {
            assert.equal(d.channels.scene.state, state, `${FULL_SPEC}: ${context} waits for real stop/reply input`);
            d.slime.oneShot({ id: `end-${activation}`, name: 'stop_listening' }); d.step();
          } else if (state === 'needs_you') { d.slime.setFacts({ base: 'working' }); d.step(); }
        }
      }
      assert.ok(activeFrames > 0, `${FULL_SPEC}: ${context} was actually advanced`);
      if (!quietStates.has(state)) {
        assert.deepEqual([...variants].sort(), [0, 1, 2], `${FULL_SPEC}: ${context} exercises all three active variants`);
        const signatures = [...evidence.values()].map(item => JSON.stringify({ contacts: item.contacts, samples: item.samples }));
        assert.equal(new Set(signatures).size, 3, `${FULL_SPEC}: ${context} needs three physically different rhythms or poses, not metadata-only variants`);
        for (const item of evidence.values()) {
          assert.ok(item.peak > 0.0001, `${FULL_SPEC}: ${context} each active variant participates in actual body motion`);
          assert.ok(item.samples.every(sample => sample !== null), `${FULL_SPEC}: ${context} physically samples all 24 normalized phases`);
        }
        const requiredProp = state === 'starting' ? 'start' : ['reply_ready', 'task_complete', 'error', 'stopped'].includes(state) ? 'result'
          : ['delegating', 'helper_return'].includes(state) ? 'helpers' : state === 'listening' ? 'listening'
            : state === 'needs_you' ? 'alert' : definition.scene === 'desk' ? 'desk' : null;
        if (requiredProp) for (const [variant, item] of evidence) assert.ok(item.visible.has(requiredProp),
          `${FULL_SPEC}: ${context} variant ${variant} actually reveals its ${requiredProp} prop`);
        variantsChecked += variants.size;
      }
      factCasesChecked++;
    }
    verified.add(`${mood}.${state}`);
  }
  assert.deepEqual([...verified].sort(), [...fullMatrixCells].sort(), `${FULL_SPEC}: coverage comes only from exercised cells`);
  return { cells: [...verified], frames: frameCount, variants: variantsChecked, factCases: factCasesChecked, quietAliases };
}

const SPEC = 'CONTINUITY.md, Representative activity scenes';
const SCRIPT = 'scripts/representative-matrix.jsonl';
const CASE_MS = 8000;
const moods = ['happy', 'grumpy', 'sad', 'frightened'];
const examples = [{ state: 'working' }, { state: 'terminal' }, { state: 'needs_you' },
  { state: 'task_complete', outcome: 'success' }, { state: 'task_complete', outcome: 'failure' }, { state: 'asleep' }];

export const representativeCases = moods.flatMap(mood => examples.map(example => ({
  id: [mood, example.state, example.outcome].filter(Boolean).join('.'), mood, ...example, script: SCRIPT,
}))).map((sample, index) => ({ ...sample, startMs: index * CASE_MS, endMs: (index + 1) * CASE_MS }));
export const exercisedCells = [...new Set(representativeCases.map(sample => `${sample.mood}.${sample.state}`))];

function near(actual, expected, message, tolerance = 1e-10) {
  assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) <= tolerance, `${SPEC}: ${message}: ${actual} != ${expected}`);
}
function physical(slime) {
  const state = slime.inspect();
  return structuredClone({ modes: state.modes, actorChannels: state.actorChannels,
    activityChannels: state.activityChannels, pull: state.grab.pull, pose: state.pose, life: state.life });
}
// Every driven actor's frames, against the bounds on what is drawn.
const smooth = createSmoothness('scene matrix');
function driver(createSlime, catalog, mood = 'happy') {
  let event = false;
  const slime = tracked(createSlime({ seed: 53, catalog }), () => { event = true; }), observe = smooth.run();
  slime.setMood(mood);
  let at = 0, channels = slime.step(at).channels;
  observe(channels, event); event = false;
  return {
    slime,
    get at() { return at; },
    get channels() { return channels; },
    step() { at += STEP_MS; channels = slime.step(at).channels; observe(channels, event); event = false; return channels; },
    advance(ms, visit = () => {}) {
      assert.equal(ms % STEP_MS, 0, `${SPEC}: tests advance on the fixed trace clock`);
      for (let passed = 0; passed < ms; passed += STEP_MS) visit(this.step());
      return channels;
    },
  };
}
function route(d, expected, message = expected) {
  const channels = d.step();
  assert.equal(channels.scene.state, expected, `${SPEC}: ${message}`);
  return channels;
}
function setWithoutReset(slime, action, message) {
  const before = physical(slime);
  action();
  assert.deepEqual(physical(slime), before, `${SPEC}: ${message} must preserve every spring position and velocity`);
}

export async function checkRepresentative() {
  const createSlime = await loadEngine(), catalog = loadCatalog();
  assert.equal(representativeCases.length, 24, `${SPEC}: the owner gate has 24 visual cases`);
  assert.equal(exercisedCells.length, 20, `${SPEC}: completion outcomes share one mood/state coverage cell`);
  const script = readScript(path.join(root, SCRIPT));
  assert.equal(script.durationMs, representativeCases.length * CASE_MS, `${SPEC}: every case has its review window`);
  const played = runScript(createSlime, catalog, script, 53);
  for (const sample of representativeCases) {
    const frames = played.frames.slice(sample.startMs / STEP_MS, sample.endMs / STEP_MS);
    assert.ok(frames.length > 0, `${SPEC}: missing frames for ${sample.id}`);
    assert.ok(frames.every(frame => frame.mood === sample.mood), `${SPEC}: actor retains host mood for ${sample.id}`);
    const active = frames.filter(frame => frame.scene.state === sample.state);
    assert.ok(active.length > 0, `${SPEC}: script never exercised ${sample.id}`);
    assert.ok(active.every(frame => frame.scene.implemented === true), `${SPEC}: ${sample.id} is still a planned scene`);
    for (const frame of frames) {
      near(frame.props.lane.top, 0.8, `bottom 20% remains the text lane in ${sample.id}`);
      assert.ok(frame.props.desk.y < frame.props.lane.top, `${SPEC}: desk anchor must remain above text lane`);
      if (frame.props.result.trophy) assert.equal(frame.props.result.outcome, 'success', `${SPEC}: trophy only on explicit success`);
    }
    if (sample.state === 'working' || sample.state === 'terminal') {
      assert.ok(active.some(frame => frame.props.desk.visible > 0.9), `${SPEC}: desk never appears for ${sample.id}`);
      assert.ok(active.some(frame => frame.contacts.some(contact => contact.kind === 'key_contact')),
        `${SPEC}: no visible keyboard contact exercised for ${sample.id}`);
    }
    if (sample.state === 'needs_you') {
      assert.ok(active.some(frame => frame.props.alert.visible > 0.9), `${SPEC}: sign never appears for ${sample.id}`);
      assert.ok(active.some(frame => frame.contacts.length > 0), `${SPEC}: alert entry contacts never exercised for ${sample.id}`);
    }
    if (sample.state === 'task_complete') {
      assert.ok(active.every(frame => frame.scene.outcome === sample.outcome), `${SPEC}: truthful outcome for ${sample.id}`);
      assert.ok(active.some(frame => frame.props.result.visible > 0.9), `${SPEC}: result never appears for ${sample.id}`);
      if (sample.outcome === 'failure') assert.ok(frames.every(frame => !frame.props.result.trophy), `${SPEC}: failed task never shows trophy`);
      else assert.ok(active.some(frame => frame.props.result.trophy), `${SPEC}: successful task reveal exercised`);
      assert.equal(frames.at(-1).scene.state, 'working', `${SPEC}: ${sample.id} returns to live facts after its own lifetime`);
    }
    if (sample.state === 'asleep') {
      assert.ok(active.every(frame => frame.scene.quiet && frame.contacts.length === 0), `${SPEC}: sleeping is an explicit quiet alias`);
      assert.ok(active.every(frame => frame.performance === null), `${SPEC}: no decorative recipe while asleep`);
      assert.ok(active.filter(frame => frame.scene.ageMs >= 240).every(frame => frame.face.sleeping),
        `${SPEC}: shared sleeping face settles through its blink bridge while retaining stored mood`);
    }
  }
  checkRepresentativeVariations(createSlime, catalog);
  return { cases: representativeCases, cells: exercisedCells };
}

function checkRepresentativeVariations(createSlime, catalog) {
  for (const sample of representativeCases.filter(sample => sample.state !== 'asleep')) {
    const d = driver(createSlime, catalog, sample.mood), variants = new Set();
    d.slime.setFacts({ base: 'working', act: sample.state === 'terminal' ? 'terminal' : null });
    if (sample.state === 'working' || sample.state === 'terminal') {
      let previous;
      d.advance(16000, frame => {
        variants.add(frame.scene.variant);
        if (previous && frame.scene.iteration !== previous.scene.iteration) {
          assert.equal(previous.scene.phase, 'sustain', `${SPEC}: variation changes only after recovery has finished`);
          assert.notEqual(frame.scene.variant, previous.scene.variant, `${SPEC}: ${sample.id} cannot immediately repeat a variation`);
        }
        previous = frame;
      });
    } else {
      for (let activation = 0; activation < 3; activation++) {
        if (sample.state === 'needs_you') {
          d.slime.setFacts({ base: 'working', attn: { id: 2000 + activation, agent: 'codex', project: 'slime' } });
        } else {
          d.slime.oneShot({ id: 3000 + activation, name: 'task_complete', args: { outcome: sample.outcome, loops: 1 } });
        }
        const started = route(d, sample.state), requestId = started.scene.requestId;
        variants.add(started.scene.variant);
        let reveals = 0;
        d.advance(4800, frame => {
          for (const contact of frame.contacts) {
            assert.equal(contact.requestId, frame.scene.requestId, `${SPEC}: an old recipe cannot emit contacts after interruption`);
            if (contact.requestId === requestId && contact.kind.endsWith('_reveal')) reveals++;
          }
        });
        assert.equal(reveals, 1, `${SPEC}: ${sample.id} variant ${started.scene.variant} reveals exactly once per request`);
        if (sample.state === 'needs_you') { d.slime.setFacts({ base: 'working' }); d.step(); }
      }
    }
    assert.deepEqual([...variants].sort(), [0, 1, 2], `${SPEC}: all three variants actually exercised for ${sample.id}`);
  }
}

function checkRouting(createSlime, catalog) {
  const visited = new Set();
  const d = driver(createSlime, catalog);
  const expect = (state, message) => { visited.add(state); return route(d, state, message); };
  for (const state of ['asleep', 'idle', 'working']) {
    d.slime.setFacts({ base: state }); expect(state);
  }
  for (const act of ['testing', 'delegating', 'terminal', 'searching', 'analyzing', 'tool_use', 'waiting', 'planning']) {
    d.slime.setFacts({ base: 'working', act }); expect(act);
  }
  d.slime.setFacts({ base: 'idle', act: 'testing' }); expect('idle', 'activity only applies to working');
  d.slime.setFacts({ base: 'working', act: 'invented' }); expect('working', 'unknown activity keeps working');
  d.slime.setFacts({ base: 'invented', state: 'error' }); expect('idle', 'unknown base falls back to idle; flat state is not a wire fact');
  d.slime.setFacts({ base: 'working', attn: { id: 1, agent: 'codex', project: 'slime', more: 0 } }); expect('needs_you');
  d.slime.oneShot({ id: 2, name: 'listening', args: {} }); expect('listening', 'listening holds priority over attention');
  const listeningRequest = d.channels.scene.requestId;
  d.slime.oneShot({ id: 99, name: 'listening', args: {} }); expect('listening');
  assert.equal(d.channels.scene.requestId, listeningRequest, `${SPEC}: repeated listening preserves its design lifetime`);
  d.slime.setLinkTimedOut(true); expect('no_app', 'only explicit device timeout produces no_app');
  d.slime.setLinkTimedOut(false); expect('listening');
  d.slime.oneShot({ id: 3, name: 'react', args: { say: {} } }); expect('needs_you', 'empty say ends listening');
  d.slime.setFacts({ base: 'working' }); expect('working', 'full snapshot without attn clears attention');
  let id = 10;
  for (const name of ['starting', 'stopped', 'error', 'helper_return', 'reply_ready', 'task_complete', 'poked', 'tap_spam', 'wake_up']) {
    const single = driver(createSlime, catalog);
    single.slime.setFacts({ base: 'working' });
    single.slime.oneShot({ id: id++, name, args: { outcome: 'failure', ctx: 'continuation', loops: 1 } });
    route(single, name); visited.add(name);
  }
  const planned = JSON.parse(fs.readFileSync(path.join(root, 'state-plan.json'), 'utf8')).states.map(state => state.id);
  assert.deepEqual([...visited].sort(), [...planned].sort(), `${SPEC}: route all 23 existing state IDs from current facts`);
  const stopped = driver(createSlime, catalog);
  stopped.slime.oneShot({ id: 1, name: 'task_complete', args: { outcome: 'failure' } }); route(stopped, 'task_complete');
  stopped.slime.oneShot({ id: 2, name: 'stop_listening' }); route(stopped, 'task_complete', 'stop_listening does not end unrelated moments');
  for (const outcome of [undefined, 'unknown', 'failure']) {
    const single = driver(createSlime, catalog);
    single.slime.oneShot({ id: 40, name: 'task_complete', args: { outcome } });
    single.advance(2400, frame => assert.ok(!frame.props.result.trophy, `${SPEC}: missing/unknown/failed outcome cannot invent success`));
  }
  const layered = driver(createSlime, catalog);
  layered.slime.setFacts({ base: 'working' });
  layered.slime.oneShot({ id: 60, name: 'task_complete', args: { outcome: 'failure' } });
  const finish = route(layered, 'task_complete');
  const identity = { requestId: finish.scene.requestId, generation: finish.scene.generation };
  layered.slime.oneShot({ id: 61, name: 'react', args: { mood: 'sad' } });
  const reaction = route(layered, 'task_complete', 'reaction expression overlays the active animation');
  assert.equal(reaction.scene.outcome, 'failure', `${SPEC}: reaction cannot change completion outcome`);
  assert.equal(reaction.mood, 'happy', `${SPEC}: reaction expression never changes the lasting mood`);
  assert.equal(reaction.expression, 'sad', `${SPEC}: reaction selects only its temporary expression`);
  assert.deepEqual({ requestId: reaction.scene.requestId, generation: reaction.scene.generation }, identity,
    `${SPEC}: react does not replace the active animation request`);
  layered.slime.oneShot({ id: 62, name: 'react', args: { say: {} } });
  const speech = route(layered, 'task_complete', 'speech-only reply never replaces scene');
  assert.equal(speech.scene.generation, identity.generation, `${SPEC}: speech-only reply does not restart choreography`);
  const bare = layered.slime.oneShot({ id: 63, name: 'react', args: {} });
  assert.equal(bare.accepted, false, `${SPEC}: a bare react has nothing to play`);
  for (const loops of [-2, 0, 1, 4, 100, NaN]) {
    const single = driver(createSlime, catalog);
    single.slime.oneShot({ id: 64, name: 'task_complete', args: { outcome: 'failure', loops } });
    assert.equal(route(single, 'task_complete').scene.loops, Number.isFinite(loops) ? Math.max(1, Math.min(6, loops)) : 1,
      `${SPEC}: loops use the existing protocol range 1–6`);
  }
  const plannedMoment = driver(createSlime, catalog);
  plannedMoment.slime.setFacts({ base: 'working' });
  plannedMoment.slime.oneShot({ id: 70, name: 'starting', args: { ctx: 'new_task' } });
  route(plannedMoment, 'starting');
  plannedMoment.slime.setFacts({ base: 'working', act: 'terminal' });
  plannedMoment.advance(16000);
  assert.equal(plannedMoment.channels.scene.state, 'terminal', `${SPEC}: a starting one-shot cannot trap the actor forever`);
  const repeated = driver(createSlime, catalog);
  repeated.slime.setFacts({ base: 'working' });
  repeated.slime.oneShot({ id: 80, name: 'task_complete', args: { outcome: 'failure', loops: 3 } });
  const loopVariants = new Set(), loopIterations = new Set(); let loopReveals = 0;
  repeated.advance(14400, frame => {
    if (frame.scene.state === 'task_complete') { loopVariants.add(frame.scene.variant); loopIterations.add(frame.scene.iteration); }
    loopReveals += frame.contacts.filter(contact => contact.kind === 'failure_reveal').length;
  });
  assert.equal(loopVariants.size, 1, `${SPEC}: explicit loops repeat the selected design, not a new variation`);
  assert.deepEqual([...loopIterations].sort(), [0, 1, 2], `${SPEC}: explicit loops retain their own iteration identity`);
  assert.equal(loopReveals, 3, `${SPEC}: each explicitly requested loop has one visible reveal`);
}

async function checkSceneConstants(createSlime, catalog) {
  const { sceneConstants: constants } = await import('../engine/scenes/constants.mjs');
  const { deskRecipe } = await import('../engine/scenes/desk.mjs');
  const { alertRecipe } = await import('../engine/scenes/alert.mjs');
  const { resultRecipe } = await import('../engine/scenes/result.mjs');
  const { sceneMoodTraits } = await import('../engine/scenes/mood.mjs');
  assert.deepEqual(constants, {
    entryMs: 240, recoveryMs: 480, contactMs: 120, cycleMs: [3200, 3700, 4200], timingJitterMs: 40,
    gainJitter: 0.1, activityFrequency: 12, activityDamping: 10, activityVelocity: 1.2,
    activityBounds: { lean: 0.08, squash: 0.06, forward: 0.05 }, propFrequency: 10, propDamping: 14, propRampMs: 200,
    hostLaneTop: 0.8, poseBounds: [1.25, 1.32, 1.14, 0.72], lifeBounds: [0.24, 0.12, 0.23],
  }, `${SPEC}: provisional representative-scene numbers are pinned for owner review`);
  assert.deepEqual(sceneMoodTraits, {
    happy: { delayMs: 0, spacing: 1, gain: 1.05, lean: 0.014 },
    grumpy: { delayMs: -40, spacing: 0.86, gain: 1.12, lean: 0.024 },
    sad: { delayMs: 160, spacing: 1.18, gain: 0.62, lean: -0.016 },
    frightened: { delayMs: 240, spacing: 1.28, gain: 0.68, lean: -0.018 },
  }, `${SPEC}: mood shapes a truthful alert/result, with bounded timing and force`);
  const ordinary = {
    working: [[580, 780, 1040], [560, 760, 1680, 1880], [1100, 2220]],
    terminal: [[600, 780, 960], [780, 1810, 2090], [580, 740, 900, 1060, 1960, 2120]],
  };
  const frightened = [[800, 1700, 2040], [740, 1800, 2240, 2480], [1080, 2380]];
  const grumpy = [[640, 800, 960], [800, 960, 1120, 2100], [660, 820, 980, 1140, 2120]];
  for (const mood of moods) for (const state of ['working', 'terminal']) {
    const signatures = [];
    for (const variant of [0, 1, 2]) {
      const base = deskRecipe(state, mood, variant, () => 0.5);
      let expected = mood === 'frightened' ? frightened[variant]
        : mood === 'grumpy' && state === 'terminal' ? grumpy[variant] : ordinary[state][variant];
      if (mood === 'sad') expected = expected.filter((_, index) => index % 2 === 0);
      assert.deepEqual(base.contacts.map(contact => contact.at), expected, `${SPEC}: ${mood}/${state}/${variant} has authored rhythm`);
      signatures.push(JSON.stringify(expected));
      const gain = mood === 'frightened' ? 0.68 : mood === 'sad' ? 0.62
        : mood === 'grumpy' && state === 'terminal' ? 1.12 : mood === 'happy' ? 1.05 : 1;
      const lean = mood === 'frightened' ? -0.018 : mood === 'sad' ? -0.016
        : mood === 'grumpy' && state === 'terminal' ? 0.032 : 0.018;
      near(base.lean, lean, 'representative mood posture target');
      for (const contact of base.contacts) near(contact.strength, gain, 'representative contact strength');
      for (const extreme of [0, 1]) {
        const varied = deskRecipe(state, mood, variant, () => extreme);
        for (const [i, contact] of varied.contacts.entries()) {
          near(contact.at - base.contacts[i].at, (extreme * 2 - 1) * 40, 'contact timing jitter is bounded to 40 ms');
          near(contact.strength / base.contacts[i].strength, 1 + (extreme * 2 - 1) * 0.1, 'contact gain jitter is bounded to 10%');
          assert.equal(contact.side, i % 2 ? -1 : 1, `${SPEC}: keyboard contact alternates visible sides`);
        }
      }
      assert.equal(base.duration, constants.cycleMs[variant], `${SPEC}: all variants have finite recovery boundaries`);
    }
    assert.equal(new Set(signatures).size, 3, `${SPEC}: ${mood}/${state} variants differ in rhythm, not just amplitude`);
  }
  const knocks = [[420], [420, 740], [420, 690, 960]];
  for (const variant of [0, 1, 2]) {
    const alert = alertRecipe(variant);
    assert.deepEqual(alert.contacts.map(contact => contact.at), [...knocks[variant], knocks[variant].at(-1) + 240],
      `${SPEC}: alert contact/reveal sequence is one finite entry`);
    for (const outcome of ['success', 'failure', null]) {
      const result = resultRecipe(outcome, variant);
      assert.equal(result.contacts[0].at, [680, 960, 1240][variant], `${SPEC}: result reveal timing`);
      assert.equal(result.contacts[0].kind, outcome === 'success' ? 'success_reveal' : outcome === 'failure' ? 'failure_reveal' : 'result_reveal',
        `${SPEC}: outcome chooses truthful contact/reveal family`);
    }
    for (const mood of moods) {
      const traits = sceneMoodTraits[mood], shaped = alertRecipe(variant, mood);
      const expectedKnocks = knocks[variant].map(at => knocks[variant][0] + traits.delayMs + (at - knocks[variant][0]) * traits.spacing);
      assert.deepEqual(shaped.contacts.map(contact => contact.at), [...expectedKnocks, expectedKnocks.at(-1) + 240],
        `${SPEC}: ${mood} changes alert rhythm while keeping the confirmation gap`);
      for (const contact of shaped.contacts.filter(contact => contact.kind === 'screen_knock')) {
        near(contact.strength, traits.gain, `${mood} knock force`);
      }
      for (const outcome of ['success', 'failure']) {
        const result = resultRecipe(outcome, variant, mood);
        near(result.contacts[0].at, [680, 960, 1240][variant] + traits.delayMs, `${mood} result timing`);
        near(result.contacts[0].strength, traits.gain, `${mood} result force`);
        assert.equal(result.contacts[0].kind, `${outcome}_reveal`, `${SPEC}: ${mood} never changes factual outcome`);
      }
    }
  }
  for (const reducedMotion of [false, true]) {
    const slime = createSlime({ seed: 53, catalog, reducedMotion });
    slime.setFacts({ base: 'working' }); slime.step(0);
    for (let at = STEP_MS; at <= 16000; at += STEP_MS) {
      const frame = slime.step(at).channels;
      for (const [name, spring] of Object.entries(frame.activityChannels)) {
        assert.ok(Math.abs(spring.x) <= constants.activityBounds[name] + 1e-10, `${SPEC}: combined activity displacement bound`);
        assert.ok(Math.abs(spring.v) <= constants.activityVelocity + 1e-10, `${SPEC}: activity velocity bound`);
      }
      for (const [i, value] of frame.pose.entries()) assert.ok(Math.abs(value) <= constants.poseBounds[i] + 1e-10, `${SPEC}: final composed pose clamp`);
      for (const [i, value] of frame.life.entries()) assert.ok(Math.abs(value) <= constants.lifeBounds[i] + 1e-10, `${SPEC}: final composed life clamp`);
    }
  }
  const sleepy = driver(createSlime, catalog, 'frightened');
  sleepy.slime.setFacts({ base: 'asleep' });
  let wasSleeping = sleepy.channels.face.sleeping;
  sleepy.advance(1600, frame => {
    if (!wasSleeping && frame.face.sleeping) near(frame.face.bridgeBlink, 1, 'shared sleepy primitive changes only at bridge closure');
    wasSleeping = frame.face.sleeping;
  });
  assert.ok(wasSleeping, `${SPEC}: explicit quiet face is exercised`);
  for (const [key, value] of Object.entries({ eyeOpen: 0.004, mouthWidth: 0.018, curve: 0.008, cheekAlpha: 0, tearAmount: 0 })) {
    near(sleepy.channels.face[key], value, `shared quiet target ${key}`, 1e-8);
  }
}

function checkDeskAndRecovery(createSlime, catalog) {
  const d = driver(createSlime, catalog, 'grumpy');
  d.slime.setFacts({ base: 'working' }); d.advance(640);
  const desk = d.channels.props.desk;
  assert.deepEqual({ id: desk.id, x: desk.x, y: desk.y }, { id: 'desk-1', x: 0.5, y: 0.64 },
    `${SPEC}: persistent desk anchor stays above the reserved text lane`);
  const identity = { id: desk.id, x: desk.x, y: desk.y };
  d.slime.poke(0.4, 0.2); d.step();
  for (const act of ['terminal', 'searching', 'analyzing', 'testing', 'waiting', 'planning', null]) {
    setWithoutReset(d.slime, () => d.slime.setFacts({ base: 'working', act }), `work -> ${act ?? 'working'}`);
    const current = d.step().props.desk;
    assert.deepEqual({ id: current.id, x: current.x, y: current.y }, identity, `${SPEC}: one persistent desk throughout factual work modes`);
  }
  setWithoutReset(d.slime, () => d.slime.oneShot({ id: 90, name: 'task_complete', args: { outcome: 'success', loops: 1 } }), 'completion entry');
  route(d, 'task_complete');
  d.advance(320);
  setWithoutReset(d.slime, () => d.slime.setFacts({ base: 'working', act: 'terminal' }), 'facts update during completion');
  d.advance(6400);
  assert.equal(d.channels.scene.state, 'terminal', `${SPEC}: after a moment return to latest facts, not captured facts`);
  assert.deepEqual({ id: d.channels.props.desk.id, x: d.channels.props.desk.x, y: d.channels.props.desk.y }, identity,
    `${SPEC}: completion never replaces desk identity`);
}

function checkAttention(createSlime, catalog) {
  const d = driver(createSlime, catalog, 'sad');
  d.slime.setFacts({ base: 'working' }); d.advance(640);
  const attention = { id: 777, agent: 'codex', project: 'slime', name: 'Review', more: 0 };
  setWithoutReset(d.slime, () => d.slime.setFacts({ base: 'working', attn: attention }), 'attention interruption');
  const first = route(d, 'needs_you');
  const requestId = first.scene.requestId;
  const emitted = new Set(); let contacts = 0, confirmationAt;
  d.advance(4000, frame => {
    for (const contact of frame.contacts) {
      assert.notEqual(contact.kind, 'key_contact', `${SPEC}: attention cancels future working contacts immediately`);
      assert.ok(!emitted.has(contact.id), `${SPEC}: no contact identity is emitted twice`);
      emitted.add(contact.id); contacts++;
      if (contact.kind === 'alert_reveal') {
        near(frame.props.alert.confirmation, 1, 'visible confirmation pulse begins at the reveal contact');
        confirmationAt = frame.time * 1000;
      }
    }
    if (confirmationAt !== undefined && frame.time * 1000 - confirmationAt >= 120) {
      near(frame.props.alert.confirmation, 0, 'confirmation pulse ends at 120 ms and does not repeat');
    }
  });
  assert.ok(contacts > 0, `${SPEC}: initial attention was exercised`);
  const iteration = d.channels.scene.iteration;
  for (const mood of ['happy', 'grumpy', 'frightened']) {
    setWithoutReset(d.slime, () => d.slime.setMood(mood), 'mood change under attention');
    d.slime.setFacts({ base: 'working', attn: { ...attention, name: `Renamed ${mood}`, more: 3 } });
    d.advance(800, frame => {
      assert.equal(frame.scene.requestId, requestId, `${SPEC}: name/more/mood retain attention identity`);
      assert.equal(frame.scene.iteration, iteration, `${SPEC}: alert does not repeat its entry`);
      assert.equal(frame.contacts.length, 0, `${SPEC}: a held attention sign is silent and has no replayed contacts`);
    });
  }
  d.slime.setFacts({ base: 'working', attn: { ...attention, id: 778 } });
  const next = route(d, 'needs_you');
  assert.notEqual(next.scene.requestId, requestId, `${SPEC}: new request identity starts fresh entry`);
  d.slime.setFacts({ base: 'working' }); route(d, 'working');
  d.slime.setFacts({ base: 'working', attn: { ...attention, id: 778 } });
  assert.notEqual(route(d, 'needs_you').scene.requestId, next.scene.requestId, `${SPEC}: same ID after clearing has a new activation epoch`);
  let previousRequest = d.channels.scene.requestId;
  for (const change of [{ agent: 'claude' }, { agent: 'claude', project: 'other' }]) {
    d.slime.setFacts({ base: 'working', attn: { ...attention, id: 778, ...change } });
    const changed = route(d, 'needs_you');
    assert.notEqual(changed.scene.requestId, previousRequest, `${SPEC}: agent/project are part of attention request identity`);
    previousRequest = changed.scene.requestId;
  }
}

// Alerts, taps and interruption: a request's knocks and ding play exactly once
// however it is interrupted, at whatever point. An alert left early resumes
// where it stopped; one that already signalled returns to its silent hold.
function checkAlertInterruption(createSlime, catalog) {
  const counts = frames => {
    const per = new Map();
    for (const frame of frames) for (const contact of frame.contacts) {
      const entry = per.get(contact.requestId) ?? { knocks: 0, dings: 0, variant: null };
      if (contact.kind === 'screen_knock') entry.knocks++;
      if (contact.kind === 'alert_reveal') entry.dings++;
      if (frame.scene.requestId === contact.requestId) entry.variant = frame.scene.variant;
      per.set(contact.requestId, entry);
    }
    return per;
  };
  const script = readScript(path.join(root, 'scripts/alert-interrupted.jsonl'));
  const played = runScript(createSlime, catalog, script, 53);
  const requests = counts(played.frames);
  assert.equal(requests.size, 4, `${SPEC}: the interruption script raises four requests`);
  for (const [requestId, entry] of requests) {
    assert.equal(entry.knocks, entry.variant + 1, `${SPEC}: ${requestId} knocks once each, never zero or twice`);
    assert.equal(entry.dings, 1, `${SPEC}: ${requestId} confirms exactly once`);
  }
  assert.equal(played.cues.filter(({ cue }) => cue.recipe === 'ding').length, 4, `${SPEC}: one ding per interrupted request`);
  for (const interrupt of ['listening', 'timeout']) for (const after of [0, 160, 320, 480, 640, 800, 1200, 2000]) {
    const d = driver(createSlime, catalog, 'sad'), frames = [];
    d.slime.setFacts({ base: 'working', attn: { id: 30 + after, agent: 'codex', project: 'interrupt' } });
    d.advance(after, frame => frames.push(frame));
    if (interrupt === 'listening') d.slime.oneShot({ id: `mic-${after}`, name: 'listening' }); else d.slime.setLinkTimedOut(true);
    d.advance(640, frame => frames.push(frame));
    if (interrupt === 'listening') d.slime.oneShot({ id: `mic-${after}-stop`, name: 'stop_listening' }); else d.slime.setLinkTimedOut(false);
    d.advance(4800, frame => frames.push(frame));
    const [entry] = counts(frames).values();
    assert.ok(entry, `${SPEC}: an alert interrupted after ${after} ms still signals`);
    assert.equal(entry.knocks, entry.variant + 1, `${SPEC}: ${interrupt} after ${after} ms keeps every knock exactly once`);
    assert.equal(entry.dings, 1, `${SPEC}: ${interrupt} after ${after} ms keeps exactly one confirmation`);
  }
}

function checkQuietAndTimeout(createSlime, catalog) {
  const d = driver(createSlime, catalog, 'frightened');
  d.slime.setFacts({ base: 'working' }); d.slime.perform(0); d.advance(160);
  setWithoutReset(d.slime, () => d.slime.setFacts({ base: 'asleep' }), 'asleep interruption');
  const quietCount = d.slime.inspect().performanceCount;
  d.advance(60000, frame => {
    assert.equal(frame.scene.state, 'asleep'); assert.ok(frame.scene.quiet);
    assert.equal(frame.mood, 'frightened', `${SPEC}: rest preserves stored mood`);
    assert.equal(frame.performance, null, `${SPEC}: rest suppresses acting recipes`);
    assert.equal(frame.performanceCount, quietCount, `${SPEC}: no hidden acting scheduler runs during rest`);
    assert.equal(frame.contacts.length, 0, `${SPEC}: no contacts during quiet rest`);
  });
  d.slime.setFacts({ base: 'working' }); d.advance(32000);
  assert.equal(d.channels.scene.state, 'working', `${SPEC}: elapsed wall/presentation time cannot infer device no_app timeout`);
  setWithoutReset(d.slime, () => d.slime.setLinkTimedOut(true), 'explicit link timeout');
  route(d, 'no_app');
  d.slime.setFacts({ base: 'working', act: 'terminal' });
  d.advance(320, frame => assert.equal(frame.scene.state, 'no_app', `${SPEC}: facts cannot clear explicit link timeout`));
  d.slime.setLinkTimedOut(false); route(d, 'terminal', 'restored link returns to latest facts');
  const elapsed = driver(createSlime, catalog);
  elapsed.slime.setFacts({ base: 'working' });
  elapsed.slime.oneShot({ id: 900, name: 'task_complete', args: { outcome: 'success' } });
  route(elapsed, 'task_complete');
  elapsed.slime.setLinkTimedOut(true); elapsed.advance(6400);
  elapsed.slime.setLinkTimedOut(false);
  route(elapsed, 'working', 'a moment whose own lifetime elapsed during timeout does not resurrect');
}

function checkContactInterruption(createSlime, catalog) {
  const d = driver(createSlime, catalog);
  d.slime.setFacts({ base: 'working' }); d.step();
  d.slime.dragStart([0.2, 0.3]); d.slime.dragMove([0.3, 0.2, 0]);
  d.advance(2800, frame => assert.equal(frame.contacts.length, 0, `${SPEC}: drag owns the contact patch`));
  d.slime.dragEnd();
  d.advance(160, frame => assert.equal(frame.contacts.length, 0, `${SPEC}: release never replays elapsed contacts`));
  const finish = driver(createSlime, catalog);
  finish.slime.setFacts({ base: 'working' });
  finish.slime.oneShot({ id: 901, name: 'task_complete', args: { outcome: 'success' } });
  finish.advance(160); // Before every authored reveal, while velocity is alive.
  const oldRequest = finish.channels.scene.requestId;
  setWithoutReset(finish.slime, () => finish.slime.setFacts({ base: 'working', attn: { id: 902, agent: 'codex', project: 'slime' } }),
    'attention interrupts result');
  finish.advance(4800, frame => {
    assert.equal(frame.scene.state, 'needs_you');
    assert.ok(!frame.props.result.trophy, `${SPEC}: attention removes interrupted completion decoration`);
    for (const contact of frame.contacts) assert.notEqual(contact.requestId, oldRequest, `${SPEC}: interrupted result cannot reveal later`);
  });
  for (const outcome of ['success', 'failure']) {
    const grabbed = driver(createSlime, catalog, 'frightened');
    grabbed.slime.setFacts({ base: 'working' });
    grabbed.slime.oneShot({ id: 910, name: 'task_complete', args: { outcome } });
    grabbed.slime.dragStart([0.2, 0.3]); grabbed.slime.dragMove([0.3, 0.2, 0]);
    let reveals = 0, visible = false;
    grabbed.advance(2400, frame => {
      visible ||= frame.props.result.visible;
      if (frame.props.result.visible) assert.equal(frame.props.result.outcome, outcome, `${SPEC}: drag retains truthful result card`);
      for (const contact of frame.contacts) {
        assert.ok(contact.kind.endsWith('_reveal'), `${SPEC}: drag suppresses physical contacts while preserving factual reveal`);
        reveals++;
      }
    });
    assert.ok(visible, `${SPEC}: holding the actor cannot hide a real ${outcome} result`);
    assert.equal(reveals, 1, `${SPEC}: factual ${outcome} reveal occurs once while held`);
    grabbed.slime.dragEnd();
    grabbed.advance(320, frame => assert.equal(frame.contacts.length, 0, `${SPEC}: released result does not replay elapsed reveal`));
  }
}

function checkLongWork(createSlime, catalog) {
  const d = driver(createSlime, catalog, 'happy');
  d.slime.setFacts({ base: 'working' });
  let previousVariant, previousIteration;
  const variants = new Set(), contactIds = new Set();
  let iterations = 0, contacts = 0;
  d.advance(600000, frame => {
    assert.equal(frame.scene.state, 'working', `${SPEC}: ten-minute working state remains factual`);
    assert.equal(frame.props.desk.id, 'desk-1', `${SPEC}: ten-minute desk persists`);
    assert.equal(frame.mood, 'happy', `${SPEC}: animation never selects a new mood`);
    assert.ok([0, 1, 2].includes(frame.scene.variant), `${SPEC}: exactly three authored state variants`);
    if (frame.scene.iteration !== previousIteration) {
      if (previousIteration !== undefined) assert.notEqual(frame.scene.variant, previousVariant, `${SPEC}: no immediate variation repeat`);
      previousIteration = frame.scene.iteration; previousVariant = frame.scene.variant;
      variants.add(frame.scene.variant); iterations++;
    }
    for (const contact of frame.contacts) {
      assert.ok(!contactIds.has(contact.id), `${SPEC}: contact identity survives long-running iteration counters`);
      contactIds.add(contact.id); contacts++;
    }
    for (const group of [frame.modes, frame.actorChannels, frame.activityChannels]) for (const spring of Object.values(group ?? {})) {
      assert.ok(Number.isFinite(spring.x) && Number.isFinite(spring.v), `${SPEC}: long-run springs stay finite`);
    }
  });
  assert.deepEqual([...variants].sort(), [0, 1, 2], `${SPEC}: all three work rhythms exercised`);
  assert.ok(iterations > 3 && contacts > iterations, `${SPEC}: sustained work really exercises repeated choreography`);
  return { iterations, contacts };
}

export async function checkScenes({ coverageOnly = false } = {}) {
  const coverage = await checkRepresentative();
  const matrix = await checkFullMatrix();
  coverage.cells = matrix.cells;
  smooth.finish();
  if (coverageOnly) return coverage;
  const createSlime = await loadEngine(), catalog = loadCatalog();
  checkRouting(createSlime, catalog);
  await checkSceneConstants(createSlime, catalog);
  checkDeskAndRecovery(createSlime, catalog);
  checkAttention(createSlime, catalog);
  checkAlertInterruption(createSlime, catalog);
  checkQuietAndTimeout(createSlime, catalog);
  checkContactInterruption(createSlime, catalog);
  const longWork = checkLongWork(createSlime, catalog);
  smooth.finish();
  return { status: 'FULL SCENE MATRIX PASS', cases: coverage.cases.length, cells: coverage.cells.length, smoothness: smooth.summary(),
    traceFrames: representativeCases.length * CASE_MS / STEP_MS + 1, matrixFrames: matrix.frames,
    activeVariants: matrix.variants, factualCases: matrix.factCases, quietAliases: matrix.quietAliases, longWork,
    ownerReview: 'Representative art approved at Q1; full matrix has executed engineering evidence',
    scope: '42 canonical moods × 23 factual states; sound, graph bridges and production ports checked separately' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--help') {
    console.log('node tools/check-scenes.mjs [--coverage]\nChecks all 966 Phase 2 cells, active variants, factual contexts/outcomes and routing invariants.\n--coverage executes the full matrix, then prints {cases:24 representative reviews,cells:966 verified cells} for the builder.');
  } else if (args.length > 0 && !(args.length === 1 && args[0] === '--coverage')) {
    console.error('Unknown arguments; use --help'); process.exitCode = 1;
  } else {
    checkScenes({ coverageOnly: args.includes('--coverage') }).then(result => console.log(JSON.stringify(result)))
      .catch(error => { console.error(error); process.exitCode = 1; });
  }
}
