// The simulator's core as the browser runs it (simulator/README.md): the
// WebAssembly build, driven as the page drives it, the page's demo player,
// and its USB cable (web/serve.py). Needs simulator/web/build.sh to have run.
//   node --test simulator/tests/
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const dist = path.join(repo, 'simulator/web/dist');
const voice = path.join(repo, '.build/voice/voice.bin');
const skip = existsSync(path.join(dist, 'boop-sim.wasm')) ? false : 'the page isn\'t built: simulator/web/build.sh';
const needsVoice = skip || (existsSync(voice) ? false : 'needs a voice pack: make -C internal voice');
const sleep = ms => new Promise(r => setTimeout(r, ms));

const WORKING = { t: 'state', base: 'working', mood: 'calm', busy: 1, vol: 6 };
const QUIET = { ...WORKING, base: 'idle', busy: 0 };  // a face that makes no sound of its own
const GO = { t: 'do', id: 1, name: 'react', play: 'now', args: { say: { take: 'previous.go' } } };

/// The core, with what the page's script does around it.
async function board(face = 'pixel', env = {}) {
  const { default: make } = await import(path.join(dist, 'boop-sim.js'));
  const core = await make();
  const setenv = core.cwrap('sim_env', null, ['string', 'string']);
  const usb = core.cwrap('sim_usb', null, ['string']);
  const b = {
    core, frames: [], lines: [], parts: {},
    input: core.cwrap('sim_input', null, ['string']),
    power(on) {
      setenv('BOOP_SIM_FACE', face);
      for (const [k, v] of Object.entries(env)) setenv(k, v);
      core._sim_power(on ? 1 : 0);
    },
    send: message => usb(JSON.stringify(message) + '\n'),
    insert(bytes) {
      const at = core._sim_card(bytes.length);
      core.HEAPU8.set(bytes, at);
      b.input('card in');
    },
    /// The board's loop for this long, as the page runs it.
    async run(ms) {
      for (const end = Date.now() + ms; Date.now() < end; await sleep(2)) {
        if (core._sim_tick()) b.frames.push([core._sim_width(), core._sim_height()]);
        const said = core._sim_usb_out(), parts = core._sim_parts();
        if (said) for (const line of core.UTF8ToString(said).split('\n')) if (line.startsWith('{')) b.lines.push(JSON.parse(line));
        if (parts) b.parts = JSON.parse(core.UTF8ToString(parts));
      }
    },
    async request(message, ms = 100) {
      const before = b.lines.length;
      b.send(message);
      await b.run(ms);
      const reply = b.lines.slice(before).filter(m => m.t === message.t).pop();
      assert.ok(reply, `no reply to ${JSON.stringify(message)}`);
      return reply;
    },
    /// The page's audio asking for chunks until a sound has come and gone: how many had sound.
    async listen() {
      let loud = 0;
      for (let i = 0; i < 400; i++) {
        if (core._sim_sound()) loud++;
        else if (loud) break;
        if (i % 8 === 0) await b.run(4);
      }
      return loud;
    },
  };
  b.power(true);
  return b;
}

test('it says hello and draws in real time', { skip }, async () => {
  const b = await board();
  const hello = await b.request({ t: 'hello' });
  assert.deepEqual([hello.app, hello.fw, hello.face], ['boop', 'sim', 'pixel']);
  b.send(WORKING);
  await b.run(1000);
  assert.ok(b.frames.length > 0, 'the working face moves on its own');
  assert.deepEqual([...new Set(b.frames.map(String))], ['320,240']);
  assert.equal(b.parts.backlight, 255);
  assert.equal(b.core._sim_parts(), 0, 'parts are told once, until one changes');
});

test('a native face fills the panel it is given', { skip }, async () => {
  const b = await board('gel');
  if ((await b.request({ t: 'hello' })).face !== 'gel') return;  // a checkout without Boop's pack has only the pixel face
  b.send(WORKING);
  await b.run(300);
  assert.deepEqual([...new Set(b.frames.map(String))], ['502,410'], "the AMOLED's panel, by default");
  const small = await board('gel', { BOOP_SIM_NATIVE: '400x300' });
  small.send(WORKING);
  await small.run(300);
  assert.deepEqual([...new Set(small.frames.map(String))], ['400,300']);
});

test('a touch is a tap however soon it lifts, and power-on is a new boot', { skip }, async () => {
  const b = await board();
  const first = (await b.request({ t: 'hello' })).boot;
  b.send(WORKING);
  await b.run(200);
  // A click: down and up before the board has looked once.
  b.input('touch 160 120');
  b.input('release');
  await b.run(400);
  assert.ok(b.lines.some(m => m.t === 'ev' && m.kind === 'tap'));
  b.input('boot 1');
  await b.run(1200);
  b.input('boot 0');
  await b.run(300);
  const kinds = b.lines.filter(m => m.t === 'ev').map(m => m.kind);
  assert.ok(kinds.includes('talk_on') && kinds.includes('talk_off'), 'BOOT held is talking');
  b.power(true);
  b.lines.length = 0;
  const second = (await b.request({ t: 'hello' })).boot;
  assert.ok(first && second && first !== second);
  assert.equal(b.lines.filter(m => m.t === 'ev').length, 0, 'nothing of the board before is left');
});

