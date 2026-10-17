# Boop Simulator

Updated 2026-10-17. A board with no board: the firmware's own code in a
web page, for development, tests and demos, and for trying Boop without
one. It's Boop's only; nothing here ships in the Mac app or the firmware.

```sh
brew install emscripten   # once: it builds the firmware for a browser
make simulator            # builds it, then serves http://127.0.0.1:8206/
```

Add `?face=gel` for Boop's own face and
`?zoom=3` for a bigger one. It uses no Bluetooth, so an agent's shell may
run it.

**With the Mac app.** While the simulator runs, Boop's Settings shows it
under Device: **Use it** makes it Boop's body, with your real hooks and
brain, and **Use the board** goes back. The choice lasts while the
simulator runs: when it stops, Boop is back on its board by itself, and
the next launch starts with the board (`DeviceChooser`, in
`app/BoopKit/DeviceLink/`). The app finds a simulator by its USB socket,
`/tmp/boop-sim-usb.sock`, and only one that this user started.

## One core, two builds

```
                        ┌─ boop-sim.wasm ── the page (web/): <boop-simulator>
 simulator/core/ ───────┤
 the simulated board    └─ native build ─── the Mac: tests, tools, CI, with no browser
```

**The core** (`core/`) is the firmware's portable code (`render/`, `app/`
and `voice/`) and LinkKit's device library, with a stand-in for the
hardware (`sim_hal.h`). It takes USB's messages as the firmware's loop
does: in order, with a `dbg.*` message ending the batch, so the messages
after it wait for the next pass. Both builds run the same `Board` (`board.h`), so
they show the same board:

| Build | By | Runs | For |
| --- | --- | --- | --- |
| `boop-sim.wasm` | `web/build.sh` (Emscripten) | In the page, which calls it for each pass of the board's loop and each chunk of sound | The page, here and embedded in a site |
| `firmware/.pio/build/native/program --live` | PlatformIO's `native` env (`firmware/tools/pio.sh run -e native`) | A process in real time, its USB a serial port, with nobody looking at it | Tests, `boopctl` and CI, with no browser |
| `firmware/.pio/build/native/program` | The same | Frozen at 0, moved only by `dbg.*` messages | `boopctl sim` and the golden pictures ([internal/VERIFICATION.md](../internal/VERIFICATION.md) L1) |

Power off ends the board and power on makes a new one, so nothing the
firmware knew survives and each power-on has a new boot ID, as on a real
board.

## The board it simulates

A generic one, not the CYD or the AMOLED board:

| Part | In the simulator |
| --- | --- |
| Screen | The pixel face's 320×240 canvas, or a native face's panel: 502×410 (the AMOLED's) unless told otherwise (`native="400x300"`, `BOOP_SIM_NATIVE`). Every pixel is the firmware's; the page draws nothing on it |
| Touch | The pointer on the screen: a touch is a tap, as on the boards. The board sees a press however soon it's let go, since a click is over sooner than it looks |
| BOOT | The button under the screen, or Space; hold it to talk |
| Sound | The firmware's own samples (`app/sound.h`, the code the boards' sound task runs), at the pace a DAC plays them. A browser plays nothing until a click: Sound on |
| Light | The dot under the screen, in the LED's colour |
| Backlight | The screen dims as the firmware dims it |
| Card | A voice file: the page fetches one (`voice="…"`), and it can be ejected and put back. On the Mac, the chosen character pack's voice file (its `voice/voice.bin`), or with `BOOP_SIM_CARD=DIR` a folder that is the card, where `dbg.card` copies a voice file as on a board |
| Power, reset | Power off and Reset. The card stays in its slot through both |

## The page

One script, `web/boop-simulator.js`, with the core beside it
(`boop-sim.js`, `boop-sim.wasm`). `web/build.sh` puts all three, and the
local page, in `web/dist/`:

```html
<script type="module" src="boop-simulator.js"></script>
<boop-simulator face="pixel" voice="voice.bin" controls></boop-simulator>
```

| Attribute | What |
| --- | --- |
| `face` | `pixel` (the default) or `gel` |
| `zoom` | How many times as big the screen is drawn (2 for the pixel face, 1 for a native one), shrunk to fit a narrower page |
| `native` | A native face's panel, `WxH` |
| `voice` | A voice file to fetch for the card |
| `usb` | A WebSocket that is the board's USB cable, one WebSocket message per LinkKit message each way |
| `controls` | Adds the Power, Reset and card buttons. Sound on is always there |
| `demo` | A recording to play (below). The board's face is then the recording's |
| `board-id` | The board's id, its `hello`'s, so boards on one page differ (`b00p-0000` without it) |
| `pack` | The character pack whose build it runs, `boop-sim-PACK.js` (below); the staged pack's `boop-sim.js` without it |

