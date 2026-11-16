# The cut list

Updated: 2026-11-15. An audit, nothing built. Read at engine `763ce92f`,
SlimeBuddy `b527599`.

The owner asked for an 80/20 cut: what can go, or get simpler, without
hurting what a person sees, so changes get fast again. Four reviews fed this:
the moods and faces (with the owner's own transcripts), the gel's screen, the
Mac's concepts, and the weight every change drags along.

**Read this first.** `plan/product-review.md` §8.3 (2026-11-09) already
designed a simpler model, and `plan/TODO.md` "Decided" accepted most of it.
Phase 2 there is still unbuilt. This list does not redo it. It adds:

1. The screen cuts. The review said to keep pastimes, kit and dressing. The
   owner now finds the working screen cluttered, so this list cuts there.
2. A build order that starts with the test weight, because that weight is
   why the decided cuts have not been built.
3. Numbers from the owner's own desk for the moods and faces.

Marks: **D** = already decided in `plan/TODO.md`, not built. **N** = new
here. **O** = needs the owner's call.

## 1. The size of it

| | Today | After this list |
| --- | --- | --- |
| Lasting moods | 16 | 7 |
| Faces (emotions) | 42 | 18 |
| Activities | 8, told apart by a 30-pixel glyph | 4, told apart by the body |
| Tiers | 5 | 3 |
| Work acts | 3 full scenes (1,200 lines, 59 pictures) | 0 scenes; the low sign stays |
| Pastimes | 48 | about 15 |
| Things beside the face at work | up to 12 kinds | words, desk, paws, one low sign |
| Finishes | 7 | 3 |
| Jev's questions a pass | 5 or 6 | 3 or 4 |
| Kinds of event that wake Jev | 17 | about 7 |
| Gel pictures pinned pixel for pixel | 579 | about 200 |
| Prompt goldens | 154 files, 97,000 lines | about 10 files |
| Eval scenarios | 142 | about 40 |

## 2. Moods and faces

### What the owner's desk shows

268 Jev passes from the transcripts in `~/Library/Application Support/Boop*`
(7 day files, October and November; counted by value only, no words read).

- **Mood picked:** happy 76, calm 35, excited 34, sad 31, annoyed 25,
  engaged 20, curious 18, determined 8, proud 7, irritated 7, surprised 5,
  wounded 1, grumpy 1. **Never: comfy, lazy, lonely.**
- **Face picked:** curious 86, none 43, pleased 19, determined 14,
  affectionate 13, annoyed 11, comfy 10, excited 9, sad 9, amused 8, proud 7,
  hopeful 7, then 13 faces at 5 or fewer.
- **18 of 42 faces were never picked:** angry, baffled, crying, disappointed,
  disgusted, embarrassed, exhausted, frightened, lonely, overwhelmed, scared,
  shy, skeptical, speechless, stunned, tired, uncomfortable, whiny.
- Six faces are 70% of all faces shown. One face, curious, is 38%.
- Size: medium 169, small 86, big 12, huge 1.

Amused is a face, not a mood: 8 picks in 268.

### What the panel shows

A contact sheet of the 42 face pictures (`tests/golden-gel/moods`) shows
groups that read as one face at arm's length:

- calm, curious, surprised, confused
- annoyed, bored, irritated, skeptical, speechless
- sad, disappointed, tired, exhausted
- engaged, hopeful, embarrassed
- pleased, proud, relieved, affectionate
- crying, frightened, wounded
- stunned, uncomfortable, scared
- shy, disgusted, angry (all three use the `> <` eyes)

So the most-shown face, curious, looks like calm. **N:** when the set is 18,
give curious a face of its own. That one drawing does more than the 24 that go.

### The cut

| # | Cut | Mark | Frees |
| --- | --- | --- | --- |
| 2.1 | 16 moods to 7: calm (takes comfy, lazy), happy (excited), focused (engaged, determined, curious), proud, cross (annoyed, irritated, grumpy, with a level 1 to 3 that code counts), sad (wounded), lonely. Surprised is a face only | D | 9 mood files, 125 steering lines |
| 2.2 | 42 faces to 18, by an alias table first: the old names stay in `character.json` and map to a kept face. Delete after a week | D | 24 faces' art, 72 performances, 24 pictures |
| 2.3 | No mood graph. Any mood may follow any; a fade is one number per mood, run by code | D | `emotion-graph.json` (1,225 lines), `MoodGraph.swift`, `test_bridges.cpp` (606), the hourly check-in |
| 2.4 | The 18: the review's list has skeptical, angry, tired, scared, relieved (0 or 1 pick each here) and leaves out pleased (19) and comfy (10). Swap by the desk's numbers: keep pleased; fold relieved into it; fold skeptical into annoyed | N, O | nothing more; a better 18 |
| 2.5 | The per-mood pairs of big finishes (`bigFinishes`) go with 6.1 | N | |
| 2.6 | One source for the mood docs: `MOODS.md` (730 lines) and CHARACTER.md §5 point at `character.json` | N | about 800 doc lines; a mood change touches 2 design files, not 7 |

**Keep:** the cross ladder as three faces; determined with "retry" when the
owner sounds frustrated; a strong feeling flipping the mood at once.

## 3. The working screen

What can be on the working screen at once today: body and face; desk,
monitor with a glyph, a turn clock and a to-do bar; keyboard and paws;
headphones; a hat or shades; up to 8 falling words; a word forward with its
effect; a thought cloud; a pastime's props; the wish bubble; the growth bar;
leaves; a sign; the START card; the strip; a low sign; a bubble and a caption.

Three facts from the code:

- **The thinking bubble is 12 lines** (`stream.cpp:227-238`). It shows after
  20 s with no new call. The monitor already shows `. . .` at the same 20 s.
- **An activity changes almost nothing.** The 8 differ by a glyph on a 78 by
  36 pixel monitor (`props.cpp:172-208`). No pose, no prop.
- **"Building" is a work act, a full scene.** The desk goes, a hard hat
  drops on, a house goes up over 75 s. Tests has a sled and a wall; push has a
  rocket. They are `act.cpp`, 1,133 lines, and they hide the work stream
  while they play.

| # | Cut | Mark | Frees | Notes |
| --- | --- | --- | --- | --- |
| 3.1 | The thought cloud at 20 s quiet | N | 12 lines, 1 picture | Nothing else reads it |
| 3.2 | The headphones (the whole kit) | N | about 150 lines, clip `phones-on`, 5 or more pictures | `bop`'s notes go too (3.5) |
| 3.3 | The three full work acts: house, sled, rocket. Keep the low sign (`running tests`, then `pass` or `fail`) and Jev's word at the end | N | about 1,000 lines of `act.cpp`, about 55 pictures, most of `acts.jsonl` (4,974 lines), clips `act-on`, `act-off`, 9 scene sentences in `character.json`, 6 guide lines | The Mac's `act` event stays: the world's ship cheer and the daily counts read it. The small hats (hard hat, helmet) go too, replaced by 3.4 |
| 3.4 | Activities 8 to 4, shown by the body: typing (edit, tool), looking (read, grep, web), running (terminal, tests, build, push), waiting. One pose, gaze and paw rhythm each. No props | D, and N for "no props" | 4 glyphs, 4 pictures; adds 4 small clips | This is the "building is not grepping" the owner wants, done calmly. Running a build: paws off the keys, eyes on the monitor, a small lean in; the low sign says which |
| 3.5 | At-work pastime drawings: peek's heart, hum's notes, ponder's cloud and bulb, nod's ticks, bop's notes, drum's `tk`, the sticky note, the snack. Keep three body-only moves: stretch, melt, the done beat | N | about 210 lines, 9 clips, 14 pictures | The owner liked whole-body moves; these are the props around them |
| 3.6 | The turn clock and the to-do bar on the monitor | N | 30 lines, 1 picture, 1 test | The strip already shows `3/7` |
| 3.7 | Word effects: keep falling, land, the bonk ladder, gather, drop. Cut compact, buried, freeze, shatter's burp, shrug's bubble, the monitor's crack and edit bars | N | about 150 lines, 8 pictures | Unknown styles already fall back to `land`, so the Mac may change later |
| 3.8 | Needs-you pastimes (wave hand, tap rings, pocket watch, drowsy) | N | 63 lines, 4 clips | The amber screen is the message |
| 3.9 | The START card at each turn (`NEW TASK`, `COMPACTED`) | N, O | about 45 lines on the Mac, the card keeping in `props.cpp`, 3 pictures | The first falling word says the same |
| 3.10 | Tiers 5 to 3 | D | 2 clips, tier rules | Finish sizes then map one to one |
| 3.11 | Pace (`busy`, `frantic`) | N, O | about 10 lines, 2 takes, 1 picture | Small. Cut only if it reads as jitter |

After 3.1 to 3.9 the working screen is: Boop, the desk, the falling words,
the strip, and one low sign when a command is worth naming.

## 4. The rest of the screen

| # | Cut | Mark | Frees | Notes |
| --- | --- | --- | --- | --- |
| 4.1 | Finishes 7 to 3: Little Win, Confetti, one big (Gold Rush). Cut Fireworks, Parade, Spotlight, Mega Boop | N, O | 300 to 500 lines of `finish.cpp`, 12 to 20 pictures | Size 4 to 3 (D): huge was 1 pick in 268 |
| 4.2 | Idle pastimes 23 to about 8. Cut the ones with the most props: snuggle blanket (100 lines), plane (49), dance (26), book (26), game (25), doodle (24), tower (21), brb card, bubble | N | about 300 lines, 9 clips | The `dance` and `nap` replies use dance and snuggle: they go in 5.9 |
| 4.3 | Holiday hats and shades: witch, party, bobble, Friday shades. Keep the nightcap | N, O | about 75 lines, the outfit keeping (about 185), 13 pictures, `Narration.Dressing` | Each shows 1 to 3 days a year |
| 4.4 | The 7 tagged idle bits (morning stretch, Friday sway, Halloween wobble...) and the 5 Mac-only tags | D for the tags, N for the bits | 7 takes, 12 tags | |
| 4.5 | Touches 14 to 7: poke, stroke, hold, shake, pick-up, swipe, face down | D | 7 detectors' tests and takes | |
| 4.6 | The ponder and dream clouds, the empty shrug bubble | N | 50 lines | With 3.1, bubbles go from 6 kinds to 2: speech and wish |
| 4.7 | Dead: `render::airFor` and `enum Air`; the rig's empty scene and air layers | N | about 20 lines | No caller |

**Keep:** the drawer, the needs-you screen, the strip, the speech bubble and
caption, the rim glow and the finished thread's name, the growth bar, the
finger answers (drag, lean, tilt).

## 5. The Mac's mind

| # | Cut or merge | Mark | Frees | Risk |
| --- | --- | --- | --- | --- |
| 5.1 | Code picks the move and the size | D | 2 of Jev's questions on every pass; about 270 lines with tests | Low |
| 5.2 | No pass at a turn's start with no prompt | D | 146 of 146 chose nothing | None |
| 5.3 | Lock and unlock by rule: wave by time away, a snub when cross, a nap at night | N | 5 to 20 requests a day; 7 scenarios become free tests; 10 steering lines | Low: the steering is already a table |
| 5.4 | The working check-in by rule | N | up to 10 requests an agent-hour | Low to medium |
| 5.5 | The hourly check-in goes once fades are numbers (2.3) | D | up to 24 requests a day | Low |
| 5.6 | One idle beat. Musing, ask, wish, notice and remembered line all fire at an idle check-in through one question, then branch five ways with five sets of caps. Code picks the one that is due, with one cap | N | about 650 lines with tests, 8 scenarios, 12 personality lines, 3 CONTEXT rows | Medium: Jev no longer times the wish |
| 5.7 | One hello and one bye. Wave, greeting, the day's greeting, the telling, the special-day greeting and nap are seven names for "you came or went". Code picks the size and the one extra | N | about 320 lines with tests; the second special-day path (`greetDay`) | Low: the same moments play |
| 5.8 | Quiet: Talk is quiet or normal; hush sets quiet with a timer. Drop chatty, the four hush lengths, the `unhush` reply | D for chatty, N for the merge | about 280 lines with `HushTests`, 2 events, 1 tag | Low |
| 5.9 | Replies 15 to about 10: thanks with love, no with notme; drop dance and the spoken nap. `say` 22 to 12 | D for `say`, N for replies | 5 clips, about 250 tokens a talk pass | Low |
| 5.10 | One ladder counter for pokes, shakes, wins and failures (four counters, four line texts today) | N | about 160 lines, 5 how-to-read lines | Low |
| 5.11 | Boops from the world and the work act's word by rule | N | 7 scenarios become free tests | Low to medium |
| 5.12 | Ring and level as one moment and one event; stage names out of the UI | D | 2 events | Low |
| 5.13 | Small: the compacted-context line, the makeup tag, April Fools, the unused ask flags (`touch`, `daily`, `lonely`), the "Falling words" setting, the leftovers of several buddies, 12 golden states no eval reads | N | about 200 lines, 12 files | None |
| 5.14 | Written memory, the dream's write, the Memory pane, the remembered line. Keep the dream's sentence, the digest, the daily counts | O | about 3,000 lines with tests, 300 tokens on every pass | Medium. It is frozen already, and the remembered line never fires without Apple Intelligence |
| 5.15 | Asks: the pack has 2 questions, each asked once ever. Write the 20 the plan wants, or cut the machine | O | about 530 lines with tests, `do.ask`, the board's two tap targets | Low today |
| 5.16 | Wish down to one kind: no `how` sign, no away clock, no "an hour makes it lonely" | O | about 400 lines with tests | Medium to high: it is the pet side's one mechanic |
| 5.17 | Notices: keep `waiting` and the while-away fact; cut stretch, rough, late, the ritual, the goodnight count | O | about 400 lines with tests, 6 scenarios | Low to medium |
| 5.18 | Jev at every touch: wake only at the first of a run | O | many requests | Medium |

After 5.1 to 5.5 and 5.11, Jev is asked about your prompt, a finish, your
words, a failed check on the ladder, a touch and a coming back. That is
where it earns its place.

## 6. What every change drags along

This is why the decided cuts are unbuilt. Removing one mood today touches
about 40 files by hand, re-records 153 goldens, regenerates 4 artefacts and
lands in 3 repositories.

| # | Cut | Mark | Frees | Risk |
| --- | --- | --- | --- | --- |
| 6.1 | Prompt goldens (`tests/golden-states`): keep about 10 | N, O | 144 files, about 90,000 lines. A mood or prompt word stops rewriting 153 files | Medium: a prompt regression shows only in a Jev eval |
| 6.2 | Gel pictures by stage: `growth` replays 32 scenes for each of 4 stages (130 pictures); the growth bar has 79. Keep one full stage and 3 scenes for each other | N | about 150 pictures | Low |
| 6.3 | Evals 142 to about 40: the 20 musts, the 11 scripted, about 10 feel | O | about 100 files; a standard run falls from about 746 requests to about 250 | Medium |
| 6.4 | Stop CI failing on demo recordings; record on demand | N | 25 files stop churning | Low: a demo can go stale |
| 6.5 | Stop checking in the mirror (`board.js`, 3.4 MB); build it in `make dev` and `make bundle` | N, O | No Emscripten rebuild on each gel change | Medium: CI's mirror test needs another source |
| 6.6 | The CYD and Pixel out of the engine | D | about 1,100 firmware lines, 2,500 of tests, 124 pictures, one repository per landing | Medium to high. First port `test_behaviour` and `test_device` (198 tests) to the gel or a stub face. `env:amoled206` extends `env:cyd24`. `new-character` copies Pixel |
| 6.7 | Docs: make targets described once (5 places today); `plan/TODOs.md` into `TODO.md`; the built reviews out of `plan/` (about 2,800 lines); CLAUDE.md's Words table follows the cuts, about 95 words to 55 | N | | Low |
| 6.8 | Tools nothing runs: `boopctl calibrate` (CYD only), `factory`, `appicon`; `boopctl day` beside `Boop --counts`; `beacon` and `mellowharness-emit` built on every `make build` | N, O | 0.3 to 1.2 thousand lines | Low |
| 6.9 | 82 local branches (74 unmerged by squash), 11 worktrees, 8.3 GB | N | The owner deletes, after a check of each | Low |

Also found: `make -C internal check` has no stated time; `sim` and most of
`tools-test` never run in CI; the eval limit in code is 2,500 a day.

## 7. The order

1. **Lighten the tests first** (6.1, 6.2, 6.4, then 5.13). No one sees a
   difference, and every later step costs a tenth of what it does today.
2. **The working screen** (3.1 to 3.9). It is what the owner sees all day,
   and it is one pack commit plus a small engine one.
3. **The alias table** (2.1, 2.2, 2.4): 7 moods and 18 faces with nothing
   deleted. A week on the desk.
4. **Jev's load** (5.1 to 5.5, 5.11).
5. **Delete** what the alias week did not miss (2.3), then the merges (5.6
   to 5.10), then the rest of the screen (section 4).
6. **The owner's calls** (5.14 to 5.18, 6.3, 6.5), and the CYD and Pixel (6.6).

Each screen step needs the mirror rebuilt, the pack's `CONTINUITY.md`,
`VALIDATION.md` and `mac/passing.tsv`, and the usual landing order: the
pack, then here, then the pack's pin.

## 8. Not on the list

Kept by the owner before, and nothing here argues with it: onboarding, the
drawer, the speech bubble beside the sign, real-agent demos, the world, the
needs-you rules, the bonk ladder, swearing as a switch.
