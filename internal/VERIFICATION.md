# Boop: verification

Updated 2026-10-11. How we check that Boop works, including what's on its
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
`main` and every pull request: `make -C internal test` on macOS 26, and
`make -C internal fw-test` (L0 for the firmware and LinkKit's device
library). The runner's Swift (Xcode 26.6) is older than the 6.4 Boop is
written with, so code must compile on both, and a test that times the
wall clock checks it only when `CI` isn't set.

## 2. The tools

**The animation bank and the mood graph.** The bank is where the
device's designs and sounds come from: `make -C internal faces` and
sfxgen (below) build from it.
`node characters/pixel/design/boop-mood-spectrum-v2/validate.mjs` checks the
approved graph topology. `node characters/pixel/design/boop-sound-bank-v4/source/build.mjs`
builds the portable runtime and manifests; `--svg` additionally
exports all selections as SVG. Then
`node characters/pixel/design/boop-sound-bank-v4/qa/check.mjs` checks coverage,
legacy fingerprints, selection guards, timing and generated audio.
`node characters/pixel/design/boop-sound-bank-v4/qa/browser.mjs` runs browser,
cue/frame, loop and text-lane checks, then drives the pixel character in
the [Character Studio](../characters/studio/README.md), the one page that
plays every pack's characters (`python3 characters/charactergen.py` writes
its data first). Browser dependencies and
overrides are in the [package guide](../characters/pixel/design/README.md).
All scripts support `--help`; none contacts JEV, ElevenLabs or a device.
Evidence: mood design publication.
These checks are not physical audio tests or the owner's approval of the
new art.

**The separate slime design audition.** The nonshipping
[VideoG Slime Blob package](../characters/boop/design/slime-blob/README.md)
has offline build/graph/coverage/motion/SFX/link checks, seeded headless
channel traces and optional browser
checks, with commands and results in its
[validation guide](../characters/boop/design/slime-blob/VALIDATION.md).
The reference renderer powers the bundled Mac mirror; firmware integration
is separate. The opt-in host graph
is now generated from its catalog; v2 remains default. Offline checks cover
reference choreography, visual bridges and synchronized sound. Host policy
is checked by the Swift tests; none of these checks validates hardware.
The engine's `tools/trace.mjs --script scripts/idle-60s.jsonl --seed 53` emits
every 16 ms frame; its `tools/check-engine.mjs` checks golden reproduction,
retarget continuity and bounds. With the bridge and scene checks below it
also bounds what is drawn in every frame (`tools/smooth.mjs`, CONTINUITY.md
"Continuity of what is drawn"): at an event a channel's change in velocity is
at most twice what it reaches elsewhere, drawn face ratios stay in 0.75–4/3
without jumps, no prop's opacity moves more than a 16 ms slice of its ramp,
the face painter never fades the face, and the body's modes move only by
their own springs.
Run those from the slime package folder,
or run `node characters/boop/design/slime-blob/tools/check.cjs` at the root
to include them. `tools/build.cjs` also bundles the pure engine and
renderers into the preview's checked-in IIFE for direct `file://` use.
`tools/check-scenes.mjs` checks every canonical mood/state cell, all three
active variants, start contexts, completion outcomes, interruption, request
identity, alerts interrupted at any point still knocking and confirming
exactly once (`scripts/alert-interrupted.jsonl` pins it), and a ten-minute
work run. Visible prop and motion checks earn
coverage before the builder marks a cell implemented. The preview can replay
the event scripts and record the representative set to local, silent WebM
clips; this captures its canvases, not the camera or desktop. The owner
approved that representative set before the matrix was expanded.
`tools/check-bridges.mjs` walks all directed edges in all three variants,
including rest, drag and alert contexts, and checks continuous semantic faces
and bounded body motion. It earns the generated transition status. The studio's
**Directed mood bridges** review set records 13 cases for the owner's spot-check.
`tools/check-cues.mjs` checks contact-timed audio, deterministic cue identity,
sparse routine selection, one ding per request, and a mock output mixer.
It plays no sound; speaker review remains separate.
The studio's optional `characters/studio/serve.cjs --capture-dir DIR` enables local clip saving
when browser downloads are unavailable; `tools/check-server.cjs` checks
that bounded write endpoint with a temporary directory and loopback socket.

The firmware face seam keeps the existing pixel goldens byte-identical.
`render/face.h` isolates clocks, drawing, clips and cues.
Native builds both faces, and
`make -C internal sim` checks both: `internal/tools/boopctl sim --face pixel`
the existing scenarios, then `internal/tools/boopctl sim --face gel`
Boop's pack's `characters/boop/tests/scenarios-gel/` against its `golden-gel/`. The gel set covers all canonical moods and factual states,
with additional failure and neutral-finish frames, and the host lane at
the panel's size (`lane.jsonl`): the working count, a long name that
needs you, the finish's marks and the bubble in each of its fonts. `--accept` updates only
the selected face's goldens after visual inspection. `boopctl run` reads the
connected board's hello before choosing the matching simulator and scenarios.
Outputs are `/tmp/boop-sim/FACE/SCENARIO/` and `/tmp/boop-run/FACE/SCENARIO/`.

