# Simplifying Boop: the audit (updated 2026-11-01)

Boop grew by trying things, and the owner no longer holds all of it in
their head. This file is what an audit of the whole product found on
2026-11-01: how Boop works on one page, every concept it has, and what
can go or merge, ranked by how much understanding each change buys for
its risk. It replaces the plan of 2026-10-25, of which only one item
(one "how big" question, `react.intensity`) was built; its other items
are folded in below, corrected where the code proved them wrong.

Five read-only reviews ran against `main` at 085a7579: the brain
pipeline, the character pack and steering, the board and the wire, the
Mac app and the tools, and a map of every concept. Each checked its
claims with grep and the code. Where a doc and the code disagree, the
code wins (the drift is listed at the end). The dreaming work
([dreaming.md](dreaming.md), being built on branch `dreaming`) is taken
as given: nothing here re-proposes it.

## How Boop works, on one page

One ordinary moment: Claude finishes a turn on "api".

1. **The hook.** Claude Code's Stop hook runs `agent-hook`, which writes
   one JSON line to Boop's socket and never waits.
2. **Intake.** The Mac reads the agent's last message into a reading
   (its kind, tone, length and up to three short phrases) and throws
   the words away. The finish and the reading are appended to today's
   transcript file.
3. **The rules, at once.** The core updates the sessions and sends the
   board a new `state`: the look (idle), the mood, the counts, the to-do
   list and the tags. The work stream sends its own word for the finish
   too ("done", gathered).
4. **The view.** `TranscriptView` writes the event as a sentence for the
   brain, counts runs (quick wins, failing checks), and decides whether
   it wakes the brain.
5. **The brain, later.** Jev reads the prompt and answers every question
   in one request: the mood, the face, the move, the size, what Boop
   says, and sometimes a sign. All multiple choice.
6. **The outputs.** The mood output keeps or moves the mood. The react
   output applies its code rules (quiet, hush, needs you), picks a
   recorded take, and sends a `do` to the board.
7. **The board.** LinkKit's queue plays it when the reaction before it
   ends. The board picks the design's variation, sizes the finish by the
   turn's length, plays the take, marks whose turn it was, and reports
   `ended`.

**Where decisions are made:** agent-hooks (which hooks count, needs
you), the prompt reader (readings), the core (the look, needs you, the
tags, the tiers, hush, the rule reactions, BOOT's line, the drawer), the
work stream (which word plays), the view (lines, runs, what wakes the
brain, the heartbeats), Jev (mood and every brain reaction), the react
output's code (silences, signs offered, takes), the board (the queue,
variations, pastimes, what a touch is), and the pack (the mood graph's
prose, every look and sound).

## The concepts, counted

