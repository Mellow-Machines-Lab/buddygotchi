# Character Studio audit, and the cost of making a character

Date: 2026-11-09. Worktree: `/Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish` (branch `v1-polish`, HEAD `270ee70c`).
Research only. No repo file was changed. Screenshots: `/tmp/boop-review/studio/*.png` (32 files, 16 views x 2 packs, 1400 px wide, scale 1).

## Short answer

- The Studio is 16 views in 8 tabs. Its hand-written page is 2,990 lines. With its checks, data files, docs and its share of `charactergen.py`, it is about 6,900 lines.
- `packs.js` is **not** a git cost. Git ignores it. It takes 0.05 s to make. 86% of its 117,736 lines are two pretty-printed voice tables.
- A new character needs **nothing** from the Studio. The playbook's 7 steps do not use it once.
- The Studio is partly broken today, and nobody noticed for 8 days: the landing view is blank, the default pack's board preview does not load, and `check.cjs` cannot pass.
- Smallest useful Studio: one contact-sheet page (Matrix, with Scene as its detail) plus `charactergen.py --check`. That deletes about 4,200 hand-written lines.

## 1. The generated files

| File | Lines | Bytes | Made by | From | Time | In git? | Changes in git |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `packs.js` | 117,736 | 1,946,124 | `charactergen.py` `write_studio()` (`characters/charactergen.py:1181-1190`), on `--check` and `--stage` | each pack's `character.json`, steering, `mac/takes.tsv`, demos, evals, golden frames, references, review; `states.json`, `behavior.json`, `everyday.jsonl`; numbers read from Swift and C++ sources | 0.02 s checks + 0.03-0.04 s data and dump (measured in memory, 2 runs) | **No.** `.gitignore:79` | 0 commits since the ignore. It was tracked in 3 commits (2026-10-07 to 10-11), then removed |
| `prompts.js` | 2 | 1,543,310 | `boopdev prompts` (`internal/app/BoopDev/main.swift:299-354`); `make dev` runs it (`internal/tools/dev.sh:40`) | every eval scenario, run with the scripted brain | not measured (the command writes the file; it needs the Swift build) | **No.** `.gitignore:80` | 0 |
| `everyday.jsonl` | 913 | 21,273 | written by hand (a simulator scenario) | - | - | Yes | 1 commit |
| `board.svg` | 1 | 532 | written by hand (an icon) | - | - | Yes | 1 commit |

What fills `packs.js` (measured with `json.dumps(indent=1)`, as the tool writes it):

| Part | Lines | Share |
| --- | --- | --- |
| `voices.boop` (3,479 takes) | 50,038 | 42.5% |
| `voices.pixel` (3,586 takes) | 51,612 | 43.8% |
| `packs.boop` (evals 6,618; stills 2,462; demos 1,675; steering 627; moods 469) | 12,733 | 10.8% |
| `packs.pixel` | 2,098 | 1.8% |
| `behavior` | 1,024 | 0.9% |
| the rest (`states`, `everyday`) | about 230 | 0.2% |

- The "118,000 lines" number is a pretty-print effect. The same data as compact JSON is 1,199,745 bytes on one line.
- The two voice tables are near copies: 2,995 take ids are in both. CHARACTER.md §8 says Pixel "has a copy of the two built files".
- The page uses the take list in one view only (Voice).

Hand-written part, verified:

| File | Lines |
| --- | --- |
| `character.js` | 623 |
| `studio.js` | 492 |
| `studio.css` | 487 |
| `views.js` | 378 |
| `board.js` | 263 |
| `behavior.js` | 226 |
| `behavior.json` | 206 |
| `index.html` | 184 |
| `markdown.js` | 79 |
| `states.json` | 52 |
| **The page** | **2,990** |
| `everyday.jsonl` | 913 |
| `README.md` | 387 |
| `check.cjs` | 277 |
| `tests/studio.test.cjs` + `changed.json` | 233 |
| **All of `characters/studio/` in git** | **4,800** |

