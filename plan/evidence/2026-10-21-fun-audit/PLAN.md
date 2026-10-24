# Fun plan, second pass: the simplest core that can be fun (2026-10-21)

The audit is [README.md](README.md). This pass re-cuts the first one for
the owner's rule: **the core stays simple and stable; tune through pack
content, steering, new events and lines, and animations; add machinery
only when nothing else can carry it.** Fewer mechanisms, one pattern
reused everywhere, and an explicit list of what is not being built.
Each item is a brief a subagent can take alone.

## What changed from the first pass

- **Variety no longer lives in `react`.** The echo rule, the off die, the
  kind bump, the `last` state and the `varied` facts are gone. Instead
  the view counts (quick wins in a row, check-ins on a turn) and says so
  on the line, and the steering answers each rung differently: the
  pattern pokes already use (`You poked Boop 4 times in a row.`). A few
  lines of view code and some Examples; no hidden state in an output.
- **Wrong on purpose moves to where the randomness is born.** Ears
  mishears one command in five and records it in the event
  (`misheard: true`); the line says so and the steering decides what a
  misheard "dance" does. No `mischief` table in `character.json`, no die
  in `react`.
- **The idle check-in is the idle heartbeat with a shorter period** for
  the first two hours, not a fourth heartbeat kind.
- **The check-in's topic joins the counted line** (R4) instead of being
  an item of its own.
- **Bigger says for long holds** (a `Voice` change) is dropped to Not
  now: the hold and the kind already carry loudness.
- Every item opens with its architecture change in one sentence and the
  pattern it reuses.

## 0. The rule, made concrete

Five patterns, each already in the engine, each reused several times.
Nothing in the plan is a sixth.

| Pattern | Already proven by | Reused by |
| --- | --- | --- |
| **P1 Pack content plays itself.** A new variation of a look or a finish, with a sound policy on its timeline, shows with no Mac change: the pixel face turns a look's variation at loop end (`PixelFace::kTurnPct`), both faces pick a finish's variation never-the-last, the gel plays a performance per mood every 7–15 s | The three idle designs, the four trophy designs | R6, R7 |
| **P2 The line carries the count, the steering carries the ladder.** The view counts a run and writes it on the line; the personality's Examples answer each rung | `You poked Boop 4 times in a row.`, `answersRunFrom`; last night: a second barrage read as fresh until the line said `, again` | R2 (optional), R4, R5 |
| **P3 A new thing is one new raw event with one line.** A kind, a line with facts, a wake; the harness and the brain never change | `talk`, `presence`, `poke` | R5, R8 |
| **P4 Randomness is born at the source and recorded.** The view is a pure function of the log; what's random is decided before the event is logged, and the event says so | `Core.pickVariant` records `variant`; `ReactOutput.takes` | R8 |
| **P5 Evals pin the ladder.** Every rung has a scenario step with its count, and the whole-run checks hold variety | `05`, `16`, `23` | R9 |

**What the plan never touches:** the core's rules (`Core.swift`), the
harness, the questions Jev is asked, the protocol and the device's
queue, "needs you", the output contracts. No rule chooses a face or a
word. No new state unless R10 is chosen. No new timer in the core.

| Layer | Touched by |
| --- | --- |
| Core | none |
| Harness, brain, questions, protocol, queue | none |
| `ReactOutput`, `Voice` | none |
| View (`TranscriptView`, `EventLine`, `Personality.Rules`) | R4 (two counts, two line forms), R5 (four lines, one front-matter key), R8 (one event kind, one line) |
| Steering (`characters/*/steering/`) | R1, R2, R3, R4, R5, R8 |
| `character.json` | R1 (`face` text for 29 moods) |
| Pack art and sound | R6, R7 |
| New component | R8 (`app/Boop/Ears.swift`, which only writes events) |
| Evals, working day, demos | R2, R3, R4, R5, R8, R9 |

**For every subagent.** Start from the latest `main` (`git log
--oneline HEAD..main` prints nothing). Read CLAUDE.md's "Docs stay in
sync" table and update the doc in the same commit. Pin every number in
a test. Run only the evals the brief names, `--runs 1`, with
`BOOP_JEV_KEY` from the owner; `boopdev eval --list` prices a scenario
without a key, and `boopdev eval` stops over 100 requests unless
`--budget` says otherwise. Don't run `make eval` (660 requests). The
evals live in Boop's pack and run on the pack in use; each item says
what Pixel gets. Boop's Examples are written `NOW: … → face, animation,
feeling in a kind, then topic, hold`; Pixel's as prose. Keep each pack's
style.

## R1. Room in the steering, and real words for the 29 slime moods

**Issue.** The guide is at 300/300 tokens, `boop.md` at 729/750 and
`engaged.md` at 175/175, so no Example can be added without cutting one.
And 29 of Boop's 42 moods reach Jev as the slime design's engineering
prose with no `face` text and a boilerplate mood file, so the comic
moods (lazy, bored, mischievous, amused, surprised, stunned, baffled,
embarrassed, disgusted, tired) are never picked.

**Architecture change.** None. One constant and pack content.

**What to do.**

1. `app/BoopKit/Harness/Steering.swift` `Budget`: guide 300 → 400,
   personality 750 → 1000, nature 150 → 250, mood 175 → 225. A request
   is about 3,400 tokens; this adds at most 350. The pins in
   `internal/app/Tests/RuntimeTests.swift` (`overBudget() == []`),
   `CharacterPackTests.swift` and `HarnessTests.swift` (nature) still
   pass.
2. `characters/boop/character.json`: a `face` (and `face_not_for` where
   it helps) for each of the 29 moods without one, in Pixel's plain
   register: `"face": "A lazy face: can't be bothered, but it's getting
   done."`, `"face": "A bored face: nothing to see here."`,
   `"face": "An amused face: that was funny."`. The `meaning` stays the
   design's (`slimegen` writes it from `emotion-graph.json` and keeps
   `face`), or change it there and rerun `node
   characters/boop/tools/slimegen/slimegen.mjs`. `python3
   characters/charactergen.py --check`, `boopdev check` and `slimegen
   --check` stay green.
