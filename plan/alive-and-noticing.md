# Alive under your hand, and it noticed

Updated 2026-11-03. Decided with the owner on 2026-11-03. Make Boop feel more
interactive every day. No random surprises, no saga payoff, no rhythm game.

## 1. Alive under your hand

On the board, with no Jev and no new message unless it says.

- **Eyes follow your finger.** While a finger is down, the gaze target goes
  toward it (`GelFace::finger`, the engine's `gazeTarget`), and drifts back after.
- **Leans into a held finger.** A still touch past about a second: eyes close,
  it leans into the spot, a soft purr. Past about 5 s it dozes; lifting wakes
  it. Counts as care, so it meets a pet wish.
- **Sloshes when tilted.** The accelerometer's steady tilt, relative to how it's
  been resting, feeds the body's lean with a springy lag; the eyes stay level.
  Only when no animation moves the body. Check the frame rate.
- **Ears perk while you talk.** A nod while listening, on the board. Send the
  mic's loudness at about 5 a second only if the nod feels fake.

## 2. Reasons for everything

Every reaction has a plain reason. Add: a wish being made ("Boop wants a pet.");
work acts ("claude is running the tests on api."), tests' first pass included;
short board versions where they help (your prompts, turns starting, stepping
away, compaction, hush); board-only reactions showing their reason themselves
("you poked Boop"), since a tap plays before any Jev; a real mood change on
the board; sleeping, dozing and waking ("Nothing's happened for an hour, so Boop
dozed off."). Dressing stays in the popover. Pastimes and transitions get no
board caption, only the popover ("Boop's blowing bubbles to pass the time").

A test: every event kind has a reason or is listed as deliberately silent, so a
new reaction with no reason fails.

## 3. It noticed

**A notice never makes a new moment where one exists: it adds a fact to that
moment. New moments come only at a check-in, one at a time, and a waiting wish
comes first.** Code finds what's true and puts it in CONTEXT; Jev decides whether
to use it, often with only a face. Guideline, not Example: caring, not nagging.

**Facts on existing moments:**
1. Back from a break: "While you were gone, claude finished on api."
2. Back on an old project, at the prompt: "First time on api in 9 days."
3. Goodnight: "23 turns today."
4. Milestones in the morning sequence (`Days.special`): a month, 100 days, a
   year. Keep the morning caption to the day and the dream.

**Reason for a wish:**
5. You haven't said hi, or your morning ritual was missed (5 of the last 7
   days stroked in the morning, an hour past your usual time). Quiet in the first
   two weeks, with too little history.

**Notices, at most about 2 a day:** each a pure function over the digest and the
moment, a CONTEXT fact, lines in `signs.md` tagged by name, and a rest. Each
counts only once played, and has its reason.

| Notice | True when | Rest | Words |
| --- | --- | --- | --- |
| `waiting` | An idle agent has sat 15–20 min; never during a needs-you | Per agent, not repeating | "claude's waiting" |
| `stretch` | At the Mac 2–3 h with no break | A day | "stretch?" |
| `rough` | 3+ failures in the last hour, or a sharp prompt, then a quiet moment, never instead of the failure's own reaction; Boop scoots close and leans | A day | "i'm here", "*hug*" |
| `late` | 3 nights past 1 am; only at idle, at most gently | A week | "bed?", "still up?" |

Several lines each. Tests pin the rules and rests; evals are feel evals.

## 4. Daily counts, on the Mac only

A small local file, a row a day: days touched, touches with no wish open, wishes
made, met, given up and their waits, threads opened from the board, needs-you and
answer times, spoken per hour, hushes, Quiet, volume, face-down, unplugged by day,
disconnects, failures, stage. A "This week" view in the dashboard, and a command
printing a counts-only summary a person may choose to send: no words, threads or
notes. Nothing leaves the Mac by itself.

## 5. A full pass

When everything above is landed: the board, the Mac app, how they integrate and the
debug dashboard. Performance wins, polish, architectural simplification, UI and UX
bugs, whatever else could be better. Use real runs: the simulator, `Boop
--headless`, `Boop --snapshots`, the dashboard's real terminal, and the real board
over USB at volume 0, with its lock. Measure the frame rate and heap on the board
(the acts' lift-off, a Chonk, the bar, tilt): those have been estimates. Clear
`plan/TODO.md`'s leftovers from the reviews that are real: `to-work` being cut by
`starting`, the heart crossing LISTENING, the nose hit and dragging at other
sizes, a dream told twice with several buddies, a held `grew`, the gulp replaying,
and `check` narrower than CI (the boards, `slimegen --check`).
