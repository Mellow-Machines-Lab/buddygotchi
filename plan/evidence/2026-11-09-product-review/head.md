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
| Pastimes, stage 1, ordinary day | 35 of 52 rows under once a day; 15 locked to stage 3, 9 to stage 2; `drowsy` needs a request left 10 minutes; 9 tag rows |
| Moods in scenario musts | determined, engaged, comfy, proud-as-start: no step expects `mood: determined`, `engaged` or `comfy` |

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
