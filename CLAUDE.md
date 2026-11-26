# Boop Agent Instructions

These instructions apply to the whole repo. `AGENTS.md` is a link to
`CLAUDE.md`: edit `CLAUDE.md` only. It's
an index: each fact lives in the doc it points to.

## What Boop is

Boop is a small desk creature with a personality of its own that watches
your Claude Code and Codex agents. It grunts, huffs and says the odd word,
tells you when an agent needs your approval on the Mac, and celebrates
work that earns it. It never approves anything. A Mac app does the thinking; a
cheap ESP32 board with a screen is the body.

## Where to read

Six docs are the core. Read these, in this order, as far as the task needs:

| To know | Read |
| --- | --- |
| What Boop is and how to run it | [README.md](README.md) |
| The rules for working here | this file |
| How Boop works: the model (Doing, Mood, Moment), one turn through every piece, what Jev reads, memory, the rules | [documentation/architecture.html](documentation/architecture.html) |
| The words to use | [documentation/words.md](documentation/words.md) |
| How everything is checked, every make target and tool | [internal/VERIFICATION.md](internal/VERIFICATION.md) |
| What the character's pack holds | [characters/CHARACTER.md](characters/CHARACTER.md) |

Everything else is a reference beside the code it describes:
[CONTRIBUTING.md](CONTRIBUTING.md) for setting up a Mac and the packages'
repositories, each folder's
`README.md` (`firmware/`, `simulator/`, `linkkit/`, `internal/world/`, the
Studio, the tools), [internal/EVALS.md](internal/EVALS.md) for the evals, and
the gel's rule book in `characters/boop/design/slime-blob/`. The design the
builds work toward is [documentation/design/](documentation/design/README.md).
`plan/` holds what's next ([TODO.md](plan/TODO.md),
[product-ideas.md](plan/product-ideas.md)) and three built specs the code
cites by section (`world.md`, `xp-league.md`, `agent-cards.md`).

## Repo layout

| Path | What it is |
| --- | --- |
| `app/` | What ships on the Mac: the menu-bar app (`Boop`) and `BoopKit`, with the world's client in `app/BoopKit/World/`, and `boop-cards`, the tool server agents hand Boop cards through (`app/BoopCards/`) |
| `firmware/` | PlatformIO firmware for the board |
| `linkkit/` | The device link, a package of its own: protocol, host library, device library ([SPEC](linkkit/SPEC.md)) |
| `agent-hooks/`, `mellowharness/` | Submodules: reading agents' hooks, and the brain's harness. Each depends on nothing else here |
| `characters/` | The pack contract, `charactergen.py`, the Studio, and the character's pack itself, `characters/boop/`: the gel slime's words, art, firmware, sounds and evals |
| `simulator/` | The board with no board, for development, tests and demos |
| `internal/` | Everything that doesn't ship: tests, evals, `boopdev`, tools (`boopctl`), skills ([README](internal/README.md)) |
| `internal/world/` | The world's server: Hono on Vercel, Postgres, PGlite in its tests (`npm test` there; [README](internal/world/README.md)) |
| `plan/`, `documentation/`, `landing/` | What's not built yet; the architecture and media; the landing page, a repository of its own that this one ignores |

What ships never depends on `internal/`, and `make -C internal build` fails
if a Swift target imports one it doesn't declare. The packages depend on
nothing of Boop's. Delete code that nothing uses; git keeps it.

## Commands

The root `Makefile` has only what the owner runs: `dev`, `bundle`, `demo`,
`flash`, `eval` and `clean`. Keep it that short: anything for agents, tests
or tools goes in `internal/Makefile`. `make dev` uses Bluetooth, so it's
the owner's. For agents:

```sh
git submodule update --init                           # first, in every new worktree
make -C internal build                                # everything Swift
make -C internal quick                                # while you work: the Swift and firmware tests, about 1.5 min
make -C internal check                                # the tests that need no board, camera or Jev key; not the board's build
make -C internal boards                               # the board's firmware, as CI builds it
make -C internal test                                 # the Swift tests
.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth
.build/debug/Boop --snapshots DIR                     # the popover and onboarding as PNGs, then exits
.build/debug/Boop --counts --state-dir DIR            # the daily counts' summary, numbers only, then exits
make -C internal demos                                # records each new or changed demo script
```

Jev requests cost, and evals have a daily limit: a code-only change that
leaves prompts unchanged needs no Jev run. Which level to run is in
[internal/EVALS.md](internal/EVALS.md) §2.