test('a line plays for as long as its samples last, from the card in the slot', { skip: needsVoice }, async () => {
  const b = await board();
  await b.run(20);
  assert.equal(b.parts.card, 'no card');
  b.insert(readFileSync(voice));
  b.send(QUIET);
  await b.run(200);
  assert.equal(b.parts.card, 'ok');
  assert.equal(b.core._sim_sound(), 0, 'silence is no chunk');
  b.send(GO);
  await b.run(100);
  assert.ok(await b.listen() > 4, 'the line made sound');
  const out = (await b.request({ t: 'dbg.state' })).audio.out;
  assert.equal(out.lines, 1);
  assert.ok(out.out_ms > 100);
  // Pins the browser's output time: the chunks' own, so exactly the line's.
  assert.ok(Math.abs(out.wall_ms / out.out_ms - 1) < 0.1);
  // The card stays in its slot through a reset, and out once it's taken out.
  b.power(true);
  await b.run(20);
  assert.equal(b.parts.card, 'ok');
  b.input('card out');
  b.power(true);
  await b.run(20);
  assert.equal(b.parts.card, 'no card');
  b.input('card in');
  await b.run(20);
  assert.equal(b.parts.card, 'ok');
});

test('the cable carries whole lines both ways, long ones too', { skip }, async t => {
  const dir = mkdtempSync(path.join(tmpdir(), 'bsim-'));
  const socket = path.join(dir, 'usb.sock'), port = 18206 + Math.floor(Math.random() * 1000);
  const server = spawn('python3', [path.join(repo, 'simulator/web/serve.py'), '--port', String(port), '--socket', socket, '--dist', dist]);
  t.after(() => server.kill());
  for (let i = 0; i < 100 && !existsSync(socket); i++) await sleep(50);
  // The page's end, and a tool's.
  const page = new WebSocket(`ws://127.0.0.1:${port}/usb`);
  await new Promise((ok, no) => { page.onopen = ok; page.onerror = no; });
  const tool = net.connect(socket);
  await new Promise(ok => tool.on('connect', ok));
  await sleep(100);
  const heardByPage = [], heardByTool = [];
  page.onmessage = e => heardByPage.push(String(e.data));
  let buffer = '';
  tool.on('data', d => { buffer += d; for (let i; (i = buffer.indexOf('\n')) >= 0; buffer = buffer.slice(i + 1)) heardByTool.push(buffer.slice(0, i)); });
  tool.write('{"t":"hello"}\n{"t":"dbg.ping"}\n');
  const long = 'x'.repeat(900_000);  // a native screenshot's line
  page.send('{"t":"hello","app":"boop"}');
  page.send(long);
  for (let i = 0; i < 100 && (heardByPage.length < 2 || heardByTool.length < 2); i++) await sleep(50);
  assert.deepEqual(heardByPage, ['{"t":"hello"}', '{"t":"dbg.ping"}']);
  assert.equal(heardByTool[0], '{"t":"hello","app":"boop"}');
  assert.equal(heardByTool[1], long);
  page.close();
  tool.destroy();
});

test('a recording plays into the board in order, and knows nothing of what its lines mean', { skip }, async () => {
  const { DemoPlayer } = await import(path.join(dist, 'boop-simulator.js'));
  const recording = {
    version: 1, character: 'pixel', name: 'Pip', face: 'pixel', length: 0.4, takes: ['t.go'],
    events: [
      { at: 0, line: '{"t":"state","base":"working"}' },
      { at: 0.05, cause: { kind: 'prompt', text: 'You ask Claude: “Fix it”' } },
      { at: 0.1, line: '{"t":"do","id":2,"name":"react"}', effect: 'Pip makes an excited face and says “Go”' },
      { at: 0.15, cause: { kind: 'tap', text: 'You poke Pip' }, input: 'tap' },
      { at: 0.2, line: '{"t":"anything","the":"app sends"}' },
    ],
  };
  const did = [];
  const fake = { send: line => did.push(['line', JSON.parse(line).t]), touch: (x, y) => did.push(['touch', x, y]), release: () => did.push(['release']) };
  const player = new DemoPlayer(fake, recording);
  const told = [];
  for (const kind of ['cause', 'effect']) player.addEventListener(kind, e => told.push(kind === 'cause' ? e.detail.text : e.detail));
  const ended = new Promise(ok => player.addEventListener('end', ok));
  player.play();
  await ended;
  player.stop();
  assert.deepEqual(did, [['line', 'state'], ['line', 'do'], ['touch', 160, 120], ['release'], ['line', 'anything']]);
  assert.deepEqual(told, ['You ask Claude: “Fix it”', 'Pip makes an excited face and says “Go”', 'You poke Pip']);
  assert.ok(player.ended && !player.playing);
  assert.throws(() => new DemoPlayer(fake, { ...recording, version: 2 }), /version 2/);
});

test('a voice pack cut down to a demo is one the board plays from', { skip: needsVoice }, async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'bsim-voice-'));
  const recording = path.join(dir, 'demo.json'), small = path.join(dir, 'voice.bin');
  writeFileSync(recording, JSON.stringify({ takes: ['previous.go', 'previous.tsk'] }));
  const cut = spawn('python3', [path.join(repo, 'simulator/tools/voice_subset.py'), recording, '--out', small]);
  assert.equal(await new Promise(ok => cut.on('exit', ok)), 0);
  assert.ok(statSync(small).size < 200_000, 'two takes, not the whole voice');
  const whole = await board();
  whole.insert(readFileSync(voice));
  const b = await board();
  b.insert(readFileSync(small));
  assert.equal((await b.request({ t: 'hello' })).voice, (await whole.request({ t: 'hello' })).voice, 'the same voice, by its version');
  b.send(QUIET);
  b.send({ ...GO, args: { say: { take: 'previous.tsk' } } });
  await b.run(150);
  assert.ok(await b.listen() > 2, 'it says a take the small pack has');
});
