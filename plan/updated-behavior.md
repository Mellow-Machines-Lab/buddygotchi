# Updated behaviour: the plan (2026-10-21, outcome 2026-10-22)

The implementation plan for everything marked Yes in
[product-ideas.md](product-ideas.md), for an overnight run. It lands on
`feature/updated-behavior`, not `main`.

## Outcome (2026-10-22)

Stages 0 to 7 landed, one commit each, plus a build fix. Then a
second pass, at the owner's word: the gel's own art, the simulator's
motion buttons, the review's deeper cleanups, and stage 8 started.

**Checks that ran and passed** at the last commit:
- `.build/debug/BoopTests`: 349 passed, 1 skipped.
- `boopdev eval --scripted`: 82 of 82 on the expect brain.
- `make -C internal fw-test`: 224 and 55.
- `make -C internal sim`: Pixel's 18 scenarios and the gel's 6.
- `make -C internal fw`: both boards build (CYD flash 65.1%, AMOLED 41.1%).
- `make -C internal sim-test`: the core's tests and the page's 12.
- `make -C internal tools-test` and `faces`; slimegen `--check`,
  `check-mirror.mjs` and `check-port.py`; `charactergen --check`; the
  bank's `qa/check.mjs`; `boopdev check`.
- `boopctl workday run --brain scripted`, then `workday check`: every
  limit but `min_mood_changes`, which the scripted brain can't meet
  because it never changes mood.

**Not run:** any Jev eval or Jev workday (no key here), and anything on
a board (no Bluetooth or webcam from an agent shell).

**Stage 8, waiting on a push.** AgentHooks' branch
`terminal-tab-and-edit-sizes` (14b0bf4, in `agent-hooks/`, not pushed)
records the terminal and tab a session runs in and opens that tab
(iTerm2, Terminal.app, tmux), and counts the lines an edit adds and
removes. Boop's side is the local branch `boop-terminal-tab`: the
popover's "open its tab in …", the Automation prompt's words in
Info.plist, and a finish that says `, 1,200 lines gone` once a turn
removes 500 lines or more net (eval 100). It leaves out the submodule
pointer: push AgentHooks' branch, merge it, bump `agent-hooks` in that
commit, then merge it here. Neither has met a real terminal.

**Left for the owner:**
- **Regional holidays.** Only the fixed list in `Occasions` is in, which
  is fine for now.
- **The gel's art is best effort.** Its gestures borrow a face each;
  it has no colour for a party, and no occasions for April Fools, Pi
  Day, May the 4th or Friday the 13th. The studio plays only the first
  gesture.
- **The QMI8658's axis signs.** `kFlipZ` in
  `firmware/src/board/amoled206/imu.cpp` is a guess until the board is
  turned over on the desk; check `dbg.imu`.
- **Touch thresholds.** `kStrokePx`, the swipe's speed (`kSwipePxPerS`),
  the tickle path and the nose box are tuned on the simulator, not under
  a finger on the board; `dbg.state`'s `touch.last` shows each touch's
  path, time and what it was.
- **Gestures by position.** A gesture's design is its place in
  `render::Gesture`'s order. Both faces now draw all ten (the gel's
  test pins its count), so naming them was left alone.

## The shape, in one paragraph

The engine gets four small, generic things and nothing else: **tags**
(`when`, a set of words that say when a design or a diary line fits),
**`after`** (how long a look has shown before a variation may play),
three counts in the `state` message (`idle`, `helpers`, and `when`
itself), and **one new reaction state, `gesture`**, whose fact `kind`
says what the person did (as `task_complete`'s `outcome` does). The
board owns every look's variation and every reflex. Everything that
decides *how Boop feels about it* is a line in the view plus Examples
in the steering plus evals, so a later rules brain can be read off the
evals. No new question for Jev except the diary's one, asked once a day.

## Ground rules (from the owner, and the fun plan)

- Made for buyers of a ready-made Boop: nothing a person must learn.
- One buddy first. Two-buddy work is demos only.
- Everything on the buddy; nothing on a phone.
- Nothing that keeps the Mac's mic on. Push-to-talk on BOOT stays.
- Keep the engine simple; the complexity goes in the brain parts (the
  steering, the evals, the packs' content).
- Every feature lands with a demo and evals, and a test that pins each number.
- Don't add a question to Jev (except the diary's), don't change
  MellowHarness's contracts, don't put a rule that chooses a face or a
  word anywhere in the engine, don't send a new message type (the four
  stay), don't let the board decide *what* Boop does (only when it plays).
