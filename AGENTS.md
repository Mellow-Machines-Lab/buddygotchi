# Boop Agent Instructions

These instructions apply to the whole repo. `CLAUDE.md` and `AGENTS.md`
are the same file: edit `CLAUDE.md`, then copy it over `AGENTS.md`. It's
an index: each fact lives in the doc it points to.

## What Boop is

Boop is a small desk creature with a personality of its own that watches
your Claude Code and Codex agents. It grunts, huffs and says the odd word,
tells you when an agent needs your approval on the Mac, and celebrates
work that earns it. It never approves anything. A Mac app does the thinking; a
cheap ESP32 board with a screen is the body.

## Where to read

| To know | Read |
| --- | --- |
| How Boop works: the model (Doing, Mood, Moment), one turn through every piece, what Jev reads, memory, the rules | [documentation/architecture.html](documentation/architecture.html) |
| How to build, test and work across the repositories | [CONTRIBUTING.md](CONTRIBUTING.md) |
| How everything is checked, every make target and tool | [internal/VERIFICATION.md](internal/VERIFICATION.md), [internal/EVALS.md](internal/EVALS.md) |
| What a character pack holds | [characters/CHARACTER.md](characters/CHARACTER.md), [characters/new-character-playbook.md](characters/new-character-playbook.md) |
| The boards and flashing | [firmware/README.md](firmware/README.md) |
| The board with no board | [simulator/README.md](simulator/README.md) |
| What's next | [plan/TODO.md](plan/TODO.md), [plan/product-ideas.md](plan/product-ideas.md) |

## Repo layout

