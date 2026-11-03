# Boop: verification

Updated 2026-11-03. How we check that Boop works, including what's on its
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
`main` and every pull request, all as Boop, the default pack, except
where it says:

- `make -C internal test`, on macOS 26.
- The Python tests that need only the standard library, on the Mac's own
  Python 3.9: `python3 characters/charactergen.py --check`, and the
  `unittest` suites in `internal/characters/`,
  `internal/tools/session/tests/` and each pack's `tests/tools/` (the
  part of `make -C internal tools-test` without boopctl's venv or the
  webcam recorder).
- `make -C internal fw-test`, then the Mac's mirror of the board: its
  page's tests and `boopctl mirror` (the part of `make -C internal mirror`
  without Emscripten, which the runners don't have; they test the board.js
  checked in).
- Both boards' firmware: the CYD's with Pixel
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

**Make targets.** The root `Makefile` has the owner's everyday targets
and nothing else; `internal/Makefile` has the builds, tests and tools
agents use, run from the repo root as `make -C internal <target>`. Each target's comment says what it runs.

| Target | What it does |
| --- | --- |
| `make dev` | The debug app with `--debug`, on a folder of its own (`~/Library/Application Support/Boop-dev`), with the simulator window's page beside it (`app/tools/simulator.sh`), the studio's server and its matrix (`boopdev prompts` written first) and `boopctl dash` in a Terminal window of its own (`internal/tools/dev.sh`). It starts on the board over Bluetooth, so it's the owner's; onboarding's act 4 and Settings' Simulator row switch to the simulator window (it needs Emscripten) and back, and the choice is kept. Its folder registers its own hook socket (`dev-Boop-dev.sock` in `~/.agent-hooks/sockets`) and keeps its own Jev key (Keychain account `dev-Boop-dev`), and it never changes the real hooks or the login item. `FRESH=1` starts the folder and its key afresh, so it's onboarding again. Ctrl-C stops the app, the studio's server and the dashboard |
| `make bundle` | `Boop.app` as it ships, in `.build/Boop.app` (`app/tools/bundle.sh`): a release build for Apple silicon and Intel, signed with the hardened runtime, ad hoc unless `SIGN_IDENTITY` names a Developer ID. It fails unless the binary links FoundationModels weak and asks for macOS 14.0 at least. Opening it uses Bluetooth, so that's the owner's; agents can check it with `Boop.app/Contents/MacOS/Boop --snapshots DIR` or `--headless`. `INTERNAL=1` makes the internal build, in `.build/internal/Boop.app`, with the simulator as a body to choose, in a window of the app's own (`app/Boop/BoardWindow.swift`). It needs Emscripten. On the simulator it never uses Bluetooth, so an agent may open it on a folder of its own (`--state-dir`) and choose the simulator in onboarding's act 4 before anything looks for a board |
| `make demo` | Asks which demo and where it plays, then plays it: on the simulator's page from its checked-in recording, at once, on a board, or with a real agent (`simulator/tools/demos.py`, [characters/DEMOS.md](../characters/DEMOS.md)). `NAME=` plays one without asking, `NAME=all` every one in the page |
| `make flash` | Builds the firmware and uploads it to the board on USB ([firmware/README.md](../firmware/README.md)) |
| `make eval` | Every eval scenario against Jev at the full level (L5, [EVALS.md](EVALS.md) §2), only when the owner asks or before a release. It needs `BOOP_JEV_KEY`, and `BOOP_JEV_OVER_LIMIT=1`, which it never sets |
| `make clean` | Deletes every build's output. It keeps `internal/tools/.venv` and `firmware/.platformio-core` |
| `make -C internal build` | The Mac app, `boopdev`, the tests' runner, `agent-hook`, `mellowharness-emit`, `beacon`, `linkkit-bridge` and `linkkit-flash`. Importing a target that isn't a declared dependency fails it ([internal/README.md](README.md), How it's wired) |
| `make -C internal app` | What `make dev` needs: the Mac app, `agent-hook` and `boopdev`, without the tests |
| `make -C internal simulator` | The board in a browser at `http://127.0.0.1:8206/`, alone, its USB on `/tmp/boop-sim-usb.sock` ([simulator/README.md](../simulator/README.md); several boards side by side with `serve.py --cable NAME=SOCKET`), and beside it the Character Studio at `/characters/studio/`. No Bluetooth, so agents may run it |
| `make -C internal packs` | The character packs the engine is tested with (`characters/packs.json`), each fetched from its repository if it's missing: a clone in `characters/.repos/`, and `characters/<id>` a link to its pack (`internal/tools/packs.py`; `--update` pulls them, `ID=PATH` links a pack of yours in its place) |
| `make -C internal new-character ID=… NAME=…` | A new character from Pixel's pack (`internal/tools/new_character.py`; `TO=DIR`, by default `../ID`): its id and name set, linked as `characters/ID` and checked with `boopdev check`. [characters/new-character-playbook.md](../characters/new-character-playbook.md) says what to make its own |
| `make -C internal check` | Every check that needs no board, camera or Jev key, one after another: `packs`, `test`, `fw-test`, `tools-test`, `sim` and `mirror`, then the chosen pack staged again, as some stage another |
| `make -C internal test` | `make -C internal build`, then Boop's Swift tests through the XCTest shim, with Boop's pack (`CHARACTER=boop .build/debug/BoopTests`; `BOOP_TEST_FILTER=Golden` runs only the tests whose `Class.method` contains `Golden`), then each package's own, one test at a time: `swift test --no-parallel --scratch-path .build/tests` in `agent-hooks/`, `mellowharness/` and `linkkit/`. That build now and then fails with "plugin for module 'TestingMacros' not found", a toolchain flake, even from a clean build folder, so the target retries that failure alone, up to eight tries in all |
| `make -C internal fw` | The firmware for every board the chosen pack has a face for (`charactergen.py --boards`) |
| `make -C internal fw-test` | The firmware's unit tests on the Mac (env `native`): the chosen pack's `tests/firmware/`, then the engine's suites in `internal/firmware/test/` with Pixel's pack, then LinkKit's device library's own (`pio test -d linkkit/device -e native`). `pio.sh test` keeps each project's tests in its `.pio/test`, apart from `pio run`'s `.pio/build` |
| `make -C internal sim` | Every scenario in the simulator, against the goldens (L1): the pixel face's, with Pixel's pack, then the gel face's, with Boop's |
| `make -C internal mirror` | The Mac's mirror of the board ([characters/CHARACTER.md](../characters/CHARACTER.md) §9): its page's tests (`node --test characters/boop/tests/mirror/page.test.mjs`), every gel scenario on it and on the native simulator, the same pixel for pixel (`internal/tools/boopctl mirror`), and its `board.js` built again and compared with the one checked in (`firmware/tools/mirror.sh --check`). It needs Emscripten and Node |
| `make -C internal demos` | Records each demo whose script has changed since its recording, or has none, into `characters/PACK/demo/recordings/` (`simulator/tools/demos.py record`); `NAMES=…` records those again, `ALL=1` every one. It needs the app, PlatformIO's native env (built once for each pack) and no board |
| `make -C internal sim-test` | The simulator's tests ([simulator/README.md](../simulator/README.md), Tests), with the page built for the staged pack and for Pixel's (`simulator/web/build.sh pixel`). It needs Emscripten and Node |
| `make -C internal e2e` | `make -C internal build`, then the pipeline check (L4) |
| `make -C internal tools` | Makes or refreshes `internal/tools/.venv` (pyserial, Pillow, Textual). `boopctl` runs it on its first run |
| `make -C internal tools-test` | The tools' own tests, with no board or camera: boopctl's, the Character Studio's logic and server's (`node --test characters/studio/tests/*.test.cjs`, so it needs Node), the webcam recorder's, the session tool's, that every demo's recording is up to date (`simulator/tools/demos.py check`), `charactergen.py`'s (`internal/characters/`) and each pack's `tests/tools/` |

**Tools.**

- `internal/tools/boopctl`: the board over USB (`ping`, `state`, `shot`,
  `send`, `play`, `takes`, `card`, `calibrate`), who has the board and
  what was flashed on it (`board`, below), a board's factory test,
  pass or fail (`factory`; `--auto` asks a person nothing), the scenarios (`sim`,
  `run`, and `mirror`), measurements (`perf`, `latency`, `soak`), the pipeline check
  (`e2e`), the webcam (`cam`), the debug logs (`dash`, `day`), and a reference a person gave
  (`reference`, [CHARACTER.md](../characters/CHARACTER.md) §16). `--port` picks the
  serial port; without it, while a bridge runs (below), commands go
  through the bridge. `dash` reads only the app's `debug.jsonl`, and its
  keys are in its footer: `m` sets a lasting mood, `r` forces a pass, `p`
  previews on its own sim, `d` dreams now, `D` previews a dream and keeps
  nothing, `s` shows the prompt Jev read, `t` the timeline of every line,
  and `b` asks for a bug report and copies its path. A report gets the
  device's screen as `screen.png` when the app reaches its device through
  a socket (`about.json`'s `link` is `usb:SOCKET`).
- `.build/debug/boopdev`: `eval` (L5, [EVALS.md](EVALS.md)), `check`
  (character packs, [CHARACTER.md](../characters/CHARACTER.md)),
  `read-check` (Apple Intelligence's readings of the samples in
  `internal/app/Tests/Fixtures/readings.json`, scored against floors),
  `memory write` (the dream's write, with Apple Intelligence's answers, over the
  fixtures in `internal/app/Tests/Fixtures/memory-nights.json`, for a
  person to judge it by), `memory gates` (its small questions scored
  against labels in `Fixtures/memory-gates.json`), `prompts` (what the brain reads in every
  eval scenario, with no key, to `characters/studio/prompts.js` for the
  Character Studio's Brain view; `make dev` writes it) and `hooks` (Boop's
  hook installer, against any `--home`).
- `.build/debug/Boop`: the menu-bar app; `--headless --state-dir DIR`,
  the whole runtime with no UI or Bluetooth (L4); `--snapshots DIR`, the
  popover's panes, onboarding's acts and their states, gel frames and
  menu-bar icons as PNGs (L0). Besides the `{"dev":…}` lines `--help`
  lists, a headless socket takes `{"dev":"presence",…}`, the Mac's lock,
  sleep and idle time. `--buddies left:pixel:claude,right:boop:codex` runs
  two buddies side by side, and `--links usb:SOCKET,usb:SOCKET` gives each
  its own board; the menu-bar app reads the same from `settings.json`'s
  `buddies`, each with its board's `hello.id` as `board`, over Bluetooth.
- `.build/debug/beacon` and `.build/debug/mellowharness-emit`:
  MellowHarness's worked example and its event sender
  ([mellowharness/README.md](../mellowharness/README.md)).
- `.build/debug/linkkit-bridge`: the USB bridge (below).
- `.build/debug/linkkit-flash`: writes firmware onto a board over USB
  through its ROM bootloader, without PlatformIO
  ([linkkit/ARCHITECTURE.md](../linkkit/ARCHITECTURE.md)); `make flash`
  still builds and uploads with PlatformIO.
- `agent-hooks`: agent-hooks' own command line, built in `agent-hooks/`
  with `swift build`. In tests, give it a temporary `HOME` and `--home`
  together, as for `boopdev hooks`.
- `python3 characters/charactergen.py`: `--check` and `--stage` a pack,
  `--which` names the pack in use, `--boards` the boards it has a face
  for and `--sim-face` the face the simulator draws for it
  ([CHARACTER.md](../characters/CHARACTER.md) §2).
- `internal/tools/packs.py`: the character packs in `characters/`,
  fetched from their repositories (what `make -C internal packs` runs;
  `--help`).
- The generators, each in its pack and writing into it, which its
  repository's `make` runs: `characters/boop/tools/voicegen/voicegen.py`
  (the voice file and the Mac's take table; SlimeBuddy's `make voice`;
  beside it `placeholders.py`, which speaks the planned lines not recorded
  yet and needs `brew install espeak-ng`, and `reply_slots.py`, which turns
  the replies' lines in `plan/voice-range.md` into the bank's slots),
  `characters/pixel/tools/facegen/facegen.py` (Pixel's faces, about
  7 minutes; PixelBuddy's `make faces`, which runs sfxgen after it),
  `characters/pixel/tools/sfxgen/sfxgen.mjs` (the sound effects) and
  `characters/boop/tools/slimegen/slimegen.mjs` (the gel slime's tables
  and the pack's moods;
  [its README](https://github.com/Mellow-Machines-Lab/SlimeBuddy/blob/main/character/tools/slimegen/README.md)), and
  the engine's `firmware/tools/mirror.sh` (the Mac's mirror of the
  board, `characters/boop/mac/mirror/board.js`, with Emscripten;
  `--check` builds it again and compares), on `firmware/tools/wasm.sh`,
  which `simulator/web/build.sh` shares.
- `swift internal/tools/appicon/appicon.swift app/Boop/AppIcon.icns`:
  the app's placeholder icon; a second argument also writes a 1024-pixel
  PNG to look at.
- `node characters/studio/check.cjs`: the Character Studio in a headless
  browser (its README, Checking it). It needs `boopdev prompts` run first,
  and the studio's server (`python3 simulator/web/serve.py`).
- `internal/tools/fontgen/fontgen.py` (the device's fonts) and
  `internal/tools/mediagen/mediagen.py` (the READMEs' GIFs, from real
  runs, [its README](tools/mediagen/README.md)), with
  `internal/tools/.venv/bin/python`.
- `internal/tools/webcam/webcam.sh`: the camera recorder
  ([its README](tools/webcam/README.md)); `boopctl cam` wraps it.
- `internal/tools/session/session.py`: a demo through a real agent
  ([sessions/README.md](sessions/README.md)).
- `simulator/tools/demos.py`: the demos, which `make demo` asks you to
  choose from; `list`, `play`, `all`, `record` and `check`
  ([characters/DEMOS.md](../characters/DEMOS.md)).
- `internal/skills/doctor/doctor.sh`: checks from inside an agent that
  its hooks reach Boop; `--headless` against a throwaway app.

**A pack's own design checks** live with the pack: Pixel's animation
bank's in [its design guide](https://github.com/Mellow-Machines-Lab/PixelBuddy/blob/main/character/design/README.md),
Boop's gel slime's in its
[VALIDATION.md](https://github.com/Mellow-Machines-Lab/SlimeBuddy/blob/main/character/design/slime-blob/VALIDATION.md) and
[slimegen's README](https://github.com/Mellow-Machines-Lab/SlimeBuddy/blob/main/character/tools/slimegen/README.md), and
Boop's recorded voice bank's in
[its README](https://github.com/Mellow-Machines-Lab/SlimeBuddy/blob/main/character/design/assets/boop-voice-v1/README.md).
None of them contacts Jev, a paid API or a device.

**Side by side.** Make targets can run at once, in one checkout or in
worktrees beside it. A stage replaces only the staged files that differ
([CHARACTER.md](../characters/CHARACTER.md) §2), the unit tests build
apart from the simulator (`fw-test`, above), and every tool keeps its
output under `/tmp/<tool's folder>/<checkout>/` (`checkout_tmp`),
`<checkout>` the checkout's folder name and a hash of its path:
`/tmp/boop-sim/`, `/tmp/boop-run/`, `/tmp/boop-e2e/`, `/tmp/boop-e2e-out/`,
`/tmp/boop-soak/`, `shot`'s picture, `cam`'s crop and clips, and
`mediagen`'s Beacon socket. An incremental native build is the clean one,
after a checkout or a merge too: PlatformIO decides by contents, not
dates. The board is one process's at a time (below), and so is
`boopctl e2e`'s.

**Sharing the port.** Only one process can open the serial port, so
LinkKit's bridge owns it and shares it on a Unix socket, by the rules in
[linkkit/SPEC.md](../linkkit/SPEC.md) §8. `make -C internal build` builds it; run it
in a terminal of its own:

```sh
.build/debug/linkkit-bridge                     # the only USB board here, on $TMPDIR/linkkit-bridge.sock
.build/debug/linkkit-bridge --port /dev/cu.usbmodem1101 --socket /tmp/my.sock
```

`boopctl` finds the bridge at `$BOOP_BRIDGE`, else at `linkkit-bridge`'s
own socket, and the app's USB link takes it as
`--link usb:$TMPDIR/linkkit-bridge.sock`; both can use the board at the
same time.

**Sharing the board.** Many sessions share one board, so everything that
talks to it over USB takes the board's lock first,
`/tmp/boop-board.lock` (`internal/tools/boopctl_lib/board.py`), one for
every board on the Mac: boopctl's serial link for each command, `e2e`
and `soak --pipeline` for as long as their bridge runs, and every
PlatformIO upload, `make flash` and `-e amoled206_profile` included.
A tool that finds it held prints who has it and waits up to a minute
(`BOOP_BOARD_WAIT=SECONDS`), then stops and says so. The simulator's
port needs no lock, and nor does a link through a bridge: whoever
started the bridge holds the board for it.

```sh
internal/tools/boopctl board                          # who has the board now, and the last uploads: when, env, commit, worktree
internal/tools/boopctl board hold -- sh -c 'firmware/tools/pio.sh run -e amoled206_profile -t upload && internal/tools/boopctl perf --scenes && make flash'
internal/tools/boopctl board hold -- .build/debug/linkkit-bridge   # a bridge started by hand
```

`board hold -- CMD` keeps the board through all of CMD, so no other
session flashes between its steps. Every upload is logged in
`/tmp/boop-board-flashes.log`, so `board` tells you whose firmware is on
the board. `linkkit-flash` and the Mac app take no lock: run
`linkkit-flash` under `board hold`.

## 3. The debug channel

Over USB the board takes every protocol message plus the `dbg.*`
messages that tests use. LinkKit answers the generic ones
([linkkit/SPEC.md](../linkkit/SPEC.md) §7) and Boop's app the rest
(`firmware/src/app/device_debug.cpp`). The board ignores them over Bluetooth.

The board handles waiting messages in order before it draws the next
frame, and a debug message ends the batch. So a reply reflects every
message before it, and injected input and clock steps land between frames
exactly as in the simulator.

**Why screenshots are exact.** The firmware and the simulator run the same
drawing code into the same 8-bit canvas. With a frozen clock and the same
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

Each suite says what it pins.

- **Swift (`make -C internal test`):** every part of the Mac app has
  tests; the harness and outputs run with a scripted brain and no network,
  and so does the eval runner ([EVALS.md](EVALS.md)). `CoreFuzzTests`
  plays random hooks through the pipeline and checks that HISTORY and the
  screen agree. `GoldenStateTests` runs every eval scenario with a scripted
  brain and checks every state it's sent against
  `characters/boop/tests/golden-states/`, byte for byte, so a change to
  how the prompt is built can't pass unnoticed without Jev. A deliberate
  change rewrites them:
  `BOOP_GOLDEN_RECORD=1 BOOP_TEST_FILTER=Golden .build/debug/BoopTests`
  (`BOOP_GOLDEN_OUT=DIR` keeps what a failing run built, to diff).
- **agent-hooks (`swift test` in `agent-hooks/`, run by
  `make -C internal test`):** `AgentHooksTests`, on its own, against the
  real and synthetic payloads in its `Fixtures/`.
- **MellowHarness (`swift test` in `mellowharness/`, run by
  `make -C internal test`):** `MellowHarnessTests`, on its own with toy
  outputs and no Boop; `JevBrainTests`, Jev's request, answer and retry;
  `BeaconTests`, the worked example.
- **LinkKit's host (`swift test` in `linkkit/`, run by
  `make -C internal test`):** `LinkKitTests`, on its own, each test naming
  the [linkkit/SPEC.md](../linkkit/SPEC.md) section it pins.
- **LinkKit's device library (`pio test -d linkkit/device -e native`,
  run by `make -C internal fw-test`):** the library alone, with a fake app
  and nothing of Boop's: `test_queue`, `test_kit` and `test_helpers`, each
  test naming its [linkkit/SPEC.md](../linkkit/SPEC.md) section.
- **Firmware (`make -C internal fw-test`):** in
  `internal/firmware/test/`, `test_gesture` (BOOT's, the touch's and the
  motion sensor's), `test_device` (messages, the queue's rules, the debug
  channel, inputs and latency), `test_behaviour` (the behaviour state
  machine, to the millisecond), `test_canvas` and `test_face` (the canvas
  and renderer), `test_push` (what reaches the AMOLED's panel), `test_voice`,
  `test_effects` (the sound effects) and `test_rig`. In Pixel's pack,
  `test_scene` (the animation bank's player against facegen's frames) and
  `test_rig_face`. In Boop's, `test_gel`, which holds the gel slime's engine
  to every rule of its design ([its VALIDATION.md](https://github.com/Mellow-Machines-Lab/SlimeBuddy/blob/main/character/design/slime-blob/VALIDATION.md)).
- **The Mac app's look**, for Mac UI changes: run
  `.build/debug/Boop --snapshots DIR` and open every PNG and check:
  nothing clipped, no debug data, text readable, the Warm Terminal
  look, and nothing blurred or seamed: the panes and acts are drawn at
  2 pixels a point, as a Retina Mac shows them. The run fails by itself on
  low contrast. It includes Unicode names, invalid names, every onboarding
  act (`onboarding-*`) and a crowded Overview at a bounded height.
  There are no goldens.

**Pass:** everything green. New code comes with tests.

### L1: simulator

1. `make -C internal sim` (or `internal/tools/boopctl sim <scenario>`)
   writes PNGs to `/tmp/boop-sim/<checkout>/<face>/<scenario>/` (§2, Side by
   side) and compares them with the
   goldens. Unchanged pictures pass.
2. Open every new or changed picture and check it against the spec: the
   right screen and state, eyes centred and readable, text inside its
   area, palette colours, nothing clipped or overlapping.
3. Only then does `internal/tools/boopctl sim <scenario> --accept` update
   the goldens, with a one-line reason in the commit message (§7).

4. When what the gel board draws changes, `firmware/tools/mirror.sh`
   builds the Mac's mirror of the board again, and
   `make -C internal mirror` checks it draws every scenario's shots as
   the simulator does.

**Pass:** every golden matches, or the changed ones were looked at and
accepted; the mirror's shots are the simulator's.

### L2: device over USB

1. `make flash`, then `internal/tools/boopctl ping`: `sha` must match the
   commit under test, and `ble` mustn't be `conn`. **One writer only:** a
   Mac app connected over Bluetooth keeps sending its own `state`, which
   silently replaces the test's.
2. `internal/tools/boopctl run`: every `expect` passes, and every
   screenshot is identical to the simulator's.
3. `internal/tools/boopctl perf --motion`: a frame drawn in every second
   while moving, no sampled frame taking over 40 ms to draw and push (on a
   board whose `hello` says `gel`, the longer of the two), at
   least 60 KB minimum free heap (not checked on the simulator, whose
   `sha` is `sim` and which has no heap), and no reset (uptime keeps rising).
   `fps` follows the design rather than the board: a frame is drawn only
   when the picture changes.
4. When a change touches the loop, inputs or drawing speed:
   `internal/tools/boopctl latency`: every press, tap, mood change and
   `do` reaches the panel within its budget at the p95 and at worst, none
   lost (the budgets are in §8). On the
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
   audio errors, the plain face back with no Moment or emotion
   (within 75 s of calm), and one `ended` for every `do` it sent
   ([linkkit/SPEC.md](../linkkit/SPEC.md) §4), short only by as many messages
   as were lost; one skipped as a name the board doesn't play fails.

**Pass:** all of the above.

### L3: webcam

At bring-up, and when a new screen or a change in colour or motion lands,
if authorised (§6):

1. **Framing:** `internal/tools/boopctl cam frame` finds the screen by
   lighting it white and then turning the backlight off, and saves the
   crop to `/tmp/boop-cam/<checkout>/crop.json`, turned so USB-C is on the left
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

1. `linkkit-bridge` owns the serial port on `/tmp/boop-e2e/<checkout>/usb.sock`.
2. The app runs headless with its own state and sockets, never the
   everyday ones:
   `.build/debug/Boop --headless --state-dir /tmp/boop-e2e/<checkout>/state --link usb:/tmp/boop-e2e/<checkout>/usb.sock --socket /tmp/boop-e2e/<checkout>/boop.sock --brain scripted --name Pip --no-open --debug`.
   The scripted brain makes runs repeatable; `boopctl e2e --brain jev`
   asks Jev, with `BOOP_JEV_KEY`. The volume is 0, so a run is silent on
   the board.
3. The fixtures in `internal/app/Tests/Fixtures/hooks/e2e/` go through the
   real `agent-hook`, run as Boop installs it (`--keep-text`), with the
   run's socket and an empty home. Between payloads they hold
   checkpoints: `expect` (poll `dbg.state` until it matches, within
   `within_ms`, 2000 by default; `shot` on the line saves a screenshot),
   `expect_not` (no match for `for_ms`, or until `until_ms` after the last
   hook), `wait_ms`, and `advance_ms` (moves the app's clock).
4. Latency runs from launching `agent-hook` to the board's `rx.state` going
   up. A hook that changes nothing sends no `state` and is left out.
5. Afterwards it checks the view events' lines in `debug.jsonl` against
   the fixtures' `expect.json` (for the whole run, not named fixtures or
   `--clip`), that no `PRIVATE_` marker from the fixtures reached any app
   file, and, from `boop.log`, how every Moment Jev made ended (none
   skipped as a name the board doesn't play, none cut short by Jev's own
   next one). One that waited in the queue, or was skipped for waiting past
   its 5 s, is fine.

**Pass:** every checkpoint matches, and p95 latency from hook to board is
under 200 ms.

`internal/tools/boopctl soak --pipeline` loops the same fixtures for
`--minutes`, with a poke between rounds and a quiet minute at the end. It
fails on a board reset, a minimum-heap drift over 2 KB, audio errors, the
app exiting, or anything left on screen (not the plain face, or `attn` or
a Moment still set), and reports checkpoint misses. The CH340 now and then
drops bytes over a long run, so a debug request that loses its reply is
retried once and counted as a link glitch.

### L5: brain

1. First, with no key, `boopdev eval --scripted`: every scenario with the
   expect brain, so anything that fails is the pipeline's, the screen's or
   the scenario's, not Jev's. A code-only change that leaves prompts unchanged needs no
   Jev run. While working, `boopdev eval --only TEXT` (with `BOOP_JEV_KEY`)
   runs the scenarios the change touches. `boopdev eval` runs the quick level,
   for a change to steering or prompts broadly, and `--level standard` runs
   before a branch merges. `make eval` runs the full level only when the owner
   asks or before a release. All of them count against a daily limit of Jev
   requests. The levels, the limit and what a run reports are in
   [EVALS.md](EVALS.md) §2.
   After a change to the written memory's write or checks (`MemoryProposer`, `MemoryPipeline`, `MemoryEdits`),
   `boopdev memory write`, read case by case against each fixture's `accept`, and
   `boopdev memory gates` for a changed question.
   After a change to how prompts or last messages are read (the scrubber, the cues or the
   labeler's instructions), `boopdev read-check`, which fails under its
   floors, and the scenarios with prompts or messages again with `--labeler apple`.
   The scrubber's own corpora, `must-scrub.tsv` and
   `must-keep.txt` in `internal/app/Tests/Fixtures/scrubber/`, run with
   the unit tests; a secret format it missed goes in the first, and text
   it scrubbed by mistake in the second.
2. Read a sample of its passes (`--timeline`, or the run's file it names)
   against the steering files (`characters/boop/steering/`): are the Moments and
   mood changes in character and never nagging, and the words and how
   long each emotion holds right for what happened?

**Pass:** every scenario passes in every run, but for known gaps
([EVALS.md](EVALS.md) §1), and every `always` one does; no pass is dropped; the
slowest pass is under the 1.5 s deadline; and the sample reads well.

### L6: the owner

Only a person can check Bluetooth (`make dev`), real touches and
calibration (`boopctl calibrate`), sound by ear (`boopctl takes`,
`takes --board-volume`, `takes --levels`, `play needs`), real Claude
Code and Codex sessions, the Mac app in the real menu bar, and how Boop
feels. A day of real
use under `make dev` reads back with
`internal/tools/boopctl day --state-dir ~/Library/Application\ Support/Boop-dev`:
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
(BOOT or a touch), a poke's release, a `state` that changes the picture,
and a `do` as it starts to play, so not its wait in the queue. A frame
counts as sent when the AMOLED's push task has finished it, when the CYD's
push returns, and in the simulator when it's taken. Each kind keeps its
latest 32 samples for the p95 and the worst. `boopctl latency` adds the
wait before the device stamps it back: it finds the board's clock with
pings and times a press, a `state` and a `do` from when it sent them. A
poke counts from its release, including the 50 ms the device waits to be
sure the finger lifted.

| Path | Target | Source, and what checks it |
| --- | --- | --- |
| Agent event → pixel (the reactive speed: hook → rule → `state` or a rule's Moment, never waiting for the brain) | < 200 ms p95 | This table; `make -C internal e2e` fails over it (L4) |
| An input or a Mac message → the frame showing it (the device's reflex speed: a touch's feedback, blinks, the queue, needs you, never waiting for the Mac) | A press 80 ms p95 (100 at worst), a poke's release 80 ms, a `state` or a `do` 100 ms, on the device | `LATENCY_BUDGETS` in `internal/tools/boopctl_lib/`; `boopctl latency` on the board (L2), and `test_device`'s `test_the_redraw_cap_doesnt_delay_a_press` |
| Hook client | Single-digit ms. Connecting and writing share 50 ms for each app listening, then it gives up on it; it exits within 1 s whatever happens. It reads at most 256 KB and keeps fields of at most 200 characters | `HookSocket.send` and `agent-hook`'s `main.swift` in `agent-hooks/Sources/` |
| Hook entry timeout | 3 s in the agent's settings; never reached | `HookInstaller.timeout` in `agent-hooks/Sources/AgentHooks/` |
| Hook server | A connection is read until it closes, is quiet for 200 ms, or reaches 64 KB | `HookServer` in `agent-hooks/Sources/AgentHooks/` |
| Brain, per pass (the deliberative speed, which never blocks the reactive one) | Jev's answer within 1.5 s, one retry included; a late answer is dropped | `deadlineMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| A Moment of Jev's wait in the queue | 5 s on the device (its `ttl`), then the device skips it | `BoopDevice.reactionTTL` in `app/BoopKit/DeviceLink/BoopDevice.swift` |
| An `ended` | The link gives up on it at the `do`'s `ttl` plus 60 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §5 |
| An output's `run` | Logged if it takes over 300 ms | `outputSlowMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| `state` keepalive | Every 10 s; the device gives up on the app after 30 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §9, `kNoAppMs` in `firmware/src/app/behaviour.h` |
| Protocol message | At most 512 bytes; each text field has its own cap (`attn.project` 47 bytes, `who.thread` 50, …), so every `state` fits | [linkkit/SPEC.md](../linkkit/SPEC.md) §9 |
