# Boop: verification

Updated 2026-10-21. How we check that Boop works, including what's on its
screen, without a person watching, and every tool that does it.

## 1. The loop

Every change goes around the same loop and stops at the first level that
fails:

```
 change ─► L0 unit tests ─► L1 simulator ─► flash ─► L2 device over USB ─► L3 webcam ─► commit
            (logic)          (look at the     │       (same pixels as       (the real panel,
                              PNGs)           │        the simulator?)       when authorised)
                                              └─ skip L2–L3 for Mac-only changes
```

L4 and L5 run when a change touches the pipeline or the brain. L6 needs
the owner.

| Level | Question | Needs |
| --- | --- | --- |
| L0 Unit tests | Is the logic right? | Nothing |
| L1 Simulator | Does the renderer draw what we meant? | Nothing: the device's drawing code builds on the Mac |
| L2 Device over USB | Does the board do and draw exactly that? | The board on USB |
| L3 Webcam | Does the real panel look right: colours, orientation, motion? | The board facing the camera, when authorised (§6) |
| L4 Pipeline | Does a real hook event reach the screen? | The board on USB; no Bluetooth |
| L5 Brain | Does Jev behave? | Jev's key in `BOOP_JEV_KEY` |
| L6 Owner | Bluetooth, touch, sound, real agents, how it feels | The owner |

