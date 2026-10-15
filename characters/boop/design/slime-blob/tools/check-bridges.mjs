#!/usr/bin/env node
// Executed directed-edge evidence. Host pacing and evidence admission remain
// separate; these checks authorize no autonomous mood changes or audio cues.
import assert from 'node:assert/strict';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { root, STEP_MS, loadCatalog, loadEngine, readScript, runScript } from './trace.mjs';
import { createSmoothness, tracked, faceAlpha, SMOOTH_SPEC } from './smooth.mjs';

const SPEC = 'CONTINUITY.md, Directed edge bridges';
// Every edge run's frames, against the bounds on what is drawn.
const smooth = createSmoothness('directed bridges');
const SCRIPT = 'scripts/edge-review.jsonl';
const catalog = loadCatalog();
const graph = catalog.graph;
const graphEdges = Object.entries(graph.nodes).flatMap(([from, node]) => ['ordinary', 'dramatic'].flatMap(category =>
  node[category].map(to => ({ id: `${from}->${to}`, from, to, category }))));
const selectedPairs = [['calm', 'curious'], ['happy', 'excited'], ['grumpy', 'sad'], ['sad', 'crying'],
  ['frightened', 'relieved'], ['uneasy', 'frightened'], ['proud', 'wounded'], ['calm', 'surprised'],
  ['scared', 'frightened'], ['frightened', 'scared'], ['crying', 'sad'], ['wounded', 'calm'], ['calm', 'comfy']];
export const bridgeReviewCases = selectedPairs.map(([from, to], index) => {
  const edge = graphEdges.find(edge => edge.from === from && edge.to === to);
  assert.ok(edge, `${SPEC}: review case must be a real directed edge`);
  return { id: `edge.${from}-to-${to}`, from, to, category: edge.category, script: SCRIPT,
    bridgeVariant: index % 3, startMs: index * 6400, endMs: (index + 1) * 6400, retargetMs: 1600 };
});
const semanticKeys = ['eyeX', 'eyeY', 'eyeOpen', 'mouthY', 'mouthWidth', 'curve', 'cheekAlpha', 'tearAmount'];
const controls = face => Object.fromEntries(semanticKeys.map(key => [key, face[key]]));
const physical = state => structuredClone({ modes: state.modes, actorChannels: state.actorChannels,
  activityChannels: state.activityChannels, bridgeChannels: state.bridgeChannels, pull: state.grab.pull,
  pose: state.pose, life: state.life, face: controls(state.face), artId: state.face.artId, closure: state.face.bridgeBlink });
