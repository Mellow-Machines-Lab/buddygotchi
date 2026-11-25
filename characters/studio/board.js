// The board itself in the Character Studio (README.md, "On the board"): the
// firmware's own code, built to WebAssembly (simulator/README.md), for the
// face a pack's board has. It plays what the page asks live, from a reset,
// as the Mac and a finger would (logic.js says the messages), and records
// frames on the board's frozen clock (dbg.clock, as the simulator's
// scenarios step it): the faces sheet's stills, and a pack's own tools'
// clips. Both servers serve the build at /simulator/; from file:// it can't
// load.
(() => {
  const SETTLE_MS = 2000;  // how long a recording's start plays before its end is asked for
  const FRAME_MS = window.StudioData?.frame_ms;  // charactergen's: a reference's frames' interval too
  const FROM_FILE = 'The board runs from a server: python3 simulator/web/serve.py, then http://127.0.0.1:8206/characters/studio/.';
  let simulator = null;
  // The simulator's script, and wire() with its tap.
  const load = () => simulator ??= (location.protocol === 'file:' ? Promise.reject(Error(FROM_FILE)) : import('/simulator/boop-simulator.js'))
    .then(sim => ({sim, wire: StudioLogic.wiring({acts: window.StudioData.states.acts, tap: sim.TAP})}));

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
  // hello; with the simulator's script and wire(). The staged pack's has
  // its voice on the card, which the server serves, so its takes play.
  async function make(pack, face) {
    const kit = await load(), staged = window.StudioData.staged === pack;
    const build = `simulator/web/build.sh${staged ? '' : ' ' + pack}`;
    const card = staged ? fetch('/voice.bin').then(r => r.ok ? r.arrayBuffer() : null).catch(() => null) : null;
    const board = await kit.sim.Board.make(staged ? {} : {pack}).catch(() => { throw Error(`There's no build of ${pack} for the board: run ${build}.`); });
    const bytes = await card;
    if (bytes) board.insertCard(new Uint8Array(bytes));
    board.power(true);
    const hello = await request(board, {t: 'hello'}), built = String(hello.pack).split(' ')[0];  // `id version`
    if (built !== pack || hello.face !== face) {
      board.power(false);
      throw Error(`The board's build is ${built}'s with the ${hello.face} face, not ${pack}'s ${face}: run ${build}.`);
    }
    return {...kit, board};
  }

  // Frames from one cell to another on the frozen clock: dbg.reset (which
  // freezes it at 0), the start's messages, then the end's at the change,
  // SETTLE_MS on (and no_app's window later); a frame every FRAME_MS,
  // `before` of them before the change and `after` from it, each with its
  // ms from the change and its picture (an ImageBitmap). Messages due by a
  // frame go before it, as a scenario's lines before its {"clock"}. With no
  // end, the start goes on. Null once `live()` says nobody wants it any more.
  async function record(board, wire, {from, to = null, before = 5, after = 100, live = () => true}) {
    const start = wire(from), end = to && wire(to, start.look);
    const change = SETTLE_MS + start.after, shown = change + (end?.after || 0);
    const due = [...start.steps, ...(end ? end.steps.map(([ms, m]) => [change + ms, m]) : [])].sort((a, b) => a[0] - b[0]);
    board.send({t: 'dbg.reset'});
    const frames = [];
    for (let t = 0, next = 0; t <= shown + after * FRAME_MS; t += FRAME_MS) {
      while (next < due.length && due[next][0] <= t) board.send(due[next++][1]);
      board.send({t: 'dbg.clock', freeze: t});
      if (t >= shown - before * FRAME_MS) {
        await request(board, {t: 'dbg.ping'});  // answered once it has drawn everything before
        frames.push({ms: t - shown, image: await createImageBitmap(board.frame)});
      }
      if (!live()) return null;
    }
    return frames;
  }

  // The board's ImageData on a canvas, as it draws, at its size.
  function draw(canvas, frame) {
    if (canvas.width !== frame.width || canvas.height !== frame.height) [canvas.width, canvas.height] = [frame.width, frame.height];
    canvas.getContext('2d').putImageData(frame, 0, 0);
  }

  // The studio's adapter (README.md, "The board's calls") for one face: a
  // board of its own on the stage, playing what the page asks from a reset.
  // The faces sheet's stills and a pack's tools (its entry's scripts, in the
  // Tools drawer) record on the same board, one at a time, so no other board
  // is kept: it's theirs until the stage plays again, and then it plays the
  // page's steps from a reset.
  function adapter(pack, face) {
    return {create(ctx) {
      const canvas = document.createElement('canvas');
      canvas.className = 'board-screen';
      ctx.stage.append(canvas);
      const making = make(pack, face);
      let kit = null, steps = null, look = null, paused = false, lent = false, gone = false, said = 'Starting the board…';
      let timers = [], beat = 0, turn = making;
      const quiet = () => { timers.forEach(clearTimeout); clearInterval(beat); };
      const vol = () => ctx.sound ? Math.max(1, Math.round(ctx.volume * 10)) : 0;
      // A message at its ms from now; a `state` with the volume the studio's
      // sound has, and kept, the look the heartbeat says again.
      function send(m) {
        if (m.t === 'state') look = m;
        kit.board.send(m.t === 'state' ? {...m, vol: vol()} : m);
      }
      const later = list => list.forEach(([ms, m]) => ms ? timers.push(setTimeout(() => send(m), ms)) : send(m));
      // The page's steps from a reset, the motion rules it has off again,
      // and the look said every so often, as the Mac does.
      function run() {
        if (!kit || !steps || lent) return;
        quiet();
        timers = [];
        look = null;
        kit.board.send({t: 'dbg.reset'});
        ctx.motion().forEach(m => kit.board.send(m));
        later(steps);
        if (!paused) kit.board.send({t: 'dbg.clock', run: true});
        beat = setInterval(() => look && send(look), kit.sim.HEARTBEAT_MS);
      }
      // Lent to a recording: the board comes back to the stage playing the
      // page's steps from a reset, paused or not.
      function lend(then) {
        lent = true;
        quiet();
        return turn = turn.catch(() => {}).then(() => making).then(then);
      }
      making.then(made => {
        if (gone) return made.board.power(false);
        kit = made;
        kit.board.addEventListener('frame', e => { if (!lent) draw(canvas, e.detail); });
        kit.board.addEventListener('line', e => ctx.onLine?.(e.detail));
        said = '';
        run();
        ctx.onChange();
      }, error => {
        // Why it can't run, in the pane where the board would be.
        const note = document.createElement('p');
        note.className = 'board-note';
        note.textContent = error.message;
        ctx.stage.append(note);
        said = null;
        ctx.onChange();
      });
      return {
        // Plays [ms, message] pairs from a reset (logic.js).
        play(list) {
          steps = list;
          run();
        },
        replay: run,
        // Sends [ms, message] pairs now, with no reset: a touch, a switch.
        send(list) {
          if (kit && !lent) later(list);
        },
        // The board's answer to a message, as request() has it.
        ask(message) {
          return kit && !lent ? request(kit.board, message) : Promise.reject(Error('The board is busy'));
        },
        get ready() { return making.then(() => true); },
        get tap() { return kit?.sim.TAP; },
        get paused() { return paused; },
        setPaused(on) {
          paused = on;
          if (lent) turn.catch(() => {}).then(() => { lent = false; run(); });
          else kit?.board.send(on ? {t: 'dbg.clock', step: 0} : {t: 'dbg.clock', run: true});
        },
        record(options) {
          return lend(({board, wire}) => record(board, wire, {...options, live: () => !gone && (options.live?.() ?? true)}));
        },
        // Each face at rest, a still after the look settles, to `each(face,
        // picture)` as it comes; then the stage takes its board back.
        stills(faces, each) {
          return lend(async ({board, wire}) => {
            for (const mood of faces) {
              const frames = await record(board, wire, {from: {mood, state: 'idle'}, before: 0, after: 0, live: () => !gone});
              if (!frames) break;
              each(mood, frames[0].image);
            }
          }).finally(() => this.setPaused(paused));
        },
        setSound() {
          if (!kit) return;
          ctx.sound ? kit.board.unmute() : kit.board.mute();
          if (look && !lent) send(look);
        },
        status() {
          if (said === null) return '';  // the pane says why it can't run
          return said || `The ${face} face's firmware · ${paused ? 'paused' : 'running'} · ${kit.board.audible ? 'sound on' : 'silent'}`;
        },
        destroy() {
          gone = true;
          quiet();
          kit?.board.power(false);
          canvas.remove();
          ctx.stage.querySelector('.board-note')?.remove();
        },
      };
    }};
  }

  window.StudioBoard = {FRAME_MS, adapter};
})();
