# Boop Agent Instructions

These instructions apply to the whole repo. `CLAUDE.md` and `AGENTS.md`
are the same file: edit `CLAUDE.md`, then copy it over `AGENTS.md`.

## What Boop is

Boop is a small desk creature with a personality of its own that watches
your Claude Code and Codex agents. It grunts, huffs and says the odd word,
tells you when an agent needs your approval on the Mac, and celebrates
work that earns it. It never approves anything. A Mac app does the thinking; a
cheap ESP32 board with a screen is the body. Start with
[documentation/architecture.html](documentation/architecture.html).

## Repo layout

| Path | What it is |
| --- | --- |
| `documentation/` | [architecture.html](documentation/architecture.html), the architecture on one page (the shape, one turn through every piece, and where the three packages below join Boop), and `media/`, the READMEs' pictures (`internal/tools/mediagen/`). The code is the source of truth |
| `Package.swift` | The Swift package, at the root because its targets are in both `app/` and `internal/`. It builds into `.build/` |
| `agent-hooks/` | The hook layer, a Swift package of its own: a submodule of [Mellow-Machines-Lab/AgentHooks](https://github.com/Mellow-Machines-Lab/AgentHooks) (below, Repositories; [its README](agent-hooks/README.md), [how it works](agent-hooks/ARCHITECTURE.md)): the `agent-hook` hook client, the `agent-hooks` command line, and the `AgentHooks` library that turns hooks into events and keeps the sessions and "needs you". It depends on nothing else in the repo; Boop depends on it |
| `mellowharness/` | The brain's harness, a Swift package of its own: a submodule of [Mellow-Machines-Lab/MellowHarness](https://github.com/Mellow-Machines-Lab/MellowHarness) (below, Repositories; [its README](mellowharness/README.md), [how it works](mellowharness/ARCHITECTURE.md)): the `MellowHarness` library (events and the log, each kind's line, rules, outputs and `Choice`, the prompt, Jev and the loop that asks it), `mellowharness-emit`, and its worked example Beacon (`beacon`). It depends on nothing else in the repo; Boop's brain runs on it |
| `linkkit/` | The device link, a package of its own meant to be open-sourced ([its README](linkkit/README.md), [how it works](linkkit/ARCHITECTURE.md), [its spec](linkkit/SPEC.md)): the protocol (four JSON messages, and the queue, by which the device decides what plays when), the Swift host library `LinkKit` with its Bluetooth and socket transports, `linkkit-bridge` (the USB bridge), `linkkit-flash` (firmware onto a board over USB), and the C++ device library in `linkkit/device/` ([its README](linkkit/device/README.md)), with its own PlatformIO project for its tests, that Boop's firmware plugs into. It depends on nothing else in the repo; Boop depends on it |
| `characters/` | The character packs ([characters/CHARACTER.md](characters/CHARACTER.md), the contract a pack meets), each with what the engine reads (`character.json`, `steering/`, `mac/`, `firmware/`, `rig/`, what its moods wear and its moves on the rig the faces are moving onto, and `demo/`, scripted demos, [characters/DEMOS.md](characters/DEMOS.md)) and what makes it (`design/`, `tools/`, `tests/`, and `references/` and `review/`, what people gave to make it from and what's up for review). Each stands alone: the engine reads a pack's files from its own folder only. `pixel/`, the open default, with the animation bank ([its design guide](characters/pixel/design/README.md)), the recorded voice as built files (`voice/voice.bin`, `mac/takes.tsv`), and `tools/borrowed.json`, the table that lends its 13 drawn moods' art and takes to the other universal moods; and `boop/`, Boop's own and the default: its prompts, gel slime, evals and goldens, the Mac's mirror of its gel board (`mac/mirror/`), its own copies of Pixel's face and of the voice, and the voice's recordings. Both are public. Also `studio/`, the Character Studio, one page for everything a pack makes its character: its personality, moods, what sets its behaviour off and who decides, what its brain reads, animations, words, evals and demos ([its README](characters/studio/README.md)), and `charactergen.py`, which builds a pack's generated files, the studio's data, and stages the chosen pack for the builds |
| `app/` | The Mac side that ships: the menu-bar app (`Boop`, with its placeholder icon, `app/Boop/AppIcon.icns`, and `app/tools/bundle.sh`, which builds it into a signed `Boop.app`, `make bundle`) and the `BoopKit` library, Boop's own code on the three packages, and `CBoopVersion`, which compiles in `VERSION`, the one place the version is written (the firmware's build reads it too) |
| `firmware/` | PlatformIO firmware for the two boards ([its README](firmware/README.md): the boards, building, flashing, quirks): Boop's app on LinkKit's device library, with its generated assets and build scripts, and the boards with no hardware: `src/board/hosted/`, the loop the simulator and the Mac's mirror run, and `src/board/mirror/`, the Mac's mirror of the board, which `tools/mirror.sh` builds to WebAssembly into a pack's `mac/mirror/` |
| `simulator/` | The board with no board, for development, tests and demos ([its README](simulator/README.md)): `core/`, the firmware's portable code and LinkKit's device library as a simulated board on the firmware's hosted board, built for the Mac as `firmware/.pio/build/native/program` (PlatformIO's `native` env) and for a browser as WebAssembly; `web/`, the page that is its screen, finger, speaker and card (`<boop-simulator>`, one script to embed), which also plays a pack's recorded demo, with the local server that gives it a USB cable; `tools/`, which record a demo and cut its voice. Neither ships in the app or the firmware |
| `internal/` | Everything that doesn't ship ([its README](internal/README.md)), with [VERIFICATION.md](internal/VERIFICATION.md), how everything is checked, [EVALS.md](internal/EVALS.md), the brain's eval scenarios, and [RELEASING.md](internal/RELEASING.md), how a version goes out: `boopdev` and its library, Boop's Swift tests and eval scenarios, the sources of `Boop --headless` and `--snapshots`, and the firmware's unit tests and the simulator's scenarios (env `native`), and `sessions/`, the projects a real agent plays a demo in ([internal/sessions/README.md](internal/sessions/README.md)) |
| `internal/tools/` | The dev tools: `boopctl` (the board over USB, the simulator, the logs, references people give), `fluid/` (how fluid the transitions are), `appicon` (the app's placeholder icon), `fontgen`, `mediagen`, `session/` and `webcam/` ([internal/README.md](internal/README.md)). The faces' and voice's generators live in their packs' `tools/` |
| `internal/skills/` | `doctor` (hook self-check) and `webcam-verify`, symlinked for Claude and Codex |
| `plan/` | What isn't built yet: [TODO.md](plan/TODO.md), what's next, worked one at a time and ticked in the commit that finishes it; [product-ideas.md](plan/product-ideas.md), the running list of what Boop builds next and what it won't; [updated-behavior.md](plan/updated-behavior.md), the plan the overnight work built; [character-engine.md](plan/character-engine.md), the plan for one rig and mixer for both faces; [glance-and-wait.md](plan/glance-and-wait.md), the plan for requests that last, opening the right window, and the working and idle tiers; [work-stream.md](plan/work-stream.md), the plan for agents' calls as words that fall past the slime and hit it; and [simplify-behavior.md](plan/simplify-behavior.md), the plan to comb the behaviour down to one owner for each moment and one word for each idea |
| `landing/` | The Next.js landing page, a repository of its own: clone it here, and this one ignores it |
| `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `SECURITY.md` | MIT for everything here (each package has its own copy), the fonts and libraries the firmware carries, how to build and test, how to report a vulnerability and what's in scope |
| `.github/workflows/` | CI: the Swift tests, the Python tests that need only the standard library, the firmware's unit tests, and both boards' firmware ([internal/VERIFICATION.md](internal/VERIFICATION.md) §1) |

Code that doesn't ship goes in `internal/`: tests, evals, dev tools,
skills and the simulator. What ships (`BoopKit`, `Boop`, the three
packages agent-hooks, mellowharness and linkkit, LinkKit's device library and
the firmware) never depends on internal code, and `make -C internal build` fails if a
Swift target imports one it doesn't declare. The packages depend on
nothing of Boop's and nothing outside their folders; the device library's build fails if it
includes a header that isn't its own (`linkkit/device/tools/check_includes.py`).
Their own tests live in each package. The one overlap is `Boop --headless` and
`Boop --snapshots`, flags of the shipped app whose sources are in
`internal/app/Boop/`.

Delete code that nothing uses; git keeps it.

## Commands

The everyday entry points are in [README.md](README.md), which stays a
short overview. The root `Makefile` has only what the owner runs: `dev`,
`bundle`, `demo`, `flash`, `eval` and `clean`. Keep it that short: a new
target for agents, tests or tools goes in `internal/Makefile`, which has
`build`, `app`, `simulator`, `check`, `test`, `tools-test`, `fw`,
`fw-test`, `sim`, `sim-test`, `mirror`, `e2e`, `faces`, `tools` and
`eval-pixel`; run them from the repo root as `make -C internal <target>`.
`boopctl` and the rest of `internal/tools/` are agent tooling the owner
needn't learn. Every make target and tool is in
[internal/VERIFICATION.md](internal/VERIFICATION.md) §2, and each CLI prints its
flags with `--help`. `make dev` uses Bluetooth, so it's the owner's. For
agents:

```sh
make -C internal build                                # Mac app, boopdev, the tests' runner, agent-hook, mellowharness-emit, beacon, linkkit-bridge and linkkit-flash (make -C internal test builds it too)
make -C internal check                                # every check that needs no board, camera or Jev key
make -C internal test                                 # Swift unit tests: Boop's, then swift test in agent-hooks/, mellowharness/ and linkkit/
.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth, printing everything
.build/debug/Boop --snapshots DIR                     # the popover's panes, onboarding's acts and the menu-bar icons as PNGs, then exits
```

## Environment notes

- There's no Xcode, so XCTest is missing and `swift test` runs nothing of
  Boop's. `make -C internal test` runs `make -C internal build`, which generates the
  XCTest shim's runner and builds the package in one `swift build`, then
  runs `.build/debug/BoopTests`. Then it runs the three packages' own
  tests, which use Swift Testing, as
  `swift test --no-parallel --scratch-path .build/tests` in `agent-hooks/`,
  `mellowharness/` and `linkkit/` in turn, retrying the "TestingMacros"
  toolchain flake ([internal/VERIFICATION.md](internal/VERIFICATION.md) §2). LinkKit's device library has no
  Swift: its own tests (`linkkit/device/test/`) run after the firmware's
  in `make -C internal fw-test`.
- Command Line Tools lack some Swift macro plugins, so SwiftUI's `@State`
  doesn't compile. Write `@ViewState` (the alias in
  `app/Boop/Views/ViewState.swift`).
- If a SwiftPM build fails before compiling, with module-cache errors under
  `~/.cache/clang` or `~/Library/org.swift.swiftpm`, rerun it outside the
  sandbox before investigating the source.
- `boopdev` and `Boop --headless` read Jev's API key only from
  `BOOP_JEV_KEY`, so Jev runs (`make eval`) need the owner to supply it.
  `Boop --headless --brain scripted` runs the whole pipeline without it. Never read the
  Keychain from an agent shell, and don't go looking for the key.
- The firmware's C++ style is `firmware/.clang-format` (Google's, 120
  columns). Format new and rewritten files with
  `/Library/Developer/CommandLineTools/usr/bin/clang-format -i`; older
  files follow it closely and are reformatted only where edited.
- Call PlatformIO through `firmware/tools/pio.sh` (the make targets
  do), which keeps its packages in the main checkout's
  `firmware/.platformio-core`, one copy every worktree shares. It uses
  the `pio` on `PATH` (here `/opt/homebrew/bin/pio`), or installs one into
  that folder's `venv` on its first run, with Python 3.10 or
  later (the ESP32 platform refuses 3.9). The board shows up as
  `/dev/cu.usbserial-*` (the AMOLED board, env `amoled206`, as
  `/dev/cu.usbmodem*`; [firmware/README.md](firmware/README.md)), and the serial port needs no
  special permissions.
- The simulator's page and the Mac's mirror of the board need Emscripten
  (`brew install emscripten`), which builds the firmware's portable code
  to WebAssembly (`simulator/web/build.sh` and `firmware/tools/mirror.sh`,
  both on `firmware/tools/wasm.sh`), and Node for their tests. The mirror is checked in, so nothing else in
  the repo needs Emscripten.
- The build's own scripts run on the Mac's `/usr/bin/python3` (3.9);
  keep them to it. System Python has no pyserial, Pillow or Textual. The
  tools use `internal/tools/.venv`, which `internal/tools/boopctl` makes
  on its first run (`make -C internal tools` refreshes it), and which
  needs Python 3.10 or later.
- Other sessions share the board. Everything that talks to it over USB,
  `make flash` and any `pio.sh … -t upload` included, takes its lock and
  waits for a session holding it; `internal/tools/boopctl board` says who
  has it and whose firmware is on it. Keep it through a flash, a test and
  a flash back with `internal/tools/boopctl board hold -- CMD`
  ([internal/VERIFICATION.md](internal/VERIFICATION.md) §2).
- A Unix socket's path has room for 103 bytes, so give `Boop --headless`
  a short state directory (under `/tmp`) or a short `--socket`.
- Webcam recording works only from a terminal the Claude app opens (its
  Terminal panel). macOS gives camera permission to the app that launched
  the process, and an agent's own shell has none.

## Repositories

Boop is spread over three repositories, all public, and the
organisation has a fourth for its profile. You work in the first three
from here:

| Repository | Visibility | Here at | What goes in it |
| --- | --- | --- | --- |
| Mellow-Machines-Lab/buddygotchi | Public | the root | Boop's engine: the Mac app, the firmware, LinkKit, the character packs (Boop's and Pixel's), the studio and the tools, the internal tests and docs |
| Mellow-Machines-Lab/AgentHooks | Public | `agent-hooks/`, a submodule | Reading coding agents' hooks: events, sessions, "needs you", the installer. Nothing of Boop |
| Mellow-Machines-Lab/MellowHarness | Public | `mellowharness/`, a submodule | The generic multiple-choice brain: the log, lines, rules, outputs, the prompt, brains. Nothing of Boop |
| Mellow-Machines-Lab/.github | Public | not here: clone it beside this one | The organisation's profile README (`profile/README.md`), shown on github.com/Mellow-Machines-Lab, and later the community files every repository shares |

**What goes where.**
- Anything another app could use about agents' hooks goes in
  AgentHooks, and anything about a generic personality brain in
  MellowHarness. Neither names Boop or the other.
- Boop's own behaviour, the device protocol (`linkkit/`) and anything
  every character shares stay in buddygotchi.
- Anything that's the slime's own, its words, art, sounds and evals,
  goes in Boop's pack, `characters/boop/`, and so do the voice's
  recordings. Pixel's go in `characters/pixel/`, and so does the built
  voice, which Boop's pack uses with Pixel's face
  ([CHARACTER.md](characters/CHARACTER.md) §6).
- A change that spans repositories lands package first, then
  buddygotchi's side, so buddygotchi never depends on something that
  isn't pushed.
- Every repository squash-merges, so each change is one commit.
- Only the owner pushes, tags or force-pushes, or says to.

`agent-hooks/` and `mellowharness/` are git submodules: each is a
clone of its own repository, and this one records which commit it's on.
Contributors work in those repositories directly; this one only bumps.

**Setting up.** A fresh clone needs `git clone --recurse-submodules`, and
**every new worktree**, the app's included, starts with both folders
empty: run this in it before anything else, or the build can't find
the packages:

```sh
git submodule update --init
```

To push from a submodule (the owner's, when asked), point it at the SSH
alias that can write to the organisation:

```sh
git -C agent-hooks remote set-url --push origin git@github-fdsa:Mellow-Machines-Lab/AgentHooks.git
git -C mellowharness remote set-url --push origin git@github-fdsa:Mellow-Machines-Lab/MellowHarness.git
```

**Changing a package.** A submodule is checked out on no branch, and a
commit made there is easy to lose. So:

1. In the submodule, start a branch from its `main`:
   `git -C agent-hooks switch -c <branch> origin/main`.
2. Commit there, with the package's own docs (the table below) in the
   same commit.
3. Push the branch and open a pull request in the package's
   repository; it's squash-merged there. Only the owner pushes, or says
   to.
4. Bump this repository to the merged commit (below), in the same commit
   as Boop's side of the change.

Until the package's change is merged, this repository may point at the
branch's commit while you work, but never commit a pointer to a commit
that isn't pushed: `git push --recurse-submodules=check` refuses to.

**Bumping.** To take a package's newer commits, contributors' included:

```sh
git -C agent-hooks fetch && git -C agent-hooks checkout origin/main
git add agent-hooks && git commit
```

The message says what came in: `agent-hooks: bump to <short sha>`, then
each new commit's subject (`git -C agent-hooks log --oneline OLD..NEW`).

**Releasing** is separate from pushing, and only when the owner asks: tag
any commit on the package's `main` as a version, and push the tag. Apps
using the package (`from: "1.0.0"`) see it then.

```sh
git -C agent-hooks tag 1.1.0 <commit> && git -C agent-hooks push origin 1.1.0
```

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `.build/debug/linkkit-bridge` plus
  `Boop --headless --state-dir DIR --link usb:$TMPDIR/linkkit-bridge.sock`
  ([internal/VERIFICATION.md](internal/VERIFICATION.md) L4). Ask the owner to run
  `make dev` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories, and give
  the installers `--home` too: `NSHomeDirectory()` ignores `HOME`.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless the owner asks** (below).

## Words

One concept, one word, in code, comments and docs. Wire and on-disk keys
keep their names.

| Word | Means | Not |
| --- | --- | --- |
| reaction | What plays on the device: the brain's, a rule's, or the board's own (a tap) | one-shot, moment, request |
| sign | A short caption the buddy holds up while a reaction plays, often your own words (`Signs`, a pack's `signs.md`, the `do`'s `sign`) | banner, label |
| reading | What Boop takes from your prompt, or an agent's last message, in its place: its kind, tone, length, which buddies' names you said, and a few of its words (`PromptReading`, `MessageReading`) | summary, label (for the whole) |
| the queue | LinkKit's rule for what plays when (linkkit/SPEC.md §4). A turn is only ever an agent's | the turn |
| message | One JSON line on the wire (`hello`, `state`, `do`, `ev`) | line |
| line | What the brain reads for one event (MellowHarness's `Line`) | |
| take | One recorded clip of the voice; a `say` is up to two | line |
| step | One row of a demo script or an eval scenario | line |
| output | What the brain's answers drive (MellowHarness's `Output`; Boop's `mood` and `react`) | action |
| transcript | Boop's event files: MellowHarness's log, kept as files (`app/BoopKit/Harness/Transcript.swift`) | the log |
| activity | What an agent is doing: working, idle, a tool | state (the `state` message keeps its name) |
| the prompt | What Jev reads on each pass | the state |
| speeds | Reflex, reactive and deliberative (documentation/architecture.html) | loops (`loops` is a repeat count) |
| the voice file | `voice/voice.bin`, on the board's card | voice pack |
| needs you | An agent waiting on you (the wire's `attn`; the face's knock is a sound) | attn, alert |
| the needs-you screen | What the board shows while an agent needs you: who's asking, in amber, until you answer or hold a finger on it | sign (that's a reaction's caption) |
| buddy | One board running one character pack, with its own name, place, mood, face and agents (`Buddy`); several share one transcript and brain, each a voice of MellowHarness's | body, creature (for one of several) |
| diary | Boop's line a day about the day before (`DiaryOutput`, the memory store's `diary.md`) | journal, log |
| gesture | What you do to the board that it reacts to itself (BOOT's hand-off, a stroke, a shake, face down…), the `gesture` state's variations and the `gesture` event | touch, motion (for one) |
| tag | One thing true now that a design may need (`state.when`: the part of the day, a holiday, a milestone day; and the board's own `busy`, `frantic`); a design that needs tags is an occasion | flag, label |
| tier | How long the agents have worked (their working stretch) or rested: `tier1` from 30 s to `tier5` from 10 minutes, a tag (`Occasions.tiers`) | stage (that's growth's) |
| pastime | What the gel does to pass the time in a look: a rig clip and its drawing in time with it, dealt by tier or wait (`render/gel/pastimes.h`); the kit is what the tiers put out round it | gag (the engine's), bit |
| personality, nature | The pack's personality file, and the person's sweet or cheeky choice laid over it (characters/CHARACTER.md §7) | |

## Architecture rules

The full picture, with how Boop sits on its three packages (agent-hooks,
MellowHarness, LinkKit), is
[documentation/architecture.html](documentation/architecture.html). The rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Outputs (`mood`, `react`) carry out effects and check their own rules.
- **Everything goes through the transcript.** Hooks, pokes, heartbeats
  and everything the rules and outputs do are raw events in one shape; the view folds them into
  what the brain hears (`app/BoopKit/Core/TranscriptView.swift`).
  Anything else is a log line.
- **The packages stay apart.** agent-hooks, MellowHarness and LinkKit know
  nothing of Boop or of each other.
  Boop translates between them in a few places (documentation/architecture.html,
  Where the pieces join), and anything Boop-specific stays in `app/` or `firmware/`.
- **The harness is generic.** MellowHarness takes events, asks every output's
  questions in one request and hands each output its own answers. It
  never reads an event's facts, picks what Boop says or talks to the
  device.
- **Only Voice knows what Boop can say.** Only the memory store reads and writes
  the memory files. Only LinkKit knows Bluetooth or USB: on the Mac its
  `DeviceLink` and transports, with Boop's vocabulary on them in
  `app/BoopKit/DeviceLink/BoopDevice.swift`; on the board its device
  library, which `firmware/src/main.cpp` feeds the serial port's messages.
- **The brain is never on the screen's path.** Rules keep the screen true
  at once (the look, "needs you", the tap's poke, the rules' reactions).
  Every reaction, a finished turn's included, is the brain's, later or
  not at all.
- **The brain is Jev: multiple choice only.** It answers questions about
  the prompt, in plain text; there's no free text. Keep questions few, with
  options that say what they're not.
- **The steering files are read-only at runtime.** `characters/boop/steering/` is
  the single source, and the app bundles it at build time
  (`Package.swift` copies it into the app's resources).
- **No code, commands, tool output, file contents or agent transcripts go
  to the brain.** Of your prompt and of the agent's last message only
  the reading goes, each with up to three short phrases of it; the only
  other words are what you say to Boop on push-to-talk, cut short. Both
  texts stay on the Mac: `app/BoopKit/Prompt/` scrubs each, reads it
  (with Apple Intelligence on macOS 26 while it's on, else by counting
  only) and passes on only its reading; nothing keeps them.
- **"Needs you" and the screen priority are plain rules in the core.**
- **The device renders, reports, and decides when a reaction plays**
  (LinkKit's queue), never what Boop does: the Mac sends each thing to
  play at once and never times it. It receives the same messages over
  Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.
- **The Mac's face is the board's firmware.** The popover and onboarding
  show the gel through the pack's mirror of the board
  (`characters/boop/mac/mirror/board.js`), the firmware built to
  WebAssembly and checked in: a change to what the gel board draws
  rebuilds it (`firmware/tools/mirror.sh`) in the same commit, and
  `make -C internal mirror` fails until it does. It's fed what the board
  gets and never answers.

## Docs stay in sync

The code is the source of truth. The docs that remain cover what no single
file shows: how the pieces join, each package's contract and tour, the
character pack contract, the boards, and how everything is checked. A
change that alters what one of them says updates it in the same commit.

**Start from the latest code.** In a worktree, check that
`git log --oneline HEAD..main` prints nothing before you compare or edit
anything: a worktree made from `origin/main` can be far behind an
unpushed local `main`.

| When you change | Update |
| --- | --- |
| `agent-hooks/` (its sources, tests, fixtures and command line), in its own commit there | `agent-hooks/ARCHITECTURE.md`, `README.md` |
| `mellowharness/` (its sources, tests, `mellowharness-emit` and Beacon), in its own commit there | `mellowharness/ARCHITECTURE.md`, `README.md` |
| `linkkit/` (the device library included) | `linkkit/SPEC.md`, `ARCHITECTURE.md`, `README.md`, `linkkit/device/README.md` |
| How the pieces join, structure or boundaries, which package products Boop takes | `documentation/architecture.html` |
| What a character pack holds or how the engine loads one (`characters/`, `app/BoopKit/Character/`, `internal/app/BoopDevKit/PackCheck.swift`, `characters/charactergen.py` and its staging) | `characters/CHARACTER.md` |
| A demo script's steps or how one plays (`app/BoopKit/Demo/`, `make demo`, `simulator/tools/demo.sh`, `internal/tools/session/`) | `characters/DEMOS.md`, `internal/sessions/README.md` |
| The boards, `firmware/src/board/`, `firmware/platformio.ini`, flashing | `firmware/README.md` |
| `simulator/` (the core, the page, the server and its cable, recording and playing demos, its tests) | `simulator/README.md`, `internal/VERIFICATION.md` |
| `Makefile`, `internal/Makefile`, `internal/tools/`, `internal/app/BoopDev/`, `internal/skills/`, the simulator, tests, `.github/workflows/`, a budget | `internal/VERIFICATION.md`, this file, `README.md`, `CONTRIBUTING.md` |
| `internal/app/BoopDevKit/Eval/`, `internal/app/Evals/`, `internal/tools/boopctl_lib/workday.py` | `internal/EVALS.md` |
| `Package.swift`, a package's `Package.swift`, what goes in `internal/` | `internal/README.md`, `documentation/architecture.html`, this file |
| `characters/studio/`, a pack's `studio` entry or `studio/` adapter | `characters/studio/README.md`, `characters/CHARACTER.md` §12 |
| The gel slime: its design (`characters/boop/design/slime-blob/`), `characters/boop/tools/slimegen/`, its engine (`characters/boop/firmware/src/render/gel/`) or `test_gel` | The slime package's `CONTINUITY.md` and `VALIDATION.md`, slimegen's `README.md` |

**Rules that keep them from drifting:**

- **Say each fact once.** A number, name or rule lives in one place, the
  code where it can. When you change one, grep the docs above, this
  file and code comments for the old value or name, and fix every hit.
- **Comments explain, they don't cite.** Say the rule where the code
  keeps it. Don't point comments at docs that might move.
- **Examples are real.** JSON, command lines and file layouts in a doc
  come from a test fixture or actual output. When the shape changes, the
  example changes with it.
- **Commands run as written.** Every command in this file, `README.md`,
  `CONTRIBUTING.md`, `firmware/README.md`, `internal/VERIFICATION.md`,
  the packages' READMEs and `ARCHITECTURE.md`, and the skills exists
  with those arguments. When you add, rename or remove a make target, a
  `boopctl` or `boopdev` subcommand, a flag or a path, grep the docs for
  it in the same commit.
- **Pin rules in tests.** When you implement or change a rule with a number
  in it (a timing, cap, threshold or priority), add or update a test that
  checks it and says which rule it pins.
- **Removed code takes its docs with it.** Delete any doc, skill, checklist
  or code comment that describes code that's gone.
- **Dates move with the work.** Bump the "Updated" date on every doc you
  touched. Tell the owner about drift you find but don't fix.
- **Before you commit,** go through `git diff --stat` against the table
  above, check that `cmp CLAUDE.md AGENTS.md` is silent, and check that
  new or edited links resolve.

## Checking your work

Check changes with the loop in [internal/VERIFICATION.md](internal/VERIFICATION.md)
§1, and report only checks that actually ran and passed. Say what you
checked, and what it showed, in the commit message or pull request; raw
logs, screenshots and footage stay local, out of git.

Before trusting anything that depends on hooks, run the `doctor` skill
(`internal/skills/doctor/doctor.sh`). It checks that this agent's hooks
reach Boop; `--headless` checks against a throwaway headless app instead
of the owner's.

**Webcam.** Webcam verification is opt-in. Use the `webcam-verify` skill
only when the owner asks for it and confirms the board is set up for that
session. Clips are bounded and video only, and raw footage stays local and
out of git.
