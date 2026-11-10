# TODO

Updated 2026-11-09. What's next, one at a time, top first. Tick an item
in the commit that finishes it, and say there what checked it. Ideas
that aren't decided yet stay in [product-ideas.md](product-ideas.md).

## Plan, 2026-11-09: after the product review

**Read this first.** The owner's answers to [product-review.md](product-review.md)
§13, and the work in order. Bug numbers (#) and section numbers (§) are the review's.
The brain in the box and the voice come last ([TODOs.md](TODOs.md)): Jev stays the
brain until the behaviour is right, and every phase below shapes that behaviour.
The review's evidence (reports, logs, the bugs' log lines) is in
[evidence/2026-11-09-product-review/](evidence/2026-11-09-product-review/); its
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

- [ ] Finishes wait longer in the queue (`BoopDevice.swift:36`, `reactionTTL`; #1).
      Test: three agents end within 2 s, and three names show.
- [ ] Failed checks reach the brain on the ladder (`Harness.swift:604`,
      `TranscriptView.swift:334-336`; #2). Eval `04` gets act events so it can fail.
- [ ] One moment for ring and level (`Core.swift:523-537`; #3): the sign
      `today's done!` and the low sign `Level N!`.
- [ ] A level-up cut by needs you comes back (`GrowthStore.swift:118-131`; #4), and
      is sent once (`Runtime.swift:792-811`; #5).
- [ ] Rough touches earn no XP (`Touch.swift:24-28`, `Growth.swift:68`; #6). A poke
      stays at 0, as now.
- [ ] Batched world gestures play (`WorldGestures.swift:47-51`; #7); a cheer needs a
      ship (`internal/world/src/app.ts`; #8); "while you were away" only after an
      away (#10); the data race at `Runtime+World.swift:135` (#11).
- [ ] The dream's sentence names its threads and its real days; the morning caption
      leads with turns (`MemoryReader.swift:254, 262-267`; #13 to #15).
- [ ] No brain pass for hourly check-ins while away, or a turn start with no prompt
      (#17, #18); fix the `(no pass)` debug label.
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
- [ ] Stop several buddies; then, after the panel checks, the CYD and Pixel in the
      engine; the Studio as one contact sheet.

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

## Report, 2026-11-09: a check and polish of v1, on `v1-polish`

**Read this first.** v1 was reviewed against its plans, the bugs found are fixed with a test each, and the AMOLED runs this branch's firmware. Nothing is pushed; `v1-polish` sits on `main-v2`, and SlimeBuddy's `main-v2` has one new local commit (the label).

**Fixed:**
- World: a lock keeps the buddy asleep in the world until you're back (it woke again 10 s later); a retry the server had counted sends the state again; cheers' window no longer slides; a gesture while something needs you waits instead of being lost; a quit sends the counts not yet sent; the snapshot goes when the World tab closes; at most 50 arrivals a day are kept.
- XP: a level-up or the ring held over a quit plays at the board's next hello, and after a demo; a ring held past 5:00 doesn't play the next morning; a size held while the next level comes keeps its bigger moment.
- The popover: the World tab says when it's private, joining or out of date; your own dot is marked and has no gesture buttons; one gesture at a time, a sent one ticked, a failed one said; "Resting", "Click one", "1 hello"; VoiceOver can reach the band's buddies; asleep dots show in dark mode; ⇧⌘M works on every tab.
- The board: the "N today" label sits inside the panel's rounded corner (the bar is 232 wide); a ring filled while the bar was hidden shows and sparkles next time it can; one sparkle per fill; the wish that closes the ring keeps its heart; at 5:00 the bar slides out.
- `boopctl run` stops when the board says it's face down.

**Checked:** `make -C internal check` and `boards`; `world_e2e.py` against `npm run dev`; the board flashed and `boopctl run growbar growth v1 wish`. No Jev run: no prompt changed.

**On the board:** it had been lying screen down (`dbg.state`'s `face_down`), which refuses Moments and hides the bar, so 69 shots differed. Screen up, `boopctl run growbar growbar-listening growth v1 wish` gives 0 expect failures and 9 of its shots differ, each a few pixels of the body's motion (the heart's flight, `gone`, the wish's `slump`): the bar, its label, the heart and the signs draw as the simulator's.

**Owed:** the panel by eye (the label in the corner, the sparkle, gold at arm's length, a level's body change before its held Moment); `18-long-grind`; the judge for the standard run; the packs' `engine/` pins once this lands.

## Report, 2026-11-08: Boop v1 on `main-v2`

**Read this first.** v1's four tenets are built on `main-v2` (plan/world.md §9, plan/v1-buddy.md §5): XP kept simple, the popover's three tabs, and the world of buddies, client and board. Nothing was flashed and nobody has seen it on the panel; the frames are the simulator's.

Frames and snapshots are on the owner's Mac in `~/.boopdev/v1/` (`frames/`, `snapshots/`).

**Landed:**
- **XP, kept simple.** A fixed XP per thing, one ring of 100 a Boop day, a level per 100 XP, never down, and the sizes as bigger level-ups at levels 5, 15 and 30. XP starts from zero, with no migration. `Growth` and `GrowthStore` are rewritten; the pools, the decay, the stage's party day and the `grew` event are gone.
- **On the board, today's ring.** The growth bar is today's ring: it shows when XP comes in, with "54 today" beside it, and turns gold and sparkles when it's full. A level-up is the rules' moment, proud, with `Level 12!` on the low sign. The ring closing is a happy one, "Today's done!". Both wait while something needs you.
- **The popover's three tabs**, as sketched:
  - Now: status first.
  - Boop: the ring, the level, the last 7 days, a peek at what Boop knows.
  - World: live numbers; the time-zone band, night shaded, you marked; a buddy's card with Wave, Boop and Heart (and Cheer for one shipping); today's arrivals; the regions.
  - Settings has the world's switch, which leaves the world when off, how the buddy shows, and what's shared. Onboarding has its world screen, which tells and doesn't ask, with "Keep Mochi private". Nothing is sent until you leave that screen forward.
- **The world client** (`app/BoopKit/World/`). The live server allows 5 joins an hour from one address, and each e2e run joins 2.
  - It joins after onboarding's world screen and sends `World.State` only (`WorldTests` fails on any other field).
  - It sends on a change, batches the counts for 3 min, heartbeats every 10, and says asleep at once on a lock or quit.
  - Gestures come back in the reply, or from a check every 10 min and on an unlock. The world is fetched only while the World tab is open, every 30 s.
  - The world off leaves it: the buddy is deleted on the server.
- **Boops on the board.**
  - A gesture is a `world` event that Jev answers: always a face, and a sign from the pack's `[world]` lines.
  - The reason says who, by region.
  - At most 3 boops, waves and hearts an hour play, and the rest are counted on the World tab. Cheers for one ship are one moment. At night or while you're away they wait, and come back as one line.
- **The words rule** is in CLAUDE.md and applied to the new strings.

**Checked:**
- The Swift tests: 719 pass.
- The firmware's native tests, the simulator's gel scenarios (new goldens for the bar and a `v1` scenario), and Pixel's, with no change.
- Both boards' firmware builds, and the mirror is rebuilt.
- `internal/tools/world_e2e.py`: two headless Boops join, see each other, boop and wave, and leave. It passes against `npm run dev`, and passed against the live server on 2026-11-09 at 07:57 UTC, and again at 08:54 on the reviewed code with main-v2's server retry: the live world had 0 buddies after each.
- Getting there took three live runs, and it found a client bug. A leave the server didn't take was lost, because the key went before the DELETE succeeded, so a buddy stayed in the world. Now the key stays, marked as leaving, and the DELETE is tried again until the server confirms (`WorldTests`). The test buddies left on the live server by the earlier runs were deleted by hand.
- No server change was needed.

**After the orchestrator's review** (fixed, each with a test where one could fail first):
- No rejoin storm: only the world server's own 401 forgets the key, and a rejoin or a failed join waits its backoff.
- Keeping private is safe: "Keep Mochi private" wins over a join on its way, and a leave keeps the key until the server confirms.
- XP starts from zero: the old `growth.*` rows are deleted, and the new keys are `xp.*`. A level-up and the ring closing are marked done only as they play, so a quit or a demo loses neither.
- Sends: a send with no answer goes again with the same seq and counts. "Asleep" at a lock waits for a send on its way, and at a quit waits up to 2 s.
- Gestures: held ones are kept across a quit, and ones that arrive after you left are dropped. The unlock check follows the switch and the backoff. The key file is 0600 from the start.
- On the board: a met wish after a full ring shows no bar.
- The UI's words were reviewed, and the header says "Working" or "Idle". The band shades night better in dark mode, and "you" is dim when you're not in the world. A `world-long` snapshot was added.

**Evals:**
- The standard suite passed 130/131, with 748 Jev requests.
- The new world musts `187` and `188` pass, and `06` is Pixel's. `189`, a boop when cross, moved from grumpy to curious after its guideline was made plainer.
- The one miss, `18-long-grind` (20 quiet minutes of work, against 7), fails the same way on `main-v2` before this work: it isn't v1's, and it's still to fix.
- The feel scenarios (110) went to no judge: run the judge on `/tmp/boop-eval/20261108-220953-81575.trajectories.jsonl` if it's still there, or on the next standard run.

**Decisions taken, say if wrong:**
- The middle tab says "Boop", whatever the buddy is called.
- Full rings are green on the Mac and gold on the board.
- A stage reached no longer makes the day a party: it's a bigger level-up.
- With no growth store (demos, evals), CONTEXT says level 1 with an empty ring.
- The world switched off deletes the buddy on the server: one control, the switch.
- The pack's `[grew]` signs and the four growing evals are deleted.

**Owed:**
- The panel: the ring's bar and label at arm's length, the sparkle, the level-up's low sign, and a boop's bounce. No fps was measured.
- The judge for the standard run.
- `18-long-grind`.
- The world snapshot stays in the popover's status after the World tab closes, and the day's arrivals aren't capped. Both are fine at today's sizes (the /simplify pass's notes).
- The packs' `engine/` pins move to this commit once it lands.

## Report, 2026-11-04

**Read this first.** The board ran its USB tests with the owner's `make dev` app connected over Bluetooth all night, so frame-rate budgets, scenarios and latency need a rerun with the Mac off. Nobody has seen any of this on the panel: no eyes, no webcam.

Frames, verdicts and logs are on the owner's Mac in `~/.boopdev/tonight/`.

**Landed:** eyes following a finger, leaning into a held finger, tilt, the listening nod, a reason for every reaction with a test that keeps it so, "it noticed" with four notices, daily counts (`w` in the dashboard, `Boop --counts`), and the board's measurements with their fixes.

**Not done, stage two:** the Mac and dashboard pass by running them, and the leftovers below.

**Evals, on the final tree:** standard 132/132, with no re-runs, and the judge at **99 reasonable, 11 odd, 0 unreasonable**, so `internal/EVALS.md`'s rule is met this time. On main at the start: 123/124 and 85, 13, 4. Odd: `121`, `144`, `173`, `180`, `181`, `186`, `28`, `54`, `57`, `85`, `94`. 129 passes, after adding `shaken` to what its pokes may say.

**What guidelines did:** a cross Boop now says "Stop" and "Enough"; lonely holds its hour; a lock while cross snubs; days away is a big hello. What they can't do: a lonely face can still say "Cozy" on a calm mood, because `say` doesn't know the face. The full fix is a take table that lends `quiet` and `tickled` only to fitting moods.

**Idle may now be too quiet.** Across the final run, 36 of 83 idle check-ins have a moment, 8 of them a real face, and 5 a word, all on Chatty. On one workday, moments went from 13 of 13 to 4 of 13. It's what was asked: worth a look.

**Notices.** 17 in the final run, and none nags. A played notice looks at you and shows a short reason on the board. But "claude sits idle" is 13 of them, and reads as a flat report, not care. `stretch` and `rough` chose no sign and no face in `173`, `180`, `181`: in the eval's record only the narration shows them, and whether the look reads on the panel is unchecked. "still up?" is the one warm one. An open wish holds up `stretch`, `rough` and `late`, never `waiting`. On a no-wish day `waiting` can beat the wish (`186`).

**Lunch no longer reads as night:** a dream made by itself takes 2 h of sleep begun at night (22:00 to 5:00), or 5 h begun by day; `d` and the two-day fallback stay. Night signs were already gated by tags; the voice's words weren't audited.

**What the real board measured** (AMOLED, volume 0, USB, a profile build, Mac connected). **The fps budgets are unproven.** `perf --scenes`, the real check, reported `ok: false`, with the Mac's state in every window: working mean 30.5, min 15.4 (budget 30); needs you 26.1, 12.8 (budget 28); frightened 25.0, 11.1 (budget 28). The table's clean fps is the slowest second, leaving out seconds with a Mac state and the 3 after, so it shows the frames between states and can't pass a budget by itself. Each state costs about 2 s at 12 to 15 fps here because it flips everything back against the test's own state, which a real state wouldn't always do. Only a rerun of `perf --scenes` with the Mac off settles it.

| Scene | Clean fps | Steady | Budget |
| --- | --- | --- | --- |
| Working | 33.8 | 34 | 30: unproven |
| Needs you | 29.1 | 29.6 | 28: unproven |
| Frightened | 29.8 | 30 | 28: unproven |
| Idle | 40.8 | 41 | none |
| Working at night | 17.9 | 21 | none, well under working's |
| Asleep at night | 21.3 | 25 | none |
| Push: lift-off, away | 19.2 (1 s), not a minimum | 26-29, 59 | none |
| Tests' hold (was 22) | 25.2 | 27 | none |
| Build | 25.0 | 30 | none |
| Chonk idle, working, big finish | 37.2, 31.0, 20.2 (3 s) | 37, 31.5, 31 | none |
| Bar, heart | 44.6, 34.4 | 45-50, 37-48 | none |
| Grow to Sprout, to Chonk | 17.9 (1 s), 11.5 (1 s) | 47, 35 | none |
| Tilt, lean (driven by debug commands) | 41.1, 37.0 | 41, 37-41 | none |
| Parade, Gold Rush | 17.1 (2 s), 20.8 (3 s) | 33, 34 | none |

Heap: at least 141,044 bytes free in every scene, against 50,000. No audio write errors. `factory --auto` 6 of 6; card and voice right. `boopctl run`: 6 expect failures and 155 of 563 pictures differ on the last run; the failures show the Mac's state, and the smallest picture differences aren't explained. Latency at the host over budget (press 133 against 80), the board's own press 75. `perf --motion` 86 ms against 40. Not run: sound, soak, e2e.

These measurements predate the five calls and the last cleanup. **The board tests flashed `tonight` and restarted the board by watchdog three times**, from a tool's clock jump, since fixed: the owner may see that in `Boop-dev`'s log.

**Fixed from the leftovers:** `to-work` waits for a turn's start; the heart flies over LISTENING; nose and drag go by stage; the gulp plays once; a Hatchling's sign hops clear of its mouth; the witch hat's height is capped. `check` now has `make -C internal boards` beside it, slimegen's check, and a test count. Two real bugs from cleanup: Quiet saved on every input all day, and counts lost at 5:00.

**Choices to overrule:** a long hold on the face or nose is now a lean on the gel, not a tap. The purr is the snore's `breath` clip, as the bank has no purr. A touch shows its own caption for 2.5 s, hiding the strip: it may nag. `state.buddy` is new, for a name you gave. Pixel's bubble shows the Mac's new reasons.

**Feel on the board, in order:**
1. A finger at rest: does the lean start, on a real panel's jitter (`kLeanSpotPx`, `kLeanWigglePx`)?
2. Tilt's direction: the IMU's axis is a guess (`Tilt::kAcross`).
3. Is `breath` content or a snore?
4. A caption on every poke.
5. The higher Hatchling hop, the heart's path, the capped hat.

**The Mac and dashboard pass:** done by running them (`Boop --headless`, `--snapshots`, the dashboard in a real terminal, two buddies on two simulators). Fixed: an input's XP went out as its own state, just before the real change; 17 places where text was cut off in the popover and onboarding (the mood's reason among them; lists of them in `~/.boopdev/tonight/ui/`); a long quote hiding the needs-you card, which now comes first, with a quote kept to 160 characters; a telling that named Boop whatever the buddy's name; stale words and cut-off text in the dashboard; a `grew` lost to a quit now comes at the next launch that day. `dash` and `day` no longer read old log formats. A reason that quotes you still stops at 160 characters, with a "…".

**What the Mac measured for frame cost** (the firmware's own `Measure`, at -O2 on the Mac, a scratch bench; no board, so no frame rate is known). Every frame of 29 scenes hashes the same before and after, and the sim's goldens don't change. Working at night: its layers 84 to 78 us a frame, the whole frame 245 to 239 (-2%). Night asleep: layers 68 to 61. The grow pop's worst second: to Chonk 452 to 381 (-16%), to Sprout 340 to 306. Gold Rush's rays divide in 32 bits rather than through `__divdi3`, which the Mac can't show: reasoned from the Xtensa compiler's output. The parade, a Chonk's finish and the lift-off have no easy win. So working at night is still short: expect little there. The real cost is the body under its outfit and the outfit's 9,400 blended and 35,000 filled pixels a frame, on one core. Sharing the outfit's replay with the helper core (as the body's rows are shared) is the next thing to try, with the board.

**Still to do:** rerun `perf --scenes`, `boopctl run`, latency and `perf --motion` with the Mac off (the owner's app stays on Bluetooth until they say); working at night's fps (nightcap and pyjamas cost 15 to 18 ms a frame).

## Report, 2026-11-03

**Read this first.** The standard run and the judge go first thing after midnight, as a follow-up. Until then, feel on most of this work is unjudged. `internal/EVALS.md` says standard runs before a branch merges: on this branch that was knowingly not met.

Frames, verdicts and logs are on the owner's Mac in `~/.boopdev/day2/` (growth, polish, listening-heart) and `~/.boopdev/night-2026-11-01/`. Nothing has run on a board.

**Landed:** wish frequency, the flatness fixes, growth with the bar and the heart, the morning and its collision rule, less repetition, the new memory writer and its line on the low sign, and transitions.

**Not done: level B.** The day's Jev limit ran out, so which of its 8 failures are too-strict musts is still open. Stay near level A until it's tried. The prompt is about 5,000 tokens, with 6 Examples left of 24.

**Wishes.** Last night's zero came from scenarios too short to reach one. A simulated workday on the final words: 1 a day on all 5 days (2 full, 3 with only the quiet stretches sent to Jev), between 09:43 and 10:45. A busy day: 1 on the 2 seeds re-run; 2 of 4 seeds had none on the earlier words, and those weren't re-run. The real fault was a second wish after one gave up: a guideline alone gave one on 4 of 4 days, and one line in the sign question stopped it, on 2 days measured. No cap, no Examples, no code offering it more. The margin is thin on Quiet (0.47 to 0.51). Every workday wish came before 11:00, and chat is most of them.

**Flatness: guidelines mostly did it.**

| | Musts | Judge: reasonable, odd, unreasonable | Mood moves |
| --- | --- | --- | --- |
| Before | 118/119 | 81, 11, 9 | 300 |
| After | 119/119, with 03, 27 and 129 loosened | 83, 15, 3 | 279 |

That 119/119 predates tightening `129` and `17`, so it isn't the score of this tree: see below.

What worked was removing Examples: Jev was copying them. Guidelines giving a ladder or a direction work; naming what to avoid raises it; words matching the row Jev reads work best. Words couldn't fix: `11`, a finish just after its fix still goes big (the line would have to say the fix was just reacted to); Halloween and day 50 are still alike, as a return offers no sign; `98` April Fools. The code now gives a special day's sign at your first showing up, seen only in a scripted run. The 3 left, `137`, `141` and `167`, had briefs wrong against the wish rule, and those briefs are corrected, not re-judged.

**Evals on this tree:** not re-run as a whole: standard's about 700 requests didn't fit. The last standard predates growth, the polish plan and the review's fixes. Each must run alone after the review's fixes: `03` (now refusing the word `done` too), `17` and `136` pass. `139` and `27` passed before those fixes and weren't run again. **`129` fails, twice in its run:** the first hush now steps calm down to lazy, by a line in `calm.md`. Hushed from the Mac later, while curious, Jev picks calm (0.56, 0.61) over annoyed (0.27). It's a real miss, and its must stays as tight as it is.

**Owed with Jev, first thing after midnight:** `--level standard` and the judge on this tree, with `129`. It covers the faces guideline (`05`, `10`, `16`, `18`, `19`, `21`, `23`, `85`), a remembered line (`178`, `76`, `144`, `152`, `167`), special days (`90`, `91`), the morning (`63`, `97`, `135`, `136`, `140`, `147`), growing (`174`-`177`) and the changed words. A `grew` while something needs you has no scenario. Then level B.

**Memory writer:** no real week has been through it, and the sign pass hasn't run in a real dream. Its figures (false notes 33 of 56 to 0 of 43, refusals 526 to 1, notes that feel known 4 to 22) are hand-graded on made-up nights. Its gates on this Mac: worth 39/43, private 45/53, story 28/34 and 13/16 held out, after a wording change and 9 new rows. Code refuses a question or a negation before the model is asked, so "not moving after all" no longer ends a story either. On a night with one thread, the real model still says yes to "the audio is done", and that overwrites the thread's note: that's the cost of letting a saga end.

**The tests:** the runner had been silently dropping every test after a local class in a test function, 9 in all. All run now. The board's firmware also stopped compiling at one point with `check` passing, as `check` doesn't build for the boards: run `make -C internal fw` too.

**Choices to overrule:** saved stages keep at least their size (Pal to Buddy, Chonk and Legend to Chonk), but Hatchlings and Sprouts will look smaller, as every stage used to draw full size. The 3-day clock starts at the first launch. "Forget" clears the digest's words and history copies, keeps care counts, and leaves an untold dream's sentence and the transcript's two weeks. Every stage draws Buddy's Mega. The party hat goes on a Sprout. No voice pitch or moves by stage: not cheap.

**Look at first:** `growth/sheet-wish-reaches-a-stage.png`, `growth/sheet-stages.png`, `growth/board-fixes/sheet-all.png`, `polish/remember-line.png`. `growth/sheet-bar-states.png` is the old look.

## Stage two: the full pass (2026-11-04)

What it is: [alive-and-noticing.md](alive-and-noticing.md). Its order is in the
report above.

Left by the Mac and dashboard part of it:

- [ ] `boopctl dash` narrower than about 180 columns stacks its panes and opens scrolled to
      the columns, as the first column takes the focus: the face and "Boop now" are a
      scroll up. It's readable; whether it should open at the top is a judgement.
- [ ] `w`'s table wraps under about 130 columns, and its counts run up to a minute behind,
      as the counts file is saved once a minute.

## Left by the review of `tonight` (2026-11-04)

- [ ] Evals 179 to 186 pass even if a notice's sign never shows. `checks` are
  judged per run and a notice's sign is only now and then, so `signs_seen` on one
  run would fail by chance. It wants a check across `--runs`, which the harness
  doesn't have, and Jev requests to set its bar.
- [ ] One sharp prompt alone makes `rough`: it may be too eager, with no failure
  behind it (`Notices.rough`). The owner's call: `testRough` pins it as it is.

## Owed from the Mac fixes (2026-11-03)

No Jev requests went to these, as the day's limit was nearly spent:

- [x] Run `17`: passes on this tree.
- [ ] `129` fails at its hush from the Mac, while curious (see the report).
- [ ] Run `137`, `141` and `167` with the judge: their briefs changed.
- [ ] Run what `personality.md`'s words touch, coming back and a long wish: `136`
      passes alone; the scenarios that name lonely aren't run.
- [ ] A stage reached while something needs you: `grew` now waits for the answer, and
      no Jev run has seen it.

For the owner to decide or look at:

- [ ] A board power-cycled with no Mac draws a full Buddy until the first state, since
      it doesn't save its stage. A Hatchling looks full-grown for those seconds. Left:
      saving it means writing flash on every stage change, for a moment's look.
- [ ] `memory-days.json` as it stands: entries in `added` from updated notes still
      count as deleted, and `signs` of "" from Apple Intelligence being off still
      count as refused. Nothing tells them apart; deleting the file's `added` and those
      rows would, at the cost of notes you did delete.

## Owed from mornings and polish (2026-11-03)

Built: the morning, less repetition, memory you feel, transitions. The rule is in
[architecture.html](../documentation/architecture.html#collisions).

On the board, none of it has been on one:

- [ ] Flash, and come back in the morning: the greeting, then the words, then the
      sign; no words falling or act until it's over; a needs-you cutting it.
- [ ] A special day's sign at your showing up (a `party` or `halloween` day).
- [ ] The low sign's remembered line, and its look. Pictures: `sign/remember-*`.
- [ ] Each transition's feel, above all `to-work` (no real sleeves: a tuck each
      side and a sit) and `to-sleep` (the mouth has one size, so little yawn).
      Frame rate and heap: they add no art, only channels, so no change is
      expected; that's reasoned, not measured.

With Jev, none asked yet (zero requests were spent on this):

- [ ] `boopdev eval --only` each of: the faces' new guideline on 05, 10, 16, 18, 19,
      21, 23, 85; bringing up a line on 178 (new), 76, 144, 152, 167; the special
      day on 90, 91; the morning on 63, 97, 135, 136, 140, 147. Read the faces:
      if a streak still repeats the same face at routine moments, build the
      other half of the plan, code dropping the last face there. Before the
      guideline, 168 of 581 faces in the last run matched the one before.

The memory writer:

- [ ] No real week has been through it. Run it on your own days, and read
      `memory.md` after a week ([memory-writer.md](memory-writer.md)).
- [ ] The sign pass in a real dream of the running app: only a stub has driven it.
- [ ] Decisions to overrule if you like: forget clears the digest's `said`;
      `memory.md` says it's written on this Mac; the stopped habit's 30 days and
      You and Boop's 4 notes stay.

The voice:

- [ ] Record a "hey!" and point `remember_word` at it: the bank's "Hey" stands in.

Growth, merged into `day2` on 2026-11-03. Owed on the AMOLED, for the owner to look at:

- [ ] Chonk's frames a second, unmeasured: a Chonk shades 21% more of the body than
      Buddy (`boopctl perf --scenes` with a saved XP past Chonk's).
- [ ] `boopctl perf` with the growth bar up: estimated at about 6,000 pixels of
      205,820, for about 4 s at a time, not measured.
- [ ] Whether a Hatchling's face reads at arm's length.
- [ ] The old-Hatchling shrink: the old build drew every stage at full size, so an
      existing Hatchling or Sprout looks smaller after the update. That's the plan's
      look, not a lost stage. Judge it.
- [ ] A Hatchling's Mega Boop doesn't fill the screen. Left as it is, to judge.

Growth, not built:

- [ ] Voice pitch by stage: a take plays at one speed (`voice::Player`), and the mouth,
      the bubble and the Mac's `Take.ms` all time from it, so it isn't cheap. Sound
      effects already take a pitch (`FxEvent::pitch`), a small change if wanted.
- [ ] How it moves by stage: clumsy, bouncy or slow needs tuning by eye on the board.
      The body settings are size, eyes and squash.
- [ ] A pastime only a Chonk knows: a Buddy would deal differently, as a board with no
      tag is a Buddy.
- [ ] A demo with the bar: demos send no `xp`, so `make demo` doesn't show it.

## Measured on the AMOLED, still short (2026-11-04)

With the Mac on Bluetooth all through, as `make dev` was running; each second's numbers
come from `boopctl perf --plays` (`~/.boopdev/tonight/board/`).

- [ ] Working at night draws about 21 fps (asleep at night 25): the nightcap and pyjamas
      cost 15 to 18 ms a frame. By day working is 34.
- [ ] Short dips with no budget: the parade 17 fps for 2 s, Gold Rush and a Chonk's 21 for
      3 s, the rocket's lift-off 19 for 1 s, the grow ceremony's pop 12 to 18 for 1 s.
- [ ] `boopctl latency` was over budget at the host (press p95 133 ms against 80, tap 85
      against 80, state 111 against 100) and `perf --motion` over its 40 ms frame (86 ms).
      Measure both with the Mac off before believing them.
- [ ] `boopctl run` with the Mac off. With it on, 6 expects failed and 155 of 563 pictures on the last run
      differed; the ones opened show the Mac's own state or eyelids a little apart.

## Found by the review, not fixed (2026-11-03)

On the board:

- [ ] A met wish while something needs you is still refused (`needs_you`), so its heart
      doesn't show. Same shape as the chat wish's fix, but the screen is the agent's.

On the Mac:

- [x] A dream told twice with several buddies: it didn't happen on two simulator boards,
      by taps or by coming back, unless the first telling was refused, when telling it
      again is the rule. Pinned (`testSeveralBuddiesTellOneDreamOnce`). What was wrong:
      your coming back told it as "Boop dreamed", whatever their names.
- [x] A held `grew` a quit lost now comes at the next launch that day, from the log
      not having it (`Core.grewLost`).

In the docs and tools:

- [x] A `digest` row in the Words table of `CLAUDE.md`.
- [x] A check on the test runner's count: `gen-test-runner.py`'s floor.
- [x] `make -C internal check` doesn't build for the boards: by choice, as it takes
      minutes. `make -C internal boards` does, and CI.

## Now: the simplify branch, on the board (2026-11-01)

What the `simplify` branches change on the board, for the owner to look
at after `make flash` and a new voice on the card:
- [ ] A stopped or failed turn shows no card; a helper coming back plays nothing.
- [ ] Pastimes still come by tier; a yawn or sneeze from `tier1`; busy typing still speeds up.
- [ ] Free heap at boot is about 76.8 KB higher than before.
- [ ] The voice plays once the card has the new `voice.bin` (`353ddadc006b`).

## Owed on the board, from the night of 2026-11-01

From the plans that were finished and deleted, for the owner, after
`make flash`:
- [ ] Work acts: the look and the frame rate of the push, the tests and the build, full and small.
- [ ] A finish's low sign: can you read the thread's name at arm's length, and does a cheer still read?
- [ ] A tap on a finish: the face, the rim and the strip during a finish each open the thread.
- [ ] A lock and an unlock: a wave, a snub or the nap; a Boop asleep when the Mac goes quiet stays asleep with no plug until you touch it.
- [ ] Alive without the Mac: it breathes, sleeps, answers a poke or a stroke in its last mood, and gives a small hello when the Mac returns.
- [ ] The wish's bubble: its place beside the head, its how, the heart popping; none during a full act or with no Mac.

## Now: from the night's review (2026-11-02)

- [ ] A dream's write can be lost if the writer fails (`Memory.swift`, `dream()`).
- [ ] Several buddies don't replay an away (`Pipeline.readBack`).
- [x] The Pixel wish's text (`screens.h:48`, `sameModel`): a wish coming or going now redraws (`test_a_wish_redraws_the_picture`).
- [x] A `Measure` around `paintActFront`, for the board's frame rate check: `profile.front`, `front_us` on the profile line.
- [ ] **For the owner:** `make eval` refuses without the override, so your bare command never runs.
- [ ] Remove the dead lost-link path.
- [ ] Acts: wall caching and a frame cap.
- [ ] Unify the acts' timing.
- [ ] The idle `tower` pastime is hard to read.
- [ ] The takes "We pushing!", "shipped!" and "built it!" aren't recorded: until then Jev has the voice's existing words.
- [ ] Jev rarely speaks over an act from a calm mood.
- [ ] The duplicated memory cards on the Overview ("What Boop remembers", "Recently") and the Memory pane: whether they move is the owner's call.
- [ ] Eval Level A's 7 confirmed unreasonable runs: 11, 19, 47, 90, 91, 96, 140.
- [ ] No standard eval run since items 2 to 10 of the night.
- [ ] Pixel Bro's clone fails `boopdev check`: `personality.md` is missing.
- [ ] A chat wish already open when you take back the mic's authorization still waits and can give up: nothing rechecks it.
- [ ] A wish can give up while you're idle, before the away is noticed: the away takes back the wait, but not a give-up already played.
- [ ] A wish's wait read back on launch counts time a needs-you or a doze held, and time Boop wasn't running between two events of the same day: the transcript has no launch marker, and the wait isn't recorded until its end.

## Now: left by the finished plans (2026-11-01)

- [ ] **The care lean.** A cuddly "You and Boop" note still leaves a
      poke from calm curious (eval 149, 3 of 3); the lever left is a
      sentence in `calm.md` letting its fade follow the note.
- [ ] **Lonely on the AMOLED:** look at the lonely idle, the lonely
      wake-up and a stroke ending it; add a reunion clip (Boop perking
      up toward you) if the look falls flat.
- [ ] **The work stream's replay check:** the owner's 229-call session
      as a fixture through `Boop --headless --brain scripted` to the
      simulator: words reach `state.calls`, at most 4 states a second,
      none of the first rank dropped but by ttl, and the brain's passes
      the same with the stream on and off.
- [ ] **Pixel's copy of the voice** still has the 164 `attention` takes
      the gel's lost (SlimeBuddy's voicegen leaves them out now): copy the
      new `voice.bin` and `takes.tsv` over, then drop `Take.Part.attention`.
- [ ] **Eval 09** fails 1 run in 3 (accepted for now); 14 and 98 are
      known gaps (internal/EVALS.md).

## Now: Pixel Bro, the third character (2026-10-26)

Pixel Bro is in [PixelBro](https://github.com/Mellow-Machines-Lab/PixelBro):
Pixel's face on the AMOLED with a new soul. Making him showed what makes a
new character slow; [new-character-playbook.md](../characters/new-character-playbook.md)
has the playbook and the fixes to pick from.

- [ ] Pick which of the playbook's fixes to build first (a scaffold,
      a shared voicegen and the pack-generic voice checks would have
      saved the most).
- [ ] CHARACTER.md §14 still says to copy a pack into the engine's
      `characters/`; rewrite it for packs in repositories of their own.

## Now: the QA night, as users (2026-10-26)

The owner asked for a night of using Boop as users would. Seven testers
played profiles on the simulated board through the headless app: a
first-week buyer with no key, a multi-agent power user, a talker with
the real brain, the clock and calendar, the Mac app's surfaces, a real
workday with the brain, and odd inputs with restarts. What they found
and is fixed is in the night's commits here and SlimeBuddy's; what's
left is below.

- [ ] The mood after a win: calm goes to annoyed at your frustration
      (`mood/calm.md`), where annoyed itself says frustration means
      determined, and annoyed has no way out at a check passing or a
      turn done but a 3-minute fade, so Boop frowns through a success.
      Suggested: calm to determined at frustration; annoyed and irritated
      to relieved when a check passes after failing. Needs the moods'
      `moves` (the design's emotion graph) and Jev's mood evals.
- [ ] Voice: quick, easy wins can say relief ("Phew", "Whew"), tagged
      plain `glad`; some takes' meanings read wrong where they play
      ("Yep" as tickled at a poke, "Failed" as upset, "Search" at a
      compaction, "Restart" as retry, "Mwahaha" for a typo fix). The
      bank's tags (voice-range).
- [ ] Steering: `boop.md` says an idle check-in gets "a small face or
      nothing" but its Example gives medium; an approval's Example
      cheers ("pleased, says glad"), which on a day of approvals is
      noise and requests.
- [ ] A request restored at relaunch whose answer came while the app
      was down stays amber up to a day (the agent's process lives on);
      and each relaunch numbers requests afresh, so the board knocks
      again for one already seen. Both in AgentHooks' session tracking.
- [ ] With four lanes, a long word in an outer lane is cut by the panel's
      edge; moving it in puts it over the next lane and behind the body.
      A smaller font, or a shorter word, at three and four lanes.
- [ ] A demo's `wait` that jumps the clock while a reaction plays ends
      it as "didn't happen" in HISTORY.

## Now: the overnight UI audit (2026-10-26)

The owner asked for every UI and UX bug on the Mac and the board,
fixed overnight. Four reviews (the popover, onboarding, the board's
drawing, its touch and sound) found them; what's fixed is in the audit's
commit here and SlimeBuddy's.

- [ ] On the AMOLED: none of it is played on the board yet. It stopped
      answering over USB (not even its bootloader), so unplug it and
      plug it back in, flash, and feel the drawer, the needs-you hold,
      a rub, and carrying it (the put-down's new steadiness, 40 mg for
      1.5 s, is a first guess to tune).
- [ ] The strip comes back at once after a bubble: its fade belongs in
      `Behaviour::strip` (when the bubble ended), not the face.
- [ ] Decide: the popover's mic button says "Talk", which the Words
      table keeps for the talk level; and an agent's first hook after
      Connect counts as the hello even from a session already open.

## Now: calm work (2026-10-25)

The owner found the working look's body boring and its kit cluttered,
and chose a calm look that works harder the longer the agents do, with
the whole body moving now and then (the calm-work plan (in git: `plan/calm-work.md`)).

- [ ] On the AMOLED: how the moves and the typing feel, by the owner.

## Now: talking back (2026-10-25)

The owner wanted the buddy to understand what's said to it, a smart pet
rather than a conversation (the talk-back plan (in git: `plan/talk-back.md`)).

- [ ] On the real AMOLED: whether each reply's clip reads as meant, a
      nod, a shake of the head, a shrug and the rest
      (`make demo NAME=talk-back FACE=gel` plays them in the simulator).

## Now: four questions, and talking back, part two (2026-10-25)

Every reaction asks the same four things, and talk covers what it
didn't (the talk-back plan (in git: `plan/talk-back.md`), Part two).

- [ ] On the real AMOLED: the zipped mouth while hushed.
- [ ] On the real AMOLED: the new clips, and the nap and dance on
      request.

## Now: the polish pass (2026-10-25)

The owner asked for smoother animation, crisper pictures, quicker touch
and a simpler build. Four audits (the gel's picture, the board's frame
pacing and touch, the Mac app, the architecture) found what's below.

- [ ] On a real Mac: the popover opens quickly and never shows a stale
      pose; the 46 pt slime is crisp at 60 fps; with Bluetooth off it
      stays the slime; onboarding's acts show no black glass; two quick
      confetti bursts both play; the menu-bar glyph looks centred.
- [ ] On the real board: whether the hat and the falling words now look
      smooth asleep and at work, and whether words entering behind the
      panel's top corners (110 px radius) look like they come from above
      or look cut off.
- [ ] No tearing sync. The CO5300's TE line is wired to GPIO 13 (a
      probe counted 12 rising edges in 200 ms: 60 Hz; LovyanGFX's init
      already sends TE on). Syncing isn't simple: a push writes bands of
      16 panel columns each across the whole scan, so it crosses the
      scan line ~26 times a frame, and at 40 MHz the writer (~15-20 panel
      rows a ms, preempted by the body's helper) is about half the scan's
      speed (30 rows a ms). Tear-free needs pushes in scan order (bands of
      panel rows) started just behind the scan line, the scan's direction
      checked on the panel; or 80 MHz QSPI (needs eyes on the panel).
      Tried 2026-10-26 (branch `tearing-scan-order`, not merged): bands of
      16 panel rows sent in scan order, each band's changed rows as up to
      four runs, from TE's rising edge (`dbg.scan off|down|up`), with a tear
      counted when the scan, timed from TE, passes a band as it's sent.
      `perf --scenes`: 26% of frames counted torn unsynced, 26-29% synced
      (either direction), the push 3-4 ms longer and attention under its
      28 fps. A push takes 22-38 ms for 60-130 K pixels, far below the
      bus's 10 px/µs: it waits on the body's helper (priority 2, above the
      push's 1) and packing, so it can't stay ahead of the scan. Raising
      the push above the helper while a synced frame goes made it worse
      (34% torn; working 33.7 -> 30.2 fps, night 22.7 -> 20.2), and even
      unpreempted a push of 65 K pixels took ~20 ms. A push's time is its
      wall time on core 0, under the body's helper since the pass added
      it (60 K pixels took ~7.5 ms before; the material read from flash
      instead of PSRAM leaves it at ~25 ms, so that isn't it). The loop
      waits on it only 0.1-1 ms a frame, but a synced frame can't stay
      ahead of the scan while the helper shares the core: a tear-free
      push wants core 0 to itself for ~8 ms, which the body's split
      can't give without slowing every frame.
- [ ] The engine's step is 2.3-2.6 ms a frame on the AMOLED (2.5 µs on
      the Mac): its 25 KB `Engine` is in PSRAM (malloc puts anything over
      4 KB there) and its code runs from flash past a 16 KB cache. The
      other core can't hide much of it (looked at 2026-10-26, natively):
      a frame takes 2.6-3 steps (the 16 ms grid and the pass's own time),
      and only the first, about 38% of them, depends on nothing that
      arrives during the pass (messages, the finger, `sync`'s occasion and
      held expression, a landing word); `Engine::step` is 59% of
      `engine_us`, the face's work after it the rest. Stepping a copy
      ahead on the other core would hide at most ~0.55 ms a frame, likely
      0.2-0.5 with the shared caches and bus, for a second 25 KB engine
      copied each frame and a guard on everything that changes it. The
      lever is the step itself: fewer of them a frame, or less code
      (about 45 KB at -Os, fetched from flash each step).
- [ ] The board's frame rate, all of the above merged (01ee9a01,
      `perf --scenes`, 12 s a scene, muted; before is the pass's start,
      008e5e7d): asleep 45.3 → 42.4 fps, working 38.4 → 37.0, pokes
      38.2 → 36.8, attention 34.0 → 32.7, frightened 31.3 → 31.9; the
      new stream scene 31.2 and night 24.4. The sharper material and the
      outline cost ~1 ms of body, the hat's sub-pixel replay ~3.5 ms at
      night. Every scene passes; the internal heap's least is 50,968
      against 50,000, so ~1 KB is left (by bebdb5a7 it was 48.2 KB, every
      scene failing; SlimeBuddy's 09fb042 puts the outfit's recordings in
      PSRAM: 66.4 KB, every scene passing, fps unchanged). Owner's call: whether night's
      24 fps is enough for a smooth hat (whole-pixel replay gives ~28),
      and whether an even 30 fps reads better than ~37 on the 60 Hz
      panel. `perf --motion`'s 60 KB heap budget fails, as it already did
      at 008e5e7d (51.5 KB): the budget or the heap wants a look.

## Now: the character engine

The plan is the character-engine plan (in git: `plan/character-engine.md`): one rig, mixer and
layer stack for both faces, packs as data agents edit, references turned
into clips, and the Studio as the dashboard. Each checkpoint lands
reviewed, simplified and merged. Measure fluidity with
`internal/tools/fluid/` (baseline 2026-10-23, gel: a mood change's
largest frame 32x its median, a finish's 33x, going to work 9x).

**The CYD is frozen** (the owner, 2026-10-24): it keeps building and
gets no new features; new work is the AMOLED board's, on the gel's own
engine and its rig (checkpoint 5), starting with
the work-stream plan (in git: `plan/work-stream.md`). Pixel's rig face on the board waits
with it.

- [ ] **The gel on the rig on the board**: its frame cost on the AMOLED
      with a hat, asleep at night and at `tier5`, its pastimes and kit
      out (`boopctl perf --scenes`), and a look at the stretch, the
      layers' fades, the notice and the pastimes.
- [ ] **6. Retire what the engine replaces.**

## Now: something new at every glance

The tiers' art, from the glance-and-wait plan (in git: `plan/glance-and-wait.md`) §3, redone
with the owner on 2026-10-25: five tiers, closer together, and something
to see at each.

- [ ] **The pastimes on the board**: a look on the AMOLED, and their
      frame cost there with the kit and a pastime out (`boopctl perf
      --scenes`); tune their timing and art.

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

## The five repositories: a recommendation (investigated 2026-11-01, nothing changed)

**How it is.** The engine fetches the packs it's tested with from
`characters/packs.json`, at each pack's `main`, into `characters/.repos/`.
Each pack in turn pins the engine as `engine/`, a submodule, and its
`Makefile` runs every target through it (`make setup` links the pack in
and chooses it). A pack's CI checks it against its pinned engine; the
engine's checks run against the packs' `main`. A change that spans both
lands pack first (or the engine's checks fail), but the pack's CI runs
against the old pin until the engine is pushed and bumped: each such
change is three commits in two repositories, and for a while one side's
checks are red. The gel's engine (`render/gel/`) is the pack's own C++,
so most slime work is exactly such a change.

**Can the packs drop `engine/`?** Who builds a pack on its own: its CI,
and a contributor who clones only SlimeBuddy or PixelBuddy and runs
`make flash` or `make dev`. Buyers never do: they get Boop.app with its
packs inside. Both need *an* engine at a known commit, not a submodule.
Recommendation: yes, replace the submodule with a pinned commit in the
pack (`character.json`'s `engine`, or one line in `Makefile`) that
`make setup` clones into an ignored `.engine/`. The same reproducibility,
no gitlink to bump by hand, no nested submodules (the engine's own two)
inside a submodule, and a pack clone needs no `--recurse-submodules`.

**What would make cross-repo changes lighter**, in order of payoff:
1. *Bring the two first-party packs back in as folders* (`characters/boop`,
   `characters/pixel`): one commit per change, one CI, no bump dance.
   Keep SlimeBuddy and PixelBuddy as their public faces, published from
   those folders by `git subtree split` on release. Pixel Bro and any
   third-party pack stay outside, on a pinned engine. This undoes the
   split of 2026-10-26, so it's the owner's call; it's the only option
   that removes the problem rather than easing it.
2. Short of that, *pin the packs in the engine too*: `packs.json` names
   each pack's commit, not `main`, and `packs.py --bump` moves them. The
   engine's checks are then reproducible, and a cross-repo change is:
   the pack's branch pushed, the engine's commit pinning it, the pack's
   pin moved by a script, with neither side red in between.
3. A `boopctl` command that starts one branch name in the engine and
   both packs, runs `make -C internal check` across them, and prints the
   pushes in order (package, engine, packs), so the order is a tool's,
   not a person's memory.