| | Concepts |
| --- | --- |
| Today | 79 |
| After the dreaming plan lands | about 92 (it adds the reason, CONTEXT, memory, the dream, asks; removes the diary and the popover's dressing) |
| If this audit's merges are taken | about 30 |

**The smaller vocabulary.** Each new concept absorbs old ones; the
right column is the only behaviour that changes.

| Concept | Absorbs | Changes |
| --- | --- | --- |
| Agent | agent, session or thread, session gone | Nothing |
| Turn | turn, outcome, tool call, helper, to-do, working stretch | Nothing |
| Needs you | request, dismiss, the line, BOOT's hand-off, the needs-you screen | Nothing |
| You | readings, presence, pokes, gestures, push-to-talk, face down | Nothing |
| Transcript | event, line, HISTORY and NOW, wake and hold, runs | Nothing |
| Check-in | the working check-in, the idle check-in, the hourly heartbeat | The hourly heartbeat goes (C4) |
| Look | base, activity, asleep, needs-you, no app | Nothing |
| Tag | special days, part of day, tier, stage, `reading`, `hushed`, busy and frantic | The Mac makes busy and frantic (A-board) |
| Tier | the tiers and the doze-off timing | Asleep reads as the last idle tier; same times |
| Dressing (the board's side) | occasion designs, pastimes, the kit, outfits, pace | Nothing, or one dealer (C8) |
| Reaction | the brain's, the rules', the board's own, the stream's word forward, the queue, variations, loops | Two rule cards go (C5) |
| Work stream | lanes, words, gags, combos, the bonk ladder | Nothing |
| Mood | mood and face (one list of 42), the graph, fades | Fades on time (C4); boilerplate moods face-only (C3) |
| Move | `react.move`, reply, wake up, notice, outcome | Computed in code outside push-to-talk (C6) |
| Size | intensity, loops, the take's size | Nothing |
| Say | feeling, topic, swear, take, lead sound, reply words | Nothing |
| Sign | prompt signs, replies, status, the dream's sign, asks, musings | Nothing beyond dreaming |
| Reason | the Mac's narration, the popover's "why" | Per dreaming |
| Talk | quiet, normal, chatty, and hush as "silent for N min" | The hush button joins the Talk control |
| Personality | the personality, its temperament | The picker goes (A1) |
| Growth | XP, stages, the daily caps | Nothing |
| Memory | the dream, `memory.md`, MEMORY, the reader, the ask record, `long-term.md` | Per dreaming |
| Prompt | Jev, a pass, the sections, CONTEXT | Nothing beyond dreaming |
| Drawer | the drawer, its list, `show: drawer` | Nothing, or no scrolling (B8) |
| Pack | steering, the rig, the gel's internals, the mirror, demos, sounds | Nothing |

## A. Safe, invisible: do any time

Each removes code or data that nothing reaches, or a value that is the
same everywhere. None changes what plays, and none needs a Jev run
beyond the usual checks.

**The Mac and the brain**
1. **Personality as a choice.** Every pack has exactly one personality
   (`boop.md`, `pixel.md`, `bro.md`), and the Settings picker only shows
   for more than one. Drop the list, `about`, `allCases`,
   `setPersonality`, the setting, the picker and headless
   `--personality`; each pack has one `steering/personality.md`, whose
   front matter stays. About 120 lines, pack first.
2. **`tool_uses: all`.** All three packs say `notable`. Drop the key,
   its enum, `EventLine.routine` and the `allToolEnds` path. About 40
   lines.
3. **`eval --to-demo`** (`DemoFromScenario`): nothing calls it. About
   160 lines.
4. **Headless `--labeler`** has no caller; `boopdev eval --labeler`
   covers it.
5. **Small dead bits:** `idleBeatMs`'s nil path (make it required),
   `wakesWhileNeeded` (a set of one), the `nature/` note in PackCheck,
   the `[words]` sign tag (a `{words}` line yields nothing without
   phrases), and `CharacterPack.Mood.family` in Swift (read nowhere;
   families are the studio's).
6. **The 212 `attention` takes** in SlimeBuddy's `takes.tsv`, which
   nothing plays ("Boop never says them"). Pack data; frees card space.

**The pack**
7. **`uses` and `shares`,** one pack borrowing another's files: no pack
   uses it, a test asserts none does, and the packs copy instead. About
   120 lines of code and tests, and a section of CHARACTER.md.
8. **Two pack checkers.** `charactergen.py --check` and `PackCheck`
   both check the moods and moves. Keep PackCheck as "the pack plays"
   and charactergen as "the pack builds", and drop the overlap.

**The board and the wire**
9. **Dead names and paths:** the `error` do (the Mac never sends it;
   it keeps a scene state, a recipe row in 42 profiles, a contact kind
   and props), the gel `Router`'s stop, expiry, overlay and dedupe
   paths, `GelFace::pick`'s gesture branch, `Kit::cut` (only its own
   test calls it), and the rig's `blink.json` (the gel blinks itself).
   `dbg.look` replies `ok:false` on the gel. The earlier plan listed
   `rig::Layer::kScene` as dead: it isn't, the sun and night sky use it.
10. **`default_envs = amoled206`.** The default build is still the
    frozen CYD.
11. **One loop cap.** "At most 6" lives in three places, and the brain
    asks for 1 to 4. One constant.
12. **Tags no board reads:** `weekend`, `friday13`, `piday`,
    `aprilfools`, `may4`, `buddy`, `pal`, `chonk`, `legend` go to the
    board and nothing there reads them. Keep them Mac-side for signs and
    the brain; free 9 bits of the wire's 32.
13. **`hello.face` as a capability flag.** It decides the popover's
    face and onboarding's tour, and it is wrong for Pixel Bro, which
    says `pixel` on the AMOLED. Decide by what the board does; keep
    `face` for logs. Merge `pack` and `pack_version` into one field.
14. **The 76.8 KB canvas** is allocated even when the face is the gel,
    which draws natively. Allocate it only for a pixel face (check
    whether it lands in PSRAM first).

**Tools**
15. **`internal/tools/fluid`** measures what the Studio's Transitions
    view measures. Delete it.
16. **Evals that spend Jev on code rules.** `53`, `68` and `69` check
    that the mood stays on the graph, which code guarantees; `92`, `93`,
    `115`, `116`, `117` check Mac rules with no brain expectation. Move
    them to `--scripted` or unit tests. Merge the duplicate clusters
    (giving up 42 into 27; pokes 05, 49, 16, 23, 78; talking 35, 37, 38
    into 126; routine turns 01, 14, 83, 120; long turns 02, 29, 41), and
    renumber the second `100`. About 10 files.

## B. The owner's calls: the biggest concept wins

**Decided 2026-11-01:** A is agreed, all of it. B1 (several buddies)
stays: it will be a production feature. B2 (the CYD) stays for now. B3
(real-agent demo venues) stays: the scenarios will grow. B4 (`workday`)
goes. B5 to B10, C and D were decided after an explanation: see
Decisions, below. Nothing here is built by this file's thread: each
yes is handed to a building thread.

Each is invisible to buyers or nearly so, but takes away a lot to
understand. Each needs a yes.

1. **Several buddies.** *(Decided: keep; it will be a production feature.)* Several boards, each with its pack, place, core
   and brain voice, on one transcript, hearing and answering each other.
   It costs about 600 lines in about 28 files, six concepts, and
   MellowHarness's voices; it buys one demo (`not-my-turn`) and has no
   Settings UI. **Recommended: remove,** after the dreaming branch lands
   (it adds per-buddy closures in the same file). One buddy, hard-wired;
   old transcripts' `buddy` key ignored.
2. **Retire the CYD board from the engine.** *(Decided: not yet.)* Its env, folder, touch
   calibration (`touch_cal.h`, NVS, `dbg.touchcal`, `boopctl
   calibrate`), the LED, the CI build and the flash script's port
   detection: about 600 lines and two concepts. **The pixel face stays:**
   Pixel Bro draws it on the AMOLED. PixelBuddy then either moves to the
   AMOLED, as Bro did, or leaves `packs.json`.
3. **Real-agent demo venues** *(decided: keep; the scenarios will grow)* (`make demo IN=…`, `internal/tools/session`,
   `internal/sessions/`): about 2,100 lines, and all five projects are
   Pixel demos, so no gel demo can use them. Retire, unless real-agent
   footage is still wanted for marketing (then it needs a gel project).
4. **`boopctl workday`** *(decided: remove),* a second brain harness beside the evals
   (about 1,400 lines), which no target or CI step runs. It is the only
   long-run "is Boop too chatty" check: fold its limits into one long
   eval scenario, or retire it.
5. **Three ways to make the simulator Boop's body** in the app (a
   polled browser sim, `make dev SIM=1`, the internal build's window).
   Keep the window: about 200 lines and three small state enums go.
6. **Onboarding from 8 acts to 6.** *(Decided: no.)* Merge the two static intro acts,
   and fold "small things" (login, mic, key) into the finale.
7. **The mirror's upkeep.** It stays (the real gel on the Mac), but its
   byte-exact check in every drawing commit pins Emscripten's version
   and makes every art change rebuild 3.4 MB. Rebuild it at release,
   and say "close to the board": it seeds its own dice, so it deals
   different pastimes than the board shows.
8. **The drawer's scrolling.** Seven timers, about 170 lines and three
   wire fields, for more than six sessions. Without it: six rows and
   "+N".
9. **Two text channels for one reaction.** A take's words show in a
   bubble while a sign shows held-up words, both at once. Pick one (for
   example, the take's words as the sign when there is no sign). This is
   visible.
10. **One Studio server,** `serve.py`, absorbing `serve.cjs`'s review
    and captures.

## C. Brain and board changes: gated by evals and goldens

These change what Jev reads or what the gel deals, so each runs the
evals before and after (and the gel's goldens where the board changes).

1. **One mood graph.** "Where a mood can move" is written four times
   and they disagree: `character.json`'s moves (copied byte for byte in
   all three packs), the gel's design graph (`emotion-graph.json`, baked
   into the board's `kEdges`, which picks each transition), and each mood
   file's prose. The board's copy lacks 46 edges the brain uses, among
   them calm to happy and happy to calm, so they play the plain "no
   edge" transition. Write the graph once, **in the pack's
   `character.json`** (decided: the graph is each character's own, even
   where today's packs agree), generate the board's edges from it at
   staging, and delete the design graph's edges and drafts. The board's
   transition table holds at most 8 edges a mood (calm and bored are
   full), so the one graph respects that cap or the board's table grows;
   the build decides with the goldens. The 46 transitions get their proper
   animation.
2. **`meaning` owned by the pack, in plain words.** A mood's meaning is
   Jev's option text, but slimegen overwrites it from the design file
   and a test pins them equal, so design notes reach Jev ("display label
   Hurt, stable legacy ID wounded", in most passes). It also breaks the
   dreaming plan's edit to lonely's meaning (the other thread has been
   told). Make it the pack's, plain, and drop slimegen's ownership and
   the test.
3. **Boilerplate moods become face-only.** 14 mood files carry the same
   five generic sentences, and real use settles into about 15 of the 42
   moods while faces use all 42 (26 played in two days). Keep all 42
   faces; remove the graph edges into the boilerplate moods (lonely is
   being written for real), and delete their files. Boop never sits for
   minutes in, say, speechless, which it almost never does today.
4. **Fades in code; then the hourly heartbeat goes.** 37 mood files
   end "Fades to X once Boop has been Y for N min", which Jev has to
   notice. Give each mood `fades: {to, after_min}` and let the mood
   output move it on the core's tick; drop the fade prose. The hourly
   heartbeat exists mainly so Jev notices a fade in a long quiet, so it
   goes with it. Fades come on time.
5. **The rule cards for a stopped turn and a returning helper.**
   (Corrected 2026-11-01: an ordinary finish is not shown five ways.)
   A finish that names its thread, as every brain finish of a turn does,
   shows the brain's finish (sized by the turn: a hop up to Mega Boop),
   the ticket and rim glow, the strip's tick, and the work stream's word
   if it's on; a success shows its trophy. The engine's card
   ("FINISHED", "FAILED") shows only for a finish that names no thread
   and isn't a success: in practice the `stopped` rule's reaction. What
   repeats: a stopped turn gets the `stopped` rule's card, the stream's
   dropped word and the brain's reaction; a returning helper gets the
   `helper_return` rule's reaction, the stream's "back" word and the
   brain's topic. Proposal: drop those two rule reactions (the stream and
   the brain cover both moments), and with them the card, which then has
   nothing left to show.
6. **The move in code, outside push-to-talk.** Jev picks success,
   failure, reply, wake up or notice each pass, but the options spell out
   a fixed mapping from the line's facts (the outcome, the message's
   kind, the away band, your prompt naming Boop). Compute it; keep
   `react.move` for replies only; April Fools' becomes one code rule or
   goes. One question fewer on every pass.
7. **The poke hold: five pieces for one rule.** "One brain reaction per
   poke run" holds a tap-cut reaction open across three files and a
   MellowHarness API (`keepOpen`). Make it: a run already answered, and
   the mood unchanged. About 90 lines, and `keepOpen` can leave
   MellowHarness.
8. **One pastime dealer.** Five dealers decide what the gel does while
   a look shows (idle gags, idle occasions, look occasions, `looks.json`
   occasions and tier clips, pastimes), each with its own gate and dice.
   Keep the kit and outfits (state, not events); turn the other
   occasions into rows of the one pastime table. The shuffle order
   changes; the goldens change.
9. **The gel's Router becomes a plain struct.** What is left of the
   engine timing its own moments (string request ids, a 64-deep resume
   history) now sits under Behaviour, which times every reaction. About
   150 lines; key scenes by the reaction's number.
10. **Mood families' and jumps' extra texts.** After C1, the ordinary
    versus dramatic split buys one appended sentence whose trigger list
    repeats the guide and the mood files. Fold it into the prose's "at
    once when…", or keep it; cheap either way.

## D. One word for one idea

Renames in code and docs only; the wire's keys and the art's tags keep
their names.

| Word | Its meanings today | Proposal |
| --- | --- | --- |
| talk | the Talk setting; push-to-talk (`Core.Talk`, the `.talk` event, the "Talk" button) | `Core.Listening` and "said" for push-to-talk |
| move | the graph's `moves`; `react.move`; the gel's three body moves | "neighbours" for the graph |
| hold | the view's wake gate; the activity minimum; the stream's `holdMs`; the poke hold; the board's `held` | `showMs` for the stream; the poke hold goes (C7) |
| busy | a count, a tag, a queue state, a skip reason | "working" for the count in code |
| gag | a stream word's gag; the gel's idle comedy | "bit" for the gel's |
| moment | the Words table bans it for a reaction; code uses it for an event's size | "size" in code |
| wiggle | a poke, recorded by its older name, in HISTORY's wording | "poke" (changes what Jev reads) |

## Decisions (2026-11-01)

The owner's answer to each item. "Yes" means it goes to a building
thread, not that it's built.

| Item | Decision |
| --- | --- |
| A, all | Yes, in the commits under "A, in commits" below |
| B1 Several buddies | Keep |
| B2 Retire the CYD | Not yet |
| B3 Real-agent demo venues | Keep |
| B4 `workday` | Yes, remove |
| B5 The simulator as the app's body | Yes, one path (below) |
| B6 Onboarding | No change |
| B7 The mirror's upkeep | Keep as it is |
| B8 The drawer's scrolling | Keep as it is |
| B9 The bubble beside the sign | Keep both |
| B10 One Studio server | Yes |
| C1 One mood graph | Yes, owned by the pack, over the 16 lasting moods |
| C2 `meaning` owned by the pack | Yes |
| C3 Lasting moods | Yes: 16 lasting moods, all 42 faces (below) |
| C4 Fades in code, no hourly heartbeat | No: keep the heartbeat and the prose fades |
| C5 The two rule cards | Yes: drop `stopped` and `helper_return` and the card |
| C6 The move in code | No: keep it in Jev |
| C7 The poke hold | No |
| C8 One pastime dealer | Yes, built together with C9 (the gel Router), since both are the same part of the engine |
| C9 The gel Router as a plain struct | Yes |
| A8 The two pack checkers | Yes, the agent's call (the owner left it to it): `boopdev check` owns whether a pack plays, the moods and the graph included, read as the app loads them; `charactergen.py --check` keeps only whether it builds, and stops reading the mood list out of Swift source |
| Counted memory (rows per day, traits) | Skipped for now: too complicated |
| E1 The docs and plans | Yes (below) |
| E4 The pixel face's spec and a second eval prune | Yes (below) |
| E2a Away and back, paired twice | Yes, as one shared piece of code: the view and the memory reader each keep their own result, since the view must stay rebuildable from the log's last 24 hours and the reader must last across days; no event, line or CONTEXT row changes |
| E2b Growth's daily totals | Yes: growth reads them from the memory reader's tallies |
| E3a Hush folds into Talk | Yes (below) |
| E3b The calendar moves into CONTEXT | Yes (below); one full eval run, asked of the owner first |
| C8's idle cleanup | Yes (below) |
| The six evals failing on `main` | Yes, a separate cleanup (below) |
| C10 Ordinary versus dramatic | Not now |
| D, all renames | Yes |

**B5, decided.** The simulator is Boop's body in one way: run the app's
debug build and turn the simulator on inside the app (its board window,
today the internal build's only). The other supported place is `make
demo`, which plays on a real board or on the simulator page. Removed:
the app's polling for a browser simulator and its "Use it" toggle,
`make dev SIM=1` opening a browser tab, the `--simulator` flag, and the
three small simulator states in the app (one on/off remains). The
browser page and its USB-cable server stay for the tools (`boopctl
sim`, the Studio, `Boop --headless --link usb:…`), which aren't the
app's body. Onboarding's "my body" act and Settings' Device rows say
"the simulator window" where they say "your browser".

**C3, decided: 16 lasting moods, 42 faces.** Boop keeps all 42 faces:
the face question offers every one, with its art, voice and `face` text,
so a reaction can still be mischievous, affectionate or skeptical. But
Boop settles only into 16 lasting moods: the 15 it settled into in real
use, which every eval that requires a lasting mood also names, plus
lonely, the absence feature.

| Settled | Low or cross | Busy or alert | Missing you |
| --- | --- | --- | --- |
| calm, comfy, lazy, happy, proud | annoyed, irritated, grumpy, sad, wounded | engaged, curious, surprised, determined, excited | lonely |

- **The graph** (C1, in the pack's `character.json`) has these 16 nodes.
  Every move into one of the other 26 points instead at the nearest of
  the 16: crying, disappointed and whiny to sad; frightened, scared,
  uneasy and uncomfortable to annoyed or surprised as the trigger fits;
  speechless and stunned to surprised; relieved, pleased and hopeful to
  happy; shy, embarrassed and affectionate to comfy; exhausted and tired
  to lazy; bored to lazy; angry to grumpy; overwhelmed to engaged;
  skeptical, disgusted and baffled to annoyed; amused and mischievous to
  happy; confused to curious. Lonely is reached from calm, comfy and
  lazy.
- **26 mood files go,** the 14 boilerplate ones included, and the 16
  that stay have their "Leaves for…" prose rewritten to name only the
  16. `character.json` keeps an entry for all 42 (each face's text and
  art), and only the 16 have moves and a `meaning`.
- **The mood question** offers only the 16, and so is shorter on every
  pass.
- **Evals** that start in or require one of the 26 as a lasting mood
  (68 starts in frightened) are rewritten; permissive face lists stay.
- **Gate:** one full Jev eval run, before and after.

**C8's idle cleanup, decided.** While the pastimes become one table, the
gel's idle behaviour loses its near-duplicates, with no new art:
- **Naps:** keep snooze (idle, the last tier); drop nod-off (the same
  moment) and doze-and-snap (a general gag that repeats it). Keep
  night-drowse as the asleep look's night variant.
- **Stretches:** keep stretch-break (long work) and morning-stretch
  (tied to the morning); drop the rig's tier-4 stretch clip.
- **Yawns:** keep yawn-and-settle, and long-yawn as tired's own.
- **Dreams:** keep the asleep dream after 30 minutes; rename the idle
  pastime "dream" to "daydream", so "dream" means the night's dream,
  which the morning telling refers to.
- **Fly:** remove it, as an earlier session decided (the docs already
  say it's gone; the code still deals it).

**The six evals failing on `main`** (01, 11, 14, 29, 98, 110, found
by the dreaming build) are their own cleanup: each fixed in the
steering or the eval, so a failure always means a regression.

**E1, the docs and plans, decided.** For an owner who no longer holds
all of Boop in their head, the docs say how it works, short, and the
plans hold only what's next:
- **Finished plans go** (git keeps them): updated-behavior, glance-and-wait,
  calm-work, talk-back, work-stream, character-engine, dreaming,
  dreaming-memory and this file, once each is built; `plan/evidence/`.
  Anything in them not built moves to TODO.md or product-ideas.md first.
- **What stays in `plan/`:** TODO.md (pruned of done items),
  product-ideas.md (brought up to date with the decisions), voice-range.md
  (an unfinished draft). new-character-playbook.md moves to
  `characters/`, since it's a how-to, not a plan.
- **architecture.html opens with "How Boop works, on one page"** (this
  file's, updated for what's built), then the prompt's sections, memory,
  the reason and asks, and keeps "Where the pieces join".
- **CLAUDE.md:** the Words table gains the new words and loses the gone
  ones; the plan row lists only what stays; long passages that repeat
  another doc point to it instead.
- **CHARACTER.md** loses what no pack does any more (the TALK files, the
  diary, the personality list, borrowing), and anything that repeats the
  code.

**E4, decided.** The pixel face's spec (styles, `wears`, `kWears`,
`mac/faces.json`, its palette; about 90 lines of CHARACTER.md) moves to
the pixel face's own README, and the palette becomes the face's own,
not a contract rule. A second eval prune: an eval whose accepted faces
or moods are so many it checks little (40, 121 and others) is tightened
to what the scenario means, or removed.

**E3a, decided: hush is a Talk level.** Talk has four levels: quiet,
normal, chatty, and silent for N minutes, which drops back to the level
it was when the time runs out. Saying "shh" to Boop, the popover's Hush
button and the hush reply all set it; CONTEXT's Talk row says it
("Talk: silent for 8 more min"), and the Boop row stops carrying the
hush. Code holds silent as it holds hush today: Boop says nothing, its
faces go on. One concept goes: the hush as its own setting.

**E3b, decided: the calendar is in CONTEXT.** NOW's heading keeps only
what's about this event ("Boop reacted 1 min ago"); the time, the
weekday, the part of the day and any special day become CONTEXT's first
row ("When: 09:02, Saturday, morning; Halloween"). The mood's duration
stays HISTORY's closing line, as decided. The personality's Examples
that quote the heading's calendar ("NOW (09:02, Saturday, Halloween)")
quote CONTEXT's row instead, and their evals change with them. Gate: one
full eval run, asked of the owner first.

**A, in commits.** Each is small, invisible, and checked by `make -C
internal check`:
1. **Pack contract leftovers:** personality as a choice (A1),
   `tool_uses` (A2), `uses`/`shares` (A7), the two checkers' overlap
   (A8), `family` in Swift, the `nature/` note and the `[words]` tag
   (A5). Pack side first, after the dreaming branch merges, since it
   edits the same files.
2. **Dead code in the app and tools:** `eval --to-demo` (A3), headless
   `--labeler` (A4), `idleBeatMs`'s nil path and `wakesWhileNeeded`
   (A5), `fluid` (A15), and `workday` (B4).
3. **The board:** the `error` do and the gel's dead paths (A9),
   `default_envs = amoled206` (A10), one loop cap (A11), the canvas
   only for a pixel face (A14), the gel's `dbg.look` reply.
4. **The wire:** tags no board reads stay Mac-side (A12); `hello.face`
   no longer a capability, `pack` and `pack_version` one field (A13).
   Record every demo again.
5. **Pack data and evals:** the `attention` takes (A6), the eval
   duplicates and code-rule evals (A16).

## For the dreaming build

Passed on to the thread building it, or to do when it lands:

- **Four keepers of "away"** (the presence detector, the view, the new
  `presence.away_since`, the memory reader) and three of "which turns
  are working". Let the reader ask the view and the core, not fold
  again.
- **Growth's daily caps** should read the memory reader's tallies, not
  count events a second time.
- **The dreaming branch's mood cues** (`cueNames`, `only_when`) duplicate
  CONTEXT's facts now that lonely is prompt-only: drop them.
- **Two first-of-day rituals:** the core's occasion greeting and the
  dream's telling. The plan gives the first wake one owner; build it
  that way.
- **The question texts** still say "TALK, if there is one" in four
  places in `ReactOutput`; rewrite them with the TALK section's removal.

## What earns its place

The audit looked hard at these and would keep them:

- **The Mac's face-down hold.** The earlier plan said drop it; face down
  can last hours while agents work, and without the hold every event
  costs a Jev request.
- **The duplicated tap-run and listen numbers.** Parity tests pin both
  sides, and the Mac's listen timer guards the app's own mic button with
  no board. Moving them to the board needs a protocol change for little.
  (The earlier plan's "the Mac owns who's in line" is already true:
  `state.idle` counts the line.)
- **Two session trackers** (the core and the view): the view must stay a
  pure function of the log, for replays and evals.
- **LinkKit's queue and lifecycle,** `Behaviour` as a function of the
  clock, and the hosted board shared by the simulator, the mirror and
  the tests.
- **42 faces, the graph as an idea, the mood files with real reasons,
  `face_not_for`, `TaggedLine`, the budgets, `startup_mood` and
  `default_mood`.**
- **The work stream's split** (lanes in `state`, the word forward as a
  `do`), the kit and outfits, the finish sizes by tier, the drawer's
  open and closed handshake (the 512-byte limit forces it).
- **boopctl and boopdev** (a real language split), demo scripts and eval
  scenarios as two formats, `Boop --snapshots`, the recordings checked
  in, the Studio.

## Drift found

- The guide says Boop does nothing on its own; the core still plays
  `starting`, `stopped`, `helper_return`, the day's greeting and a
  stage's celebration, and the stream marks every finish.
- The dreaming plan counts 12 template mood files; there are 14.
- The Words table fixes "talk" and bans "moment"; the code uses both
  otherwise (D).
- CHARACTER.md §9 calls `waiting` a slow tool; it also shows for a Codex
  request in its grace period. §15 says Boop's rig blinks; the gel
  blinks itself.
- `behaviour.h`'s refuse reasons lack `facedown`; its BOOT comment says
  a hand-off plays over needs you, and nothing does.
- `GrowthStore`'s comment says the transcript restarts its numbering
  after two weeks away; the newest file is always read, so it doesn't.
- The design's `MOODS.md` shows the board's stale graph.

## Order

1. **A, any time,** in small commits, pack side first where a pack
   changes. Nothing to decide.
2. **B's yes or no from the owner,** then the ones taken, after the
   dreaming branch lands (several buddies especially).
3. **C, one at a time, each gated by the evals** (`make eval` before and
   after, `--only` on the scenarios it touches first) and, on the board,
   the goldens. C2 first, before the dreaming build's lonely step.
4. **D** with whichever change touches the file anyway.