const round = number => Number(number.toFixed(7));
function near(actual, expected, message, epsilon = 1e-10) {
  assert.ok(Number.isFinite(actual) && Math.abs(actual - expected) <= epsilon, `${SPEC}: ${message}: ${actual} != ${expected}`);
}
function makeDriver(createSlime, { seed = 53, reducedMotion = false } = {}) {
  let event = false;
  const slime = tracked(createSlime({ seed, catalog, reducedMotion }), () => { event = true; });
  const observe = smooth.run();
  let at = 0, frame = slime.step(0).channels, frames = 1;
  observe(frame, event); event = false;
  return { slime, get at() { return at; }, get frame() { return frame; }, get frames() { return frames; },
    step() { at += STEP_MS; const output = slime.step(at); frame = output.channels; frames++;
      observe(frame, event); event = false;
      assert.ok(output.cues.every(cue=>frame.contacts.some(contact=>contact.id===cue.contactId)), `${SPEC}: bridges cannot create sound without a visible contact`); return frame; },
    advance(ms, visit = () => {}) { for (let elapsed = 0; elapsed < ms; elapsed += STEP_MS) visit(this.step()); return frame; } };
}
function prepare(d, from, gesture = 0) {
  d.slime.setFacts({ base: 'idle' }); d.slime.setMood(from); d.advance(1600);
  d.slime.perform(gesture); d.advance(512);
  assert.equal(d.frame.performance.index, gesture, `${SPEC}: each edge starts in an authored gesture`);
}
function retarget(d, edge, variant) {
  const before = d.slime.inspect();
  d.slime.setMood(edge.to, { bridgeVariant: variant });
  const after = d.slime.inspect();
  assert.deepEqual(physical(after), physical(before), `${SPEC}: ${edge.id}/${variant} preserves every live spring, face control and composed pose at retarget`);
  near(after.time, before.time, `${edge.id} cannot reset the animation clock`);
  return { before, after };
}
function validateFrame(frame, previous, endpoints, constants, label) {
  for (const key of semanticKeys) {
    const lower = Math.min(endpoints.from[key], endpoints.to[key]), upper = Math.max(endpoints.from[key], endpoints.to[key]);
    assert.ok(frame.face[key] >= lower - 1e-10 && frame.face[key] <= upper + 1e-10,
      `${SPEC}: ${label} ${key} remains between actual source controls and destination`);
  }
  for (const key of ['blink', 'bridgeBlink', 'cheekAlpha', 'tearAmount']) {
    assert.ok(frame.face[key] >= 0 && frame.face[key] <= 1, `${SPEC}: ${label} ${key} stays in [0,1]`);
  }
  assert.equal(typeof frame.face.artId, 'string', `${SPEC}: ${label} has exactly one art identity`);
  assert.equal(typeof frame.face.art.eyes, 'string', `${SPEC}: ${label} has one eye primitive`);
  assert.equal(typeof frame.face.art.mouth, 'string', `${SPEC}: ${label} has one mouth primitive`);
  assert.ok(!('weights' in frame.face), `${SPEC}: ${label} cannot crossfade facial silhouettes`);
  if (frame.face.artId !== previous.face.artId) near(frame.face.bridgeBlink, 1, `${label} changes art only behind closed lids`);
  for (const [name, spring] of Object.entries(frame.bridgeChannels)) {
    assert.ok(Math.abs(spring.x) <= constants.bounds[name] + 1e-12, `${SPEC}: ${label} ${name} stays inside its displacement bound`);
    assert.ok(Math.abs(spring.v) <= constants.velocityBound + 1e-12, `${SPEC}: ${label} ${name} stays inside its velocity bound`);
  }
  for (const [index, bound] of [1.25, 1.32, 1.14, 0.72].entries()) {
    assert.ok(Number.isFinite(frame.pose[index]) && Math.abs(frame.pose[index]) <= bound + 1e-12, `${SPEC}: ${label} composed pose remains bounded`);
  }
}
function zeroTargetStep(springs, constants) {
  return Object.fromEntries(Object.entries(springs).map(([name, spring]) => {
    let { x, v } = spring, remaining = STEP_MS / 1000;
    while (remaining > 0) { const h = Math.min(remaining, 1 / 240); v += (-(constants.frequency ** 2) * x - constants.damping * v) * h; x += v * h; remaining -= h; }
    return [name, { x: Math.max(-constants.bounds[name], Math.min(constants.bounds[name], x)), v: Math.max(-constants.velocityBound, Math.min(constants.velocityBound, v)) }];
  }));
}
function assertQuietIntegration(d, duration, constants, label) {
  let previous = d.slime.inspect().bridgeChannels;
  d.advance(duration, frame => {
    const expected = zeroTargetStep(previous, constants);
    for (const key of Object.keys(expected)) for (const axis of ['x', 'v']) near(frame.bridgeChannels[key][axis], expected[key][axis], `${label}: suppressed bridge ${key}.${axis}`);
    previous = frame.bridgeChannels;
  });
}