3. `characters/boop/steering/mood/{lazy,bored,mischievous,amused,
   surprised,stunned,baffled,embarrassed,disgusted,tired}.md`, each in
   `grumpy.md`'s shape: what its faces lean to, what it says, what it
   stays through, what it leaves for (only moves the graph has), when it
   fades. `bored.md` for example: "Bored. Nothing has happened for a
   while, or the same thing keeps happening. Its faces lean bored and
   lazy; a win gets a pleased face. Says quiet in a sound. Stays bored
   through check-ins and quick wins. Leaves for curious at a poke or
   anything new; calm when work starts; excited at a big win. Fades to
   calm once Boop has been bored for 10 min."
4. `characters/pixel/steering/mood/*.md`: the same shape, three to five
   lines each, for all 42.

**Specs.** `characters/CHARACTER.md` §7 if it quotes a budget;
"Updated" dates.

**Untouched.** The questions, the mood graph and its moves, every other
mood file.

**Tests and evals.** The budget tests. `17-never-the-wrong-face`,
`47-recovery-walk`, `53-busy-day-on-the-graph` once each (~45 requests)
to check the new face texts don't pull Jev off the graph or onto a wrong
face. The comic moods get their own scenarios in R4 and R5.

**Done when** `overBudget()` is empty in both packs, `boopdev check`
passes, the three scenarios pass once, and `boopdev eval --list` prints
unchanged counts.

**Depends on** nothing. First: R2, R3, R4, R5 and R8 add text.

**Per pack.** Boop: the budgets (engine) and all of the above. Pixel:
the mood files; its `character.json` already has plain meanings and
faces.

## R2. The cuss, and a ladder of failure

**Issue.** A failed turn is one hold of an irritated face with "upset or
nothing"; the swear is kept for a stinging failure that was already
grumpy (60). Nothing escalates: a second failure in a turn, a failure
after a fix, a failure after a barrage. "Loud is better" means pulling
the two levers the steering has, the hold and the kind.

**Architecture change.** None: steering and evals. If Jev can't climb
the ladder from HISTORY alone (the eval below decides), one count joins
the finish line by P2, the same change as R4's.

**What to do.**

