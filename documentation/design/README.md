# Boop's design

Updated 2026-11-25. How Boop should feel and look on the board, across idle
and work. This is the design the next build works toward. Most of it is not
built yet; "What is built" below says what is.

| Read | For |
| --- | --- |
| [theory.md](theory.md) | The ideas: why Boop behaves as one thing in every state |
| [animations.html](animations.html) | What to expect: every core state and event, moving. Open it in a browser |
| [screen-guide.md](screen-guide.md) | How to build it: what sits where, sizes, shapes, colors, motion, what wins |
| [brain.md](brain.md) | Who thinks for Boop: rules, the calling agent, the dream, skits, with no key. Mostly built |

The order to build it in is [plan/design-build.md](../../plan/design-build.md).

When two of them disagree, the theory says why, the screen guide says what,
and the animations are examples. Fix the one that is wrong in the same commit.

## What is built

As of main `66d7fc1a`:

- Built: the regions, the monitor's icon, the strip that leads with what the
  agent is doing, the agent's card as a window in its lane color, no finish
  for a chat turn, typing along and the other with-you poses when idle and in
  the typing pose, and the strip's words (plain verbs, the 1 s hold, the
  time on a long call, "thinking"), and the cuts: no nightcap, no work
  pastime but the stretch, no copied pose; and energy (bright, normal,
  tired) on the lids, the eyes and the idle tempo, with the popover's line;
  and speaking along (a camera alone is a call; another app recording with
  none is you speaking); and going with you as a layer: typing along sways
  the body in every work pose and with a card held, its hands and eyes the
  pose's; a chat turn's end: a look up at you and "your turn" low; and
  several agents: the watched one, pips, the name chip, the swipe, the pill,
  and the sideways slide on a switch; and held pictures (plan, changes,
  helpers) in place of the text card; and the show on the board, its picture
  sent as a `blob`, LinkKit's image message.
- Not built: the lean under a finger with a card held, and the arrows at
  the screen's sides. A finished turn of an agent you aren't watching still
  plays its finish as well as the pill.

## Keeping it alive

- A change to Boop's behavior on the board changes these files in the same
  commit, as the code's own docs do.
- The animations are a sketch. Boop is a plain blue dome there, and the
  positions were chosen by eye. When the firmware settles a position or a
  size, write it into the screen guide and correct the sketch.
- A new behavior names its element in the screen guide's table. If none
  fits, it probably should not ship.

## To check while building

These are not design questions. They are things only a build can answer.

1. **Arm's length.** The light sway, the nod with the cupped ear, and every
   text size, on the real board from a chair.
2. **Do agents draw well?** Before any firmware work on the show, extend
   `internal/tools/cards/trial.py`: fixed tasks, real sessions, and a score
   for each picture (true to the turn, readable). View the pictures on the
   Mac only.
3. **The plan picture's data.** The Mac sends the to-do list as done and
   total. The picture also needs the current step's name.
4. **Lane colors.** The samples use teal, violet and orange. Use the
   board's real lane colors, and keep them away from the needs-you amber.
5. **Codex.** The card trial covered Claude Code only.