async function checkConstants(createSlime, bridgeModule) {
  const { bridgeConstants: constants, bridgeTarget, bridgeDirection, createBridges, amplitudeLimit } = bridgeModule;
  // Every primitive at its largest amplitude stays inside each channel's
  // displacement bound; only the dramatic compression needs the limit.
  for (const [primitive, variant, category] of [['soft-retarget', 0, 'ordinary'], ['gather-settle', 1, 'ordinary'],
    ['blink-retarget', 2, 'ordinary'], ['blink-retarget', 2, 'dramatic'], ['recoil-compress', 0, 'dramatic'], ['recoil-compress', 1, 'dramatic']]) {
    const amplitude = Math.min(1.2, amplitudeLimit(primitive, variant, category));
    for (let progress = 0; progress <= 1; progress += 1 / 512) for (const direction of [-1, 1]) {
      for (const [name, value] of Object.entries(bridgeTarget(primitive, variant, category, progress, direction, amplitude))) {
        assert.ok(Math.abs(value) <= constants.bounds[name] + 1e-12, `${SPEC}: ${primitive}/${variant} ${name} target stays inside its bound`);
      }
    }
  }
  near(amplitudeLimit('recoil-compress', 1, 'dramatic'), 0.05 / 0.048, 'the compression squash limits its amplitude to 0.05 / 0.048');
  assert.ok(amplitudeLimit('recoil-compress', 0, 'dramatic') > 1.2, `${SPEC}: the recoil's own coefficients already fit at 1.2`);
  assert.deepEqual(constants, {
    durationsMs: { ordinary: [420, 680, 360], dramatic: [760, 920, 560] },
    frequency: 14, damping: 12, velocityBound: 1, reducedGain: 0.18, dragDeferMs: 320,
    bounds: { lean: 0.06, squash: 0.05, forward: 0.04 },
    faceDurationMs: { ordinary: [180, 180, 260], dramatic: [220, 240, 280] },
  }, `${SPEC}: bridge timing, spring limits, face durations and drag deferral are pinned`);
  const targets = [
    ['soft-retarget', 0, 'ordinary', 0.5, [0.009, 0.004, 0.003]],
    ['gather-settle', 1, 'ordinary', 0.5, [0.026, -0.032, 0]],
    ['gather-settle', 1, 'ordinary', 0.25, [0.013, -0.016, 0.006]],
    ['blink-retarget', 2, 'ordinary', 0.25, [0, 0, 0]],
    ['blink-retarget', 2, 'ordinary', 0.625, [0.006, -0.014, -0.004]],
    ['blink-retarget', 2, 'dramatic', 0.625, [0.026, -0.035, -0.014]],
    ['recoil-compress', 0, 'dramatic', 0.25, [-0.0225, -0.019, -0.016]],
    ['recoil-compress', 1, 'dramatic', 0.25, [0.011, -0.024, 0.013]],
  ];
  for (const [primitive, variant, category, progress, expected] of targets) for (const direction of [-1, 0, 1]) {
    for (const amplitude of [0.8, 1, 1.2]) {
      const actual = bridgeTarget(primitive, variant, category, progress, direction, amplitude);
      for (const [index, key] of ['lean', 'squash', 'forward'].entries()) near(actual[key], expected[index] * amplitude * (index === 0 ? direction : 1),
        `${primitive}/${variant} ${key} authored waveform, direction and amplitude`);
      for (const boundary of [-1, 0, 1, 2]) for (const value of Object.values(bridgeTarget(primitive, variant, category, boundary, direction, amplitude))) {
        near(value, 0, `${primitive}/${variant} clamps progress and has no boundary impulse`);
      }
    }
  }
  const score = (-0.016 - 0.014) + (0.62 - 1.05) * 0.025 + (0 - 160) / 10000
    + (0.077 - 0.046) * 0.01 + (0.035 - 0.076) * 0.005;
  const direction = bridgeDirection(catalog.expressions.happy, catalog.expressions.sad);
  assert.equal(direction.direction, Math.sign(score), `${SPEC}: authored direction uses posture, energy, delay and face dimensions`);
  near(direction.amplitude, 0.8 + Math.abs(score) * 4, 'bridge direction amplitude formula');
  assert.deepEqual(bridgeDirection(catalog.expressions.calm, catalog.expressions.calm), { direction: 0, amplitude: 0.8 },
    `${SPEC}: equivalent endpoints have no arbitrary left/right sign`);
  for (const edge of graphEdges) {
    const forward = bridgeDirection(catalog.expressions[edge.from], catalog.expressions[edge.to]);
    const reverse = bridgeDirection(catalog.expressions[edge.to], catalog.expressions[edge.from]);
    assert.equal(forward.direction, -reverse.direction || 0, `${SPEC}: reversing an authored edge reverses its directional intent`);
    near(forward.amplitude, reverse.amplitude, 'reverse direction keeps its amplitude');
    assert.ok(forward.amplitude >= 0.8 && forward.amplitude <= 1.2, `${SPEC}: bridge amplitude is bounded`);
  }
  const make = reducedMotion => createBridges({ graph, profiles: catalog.expressions, rand: () => 0.5, reduced: { matches: reducedMotion } });
  const numeric = make(false); numeric.retarget('calm', 'curious', 0, { bridgeVariant: 1 });
  const initial = numeric.inspect().bridge;
  const target = bridgeTarget(initial.primitive, initial.variant, initial.category, 16 / initial.durationMs, initial.direction, initial.amplitude);
  numeric.advance(0.016);
  for (const [name, force] of Object.entries(target)) {
    let x = 0, v = 0, remaining = 0.016;
    while (remaining > 0) { const h = Math.min(remaining, 1 / 240); v += (196 * (force - x) - 12 * v) * h; x += v * h; remaining -= h; }
    near(numeric.inspect().bridgeChannels[name].x, x, 'bridge displacement follows its 14/12 spring with 1/240 s substeps');
    near(numeric.inspect().bridgeChannels[name].v, v, 'bridge velocity follows its 14/12 spring with 1/240 s substeps');
  }
  const bounded = make(false);
  for (const spring of Object.values(bounded.channels)) spring.v = 100;
  bounded.advance(0.016);
  for (const [name, spring] of Object.entries(bounded.inspect().bridgeChannels)) {
    near(spring.x, constants.bounds[name], 'bridge displacement cap applies after integration');
    near(spring.v, 1, 'bridge velocity cap applies after integration');
  }
  const ordinary = make(false), dramatic = make(false), reduced = make(true);
  ordinary.retarget('calm', 'curious', 0, { bridgeVariant: 1 });
  dramatic.retarget('calm', 'surprised', 0, { bridgeVariant: 1 });
  reduced.retarget('calm', 'surprised', 0, { bridgeVariant: 1 });
  let normalPeak = 0, dramaticPeak = 0;
  for (let at = 16; at <= 1008; at += 16) {
    for (const bridge of [ordinary, dramatic, reduced]) bridge.advance(0.016);
    const a = ordinary.inspect(), b = dramatic.inspect(), c = reduced.inspect();
    normalPeak = Math.max(normalPeak, Math.abs(a.bridgeChannels.squash.x));
    dramaticPeak = Math.max(dramaticPeak, Math.abs(b.bridgeChannels.squash.x));
    for (const name of Object.keys(b.bridgeChannels)) for (const axis of ['x', 'v']) near(c.bridgeChannels[name][axis], b.bridgeChannels[name][axis] * 0.18,
      `reduced motion scales actual ${name}.${axis}, not just a descriptor`);
  }
  assert.ok(dramaticPeak > normalPeak * 1.2, `${SPEC}: a dramatic recoil has a materially stronger body compression than ordinary gathering`);
  ordinary.setContext({ grabActive: true });
  for (let count = 0; count < 24; count++) ordinary.advance(0.016);
  assert.equal(ordinary.inspect().bridge.phase, 'settled', `${SPEC}: grabbing after completion cannot defer an already consumed bridge`);
  assert.equal(ordinary.inspect().bridge.deferred, false, `${SPEC}: a settled bridge has no deferred body action`);
  assert.equal(ordinary.inspect().bridge.expired, false, `${SPEC}: a later grab cannot relabel a settled bridge as expired`);
  const drag = make(false); drag.setContext({ grabActive: true }); drag.retarget('calm', 'surprised', 0, { bridgeVariant: 1 });
  for (let count = 0; count < 19; count++) drag.advance(0.016);
  assert.equal(drag.inspect().bridge.expired, false, `${SPEC}: a 304 ms grab is still inside the 320 ms defer window`);
  near(drag.inspect().bridge.elapsedMs, 0, 'drag freezes the pending bridge progress');
  drag.advance(0.016);
  assert.equal(drag.inspect().bridge.expired, true, `${SPEC}: a 320 ms grab expires the old body gesture`);
  drag.setContext({ grabActive: false }); drag.advance(0.016);
  assert.ok(Object.values(drag.inspect().bridgeChannels).every(spring => spring.x === 0 && spring.v === 0), `${SPEC}: expired drag release has no bridge impulse backlog`);
  const early = make(false); early.setContext({ grabActive: true }); early.retarget('calm', 'surprised', 0, { bridgeVariant: 1 });
  for (let count = 0; count < 10; count++) early.advance(0.016);
  early.setContext({ grabActive: false }); early.advance(0.016);
  near(early.inspect().bridge.elapsedMs, 16, 'early drag release starts at elapsed bridge time, without catching up');
  early.setContext({ grabActive: true });
  for (let count = 0; count < 10; count++) early.advance(0.016);
  assert.equal(early.inspect().bridge.expired, true, `${SPEC}: separate grabs consume the same cumulative 320 ms deferral budget`);
  const invalid = makeDriver(createSlime), snapshot = physical(invalid.slime.inspect());
  for (const value of [-1, 3, 1.5, NaN]) assert.throws(() => invalid.slime.setMood('curious', { bridgeVariant: value }), RangeError,
    `${SPEC}: invalid explicit variant is refused`);
  assert.deepEqual(physical(invalid.slime.inspect()), snapshot, `${SPEC}: rejected variant leaves the actor untouched`);
  const shuffled = make(false), selections = new Map(graphEdges.map(edge => [edge.id, []]));
  for (let round = 0; round < 6; round++) for (const edge of graphEdges) {
    shuffled.retarget(edge.from, edge.to, round * 1000);
    selections.get(edge.id).push(shuffled.inspect().bridge.variant);
  }
  for (const [id, variants] of selections) {
    for (let offset = 0; offset < 6; offset += 3) assert.deepEqual(variants.slice(offset, offset + 3).sort(), [0, 1, 2],
      `${SPEC}: ${id} consumes its own directed three-variant bag`);
    for (let index = 1; index < variants.length; index++) assert.notEqual(variants[index], variants[index - 1],
      `${SPEC}: ${id} does not immediately repeat across bag boundaries`);
  }
}