Outside the folder, for the Studio only:

- `charactergen.py`: about 560 of 1,397 lines (lines 629-1191), plus 132 lines of reference and review checks (467-598).
- `internal/characters/test_charactergen.py`: 705 lines, 44 tests; about 15 are Studio rules.
- `simulator/web/serve.py`: about 150 of 702 lines (`/review`, `/review-captures/`, `capture_names`, lines 330-370 and 496-605).
- Pack adapters: Boop 169 lines, Pixel 58 lines (`characters/<pack>/studio/adapter.js`).

Churn (`git log --oneline --since=2026-09-01 -- characters/studio | wc -l`):

- 33 commits of 294 in the repo since 2026-09-01 (11%) touch the Studio.
- Most-changed files: `README.md` 21, `studio.js` 11, `index.html` 10, `behavior.json` 10, `check.cjs` 9, `character.js` 9, `studio.css` 8, `states.json` 7, `tests/studio.test.cjs` 7, `views.js` 6.
- The README changes in 21 of 33 Studio commits. That is the docs-in-sync rule at work: the README repeats the page in prose (387 lines for a 2,990-line page).
- `behavior.json` changes 10 times in 15 days (it began 2026-10-25). Each engine behaviour change must edit it.
- `charactergen.py` changed in 30 commits in the same period.

## 2. Every view

8 tabs, 16 views (`studio.js:348-362`). LOC is the view's own function; shared code is listed after.

| # | Tab / view | Shows | For whom | LOC | Another tool does it? |
| --- | --- | --- | --- | --- | --- |
| 1 | Overview | The pack's card: face, counts per part, "Worth a look" gaps | owner, at a glance | 76 (`character.js:89-164`) | Gaps are check material: `charactergen.py --check`, `boopdev check`. **Broken now** (§7) |
| 2 | Personality | `personality.md` and `guide.md`, re-set as cards; settings in plain words | owner tuning steering | 59 (`169-227`) | The Markdown files. The Brain view and `boopdev prompts` show the same text as Jev reads it |
| 3 | Moods | 42 moods by family; one mood's move map; its steering file split into parts | owner, pack author | 80 (`232-311`) | `character.json` + `steering/mood/*.md`; `boopdev check` checks the graph |
| 4 | Behavior / Map | Engine behaviour: layers, each trigger, who decides, numbers read from code | owner, new contributors. Not about a pack | 83 (`behavior.js:55-137`) + `behavior.json` 206 + `charactergen.py:710-813` | `documentation/architecture.html` describes the same model. Only this view reads the numbers from code |
| 5 | Behavior / Brain | Each eval pass: the prompt, the questions, the expected answers | owner tuning prompts | 82 (`behavior.js:143-224`) + `prompts.js` 1.5 MB | `boopdev prompts` has the data; `boopdev eval --scripted`; the dashboard (`boopctl dash`) shows CONTEXT live |
| 6 | Animations / Scene | One mood x state, live or as a clip; variations; poke, shake; sound | pack author, owner | about 190 (`studio.js:59-194, 421-475`) | The simulator page (`simulator/`) runs the same firmware, but has no mood x state picker. `boopctl play` on a board |
| 7 | Animations / Matrix | 42 moods x 22 states, all at once; marks the simulated board's cell | pack author; the one "see it all" view | 136 (`studio.js:195-330`) | **Nothing else.** The playbook asks for exactly this as a contact sheet (`new-character-playbook.md:65`) |
| 8 | Animations / Transitions (+ Rank) | Frames across a change; pixel-change graph; ranks the jumpiest of 7 everyday transitions | owner measuring fluidity | 124 (`views.js:100-223`) + `everyday.jsonl` 913 + `charactergen.py:670-709` | `boopctl sim` plays the same scenario. `plan/TODO.md:555` names `internal/tools/fluid/`, which does not exist any more |
| 9 | Animations / Stills | Golden frames as a gallery, by group (Boop: 28 groups; Pixel: none) | owner | 25 (`595-619`) | Finder on `tests/golden-*/`; `boopctl sim` compares them |
| 10 | Words / Signs | Each sign drawn, filter by tag | owner | 23 (`318-340`) | `steering/signs.md` (58 Boop, 29 Pixel) |
| 11 | Words / Dreams | Dream signs with tags (Boop 17; Pixel none) | owner | 14 (`344-357`) | `steering/dreams.md` |
| 12 | Words / Voice | Takes by mood x kind, search, Play from `voice.bin` by HTTP range | owner, voice work | 122 (`362-483`) | `mac/takes.tsv`; `boopctl takes` plays and checks every take on a board. Costs 86% of `packs.js` |
| 13 | Tests / Evals | Each scenario, step by step (Boop 142, Pixel 6) | owner | 65 (`487-551`) | `evals/*.json`; `boopdev eval --list` |
| 14 | Tests / Demos | Each demo script as a story (Boop 15, Pixel 11) | owner | 37 (`555-591`) | `demo/*.jsonl`; `make demo`; the simulator page plays the recordings |
| 15 | Workbench / References | A reference's media beside the board, frame for frame; its reading from Markdown | owner + art agents | 84 (`views.js:229-312`) + `markdown.js` 79 | `boopctl reference`. Used once: Boop has 1 reference, Pixel 0 |
| 16 | Workbench / Review | Review queue, before/after, Approve or ask for a change; the server writes `notes.jsonl` | owner answering agents | 60 (`views.js:317-376`) + server | Chat or a pull request. Used once: 1 item, 1 note |

