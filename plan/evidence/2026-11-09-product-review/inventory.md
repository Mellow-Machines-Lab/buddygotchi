# Boop concept inventory (for the simplification audit)

Measured 2026-11-09 in the worktree `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish`
(branch `v1-polish`, engine `270ee70c`, SlimeBuddy `a1eea4a`, PixelBuddy `15e5302`).
Research only. No repo file was changed.

## How the numbers were made

- **LOC** is `wc -l` (blank lines and comments count). The code base is comment-heavy, so real code is about 60-70% of each figure (estimate).
- **File totals** come from this helper, run per folder:
  `find -L DIR -type f \( -name '*.swift' -o -name '*.cpp' -o -name '*.h' -o -name '*.c' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.mjs' -o -name '*.html' -o -name '*.css' -o -name '*.md' -o -name '*.sh' -o -name '*.json' -o -name '*.jsonl' -o -name '*.ini' \) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.build/*' -not -path '*/.pio/*' | xargs wc -l`
- **Mention lines** are `grep -r -i -E 'REGEX' DIR | wc -l`: lines that name the concept. They show spread, not ownership. Script: `/tmp/boop-review/g.sh REGEX`.
- **Tests and evals "named"** are a regex match on the test function name (`func test…` in `internal/app/Tests/*.swift`, `void test_…()` in firmware and pack tests) and on the eval file name or its `name` field. Script: `/tmp/boop-review/t.py LABEL REGEX`. These are estimates: a regex both over- and under-matches.
- "gel" = `characters/boop/firmware/src/render/gel/` (the path is real; `characters/boop` is a symlink to `characters/.repos/SlimeBuddy/character`).
- Every figure marked (est.) is an estimate.

---

## 1. Doing (`base`)

- **Values: 5 in the model** (resting, working, asleep, listening, no app). **On the wire `base` has 3:** `idle`, `working`, `asleep`. The board adds `listening` (BOOT held, or the `listening` do) and `no_app` (link lost) itself. The needs-you screen (`attn`) is a sixth look.
- **Defined:**
  - `app/BoopKit/Core/Core.swift:623` (`let base = !working.isEmpty ? "working" : sessions.isEmpty || dozed ? "asleep" : "idle"`).
  - `app/BoopKit/Core/StateSnapshot.swift:124-126` (`doing`), `:294` (`"base"`).
  - `firmware/src/render/types.h:25-50` (`SceneState`: 22 states, of which 6 are Doing looks, 8 are activities, 8 are Moment animations).
  - `characters/boop/rig/looks.json` (3 looks: idle→`breathe`, working→`work`, asleep→`doze`), transitions `to-rest.json`, `to-sleep.json`, `to-work.json`.
  - `characters/studio/states.json`: 7 groups, 20 states.
- **LOC:** not separable. Mention lines for `asleep|no_app|idle|working|doing|base|listening`: Swift 334, firmware/src 171, gel 208, Pixel firmware 26, Swift tests 303, firmware tests 702, gel tests 349.
  Command: `grep -r -i -E 'asleep|no_app|kNoApp|kAsleep|"idle"|kIdle|"working"|kWorking|doing|\bbase\b|listening|kListening' DIR | wc -l`.

## 2. Activities (`act`)

- **Values: 8**, in priority order: `testing, delegating, terminal, searching, analyzing, tool_use, waiting, planning`.
- **Defined:** `app/BoopKit/Core/Activity.swift:7-8` (`enum Act`), rules `:21-110` (hold 1,500 ms, waiting after 20 s). Board: `firmware/src/render/types.h:34-41`.
- **LOC:** `Activity.swift` 111. Tests: `internal/app/Tests/ActivityTests.swift` 469 lines, 18 tests. Each activity is one recipe row × 44 profiles × 3 takes in the generated `slime.h` (so 8 of 28 recipe states).
- Mention lines (`\bAct\b|activity|shownAct|…`): Swift 339, firmware 56, gel 173, steering 3.

## 3. Tiers

- **Values: 5.** `tier1` 30 s, `tier2` 60 s, `tier3` 2 min, `tier4` 5 min, `tier5` 10 min. Shared by working and idle. Also sizes a finish (`turn` 0-5).
- **Defined:** `app/BoopKit/Core/Tags.swift:33-46`. Board: `firmware/src/render/tags.h:16-19, 32-34`, `tags.cpp:14-20` (`reached`). Finish size: `app/BoopKit/Outputs/Moment.swift:134`.
- **Serves:** 5 working clips in `looks.json` (`work-easy`, `work-leaning`, `work-focused`, `work-content`, `work-zone`), the pastime table's tier column, the kit.
- **LOC:** about 20 lines Swift, about 15 lines firmware of its own. Mention lines for `tier`: Swift 30, firmware 27, gel 56, Swift tests 74, gel tests 95. Tests named: 3 Swift, 4 firmware. Evals named: 1 (`116-tiers-on-the-screen`, scripted).

## 4. Pastimes, kit, dressing

### Pastimes: 52 rows
- **Defined:** enum `characters/boop/firmware/src/render/gel/pastimes.h:56-115`, table `pastimes.cpp:20-73`.
  Count command: `sed -n 20,74p pastimes.cpp | grep -c '{Pastime::k'` → 52.
- **By look:** working 19, idle 24, needs-you 4, asleep 5. **By body:** rig clip 39, engine bit 9, engine take 4. **Moves** (whole body): 3 (reach, melt, stretch-break).
- **Names:**
  - Working (19): sip, peek, hum, done-beat, ponder, read, nod, bop, drum, sticky, phones-on, coffee-reach, refill, snack, melt, stretch-break, stretch (limber), busy-typing, frantic-typing.
  - Idle (24): look-around, hopeful, hop, bubble, doodle, book, game, water, brb, tower, dance, plane, snooze, daydream, snuggle, yawn-and-settle, sneeze-and-shake, morning-stretch, night-drowse, party-bounce, friday-sway, winter-shiver, halloween-wobble, valentines-swoon.
  - Needs you (4): wave (30 s), tap (2 min), watch (5 min), drowsy (10 min).
  - Asleep (5): roll-over, sheep, snore-bubble, deep-snore, dream.
