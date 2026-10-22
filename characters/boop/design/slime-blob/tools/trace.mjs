#!/usr/bin/env node
// Reference channel traces; CONTINUITY.md, "Headless reference traces".
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const STEP_MS = 16;
export const TRACE_DECIMALS = 6;
const operations = new Set(['facts', 'mood', 'poke', 'shake', 'perform', 'dragStart', 'dragMove', 'dragEnd', 'oneShot', 'linkTimedOut',
  'clearTransient', 'holdExpression', 'occasion', 'end']);

export function readScript(file) {
  const source = fs.readFileSync(file, 'utf8');
  const events = source.split(/\r?\n/).filter(line => line.trim()).map((line, index) => {
    let event;
    try { event = JSON.parse(line); } catch (error) { throw new Error(`${file}:${index + 1}: ${error.message}`); }
    if (!event || !Number.isSafeInteger(event.at) || event.at < 0 || !operations.has(event.type)) {
      throw new Error(`${file}:${index + 1}: expected a nonnegative integer at and a supported type`);
    }
    return event;
  });
  if (!events.length || events.at(-1).type !== 'end') throw new Error(`${file}: final row must be an end event`);
  for (let i = 0; i < events.length; i++) {
    if (i && events[i].at < events[i - 1].at) throw new Error(`${file}: timestamps must not go backwards`);
    if (events[i].type === 'end' && i !== events.length - 1) throw new Error(`${file}: end must be the final row`);
  }
  const durationMs = events.at(-1).at;
  if (durationMs % STEP_MS) throw new Error(`${file}: end time must be a multiple of ${STEP_MS} ms`);
  return { events, durationMs, sha256: createHash('sha256').update(source).digest('hex') };
}

export function loadCatalog() {
  return { ...JSON.parse(fs.readFileSync(path.join(root, 'expressions.json'), 'utf8')),
    graph: JSON.parse(fs.readFileSync(path.join(root, 'emotion-graph.json'), 'utf8')),
    sound: JSON.parse(fs.readFileSync(path.join(root, 'sound/sound-plan.json'), 'utf8')) };
}

export async function loadEngine() {
  return (await import('../engine/index.mjs')).createSlime;
}

export function applyEvent(slime, event) {
  switch (event.type) {
    case 'facts': slime.setFacts(event.facts); break;
    case 'mood': slime.setMood(event.mood, event.bridgeVariant === undefined ? undefined : { bridgeVariant: event.bridgeVariant }); break;
    case 'poke': slime.poke(event.x, event.y); break;
    case 'shake': slime.shake(); break;
    case 'perform': slime.perform(event.index); break;
    case 'dragStart': slime.dragStart(event.point); break;
    case 'dragMove': slime.dragMove(event.delta); break;
    case 'dragEnd': slime.dragEnd(); break;
    case 'oneShot': slime.oneShot(event.moment); break;
    case 'linkTimedOut': slime.setLinkTimedOut(event.value); break;
    case 'clearTransient': slime.clearTransient(); break;
    case 'holdExpression': slime.holdExpression(event.mood ?? null); break;
    case 'occasion': slime.setOccasion({ when: event.when ?? [], lookMs: event.lookMs ?? 0 }); break;
    case 'end': break;
    default: throw new Error(`Unsupported event type: ${event.type}`);
  }
}

export function runScript(createSlime, catalog, script, seed = 53, observe) {
  const slime = createSlime({ seed, catalog });
  const frames = [], cues = [];
  let cursor = 0;
  for (let at = 0; at <= script.durationMs; at += STEP_MS) {
    const applied = [];
    while (cursor < script.events.length && script.events[cursor].at <= at) {
      const event = script.events[cursor++];
      const before = observe ? structuredClone(slime.inspect()) : undefined;
      applyEvent(slime, event);
      observe?.({ kind: 'event', at, event, before, after: structuredClone(slime.inspect()) });
      applied.push(event);
    }
    const result = slime.step(at);
    frames.push(structuredClone(result.channels));
    for (const cue of result.cues) cues.push({ at, cue: structuredClone(cue) });
    observe?.({ kind: 'frame', at, channels: result.channels, applied, inspect: slime.inspect() });
  }
  return { frames, cues };
}

