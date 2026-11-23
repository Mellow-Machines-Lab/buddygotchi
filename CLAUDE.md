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
| Agents' cards: what one is, the rules, how agents did | [plan/agent-cards.md](plan/agent-cards.md) |

## Repo layout

| Path | What it is |
| --- | --- |
| `app/` | What ships on the Mac: the menu-bar app (`Boop`) and `BoopKit`, with the world's client in `app/BoopKit/World/`, and `boop-cards`, the tool server agents hand Boop cards through (`app/BoopCards/`) |
| `firmware/` | PlatformIO firmware for the two boards |
| `linkkit/` | The device link, a package of its own: protocol, host library, device library ([SPEC](linkkit/SPEC.md)) |
| `agent-hooks/`, `mellowharness/` | Submodules: reading agents' hooks, and the brain's harness. Each depends on nothing else here |
| `characters/` | The pack contract, `charactergen.py`, the Studio; the packs are fetched into `characters/.repos/` (`boop`, `pixel`) |
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
git submodule update --init && make -C internal packs  # first, in every new worktree
make -C internal build                                # everything Swift
make -C internal check                                # the tests that need no board, camera or Jev key; not the boards' builds
make -C internal boards                               # both boards' firmware, as CI builds them
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
| in a row | The same thing coming again with no break, counted one way and said one way in a line (", the 3rd in a row"): pokes, shakes, quick wins, a check failing, calls failing (`InARow`) | streak, run, again | `in_a_row`, `wins_in_a_row`, `failed_before`, `failing` |
| the line | Agents waiting for you, in order | | |
| reading | What Boop takes from a text in its place: kind, tone, length, names said, a few words (`PromptReading`, `MessageReading`) | summary, label | `reading` |

**You**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| touch | Anything you do to the board with a finger or a hand, one of seven: a poke, a stroke, a hold (a finger kept still), a shake, a pick-up, a swipe, face down. The board finds more kinds and plays each its own way; the Mac reads them as these (`Touch.read`): a wrong-way stroke is a stroke, a nose boop or a tickle a poke, a thump a shake, a put-down and turning it back up the ends of a pick-up and of face down | tap, gesture (as two kinds), lean, ruffle, tickle | `tap`, `gesture`; the board's `lean`, `ruffle`, `nose`, `tickle`, `dizzy`, `startle`, `putdown`, `peekaboo` |
| poke | One tap on the face, wherever it lands; several are counted in a row | tap | `tap` |
| care | The touches and words that count as caring (strokes, kind words, talking, coming back) | | |
| words | What you say to Boop on push-to-talk | talk (for the event), said | `talk` |
| listening | Boop hearing you, while BOOT or the mic is held | push-to-talk (the state) | `listening` |
| presence | You at the Mac, away, or back | | `presence_start`, `presence_end` |
| your hands | Whether you're typing at the Mac, scrolling, or there with your hands still: idle times, never the keys or the page; a tag, not an event (`Hands`) | pace (that's the agents'), activity | `typing`, `scrolling`, `reading` |
| with you | What Boop notices you do at the Mac besides your hands, each a plain fact sent as a tag or `ptr`, never content, never an event, the transcript, the logs or the brain's (`Along`); Settings' "Notices what you do at the Mac" turns it all off | watching you, tracking, telemetry | the tags below, `ptr` |
| typing fast | Keys in at least 6 of the last 8 quarter seconds (`Along.fastSlots`) | | `typingfast` |
| pointer | The way from Boop to your pointer while it moves, as you see the board beside the screen, each of x and y in -10…10; none 3 s after it stops, or with no anchor (`Pointer`) | cursor, mouse | `ptr`: `[x, y]`, `[x, y, 1]` at the edge nearest Boop |
| anchor | Where Boop sits beside your screen: the spot nearest it, shown once in Settings by pointing there and touching Boop ("Show Boop where it sits"); the side the screen is on comes from it, and up when it's in the middle third (`Anchor`) | calibration, position | `macleft`, `macright`, `macup` |
| music | Sound another app plays, or a frontmost app that isn't a player, for 5 s and more (Core Audio's process objects, macOS 14.2+) | audio, song | `music` |
| video | Sound the frontmost app itself plays, when it's a browser or a video player (`Along.players`) | watching | `video` |
| on a call | A camera, or another app recording sound (never Boop's push-to-talk), on 5 s and more: Boop keeps still and silent, the board is sent no volume, no take is spoken and every Moment is small | meeting, call (that's a tool use) | `oncall` |
| copied | A copy, from the pasteboard's change count, until your next key or click or 10 s; never what was copied | clipboard, holding | `copied` |
| lock, unlock | The Mac's screen locking and unlocking, every time however short; an away only after 10 min | | `lock_start`, `lock_end` |
| button | BOOT: hands you the next agent in the line | press, hand-off | `press` |
| dismiss | A finger held on the needs-you screen | | |
| face down | Do not disturb: Moments are refused, Doing goes on | | `facedown` |

