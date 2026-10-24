// CONTINUITY.md, "Continuity of what is drawn": shared per-frame bounds on what
// the painters draw. check-engine (every script), check-bridges (every
// directed edge) and check-scenes (the full matrix) feed their frames here.
import assert from 'node:assert/strict';
import { STEP_MS } from './trace.mjs';
import { faceRender, faceTransition, dimensions } from '../engine/face.mjs';
import { bridgeConstants } from '../engine/bridges.mjs';
import { sceneConstants } from '../engine/scenes/constants.mjs';
import { hermite } from '../engine/scenes/ramp.mjs';

export const SMOOTH_SPEC = 'CONTINUITY.md, Continuity of what is drawn';
const controls = ['eyeX', 'eyeY', 'eyeOpen', 'mouthY', 'mouthWidth', 'curve', 'cheekAlpha', 'tearAmount'];
// Each drawn ratio and the control it follows.
const ratios = { eye: 'eyeOpen', mouthWidth: 'mouthWidth', mouthHeight: 'curve' };
const props = ['alert', 'result', 'start', 'helpers', 'listening', 'touch'];
const eps = 1e-9;

// A Hermite ramp's steepest slope over its window. From rest it is a
// smoothstep (peak slope 1.5); a reversal keeps the current slope. Sample the
// worst reversal, and reversal of a reversal, with 2% margin.
const hermiteSlope = (() => {
  let worst = 1.5;
  for (let p = 0; p <= 1; p += 0.01) {
    const rising = hermite({ from: 0, tangent: 0, to: 1 }, p);
    for (let q = 0; q <= 1; q += 0.01) {
      const falling = hermite({ from: rising.value, tangent: rising.slope, to: 0 }, q);
      worst = Math.max(worst, Math.abs(falling.slope));
      for (let s = 0; s <= 1; s += 0.05) worst = Math.max(worst, Math.abs(hermite({ from: falling.value, tangent: falling.slope, to: 1 }, s).slope));
    }
  }
  return worst * 1.02;
})();
// A prop ramp's steepest 16 ms.
export const rampStep = hermiteSlope * STEP_MS / sceneConstants.propRampMs;
// A face layer's weight crosses over on the same Hermite, over the shortest
// face window.
const shortestFaceMs = Math.min(faceTransition.durationMs, ...Object.values(bridgeConstants.faceDurationMs).flat());
export const weightStep = hermiteSlope * STEP_MS / shortestFaceMs;
// The desk's existing spring, simulated from rest: its steepest frame.
export const deskStep = (() => {
  let x = 0, v = 0, step = 0;
  for (let frame = 0; frame < 120; frame++) {
    const before = x; let left = STEP_MS / 1000;
    while (left > 0) { const h = Math.min(left, 1 / 240); v += (sceneConstants.propFrequency ** 2 * (1 - x) - sceneConstants.propDamping * v) * h; x += v * h; left -= h; }
    x = Math.min(1, x); step = Math.max(step, x - before);
  }
  return step;
})();
// At an event, the change in per-frame velocity may be at most this many
// times the largest change the same channel makes anywhere else.
export const eventFactor = 2;

// What the painters draw of a frame, by channel; `profiles` are the
// catalog's expressions, which give each layer its own size.
export function drawnChannels(frame, profiles) {
  const out = {};
  for (const key of controls) out[`face.${key}`] = frame.face[key];
  // Each layer by its art, so one is followed from frame to frame.
  for (const layer of frame.face.layers) {
    const art = layer.artId + (layer.sleeping ? ' asleep' : ''), size = dimensions(profiles, layer);
    out[`weight.${art}`] = layer.weight;
    // What is drawn: each ratio times its art's own size.
    for (const [key, control] of Object.entries(ratios)) out[`size.${key}.${art}`] = layer[key] * size[control];
  }
  out['posture.lean'] = frame.posture[0]; out['posture.squash'] = frame.posture[1];
  out['props.desk.visible'] = frame.props.desk.visible;
  for (const key of props) out[`props.${key}.visible`] = frame.props[key].visible;
  out['props.result.reveal'] = frame.props.result.reveal; out['props.start.reveal'] = frame.props.start.reveal;
  return out;
}