- "Needs you" stays exactly as it is: a core rule, held by the device
  over everything, nothing but your words waking the brain while it shows.

## Where to work

- **Base:** `feature/updated-behavior` at `e637c38` (main + the studio
  matrix + the fun work merged). It is checked out in the worktree
  `.claude/worktrees/bridge-cse_01GAkMPNeRLsr58fJVHj7D3S`, so make a new
  worktree: `git worktree add .claude/worktrees/updated-behavior-2 -b
  updated-behavior-2 feature/updated-behavior`, then `git submodule
  update --init` in it (both submodules are empty in a fresh worktree).
- **Landing:** when the run ends, fast-forward the feature branch from
  its own worktree: `git -C .claude/worktrees/bridge-cse_01GAkM… merge
  --ff-only updated-behavior-2`. Never touch `main`, never push.
- **One commit per stage** below, each with its tests, docs and
  demo. The owner squash-merges later, so the stage commits are the
  record: say what ran and what it showed in each message.
- **Jev:** `BOOP_JEV_KEY` is probably unset. Price every scenario with
  the scripted brains (free). Run Jev only if the key is there, and say
  in the commit which runs happened. Never look for the key.
- Before each stage, check `git log --oneline HEAD..feature/updated-behavior`
  prints nothing.

## The verification loop (every stage)

`make build`; `.build/debug/BoopTests`; `make -C internal test` at
stages that touch the packages; `make -C internal fw-test` and `make -C
internal sim` at stages that touch the firmware (re-record goldens only
when the picture is meant to change, and say so); `make -C internal fw`
(both boards) at the end of each firmware stage; `python3
characters/charactergen.py --check`; `.build/debug/boopdev check`;
`boopdev eval --list` (prices). The full rule set is
[internal/VERIFICATION.md](../internal/VERIFICATION.md) §1.

---

## Stage 0. Baseline

Build and run the whole loop on the untouched base so a later failure
is known to be yours. Note the counts (BoopTests 341 passed, 1
skipped on the fun branch; fw-test 210 + 55; sim 17 + 4 scenarios).

## Stage 1. Ears out

Always-on hearing keeps the Mac's mic indicator on, so it goes (the
owner's call). Push-to-talk stays as it was before the fun work.

- Delete `app/Boop/Ears.swift`, `app/BoopKit/Ears/Hearing.swift`,
  `internal/app/Tests/HearingTests.swift`, evals `79-good-boy`,
  `80-shouted`, `81-dance`, `82-shh`, `86-misheard-dance` and their
  golden states.
- `git checkout main -- app/Boop/Talk.swift` (the "simplify" commit only
  moved the mic code into `Mic` for the ears; main's is the push-to-talk
  it was).
- Take the ears hunks out of: `Package.swift` (the file list),
  `app/Boop/main.swift` (`--ears`), `app/Boop/MenuBarApp.swift`
  (`earsTrouble`, `setEars`, the `Ears` build, pause/resume around
  push-to-talk), `app/Boop/Views/SettingsPane.swift` (the Ears row),
  `app/BoopKit/App/AppSettings.swift` (`ears`), `Pipeline.swift`
  (`heard`), `Runtime+Status.swift`, `Runtime+Talk.swift` (`setEars`,
  `heard`), `Runtime.swift` (`onEars`), `Core/Event.swift` (`.heard`),
  `Core/TranscriptView.swift` (the `heard` wake, `keeps`, `take`, `func
  heard`, `EventLine.heard`, the guide bullet "With its ears on…"),
  `internal/app/Boop/Headless.swift` (`--ears`),
  `internal/app/BoopDevKit/Eval/Eval.swift` (`what`, `misheard`, the
  `heard` step), the steering (`boop.md`'s "What it hears, it takes like
  a dog…" paragraph and its ten `heard` Examples; `chatter.md`'s two;
  `pixel.md`'s bullet), `README.md`, `CLAUDE.md`/`AGENTS.md` (the ears
  rule and row), `documentation/architecture.html` (the mic row),
  `internal/EVALS.md`, `internal/VERIFICATION.md`.