`python3 characters/boop/tools/slimegen/check-port.py --output /tmp/boop-gel-port`
builds the native trace adapter (with `BOOP_GEL_TRACE`, the one build
that keeps the recipes' `intent`) and replays every `slime-blob/scripts/*.jsonl`
against the saved traces. It compiles against the ArduinoJson that
`make -C internal fw-test` fetches, so run that first. It checks every scalar, categorical field, cue and
frame count within its tolerance. It fails on
unexpected extra fields too. `test_gel` checks arithmetic, reference clock
rounding, all expression buffer bounds, deterministic pixels, request identity,
bounded caches, alerts interrupted by listening or a link timeout signalling
exactly once, drawn face ratios and the alert's ramp moving without jumps
across every directed edge, voice lead, stale cues, return to the latest facts, projected
face anchors against the reference camera, extreme-pose buffer bounds,
drawing by coverage (a shape's ink is its area wherever it sits between
pixels, a stroke keeps its width and blends once, the body's outline is
soft with no seam inside), and
tracked-clear parity with full clearing across pose/prop changes and diagnostic
invalidation. RGB565 opacity rounding is checked against an independent scalar
reference across every channel value and all 256 opacity levels. The
screenshot unit tests check RGB565 endianness and indexed compatibility.
These are simulator/host checks; hardware throughput and speaker review are
separate checks. The temporary Phase 8 fixture has been removed.

**Slime host generation.** `node characters/boop/tools/slimegen/slimegen.mjs`
regenerates v3's moods and pacing in `characters/boop/character.json`, the offline Mac mirror resources, and the
firmware gel catalogs, vector art and sampled material mesh; add
`--check` for freshness only. Swift
`MoodPolicyTests` cover topology, pacing boundaries, evidence identity (a
decision's own pass never using up its event through a real harness pass,
and the copies-only check matching a whole-log scan on a long log), v2
option parity, pixel/gel serialization, and the newer moods' reactions
speaking in their fallback's voice. Runtime tests check the first hello
reply, a hello LinkKit turns away, and reconnect. The eval runner accepts `graph: "v3"`;
the v3 scenarios are prepared for interleaved A/B Jev runs when the owner
provides the key. Scripted tests cannot substitute for those judgments.

`node characters/boop/tools/slimegen/check-mirror.mjs` checks transient clearing,
preserved body state and the silent offline resource policy. It also runs
the generated `slime.js` on stubs (Canvas fallback, a fake display clock)
to check that a closed popover draws nothing, opening draws at once, and
120 Hz and 60 Hz refreshes both draw 60 frames a second, and it checks the
renderer's supersampling tiers.
`python3 characters/boop/tools/slimegen/check-headless.py --output /tmp/boop-slime-headless.json`
runs the real scripted headless app with an isolated HOME/state directory and
a synthetic USB peer advertising gel. It checks working, terminal, full mood
IDs and attention on real outbound snapshots. It neither flashes nor tests
a physical board. After building the native firmware, add `--native` to
connect the app to the real gel simulator through the temporary Unix socket.
That mode also checks native `hello.face`, the received full mood/attention
state, and actual device completion events.
`Boop --snapshots DIR` additionally captures working and
needs-you frames through the bundled WKWebView, plus gel Overview panes in
both themes. The renderer may need access outside the shell sandbox for
WebKit's subprocesses; it uses no runtime or Bluetooth.

**The recorded voice bank.** The voice comes from it. It's in Boop's
private pack, so only a checkout with that pack can run these two.
`node characters/boop/design/assets/boop-voice-v1/tools/check.mjs`
validates the bank itself: every recording's hash, PCM format and level,
the indexes, and its own reference selector; it's offline and never plays
sound or calls an API; the repo keeps only the robot-soft WAVs, and it
checks the textures that are there. `voicegen` turns the bank into the
voice pack and the Mac's table (below), which Boop's pack and Pixel's
each have a copy of, checked in. `VoiceTests` checks the chosen pack's
two list the same takes.
Evidence: voice asset publication,
voice bank integration.

Every tool prints its flags with `--help` (`internal/tools/boopctl
<command> --help`, `.build/debug/boopdev <command> --help`,
`.build/debug/Boop --help`). `Boop` and `boopdev` stop with their usage on
a flag they don't take, `Boop` before anything starts, so a typo can't
launch the menu-bar app or run the whole eval.

**Make targets.** The root `Makefile` has the owner's everyday targets;
`internal/Makefile` has the development ones, run from the repo root as
`make -C internal <target>`.

| Target | What it does |
| --- | --- |
| `make build` | Builds the Mac app, `boopdev` and the tests' runner in one `swift build`, then agent-hooks' `agent-hook`, MellowHarness's `mellowharness-emit` and `beacon`, and LinkKit's `linkkit-bridge` by product name. Importing a target that isn't a declared dependency fails it, so `app/` can't use `internal/` code ([internal/README.md](README.md), How it's wired) |
| `make app` | Builds the Mac app, `agent-hook` and `boopdev` (the doctor skill checks the hooks with it), not the tests, with the same import check: what `make run` needs |
| `make run` | `make app`, then runs the menu-bar app with Bluetooth. The owner's; never from an agent's shell |
| `make debug` | The same with `--debug` |
| `make dash` | The dashboard for the app `make debug` started, in a second terminal |
| `make day` | What the everyday app did in a day, and why, from the logs `make debug` leaves (`boopctl day`, below); `DATE=YYYY-MM-DD` picks the day, the newest line's by default |
| `make flash` | Builds the firmware and uploads it over USB, for whichever board is plugged in (`firmware/tools/flash.sh`); `BOOP_PORT` or `BOARD=cyd24`/`BOARD=amoled206` picks one when more than one is ([firmware/README.md](../firmware/README.md)) |
| `make eval` | Builds, then runs every eval scenario against Jev with no request budget, 3 runs each for an `always` scenario and 1 for the rest (L5): the final pass ([EVALS.md](EVALS.md) §2 counts its requests); fails without `BOOP_JEV_KEY` |
| `make clean` | Deletes `.build` and `firmware/.pio` |
| `make -C internal voice` | With Boop's pack here, rebuilds both packs' voice files (`voice/voice.bin` and `mac/takes.tsv` in `characters/boop/` and `characters/pixel/`) with voicegen (below) when the bank or voicegen changed. Without it, says the files are as checked in. Nothing else runs it: the tests read the checked-in files |
| `make -C internal test` | The Swift unit tests, the eval runner included with a scripted brain, through the XCTest shim, since there's no Xcode: `make build`, then `.build/debug/BoopTests`. `BOOP_TEST_FILTER=Golden .build/debug/BoopTests` runs only the tests whose `Class.method` name contains `Golden`. Then the own tests of agent-hooks, MellowHarness and LinkKit, in Swift Testing: `swift test --scratch-path .build/tests` in `agent-hooks/`, `mellowharness/` and `linkkit/`, each tried again up to seven times when its build fails with the "plugin for module 'TestingMacros' not found" flake |
| `make -C internal fw` | Builds the firmware for both boards (envs `cyd24` and `amoled206`, [firmware/README.md](../firmware/README.md)): Boop's app on LinkKit's device library (`linkkit/device/`), whose build fails if the kit includes anything of Boop's (`linkkit/device/tools/check_includes.py`, run by every env) |
| `make -C internal fw-test` | That the character pack's generated `moods.h` is fresh (`charactergen.py --check`), then the firmware's unit tests on the Mac (`pio test -e native`): the engine's suites in `internal/firmware/test/` and the chosen pack's in its `tests/firmware/` (Boop's `test_gel`), which `characters/charactergen.py --stage` links into `.character-build/firmware-test/` (`CHARACTER=pixel` runs them as Pixel), then LinkKit's device library's own, from its own project (`pio test -d linkkit/device -e native`: `test_turn`, `test_kit`, `test_helpers`) |
| `make -C internal sim` | Every scenario in the simulator, against the goldens (L1): the pixel face's, then the gel face's |
| `make -C internal e2e` | Builds, then runs the pipeline check (L4) |
| `make -C internal faces` | Regenerates the faces (`characters/pixel/firmware/include/faces.h`, the Pixel pack's `characters/pixel/mac/faces.json` with the popover's faces and the designs' loops for the Mac, the frames `fw-test` checks, and the designs' list in `characters/pixel/tools/facegen/design/manifest.json`) from the animation bank (`characters/pixel/design/boop-sound-bank-v4/`), whose generator it runs with node. It stops if an older mood's design doesn't come out as it was captured, then draws each design at a dozen moments in Google Chrome and fails unless facegen's own drawing matches pixel for pixel in RGB565, a blended pixel within one step (7,970 frames of 704 scenes, 7 minutes or so). Then rerun sfxgen (below) |
| `make -C internal tools` | Makes or refreshes `internal/tools/.venv` (pyserial, Pillow, Textual), with Python 3.10 or later; a venv that already works, such as a worktree's link to the main checkout's, is kept and its packages brought up to date. `internal/tools/boopctl` runs it on first run |
| `make -C internal tools-test` | The tools' own tests, with no board or camera: `boopctl`'s commands and link, the card copy (`test_card.py`), the dashboard (`test_dash.py`), the day's summary (`test_day.py`), the working day's script and report (`test_workday.py`), the pipeline check's order check and the result it still writes when it can't start (`test_e2e.py`), the webcam recorder on synthetic video, `charactergen.py`'s staging and studio rules and `packs.py` (`internal/characters/`), and each character pack's own (`characters/<pack>/tests/tools/`: Boop's checks its copy of Pixel's face). boopctl reads the takes from the chosen pack's `voice/voice.bin` |

**`internal/tools/boopctl`**, the board over USB, the simulator, the
dashboard and the day's summary. `--port PORT` picks the serial port (default `$BOOP_PORT` or
the first `/dev/cu.usbserial-*`, or `/dev/cu.usbmodem*` for the AMOLED board, [firmware/README.md](../firmware/README.md)). Without it, while a bridge runs (below),
commands go through the bridge.

| Command | What it does |
| --- | --- |
| `ping` | Prints `dbg.ping`'s vitals |
| `state` | Prints `dbg.state`, the device's own view of itself |
| `shot [--out FILE]` | Saves a screenshot of the canvas as a PNG (default `/tmp/boop-shot.png`) |
| `send '<json>'` | Sends one message as the Mac would; for a `dbg.*` request it prints the reply |
| `play ANIM\|needs\|pattern` | Makes the board do one thing the Mac can, and checks it took. An animation (`task_complete`, `reply_ready`, `starting`, `stopped`, `error`, `helper_return`, `poked` or `tap_spam`, or the older `cheer` and `wiggle`, sent as task_complete's success and poked) is a `do` played `now`, replacing whatever plays, over `--base` (idle) in `--mood` (happy) at `--vol` (1–10, 6), and `--loops N` (1–6) sends that many loops (without it the `do` has none, which plays once); `--variant N`, `--outcome success\|failure` (task_complete) and `--ctx new_task\|session\|continuation` (starting) pick its variation, and it prints the one playing; `--take ID` adds that take, from the design's voice window. `needs` holds a fake "needs you" for `--seconds` (10) from `--agent` (claude) on `--project` (boopctl) with `--more` (0), and reports whether its performance started and its ding was sent. `pattern` shows the test pattern |
| `takes [--only TEXT]` | Plays every take in the card's voice pack on its own, one after another, about two and a half hours for all 2,722 (or those whose id starts with `--only`, or whose text is it or has it as a word, any case), printing each id and text, and checks each in `audio.out`: the take, and the DAC's time within 10% of its length; then that a muted line moves the mouth silently. `--vol`, `--gap S` between takes (0.8), `--json`. For listening: `--board-volume` plays the first take at the volume the board already has; `--levels L…` plays the first take at each level, `--rounds N` times (6) |
| `sim [scenario…] [--face pixel\|gel] [--accept]` | Plays scenarios (all by default) in the simulator into `/tmp/boop-sim/<face>/<scenario>/` and compares them with the goldens (L1); `--accept` copies the pictures in |
| `run [scenario…]` | Plays scenarios on the board and diffs each screenshot against the simulator's, threshold 0 (L2), then lets the clock run again |
| `perf [--seconds N] [--motion \| --scenes [--sound]]` | Samples fps, frame time and heap once a second for N s (30), muted; `--motion` keeps the face moving (L2). `--scenes` needs the `amoled206_profile` build: it holds working, needs you, pokes, the frightened face and asleep for N s each and averages the build's one-second lines per scene against their budgets (§8); muted, or with `--sound` a line every 3 s |
| `latency [--rounds N] [--pings N] [--seed N]` | BOOT taps, touches, mood changes and pokes, N of each (20), muted, each sent at a random moment of the board's frame, timed to the frame that shows it against the budgets in §8; `--pings` (40) find the board's clock first (L2) |
| `soak [--minutes N] [--seed N] [--vol N] [--out FILE]` | Random, realistic traffic and inputs for N minutes (20), each `do` asking for its turn as the Mac or a tool would, brain reactions with ids and loops among them, at `--vol` (6; 1 is quiet; 0 is silent) (L2). `--out` is rewritten after every 5-second sample, and a soak cut short (the port lost, Ctrl-C) reports the minutes it ran and its heap so far, and fails. `--pipeline` loops the L4 fixtures through the headless app instead, with `--brain scripted\|jev` and `--out DIR` |
| `e2e [fixture…]` | The pipeline check (L4). `--brain scripted\|jev` (scripted), `--out DIR` (`/tmp/boop-e2e-out`), `--clip` to film a Claude session first (L3, with `--camera ID`) |
| `bridge [--socket PATH] [--quiet]` | Owns the serial port and shares it on a Unix socket (below) |
| `cam frame\|pattern\|clip [name]` | The webcam helpers (L3). `--seconds N` for a clip (8, at most 10), `--usb bottom\|right\|top\|left` for framing, `--camera ID` (default `$BOOP_CAMERA` or the built-in camera) |
| `dash [--state-dir DIR] [--socket PATH]` | The live dashboard |
| `day [--state-dir DIR] [--date YYYY-MM-DD] [file…]` | What Boop did in a day, and why, from debug mode's logs: the state directory's `debug.jsonl` and the earlier launches' kept beside it, oldest first (the everyday app's by default), or the files named, oldest launch first. A table by the hour (finishes: task_complete, reply_ready and older logs' cheers; chatter, the brain's reactions and their faces, alerts (a new or different request shown), mood changes, passes, dropped passes, the brain's reactions that didn't happen, pokes and minutes needing you), then the brain's passes and what the dashboard forced, each mood change and what made it, each time something needed you and how long it took to clear, and why reactions didn't happen. `--date` defaults to the newest line's day; it exits 1 when that day has no lines |
| `workday plan\|run\|report\|check` | A scripted 8-hour working day through `Boop --headless` and its brain on a compressed clock, and a report of what Boop did hour by hour: mood changes, reactions by kind of line, faces, holds, and the takes they said (L5, [EVALS.md](EVALS.md) §5). `plan` prints the day's story; `run --state DIR` (short, under `/tmp`; it's deleted first), `--seed N` (1), `--brain jev\|scripted` (jev, with `BOOP_JEV_KEY`), `--personality`, `--out DIR`, `--verbose`; `report FILE…` takes `debug.jsonl` files, `--json`; `check FILE…` holds each to the liveliness limits and exits 1 if one fails |
| `calibrate` | Touch calibration: a person taps crosses on the screen (L6). `--show` prints the stored map, `--show --clear` forgets it |
| `card [--pack FILE] [--force] [--fresh]` | Copies the voice pack (the chosen character pack's `voice/voice.bin`) onto the board's microSD card over USB with `dbg.card`, unless the board already plays that version; goes on where a cut-off copy stopped, and resyncs after a lost line. Slow: about 0.7 KB/s on the bench board (2026-09-29), hours for the whole pack, so copying it with a card reader comes first: the file goes on the card as `boop/voice.bin` |

**`.build/debug/boopdev`**, the developer CLI.

| Command | What it does |
| --- | --- |
| `replay <hooks.jsonl> [--agent claude\|codex] [--gap-ms N] [--states]` | Runs recorded hook payloads through `agent-hook`'s field picking (with `--keep-text`, as Boop installs it), the adapter and the pipeline (the core and the view) on a virtual clock, and prints each raw event, the core's decisions and the view events. `{"wait_ms":N}` and `{"advance_ms":N}` lines move the clock. `--states` prints only what goes to the device: each `state` and each rule one-shot's `do` |
| `replay <hooks.jsonl> --socket PATH [--agent …] [--gap-ms N]` | Sends each payload through the real `agent-hook --keep-text` to a running app, in real time, and times each `agent-hook` from launch to exit. `{"advance_ms":N}` moves a headless app's clock |
| `say [--feeling F] [--about TOPIC] [--face MOOD] [--kind K] [--finish success\|failure]` | Prints the takes the board has that fit, and with a face and a feeling or topic, the line `react` would say; `--kind` is `sound` by default |
| `eval [--runs N] [--only TEXT] [--always] [--budget N \| --no-budget] [--timeline] [--scenarios DIR] [--steering DIR]`, `eval --list` | The eval scenarios against Jev (L5, [EVALS.md](EVALS.md)), stopping first if they'd send more than the budget of requests (100 by default); `--list` prints each one's case, runs and requests with no key |
| `watch [FILE] [--new]` | Prints a `debug.jsonl`'s view events, passes and actions readably as it grows, waiting for it if it isn't there yet; with no file, the everyday app's. `--new` skips what's already there, though the first pass still prints the state's head in force |
| `hooks status\|install\|remove [claude\|codex] --home DIR [--hook PATH]` | Boop's hook installer, against any HOME |

**MellowHarness's example and tool** ([how it works](../mellowharness/ARCHITECTURE.md)), built by `make build` (or `swift build` in `mellowharness/`, into
`mellowharness/.build/debug/`):

| Command | What it does |
| --- | --- |
| `.build/debug/beacon` | Runs Beacon, MellowHarness's worked example, through its timeline on a virtual clock with a scripted brain, and prints every event the log wrote and every prompt the brain was sent. `--steering DIR` (default `mellowharness/Examples/Beacon/steering` in the source tree it was built from) |
| `.build/debug/beacon listen --socket PATH` | Beacon live on a socket, the scripted brain answering and the light saying each one-shot is done 2 s later; prints each line, action and pass as it happens, until Ctrl-C |
| `.build/debug/mellowharness-emit --socket PATH SOURCE KIND [key=value …] [--line TEXT]` | Sends one event to a harness's socket: `mellowharness-emit --socket /tmp/beacon.sock ci build_failed branch=main run=812`. A whole number is one, `true` and `false` yes and no, the rest strings |

**`.build/debug/Boop`**, the app.

| Way | What it does |
| --- | --- |
| `Boop [--state-dir DIR] [--link ble\|usb:SOCKET\|none] [--debug]` | The menu-bar app, with Bluetooth by default. The owner's. With a state directory other than the everyday one, it never installs or repairs the hooks |
| `Boop --headless --state-dir DIR` | The whole runtime with no UI and no Bluetooth (L4). `--link usb:SOCKET\|none` (none), `--socket PATH` (`DIR/boop.sock`), `--personality boop\|chatter` for this run, `--brain jev\|scripted` (jev, only with `BOOP_JEV_KEY`; scripted answers every pass the same way, with no network), `--name NAME` and `--nature sweet\|cheeky` for a new state directory, `--debug`. `--no-open` only logs where a tap would open a thread, instead of opening it on this Mac: `boopctl e2e`, `soak --pipeline` and `workday` pass it (`boopctl_lib/headless.py`). On its socket `{"dev":"advance","ms":N}` moves its clock, `{"dev":"tap"}` stands in for a tap on the board, `{"dev":"listen","on":true}` and `{"dev":"said","words":"…"}` stand in for push-to-talk's button and mic, and `{"dev":"presence",…}` for the Mac's lock, sleep and idle time. It keeps its transcript in `DIR/transcript/` and reads it back at launch |
| `--debug`, either way | Prints every hook, view event, action, device line and brain pass as it happens, and writes `DIR/debug.jsonl` for `boopdev watch` and `boopctl dash`; the socket then also takes the dashboard's dev lines |
| `Boop --snapshots DIR` | Renders the popover's panes, fixed WebKit gel frames, and the menu-bar icons to PNGs, light and dark, from fixtures, and fails on low contrast (L0). No runtime, no Bluetooth |

**Other tools.**

| Tool | What it does |
| --- | --- |
| `python3 characters/boop/tools/voicegen/voicegen.py [--packs DIR ...] [--card DIR] [--wav-dir DIR]` | With Boop's pack here, rebuilds the voice from the recorded bank, in about 4 s: the pack, `voice/voice.bin`, and the Mac's take table, `mac/takes.tsv`, the same in each character pack that has the voice (`--packs`; Boop's and Pixel's unless given), all checked in. `--card /Volumes/<card>` also copies the pack onto a microSD card in the Mac, as `boop/voice.bin`; `--wav-dir` writes every converted take as a WAV |
| `python3 characters/boop/tools/pixelsync/pixelsync.py [--check]` | With Boop's pack here, copies Pixel's face into it again: the firmware's pixel renderer, faces and sound effects, `mac/faces.json` and the studio's preview. `--check` copies nothing, says which of Boop's copies differ from Pixel's, and fails if any do |
| `node characters/pixel/tools/sfxgen/sfxgen.mjs [--wav-dir DIR]` | Rebuilds the sound effects, `characters/pixel/firmware/include/sfx.h`, from the animation bank's synthesiser and timelines, for the designs facegen lists, so after `make -C internal faces`; `--wav-dir` also writes every clip as a WAV |
| `internal/tools/.venv/bin/python internal/tools/fontgen/fontgen.py [--ttf-dir DIR]` | Rebuilds the device's fonts, `firmware/assets/fonts.h`, and the gel's own, `fonts_gel.h`, from Geist Mono; the `.ttf` files are in `landing/node_modules` after `npm ci` there (the landing page's repository, cloned into `landing/`), by default |
| `python3 characters/charactergen.py [--check] [PACK]`, `--stage [PACK]`, `--which` | Builds a character pack's generated files from its `character.json`: the firmware's `firmware/include/moods.h` ([CHARACTER.md](../characters/CHARACTER.md) §9), for PACK or every pack in `characters/`. Every form but `--which` also writes the [Character Studio](../characters/studio/README.md)'s `packs.js` and checks its data: the states against the board's, and that each pack's preview plays every mood and state (`--check` fails on a problem, the others warn; [CHARACTER.md](../characters/CHARACTER.md) §12). `--stage` lays the chosen pack out in `.character-build/`, as `firmware/tools/pio.sh` does before every build, and `--which` names it ([CHARACTER.md](../characters/CHARACTER.md) §2) |
| `python3 characters/packs.py add NAME URL\|sync\|list\|remove NAME` | Installs character packs that live in repositories of their own, as untracked checkouts at `characters/NAME/` ([CHARACTER.md](../characters/CHARACTER.md) §2); `sync` checks every installed pack out in a new worktree. Its tests (`internal/characters/test_packs.py`, in `make -C internal tools-test`) run against throwaway repositories |
| `internal/tools/.venv/bin/python characters/pixel/tools/facegen/facegen.py [--check]` | What `make -C internal faces` runs; without `--check` it skips the comparison with Chrome |
| `internal/tools/.venv/bin/python internal/tools/mediagen/mediagen.py [boop moods popover watch beacon]` | Makes the READMEs' GIFs and the popover's picture again, each from a real run: boop-sim's frames, `Boop --snapshots` (after `make build`), agent-hooks' `Examples/watch.sh` and `beacon listen` ([its README](tools/mediagen/README.md)) |
| `python3 internal/tools/export/export.py OUT [--commit] [--report FILE]` | Lays out the public repository in OUT, without private character packs, and fails if any of a private pack's content (or anything key-like) got through ([CHARACTER.md](../characters/CHARACTER.md) §11). `--commit` makes OUT a one-commit repository; nothing is pushed |
| `internal/tools/webcam/webcam.sh list\|record\|analyze` | The camera recorder ([its README](tools/webcam/README.md)); `boopctl cam` wraps it |
| `internal/skills/doctor/doctor.sh` | Checks from inside an agent that its hooks reach Boop; `--headless` against a throwaway app |
| `agent-hooks install\|remove\|status\|tail\|doctor` | agent-hooks' own command line, built in `agent-hooks/` with `swift build` (`agent-hooks --help`). `tail --sessions` prints every hook's event and each session's state as it changes. Give it a temporary `HOME` and `--home` together in tests, as for `boopdev hooks`: without `--keep-text` its install makes Boop's entries outdated |

**Sharing the port.** Only one process can open the serial port, so
`boopctl bridge` owns it and shares it on a Unix socket (`--socket`,
default `$BOOP_BRIDGE` or `/tmp/boop-bridge.sock`). Every line from the
board goes to every client, and each client's lines reach the board whole.
The bridge never waits on a client: one that stops reading and falls 4 MB
behind is dropped. These are LinkKit's bridge rules
([linkkit/SPEC.md](../linkkit/SPEC.md) §8), which LinkKit's own
`linkkit-bridge` keeps too. The app's USB link (`--link usb:SOCKET`) and
other `boopctl` commands can use the board at the same time.

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
| A protocol message | Sent as if it came from the Mac: a `state`, or a `do` (the scenarios send `"play":"now"`, so each replaces the last at once, as a tool's does; `turn.jsonl` plays them as the Mac does, `next` and `if_free`) |
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
  the Mac app (the core, the view, the harness, the actions, Voice, the
  memory store, the device link and the runtime) has tests; the harness and actions
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
  look, every variation is one the visual has, and the rules' one-shots
  never go out while something needs you or with an `id`, the error one
  at most every 30 s.
  `GoldenStateTests` runs every eval scenario with a scripted brain that
  answers from NOW alone and checks each of the 387 states it's sent
  against `characters/boop/tests/golden-states/`, byte for byte, so
  a change to how the prompt is built can't pass unnoticed without Jev.
  A deliberate change rewrites them:
  `BOOP_GOLDEN_RECORD=1 BOOP_TEST_FILTER=Golden .build/debug/BoopTests`
  (`BOOP_GOLDEN_OUT=DIR` keeps what a failing run built, to diff).
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
  `do`, and its `ev`s are dropped), who sent each line, ids, exactly one
  end per `do`, the give-up at its `ttl` plus 60 s and a link that drops.
- **LinkKit's device library (`pio test -d linkkit/device -e native`,
  run by `make -C internal fw-test`):** the library alone, from its own
  PlatformIO project, with a fake app and nothing of Boop's: every rule of the turn with its numbers
  (`test_turn`: `now`, `next` and `if_free`, rest and the line moving at
  its exact millisecond, 4 waiting, `ttl` 5000 and 1–60000, refuse, the
  one `ended` per id, same id again, dropping the line whole or by link,
  `dbg.reset`) and the rest of the kit (`test_kit`: 512-byte lines,
  `hello`, the host's `hello` asking for one, one too long for a line,
  its 60 s repeat, the 30 s host-gone window, `ev` routing, the app's
  words escaped, `dbg.ping`, `dbg.clock` and its thaw, `dbg.shot`,
  `dbg.state`, and the README's lamp example), and line reassembly
  across Bluetooth packets (a dropped link's part line included),
  screenshot encoding and the clock (`test_helpers`), each test naming
  its [linkkit/SPEC.md](../linkkit/SPEC.md) section.
- **Firmware (`make -C internal fw-test`):** BOOT's gestures
  (`test_gesture`); Boop's vocabulary line in and line out, its
  rules for the turn, the debug channel and inputs (`test_device`),
  including unchanged heartbeats causing no redraw while changed state,
  reconnection and leaving the test pattern still draw at once, and each
  latency counted from its event to the frame sent after it
  (`dbg.latency`, its window's p95 and the frames in flight);
  the behaviour state machine, to the millisecond, including
  `test_no_change_ever_cuts_hard` and
  `test_nothing_cuts_hard_as_it_plays_out`, which hold every change and
  every moment running out (a reaction's borrowed face, a finish's loops
  and its line, a one-shot and a poke included), in the first pack's
  moods and the new moods' flip-books, to the face never cutting hard:
  the same design at the same moment, or the design's own shut eyes
  showing; and what the agents are doing, the one-shots and the finish
  with their facts and voice window, taps in a row and what shows first
  (`test_behaviour`); the canvas and
  renderer, the bubble in the bottom lane included (`test_canvas`,
  `test_face`); what reaches the AMOLED's panel (`test_push`): every
  window a frame's push plan sends, applied through the board's own code
  to a model panel, which must show the frame drawn after every frame of
  random drawing, lane changes, test patterns and frames without the lane,
  and of a long random gel sequence through `Device` (moods, states,
  moments, pokes, needs you, bubbles, patterns, screenshots), whose frames
  must also match one surface drawn as before, and a lane the gel draws
  itself going out only when it changes; it prints what steady gel
  scenes send a frame; the animation bank's player
  against facegen's frames, every mood, state and variation, and the
  variations' host facts (`test_scene`); the voice
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
   least 60 KB minimum free heap, and no reset (uptime keeps rising). A
   frame is drawn only when the picture changes, and the designs step a
   few times a second, so `fps` follows the design rather than the board,
   and a second of a slow one draws only a few frames.
4. When a change touches the loop, inputs or drawing speed:
   `internal/tools/boopctl latency`: every press, tap, mood change and
   poke reaches the panel within its budget at the p95 and at worst, none
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
   audio errors, the plain face back with no moment or borrowed face
   (within 75 s of calm), and one `ended` for every reaction it sent
   ([linkkit/SPEC.md](../linkkit/SPEC.md) §4), short only by as many lines
   as were lost; a reaction skipped for waiting its turn too long has
   ended too, and one skipped as a name the board doesn't play fails. It
   reports how they ended, the lines the board never got (from
   `dbg.state`'s `rx`, which counts `state` and `do`), lines that came back
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

1. `boopctl bridge` owns the serial port on `/tmp/boop-e2e/usb.sock`.
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
   that none was cut short by the brain's own next request, which waits
   for the line to play (LinkKit's turn), and
   that none was skipped as a name the board doesn't play. The board
   queues the brain's reactions, so one that waited behind another's
   line, or was skipped for waiting past its 5 s, is fine. It lists the
   ones a `now` request cut short.

**Pass:** every checkpoint matches, and p95 latency from hook to board is
under 200 ms.

`internal/tools/boopctl soak --pipeline` loops the same fixtures for
`--minutes`, with a tap between rounds and a quiet minute at the end. It
fails on a board reset, a minimum-heap drift over 2 KB, audio errors, the
app exiting, or anything left on screen (not the plain face, or `attn` or
a moment still set), and reports checkpoint misses. The CH340 now and then
drops bytes over a long run, so a debug request that loses its reply is
retried once and counted as a link glitch.

### L5: brain

1. While developing, `boopdev eval --only TEXT` (with `BOOP_JEV_KEY`)
   runs the scenarios the change touches, under a budget of Jev
   requests. As the final pass, `make eval` runs every scenario, 3 times
   each for an `always` one and once for the rest, with no budget. What it reports is in [EVALS.md](EVALS.md) §2.
2. Read a sample of its passes (`boopdev watch` on the file it names)
   against the steering files (`characters/boop/steering/`): are the reactions and
   mood changes in character and never nagging, and the words and how
   long each face holds right for what happened?
3. After a change to the steering files or the questions, the working
   day ([EVALS.md](EVALS.md) §5): `boopctl workday run` twice before the
   change and twice after, same seed, and `boopctl workday report` and
   `boopctl workday check` on each.
   How often the mood changes per hour, whether a routine line changed
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
feels. A day of real use under `make debug` reads back with `make day`:
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
for the turn. A frame counts as sent when the AMOLED's push task has
finished it, when the CYD's push returns, and in the simulator when it's
taken. Each kind keeps its latest 32 samples for the p95 and the worst.
The device stamps a line when it reads it and a press when a loop pass
sees it, so `boopctl latency` adds the wait back: it finds the board's
clock with pings and times a press, a `state` and a `do` from when it
sent them. A tap counts from its release, including the 50 ms the device
waits to be sure the finger lifted.

| Path | Target | Source, and what checks it |
| --- | --- | --- |
| Agent event → pixel (the reactive loop: hook → rule → `state` or a rule's one-shot, never waiting for the brain) | < 200 ms p95 | This table; `make -C internal e2e` fails over it (L4) |
| An input or a Mac message → the frame showing it (the device's reflex loop: tap feedback, blinks, what plays when, the needs-you alert, never waiting for the Mac) | A press 80 ms p95 (100 at worst), a tap's release to its poke 80 ms, a `state` or a `do` 100 ms, on the device | `LATENCY_BUDGETS` in `internal/tools/boopctl_lib/`; `boopctl latency` on the board (L2), and `test_device`'s `test_the_redraw_cap_doesnt_delay_a_press` |
| Hook client | Single-digit ms. Connecting and writing share 50 ms for each app listening, then it gives up on it; it exits within 1 s whatever happens. It reads at most 256 KB and keeps fields of at most 200 characters | `HookSocket.send` and `agent-hook`'s `main.swift` in `agent-hooks/Sources/` |
| Hook entry timeout | 5 s in the agent's settings; never reached | `HookInstaller.timeout` in `agent-hooks/Sources/AgentHooks/` |
| Hook server | A connection is read until it closes, is quiet for 200 ms, or reaches 64 KB | `HookServer` in `agent-hooks/Sources/AgentHooks/` |
| Brain, per pass (the deliberative loop, which never blocks the reactive one) | Jev's answer within 1.5 s, one retry included; a late answer is dropped | `deadlineMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| A brain reaction's wait for its turn | 5 s on the device (its `ttl`), then the device skips it | `BoopDevice.reactionTTL` in `app/BoopKit/DeviceLink/BoopDevice.swift` |
| An `ended` | The link gives up on it at the `do`'s `ttl` plus 60 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §5 |
| An action | Logged if it takes over 300 ms | `actionSlowMs` in `mellowharness/Sources/MellowHarness/Harness.swift` |
| `state` keepalive | Every 10 s; the device gives up on the app after 30 s | [linkkit/SPEC.md](../linkkit/SPEC.md) §9, `kNoAppMs` in `firmware/src/app/behaviour.h` |
| Protocol line | At most 512 bytes; each text field has its own cap (`attn.project` 47 bytes, `who.thread` 23, …), so every `state` fits | [linkkit/SPEC.md](../linkkit/SPEC.md) §9 |