- **LOC:**
  - `pastimes.cpp` 1,375 + `pastimes.h` 238 = **1,613**.
  - Per-pastime drawing function in `pastimes.cpp` (lines from one function start to the next; awk over lines 535-1243): sip 15, peek 9, hum 11, ponder 28, done 21, read 18, phonesOn 9, nod 12, bop 14, drum 12, sticky 19, refill 19, reach 18, melt 26, stretch 11, snack 28, blanket (snuggle) 96, lookAround 8, hopeful 11, hop 14, blow (bubble) 19, doodle 24, book 27, game 26, water 20, brb 13, tower 23, dance 28, planeAt+paperPlane 38, snore 14, wave 16, tap 13, watch 25, drowsy 13, rollOver 10. **Median about 18 lines each; about 710 lines of per-pastime drawing.** The other 665 lines are the table, shared shapes (hand, note, star, heart, cloud, mug, …) and the kit.
  - Rig clips: `characters/boop/rig/clips/` has 73 JSON files, 768 lines; 39 are pastime bodies (about 10 lines each).
  - Engine bits and takes: 11 entries in `design/slime-blob/expressions.json` `pastimes` and 4 `gags`, generated into `slime.h`.
  - Tests: `characters/boop/tests/firmware/test_gel/test_pastimes.cpp` 588 lines, 12 tests; mention lines in gel tests 128. Popover names: `characters/boop/mac/passing.tsv` 59 lines.
- **Dealing rules:** rest 4-10 s between two, newest 60% of the time, moves at least 90 s apart, each row has a growth stage (1-3) that "knows" it.

### The kit: 4 props
- Mug (stack to 4 from tier5), headphones (tier3, with tune notes), zone motes (tier5), plant (idle, tier3-5, 3 sizes).
- **Defined:** `pastimes.h:35-44, 172-190`, drawing in `pastimes.cpp:318-486` (mug 25 lines, motes 16, headphones+cups+tune about 75, plant 29). **About 150 lines** (est.).

### The dressing: 13 designs
- **Outfit 6:** nightcap, party hat, witch hat, bobble hat, pyjamas, shades. **Air 3:** snow, confetti, hearts. **Sky 2:** night sky, sun. **Beside 2:** Zs, coffee mug.
- **Defined:** rules in `firmware/src/render/tags.h:63-77` and `tags.cpp:37-54`; art in `characters/boop/firmware/src/render/gel/layers.cpp` (925 lines) + `layers.h` (125).
- **LOC per design in `layers.cpp`:** nightcap 39, partyHat 20, witchHat 20, bobble 17, shades 17, pyjamas 48, snow 9, confetti 12, hearts 16, zs 15, nightSky 28, sun 72, coffee 65 = **about 380 lines of art**, plus about 220 lines that cache and blend the outfit (`wear`, `outfit`, `lookFor`, `paintLayers`, `paintSky`). **Dressing total about 600 of the 925 lines** (est.). The rest of `layers.cpp` is the sign (about 60), the wish bubble (about 70) and the growth bar (about 80).
- Pixel has its own: `characters/pixel/firmware/src/render/pixel/outfit.cpp` 133 + `outfit.h` 24.

## 5. Moods

- **Values: 16 lasting moods**, of 42 faces: calm, comfy, lazy, happy, excited, curious, engaged, determined, proud, annoyed, irritated, grumpy, sad, wounded, surprised, lonely.
- **Defined:** `characters/boop/character.json` `moods` (42 entries; the 16 with a `moves` key are lasting). Swift: `app/BoopKit/Character/CharacterPack.swift` (298), `Character/Moods.swift:9-15` (the 42 names), `Outputs/MoodGraph.swift` (32), `Outputs/MoodOutput.swift` (116).
- **The graph:** in `character.json` only. **119 directed edges: 79 ordinary, 40 dramatic (jumps).** Per mood 3-7 ordinary and 1-4 dramatic. calm has the most (7 + 4). The same graph is byte-equal in the Pixel pack. The board's copy is generated: `slime.h` `kEdges` = 119, 40 dramatic.
  Command: python over `character.json` summing `moves.ordinary` and `moves.dramatic`; and `awk 'NR>=138 && NR<=257' slime.h | grep -o '{[0-9]*,[0-9]*,\(true\|false\)}' | wc -l`.
- The 26 face-only moods each have a `settles` key (the lasting mood they move as).
- **Fades:** prose only, in each mood file ("only for 5 min … fades to happy"). No fade code. `MoodOutput.sinceLine` gives Jev the minutes. The hourly check-in still exists (`TranscriptView.swift:266`).
- **Steering:** `characters/boop/steering/mood/*.md` 16 files, **205 lines** (9-17 each). Pixel: 16 files, 98 lines.
- **Tests:** `MoodGraphTests.swift` 58 lines, 3 tests; `CharacterPackTests.swift` 206, 10 tests; gel `test_bridges.cpp` 606 lines, 7 tests (the transitions the board draws). Named (regex `mood`): 17 Swift tests, 7 firmware tests, 14 evals; 76 of 148 evals mention a mood.
- Mention lines for `mood`: Swift 427, firmware 83, gel 81, Pixel firmware 158, steering 49, Swift tests 497.

## 6. Emotions (a Moment's faces)