CI (`.github/workflows/ci.yml`) runs what needs nothing on every push to
`main` and every pull request: `make -C internal test` on macOS 26;
the Python tests that need only the standard library, on the Mac's own
Python 3.9 (`python3 characters/charactergen.py --check`, and the
`unittest` suites in `internal/characters/`,
`internal/tools/session/tests/` and each pack's `tests/tools/`: the
part of `make -C internal tools-test` without boopctl's venv or the
webcam recorder); `make -C internal fw-test` (L0 for the firmware and
LinkKit's device library), all as Boop, the default pack; and both
boards' firmware: the CYD's with Pixel
(`CHARACTER=pixel firmware/tools/pio.sh run -e cyd24`) and the AMOLED's
with Boop's gel face (`CHARACTER=boop firmware/tools/pio.sh run -e amoled206`).
`Package.swift` needs Swift 6.2 or later (its `swift-tools-version`).
Boop is developed with Swift 6.4, and the runner's Swift (Xcode 26.6)
is older, so code must compile on both, and a test that times the wall
clock checks it only when `CI` isn't set.

## 2. The tools

Every tool prints its flags with `--help`: `internal/tools/boopctl
<command> --help`, `.build/debug/boopdev <command> --help`,
`.build/debug/Boop --help`, and each script below. `Boop` and `boopdev`
stop with their usage on a flag they don't take, `Boop` before anything
starts, so a typo can't launch the menu-bar app or run the whole eval.

**Make targets.** The root `Makefile` has the owner's everyday targets;
`internal/Makefile` has the development ones, run from the repo root as
`make -C internal <target>`. Each target's comment says what it runs.

| Target | What it does |
| --- | --- |
| `make build` | The Mac app, `boopdev`, the tests' runner, `agent-hook`, `mellowharness-emit`, `beacon` and `linkkit-bridge`. Importing a target that isn't a declared dependency fails it ([internal/README.md](README.md), How it's wired) |
| `make app` | What `make run` needs: the Mac app, `agent-hook` and `boopdev`, without the tests |
| `make run`, `make debug` | The menu-bar app with Bluetooth; `debug` adds `--debug`. The owner's; never from an agent's shell |
| `make dash` | `boopctl dash`, for the app `make debug` started. `b` asks the app for a bug report (as its ladybug does) and copies the path; any new report, from either, gets the device's screen as `screen.png` when the app reaches its device through a socket (`about.json`'s `link` is `usb:SOCKET`: the simulator, or a board's bridge), asked for there as `boopctl shot` would |
| `make day` | `boopctl day`: what the everyday app did in a day, from the logs `make debug` leaves; `DATE=YYYY-MM-DD` picks the day |
| `make simulator` | The board in a browser at `http://127.0.0.1:8206/`, its USB on `/tmp/boop-sim-usb.sock` ([simulator/README.md](../simulator/README.md); several boards side by side, each on its own socket, with `serve.py --cable NAME=SOCKET`), and beside it the Character Studio at `/characters/studio/`, whose matrix marks what the board shows. No Bluetooth, so agents may run it |
| `make demo` | A pack's demo, on the simulator's page, a board or with a real agent ([characters/DEMOS.md](../characters/DEMOS.md)) |
| `make flash` | Builds the firmware and uploads it to the board on USB ([firmware/README.md](../firmware/README.md)) |
| `make eval` | Every eval scenario against Jev, with no request budget (L5, [EVALS.md](EVALS.md) §2). It needs `BOOP_JEV_KEY` |
| `make clean` | Deletes every build's output. It keeps `internal/tools/.venv` and `firmware/.platformio-core` |
| `make -C internal test` | `make build`, then Boop's Swift tests through the XCTest shim (`.build/debug/BoopTests`; `BOOP_TEST_FILTER=Golden` runs only the tests whose `Class.method` contains `Golden`), then each package's own, one test at a time: `swift test --no-parallel --scratch-path .build/tests` in `agent-hooks/`, `mellowharness/` and `linkkit/`. That build now and then fails with "plugin for module 'TestingMacros' not found", a toolchain flake, even from a clean build folder. It passes when run again, so the target tries that failure alone again, up to eight tries in all |
| `make -C internal fw` | The firmware for both boards (envs `cyd24` and `amoled206`) |
| `make -C internal fw-test` | The firmware's unit tests on the Mac (env `native`): the engine's suites in `internal/firmware/test/` and the staged pack's `tests/firmware/`, then LinkKit's device library's own (`pio test -d linkkit/device -e native`) |
| `make -C internal sim` | Every scenario in the simulator, against the goldens (L1): the pixel face's, then the gel face's |
| `make -C internal sim-test` | The simulator's tests ([simulator/README.md](../simulator/README.md), Tests), with the page built for the staged pack and for Pixel's (`simulator/web/build.sh pixel`). It needs Emscripten and Node |
| `make -C internal e2e` | `make build`, then the pipeline check (L4) |
| `make -C internal faces` | Pixel's faces, made again from its animation bank and checked pixel for pixel against Chrome's drawing (about 7 minutes). Then run sfxgen (below) |
| `make -C internal tools` | Makes or refreshes `internal/tools/.venv` (pyserial, Pillow, Textual). `boopctl` runs it on its first run |
| `make -C internal eval-pixel` | `make build`, then Pixel's own eval scenarios against Jev, once each (L5, [EVALS.md](EVALS.md) §4). It needs `BOOP_JEV_KEY` |
| `make -C internal tools-test` | The tools' own tests, with no board or camera: boopctl's, the webcam recorder's, the session tool's, `charactergen.py`'s (`internal/characters/`) and each pack's `tests/tools/` |

**Tools.**

- `internal/tools/boopctl`: the board over USB (`ping`, `state`, `shot`,
  `send`, `play`, `takes`, `card`, `calibrate`), the scenarios (`sim`,
  `run`), measurements (`perf`, `latency`, `soak`), the pipeline check
  (`e2e`), the webcam (`cam`), and the debug logs (`dash`, `day`,
  `workday`). `--port` picks the serial port; without it, while a bridge
  runs (below), commands go through the bridge.
- `.build/debug/boopdev`: `eval` (L5, [EVALS.md](EVALS.md)), `check`
  (character packs, [CHARACTER.md](../characters/CHARACTER.md)) and
  `hooks` (Boop's hook installer, against any `--home`).
- `.build/debug/Boop`: the menu-bar app; `--headless --state-dir DIR`,
  the whole runtime with no UI or Bluetooth (L4); `--snapshots DIR`, the
  popover's panes, gel frames and menu-bar icons as PNGs (L0). With a
  state directory other than the everyday one, it never installs or
  repairs the hooks. Besides the `{"dev":…}` lines `--help` lists, a
  headless socket takes `{"dev":"presence",…}`, the Mac's lock, sleep
  and idle time. `--ears` turns on Boop's ears, the Mac's mic, which only
  the owner can check (L6): an agent's shell has no mic permission. `--buddies left:pixel:claude,right:boop:codex` runs two
  buddies side by side, each with its own pack and the agent it watches
  first, and `--links usb:SOCKET,usb:SOCKET` gives each its own board, in
  order; a `{"dev":…}` line then takes `"buddy": PLACE`. The menu-bar app
  reads the same from `settings.json`'s `buddies`, each with its board's
  `hello.id` as `board`, over Bluetooth. `BuddiesTests` checks them end to
  end on two fake boards.
- `.build/debug/beacon` and `.build/debug/mellowharness-emit`:
  MellowHarness's worked example and its event sender
  ([mellowharness/README.md](../mellowharness/README.md)).
- `.build/debug/linkkit-bridge`: the USB bridge (below).
- `agent-hooks`: agent-hooks' own command line, built in `agent-hooks/`
  with `swift build`. In tests, give it a temporary `HOME` and `--home`
  together, as for `boopdev hooks`.
- `python3 characters/charactergen.py`: `--check` and `--stage` a pack,
  and `--which` names the pack in use
  ([CHARACTER.md](../characters/CHARACTER.md) §2).
- The generators, each into a pack: `characters/boop/tools/voicegen/voicegen.py`
  (the voice file and the Mac's take table, from the recorded bank),
  `characters/pixel/tools/facegen/facegen.py` (what `make -C internal faces` runs),
  `characters/pixel/tools/sfxgen/sfxgen.mjs` (the sound effects, after facegen) and
  `characters/boop/tools/slimegen/slimegen.mjs` (the gel slime's
  assets, [its README](../characters/boop/tools/slimegen/README.md)).
- `internal/tools/fontgen/fontgen.py` (the device's fonts) and
  `internal/tools/mediagen/mediagen.py` (the READMEs' GIFs, from real
  runs, [its README](tools/mediagen/README.md)), with
  `internal/tools/.venv/bin/python`.
- `internal/tools/webcam/webcam.sh`: the camera recorder
  ([its README](tools/webcam/README.md)); `boopctl cam` wraps it.
- `internal/tools/session/session.py`: a demo through a real agent
  ([sessions/README.md](sessions/README.md)).
- `internal/skills/doctor/doctor.sh`: checks from inside an agent that
  its hooks reach Boop; `--headless` against a throwaway app.

**A pack's own design checks** live with the pack: Pixel's animation
bank's in [its design guide](../characters/pixel/design/README.md),
Boop's gel slime's in its
[VALIDATION.md](../characters/boop/design/slime-blob/VALIDATION.md) and
[slimegen's README](../characters/boop/tools/slimegen/README.md), and
Boop's recorded voice bank's in
[its README](../characters/boop/design/assets/boop-voice-v1/README.md).
None of them contacts Jev, a paid API or a device.

**Sharing the port.** Only one process can open the serial port, so
LinkKit's bridge owns it and shares it on a Unix socket, by the rules in
[linkkit/SPEC.md](../linkkit/SPEC.md) §8. `make build` builds it; run it
in a terminal of its own:

```sh
.build/debug/linkkit-bridge                     # the only USB board here, on $TMPDIR/linkkit-bridge.sock
.build/debug/linkkit-bridge --port /dev/cu.usbmodem1101 --socket /tmp/my.sock
```

`boopctl` finds the bridge at `$BOOP_BRIDGE`, else at `linkkit-bridge`'s
own socket, and the app's USB link takes it as
`--link usb:$TMPDIR/linkkit-bridge.sock`; both can use the board at the
same time.

## 3. The debug channel

Over USB the board takes every protocol message plus the `dbg.*`
messages that tests use: vitals, the device's own view of itself (the
turn's holder and waiting calls included), screenshots, a frozen clock,
injected presses and touches, the test pattern, the lights, touch
calibration and a reset. LinkKit answers the generic ones
([linkkit/SPEC.md](../linkkit/SPEC.md) §7) and Boop's app the rest
(`firmware/src/app/device.cpp`). The board ignores them over Bluetooth.

The board handles waiting lines in order before it draws the next frame,
and a debug message ends the batch. So a
reply reflects every message before it, and injected input and clock
steps land between frames exactly as in the simulator.

**Why screenshots are exact.** The firmware draws every frame into one
8-bit canvas and pushes that to the screen, and the simulator runs the
same drawing code into the same canvas. With a frozen clock and the same
scenario, a device screenshot and a simulator PNG are identical, pixel for
pixel, so any difference is a bug. A screenshot can't show colour
inversion, RGB/BGR order, rotation, the backlight or how the panel really
looks. That's L3's job.

## 4. Scenarios

A scenario is a JSON-lines file in `internal/firmware/test/scenarios/`,
played the same way in the simulator and on the board. This is the start
of `behaviour.jsonl`:

```
// Device behaviour: press feedback, gestures, and the
// needs-you tap. Shots are the rows' goldens.
{"clock":0}
{"t":"state","base":"idle","busy":0}
{"clock":500}
{"input":{"press":"tap"}}
{"clock":516}
{"expect":{"moment":null,"boot":true}}
{"shot":"press-feedback"}
{"clock":600}
{"expect":{"moment":{"anim":"poked","left_ms":2800},"last_input":{"k":"tap","at":600}}}
{"clock":850}
{"shot":"tap-poked"}
```

| Line | Meaning |
| --- | --- |
| `{"clock": ms}` | Freezes the clock at this time since the scenario started |
| A protocol message | Sent as if it came from the Mac: a `state`, or a `do` (the scenarios send `"play":"now"`, so each replaces the last at once, as a tool's does; `queue.jsonl` plays them as the Mac does, `next` and `if_free`) |
| A `dbg.` message | Sent as a debug request, such as `{"t":"dbg.pattern"}` |
| `{"input": {"press":"tap"}}` | Presses BOOT for 100 ms, or `"ms"`; 400 ms or more is push-to-talk (the scenarios write `"press":"hold"`) |
| `{"input": {"touch":[x,y]}}` | Touches the screen at (x, y) for 100 ms, or `"ms"` |
| `{"shot": "name"}` | Saves a screenshot as `name.png` |
| `{"expect": {…}}` | Reads `dbg.state` once and fails on a mismatch. Only the keys given are compared, recursively |
| `// …` | A comment; blank lines are skipped too |

An `input` line doesn't move the clock: the press stays down until the
clock passes its length, so the tap above lands at 600. Both runners send
`dbg.reset` first, so the board starts each scenario exactly as a fresh
simulator does.

Every screen and state the board draws
gets at least one scenario. Their pictures are the golden images in
`internal/firmware/test/golden/<scenario>/` for pixel and
`characters/boop/tests/golden-gel/<scenario>/` for gel.

## 5. The levels in detail

### L0: unit tests

- **Swift (`make -C internal test`):** every part in
  the Mac app (the core, the view, the harness, the outputs, Voice, the
  memory store, the device link and the runtime) has tests; the harness and outputs
  run with a scripted brain and no network, and the eval runner is tested
  the same way ([EVALS.md](EVALS.md)). `CoreFuzzTests` plays 20,000 random
  hooks from three sessions (Claude with subagents, and Codex) into the
  pipeline, with ticks and clock jumps, and checks after each that HISTORY
  and the screen agree (every `tool` wait view event is for a session
  shown waiting, nothing plays or wakes the brain while something needs you,
  and one request's number never changes its agent or project), and that
  a subagent's end, or a turn-level hook from inside one, answers only
  that subagent's request, isn't activity, and makes its session work
  again only while its turn goes on, and its start changes none of that.
  It also checks what the agents are doing shows only in the working
  look, every variation is one the visual has, and the rules' reactions
  never go out while something needs you or with an `id`, the error one
  at most every 30 s.
  `GoldenStateTests` runs every eval scenario with a scripted brain that
  answers from NOW alone and checks every state it's sent
  against `characters/boop/tests/golden-states/`, byte for byte, so
  a change to how the prompt is built can't pass unnoticed without Jev.
  A deliberate change rewrites them:
  `BOOP_GOLDEN_RECORD=1 BOOP_TEST_FILTER=Golden .build/debug/BoopTests`
  (`BOOP_GOLDEN_OUT=DIR` keeps what a failing run built, to diff).
  `MoodGraphTests` holds every pack in `characters/` to the universal
  moods and to a graph where every mood reaches every other by ordinary
  moves, so each can fade to the resting mood.
  Runtime and memory regressions cover late startup key reads, saved
  volume bounds, separate reports created in the same second, and
  recovery of invalid UTF-8 without treating unreadable files as corrupt.
- **agent-hooks (`swift test` in `agent-hooks/`, run by
  `make -C internal test`):** `AgentHooksTests` checks it on its own: the hook line and the
  client's field picking, against the real and synthetic payloads in its
  `Fixtures/`; every hook's event; sessions and "needs you"; the
  listener; the installer in a temporary home; where a thread opens; and
  project and workspace names, including a complete title line exactly
  at the bounded file tail's first byte.
- **MellowHarness (`swift test` in `mellowharness/`, run by
  `make -C internal test`):** `MellowHarnessTests` checks it on its own, with
  toy outputs and no Boop: the
  log and its defaults (time-window queries over out-of-order older logs
  included), lines, rules, the prompt's layout, the loop (the
  10 s wait, nothing from before a relaunch, repeated question keys
  dropped, a late answer running nothing), what takes a while, forced
  passes, `Choice`, the tick and the socket in; `JevBrainTests` Jev's
  request, answer and retry; `BeaconTests` the worked example, pinned as
  the spec quotes it.
- **LinkKit's host (`swift test` in `linkkit/`, run by
  `make -C internal test`):** `LinkKitTests` checks it on its own, each
  test naming the [linkkit/SPEC.md](../linkkit/SPEC.md) section it pins:
  framing and chunking, the Bluetooth outbox (states merge, no `do` is
  dropped, and past 4 KB the link is stuck) and reconnect timing, the
  socket transport (that letting go of it stops it, and a slowly reading
  bridge cannot renew the write deadline), the USB bridge
  on a pseudo-terminal (whole lines both ways, a client that stops
  reading dropped, the board going away), the wire, the keepalive,
  `hello` and trouble (a device that doesn't fit gets `state` but no
  `do`, and its `ev`s are dropped), who sent each message, ids, exactly one
  end per `do`, the give-up at its `ttl` plus 60 s and a link that drops.
- **LinkKit's device library (`pio test -d linkkit/device -e native`,
  run by `make -C internal fw-test`):** the library alone, from its own
  PlatformIO project, with a fake app and nothing of Boop's: every rule of the queue with its numbers
  (`test_queue`: `now`, `next` and `if_free`, rest and the queue moving at
  its exact millisecond, 4 waiting, `ttl` 5000 and 1–60000, refuse, the
  one `ended` per id, same id again, dropping the queue whole or by link,
  `dbg.reset`) and the rest of the kit (`test_kit`: 512-byte messages,
  `hello`, the host's `hello` asking for one, one too long for a message,
  its 60 s repeat, the 30 s host-gone window, `ev` routing, the app's
  words escaped, `dbg.ping`, `dbg.clock` and its thaw, `dbg.shot`,
  `dbg.state`, and the README's lamp example), and line reassembly
  across Bluetooth packets (a dropped link's part line included),
  screenshot encoding and the clock (`test_helpers`), each test naming
  its [linkkit/SPEC.md](../linkkit/SPEC.md) section.
- **Firmware (`make -C internal fw-test`):** BOOT's gestures
  (`test_gesture`); Boop's vocabulary message in and message out, its
  rules for the queue, the debug channel and inputs (`test_device`),
  including unchanged heartbeats causing no redraw while changed state,
  reconnection and leaving the test pattern still draw at once, and each
  latency counted from its event to the frame sent after it
  (`dbg.latency`, its window's p95 and the frames in flight);
  the behaviour state machine, to the millisecond, including
  `test_no_change_ever_cuts_hard` and
  `test_nothing_cuts_hard_as_it_plays_out`, which hold every change and
  every reaction running out (a brain reaction's borrowed face, a finish's loops
  and its `say`, a rule's reaction and a poke included), in the first pack's
  moods and the new moods' flip-books, to the face never cutting hard:
  the same design at the same moment, or the design's own shut eyes
  showing; and what the agents are doing, the rules' reactions and the finish
  with their facts and voice window, taps in a row and what shows first
  (`test_behaviour`); the canvas and
  renderer, the bubble in the bottom lane included (`test_canvas`,
  `test_face`); what reaches the AMOLED's panel (`test_push`): every
  window a frame's push plan sends, applied through the board's own code
  to a model panel, which must show the frame drawn after every frame of
  random drawing, lane changes, test patterns and frames without the lane,
  and of a long random gel sequence through `Device` (moods, states,
  reactions, pokes, needs you, bubbles, patterns, screenshots), whose frames
  must also match one surface drawn as before, and a lane the gel draws
  itself going out only when it changes; it prints what steady gel
  scenes send a frame; the animation bank's player
  against facegen's frames, every mood, state and variation, and the
  variations' host facts (`test_scene`, Pixel's pack's, which comes with
  the pixel face to a pack that uses it); the voice
  player (`test_voice`); and the sound effects' assets, policies, timing
  and mixer (`test_effects`).
- **The Mac app's look**, for Mac UI changes: run
  `.build/debug/Boop --snapshots DIR` and open every PNG and check:
  nothing clipped, no debug data, text readable, the Warm Terminal
  look. The run fails by itself on low contrast.
  It also checks setup-name character limits and validation, and includes
  Unicode names, invalid names and a crowded Overview at a bounded height.
  There are no goldens.

**Pass:** everything green. New code comes with tests.

### L1: simulator

1. `make -C internal sim` (or `internal/tools/boopctl sim <scenario>`)
   writes PNGs to `/tmp/boop-sim/<face>/<scenario>/` and compares them with the
   goldens. Unchanged pictures pass.
2. Open every new or changed picture and check it against the spec: the
   right screen and state, eyes centred and readable, text inside its
   area, palette colours, nothing clipped or overlapping.
3. Only then does `internal/tools/boopctl sim <scenario> --accept` update
   the goldens, with a one-line reason in the commit message (§7).

**Pass:** every golden matches, or the changed ones were looked at and
accepted.

### L2: device over USB

1. `make flash`, then `internal/tools/boopctl ping`: `sha` must match the
   commit under test, and `ble` mustn't be `conn`. **One writer only:** a
   Mac app connected over Bluetooth keeps sending its own `state`, which
   silently replaces the test's.
2. `internal/tools/boopctl run`: every `expect` passes, and every
   screenshot is identical to the simulator's.
3. `internal/tools/boopctl perf --motion`: a frame drawn in every second
   while moving, no sampled frame taking over 40 ms to draw and push (on a
   board whose `hello` says `gel`, which sends a frame while it draws the
   next, the longer of the two), at
   least 60 KB minimum free heap (not checked on the simulator, whose
   `sha` is `sim` and which has no heap), and no reset (uptime keeps rising). A
   frame is drawn only when the picture changes, and the designs step a
   few times a second, so `fps` follows the design rather than the board,
   and a second of a slow one draws only a few frames.
4. When a change touches the loop, inputs or drawing speed:
   `internal/tools/boopctl latency`: every press, tap, mood change and
   `do` reaches the panel within its budget at the p95 and at worst, none
   lost (the budgets are in §8). It
   prints the board's own figures beside its own and the frame-to-frame
   time, and the error of its clock match, a few ms at most. On the
   AMOLED, with the `amoled206_profile` build flashed,
   `internal/tools/boopctl perf --scenes` (and again with `--sound`): each
   scene's slowest second reaches its frames a second, working draws no
   frame over 50 ms, at least 50 KB of internal heap stays free and the
   DAC has no write errors. Flash the everyday build (`make flash`)
   afterwards.
5. When a change could leak memory or wedge the board:
   `internal/tools/boopctl soak` (20 minutes by default, with one 35 s
   silence halfway) ends with no reset, the minimum heap within 2 KB of
   where it stood after the first minute, the board still answering, no
   audio errors, the plain face back with no reaction or borrowed face
   (within 75 s of calm), and one `ended` for every reaction it sent
   ([linkkit/SPEC.md](../linkkit/SPEC.md) §4), short only by as many messages
   as were lost; a reaction skipped for waiting in the queue too long has
   ended too, and one skipped as a name the board doesn't play fails. It
   reports how they ended, the messages the board never got (from
   `dbg.state`'s `rx`, which counts `state` and `do`), messages that came back
   torn, and debug replies it had to ask for again.

**Pass:** all of the above.

### L3: webcam

At bring-up, and when a new screen or a change in colour or motion lands,
if authorised (§6):

1. **Framing:** `internal/tools/boopctl cam frame` finds the screen by
   lighting it white and then turning the backlight off, and saves the
   crop to `/tmp/boop-cam/crop.json`, turned so USB-C is on the left
   (`--usb` says where it is otherwise). If it finds no screen, skip L3
   and say so.
2. **Pattern:** `internal/tools/boopctl cam pattern` samples the test
   pattern: red reads as red (blue means BGR order), white is brighter
   than black (otherwise it's inverted), the UP arrow is at the top and
   the black bar on the USB-C side (rotation). Fix the panel settings
   until it passes and record them in [firmware/README.md](../firmware/README.md).
3. **Clips:** `internal/tools/boopctl cam clip <name>` records up to 10 s
   of a live preset with the clock running (`idle`, `needs_you`, `cheer`
   then a line, or `tap`) and saves a contact sheet of cropped frames.
   Compare it with the simulator's pictures: recognisably the same,
   readable, the right colours, and moving smoothly with no tearing, stuck
   frames or flicker. `internal/tools/boopctl e2e --clip` films a short
   Claude session through the pipeline.

**Pass:** the pattern check passes and the clips match the spec. The
camera judges "looks right"; pixel accuracy comes from L2.

### L4: pipeline over USB

This checks the whole path, hook → app → board, without Bluetooth, which
an agent can't use. `make -C internal e2e` (`internal/tools/boopctl e2e`)
does all of it:

1. `linkkit-bridge` owns the serial port on `/tmp/boop-e2e/usb.sock`.
2. The app runs headless with its own state and sockets, never the
   everyday ones:
   `.build/debug/Boop --headless --state-dir /tmp/boop-e2e/state --link usb:/tmp/boop-e2e/usb.sock --socket /tmp/boop-e2e/boop.sock --brain scripted --name Pip --no-open --debug`.
   The scripted brain makes runs repeatable; `boopctl e2e --brain jev`
   asks Jev, with `BOOP_JEV_KEY`.
3. The fixtures in `internal/app/Tests/Fixtures/hooks/e2e/` go through the
   real `agent-hook`, run as Boop installs it (`--keep-text`): a Claude
   session, a Codex approval answered within the 2 s grace period, and one
   left for 10 s. Between payloads they hold
   checkpoints: `expect` (poll `dbg.state` until it matches, within
   `within_ms`, 2000 by default; `shot` on the line saves a screenshot),
   `expect_not` (no match for `for_ms`, or until `until_ms` after the last
   hook), `wait_ms`, and `advance_ms` (moves the app's clock).
4. Latency runs from launching `agent-hook` to the board's `rx.state` going
   up. A hook that changes nothing sends no `state` and is left out.
5. Afterwards it checks the view events' lines in `debug.jsonl` against
   the fixtures' `expect.json` (for the whole run, not named fixtures or
   `--clip`), that no `PRIVATE_` marker from the
   fixtures reached any app file (`debug.jsonl` and the transcript
   included) but `PRIVATE_PROMPT` and `PRIVATE_CLOSING`, which mark your
   prompt and the agent's last message, and, from `boop.log`
   (`link brain → …` and `device: do N ended HOW (WHY)`), that every
   brain reaction came after the rules' reaction, that the board said how
   every one it was sent ended (`ended`, [linkkit/SPEC.md](../linkkit/SPEC.md) §4),
   that none was cut short by the brain's own next reaction, which waits
   for the one playing (LinkKit's queue), and
   that none was skipped as a name the board doesn't play. The board
   queues the brain's reactions, so one that waited behind another's
   `say`, or was skipped for waiting past its 5 s, is fine. It lists the
   ones a `now` cut short.

**Pass:** every checkpoint matches, and p95 latency from hook to board is
under 200 ms.

`internal/tools/boopctl soak --pipeline` loops the same fixtures for
`--minutes`, with a tap between rounds and a quiet minute at the end. It
fails on a board reset, a minimum-heap drift over 2 KB, audio errors, the
app exiting, or anything left on screen (not the plain face, or `attn` or
a reaction still set), and reports checkpoint misses. The CH340 now and then
drops bytes over a long run, so a debug request that loses its reply is
retried once and counted as a link glitch.

### L5: brain

1. While developing, `boopdev eval --only TEXT` (with `BOOP_JEV_KEY`)
   runs the scenarios the change touches, under a budget of Jev
   requests. As the final pass, `make eval` runs every scenario, 3 times
   each for an `always` one and once for the rest, with no budget. What it reports is in [EVALS.md](EVALS.md) §2.
2. Read a sample of its passes (`--timeline`, or the run's file it names)
   against the steering files (`characters/boop/steering/`): are the reactions and
   mood changes in character and never nagging, and the words and how
   long each face holds right for what happened?
3. After a change to the steering files or the questions, the working
   day ([EVALS.md](EVALS.md) §5): `boopctl workday run` twice before the
   change and twice after, same seed, and `boopctl workday report` and
   `boopctl workday check` on each.
   How often the mood changes per hour, whether a routine step changed
   it, and how often, with which faces and which takes Boop reacts,
   before against after.

**Pass:** every scenario passes in every run, but for known gaps
([EVALS.md](EVALS.md) §1), and every `always` one does; no pass is dropped; the
slowest pass is under the 1.5 s deadline; and the sample reads well.

### L6: the owner

Only a person can check Bluetooth (`make run`), real touches and
calibration (`boopctl calibrate`), sound by ear (`boopctl takes`,
`takes --board-volume`, `takes --levels`, `play needs`), real Claude
Code and Codex sessions, the Mac app in the real menu bar, and how Boop
feels. Boop's ears too: from a terminal you started, run
`.build/debug/Boop --headless --state-dir /tmp/ears --ears --debug`, then
say its name, "good boy" and its name with "dance", clap and shout, and
look for the `heard` events (`git grep -n "AVAudioFile\|write(to"
app/Boop/Ears.swift` finds nothing: no audio is written). A day of real
use under `make debug` reads back with `make day`:
what Boop did each hour and why, relaunches included.

## 6. Webcam

The camera is opt-in ([CLAUDE.md](../CLAUDE.md)), and its procedure is the
[`webcam-verify` skill](skills/webcam-verify/SKILL.md). Its
footage stays local, out of git. If framing fails, skip
L3 and report it.

## 7. Evidence

Evidence isn't kept in the repo. Work that needs a record says in its
commit message or pull request what was checked, how, and what it showed,
and anything accepted or changed and why. Raw logs, screenshots and
footage stay local, out of git, as the webcam's footage already does.

## 8. Budgets

The targets Boop is held to, from hook to screen. Where a package's spec
or Boop's code owns a number, that is the source and this
table only gathers them.

**How latency is measured.** The device times each input and message
from when it knew of it to the end of sending the first frame drawn
after it (`app::Latency`, read with `dbg.latency`): a press going down
(BOOT or a touch), a tap's release, which plays the poke, a `state` that
changes the picture, and a `do` as it starts to play, so not its wait
in the queue. A frame counts as sent when the AMOLED's push task has
finished it, when the CYD's push returns, and in the simulator when it's
taken. Each kind keeps its latest 32 samples for the p95 and the worst.
The device stamps a message when it reads it and a press when a loop pass
sees it, so `boopctl latency` adds the wait back: it finds the board's
clock with pings and times a press, a `state` and a `do` from when it
sent them. A tap counts from its release, including the 50 ms the device
waits to be sure the finger lifted.

| Path | Target | Source, and what checks it |
| --- | --- | --- |
| Agent event → pixel (the reactive speed: hook → rule → `state` or a rule's reaction, never waiting for the brain) | < 200 ms p95 | This table; `make -C internal e2e` fails over it (L4) |
| An input or a Mac message → the frame showing it (the device's reflex speed: tap feedback, blinks, the queue, needs you, never waiting for the Mac) | A press 80 ms p95 (100 at worst), a tap's release to its poke 80 ms, a `state` or a `do` 100 ms, on the device | `LATENCY_BUDGETS` in `internal/tools/boopctl_lib/`; `boopctl latency` on the board (L2), and `test_device`'s `test_the_redraw_cap_doesnt_delay_a_press` |
| Hook client | Single-digit ms. Connecting and writing share 50 ms for each app listening, then it gives up on it; it exits within 1 s whatever happens. It reads at most 256 KB and keeps fields of at most 200 characters | `HookSocket.send` and `agent-hook`'s `main.swift` in `agent-hooks/Sources/` |
| Hook entry timeout | 3 s in the agent's settings; never reached | `HookInstaller.timeout` in `agent-hooks/Sources/AgentHooks/` |
| Hook server | A connection is read until it closes, is quiet for 200 ms, or reaches 64 KB | `HookServer` in `agent-hooks/Sources/AgentHooks/` |
| Brain, per pass (the deliberative speed, which never blocks the reactive one) | Jev's answer within 1.5 s, one retry included; a late answer is dropped | `deadlineMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| A brain reaction's wait in the queue | 5 s on the device (its `ttl`), then the device skips it | `BoopDevice.reactionTTL` in `app/BoopKit/DeviceLink/BoopDevice.swift` |
| An `ended` | The link gives up on it at the `do`'s `ttl` plus 60 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §5 |
| An output's `run` | Logged if it takes over 300 ms | `outputSlowMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| `state` keepalive | Every 10 s; the device gives up on the app after 30 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §9, `kNoAppMs` in `firmware/src/app/behaviour.h` |
| Protocol message | At most 512 bytes; each text field has its own cap (`attn.project` 47 bytes, `who.thread` 23, …), so every `state` fits | [linkkit/SPEC.md](../linkkit/SPEC.md) §9 |