Shared code: `character.js:1-85` (helpers), `views.js:1-95` (transport, pickers), `board.js` 263 (the firmware as an adapter, recording, the change measure), `studio.js` tabs, address and wiring (about 165).

Who uses it, in practice:

- No agent step and no CI job opens the page. `check.cjs` is in no make target and no workflow (`grep -rn check.cjs` finds only docs).
- The owner is the only user. The evidence of use is weak: three failures in the main path stayed unseen since 2026-11-01 (§7).

## 3. What a new character needs from the Studio

By the playbook (`characters/new-character-playbook.md:12-45`), 7 steps:

| Step | Uses the Studio? | A script already? |
| --- | --- | --- |
| 1. Write the bible (`design/<NAME>.md`) | No | No (writing) |
| 2. Copy the closest pack's repository; set `id`, `name`, `faces` | No | Half. `make -C internal new-character ID= NAME=` (`internal/tools/new_character.py`, 73 lines) copies only `character/`, renames, links, runs `boopdev check`. The repository files (Makefile, CI, CLAUDE.md, README) are still copied by hand |
| 3. Pick the face per board | No | No. No check catches a face that a board never pushes (playbook row 2) |
| 4. Map moments to moods (`face` strings, Examples) | No | No (writing) |
| 5. Three workers: steering + evals; voice; art, sounds, face code | No. The art worker wrote its own contact sheet (`tools/facegen/sheet.py`, playbook row at line 65) | No voice builder in the engine (line 56) |
| 6. Demos, then record | No | Yes: `make -C internal demos` |
| 7. Check | Only `charactergen.py --check`, which also checks the Studio entry | Yes: `boopdev check`, `charactergen.py --check`, `CHARACTER=<id> make -C internal fw-test`, firmware build, `boopdev eval --scripted` |

- CHARACTER.md §14 step 8 says the Studio entry is optional (`CHARACTER.md:830-832`). §14 step 1 says to leave the `studio` entry out "until you need them".
- With no entry, a pack still gets the board's own preview for each face (`CHARACTER.md:793-796`).
- The Studio made the new character harder in two places: `check.cjs` fails unless every face's simulator build exists (playbook line 67), and adapters clash when two packs share a face id (line 69).

So: the Studio is a viewer for after the work. It is not on the path.

## 4. The pack contract and the cost of a character

Required (`CHARACTER.md:13-30`): 4 things.