- **Values: 42**, plus 2 art variants (`comfy:rosy`, `speechless:tearful`) = 44 profiles.
- **All 42:** calm, comfy, lazy, bored, pleased, happy, excited, curious, engaged, determined, proud, mischievous, shy, uncomfortable, annoyed, irritated, grumpy, angry, disappointed, sad, crying, whiny, wounded, uneasy, scared, frightened, surprised, stunned, speechless, amused, hopeful, relieved, confused, baffled, skeptical, embarrassed, affectionate, lonely, tired, exhausted, overwhelmed, disgusted.
- **Defined:** names `app/BoopKit/Character/Moods.swift:9-15`; meaning and `face` text in `character.json`; art in `characters/boop/design/slime-blob/expressions.json` (6,582 lines; 44 expressions of 82-130 pretty-printed lines each, about 100 average).
- **How each is drawn:** data, not code. `tools/slimegen/painter.mjs` (235 lines) + `face.mjs` (39) turn each expression into vector paths. Generated `slime_art.h` has 372 paths and 10,998 point lines for 44 arts: **8.5 paths and 250 points per emotion on average** (bored/engaged/annoyed 95 points; scared 555, frightened 557). Each emotion has its own eye shape (44 distinct eye names) and 39 distinct mouths; 7 have tears. Each also has 3 "performances" and one recipe row per state (28 states × 3 takes) in generated `slime.h`.
  The hand-written face code is shared: `gel/face.cpp` 785, `art.cpp` 283, `motion.cpp` 208.
- **Voice takes:** takes are **performed in 13 moods only**: calm, engaged, happy, determined, annoyed, whiny, curious, grumpy, excited, proud, sad, irritated, wounded. The other 29 borrow (the pack "lends" takes), so all 42 play 219-331 takes each. No emotion is silent.
  Command: python over `characters/boop/mac/takes.tsv` column 6.

## 7. Sizes

- **Values: 4.** small (1 loop, a sound), medium (2 loops, a word), big (3, a phrase), huge (4, a phrase).
- **Defined:** `app/BoopKit/Outputs/MomentOutput.swift:486-508` (`sizeOptions`, `sizes`, `size`). Wire: `loops` (board cap 6, `Moment.maxLoops`). Also sets hush length (15/30/60/120 min).
- **A second size scale exists for finishes:** small, medium, big (4 designs: Gold Rush, Jelly Fireworks, Mini-Boop Parade, Proud Spotlight), biggest (Mega Boop), chosen by `loops` and the turn's tier. `gel/finish.cpp` 835 + `finish.h` 97.
- **LOC of its own:** about 25 lines Swift. It is one of Jev's 4 questions (`react.intensity`).

## 8. Moment kinds

Jev answers 4 questions per pass (`react.face`, `react.move`, `react.intensity`, `say`) plus `mood`, and sometimes `react.sign`. Most kinds are decided in `app/BoopKit/Outputs/MomentOutput.swift` (1,079 lines, the largest decision file).

| Kind | Where decided | LOC that mostly serves it | Tests named (Swift / firmware) | Evals named (mentioning) |
| --- | --- | --- | --- | --- |
| Finish (success, failure, reply) | Jev's `react.move` → `MomentOutput.swift:528-560` (`animations`, `scenes`); board sizes it | `gel/finish.cpp`+`.h` 932, `gel/done.cpp`+`.h` 139, `gel/low_sign.cpp`+`.h` 182; `test_finish.cpp` 269 | 19 / 20 | 14 (99) |
| Greeting (`wake_up`, `notice` anims) | Jev's `react.move`; day greeting rule `Core.swift:552-569` | recipe rows + `rig/clips/notice.json`; about 60 lines Swift (est.) | 9 / 14 | 10 (24) |
| Wave (lock, unlock; `bye`, `hello`, `reply-wave`, nap) | `MomentOutput.swift:400-450` (`lockQuestions`, `mayNap`, `waved`) | about 70 lines Swift; `LockTests.swift` 181 (8 tests); 3 clips | 13 / 14 | 7 (14) |
| Reply (to your words) | Jev's `react.move` among 16 replies + `unhush`; `MomentOutput.swift:324-370, 740-840, 1068-1079`; `Core/Core+Talk.swift` 209; `Outputs/StatusReply.swift` 220 | `steering/replies.md` 68 lines (67 lines of signs, 16 tags); 19 `reply-*.json` clips; `ReplyTests.swift` 589 (21 tests); 864 reply takes | 29 / 13 | 11 (37) |
| Ask | `Outputs/Asks.swift` 153; offered in `MomentOutput.swift:155-195` | `steering/asks.md` (2 questions, 4 answer lines); board targets in `device.cpp` and `behaviour.*` (84 firmware mention lines); `AsksTests.swift` 165 (10) | 31 / 12 | 14 (41) (regex is broad) |
| Wish (3 kinds: pet, chat, work; ends met, gaveup, closed) | `Core/Core+Wish.swift` 230 (a rule); sign picked by Jev (`MomentOutput.swift:123-129`) | 15 `[wish …]` lines in `asks.md`; `layers.cpp` `paintWish`+`wishIcon` about 70; dos `wish_met`, `wish_gone`; `WishTests.swift` 349 (15) | 8 / 10 | 12 (17) |
| Notice (4 kinds: waiting, stretch, rough, late) | `Core/Notices.swift` 198; offered `MomentOutput.swift:141-154` | 12 `[notice …]` lines in `signs.md`; `NoticesTests.swift` 394 (20) | 6 / 2 | 5 (10) |
| Musing | `MomentOutput.swift:115-122` (`mused`) and the sign question | 6 `[idle]` lines in `signs.md`; 19 Swift mention lines | 6 / 0 | 5 (9) |
| The telling (dream) | `MomentOutput.swift:75-81` (`told`), `Memory/DreamReader.swift` 91, `Core/TranscriptView.swift` | `steering/dreams.md` 17 sign lines; 33 Swift mention lines | 18 / 0 (regex includes "dream") | 3 (5) |
| The day's greeting | `MomentOutput.swift:82` (`firstToday`), `Moment.greeting`; board holds the stream back (`behaviour.cpp`, 23 firmware mention lines) | about 35 Swift mention lines | 6 / 3 | 3 (14) |
| Work acts (3: push, tests, build) | rule in `Core/WorkStream.swift:80-118` and `Core.swift:265`; Jev says the voice | `gel/act.cpp` 1,133 + `act.h` 68 = **1,201**; `character.json` `acts` (9 sentences) | 0 / 7 | 4 (5) |
| The work stream (16 call styles) | rule: `Core/WorkStream.swift` 421 | `firmware/src/render/stream.cpp`+`.h` 464, `gel/stream.cpp`+`.h` 527; `WorkStreamTests.swift` 516 (26 tests) | 2 / 19 (26 in its own file) | 0 (2) |
| Level-up, size grown | rule: `Core.swift:486-539` (`grew`) | see Growth | 7 / 1 | 0 (0) |
| The ring closing | rule: `Core.swift:519-526` | see Growth | 12 / 13 (regex broad) | 0 |
| World gestures (4: boop, wave, heart, cheer) | `World/WorldGestures.swift` 92 (limits), Jev answers | 10 `[world …]` lines in `signs.md`; see The world | 4 / 4 | 7 (24) |
| Rule start card (`starting`, 4 contexts) | `Core.swift:377-392` | `gel/props.cpp` start card | — | — |
| Board's own (poked, tap_spam, gesture ×10, listening) | firmware `behaviour.cpp` | see Touches | — | — |

