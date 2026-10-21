# Fun plan: ten recommendations for a simple core, both packs (2026-10-21)

The audit is [README.md](README.md). This plan keeps one rule from the
owner: **the core stays simple and stable; tune through pack content,
steering, new events and lines, and `react` reading its own answers; add
machinery only when nothing else can carry it.** Each item is a brief a
subagent can take alone: the issue, the change, the steps with files and
functions, the specs to update, what stays untouched, the evals with
their expected values and Jev cost, when it's done, what it depends on,
and how it lands in each pack.

## 0. The rule, made concrete for this engine

The extension points, in the order to prefer them:

1. **Pack content.** A new variation of a look or a finish, a sound on a
   design's timeline, a gel recipe or performance. Both faces already
   pick among variations on their own (the pixel face turns a look's
   variation at loop end, the gel plays a performance every 7–15 s), so
   new content shows with no Mac change.
2. **Steering text.** Examples, mood files, nature files. Both packs,
   each its own.
3. **New lines in the view.** A thing that happens becomes one more line
   `TranscriptView` writes, with facts and a wake. Pokes and the back
   from a break are the model. The harness and the brain never change.
4. **View rules from the personality's front matter.** Timings and which
   events wake the brain, as `working_heartbeat` is.
5. **`react` reading its own answers.** `ReactOutput.run` owns how it
   reads Jev's probabilities. Variety lives there, in one file.
6. **A new component**, only for ears, which turn something the Mac can
   hear into one raw event, as `Pipeline.said` does for push-to-talk.

What the plan does **not** do: no new question to Jev; no change to the
harness, the core's rules, the protocol, the device's queue or "needs
you"; no rule that chooses a face or a word; no new message on the wire;
no new state in the engine unless R10 is chosen.

| Layer | Touched by |
| --- | --- |
| Core (`app/BoopKit/Core/Core.swift`) | none |
| Harness, brain, protocol, queue | none |
| View (`TranscriptView`, `EventLine`, `Personality.Rules`) | R5, R8 (lines, facts, one front-matter rule, one event kind) |
| `ReactOutput` | R4, R7 (reads second-best answers and a die; passes the hold to Voice) |
| `Voice` | R7 |
| Steering (`characters/*/steering/`) | R1, R2, R3, R5, R8 |
| `character.json` | R1 (`face` text), R8 (`mischief`) |
| Pack art and sound | R6, R7 |
| New component | R8 (`app/Boop/Ears.swift`, which only writes events) |
| Evals, working day, demos | R2, R3, R5, R8, R9 |

**For every subagent.** Start from the latest `main` (`git log
--oneline HEAD..main` prints nothing). Read CLAUDE.md's "Docs stay in
sync" table and update the doc in the same commit. Pin every number in
a test. Run only the evals the brief names, `--runs 1`, with
`BOOP_JEV_KEY` from the owner. `boopdev eval --list` prices a scenario
without a key; `boopdev eval` stops over 100 requests unless `--budget`
says otherwise. Don't run `make eval` (660 requests at the default runs).

The evals live in Boop's pack (`characters/boop/evals/`) and run on the
pack in use. Each item says what Pixel gets. Boop's steering writes its
Examples as `NOW: … → face, animation, feeling in a kind, then topic,
hold`; Pixel's as prose. Keep each pack's style.

## R1. Room in the steering, and real words for the 29 slime moods

**Issue.** The guide is at 300/300 tokens, `boop.md` at 729/750 and
`engaged.md` at 175/175, so no Example can be added without cutting one.
And 29 of Boop's 42 moods reach Jev as the slime design's engineering
prose with no `face` text and a boilerplate mood file, so the comic
moods (lazy, bored, mischievous, amused, surprised, stunned, baffled,
embarrassed, disgusted, tired) are never picked.

**Change.** `Steering.Budget`: guide 300 → 400, personality 750 → 1000,
nature 150 → 250, mood 175 → 225 (a request is about 3,400 tokens; this
adds at most 350). Then content: in Boop's `character.json`, a `face`
and, where it helps, a `face_not_for` for each of the 29 moods, in
Pixel's plain register ("A lazy face: can't be bothered, but it's
getting done"); the `meaning` stays the design's, since `slimegen`
writes it, or change it in `emotion-graph.json` and rerun `slimegen`.
Mood files for ten comic moods in the shape of `grumpy.md` (what it
leans to, what it says, what it stays through, what it leaves for, when
it fades): lazy, bored, mischievous, amused, surprised, stunned,
baffled, embarrassed, disgusted, tired. Pixel: its 42 mood files get the
same shape, three to five lines each.

**Steps.**

1. `app/BoopKit/Harness/Steering.swift` `Budget`; the pins in
   `internal/app/Tests/RuntimeTests.swift` (`overBudget() == []`) and
   `CharacterPackTests.swift` still pass; `HarnessTests` for nature.
2. `characters/boop/character.json`: `face`/`face_not_for` on the 29
   moods. `python3 characters/charactergen.py --check` and `boopdev
   check` still pass; `node characters/boop/tools/slimegen/slimegen.mjs
   --check` stays fresh (it keeps `face`).
