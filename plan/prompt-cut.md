# Cutting the prompt

Updated 2026-11-01. Decided with the owner on 2026-11-01. Build this
first, before the rest of the night's queue, and stop tuning prompts to
pass today's evals: most of those words are about to go.

## Why

The personality should steer in general, with few things truly
deterministic, and moods fluid. A typical prompt is about 6,900 tokens
(characters / 4, from `boopdev prompts`), and only about 170 of them
change from moment to moment:

| Part | Tokens |
| --- | --- |
| PERSONALITY's 76 Examples | 2,020 |
| PERSONALITY's rules | 780 |
| The guide | 1,010 |
| MOOD | 240 |
| Question text | 2,550–2,850 (about 740 of it "not for" guards) |
| CONTEXT, HISTORY, NOW | 170 |

The evals reward copying the Examples, so the evals change first.

## 1. The evals: three groups

- **Code checks, unchanged:** the scripted ones: 53, 68, 69, 92, 93,
  115, 116, 117.
- **Must, strict:** would be plain wrong. Exact checks stay.
  - A failed turn is never celebrated: 3, 43, 143.
  - No wrong face, no swearing at the person: 17, 61.
  - Talked to, it answers, and rightly about agents: 36, 40, 126, 127.
  - Hush, Quiet and Chatty hold: 129, 122, 123.
  - Moments the owner loves (frustrated → on your side, curse → sorry →
    happy): 24, 150.
  - Never lonely after a night or while agents work; never sad about a
    wish you couldn't answer: 136, 139, 155.
  Chosen from the scenarios' names: move one if reading it shows it's
  wrong, and say so.
- **Feel, judged:** everything else. Steps stay; exact checks and `why`
  go. Each gets a brief:

  ```json
  {"name": "...", "judge": "what matters here",
   "reasonable": "a range of fine answers",
   "unreasonable": "what would be wrong", "steps": []}
  ```

  Merge scenarios that check the same thing (104–113).

## 2. The judge

- The runner saves each scenario's trajectory: per step, the line Jev
  read, the mood, face, move, say, sign and narration.
- **Jev runs each scenario once.** A must failure or an unreasonable
  verdict gets one re-run to confirm before it blocks.
- A fresh Claude session agent judges each trajectory against its brief:
  reasonable, odd or unreasonable, with one line why. It is not an API
  call, there is no new key, and nothing new goes in CI. CI keeps what
  needs no Jev.
- The judge isn't the rewriter, and doesn't see the old Examples.
- Test the judge with a few made-up bad trajectories (Boop celebrating a
  failed turn). If it passes them, its verdicts aren't to be trusted: fix
  that before using it.
- It also flags Boop going flat or passive, and compares similar
  scenarios for sameness. Flat is the failure to expect.

## 3. Step the prompt down

Each level is one commit (engine and packs), run once and judged, on a
branch of its own (`prompt-cut`), so any level can be picked:

| Level | Size | What goes |
| --- | --- | --- |
| A | about 4,500 | Most Examples, guards that don't protect a must rule, what's said twice (where a mood goes: MOOD and the mood question) |
| B | about 3,000 | Nearly all Examples, the guide's glossary of lines, most option descriptions, the reply options' quoted samples |
| C | about 1,800 | The floor: guide 150, PERSONALITY 450 with about 3 Examples, MOOD one line, questions 900 (face names alone where clear) |

- Guidelines, not Examples. Reasoning words Jev can use: "moods drift:
  small things nudge them, big things flip them", without flickering.
- `judge_by` stops pointing at Examples.
- Keep the closing temperament lines longest: the cheek lives there.
- At level C, try moving must rules into code where it's simple: a failed
  turn isn't offered a success. Only for those few absolutes.
- CONTEXT, HISTORY and NOW stay. So do the code's rules (Talk, hush, the
  graph).
- Pixel's and Pixel Bro's packs have to keep passing `make -C internal
  check`, not to shrink tonight.

`CLAUDE.md`'s rule "options that say what they're not" becomes options as
short as their meaning allows; the Docs table applies as usual.

## 4. Jev's budget

Three full runs, one for each level, each scenario once. `eval --list`
says a full run is about 622 requests. The owner raised the daily limit
for this: `JevAllowance.dailyLimit` goes from 1000 to 2500. That is room
to finish, with re-runs and `--only` runs, not more full runs. Don't set
`BOOP_JEV_OVER_LIMIT`. Report how many requests the night used.

## 5. The morning report

The three levels side by side: size, must results, what the judge
flagged, how varied, and old and new answers for the same moments
(baseline: the last full run's logs, if they're still there). Say which
level you'd pick, and why. The owner picks, after trying it on the board.

Build the rest of the queue on the level you'd pick, in separate commits,
so another level can still be chosen.