function checkRapidRetarget(createSlime, constants) {
  let frames = 0;
  for (const reducedMotion of [false, true]) {
    const d = makeDriver(createSlime, { reducedMotion });
    let switches = 0, endpoints, previous;
    const observe = frame => {
      validateFrame(frame, previous, endpoints, constants, 'rapid retarget');
      if (frame.face.artId !== previous.face.artId) switches++;
      previous = frame;
    };
    for (const [index, to] of ['curious', 'surprised', 'frightened', 'sad', 'happy', 'wounded', 'angry'].entries()) {
      const { before, after } = retarget(d, { id: `rapid-${to}`, to }, index % 3);
      assert.deepEqual(after.face.transition.from, controls(before.face), `${SPEC}: rapid retarget starts from actual current controls`);
      // Each control keeps its velocity across a retarget, so a rapid chain
      // stays within the span of everything it started from or was asked for.
      const span = [controls(before.face), after.face.transition.to, ...(endpoints ? [endpoints.from, endpoints.to] : [])];
      endpoints = { from: Object.fromEntries(semanticKeys.map(key => [key, Math.min(...span.map(value => value[key]))])),
        to: Object.fromEntries(semanticKeys.map(key => [key, Math.max(...span.map(value => value[key]))])) };
      previous = before;
      d.advance(48, observe);
    }
    d.advance(1024, observe);
    assert.ok(switches > 0, `${SPEC}: rapid retarget test really observes a fully closed primitive switch`);
    assert.equal(d.frame.face.artId, 'angry', `${SPEC}: the last rapid request wins`);
    frames += d.frames;
  }
  return frames;
}