1. `character.json`: 6 required keys (`id`, `name`, `version`, `default_mood`, `moods`, `faces`; `CHARACTER.md:213-225`).
2. `steering/guide.md`.
3. `steering/personality.md`.
4. `firmware/`: at least one face behind `render::Face`, plus `make_face.cpp`.

Everything else is optional: mood files, rig, voice, mirror, demos, studio, references, review, evals, tests.

Required content:

- **Moods:** all 42 universal moods, each once (`CHARACTER.md:229-235`). 16 are lasting (need `meaning` and `moves`); 26 are faces only (need `settles`). Every mood needs `face`.
- **Faces:** each face must answer 22 states in every mood: 42 x 22 = 924 cells. A face may reuse a design (`CHARACTER.md:486-488`). Pixel reuses heavily (its `wears` table; the Matrix shows "Comfy -> Calm").
- **Takes:** none required. With a voice, a pack needs takes for every mood (`CHARACTER.md:473`). Boop has 3,479 rows, Pixel 3,586; `voice.bin` is 31.7 MB and 33.3 MB.
- **Signs:** none required. Boop 58, Pixel 29.
- **Designs:** no count required. A state a face does not know draws `idle`.

What the two packs hold today:

| | Boop (SlimeBuddy) | Pixel (PixelBuddy) |
| --- | --- | --- |
| Tracked files in the repository | 4,321 (3,191 in `design/`, 767 in `tests/`) | 146 |
| Size on disk | 143 MB | 38 MB |
| Firmware files / lines (.cpp + .h, art tables included) | 50 / 39,280 | 20 / 33,363 |
| Mood steering files | 16 | 16 |
| Evals | 142 | 6 |
| Demos | 15 | 11 |
| Rig clips | 73 | 5 |

`charactergen.py` (1,397 lines) by area:

| Area | Lines | About |
| --- | --- | --- |
| Header, choosing the pack (`chosen`, `staged`, `in_use`) | 1-123 | 123 |
| `moods_h` (generates `moods.h`) | 124-171 | 48 |
| Schema rules (`Rule`, `fields`) | 172-229 | 58 |
| The rig: read, validate, generate `rig_tables.h` | 230-466 | 237 |
| References and review checks (§16) | 467-598 | 132 |
| Load, overlay | 599-628 | 30 |
| **Studio only**: states, everyday, behaviour map and its numbers, `wears`, studio checks, steering parsing, voice table, demos, evals, stills, `studio_data`, `write_studio` | 629-1191 | **563 (40%)** |
| `pack_problems`, `check` | 1193-1224 | 32 |
| Staging: `bundle`, `stage`, `sync`, `firmware_from/to` | 1226-1358 | 133 |
| `main` | 1360-1397 | 38 |

What it generates: `moods.h`, `rig_tables.h`, the staged layout in `.character-build/`, and `packs.js`.
What it validates: moods exist, startup mood, id and version length, each board's face folder, the rig schema; then the Studio rules (states list, entry files, `wears`, references, review, `behavior.json`).
What it does **not** validate: whether the pack plays. That is `boopdev check`.

The cost of a character:

- The playbook gives **no time estimate**. It gives a shape: 1 bible, 3 parallel workers, 7 steps, and 24 friction rows.
- Pixel Bro ("Pixel's body with a new soul"): 1 commit on 2026-10-26; about 190 tracked files: 50 steering, 45 design, 28 demo, 19 firmware, 15 evals. (Counted read-only with `git -C ~/src/PixelBro ls-files`.)
- It still left open: the voice is espeak placeholders, no mirror, no goldens of its own, no reply clips, the board's picture never seen (`new-character-playbook.md:76-87`).
- The animation bank was copied whole: 1,214 performances (line 62). The voice tools were copied from SlimeBuddy (line 56).
- The real costs are the face (33,000+ lines of mostly generated art code), the voice (about 3,500 takes), and steering + evals. None of them is a Studio task.

## 5. Tests for the Studio

