# Boop: how often each mood, emotion, pastime, voice take, sign and Moment happens

Written 2026-11-09 for the simplification audit. Research only: no file in the repo was changed and no Jev request was sent (`~/.boopdev/jev-requests.json` still reads `{"used":762,"day":"2026-11-08"}`; `boopdev eval --list` says "today: 0 of 2500 used").
Worktree: `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish` (commit 270ee70c). Pack: `characters/boop` (a link to `characters/.repos/SlimeBuddy/character`).

## 0. The short answer

1. **Moods.** Calm holds 44% of all passes. Five moods (calm, happy, annoyed, sad, grumpy) hold 77%. Lazy is dead: Jev chose it 0 times in the latest run, its highest probability at any of 427 offers was 0.09, and all 16 passes in lazy come from one older run. Surprised (0.4%), comfy (0.6%), wounded (0.8%), lonely (1.4%) and curious (1.4%) are each under 2%.
2. **Emotions (faces).** The pack has 42. Jev never chose 13 of them in 9 runs (5,138 Moments): shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, stunned, embarrassed, exhausted, overwhelmed, disgusted. In the current build 3 more are gone (bored, tired, speechless). 7 more are under 0.5% each. Five faces (determined, proud, calm, happy, annoyed) are 50% of all Moments, and ten are 75%.
3. **Each slot has one face.** Current build: a long finish is proud 89% of the time; a working check-in is determined 69%; a prompt is calm 60%; a lock is calm 85%; a failed check is annoyed 57%; a turn start gets no Moment 100% of the time (146 of 146 passes, each a paid Jev request).
4. **Moment size.** Small 44%, medium 45%, big 7%, huge 4%. Size is set by the slot, not chosen freely: every working check-in is medium, every very long finish is big or huge.
5. **Voice.** The pack has 3,479 takes and 486 distinct texts. The 9 runs used 220 texts (45%). Only 34 of 202 phrases (17%) were heard, because phrases need a big or huge Moment (11% of Moments). Jev never chose 8 of the 21 `say` kinds in the latest run: waiting, looking, command, helper back, stopped, helpers, tool, planning. The takes of 5 of them (76 texts) were never heard in any run.
6. **Signs.** 72 of the 146 written lines were never held up: 35 of 58 in `signs.md`, 19 of 67 in `replies.md`, 18 of 21 in `asks.md`. Only 2 wish wordings ever show ("hold BOOT, say hi?", "stroke my face?"), and the three `[wish pet]`, three `[wish chat]` and all `[wish work]` lines never show. The two asks ("fav snack?", "hat or bow?") never showed in a Jev run.
7. **Moment kinds (moves).** 59% of Moments have no move. Success is 18%, failure 5%. Of the reply moves, dance (4 uses, 0.1%), unhush, no, hush and nap are the rarest. `notice` played 9 times.
8. **Pastimes.** The table has 52 rows. The board deals one about every 11 seconds, so about 2,000 a day by my estimate. A new buyer (Hatchling, stage 1) knows 28 rows and sees 17 on an ordinary day. 15 rows wait for stage 3 (level 15, 14 days at the earliest, because XP is capped at 100 a day and a level is 100 XP). 8 rows need a calendar tag, and while its tag is on, a tag row takes about 42% of all idle pastimes (all morning, all Friday).
9. **Mood moves.** 2,340 moves in 6,363 passes: the mood moves at 37% of passes. On the simulated workday (scenario 173) that is 23 to 27 moves in 8.7 hours, about 3 an hour. 48 of the graph's 119 edges were never taken.
10. **Interchangeable.** The data points at these merges: happy/pleased; bored/tired/comfy (idle); annoyed/irritated; determined/hopeful/engaged (working); calm/"no Moment" (prompts); wounded/speechless/confused (your words); excited/happy and calm/engaged as moods. Details in section 9.

Every count below is from scenario runs, not from a buyer's desk. The scenarios choose which events happen, so the shares say "what Jev picks when this event happens", not "what a buyer sees per day". Section 10 gives the limits of each source.

## 1. Sources and commands

| # | Source | Path | What it is |
|---|---|---|---|
| 1 | `boopdev eval --list` | `/tmp/boop-review/evals/list.txt`, `list-standard.txt` | Every scenario and its cost. 142 scenarios: 20 must, 111 feel, 11 scripted |
| 1 | `boopdev eval --scripted --timeline` | `/tmp/boop-review/evals/scripted-timeline.txt`, `scripted-run.jsonl` (792 passes, 142/142 pass) | The expect brain, not Jev |
| 2 | Real Jev trajectories, 9 standard runs | `~/.boopdev/night-2026-11-01/traj-{A,B,C}.jsonl` (2026-11-02), `~/.boopdev/day2/traj-{d2a,d2b}.jsonl` (11-03), `~/.boopdev/tonight/traj-{t0,t1,t2}.jsonl` (11-04, 11-05), `/tmp/boop-eval/20261108-220953-81575.trajectories.jsonl` (11-08) | 1,084 scenario runs, 6,363 passes, all `jev:jev-latest` |
| 2 | Jev's raw answers with probabilities | `/tmp/boop-eval/20261108-220953-81575.jsonl` (748 passes) | The only run file with every option's probability. Files in `/tmp/boop-eval` over a day old are cleared, so this one will go |
| 2 | Judge verdicts | `~/.boopdev/*/verdicts-*.jsonl` (806 verdicts, 9 whole-run summaries) | 628 reasonable, 121 odd, 57 unreasonable |
| 3 | Demo recordings | `characters/boop/demo/recordings/*.json` (14, 624 s), `characters/pixel/demo/recordings/*.json` (11, 432 s) | What the app sent the board, from hand-written brain steps |
| 4 | Scenario files | `characters/boop/evals/*.json` (142) | Musts, briefs, scripted answers |
| 5 | Pack definitions | `characters/boop/character.json` (42 moods, 16 lasting, the graph), `characters/boop/mac/takes.tsv`, `characters/boop/steering/{signs,replies,asks}.md`, `characters/boop/firmware/src/render/gel/pastimes.{h,cpp}`, `face.cpp` (the dealer), `app/BoopKit/Core/{Tags,Days,Growth}.swift` | |
| 6 | Plans | `plan/TODO.md`, `plan/v1-buddy.md`, `~/.boopdev/day2/notes.md`, `~/.boopdev/night-2026-11-01/report-notes.md` | Judge notes |

Commands, all run from the worktree:

```sh
cd /Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish
.build/debug/boopdev eval --list                   > /tmp/boop-review/evals/list.txt
.build/debug/boopdev eval --level standard --list  > /tmp/boop-review/evals/list-standard.txt
.build/debug/boopdev eval --scripted --timeline    > /tmp/boop-review/evals/scripted-timeline.txt
python3 /tmp/boop-review/scripts/traj.py         # 9 Jev runs      -> traj-tables.md
python3 /tmp/boop-review/scripts/raw.py          # raw answers     -> raw-tables.md
python3 /tmp/boop-review/scripts/voice_signs.py  # takes and signs -> voice-signs-tables.md (run traj.py first)
python3 /tmp/boop-review/scripts/demos.py        # recordings      -> demo-tables.md
python3 /tmp/boop-review/scripts/scen.py         # scenarios, graph-> scenario-graph-tables.md
python3 /tmp/boop-review/scripts/pastimes.py     # pastimes model  -> pastime-tables.md
```

The scripts only read. The "current build" and workday tables (sections 4 and 5) came from one-off inline Python over the same files; their output is in `current-tables.md` and `workday-tables.md`.

How to read a trajectory pass: no `face` key means no Moment played (Jev picked nothing, or the code held it). `face: none` means a Moment with no face, such as a sign alone. The trajectory keeps the text Boop said, not the `say` kind; the `say` kind is only in the raw run file.

The 9 runs are not 9 samples of one build. A, B and C are three prompt sizes tried on one night (4,800, 3,140 and 2,100 tokens; A was kept). d2a and d2b are before and after the "flatness" guidelines. t0, t1, t2 and nov8 are later builds. Jev answers nearly the same for the same prompt, so runs of one build are close to one sample. Where the builds differ I say so, and section 4 gives the current build alone (t2 and nov8).

## 2. Ranked list: rarely or never used

**Never, in any Jev run (remove or merge first):**

| Kind | Values |
|---|---|
| Emotion, 13 of 42 | shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, stunned, embarrassed, exhausted, overwhelmed, disgusted |
| Emotion, never above p 0.10 at any of 748 passes | bored, angry, uncomfortable, disappointed, crying, shy, exhausted, disgusted, overwhelmed, embarrassed |
| `say` kind, 8 of 21 (latest run) | waiting, looking, command, helper back, stopped, helpers, tool, planning. helper back, helpers, tool and planning never reach p 0.10 |
| Voice meanings with no text heard | waiting (18 texts), helper back (18), planning (16), helpers (16), tool (8) |
| Voice texts | 266 of 486 never heard; 168 of 202 phrases |
| Sign lines | 72 of 146 (list in section 7) |
| Graph edges | 48 of 119 (list in section 3) |
| Pastimes, stage 1, ordinary day | 35 of 52 rows under once a day; 15 locked to stage 3, 9 to stage 2; `drowsy` needs a request left 10 minutes; 10 tag rows (8 calendar, 2 pace) |
| Moods no scenario step expects as `mood` | determined, engaged, comfy (section 12) |

**Rare (under 0.5% of their kind):**

| Kind | Value | Count |
|---|---|---|
| Lasting mood | lazy | 16 of 6,363 passes (0.3%), 3 moves in; all in run t0; never in 7 other runs |
| Lasting mood | surprised | 25 passes (0.4%), 18 moves in |
| Lasting mood | comfy | 35 passes (0.6%), 22 moves in, 1 move out |
| Lasting mood | wounded | 53 passes (0.8%), only from your words |
| Emotion | baffled 5, frightened 8, lazy 12, confused 15, speechless 19, surprised 20, skeptical 23 | of 5,138 Moments |
| Emotion gone from the current build | bored (161, all in A, C, d2a), tired (65, B, d2b, t0, t1), speechless (19, 16 of them in B) | |
| Move | dance 4, notice 9, unhush 13, no 21 | of 5,138 |
| Size | huge 221 (4.3%), big 360 (7.0%) | |
| `say` kind | start 4, upset 10, retry 11, quiet 13 | of 744 asks, latest run |

**Counted but not what it seems:**

- Grumpy holds 5.4% of passes, but only 59 moves go into it (2.5%). 7 scenarios start in grumpy. Jev rarely moves there itself: it has one ordinary edge in (from irritated).
- Proud is the second face (11%) but only the tenth mood (2.2%). It is a finish's face, not a state Boop stays in.
- Determined is the top face (14%) and 77% of its uses are working check-ins.

## 3. The 16 lasting moods and the graph

Counts over the 9 Jev runs. "Passes in" is the mood after a pass. "Moves in" is how often Jev moved there.
### Runs, passes and mood moves per hour (9 runs, 6,363 passes)

| run | scenarios | passes | no Moment | Moment, face none | Moment with a face | mood moves | virtual hours | moves/h |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | 109 | 623 | 88 (14%) | 0 | 535 | 235 | 224 | 1.05 |
| B | 109 | 683 | 105 (15%) | 0 | 578 | 149 | 224 | 0.67 |
| C | 109 | 683 | 212 (31%) | 0 | 471 | 144 | 224 | 0.64 |
| d2a | 119 | 710 | 111 (16%) | 0 | 599 | 300 | 235 | 1.28 |
| d2b | 119 | 701 | 120 (17%) | 0 | 581 | 279 | 236 | 1.18 |
| t0 | 124 | 717 | 136 (19%) | 0 | 581 | 288 | 237 | 1.22 |
| t1 | 132 | 749 | 125 (17%) | 0 | 624 | 316 | 242 | 1.30 |
| t2 | 132 | 749 | 161 (21%) | 28 | 560 | 319 | 242 | 1.32 |
| nov8 | 131 | 748 | 167 (22%) | 28 | 553 | 310 | 242 | 1.28 |
| ALL | 1084 | 6363 | 1225 (19%) | 56 | 5082 | 2340 | 2105 | 1.11 |

Scenarios of 4 h or less only: 1921 moves in 329 virtual hours = 5.84 moves/h (988 of 1084 scenario runs).

Moves per hour over all scenarios (1.1) is low because 96 scenario runs jump hours or days ahead. In scenarios of 4 hours or less it is 5.8 an hour, because they pack events close together. The workday scenario (section 5) gives about 3 an hour, the best single figure.

### Mood after each pass (16 lasting moods)
| value | count | share |
| --- | ---: | ---: |
| calm | 2777 | 43.6% |
| happy | 782 | 12.3% |
| annoyed | 602 | 9.5% |
| sad | 415 | 6.5% |
| grumpy | 341 | 5.4% |
| excited | 337 | 5.3% |
| engaged | 287 | 4.5% |
| determined | 224 | 3.5% |
| irritated | 153 | 2.4% |
| proud | 142 | 2.2% |
| curious | 88 | 1.4% |
| lonely | 86 | 1.4% |
| wounded | 53 | 0.8% |
| comfy | 35 | 0.6% |
| surprised | 25 | 0.4% |
| lazy | 16 | 0.3% |

Never: (none)

Per run (count of passes in the mood):
| mood | A | B | C | d2a | d2b | t0 | t1 | t2 | nov8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| calm | 262 | 388 | 341 | 253 | 296 | 285 | 321 | 313 | 318 |
| happy | 51 | 54 | 125 | 88 | 65 | 68 | 106 | 108 | 117 |
| annoyed | 51 | 60 | 96 | 52 | 68 | 66 | 70 | 71 | 68 |
| sad | 41 | 59 | 51 | 48 | 35 | 36 | 48 | 50 | 47 |
| grumpy | 49 | 32 | 25 | 51 | 38 | 37 | 34 | 35 | 40 |
| excited | 31 | 27 | 2 | 46 | 44 | 39 | 54 | 50 | 44 |
| engaged | 41 | 2 | 4 | 45 | 49 | 58 | 26 | 31 | 31 |
| determined | 32 | 3 | 5 | 47 | 31 | 34 | 24 | 29 | 19 |
| irritated | 15 | 26 | 4 | 15 | 18 | 16 | 21 | 19 | 19 |
| proud | 20 | 11 | 0 | 19 | 19 | 22 | 16 | 16 | 19 |
| curious | 11 | 0 | 1 | 15 | 13 | 14 | 11 | 11 | 12 |
| lonely | 7 | 7 | 12 | 16 | 13 | 16 | 7 | 4 | 4 |
| wounded | 5 | 6 | 11 | 6 | 5 | 4 | 6 | 5 | 5 |
| comfy | 5 | 3 | 0 | 7 | 5 | 4 | 3 | 5 | 3 |
| surprised | 2 | 5 | 6 | 2 | 2 | 2 | 2 | 2 | 2 |
| lazy | 0 | 0 | 0 | 0 | 0 | 16 | 0 | 0 | 0 |