function checkContext(createSlime, edge, index, constants) {
  let frames = 0;
  for (const context of ['rest', 'drag']) {
    const d = makeDriver(createSlime); prepare(d, edge.from);
    if (context === 'rest') d.slime.setFacts({ base: 'asleep' });
    else { d.slime.dragStart([0.2, 0.3]); d.slime.dragMove([0.15, 0.1, 0]); }
    d.advance(320);
    retarget(d, edge, index % 3);
    const identity = d.slime.inspect().scene.requestId;
    assertQuietIntegration(d, 1280, constants, `${edge.id} ${context}`);
    assert.equal(d.frame.scene.requestId, identity, `${SPEC}: ${edge.id} cannot disturb ${context} factual identity`);
    if (context === 'rest') { assert.equal(d.frame.face.sleeping, true, `${SPEC}: rest keeps the shared closed face`); d.slime.setFacts({ base: 'idle' }); }
    else { assert.equal(d.frame.bridge.expired, true, `${SPEC}: long drag expires the body bridge`); d.slime.dragEnd(); }
    assertQuietIntegration(d, 480, constants, `${edge.id} after ${context}`);
    assert.equal(d.frame.mood, edge.to, `${SPEC}: suppressing body action does not discard the host's target mood`);
    frames += d.frames;
  }
  const subject = makeDriver(createSlime), baseline = makeDriver(createSlime);
  for (const d of [subject, baseline]) {
    prepare(d, edge.from);
    d.slime.setFacts({ base: 'working', attn: { id: 99, agent: 'codex', project: 'bridge' } }); d.advance(96);
  }
  const identity = subject.frame.scene.requestId;
  retarget(subject, edge, index % 3);
  let reveals = 0, previousBridge = subject.slime.inspect().bridgeChannels;
  for (let time = 0; time < 4800; time += STEP_MS) {
    const frame = subject.step(), expected = baseline.step();
    const settled = zeroTargetStep(previousBridge, constants);
    for (const name of Object.keys(settled)) for (const axis of ['x', 'v']) near(frame.bridgeChannels[name][axis], settled[name][axis],
      `${edge.id}: attention suppresses decorative bridge ${name}.${axis}`);
    previousBridge = frame.bridgeChannels;
    assert.equal(frame.scene.requestId, identity, `${SPEC}: ${edge.id} preserves pending alert identity`);
    assert.deepEqual(frame.contacts, expected.contacts, `${SPEC}: ${edge.id} cannot cancel, delay or repeat the factual alert contacts`);
    reveals += frame.contacts.filter(contact => contact.kind === 'alert_reveal').length;
  }
  assert.equal(reveals, 1, `${SPEC}: ${edge.id} retains exactly one alert confirmation`);
  subject.slime.setFacts({ base: 'idle' });
  assertQuietIntegration(subject, 480, constants, `${edge.id} after attention`);
  return frames + subject.frames + baseline.frames;
}

