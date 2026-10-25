// The Mac's mirror of the board (characters/CHARACTER.md §9): the board's
// own firmware as WebAssembly (board.js, which firmware/tools/mirror.sh
// builds), fed the messages the Mac sends the board, its screen drawn
// here. It makes no sound, and nothing it says leaves this page.
//
// The app (app/Boop/Views/Slime/SlimeFeed.swift) calls window.BoopMirror:
//   send(line)      a message the board got, as its link sent it: every
//                   `state`, the 10 s keepalive's included, and every `do`
//   tap(button)     a tap on the board, which it reacts to itself: a finger
//                   on its screen, or BOOT pressed
//   shown(on)       whether it's on screen: it draws only then, and runs either way
//   zoom(on)        whether it frames the slime alone, for a tile too small
//                   for the board's whole screen, or the whole screen
//   snapshot(line)  a new board on a frozen clock in that `state`, drawn
//                   once as a scenario's shot draws it; what it says it
//                   shows (its dbg.state), for the app's snapshots to check
//   state()         what the board says it shows now: its dbg.state
'use strict';
(() => {
  // A new board shows its first `state` this long on a frozen clock, as a
  // scenario's shot waits, so it starts settled in it; then it runs.
  const SETTLE_MS = 1504;
  // A finger in the canvas's 320×240, beside the nose (a boop on it is a
  // gesture), and BOOT, each held as long as a tap.
  const TAP = '{"t":"dbg.touch","x":80,"y":120,"ms":100}', PRESS = '{"t":"dbg.press","ms":100}';
  // The slime on the board's 502×410 screen, in its pixels: a square
  // around it as it rests (x 105–398, y 95–320), with most of the props
  // beside it and the sign above it, and the lane under it (y 348) left
  // out. What a small tile shows.
  const SLIME = {x: 101, y: 44, w: 300, h: 300};
  // A drawing scaled down more than this many times skips pixels and
  // shimmers as the slime moves, so it's halved in steps until it isn't.
  const MOST_SHRINK = 2;

  const canvas = document.getElementById('screen'), context = canvas.getContext('2d');
  const panel = document.createElement('canvas'), panelContext = panel.getContext('2d');  // the board's own pixels
  const steps = [];  // the halved drawings, as many as a shrink needs
  let core, usb, image = null, state = null, powered = false, shown = false, still = false, zoomed = false, loop = 0;

  // The board's clock (its realMs reads performance.now). While the
  // display's refreshes run its passes, it reads the latest refresh's
  // time, not the moment something happens to run: the board draws once
  // 16 ms have gone since its last frame (kFrameMs), and at 60 Hz a pass
  // run a little earlier after one run a little late would read 15.9 and
  // show the last frame again. A display refreshing more often than that
  // (WebKit asks 72 times a second on a 144 Hz one) would have the board
  // draw every other refresh, 36 a second, so there the refresh's time
  // goes to the nearest 60th of a second, and the board draws 60, each
  // within half a 60th of its refresh. With no pass in the last 50 ms
  // (hidden, or the display stopped) it reads the time, and it never reads
  // earlier than it has before.
  const BOARD_FRAME_MS = 16, SIXTIETH = 1000 / 60, PASS_HOLDS_MS = 50;
  const realNow = performance.now.bind(performance);
  let pass = null, passAt = 0, read = 0, lastRefresh = null, between = SIXTIETH;
  performance.now = () => {
    const now = realNow();
    return (read = Math.max(read, pass !== null && now - passAt < PASS_HOLDS_MS ? pass : now));
  };

  // The board's time for the refresh at `at`, by how often the display
  // has been refreshing (a gap over 100 ms is a pause, not a refresh).
  function boardTime(at) {
    if (lastRefresh !== null && at - lastRefresh < 100) between = 0.8 * between + 0.2 * (at - lastRefresh);
    lastRefresh = at;
    return between >= BOARD_FRAME_MS ? at : Math.round(at / SIXTIETH) * SIXTIETH;
  }

  const ready = BoopMirrorBoard().then(made => {
    core = made;
    usb = core.cwrap('mirror_send', 'number', ['string']);
  });

  // A new board, settled in the state `line` says (none: as it starts up).
  function power(line, frozen) {
    powered = true;
    core._mirror_power();
    usb((line ? line + '\n' : '') + `{"t":"dbg.clock","freeze":${SETTLE_MS}}\n`);
    tick();
    if (!frozen) debug('{"t":"dbg.clock","run":true}');
  }

  // A dbg.* line ends the board's batch, so the lines after it wait for
  // its next pass, as on USB: it has one at once, drawn or not.
  function debug(line) {
    usb(line + '\n');
    core._mirror_tick();
  }

  // What the board says it shows, as a tool on its USB asks (dbg.state),
  // with the pass of its loop that ends that line's batch.
  function shows() {
    usb('{"t":"dbg.state"}\n');
    const said = core.UTF8ToString(core._mirror_said()) || '';
    core._mirror_tick();
    return JSON.parse(said.split('\n').find(l => l.startsWith('{"t":"dbg.state"')) || '{}');
  }

  // One pass of the board's loop, and the frame if it drew one: its
  // pixels where the board keeps them, with no copy, until its memory
  // grows or the frame changes size. The board decides when it has a
  // new frame, as it does on its own screen.
  function tick() {
    if (!core._mirror_tick()) return;
    const w = core._mirror_width(), h = core._mirror_height(), at = core._mirror_frame();
    if (image?.data.buffer !== core.HEAPU8.buffer || image.data.byteOffset !== at || image.width !== w || image.height !== h) {
      image = new ImageData(new Uint8ClampedArray(core.HEAPU8.buffer, at, w * h * 4), w, h);
      panel.width = w, panel.height = h;
    }
    panelContext.putImageData(image, 0, 0);
    paint();
  }

  // What the tile shows of the panel: the slime, zoomed, else the whole
  // screen.
  function source() {
    if (!zoomed) return {x: 0, y: 0, w: panel.width, h: panel.height};
    const x = Math.min(SLIME.x, panel.width - 1), y = Math.min(SLIME.y, panel.height - 1);
    return {x, y, w: Math.min(SLIME.w, panel.width - x), h: Math.min(SLIME.h, panel.height - y)};
  }

  // The source as big as fits and centred: a tile of another shape has
  // glass beside it, as black as the panel, and never loses any of it,
  // the lane included when it's the whole screen. A large shrink goes in
  // halves first.
  function paint() {
    const ratio = devicePixelRatio || 1;
    const w = Math.max(1, Math.round(canvas.clientWidth * ratio)), h = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== w || canvas.height !== h) canvas.width = w, canvas.height = h;
    if (!image) return;
    let from = panel, {x, y, w: sw, h: sh} = source();
    const fit = Math.min(w / sw, h / sh), dw = sw * fit, dh = sh * fit;
    for (let i = 0; sw / dw > MOST_SHRINK; i++) {
      const half = steps[i] ??= document.createElement('canvas');
      const hw = Math.max(1, Math.round(sw / 2)), hh = Math.max(1, Math.round(sh / 2));
      if (half.width !== hw || half.height !== hh) half.width = hw, half.height = hh;
      const halfContext = half.getContext('2d');
      halfContext.imageSmoothingQuality = 'high';
      halfContext.drawImage(from, x, y, sw, sh, 0, 0, hw, hh);
      from = half, x = 0, y = 0, sw = hw, sh = hh;
    }
    context.clearRect(0, 0, w, h);
    context.imageSmoothingQuality = 'high';
    context.drawImage(from, x, y, sw, sh, (w - dw) / 2, (h - dh) / 2, dw, dh);
  }
  new ResizeObserver(paint).observe(canvas);

  // Each display refresh while shown, a pass of the board's loop, which
  // draws when it has a new frame.
  function frame(at) {
    loop = 0;
    if (!shown || still) {
      pass = null;
      return;
    }
    pass = boardTime(at), passAt = realNow();
    if (powered) tick();
    loop = requestAnimationFrame(frame);
  }

  window.BoopMirror = {
    // The board powers on at the first message, settled in the state it
    // has by then, which the app sends as soon as the page has loaded.
    async send(line) {
      const isState = line.startsWith('{"t":"state"');
      if (isState) state = line;
      await ready;
      if (still) return;
      if (!powered) {
        power(state);
        if (isState) return;  // it's in already
      }
      usb(line + '\n');
    },
    async tap(button) {
      await ready;
      if (still) return;
      if (!powered) power(state);
      debug(button ? PRESS : TAP);
    },
    // Shown again, it draws where the board is now at once, not the
    // frame it last drew before it was hidden.
    shown(on) {
      const was = shown;
      shown = Boolean(on);
      if (shown && !was && powered && !still) tick();
      if (shown && !loop) loop = requestAnimationFrame(frame);
    },
    zoom(on) {
      if (zoomed === Boolean(on)) return;
      zoomed = Boolean(on);
      paint();
    },
    async snapshot(line) {
      await ready;
      still = true;
      power(line, true);
      const reply = shows();
      return { screen: reply.screen, base: reply.base, act: reply.act, mood: reply.mood };
    },
    async state() {
      await ready;
      return shows();
    },
  };
})();