**Doing**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| doing | What Boop is busy with: resting, working, asleep, listening, no app. With no agent open, resting while you're at the Mac and asleep once you're away, the screen is locked or you've been still its doze time (`Core.sleepsAlone`) | base, look (for the state) | `base` |
| nap | Boop asleep at once, the rule's at a bye at night with no agent working, after its good-night wave, until you show up (`MomentRule.bye`, `Core.nap`); with no agent open, any lock puts it to sleep too (`doing`) | | `base`: `asleep` |
| look | Only the art that draws a Doing | | |
| activity | How it's working, one of four the whole body shows (`Act`): typing (an edit, any other tool, a plan), looking (a read, a search, the web), running (a command, the tests, a build, helpers at work), waiting (a call gone quiet) | act | `act`: `tool_use`, `analyzing`, `terminal`, `waiting` |
| tier | How long it's been working or resting: tier 1 at 1 min, tier 2 at 5 min, tier 3 at 15 min (`Tags.tiers`) | stage | `tier1`…`tier3` |
| pastime | What Boop does to pass the time, by Doing and tier or wait: a move of the body and nothing beside it, none while something needs you (`render/gel/pastimes.h`) | gag (the gel's), idle gag, occasion (the rig's) | |
| dressing | What's worn for the tags: on the gel, a nightcap at night and nothing for a special day, nothing in the sky or the air | outfit, layers, occasion (as a design) | |
| pace | Working faster when busy or frantic | | `busy`, `frantic` |
| gaze | Where Boop's eyes look by themselves: one thing at a time, held, then forward; at work only while it types, as the other activities' poses have the eyes (the gel's `render/gel/gaze.h`) | look (that's a Doing's art), attention | `macleft`, `macright`, `ptr` |
| typing along | Boop typing while you do, a small sway over its keys, never a hop, quicker when you type fast, and a look up at you when a long stretch stops: at its desk at work while its own activity is typing, with its keyboard out when idle (`GelFace::showAlong`) | mirroring | `typing`, `typingfast` |
| reading along | Boop turned to the screen while you scroll, its eyes going down a line at a time, settling in after two minutes (`GelFace::showWithYou`); its music, video, on-a-call and copied poses are the same function's | | `scrolling` |
| tilt | How far the board is tipped against how it's been resting, which the body sloshes by (`app::Tilt`); no touch | hold (that's a finger's) | |
| the work stream | Agents' calls as words: the newest after the strip's count (the work's term), and the few that come forward from the desk's monitor and land on Boop: part of Doing, never a Moment | gag (the stream's), call forward, falling words | `call` |
| work act | A command worth naming while it runs, the tests, the push or the build: on the gel, the monitor's icon (a flask for tests) and the strip's term say what's running, then a tick or a cross and `tests passed` or `tests failed`, never a card, and Boop hops or flinches at the result | act (that's the activity) | `wact` |
| the strip | The counts along the bottom, and after them while agents work, the work's term: the newest call's word, a work act's, or a failure's (`termFor`, the gel's) | | |
| the drawer | The AMOLED board's list of every agent, pulled up from the strip, a row each to open on the Mac (`render::Drawer`) | roll call, list view | `list`, `drawer` |
| card | What an agent hands Boop to hold, through the `boop-cards` tool server: a status while its turn runs, a result for 15 s after it; one main thing and at most one small line, in the agent's own words, never Jev's to read. On the gel it's the agent's window: a title bar in its lane colour naming the agent, square-ish corners, and the desk's monitor lit in that colour, never one of Boop's round signs. Part of Doing: a swipe changes card, a tap opens it on the Mac (`Card`, `Cards`, `gel::paintCard`) | artifact, widget; sign, low sign (those are Boop's own) | `card` |
| the needs-you screen | Amber, naming who's waiting, until you answer or dismiss it | sign (that's a Moment's) | |

**Mood**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| mood | One of the pack's 7 lasting moods: calm, happy, focused, proud, cross, sad, lonely (`CharacterPack.lasting`). Jev keeps it or moves it to any other; the wire carries the face it rests in | (a Moment's emotion) | `mood` |
| resting mood | Calm, where moods settle | default mood | |
| level | How cross it is, 1 to 3, which code counts and Jev never picks: pokes and shakes in a row, failed checks and turns, rude words; a stroke takes it one down. It picks cross's resting face: annoyed, grumpy, angry (`MoodOutput.level`) | intensity, step | `level` (the transcript's) |
| fade | A mood settling by itself after its minutes in `character.json`, to calm (proud to happy, cross a level down), run by code on the Mac's clock, never by Jev (`MoodOutput.fade`) | drift | `fade` (the transcript's) |
| mood file | The steering for one mood (`steering/mood/`): what it is, how its faces lean, what moves it. No minutes: code fades it | | |

**Moment**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| moment | A beat on top of Doing: event, emotion, size, voice and sign; made by the board, the rules or Jev. Jev picks only the emotion, the voice and the sign; the move and the size are the rules' (`MomentRule`), and so is the whole Moment at your lock or unlock, a working check-in, a boop from the world and Boop's growth, and which idle beat is due (`IdleBeat`) | reaction (for the beat), one-shot | `do` |
| event | What happened: a finish, a check, you came back, your words, your prompt naming Boop, a touch, or Boop's own beat | | |
| Boop's own beat | A Moment with no outside event: an idle beat | | |
| idle beat | The one thing Boop may hold up at an idle check-in, which code deals: the first that's due of an agent waiting on you (the `waiting` notice), the wish, another notice, an ask, a remembered line, a musing; at most one an hour and four a Boop day, on Quiet only the first. Jev says only whether to hold it up (`IdleBeat`) | | `beat` |
| emotion | The expression for one Moment, any of the pack's 18 faces | face | `react.face`, a `do`'s `mood` |
| size | How much the Moment matters: small, medium, big. A rule's pick, never Jev's: a finish by its turn's length, your words medium, a touch small (`MomentRule.size`) | intensity | `loops` |
| finish | The animation a turn's end plays, the rule's pick by how the turn ended (`MomentRule.move`), one for each size by the turn's length: Little Win, Confetti, Gold Rush; the low sign and rim glow name the thread. A chat turn (its last message a question or an answer, or quick with no calls) plays none and names nothing: the strip's idle count says it's your turn | move (success, failure), task_complete | `task_complete`, `reply_ready`, `outcome` |
| hello | You came: your unlock, your coming back from an away, or your first touch of Boop's day. The rule picks its size by the time away (small; medium with the wake-up after an hour; big after a day) and at most one extra: a special day's sign, else the dream told, else what happened while you were away. The first of Boop's day, and one that tells the dream, plays whole. An unlock's is the rule's alone, a slight wave; Jev picks the face and the word only after a real away, 10 min or more (`MomentRule.hello`, `TranscriptView.hello`) | greeting, wave, the day's greeting, the telling | `wake_up`, `reply`: `hello` and `wave`, `greeting` |
| bye | You went: your lock of the Mac, by rule and with no pass (`MomentRule.bye`): a real wave with a word and a sign at a first lock in an hour, good night and the nap at a lock at night, else `reply-wave`, slighter and silent; cross, a snub, which has none. Stepping away has none | wave | `reply`: `bye` and `wave` |
| reply | Boop's answer to your words, Jev's pick of 11 (yes, no, huh, hello, bye, thanks, ouch, comfort, hehe, status, hush), with its clip and sign (`MomentOutput.replies`) | answer (that's a topic), response | `react.reply`, `reply` |
| ask | A sign that is a question, with two answers you tap, from the pack's `asks.md`, dealt as an idle beat; never needs an answer | quiz, prompt | `ask` |
| wish | Boop's want, one a Boop day, kind pet, chat or work, dealt as an idle beat, never while it's cross; a rule meets it at once by a touch on its face, push-to-talk or working with an agent; left too long it sighs and slumps (`Core.Wish`, `[wish …]` in `asks.md`, `state.wish`, `wish_met`, `wish_gone`) | need, request | `wish` |
| notice | Something true about your day that Boop may care about: a fact on a moment that exists (`Noticed` in CONTEXT), or a line of its own dealt as an idle beat, `waiting` first, `stretch`, `rough` or `late` after the wish (`Notices`, `[notice …]` in `signs.md`). The animation called `notice` on the wire is your prompt naming Boop's, which a played notice borrows to look up at you | nag, reminder | `notice_key` |
| musing | An idle beat with a sign and no question, a `[idle]` line of `signs.md`: what's dealt when nothing else is due | thought, quip | |
| variation | Which version of a design plays; the board picks | | `variant` |
| the queue | LinkKit's rule for what plays when (linkkit/SPEC.md §4) | the turn | |

**Voice, sign and narration**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| voice | What Boop says aloud: none, a sound, a word, a phrase, a swear (only with Settings' swearing on). Jev picks what it's about (`say`): nothing, a swear, one of 4 feelings or one of 6 topics (hello, work, tests, done, retry, quiet) | say | `say` |
| take | One recorded clip; a lead sound may come first | line | `take` |
| the voice file | `voice/voice.bin`, on the board's card | voice pack | |
| sign | A caption Boop holds up, at most 18 characters (`Signs`, `signs.md`) | banner, label | `sign` |
| low sign | A card Boop holds up in the strip's place, two lines at most, one under the rim's glow: a finish's thread, a work act's words, a remembered line, a level in gold (`gel::LowSign`) | ticket | `low`, `gold` |
| bubble | The voice's words as text in the lane | | |
| talk | How much Boop says: quiet or normal. "Shh", the hush reply and the popover's Hush make it quiet for half an hour, then it's the setting's again; talking to Boop ends that sooner (`Talk`, `Core.quiet`) | chattiness, mute (that's the volume), hush (as a state) | `talk` |
| narration | The plain words for why, the Mac's and the gel's board's own for a touch, never Jev's or Boop's voice (`Narration`, `app/touch_reason.h`); on the board, the caption | explanation | `reason` |

**The mind**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| transcript | Every event, one file a day (`Transcript`) | the log | |
| daily counts | A row a day of numbers on the Mac, `daily-counts.jsonl`, for "This week" and a summary you may send; no words, threads or notes (`DayCounts`, `Boop --counts`) | stats, telemetry | |
| line | One event as a sentence Jev reads (MellowHarness's `Line`) | | |
| message | One JSON line on the wire: `hello`, `state`, `do`, `ev` | line | |
| the prompt | What Jev reads: guide, PERSONALITY, MEMORY, MOOD (the mood's file, then cross's level now), CONTEXT, HISTORY, NOW | the state | |
| CONTEXT | The prompt's section for how things stand: When, Talk, the buddy, you, the agents, the day so far (`ContextSection`) | NOW (that's the event), status | |
| pass | One request to Jev: its mood, its emotion and what it says; to your words, its reply too; at some events a sign | | |
| wake, hold | Whether an event asks Jev at all. What wakes it: your prompt's reading, a finish, your words, a failed check or a fix, a touch, your coming back, an answered ask, a wish's end, a push's result, an answered request, and the idle check-in (`TranscriptView.wakes`). A turn's start, your lock and unlock, the working check-in, a boop from the world and Boop's growth never do | | |
| check-in | Boop looking in by itself: working (during a turn), the rule's small Moment with a word about the work and no pass (`MomentRule.checkIn`); or idle (while you're here), where the idle beat is dealt and Jev picks the face | heartbeat | `check_in`, `working` |
| output | What Jev's answers drive (MellowHarness's `Output`; Boop's `mood` and `react`) | action | |
| speeds | Reflex, reactive and deliberative | loops | |
| personality | Who Boop is, temperament included (characters/CHARACTER.md §7) | nature | |
| steering | The pack's text Jev reads | | |
| buddy | One board running one pack, with its own name, Doing, Mood and agents (`Buddy`) | body, creature | |
| step | One row of a demo script or an eval scenario | line | |

**Memory and time**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| Boop's day | 5:00 to 5:00, today for CONTEXT's Today row and the ring; it triggers nothing | | |
| dream | Everything since the last dream as tags and a sentence, and the memory's update from it: on `d`, once a night's sleep or one of 5 h, or after two days (`DreamReader`, `Memory.dream`, `dreams.md`) | diary, journal, closing the day | |
| digest | One dream's span in numbers and the few words that may be kept, in `memory-days.json`: what habits and notices are read from (`DayDigest`) | summary, day file | |
| written memory | `memory.md`: You, Your work, You and Boop, Recently (`WrittenMemory`) | diary, memory file | |
| remembered line | A note of the written memory in the pet's voice, at most 40 characters: what Boop brings up on the low sign as an idle beat, each line once in 14 days (`Memory.Felt`, `memory-days.json`) | | `low`, `felt` |
| the dream's write | Code proposing the written memory's edits as Boop dreams, with Apple Intelligence answering small questions, and the checks holding each (`MemoryPipeline`, `MemoryProposer`, `MemoryEdits`) | the night's write | |
| XP | What Boop earns, a fixed amount for each thing the agents get done and each bit of your care, never lost (`Growth`, plan/v1-buddy.md §5) | points | |
| the ring | Today's XP, up to 100 a Boop day: full, nothing more counts that day. On the board, a bar that shows only when XP comes in (`GrowthShow`), with a met wish's heart flying in; its closing is the rules' moment, one with a level reached at once, and one `growth` event for both | daily goal, progress bar | `xp` (today's percent), `growth` |
| level | 1 + every XP / 100, no maximum, never down; a level-up is the rules' moment, `Level 12!` on the low sign, the same at every level: Boop's body is one size | stage, size (for growing) | `growth`'s `level` |
| special day | A holiday, a milestone day, Boop's birthday | occasion (for a day) | |
| tag | A fact true now, sent to the board | flag, label | `when` |