### Mood moves: the mood moved to
| value | count | share |
| --- | ---: | ---: |
| annoyed | 425 | 18.2% |
| calm | 417 | 17.8% |
| happy | 401 | 17.1% |
| excited | 197 | 8.4% |
| engaged | 185 | 7.9% |
| determined | 129 | 5.5% |
| sad | 127 | 5.4% |
| irritated | 91 | 3.9% |
| curious | 87 | 3.7% |
| proud | 80 | 3.4% |
| lonely | 61 | 2.6% |
| grumpy | 59 | 2.5% |
| wounded | 38 | 1.6% |
| comfy | 22 | 0.9% |
| surprised | 18 | 0.8% |
| lazy | 3 | 0.1% |

Never: (none)

### Mood moves: the mood left
| value | count | share |
| --- | ---: | ---: |
| calm | 1045 | 44.7% |
| annoyed | 298 | 12.7% |
| happy | 212 | 9.1% |
| engaged | 183 | 7.8% |
| determined | 116 | 5.0% |
| excited | 94 | 4.0% |
| sad | 85 | 3.6% |
| grumpy | 75 | 3.2% |
| curious | 64 | 2.7% |
| irritated | 60 | 2.6% |
| lonely | 37 | 1.6% |
| proud | 36 | 1.5% |
| wounded | 24 | 1.0% |
| surprised | 8 | 0.3% |
| lazy | 2 | 0.1% |
| comfy | 1 | 0.0% |

Never: (none)
### Mood moves: from > to (top 40)
| value | count | share |
| --- | ---: | ---: |
| calm > annoyed | 285 | 12.2% |
| calm > happy | 262 | 11.2% |
| calm > engaged | 145 | 6.2% |
| happy > calm | 139 | 5.9% |
| annoyed > calm | 112 | 4.8% |
| calm > excited | 102 | 4.4% |
| calm > curious | 85 | 3.6% |
| annoyed > determined | 76 | 3.2% |
| excited > happy | 70 | 3.0% |
| engaged > calm | 68 | 2.9% |
| annoyed > irritated | 66 | 2.8% |
| calm > sad | 62 | 2.6% |
| calm > lonely | 61 | 2.6% |
| determined > proud | 58 | 2.5% |
| engaged > excited | 58 | 2.5% |
| sad > calm | 46 | 2.0% |
| engaged > determined | 45 | 1.9% |
| grumpy > annoyed | 44 | 1.9% |
| curious > annoyed | 37 | 1.6% |
| sad > happy | 37 | 1.6% |
| determined > engaged | 34 | 1.5% |
| irritated > grumpy | 30 | 1.3% |
| annoyed > grumpy | 26 | 1.1% |
| irritated > annoyed | 26 | 1.1% |
| grumpy > irritated | 25 | 1.1% |
| happy > annoyed | 24 | 1.0% |
| curious > calm | 23 | 1.0% |
| lonely > calm | 19 | 0.8% |
| calm > wounded | 18 | 0.8% |
| wounded > happy | 18 | 0.8% |
| calm > surprised | 17 | 0.7% |
| annoyed > sad | 17 | 0.7% |
| lonely > comfy | 17 | 0.7% |
| proud > excited | 16 | 0.7% |
| determined > sad | 14 | 0.6% |
| happy > proud | 14 | 0.6% |
| happy > sad | 11 | 0.5% |
| happy > excited | 11 | 0.5% |
| proud > happy | 10 | 0.4% |
| determined > excited | 10 | 0.4% |

Graph edges: 119. Edges never taken in any run: 48.
Never taken: annoyed>engaged, annoyed>wounded, comfy>happy, comfy>lazy, comfy>lonely, comfy>surprised, curious>determined, curious>excited, curious>sad, curious>surprised, curious>wounded, determined>annoyed, determined>grumpy, determined>happy, determined>irritated, engaged>happy, engaged>lazy, excited>curious, excited>grumpy, excited>proud, excited>surprised, grumpy>determined, grumpy>surprised, grumpy>wounded, happy>comfy, happy>curious, happy>surprised, irritated>calm, irritated>determined, irritated>engaged, irritated>sad, irritated>wounded, lazy>comfy, lazy>lonely, lazy>surprised, lonely>sad, proud>comfy, proud>engaged, proud>wounded, sad>determined, surprised>grumpy, surprised>happy, wounded>annoyed, wounded>comfy, wounded>determined, wounded>grumpy, wounded>sad, wounded>surprised
Moves not on today's graph (older graph or a start mood):

### The graph (character.json)
| mood | family | out ordinary | out dramatic | in ordinary | in dramatic | in total | in from |
|---|---|---:|---:|---:|---:|---:|---|
| lazy | settled | 4 | 1 | 3 | 0 | 3 | calm, comfy, engaged; jumps:  |
| irritated | frustration | 5 | 3 | 3 | 0 | 3 | determined, annoyed, grumpy; jumps:  |
| lonely | social | 3 | 1 | 3 | 0 | 3 | calm, comfy, lazy; jumps:  |
| curious | cognition | 7 | 2 | 5 | 0 | 5 | calm, happy, excited, engaged, surprised; jumps:  |
| comfy | settled | 4 | 1 | 5 | 1 | 6 | calm, lazy, happy, wounded, lonely; jumps: proud |
| excited | joy | 4 | 4 | 3 | 3 | 6 | happy, curious, proud; jumps: calm, engaged, determined |
| proud | confidence | 5 | 4 | 4 | 2 | 6 | happy, excited, engaged, determined; jumps: irritated, grumpy |
| engaged | cognition | 7 | 2 | 8 | 0 | 8 | calm, lazy, happy, curious, determined, proud, annoyed, irritated; jumps:  |
| grumpy | frustration | 4 | 4 | 1 | 7 | 8 | irritated; jumps: excited, determined, proud, annoyed, sad, wounded, surprised |
| determined | cognition | 6 | 2 | 7 | 2 | 9 | excited, curious, engaged, proud, annoyed, irritated, grumpy; jumps: sad, wounded |
| wounded | sadness | 5 | 3 | 1 | 8 | 9 | sad; jumps: calm, happy, excited, curious, proud, annoyed, irritated, grumpy |
| surprised | surprise | 3 | 1 | 3 | 6 | 9 | curious, annoyed, wounded; jumps: calm, comfy, lazy, happy, excited, grumpy |
| annoyed | frustration | 6 | 2 | 10 | 0 | 10 | calm, happy, curious, engaged, determined, proud, irritated, grumpy, wounded, surprised; jumps:  |
| calm | settled | 7 | 4 | 9 | 2 | 11 | comfy, lazy, happy, curious, engaged, annoyed, sad, wounded, lonely; jumps: irritated, grumpy |
| happy | joy | 7 | 3 | 8 | 3 | 11 | calm, comfy, excited, curious, engaged, determined, proud, surprised; jumps: sad, wounded, lonely |
| sad | sadness | 2 | 3 | 6 | 6 | 12 | determined, annoyed, irritated, grumpy, wounded, lonely; jumps: calm, happy, excited, curious, engaged, proud |

From calm in one move: ordinary comfy, curious, engaged, happy, lazy, annoyed, lonely; jumps surprised, wounded, excited, sad.
Not reachable from calm in one move: determined, proud, irritated, grumpy
Moves from calm (any move): {'calm': 0, 'comfy': 1, 'curious': 1, 'engaged': 1, 'happy': 1, 'lazy': 1, 'annoyed': 1, 'lonely': 1, 'surprised': 1, 'wounded': 1, 'excited': 1, 'sad': 1, 'determined': 2, 'proud': 2, 'irritated': 2, 'grumpy': 2}
Moves from calm (ordinary moves only): {'calm': 0, 'comfy': 1, 'curious': 1, 'engaged': 1, 'happy': 1, 'lazy': 1, 'annoyed': 1, 'lonely': 1, 'surprised': 2, 'excited': 2, 'determined': 2, 'proud': 2, 'irritated': 2, 'sad': 2, 'grumpy': 3, 'wounded': 3}

Faces with no lasting mood (Moment emotions only, 26): bored, pleased, mischievous, shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, frightened, stunned, speechless, amused, hopeful, relieved, confused, baffled, skeptical, embarrassed, affectionate, tired, exhausted, overwhelmed, disgusted

Families (* = lasting): settled: calm*, comfy*, lazy*, bored; joy: pleased, happy*, excited*, amused; cognition: curious*, engaged*, determined*, confused, baffled, skeptical; confidence: proud*, mischievous; social: shy, embarrassed, affectionate, lonely*; strain: uncomfortable, overwhelmed, disgusted; frustration: annoyed*, irritated*, grumpy*, angry; sadness: disappointed, sad*, crying, whiny, wounded*; alarm: uneasy, scared, frightened; surprise: surprised*, stunned, speechless; recovery: hopeful, relieved; energy: tired, exhausted

What the graph and the moves say together:

- From calm, 11 of the other 15 moods are one move away. Determined, proud, irritated and grumpy are two moves away.
- Fewest edges in: lazy 3, irritated 3, lonely 3 (all ordinary), then curious 5. Grumpy has 1 ordinary edge in and 7 jumps; wounded has 1 ordinary and 8 jumps.
- Comfy is a sink in practice: 22 moves in, 1 move out in 9 runs (it starts 1 scenario).
- Calm is the hub: 45% of all moves leave calm and 18% return to it. calm > annoyed (285) and calm > happy (262) are a quarter of all moves.
- 48 edges were never taken. Unused edges out: 6 of wounded's 8 (only wounded > happy and wounded > calm are taken), 4 of comfy's 5, 3 of lazy's 5.

## 4. Emotions (faces), moves and sizes

### Emotion (react.face) of each Moment played, "none" included
| value | count | share |
| --- | ---: | ---: |
| determined | 736 | 14.3% |
| proud | 586 | 11.4% |
| calm | 524 | 10.2% |
| happy | 392 | 7.6% |
| annoyed | 303 | 5.9% |
| grumpy | 298 | 5.8% |
| curious | 282 | 5.5% |
| irritated | 280 | 5.4% |
| sad | 230 | 4.5% |
| pleased | 206 | 4.0% |
| comfy | 182 | 3.5% |
| bored | 161 | 3.1% |
| engaged | 141 | 2.7% |
| affectionate | 118 | 2.3% |
| lonely | 86 | 1.7% |
| mischievous | 85 | 1.7% |
| excited | 77 | 1.5% |
| relieved | 77 | 1.5% |
| wounded | 68 | 1.3% |
| tired | 65 | 1.3% |
| none | 56 | 1.1% |
| amused | 49 | 1.0% |
| hopeful | 34 | 0.7% |
| skeptical | 23 | 0.4% |
| surprised | 20 | 0.4% |
| speechless | 19 | 0.4% |
| confused | 15 | 0.3% |
| lazy | 12 | 0.2% |
| frightened | 8 | 0.2% |
| baffled | 5 | 0.1% |

Never: shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, stunned, embarrassed, exhausted, overwhelmed, disgusted

Per run:
| face | A | B | C | d2a | d2b | t0 | t1 | t2 | nov8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| determined | 81 | 95 | 10 | 91 | 101 | 101 | 93 | 85 | 79 |
| proud | 40 | 61 | 56 | 44 | 66 | 71 | 82 | 82 | 84 |
| calm | 48 | 56 | 22 | 52 | 57 | 48 | 72 | 84 | 85 |
| happy | 87 | 62 | 29 | 89 | 33 | 25 | 19 | 22 | 26 |
| annoyed | 27 | 23 | 4 | 21 | 39 | 38 | 50 | 49 | 52 |
| grumpy | 36 | 28 | 24 | 38 | 35 | 35 | 33 | 34 | 35 |
| curious | 31 | 55 | 15 | 34 | 25 | 26 | 34 | 34 | 28 |
| irritated | 25 | 49 | 53 | 41 | 24 | 23 | 21 | 20 | 24 |
| sad | 22 | 16 | 36 | 24 | 28 | 27 | 25 | 27 | 25 |
| pleased | 0 | 4 | 63 | 0 | 28 | 33 | 29 | 27 | 22 |
| comfy | 9 | 5 | 0 | 11 | 40 | 46 | 53 | 9 | 9 |
| bored | 53 | 0 | 38 | 70 | 0 | 0 | 0 | 0 | 0 |
| engaged | 18 | 34 | 13 | 18 | 13 | 8 | 14 | 10 | 13 |
| affectionate | 4 | 13 | 60 | 3 | 10 | 10 | 6 | 6 | 6 |
| lonely | 5 | 3 | 4 | 6 | 18 | 18 | 14 | 10 | 8 |
| mischievous | 15 | 13 | 0 | 19 | 5 | 4 | 9 | 11 | 9 |
| excited | 2 | 4 | 5 | 5 | 9 | 10 | 17 | 15 | 10 |
| relieved | 7 | 10 | 7 | 10 | 9 | 9 | 7 | 9 | 9 |
| wounded | 6 | 9 | 15 | 6 | 6 | 8 | 6 | 6 | 6 |
| tired | 0 | 7 | 0 | 0 | 20 | 16 | 22 | 0 | 0 |
| none | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 28 | 28 |
| amused | 2 | 5 | 5 | 2 | 7 | 7 | 7 | 6 | 8 |
| hopeful | 7 | 1 | 0 | 2 | 2 | 3 | 4 | 7 | 8 |
| skeptical | 4 | 4 | 6 | 6 | 0 | 0 | 1 | 1 | 1 |
| surprised | 2 | 3 | 1 | 3 | 2 | 3 | 2 | 2 | 2 |
| speechless | 1 | 16 | 0 | 1 | 1 | 0 | 0 | 0 | 0 |
| confused | 1 | 1 | 4 | 2 | 1 | 2 | 1 | 1 | 2 |
| lazy | 0 | 0 | 0 | 0 | 0 | 9 | 1 | 1 | 1 |
| frightened | 1 | 1 | 1 | 0 | 1 | 1 | 1 | 1 | 1 |
| baffled | 1 | 0 | 0 | 1 | 1 | 0 | 1 | 1 | 0 |

### Move (animation) of each Moment
| value | count | share |
| --- | ---: | ---: |
| none | 3026 | 58.9% |
| success | 922 | 17.9% |
| failure | 241 | 4.7% |
| status | 142 | 2.8% |
| wake up | 98 | 1.9% |
| love | 83 | 1.6% |
| comfort | 68 | 1.3% |
| hello | 66 | 1.3% |
| huh | 66 | 1.3% |
| thanks | 57 | 1.1% |
| reply | 50 | 1.0% |
| ouch | 48 | 0.9% |
| wave | 42 | 0.8% |
| yes | 35 | 0.7% |
| bye | 31 | 0.6% |
| hehe | 30 | 0.6% |
| notme | 30 | 0.6% |
| nap | 29 | 0.6% |
| hush | 27 | 0.5% |
| no | 21 | 0.4% |
| unhush | 13 | 0.3% |
| notice | 9 | 0.2% |
| dance | 4 | 0.1% |

