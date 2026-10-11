// Boop Simulator in a page (simulator/README.md): the board's firmware,
// built to WebAssembly, with this script as its screen, finger, BOOT
// button, speaker, light and card.
//
//   <script type="module" src="boop-simulator.js"></script>
//   <boop-simulator face="pixel"></boop-simulator>
//
// Nothing here draws on the screen: every pixel there is the firmware's.
// And nothing here knows what the board's lines mean: they pass through.

import makeCore from './boop-sim.js';

const CHUNK = 512;       // app::Sound::kChunk
const OUT_RATE = 22050;  // voice::kOutRate
const CANVAS = [320, 240];  // a touch is in the canvas's pixels on every board
const PANEL = { pixel: CANVAS, gel: [502, 410] };  // each face's panel, until its first frame says

/// One simulated board: the core, switched on and off, with its USB as
/// lines in and out. A page can have several. It fires `power` (on or
/// off), `frame` (an ImageData, the same one each time for a size),
/// `line` (each line the board says on USB) and `parts`
/// (`{led, backlight, amp, card}`, whenever one changes).
export class Board extends EventTarget {
  #core; #usb; #env; #input; #timer = 0;
  #audio = null; #soundAt = 0; #muted = false;

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

  /// Power: on is a new boot with nothing remembered, as on a board, but
  /// for the card, which stays in its slot. `face` is `pixel` or `gel`;
  /// `native` a native face's panel, `502x410`.
  power(on, { face = 'pixel', native } = {}) {
    clearInterval(this.#timer);
    if (on) {
      this.#env('BOOP_SIM_FACE', face);
      if (native) this.#env('BOOP_SIM_NATIVE', native);
    }
    this.#core._sim_power(on ? 1 : 0);
    this.on = !!on;
    this.frame = null;
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

  /// The finger, in the canvas's 320×240, and the BOOT button. The board
  /// sees a press however soon it's let go.
  touch(x, y) { this.#say(`touch ${Math.round(x)} ${Math.round(y)}`); }
  release() { this.#say('release'); }
  boot(down) { this.#say(`boot ${down ? 1 : 0}`); }

  /// The card: a voice pack's bytes go in, the card that came out goes
  /// back (no bytes), or it comes out.
  insertCard(bytes) {
    if (bytes) {
      // Its room first: making it may move the core's memory.
      const at = this.#core._sim_card(bytes.length);
      this.#core.HEAPU8.set(bytes, at);
    }
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
      const w = core._sim_width(), h = core._sim_height();
      if (this.frame?.width !== w || this.frame?.height !== h) this.frame = new ImageData(w, h);
      const at = core._sim_frame();
      this.frame.data.set(core.HEAPU8.subarray(at, at + w * h * 4));
      this.dispatchEvent(new CustomEvent('frame', { detail: this.frame }));
    }
    // Null for nothing said, and for parts that haven't changed.
    const said = core._sim_usb_out();
    if (said) for (const line of core.UTF8ToString(said).split('\n')) if (line) this.dispatchEvent(new CustomEvent('line', { detail: line }));
    const parts = core._sim_parts();
    if (parts) this.dispatchEvent(new CustomEvent('parts', { detail: JSON.parse(core.UTF8ToString(parts)) }));
    this.#sound();
  }

  // The board makes its sound a chunk at a time, at the pace it plays:
  // each is asked for a little before it's due, and what's due goes to the
  // page's audio as one buffer. With no audio yet, or muted, it's made all
  // the same and dropped, so a line still takes as long as it takes.
  #sound() {
    const now = this.#clock(), core = this.#core;
    if (this.#soundAt < now - 0.2) this.#soundAt = now;  // the tab slept: don't catch up
    const chunks = Math.ceil((now + 0.1 - this.#soundAt) * OUT_RATE / CHUNK);
    if (chunks <= 0) return;
    let buffer = null;
    for (let i = 0; i < chunks; i++) {
      const at = core._sim_sound();  // null is silence
      if (!at || !this.audible) continue;
      buffer ??= this.#audio.createBuffer(1, chunks * CHUNK, OUT_RATE);
      const out = buffer.getChannelData(0), samples = core.HEAPU8.subarray(at, at + CHUNK);
      for (let j = 0; j < CHUNK; j++) out[i * CHUNK + j] = (samples[j] - 128) / 128;
    }
    if (buffer) {
      const source = this.#audio.createBufferSource();
      source.buffer = buffer;
      source.connect(this.#audio.destination);
      source.start(Math.max(this.#soundAt, this.#audio.currentTime));
    }
    this.#soundAt += chunks * CHUNK / OUT_RATE;
  }
}

/// Plays a demo's recording into a board (DemoRecording, which the app's
/// `Boop --headless --demo … --record` writes): every line the app sent
/// the device, when it sent it, so the firmware does what it did, with no
/// app behind it. It fires `cause` for what happens (`{kind, text}`),
/// `effect` for what the creature does about it (words), `time` as it
/// goes, `rewind` before it starts again, and `end`.
export class DemoPlayer extends EventTarget {
  #board; #recording; #next = 0; #at = 0; #from = 0; #timer = 0; #state = null; #told = 0;
  playing = false;

  constructor(board, recording) {
    super();
    if (recording.version !== 1) throw new Error(`a recording of version ${recording.version}, and this page plays 1`);
    this.#board = board;
    this.#recording = recording;
  }

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
    if (event.cause) this.dispatchEvent(new CustomEvent('cause', { detail: event.cause }));
    // A finger on the screen, which is the board's own to react to.
    if (event.input === 'tap') {
      this.#board.touch(CANVAS[0] / 2, CANVAS[1] / 2);
      this.#board.release();
    }
    if (event.line) {
      if (event.line.startsWith('{"t":"state"')) this.#state = event.line;
      this.#send(event.line);
    }
    if (event.effect) this.dispatchEvent(new CustomEvent('effect', { detail: event.effect }));
  }
}

const STYLE = `
  :host { display: inline-block; font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; color: #999; }
  .body { background: #212121; border-radius: 18px; padding: 22px 22px 12px; }
  .screen { position: relative; }
  canvas { display: block; background: #000; border-radius: 6px; image-rendering: pixelated; touch-action: none;
           cursor: pointer; width: var(--w); height: var(--h); }
  .finger { position: absolute; left: 50%; top: 50%; width: 46px; height: 46px; margin: -23px; border-radius: 50%;
            border: 2px solid #fff; opacity: 0; pointer-events: none; }
  .finger.down { animation: finger .6s ease-out; }
  @keyframes finger { from { opacity: .9; transform: scale(.3); } to { opacity: 0; transform: scale(1.4); } }
  .chin { display: flex; align-items: center; gap: 8px; height: 34px; }
  button { font: inherit; color: #bbb; background: #383838; border: 0; border-radius: 5px; padding: 3px 10px; cursor: pointer; }
  button:active, button.down { background: #666; }
  .led { margin-left: auto; width: 10px; height: 10px; border-radius: 50%; background: #333; }
  .status { padding: 6px 4px 0; min-height: 1.3em; }
  .demo { margin-top: 10px; width: 0; min-width: 100%; color: #bbb; }
  .bar { display: flex; align-items: center; gap: 8px; }
  .bar .track { flex: 1; height: 4px; border-radius: 2px; background: #333; overflow: hidden; }
  .bar .done { display: block; height: 100%; width: 0; background: #999; }
  .story { list-style: none; margin: 8px 0 0; padding: 0; display: flex; flex-direction: column; gap: 3px; min-height: 9.5em;
           justify-content: flex-end; }
  .story li { padding: 3px 8px; border-radius: 5px; opacity: .45; transition: opacity .3s; }
  .story li.cause { background: #1e1e1e; color: #ddd; }
  .story li.effect { padding-left: 30px; color: #9a9; }
  .story li.new { opacity: 1; }
  .story .icon { display: inline-block; width: 1.4em; }
`;

// A cause's kind, as an icon (DemoScript.Cause).
const ICONS = { prompt: '💬', tool: '⚙', tool_failed: '✕', tap: '👆', needs_you: '✋', talk: '🎙', done: '✓', failed: '✕', stopped: '■' };

// Outside a browser (the tests, under Node) there's no element to be.
const Element = globalThis.HTMLElement ?? class {};

/// <boop-simulator face="pixel|gel" zoom="2" voice="voice.bin" usb="ws://…/usb" demo="demo.json" controls>
/// The board, drawn as a thing on a desk, with its BOOT button and a Sound
/// button (a browser plays nothing until a click). `voice` is a voice pack
/// to fetch for its card; `usb` a WebSocket that is its USB cable, one
/// line a message each way (serve.py's, which leads to the Mac app and the
/// tools); `controls` adds power, reset and card buttons. `demo` is a
/// recording to play (DemoPlayer), told as a story under the board: what
/// happens, and what the creature does about it. The board's face is then
/// the recording's. `element.board` is its Board, and `element.demo` its
/// DemoPlayer, once `ready` has fired.
export class BoopSimulator extends Element {
  static observedAttributes = ['face', 'zoom'];
  board = null;
  demo = null;
  #root; #canvas; #context; #led; #status;
  #parts = {}; #recording = null; #plugged = false;
  #labels = [];  // each button's words, to say again when something changes

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
        <div class="bar"><span class="tools"></span><span class="track"><span class="done"></span></span><span class="clock"></span></div>
        <ol class="story"></ol>
      </div>`;
    this.#canvas = this.#root.querySelector('canvas');
    this.#context = this.#canvas.getContext('2d');
    this.#led = this.#root.querySelector('.led');
    this.#status = this.#root.querySelector('.status');
    this.tabIndex = 0;
    this.#start();
  }

  disconnectedCallback() {
    this.demo?.stop();
    this.board?.power(false);
  }
  attributeChangedCallback(name, was, now) {
    if (!this.board || was === now) return;
    if (name === 'face') this.reset();
    if (name === 'zoom') this.#size(this.#canvas.width, this.#canvas.height);
  }

  get face() { return (this.#recording?.face ?? this.getAttribute('face')) === 'gel' ? 'gel' : 'pixel'; }
  get zoom() { return Number(this.getAttribute('zoom')) || (this.face === 'gel' ? 1 : 2); }

  /// Power, and the RESET button: off and on again.
  power(on) { this.board.power(on, { face: this.face, native: this.getAttribute('native') || undefined }); }
  reset() { this.power(true); }

  async #start() {
    const demo = this.getAttribute('demo');
    if (demo) {
      try { this.#recording = await (await fetch(demo)).json(); } catch { this.#status.textContent = `no demo at ${demo}`; }
    }
    this.#size(...PANEL[this.face]);
    const board = this.board = await Board.make();
    board.addEventListener('frame', e => this.#draw(e.detail));
    board.addEventListener('parts', e => { this.#parts = e.detail; this.#show(); });
    board.addEventListener('power', e => {
      this.#parts = {};
      if (!e.detail) this.#context.clearRect(0, 0, this.#canvas.width, this.#canvas.height);
      this.#show();
    });
    this.#inputs();
    this.#cable(this.getAttribute('usb'));
    this.#controls();
    this.power(true);
    if (this.#recording) this.#story();
    this.dispatchEvent(new CustomEvent('ready'));
    const voice = this.getAttribute('voice');
    if (voice) {
      try {
        const got = await fetch(voice);
        if (got.ok) board.insertCard(new Uint8Array(await got.arrayBuffer()));
      } catch { /* a board with no card */ }
    }
  }

  #size(w, h) {
    if (this.#canvas.width !== w || this.#canvas.height !== h) { this.#canvas.width = w; this.#canvas.height = h; }
    this.#canvas.style.setProperty('--w', `${w * this.zoom}px`);
    this.#canvas.style.setProperty('--h', `${h * this.zoom}px`);
  }

  #draw(frame) {
    this.#size(frame.width, frame.height);
    this.#context.putImageData(frame, 0, 0);
  }

  // The board's parts, and every button's words, as they are now.
  #show() {
    const p = this.#parts, on = this.board.on;
    const led = p.led ? `#${p.led.toString(16).padStart(6, '0')}` : '';
    this.#led.style.background = led || '#333';
    this.#led.style.boxShadow = led ? `0 0 10px 2px ${led}` : '';
    // The backlight dims the panel; the firmware's pixels stay what they are.
    this.#canvas.style.filter = (p.backlight ?? 255) < 255 ? `brightness(${p.backlight / 255})` : '';
    const usb = this.hasAttribute('usb') ? ` · usb ${this.#plugged ? 'plugged in' : 'unplugged'}` : '';
    this.#status.textContent = on ? `${this.face}${usb} · card: ${p.card ?? '…'} · sound ${this.board.audible ? 'on' : 'off'}` : 'off';
    for (const [button, words] of this.#labels) button.textContent = words();
  }

  // A button whose words follow what it would do now.
  #button(tools, words, run) {
    const button = document.createElement('button');
    button.textContent = words();
    button.addEventListener('click', async () => { await run(); this.#show(); });
    this.#labels.push([button, words]);
    tools.append(button, ' ');
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

  #controls() {
    const tools = this.#root.querySelector('.chin .tools'), board = this.board;
    if (this.hasAttribute('controls')) {
      this.#button(tools, () => board.on ? 'Power off' : 'Power on', () => this.power(!board.on));
      this.#button(tools, () => 'Reset', () => this.reset());
      this.#button(tools, () => this.#parts.card === 'no card' ? 'Insert card' : 'Eject card',
                   () => this.#parts.card === 'no card' ? board.insertCard() : board.ejectCard());
    }
    this.#button(tools, () => board.audible ? 'Sound off' : 'Sound on', () => board.audible ? board.mute() : board.unmute());
  }

  // A demo, told under the board: what happens, and what the creature does.
  #story() {
    const root = this.#root.querySelector('.demo'), story = root.querySelector('.story');
    const done = root.querySelector('.done'), clock = root.querySelector('.clock'), finger = this.#root.querySelector('.finger');
    const player = this.demo = new DemoPlayer(this.board, this.#recording);
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
    player.addEventListener('cause', e => {
      row('cause', e.detail.text, ICONS[e.detail.kind] ?? '·');
      if (e.detail.kind === 'tap') { finger.classList.remove('down'); void finger.offsetWidth; finger.classList.add('down'); }
    });
    player.addEventListener('effect', e => row('effect', e.detail));
    player.addEventListener('time', e => {
      const words = `${time(e.detail)} / ${time(player.length)}`;
      if (words !== clock.textContent) clock.textContent = words;
      done.style.width = `${Math.min(100, e.detail / player.length * 100)}%`;
    });
    player.addEventListener('end', () => this.#show());
    player.addEventListener('rewind', () => { story.replaceChildren(); this.reset(); });
    const tools = root.querySelector('.tools');
    this.#button(tools, () => player.playing ? 'Pause' : player.ended ? 'Replay' : 'Play', () => player.playing ? player.pause() : player.play());
    this.#button(tools, () => 'Restart', () => player.restart());
    root.hidden = false;
    player.play();
    this.#show();
  }
}

if (typeof customElements !== 'undefined' && !customElements.get('boop-simulator')) customElements.define('boop-simulator', BoopSimulator);