// The channel a drawn value counts in for jolts: every art's weight is one;
// a size is its control's, drawn, which it may jolt no more than.
const channel = key => key.startsWith('weight.') ? 'weight' : key.startsWith('size.') ? `face.${ratios[key.split('.')[1]]}` : key;

// One corpus (every script, every edge, the scene matrix) shares its
// statistics; each actor's run, given the catalog's expressions, keeps its
// own frame history.
export function createSmoothness(label) {
  const stats = {};
  // A drawn size moves no further in a frame than the control it follows:
  // the ratio's saturation has a slope of at most one.
  const sizeStep = (key, values, previous) => Math.abs(values[channel(key)] - previous[channel(key)]);
  function bounded(key, values, previous, at) {
    if (previous?.[key] === undefined) return;
    const step = Math.abs(values[key] - previous[key]);
    const limit = key.startsWith('size.') ? sizeStep(key, values, previous) : key.startsWith('weight.') ? weightStep
      : key === 'props.desk.visible' ? deskStep : key.startsWith('props.') ? rampStep : Infinity;
    assert.ok(step <= limit + eps, `${SMOOTH_SPEC}: ${label} ${key} moves ${step} in one frame at ${at}, more than its ${limit}`);
  }
  const run = profiles => {
    let history = [];
    return (frame, event = false) => {
      const values = drawnChannels(frame, profiles), at = frame.time;
      for (const layer of frame.face.layers) for (const key of Object.keys(ratios)) {
        assert.ok(layer[key] >= faceRender.ratioLow - eps && layer[key] <= faceRender.ratioHigh + eps,
          `${SMOOTH_SPEC}: ${label} drawn ${key} ratio ${layer[key]} leaves [0.75, 4/3] at ${at}`);
      }
      const sum = frame.face.layers.reduce((total, layer) => total + layer.weight, 0);
      assert.ok(Math.abs(sum - 1) <= eps, `${SMOOTH_SPEC}: ${label} the face's layers' weights sum to ${sum}, not one, at ${at}`);
      const previous = history.at(-1);
      for (const [key, value] of Object.entries(values)) {
        bounded(key, values, previous?.values, at);
        const s = stats[channel(key)] ??= { eventD2: 0, steadyD2: 0, eventAt: null };
        if (history.length === 2 && history.every(past => key in past.values)) {
          const d2 = Math.abs(value - 2 * history[1].values[key] + history[0].values[key]);
          if (event) { if (d2 > s.eventD2) { s.eventD2 = d2; s.eventAt = at; } } else s.steadyD2 = Math.max(s.steadyD2, d2);
        }
      }
      history = [...history.slice(-1), { values }];
    };
  };
  return {
    stats, run,
    // The worst event-to-elsewhere velocity-change ratio per channel family.
    summary() {
      const worst = {};
      for (const [key, s] of Object.entries(stats)) {
        const family = key.split('.').slice(0, key.startsWith('props.') ? 2 : 1).join('.');
        worst[family] = Math.max(worst[family] ?? 0, s.steadyD2 ? s.eventD2 / s.steadyD2 : 0);
      }
      return Object.fromEntries(Object.entries(worst).map(([key, value]) => [key, Number(value.toFixed(3))]));
    },
    finish() {
      for (const [key, s] of Object.entries(stats)) {
        assert.ok(s.eventD2 <= eventFactor * s.steadyD2 + eps,
          `${SMOOTH_SPEC}: ${label} ${key} changes velocity by ${s.eventD2} at an event (t=${s.eventAt}), over ${eventFactor}× the ${s.steadyD2} it reaches elsewhere`);
      }
      return stats;
    }
  };
}

// Marks every call that changes the actor, so a frame knows an event preceded it.
export function tracked(slime, onEvent) {
  return new Proxy(slime, {
    get(target, key) {
      const value = target[key];
      if (typeof value !== 'function' || key === 'step' || key === 'inspect') return value;
      return (...args) => { onEvent(); return value.apply(target, args); };
    }
  });
}