`web/build.sh` builds the staged pack. `web/build.sh PACK` builds a
pack by its name in `characters/` beside it, as `boop-sim-PACK.js` and
`.wasm`, and leaves what's staged alone (`charactergen.py --firmware-to`),
so two packs can run on one page: `<boop-simulator pack="pixel">`.

The element's `board` (once it has fired `ready`) is the board itself:
`send(line)` is a host's message on USB, and it fires `line` for each the
board says, `frame`, `parts` (`{"led":0,"backlight":255,"amp":false,"card":"ok"}`,
whenever one changes) and `power`. The script knows nothing of what the
board's messages mean: they pass through it.

## Demos

`make demo` shows a character pack's demo here
([characters/DEMOS.md](../characters/DEMOS.md)). A demo is a script the
Mac app plays, and the app can't run in a browser, so the page plays a
**recording** of it: every message the app sent the board, with when,
so the firmware in the page does what it did, with no app behind it.
The screen is still the firmware's own drawing, and you can still poke
it. The page opens at `http://127.0.0.1:8206/?demo=pixel-landing` (the
face, then the name).

`tools/record-demo.sh` plays the script through the real headless app
(`Boop --headless --demo pack:NAME --record FILE`) with the Mac build's
board as its device, and takes as long as the demo runs. Into
`web/dist/demo/` go `<face>-NAME.json`, the recording, and
`<face>-NAME-voice.bin`, a voice file with only the takes it says
(`tools/voice_subset.py`: about 70 KB for a minute's demo, where the whole
voice is 29 MB).

A recording (`DemoRecording`, `app/BoopKit/Demo/`), the start of one:

```json
{
  "version": 1, "character": "boop", "name": "Boop", "face": "pixel", "length": 79,
  "takes": ["…"],
  "events": [
    {"at": 0, "line": "{\"t\":\"state\",\"base\":\"asleep\",\"mood\":\"calm\",\"busy\":0,\"vol\":6,\"variant\":3}"},
    {"at": 0.001, "line": "{\"t\":\"do\",\"id\":1493456480,\"name\":\"starting\",\"play\":\"if_free\",\"args\":{\"variant\":5,\"ctx\":\"session\"}}"},
    {"at": 2.003, "cause": {"kind": "prompt", "text": "You ask Claude: “Add keyboard shortcuts”"}}
  ]
}
```

`takes` lists the takes it says, for its voice file. An event is one or
more of:

- **`line`:** a message, sent to the board as it was.
- **`effect`:** what the creature does at that message, in words, when it's
  something to see: `Boop makes a curious face and says “…”`,
  `Boop shows that it needs you`. The recorder writes them, since it knows
  what the messages mean and the page doesn't.
- **`cause`:** what happened, in words, with a `kind` for its icon:
  `prompt`, `tool`, `tool_failed`, `compact`, `needs_you`, `tap`, `talk`, `back`,
  `done`, `failed`, `stopped` or `note`.
- **`input`:** what to do to the board itself: `tap`, a finger on its
  screen, which the board reacts to by itself, as it does to a real one.

The page tells it as a story under the board (`DemoPlayer`): each cause,
and under it each effect. Nothing of it is on the board's screen. Play, Pause and Restart are there; paused or over, the page
keeps the board company as an app does, so it doesn't take its app for
gone.

## USB

The board's USB carries LinkKit's messages
([linkkit/SPEC.md](../linkkit/SPEC.md)) and `dbg.*`, and nothing about
them differs from a board's.

**The page's**, served by `make simulator` (`web/serve.py`), is a Unix
socket, `/tmp/boop-sim-usb.sock`, that keeps a bridge's rules
([linkkit/SPEC.md](../linkkit/SPEC.md) §8). A client's message longer
than a message may be is dropped whole, as a board drops it. So the
tools and the Mac app reach the board in the browser as they reach one
on a bridge ([internal/VERIFICATION.md](../internal/VERIFICATION.md) L4):

```sh
BOOP_BRIDGE=/tmp/boop-sim-usb.sock internal/tools/boopctl ping
BOOP_BRIDGE=/tmp/boop-sim-usb.sock internal/tools/boopctl run     # every scenario, as on a board
.build/debug/Boop --headless --state-dir /tmp/boop-sim-state --link usb:/tmp/boop-sim-usb.sock --brain scripted
```

Only this Mac can reach it: the page is served on 127.0.0.1 and the
socket is its user's alone. The newest page to open is the board.

