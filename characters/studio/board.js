// The board itself in the Character Studio (README.md, "On the board"): the
// firmware's own code, built to WebAssembly (simulator/README.md), for each
// face a pack's boards have. It plays a mood and state live as the board
// would, records frames from one to another on the board's frozen clock
// (dbg.clock, as the simulator's scenarios step it), and counts how much
// each frame changed. Both servers serve the build at /simulator/; from
// file:// it can't load. Under Node (tests/), the pure parts only.
(() => {
  const SETTLE_MS = 2000;  // how long a recording's start plays before its end is asked for
  const NO_APP_MS = 30000;  // with no state this long, the board takes the Mac for gone (linkkit's kHostGoneMs)
  const LEVELS = 24;  // a pixel changed when its difference's luma is over this (internal/tools/fluid/measure.py)
  const DOES = ['listening', 'starting', 'helper_return', 'reply_ready', 'task_complete', 'error', 'stopped', 'wake_up', 'notice'];
  const STROKE = {t: 'dbg.touch', x: 60, y: 120, to_x: 220, to_y: 120, ms: 500};

  // How the board is asked for each of the studio's states (states.json),
  // given the acts it draws while working (StudioData.states.acts, which
  // charactergen reads from the firmware) and where the simulator taps
  // (boop-simulator.js's TAP). A look is a `state` message: its base, and
  // what the agent is doing while working, or needs you; a reaction is a
  // `do` over a look; the board's own are inputs, at their ms: a tap, taps
  // in a row, a stroke across.
  //
  // wire(cell, under, vol) is what the board is sent to show a cell, as
  // [ms, message] pairs from when it's asked: a look's `state`, or the look
  // a reaction or input plays over (working, or idle for waking up and a
  // stroke) and then it. As a transition's end, over its start's look
  // (`under`), a reaction is asked in its own mood, as the Mac asks for one,
  // and the start's `state` stays. `after` is how long the board takes to
  // show it with nothing more said: no_app's window.
  function wiring({acts, tap}) {
    const WORKING = {base: 'working', busy: 1};
    const LOOKS = {idle: {base: 'idle'}, asleep: {base: 'asleep'}, no_app: WORKING, working: WORKING,
      needs_you: {...WORKING, attn: {id: 1, agent: 'claude', project: 'Studio', more: 0}},
      ...Object.fromEntries(acts.map(act => [act, {...WORKING, act}]))};
    const TOUCH = {t: 'dbg.touch', x: tap[0], y: tap[1], ms: 60};
    const INPUTS = {poked: [[0, TOUCH]], tap_spam: [[0, TOUCH], [200, TOUCH], [400, TOUCH]], gesture: [[0, STROKE]]};
    let ids = 0;
    return function wire({mood, state, outcome = 'success', context = 'new_task'}, under = null, vol = 0) {
      if (LOOKS[state]) return {look: LOOKS[state], after: state === 'no_app' ? NO_APP_MS : 0, steps: [[0, {t: 'state', ...LOOKS[state], mood, vol}]]};
      const look = under || (state === 'wake_up' || state === 'gesture' ? LOOKS.idle : WORKING);
      const does = DOES.includes(state), steps = under && does ? [] : [[0, {t: 'state', ...look, mood, vol}]];
      if (does) {
        const args = state === 'task_complete' ? {outcome} : state === 'starting' ? {ctx: context} : {};
        steps.push([0, {t: 'do', id: ++ids, name: state, play: 'now', args: under ? {...args, mood} : args}]);
      } else if (INPUTS[state]) steps.push(...INPUTS[state]);
      else throw Error(`The board has no state ${state}`);
      return {look, after: 0, steps};
    };
  }

  // Pixels changed from one frame to the next (RGBA bytes): those whose
  // difference's luma is over LEVELS, as measure.py counts them with Pillow
  // (ImageChops.difference, then convert("L"), whose luma is this integer one).
  function changed(a, b) {
    let n = 0;
    for (let i = 0; i < a.length; i += 4) {
      const luma = (Math.abs(a[i] - b[i]) * 19595 + Math.abs(a[i + 1] - b[i + 1]) * 38470 + Math.abs(a[i + 2] - b[i + 2]) * 7471 + 0x8000) >> 16;
      if (luma > LEVELS) n++;
    }
    return n;
  }
  // A transition's changes in measure.py's terms (its summary(), the same
  // rule, which internal/tools/fluid/tests/changed.json pins for both): the
  // median, the upper of the middle two; the largest and where, the first;
  // and their ratio, several times the median for a cut.
  function summary(changes) {
    const median = [...changes].sort((a, b) => a - b)[changes.length >> 1], at = changes.indexOf(Math.max(...changes));
    return {median, largest: changes[at], at, ratio: changes[at] / Math.max(median, 1)};
  }

  if (typeof module !== 'undefined') {
    module.exports = {wiring, changed, summary};
    return;
  }

  const FRAME_MS = window.StudioData?.frame_ms;  // charactergen's, a reference's frames' too: the References view pairs them
  const FROM_FILE = 'The board runs from a server: node characters/studio/serve.cjs --port 4190, then http://127.0.0.1:4190/.';
  let simulator = null;
  // The simulator's script, and wire() with its tap.
  const load = () => simulator ??= (location.protocol === 'file:' ? Promise.reject(Error(FROM_FILE)) : import('/simulator/boop-simulator.js'))
    .then(sim => ({sim, wire: wiring({acts: window.StudioData.states.acts, tap: sim.TAP})}));
  const sleep = ms => new Promise(ok => setTimeout(ok, ms));

  // The first line the board says that starts with {"t":"T", after sending
  // it `message`; it fails if the board goes off first.
  function request(board, message, t = message.t, ms = 30000) {
    return new Promise((ok, fail) => {
      const done = (error, said) => {
        clearTimeout(timer);
        board.removeEventListener('line', heard);
        board.removeEventListener('power', off);
        error ? fail(error) : ok(said);
      };
      const heard = e => { if (e.detail.startsWith(`{"t":"${t}"`)) done(null, JSON.parse(e.detail)); };
      const off = e => { if (!e.detail) done(Error('The board went off')); };
      const timer = setTimeout(() => done(Error(`The board didn't answer ${t}`)), ms);
      board.addEventListener('line', heard);
      board.addEventListener('power', off);
      board.send(message);
    });
  }

  // A board running a pack's build with one of its faces: the staged pack's
  // simulator/web/build.sh, or build.sh PACK for another, checked by its
  // hello; with the simulator's script and wire().
  async function make(pack, face) {
    const kit = await load(), staged = window.StudioData.staged === pack;
    const build = `simulator/web/build.sh${staged ? '' : ' ' + pack}`;
    const board = await kit.sim.Board.make(staged ? {} : {pack}).catch(() => { throw Error(`There's no build of ${pack} for the board: run ${build}.`); });
    board.power(true, {face});
    const hello = await request(board, {t: 'hello'});
    if (hello.pack !== pack || hello.face !== face) {
      board.power(false);
      throw Error(`The board's build is ${hello.pack}'s with the ${hello.face} face, not ${pack}'s ${face}: run ${build}.`);
    }
    return {...kit, board};
  }

  // Frames from one cell to another on the frozen clock: dbg.reset (which
  // freezes it at 0), the start's messages, then the end's at the change,
  // SETTLE_MS on (and no_app's window later); a frame every FRAME_MS,
  // `before` of them before the change and `after` from it, each with its
  // ms from the change, how many pixels changed from the one before (0 for
  // the first), counted as it comes, and its picture (an ImageBitmap; none
  // with `pictures` false). Messages due by a frame go before it, as a
  // scenario's lines before its {"clock"}. With no end, the start goes on.
  // `heard(frame)` hears each as it comes. Null once `live()` says nobody
  // wants it any more.
  async function record(board, wire, {from, to = null, before = 5, after = 100, live = () => true, pictures = true, heard = () => {}}) {
    const start = wire(from), end = to && wire(to, start.look);
    const change = SETTLE_MS + start.after, shown = change + (end?.after || 0);
    const due = [...start.steps, ...(end ? end.steps.map(([ms, m]) => [change + ms, m]) : [])].sort((a, b) => a[0] - b[0]);
    board.send({t: 'dbg.reset'});
    const frames = [];
    let last = null;  // the frame before's pixels: the board draws every frame into one ImageData
    for (let t = 0, next = 0; t <= shown + after * FRAME_MS; t += FRAME_MS) {
      while (next < due.length && due[next][0] <= t) board.send(due[next++][1]);
      board.send({t: 'dbg.clock', freeze: t});
      if (t >= shown - before * FRAME_MS) {
        await request(board, {t: 'dbg.ping'});  // answered once it has drawn everything before
        const image = board.frame, frame = {ms: t - shown, change: last ? changed(last, image.data) : 0, image: null};
        if (last?.length === image.data.length) last.set(image.data);
        else last = image.data.slice();
        if (pictures) frame.image = await createImageBitmap(image);
        frames.push(frame);
        heard(frame);
      }
      if (!live()) return null;
    }
    return frames;
  }

  // A frame on a canvas: the board's ImageData as it draws, at its size, or
  // a recorded ImageBitmap, at its size or `width` wide.
  function draw(canvas, frame, width = frame.width) {
    const height = Math.round(frame.height * width / frame.width);
    if (canvas.width !== width || canvas.height !== height) [canvas.width, canvas.height] = [width, height];
    if (frame instanceof ImageData) canvas.getContext('2d').putImageData(frame, 0, 0);
    else canvas.getContext('2d').drawImage(frame, 0, 0, width, height);
    return canvas;
  }

  // The studio's adapter (README.md, "Writing an adapter") for one face: a
  // board of its own, playing the selection live from a reset, as the Mac
  // would ask for it. A matrix cell's steps its clock 100 ms ten times a
  // second instead, so many play at once. The board's views record on the
  // stage's board, one recording at a time (`record(options)`), so no
  // other board is kept: it's theirs until the stage plays again, and then
  // it plays the selection from a reset.
  function adapter(pack, face) {
    return {transport: 'live', variantLabel: 'Variation', create(ctx) {
      const canvas = document.createElement('canvas');
      canvas.className = 'board-screen';
      ctx.stage.append(canvas);
      const making = make(pack, face);
      let kit = null, cell = null, look = null, paused = false, lent = false, gone = false, said = 'Starting the board…';
      let timers = [], beat = 0, stepping = 0, turn = making;
      const quiet = () => { timers.forEach(clearTimeout); clearInterval(beat); };
      // Its `state` again, with the volume the studio's sound has now.
      const say = () => kit.board.send({...look, vol: ctx.sound ? Math.max(1, Math.round(ctx.volume * 10)) : 0});
      function play() {
        if (!kit || !cell || lent) return;
        quiet();
        const {steps, after} = kit.wire(cell), board = kit.board;
        look = steps[0][1];
        board.send({t: 'dbg.reset'});
        say();
        timers = steps.slice(1).map(([ms, m]) => setTimeout(() => board.send(m), ms));
        if (after) board.send({t: 'dbg.clock', freeze: after});
        if (!paused && !stepping) board.send({t: 'dbg.clock', run: true});
        if (!after) beat = setInterval(say, kit.sim.HEARTBEAT_MS);
      }
      making.then(made => {
        if (gone) return made.board.power(false);
        kit = made;
        kit.board.addEventListener('frame', e => { if (!lent) draw(canvas, e.detail); });
        said = '';
        play();
        ctx.onChange();
      }, error => { said = error.message; ctx.onChange(); });
      return {
        select(s) {
          cell = {mood: s.mood, state: s.state, outcome: s.outcome, context: s.context};
          play();
          return {variants: [], caption: ''};
        },
        preview() {
          stepping = setInterval(() => kit?.board.send({t: 'dbg.clock', step: 100}), 100);
        },
        get paused() { return paused; },
        // Lent to a view's recording, the board comes back to the stage
        // playing the selection from a reset, paused or not.
        setPaused(on) {
          paused = on;
          if (lent) turn.catch(() => {}).then(() => { lent = false; play(); });
          else kit?.board.send(on ? {t: 'dbg.clock', step: 0} : {t: 'dbg.clock', run: true});
        },
        record(options) {
          lent = true;
          quiet();
          return turn = turn.catch(() => {}).then(() => making)
            .then(({board, wire}) => record(board, wire, {...options, live: () => !gone && (options.live?.() ?? true)}));
        },
        replay: play,
        poke() {
          if (!kit) return;
          kit.board.touch(...kit.sim.TAP);
          kit.board.release();
        },
        async shake() {
          for (const [az, ms] of kit?.sim.SHAKE || []) { kit.board.motion(0, 0, az); await sleep(ms); }
        },
        setSound() {
          if (!kit) return;
          ctx.sound ? kit.board.unmute() : kit.board.mute();
          if (look && !lent) say();
        },
        status() {
          return said || `The ${face} face's firmware, picking its own variations · ${paused ? 'paused' : 'running'} · ${kit.board.audible ? 'sound on' : 'silent'}`;
        },
        destroy() {
          gone = true;
          quiet();
          clearInterval(stepping);
          kit?.board.power(false);
          canvas.remove();
        },
      };
    }};
  }

  window.StudioBoard = {FRAME_MS, changed, summary, draw, adapter};
})();