| Test | What | Runs where | Cost |
| --- | --- | --- | --- |
| `tests/studio.test.cjs` (208 lines, 6 tests) | change measure against `changed.json`; `everyday` names; how each state is asked of the board; the server's `/review` and review clips; `markdown.js` | `make -C internal tools-test` only (`internal/Makefile:186`). **Not in CI** | 15.5 s measured; 15.2 s is one test that waits for a 15 s upload timeout. All 6 pass |
| `internal/characters/test_charactergen.py` (705 lines, 44 tests, about 15 on Studio rules) | staging, rig, Studio data and checks | CI job "Python tests" (`ci.yml:83-84`) and `tools-test` | seconds |
| `charactergen.py --check` | every pack + the Studio rules; writes `packs.js` | CI (`ci.yml:81-82`) | under 0.1 s for the Studio part |
| `check.cjs` (277 lines, Playwright) | every view in a headless browser, both packs | **Nowhere.** By hand only (`internal/VERIFICATION.md:176`). Needs Playwright, the server, a simulator build for every face, and `boopdev prompts` | Cannot pass today (§7) |

CI cost of the Studio is close to zero. The real cost is authoring: each Studio feature adds data code in `charactergen.py`, a rule, a Python test, a browser check and README prose.

## 6. Proposal: the smallest useful Studio

Principle: keep what only the Studio can do (show every look of a pack at once). Turn checks into `charactergen.py --check` output. Cut views that re-typeset files.

