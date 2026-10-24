// The Mac's mirror of the board (characters/CHARACTER.md §9): the board's
// own firmware as WebAssembly (board.js, which firmware/tools/mirror.sh
// builds), fed the messages the Mac sends the board, its screen drawn
// here. It makes no sound, and nothing it says leaves this page.
//
// The app (app/Boop/Views/Slime/SlimeFeed.swift) calls window.BoopMirror:
//   send(line)      a message the board got: a `state`, or a `do`
//   tap()           a finger on the board's screen, which it reacts to itself
//   shown(on)       whether it's on screen: it draws only then, and runs either way
//   snapshot(line)  a new board on a frozen clock in that `state`, drawn
//                   once as a scenario's shot draws it; what it says it
//                   shows (its dbg.state), for the app's snapshots to check
'use strict';
(() => {
  // The Mac says its `state` again every 10 s, and a board that hears
  // nothing for 30 s takes its Mac for gone: this says the last one every 8 s.
  const HEARTBEAT_MS = 8000;
  // A new board shows its first `state` this long on a frozen clock, as a
  // scenario's shot waits, so it starts settled in it; then it runs.
  const SETTLE_MS = 1504;
  // A finger in the canvas's 320×240, beside the nose (a boop on it is a gesture).
  const TAP = '{"t":"dbg.touch","x":80,"y":120,"ms":100}';

  const canvas = document.getElementById('screen'), context = canvas.getContext('2d');
  const panel = document.createElement('canvas'), panelContext = panel.getContext('2d');  // the board's own pixels
  let core, usb, image = null, state = null, powered = false, shown = false, still = false, loop = 0;

  const ready = BoopMirrorBoard().then(made => {
    core = made;
    usb = core.cwrap('mirror_send', 'number', ['string']);
    setInterval(() => { if (powered && !still && state) usb(state + '\n'); }, HEARTBEAT_MS);
  });

  // A new board, settled in the state `line` says (none: as it starts up).
  function power(line, frozen) {
    powered = true;
    core._mirror_power(1);
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

  // One pass of the board's loop, and the frame if it drew one.
  function tick() {
    if (!core._mirror_tick()) return;
    const w = core._mirror_width(), h = core._mirror_height(), at = core._mirror_frame();
    if (image?.width !== w || image?.height !== h) {
      image = new ImageData(w, h);
      panel.width = w, panel.height = h;
    }
    image.data.set(core.HEAPU8.subarray(at, at + w * h * 4));
    panelContext.putImageData(image, 0, 0);
    paint();
  }

  // The board's screen as tall as the canvas, centred: a tile wider than
  // the panel has glass either side, as black as the panel, and a square
  // one loses a little of the panel's sides, beyond the slime.
  function paint() {
    const ratio = devicePixelRatio || 1;
    const w = Math.max(1, Math.round(canvas.clientWidth * ratio)), h = Math.max(1, Math.round(canvas.clientHeight * ratio));
    if (canvas.width !== w || canvas.height !== h) canvas.width = w, canvas.height = h;
    if (!image) return;
    const dw = panel.width * h / panel.height;
    context.clearRect(0, 0, w, h);
    context.imageSmoothingQuality = 'high';
    context.drawImage(panel, (w - dw) / 2, 0, dw, h);
  }
  new ResizeObserver(paint).observe(canvas);

  // Each display refresh while shown; the board draws at most every 16 ms.
  function frame() {
    loop = 0;
    if (!shown || still) return;
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
    async tap() {
      await ready;
      if (still) return;
      if (!powered) power(state);
      debug(TAP);
    },
    shown(on) {
      shown = Boolean(on);
      if (shown && !loop) loop = requestAnimationFrame(frame);
    },
    async snapshot(line) {
      await ready;
      still = true;
      power(line, true);
      usb('{"t":"dbg.state"}\n');
      const said = core.UTF8ToString(core._mirror_said() || 0) || '';
      const reply = JSON.parse(said.split('\n').find(l => l.startsWith('{"t":"dbg.state"')) || '{}');
      return { screen: reply.screen, base: reply.base, act: reply.act, mood: reply.mood };
    },
  };
})();