Call styles (`firmware/src/render/stream.h:12-31`): land, helper, back, shatter, bonk, bonk2, bonk3, throw, shrug, timeout, no, compact, buried, freeze, drop, gather.

What Jev can say (`say`): none, swear, 4 feelings (upset, glad, tickled, shaken), 16 topics (start, helpers, helper back, retry, work, tests, command, tool, looking, planning, done, answer, stopped, waiting, quiet, hello) = 22 options (`MomentOutput.swift:284-312, 512-524`).

Event kinds in the transcript: 26 (`app/BoopKit/Core/Event.swift:31-…`): session, turn, tool, subagent, poke, presence, lock, heartbeat, talk, needs_you, listen, reacted, press, gesture, hush, act, prompt, last_message, dream, memory, wish, level, ring, world, link, ask.

## 9. Talk

- **Values: 3 + 1.** quiet, normal, chatty; and hush (silent for 15, 30, 60 or 120 min by the moment's size).
- **Defined:** `app/BoopKit/Core/Talk.swift` (40), `Core/Core+Hush.swift` (79), tag `hushed` (`Tags.swift:24`). Check-in pace per level in `Talk.pace`. UI: `app/Boop/Talk.swift` (171; this file is push-to-talk).
- **LOC:** 119 lines of its own; `hush` mention lines Swift 146 (35 in `MomentOutput.swift`), firmware 30. Tests: `HushTests.swift` 129 (5 tests). Evals with a talk level: 4 chatty, 1 quiet (from `boopdev eval --list --level full`), plus `129-hushed-says-nothing`.

## 10. Touches

- **Values: 14 in Swift** (`app/BoopKit/Core/Touch.swift:8`): poke, stroke, lean, ruffle, swipe, nose, tickle, dizzy (shake), pickup, putdown, startle (thump), facedown, peekaboo, dismiss. The board's `Gesture` enum has 10 (`firmware/src/render/types.h:69-81`): handoff, stroke, ruffle, nose, tickle, dizzy, pickup, putdown, startle, peekaboo. BOOT gives tap, hold (push-to-talk).
- **Where detected:**
  - Finger: `firmware/src/app/touch_gesture.h` 96 + `.cpp` 84 = 180. Classifies tap, swipe, stroke, ruffle, tickle, nose, hold, lean.
  - Motion (IMU): `firmware/src/app/motion_gesture.h` 91 + `.cpp` 101 = 192. Pickup, putdown, shake, thump, face down, face up; plus `Tilt` (slosh).
  - BOOT: `firmware/src/app/gesture.h` 38 + `.cpp` 33 = 71.
  - Captions: `firmware/src/app/touch_reason.h` 32 + `.cpp` 35 = 67.
  - Routing: `firmware/src/app/device.cpp:458-940` (165 touch mention lines in `device.cpp`).
  - Boards: `board/amoled206/touch.cpp` 84, `imu.cpp` 51; `board/cyd24/touch.cpp` 71; `touch_cal.h` 86.
- **Per touch** (detection is shared code, so LOC is not separable; mention lines firmware/src, gel, Swift):

| Touch | Detected in | Triggers | Mention lines (fw / gel / Swift) |
| --- | --- | --- | --- |
| poke (and a run) | `touch_gesture` tap | board plays `poked`, `tap_spam` from the 3rd; `ev tap`; Jev may answer once per run; care XP 3; meets a pet wish | 33 / 16 / 200 |
| stroke | travel ≥ 40 px, slow | gesture take; `ev gesture stroke`; care; meets a pet wish | 36 / 58 / 111 |
| lean (doze after 5 s) | finger at rest 1 s | body leans in, dozes; `ev gesture lean`; care | 61 / 109 / 76 |
| ruffle | stroke going up | gesture take; care; meets a pet wish | 10 / 0 / 5 |
| nose boop | tap in 28 px box at (160,134) | gesture take; care | 20 / 11 / 10 |
| tickle | wiggle ≥ 90 px in 36 px | gesture take; care | 14 / 0 / 10 |
| swipe | travel, > 600 px/s | body flings; on the strip opens the drawer; not care | 29 / 6 / 9 |
| shake | 3 swings > 500 mg in 600 ms | `dizzy`; the shake ladder (whoa → stop); care | 22 / 25 / 32 |
| pick-up | off 1 g by 150 mg for 150 ms | `pickup` take; care | 22 / 4 / 43 |
| put-down | still 1.5 s after held | `putdown` take; not care | 8 / 0 / 5 |
| thump | jolt > 350 mg under 80 ms | `startle` take; not care | 22 / 2 / 7 |
| peekaboo | face up again | `peekaboo` take | 10 / 5 / 8 |
| face down | z < −800 mg for 1 s | do not disturb: Moments refused, `ev gesture facedown` | 43 / 1 / 24 |
| dismiss | hold on needs-you screen | request hidden | 16 / 0 / 111 |
| BOOT tap (handoff) | `gesture.cpp` | opens the next agent on the Mac | 11 / 0 / 5 |

- **Tests:** `internal/firmware/test/test_gesture` 523 lines, 17 tests; gel `test_hand.cpp` 714 lines, 25 tests. Named (broad regex): 31 Swift, 50 firmware, 17 evals.

## 11. Memory

| Part | Files | LOC |
| --- | --- | --- |
| Transcript | `Harness/Transcript.swift` 37, `Memory/TranscriptReader.swift` 127, `Core/TranscriptView.swift` 1,248 (the view Jev reads), `Core/EventLine.swift` 400 | 1,812 |
| Daily counts | `Memory/DailyCounts.swift` 211 | 211 |
| Digests | `Memory/MemoryReader.swift` 322, `Memory/MemoryStore.swift` 250, `Memory/MemoryFiles.swift` 61, `Memory/KeyValueStore.swift` 131 | 764 |
| Written memory | `Memory/WrittenMemory.swift` 204, `Memory/MemoryEdits.swift` 271 | 475 |
| The dream's write | `Prompt/MemoryPipeline.swift` 348, `Prompt/MemoryProposer.swift` 449, `Prompt/MemoryWriter.swift` 120 | 917 |
| Dreams, remembered lines | `Memory/Memory.swift` 606, `Memory/DreamReader.swift` 91, `App/Runtime+Memory.swift` 43 | 740 |
| UI | `app/Boop/Views/MemoryPane.swift` 88 | 88 |

- `app/BoopKit/Memory/` total **2,421** (includes `GrowthStore.swift` 147). Memory proper without the transcript view: about **3,200 lines**; with `TranscriptView` and `EventLine`: about 4,850.
- **Tests:** `MemoryPipelineTests` 674 (32 tests), `MemoryReaderTests` 610 (23), `MemoryTests` 195 (12), `WrittenMemoryTests` 242 (11), `DailyCountsTests` 270 (11) = **1,991 lines, 89 tests**. Evals named: 7.
- Steering: `dreams.md` 18 lines. Plan doc: `plan/memory-writer.md` 187.

## 12. Growth

- **Values:** XP (8 fixed amounts: turn 5, tool 1, helper 2, care 3, talk 3, answer 5, wish 20, back 2); the ring (100 XP a day); levels (1 + XP/100, no cap); **4 stages** (Hatchling 1, Sprout 5, Buddy 15, Chonk 30), 3 with a tag.
- **Defined:** `app/BoopKit/Core/Growth.swift` 79; `Memory/GrowthStore.swift` 147; moments `Core.swift:486-539`; UI `app/Boop/Views/BoopPane.swift` 121.
- **Board:** `firmware/src/app/growth_bar.cpp` 132 + `.h` 69 = 201; gel `paintGrowthBar` (`layers.cpp:806-884`, about 80), `paintSprout` and `paintGrowing` (`props.cpp:265-335`, about 70), stage body sizes in `painter.cpp`.
- **LOC (est.):** about 430 Swift + about 350 firmware. Mention lines (`growth|xp|stage|level|hatchling|sprout|chonk|ring|grew`): BoopKit 301, UI 59, firmware/src 139, gel 239, Swift tests 249, firmware tests 181, gel tests 49. Steering 0, evals 0.
- **Tests:** `GrowthTests.swift` 288 (12 tests). 13 of 52 pastimes need stage 3, 9 need stage 2.

## 13. The world

- **Mac:** `app/BoopKit/World/` **940** (`WorldLink` 495, `WorldWire` 221, `WorldClient` 132, `WorldGestures` 92); `App/Runtime+World.swift` 138; UI `WorldPane.swift` 264, `WorldBand.swift` 180, `Onboarding/OnboardingWorld.swift` 46. **About 1,570 Swift lines.** `world` mention lines in Swift: 357.
- **Server:** `internal/world/src/*.ts` **972** (app 400, world 211, db 144, names 71, auth 57, limits 55, regions 34); migrations 103 lines SQL; scripts 44; README 187. Tests `internal/world/test/*.ts` 980 lines, **54 tests**.
- **Other tests:** `internal/app/Tests/WorldTests.swift` 478 (19 tests); `internal/tools/world_e2e.py` 182. Evals named: `187-a-boop-from-the-world`, `188-cheers-for-your-ship`, `189-a-boop-when-cross`, Pixel `06-a-boop-from-the-world`.
- Values: 4 gesture kinds; 3 regions; at most 3 play an hour; cheers 30 min apart. Steering: 10 `[world …]` lines. Plan: `plan/world.md` 385.

## 14. Tags (`state.when`), special days, variations

- **28 tags in all** (`Tags.all`, `app/BoopKit/Core/Tags.swift:14`); **23 go to the board** (`firmware/src/render/tags.h:15-19`), 5 are Mac-only.
  - Part of day (4): morning, day, evening, night.
  - Weekday (3): friday; Mac-only weekend, friday13.
  - Holidays (7): newyear, valentines, halloween, winter (Dec 24-26); Mac-only piday, aprilfools, may4.
  - Others (3): programmers (day 256), lunar, party.
  - Board's own (2): busy (≥ 2 working), frantic (≥ 4).
  - Tiers (5), stages (3: hatchling, sprout, chonk), hushed (1).
- **Special days: 10 calendar + Boop's own** (`app/BoopKit/Core/Days.swift:26-66, 88-103`): Friday the 13th, New Year's Day, Valentine's, Pi Day, April Fools', May the 4th, Halloween, the winter holidays, Programmers' Day, Lunar New Year; and day 10, one month (30), day 50, every 100th day, each anniversary.
- `Days.swift` 114 + `LocalTime.swift` 163; `DaysTests.swift` 324 (16 tests).
- **Variations:** the board picks. Each of 28 recipe states has 3 takes per profile (4 for two rows, 10 for `gesture`): `slime.h` `kRecipes[44][28][3]`. `variant` mention lines: Swift 12, firmware 55, gel 67, Pixel firmware 101. The Mac may send `variant` but normally sends none.

## 15. Voice

- **Bank:** `characters/boop/design/assets/boop-voice-v1/`: 3,159 audio files; `storage-report.json` says 2,722 distinct recorded takes + **437 placeholder takes** (espeak). 13 performed moods.
- **Table:** `characters/boop/mac/takes.tsv`: **3,479 rows, 2,995 unique take ids, 486 distinct texts**; total play time 3,278 s. `voice/voice.bin` is 31.7 MB.
  - By part: about 2,016, reply 864, feeling 599, attention 0.
  - By kind: word 2,637, sound 520, phrase 304, swear 18.
  - Distinct texts: **215 words, 67 sounds, 202 phrases, 5 swears** (Crap, Damn, Fuck, Shiba, Shit).
  - Meanings: 4 feelings, 16 topics, 17 replies = 37.
- **Word list (215):** Ach, Again, Aha, Aigo, Andiamo, Answer, Assemble, Assist, Attends, Awake, Aww, Back, Backup, Basta, Begin, Behold, Bingo, Boop, Bother, Bravo, Break, Broken, Browse, Busy, Bye, Call, Careful, Cease, Check, Checking, Chill, Chotto, Ciao, Cleared, Clue, Code, Comfy, Compare, Compile, Complete, Connect, Cozy, Dai, Dance!, Debrief, Delivery, Doh, Done, Drat, Dunno, Easy, Enough, Eureka, Evviva, Execute, Failed, Fetch, Finally, Fine, Finish, Finished, Finito, First, Fixed, Focus, Free, Gently, Go, Haha, Halt, Hello, Helpers, Here, Hey, Hey!, Hi, Hiya, Hmm, Hold, Hooray, Hop, Howdy, Hug, Hullo, Hunt, Idea, Incoming, Inspect, Jawohl, Later, Launch, Listen, Load, Lol, Look, Love, Mac, Maybe, Mean, Measure, Mellow, Moment, Nah, Nap, Never, Next, Nice, Night, No, Nope, Oh, Ohh, Okay, Ole, Onward, Oops, Ouch, Pardon?, Party, Passed, Patience, Pause, Peace, Peek, Pending, Piano, Plan, Ponder, Present, Probe, Process, Query, Quiet, Rally, Read, Ready, Reboot, Recheck, Redo, Reply, Report, Reporting, Request, Rerun, Rest, Restart, Retry, Returned, Rewind, Rolling, Rude, Run, Salut, Scan, Scout, Script, Search, See?, Seek, Shell, Shh, Silly, Sketch, Sleepy, Slowly, Sort, Squad, Standby, Start, Steady, Still, Stop, Stopped, Study, Success, Sure, Sweet, Sync, Ta-da, Tadaima, Team, Terminal, Test, Testing, Thanks, Them, There, Think, Tickles, Tool, Trace, Trial, Trouble, Uff, Uh-oh, Um, Validate, Vamos, Verify, Victory, Voila, Wait, Waiting, What?, Whoa, Wiggle, Woo, Woohoo, Work, Yatta, Yay, Yep, Yes, Yo, Yup.
- **LOC:** Swift `app/BoopKit/Voice/` 165 (Voice 84, Take 81); firmware `firmware/src/voice/` 525 + `app/sound.*` 204 + `board/audio*`, `card.*` 311; tool `characters/boop/tools/voicegen/*.py` 602. Tests: `VoiceTests.swift` 255 (12), `test_voice` 250 (9), `test_effects` 603 (14).
- Pixel keeps an older copy: 3,586 rows, with 164 `attention` takes that nothing plays.

## 16. Wire messages and `do` designs

- **Message types: 4** (+ `dbg.*`): `hello`, `state`, `do`, `ev` (`linkkit/SPEC.md` §3). Max 512 bytes.
- **`state` keys: 20:** base, act, mood, attn{agent, project, name, more, id}, busy, idle, helpers, vol, when, xp, todo{done,total}, buddy, wish, wish_how, calls, wact, list, skip, unlisted (`StateSnapshot.swift:293-332`).
- **`do` names: 11** (`firmware/src/app/device.cpp:55-71`): `react`, `task_complete`, `reply_ready`, `starting`, `wake_up`, `listening`, `stop_listening`, `notice`, `call`, `wish_met`, `wish_gone`.
- **`do` args: 17:** outcome (2), turn (0-5), variant, ctx (4), sign, reason, ask{q,a,b,touch}, reply, show (`drawer`), greeting, low, clip, who{agent,thread}, say{take,then}, mood (42), loops (1-6); `call` adds `as` (16 styles) and `word` (`Moment.swift:154-175`).
- **What the Mac can ask the board to play, counted as named designs:** 11 dos × args. Named things: 42 faces, 19 reply clips (`reply-bye, comfort, dance, dunno, hehe, hello, huh, hush, love, nap, no, notme, ouch, remember, status, thanks, unhush, wave, yes`), 16 call styles, 3 work acts (via `state.wact`), 4 start contexts, 2 outcomes, 2,995 takes. **About 100 named designs, not counting takes** (est.).
- **`ev` kinds: 7:** `tap`, `gesture`, `drawer` (open, closed, pick), `ask`, `talk_on`, `talk_off`, and the kit's `ended` (`app/BoopKit/App/Runtime+Device.swift:57-105`). `dbg.*` types: 15.
- **LOC:** `linkkit/` 7,565 (Swift sources 2,433, device C++ 2,867, tests 1,339 Swift + 1,172 C++, docs 811); `app/BoopKit/DeviceLink/` 427.

## 17. Totals

| Area | LOC | Notes |
| --- | --- | --- |
| `app/Boop` (menu-bar app) | 7,398 | Onboarding 2,123; `MenuBarApp` 1,107; `OverviewPane` 832; `Theme` 615 |
| `app/BoopKit` | 19,593 | below |
| · Core | 6,062 | `Core.swift` 1,306; `TranscriptView` 1,248 |
| · App | 3,528 | `Runtime*.swift` 2,107 |
| · Memory | 2,421 | |
| · Outputs | 1,957 | `MomentOutput` 1,079 |
| · Prompt | 1,678 | |
| · Demo | 1,089 | |
| · World | 940 | |
| · Harness | 621 | |
| · DeviceLink | 427 | |
| · Character | 314 | |
| · Voice 165, Presence 133, Buddies 127, Adapters 89, Brains 42 | 556 | |
| `firmware/src` | 10,354 | app 4,646; render 3,188; board 1,828; voice 525; main 167 |
| `linkkit` | 7,565 | Swift 3,800; C++ 2,867; docs 811 |
| Gel renderer, hand-written (`render/gel`) | 12,651 | 9,854 `.cpp` + 2,797 `.h` |
| Gel generated headers (`firmware/include`) | 26,622 | `slime.h` 11,729 (10,000 are sound samples), `slime_art.h` 11,428, `fonts_gel.h` 1,857, `slime_mesh.h` 1,608 |
| Steering, boop | 518 | personality 117, replies 68, signs 59, guide 29, asks 22, dreams 18, mood 205 |
| Steering, pixel | 190 | |
| `internal/` (all) | 54,292 | |
| · Swift tests `internal/app/Tests` | 19,176 | 53 files, **731 `func test`** (764 lines are the generated runner) |
| · other `internal/app` Swift | 4,111 | Eval 1,505; Snapshots 1,201; `boopdev` main 563 |
| · firmware tests `internal/firmware/test` | 10,640 C++ | **289 tests** in 9 suites; 22 goldens dirs; 23 scenarios (1,121 lines) |
| · `internal/tools` | 12,520 | Python 11,265 (`boopctl_lib` about 8,500 incl. 2,952 of its tests; `session` 1,648; `mediagen` 392) |
| · `internal/world` | 3,013 | src 972, tests 980, package-lock 713 |
| Gel pack tests | 23,278 | `test_gel` 8,376 lines, **161 tests**; 28 scenarios (14,690 jsonl lines); 573 PNG + 154 txt goldens |
| Evals | 148 scenarios | boop 142 (131 for Jev, 11 scripted, 10 `always`; 752 steps; 2,666 lines); pixel 6. Levels: quick 20 scenarios / about 87 requests; standard 131 / about 746; full 131 / about 846 |
| Demos | 26 scripts | boop 15 (321 lines, 14 recordings, 2,961 lines); pixel 11 (195 lines); `app/BoopKit/Demo` 1,089; `internal/sessions` 5 projects |
| `simulator/` | 5,119 | about 4,290 hand-written (dist copies and wasm excluded); Python 1,744; JS 1,364; C++ 831 |
| `characters/studio/` | 122,306 by `wc -l *` | **`packs.js` 117,736 lines, generated and git-ignored.** Hand-written: JS 2,338 (`studio.js` 492, `character.js` 623, `views.js` 378, `check.cjs` 277, `board.js` 263, `behavior.js` 226, `markdown.js` 79) + `index.html` 184 + `studio.css` 487 = **3,009**; plus `behavior.json` 206, `states.json` 52, tests 233, README 387, `everyday.jsonl` 913 (data). **The claim holds: about 118,000 generated, about 3,000 hand-written.** |
| `characters/charactergen.py` | 1,397 | tests `internal/characters/*.py` 735 |
| Packages | 14,155 | `agent-hooks` 9,042; `mellowharness` 5,113 (sources 8,080 Swift, tests 5,851 across both) |
| Docs | about 7,000 | `CHARACTER.md` 1,088; `plan/` 2,580; `CLAUDE.md` 346 (Words table: **95 defined words**) |

Eval command: `.build/debug/boopdev eval --list --level full` (free; output kept at `/tmp/boop-review/eval-list-full.txt`).
Other tests: Python `def test_` 240 (4,564 lines); world server 54; JS (simulator 17, studio 6, mirror 11).

Rough hand-written product code (app + firmware + linkkit + gel renderer): **about 57,600 lines.** Tests and tools around it: about 66,000 lines.

## 18. Cost of the second character (Pixel) and the second board (CYD)

- **PixelBuddy pack, hand-written (est. 6,600):** renderer `characters/pixel/firmware/src/render/pixel/` 2,183 (+ `make_face.cpp` 8); tools 3,129 (facegen, sfxgen; 1,173 of it JSON); steering 190; test code 754; demo scripts 195; evals 58 (6 scenarios); rig 66; studio 61.
- **PixelBuddy pack, generated:** `faces.h` 22,991 + `sfx.h` 8,189 = 31,180; test golden header 11,836; recordings 1,975; `mac/faces.json`; a 31 MB voice copy.
- **Engine code only for the CYD or the pixel face (est. 1,900-2,000):**
  - `firmware/src/board/cyd24/` 374 (config, display, touch, hal, audio).
  - The 8-bit canvas path: `render/canvas.*` 201, `render/push.*` 158; `app/touch_cal.h` 86; `render/pattern.*` 72.
  - `firmware/platformio.ini` `[env:cyd24]` about 25 lines (amoled206 extends it).
  - Mac: `app/Boop/Views/BoopFace.swift` 284 + `FaceDesigns.swift` 40 = 324 (the popover's pixel face; the gel uses the mirror).
  - Tools and tests: `boopctl_lib/calibrate.py` 105; `test_canvas` 150; `test_push` 461.
- **Preprocessor branches:** only 9 `#if` lines in all firmware; 2 pick the board (`firmware/src/board/config.h:6-8`). Boards and faces are split by folder and by `make_face.cpp`, not by `#if`.
- **Machinery that exists because there is more than one pack (partly needed with one):** `charactergen.py` 1,397; `internal/tools/packs.py` 103; `new_character.py` 73; `PackCheck.swift` 123; `CharacterPack.swift` 298; `CHARACTER.md` 1,088; `new-character-playbook.md` 87; pack tests 735; the Studio's pack switching. Mentions of pixel/cyd: 25 lines in app Swift, 21 in `CharacterPackTests`, 50 in `CHARACTER.md`.
- **Summary (est.):** about 8,500 hand-written lines exist only for Pixel or the CYD (6,600 in its own repo, 1,900 in the engine), plus about 45,000 generated lines. Shared pack machinery adds about 3,900 lines whose size, not existence, depends on a second pack.

## 19. Several buddies

- **Own files:** `app/BoopKit/Buddies/Buddy.swift` 127 (Buddy, `header`, `BuddyBinding`); `app/BoopKit/App/Runtime+Buddies.swift` 310 (about 130 is the rig list and speakers; the rest wires one buddy's brain) ; `--buddies` and `--links` parsing in `app/Boop/main.swift` (about 40 lines).
- **Spread:** 415 Swift lines name `buddies`, `rig(s)`, `Rig` or `buddy:` in 25+ files. Top: `Runtime.swift` 80, `Pipeline.swift` 59, `Runtime+Device.swift` 49, `Runtime+Dev.swift` 28, `Runtime+Buddies.swift` 24, `DemoScript.swift` 18, `TranscriptView.swift` 16, `Runtime+Talk.swift` 16.
  Command: `grep -r -E '\bbuddies\b|Buddies|\brigs?\b|\bRig\b|buddy: |for rig in' app --include='*.swift' | wc -l`.
- Also: the `reacted` event kind, `Event.buddy` tags, `state.buddy`, MellowHarness "voices" (in `mellowharness/Sources/MellowHarness/Harness.swift`), per-buddy cores in `Pipeline`.
- **Tests:** `BuddiesTests.swift` 178 (6 tests). **Demos:** 1 script names buddies (`not-my-turn.jsonl`). **Evals:** 0. No Settings UI.
- **Estimate:** about 500-600 Swift lines exist only for more than one buddy, in about 25 files, plus about 180 test lines and the harness's voices. The earlier audit said about 600 lines in about 28 files; today's count agrees.

---

## The earlier audit (`plan-simplify:plan/simplify-behavior.md`, 571 lines, 2026-11-01)

1. It audited `main` at 085a7579 with five read-only reviews, and replaced a plan of 2026-10-25 of which one item was built.
2. **Concept count:** 79 then; about 92 once dreaming landed; about 30 if every merge were taken. It listed 25 merged concepts (Agent, Turn, Needs you, You, Transcript, Check-in, Look, Tag, Tier, Dressing, Reaction, Work stream, Mood, Move, Size, Say, Sign, Reason, Talk, Personality, Growth, Memory, Prompt, Drawer, Pack).
3. **A (safe, invisible), 16 items, all agreed:** personality as a choice (about 120 lines), `tool_uses: all` (40), `eval --to-demo` (160), the 212 unused `attention` takes, `uses`/`shares` (120), two pack checkers, the dead `error` do, default env to amoled206, one loop cap, 9 tags no board reads, `hello.face`, the 76.8 KB canvas, `fluid`, evals that spend Jev on code rules.
4. **B1 Several buddies:** about 600 lines in about 28 files, six concepts, one demo. Recommended remove. **Owner: keep.**
5. **B2 Retire the CYD:** about 600 lines, two concepts. **Owner: not yet.**
6. **B3 Real-agent demo venues:** about 2,100 lines. **Owner: keep.**
7. **B4 `boopctl workday`:** about 1,400 lines. **Owner: remove** (gone today: 0 hits in `cli.py`).
8. B5 one simulator path (yes), B6 onboarding 8 acts to 6 (no), B7 mirror upkeep (keep), B8 drawer scrolling, about 170 lines (keep), B9 bubble beside sign (keep both), B10 one Studio server (yes).
9. **C1 One mood graph:** it was written four times; the board's copy lacked 46 edges. Decided: one graph in `character.json`. Built: today 119 edges, and the board's `kEdges` is generated with the same 119.
10. **C3:** 16 lasting moods, 42 faces; 26 mood files go. Built: 16 mood files today.
11. **C4 Fades in code and no hourly heartbeat: owner said no.** Today fades are still prose and the hourly check-in exists.
12. **C5** drop the `stopped` and `helper_return` rule cards (yes). **C6** compute the move in code (no: Jev still picks it). **C7** the poke hold (no).
13. **C8 One pastime dealer + C9 the gel Router as a struct (yes).** Built: one table of 52 rows today; `router.cpp` is 93 lines.
14. **D:** renames for talk, move, hold, busy, gag, moment, wiggle (yes).
15. **E3a** hush becomes a Talk level (built: `Talk.swift`, `Core+Hush.swift`). **E3b** the calendar moves to CONTEXT (built: `ContextSection`).
16. It kept: 42 faces, the graph, the face-down hold, two session trackers, LinkKit's queue, the kit and outfits, finish sizes by tier, the Studio, boopctl and boopdev.
17. Its own numbers for size were few: line counts per removal (40 to 2,100) and the concept count. It gave no totals per area.

**Then against now:**

| | 2026-11-01 audit | Today |
| --- | --- | --- |
| Concepts | 79 (92 after dreaming); target about 30 | 95 words in CLAUDE.md's Words table |
| Lasting moods / faces | 42 / 42, proposed 16 / 42 | 16 / 42 |
| Mood graph | 4 copies, 46 edges missing on the board | 1 source, 119 edges (79 + 40) |
| Tags to the board | 9 unread ones sent | 23 sent, 5 Mac-only |
| Several buddies | about 600 lines, 28 files | about 500-600 lines, about 25 files; still 1 demo, 0 evals |
| CYD-only engine code | about 600 lines | about 900 firmware lines (cyd24 374, canvas and push 359, touch_cal 86, pattern 72) + 324 Mac + tools and tests |
| Evals | pruned by about 10 files | 148 scenarios (11 scripted) |
| New since the audit | — | growth ring and levels, wishes, notices, the world (about 1,570 Swift + 972 server lines), work acts (1,201 gel lines), memory written by code (917 lines), remembered lines, lean and tilt |

The audit's merges of vocabulary were mostly not taken as merges: the concept count went up (79 → 95), while the removals in A and C were largely built.
