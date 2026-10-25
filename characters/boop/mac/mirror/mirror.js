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
//   snapshot(line)  a new board on a frozen clock in that `state`, drawn
//                   once as a scenario's shot draws it; what it says it
//                   shows (its dbg.state), for the app's snapshots to check
//   state()         what the board says it shows now: its dbg.state
'use strict';
(() => {
  // A new board shows its first `state` this long on a frozen clock, as a
  // scenario's shot waits, so it starts settled in it; then it runs.
  const SETTLE_MS = 1504;
  // At most this many frames a second: the board draws up to 60, more
  // than a tile shows. A refresh a little early still draws, so a 60 or
  // 120 Hz display draws every second or fourth.
  const FPS = 30, EARLY_MS = 4;
  // A finger in the canvas's 320×240, beside the nose (a boop on it is a
  // gesture), and BOOT, each held as long as a tap.
  const TAP = '{"t":"dbg.touch","x":80,"y":120,"ms":100}', PRESS = '{"t":"dbg.press","ms":100}';

  const canvas = document.getElementById('screen'), context = canvas.getContext('2d');
  const panel = document.createElement('canvas'), panelContext = panel.getContext('2d');  // the board's own pixels
  let core, usb, image = null, state = null, powered = false, shown = false, still = false, loop = 0, drewAt = -Infinity;

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
  // grows or the frame changes size.
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

  // The board's whole screen, as big as fits and centred: a tile of
  // another shape has glass beside it, as black as the panel, and never
  // loses any of the panel, its lane included.
  function paint() {
    const ratio = devicePixelRatio || 1;
    const w = Math.max(1, Math.round(canvas.clientWidth * ratio)), h = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== w || canvas.height !== h) canvas.width = w, canvas.height = h;
    if (!image) return;
    const fit = Math.min(w / panel.width, h / panel.height), dw = panel.width * fit, dh = panel.height * fit;
    context.clearRect(0, 0, w, h);
    context.imageSmoothingQuality = 'high';
    context.drawImage(panel, (w - dw) / 2, (h - dh) / 2, dw, dh);
  }
  new ResizeObserver(paint).observe(canvas);

  // Each display refresh while shown, a pass of the board's loop at FPS.
  function frame(now) {
    loop = 0;
    if (!shown || still) return;
    if (powered && now - drewAt >= 1000 / FPS - EARLY_MS) drewAt = now, tick();
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
    shown(on) {
      shown = Boolean(on);
      if (shown && !loop) loop = requestAnimationFrame(frame);
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