- Re-record the golden states (the guide bullet changed every prompt).
- Tests: the ones that remain pass; `grep -ri "ears\|heard\|Hearing"`
  over `app/ internal/ characters/*/steering documentation` finds only
  push-to-talk's words.

## Stage 2. Evals and demos can carry everything that follows

The loop every later stage uses. Nothing here changes behaviour.

**The eval runner** (`internal/app/BoopDevKit/Eval/Eval.swift`):

- Header `start`: a local date-time, `"2026-10-31T09:00"`, that sets the
  virtual clock (default stays `Replay.defaultStart`, Wednesday 14:00).
  `LocalTime` in evals is UTC; keep it, and write scenario starts in UTC.
- New steps, each one input: `button` (a BOOT press, stage 4), `gesture`
  with `kind` (stage 7), `helper started` and `helper returned`
  (`SubagentStart`/`SubagentStop` hooks, with `session`; stage 5).
- `expect` gains screen fields, checked against the core's
  `StateSnapshot` after the step's inputs (no brain needed, so they're
  free): `look`, `idle`, `helpers`, `when` (a `|` set of tags that must
  all be present), `attn` (`some|none`), and `opens` (the thread a
  `button` step opened, `agent · thread`, from the `open_thread` did).
  A step with only screen `expect`s needs no pass; today the runner
  throws when nothing woke the brain, so relax that to "throws when a
  brain field is expected and nothing woke it".
- A scenario may also carry `brain` on a step (one answer per question,
  as a demo does): the **expect brain** (`ScriptedBrain.expecting(scenario)`,
  in BoopDevKit) answers each step from its `brain`, else the first
  option of each `expect` set, else as `pipelineCheck` does. Use it for
  pricing in place of `pipelineCheck`, so prices and prompts follow the
  scenario.
- `boopdev eval --to-demo NAME DIR` writes the scenario as a demo
  script (`DIR/NAME.jsonl`): `turn started` → `prompt`, `command` →
  `run` (`ask` for `needs you`/`answered`), `turn finished`/`failed` →
  `reply`, `poke`/`pokes`, `said` → `talk`, `away`+`back` → `back`,
  `compact`, `button`, `gesture`, helpers → `review`, with a `brain`
  step from the expect brain after each step that wakes it and the
  header's `start`. Then `make demo` plays any eval in the simulator.
  That is "auditing the evals is watching them".

**The demo format** (`app/BoopKit/Demo/DemoScript.swift`, `Runtime+Demo.swift`):

- Header `start` (as above; the headless app's clock starts there).
- A step may name a `session` (default `demo`): the player keeps one
  session id and cwd per name (`demo-<name>`, `/demo/<slug>-<name>`), so
  one buddy can run several agents in a demo.
- Steps `button` and `gesture` (`kind`), sent to the headless app as the
  device's `ev` would be (the dev socket's `tap` line gains `src`, and a
  `gesture` line).

**Docs:** `internal/EVALS.md` §3 (the new header, steps and `expect`
fields, the expect brain, `--to-demo`), `characters/DEMOS.md` (the
header, `session`, the two steps), `internal/VERIFICATION.md` §2.
**Tests:** `EvalTests` load a scenario with each new field and reject a
bad one; a `--to-demo` round trip of `05-pokes…` loads as a demo;
`DemoScript` tests for `session` and `start`.

## Stage 3. Tags, `after`, and the board owns its variations

The one generic mechanism that time of day, Fridays, holidays, day
counts, frantic, and the time-in-look animations all ride on.

**Tags** (`app/BoopKit/Core/Occasions.swift`, pure, tested):
`Occasions.tags(at: ms, hatched: day, busy: Int, time: LocalTime) -> [String]`:

| Tag | When |
| --- | --- |
| `morning`, `day`, `evening`, `night` | 05–11, 11–17, 17–22, 22–05 local |
| `friday`, `weekend` | the weekday |
| `friday13` | the date |
| `newyear` 01-01, `valentines` 02-14, `piday` 03-14, `aprilfools` 04-01, `may4` 05-04, `halloween` 10-31, `winter` 12-24…26, `programmers` the 256th day of the year, `lunar` (Lunar New Year's day, from `Calendar(identifier: .chinese)`) | the date |
| `party` | a milestone day since `hatched`: 10, 50, 100, then every 100, and each anniversary |
| `busy`, `frantic` | 2–3 sessions working; 4 or more |

Regional holidays (Thanksgiving, Diwali, Eid) wait for the owner's
answer on regions. Pin every boundary in `OccasionsTests` (the hours,
each date, Lunar New Year for 2026-02-17 and 2027-02-06, the 256th day
in a leap year, day 10/50/100/200 and the anniversary).

**The `state` message** (`StateSnapshot`, `Core.snapshot`): three
fields after `busy`: `idle` (sessions idle, from `tracker.grouped`),
`helpers` (helpers running, summed over working sessions' `helpers`),
`when` (the tags). Stay under LinkKit's 512 bytes: tags are short, at
most ~8 at once. The core gets `hatched` through `Core.Config`
(`Runtime` has it from `MemoryStore.longTerm`; evals pass the start day).
`variant` leaves the `state` message: see below.

**The prompt's heading** (`Pipeline.init`, `options.heading`): today
`14:05, Tuesday`; now the calendar tags join it in words, `14:05,
Friday, Halloween` and `09:01, Monday, Boop's 50th day`, so Jev
always knows and can play along without a new line. Examples in the
steering may quote the heading: `- NOW (Halloween): You came back to the
Mac after a very long break. → mischievous, wake up, …`. (`busy`/`frantic`
don't go in the heading: the check-in line already says what works.)

**The board owns look variations.** Today the Mac picks a look's first
variation and Pixel honours it while the gel ignores it (`gel/face.h:22`).
Make Pixel do as the gel does: `Device::onState` stops reading
`variant`; `anim.cpp`'s `pick` for looks is random among the fitting;
delete the Mac's `shown.variant`, `lastVariant` for looks and the
repick in `Core.publish`, and `FaceLoops.variants`/`Core.pickVariant`
for looks. Reactions keep `variant` in the `do` (the Mac still picks
among `outcome`/`ctx` fits, avoiding the last), unchanged. Update
`linkkit`'s example and `characters/CHARACTER.md` §9 ("The Mac picks
one" → "the board picks"), the device tests, the demo recordings that
pin `variant` in `state`.

**Eligibility on the board** (`characters/pixel/firmware/src/render/pixel/anim.cpp`
`fitting`/`step`, and the gel's `Acting`/`scenes.cpp`): a design may
carry `when` (tags) and `after` (ms). A design fits when every one of
its tags is in `state.when` and the look has shown at least `after`.
When any fitting design carries a tag, the turn picks among the tagged
ones `kTaggedPct = 67`% of the time (so a costume or coffee shows
more than one-in-seven, and ordinary life still turns up). Pin
`kTaggedPct` and the `after` gate in `fw-test`. The generated tables:
`faces.h` gains `when` and `after` per design (facegen), `faces.json`
the same (for `charactergen --check` and the studio), the gel's
`expressions.json` gags and `state-plan.json` scenes gain `when`/`after`
(slimegen). `charactergen --check` refuses an unknown tag (the list
lives in one place: `Occasions.all`, exported to the packs' check as
`characters/tags.json`, generated).

**Frantic** is `busy`/`frantic` tags plus pace: the working looks play
at ×1.25 and ×1.6 (`anim.cpp` pace for Pixel; `baseMotion` speed for
the gel), pinned in tests. Packs may tag designs `frantic` later.

**The studio:** the matrix gains a tag picker and a time-in-look slider
so each `when`/`after` design can be seen (`characters/studio/`).

**Pack content for this stage** (small, so the mechanism is proven):
Pixel: tag "Nodding off" `after` 20 min on `idle`; the snore `after` 10
min on `asleep`; a new "coffee" idle/working variation tagged `morning`
and a "pyjamas" one tagged `night` (facegen, the wake-up's helpers);
a "sweat" working variation tagged `frantic`. Gel: the yawn gag
`after` 20 min; a nightcap prop on `night`; a mug on `morning`. Both
packs' `--check` pass.

**Tests:** `OccasionsTests`; `CoreTests` for `idle`/`helpers`/`when` in
the snapshot; `fw-test` for the gate and `kTaggedPct`; `sim` scenarios
at `night`, `morning`, `frantic` and 25 min into `idle` (new goldens,
said so); evals `90-halloween-morning.json` (start 10-31 09:00, `back`
→ wake up, `expect.when` has `halloween|morning`) and
`91-day-50.json`.
**Docs:** CHARACTER.md §9 (`when`, `after`, the board picks, the tag
list), `firmware/README.md` (pace), `simulator/README.md`,
`documentation/architecture.html` (the heading and `state`'s fields),
CLAUDE.md's Words table (`tag`, `occasion`).

## Stage 4. BOOT opens the next one

- **The wire:** `ev tap` gains `data.src`: `"screen"` or `"button"`
  (`firmware/src/app/device.cpp` `tapped`, from `readInputs`). The
  headless dev socket's `tap` line takes `src` too.
- **The board's reflex:** a BOOT tap while `state.attn` or `state.idle >
  0` plays `gesture` with `kind: handoff` (the new state, below) instead
  of `poked`; otherwise `poked` as today. A screen tap is unchanged.
- **The core rule** (`Core.poked` grows a `src`): a button press opens
  the next thread: those that need you, oldest first, as now; then the
  idle sessions, newest first. A press within `Core.walkMs = 8_000` of
  the last button press opens the one after the one last opened (the
  core keeps `lastHanded: (thread, at)`); after that it starts again at
  the top. Recorded as the `open_thread` did, `by: "button"`, with
  `facts: {agent, thread, more}`; the view makes it a line that wakes
  the brain: `Boop handed you claude on "api"; 2 more sit idle.` A
  button press with nothing to open is a poke. Pin `walkMs`, the order
  and the restart in `CoreTests`.
- **The exact tab** is stage 8 (it's an AgentHooks change).
- **Steering:** one Example per pack (`→ pleased, glad in a word, then
  hello, once`), and the guide's words say the button hands you an agent.
- **Evals:** `92-button-hands-over.json`: two sessions finish, one
  needs you; three `button` steps with `expect.opens` in the right
  order, then a fourth 10 s later that starts again.
- **Demo:** `boop/demo/handoff.jsonl` and Pixel's: three agents, two
  finish, BOOT twice.
- **Docs:** architecture.html (the tap row), CHARACTER.md §9 (the
  `gesture` state's `handoff`), DEMOS.md, the popover's hint text.

**The `gesture` state** lands here (the one engine change for a new
reaction state, used by stages 4 and 7): `SceneState::kGesture`,
`stateName "gesture"`, a fact `kind`; `charactergen --check`'s table,
`faces.json`'s `states`, `FaceLoops`, `DeviceReaction.anims`,
`ReactOutput.scenes` (not offered to Jev: it's the board's own, like
`poked`), the gel's families and `kRecipeStates`, the studio's
`states.json`. Variations pick by `kind` exactly as `task_complete`'s
do by `outcome`. This stage draws only `handoff` on both faces (Pixel:
the mitts offer something toward you; gel: the dome leans and lifts).

## Stage 5. Minis for helpers

- `state.helpers` is in (stage 3). The lane draws them: Pixel, up to
  four tiny faces at the strip's right, then `+N` (`screens.cpp`
  `drawStrip`, a `helpers` field in `Strip`); the gel, droplets beside
  the dome that split off when the count rises and are reabsorbed when
  it falls (`lane.cpp`, the engine's `life`). The count also prints next
  to the working count.
- Tapping a mini is later: it needs touch position on the board (stage
  7 brings it); leave a note.
- **Tests:** `sim` scenarios at 0, 1, 4 and 7 helpers on both faces;
  `CoreTests` for the count across two sessions; eval
  `93-helpers.json` with `helper started` ×3, `expect.helpers: 3`, then
  `helper returned`.
- **Demo:** `boop/demo/helpers.jsonl` (one agent sends three reviewers).
- **Docs:** CHARACTER.md §9 (the lane), architecture.html.

## Stage 6. Holidays, day counts, the diary, and opinions

**Holidays and day counts** are stage 3's tags plus art and Examples:

- Art, both faces: Halloween (a costume on the looks, candy as the
  gift's variation), `party` (a party hat on the wake-up and the idle
  looks; also the finish), `winter` (a hat and snow), `newyear` (a party
  hat), `valentines` (hearts), `friday` (a Friday idle variation). The
  in-jokes (`piday`, `aprilfools`, `may4`, `programmers`, `friday13`)
  get one variation each where cheap, else nothing yet: the tag exists
  and the pack may fill it later.
- `aprilfools`: an Example where Boop answers the wrong finish on
  purpose (`→ a failure face at a done turn, tickled in a sound`), with
  an eval that accepts it only on that day.
- The popover shows `Day 47` beside the name (`OverviewPane`).
- Growth's stage-ups join `party`: `Growth.stage` rising adds the tag
  for the rest of the day and the heading says `Boop became a Sprout`.
  That gives Growth its first job.
- **Evals:** `90`/`91` from stage 3 grow Examples' expectations;
  `94-april-fools.json`, `95-stage-up.json`.
- **Demo:** `boop/demo/halloween.jsonl` (start 10-31 09:00: the wake-up
  in costume, a finish with candy).

**The diary** (the only new question):

- `characters/<pack>/steering/diary.md`: templates, one a line, with
  placeholders `{turns}`, `{failed}`, `{wins}`, `{longest}`, `{project}`,
  `{away}`, `{pokes}` and optional tags in front, `[failed long] Tuesday.
  {project} fell over {failed} times. I stayed brave.` The day's tags
  come from the counts: `failed` (≥1), `clean` (0 failed, ≥1 turn),
  `long` (longest ≥ 30 min), `quiet` (no turns), `away` (≥ 2 h away),
  `poked` (≥ 5), `streak` (a run of ≥ 3 quick wins), plus the day's
  calendar tags. Same rule as faces: a template fits when every one of
  its tags is in the day's set.
- `DiaryOutput` (`app/BoopKit/Outputs/DiaryOutput.swift`): asks one
  question, `diary.line` ("What does Boop write in its diary about
  yesterday?"), with the fitting templates filled in as options, at most
  8, **only when NOW is the day's first event** (the output returns `[]`
  on every other pass). The day's first event already exists as
  `CoreEffect.newDay`; make the view write a line for it: `A new day.
  Yesterday: 14 turns, 3 failed, the longest 42 min, on "api"; you
  were away 2 h.` (wake 0), with the counts as facts. The view keeps the
  day's counts (`Counts` per day, reset at the line). The output's `run`
  records `Boop wrote: "…"` and `MemoryStore.appendDiary(day:line:)`
  writes `diary.md` (the memory store stays the only writer). The
  popover shows the last seven lines under a Diary row.
- **Scripted brains** answer the first option; `pipelineCheck` too.
- **Evals:** `96-diary.json` (a day of steps, then the clock past
  midnight and a `turn started`: `expect.diary: some`, and one with
  `expect.diary` naming the `failed` template).
- **Docs:** CHARACTER.md §7 (the steering folder's `diary.md`),
  EVALS.md, architecture.html (the eighth question, when it's asked),
  CLAUDE.md's Words (`diary`).

**Opinions about you** (steering only, plus one count):

- Examples, both packs, for the prompt's note (`You asked: …`): "please"
  → a warm face; "thanks"/"thank you" → beam; ALL CAPS → flinch
  (`surprised`/`wounded`); swearing at the agent → gasp (`stunned`);
  "ultrathink"/"think hard" → `determined`; a bare "continue"/"go on" →
  `bored`. And for the agent's last message: "You're absolutely right!"
  → an eye-roll (`disgusted`/`amused`), "I apologize for the confusion"
  → `affectionate`, "Let me try a different approach" → `tired`.
- Deleted code: check whether AgentHooks' edit events carry the old and
  new text's sizes. If they do, the turn's finish line gains `, 1,200
  lines gone` when a turn removed ≥ 500 lines net (the view sums per
  turn; counts, never the text), with an Example (`→ excited, success,
  glad in a phrase, twice`). If they don't, leave it for stage 8's
  AgentHooks work and say so.
- Raise `Steering.Budget.personality` to 2000 tokens (boop.md is at
  ~1,480 of 1,500) and note the cost in the commit (about 5,000 tokens a request).
- **Evals:** `97-please.json`, `98-all-caps.json`,
  `99-absolutely-right.json`, each `always: false`, 2 runs.

## Stage 7. Touch and motion on the AMOLED board

The board recognises each gesture, plays `gesture` with its `kind` at
once (its own reflex, like `poked`), and sends `ev gesture {kind}`; the
Mac records a raw `gesture` event (like a poke: `Pipeline.gesture`), the
view's line wakes the brain, and the steering decides the mood. The
Cheap Yellow Display keeps tap and BOOT: its panel has no reliable
stroke and no motion sensor.

**7a. Touch** (`firmware/src/app/touch_gesture.{h,cpp}`, pure C++ on the
device clock, tested in `fw-test`): from the panel's positions
(`BoardHal::touch` already gives x, y), classify a release as `tap`
(as now), `stroke` (≥ 40 canvas px of travel within 1 s, along the face;
upward is `ruffle`), `tickle` (≥ 4 touches within 2 s inside a 30 px
spot), `nose` (a tap inside the face's centre box, which the face
reports: `Face::noseBox()`). The thresholds are constants, pinned.
Reflexes: stroke → the gel's `dragStart/dragMove` finally gets a
caller (the dome follows the finger) and Pixel's eyes close and lean;
nose → a squish and "boop!"; tickle → a giggle, then a squirm from the
third. Lines: `You stroked Boop.`, `You stroked Boop the wrong way.`,
`You booped Boop's nose.`, `You tickled Boop (3 times in a row).`
Examples: stroke → `comfy`/`affectionate`, and a grumpy Boop calms a
step (the mood files' "leaves for" lines); ruffle → `annoyed`; nose →
`amused`; tickle ×3 → `grumpy`.

**7b. Motion** (`firmware/src/board/amoled206/imu.{h,cpp}`, a minimal
QMI8658 driver on the shared I2C bus, polled at 50 Hz, no interrupt;
and `firmware/src/app/motion_gesture.{h,cpp}`, pure, tested): `pickup`
(|a| leaves 1 g for ≥ 150 ms and the orientation changes), `putdown`
(a settle after a pickup), `shake` (≥ 3 sign changes above 1.5 g within
600 ms; a second shake within 2 min counts `again`, as pokes do),
`facedown` (z ≈ −1 g for 1 s) and `faceup`, `thump` (a < 80 ms spike
with no orientation change). Tilt, rocking and upside-down wait.
Reflexes: pickup → looks up (`surprised`, "oh, hi!", groggy if asleep);
putdown → a landing squish, "oof"; shake → dizzy (spiral eyes on Pixel,
a wobble on the gel); thump → a jump; facedown → **do not disturb**: the
board dims, its `refuse` skips every `do` but `listening` with reason
`facedown` (HISTORY then shows reactions skipped, truthfully), the look
stays and so does needs you; faceup → peekaboo, and the idle count
shows. Lines: `You picked Boop up.`, `You put Boop down.`, `You shook
Boop.`/`…3 times in a row.`, `You thumped the desk.`, `You turned Boop
face down.`, `You turned Boop back up.` Examples: pickup → `happy`;
shake → `baffled` then `grumpy` on repeats (the poke ladder); thump →
`frightened`; facedown → none; faceup → `curious`.

**The simulator** gets a tilt/shake/face-down input on the page and a
`dbg.imu` injection line (as `dbg.touchcal` is), so `sim` scenarios
cover each gesture and the demos play them.
**Evals:** `100-stroke-calms.json`, `101-shake-ladder.json`,
`102-facedown-holds.json` (a finish while face down: `expect.react` is
checked but the reaction's ending is `failed: skipped: facedown`).
**Demos:** `boop/demo/gestures.jsonl` (gel only; Pixel's `handoff`
exists from stage 4).
**Docs:** `firmware/README.md` (the IMU, its address, the thresholds'
home), CHARACTER.md §9 (`gesture`'s kinds, `noseBox`), architecture.html
(the `ev` kinds), `simulator/README.md`, CLAUDE.md's Words (`gesture`).

## Stage 8. The exact tab (AgentHooks; only if the night allows)

A terminal session opens its app, not its tab. In `agent-hooks/` on a
branch from its `origin/main` (never commit a pointer to an unpushed
commit; the owner pushes): the hook client records the terminal it
runs in (`TERM_PROGRAM`, `ITERM_SESSION_ID`, `TERM_SESSION_ID`,
`TMUX_PANE`, the tty) on the session; `ThreadLink.target` gains
`.terminal(app, tab)`. In Boop, `Runtime.open` selects the tab with the
app's own scripting (iTerm2 and Terminal.app; tmux by `tmux
select-window`), and the popover's hint says "open its tab". The
change lands here as the submodule branch plus Boop's side, with a note
to the owner to push and bump.

## Stage 9. Close

- The whole loop once more; `boopdev eval --runs 1 --no-budget` with
  Jev only if the key is there.
- `boopctl workday run` with the expect brain (free) and `workday check`.
- Bump "Updated" dates on every doc touched; `cmp CLAUDE.md AGENTS.md`
  silent; new links resolve; `git diff --stat` against CLAUDE.md's docs
  table.
- Fast-forward `feature/updated-behavior` (above). Report what ran,
  what passed, what was skipped and why.

---

## Simplifications this plan makes (and found on the way)

1. **Ears out** (~1,100 lines, two settings, a flag, five evals).
2. **One owner for variations.** The board picks every look's variation
   (the gel already did); the Mac's `shown.variant`, `lastVariant` for
   looks and the repick in `publish` go, and `variant` leaves `state`.
3. **One concept for "when".** Tags carry time of day, the weekday,
   holidays, day counts, load, and the diary's day; `after` carries
   time-in-look. Faces and diary lines use the same subset rule.
4. **One new reaction state** carries the button's hand-off and every
   gesture, by a fact, instead of a state each.
5. **One clock for evals and demos** (`start`), replacing the fixed
   Wednesday only where a scenario says.
6. **Growth gets a job** (`party` on a stage-up) instead of counting for nothing.
7. **The heading, not a line,** tells Jev the occasion: no new line kinds
   for time of day, holidays or day counts.

Left alone on purpose: `poked`/`tap_spam` stay their own states
(folding them into `gesture` would re-map every pack's existing art for
no gain); the `say` cap and `react`'s top-choice reading (the fun plan's
Not now); the rules brain (it comes after these evals exist, and reads
them).

## Order and cost

| Stage | What | Jev requests (if a key) |
| --- | --- | --- |
| 0 | Baseline | 0 |
| 1 | Ears out | ~0 (regression on the always set, 165) |
| 2 | Evals and demos | 0 |
| 3 | Tags, `after`, `state`, the board's variations, frantic | ~10 (90, 91) |
| 4 | BOOT hands over, the `gesture` state | ~6 |
| 5 | Minis | ~3 |
| 6 | Holidays, day counts, diary, opinions | ~30 |
| 7 | Touch and motion | ~15 |
| 8 | The exact tab (optional) | 0 |
| 9 | Close | the always set, 165; `--runs 1 --no-budget` ~500 |

If the night runs short, stop after any stage: each one stands alone.
Stage 7b (motion) is the one that needs the board on the desk to tune
its thresholds; land it with the thresholds as constants and a
`boopctl imu` readout for the owner to tune by hand.