### Size of each Moment
| value | count | share |
| --- | ---: | ---: |
| medium | 2305 | 44.9% |
| small | 2252 | 43.8% |
| big | 360 | 7.0% |
| huge | 221 | 4.3% |

### Size of Moments with a face
| value | count | share |
| --- | ---: | ---: |
| medium | 2305 | 45.4% |
| small | 2196 | 43.2% |
| big | 360 | 7.1% |
| huge | 221 | 4.3% |

### By event: passes, Moment rate, top faces, top moods moved to
| event | passes | Moment with a face | said something | sign | mood moved | top faces | top moods moved to |
|---|---:|---:|---:|---:|---:|---|---|
| prompt reading | 847 | 73% | 19% | 26% | 15% | calm 348, determined 71, curious 70, happy 29, mischievous 22 | annoyed 43, happy 37, calm 33, surprised 7 |
| working check-in | 806 | 83% | 80% | 0% | 39% | determined 564, engaged 70, hopeful 33, lonely 1 | engaged 182, calm 86, determined 47 |
| your words | 741 | 100% | 76% | 100% | 25% | curious 136, sad 122, wounded 68, calm 48, happy 47 | happy 38, wounded 38, sad 28, calm 25 |
| turn start | 655 | 6% | 2% | 0% | 7% | engaged 34, determined 6, curious 1 | calm 21, annoyed 13, happy 11, engaged 1 |
| idle check-in | 626 | 74% | 64% | 16% | 40% | bored 161, comfy 118, tired 64, lonely 63, calm 51 | calm 147, happy 44, lonely 35, annoyed 14 |
| poke | 570 | 97% | 91% | 0% | 40% | grumpy 232, annoyed 108, curious 66, mischievous 53, affectionate 39 | curious 83, annoyed 54, grumpy 41, irritated 38 |
| finish done, long | 425 | 99% | 89% | 0% | 53% | proud 297, happy 56, pleased 29, sad 16, relieved 13 | happy 113, calm 38, excited 33, annoyed 17 |
| finish done, short | 374 | 100% | 40% | 1% | 14% | happy 160, pleased 146, amused 21, proud 17, calm 10 | happy 43, annoyed 4, calm 3, engaged 1 |
| check failed | 316 | 99% | 82% | 0% | 85% | annoyed 114, irritated 99, determined 85, grumpy 16 | annoyed 183, determined 71, irritated 10, sad 4 |
| finish done, very long | 192 | 100% | 99% | 0% | 91% | proud 188, excited 2, relieved 1, pleased 1 | excited 143, happy 13, calm 10, proud 8 |
| check passed after failing | 170 | 85% | 64% | 0% | 52% | proud 75, happy 45, relieved 15, pleased 8, annoyed 1 | proud 58, calm 20, happy 9, annoyed 2 |
| other touch | 165 | 96% | 47% | 5% | 61% | comfy 61, affectionate 32, annoyed 26, surprised 12, irritated 11 | annoyed 28, comfy 19, calm 17, irritated 14 |
| back | 127 | 97% | 97% | 35% | 83% | happy 49, excited 34, lonely 22, calm 9, affectionate 7 | happy 73, lonely 26, calm 3, excited 3 |
| finish failed, long | 106 | 100% | 99% | 0% | 83% | irritated 90, sad 12, skeptical 3, grumpy 1 | annoyed 33, sad 32, grumpy 18, irritated 5 |
| lock/unlock | 57 | 100% | 75% | 65% | 2% | calm 48, grumpy 6, surprised 1, comfy 1, annoyed 1 | comfy 1 |
| finish failed, very long | 56 | 100% | 80% | 0% | 93% | sad 53, irritated 3 | sad 44, annoyed 8 |
| work act | 42 | 0% | 0% | 0% | 0% |  |  |
| wish | 24 | 33% | 21% | 0% | 4% | happy 3, affectionate 2, comfy 2, pleased 1 | calm 1 |
| hush | 13 | 38% | 0% | 0% | 54% | speechless 3, annoyed 2 | calm 4, annoyed 3 |
| other | 12 | 100% | 100% | 100% | 100% | excited 12 | excited 9, proud 3 |
| finish done, very short | 9 | 100% | 11% | 0% | 0% | pleased 5, happy 3, calm 1 |  |
| finish failed, very short | 9 | 100% | 100% | 0% | 100% | irritated 9 | annoyed 9 |
| answered | 9 | 0% | 0% | 0% | 0% |  |  |
| compact | 9 | 0% | 0% | 0% | 89% |  | calm 8 |
| world | 3 | 100% | 67% | 100% | 67% | amused 1, proud 1, grumpy 1 | curious 1, happy 1 |

Face same as the Moment before it in the same scenario: 1477 of 4004 (37%).
Face equals the mood after the pass: 1992 of 5082 (39%).

### Each face's events
| face | uses | events |
|---|---:|---|
| determined | 736 | working check-in 564, check failed 85, prompt reading 71, your words 10, turn start 6 |
| proud | 586 | finish done, long 297, finish done, very long 188, check passed after failing 75, finish done, short 17, your words 8 |
| calm | 524 | prompt reading 348, idle check-in 51, your words 48, lock/unlock 48, finish done, short 10 |
| happy | 392 | finish done, short 160, finish done, long 56, back 49, your words 47, check passed after failing 45 |
| annoyed | 303 | check failed 114, poke 108, your words 44, other touch 26, prompt reading 5 |
| grumpy | 298 | poke 232, check failed 16, prompt reading 14, your words 13, other touch 8 |
| curious | 282 | your words 136, prompt reading 70, poke 66, finish done, short 8, turn start 1 |
| irritated | 280 | check failed 99, finish failed, long 90, poke 36, your words 27, other touch 11 |
| sad | 230 | your words 122, finish failed, very long 53, finish done, long 16, poke 13, finish failed, long 12 |
| pleased | 206 | finish done, short 146, finish done, long 29, your words 8, prompt reading 8, check passed after failing 8 |
| comfy | 182 | idle check-in 118, other touch 61, wish 2, lock/unlock 1 |
| bored | 161 | idle check-in 161 |
| engaged | 141 | working check-in 70, turn start 34, your words 19, prompt reading 16, finish done, short 2 |
| affectionate | 118 | poke 39, your words 38, other touch 32, back 7, wish 2 |
| lonely | 86 | idle check-in 63, back 22, working check-in 1 |
| mischievous | 85 | poke 53, prompt reading 22, your words 7, finish done, short 3 |
| excited | 77 | back 34, your words 26, other 12, finish done, very long 2, idle check-in 2 |
| relieved | 77 | your words 40, check passed after failing 15, finish done, long 13, prompt reading 8, finish done, very long 1 |
| wounded | 68 | your words 68 |
| tired | 65 | idle check-in 64, back 1 |
| amused | 49 | finish done, short 21, your words 20, poke 4, prompt reading 3, world 1 |
| hopeful | 34 | working check-in 33, your words 1 |
| skeptical | 23 | your words 15, finish done, short 4, finish failed, long 3, finish done, long 1 |
| surprised | 20 | other touch 12, prompt reading 7, lock/unlock 1 |
| speechless | 19 | your words 16, hush 3 |
| confused | 15 | your words 15 |
| lazy | 12 | your words 8, poke 2, other touch 1, idle check-in 1 |
| frightened | 8 | prompt reading 7, other touch 1 |
| baffled | 5 | your words 5 |

### Current build only: runs t2 (2026-11-05) and nov8 (2026-11-08), 1497 passes

### Face at each pass (no Moment and face none included)
| value | count | share |
|---|---:|---:|
| no Moment | 328 | 21.9% |
| calm | 169 | 11.3% |
| proud | 166 | 11.1% |
| determined | 164 | 11.0% |
| annoyed | 101 | 6.7% |
| grumpy | 69 | 4.6% |
| curious | 62 | 4.1% |
| none | 56 | 3.7% |
| sad | 52 | 3.5% |
| pleased | 49 | 3.3% |
| happy | 48 | 3.2% |
| irritated | 44 | 2.9% |
| excited | 25 | 1.7% |
| engaged | 23 | 1.5% |
| mischievous | 20 | 1.3% |
| relieved | 18 | 1.2% |
| lonely | 18 | 1.2% |
| comfy | 18 | 1.2% |
| hopeful | 15 | 1.0% |
| amused | 14 | 0.9% |
| affectionate | 12 | 0.8% |
| wounded | 12 | 0.8% |
| surprised | 4 | 0.3% |
| confused | 3 | 0.2% |
| lazy | 2 | 0.1% |
| frightened | 2 | 0.1% |
| skeptical | 2 | 0.1% |
| baffled | 1 | 0.1% |

Never: bored, shy, uncomfortable, angry, disappointed, crying, whiny, uneasy, scared, stunned, speechless, embarrassed, tired, exhausted, overwhelmed, disgusted

### Mood after each pass
| value | count | share |
|---|---:|---:|
| calm | 631 | 42.2% |
| happy | 225 | 15.0% |
| annoyed | 139 | 9.3% |
| sad | 97 | 6.5% |
| excited | 94 | 6.3% |
| grumpy | 75 | 5.0% |
| engaged | 62 | 4.1% |
| determined | 48 | 3.2% |
| irritated | 38 | 2.5% |
| proud | 35 | 2.3% |
| curious | 23 | 1.5% |
| wounded | 10 | 0.7% |
| lonely | 8 | 0.5% |
| comfy | 8 | 0.5% |
| surprised | 4 | 0.3% |

Never: lazy

### Mood moved to
| value | count | share |
|---|---:|---:|
| calm | 124 | 19.7% |
| happy | 122 | 19.4% |
| annoyed | 103 | 16.4% |
| excited | 62 | 9.9% |
| engaged | 47 | 7.5% |
| sad | 34 | 5.4% |
| determined | 29 | 4.6% |
| irritated | 27 | 4.3% |
| curious | 23 | 3.7% |
| proud | 20 | 3.2% |
| grumpy | 15 | 2.4% |
| wounded | 8 | 1.3% |
| lonely | 6 | 1.0% |
| comfy | 5 | 0.8% |
| surprised | 4 | 0.6% |

Never: lazy

### Sameness by slot, current build
- Finish done, long or very long: 158 passes; proud 140 (89%), relieved 5 (3%), sad 4 (3%), pleased 4 (3%), grumpy 2 (1%), no Moment 1 (1%)
- Finish done, short: 82 passes; pleased 40 (49%), happy 19 (23%), amused 9 (11%), calm 6 (7%), proud 3 (4%), skeptical 2 (2%)
- Finish failed: 42 passes; irritated 25 (60%), sad 17 (40%)
- Check passed after failing: 38 passes; proud 20 (53%), no Moment 16 (42%), relieved 2 (5%)
- Check failed: 72 passes; annoyed 41 (57%), determined 26 (36%), grumpy 4 (6%), no Moment 1 (1%)
- Working check-in: 182 passes; determined 125 (69%), no Moment 21 (12%), engaged 21 (12%), hopeful 15 (8%)
- Idle check-in: 166 passes; no Moment 96 (58%), none 56 (34%), lonely 14 (8%)
- Turn start: 146 passes; no Moment 146 (100%)
- Prompt reading: 216 passes; calm 130 (60%), no Moment 27 (12%), determined 13 (6%), mischievous 10 (5%), happy 10 (5%), curious 7 (3%)
- Poke: 122 passes; grumpy 53 (43%), annoyed 27 (22%), curious 22 (18%), irritated 9 (7%), mischievous 6 (5%), sad 5 (4%)
- Other touch: 38 passes; comfy 16 (42%), annoyed 9 (24%), affectionate 5 (13%), irritated 3 (8%), surprised 2 (5%), grumpy 2 (5%)
- Back: 30 passes; excited 14 (47%), happy 11 (37%), lonely 4 (13%), affectionate 1 (3%)
- Your words: 150 passes; curious 33 (22%), sad 20 (13%), annoyed 20 (13%), calm 13 (9%), wounded 12 (8%), relieved 9 (6%)
- Lock/unlock: 20 passes; calm 17 (85%), grumpy 2 (10%), annoyed 1 (5%)

Face same as the Moment before it: 290 of 856 (34%). Per run over all 9: A 166/426, B 163/464, C 162/358, d2a 180/481, d2b 168/465, t0 174/459, t1 174/495, t2 143/431, nov8 147/425

### Size by event, current build
| event | small | medium | big | huge |
|---|---:|---:|---:|---:|
| prompt reading | 149 | 40 | 0 | 0 |
| working check-in | 0 | 161 | 0 | 0 |
| your words | 73 | 62 | 15 | 0 |
| poke | 44 | 78 | 0 | 0 |
| finish done, long | 9 | 94 | 5 | 3 |
| finish done, short | 44 | 32 | 6 | 0 |
| check failed | 69 | 2 | 0 | 0 |
| finish done, very long | 0 | 0 | 35 | 11 |
| other touch | 19 | 19 | 0 | 0 |
| back | 1 | 5 | 24 | 0 |
| finish failed, long | 0 | 12 | 0 | 16 |
| check passed after failing | 5 | 17 | 0 | 0 |
| lock/unlock | 4 | 16 | 0 | 0 |
| idle check-in | 8 | 6 | 0 | 0 |
| finish failed, very long | 0 | 0 | 0 | 12 |
| wish | 3 | 1 | 0 | 0 |
| other | 0 | 0 | 2 | 2 |
| world | 2 | 0 | 1 | 0 |
| finish done, very short | 2 | 0 | 0 | 0 |
| finish failed, very short | 0 | 2 | 0 | 0 |
| hush | 2 | 0 | 0 | 0 |

### Words by slot, current build (top 8 each)
- finish done, long (112 passes, 98 said something, 16 distinct): Finish 14, Cleared 13, Done 13, Finito 12, Success 11, Finished 11, Complete 10, Well, poop 2
- finish done, very long (46 passes, 46 said something, 8 distinct): Done 8, Cleared 8, Finished 7, Finito 6, Success 5, Finish 5, Complete 4, Fixed 3
- finish done, short (82 passes, 34 said something, 18 distinct): Yay 4, Ahh... Nice 2, Mm-hm Yay 2, Listen 2, Phew... 2, Ooh! Bingo 2, Whew Ole 2, Heh... Yatta 2
- check failed (72 passes, 49 said something, 17 distinct): Test 7, Checking 5, Redo 4, Verify 4, Again 4, Probe 4, Rewind 3, Validate 3
- check passed after failing (38 passes, 14 said something, 7 distinct): Trial 3, Eep! 3, Verify 2, Heh... 2, Measure 2, Probe 1, Test 1
- working check-in (182 passes, 161 said something, 47 distinct): Busy 12, Work 12, Easy 9, Steady 8, Probe 8, Careful 7, Gently 6, Piano 6
- idle check-in (166 passes, 9 said something, 4 distinct): Quiet 4, Peace 3, Comfy 1, Hullo 1
- poke (122 passes, 113 said something, 17 distinct): Hmph Ouch 17, Whoa 14, Oh 13, Tickles 11, Hmph Oh 9, Stop 7, Hmph Halt 7, Hmph 6
- back (30 passes, 30 said something, 6 distinct): Hey 8, Hello 6, Hey hey 6, Hi 4, Howdy 4, Salut 2
- finish failed, long (28 passes, 27 said something, 15 distinct): Shiba 7, Hff Crap 3, Hmph Fuck 2, Nnngh... Shit 2, Damn 2, Pfft Shit 2, Grr... Fuck 1, Not quite 1