**The world**

| Word | Means | Not | On the wire |
| --- | --- | --- | --- |
| the world | Everyone's buddies together on one server (`internal/world/`), which Boop joins unless you keep it private; the Mac's client is `WorldLink` | map, network | |
| boop (from the world) | Another buddy's gesture for yours: a boop, a wave, a heart, or a cheer for your ship; a `world` event, which the rules answer with a warm small face and one of the pack's signs for it, no pass (`MomentRule.world`). One reply's are one moment, at most 3 an hour; at night they wait for the morning (`WorldGestures`) | ping, notification | `world` |
| region | Where a buddy is, from its UTC offset only: the Americas, Europe and Africa, Asia and Oceania | country, location | `from_region` |

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
  to the brain: only readings, and your words to Boop. An agent's card
  goes to the screen and the transcript, never to the brain.
- Your hands and what else Boop notices of you at the Mac reach the board
  as tags and `ptr` and nothing else (`Hands`, `Along`): that you type,
  scroll, copy or listen, never what, with no event, nothing in the
  transcript and nothing for the brain, the world or the daily counts.
- The world gets only `World.State`'s fields (`WorldTests` pins them): the
  buddy's name and level, its UTC offset, one of six activities and
  counts. Nothing before onboarding's world screen, nothing with it off.
- "Needs you" and the screen priority are plain rules in the core.
- Jev is asked only where it earns its place: a Moment's move and size,
  and the whole Moment at your lock or unlock, a working check-in and a
  boop from the world, are plain rules in one place (`MomentRule`), and
  so is which one thing an idle check-in may hold up (`IdleBeat`).
- The device renders, reports and decides when a Moment plays, never what
  Boop does.
- The Mac's face is the board's firmware: a change to what the gel draws
  rebuilds the mirror (`firmware/tools/mirror.sh`).

## The UI's words

Every string a person reads, on the Mac or the board: short and warm, with
no numbers that aren't needed. Talk like a friend, not a manual: "82
today. Fill the ring and you're done for the day," not "A full ring is
100. More doesn't count." No game jargon, no exclamation spam.

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
| `internal/world/`, its routes, limits or wire fixtures | `internal/world/README.md`; the Mac's `app/BoopKit/World/` with them |
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