**Several boards.** One server can give each of several boards its own
cable: `--cable NAME[=SOCKET]`, once for each, in place of `--socket`. Each
cable is a WebSocket at `/usb/NAME` and its own socket, and there's no
`/usb`. With no socket given it's `/tmp/boop-sim-NAME.sock`, where the
Mac app looks for the buddy that sits at NAME: Settings' Simulator row
then moves every buddy to its simulated board at once. The page shows them side by side with `?boards=NAME,NAME`, each
with the id `b00p-NAME`, and `&packs=PACK,PACK` gives each board its
pack's build and voice (`/voice/PACK.bin`):

```sh
python3 characters/charactergen.py --stage
simulator/web/build.sh boop && simulator/web/build.sh pixel
python3 simulator/web/serve.py --cable left --cable right
open 'http://127.0.0.1:8206/?boards=left,right&packs=boop,pixel'
BOOP_BRIDGE=/tmp/boop-sim-right.sock internal/tools/boopctl ping
```

One simulator runs at a time. A second fails at once ("port 8206 is in
use: is a simulator already running?") and leaves the first's socket
alone, and so does one given another `--port` while something still
answers on the socket. A socket nothing answers on is a stale one's, and
the next simulator replaces it. Stopped by Ctrl-C, SIGTERM or SIGHUP (a
closed terminal), the server removes its sockets, unless a newer one has
taken the path since; only a kill leaves it behind, for the next to
replace (`tests/test_serve.py`).

**The Mac build's** is a pseudo serial port, which bridges and tools open
as they open a board's `/dev/cu.usbserial-*` (`core/port.h`). It prints
where it is (`port /dev/ttys004`), and `BOOP_SIM_PORT` names a path that
will lead there:

```sh
BOOP_SIM_PORT=/tmp/boop-sim.port firmware/.pio/build/native/program --live
BOOP_PORT=/tmp/boop-sim.port internal/tools/boopctl e2e     # hooks → headless app → bridge → the simulator
```

Three things a cable does that the port does too:

- **It has no rate.** A pseudo-terminal refuses the board's 460800 baud:
  `linkkit-bridge` goes on without one, and `boopctl` opens it at a
  standard rate.
- **Nobody listening hears nothing later.** With nothing reading, what
  the board said 500 ms ago is thrown away, so a tool that opens the port
  later hears only what's said from then on. A tool that pauses with the
  port open keeps reading as it waits (`boopctl`'s soak and perf do), or
  what comes unasked, such as an `ended`, is lost.
- **A long reply arrives whole.** A screenshot is far more than the port
  holds at once: the board waits for its reader, and gives up on one that
  takes nothing for 250 ms.

## The core's settings

In its environment, or from the page's attributes: `BOOP_SIM_FACE` (`pixel` or `gel`),
`BOOP_SIM_NATIVE` (`WxH`), `BOOP_SIM_ID` (the device's ID, `b00p-0000`
without it; the page's `board-id`), and on the Mac `BOOP_SIM_CARD` (the card's folder) and
`BOOP_SIM_PORT`.

## Tests

```sh
make -C internal sim-test
```

- **`tests/test_core.py`**, the Mac build in real time, driven over its
  serial port as a board is: it says hello and draws by itself, a native
  face fills the panel it's given, every power-on is a new boot, and a
  `say` plays at the pace a DAC would (the output's time within 10% of
  the `say`'s length, as the boards' takes check holds them). Of the port:
  it's a serial port at the path asked for, what nobody heard is
  forgotten, a long reply arrives whole, and a debug message ends a batch
  of messages that arrive together.
- **`tests/test_serve.py`**, the page's server and its socket, on a free
  port and a socket of its own: a second server leaves a live socket
  alone, whichever port it's given; a stale socket is replaced, and a
  file that isn't a socket is left; SIGTERM and SIGHUP remove the
  socket, but not a newer server's at the same path. With `--cable`, each
  board has its own socket and no default one, all removed at the end; a
  cable whose socket is live stops the server and takes back the sockets
  it made; and a cable needs a name and a socket of its own.
- **`tests/web.test.mjs`**, the WebAssembly build under Node, driven as
  the page drives it: hello and drawing, a native face's panel, a touch
  that's a tap however soon it lifts, BOOT held as talking, a new boot, a
  `say`'s sound asked for a chunk at a time, and the card staying in its
  slot through a reset. Boards side by side each say their own id, and
  Pixel's build (`build.sh pixel`, which `sim-test` makes) says its pack.
  Then the page's cable carrying whole messages both
  ways, a 900 KB one among them, and keeping a bridge's rules: a client
  that stops reading dropped while another hears every message, and a
  client's message over 512 bytes dropped whole; two cables, each page's
  messages reaching its own socket and no other's; a recording played into a board in
  order; and a voice file cut down to a demo's takes that the board plays
  from.

The sound and card tests need the chosen pack to have a voice file, and skip without one.

## Not yet

Simulated Bluetooth, an inspector for the messages and the queue, and
the device-level checks (L2) run against the simulator as a matter of
course.
