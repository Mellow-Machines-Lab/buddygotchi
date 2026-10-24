// The Mac's mirror of the board (mac/mirror/): its page's rules, with the
// real board.js on a page of stubs and a clock the test moves. That it
// draws what the board draws is `boopctl mirror`'s.
//   node --test characters/boop/tests/mirror/page.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const mirror = new URL('../../mac/mirror/', import.meta.url);
const read = name => fs.readFileSync(new URL(name, mirror), 'utf8');
const WORKING = '{"t":"state","base":"working","act":"terminal","mood":"happy","busy":1,"vol":6}';

// A page with the mirror in it: its canvas counts what's drawn, and time
// moves only by `run`, display refreshes and timers included.
async function page() {
  let clock = 1000, frames = [], timers = [], core = null;
  const drawn = {count: 0};
  const canvas = () => ({clientWidth: 46, clientHeight: 46, width: 0, height: 0,
    getContext: () => ({clearRect() {}, putImageData() {}, drawImage() { drawn.count++; }})});
  const screen = canvas();
  const context = vm.createContext({
    console, devicePixelRatio: 2, WebAssembly,
    performance: {now: () => clock},
    setInterval: (fn, ms) => timers.push({fn, ms, at: clock + ms}),
    requestAnimationFrame: fn => frames.push(fn),
    ResizeObserver: class { observe() {} },
    ImageData: class { constructor(w, h) { this.width = w, this.height = h, this.data = new Uint8ClampedArray(w * h * 4); } },
    document: {getElementById: () => screen, createElement: canvas},
  });
  context.window = context;
  vm.runInContext(read('board.js'), context);
  const make = context.BoopMirrorBoard;
  context.BoopMirrorBoard = async options => (core = await make(options));
  vm.runInContext(read('mirror.js'), context);
  const mirror = context.BoopMirror;
  await mirror.send(WORKING);  // once the board is ready
  const usb = core.cwrap('mirror_send', 'number', ['string']);
  return {
    mirror, drawn,
    // `seconds` of time, with the display refreshing `hz` times a second.
    run(seconds, hz = 60) {
      for (let i = 0; i < seconds * hz; i++) {
        clock += 1000 / hz;
        for (const t of timers) while (t.at <= clock) t.fn(), t.at += t.ms;
        const due = frames;
        frames = [];
        for (const fn of due) fn(clock);
      }
    },
    // What the board says it shows (dbg.state), as a tool on its USB
    // asks, with the pass of its loop that ends a dbg.* line's batch.
    state() {
      usb('{"t":"dbg.state"}\n');
      const said = core.UTF8ToString(core._mirror_said());
      core._mirror_tick();
      return JSON.parse(said.split('\n').find(l => l.startsWith('{"t":"dbg.state"')));
    },
  };
}

test('draws only while shown, at most a frame each 16 ms', async () => {
  const p = await page();
  const settled = p.drawn.count;
  assert.equal(settled, 1, 'a new board draws its settled frame');
  p.run(5);
  assert.equal(p.drawn.count, settled, 'a mirror not shown draws nothing');
  p.mirror.shown(true);
  p.run(1, 120);
  const promotion = p.drawn.count - settled;
  assert.ok(promotion >= 55 && promotion <= 61, `ProMotion's 120 Hz drew ${promotion} frames in a second`);
  p.run(1, 60);
  const standard = p.drawn.count - settled - promotion;
  assert.ok(standard >= 55 && standard <= 61, `60 Hz drew ${standard} frames in a second`);
  p.mirror.shown(false);
  const closed = p.drawn.count;
  p.run(2);
  assert.equal(p.drawn.count, closed, 'hiding stops the drawing');
});

test('starts settled in its first state, then runs', async () => {
  const p = await page();
  const s = p.state();
  assert.equal(s.screen, 'face');
  assert.deepEqual([s.base, s.act, s.mood], ['working', 'terminal', 'happy']);
  p.run(1);
  assert.equal(p.state().screen, 'face');
});

test('says its last state again, so it never takes its Mac for gone', async () => {
  const p = await page();
  p.run(90);  // three times the board's 30 s without its Mac, hidden
  assert.equal(p.state().screen, 'face');
  p.mirror.shown(true);
  p.run(45);
  assert.equal(p.state().screen, 'face');
});

test("plays a reaction it's sent, and a tap is a finger on its screen", async () => {
  const p = await page();
  await p.mirror.send('{"t":"do","id":7,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}');
  assert.equal(p.state().moment?.anim, 'task_complete');
  p.run(10);
  // The board reads a finger on its passes, which run while it's shown;
  // one that's gone by the next is lost, as a tap that's over is.
  p.mirror.shown(true);
  await p.mirror.tap();
  p.run(0.2);
  assert.equal(p.state().moment?.anim, 'poked');
});

test("a snapshot is a frozen board's frame, and says what it shows", async () => {
  const p = await page();
  const shows = await p.mirror.snapshot('{"t":"state","base":"idle","mood":"proud","busy":0,"attn":{"agent":"codex","project":"Boop","more":0,"id":3},"vol":0}');
  assert.deepEqual({...shows}, {screen: 'needs_you', base: 'idle', act: null, mood: 'proud'});
});

test('makes no sound, and nothing it says leaves the page', () => {
  const html = read('index.html'), script = read('mirror.js');
  for (const rule of ["connect-src 'none'", "media-src 'none'", "script-src 'self' 'wasm-unsafe-eval'"]) assert.ok(html.includes(rule), rule);
  assert.ok(!/AudioContext|postMessage|fetch\(|XMLHttpRequest|messageHandlers/.test(script));
});