async function checkReviewScript(createSlime) {
  const script = readScript(path.join(root, SCRIPT));
  assert.equal(bridgeReviewCases.length, 13, `${SPEC}: bounded review set size`);
  assert.equal(script.durationMs, 13 * 6400, `${SPEC}: review windows match the recorder`);
  const result = runScript(createSlime, catalog, script, 53);
  // Continuity of what is drawn: the painter draws the eyes and mouth at full
  // opacity through every bridge; only their scale closes and reopens.
  for (const [index, frame] of result.frames.entries()) {
    assert.equal(faceAlpha(frame, catalog), 1, `${SMOOTH_SPEC}: the face never fades during a bridge (frame ${index})`);
  }
  for (const sample of bridgeReviewCases) {
    const frame = result.frames[(sample.startMs + sample.retargetMs) / STEP_MS];
    assert.equal(frame.mood, sample.to, `${SPEC}: review script actually retargets ${sample.id}`);
    assert.equal(frame.bridge.edgeId, `${sample.from}->${sample.to}`, `${SPEC}: review script exercises the selected directed edge`);
    assert.equal(frame.bridge.from, sample.from, `${SPEC}: review script retains its declared source`);
    assert.equal(frame.bridge.to, sample.to, `${SPEC}: review script retains its declared destination`);
    assert.equal(frame.bridge.variant, sample.bridgeVariant, `${SPEC}: review script plays the selected bridge variant`);
    assert.equal(frame.bridge.category, sample.category, `${SPEC}: review script keeps graph edge category`);
  }
  return result.frames.length;
}