A demo's recording is made when the demo is wanted (`make -C internal
demos`, `ALL=1` for every one, then commit the pack's `demo/recordings/`):
no check fails on a stale one, and `simulator/tools/demos.py check` lists them.

## Environment notes

- No Xcode, so bare `swift test` runs nothing of Boop's: use `make -C internal test`.
- `@State` doesn't compile here: write `@ViewState` (`app/Boop/Views/ViewState.swift`).
- A SwiftPM failure before compiling, with module-cache errors, wants a
  rerun outside the sandbox, not a look at the source.
- Jev's key comes only from `BOOP_JEV_KEY`, which the owner supplies. Never
  read the Keychain from an agent shell, and don't go looking for the key.
  `Boop --headless --brain scripted` runs the pipeline without it.
- Firmware C++ style is `firmware/.clang-format`; format new and rewritten
  files with `/Library/Developer/CommandLineTools/usr/bin/clang-format -i`.
- Call PlatformIO through `firmware/tools/pio.sh` (the make targets do).
- The build's scripts run on `/usr/bin/python3` (3.9): keep them to it. The
  tools use `internal/tools/.venv`, which `boopctl` makes.
- The simulator's page and the mirror need Emscripten; the mirror is
  checked in, so nothing else does.
- Other sessions share the board: USB work takes its lock, `boopctl board`
  says who has it, `boopctl board hold -- CMD` keeps it.
- A worktree is removed once its branch is merged into main
  (`git worktree remove`, then `git branch -d`), so `.claude/worktrees/`
  holds only work in progress.
- A Unix socket's path has room for 103 bytes: give `Boop --headless` a
  short state directory, under `/tmp`.

## Repositories

Boop is three public repositories; the steps for working across them are in
[CONTRIBUTING.md](CONTRIBUTING.md#working-across-the-repositories).

| Repository | Here at | What goes in it |
| --- | --- | --- |
| Mellow-Machines-Lab/buddygotchi | the root | Boop's engine, LinkKit, the character's pack, tools, tests and docs |
| Mellow-Machines-Lab/AgentHooks | `agent-hooks/` | Reading agents' hooks. Nothing of Boop |
| Mellow-Machines-Lab/MellowHarness | `mellowharness/` | The generic multiple-choice brain. Nothing of Boop |

Boop is one character, the gel slime, on one board, the AMOLED
(`amoled206`), and its pack is here, in `characters/boop/`: a change to
what Boop does or draws is one commit in this repository. The pack came
from Mellow-Machines-Lab/SlimeBuddy (its `main-v2` at `a96500c`), which
keeps its history and takes no more changes. Pixel and the CYD board
(`cyd24`) are archived: restore them from commit `c71ccc5e`, the last
that has them, and Mellow-Machines-Lab/PixelBuddy.

- Anything another app could use about hooks goes in AgentHooks, about a
  personality brain in MellowHarness.
- A change that spans repositories lands in a package first, then here.
  Never commit a pointer to a commit that isn't pushed.
- Every repository squash-merges. **Only the owner pushes, tags or
  force-pushes, or says to.**

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

One concept, one word, in code, comments, the prompt and docs. Wire and
on-disk keys keep their names. The table of words is
[documentation/words.md](documentation/words.md): read it before you name
something new or write text a person reads, and add a row only for a new
concept. The model the words name is in
[documentation/architecture.html](documentation/architecture.html#model):
Boop shows three layers, **Doing**, **Mood** and **Moment**, and says
things on three channels, **voice**, **sign** and **narration**.

## Architecture rules

The rules that are easy to break, in full in
[architecture.html](documentation/architecture.html#rules):

- Decisions and effects are separate: core and brain decide, outputs act.
- Everything goes through the transcript.
- The packages stay apart, and the harness is generic.
- Only Voice knows what Boop can say; only the memory store touches the
  memory files; only LinkKit knows Bluetooth or USB.
- The brain is never on the screen's path, and answers multiple choice only.
- The steering files are read-only at runtime.
- No code, commands, tool output, file contents or agent transcripts go
  to the brain: only readings, and your words to Boop. An agent's card,
  its offered lines and its note included, goes to the screen and the
  transcript, never to the brain. What goes the other way, Boop's brief to
  the agent (`AgentBrief`), carries Boop's personality, mood and memory
  only while Settings lets the agent help.
- Your hands and what else Boop notices of you at the Mac reach the board
  as tags and `ptr` and nothing else (`Hands`, `Along`): that you type,
  scroll or listen, never what, with no event, nothing in the
  transcript and nothing for the brain, the world or the daily counts.
  One exception, and only it: music on keeps Boop from dozing off and
  ends a nap (`Core.along`), a change of Doing alone.
- The world gets only `World.State`'s fields (`WorldTests` pins them): the
  buddy's name and level, its UTC offset, one of six activities,
  counts, its days in a row and its colour. Nothing before onboarding's world screen, nothing with it off.
- "Needs you" and the screen priority are plain rules in the core.
- The rules always answer, and Jev only takes their seats, in time or
  not at all (`SeatedBrain`): a Moment's move and size, and the whole
  Moment at your lock or unlock, a working check-in and a boop from the
  world, are plain rules in one place (`MomentRule`), and so are when a
  Moment speaks (`Skits`) and which one thing an idle check-in may hold
  up (`IdleBeat`).
- The device renders, reports and decides when a Moment plays, never what
  Boop does.
- The Mac's face is the board's firmware: the mirror is built from
  it, not checked in (`firmware/tools/mirror.sh`, which the builds run).

## The UI's words

Every string a person reads, on the Mac or the board: short and warm, with
no numbers that aren't needed. Talk like a friend, not a manual: "82
today. Fill the ring and you're done for the day," not "A full ring is
100. More doesn't count." No game jargon but XP, the one unit people see, and no exclamation spam.

## Docs

The code is the source of truth. Docs are updated once per finished
feature, in one commit at its end, not in every commit. This keeps a
behavior change small.

- In the same commit, fix only what would mislead the next agent at once:
  a command in this file that no longer runs as written, or a rule here
  that is no longer true.
- At a feature's end, grep the docs for what changed and update them
  together: `documentation/architecture.html`, `documentation/words.md`,
  `characters/CHARACTER.md`, `internal/VERIFICATION.md`, `internal/EVALS.md`,
  and the README of the package or folder you changed.
- Say each fact once, in the code where it can. Comments explain, they
  don't cite docs that might move.
- Removed code takes its docs with it.
- `plan/` holds only what is not built. Delete a plan when it is built;
  git keeps it.

## Checking your work

Use the loop in [internal/VERIFICATION.md](internal/VERIFICATION.md) §1, and
report only checks that actually ran and passed, in the commit message or
pull request. Before trusting anything that depends on hooks, run the
`doctor` skill. Webcam verification only when the owner asks.