3. `characters/boop/steering/mood/{lazy,bored,mischievous,amused,
   surprised,stunned,baffled,embarrassed,disgusted,tired}.md`.
4. `characters/pixel/steering/mood/*.md`, same shape, shorter.

**Specs.** `characters/CHARACTER.md` §7 (the budgets' numbers, if
quoted); `documentation/architecture.html` only if it quotes a budget.
"Updated" dates.

**Stays untouched.** The questions, the mood graph, the moves, every
other mood file.

**Evals.** None new: `17-never-the-wrong-face`, `47-recovery-walk`,
`53-busy-day-on-the-graph` once each (~45 requests) to check the new
faces don't pull Jev off the graph or onto a wrong face. R5's idle
check-in is where the comic moods get their own scenario.

**Done when** `overBudget()` is empty in both packs, `boopdev check`
passes, the three scenarios pass once, and `boopdev eval --list` prints
unchanged counts.

**Depends on** nothing. First, since R2, R3, R5 and R8 add text.

**Per pack.** Boop: the budgets (engine) and all of the above. Pixel: the
mood files; its `character.json` already has plain meanings and faces.

## R2. The cuss, and a ladder of failure

**Issue.** A failed turn is one hold of an irritated face with "upset or
nothing"; the swear is kept for a stinging failure that was already
grumpy (`60`). Nothing escalates: a second failure in a turn, a failure
after a fix, a failure that follows a barrage. "Loud is better" means
pulling the two levers the steering has, the hold and the kind.

**Change.** Steering only. Boop's Examples (R1 makes room):

- `claude finished turn 5 on "api": failed, a long turn, 15 tool calls.`
  → `irritated, failure, upset in a phrase, twice` (cheeky: `upset in a
  swear`; see R3).
- A failed turn after `claude's tests failed on "api".` in the same turn
  → `grumpy, failure, upset in a phrase, three times` ("Not again",
  "Oh, come on").
- `claude finished turn 9 on "api": failed, a very long turn, 40 tool
  calls.` → `sad, failure, upset in a sound, four times` (already sad
  by `08`; make the hold four).
- `claude's tests failed on "api".` a second time in a turn → `annoyed,
  upset in a word, then retry, twice` ("Again").

`grumpy.md`, `irritated.md`, `annoyed.md` "Says" lines: a phrase at a
failed turn, a swear when it stings, held longer than the win before
it. The guide's "held longer for big moments" gains "a failure held
longer than the win before it". Pixel's `pixel.md`: "A turn fails: an
annoyed face held twice for a small one, with a huff or a word; a sad
face held longer for a big one; a swear only when it really stings."

**Steps.** Edit the files; `boopdev check`; the two packs' budgets.

**Specs.** None but the steering itself and `internal/EVALS.md` §4 (the
reworded scenarios).

**Stays untouched.** The questions, Voice (the swear takes exist: Crap,
Damn, Fuck, Shiba, Shit, 18 in all, on the failure finish), the device
(the failure design plays).

**Evals.** `03-turn-failed`: `react: grumpy|annoyed|irritated`,
`animation: failure`, `kind: phrase|word|swear`, `said: some`, `loops:
twice|three times`. `08-long-turn-fails`: add `said: some`, `loops:
three times|four times`. `04-tests-fight-back`: the second failure
`said: some`, `loops: once|twice`. `60` unchanged. New
`70-failure-after-fix.json`: tests fail, pass (reaction `done`), then
the turn fails 90 s later on `api_error`: `react: grumpy|irritated|
whiny`, `animation: failure`, `said: some`, `loops: twice|three
times|four times`, `mood: grumpy|irritated|annoyed`. Cost: 03 (2), 08
(13), 04 (~6), 70 (~5): about 26.

