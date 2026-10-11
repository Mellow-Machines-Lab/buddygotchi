// Boop Simulator in a page (simulator/README.md): the board's firmware,
// built to WebAssembly, with this script as its screen, finger, BOOT
// button, speaker, light and card.
//
//   <script type="module" src="boop-simulator.js"></script>
//   <boop-simulator face="pixel"></boop-simulator>
//
// Nothing here draws on the screen: every pixel there is the firmware's.

import makeCore from './boop-sim.js';

const CHUNK = 512;       // app::Sound::kChunk
const OUT_RATE = 22050;  // voice::kOutRate
const TOUCH_MS = 80;     // the shortest touch
const CANVAS = [320, 240];  // a touch is in the canvas's pixels on every board

/// One simulated board: the core, switched on and off, with its USB as
/// lines in and out. A page can have several.
export class Board extends EventTarget {
  #core; #usb; #env; #input; #timer = 0; #parts = '';
  #audio = null; #soundAt = 0; #muted = false;
  #voice = null;

  /// The picture the board last drew, for whoever shows it.
  frame = null;
  on = false;

  static async make() {
    const board = new Board();
    board.#core = await makeCore();
    board.#usb = board.#core.cwrap('sim_usb', null, ['string']);
    board.#env = board.#core.cwrap('sim_env', null, ['string', 'string']);
    board.#input = board.#core.cwrap('sim_input', null, ['string']);
    return board;
  }