1. Boop's Examples (`characters/boop/steering/personality/boop.md`;
   R1 makes room):
   - `NOW: claude finished turn 5 on "api": failed, a long turn, 15
     tool calls.` → `irritated, failure, upset in a phrase, twice`.
   - `NOW: claude finished turn 6 on "api": failed, a long turn, 15
     tool calls.` after `claude's tests failed on "api".` in the same
     turn → `grumpy, failure, upset in a phrase, three times` ("Not
     again", "Oh, come on").
   - `NOW: claude finished turn 9 on "api": failed, a very long turn,
     40 tool calls.` → `sad, failure, upset in a sound, four times`.
   - `NOW: claude's tests failed on "api".` a second time in a turn →
     `annoyed, upset in a word, then retry, twice` ("Again").
2. `grumpy.md`, `irritated.md`, `annoyed.md` "Says" lines: a phrase at a
   failed turn, a swear when it stings, held longer than the win before
   it. The guide's "held longer for big moments" gains "and a failure
   longer than the win before it".
3. Pixel's `pixel.md`: "A turn fails: an annoyed face held twice for a
   small one, with a huff or a word; a sad face held longer for a big
   one; a swear only when it really stings."
4. Only if `70` (below) fails on the second rung: the finish line says
   how many checks failed this turn, from `Counts.toolsFailed` and
   `failRuns`: `claude finished turn 6 on "api": failed, a long turn,
   15 tool calls, after its tests failed twice.`
   (`EventLine.turnEnd(... failedChecks:)`, facts `failed_checks`).
   P2, one line form, one `ViewTests` case.

**Specs.** `internal/EVALS.md` §4 (the reworded scenarios);
`documentation/architecture.html` only if step 4 lands.

**Untouched.** The questions; Voice (the 18 swear takes exist, on the
failure finish); the device (its failure design plays).

**Tests and evals.** `03-turn-failed`: `react:
grumpy|annoyed|irritated`, `animation: failure`, `kind:
phrase|word|swear`, `said: some`, `loops: twice|three times`.
`08-long-turn-fails`: add `said: some`, `loops: three times|four
times`. `04-tests-fight-back`: the second failure `said: some`, `loops:
once|twice`. New `70-failure-after-fix.json`:

```json
{"steps": [
  {"event": "turn started", "at": "0s"},
  {"event": "command", "at": "1m", "topic": "tests", "failed": true},
  {"event": "command", "at": "2m", "topic": "tests", "failed": false, "reaction": "done"},
  {"event": "turn failed", "at": "3m30s", "error": "api_error",
   "expect": {"react": "grumpy|irritated|whiny", "animation": "failure", "said": "some",
              "loops": "twice|three times|four times", "mood": "grumpy|irritated|annoyed"}}]}
```

Cost: 03 (2), 08 (13), 04 (~6), 70 (~5): about 26. `61-no-swear-at-a-
win` once (~6) as the regression.

**Done when** the four pass once, 61 still passes, and
`characters/boop/demo/the-cuss.jsonl` (and Pixel's) plays in the
simulator: a turn, tests fail, the turn fails, the brain step
`{"react.mood": "grumpy", "react.animation": "failure", "react.loops":
"twice", "say.feeling": "upset", "say.kind": "phrase"}`.

**Depends on** R1 (room). R3 splits the swear by nature.

**Per pack.** Boop: Examples and mood files; the gel plays its
`task_complete` failure recipe, the CYD "The task fell apart". Pixel:
prose, same intent, and the demo.

## R3. Nature in the evals and the Examples

**Issue.** The app always runs with a nature after setup; the evals
never do (`nature: nil`), so every scenario checks a prompt the app
doesn't show. The nature files are prose with no Examples, so cheeky and
sweet differ by adjectives Jev may or may not weigh.

**Architecture change.** None: one runner field and steering.

**What to do.**

1. `internal/app/BoopDevKit/Eval/Eval.swift`: `Scenario.nature:
   LongTerm.Nature`, from the file's `"nature": "sweet" | "cheeky"`
   (default `cheeky`, the owner's; another value fails to load), passed
   to `Runtime.harness(... nature:)`. `boopdev eval --list` prints it
   when it isn't the default. `EvalTests` loads one of each and a bad
   one.
2. `characters/boop/steering/nature/cheeky.md`, two Examples: a failed
   turn → `irritated, failure, upset in a swear, twice`; one poke →
   `mischievous, tickled in a word, once`. `sweet.md`: a failed turn →
   `disappointed, failure, upset in a word, once`; one poke →
   `affectionate, tickled in a sound, once`. Budget 250 after R1.
3. `characters/pixel/steering/nature/*.md`: the same two, in prose.

**Specs.** `internal/EVALS.md` §1 (the prompt has a NATURE section), §3
(the field); `characters/CHARACTER.md` §7 (the files may carry
Examples).

**Untouched.** `Steering.nature`, the memory format, the runtime.

**Tests and evals.** `71-turn-failed-sweet.json` (03's steps with
`"nature": "sweet"`): `react: annoyed|disappointed|sad`, `kind:
sound|word|phrase`, `loops: once|twice`. `72-pokes-sweet.json` (05's
steps, sweet): the first poke `react: happy|curious|affectionate|
pleased`, the third `react: annoyed|irritated`. Cost: 71 (2), 72 (4),
03 and 05 again (6): about 14.

**Done when** both natures pass their files once, `--always --runs 1`
passes with the default, and an eval run's `debug.jsonl` shows the
NATURE section in the state.

**Depends on** R1.

**Per pack.** Engine once; each pack's two nature files.

## R4. The line counts the run, the steering climbs the ladder

**Issue.** Routine work is one face: every quick win is `happy, success,
done in a word, once`, every check-in `engaged, work, twice`, the line
identical each time (A2, B1, B2). Text alone couldn't fix it last
night, and Jev answers the same line the same way at 0.96–0.99. But Jev
answers a *different* line differently, and the view already proves it
with pokes.

**Architecture change.** P2. The view keeps two counts and writes them
on the line: quick wins in a row on a thread, and check-ins on a turn,
with the turn's topic. The personality's Examples answer each rung with
a different face, hold and kind. Nothing changes in `react`, the
harness or the questions. (The first pass's echo rule and dice are in
Not now, with the one die to add if this isn't enough.)

**What to do.**

1. `app/BoopKit/Core/TranscriptView.swift` `Counts`: beside `failRuns`
   (which survives `resetCounts`), add `winRun = 0`, `lastWinAt:
   Int64?`, and per turn `checkIns = 0` (reset in `resetCounts`). In
   `turnEnded`: a finish `done` under 5 minutes is a quick win; if the
   last one was under `winRunGapMs` (10 min) ago, `winRun += 1`, else
   `winRun = 1`; a failed or stopped finish, or a very long one, sets
   `winRun = 0`. In `heartbeat(_:)`'s working branch:
   `fold.counts[s.key].checkIns += 1` before the line.
2. `EventLine.turnEnd(agent:turn:thread:outcome:lengthMs:tools:
   winsInARow:)`: for 2 or more, `, 2 quick wins in a row.`, capped at
   `, 5 or more quick wins in a row.` Facts `wins_in_a_row`.
3. `EventLine.working(agent:thread:ms:topic:)`: `claude is still
   working on "api", a very long turn, running tests.` (`running a
   build`, `deploying`, `editing docs`; nothing for another topic or
   none). The check-in count goes as a note under the line, where the
   prompt and the last message go: `Boop's 2nd check-in on this turn.`,
   capped at `Boop's 4th check-in on this turn, or later.` Facts
   `check_in`, `topic` (already there).
4. `EventLine.words` gains two sentences: "Quick wins in a row are
   turns done in under five minutes with nothing failed between them."
   and "A check-in is Boop looking in on a turn that's still going."
5. `characters/boop/steering/personality/boop.md` Examples (the two
   "still working" Examples become the 1st check-in):
   - `…done, a short turn, 2 tool calls, 2 quick wins in a row.` →
     `pleased, success, glad in a sound, once`
   - `…3 quick wins in a row.` → `excited, success, glad in a phrase,
     twice`
   - `…4 quick wins in a row.` → `amused, success, done in a word, once`
   - `…5 or more quick wins in a row.` → `comfy, success, done in a
     word, once`
   - `claude is still working on "api", a very long turn, running
     tests.` + `Boop's 2nd check-in on this turn.` → `hopeful, work in a
     word, then tests, twice`
   - `…a very long turn.` + `Boop's 3rd check-in on this turn.` →
     `bored, quiet in a sound, once`
   - `…running a build.` + `Boop's 4th check-in on this turn, or
     later.` → `determined, work in a grunt, twice`
   `chatter.md` gets the same rungs louder. The guide adds one line:
   "A run of quick wins or check-ins is a ladder: each rung gets its own
   face, as the Examples show, so Boop never says the same thing three
   times running."
6. Pixel's `pixel.md`, in prose: "Quick wins in a row: pleased, then
   excited by the third, then amused, then cosy and quiet. Check-ins on
   a long turn: engaged, then hopeful about the tests, then bored, then
   determined."

**Specs.** `documentation/architecture.html` "View: sentences for Jev"
(one sentence: the view counts runs and says so, as it does for pokes);
`internal/EVALS.md` §1 (the facts).

**Untouched.** `ReactOutput`, `Voice`, the core, the questions, the
device.

**Tests and evals.** `ViewTests`: the win run counts across turns,
resets on a failure, a stop, a very long turn or a 10-minute gap, and
caps at 5; the check-in note counts per turn and caps at 4; the topic
words. `19-same-win-again` is reworded (five quick wins each get a
reaction, and not the same one) and gains per-finish expectations and
checks:

```json
{"checks": {"reactions": "4-", "max_same_in_a_row": 2, "min_variety": 3},
 "steps": [
  {"event": "turn started", "at": "0m"},
  {"event": "command", "at": "0m20s", "topic": "tests", "failed": false},
  {"event": "turn finished", "at": "0m30s", "expect": {"react": "happy|pleased|calm", "animation": "success|none"}},
  {"event": "turn started", "at": "1m"},
  {"event": "command", "at": "1m20s", "topic": "tests", "failed": false},
  {"event": "turn finished", "at": "1m30s", "expect": {"react": "pleased|happy|excited"}},
  {"event": "turn started", "at": "2m"},
  {"event": "command", "at": "2m20s", "topic": "tests", "failed": false},
  {"event": "turn finished", "at": "2m30s", "expect": {"react": "excited|amused|pleased|happy"}},
  {"event": "turn started", "at": "3m"},
  {"event": "command", "at": "3m20s", "topic": "tests", "failed": false},
  {"event": "turn finished", "at": "3m30s", "expect": {"react": "amused|pleased|happy|excited|comfy"}},
  {"event": "turn started", "at": "4m"},
  {"event": "command", "at": "4m20s", "topic": "tests", "failed": false},
  {"event": "turn finished", "at": "4m30s", "expect": {"react": "comfy|calm|pleased|amused|none"}}]}
```

New `85-check-ins.json`: a turn, tests pass at 20 s, `wait` at 4m
(`react: engaged|hopeful|determined|curious|happy|calm`, `animation:
none`), `wait` at 8m (`react: hopeful|bored|engaged|determined|lazy|
calm`), `wait` at 13m (`react: determined|bored|engaged|lazy|calm|
none`), `turn finished` at 14m (`animation: success`); `checks`
`{"min_variety": 2, "max_same_in_a_row": 2, "max_quiet_working": "6m"}`.
`21-busy-session` gains `"max_same_in_a_row": 2, "min_variety": 4`.
Cost: 19 (10), 85 (~9), 21 (21): about 40; then `--always --runs 1`
(165) once, since every finish line changes.

**Done when** 19, 85 and 21 pass once, `--always` passes, `ViewTests`
pins the counts, and a 21 timeline shows no three identical reactions
in a row.

**Depends on** R1 (room). Independent of R2, R3.

**Per pack.** Engine once; each pack's Examples. The faces named are
universal moods, so both packs draw them (the pixel face borrows art
for amused, comfy, bored, hopeful; the gel has its own).

## R5. Four new lines for the brain

**Issue.** The brain is deaf to a compaction, to you answering a
request, to idle time under an hour, and to a poke while Boop sleeps or
a barrage that comes again (A5, B4). Each is one line.

**Architecture change.** P3 and P2. Four lines in the view, one
front-matter key, no new event kind, no new heartbeat kind. The core
already records the compaction (`starting` with `ctx: compacted`) and
the `needs_you` end; the view starts saying so.

**What to do.**

1. **Compacted.** In `agentEvent`, a `.sessionStarted(source)` with
   `source == Mapping.compacted` lines `claude's context on "api" was
   compacted; it picks up where it left off.`, wake 0, facts `thread`.
   `EventLine.words`: "A compacted context means the agent's memory was
   squeezed to make room; it carries on from a summary." Example →
   `confused, looking in a sound, once` (the context-wall demo's "where
   was I?", now for real); `confused.md` gets R1's shape. The rule
   reaction and the COMPACTED card are untouched.
2. **You answered.** `needs(_:)` lines a `needs_you` end whose `outcome`
   is `done`: `You answered claude on "api".`, wake 0, facts `thread`;
   failed ends (forgotten, the session ended) line nothing. `keeps`
   gains `(.needsYou?, .end?)`, `wakes` gains `"needs_you_end": 0`.
   Example → `pleased, glad in a word, once` ("Nice", "Sweet"). With
   another request still waiting the pass is held, as any is: "needs
   you" is untouched.
3. **An idle check-in.** The idle heartbeat gets a second period: while
   at least one session is open, none works, and the last agent event,
   poke, talk or back was under `idleWindowMs` (2 h) ago, it comes every
   `idle_heartbeat` seconds, a front-matter rule
   (`Personality.Rules.idleBeatMs`; `boop` 900–1800, `chatter` 300–600,
   `pixel` 1200–2400, `none` off); past the window, or with no session
   open, it comes every hour as today. `heartbeat(at:)` keeps a
   `nextIdleBeatAt` drawn from the range after each activity and each
   beat, beside `nextWorkBeatAt`. The line generalises
   `EventLine.heartbeat(hours:)` to minutes: `Nothing has happened for
   20 min; claude sits idle on "api".` (the thread idle longest), and
   past the hour the sentence it has today. Examples → `bored, quiet in
   a word, once`, → `lazy, quiet in a sound, twice`, → `none`; the
   guide: "An idle check-in is a small face or nothing, never a finish,
   and never moves the mood except to fade it."
   **A behaviour change to know about:** the mood files' minutes
   ("fades to calm once Boop has been annoyed for 3 min") take effect
   only when a pass comes. Today, with nothing happening, the first
   pass is the hourly heartbeat, so a 3-minute fade takes an hour. With
   check-ins every 15–30 minutes the fades happen about when the files
   say. `06` and `55` are rewritten for that (below). Cost: with
   sessions open eight hours a day and half of it idle, about 10–15
   passes a day.
4. **A poke while asleep, and again.** `poke(_:)` adds `while it slept`
   when the fold has no sessions (`You poked Boop while it slept.`,
   facts `asleep`), and `, again` when the previous run of pokes ended
   under `againMs` (2 min) ago (`You poked Boop 4 times in a row,
   again.`, facts `again`; `Fold.pokes` keeps the last run's end).
   Examples → `surprised, tickled in a sound, once` (the startle) and →
   `grumpy, upset in a phrase, twice` ("Personal space"); `grumpy.md`:
   "a barrage again, before it has calmed down, keeps it grumpy and
   makes it say so."
5. The eval runner (`internal/app/BoopDevKit/Eval/Eval.swift`) gains
   steps `compact` (a `SessionStart` with `source: compact`), `needs
   you` (a `PermissionRequest` for `Bash`), `answered` (its
   `PostToolUse`), and `pokes` takes `"count": N` (default 4) and
   `"asleep": true` (the step runs before any session exists). Each is
   one case in `Eval.inputs` and one line in EVALS.md §1's table.
6. `boop.md`, `chatter.md`, `pixel.md`; `confused.md`, `bored.md`,
   `grumpy.md`; the three personality files' front matter.

**Specs.** `documentation/architecture.html` "View: sentences for Jev"
(the heartbeats); `characters/CHARACTER.md` §7 (`idle_heartbeat`);
`internal/EVALS.md` §1 (steps), §3 (`count`, `asleep`).

**Untouched.** The core, the harness, the device, `wakesWhileNeeded`,
`Event.Kind`.

**Tests and evals.** `ViewTests`: each line with and without its
condition; the idle check-in only inside the window, only with a session
open, never while a thread works, never twice within its range, hourly
after; the answered line once per request and never for a forgotten
one; `again` only within 2 min. Scenarios:

- `74-answered.json`: a turn, `needs you` at 1m, `answered` at 1m30s →
  `react: pleased|happy|calm|engaged`, `animation: none`; the turn
  finishes at 3m → `animation: success`.
- `75-where-was-i.json`: a turn, tests fail at 1m, `compact` at 4m →
  `react: confused|curious|baffled|calm`, `animation: none`, `about:
  looking|none`; the turn finishes done at 6m → `animation: success`.
- `76-idle-check-in.json`: a quick turn, then `wait` 50m with
  `"checks": {"reactions": "1-3", "mood_changes": "-1", "moves_on_graph":
  true}` and the last pass `react: bored|lazy|calm|comfy|none`,
  `animation: none`.
- `77-poked-asleep.json`: `pokes` count 1, `asleep: true` → `react:
  surprised|curious|happy|stunned`, `animation: none`.
- `78-barrage-again.json`: `pokes` at 0s, `pokes` at 1m → the second
  `react: grumpy|irritated`, `kind: phrase|word|sound`, `said: some`.
- `06-heartbeat-lets-grumpy-go` rewritten: the first `wait` at 35m
  expects `mood: annoyed|irritated` (grumpy's 2 minutes are up by the
  first check-in), at 1h5m `mood: calm|annoyed`, at 3h5m `mood: calm`.
  `55-quiet-fades-from-excited` likewise: happy by the first check-in,
  calm by the third.

Cost: 74 (~5), 75 (~6), 76 (~4), 77 (1), 78 (~4), 06 (~8), 55 (~6),
15 (6): about 40.

**Done when** the eight pass once, `ViewTests` pins each line, and the
context-wall demo's brain step reads as what Jev now does.

**Depends on** R1 (room). Independent of R2–R4.

**Per pack.** Engine once; Examples and the idle pace in each pack's
personality file.

## R6. Idle and asleep life in both packs

**Issue.** Both faces turn their idle variations on their own and have
nothing comic or audible to turn to (A4). No yawn, nod-off, sneeze or
snore exists; every idle and asleep design is `silent`.

**Architecture change.** None. P1: pack content only, no Mac change, no
Jev.

**What to do.**

*Pixel's face* (`characters/pixel/design/boop-sound-bank-v4/`, which
Boop wears on the CYD). Four new designs, each one generator in the
bank's runtime drawn for all 13 moods by the mood art, each a catalog
entry per mood with its score:

| Design | State, variation | Loop | What happens | Sound policy |
| --- | --- | --- | --- | --- |
| Yawn and stretch | idle 4 | 9 s | The wake-up's yawn, slower, once per loop | `entry` (the yawn tone once, when turned to) |
| Nodding off | idle 5 | 12 s | Eyes droop into the asleep pose for 2 s, snap back with a blink | `silent` |
| Sneeze | idle 6 | 10 s | A wind-up, a sneeze, a shake | `sparse`, `every` 3 (about once a minute while showing) |
| Snore | asleep 4 | 12 s | Two soft breaths per loop | `sparse`, `every` 4 (about every 50 s), quiet; the other three asleep designs stay silent |

The device's variation turn (`kTurnPct` 67 at each loop end, after
`kTurnMinMs`) spreads them over an idle hour by itself; with six idle
variations each shows about a sixth of the time. `kMaxVariants` is 12.

1. The generators and catalog entries; `make -C internal faces` (about
   7 min, pixel for pixel against Chrome); `node
   characters/pixel/tools/sfxgen/sfxgen.mjs` (the 180 KB asset ceiling).
   `faces.json`, `faces.h` and `sfx.h` grow; `FaceLoops.count` follows.
2. `make -C internal fw-test`: `test_effects` pins the `sparse` policies
   with their `every`; `test_face` the new counts.
3. `make -C internal sim`: `life.jsonl` gains a frozen-clock turn to idle
   4 and asleep 4 with a cue expectation; new goldens.

*The gel* (`characters/boop/design/slime-blob/`):

1. `state-plan.json`: idle gains `yawn-and-settle`, `doze-and-snap`,
   `sneeze-and-shake` as variations 4–6; asleep gains `snore` as
   variation 4 with `audioPolicy` `sparse_contacts` for that variation
   only (a soft breath clip on its contacts, in `sound/`).
2. `expressions.json`: bored, tired, lazy and comfy get a yawn among
   their three performances.
3. The recipes in `render/`; `node
   characters/boop/design/slime-blob/tools/build.cjs`; `node
   characters/boop/tools/slimegen/slimegen.mjs` (`slime.h`);
   `check-port.py`. `Bag` picks among 3 (`values[3]`): widen it to the
   largest recipe count, pinned by `static_assert`.
4. `make -C internal sim` for the gel's goldens.

The owner flashes (`make flash`) and listens to the snore's level on
both boards.

**Specs.** `characters/CHARACTER.md` §9 if it quotes variation counts;
`characters/pixel/design/README.md`; the slime's `STATES.md` and
`VALIDATION.md`; `simulator/README.md` if the scenario is listed.

**Untouched.** The Mac entirely; the protocol (`variant` travels
already); the brain.

**Tests and evals.** None with Jev. `fw-test` and `sim` pin it.

**Done when** `faces`, `fw-test` and `sim` pass with the new goldens
accepted, and the owner has heard a snore and a sneeze on a board.

**Depends on** nothing. Runs in parallel with everything.

**Per pack.** Pixel's bank serves both packs' CYD face, so Pixel gets
the idle life for free; the gel is Boop's own.

## R7. Comedy on the finish

**Issue.** The owner's hiccups, the gift and the zoomies have nowhere to
show.

**Architecture change.** None. P1: variations of states that exist,
picked by the faces' own never-the-last rule.

**What to do.**

1. **Hiccups.** Pixel: `task_complete` success variation 5 in every
   mood, "Trophy, then hiccups" (the trophy, then three hiccup bounces,
   8 s; `entry` policy with three clicks). Gel: a
   `bounce-and-card-hiccup` recipe. Both faces pick a success variation
   never-the-last, so about one cheer in five hiccups.
2. **The gift.** Proud's `task_complete` success variation 2 redrawn so
   Boop holds up a pixel bug (the comeback's cheer is proud's by `09`);
   on the gel, proud's `lift-and-card` lifts a small bug. The word is
   Jev's (`done` or `tests`).
3. **Zoomies.** Excited's `working` variation 6 and `idle` variation 7
   (after R6's), the face zipping around the screen; on the gel, an
   excited performance that slides the dome edge to edge. Shows after a
   very long turn done while the mood is excited, through the variation
   turn.
4. The same generators, builds and goldens as R6; `finish.jsonl` gains
   the hiccups.

**Specs.** As R6.

**Untouched.** The Mac, the questions, the protocol.

**Tests and evals.** None with Jev. `02-long-turn` gains `loops: three
times|four times`, `said: some` (~10) once R2's holds are in.

**Done when** the goldens are accepted and the owner has seen hiccups on
a board.

**Depends on** R6's generator work (share it).

**Per pack.** Pixel's bank for both CYDs; the gel for Boop's AMOLED.

## R8. Ears: a listener that only writes events

**Issue.** Boop can't hear its name, a few words, a clap, a shout or a
sing-song voice without the button held (A3, A9, C4). The brief wants
about 20 words, mistakes on purpose, a startle and tone.

**Architecture change.** P3 and P4. One new component in the app target
that turns what the Mac's mic hears into one raw event, `heard`, as
push-to-talk turns it into `talk`; one line in the view; Examples.
Randomness (the mishearing) is decided in the component and recorded
in the event, so the view and the brain stay pure. No new question, no
pack table, nothing in `react`.

**What to do.**

1. `app/BoopKit/Core/Event.swift`: `Kind.heard`. `Source.mic` exists.
2. `app/BoopKit/App/Pipeline.swift`: `heard(_ what: String, misheard:
   Bool, at:)` beside `said`, which emits `Event(at:, source: .mic,
   type: .heard, specificType: what, data: ["misheard": .bool])`. The
   core isn't called: nothing on screen is the core's here.
3. `TranscriptView`: `keeps` gains `(.heard?, nil)`; `wakes["heard"] =
   0`; `heard(_:)` writes the line and `noteActivity`; facts `what`,
   `misheard`. `wakesWhileNeeded` stays `[.talk]`: while amber shows the
   sign already answers "who needs me", and a reaction would be blocked
   anyway. `EventLine.heard(what:misheard:name:)`:
   - `Boop heard its name.`
   - `Boop heard you say "good boy".` (one canonical phrase per word)
   - `Boop misheard you: "dance", or something like it.`
   - `Boop heard a bang.`, `Boop heard you shout.`, `Boop heard you
     singing.`
   `EventLine.words`: "Boop hears its name, a few words and three kinds
   of sound; it can't understand anything else, and it mishears now and
   then."
4. `app/Boop/Ears.swift` (beside `Talk.swift`; BoopKit stays free of
   AVFoundation and Speech):

   ```swift
   final class Ears {
       static let words: [String: [String]] = [   // what → the phrases that mean it
           "good": ["good boy", "good girl", "good job"], "no": ["no", "bad"],
           "dance": ["dance"], "sleep": ["sleep", "nap"], "wake": ["wake up"],
           "hello": ["hello", "hi"], "bye": ["bye", "goodbye"], "shh": ["shh", "quiet"],
           "stop": ["stop"], "who": ["who needs me"], "come": ["come here"],
           "sit": ["sit"], "speak": ["speak"], "treat": ["treat"], "fetch": ["fetch"]]
       static let nameGated: Set<String> = ["no", "stop", "sleep", "sit", "come"]  // only within nameGateMs of the name
       static let canMishear: Set<String> = ["dance", "sleep", "sit", "come", "speak", "fetch"]
       static let mishearOdds = 5, nameGateMs: Int64 = 3000, debounceMs: Int64 = 3000
       static let bangDb: Float = -18, shoutDb: Float = -22, singSemitones = 7
       func start(name: String, onHeard: @escaping (_ what: String, _ misheard: Bool) -> Void)
       func pause()   // push-to-talk has the mic
       func resume()
       func stop()
   }
   ```

   `AVAudioEngine`'s input tap feeds a level meter and a pitch estimate
   (autocorrelation on the buffer is enough for sing-song) and
   `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` and
   `contextualStrings` = every phrase, restarted every 50 s;
   `supportsOnDeviceRecognition` false refuses to start and says why.
   Partial results are matched against the phrases and dropped. No
   buffer is written anywhere. `bang`: level over `bangDb` for under
   300 ms with no speech; `shout`: speech with level over `shoutDb` for
   500 ms; `singsong`: pitch swinging over `singSemitones` within 2 s;
   first guesses, tuned by ear. One event per `debounceMs`. The
   mishearing: a seeded `SplitMix64`; for a word in `canMishear`, one in
   `mishearOdds` is reported `misheard: true`; never the name, `good`,
   `no`, `shh` or `stop` (the safety words are always heard right).
5. `Runtime`: `heard(what:misheard:)` → `pipeline.heard`; starts `Ears`
   when `AppSettings.ears` (new, default false) and stops it when it's
   turned off; `mic(on:)` pauses and resumes it around push-to-talk.
   `Arguments`: `--ears` for `Boop --headless`. `SettingsPane`: an
   "Ears" toggle under Sound with one line ("Boop listens for its name,
   a few words and loud sounds, on this Mac; nothing it hears leaves
   it") and the refusal reason when on-device recognition isn't there.
   `Info.plist` already carries the mic and speech usage strings.
6. Examples (`boop.md`): name → `curious, tickled in a word, once`;
   `good boy` → `proud, glad in a phrase, twice`; `no` → `embarrassed,
   upset in a sound, once`; `dance` → `excited, glad in a phrase, four
   times`; `sleep` → `tired, quiet in a word, twice`; `hello` → `happy,
   glad in a sound, then hello, once`; `shh` and `stop` → `none`; `who
   needs me` → `calm, quiet in a word, once`; a bang → `surprised,
   upset in a sound, once` (the startle; Jev answers in 100–300 ms);
   a shout → `wounded, upset in a sound, twice`, mood `wounded` or `sad`
   (hero moment 3); singing → `affectionate, tickled in a sound, once`.
   Misheard: `"dance"` → `tired, quiet in a word, twice` (asked to
   dance, it nods off); `"sleep"` → `excited, glad in a phrase, three
   times` (asked to sleep, the zoomies, through R7's excited
   variation); `"sit"` → `mischievous, tickled in a word, once`.
   `chatter.md` and Pixel's `pixel.md` (prose) the same.
7. The eval runner's `heard` step with `"what"` and optional
   `"misheard": true`.
8. The owner tests from a terminal the Claude app opened (an agent's
   shell has no mic permission): `Boop --headless --state-dir
   /tmp/ears --ears --debug`, then its name, "good boy", a clap, a
   shout, and `debug.jsonl`'s `heard` events.

**Specs.** README.md "What leaves your Mac" (with Ears on, only which of
the words or sounds was heard, and whether Boop misheard, reaches the
transcript and Jev; no audio is recorded or sent; the recogniser is
on-device or the toggle refuses); `documentation/architecture.html`
"Where the pieces join" (a row: the Mac's mic → Boop, `Runtime.heard`,
one raw event like a poke); `internal/EVALS.md` §1 (the step);
`internal/VERIFICATION.md` §2 (`--ears`, the owner's check); CLAUDE.md
"Never do these" (don't turn Ears on from an agent shell); Words table
("misheard").

**Untouched.** The core, the harness, the questions, `react`, the
device, push-to-talk, "needs you".

**Tests and evals.** `ViewTests` for the lines; a unit test on `Ears`'s
decision function (pure: phrase matching, the name gate, the die's odds
over 1,000 rolls ± 25%, never a safety word misheard). Scenarios:
`79-good-boy.json` (`heard good` → `react: proud|happy|pleased|
affectionate`, `said: some`, `loops: twice|three times`);
`80-shouted.json` (a turn working, `heard shout` → `react: wounded|sad|
scared|frightened`, `mood: wounded|sad|scared`; a finish 3 min later →
`animation: success`, `react` not grumpy); `81-dance.json` (`heard
dance` → `react: excited|happy|mischievous`, `loops: three times|four
times`, `"checks": {"reactions": "1"}`); `82-shh.json` (`heard shh`
while working → `react: none`); `86-misheard-dance.json` (`heard dance`
with `misheard: true` → `react: tired|lazy|comfy|calm`, `animation:
none`). Cost: about 10.

**Done when** the five pass once, `git grep -n "AVAudioFile\|write(to"
app/Boop/Ears.swift` finds nothing, the owner has seen `heard` events
for their name, a clap and a shout, and `--always --runs 1` passes.

**Depends on** R1 (room), R5 (the view pattern is fresh). Last.

**Per pack.** Engine once; each pack's Examples.

## R9. Evals and the working day hold the fun

**Issue.** The evals fail when Boop makes the wrong face, never when it
is dull, quiet or repetitive (D). Pixel has no evals. Codex has none.

**Architecture change.** None. P5.

**What to do.**

1. `max_same_in_a_row` and `min_variety` on in 19, 21 (R4), 22
   (`"max_same_in_a_row": 3`) and 85.
2. `Eval.judge` gains `words_said`, a range over the share of played
   reactions with a take (`"0.5-"`), in `Checks.keys`; 21 turns it on.
3. `said: some` at the hero moments: 02, 03 (R2), 05's first poke, 08,
   16's first barrage.
4. `workday.py` `LIMITS`: `max_repeat_pct: 40`, `max_longest_same_run:
   3`, `min_words_said: 0.5`; `check` holds them; `report` and `boopctl
   day` print a fun ledger per hour: distinct reactions, reactions with a
   word, the longest identical run, idle check-ins. The "reported, with
   no limit: repeats are fine" sentence goes.
   `internal/tools/boopctl_lib/tests/test_workday.py` covers the limits;
   a scripted day fails the repeat limits (the scripted brain repeats),
   which is the test.
5. The runner takes `"agent": "codex"` on a step (source `.codex`, hooks
   per `Mapping.codex`); `83-codex-turn.json`: a Codex turn with a
   command and a `Stop` after 3 min → `animation: success|reply`,
   `react` not grumpy or sad.
6. `characters/pixel/evals/`: five scenarios in Pixel's words (a failed
   turn, pokes, a long finish, back after a break, an idle check-in),
   run as `CHARACTER=pixel .build/debug/boopdev eval --scenarios
   characters/pixel/evals --steering characters/pixel/steering`;
   `internal/Makefile` gets `eval-pixel`.
7. Demos `the-cheer.jsonl` and `the-cuss.jsonl` in both packs; `boopdev
   check` plays them; `make demo NAME=the-cuss`.
8. `internal/EVALS.md` §4's kinds gain "Fun (19, 21–23, 70, 74–86)".

**Specs.** `internal/EVALS.md` §1, §3, §4, §5; `characters/DEMOS.md`;
`internal/VERIFICATION.md` §2 (`eval-pixel`); `characters/CHARACTER.md`
"At a glance" (a pack's `evals/`).

**Untouched.** The runner's shape, the existing checks.

**Tests and evals.** Each check runs with the scenario that turns it on;
83 once (~3); Pixel's five once (~15).

**Done when** `boopdev eval --list` shows every new scenario with a
case, `EvalTests` covers each new check and step without Jev, and
`workday check` on a scripted day exercises the three new limits.

**Depends on** R2, R4, R5, R8 for the scenarios each adds; the checks
and the working day can land first.

**Per pack.** Boop's evals and the working day; Pixel's new five.

## R10. Only if needed: one new animation state

**Issue.** If a variation can't carry a thing (a real dance to "dance",
a huff with steam at a barrage), it needs a state of its own, which is
engine work the rule says to avoid until it's earned.

**Architecture change.** One more `SceneState`, one more
`react.animation` option, and every table that lists the states.

**What it costs**, so the decision is informed: `firmware/src/render/
types.h` and `types.cpp` (`SceneState`, the names, `isReaction`);
`characters/CHARACTER.md` §9's table and `charactergen.py --check`'s
copy of it; Pixel's bank (one generator, 13 moods), `faces.json`'s
`states`, `FaceLoops.states`; the gel's `router.cpp` family,
`state-plan.json`, three recipes per expression, `slime.h`'s
`kRecipeStates` `static_assert`; `ReactOutput.animations` (an option
with a "not for") and `scenes`; `DeviceReaction.anims`; the device's
`hello.does` if it lists animations; `characters/studio/states.json`;
`internal/firmware/test/test_face`; a sim scenario and goldens for both
faces; `internal/EVALS.md`'s `animation` list; `characters/DEMOS.md`'s
brain answers. About a day, both packs, then 03/16/81 once each (~20).

**Do it** only after R6–R8 have shown what the variations can't do.

## Not now

- **Variety machinery in `react`** (the first pass's echo rule, off
  die and kind bump): it needs hidden state in an output, three dice
  and five constants, and it reads Jev's second-best answers, which are
  thin on routine lines. R4's counted lines give Jev a different line to
  answer instead. If the ladder isn't enough once 19, 85 and 21 run, the
  smallest thing to add is one die in `ReactOutput.run` alone: one
  routine reaction in 12 takes Jev's second-best face at or above 0.05,
  recorded in the output's facts. Nothing else from the first pass.
- **Bigger says for long holds** (a phrase then a word at three times or
  more; `Voice.say` with `loops`, `maxSayMs` 3,400): a `Voice` change for
  a small gain. The kind and the hold carry loudness. Revisit if
  four-times holds feel mute on the board.
- **Growth in the prompt** ("Boop is a Sprout: it knows three tricks"):
  cheap, but it's tuning personalities, which the owner put later.
- **A startle by rule** on the device: Jev at 100–300 ms is fast enough
  for a bang; a rule that picks a face breaks "the brain is never on the
  screen's path" the other way round.
- **Double tap, stroke, shake:** the CYD's resistive panel and BOOT make
  a poor stroke; the gel's drag is a reflex already.
- **A buddies eval:** the runner is one buddy; the `not-my-turn` demo
  and `BuddiesTests` cover it.

## Order, dependencies and cost

| Stage | Items | Why this order | Jev requests |
| --- | --- | --- | --- |
| 1 | R1, R2, R3, R9's checks and `said`s | Room first; the cuss and nature are text; the checks make the later stages measurable | ~85 (17, 47, 53, 03, 08, 04, 70, 71, 72, 05, 61) |
| 2 | R4 | The ladder: the one view change with the biggest daily effect | ~40 (19, 85, 21), then `--always --runs 1` (165) |
| 3 | R5 | Four lines and the check-in; the view pattern R8 copies | ~40 (74–78, 06, 55, 15) |
| 4 | R6, R7 | Pack art and sound, in parallel with 2–3 | 0 (~10 for 02 after R2) |
| 5 | R8 | Ears, last: copies R5's pattern | ~10, then `--always --runs 1` (165), plus the owner at the Mac |
| 6 | R9's rest | Codex, Pixel's evals, the demos, the working day | ~18, plus one scripted `workday` (free) |
| Before merging | `boopdev eval --runs 1 --no-budget` | Every scenario once, new ones included | ~460 |

About 1,000 requests in all at one run each; `make eval` at the default
runs (660 today, about 770 after) is for the owner's final pass, if at
all.

What a subagent must not do: add a question to Jev, change the harness's
contracts, put a rule that chooses a face or a word anywhere, put a die
anywhere but a component that records its roll in the event, send a new
message type to the device, add a state without R10 being chosen, or
let anything but a word from `Ears.words` or one of its three sounds
reach the transcript from the mic.
