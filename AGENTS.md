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
| `linkkit/` | The device link, a package of its own meant to be open-sourced ([its README](linkkit/README.md), [how it works](linkkit/ARCHITECTURE.md), [its spec](linkkit/SPEC.md)): the protocol (four JSON messages, and the turn, by which the device decides what plays when), the Swift host library `LinkKit` with its Bluetooth and socket transports, `linkkit-bridge` (the USB bridge), and the C++ device library in `linkkit/device/` ([its README](linkkit/device/README.md)), with its own PlatformIO project for its tests, that Boop's firmware plugs into. It depends on nothing else in the repo; Boop depends on it |
| `characters/` | The character packs ([characters/CHARACTER.md](characters/CHARACTER.md), the contract a pack meets), each with what the engine reads (`character.json`, `steering/`, `mac/`, `firmware/`, and `demo/`, a scripted demo) and what makes it (`design/`, `tools/`, `tests/`): `pixel/`, the open default, with the animation bank and the mood graph it was drawn from ([its design guide](characters/pixel/design/README.md)); and `boop/`, Boop's own, which builds on Pixel and is private: its prompts, voice bank, gel slime, evals and goldens. It isn't tracked here: it's installed from a private repository of its own with `characters/packs.py` (below, Repositories). Also `studio/`, the Character Studio, one page for any pack's moods, states and preview ([its README](characters/studio/README.md)), `charactergen.py`, which builds a pack's generated files, the studio's data, and stages the chosen pack for the builds, and `packs.py`, which installs packs that live in repositories of their own |
| `app/` | The Mac side that ships: the menu-bar app (`Boop`) and the `BoopKit` library, Boop's own code on the three packages |
| `firmware/` | PlatformIO firmware for the two boards ([its README](firmware/README.md): the boards, building, flashing, quirks): Boop's app on LinkKit's device library, with its generated assets and build scripts |
| `simulator/` | The board with no board, for development, tests and demos ([its README](simulator/README.md)): `core/`, the firmware's portable code and LinkKit's device library as a simulated board, built for the Mac as `boop-sim` (PlatformIO's `native` env) and for a browser as WebAssembly; `web/`, the page that is its screen, finger, speaker and card (`<boop-simulator>`, one script to embed), which also plays a pack's recorded demo, with the local server that gives it a USB cable; `tools/`, which record a demo and cut its voice. Neither ships in the app or the firmware |
| `internal/` | Everything that doesn't ship ([its README](internal/README.md)), with [VERIFICATION.md](internal/VERIFICATION.md), how everything is checked, and [EVALS.md](internal/EVALS.md), the brain's eval scenarios: `boopdev` and its library, Boop's Swift tests and eval scenarios, the sources of `Boop --headless` and `--snapshots`, and the firmware's unit tests and the simulator's scenarios (env `native`) |
| `internal/tools/` | `boopctl` (device tool, and `boopctl workday`, a scripted working day through the brain), `fontgen` (the device's fonts), `mediagen` (the READMEs' GIFs, from real runs), `export` (lays out the public repository without private character packs, and checks it for leaks), `webcam/` (opt-in recorder). The faces' and voice's generators live in their packs: `characters/pixel/tools/` (`facegen`, the device's faces, and `sfxgen`, their sounds, from the animation bank) and `characters/boop/tools/` (`voicegen`, the voice; `slimegen`, the v3 mood graph, the Mac's slime mirror and the gel face's assets, from the slime design; `gel-trace`) |
| `internal/skills/` | `doctor` (hook self-check) and `webcam-verify`, symlinked for Claude and Codex |
| `landing/` | The Next.js landing page, a repository of its own: clone it here, and this one ignores it |
| `LICENSE`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md` | MIT for everything here (each package has its own copy), the fonts and libraries the firmware carries, how to build and test |
| `.github/workflows/` | CI: the Swift tests and the firmware's unit tests ([internal/VERIFICATION.md](internal/VERIFICATION.md) §1) |

Code that doesn't ship goes in `internal/`: tests, evals, dev tools,
skills and the simulator. What ships (`BoopKit`, `Boop`, the three
packages agent-hooks, mellowharness and linkkit, LinkKit's device library and
the firmware) never depends on internal code, and `make build` fails if a
Swift target imports one it doesn't declare. The packages depend on
nothing of Boop's and nothing outside their folders; the device library's build fails if it
includes a header that isn't its own (`linkkit/device/tools/check_includes.py`).
Their own tests live in each package. The one overlap is `Boop --headless` and
`Boop --snapshots`, flags of the shipped app whose sources are in
`internal/app/Boop/`.

Delete code that nothing uses; git keeps it.

## Commands

The everyday entry points are in [README.md](README.md), which stays a
short overview. The root `Makefile` has only what the owner uses: `build`,
`app`, `run`, `debug`, `dash`, `day`, `simulator`, `flash`, `eval` and `clean`. The development targets
(`test`, `tools-test`, `voice`, `fw`, `fw-test`, `sim`, `sim-test`, `demo`, `e2e`, `faces`, `tools`)
are in `internal/Makefile`; run them from the repo root as
`make -C internal <target>`. Every make target and tool is in
[internal/VERIFICATION.md](internal/VERIFICATION.md) §2, and each CLI prints its
flags with `--help`. `make run` and `make debug` use Bluetooth, so they're
the owner's. For agents:

```sh
make build                                            # Mac app, boopdev, the tests' runner, agent-hook, mellowharness-emit, beacon and linkkit-bridge (make -C internal test and make eval build too)
make -C internal test                                 # Swift unit tests: Boop's, then swift test in agent-hooks/, mellowharness/ and linkkit/
.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth, printing everything
.build/debug/Boop --snapshots DIR                     # the popover's panes and the menu-bar icons as PNGs, then exits
```

## Environment notes

- There's no Xcode, so XCTest is missing and `swift test` runs nothing of
  Boop's. `make -C internal test` runs `make build`, which generates the
  XCTest shim's runner and builds the package in one `swift build`, then
  runs `.build/debug/BoopTests`. Then it runs the three packages' own
  tests, which use Swift Testing, as
  `swift test --scratch-path .build/tests` in `agent-hooks/`,
  `mellowharness/` and `linkkit/` in turn.
  That build now and then fails with "plugin for module 'TestingMacros'
  not found", a toolchain flake, even from a clean build folder; it
  passes when run again, so the target tries that failure alone again, up
  to seven times (eight tries in all). LinkKit's device library has no
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
  do), which keeps its packages in `firmware/.platformio-core`. It uses
  the `pio` on `PATH` (here `/opt/homebrew/bin/pio`), or installs one into
  `firmware/.platformio-core/venv` on its first run, with Python 3.10 or
  later (the ESP32 platform refuses 3.9). The board shows up as
  `/dev/cu.usbserial-*` (the AMOLED board, env `amoled206`, as
  `/dev/cu.usbmodem*`; [firmware/README.md](firmware/README.md)), and the serial port needs no
  special permissions.
- The simulator's page needs Emscripten (`brew install emscripten`), which
  builds the firmware's portable code to WebAssembly
  (`simulator/web/build.sh`), and Node for its tests. Nothing else in the
  repo needs either.
- The build's own scripts run on the Mac's `/usr/bin/python3` (3.9);
  keep them to it. System Python has no pyserial, Pillow or Textual. The
  tools use `internal/tools/.venv`, which `internal/tools/boopctl` makes
  on its first run (`make -C internal tools` refreshes it), and which
  needs Python 3.10 or later.
- A Unix socket's path has room for 103 bytes, so give `Boop --headless`
  a short state directory (under `/tmp`) or a short `--socket`.
- Webcam recording works only from a terminal the Claude app opens (its
  Terminal panel). macOS gives camera permission to the app that launched
  the process, and an agent's own shell has none.

## Repositories

Boop is spread over four repositories, and the organisation has a fifth
for its profile. You work in the first four from here:

| Repository | Visibility | Here at | What goes in it |
| --- | --- | --- | --- |
| Mellow-Machines-Lab/buddygotchi | Public | the root | Boop's engine: the Mac app, the firmware, LinkKit, the open Pixel pack, the studio and the tools, the internal tests and docs |
| Mellow-Machines-Lab/AgentHooks | Public | `agent-hooks/`, a submodule | Reading coding agents' hooks: events, sessions, "needs you", the installer. Nothing of Boop |
| Mellow-Machines-Lab/MellowHarness | Public | `mellowharness/`, a submodule | The generic multiple-choice brain: the log, lines, rules, outputs, the prompt, brains. Nothing of Boop |
| Boop's character pack | Private | `characters/boop/`, an installed pack | Boop's slime: its prompts, voice bank, gel face, design, evals, goldens and their tools |
| Mellow-Machines-Lab/.github | Public | not here: clone it beside this one | The organisation's profile README (`profile/README.md`), shown on github.com/Mellow-Machines-Lab, and later the community files every repository shares |

**What goes where.**
- Anything another app could use about agents' hooks goes in
  AgentHooks, and anything about a generic personality brain in
  MellowHarness. Neither names Boop or the other.
- Boop's own behaviour, the device protocol (`linkkit/`) and anything
  every character shares stay in buddygotchi.
- Anything that's the slime's own, its words, art, sounds, voice and
  evals, goes in Boop's pack, never in buddygotchi, which is public.
  Pixel's go in `characters/pixel/`, which is public by design.
- A change that spans repositories lands package or pack first, then
  buddygotchi's side, so buddygotchi never depends on something that
  isn't pushed.
- Every repository squash-merges, so each change is one commit.
- Only the owner pushes, tags or force-pushes, or says to. Nothing in a
  public repository names the private one's address.

`agent-hooks/` and `mellowharness/` are git submodules: each is a
clone of its own repository, and this one records which commit it's on.
Contributors work in those repositories directly; this one only bumps.
Boop's pack is a checkout this repository never tracks
(`characters/packs.py`, [CHARACTER.md](characters/CHARACTER.md) §2).

**Setting up.** A fresh clone needs `git clone --recurse-submodules`, and
**every new worktree**, the app's included, starts with both folders
empty: run this in it before anything else, or the build can't find
the packages:

```sh
git submodule update --init
python3 characters/packs.py sync
```

The second checks out every character pack installed from a repository
of its own (Boop's, on the owner's machine), on a branch named after the
worktree's; with none installed it says so. A pack's folder is its own
repository: commit and push its changes there (`git -C characters/boop
…`), never here, and this repository's `git status` never shows them.

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

**Changing Boop's pack.** `characters/boop/` is a repository of its
own, on a branch named after this worktree's. Commit and push there:

```sh
git -C characters/boop add -A && git -C characters/boop commit -m "…"
git -C characters/boop push -u origin HEAD
```

Then open a pull request in its repository, squash-merged like the
rest. This repository's `git status` never shows the pack's changes, so
check `python3 characters/packs.py list` for uncommitted work before
you finish.

**Releasing** is separate from pushing, and only when the owner asks: tag
any commit on the package's `main` as a version, and push the tag. Apps
using the package (`from: "1.0.0"`) see it then.

```sh
git -C agent-hooks tag 1.1.0 <commit> && git -C agent-hooks push origin 1.1.0
```

## Never do these

- **Don't launch the Boop app with Bluetooth, or run `bleak`, from an agent
  shell.** macOS kills the process on its first Bluetooth use. For live
  checks, use USB: `internal/tools/boopctl bridge` plus
  `Boop --headless --state-dir DIR --link usb:SOCKET`
  ([internal/VERIFICATION.md](internal/VERIFICATION.md) L4). Ask the owner to run
  `make run` for Bluetooth.
- **Don't modify `~/.claude`, `~/.codex`, or the everyday app's state from
  tests.** Use a temporary `HOME` and isolated state directories, and give
  the installers `--home` too: `NSHomeDirectory()` ignores `HOME`.
- **Don't let Boop approve, deny or block anything an agent does.** Hooks
  only report, and they fail open.
- **Don't use the webcam unless the owner asks** (below).

## Architecture rules

The full picture, with how Boop sits on its three packages (agent-hooks,
MellowHarness, LinkKit), is
[documentation/architecture.html](documentation/architecture.html). The rules that are easy to break:

- **Decisions and effects are separate.** The core and the brain decide.
  Actions (`mood`, `react`) carry out effects and check their own rules.
- **Everything goes through the transcript.** Hooks, pokes, heartbeats
  and every action are raw events in one shape; the view folds them into
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
  library, which `firmware/src/main.cpp` feeds the serial port's lines.
- **The brain is never on the screen's path.** Rules keep the screen true
  at once (the look, "needs you", the tap's poke, the rules' one-shots).
  Every reaction, a finished turn's included, is the brain's, later or
  not at all.
- **The brain is Jev: multiple choice only.** It answers questions about
  a plain-text state; there's no free text. Keep questions few, with
  options that say what they're not.
- **The steering files are read-only at runtime.** `characters/boop/steering/` is
  the single source, and the app bundles it at build time
  (`Package.swift` copies it into the app's resources).
- **No code, commands, tool output, file contents or agent transcripts go
  to the brain.** The only words are your prompt, the agent's last
  message and what you say to Boop on push-to-talk, cut short.
- **"Needs you" and the screen priority are plain rules in the core.**
- **The device renders, reports, and decides when a request plays**
  (LinkKit's turn), never what Boop does: the Mac sends each thing to
  play at once and never times it. It receives the same messages over
  Bluetooth and USB. Its drawing code stays independent of the display
  library, so the simulator and a later ESP-IDF + LVGL port can reuse it.

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
| What a character pack holds or how the engine loads one (`characters/`, `app/BoopKit/Character/`, a pack's demo and how it plays (`app/BoopKit/Demo/`), `characters/charactergen.py` and its staging), or what the public repository leaves out (`internal/tools/export/`) | `characters/CHARACTER.md` |
| The boards, `firmware/src/board/`, `firmware/platformio.ini`, flashing | `firmware/README.md` |
| `simulator/` (the core, the page, the server and its cable, recording and playing demos, its tests) | `simulator/README.md`, `internal/VERIFICATION.md` |
| `Makefile`, `internal/Makefile`, `internal/tools/`, `internal/app/BoopDev/`, `internal/skills/`, the simulator, tests, `.github/workflows/`, a budget | `internal/VERIFICATION.md`, this file, `README.md`, `CONTRIBUTING.md` |
| `internal/app/BoopDevKit/Eval/`, `internal/app/Evals/`, `internal/tools/boopctl_lib/workday.py` | `internal/EVALS.md` |
| `Package.swift`, a package's `Package.swift`, what goes in `internal/` | `internal/README.md`, `documentation/architecture.html`, this file |
| `characters/studio/`, a pack's `studio` entry or `studio/` adapter | `characters/studio/README.md`, `characters/CHARACTER.md` §12 |
| `characters/boop/design/slime-blob/engine/`, `render/`, its preview and trace tools | The slime package's `CONTINUITY.md` and `VALIDATION.md` |

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