| View | Verdict | Reason | Lines deleted (about) | Risk |
| --- | --- | --- | --- | --- |
| Matrix | **Keep**, as the page | The only tool that shows 42 x 22. The playbook asks for it | 0 | - |
| Scene | **Merge** into the Matrix as a cell's detail (click to enlarge, variations, poke) | Same adapter, same data | about 60 of 190 (pickers, facts row) | Low |
| Overview | **Script** | Its value is "Worth a look". Print the gaps as warnings from `charactergen.py --check` | 76 + CSS | Low. It is blank today already |
| Personality | **Cut** | It is `personality.md` and `guide.md` | 59 + `with_examples` etc. | Low |
| Moods | **Cut** (or one line per mood in the sheet's row header: meaning + moves) | Files + `boopdev check` cover it | 80 + `mood_steering`, `leaves` (38) | Low. The move map is nice, not needed |
| Behavior / Map | **Move or cut** | It is engine documentation, not a pack. Put a generated table in `documentation/architecture.html`, or cut it | 83 + 206 (`behavior.json`) + 104 (`charactergen.py`) + tests | Medium. You lose two real checks: "a number the code does not declare" and "a state nothing plays". Keep those as a small test if you want them |
| Behavior / Brain | **Script** | `boopdev prompts --only NN` to stdout or a text file | 82; `prompts.js` (1.5 MB) and the `dev.sh` step go | Low |
| Transitions + Rank | **Script** | A fluidity number is a measure, so a command should print it: `boopctl sim characters/studio/everyday.jsonl --jumps`. `board.js`'s `changed` and `summary` are already pure and tested | 124 + shared 95 in `views.js`; keep `everyday.jsonl` beside the simulator's scenarios | Medium. The scrubber is useful while tuning. Keep the frames as PNGs from the script |
| Stills | **Cut** | A folder of PNGs | 25 + `stills()` 12 + 2,462 data lines | None |
| Signs, Dreams | **Cut** | `signs.md`, `dreams.md` | 37 + `tagged` | None |
| Voice | **Script** | `boopctl takes` exists. Add the mood x kind count table as text, and warn on an empty cell in `--check` | 122 + `voice_table`; `packs.js` drops by 101,652 lines | Low. You lose Play in the browser; the board plays takes |
| Evals, Demos | **Cut** | `boopdev eval --list`, the files, `make demo` | 102 + `demo_script`, `eval_scenario` (30) + 8,400 data lines | None |
| References | **Cut the view**, keep `boopctl reference` | 1 reference in the whole project | 84 + `markdown.js` 79 + `references_data` | Low |
| Review | **Cut** | 1 item, 1 note, ever. Approve in chat or a pull request | 60 + server about 150 + `review()` checks + the 15 s test | Low. Agents lose a channel that was used once |

Totals (estimates, hand-written lines):

| Where | Now | After | Deleted |
| --- | --- | --- | --- |
| The page (JS, CSS, HTML, JSON) | 2,990 | about 1,050 (`studio.js` 430, `board.js` 263, CSS 200, HTML 100, `states.json` 52) | about 1,940 |
| `check.cjs`, tests, README | 897 | about 300 (a 60-line smoke check, a short README) | about 600 |
| `everyday.jsonl` | 913 | moved, not deleted | 0 (moves to `simulator/`) |
| `charactergen.py` | 1,397 | about 900-1,000 | about 400-500 |
| `test_charactergen.py` | 705 | about 450 | about 250 |
| `serve.py` review and capture code | 150 | 0 | about 150 |
| **Total** | | | **about 3,300-3,400, or about 4,200 with `behavior.json`, CHARACTER.md §12/§16 prose and the README counted** |

Can `packs.js` stop being checked in? **It already is not.** Two smaller steps are worth doing:

1. Stop writing it as a side effect of `--check` and `--stage`. Add `charactergen.py --studio` (or have `serve.py` make it on request at `/characters/studio/packs.js`). Then `--check` has no output file, and a stale `packs.js` cannot happen.
2. With the contact sheet only, the data is moods, studio entries, states and `wears`: about 1,500 lines, under 60 KB.

Can the Studio be one read-only contact sheet plus `charactergen.py --check`? **Yes.** One limit: the sheet is not fully static. A board face is the firmware in WebAssembly, so it needs the server (`file://` cannot load it). A `clip` face (Pixel's adapter) works from `file://`. A fully static sheet (one PNG per pack, as the playbook asks: "any mood x state, every frame, as one PNG") is a `boopctl` command on top of `boopctl sim`; that also gives agents something they can read, which the page does not.

Suggested order:

1. Fix or delete the three broken things (§7). Decide by whether anybody missed them.
2. Cut the file viewers (Personality, Signs, Dreams, Evals, Demos, Stills). No risk, about 350 page lines plus about 250 in `charactergen.py`.
3. Cut Workbench (References, Review) and the server's write paths.
4. Move Voice gaps, Overview gaps and Transitions' ratio into command output.
5. Decide the behaviour map's home (architecture doc or nothing).
6. Shrink the README to what is left.

## 7. Broken, stale or inconsistent

Broken (seen in the browser; commands in the next section):

1. **The landing view is blank.** `character.js:151` reads `Object.keys(pack.uses)`. `charactergen.py` stopped writing `uses` in `60184bc6` (2026-11-01). The page throws `TypeError: Cannot convert undefined or null to object` and Overview draws nothing, for both packs. See `boop-01-overview.png`.
2. **The default pack's board does not load.** `charactergen.py:1132` writes `"staged": own_folder(last).name`. Packs now live in `<repo>/character/`, so the value is `"character"`, not `"boop"` (`packs.js:4`). `board.js:107` then asks for `/simulator/boop-sim-boop.js`, which is a 404, and the stage says "There's no build of boop for the board: run simulator/web/build.sh boop." See `boop-06-scene.png`. Boop's Scene, Matrix, Transitions and References all depend on that board.
3. **`check.cjs` cannot pass.** It asserts the board's note matches `/serve\.cjs/` (`check.cjs:267-268`); `serve.cjs` was deleted in `60184bc6` and the note says `serve.py` (`board.js:77`). It asserts Boop has 3 cards (`check.cjs:271`); Boop has 1 (`board-gel`). It asserts no page errors and that the page opens on Overview, which throws (item 1). It also needs `boop-sim-pixel.js`, which a normal build does not make (the playbook's line 67).

Stale docs:

4. `README.md:21-22`: `packs.js` is written "on every run but `--which`". Wrong: only `--check` and `--stage` write it (`charactergen.py:1383, 1393`). `--boards`, `--sim-face`, `--firmware-to` and a bare run do not.
5. `index.html:32`: the "No pack data yet" hint says to run `python3 characters/charactergen.py`. A bare run prints usage and exits 2 (`charactergen.py:1387-1389`).
6. `README.md:116-119` says Voice's Play "needs the studio's own server (the simulator's ... reads no ranges)". There is one server now, `simulator/web/serve.py`, and it does serve ranges (`serve.py:373, 553`). `README.md:39-40, 363, 367` and the page footer (`index.html`, "the studio's server (or the simulator's ...)") still speak of two servers.
7. `README.md:363-365` and `check.cjs:15, 269`: "Boop's three characters' cards". Boop has one.
8. Dead code for removed concepts: `charactergen.py:1086-1088` still reads `steering/talk/*.md` (no pack has one; `talks` is always `[]`), and `character.js:98, 207-209`, `behavior.js:60` still draw them. The docstring at `charactergen.py:1076-1080` still says a voice "may be another" pack's (§6 now says a pack stands alone). `ci.yml:81` still says "what it uses".
9. Words: `behavior.json` and the Brain view say "reaction" ("A reaction", "a reaction is sent"). CLAUDE.md's word is "Moment", and lists "reaction" under Not.
10. `plan/TODO.md:555` says to measure fluidity with `internal/tools/fluid/`. That folder does not exist. The Studio's Rank is the only fluidity tool left, and it sits behind item 2.
11. `new-character-playbook.md:51` says CHARACTER.md §14 still tells you to copy a pack into `characters/`. §14 now uses `make -C internal new-character` (`CHARACTER.md:815-818`). The scaffold still copies only `character/`, so the row is half done, not open.
12. The tool that was asked to be found: `require('playwright')` does not resolve in this checkout (no `node_modules`, no `NODE_PATH`). I used `NODE_PATH=~/.npm/_npx/705bc6b22212b352/node_modules`. A breadcrumb is filed.

## Commands used

```sh
cd /Users/michaeljxzhu/src/buddygotchi/.claude/worktrees/v1-polish
wc -l characters/studio/* characters/studio/tests/*; wc -c characters/studio/*
git ls-files characters/studio; grep -n -i -E "studio|packs|prompts" .gitignore
git log --oneline --since=2026-09-01 -- characters/studio | wc -l            # 33
git log --oneline --since=2026-09-01 | wc -l                                  # 294
git log --format= --name-only -- characters/studio | sort | uniq -c | sort -rn
git log --oneline --all -- characters/studio/packs.js characters/studio/prompts.js
git log --format='%h %ad %s' --date=short -S'"uses"' -- characters/charactergen.py
grep -n -i -E "studio|check.cjs|charactergen" internal/Makefile Makefile .github/workflows/ci.yml
grep -n -E "^def |^class " characters/charactergen.py
# packs.js timing and parts, in memory, nothing written:
python3 - <<'EOF'
import sys, time, json; sys.path.insert(0, 'characters'); import charactergen as c
t = time.time(); pack = c.chosen(); reads = c.Reads(); packs = c.local_packs(pack)
probs = c.studio_problems(packs, reads=reads) + c.state_problems() + c.behavior()[1]; t1 = time.time()
d = c.studio_data(packs, pack, reads=reads); s = json.dumps(d, indent=1)
print(len(probs), t1 - t, time.time() - t1, len(s), s.count("\n") + 1)
EOF
time node --test characters/studio/tests/*.test.cjs                           # 6 pass, 15.5 s
# The page, on the server that already served this worktree (127.0.0.1:8206, PID 99208):
NODE_PATH=~/.npm/_npx/705bc6b22212b352/node_modules node shots.cjs            # 32 PNGs, page errors and 404s logged
```

Not done: `boopdev prompts` was not timed (it writes `prompts.js`); `check.cjs` was not run (it is known to fail by reading it, and it needs builds that are absent); no Jev, no board, no Bluetooth.
