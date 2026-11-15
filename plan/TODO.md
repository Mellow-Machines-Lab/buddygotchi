# TODO

Updated 2026-11-15. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Report, 2026-11-15: bugs, a calmer screen, a roomier popover

**Read this first.** On the worktree branch
`worktree-bridge-cse_01357DH3yRTShbBqPx5mCzgZ` (on main `2caeb3cf`) and
SlimeBuddy's `calm-2026-11-15` (on `main-v2` `4bf8c55`, in this worktree's
`characters/.repos/SlimeBuddy`). Nothing is merged or pushed, and the packs'
`engine/` pins didn't move. Every picture and number below is kept outside the
repo, in `~/.boopdev/calm-2026-11-15/`. No Jev request: no prompt or steering
changed.

**Fixed** (each with a test that failed before):
- A level-up or "today's done!" that the board never showed was celebrated
  anyway and never played. Now it waits for the board's hello, and one skipped,
  or cut by a request or face down, is due again
  (`GrowthTests.testALevelUpTheBoardNeverPlayedIsStillDue`).
- About one `say` in eight with a lead sound was silent with a bubble reading
  "(null)" (`test_voice`'s `test_a_say_keeps_its_first_take_while_the_second_loads`).
- The world's gestures played to a locked screen, and after you switched the
  world off (`PresenceRuntimeTests.testALockedScreenIsQuietForTheWorld`,
  `WorldTests.testGesturesWaitingAreDroppedWithTheWorld`).
- A finish cut by a request that came just after it never came back
  (`ViewTests.testAFinishARequestCutComesBackOnceItClears`).
- Turned over while the Mac was away, the board never said so, and the Mac held
  every event as "face down" (`test_device`'s
  `test_the_mac_hears_which_way_up_once_its_back`). A `wish_met` that played
  nothing never reported its end (the same suite).
- Shakes and wrong-way strokes earned XP (`GrowthTests.testCareEarnsXP`).
- A burst of 20 calls asked the popover for 20 statuses, now 1
  (`WorkStreamTests.testABurstOfCallsAsksForOneStatus`). Measured: a status
  takes 0.11 ms and a tool call's two hooks 0.6 to 0.8 ms (debug build), so the
  Mac's side isn't hot, and the rest of the survey's Mac items are left.
- `boopctl e2e` takes a moment cut by the mic or face down as fine.

**Cut and calmed, on the board.** The screen's rule, written where the
renderer decides it (the pack's `render/gel/layers.h` and `pastimes.h`) and
pinned by `test_nothing_hangs_in_the_sky_or_the_air` and
`test_the_kit_is_the_headphones_alone`:

1. The face comes first. What it wears is on its body, one thing at a time: a
   hat for the night or the day, or Friday's shades, or headphones in long
   work (a hat wins).
2. Nothing hangs in the sky or drifts through the air for a time of day, a
   season or a holiday. Only the work stream's words fall behind it.
3. Beside the face at most one thing moves at a time: a Moment, else the
   needs-you card, else a pastime. A pastime brings what it holds and takes it
   away, 20 to 45 s after the last.
4. The top band holds one of the needs-you card, LISTENING, a start's card or
   the bar; the lane one of the bubble, the narration, a low sign or the strip
   (as before).

| Commit (SlimeBuddy) | What went | Before and after |
| --- | --- | --- |
| `eb71c77` | The sun, the moon and stars, snow, all-day confetti, hearts, the coffee in its hand | `gel-1-sky-air-coffee.png` (32 pictures) |
| `da40b10` | The pyjamas | `gel-2-pyjamas.png` (18) |
| `98ebd8c` | The desk's mug and its stack, the zone's motes, the plant, the notes off the headphones; the sip, the refill, the coffee reach and watering; pastimes 20 to 45 s apart (was 4 to 10), moves 5 minutes (was 90 s) | `gel-3-kit-a.png`, `gel-3-kit-b.png` (51) |

Each commit reverts alone. Kept: the work stream, needs you, the strip and the
drawer, finishes and the low sign, signs, the wish, the bar, the hats, the
headphones, 48 pastimes. `board-day.png` is the board driven through a day
over USB (13 steps, each the same pixels as the simulator).

**Cut and calmed, on the Mac** (`c773a249`): the popover is 420 pt wide (was
360) with 24 pt sides (16), 16 pt inside a card (12) and 13 pt text (12), and
nothing added; onboarding's window is 620 pt tall (560), so acts 5 and 7 still
fit. The "Why it looks like this" card follows the gel (`27609a41`). Before
and after: `mac-*.png`, and every snapshot in `mac-before/` and `mac-after/`.

**Simplified:** in the pack's firmware, rig and tests, 977 lines out and 199
in (the sky, the air, the coffee, the pyjamas, the kit, four pastimes and
their clips, nine colours); here, two always-true checks, `EventLine.everyone`
and five unused Python imports. `Contents` has three layers, not five;
`PastimeShow` carries the headphones alone; the painter no longer erases the
whole surface for scenery.

**Checked** (all on the last commits):
- `make -C internal check`: its tests, firmware tests, tools' tests and both
  faces' scenarios pass (741 Swift tests, 1 skipped); its last step, the
  mirror, failed on the page test's "a pastime in 40 s", was fixed in the pack
  (`4859c1f`) and passes run again (`make -C internal mirror`). `make -C
  internal boards`: both boards build. The simulator's own tests
  (`sim-test`) and the demos weren't run.
- BoopTests 740 passed, 1 skipped; test_gel 159 of 159; test_device 100 of
  100; test_voice 10 of 10; boopctl's 155.
- The mirror built again after each cut, its shots (576) the simulator's.
- On the AMOLED, the profiling build, before → after: night 25.1 → 30.5 fps,
  asleep 32.3 → 38.2, working 34.0 → 34.9 (its slowest frame 51 → 48 ms, so
  `perf --scenes` passes where it failed), needs you 30.4 → 31.0, frightened
  29.8 → 30.0, stream 29.0 → 29.2, pokes 35.3 → 35.8; the heap floor 141.2 →
  142.4 KB. `perf --plays`: night 20.5 → 27.9, working at night 18.2 → 23.0;
  three that play once read lower in their first second (the push 20.7 → 17.5,
  growing to a Chonk 23.0 → 18.8, the bar 45.8 → 40.4) and have no budget.
  `perf --motion`: 32 fps at worst, no frame over 33.7 ms.
- On the everyday build: `boopctl e2e` PASS (p95 231 ms); `boopctl latency`
  within every budget (a press 78 ms p95, a tap 73, a state 70, a do 77, none
  lost); `boopctl soak`, 20 minutes: no reset, heap drift 0, 141 moments each
  ended once; `boopctl run`: 0 expect failures, 574 of 576 pictures the
  simulator's (the two below).

**Suspected, not fixed:**
- On the board, `wish/gone` and `wish/slump` draw the body less slumped than
  the simulator (`boopctl run wish`). Not known to be new: the last pass ran
  other scenarios.
- Face down doesn't end when the board is stood up rather than laid flat
  (`motion_gesture.cpp` wants az over +800 mg): try it in the case.
- A shell command started in the background reads as passed, and counts a
  ship, as its hook returns.
- The first USB line after a board reset may be lost (the boot ROM's text
  joins it).
- The time zone is read once at launch: after a flight, night and Boop's day
  are the old place's until the app restarts.
- A `say` reads the card from the frame loop; a Bluetooth notify that fails
  sleeps in it. Neither was measured.

**For the owner:**
- **The look.** Is the nightcap alone right, or do you miss the pyjamas
  (`da40b10`)? Are 20 to 45 s between pastimes calm, or too quiet? Friday's
  shades cover the eyes all afternoon: keep them (recommended, they come off
  for every feeling) or cut?
- **The time zone:** restart the runtime when macOS says the zone changed
  (recommended; it reconnects Bluetooth, as a rename does), or follow it live.
- **Failed checks reach the brain** (#2, decided): it changes when Jev is
  asked, so it wants `--only` Jev runs. Not done here.
- **"While you were away"** on a gesture that waited for a request to clear
  (#10): say "Earlier," for every wait (recommended; a prompt line, so one
  quick Jev run).
- **A slow Jev answer drops a finish:** a finish may wait 15 s on the board
  but its pass has 1.5 s and one try. Ask again while it's still news?
- **Several buddies' last leftovers** (`Runtime.Rig`, `Buddy`, one-entry maps):
  about 40 lines and a layer, a refactor of its own.
- **L6, on the desk:** the calm look from the chair by day and at night; the
  headphones going on up to 45 s into tier 3; the popover's size on your
  screen and on the laptop's; onboarding's taller window; a level-up after the
  board comes back into Bluetooth's reach.
- **To land:** SlimeBuddy `calm-2026-11-15` first, then this branch, then the
  packs' `engine/` pins. The board is flashed back to main's firmware.

### The survey, before any change

What was found on main `2caeb3cf`, ranked by how much you'd notice it. The
baseline: `make -C internal check` passes (735 tests, 1 skipped). On the AMOLED
with the profiling build: needs you 30.4 fps, working 34.0, frightened 29.8,
stream 29.0, asleep 32.3, pokes 35.3, **night 25.1**; working's slowest frame
51 ms against its 50; heap floor 141 KB; `perf --motion` 31 fps at worst, no
frame over 33.8 ms.

**Bugs**

1. A level-up or "today's done!" is marked celebrated when it's logged, not when
   the board plays it: with the board out of reach, or the moment skipped in the
   queue or cut by needs you, it never plays (`GrowthStore.played`,
   `Runtime.playRule`).
2. A `say` with a lead sound and a take: about one in eight is silent with a
   bubble that reads "(null)". The voice's eight-slot cache hands the lead's
   slot to the take (`voice/player.cpp`).
3. World gestures play to an empty chair: a lock's "asleep" send brings them and
   the next tick plays them, worded "while you were away". They also play after
   you switch the world off (`WorldLink.tick`, `leave`).
4. A finish cut by a request that came after it never comes back
   (`TranscriptView.noteMissed` keeps one only when the request came first).
5. Face down, or back up, while the Mac is away or Bluetooth blinks is never
   told: the Mac holds every event as "face down" until the next turn-over
   (`Device::tell`).
6. Shakes and wrong-way strokes earn XP (decided 2026-11-09: they don't).
7. A failed check never asks the brain (#2 of the product review, decided).
8. The time zone is read once at launch: after a flight, night, Boop's day and
   the world's region are the old place's until the app restarts.
9. `wish_met` that plays nothing never reports its `ended`.
10. `boopctl e2e` fails a moment cut by the mic or by face down: its list of
    fine endings has drifted from the firmware's.

Suspected, to be reproduced: face down never ends when the board is stood up
rather than laid flat; a shell command started in the background reads as
passed at once; the first USB line after a board reset is lost.

**Feel and performance**

1. The Mac builds a whole status, and the open popover redraws, at every tool
   call: a session's word isn't throttled as the board's is, and every line
   from the board (each call's `ended`) asks for one more.
2. That status repeats work that changes once a day or a quarter hour (the
   week, the special days, a JSON encode for the debug log outside debug mode),
   and `Memory.tick` reads SQLite and decodes the dream every second.
3. The popover's mirror of the board parses every line all day with the
   popover closed.
4. On the board: night is the slowest scene (the sky, the cap and the pyjamas);
   the morning sun is drawn a pixel at a time and no perf scene has it; a `say`
   reads the card from the frame loop.

**The look: what's on the gel's screen**

Counted in the goldens. Up to five things share the screen with the face: in
winter's morning a sun, a bobble hat, snow, a coffee and the desk.

| Thing | When | Verdict |
| --- | --- | --- |
| The sun; the moon and stars | all morning; all night | Cut: scenery that says nothing you act on |
| Coffee in a little hand | idle or working in the morning | Cut with the sun |
| Snow, confetti, hearts in the air | all winter; a party day; Valentine's | Cut: the hat says the day. A finish keeps its confetti |
| Pyjamas | all night | Cut: the nightcap says night |
| A mug on the desk, a stack of them, motes "in the zone" | working, by tier | Cut: too small to read, and they need explaining |
| A plant that grows | idle, tier 3 up | Cut: random |
| Notes floating from the headphones | working, tier 3 up | Cut: a second thing moving all the time |
| Headphones | working, tier 3 up | Keep: one thing, on the body, "settled in" |
| A hat for the day, the nightcap, Friday's shades | by tag | Keep: one thing worn |
| Pastimes with props that are gone (sip, refill, reach, water) or random (tower) | by tier | Cut |
| The other pastimes | one at a time, 4 to 10 s apart | Keep, further apart |
| The work stream, needs you, the strip, the drawer, finishes, signs, the wish, the bar | | Keep |

**The Mac's popover**: 360 pt wide with 16 pt sides and 12 pt text. Wider, with
more room round each thing, and nothing added.

**Simplification**: the leftovers of several buddies (`Runtime.Rig`, `Buddy`,
`rig === rig`, one-entry maps and name arrays), `Runtime.init` and
`Runtime.harness` wiring the same `Mind` twice, names that only tests use in
the shipped app, the wish kinds spelled three times in the firmware, unused
Python imports.

## Report, 2026-11-14 (evening): a polish pass over main

On the worktree branch `worktree-bridge-cse_01357DH6tQBCCYsfsU7iyGjZ`, six commits on
main `d98a9a60`, not merged or pushed. No firmware or pack changed.

**Fixed:**
- A level-up or the ring's moment was sent to the board twice (its `do` and its
  `state`); now once, after the step that reached it.
- An overnight hourly check-in asked Jev about once an hour: its hold was only the
  debug label's. It's the harness's hold now, pinned by a test with a counting brain.
- A third finish in a row was dropped (#1): a finish waits up to 15 s. On the board,
  three finishes 1 s apart went done, done, skipped at 5 s; done ×3 at 15 s.
- Gestures in one world reply were passed over (#7): one reply is one moment.
- The world client: replies read leniently (an unknown gesture, activity or region
  drops that item, not the reply and its gestures); counts never go negative after a
  crash; a 400 doesn't resend the same body forever; a quit sends asleep once.
- The ring's day only moves forward when the clock goes back.
- The popover: a forgotten note's id no longer hides the next new note; app names
  looked up once; `memory.md` read only when it changes, not at every event; the
  hush's end to the second, so the status doesn't change every push; a half-typed
  rename is cleared on close; renaming past 16 letters says the world will show
  "a buddy" (the server's `NAME_MAX`, pinned by a test); a buddy's local time on the
  World card keeps time. Dead views and literal font sizes removed.

**Checked:** `make -C internal test` (744 passed, 1 skipped); `make -C internal check`
(on the 2nd commit: firmware tests, both packs' scenarios, the mirror's 582 shots the
same); `boopdev eval --scripted` 142/142; `Boop --snapshots`, all 333 pixel-identical
to main's. On the AMOLED: `perf --scenes` all within budget (needs you 31.0, working
34.7, night 25.7); `boopctl e2e` passes except the two below, which fail on main too.
No Jev request.

**The owner's answers, the same evening:** merge it; the e2e latency budget is
300 ms p95 now (`LATENCY_P95_MS`; 258 ms measured); the quit's send keeps the
gestures for the next launch (`?keep_gestures=1`, a server change: **deploy the
world** for it to take); names are 23 characters in the world too (`NAME_MAX`, also
in the deploy); night's 25.7 fps is fine; the Boop tab's numbers and onboarding's
words stay.

**Still open:** `boopctl e2e` fails on the work stream's `glimpse`, which keeps
command arguments in the transcript and debug log (never in a prompt).

## Report, 2026-11-14: the UI review, built

**Read this first.** [ui-review.md](ui-review.md) is built on `v1-polish`, from
`c12c9cc8` to the merge of `ui-board`. SlimeBuddy's `main-v2` has three new local
commits (`a2bb048`, `a87455b`, `9411c55`) and PixelBuddy's one (`427a7a3`, its demo
recordings). Nothing is pushed, and the packs' `engine/` pins didn't move. The §7 questions went by the review's recommendations; the corner gap
and the angry face are left for the owner's eye.

**Landed:**
- **The base:** one spacing scale (the gutter 18 → 16), named type, radii by use,
  one `Chip`, row buttons 24 pt tall, and a light-paper partner for every bright
  colour drawn as a shape. The contrast check covers shapes (92 pairs). A request
  says what it asks (`attn.kind`: a yes or no, a question, a plan to read).
- **The header and Now:** two rows that can't overflow (the level went to the Boop
  tab, Hush into Talk's menu); a needs-you card with its kind and real buttons; one
  list sorted by need; notices as one strip; a mood card only with a reason. A
  check keeps the face on the gutter in every Overview.
- **The tabs:** the Boop tab without "XP" ("82 of 100", a level bar, days
  together, seven slots); the World tab as a sentence in a small world, a band
  with a lane for you, a legend and region counts, one "Say hi"; the memory pane
  in one card, with five seconds to undo a forget.
- **Settings:** the buddy first, Talk as one control, Advanced closed, one trouble
  strip; rename once a week (the runtime restarts to take the name); a swear
  switch, off by default (evals and demos keep swearing on, so no prompt changed).
- **Onboarding:** one frame for all 9 acts (the marks and the button never move;
  a check pins it in all 132 pictures); act 5 fits; a face for each state; the
  missing states pictured.
- **The board:** nothing to read under the 22 px font; one lane row (bubble, else
  narration, else the strip in words); a needs-you card in the top band with its
  kind; the ring and a level as one moment (a `do`'s `gold`); 66 px drawer rows;
  "no Mac"; signs Boop holds in lower case; amber for needs you only.

**Checked:** `make -C internal test` (737 passed, 1 skipped), `Boop --snapshots`
(every check), `boopdev eval --scripted` (142/142), and on `ui-board`
`make -C internal check`, `boards` (both SUCCESS), the mirror (582 shots the same),
355 goldens looked at and accepted. No Jev request.

**Not done:** the world goal card and "Mochi added" (the world snapshot has no
goal); activities 8 → 4 and emotions 42 → 18 (the model phase); onboarding's 5
acts; BRD-15, 19 (the ask's two pills), 26, 35, 36, 42; the 4 px corner gap.

**On the board** (flashed 2026-11-14 from this branch, the Mac off Bluetooth):
`boopctl run v1 lane drawer growbar states done finish acts reasons sign` gives 0
expect failures and 0 pictures that differ from the simulator. `perf --scenes`
passes every budget: needs you 30.7 fps (28), working 34.3 (30), frightened 30.0
(28); stream 31.3, pokes 35.7, asleep 41.1, night 25.7. Needs you had been 26.0:
the card's words were drawn whole for each corner of the card redrawn, now only
inside its bounds (SlimeBuddy `9411c55`).

**The owner, on the panel:**
- From the chair: the narration, the ring's number, the strip in words, the card's
  kind line. Is the saturated amber card too bright at night?
- A finger on each 66 px drawer row; the bubble 3 px under the grabber.
- The finish glow's dither; the gold flood, by day and at night.
- The work act's rise: the strip fades beside the sign for a moment.
- The angry face (`moods/angry.png` looks delighted) and the corner gap.

**On the Mac, live:** rename restarts the runtime, which reconnects the board's
Bluetooth: try it once. Hover, motion and focus were judged from stills only.

## Plan, 2026-11-09: after the product review

**Read this first.** The owner's answers to [product-review.md](product-review.md)
§13, and the work in order. Bug numbers (#) and section numbers (§) are the review's.
The brain in the box and the voice come last ([TODOs.md](TODOs.md)): Jev stays the
brain until the behaviour is right, and every phase below shapes that behaviour.
The review's evidence (reports, logs, the bugs' log lines) is in
`plan/evidence/2026-11-09-product-review/` (at commit `510a78ac`); its
pictures are in `~/.boopdev/product-review-2026-11-09/`.

### Decided

- **Boop is a coworker and a pet, about equally.** Not a mirror: notices and memory
  stay small and correctable. Say it at the top of `personality.md` (Phase 2).
- **Status:** a finish waits longer in the queue, not folded (keeps it simple). A
  failed check wakes the brain on the ladder: the first failure, the third in a
  row, and a pass after failures. Ring and level make one moment. Rough touches
  (shake, wrong-way stroke) earn no XP. No hourly check-ins while you're away.
  Prompt reactions stay; only a turn start with no prompt stops asking the brain.
- **Growth:** XP amounts may change, set from a measured week. Stage names leave the
  UI; the bigger body at 5, 15 and 30 stays. Marks at levels 50, 100 and 365; the
  shelf only if the Boop tab gets opened. Most pastimes unlock from day one, 6 stay
  as stage rewards.
- **The model:** 7 moods and 18 emotions, by an alias table first and deletion after
  a week. Fades as numbers in code, and no mood graph. Code picks the move and the
  size. Activities 8 to 4, touches 14 to 7; tiers 5 to 3 last.
- **Friend:** the signs' register is settled now (lowercase, teasing); the spoken
  words wait for the voice. An idle floor. Awake while you're at the Mac. No swearing
  by default, with a switch. The memory writer is frozen until two real weeks are read.
- **World:** a goal a month, no XP reward. The public list shows no names. A rename
  once a week. A poke boops back. A product domain before any buyer.
- **Scope:** stop several buddies; stop the CYD and Pixel in the engine after v1's
  panel checks; the Studio becomes one contact sheet; onboarding goes to 5 acts once
  the board teaches touches itself, keeping the brain card until the end.
- **Measure:** the counts below, and evals that cover act events, stacked finishes
  and batched gestures.

**Still open:** how care counts in the ring (below); a Mac-only test with 10 people
(review §9.4).

### Phase 0: fix and measure

- [x] Finishes wait longer in the queue (`BoopDevice.finishTTL`, 15 s; #1).
      Checked on the AMOLED: three finishes sent 1 s apart all end `done`; at
      5 s the third went `skipped late`. `DeviceLinkTests` pins it.
- [ ] Failed checks reach the brain on the ladder (`Harness.swift:604`,
      `TranscriptView.swift:334-336`; #2). Eval `04` gets act events so it can fail.
- [ ] One moment for ring and level (`Core.swift:523-537`; #3): the sign
      `today's done!` and the low sign `Level N!`.
- [ ] A level-up cut by needs you comes back (`GrowthStore.swift:118-131`; #4), and
      is sent once (`Runtime.swift:792-811`; #5).
- [ ] Rough touches earn no XP (`Touch.swift:24-28`, `Growth.swift:68`; #6). A poke
      stays at 0, as now.
- [ ] ~~Batched world gestures play (#7)~~ done 2026-11-14: one reply's gestures are
      one moment (`WorldGestures.arrived`). Still open: a cheer needs a
      ship (`internal/world/src/app.ts`; #8); "while you were away" only after an
      away (#10); the data race at `Runtime+World.swift:135` (#11).
- [ ] The dream's sentence names its threads and its real days; the morning caption
      leads with turns (`MemoryReader.swift:254, 262-267`; #13 to #15).
- [ ] No brain pass for hourly check-ins while away, or a turn start with no prompt
      (#17, #18); fix the `(no pass)` debug label. The hourly half is done
      (2026-11-14): the hold was only the label's, now it's the harness's
      (`Pipeline.hourlyHold`); a turn start with no prompt still asks.
- [ ] Quick wins 1 to 5, 11, 12, 15, 17 to 22 and 26 (review §11.1): strings, asks,
      `[bye working]`, Login Items, the narrations that scold.
- [ ] Trust: the world screen and Settings name all five counts; the brain's
      line says what goes to Jev (#24, #25).
- [ ] Daily counts: the hour the ring closed, XP by source and past the cap,
      finishes played and dropped, needs-you answer time in seconds, push-to-talk
      uses, asks shown and answered, touches by kind, world gestures in, played,
      held and sent, Boop and World tab opens (`DailyCounts.swift`).
- [ ] Owed panel checks with the Mac off (the reports below): `perf --scenes`,
      latency, the ring's label and sparkle at arm's length.

Jev: `--only` on the scenarios each fix touches, then one standard run at the end.

### Phase 1: growth

- [ ] Run Phase 0's counts on the owner's own desk for a week.
- [ ] Decide how care counts (open, below), then set the amounts in `Growth.swift`
      from the week, and pin them in `GrowthTests`.
- [ ] Part-full rings blue, not red; no "XP" in the UI (`BoopPane.swift`).
- [ ] Stage names out of the UI and the world; marks at 50, 100 and 365.
- [ ] Unlock pastimes but 6 (`pastimes.cpp`'s stage column).
- [ ] A demo that sends `xp`, and scripted evals for the ring and a level-up.

### Phase 2: the model

- [ ] "A coworker and a pet" at the top of `personality.md`.
- [ ] The alias table: 42 emotions onto 18, 16 moods onto 7 (`character.json`),
      with cross as one mood with a level counted by code. A week on the owner's desk.
- [ ] Then delete: the 24 emotions' art, 9 mood files, the graph and its bridge
      tests; fades as numbers in code.
- [ ] Code picks the move and the size; Jev's questions drop to mood, emotion, say
      and sometimes a sign (`MomentOutput.swift`).
- [ ] Activities to 4 on the board, each with a body-size prop; touches to 7, each
      with its own clear answer; tiers to 3.
- [x] Stop several buddies (2026-11-14: the code, its demo `not-my-turn`, its
      tests and docs, and the other packs bundled in the app). Then, after the panel checks, the CYD and Pixel in the
      engine.
- [x] The Studio as one contact sheet (2026-11-14: the matrix, with the scene as a
      cell's detail; every other view, `behavior.json`, the review server and what
      fed them gone; `charactergen.py --check` prints the gaps. Checked by the
      studio's and charactergen's tests, and the page in a headless browser).

Jev: `--only` while building; one standard run and the judge to re-baseline.

### Phase 3: the pet and the content

- [ ] The signs' register: one page in the pack (`VOICE.md`), and the code's signs
      (`Level N!`, `Today's done!`, the special days) moved into the pack.
- [ ] About 170 sign lines where they fire most (review `words.md` §I).
- [ ] Asks that come back: 20, some daily, some monthly (`asks.md`, `Asks.swift`).
- [ ] Notices that read as care, each with its own pose and a sign (review idea 2.4).
- [ ] The pet side: wishes with more variety, first-time hints for each touch on
      the board (idea 1.13), care that shows on the ring.

### Phase 4: the day and the world

- [ ] Awake while you're at the Mac with no agent, on the board and in the world (#9).
- [ ] The idle floor; the evening card.
- [ ] The swear switch, off by default.
- [ ] World: a monthly goal, "Mochi added 82", the honest small world, boop back,
      no names in the public list, rename, the product domain, the abuse limits (#12).
- [ ] Onboarding in 5 acts, the brain card kept.

### Open

- [ ] **How care counts in the ring.** With the pet equal, care must move the ring
      on a busy day too, and new amounts alone can't promise that. Options: (a) new
      amounts only, measured; (b) work can fill at most part of the ring (say 70),
      so the rest is care; (c) two halves, work and care, and the ring closes when
      both are full. (b) and (c) bend "no limits by source". Recommended: (b), set
      from the week of counts, and never a sad Boop for a ring that isn't full.
- [ ] A Mac-only Boop for 10 testers (review §9.4): it bends "built for buyers of a
      board", and is the only way to get real counts before hardware ships.

## Older reports

The reports and lists from 2026-10-24 to 2026-11-09 left this file on
2026-11-14; read them at commit `510a78ac` (`git show 510a78ac:plan/TODO.md`).

## On a real Mac, later

The owner's checks, when they're at the desk: what only a real Mac
session, Bluetooth and the boards can show.

- [ ] The exact terminal tab: a tap on the board brings forward the tab
      the agent runs in, in iTerm2 and in Terminal, with macOS's
      Automation prompt the first time.
- [ ] 2026-10-24's setup fixes on a real launch: act 5's talk lesson
      ticking with what the Mac heard, act 6's plain words, act 7 without
      the mic card once act 5 had it allowed, the Dock icon while setup
      shows, and the found board holding up "Tap me!".
- [ ] Onboarding's window coming forward over the terminal at the
      agent's hello in act 6.
- [ ] Act 6's tour on the AMOLED, with a fresh Claude Code session
      asked to list its files: the words fall on the board and in the
      window, Boop cheers once the turn ends and a tap on it opens the
      thread, the drawer swiped up and its row tapped opens it again, the
      window comes back after each, and Next unlocks only then. Act 2's
      FAIL rain on the window's Boop.
- [ ] Reopening Boop.app while it runs brings its window or popover.
- [ ] "I don't have my Boop yet" remembers no board.
- [ ] In act 5, BOOT ticks only the button's lesson.
- [ ] An update with both boards plugged in: a refusal for the wrong
      board, the chip's image, a restart after a cut-off write. It needs
      a board on older firmware than the app carries.
- [ ] Opening an agent's tab from the bundled app (the Automation
      prompt).
- [ ] `make dev FRESH=1` keeping its own Keychain entry and leaving no
      socket behind.
- [ ] An SD card for the CYD's voice (`boop/voice.bin`); the CYD isn't
      a priority.

## Later

- [ ] Apologies don't soften a grumpy Boop's mood against Jev: 56
      (one apology softens it) passes 0 or 1 of 3 and 57 (undone by
      poking) 0 of 3, before and after 2026-10-24's grumpy wording. The
      face is right (annoyed); the mood question gives grumpy 0.61,
      irritated 0.27, annoyed 0.12: the stay option ("hasn't been grumpy as
      long as MOOD says it lasts. No change is fine.") outweighs grumpy's
      "a sorry cools it at once". A full Jev run of every scenario (about
      820 requests) would show what else sits outside the always set.
- [ ] The gel's lane scales with its panel (lane.cpp's fonts, margins
      and bubble are fixed px), then the Mac mirror renders at the
      tile's size (about 20× fewer pixels). Drawn at the popover tile's
      113 × 92 (2026-10-24, the simulator's `BOOP_SIM_NATIVE`), the
      slime, desk and needs-you plate scale, but the lane's text, dots
      and sign come out several times too big and run off the panel.