**Done when** the four pass once, `61-no-swear-at-a-win` still passes
(~6), and a new demo `characters/boop/demo/the-cuss.jsonl` (and Pixel's)
plays in the simulator: a turn, tests fail, the turn fails, the brain
step `{"react.mood": "grumpy", "react.animation": "failure",
"react.loops": "twice", "say.feeling": "upset", "say.kind": "phrase"}`.

**Depends on** R1 (room). R3 splits the swear by nature.

**Per pack.** Boop: Examples and mood files; the gel plays its
`task_complete` failure recipe, the CYD "The task fell apart". Pixel:
prose, same intent, and the demo.

## R3. Nature in the evals and the Examples

**Issue.** The app always runs with a nature after setup; the evals
never do (`nature: nil`), so every scenario checks a prompt the app
doesn't show. The nature files are prose with no Examples, so cheeky and
sweet differ by adjectives Jev may or may not weigh.

**Change.** The runner takes a scenario field `"nature": "sweet" |
"cheeky"`, default `cheeky` (the owner's), and builds the harness with
it. Each nature file gets two Examples in the pack's style (budget 250
after R1): cheeky, a failed turn → `irritated, failure, upset in a
swear, twice` and one poke → `mischievous, tickled in a word, once`;
sweet, a failed turn → `disappointed, failure, upset in a word, once`
and one poke → `affectionate, tickled in a sound, once`.

**Steps.**

1. `internal/app/BoopDevKit/Eval/Eval.swift`: `Scenario.nature`
   (`LongTerm.Nature`, parsed, unknown value fails to load), passed to
   `Runtime.harness(... nature:)`; `EvalTests` loads a scenario with each
   value and one with a bad one.
2. `boopdev eval --list` prints the nature when it isn't the default.
3. `characters/boop/steering/nature/{cheeky,sweet}.md`,
   `characters/pixel/steering/nature/*.md` (prose Examples).

**Specs.** `internal/EVALS.md` §1 (the run's prompt has a NATURE
section), §3 (the field), `characters/CHARACTER.md` §7 (the files may
carry Examples).

**Stays untouched.** `Steering.nature`, the memory format, the
runtime.

**Evals.** `03` runs twice, once per nature, as two files or one with
`nature: sweet` copied to `71-turn-failed-sweet.json`: sweet expects
`react: annoyed|disappointed|sad`, `kind: sound|word|phrase` (never
swear), `loops: once|twice`. `05-pokes-glad-miffed-grumpy` gets
`71`-style twin `72-pokes-sweet.json`: the first poke `react:
happy|curious|affectionate|pleased`, the third `react:
annoyed|irritated` (sweet gets miffed, not grumpy). Cost: 71 (2), 72
(4), and 03 and 05 again (6): about 14.

**Done when** both natures pass their files once, `--always --runs 1`
passes with the default nature, and `debug.jsonl` of an eval run shows
the NATURE section in the state.

**Depends on** R1.

**Per pack.** Engine change once; each pack's two nature files.

## R4. Variety inside `react`: the echo rule, the off die, the kind bump

**Issue.** Routine lines get one answer (A2, B1, B2), and nothing is
ever wrong on purpose (A7). Text couldn't fix it last night; Jev answers
a routine line at 0.96–0.99.

**Change.** `ReactOutput` keeps its last reaction (face, animation,
loops, kind, when) and a second seeded RNG, and reads the answers in
four steps instead of taking each top choice:

1. **Routine or notable?** Routine is a pass whose event is a turn end
   or a heartbeat, whose `react.animation` is `none` or `success`, whose
   `say.kind` isn't `swear`, and whose `react.mood` top probability is
   at least `routineFloor` (0.8). Everything else is notable and keeps
   Jev's answers whole: a failure, a reply, a wake-up, a poke, talk, a
   heard word (R8). So `03`, `05`, `16`, `17`, `23`, `35`–`40` and `60`
   can't change.
2. **The echo rule.** On a routine line, if the top face, the animation
   and the hold would all equal the last reaction's within `echoMs`
   (10 min), vary one, in this order: the hold (`once` → `twice`), else
   the kind (`sound` → `word`, `word` → `phrase`), else the face, to the
   second-best face with probability at least `secondBest` (0.15). The
   face comes last and only above 0.15 so `17` can't break: Jev never
   gives a wrong face that much at a win.
3. **The off die.** One routine reaction in `offDie` (12) takes the
   second-best face at or above `offFloor` (0.05), whatever the last
   was. The obtuse pet, seeded, repeatable, logged.
4. **The kind bump.** One routine reaction in `bumpDie` (4) takes the
   next kind up (sound → word → phrase). "Loud is better."

Every swap is recorded in the output's facts, beside `takes`:
`"varied": ["loops once → twice"]`, so `debug.jsonl`, `boopctl day` and
the evals can count them. `run` still returns `.started(message,
pending, facts:)`.

**Steps.**

1. `app/BoopKit/Outputs/ReactOutput.swift`: `last`, `dice`
   (`SplitMix64(seed: 0xD1CE ^ voiceSeed)`), the constants above as
   `static let`s, a pure `static func pick(_ answers: Answers, now:
   Event?, last: Last?, at: Int64, dice: inout SplitMix64) ->
   (face: String, loops: Int, kind: Take.Kind, varied: [String])` that
   `run` calls; `loops(_:)`, `kind(_:)` stay as "Jev's own pick".
2. A new `internal/app/Tests/ReactOutputTests.swift` (the runner is
   generated from the test files): (a) a notable line is never varied;
   (b) two identical routine answers 30 s apart differ in hold, kind or
   face; (c) the same two 11 min apart don't; (d) the off die hits 1 in
   12 ± 25% over 1,200 rolls and never a face under 0.05; (e) the kind
   bump never reaches `swear`; (f) `EvalTests`' scripted brain still
   passes `04` and fails `05` as before.
3. `internal/tools/boopctl_lib/day.py` and `workday.py` read `varied`
   from the action's facts, as they read `takes`.

**Specs.** `documentation/architecture.html` "Outputs and Voice" (one
sentence: `react` varies a routine answer that would echo the last);
`internal/EVALS.md` §1 (`varied` in the facts); a comment in
`ReactOutput` saying why (text couldn't).

**Stays untouched.** The harness, the questions, the steering, the
device. Jev is asked exactly what it's asked today.

**Evals.** `19-same-win-again`: `checks` gains `"max_same_in_a_row":
2`, `"min_variety": 3`; its case loses "The same face every time is
fine". `21-busy-session`: `"max_same_in_a_row": 2`, `"min_variety": 4`.
New `73-no-echo.json`: a comeback (tests fail, pass, reaction `done`),
the turn finishes 40 s later: the finish's `expect` has `react:
happy|pleased|proud|excited|calm` and the run `"max_same_in_a_row": 1`.
Cost: 19 (10), 21 (21), 73 (~6): about 37; then `--always --runs 1`
(165) once, since this touches every reaction.

**Done when** 19, 21 and 73 pass once, `--always` passes, the unit tests
pin the numbers, and a `21` timeline shows no two identical routine
reactions in a row.

**Depends on** nothing. R2's holds and R7's bigger says make the bump
visible.

**Per pack.** Engine, pack-agnostic: the rule reads Jev's probabilities
and the event's kind, never a mood name. Both packs' faces and takes.

## R5. Five new lines for the brain

**Issue.** The brain is deaf to a compaction, to you answering a
request, to what the agent is doing at a check-in, to idle time under an
hour, and to a poke while Boop sleeps or a barrage that comes again
(A5, B1, B4). Each is a view change: a line, facts and a wake, gated
like every other event.

**Change.**

1. **Compacted.** In `agentEvent`, a `.sessionStarted(source)` whose
   source is `Mapping.compacted` lines `claude's context on "api" was
   squeezed; it picks up where it left off.`, wake 0, facts thread.
   Boop's Example → `confused, looking in a sound, once` (the
   context-wall demo's "where was I?", now for real); `confused.md` gets
   R1's shape. Rule reactions and the COMPACTED card stay as they are.
2. **You answered.** `needs(_:)` lines a `needs_you` end whose `outcome`
   is `done`: `You answered claude on "api".`, wake 0, facts thread;
   failed ends (forgotten, the session ended) line nothing. `keeps`
   gains `(.needsYou?, .end?)`; `wakes` gains `"needs_you_end": 0`.
   Example → `happy, glad in a sound, then quiet... ` no: → `pleased,
   glad in a word, once` ("Nice", "Sweet"). The hold rule is untouched:
   with another request still waiting the pass is held as any is.
3. **The check-in says the topic.** `EventLine.working(agent:thread:
   ms:topic:)`: `claude is still working on "api", a very long turn,
   running tests.` (`running a build`, `deploying`, `editing docs`; none
   when there's no topic). The facts already carry it. Examples: with
   tests → `hopeful, work in a word, then tests, twice`; without → as
   now.
4. **An idle check-in.** A fourth heartbeat, `specificType:
   "idle-short"`, while at least one session is open, none works, and
   the last agent event, poke, talk or back was under `idleWindowMs`
   (2 h) ago, every `idle_heartbeat` seconds, a new front-matter rule
   (`boop` 900–1800, `chatter` 300–600, `pixel` 1200–2400, `none` to
   turn it off). Past the window the hourly heartbeat carries on as now,
   so nights and weekends stay silent and `06`, `55` keep passing. Line:
   `Nothing is happening; claude sits idle on "api".` Examples → `bored,
   quiet in a word, once`, → `lazy, quiet in a sound, twice`, → `none`;
   the guide: "An idle check-in is a small face or nothing, never a
   finish, and never moves the mood but to fade it." `EventLine.words`
   gains "An idle check-in means the person is around but no agent is
   working."
5. **A poke while asleep, and again.** `poke(_:)` adds `while it slept`
   when the fold has no sessions (`You poked Boop while it slept.`,
   facts `asleep`), and `, again` when the last run of pokes ended under
   `againMs` (2 min) ago (`You poked Boop 4 times in a row, again.`,
   facts `again`). Examples → `surprised, tickled in a sound, once`
   (the startle) and → `grumpy, upset in a phrase, twice` ("Personal
   space"); `grumpy.md`: "a barrage again, before it has calmed down,
   keeps it grumpy and makes it say so."

**Steps.**

1. `app/BoopKit/Core/Personality.swift` `Rules.idleBeatMs:
   ClosedRange<Int>?` from `idle_heartbeat`; the three personality
   files' front matter.
2. `app/BoopKit/Core/TranscriptView.swift`: `Config.idleWindowMs`,
   `nextIdleBeatAt`, the branch in `heartbeat(at:)` and the line in
   `heartbeat(_:)`; the `.sessionStarted` line in `agentEvent`; the end
   branch in `needs(_:)`; `keeps`, `wakes`; `poke(_:)` with
   `lastRunEndedAt`; `EventLine.compacted`, `.answered`, `.idle`,
   `.working(topic:)`, the `words` sentence.
3. `internal/app/Tests/ViewTests.swift`: each line with and without its
   condition; the idle check-in only inside the window, only with a
   session open, never while a thread works, never twice within its
   range; the answered line once per request and not for a forgotten
   one; `again` only within 2 min.
4. The eval runner gains steps `compact` (a `SessionStart` with source
   `compact`), `needs you` (a `PermissionRequest` for `Bash`), `answered`
   (its `PostToolUse`), and `pokes` takes `"count": N` (default 4) and
   `"asleep": true` (the step runs before any session exists).
5. `boop.md`, `chatter.md`, `pixel.md`, the mood files named.

**Specs.** `documentation/architecture.html` "View: sentences for Jev"
(the heartbeats, in a sentence); `characters/CHARACTER.md` §7 (the new
front-matter key); `internal/EVALS.md` §1 (steps), §3 (`count`,
`asleep`); CLAUDE.md's Words table if a word is new (none: "check-in"
is in use).

**Stays untouched.** The core (it already records the `needs_you` end
and plays the card), the harness, the device, `wakesWhileNeeded`.

**Evals.** New `74-answered.json`: a turn, `needs you` at 1m, `answered`
at 1m30s → `react: pleased|happy|calm|engaged`, `animation: none`,
`said: some|none`, mood unchanged or happy; the turn finishes at 3m.
`75-where-was-i.json`: a turn, tests fail, `compact` at 4m →
`react: confused|curious|baffled|calm`, `animation: none`, `about:
looking|none`; the turn finishes done at 6m → `animation: success`.
`76-idle-check-in.json`: a quick turn, then `wait` 50m with `"checks":
{"reactions": "1-3", "mood_changes": "-1", "moves_on_graph": true}` and
the last pass `react: bored|lazy|calm|comfy|none`, `animation: none`.
`77-poked-asleep.json`: `pokes` count 1, asleep → `react:
surprised|curious|happy|stunned`, `animation: none`. `78-barrage-again`:
`pokes` at 0s, `pokes` at 1m → the second `react: grumpy|irritated`,
`kind: phrase|word|sound`, `said: some`. `15-quiet-work` gains `about:
none|work|tests|waiting|quiet`. Cost: 74 (~5), 75 (~6), 76 (~4), 77 (1),
78 (~4), 15 (6): about 26, plus `06` and `55` once (~10) as regressions.

**Done when** the six pass once, 06 and 55 still pass, `ViewTests` pins
each line, and the context-wall demo's brain step reads as what Jev
now does.

**Depends on** R1 (room). Independent of R2–R4.

**Per pack.** Engine once; Examples in each pack. The idle check-in's
pace is per personality, so Pixel sets its own.

## R6. Idle and asleep life in both packs

**Issue.** Both faces turn their idle variations on their own and have
nothing comic or audible to turn to (A4). No yawn, nod-off, sneeze or
snore exists, and idle and asleep designs are all `silent`.

**Change.** Pack content only, no Mac change, no Jev.

*Pixel's face* (`characters/pixel/design/boop-sound-bank-v4/`, which
Boop wears on the CYD): three idle variations and one asleep one, each a
generator in the bank's style, drawn for all 13 moods by the bank's
mood art:

- idle 4 "Yawn and stretch" (9 s): the wake-up's yawn, slower, once per
  loop; sound policy `entry` (the yawn tone once, when the variation is
  turned to).
- idle 5 "Nodding off" (12 s): eyes droop into the asleep pose for 2 s,
  snap back with a blink; `silent`.
- idle 6 "Sneeze" (10 s): a wind-up, a sneeze, a shake; `sparse` with
  `every` 3 (the sneeze sounds one loop in three, so about once a
  minute while it's the variation showing).
- asleep 4 "Snore" (12 s): two soft breaths per loop; `sparse`, `every`
  4 (about every 50 s), quiet. The other three asleep designs stay
  silent, so a sleeping Boop snores now and then, not always.

The device's variation turn (`kTurnPct` 67 at each loop end) spreads
these over an idle hour by itself. With six idle variations each shows
about a sixth of the time.

*The gel* (`characters/boop/design/slime-blob/`): `state-plan.json`
idle gains `yawn-and-settle`, `doze-and-snap`, `sneeze-and-shake` as
variations 4–6, asleep gains `snore` as variation 4 with `audioPolicy`
`sparse_contacts` for that variation only (a soft clip on its contacts,
`sound/`); `expressions.json` gives bored, tired, lazy and comfy a yawn
among their three performances. `slimegen` regenerates `slime.h`;
`Bag` picks among 3, so raise `kCanonical`'s per-state bag size where
the recipe count grows (one constant in `acting.h`/`scenes.h`, pinned
by `static_assert`).

**Steps.**

1. Pixel: the bank's generators (`runtime/`), `catalog.mjs` entries,
   `make -C internal faces` (about 7 min; pixel-for-pixel against
   Chrome), `node characters/pixel/tools/sfxgen/sfxgen.mjs`; `faces.json`
   and `faces.h` grow; `FaceLoops.count` follows; the 180 KB asset
   ceiling in `sfxgen`.
2. Gel: the JSON inputs, `node characters/boop/design/slime-blob/tools/
   build.cjs`, `node characters/boop/tools/slimegen/slimegen.mjs`,
   `check-port.py`.
3. `make -C internal fw-test`: `test_effects` pins the sparse policies;
   `test_face` the variation counts.
4. `make -C internal sim`: `life.jsonl` gains a frozen-clock turn to
   idle 4 and asleep 4 with a cue expectation; new goldens for both
   faces.
5. The owner flashes (`make flash`) and listens to the snore's level on
   both boards.

**Specs.** `characters/CHARACTER.md` §9 (variation counts if quoted),
`characters/pixel/design/README.md`, the slime's `STATES.md` and
`VALIDATION.md`, `simulator/README.md` if a scenario is listed.

**Stays untouched.** The Mac entirely; the protocol (`variant` already
travels); the brain.

**Evals.** None with Jev. The sim scenario and `fw-test` pin it.

**Done when** `faces`, `fw-test` and `sim` pass with the new goldens
accepted, and the owner has heard a snore and a sneeze on a board.

**Depends on** nothing. Can run in parallel with everything else.

**Per pack.** Pixel's bank serves both packs' CYD face; the gel is
Boop's own. Pixel gets the idle life on the CYD for free.

## R7. Comedy on the finish, and bigger says for big holds

**Issue.** The owner's hiccups, the gift and the zoomies have nowhere to
show; and a four-times hold says the same two takes as a once (C7).

**Change.**

*Pack content, as variations of states that exist:*

- Hiccups: `task_complete` success variation 5 on Pixel's face ("Trophy,
  then hiccups": the trophy, then three hiccup bounces, 8 s; `entry`
  policy with three clicks) and a `bounce-and-card-hiccup` recipe on the
  gel. Both faces pick a success variation never-the-last, so one cheer
  in five hiccups.
- The gift: proud's `task_complete` success variation 2 redrawn so Boop
  holds up a pixel bug (the comeback cheer is proud's by `09`); on the
  gel, proud's `lift-and-card` lifts a small bug. The word is Jev's
  (`done` or `tests`).
- Zoomies: excited's `working` variation 6 and `idle` variation 7, the
  face zipping around the screen; the gel: an excited performance that
  slides the dome edge to edge. Shows after a very long turn done, while
  the mood is excited, through the variation turn.

*Bigger says (engine, small):* `Voice.say` takes `loops`; for three
times or more a phrase may be followed by the topic's word when the two
fit in `maxSayMs` raised to 3,400 ms for those holds (the device plays
two takes of any length; its bubble buffer holds two texts). Once and
twice keep today's rule. `ReactOutput.run` passes `loops`.

**Steps.**

1. Pixel's bank and the gel's inputs as in R6; `faces`, `sfxgen`,
   `slimegen`, `fw-test`, `sim` (`finish.jsonl` gains the hiccups).
2. `app/BoopKit/Voice/Voice.swift` `say(... loops:)`, `maxSayMs(for
   loops:)`; `VoiceTests` pins both caps and that a phrase + word only
   comes at three or more; `RuntimeTests`'
   `testAReactionEndsBeforeTheHarnessCeiling` still holds (the longest
   hold plus the longest say must end before `openForMs` 90 s).
3. `boopctl play --take` to hear a phrase + word pair on a board.

**Specs.** `characters/CHARACTER.md` §8 (a say is up to two takes; the
cap by hold), `documentation/architecture.html` if it quotes 2.8 s.

**Stays untouched.** The questions, the device's player, the protocol.

**Evals.** None with Jev for the art. `02-long-turn` gains `loops:
three times|four times`, `said: some` (~10) once R2's holds land.

**Done when** the goldens are accepted, `VoiceTests` pins the caps, and
the owner has seen hiccups on a board.

**Depends on** R6's generator work (share it). R2 for the holds.

**Per pack.** Pixel's bank for both CYDs; the gel for Boop's AMOLED.

## R8. Ears: a listener that only writes events

**Issue.** Boop can't hear its name, a few words, a clap, a shout or a
sing-song voice without the button held (A3, A9, C4). The brief wants
about 20 words, mistakes on purpose, a startle, and tone.

**Change.** An opt-in component, off by default, Mac-side, in the app
target beside push-to-talk (`app/Boop/Ears.swift`; BoopKit stays free
of AVFoundation and Speech). It uses `AVAudioEngine`'s input tap for a
level meter and a pitch estimate, and `SFSpeechRecognizer` with
`requiresOnDeviceRecognition = true` and `contextualStrings` set to the
word list, restarted every 50 s; `supportsOnDeviceRecognition` false
refuses the toggle and says why. It never writes audio anywhere; the
recogniser's partial results are matched against the list and dropped.
It yields to push-to-talk (stops its engine when the mic is held,
restarts after) and emits only raw events, debounced to one per 3 s:

- `heard` with `specificType` one of about 20 words in `Ears.words`:
  `name` (whatever the person called Boop), `good` ("good boy", "good
  girl", "good job"), `no`, `bad`, `dance`, `sleep`, `wake up`, `hello`,
  `bye`, `shh`, `stop`, `who` ("who needs me"), `come`, `sit`, `speak`,
  `treat`, `fetch`; the everyday ones (`no`, `stop`, `sleep`, `sit`)
  only within 3 s of the name, so talk at the desk doesn't train it.
- `heard` with `specificType` `bang` (level over `bangDb` −18 dBFS for
  under 300 ms with no speech), `shout` (speech with level over
  `shoutDb` −22 dBFS for 500 ms), `singsong` (pitch swinging over
  `singRange` 7 semitones within 2 s). First guesses; the owner tunes
  by ear.

The view lines them (`EventLine.heard`): `Boop heard its name.`, `Boop
heard you say "dance".`, `Boop heard a bang.`, `Boop heard you shout.`,
`Boop heard you singing.`; wake 0; not in `wakesWhileNeeded` (while
amber shows, the sign already answers "who needs me", and the reaction
would be blocked anyway). `EventLine.words` gains "Boop hears its name,
a few words and three kinds of sound; it can't understand anything
else." Examples (Boop): name → `curious, tickled in a word, once`;
`good` → `proud, glad in a phrase, twice`; `no` → `embarrassed, upset
in a sound, once`; `dance` → `excited, glad in a phrase, four times`;
`sleep` → `tired, quiet in a word, twice`; `hello` → `happy, glad in a
sound, then hello, once`; `shh`/`stop` → `none`; `who` → `calm, quiet
in a word, once`; `bang` → `surprised, upset in a sound, once` (the
startle; Jev answers in 100–300 ms, fast enough); `shout` → `wounded,
upset in a sound, twice`, mood `wounded|sad` (hero moment 3);
`singsong` → `affectionate, tickled in a sound, once`. Pixel: the same
in prose.

**Wrong on purpose.** A pack says which heard words it gets wrong, as
data: `character.json` gains an optional `"mischief": {"odds": 5,
"swaps": {"dance": "tired", "sleep": "excited", "sit": "mischievous"}}`.
On a `heard` line whose word is in `swaps`, `ReactOutput.pick` (R4)
rolls `odds`; on a hit the face becomes the swap, the hold `twice`, and
`varied` says `mischief: dance → tired`. Jev's answer is kept otherwise.
One die, one table, pack-owned.

**Steps.**

1. `app/BoopKit/Core/Event.swift`: `Kind.heard`. `TranscriptView`:
   `keeps`, `wakes["heard"] = 0`, `heard(_:)` with facts `what`;
   `EventLine.heard`, `words`; `ViewTests`.
2. `app/BoopKit/App/Pipeline.swift` `heard(_ what: String, at:)` beside
   `said`; `Runtime.heard(what:)`; the core isn't called.
3. `app/BoopKit/Character/CharacterPack.swift`: `mischief` (optional;
   `PackCheck` refuses a swap to a mood the pack doesn't have);
   `ReactOutput.pick`'s roll; `ReactOutputTests` (the die hits 1 in 5
   ± 25% over 1,000 rolls; a word not in `swaps` never swaps).
4. `app/Boop/Ears.swift`; `Runtime` starts and stops it from
   `AppSettings.ears`; `SettingsPane` "Ears" toggle with one line and
   the privacy note; `Arguments` `--ears` for `Boop --headless`;
   `Info.plist` already carries the mic and speech usage strings.
5. `characters/boop/steering/personality/boop.md`, `chatter.md`,
   `characters/pixel/steering/personality/pixel.md`; both
   `character.json`'s `mischief`.
6. The eval runner's `heard` step with `"what"`.
7. The owner tests the recogniser from a terminal the Claude app opened
   (an agent's shell has no mic permission): `Boop --headless
   --state-dir /tmp/ears --ears --debug`, then its name, "good boy", a
   clap, a shout, and `debug.jsonl`'s `heard` events.

**Specs.** README.md "What leaves your Mac" (with Ears on, only which of
the words or sounds was heard reaches the transcript and Jev; no audio
is recorded or sent; the recogniser is on-device or the toggle refuses);
`documentation/architecture.html` "Where the pieces join" (a row: the
Mac's mic → Boop, `Runtime.heard`, one raw event like a poke);
`characters/CHARACTER.md` §4 (`mischief`); `internal/EVALS.md` §1 (the
step); `internal/VERIFICATION.md` §2 (`--ears`, the owner's check);
CLAUDE.md "Never do these" (don't turn Ears on from an agent shell).

**Stays untouched.** The core, the harness, the device, push-to-talk,
"needs you".

**Evals.** `79-good-boy.json`: `heard good` → `react:
proud|happy|pleased|affectionate`, `said: some`, `loops:
twice|three times`. `80-shouted.json`: a turn working, `heard shout` →
`react: wounded|sad|scared|frightened`, `mood: wounded|sad|scared`, then
a finish 3 min later → `animation: success`, `react` not grumpy.
`81-dance.json`: `heard dance` → `react: excited|happy|mischievous`,
`loops: three times|four times`, `"checks": {"reactions": "1"}`.
`82-shh.json`: `heard shh` while working → `react: none`. The mischief
die is unit-tested, not evaled. Cost: about 8.

**Done when** the four pass once, `git grep -n "AVAudioFile\|write(to"
app/Boop/Ears.swift` finds nothing, the owner has seen `heard` events
for their name, a clap and a shout, and `--always --runs 1` passes.

**Depends on** R1 (room), R4 (`pick`), R5 (the view pattern is fresh).
Last.

**Per pack.** Engine once; each pack's Examples and `mischief` table.

## R9. Evals and the working day hold the fun

**Issue.** The evals fail when Boop makes the wrong face, never when it
is dull, quiet or repetitive (D). Pixel has no evals. Codex has none.

**Change.**

1. `max_same_in_a_row` and `min_variety` on in `19`, `21` (R4) and `22`
   (`"max_same_in_a_row": 3`).
2. `Eval.judge` gains `words_said` (a range over the share of played
   reactions with a take, `"0.5-"`) and `varied` (a count range of
   `react`'s swaps, from the facts), both in `Checks.keys`; `21` turns
   `words_said` on at `0.5-`.
3. `said: some` at the hero moments: `02`, `03` (R2), `05`'s first poke,
   `08`, `16`'s first barrage.
4. `workday.py` `LIMITS`: `max_repeat_pct: 40`, `max_longest_same_run:
   3`, `min_words_said: 0.5`; `check` holds them; `report` prints a fun
   ledger per hour: distinct reactions, reactions with a word, the
   longest identical run, `varied` count, idle check-ins. The
   "reported, with no limit: repeats are fine" sentence goes. `boopctl
   day` gets the same ledger. `internal/tools/boopctl_lib/tests/
   test_workday.py` covers the limits; a scripted day should fail the
   repeat limits (the scripted brain repeats), which is the test.
5. The runner takes `"agent": "codex"` on a step (events from source
   `.codex`, hooks per `Mapping.codex`); `83-codex-turn.json`: a Codex
   turn with a command and a `Stop` after 3 min → `animation:
   success|reply`, `react` not grumpy or sad; nothing else fires.
6. `characters/pixel/evals/`: five scenarios in Pixel's words (a
   failed turn, pokes, a long finish, back after a break, an idle
   check-in), run as `CHARACTER=pixel .build/debug/boopdev eval
   --scenarios characters/pixel/evals --steering
   characters/pixel/steering`; `internal/Makefile` gets `eval-pixel`.
7. Demos: `the-cheer.jsonl` and `the-cuss.jsonl` in both packs (R2 makes
   the cuss); `boopdev check` plays them; `make demo NAME=the-cuss`.
8. `internal/EVALS.md` §4's kinds gain "Fun (19, 21–23, 70, 73–82)".

**Specs.** `internal/EVALS.md` §1, §3, §4, §5; `characters/DEMOS.md`
(the two demos); `internal/VERIFICATION.md` §2 (`eval-pixel`);
`characters/CHARACTER.md` "At a glance" (a pack's `evals/`).

**Stays untouched.** The runner's shape, the existing checks.

**Evals.** Each check runs with the scenario that turns it on; `83`
once (~3); Pixel's five once (~15).

**Done when** `boopdev eval --list` shows every new scenario with a
case, `EvalTests` covers each new check and step without Jev, and
`workday check` on a scripted day exercises the three new limits.

**Depends on** R2, R4, R5, R8 for the scenarios each adds; the checks
and the working day can land first.

**Per pack.** Boop's evals and the working day; Pixel's new five.

## R10. Only if needed: one new animation state

**Issue.** If a variation can't carry a thing (a real dance to "dance",
a huff with steam at a barrage), it needs a state of its own, which is
engine work the owner's rule says to avoid until it's earned.

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
brain answers. About a day, both packs, then `03`/`16`/`81` once each
(~20).

**Do it** only after R6–R8 have shown what the variations can't do.

## Not now

- **Growth in the prompt** ("Boop is a Sprout: it knows three
  tricks"): a one-line section and a `tricks` table is cheap, but it's
  tuning personalities, which the owner put later.
- **A startle by rule** on the device: Jev at 100–300 ms is fast enough
  for a `bang`; a rule that picks a face breaks "the brain is never on
  the screen's path" the other way round.
- **Double tap, stroke, shake:** the CYD's resistive panel and BOOT
  make a poor stroke; the gel's drag is a reflex already.
- **A buddies eval:** the runner is one buddy; the `not-my-turn` demo
  and `BuddiesTests` cover it.

## Order, dependencies and cost

| Stage | Items | Why this order | Jev requests |
| --- | --- | --- | --- |
| 1 | R1, R2, R3, R9's checks and `said`s | Room first; the cuss and nature are text; the checks make the later stages measurable | ~85 (17, 47, 53, 03, 08, 04, 70, 71, 72, 05, 61) |
| 2 | R4 | Variety; the one engine change with the biggest daily effect; shares `19`, `21` | ~37, then `--always --runs 1` (165) |
| 3 | R5 | The five lines; the view pattern R8 copies | ~36 (74–78, 15, 06, 55) |
| 4 | R6, R7 | Pack art and sound, in parallel with 2–3 | 0 (~10 for `02` after R2) |
| 5 | R8 | Ears, last: copies R5's pattern and R4's die | ~8, then `--always --runs 1` (165), plus the owner at the Mac |
| 6 | R9's rest | Codex, Pixel's evals, the demos, the working day | ~18, plus one scripted `workday` (free) |
| Before merging | `boopdev eval --runs 1 --no-budget` | Every scenario once, new ones included | ~450 |

About 1,000 requests in all at one run each, against last night's 1,360
for a comparable night; `make eval` at the default runs (660 today,
about 760 after) is for the owner's final pass, if at all.

What a subagent must not do: add a question to Jev, change the harness's
contracts, put a rule that chooses a face or a word anywhere but
`react`, send a new message type to the device, add a state without R10
being chosen, or let anything but a word from `Ears.words` or one of its
three sounds reach the transcript from the mic.
