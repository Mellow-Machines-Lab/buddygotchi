// The board itself in the Character Studio (README.md, "On the board"): the
// firmware's own code, built to WebAssembly (simulator/README.md), for each
// face a pack's boards have. It plays a mood and state live as the board
// would, records frames from one to another on the board's frozen clock
// (dbg.clock, as the simulator's scenarios step it), and counts how much
// each frame changed. Both servers serve the build at /simulator/; from
// file:// it can't load. Under Node (tests/), the pure parts only.
(() => {
  const FRAME_MS = 40;  // 25 fps, as internal/tools/fluid/ records and boopctl reference cuts
  const SETTLE_MS = 2000;  // how long a recording's start plays before its end is asked for
  const NO_APP_MS = 30000;  // with no state this long, the board takes the Mac for gone (linkkit's kHostGoneMs)
  const LEVELS = 24;  // a pixel changed when its difference's luma is over this (internal/tools/fluid/measure.py)
  const HEARTBEAT_MS = 8000;  // a live board hears its state again this often, as from the Mac

  // How the board is asked for each of the studio's states (states.json). A
  // look is a `state` message: its base, and what the agent is doing while
  // working, or needs you; a reaction is a `do` over a look; the board's own
  // are inputs, at their ms: a tap beside the nose (on it is a gesture), taps
  // in a row, a stroke across.
  const ACTS = ['planning', 'terminal', 'tool_use', 'searching', 'analyzing', 'testing', 'delegating', 'waiting'];
  const WORKING = {base: 'working', busy: 1};
  const LOOKS = {idle: {base: 'idle'}, asleep: {base: 'asleep'}, no_app: WORKING, working: WORKING,
    needs_you: {...WORKING, attn: {id: 1, agent: 'claude', project: 'Studio', more: 0}},
    ...Object.fromEntries(ACTS.map(act => [act, {...WORKING, act}]))};
  const DOES = ['listening', 'starting', 'helper_return', 'reply_ready', 'task_complete', 'error', 'stopped', 'wake_up', 'notice'];
  const TAP = {t: 'dbg.touch', x: 60, y: 120, ms: 60};
  const INPUTS = {poked: [[0, TAP]], tap_spam: [[0, TAP], [200, TAP], [400, TAP]],
    gesture: [[0, {t: 'dbg.touch', x: 60, y: 120, to_x: 220, to_y: 120, ms: 500}]]};
  let ids = 0;

  // What the board is sent to show a cell, as [ms, message] pairs from when
  // it's asked: a look's `state`, or the look a reaction or input plays over
  // (`under`: a transition's start's, else working, or idle for waking up
  // and a stroke) and then it. `after` is how long the board takes to show
  // it with nothing more said: no_app's window.
  function wire({mood, state, outcome = 'success', context = 'new_task'}, under = null, vol = 0) {
    if (LOOKS[state]) return {look: LOOKS[state], after: state === 'no_app' ? NO_APP_MS : 0, steps: [[0, {t: 'state', ...LOOKS[state], mood, vol}]]};
    const look = under || (state === 'wake_up' || state === 'gesture' ? LOOKS.idle : WORKING);
    const steps = [[0, {t: 'state', ...look, mood, vol}]];
    if (DOES.includes(state)) {
      const args = state === 'task_complete' ? {outcome} : state === 'starting' ? {ctx: context} : {};
      steps.push([0, {t: 'do', id: ++ids, name: state, play: 'now', args}]);
    } else if (INPUTS[state]) steps.push(...INPUTS[state]);
    else throw Error(`The board has no state ${state}`);
    return {look, after: 0, steps};
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
  // A recording's changes in measure.py's terms: the median, the largest and
  // where, and their ratio, which is a cut when it's several times the median.
  function summary(changes) {
    const sorted = [...changes].sort((a, b) => a - b), median = sorted[sorted.length >> 1] || 0;
    const at = changes.indexOf(Math.max(...changes));
    return {median, largest: changes[at], at, ratio: changes[at] / Math.max(median, 1)};
  }

  if (typeof module !== 'undefined') {
    module.exports = {wire, changed, summary};
    return;
  }

  const FROM_FILE = 'The board runs from a server: node characters/studio/serve.cjs --port 4190, then http://127.0.0.1:4190/.';
  let simulator = null;
  const load = () => simulator ??= location.protocol === 'file:' ? Promise.reject(Error(FROM_FILE)) : import('/simulator/boop-simulator.js');
  const sleep = ms => new Promise(ok => setTimeout(ok, ms));

  // The first line the board says that starts with {"t":"T", after sending it `message`.
  function request(board, message, t = message.t, ms = 30000) {
    return new Promise((ok, fail) => {
      const timer = setTimeout(() => { board.removeEventListener('line', heard); fail(Error(`The board didn't answer ${t}`)); }, ms);
      const heard = e => {
        if (!e.detail.startsWith(`{"t":"${t}"`)) return;
        clearTimeout(timer);
        board.removeEventListener('line', heard);
        ok(JSON.parse(e.detail));
      };
      board.addEventListener('line', heard);
      board.send(message);
    });
  }

  // A board running a pack's build with one of its faces: the staged pack's
  // simulator/web/build.sh, or build.sh PACK for another, checked by its hello.
  async function make(pack, face) {
    const {Board} = await load(), staged = window.StudioData.staged === pack;
    const build = `simulator/web/build.sh${staged ? '' : ' ' + pack}`;
    const board = await Board.make(staged ? {} : {pack}).catch(() => { throw Error(`There's no build of ${pack} for the board: run ${build}.`); });
    board.power(true, {face});
    const hello = await request(board, {t: 'hello'});
    if (hello.pack !== pack || hello.face !== face) {
      board.power(false);
      throw Error(`The board's build is ${hello.pack}'s with the ${hello.face} face, not ${pack}'s ${face}: run ${build}.`);
    }
    return board;
  }

  // The frame the board has drawn by now, once it has answered a ping sent
  // after everything before: a copy, since the board draws into one ImageData.
  async function shot(board) {
    await request(board, {t: 'dbg.ping'});
    const f = board.frame;
    return new ImageData(new Uint8ClampedArray(f.data), f.width, f.height);
  }

  // Frames from one cell to another on the frozen clock: dbg.reset (which
  // freezes it at 0), the start's messages, then the end's at the change,
  // SETTLE_MS on (and no_app's window later); a frame every FRAME_MS,
  // `before` of them before the change and `after` from it, each with its
  // ms from the change. Messages due by a frame go before it, as a
  // scenario's lines before its {"clock"}. With no end, the start goes on.
  // Null once `live()` says nobody wants it any more.
  async function record(board, {from, to = null, before = 5, after = 100, live = () => true}) {
    const start = wire(from), end = to && wire(to, start.look);
    const change = SETTLE_MS + start.after, shown = change + (end?.after || 0);
    const due = [...start.steps, ...(end ? end.steps.map(([ms, m]) => [change + ms, m]) : [])].sort((a, b) => a[0] - b[0]);
    board.send({t: 'dbg.reset'});
    const frames = [];
    for (let t = 0, next = 0; t <= shown + after * FRAME_MS; t += FRAME_MS) {
      while (next < due.length && due[next][0] <= t) board.send(due[next++][1]);
      board.send({t: 'dbg.clock', freeze: t});
      if (t >= shown - before * FRAME_MS) frames.push({ms: t - shown, image: await shot(board)});
      if (!live()) return null;
    }
    return frames;
  }

  // The views' recordings, on a board of each pack and face kept for them,
  // one recording at a time; release() powers them off.
  const recorders = {};
  function recorder(pack, face) {
    return recorders[pack + '/' + face] ??= (() => {
      const made = make(pack, face);
      let turn = made;
      return {made, record: options => turn = turn.catch(() => {}).then(() => made).then(board => record(board, options))};
    })();
  }
  function release() {
    for (const [key, {made}] of Object.entries(recorders)) {
      made.then(board => board.power(false), () => {});
      delete recorders[key];
    }
  }

  function draw(canvas, frame) {
    if (canvas.width !== frame.width || canvas.height !== frame.height) [canvas.width, canvas.height] = [frame.width, frame.height];
    canvas.getContext('2d').putImageData(frame, 0, 0);
  }

  // The studio's adapter (README.md, "Writing an adapter") for one face: a
  // board of its own, playing the selection live from a reset, as the Mac
  // would ask for it. A matrix cell's steps its clock 100 ms ten times a
  // second instead, so many play at once.
  function adapter(pack, face) {
    return {transport: 'live', variantLabel: 'Variation', create(ctx) {
      const canvas = document.createElement('canvas');
      canvas.className = 'board-screen';
      ctx.stage.append(canvas);
      let board = null, cell = null, look = null, paused = false, gone = false, said = 'Starting the board…', timers = [], beat = 0, stepping = 0;
      // Its `state` again, with the volume the studio's sound has now.
      const say = () => board.send({...look, vol: ctx.sound ? Math.max(1, Math.round(ctx.volume * 10)) : 0});
      function play() {
        if (!board || !cell) return;
        timers.forEach(clearTimeout);
        clearInterval(beat);
        const {steps, after} = wire(cell);
        look = steps[0][1];
        board.send({t: 'dbg.reset'});
        say();
        timers = steps.slice(1).map(([ms, m]) => setTimeout(() => board.send(m), ms));
        if (after) board.send({t: 'dbg.clock', freeze: after});
        if (!paused && !stepping) board.send({t: 'dbg.clock', run: true});
        if (!after) beat = setInterval(say, HEARTBEAT_MS);
      }
      make(pack, face).then(made => {
        if (gone) return made.power(false);
        board = made;
        board.addEventListener('frame', e => draw(canvas, e.detail));
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
          stepping = setInterval(() => board?.send({t: 'dbg.clock', step: 100}), 100);
        },
        get paused() { return paused; },
        setPaused(on) { paused = on; board?.send(on ? {t: 'dbg.clock', step: 0} : {t: 'dbg.clock', run: true}); },
        replay: play,
        poke() { board?.send(TAP); },
        async shake() {
          const {SHAKE} = await load();
          for (const [az, ms] of SHAKE) { board?.motion(0, 0, az); await sleep(ms); }
        },
        setSound() {
          if (!board) return;
          ctx.sound ? board.unmute() : board.mute();
          if (look) say();
        },
        status() { return said || `The ${face} face's firmware, picking its own variations · ${paused ? 'paused' : 'running'} · ${board.audible ? 'sound on' : 'silent'}`; },
        destroy() {
          gone = true;
          timers.forEach(clearTimeout);
          clearInterval(beat);
          clearInterval(stepping);
          board?.power(false);
          canvas.remove();
        },
      };
    }};
  }

  window.StudioBoard = {FRAME_MS, changed, summary, recorder, release, draw, adapter};
})();