### Jev's raw answers, one standard run (2026-11-08, 748 passes): /tmp/boop-eval/20261108-220953-81575.jsonl
Brains: {'jev:jev-latest': 748}. Dropped: {'None': 748}
Questions answered: {'mood': 748, 'react.face': 748, 'react.intensity': 748, 'react.move': 748, 'say': 744, 'react.sign': 259}

### mood: asked at 748 passes
| option | offered | chosen | share of asks | summed probability | highest p ever |
|---|---:|---:|---:|---:|---:|
| calm | 685 | 318 | 42.5% | 282.5 | 0.99 |
| happy | 637 | 117 | 15.6% | 107.0 | 0.99 |
| annoyed | 670 | 68 | 9.1% | 62.0 | 0.96 |
| sad | 746 | 47 | 6.3% | 45.4 | 1.00 |
| excited | 586 | 44 | 5.9% | 45.2 | 0.97 |
| grumpy | 220 | 40 | 5.3% | 39.8 | 0.98 |
| engaged | 622 | 31 | 4.1% | 49.6 | 0.97 |
| determined | 260 | 19 | 2.5% | 23.0 | 0.97 |
| proud | 240 | 19 | 2.5% | 20.4 | 0.99 |
| irritated | 129 | 19 | 2.5% | 17.8 | 0.97 |
| curious | 557 | 12 | 1.6% | 19.3 | 0.94 |
| wounded | 693 | 5 | 0.7% | 6.0 | 0.99 |
| lonely | 398 | 4 | 0.5% | 6.2 | 0.87 |
| comfy | 503 | 3 | 0.4% | 18.7 | 0.93 |
| surprised | 627 | 2 | 0.3% | 2.9 | 0.61 |
| lazy | 427 | 0 | 0.0% | 2.4 | 0.09 |

Never chosen: lazy
Never above p 0.10 at any pass: lazy

### react.face: asked at 748 passes
| option | offered | chosen | share of asks | summed probability | highest p ever |
|---|---:|---:|---:|---:|---:|
| none | 656 | 195 | 26.1% | 157.1 | 0.92 |
| calm | 748 | 85 | 11.4% | 85.3 | 0.96 |
| proud | 748 | 84 | 11.2% | 67.9 | 0.99 |
| determined | 748 | 79 | 10.6% | 68.0 | 0.94 |
| annoyed | 748 | 52 | 7.0% | 42.7 | 0.93 |
| grumpy | 748 | 35 | 4.7% | 30.3 | 0.93 |
| curious | 748 | 28 | 3.7% | 32.2 | 0.78 |
| happy | 748 | 26 | 3.5% | 34.9 | 0.81 |
| sad | 748 | 25 | 3.3% | 22.2 | 0.98 |
| irritated | 748 | 24 | 3.2% | 26.5 | 0.98 |
| pleased | 748 | 22 | 2.9% | 23.8 | 0.80 |
| engaged | 748 | 13 | 1.7% | 23.9 | 0.69 |
| excited | 748 | 10 | 1.3% | 15.2 | 0.99 |
| comfy | 748 | 9 | 1.2% | 17.1 | 0.89 |
| mischievous | 748 | 9 | 1.2% | 10.9 | 0.82 |
| relieved | 748 | 9 | 1.2% | 8.6 | 0.91 |
| hopeful | 748 | 8 | 1.1% | 11.8 | 0.56 |
| amused | 748 | 8 | 1.1% | 9.3 | 0.73 |
| lonely | 748 | 8 | 1.1% | 8.9 | 0.92 |
| affectionate | 748 | 6 | 0.8% | 9.1 | 0.78 |
| wounded | 748 | 6 | 0.8% | 7.0 | 1.00 |
| surprised | 748 | 2 | 0.3% | 5.3 | 0.95 |
| confused | 748 | 2 | 0.3% | 2.2 | 0.56 |
| lazy | 748 | 1 | 0.1% | 5.1 | 0.23 |
| skeptical | 748 | 1 | 0.1% | 2.8 | 0.58 |
| frightened | 748 | 1 | 0.1% | 0.7 | 0.37 |
| tired | 748 | 0 | 0.0% | 8.1 | 0.26 |
| speechless | 748 | 0 | 0.0% | 5.4 | 0.15 |
| bored | 748 | 0 | 0.0% | 1.0 | 0.06 |
| angry | 748 | 0 | 0.0% | 0.6 | 0.05 |
| uneasy | 748 | 0 | 0.0% | 0.5 | 0.13 |
| baffled | 748 | 0 | 0.0% | 0.5 | 0.32 |
| whiny | 748 | 0 | 0.0% | 0.5 | 0.20 |
| uncomfortable | 748 | 0 | 0.0% | 0.5 | 0.09 |
| disappointed | 748 | 0 | 0.0% | 0.4 | 0.03 |
| scared | 748 | 0 | 0.0% | 0.4 | 0.12 |
| stunned | 748 | 0 | 0.0% | 0.3 | 0.17 |
| crying | 748 | 0 | 0.0% | 0.2 | 0.07 |
| shy | 748 | 0 | 0.0% | 0.2 | 0.05 |
| exhausted | 748 | 0 | 0.0% | 0.1 | 0.08 |
| disgusted | 748 | 0 | 0.0% | 0.1 | 0.01 |
| overwhelmed | 748 | 0 | 0.0% | 0.0 | 0.01 |
| embarrassed | 748 | 0 | 0.0% | 0.0 | 0.01 |

Never chosen: tired, speechless, bored, angry, uneasy, baffled, whiny, uncomfortable, disappointed, scared, stunned, crying, shy, exhausted, disgusted, overwhelmed, embarrassed
Never above p 0.10 at any pass: bored, angry, uncomfortable, disappointed, crying, shy, exhausted, disgusted, overwhelmed, embarrassed

### react.move: asked at 748 passes
| option | offered | chosen | share of asks | summed probability | highest p ever |
|---|---:|---:|---:|---:|---:|
| none | 673 | 510 | 68.2% | 513.4 | 1.00 |
| success | 663 | 112 | 15.0% | 107.9 | 0.99 |
| failure | 663 | 23 | 3.1% | 23.5 | 1.00 |
| status | 75 | 15 | 2.0% | 15.1 | 1.00 |
| wake up | 663 | 11 | 1.5% | 11.0 | 0.99 |
| love | 75 | 9 | 1.2% | 9.1 | 1.00 |
| wave | 10 | 7 | 0.9% | 7.7 | 0.99 |
| comfort | 75 | 7 | 0.9% | 7.1 | 1.00 |
| hello | 75 | 7 | 0.9% | 7.1 | 1.00 |
| reply | 663 | 7 | 0.9% | 7.0 | 0.97 |
| thanks | 75 | 6 | 0.8% | 5.9 | 1.00 |
| huh | 75 | 5 | 0.7% | 5.1 | 0.99 |
| ouch | 75 | 5 | 0.7% | 5.0 | 1.00 |
| yes | 75 | 4 | 0.5% | 3.8 | 0.99 |
| nap | 77 | 4 | 0.5% | 3.4 | 0.98 |
| bye | 75 | 3 | 0.4% | 2.9 | 0.99 |
| notme | 75 | 3 | 0.4% | 2.9 | 0.97 |
| hehe | 75 | 3 | 0.4% | 2.7 | 0.87 |
| no | 75 | 3 | 0.4% | 2.4 | 0.88 |
| hush | 75 | 2 | 0.3% | 2.4 | 1.00 |
| notice | 663 | 1 | 0.1% | 1.1 | 0.99 |
| unhush | 10 | 1 | 0.1% | 1.0 | 0.96 |
| dance | 75 | 0 | 0.0% | 0.5 | 0.41 |

Never chosen: dance
Never above p 0.10 at any pass: 

### react.intensity: asked at 748 passes
| option | offered | chosen | share of asks | summed probability | highest p ever |
|---|---:|---:|---:|---:|---:|
| small | 748 | 398 | 53.2% | 372.7 | 0.99 |
| medium | 748 | 286 | 38.2% | 282.8 | 0.96 |
| big | 748 | 42 | 5.6% | 68.8 | 0.89 |
| huge | 748 | 22 | 2.9% | 23.7 | 0.97 |

Never chosen: 
Never above p 0.10 at any pass: 

### say: asked at 744 passes
| option | offered | chosen | share of asks | summed probability | highest p ever |
|---|---:|---:|---:|---:|---:|
| none | 720 | 319 | 42.9% | 311.3 | 0.98 |
| work | 739 | 65 | 8.7% | 62.0 | 0.92 |
| done | 739 | 64 | 8.6% | 39.0 | 0.75 |
| tests | 739 | 54 | 7.3% | 37.8 | 0.83 |
| answer | 739 | 45 | 6.0% | 38.0 | 0.94 |
| glad | 744 | 42 | 5.6% | 53.9 | 0.92 |
| shaken | 744 | 42 | 5.6% | 40.0 | 0.96 |
| hello | 739 | 28 | 3.8% | 25.8 | 1.00 |
| tickled | 744 | 26 | 3.5% | 22.0 | 0.87 |
| swear | 739 | 21 | 2.8% | 19.5 | 0.89 |
| quiet | 739 | 13 | 1.7% | 28.0 | 0.80 |
| retry | 739 | 11 | 1.5% | 10.6 | 0.94 |
| upset | 744 | 10 | 1.3% | 24.0 | 0.95 |
| start | 739 | 4 | 0.5% | 22.4 | 0.53 |
| waiting | 739 | 0 | 0.0% | 5.2 | 0.12 |
| looking | 739 | 0 | 0.0% | 1.6 | 0.10 |
| command | 739 | 0 | 0.0% | 1.1 | 0.14 |
| helper back | 739 | 0 | 0.0% | 1.0 | 0.06 |
| stopped | 739 | 0 | 0.0% | 0.8 | 0.23 |
| helpers | 739 | 0 | 0.0% | 0.1 | 0.03 |
| tool | 739 | 0 | 0.0% | 0.1 | 0.01 |
| planning | 739 | 0 | 0.0% | 0.0 | 0.02 |

Never chosen: waiting, looking, command, helper back, stopped, helpers, tool, planning
Never above p 0.10 at any pass: helper back, helpers, tool, planning

### react.sign: asked at 259 passes; picked a sign at 146, none at 113

mood: median top probability 0.77; passes where the top choice is under 0.5: 67 of 748 (9%).

react.face: median top probability 0.62; passes where the top choice is under 0.5: 220 of 748 (29%).

say: median top probability 0.75; passes where the top choice is under 0.5: 120 of 744 (16%).

### react.face: close calls (the runner-up had p of 0.20 or more): 319 passes
| pair | passes |
|---|---:|
| calm / none | 54 |
| determined / none | 39 |
| calm / curious | 18 |
| happy / pleased | 13 |
| determined / engaged | 12 |
| engaged / none | 11 |
| comfy / none | 11 |
| excited / proud | 10 |
| calm / pleased | 9 |
| grumpy / irritated | 9 |
| irritated / sad | 7 |
| engaged / hopeful | 7 |
| happy / proud | 7 |
| affectionate / comfy | 7 |
| amused / pleased | 6 |
| annoyed / determined | 5 |
| annoyed / none | 5 |
| none / tired | 5 |
| lonely / none | 5 |
| excited / happy | 5 |
| annoyed / curious | 4 |
| annoyed / irritated | 4 |
| amused / happy | 3 |
| none / proud | 3 |
| calm / happy | 3 |

### mood: close calls (the runner-up had p of 0.20 or more): 346 passes
| pair | passes |
|---|---:|
| calm / engaged | 77 |
| calm / happy | 58 |
| calm / comfy | 44 |
| annoyed / calm | 36 |
| excited / happy | 22 |
| excited / proud | 11 |
| grumpy / irritated | 10 |
| annoyed / sad | 8 |
| calm / curious | 8 |
| calm / determined | 7 |
| calm / sad | 7 |
| annoyed / grumpy | 7 |
| annoyed / curious | 6 |
| grumpy / sad | 5 |
| determined / engaged | 5 |
| annoyed / irritated | 5 |
| annoyed / happy | 4 |
| happy / proud | 4 |
| annoyed / determined | 4 |
| excited / wounded | 3 |
| calm / excited | 3 |
| happy / sad | 3 |
| determined / excited | 2 |
| determined / irritated | 1 |
| determined / sad | 1 |

Face and say picks together: {'no face + no say': 171, 'face + say': 401, 'face + no say': 152, 'no face + say': 24}

## 5. The workday scenario

| run | passes | virtual hours | no Moment | face none | faces | mood moves | moves/h | moods visited | said something | signs |
|---|---:|---:|---:|---:|---|---:|---:|---|---:|---|
| d2a | 48 | 8.7 | 5 | 0 | bored 13, determined 7, happy 5, proud 4, calm 4, comfy 2, relieved 2, sad 1, mischievous 1, irritated 1, engaged 1, curious 1, surprised 1 | 24 | 2.77 | calm 13, happy 10, excited 8, lonely 6, sad 4, engaged 3, determined 2, comfy 2 | 39 | bug hunt; stroke my face?; sweet dreams; ship it?; bug hunt; hehe thx; see ya! |
| d2b | 48 | 8.7 | 4 | 0 | comfy 12, proud 8, calm 6, determined 4, happy 3, affectionate 2, tired 2, annoyed 2, relieved 2, sad 1, engaged 1, irritated 1 | 24 | 2.77 | calm 24, happy 8, excited 4, sad 4, engaged 2, proud 2, comfy 2, annoyed 1, determined 1 | 34 | hold BOOT, say hi?; see ya!; sweet dreams; i know ;); see ya! |
| t0 | 48 | 8.7 | 6 | 0 | comfy 13, proud 7, calm 5, determined 4, affectionate 3, annoyed 2, relieved 2, happy 2, sad 1, engaged 1, irritated 1, pleased 1 | 23 | 2.66 | calm 25, happy 8, excited 4, sad 4, engaged 2, proud 2, annoyed 1, determined 1, comfy 1 | 33 | hold BOOT, say hi?; see ya!; had a dream; i know ;); bye bye |
| t1 | 48 | 8.7 | 5 | 0 | comfy 10, proud 8, calm 7, lonely 4, determined 3, sad 2, affectionate 1, annoyed 1, relieved 1, curious 1, happy 1, engaged 1, irritated 1, pleased 1, tired 1 | 24 | 2.77 | calm 25, happy 8, sad 4, lonely 4, excited 3, engaged 1, annoyed 1, curious 1, determined 1 | 27 | stroke my face?; see ya!; sweet dreams; i know ;); see ya! |
| t2 | 48 | 8.7 | 12 | 3 | calm 8, proud 7, determined 4, relieved 3, affectionate 2, annoyed 2, sad 2, pleased 2, curious 1, irritated 1, comfy 1 | 27 | 3.12 | calm 25, happy 7, excited 4, sad 4, engaged 3, annoyed 3, curious 1, determined 1 | 18 | hold BOOT, say hi?; claude sits idle; ship it?; bug hunt; i know ;); see ya! |
| nov8 | 48 | 8.7 | 13 | 3 | calm 9, proud 7, happy 3, affectionate 2, sad 2, relieved 2, engaged 2, hopeful 1, annoyed 1, curious 1, determined 1, irritated 1 | 25 | 2.89 | calm 27, happy 8, excited 4, sad 4, engaged 2, annoyed 1, curious 1, determined 1 | 18 | hold BOOT, say hi?; claude sits idle; see ya!; i know ;); see ya! |