| Path | What it is |
| --- | --- |
| `app/` | What ships on the Mac: the menu-bar app (`Boop`) and `BoopKit` |
| `firmware/` | PlatformIO firmware for the two boards |
| `linkkit/` | The device link, a package of its own: protocol, host library, device library ([SPEC](linkkit/SPEC.md)) |
| `agent-hooks/`, `mellowharness/` | Submodules: reading agents' hooks, and the brain's harness. Each depends on nothing else here |
| `characters/` | The pack contract, `charactergen.py`, the Studio; the packs are fetched into `characters/.repos/` (`boop`, `pixel`) |
| `simulator/` | The board with no board, for development, tests and demos |
| `internal/` | Everything that doesn't ship: tests, evals, `boopdev`, tools (`boopctl`), skills ([README](internal/README.md)) |
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
git submodule update --init && make -C internal packs  # first, in every new worktree
make -C internal build                                # everything Swift
make -C internal check                                # every check that needs no board, camera or Jev key
make -C internal test                                 # the Swift tests
.build/debug/Boop --headless --state-dir DIR --debug  # the whole runtime with no UI or Bluetooth
.build/debug/Boop --snapshots DIR                     # the popover and onboarding as PNGs, then exits
make -C internal demos                                # records each new or changed demo script
```

Jev requests cost, and evals have a daily limit: a code-only change that
leaves prompts unchanged needs no Jev run. Which level to run is in
[internal/EVALS.md](internal/EVALS.md) §2.

A new or changed demo script is recorded in the same commit (`make -C
internal demos`, then commit the pack's `demo/recordings/`). When a change
alters what the app sends the board, record them all (`ALL=1`).

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

Boop is five public repositories; the steps for working across them are in
[CONTRIBUTING.md](CONTRIBUTING.md#working-across-the-repositories).

| Repository | Here at | What goes in it |
| --- | --- | --- |
| Mellow-Machines-Lab/buddygotchi | the root | Boop's engine, LinkKit, the pack contract, tools, tests and docs |
| Mellow-Machines-Lab/AgentHooks | `agent-hooks/` | Reading agents' hooks. Nothing of Boop |
| Mellow-Machines-Lab/MellowHarness | `mellowharness/` | The generic multiple-choice brain. Nothing of Boop |
| Mellow-Machines-Lab/SlimeBuddy | `characters/boop` | The gel slime's own words, art, engine, sounds and evals |
| Mellow-Machines-Lab/PixelBuddy | `characters/pixel` | Pixel, the open example |

- Only what's a character's own goes in its repository; anything another
  character could use stays here. Anything another app could use about
  hooks goes in AgentHooks, about a personality brain in MellowHarness.
- A change that spans repositories lands in this order: a package; the
  character's content (this repo's CI fetches the packs' main); here; then
  each character's `engine/` pin, to the commit here (its CI fails on the
  old pin until then). Never commit a pointer to a commit that isn't pushed.
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
on-disk keys keep their names (the last column). The model they name,
and its rules, is [documentation/architecture.html](documentation/architecture.html#model):
Boop shows three layers, **Doing**, **Mood** and **Moment**, and says
things on three channels, **voice**, **sign** and **narration**.

**The agents**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| agent | Claude Code or Codex | | |
| session | One conversation, with its thread's name and project | thread (for the conversation) | `session` |
| turn | From your prompt to its finish: done, failed, stopped or answering | | `turn` |
| call | One tool use | tool call, tool use | `call` |
| check | A test or build run, which passes or fails | | |
| helper | A subagent | subagent (in prose) | `subagent` |
| to-do | An agent's plan, "3/7" | todo list | `todo` |
| needs you | An agent waiting on your approval: a request | attn, alert | `attn` |
| the line | Agents waiting for you, in order | | |
| reading | What Boop takes from a text in its place: kind, tone, length, names said, a few words (`PromptReading`, `MessageReading`) | summary, label | `reading` |

**You**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| touch | Anything you do to the board with a finger or a hand: a poke, a stroke, a ruffle, a nose boop, a tickle, a swipe, a shake, a pick-up, a put-down, a thump, peekaboo | tap, gesture (as two kinds) | `tap`, `gesture` |
| poke | One tap on the face; a run is several in a row | tap | `tap` |
| care | The touches and words that count as caring (strokes, kind words, talking, coming back) | | |
| words | What you say to Boop on push-to-talk | talk (for the event), said | `talk` |
| listening | Boop hearing you, while BOOT or the mic is held | push-to-talk (the state) | `listening` |
| presence | You at the Mac, away, or back | | `presence_start`, `presence_end` |
| lock, unlock | The Mac's screen locking and unlocking, every time however short; an away only after 10 min | | `lock_start`, `lock_end` |
| button | BOOT: hands you the next agent in the line | press, hand-off | `press` |
| dismiss | A finger held on the needs-you screen | | |
| face down | Do not disturb: Moments are refused, Doing goes on | | `facedown` |

**Doing**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| doing | What Boop is busy with: resting, working, asleep, listening, no app | base, look (for the state) | `base` |
| nap | Boop asleep at once, Jev's pick at a lock at night, until you show up (`Core.nap`) | | `reply`: `nap`, `base`: `asleep` |
| look | Only the art that draws a Doing | | |
| activity | How it's working: testing, delegating, terminal, searching, analysing, a tool, waiting, planning | act | `act` |
| tier | How long it's been working or resting: tier 1 at 30 s to tier 5 at 10 min (`Tags.tiers`) | stage (that's growth's) | `tier1`…`tier5` |
| pastime | What Boop does to pass the time, by Doing and tier or wait (`render/gel/pastimes.h`) | gag (the gel's), idle gag, occasion (the rig's) | |
| kit | Props shown while true: mugs, headphones, the zone, the plant | | |
| dressing | Outfits and decorations from tags: a hat, shades, the sun, the air | outfit, layers, occasion (as a design) | |
| pace | Working faster when busy or frantic | | `busy`, `frantic` |
| the work stream | Agents' calls as falling words: part of Doing, never a Moment | gag (the stream's), call forward | `call` |
| work act | A command Boop plays out while it runs, with a low sign and Jev's voice: the tests, the push, the build | act (that's the activity) | `wact` |
| the strip | The counts along the bottom | | |
| the drawer | The AMOLED board's list of every agent, pulled up from the strip, a row each to open on the Mac (`render::Drawer`) | roll call, list view | `list`, `drawer` |
| the needs-you screen | Amber, naming who's waiting, until you answer or dismiss it | sign (that's a Moment's) | |

**Mood**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| mood | One of the pack's 16 lasting moods (`CharacterPack.Mood.lasting`) | (a Moment's emotion) | `mood` |
| resting mood | Calm, where moods settle | default mood | |
| neighbours | The moods a mood can move to; a jump is a big move | moves (the graph's), ordinary and dramatic | |
| fade | A mood settling after its minutes | | |
| mood file | The steering for one mood (`steering/mood/`) | | |

**Moment**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| moment | A beat on top of Doing: event, emotion, size, voice and sign; made by the board, the rules or Jev | reaction (for the beat), one-shot | `do` |
| event | What happened: a finish, a check, you came back, your words, your prompt naming Boop, a touch, or Boop's own beat | | |
| Boop's own beat | A Moment with no outside event: an idle check-in, a musing, an ask | | |
| emotion | The expression for one Moment, any of the pack's 42 faces | face | `react.face`, a `do`'s `mood` |
| size | How much the Moment matters: small, medium, big, huge | intensity, loops | `react.intensity`, `loops` |
| finish | The animation a turn's end plays, scaled by the turn's length; the low sign and rim glow name the thread | move (success, failure), task_complete | `task_complete`, `reply_ready`, `outcome` |
| greeting | The animation of your coming back, or of your prompt naming Boop | move (wake up, notice) | `wake_up`, `notice` |
| wave | Boop's answer to your lock or unlock: `bye` or `hello`, or `reply-wave`, slighter, when small; a snub has none | | `reply` |
| reply | Boop's answer to your words, with its clip and sign (`MomentOutput.replies`) | answer (that's a topic), response | `reply` |
| ask | A sign that is a question, with two answers you tap, from the pack's `asks.md`; never needs an answer | quiz, prompt | `ask` |
| wish | Boop's want, about one a day by its steering, kind pet, chat or work, its sign picked by Jev like an ask's; a rule meets it at once by a touch on its face, push-to-talk or working with an agent; until you've met a kind once it shows how; left too long it sighs and slumps (`Core.Wish`, `[wish …]` in `asks.md`, `state.wish`, `wish_how`, `wish_met`, `wish_gone`) | need, request | `wish` |
| musing | Boop's own beat with a sign and no question, a `[idle]` line of `signs.md` | thought, quip | |
| the telling | The Moment at your first showing up after 5:00 that tells the dream | | |
| the day's greeting | The Moment of your first showing up of Boop's day, or the one that tells the dream: it plays whole, its sign after its words, the work stream after it (`Moment.greeting`) | | `greeting` |
| variation | Which version of a design plays; the board picks | | `variant` |
| the queue | LinkKit's rule for what plays when (linkkit/SPEC.md §4) | the turn | |

**Voice, sign and narration**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| voice | What Boop says aloud: none, a sound, a word, a phrase, a swear | say | `say` |
| take | One recorded clip; a lead sound may come first | line | `take` |
| the voice file | `voice/voice.bin`, on the board's card | voice pack | |
| sign | A caption Boop holds up, at most 18 characters (`Signs`, `signs.md`) | banner, label | `sign` |
| low sign | A card Boop holds up in the strip's place, two lines at most: a finish's thread (`gel::LowSign`) | ticket | |
| bubble | The voice's words as text in the lane | | |
| talk | How much Boop says: quiet, normal, chatty, or silent for a while (a hush) (`Talk`, `Core.Hush`) | chattiness, mute (that's the volume) | `talk`, `hush`, `hushed` |
| narration | The Mac's plain words for why, never Jev's or Boop's voice (`Narration`) | explanation, caption | `reason` |

**The mind**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| transcript | Every event, one file a day (`Transcript`) | the log | |
| line | One event as a sentence Jev reads (MellowHarness's `Line`) | | |
| message | One JSON line on the wire: `hello`, `state`, `do`, `ev` | line | |
| the prompt | What Jev reads: guide, PERSONALITY, MEMORY, MOOD, CONTEXT, HISTORY, NOW | the state | |
| CONTEXT | The prompt's section for how things stand: When, Talk, the buddy, you, the agents, the day so far (`ContextSection`) | NOW (that's the event), status | |
| pass | One request to Jev | | |
| wake, hold | Whether an event asks Jev at all | | |
| check-in | Boop looking in by itself: working (during a turn), idle (while you're here), hourly | heartbeat | `check_in`, `working`, `idle` |
| output | What Jev's answers drive (MellowHarness's `Output`; Boop's `mood` and `react`) | action | |
| speeds | Reflex, reactive and deliberative | loops | |
| personality | Who Boop is, temperament included (characters/CHARACTER.md §7) | nature | |
| steering | The pack's text Jev reads | | |
| buddy | One board running one pack, with its own name, Doing, Mood and agents (`Buddy`) | body, creature | |
| step | One row of a demo script or an eval scenario | line | |

**Memory and time**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| Boop's day | 5:00 to 5:00, today for CONTEXT's Today row and the XP caps; it triggers nothing | | |
| dream | Everything since the last dream as tags and a sentence, and the memory's update from it: on `d`, once a sleep, or after two days (`DreamReader`, `Memory.dream`, `dreams.md`) | diary, journal, closing the day | |
| written memory | `memory.md`: You, Your work, You and Boop, Recently (`WrittenMemory`) | diary, memory file | |
| remembered line | A note of the written memory in the pet's voice, at most 40 characters: what Boop brings up on the low sign at an idle check-in, about once a day (`Memory.Felt`, `memory-days.json`) | | `low`, `felt` |
| the dream's write | Code proposing the written memory's edits as Boop dreams, with Apple Intelligence answering small questions, and the checks holding each (`MemoryPipeline`, `MemoryProposer`, `MemoryEdits`) | the night's write | |
| growth | XP, which can go backwards, and stages, Hatchling to Chonk; a stage changes only the body and the pastimes. The growth bar shows it on the board, with a met wish's heart flying in (`GrowthShow`), and Jev's sign says what grew (`[grew]`) | | `xp`, `grew` |
| special day | A holiday, a milestone day, Boop's birthday, a stage reached | occasion (for a day) | |
| tag | A fact true now, sent to the board | flag, label | `when` |

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
  to the brain: only readings, and your words to Boop.
- "Needs you" and the screen priority are plain rules in the core.
- The device renders, reports and decides when a Moment plays, never what
  Boop does.
- The Mac's face is the board's firmware: a change to what the gel draws
  rebuilds the mirror (`firmware/tools/mirror.sh`).

## Docs stay in sync

The code is the source of truth. A change that alters what a doc says
updates it in the same commit. In a worktree, first check that
`git log --oneline HEAD..main` prints nothing.

| When you change | Update |
| --- | --- |
| `agent-hooks/`, `mellowharness/` (in their own commit there), `linkkit/` | That package's `ARCHITECTURE.md`, `README.md`; LinkKit's `SPEC.md` and `device/README.md` too |
| How the pieces join, which products Boop takes, `Package.swift` | `documentation/architecture.html`, `internal/README.md` |
| What a pack holds or how the engine loads one | `characters/CHARACTER.md` |
| A demo script or how one plays | `characters/DEMOS.md`, `internal/sessions/README.md` |
| The boards, flashing | `firmware/README.md` |
| `simulator/` | `simulator/README.md`, `internal/VERIFICATION.md` |
| A make target, tool, test level or budget | `internal/VERIFICATION.md`, this file, `README.md`, `CONTRIBUTING.md` |
| Evals | `internal/EVALS.md` |
| The Studio | `characters/studio/README.md`, `characters/CHARACTER.md` §12 |
| The gel slime, in SlimeBuddy | Its `CONTINUITY.md`, `VALIDATION.md`, slimegen's `README.md` |

- Say each fact once, in the code where it can. When one changes, grep the
  docs and comments for the old value or name.
- Comments explain, they don't cite docs that might move.
- Examples are real, and commands run as written.
- Pin a rule with a number in it in a test that says which rule it pins.
- Removed code takes its docs with it. Bump "Updated" on each doc you touch.
- Before you commit, go through `git diff --stat` against the table, check
  `cmp CLAUDE.md AGENTS.md` is silent, and that new links resolve.

## Checking your work

Use the loop in [internal/VERIFICATION.md](internal/VERIFICATION.md) §1, and
report only checks that actually ran and passed, in the commit message or
pull request. Before trusting anything that depends on hooks, run the
`doctor` skill. Webcam verification only when the owner asks.