  /// Power: on is a new boot with nothing remembered, as on a board.
  /// `face` is `pixel` or `gel`; `native` a native face's panel, `502x410`.
  power(on, { face = 'pixel', native } = {}) {
    clearInterval(this.#timer);
    if (on) {
      this.#env('BOOP_SIM_FACE', face);
      if (native) this.#env('BOOP_SIM_NATIVE', native);
    }
    this.#core._sim_power(on ? 1 : 0);
    this.on = !!on;
    this.frame = null;
    this.#parts = '';
    this.dispatchEvent(new CustomEvent('power', { detail: this.on }));
    if (!on) return;
    this.#soundAt = this.#clock();
    // The board's loop: its lines, a frame when it drew one, its sound.
    this.#timer = setInterval(() => this.#pass(), 4);
    this.#pass();
  }

  /// A line to the board's USB, as a host sends it: text, or an object as JSON.
  send(line) {
    if (this.on) this.#usb((typeof line === 'string' ? line : JSON.stringify(line)) + '\n');
  }

  /// The finger, in the canvas's 320×240, and the BOOT button.
  /// A click is over in a millisecond or two, sooner than any finger and
  /// than the board looks, so a touch lasts at least TOUCH_MS.
  touch(x, y) {
    clearTimeout(this.#lift);
    if (!this.#touched) this.#touched = performance.now();
    this.#say(`touch ${Math.round(x)} ${Math.round(y)}`);
  }
  release() {
    const lift = () => { this.#touched = 0; this.#say('release'); };
    this.#lift = setTimeout(lift, Math.max(0, TOUCH_MS - (performance.now() - this.#touched)));
  }
  #touched = 0; #lift = 0;
  boot(down) { this.#say(`boot ${down ? 1 : 0}`); }

  /// The card: a voice pack's bytes go in, or it comes out.
  insertCard(bytes) {
    if (bytes) this.#voice = bytes;
    if (!this.#voice) return;
    // Its room first: making it may move the core's memory.
    const at = this.#core._sim_card(this.#voice.length);
    this.#core.HEAPU8.set(this.#voice, at);
    this.#say('card in');
  }
  ejectCard() { this.#say('card out'); }

  /// Sound needs a click first, as every browser asks: call this from one.
  async unmute() {
    this.#muted = false;
    this.#audio ??= new AudioContext();
    await this.#audio.resume();
    this.#soundAt = this.#clock();
  }
  mute() {
    this.#muted = true;
    this.#audio?.suspend();
    this.#soundAt = this.#clock();
  }
  get audible() { return !!this.#audio && this.#audio.state === 'running' && !this.#muted; }

  #say(line) { if (this.on) this.#input(line); }
  #clock() { return this.audible ? this.#audio.currentTime : performance.now() / 1000; }

  #pass() {
    const core = this.#core;
    if (core._sim_tick()) {
      const w = core._sim_width(), h = core._sim_height(), at = core._sim_frame();
      this.frame = new ImageData(new Uint8ClampedArray(core.HEAPU8.buffer, at, w * h * 4).slice(), w, h);
      this.dispatchEvent(new CustomEvent('frame', { detail: this.frame }));
    }
    const said = core.UTF8ToString(core._sim_usb_out());
    for (const line of said.split('\n')) if (line) this.dispatchEvent(new CustomEvent('line', { detail: line }));
    const parts = core.UTF8ToString(core._sim_parts());
    if (parts !== this.#parts) {
      this.#parts = parts;
      this.dispatchEvent(new CustomEvent('parts', { detail: JSON.parse(parts) }));
    }
    this.#sound();
  }

  // The board makes its sound a chunk at a time, at the pace it plays:
  // each is asked for a little before it's due, and queued on the page's
  // audio; with no audio yet, or muted, it's made all the same and dropped,
  // so a line still takes as long as it takes.
  #sound() {
    const now = this.#clock();
    if (this.#soundAt < now - 0.2) this.#soundAt = now;  // the tab slept: don't catch up
    while (this.#soundAt < now + 0.1) {
      const at = this.#core._sim_sound();
      if (at && this.audible) {
        const buffer = this.#audio.createBuffer(1, CHUNK, OUT_RATE);
        const out = buffer.getChannelData(0), samples = this.#core.HEAPU8.subarray(at, at + CHUNK);
        for (let i = 0; i < CHUNK; i++) out[i] = (samples[i] - 128) / 128;
        const source = this.#audio.createBufferSource();
        source.buffer = buffer;
        source.connect(this.#audio.destination);
        source.start(Math.max(this.#soundAt, this.#audio.currentTime));
      }
      this.#soundAt += CHUNK / OUT_RATE;
    }
  }
}


/// Plays a demo's recording into a board (DemoRecording, which the app's
/// `Boop --headless --demo … --record` writes): every line the app sent
/// the device, when it sent it, so the firmware does what it did, with no
/// app behind it. It fires `cause` for what happens (`{kind, text}`),
/// `effect` for what the creature does about it (words), `time` as it
/// goes and `end`.
export class DemoPlayer extends EventTarget {
  #board; #recording; #next = 0; #at = 0; #from = 0; #timer = 0; #state = null; #told = 0;
  #mood = ''; #needs = false;
  playing = false;

  constructor(board, recording) {
    super();
    if (recording.version !== 1) throw new Error(`a recording of version ${recording.version}, and this page plays 1`);
    this.#board = board;
    this.#recording = recording;
  }

  get recording() { return this.#recording; }
  get length() { return this.#recording.length; }
  /// Seconds into the demo.
  get position() { return this.playing ? Math.min(this.length, this.#at + (performance.now() - this.#from) / 1000) : this.#at; }
  get ended() { return this.#next >= this.#recording.events.length && this.position >= this.length; }

  play() {
    if (this.playing) return;
    if (this.ended) this.#rewind();
    this.playing = true;
    this.#from = performance.now();
    clearInterval(this.#timer);
    this.#timer = setInterval(() => this.#pass(), 30);
  }

  /// The story stops; the board is kept company, as an app keeps it, so
  /// it doesn't take its app for gone.
  pause() {
    if (!this.playing) return;
    this.#at = this.position;
    this.playing = false;
  }

  /// From the top, on a board that knows nothing of the last time.
  restart() {
    this.#rewind();
    this.play();
  }

  stop() { clearInterval(this.#timer); this.playing = false; }

  #rewind() {
    this.#next = 0;
    this.#at = 0;
    this.#state = null;
    this.#mood = '';
    this.#needs = false;
    this.dispatchEvent(new CustomEvent('rewind'));
  }

  #pass() {
    const now = this.position, events = this.#recording.events;
    while (this.playing && this.#next < events.length && events[this.#next].at <= now) this.#happen(events[this.#next++]);
    // The app says how things stand every 10 s; so does this, while the
    // recording doesn't (paused, or over).
    if (this.#state && performance.now() - this.#told > 8000) this.#send(this.#state);
    this.dispatchEvent(new CustomEvent('time', { detail: now }));
    if (this.playing && this.ended) {
      this.#at = this.length;
      this.playing = false;
      this.dispatchEvent(new CustomEvent('end'));
    }
  }

  #send(line) {
    this.#told = performance.now();
    this.#board.send(line);
  }

  #happen(event) {
    if (event.cause) {
      this.dispatchEvent(new CustomEvent('cause', { detail: event.cause }));
      // A poke is a finger on the screen, and the board's own to react to.
      if (event.cause.kind === 'tap') {
        this.#board.touch(160, 120);
        this.#board.release();
      }
      return;
    }
    let message;
    try { message = JSON.parse(event.line); } catch { return; }
    if (message.t === 'state') this.#state = event.line;
    this.#send(event.line);
    const effect = this.#effect(message, event.says);
    if (effect) this.dispatchEvent(new CustomEvent('effect', { detail: effect }));
  }

  // What the creature does, in words, from what the device was just told.
  #effect(message, says) {
    const name = this.#recording.name, said = says ? ` and says “${says}”` : '';
    if (message.t === 'state') {
      const needs = !!message.attn, mood = message.mood ?? '';
      const was = this.#needs, before = this.#mood;
      this.#needs = needs;
      this.#mood = mood;
      this.dispatchEvent(new CustomEvent('state', { detail: { base: needs ? 'needs you' : message.base, mood } }));
      if (needs && !was) return `${name} shows that it needs you`;
      if (before && mood && mood !== before) return `${name}'s mood is now ${mood}`;
      return null;
    }
    if (message.t !== 'do') return null;
    const mood = message.args?.mood;
    switch (message.name) {
      case 'react': return `${name} ${mood ? `makes ${/^[aeiou]/.test(mood) ? 'an' : 'a'} ${mood} face` : 'reacts'}${said}`;
      case 'task_complete': return `${name} ${message.args?.outcome === 'failure' ? 'slumps' : 'celebrates'}${said}`;
      case 'reply_ready': return `${name} perks up${said}`;
      case 'error': return `${name} winces`;
      case 'listening': return `${name} listens`;
      default: return null;
    }
  }
}

const STYLE = `
  :host { display: inline-block; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; color: #999; }
  .body { background: #212121; border-radius: 18px; padding: 22px 22px 12px; }
  canvas { display: block; background: #000; border-radius: 6px; image-rendering: pixelated; touch-action: none;
           cursor: pointer; width: var(--w); height: var(--h); }
  .chin { display: flex; align-items: center; gap: 8px; height: 34px; }
  button { font: inherit; color: #bbb; background: #383838; border: 0; border-radius: 5px; padding: 3px 10px; cursor: pointer; }
  button:active, button.down { background: #666; }
  .led { margin-left: auto; width: 10px; height: 10px; border-radius: 50%; background: #333; }
  .status { padding: 6px 4px 0; min-height: 1.3em; }
  .space { flex: 1; }
  .screen { position: relative; }
  .finger { position: absolute; left: 50%; top: 50%; width: 46px; height: 46px; margin: -23px; border-radius: 50%;
            border: 2px solid #fff; opacity: 0; pointer-events: none; }
  .finger.down { animation: finger .6s ease-out; }
  @keyframes finger { from { opacity: .9; transform: scale(.3); } to { opacity: 0; transform: scale(1.4); } }
  .demo { margin-top: 10px; width: 0; min-width: 100%; color: #bbb; }
  .bar { display: flex; align-items: center; gap: 8px; }
  .bar .track { flex: 1; height: 4px; border-radius: 2px; background: #333; overflow: hidden; }
  .bar .done { display: block; height: 100%; width: 0; background: #999; }
  .now { padding: 8px 2px 0; color: #777; }
  .story { list-style: none; margin: 8px 0 0; padding: 0; display: flex; flex-direction: column; gap: 3px; min-height: 9.5em;
           justify-content: flex-end; }
  .story li { padding: 3px 8px; border-radius: 5px; opacity: .45; transition: opacity .3s; }
  .story li.cause { background: #1e1e1e; color: #ddd; }
  .story li.effect { padding-left: 30px; color: #9a9; }
  .story li.new { opacity: 1; }
  .story .icon { display: inline-block; width: 1.4em; }
`;

/// <boop-simulator face="pixel|gel" zoom="2" voice="voice.bin" usb="ws://…/usb" controls>
/// The board, drawn as a thing on a desk. `voice` is a voice pack to fetch
/// for its card; `usb` a WebSocket that is its USB cable, one line a
/// message each way (serve.py's, which leads to the Mac app and the
/// tools); `controls` adds power, reset, card and sound buttons. `demo`
/// is a recording to play (DemoPlayer), told as a story under the board:
/// what happens, and what the creature does about it. The board's face is
/// then the recording's.
/// `element.board` is its Board, once `ready` has fired.
// Outside a browser (the tests, under Node) there's no element to be.
const Element = globalThis.HTMLElement ?? class {};

export class BoopSimulator extends Element {
  static observedAttributes = ['face', 'zoom'];
  board = null;
  #root; #canvas; #context; #led; #status; #parts = {}; #dim = 0;

  connectedCallback() {
    if (this.#root) return;
    this.#root = this.attachShadow({ mode: 'open' });
    this.#root.innerHTML = `<style>${STYLE}</style>
      <div class="body">
        <div class="screen"><canvas></canvas><span class="finger"></span></div>
        <div class="chin">
          <button class="boot" title="BOOT: a tap, or hold to talk (Space)">BOOT</button>
          <span class="tools"></span><span class="led"></span>
        </div>
      </div>
      <div class="status"></div>
      <div class="demo" hidden>
        <div class="bar"><button class="play">Pause</button><button class="again">Restart</button><button class="sound">Sound on</button>
          <span class="track"><span class="done"></span></span><span class="clock"></span></div>
        <div class="now"></div>
        <ol class="story"></ol>
      </div>`;
    this.#canvas = this.#root.querySelector('canvas');
    this.#context = this.#canvas.getContext('2d');
    this.#led = this.#root.querySelector('.led');
    this.#status = this.#root.querySelector('.status');
    this.tabIndex = 0;
    this.#size(...(this.face === 'gel' ? [502, 410] : CANVAS));
    this.#start();
  }

  disconnectedCallback() { this.board?.power(false); }
  attributeChangedCallback(name, was, now) {
    if (!this.board || was === now) return;
    if (name === 'face') this.reset();
    if (name === 'zoom') this.#size(this.#canvas.width, this.#canvas.height);
  }

  get face() { return (this.#recording?.face ?? this.getAttribute('face')) === 'gel' ? 'gel' : 'pixel'; }
  #recording = null;
  /// The demo's player, once a `demo` has loaded.
  demo = null;
  get zoom() { return Number(this.getAttribute('zoom')) || (this.face === 'gel' ? 1 : 2); }

  /// Power, and the RESET button: off and on again.
  power(on) { this.board.power(on, { face: this.face, native: this.getAttribute('native') || undefined }); }
  reset() { this.power(true); }

  async #start() {
    const demo = this.getAttribute('demo');
    if (demo) {
      try { this.#recording = await (await fetch(demo)).json(); } catch { this.#status.textContent = `no demo at ${demo}`; }
      if (this.#recording) this.#size(...(this.face === 'gel' ? [502, 410] : CANVAS));
    }
    const board = this.board = await Board.make();
    board.addEventListener('frame', e => this.#draw(e.detail));
    board.addEventListener('parts', e => { this.#parts = e.detail; this.#show(); });
    board.addEventListener('power', e => {
      if (!e.detail) { this.#parts = {}; this.#context.clearRect(0, 0, this.#canvas.width, this.#canvas.height); }
      else if (this.#voice) board.insertCard(this.#voice);
      this.#show();
    });
    this.#inputs();
    this.#cable(this.getAttribute('usb'));
    if (this.hasAttribute('controls')) this.#controls();
    this.power(true);
    if (this.#recording) this.#story();
    this.dispatchEvent(new CustomEvent('ready'));
    const voice = this.getAttribute('voice');
    if (voice) {
      try {
        const got = await fetch(voice);
        if (got.ok) { this.#voice = new Uint8Array(await got.arrayBuffer()); board.insertCard(this.#voice); }
      } catch { /* a board with no card */ }
    }
  }
  #voice = null;

  #size(w, h) {
    if (this.#canvas.width !== w || this.#canvas.height !== h) { this.#canvas.width = w; this.#canvas.height = h; }
    this.#canvas.style.setProperty('--w', `${w * this.zoom}px`);
    this.#canvas.style.setProperty('--h', `${h * this.zoom}px`);
  }

  #draw(frame) {
    this.#size(frame.width, frame.height);
    this.#context.putImageData(frame, 0, 0);
    this.#backlight();
  }

  // The backlight dims the panel; the firmware's pixels stay what they are.
  #backlight() {
    const level = this.#parts.backlight ?? 255;
    this.#canvas.style.filter = level < 255 ? `brightness(${level / 255})` : '';
  }

  #show() {
    const p = this.#parts, on = this.board.on;
    const led = p.led ? `#${p.led.toString(16).padStart(6, '0')}` : '';
    this.#led.style.background = led || '#333';
    this.#led.style.boxShadow = led ? `0 0 10px 2px ${led}` : '';
    this.#backlight();
    this.#status.textContent = on
      ? `${this.face}${this.hasAttribute('usb') ? ` · usb ${this.#plugged ? 'plugged in' : 'unplugged'}` : ''} · card: ${p.card ?? '…'} · sound ${this.board.audible ? 'on' : 'off'}`
      : 'off';
    for (const b of this.#root.querySelectorAll('[data-label]')) b.textContent = b.dataset.label.split('|')[this.#label(b.dataset.act) ? 1 : 0];
  }
  #label(act) {
    return { power: !this.board.on, card: this.#parts.card === 'no card', sound: this.board.audible }[act];
  }

  #inputs() {
    const board = this.board, canvas = this.#canvas;
    const at = e => {
      const r = canvas.getBoundingClientRect();
      board.touch((e.clientX - r.left) / r.width * CANVAS[0], (e.clientY - r.top) / r.height * CANVAS[1]);
    };
    canvas.addEventListener('pointerdown', e => { canvas.setPointerCapture(e.pointerId); at(e); });
    canvas.addEventListener('pointermove', e => { if (e.buttons) at(e); });
    for (const up of ['pointerup', 'pointercancel']) canvas.addEventListener(up, () => board.release());
    const boot = this.#root.querySelector('.boot');
    const press = down => { boot.classList.toggle('down', down); board.boot(down); };
    boot.addEventListener('pointerdown', e => { boot.setPointerCapture(e.pointerId); press(true); });
    for (const up of ['pointerup', 'pointercancel']) boot.addEventListener(up, () => press(false));
    // Space is BOOT too, while the board has the keyboard.
    this.addEventListener('keydown', e => { if (e.code === 'Space') { e.preventDefault(); if (!e.repeat) press(true); } });
    this.addEventListener('keyup', e => { if (e.code === 'Space') press(false); });
  }

  // The USB cable: the board's lines out, a host's lines in. It's plugged
  // in again a second after it drops, as the Mac's side does.
  #cable(url) {
    if (!url) return;
    let socket = null;
    const plug = () => {
      socket = new WebSocket(url);
      socket.onmessage = e => { for (const line of String(e.data).split('\n')) if (line) this.board.send(line); };
      socket.onopen = () => { this.#plugged = true; this.#show(); };
      socket.onclose = () => { this.#plugged = false; this.#show(); setTimeout(plug, 1000); };
    };
    this.board.addEventListener('line', e => { if (socket?.readyState === WebSocket.OPEN) socket.send(e.detail); });
    plug();
  }
  #plugged = false;

  // A demo, told under the board: what happens, and what the creature does.
  #story() {
    const root = this.#root.querySelector('.demo'), story = root.querySelector('.story');
    const [play, again, sound] = ['play', 'again', 'sound'].map(c => root.querySelector(`.${c}`));
    const done = root.querySelector('.done'), clock = root.querySelector('.clock'), now = root.querySelector('.now');
    const finger = this.#root.querySelector('.finger');
    const player = this.demo = new DemoPlayer(this.board, this.#recording);
    const icons = { prompt: '💬', tool: '⚙', tool_failed: '✕', tap: '👆', needs_you: '✋', talk: '🎙', done: '✓', failed: '✕', stopped: '■', note: '·' };
    const time = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
    const row = (kind, text, icon) => {
      for (const old of story.querySelectorAll(kind === 'cause' ? '.new' : '.effect.new')) old.classList.remove('new');
      const li = document.createElement('li');
      li.className = `${kind} new`;
      if (icon) { const i = document.createElement('span'); i.className = 'icon'; i.textContent = icon; li.append(i); }
      li.append(text);
      story.append(li);
      while (story.children.length > 6) story.firstChild.remove();
    };
    const labels = () => {
      play.textContent = player.playing ? 'Pause' : player.ended ? 'Replay' : 'Play';
      sound.textContent = this.board.audible ? 'Sound off' : 'Sound on';
    };
    player.addEventListener('cause', e => {
      row('cause', e.detail.text, icons[e.detail.kind] ?? '·');
      if (e.detail.kind === 'tap') { finger.classList.remove('down'); void finger.offsetWidth; finger.classList.add('down'); }
    });
    player.addEventListener('effect', e => row('effect', e.detail));
    player.addEventListener('state', e => { now.textContent = `state: ${e.detail.base ?? '…'} · mood: ${e.detail.mood || '…'}`; });
    player.addEventListener('time', e => {
      done.style.width = `${Math.min(100, e.detail / player.length * 100)}%`;
      clock.textContent = `${time(e.detail)} / ${time(player.length)}`;
    });
    player.addEventListener('end', labels);
    player.addEventListener('rewind', () => { story.replaceChildren(); this.reset(); });
    play.addEventListener('click', () => { player.playing ? player.pause() : player.play(); labels(); });
    again.addEventListener('click', () => { player.restart(); labels(); });
    sound.addEventListener('click', async () => { await (this.board.audible ? this.board.mute() : this.board.unmute()); labels(); this.#show(); });
    root.hidden = false;
    player.play();
    labels();
  }

  #controls() {
    const tools = this.#root.querySelector('.tools');
    const add = (act, label, run) => {
      const b = document.createElement('button');
      b.dataset.act = act;
      b.dataset.label = label;
      b.textContent = label.split('|')[0];
      b.addEventListener('click', async () => { await run(); this.#show(); });
      tools.append(b, ' ');
    };
    add('power', 'Power off|Power on', () => this.power(!this.board.on));
    add('reset', 'Reset', () => this.reset());
    add('card', 'Eject card|Insert card', () => this.#parts.card === 'no card' ? this.board.insertCard() : this.board.ejectCard());
    add('sound', 'Sound on|Sound off', () => this.board.audible ? this.board.mute() : this.board.unmute());
  }
}

if (typeof customElements !== 'undefined' && !customElements.get('boop-simulator')) customElements.define('boop-simulator', BoopSimulator);
