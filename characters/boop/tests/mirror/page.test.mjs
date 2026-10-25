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

// A page with the mirror in it: its canvas counts what's drawn and keeps
// the last picture put in, and time moves only by `run`, display
// refreshes and timers included. `count` is the board's frames put in;
// `draws` every drawImage, with the canvas it drew on.
async function page() {
  let clock = 1000, frames = [], timers = [];
  const drawn = {count: 0, image: null, draws: []};
  const canvas = () => {
    const it = {clientWidth: 46, clientHeight: 46, width: 0, height: 0};
    it.getContext = () => ({clearRect() {}, putImageData(image) { drawn.count++, drawn.image = image; },
                            drawImage(...args) { drawn.draws.push({on: it, args}); }});
    return it;
  };
  const screen = canvas();
  const context = vm.createContext({
    console, devicePixelRatio: 2, WebAssembly,
    performance: {now: () => clock},
    setInterval: (fn, ms) => timers.push({fn, ms, at: clock + ms}),
    requestAnimationFrame: fn => frames.push(fn),
    ResizeObserver: class { observe() {} },
    ImageData: class { constructor(data, w, h) { this.data = data, this.width = w, this.height = h; } },
    document: {getElementById: () => screen, createElement: canvas},
  });
  context.window = context;
  vm.runInContext(read('board.js'), context);
  vm.runInContext(read('mirror.js'), context);
  const mirror = context.BoopMirror;
  await mirror.send(WORKING);  // once the board is ready
  return {
    mirror, drawn, timers, screen,
    // `seconds` of time, with the display refreshing `hz` times a second,
    // each refresh's passes run `late(i)` ms after it.
    run(seconds, hz = 60, late = () => 0) {
      for (let i = 0; i < seconds * hz; i++) {
        clock += 1000 / hz;
        for (const t of timers) while (t.at <= clock) t.fn(), t.at += t.ms;
        const due = frames, at = clock;
        frames = [];
        clock = at + late(i);
        for (const fn of due) fn(at);
        clock = at;
      }
    },
    // What the board says it shows (dbg.state).
    state: () => mirror.state(),
  };
}

// The page asks for a frame on every display refresh, and the board
// draws one when it has one, as on its own screen: the page has no cap.
test('draws only while shown, every frame the board draws, on any display', async () => {
  const p = await page();
  const settled = p.drawn.count;
  assert.equal(settled, 1, 'a new board draws its settled frame');
  p.run(5);
  assert.equal(p.drawn.count, settled, 'a mirror not shown draws nothing');
  p.mirror.shown(true);
  assert.equal(p.drawn.count, settled + 1, 'shown again, it draws where the board is now at once');
  p.run(1, 120);
  const promotion = p.drawn.count - settled - 1;
  assert.ok(promotion >= 58 && promotion <= 61, `ProMotion's 120 Hz drew ${promotion} frames in a second, the board's 60`);
  p.run(1, 60);
  const standard = p.drawn.count - settled - 1 - promotion;
  assert.ok(standard >= 58 && standard <= 61, `60 Hz drew ${standard} frames in a second, one a refresh`);
  p.mirror.shown(false);
  const closed = p.drawn.count;
  p.run(2);
  assert.equal(p.drawn.count, closed, 'hiding stops the drawing');
});

// A pass runs a little after its refresh, by more or less each time. The
// board, timing its frames by the refresh, still draws one a refresh.
test('draws every refresh at 60 Hz however late each pass runs', async () => {
  const p = await page();
  p.mirror.shown(true);
  const from = p.drawn.count;
  p.run(1, 60, i => (i % 2 ? 0.2 : 2.5));
  const drawn = p.drawn.count - from;
  assert.ok(drawn >= 58 && drawn <= 61, `passes late by 0.2 and 2.5 ms in turn drew ${drawn} frames in a second, not 60`);
});