export async function checkBridges({ coverageOnly = false } = {}) {
  const createSlime = await loadEngine();
  const bridgeModule = await import('../engine/bridges.mjs');
  const { bridgePlan, bridgeConstants, amplitudeLimit } = bridgeModule;
  await checkConstants(createSlime, bridgeModule);
  const plan = bridgePlan(graph);
  assert.equal(graphEdges.length, 295, `${SPEC}: complete directed edge count`);
  assert.equal(graphEdges.filter(edge => edge.category === 'ordinary').length, 224, `${SPEC}: ordinary directed edges`);
  assert.equal(graphEdges.filter(edge => edge.category === 'dramatic').length, 71, `${SPEC}: dramatic directed edges`);
  assert.deepEqual(plan.map(({ id, from, to, category }) => ({ id, from, to, category })), graphEdges, `${SPEC}: bridge plan matches the canonical directed graph exactly`);
  for (const edge of plan) assert.deepEqual(edge.primitives, edge.category === 'ordinary'
    ? ['soft-retarget', 'gather-settle', 'blink-retarget'] : ['recoil-compress', 'recoil-compress', 'blink-retarget'],
  `${SPEC}: ${edge.id} preserves its authored ordinary/dramatic primitive family`);
  const verified = [];
  let frames = checkRapidRetarget(createSlime, bridgeConstants);
  for (const [index, edge] of plan.entries()) {
    const signatures = [];
    for (let variant = 0; variant < 3; variant++) {
      const d = makeDriver(createSlime); prepare(d, edge.from, variant);
      const { before, after } = retarget(d, edge, variant);
      const bridge = after.bridge;
      assert.equal(bridge.variant, variant, `${SPEC}: selected variant is honored for ${edge.id}`);
      assert.equal(bridge.primitive, edge.primitives[variant], `${SPEC}: ${edge.id} uses its advertised runtime primitive`);
      assert.equal(bridge.category, edge.category, `${SPEC}: edge direction retains its category`);
      assert.equal(after.face.transition.durationMs, bridgeConstants.faceDurationMs[edge.category][variant], `${SPEC}: each primitive uses its authored closure duration`);
      assert.ok(bridge.amplitude <= amplitudeLimit(bridge.primitive, bridge.variant, bridge.category) + 1e-12,
        `${SPEC}: ${edge.id}/${variant} amplitude keeps every target inside its bound`);
      const endpoints = { from: controls(before.face), to: after.face.transition.to };
      const samples = Array(16).fill(null); let previous = before;
      d.advance(bridge.durationMs + 320, frame => {
        validateFrame(frame, previous, endpoints, bridgeConstants, edge.id);
        const age = frame.bridge.elapsedMs;
        const bin = Math.min(15, Math.max(0, Math.floor(age / bridge.durationMs * 16)));
        if (samples[bin] === null) samples[bin] = [...Object.values(frame.bridgeChannels).map(spring => round(spring.x)), ...semanticKeys.map(key => round(frame.face[key]))];
        previous = frame;
      });
      assert.equal(d.frame.face.artId, edge.to, `${SPEC}: ${edge.id} reaches the destination face`);
      assert.equal(d.frame.mood, edge.to, `${SPEC}: bridge execution never chooses another mood`);
      assert.ok(samples.every(sample => sample !== null), `${SPEC}: ${edge.id} covers all normalized bridge phases`);
      signatures.push(JSON.stringify(samples)); frames += d.frames;
    }
    assert.equal(new Set(signatures).size, 3, `${SPEC}: ${edge.id} has three actual motion/face timing signatures`);
    frames += checkContext(createSlime, edge, index, bridgeConstants);
    verified.push({ id: edge.id, primitives: [...edge.primitives] });
  }
  const reviewFrames = await checkReviewScript(createSlime);
  smooth.finish();
  const coverage = { edges: verified, cases: bridgeReviewCases };
  if (coverageOnly) return coverage;
  return { status: 'DIRECTED BRIDGES PASS', smoothness: smooth.summary(), edges: verified.length, variants: verified.length * 3, contextCases: verified.length * 3, frames, reviewFrames,
    cases: bridgeReviewCases.length, scope: 'Executed visual bridges only; host evidence/pacing and audio checks remain separate' };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--help') {
    console.log('node tools/check-bridges.mjs [--coverage]\nExercises all 295 directed mood edges and all three visual bridge variants.\n--coverage prints {edges:[{id,primitives}],cases:[13 review cases]} after the checks pass.');
  } else if (args.length > 0 && !(args.length === 1 && args[0] === '--coverage')) {
    console.error('Unknown arguments; use --help'); process.exitCode = 1;
  } else checkBridges({ coverageOnly: args.includes('--coverage') }).then(result => console.log(JSON.stringify(result)))
    .catch(error => { console.error(error); process.exitCode = 1; });
}