Scenario 173 is 8.7 virtual hours with 11 turns, 2 touches, 1 poke, a lunch away and one thing said. It is light for a real day (a buyer may run 40 or more turns), so real counts are higher, but the mix is the most realistic one on disk. In the current build a whole day shows 11 or 12 different faces and visits 8 moods; calm holds 52 to 56% of its passes. No day shows lazy, comfy as a mood, proud as a mood, grumpy, irritated, wounded, surprised or lonely.

## 6. Voice

Takes in takes.tsv: 3479. Distinct texts: 486. Total audio: 55 min.

By kind (takes / distinct texts): word 2637/215, sound 520/67, phrase 304/202, swear 18/5

By part (takes / distinct texts): about 2016/267, reply 864/192, feeling 599/104

By meaning (takes / distinct texts): upset 259/49, looking 258/41, glad 211/40, work 177/25, hello 165/17, start 142/20, waiting 138/18, helper back 128/18, tests 125/17, done 114/16, retry 112/16, planning 112/16, helpers 112/16, stopped 112/16, answer 112/16, command 104/8, tool 104/8, quiet 104/8, yes 77/16, no 73/18, tickled 72/12, nap 60/11, shaken 57/9, status 55/12, hehe 53/11, unhush 53/10, bye 52/12, love 50/12, thanks 47/16, ouch 42/11, hush 40/8, dance 35/12, huh 33/12, comfort 33/11, dunno 29/11, notme 29/8

Said in the runs: 3809 Moments, 366 distinct strings. Matched to take texts: 211 distinct texts (main take), 40 distinct lead sounds; unmatched strings: 0 (0 uses): 
Distinct take texts ever heard (main or lead): 220 of 486 (45%). Never heard: 266 texts.

| kind | distinct texts | heard in 9 runs | share |
|---|---:|---:|---:|
| word | 215 | 128 | 60% |
| sound | 67 | 55 | 82% |
| swear | 5 | 5 | 100% |
| phrase | 202 | 34 | 17% |

| meaning (say kind) | part | distinct texts | heard | uses of its texts (main take) |
|---|---|---:|---:|---:|
| done | about | 16 | 14 | 507 |
| tickled | feeling | 12 | 7 | 494 |
| work | about | 25 | 17 | 474 |
| quiet | about | 8 | 8 | 429 |
| upset | feeling | 49 | 41 | 411 |
| glad | feeling | 40 | 30 | 404 |
| shaken | feeling | 9 | 8 | 396 |
| tests | about | 17 | 8 | 328 |
| hello | reply | 17 | 9 | 236 |
| love | reply | 12 | 10 | 207 |
| hehe | reply | 11 | 7 | 181 |
| nap | reply | 11 | 7 | 172 |
| status | reply | 12 | 5 | 138 |
| yes | reply | 16 | 7 | 137 |
| ouch | reply | 11 | 8 | 137 |
| bye | reply | 12 | 8 | 107 |
| thanks | reply | 16 | 13 | 106 |
| retry | about | 16 | 8 | 92 |
| stopped | about | 16 | 5 | 73 |
| looking | about | 41 | 7 | 69 |
| comfort | reply | 11 | 9 | 67 |
| hush | reply | 8 | 3 | 64 |
| dunno | reply | 11 | 5 | 63 |
| unhush | reply | 10 | 4 | 57 |
| start | about | 20 | 9 | 51 |
| answer | about | 16 | 8 | 40 |
| dance | reply | 12 | 2 | 35 |
| no | reply | 18 | 9 | 30 |
| huh | reply | 12 | 4 | 27 |
| command | about | 8 | 7 | 11 |
| notme | reply | 8 | 3 | 6 |
| waiting | about | 18 | 0 | 0 |
| tool | about | 8 | 0 | 0 |
| planning | about | 16 | 0 | 0 |
| helpers | about | 16 | 0 | 0 |
| helper back | about | 18 | 0 | 0 |

(A text can belong to several meanings, so uses are counted under each.)

Takes recorded per mood tag (a take lists the moods it suits): happy 331, pleased 331, amused 331, affectionate 331, calm 329, comfy 329, lazy 329, bored 329, relieved 329, tired 329, exhausted 329, curious 311, shy 311, surprised 311, stunned 311, speechless 311, confused 311, baffled 311, skeptical 311, proud 290, mischievous 290, excited 280, engaged 269, determined 268, hopeful 268, annoyed 259, uncomfortable 259, disgusted 259, sad 243, disappointed 243, crying 243, lonely 243, grumpy 235, angry 235, whiny 225, wounded 220, uneasy 220, scared 220, frightened 220, embarrassed 220, overwhelmed 220, irritated 219

### Voice texts, top 60
| value | count | share |
| --- | ---: | ---: |
| Whoa | 133 | 3.5% |
| Boop | 109 | 2.9% |
| Tickles | 91 | 2.4% |
| Finito | 73 | 1.9% |
| Finish | 71 | 1.9% |
| Cleared | 70 | 1.8% |
| Oh | 68 | 1.8% |
| Chill | 65 | 1.7% |
| Peace | 64 | 1.7% |
| Cozy | 63 | 1.7% |
| Mm-hm | 61 | 1.6% |
| Probe | 60 | 1.6% |
| Done | 60 | 1.6% |
| Fixed | 60 | 1.6% |
| Measure | 57 | 1.5% |
| Complete | 55 | 1.4% |
| Finished | 52 | 1.4% |
| Ohh | 49 | 1.3% |
| Howdy | 49 | 1.3% |
| Comfy | 48 | 1.3% |
| Test | 44 | 1.2% |
| Quiet | 43 | 1.1% |
| Mellow | 43 | 1.1% |
| Hullo | 41 | 1.1% |
| Argh Ouch | 40 | 1.1% |
| Eep! | 40 | 1.1% |
| Yep | 40 | 1.1% |
| Validate | 37 | 1.0% |
| Hmm | 37 | 1.0% |
| Verify | 37 | 1.0% |
| Success | 37 | 1.0% |
| Heyy | 35 | 0.9% |
| Trial | 34 | 0.9% |
| Steady | 32 | 0.8% |
| Hup Slowly | 31 | 0.8% |
| Testing | 31 | 0.8% |
| Argh Crap | 29 | 0.8% |
| Hehehe... | 28 | 0.7% |
| Oh! | 28 | 0.7% |
| Checking | 28 | 0.7% |
| Hmph Ouch | 28 | 0.7% |
| Busy | 27 | 0.7% |
| Ngh Busy | 24 | 0.6% |
| Recheck | 24 | 0.6% |
| Work | 24 | 0.6% |
| Ha! | 23 | 0.6% |
| Phew... | 23 | 0.6% |
| Retry | 22 | 0.6% |
| Hi | 22 | 0.6% |
| Heh... | 22 | 0.6% |
| Oh, come on | 20 | 0.5% |
| Hello | 20 | 0.5% |
| Rrr... Work | 19 | 0.5% |
| Peek | 19 | 0.5% |
| Mwahaha... Woohoo | 19 | 0.5% |
| Ouch | 19 | 0.5% |
| Easy | 19 | 0.5% |
| Go | 18 | 0.5% |
| Ooh! | 18 | 0.5% |
| Careful | 18 | 0.5% |

Texts said exactly once: 88. Texts said 1-2 times: 138.

Notes:

- A take row lists the faces it suits. Only 26 faces have takes tagged to them; `annoyed` has 25 takes, the cross and sad faces borrow others.
- The top texts are labels, not feelings: Finito, Finish, Cleared, Done, Fixed, Complete, Finished, Success at finishes; Probe, Measure, Test, Validate, Verify, Trial, Testing, Checking at checks. The judge calls these bland in 5 of 9 summaries (section 8).
- Idle check-ins used a pool of 6 to 8 words in every run that spoke at idle (Chill, Peace, Cozy, Comfy, Mellow, Quiet, Hullo, Ohh).

## 7. Signs

Passes with a sign: 1,171 of 6,363 (18%). Distinct signs: 124. Nearly all come from 5 events: your words (100% have a sign), lock or unlock (65%), a return (35%), a prompt (26%), an idle check-in (16%).

### Signs, top 70
| value | count | share |
| --- | ---: | ---: |
| rude. | 44 | 3.8% |
| still broken?! | 39 | 3.3% |
| there there | 38 | 3.2% |
| hold BOOT, say hi? | 36 | 3.1% |
| see ya! | 32 | 2.7% |
| forgiven <3 | 30 | 2.6% |
| all quiet | 30 | 2.6% |
| love u too | 26 | 2.2% |
| stroke my face? | 25 | 2.1% |
| claude sits idle | 24 | 2.0% |
| i know ;) | 23 | 2.0% |
| i'm here | 22 | 1.9% |
| <3 | 21 | 1.8% |
| good, u? | 20 | 1.7% |
| good night 2 u! | 20 | 1.7% |
| yes yes! | 18 | 1.5% |
| claude: a fix | 18 | 1.5% |
| warm dreams | 18 | 1.5% |
| ok, shh | 17 | 1.5% |
| ship it? | 17 | 1.5% |
| hi hi! | 16 | 1.4% |
| yep! | 14 | 1.2% |
| nah | 13 | 1.1% |
| i can talk! | 13 | 1.1% |
| please | 12 | 1.0% |
| tests! tests! | 12 | 1.0% |
| hehe thx | 12 | 1.0% |
| no idea! | 12 | 1.0% |
| perfect <3 | 12 | 1.0% |
| yay! | 11 | 0.9% |
| who knows? | 11 | 0.9% |
| zzz | 11 | 0.9% |
| not my job | 11 | 0.9% |
| claude: resting | 11 | 0.9% |
| 1 resting | 11 | 0.9% |
| new thing! | 11 | 0.9% |
| dark mode | 10 | 0.9% |
| huh? | 10 | 0.9% |
| ask them! | 10 | 0.9% |
| come again? | 10 | 0.9% |
| settings page | 9 | 0.8% |
| claude: 4 min in | 9 | 0.8% |
| tests failed | 9 | 0.8% |
| claude: done! | 9 | 0.8% |
| codex: 2 min in | 9 | 0.8% |
| 1 working, 1 idle | 9 | 0.8% |
| 2 resting | 9 | 0.8% |
| not now, busy | 9 | 0.8% |
| at it 3 min | 9 | 0.8% |
| that's ur job | 9 | 0.8% |
| 1 working | 9 | 0.8% |
| knock knock lol | 9 | 0.8% |
| had a dream | 9 | 0.8% |
| 'um okay'? | 9 | 0.8% |
| sorry <3 | 9 | 0.8% |
| hey 2 u! | 9 | 0.8% |
| just kidding lol | 9 | 0.8% |
| STILL BROKEN!! | 9 | 0.8% |
| nite nite | 9 | 0.8% |
| really cute lol | 8 | 0.7% |
| right here! | 8 | 0.7% |
| so cute lol | 8 | 0.7% |
| man? idk | 8 | 0.7% |
| bug nightmares | 8 | 0.7% |
| morning! | 8 | 0.7% |
| *hug* | 8 | 0.7% |
| zzz... hi! | 8 | 0.7% |
| careful | 7 | 0.6% |
| hold BOOT and talk | 7 | 0.6% |
| quickly | 6 | 0.5% |