// WebKit asks for 72 frames a second on a 144 Hz display: more often than
// the board's 16 ms between frames, which drew every other one, 36 a
// second. A slower display gets a frame every refresh, on its own time.
test('draws 60 a second at 72 Hz, and one a refresh at 50 Hz', async () => {
  const p = await page();
  p.mirror.shown(true);
  p.run(0.5, 72);
  let from = p.drawn.count;
  p.run(1, 72);
  const at72 = p.drawn.count - from;
  assert.ok(at72 >= 58 && at72 <= 61, `72 Hz drew ${at72} frames in a second, not the board's 60`);
  p.run(0.5, 50);
  from = p.drawn.count;
  p.run(1, 50);
  assert.equal(p.drawn.count - from, 50, '50 Hz draws every refresh');
});

test("draws the board's whole screen from where the board keeps it", async () => {
  const p = await page();
  const {width, height, data} = p.drawn.image;
  assert.deepEqual([width, height], [502, 410], "the panel's own size, lane and all, whatever the tile");
  assert.ok(data.buffer.byteLength > data.byteLength, "a view of the board's memory, not a copy");
});

// The popover's 46 pt tile, 92 pixels at 2×: the whole screen there makes
// the slime a smudge, and one shrink of more than 2× shimmers.
test('a small tile zooms on the slime, and shrinks in halves of at most 2×', async () => {
  const p = await page();
  const paint = () => {
    const draws = p.drawn.draws.splice(0);
    for (const {args} of draws) {
      const shrink = Math.max(args[3] / args[7], args[4] / args[8]);
      assert.ok(shrink <= 2, `one step shrinks ${shrink.toFixed(2)}×`);
    }
    const last = draws.at(-1);
    assert.equal(last.on, p.screen, 'the last step is on the screen');
    return {first: draws[0].args.slice(1, 5), to: last.args.slice(5).map(Math.round)};
  };
  p.drawn.draws.length = 0;
  p.mirror.zoom(true);
  const zoomed = paint();
  assert.deepEqual(zoomed.first, [101, 44, 300, 300], 'the square around the slime');
  assert.deepEqual(zoomed.to, [0, 0, 92, 92], 'filling the square tile');
  p.mirror.zoom(false);
  const whole = paint();
  assert.deepEqual(whole.first, [0, 0, 502, 410], 'the whole screen');
  assert.deepEqual(whole.to, [0, 8, 92, 75], 'as big as fits, centred');
});

test('starts settled in its first state, then runs', async () => {
  const p = await page();
  const s = await p.state();
  assert.equal(s.screen, 'face');
  assert.deepEqual([s.base, s.act, s.mood], ['working', 'terminal', 'happy']);
  p.run(1);
  assert.equal((await p.state()).screen, 'face');
});

// The Mac's link says its state again every 10 s (DeviceLink.keepaliveMs),
// and the mirror hears it as the board does: the page says nothing itself.
test("the Mac's keepalive keeps it, and the page says nothing of its own", async () => {
  const p = await page();
  for (let s = 10; s <= 90; s += 10) {  // three times the board's 30 s without its Mac
    p.run(10);
    await p.mirror.send(WORKING);
    if (s === 40) p.mirror.shown(true);
  }
  p.run(1);
  assert.equal((await p.state()).screen, 'face');
  assert.equal(p.timers.length, 0, 'no timer of its own');
});

test("plays a reaction it's sent, and a tap is a finger on its screen or BOOT", async () => {
  const p = await page();
  await p.mirror.send('{"t":"do","id":7,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success"}}');
  assert.equal((await p.state()).moment?.anim, 'task_complete');
  p.run(10);
  // The board reads a finger on its passes, which run while it's shown;
  // one that's gone by the next is lost, as a tap that's over is.
  p.mirror.shown(true);
  await p.mirror.tap();
  p.run(0.2);
  assert.equal((await p.state()).moment?.anim, 'poked');
  p.run(10);
  await p.mirror.tap(true);
  p.run(0.3);
  assert.equal((await p.state()).moment?.anim, 'poked', 'BOOT, with no agent to hand over, pokes');
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