// Sorted JSON-pointer columns retain every scalar of every frame, including
// optional performance fields. Null represents an absent optional scalar.
export function flatten(value, prefix = '', into = {}) {
  if (value !== null && typeof value === 'object') {
    for (const key of Object.keys(value).sort()) {
      flatten(value[key], prefix + '/' + key.replaceAll('~', '~0').replaceAll('/', '~1'), into);
    }
  } else {
    if (typeof value === 'number' && !Number.isFinite(value)) throw new Error(`Nonfinite channel: ${prefix}`);
    if (!['number', 'string', 'boolean'].includes(typeof value) && value !== null) throw new Error(`Unsupported channel: ${prefix}`);
    into[prefix] = value;
  }
  return into;
}

function rounded(value) {
  if (typeof value !== 'number') return value;
  const scalar = Number(value.toFixed(TRACE_DECIMALS));
  return Object.is(scalar, -0) ? 0 : scalar;
}

export function serializeTrace(script, seed, result) {
  const flat = result.frames.map(frame => {
    // The script already records host facts; artwork and its prose are fixed
    // by artId in expressions.json. Internal face weights are not a rendered
    // control: semantic face dimensions, drawn ratios and composed pose are the
    // port contract. Control velocities are internal spring state.
    const { facts, weights, frames, ...channels } = frame;
    const { art, artBaseline, velocity, ...face } = channels.face;
    const performance = channels.performance && Object.fromEntries(
      Object.entries(channels.performance).filter(([key]) => key !== 'label'));
    return flatten({ ...channels, face, performance });
  });
  const columns = [...new Set(flat.flatMap(frame => Object.keys(frame)))].sort();
  const header = {
    format: 'boop-slime-channel-trace-v1', scriptSha256: script.sha256,
    seed, stepMs: STEP_MS, durationMs: script.durationMs, decimals: TRACE_DECIMALS,
    columns,
  };
  // One frame per line keeps a numerical regression diff reviewable without
  // repeating long channel names thousands of times.
  return JSON.stringify(header).slice(0, -1) + ',"frames":[\n'
    + flat.map(frame => JSON.stringify(columns.map(key => rounded(frame[key] ?? null)))).join(',\n')
    + '\n],"cues":' + JSON.stringify(result.cues) + '}\n';
}

export function usage() {
  return 'node tools/trace.mjs --script scripts/idle-60s.jsonl [--seed 53]\n'
    + 'Writes a deterministic channel trace to stdout at a fixed 16 ms step.\n'
    + 'JSONL rows: {"at":milliseconds,"type":"facts|mood|poke|shake|perform|dragStart|dragMove|dragEnd|oneShot|linkTimedOut|clearTransient|holdExpression|occasion|end",...}.\n'
    + 'Use facts, mood, x/y, index, point, delta, moment, or value for the corresponding operation.\n'
    + 'A mood event may include bridgeVariant:0|1|2 for a repeatable directed-edge review.\n'
    + 'A oneShot moment may carry hold:true and args.variant (0 to 3, a gesture\'s 0 to 9), as a host that times its own moments sends;\n'
    + 'holdExpression takes a mood (or null) that the host holds until the next holdExpression.\n'
    + 'occasion takes when (the tags on, as names) and lookMs (how long the look has shown).\n'
    + 'The final end timestamp is the duration, a multiple of 16 ms. Events run on the first frame at or after at.\n'
    + 'Channel scalars retain six decimal places; every frame is kept. No DOM, network, or device is used.';
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 1 && args[0] === '--help') { console.log(usage()); return; }
  let scriptPath, seed = 53;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--script' && args[i + 1]) scriptPath = args[++i];
    else if (args[i] === '--seed' && args[i + 1]) seed = Number(args[++i]);
    else throw new Error(`Unknown or incomplete argument: ${args[i]}\n${usage()}`);
  }
  if (!scriptPath) throw new Error(`--script is required\n${usage()}`);
  if (!Number.isSafeInteger(seed) || seed < 0 || seed > 0xffffffff) throw new Error('--seed must be an unsigned 32-bit integer');
  const script = readScript(path.resolve(scriptPath));
  process.stdout.write(serializeTrace(script, seed, runScript(await loadEngine(), loadCatalog(), script, seed)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
