// CONTINUITY.md, "Continuity of what is drawn": shared per-frame bounds on what
// the painters draw. check-engine (every script), check-bridges (every
// directed edge) and check-scenes (the full matrix) feed their frames here.
import assert from 'node:assert/strict';
import { STEP_MS } from './trace.mjs';
import { faceRender, faceTransition } from '../engine/face.mjs';
import { bridgeConstants } from '../engine/bridges.mjs';
import { sceneConstants } from '../engine/scenes/constants.mjs';
import { paintFace } from '../render/face-painter.mjs';

export const SMOOTH_SPEC = 'CONTINUITY.md, Continuity of what is drawn';
const controls = ['eyeX', 'eyeY', 'eyeOpen', 'mouthY', 'mouthWidth', 'curve', 'cheekAlpha', 'tearAmount'];
const ratios = ['eye', 'mouthWidth', 'mouthHeight'];
const props = ['alert', 'result', 'start', 'helpers', 'listening', 'touch'];
const eps = 1e-9;

// The steepest 16 ms of the sin² bridge ease over the shortest half window,
// across the whole allowed ratio range: no frame may move a ratio further.
const shortestHalfMs = Math.min(faceTransition.durationSeconds * 1000,
  ...Object.values(bridgeConstants.faceDurationMs).flat()) / 2;
export const ratioStep = Math.PI / 2 * STEP_MS / shortestHalfMs * (faceRender.ratioHigh - faceRender.ratioLow);
// A prop ramp's steepest 16 ms. From rest it is a smoothstep (peak slope 1.5
// over its window); a reversal is a cubic Hermite that keeps the current
// slope. Sample the worst reversal, and reversal of a reversal, with margin.
export const rampStep = (() => {
  const hermite = (x0, m0, x1, s) => ({ x: (2 * s ** 3 - 3 * s ** 2 + 1) * x0 + (s ** 3 - 2 * s ** 2 + s) * m0 + (3 * s ** 2 - 2 * s ** 3) * x1,
    m: (6 * s ** 2 - 6 * s) * x0 + (3 * s ** 2 - 4 * s + 1) * m0 + (6 * s - 6 * s ** 2) * x1 });
  let worst = 1.5;
  for (let p = 0; p <= 1; p += 0.01) {
    const rising = hermite(0, 0, 1, p);
    for (let q = 0; q <= 1; q += 0.01) {
      const falling = hermite(rising.x, rising.m, 0, q);
      worst = Math.max(worst, Math.abs(falling.m));
      for (let s = 0; s <= 1; s += 0.05) worst = Math.max(worst, Math.abs(hermite(falling.x, falling.m, 1, s).m));
    }
  }
  return worst * 1.02 * STEP_MS / sceneConstants.propRampMs;
})();
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

export function drawnChannels(frame) {
  const out = {};
  for (const key of controls) out[`face.${key}`] = frame.face[key];
  for (const key of ratios) out[`render.${key}`] = frame.face.render[key];
  out['posture.lean'] = frame.posture[0]; out['posture.squash'] = frame.posture[1];
  out['props.desk.visible'] = frame.props.desk.visible;
  for (const key of props) out[`props.${key}.visible`] = frame.props[key].visible;
  out['props.result.reveal'] = frame.props.result.reveal; out['props.start.reveal'] = frame.props.start.reveal;
  return out;
}

// One corpus (every script, every edge, the scene matrix) shares its
// statistics; each actor's run keeps its own frame history.
export function createSmoothness(label) {
  const stats = {};
  function bounded(key, value, previous, at) {
    if (!previous) return;
    const step = Math.abs(value - previous[key]);
    const limit = key.startsWith('render.') ? ratioStep : key === 'props.desk.visible' ? deskStep : key.startsWith('props.') ? rampStep : Infinity;
    assert.ok(step <= limit + eps, `${SMOOTH_SPEC}: ${label} ${key} moves ${step} in one frame at ${at}, more than its ${limit}`);
  }
  const run = () => {
    let history = [];
    return (frame, event = false) => {
      const values = drawnChannels(frame), at = frame.time;
      const face = frame.face, render = face.render;
      for (const key of ratios) {
        assert.ok(render[key] >= faceRender.ratioLow - eps && render[key] <= faceRender.ratioHigh + eps,
          `${SMOOTH_SPEC}: ${label} drawn ${key} ratio ${render[key]} leaves [0.75, 4/3] at ${at}`);
      }
      assert.ok(Math.abs(render.mouth - (1 - faceRender.mouthDot * face.bridgeBlink)) <= eps,
        `${SMOOTH_SPEC}: ${label} the mouth passes through a dot only at the swap`);
      for (const key of ['cheek', 'tear']) assert.ok(render[key] >= 0 && render[key] <= 1, `${SMOOTH_SPEC}: ${label} ${key} opacity`);
      const previous = history.at(-1);
      for (const [key, value] of Object.entries(values)) {
        bounded(key, value, previous?.values, at);
        const s = stats[key] ??= { eventD2: 0, steadyD2: 0, eventAt: null };
        if (history.length === 2) {
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

// The opacity the face painter draws the eyes and mouth with: the strongest
// ink it puts down in one frame. Cheek lines use the same ink but dimmer.
export function faceAlpha(channels, catalog) {
  const stack = [];
  let strongest = 0;
  const state = { globalAlpha: 1, fillStyle: '#000000', strokeStyle: '#000000' };
  const record = style => { if (style === '#0d2b48') strongest = Math.max(strongest, ctx.globalAlpha); };
  const ctx = new Proxy(state, {
    get(target, key) {
      if (key in target) return target[key];
      if (key === 'save') return () => stack.push({ ...target });
      if (key === 'restore') return () => Object.assign(target, stack.pop());
      if (key === 'fill') return () => record(target.fillStyle);
      if (key === 'stroke') return () => record(target.strokeStyle);
      if (key === 'createLinearGradient') return () => ({ addColorStop() {} });
      return () => {};
    },
    set(target, key, value) { target[key] = value; return true; }
  });
  paintFace(ctx, channels, catalog);
  return strongest;
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