### signs.md: 58 lines
| tags | line | times held up |
|---|---|---:|
| frustrated | {words} :( | 0 |
| frustrated | {words}?! | 50 |
| frustrated | {words}. again. | 0 |
| shouting | {WORDS}!! | 9 |
| polite | {words} <3 | 61 |
| rushed | '{words}', sure | 0 |
| careful | {words}... | 3 |
| playful | {words} lol | 41 |
| named | me?! | 1 |
| named | you rang? | 0 |
| fix frustrated | bug, again | 0 |
| fix | bug hunt | 3 |
| fix | who broke it? | 0 |
| fix night | bugs at night? | 0 |
| feature | new thing! | 11 |
| feature | ooh, shiny | 0 |
| feature | another one?! | 0 |
| cleanup | bye bye code | 6 |
| cleanup | delete it all | 0 |
| refactor | tidy time | 1 |
| tests | tests! tests! | 12 |
| deploy | ship it? | 17 |
| deploy | yolo | 0 |
| deploy friday | on a FRIDAY? | 0 |
| docs | docs... | 2 |
| question | hmm? | 0 |
| question | good q | 0 |
| carry_on | onward! | 0 |
| essay | reading... | 0 |
|  | {words} | (any words; not counted) |
| idle | quiet day... | 0 |
| idle | {turns} turns today! | 0 |
| idle | {thread} again? | 12 |
| idle | still here, u? | 0 |
| idle cookie | snack time? | 0 |
| idle pizza | pizza later? | 0 |
| notice waiting | {agent}'s waiting | 0 |
| notice waiting | {agent} sits idle | 24 |
| notice waiting | {agent}'s done | 0 |
| notice stretch | stretch? | 0 |
| notice stretch | legs ok? | 0 |
| notice stretch | water break? | 0 |
| notice rough | i'm here | 22 |
| notice rough | *hug* | 8 |
| notice rough | rough one | 1 |
| notice late | bed? | 0 |
| notice late | still up? | 3 |
| notice late | getting late... | 0 |
| world boop | boop back! | 0 |
| world boop | who was that? | 1 |
| world wave | hi, friend! | 0 |
| world wave | *waves back* | 0 |
| world heart | aww, a heart | 0 |
| world heart | <3 <3 | 0 |
| world cheer | we shipped! | 1 |
| world cheer | thanks, all! | 0 |
| world | hi, world! | 0 |
| world | a friend! | 1 |

Lines never held up: 35 of 58.

### replies.md: 67 lines
| tags | line | times held up |
|---|---|---:|
| yes | yep! | 14 |
| yes | uh-huh | 3 |
| yes | mhm! | 0 |
| yes | yes yes! | 18 |
| no | nope | 5 |
| no | nuh-uh | 3 |
| no | nah | 13 |
| no | make me | 0 |
| no | no way | 0 |
| dunno | no idea! | 12 |
| dunno | beats me | 0 |
| dunno | who knows? | 11 |
| dunno | {words}? idk | 8 |
| huh | huh? | 10 |
| huh | come again? | 10 |
| huh | '{words}'? | 15 |
| huh nobrain | no brain yet :( | 0 |
| huh nobrain | need my brain! | 0 |
| hello | hi hi! | 16 |
| hello | oh, hi! | 0 |
| hello | good, u? | 20 |
| hello | right here! | 8 |
| hello | {words} 2 u! | 34 |
| hello morning | morning! | 8 |
| bye | bye bye | 1 |
| bye | see ya! | 32 |
| bye | {words} 2 u! | 34 |
| bye night | nite nite | 9 |
| bye night | {turns} turns today | 0 |
| bye working | i got this | 6 |
| thanks | i know ;) | 23 |
| thanks | hehe thx | 12 |
| thanks | woo! | 1 |
| thanks | yay! | 11 |
| thanks | {words}? me?! | 10 |
| thanks | we rock | 0 |
| love | <3 | 21 |
| love | love u too | 26 |
| love | aww | 6 |
| love makeup | ...fine | 0 |
| love makeup | forgiven <3 | 30 |
| ouch | :( | 4 |
| ouch | rude. | 44 |
| comfort | *hug* | 8 |
| comfort | there there | 38 |
| comfort | i'm here | 22 |
| comfort night | bed time? | 0 |
| comfort working | u got this | 0 |
| comfort working | we'll fix it | 0 |
| hehe | hehe | 0 |
| hehe | lol | 5 |
| hehe | {words} lol | 41 |
| nap | zzz | 11 |
| nap | nap time | 0 |
| nap working | after this | 0 |
| nap working | not now, busy | 9 |
| hush | ok, shh | 17 |
| hush | *zips lips* | 5 |
| hush | fine. hmph. | 5 |
| unhush | i can talk! | 13 |
| unhush | words! yay! | 0 |
| dance | *wiggle* | 4 |
| dance | look at me go | 0 |
| dance | wheee | 0 |
| notme | ask them! | 10 |
| notme | not my job | 11 |
| notme waiting | that's ur job | 9 |

Lines never held up: 19 of 67.

### asks.md: 21 lines
| tags | line | times held up |
|---|---|---:|
| snack idle keeps | fav snack? | cookie | pizza | 0 |
| hat idle keeps | hat or bow? | hat | bow | 0 |
| snack cookie | nom nom | 0 |
| snack pizza | pizza party! | 0 |
| hat hat | dapper! | 0 |
| hat bow | so pretty | 0 |
| wish pet | pet me? | 0 |
| wish pet | scritches? | 0 |
| wish pet | pat pat? | 0 |
| wish pet met | <3 | 21 |
| wish pet how | stroke my face? | 25 |
| wish chat | talk to me? | 0 |
| wish chat | say something? | 0 |
| wish chat | got a word? | 0 |
| wish chat met | i hear u | 0 |
| wish chat how | hold BOOT, say hi? | 36 |
| wish work | work with me? | 0 |
| wish work | give me work? | 0 |
| wish work | bored. any work? | 0 |
| wish work met | lets go! | 0 |
| wish work how | prompt an agent? | 0 |

Lines never held up: 18 of 21.

Counting notes: a `{words}` line is matched by its shape, so "{words} lol" also counts the reply line "[hehe] {words} lol", and "<3" counts the love reply as well as the met pet wish. The bare `{words}` line can't be told apart and isn't counted. Lines tagged `nobrain`, `night`, `friday`, a holiday, `cookie` or `pizza` can't show in most scenarios, so their zero says little.

## 8. What the judge and the plans already say


Judge verdicts over the 9 runs: 628 reasonable, 121 odd, 57 unreasonable. Latest two (t1, t2): 99 reasonable, 11 odd, 0 unreasonable each. The nov8 run had no judge (`plan/TODO.md:70`).

| Note | Where |
|---|---|
| "proud finishes nearly everywhere", and bland words such as "Verify" and "Trial" | `plan/v1-buddy.md:94-95`. The data agrees: proud is 89% of long and very long finishes in the current build, and at long finishes 7 words (Finish, Cleared, Done, Finito, Success, Finished, Complete) are 84 of the 98 things said |
| "168 of 581 faces in the last run matched the one before" (29%), before the faces guideline | `plan/TODO.md:247-249`. My count by scenario: 34 to 45% in every run (A 166/426, d2a 180/481, t1 174/495, t2 143/431, nov8 147/425). The guideline moved it from about 37% to 34%. My base differs from the note's (I count only Moments with a face and compare within a scenario) |
| "Idle may now be too quiet": 36 of 83 idle check-ins have a moment, 8 a real face, 5 a word | `plan/TODO.md:101`, `plan/v1-buddy.md:92-93`. The data agrees: in t2 and nov8, 166 idle check-ins give 96 no Moment, 56 a sign with no face, 14 lonely. Before that (t1) 81 of 82 had a face, which the judge called too busy. Idle went from one face every time (bored, then comfy and tired) to almost none |
| "Notices may be too faint": `stretch` and `rough` play with no visible change; "claude sits idle" is 13 of 17 notices and reads as a flat report | `plan/TODO.md:103`, `plan/v1-buddy.md:89-91`. Signs seen: "claude sits idle" 24, "still up?" 3, "rough one" 1, "i'm here" 22 (all as a comfort reply). Never: "{agent}'s waiting", "{agent}'s done", "stretch?", "legs ok?", "water break?", "bed?", "getting late..." |
| A lonely face can say "Cozy": `say` doesn't know the face | `plan/TODO.md:99` |
| Flatness before and after guidelines: judge 81/11/9 to 83/15/3, mood moves 300 to 279; "removing Examples" worked because "Jev was copying them" | `plan/TODO.md:159-168` |
| Halloween and day 50 get the same hello; a finish just after its fix still goes big | `plan/TODO.md:168` |
| Evals 179 to 186 pass even if a notice's sign never shows | `plan/TODO.md:197-200` |
| "Jev rarely speaks over an act from a calm mood." Work acts: 42 passes, 0 Moments, in every run | `plan/TODO.md:357` |
| Level A's 7 confirmed unreasonable runs: 11, 19, 47, 90, 91, 96, 140 | `plan/TODO.md:359` |
| "calm goes to annoyed at your frustration ... annoyed has no way out at a check passing ... so Boop frowns through a success" | `plan/TODO.md:408-414`. The data agrees: calm > annoyed is the most common move (285), and the judge notes "huge proud over an annoyed mood" (d2b 20, 48) |
| Takes whose meaning reads wrong: "Yep" as tickled, "Failed" as upset, "Search" at a compaction, "Restart" as retry, "Mwahaha" for a typo fix | `plan/TODO.md:415-419` |
| An approval's Example cheers ("pleased, says glad"), noise on a day of approvals | `plan/TODO.md:420-423` |
| The idle `tower` pastime is hard to read | `plan/TODO.md:355` |
| Wishes: only two wordings ever appear, "hold BOOT, say hi?" and "stroke my face?"; "hold BOOT and talk" reads as an instruction | judge summaries in `~/.boopdev/day2/verdicts-d2a.jsonl:102`, `~/.boopdev/tonight/verdicts-t1.jsonl:111`, `verdicts-t2.jsonl:111` |

The judge's own whole-run summaries (the last line of each verdicts file) name the same slots in every run:

- Working check-ins: "determined 50 of 61" (t0), "determined 43 of 60 ... often three or more in a row" (t1), "58 determined faces" (t2).
- Finishes: "proud with success is the near-universal answer, and its words come from a small interchangeable pool" (t2).
- Idle: "bored at 70 of 70" (d2a), "comfy 40, tired 16, lonely 15" (t0), "8 of 83, all lonely" (t2).
- Quick wins: "happy, success, silent, small 28 times" (d2a).
- Pokes: "reuse Oh, Boop, Whoa, Tickles, Yep whatever the mood" (t0).
- Returns: "happy, wake up, 'Howdy', medium" for an ordinary day, Halloween and day 50 alike (d2a).

Words in the judge's notes, and how often the note was odd or unreasonable: "same" 18 of 21, "flat" 8 of 10, affectionate 9 of 14, bored 10 of 16, lonely 28 of 69, sign 29 of 74. Proud is named most (160 notes) and is wrong least often (26, 16%): proud is not a wrong pick, it is the only pick.

## 9. Pairs the data says are interchangeable

Three measures. (a) **Swaps**: the same step of the same scenario got face X in one run and face Y in another (646 steps seen in 5 or more runs; only 22% got the same face in every run, 39% the same mood). (b) **Close calls**: in the latest run, the two had the top two probabilities and the runner-up had 0.20 or more. (c) **Same events**: the cosine of the two faces' use across event kinds.

| Pair | Swaps (a) | Close calls (b) | Same events (c) | Reading |
|---|---:|---:|---:|---|
| happy / pleased (faces) | 132, 64% of pleased's uses | 13 | 0.91 | The clearest merge. Both are the short finish's face; which one shows depends on the build (pleased 0 in A and d2a, 63 in C) |
| bored / tired / comfy (faces, idle) | bored/comfy 70, bored/tired 48, comfy/tired 11 | none/tired 5, comfy/none 11 | bored/tired 1.00, comfy/bored 0.89 | One idle face. Each build picked a different one: bored (A, C, d2a), comfy and tired (d2b, t0, t1), none (t2, nov8). Never two in one build |
| annoyed / irritated (faces and moods) | faces 67 (24%), moods 36 (24%) | faces 4, grumpy/irritated 9, moods 5 and 10 | check failed: annoyed 114, irritated 99 | Three steps of "cross" (annoyed, irritated, grumpy) that Jev does not separate. Irritated as a mood has only 3 edges in |
| determined / hopeful / engaged (faces, working) | determined/engaged 42, determined/hopeful 16 (47% of hopeful) | determined/engaged 12, engaged/hopeful 7 | determined/hopeful 0.98, engaged/determined 0.87 | One working check-in face |
| calm / no Moment (prompts and turn starts) | 139 | calm/none 54 | | A calm small silent face at a plain prompt is the same as nothing. The judge calls it "a bare small calm face" |
| wounded / speechless / confused / skeptical (faces, your words) | few | | 0.93 to 1.00 | All four only answer your words. Speechless 19, confused 15, skeptical 23 against wounded 68 |
| calm / happy (moods) | 267, 34% of happy's passes | 58 | | The most common mood disagreement: after a win, some builds lift to happy and some stay calm |
| calm / engaged (moods) | 92, 32% of engaged's passes | 77, the most common close call | | Engaged is "calm while working". B and C almost never used it (2 and 4 passes) |
| excited / happy (moods and faces) | moods 65 (19%), faces 19 (25% of excited) | moods 22, faces 5 | | Excited as a mood is entered from a very long finish (143 of 197 moves in) and fades to happy (70) |
| calm / lonely (moods) | 40, 47% of lonely's passes | | | Lonely comes or not by build: 16 passes in d2a and t0, 4 in t2 and nov8 |
| calm / comfy (moods) | | 44 | | Comfy is often the runner-up to calm and almost never wins: summed probability 18.7, chosen 3 times |
| calm / lazy (moods) | 12, 75% of lazy's passes | | | Lazy only ever replaced calm, in one run |
| happy / proud (faces) | 79 (20%) | 7 | | At a long finish or a check passing after failing |
| excited / proud (moods) | 13 | 11 | | After a very long finish |
| curious / mischievous, amused / happy (faces) | 24, 16 | amused/pleased 6 | | Small |

Faces with one event only, so they add no choice: bored (idle check-in, 161 of 161), wounded (your words, 68 of 68), confused (your words, 15 of 15), tired (idle, 64 of 65), hopeful (working check-in, 33 of 34), frightened (a prompt, 7 of 8).

## 10. Pastimes

Rows: 52. By look: {'kWorking': 19, 'kIdle': 24, 'kNeedsYou': 4, 'kAsleep': 5}. By growth stage that first knows it: {1: 28, 2: 9, 3: 15}. Moves: coffee-reach, melt, stretch-break. Tag rows: busy-typing (busy), frantic-typing (frantic), pastime:morning-stretch (morning), pastime:night-drowse (night), pastime:party-bounce (party|newyear|lunar|programmers), pastime:friday-sway (friday), pastime:winter-shiver (winter), pastime:halloween-wobble (halloween), pastime:valentines-swoon (valentines), deep-snore (night).

Assumed day: Working 131 min in 40 stretches [(40, 20), (180, 12), (420, 6), (1200, 2)]; Idle 260 min in 40 stretches [(60, 20), (300, 12), (900, 6), (2700, 2)]; NeedsYou 13 min in 10 stretches [(20, 6), (90, 3), (400, 1)]; Asleep 90 min in 2 stretches [(1800, 1), (3600, 1)]. Share of the time a pastime may be dealt (no live call drawn, no Moment, no finger): {'kWorking': 0.5, 'kIdle': 0.9, 'kNeedsYou': 1.0, 'kAsleep': 1.0}. No calendar tag on, not busy or frantic, not morning. A bit or take with no clip is taken as 3 s. 400 simulated days each.

| pastime | look | needs | stage | move | clip s | per day, Hatchling (stage 1) | per day, Sprout (2) | per day, Buddy or Chonk (3+) |
|---|---|---|---:|---|---:|---:|---:|---:|
| snore-bubble | Asleep | wait 240s | 1 |  | 5.2 | 188.8 | 142.9 | 142.3 |
| sheep | Asleep | wait 120s | 2 |  | 6.0 | 0.0 | 123.4 | 123.9 |
| roll-over | Asleep | wait 60s | 1 |  | 4.2 | 211.8 | 120.1 | 120.5 |
| snuggle | Idle | tier5 (600s) | 1 |  | 6.0 | 191.7 | 141.8 | 92.3 |
| snooze | Idle | tier5 (600s) | 2 |  | 6.0 | 0.0 | 142.0 | 92.1 |
| daydream | Idle | tier5 (600s) | 3 |  | 6.0 | 0.0 | 0.0 | 91.2 |
| book | Idle | tier3 (120s) | 3 |  | 5.6 | 0.0 | 0.0 | 80.4 |
| water | Idle | tier3 (120s) | 3 |  | 4.4 | 0.0 | 0.0 | 80.0 |
| game | Idle | tier3 (120s) | 3 |  | 5.2 | 0.0 | 0.0 | 80.0 |
| sneeze-and-shake | Idle | tier1 (30s) | 1 |  | 3.0 | 222.8 | 100.3 | 70.2 |
| hop | Idle | tier1 (30s) | 1 |  | 2.4 | 222.2 | 100.2 | 69.6 |
| hopeful | Idle | tier1 (30s) | 1 |  | 2.6 | 222.5 | 99.6 | 69.5 |
| look-around | Idle | tier1 (30s) | 1 |  | 3.2 | 222.3 | 100.6 | 69.5 |
| yawn-and-settle | Idle | tier1 (30s) | 1 |  | 3.0 | 222.6 | 100.0 | 69.4 |
| bubble | Idle | tier2 (60s) | 2 |  | 4.4 | 0.0 | 213.3 | 68.7 |
| doodle | Idle | tier2 (60s) | 2 |  | 4.6 | 0.0 | 213.5 | 68.0 |
| dream | Asleep | wait 1800s | 1 |  | 3.0 | 60.8 | 59.5 | 59.2 |
| brb | Idle | tier4 (300s) | 3 |  | 6.0 | 0.0 | 0.0 | 41.9 |
| tower | Idle | tier4 (300s) | 3 |  | 5.6 | 0.0 | 0.0 | 41.9 |
| dance | Idle | tier4 (300s) | 3 |  | 5.2 | 0.0 | 0.0 | 41.3 |
| plane | Idle | tier4 (300s) | 3 |  | 5.2 | 0.0 | 0.0 | 41.2 |
| wave | NeedsYou | wait 30s | 1 |  | 2.8 | 39.8 | 39.9 | 39.9 |
| done-beat | Working | tier1 (30s) | 1 |  | 2.6 | 93.9 | 38.1 | 30.5 |
| hum | Working | tier1 (30s) | 1 |  | 3.6 | 94.1 | 37.9 | 30.5 |
| peek | Working | tier1 (30s) | 1 |  | 2.4 | 93.5 | 37.9 | 30.3 |
| sip | Working | tier1 (30s) | 1 |  | 3.2 | 94.7 | 38.1 | 30.3 |
| nod | Working | tier2 (60s) | 2 |  | 3.0 | 0.0 | 43.4 | 24.8 |
| ponder | Working | tier2 (60s) | 2 |  | 3.4 | 0.0 | 43.1 | 24.6 |
| read | Working | tier2 (60s) | 2 |  | 5.0 | 0.0 | 43.4 | 24.5 |
| snack | Working | tier4 (300s) | 2 |  | 3.6 | 0.0 | 43.7 | 22.9 |
| refill | Working | tier4 (300s) | 3 |  | 4.2 | 0.0 | 0.0 | 22.9 |
| stretch | Working | tier4 (300s) | 2 |  | 2.6 | 0.0 | 44.0 | 22.4 |
| sticky | Working | tier3 (120s) | 3 |  | 3.2 | 0.0 | 0.0 | 22.3 |
| bop | Working | tier3 (120s) | 3 |  | 4.0 | 0.0 | 0.0 | 22.2 |
| drum | Working | tier3 (120s) | 3 |  | 3.0 | 0.0 | 0.0 | 22.1 |
| phones-on | Working | tier3 (120s) | 1 |  | 2.4 | 19.9 | 19.9 | 19.9 |
| coffee-reach | Working | tier3 (120s) | 3 | move | 5.0 | 0.0 | 0.0 | 14.3 |
| tap | NeedsYou | wait 120s | 1 |  | 2.6 | 12.8 | 12.7 | 12.7 |
| stretch-break | Working | tier5 (600s) | 3 | move | 10.5 | 0.0 | 0.0 | 10.2 |
| melt | Working | tier4 (300s) | 3 | move | 6.2 | 0.0 | 0.0 | 7.2 |
| watch | NeedsYou | wait 300s | 1 |  | 4.2 | 3.8 | 3.8 | 3.8 |
| busy-typing | Working | tag busy | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| frantic-typing | Working | tag frantic | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:morning-stretch | Idle | tag morning | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:night-drowse | Idle | tag night | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:party-bounce | Idle | tag party|newyear|lunar|programmers | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:friday-sway | Idle | tag friday | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:winter-shiver | Idle | tag winter | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:halloween-wobble | Idle | tag halloween | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| pastime:valentines-swoon | Idle | tag valentines | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |
| drowsy | NeedsYou | wait 600s | 1 |  | 5.2 | 0.0 | 0.0 | 0.0 |
| deep-snore | Asleep | tag night | 1 |  | 3.0 | 0.0 | 0.0 | 0.0 |

Stage 1: about 2218 pastimes a day; 17 of 52 rows at least once a day. Under once a day: ponder, read, nod, bop, drum, sticky, coffee-reach, refill, snack, melt, stretch-break, stretch, busy-typing, frantic-typing, bubble, doodle, book, game, water, brb, tower, dance, plane, snooze, daydream, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, sheep, deep-snore

Stage 2: about 2103 pastimes a day; 26 of 52 rows at least once a day. Under once a day: bop, drum, sticky, coffee-reach, refill, melt, stretch-break, busy-typing, frantic-typing, book, game, water, brb, tower, dance, plane, daydream, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, deep-snore

Stage 3: about 2051 pastimes a day; 41 of 52 rows at least once a day. Under once a day: busy-typing, frantic-typing, pastime:morning-stretch, pastime:night-drowse, pastime:party-bounce, pastime:friday-sway, pastime:winter-shiver, pastime:halloween-wobble, pastime:valentines-swoon, drowsy, deep-snore

### When a calendar tag is on (idle stretches of the same assumed day, stage 3)
| tags on | tag row | its share of idle pastimes | idle pastimes |
|---|---|---:|---:|
| morning | pastime:morning-stretch | 42% | 1341 a day |
| friday | pastime:friday-sway | 42% | 1341 a day |
| morning+friday | pastime:morning-stretch | 31% | 1389 a day |
| morning+friday | pastime:friday-sway | 32% | 1389 a day |
| night | pastime:night-drowse | 42% | 1341 a day |

How a pastime is picked (`face.cpp`, `GelFace::deal`): after each one the face rests 4 to 10 s (`kRestMinMs`, `kRestMaxMs`), then deals one that fits the look (working, idle, needs you, asleep), the growth stage and the tier or wait. The rows of the highest tier that fits are "newest" and get 60% (`kNewestPct`); the older ones share 40%; never the same twice in a row. A row that needs a tag ranks above every tier while its tag is on. A move (coffee-reach, melt, stretch-break) waits 90 s after the last move. Nothing is dealt while a finger is down, a work act plays or a live call is drawn in the work stream.

Tiers are the Mac's clock of the working stretch or of the rest: tier1 30 s, tier2 60 s, tier3 2 min, tier4 5 min, tier5 10 min (`Tags.swift:28-34`). In the demo recordings, `when` carried tier5 30 times, tier3 25, tier1 21, tier4 4, tier2 3 (of 248 `state` messages).

What the estimate says:

- About 2,000 pastimes a day, one every 11 s or so. No buyer watches 2,000. Variety matters per glance, not per day.
- 38% of this day's idle minutes are past 10 minutes (tier5), and there the three tier5 idle rows (snuggle, snooze, daydream) get 60% of the deals. A Hatchling has one of them, snuggle, and it plays about 190 times a day.
- The four tier1 working rows (sip, peek, hum, done-beat) carry all work for a Hatchling: about 94 plays each a day.
- 15 rows are held back to stage 3: bop, drum, sticky, coffee-reach, refill, melt, stretch-break, book, game, water, brb, tower, dance, plane, daydream. That is 2 weeks at least. All three moves are in this group.
- The tag rows are either off all day or very loud: about 42% of idle pastimes while the tag is on. `winter` is on only 24 to 26 December (`Days.swift:30`). `busy` and `frantic` are the board's own tags (`Tags.swift:7`); I did not trace their rule, so those two rows are not estimated.
- `drowsy` needs a request left waiting 10 minutes and `watch` 5 minutes; `dream` needs 30 minutes asleep.

All of this is a model of the code, not a measurement. No log of pastimes played on a board exists on disk. The day's mix (131 minutes working in 40 turns, 260 idle, 13 needs you, 90 asleep) and the share of time a deal is allowed (50% at work) are my assumptions; change `DAY` and `FREE` in `scripts/pastimes.py` to try others. The ranking within a look is robust to them; the per-day counts are not.

## 11. Demo recordings

### boop pack, 14 recordings, 624 s in all
Files (length s, `do` messages): asks.json 45.76/11, demo.json 87/9, dismiss.json 28/4, finishes.json 46.64/11, halloween.json 19/7, handoff.json 30/8, helpers.json 21.84/9, hush.json 28.56/11, lonely.json 53/15, long-turn.json 63/4, talk-back.json 102/42, the-cheer.json 19.7/5, the-cuss.json 19.58/6, work-stream.json 60/10

**`do` designs**
| value | count |
|---|---:|
| react | 47 |
| call | 26 |
| task_complete | 24 |
| starting | 23 |
| listening | 14 |
| stop_listening | 14 |
| wake_up | 4 |

**`do` play rule**
| value | count |
|---|---:|
| next | 98 |
| if_free | 40 |
| now | 14 |

`do` args keys: {'ctx': 23, 'reason': 54, 'say': 71, 'mood': 71, 'loops': 71, 'outcome': 24, 'turn': 24, 'who': 24, 'sign': 18, 'ask': 1, 'reply': 14, 'a': 26, 'w': 26, 'as': 26, 'greeting': 3, 'show': 1}

**Emotion on a `do` (args.mood)**
| value | count |
|---|---:|
| happy | 15 |
| curious | 13 |
| pleased | 6 |
| proud | 6 |
| excited | 5 |
| annoyed | 4 |
| determined | 3 |
| engaged | 3 |
| mischievous | 2 |
| lonely | 2 |
| calm | 2 |
| disappointed | 1 |
| amused | 1 |
| affectionate | 1 |
| uneasy | 1 |
| relieved | 1 |
| tired | 1 |
| skeptical | 1 |
| comfy | 1 |
| hopeful | 1 |
| grumpy | 1 |

**Size as loops**
| value | count |
|---|---:|
| 1 | 32 |
| 2 | 31 |
| 3 | 6 |
| 4 | 2 |

**Variants**
| value | count |
|---|---:|

**Signs**
| value | count |
|---|---:|
| fav snack? | 1 |
| nom nom | 1 |
| snack time? | 1 |
| deploy failed | 1 |
| Happy Halloween! | 1 |
| *zips lips* | 1 |
| i can talk! | 1 |
| good, u? | 1 |
| claude: 4 min in | 1 |
| tests failed | 1 |
| 1 working, 1 idle | 1 |
| yay! | 1 |
| not now, busy | 1 |
| not my job | 1 |
| woo! | 1 |
| wheee | 1 |
| who knows? | 1 |
| see ya! | 1 |

**Voice takes**
| value | count |
|---|---:|
| None | 12 |
| phase1.borrowed.andiamo__curious__contained | 2 |
| phase1.nonverbal.delight.ha__happy__contained | 2 |
| phase1.nonverbal.delight.heh__happy__contained | 2 |
| phase1.nonverbal.delight.eep__happy__contained | 2 |
| phase1.word.begin.ready__curious__contained | 2 |
| previous.pfft | 2 |
| previous.heh | 2 |
| phase1.nonverbal.delight.mwahaha__happy__contained | 2 |
| phase1.phrase.pride.heh-obviously__proud__contained | 2 |
| phase1.word.begin.start__curious__contained | 2 |
| phase1.nonverbal.delight.mm-hm__happy__contained | 2 |
| phase1.word.begin.launch__curious__contained | 2 |
| phase1.word.attention.hello__happy__contained | 1 |
| phase1.word.begin.awake__curious__contained | 1 |
| phase1.phrase.celebrate.big-tiny-win__excited__contained | 1 |
| phase1.borrowed.evviva__happy__contained | 1 |
| phase1.word.celebrate.bravo__happy__contained | 1 |
| phase1.word.celebrate.nice__happy__contained | 1 |
| phase1.word.setback.uh-oh__determined__contained | 1 |
| phase1.nonverbal.delight.heh__proud__contained | 1 |
| phase1.word.poke.oh__proud__contained | 1 |
| phase1.word.delegate.assemble__excited__contained | 1 |
| phase1.word.celebrate.sweet__proud__contained | 1 |
| phase1.word.begin.onward__curious__contained | 1 |
| placeholder.word.talk-unhush.free__happy__contained | 1 |
| phase1.word.attention.hello__sad__contained | 1 |
| phase1.word.idle.hullo__sad__contained | 1 |
| phase1.nonverbal.delight.whee__happy__contained | 1 |
| phase1.phrase.pride.nailed-it__proud__contained | 1 |
| placeholder.nonverbal.talk-hello.oh__happy__contained | 1 |
| phase1.borrowed.vamos__curious__contained | 1 |
| phase1.nonverbal.deflate.oh__annoyed__contained | 1 |
| phase1.nonverbal.delight.ooh__calm__contained | 1 |
| placeholder.nonverbal.talk-thanks.hehe__proud__contained | 1 |
| phase1.nonverbal.delight.hehehe__happy__contained | 1 |
| placeholder.phrase.talk-thanks.team-effort__excited__contained | 1 |
| placeholder.word.talk-dance.party__excited__contained | 1 |
| phase1.nonverbal.ponder.hm__curious__contained | 1 |
| placeholder.nonverbal.talk-bye.mwah__calm__contained | 1 |
| phase1.word.test.probe__determined__contained | 1 |
| phase1.phrase.celebrate.winner-winner__excited__contained | 1 |
| phase1.word.begin.launch__calm__contained | 1 |
| phase1.nonverbal.frustration.argh__annoyed__contained | 1 |
| phase1.word.setback.oops__determined__contained | 1 |
| phase1.explicit.crap__grumpy__contained | 1 |
| phase1.word.begin.launch__engaged__contained | 1 |
| phase1.phrase.pride.smooth-operator__proud__contained | 1 |

**Narration (reason)**
| value | count |
|---|---:|
| new claude thread | 18 |
| you asked claude | 13 |
| claude started | 5 |
| tests failed | 5 |
| tests pass | 3 |
| quiet for 1 h | 2 |
| Boop will remember | 1 |
| push went out | 1 |
| you were away 10 h | 1 |
| you poked Boop | 1 |
| no agents open | 1 |
| you were away 26 h | 1 |
| no touch in 2 h | 1 |
| you stroked Boop | 1 |

**`state` mood (messages)**
| value | count |
|---|---:|
| calm | 187 |
| proud | 19 |
| determined | 11 |
| happy | 10 |
| annoyed | 8 |
| lazy | 4 |
| lonely | 3 |
| engaged | 3 |
| comfy | 1 |
| excited | 1 |
| grumpy | 1 |

Seconds in each mood: calm 410, proud 109, happy 36, lazy 16, determined 12, lonely 9, annoyed 9, excited 6, grumpy 6, comfy 6, engaged 4

**`state` base (Doing)**
| value | count |
|---|---:|
| working | 158 |
| idle | 70 |
| asleep | 20 |

**`state` act (activity)**
| value | count |
|---|---:|
| testing | 35 |
| tool_use | 17 |
| terminal | 11 |
| delegating | 9 |
| analyzing | 8 |
| planning | 4 |

**`when` tags**
| value | count |
|---|---:|
| day | 230 |
| tier5 | 30 |
| tier3 | 25 |
| tier1 | 21 |
| evening | 11 |
| halloween | 8 |
| morning | 7 |
| hushed | 4 |
| tier4 | 4 |
| tier2 | 3 |

**work acts (wact)**
| value | count |
|---|---:|
| tests | 49 |
| push | 7 |
| build | 4 |

`state` keys: {'t': 248, 'base': 248, 'mood': 248, 'busy': 248, 'vol': 248, 'when': 248, 'idle': 86, 'act': 84, 'calls': 117, 'wact': 60, 'attn': 4, 'helpers': 7, 'todo': 11, 'list': 1}

### pixel pack, 11 recordings, 432 s in all
Files (length s, `do` messages): context-wall.json 37.72/9, demo.json 87.01/9, good-morning.json 24/7, halloween.json 19/7, handoff.json 30/8, hanging.json 47.01/4, hello.json 16.91/4, helpers.json 21.84/9, landing.json 110.72/29, the-cheer.json 18.62/5, the-cuss.json 19.58/6

**`do` designs**
| value | count |
|---|---:|
| react | 34 |
| call | 19 |
| starting | 16 |
| task_complete | 13 |
| listening | 6 |
| stop_listening | 6 |
| wake_up | 3 |

**`do` play rule**
| value | count |
|---|---:|
| next | 67 |
| if_free | 24 |
| now | 6 |

`do` args keys: {'ctx': 16, 'reason': 43, 'say': 47, 'mood': 47, 'loops': 47, 'a': 19, 'w': 19, 'as': 19, 'outcome': 13, 'turn': 13, 'who': 13, 'sign': 3, 'reply': 6, 'greeting': 3}

**Emotion on a `do` (args.mood)**
| value | count |
|---|---:|
| happy | 8 |
| excited | 6 |
| calm | 5 |
| determined | 5 |
| proud | 5 |
| curious | 4 |
| annoyed | 3 |
| grumpy | 3 |
| mischievous | 2 |
| confused | 1 |
| pleased | 1 |
| irritated | 1 |
| whiny | 1 |
| engaged | 1 |
| hopeful | 1 |

**Size as loops**
| value | count |
|---|---:|
| 2 | 30 |
| 1 | 8 |
| 3 | 8 |
| 4 | 1 |

**Variants**
| value | count |
|---|---:|

**Signs**
| value | count |
|---|---:|
| deploy failed | 1 |
| Happy Halloween! | 1 |
| just started | 1 |

**Voice takes**
| value | count |
|---|---:|
| None | 47 |

**Narration (reason)**
| value | count |
|---|---:|
| new claude thread | 13 |
| you asked claude | 8 |
| tests failed | 4 |
| tests pass | 4 |
| you poked Pixel | 4 |
| claude compacted | 2 |
| you were away 10 h | 2 |
| claude started | 2 |
| push went out | 1 |
| quiet for 10 min | 1 |
| quiet for 1 h | 1 |
| you poked Pixel x3 | 1 |

**`state` mood (messages)**
| value | count |
|---|---:|
| calm | 98 |
| determined | 23 |
| happy | 23 |
| proud | 10 |
| annoyed | 9 |
| excited | 8 |
| grumpy | 6 |
| engaged | 5 |
| irritated | 3 |
| sad | 1 |

Seconds in each mood: calm 213, happy 68, proud 43, determined 38, excited 19, grumpy 17, annoyed 10, engaged 9, sad 8, irritated 6

**`state` base (Doing)**
| value | count |
|---|---:|
| working | 128 |
| idle | 43 |
| asleep | 15 |

**`state` act (activity)**
| value | count |
|---|---:|
| testing | 32 |
| terminal | 11 |
| delegating | 11 |
| analyzing | 8 |
| tool_use | 8 |

**`when` tags**
| value | count |
|---|---:|
| day | 170 |
| tier1 | 22 |
| tier2 | 16 |
| night | 9 |
| halloween | 7 |
| evening | 5 |
| tier5 | 4 |
| morning | 2 |

**work acts (wact)**
| value | count |
|---|---:|
| tests | 50 |
| push | 7 |
| build | 4 |

`state` keys: {'t': 186, 'base': 186, 'mood': 186, 'busy': 186, 'vol': 186, 'when': 186, 'idle': 47, 'act': 70, 'calls': 103, 'wact': 61, 'attn': 7, 'helpers': 8}

Notes: no `do` in any recording carries a `variant` (the board picks the variation, so the recordings can't count them). The emotions here are hand-written brain steps, so they show what the authors wanted to show off: happy and curious lead, and the demos use 3 faces Jev never picked (disappointed, uneasy, whiny).

## 12. The scenario files

Groups: {'must': 20, 'feel': 111, 'scripted': 11}. Steps: 752, with an `expect`: 125. Start mood: {'calm': 123, 'happy': 1, 'determined': 1, 'sad': 3, 'irritated': 2, 'lonely': 1, 'grumpy': 7, 'engaged': 1, 'excited': 1, 'surprised': 1, 'comfy': 1}. Talk: {'normal': 137, 'quiet': 1, 'chatty': 4}.

Step events: turn started 194, turn finished 132, command 103, said 77, session started 50, wait 40, turn failed 20, gesture 20, poke 19, away 18, back 17, pokes 15, lock 11, needs you 5, wish 5, to-do list 4, unlock 4, press 4, world 3, helper started 3, helper returned 3, edit 2, hush 1, answered 1, compact 1

Whole-run checks used: moves_on_graph 16, max_quiet_working 4, reactions 3, words_said 2

### Each mood and emotion in the scenario files
| id | lasting | steps expecting it as `mood` | scenarios | steps accepting it as `react` | scenarios | named in feel briefs (judge+reasonable) | named in "unreasonable" | named in must cases | scripted `brain` face | starts a scenario |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| happy | yes | 3 | 3 | 11 | 8 | 31 | 3 | 5 | 10 | 1 |
| calm | yes | 2 | 2 | 8 | 4 | 33 | 0 | 3 | 7 | 123 |
| excited | yes | 3 | 3 | 12 | 7 | 18 | 4 | 3 | 14 | 1 |
| proud | yes | 2 | 2 | 11 | 6 | 18 | 2 | 4 | 12 | 0 |
| pleased |  | 0 | 0 | 6 | 4 | 24 | 2 | 1 | 3 | 0 |
| curious | yes | 2 | 2 | 6 | 4 | 19 | 0 | 1 | 7 | 0 |
| annoyed | yes | 4 | 3 | 7 | 6 | 16 | 0 | 5 | 11 | 0 |
| relieved |  | 0 | 0 | 7 | 5 | 16 | 0 | 2 | 1 | 0 |
| irritated | yes | 2 | 2 | 8 | 6 | 10 | 0 | 3 | 8 | 2 |
| determined | yes | 0 | 0 | 5 | 4 | 13 | 0 | 2 | 9 | 1 |
| sad | yes | 1 | 1 | 7 | 5 | 10 | 35 | 6 | 5 | 3 |
| engaged | yes | 0 | 0 | 5 | 2 | 11 | 0 | 1 | 1 | 1 |
| grumpy | yes | 1 | 1 | 6 | 5 | 9 | 4 | 3 | 7 | 7 |
| affectionate |  | 0 | 0 | 8 | 6 | 8 | 0 | 1 | 4 | 0 |
| comfy | yes | 0 | 0 | 1 | 1 | 11 | 1 | 1 | 1 | 1 |
| lazy | yes | 2 | 1 | 0 | 0 | 9 | 0 | 1 | 0 | 0 |
| bored |  | 0 | 0 | 0 | 0 | 10 | 2 | 0 | 2 | 0 |
| mischievous |  | 0 | 0 | 6 | 4 | 4 | 0 | 1 | 5 | 0 |
| amused |  | 0 | 0 | 6 | 4 | 4 | 2 | 1 | 3 | 0 |
| wounded | yes | 2 | 1 | 5 | 4 | 1 | 0 | 2 | 1 | 0 |
| hopeful |  | 0 | 0 | 5 | 3 | 3 | 0 | 1 | 1 | 0 |
| shy |  | 0 | 0 | 0 | 0 | 7 | 0 | 0 | 0 | 0 |
| whiny |  | 0 | 0 | 3 | 2 | 3 | 0 | 1 | 0 | 0 |
| lonely | yes | 1 | 1 | 0 | 0 | 5 | 9 | 2 | 1 | 1 |
| surprised | yes | 1 | 1 | 1 | 1 | 3 | 0 | 1 | 4 | 1 |
| baffled |  | 0 | 0 | 0 | 0 | 3 | 0 | 1 | 1 | 0 |
| skeptical |  | 0 | 0 | 1 | 1 | 2 | 0 | 0 | 2 | 0 |
| disappointed |  | 0 | 0 | 1 | 1 | 1 | 1 | 1 | 0 | 0 |
| uneasy |  | 0 | 0 | 1 | 1 | 1 | 0 | 0 | 2 | 0 |
| angry |  | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 |
| stunned |  | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| confused |  | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 1 | 0 |
| tired |  | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 0 |
| uncomfortable |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| crying |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| scared |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| frightened |  | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| speechless |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| embarrassed |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| exhausted |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| overwhelmed |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| disgusted |  | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

Negated (`!x`): react {'none': 6, 'happy': 3, 'annoyed': 2}; mood {'happy': 2, 'lonely': 2, 'sad': 1}; say {'glad': 2, 'none': 1, 'swear': 3}.

Other feeling words in feel briefs (scenarios): pride 6, relief 2, joy 2, glee 2, sulk 3, huff 7, cross 10, despair 1, swear 2, lonel 5, bored 10, affection 8, cheek 11

`expect.say` values (steps): tickled 6, upset 5, glad 4, shaken 4, none 3, hello 2, quiet 2, done 1

`expect.move` values (steps): status 9, failure 7, success 6, none 6, yes 3, thanks 3, huh 3, hello 2, love 2, ouch 2, comfort 2, nap 2, hush 2, no 2, notme 2, bye 2, wake up 2, hehe 1, dance 1, reply 1, unhush 1, wave 1

`expect.intensity` values (steps): medium 3, big 2, huge 2, small 2

`expect.sign` values: hi, world! 2, a friend! 2, none 1, some 1, 4 min in 1, tests failed 1, done! 1, codex: 2 min in 1, 1 working, 1 idle 1, 2 resting 1, stroke my face 1, boop back! 1, who was that? 1, we shipped! 1, thanks, all! 1

`expect.said` values: none 4, some 4

Scripted `brain` answers, react.face: none 15, excited 14, proud 12, annoyed 11, happy 10, determined 9, irritated 8, curious 7, calm 7, grumpy 7, sad 5, mischievous 5, surprised 4, affectionate 4, pleased 3, amused 3, uneasy 2, bored 2, skeptical 2, lonely 1, relieved 1, comfy 1, wounded 1, confused 1, engaged 1, hopeful 1, baffled 1

Scripted `brain` answers, say: glad 15, upset 7, none 5, tests 2, shaken 2, work 1, start 1, command 1, swear 1, looking 1

Scripted `brain` answers, react.move: none 31, success 31, wake up 8, failure 6, status 6, comfort 4, hello 3, nap 2, ouch 2, love 2, wave 2, reply 2, notice 1, notme 1, thanks 1, hehe 1, bye 1, no 1

Scripted `brain` answers, react.intensity: small 15, big 4, medium 4

Scripted `brain` answers, react.sign: none 4, a fix 2, dreamt of u 2, stroke my face? 2, still broken 1, bye bye code 1, bug hunt 1, new thing 1, tidy time 1, tests 1, friday 1, docs 1, hmm 1, reading 1, sure 1, careful 1, thank you 1, after this 1, at it 3 min 1, ur job 1, fine 1, hello 2 u 1, good, u? 1, right here 1, 1 working 1, love 1, good night 2 u 1, bad dream 1, u stay up late fridays 1, claude's waiting 1, stretch? 1, i'm here 1, still up? 1

Scripted `brain` answers, mood: calm 24, irritated 13, annoyed 12, grumpy 12, excited 8, sad 7, proud 6, happy 5, determined 3, lonely 3, comfy 3, engaged 3, curious 1, surprised 1, wounded 1

Reading: the scenarios never name 8 faces at all (uncomfortable, crying, scared, speechless, embarrassed, exhausted, overwhelmed, disgusted), and name frightened only as "unreasonable". They ask for whiny (3 steps), disappointed (1), uneasy (1) and shy (7 briefs), and Jev gave none of them once. "Sad" is named in 35 "unreasonable" texts: the briefs mostly use it to say what Boop must not be.

## 13. The scripted run

`boopdev eval --scripted`: 142 of 142 pass, 792 passes, all by the expect brain. Its picks: face excited 618 of 792, `say` start 729, size small 777, mood calm 586. Those are the expect brain's filler for steps with no `expect` (the first option that fits), not behaviour. See section 14.

## 14. The limits of each source

| Source | It can show | It cannot show |
|---|---|---|
| Scripted run and timeline | Which events wake the brain (792 passes for 752 steps), that every expected mood lies on a path of the graph, the code's rules (what's offered, the screen, tiers, counts) | Anything about how often Jev picks a value. Its faces and words are filler |
| The 9 Jev runs | What Jev picks at each kind of event, with real prompts and the real outputs; which values never win; how stable a pick is across builds | Per-day frequency: the scenarios choose the events (77 things said to Boop in 142 scenarios, far more than a real day; 3 helper steps, so helper words are barely tried). 19 scenarios start in a non-calm mood. 6 builds and 3 prompt sizes are mixed. Jev is near-deterministic, so 9 runs are closer to 4 or 5 samples. The Moment goes to a fake device that always plays it, so nothing is lost to the queue, to face down or to a busy board. The text said is recorded, not the take's id |
| The raw run file | Every option's probability at 748 passes: what was never even close | One run of one build. It will be cleared from `/tmp/boop-eval` |
| Judge verdicts | Where a person-like reader sees sameness | The judge is a Claude session reading text, not someone looking at the board |
| Demo recordings | The wire: `do` designs, loops, takes' ids, `when` tags | Frequency: every answer is scripted by hand. No variants. 17 minutes in all |
| Scenario files | What the authors think matters | Nothing about use |
| Pastime estimate | Which rows a stage and tier can reach, and their order of frequency | Real counts: it is a model with an assumed day |
| Missing altogether | | Real use. The app keeps daily counts (`daily-counts.jsonl`, `Boop --counts`) and a transcript, but I did not read the owner's own state under `~/Library/Application Support/Boop` (out of bounds for this task). Those files are the only source that could turn these shares into per-day numbers |
