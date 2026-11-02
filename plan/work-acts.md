# Work acts

Updated 2026-11-02. Decided with the owner on 2026-11-01, who signed off a
storyboard (`/tmp/boop-storyboard/index.html`, rough props on real gel
faces). The work stream has about 31 small pictures to decode, and even the
owner couldn't read the pot or the bricks. Replace them with the falling
word by default and three big acts Boop plays out. More acts come later,
only from actual use: not risky commands or installs, not now.

**Built on the night branch, 2026-11-02:** the default and all three acts
(`WorkStream.Act`, `state`'s `wact`, `gel/act.h`). Owed: the board's look and
frame rate, and recordings for "we pushing!", "shipped!" and "built it!": until
then Jev has the voice's existing words ("Launch", "Testing", "Phew..."). In the
evals Jev mostly chose silence over an act from a calm mood.

## The model

1. **The default:** the command's word slides down behind Boop, for almost
   every call.
2. **Acts:** each has the same parts: a low sign (the same one as
   `plan/finish-sign.md`), a voice through Jev, and a scene.
3. **Stay:** the failure ladder (bonk, bonk2, helmet changed, throw), the
   big deletion, the rare alerts (timeout, NO, rate limit, context full,
   compacted), the turn's end (gather, drop).

## The acts

| Act | Fires on | Sign | While it runs | Pass | Fail |
| --- | --- | --- | --- | --- | --- |
| **Tests** | The `tests` topic | "running tests…" | Crash-test helmet with targets, strapped to a sled at a start line, facing a wall; puffing up, trembling, holding its breath; the sled inches forward | Stops short of the wall, a big phew, a thumbs up, "PASS" | Hits the wall and splats, flat and wide, sliding down, "FAIL" |
| **Push** | `git push`, deploys, opening or merging a pull request (`gh pr create`, `gh pr merge`) | The command: "git push", "deploy", "pull request" | On a rocket, blasts off the screen; only its trail and the sign stay. After about 20 s it drifts back in orbit | Parachutes down, proud, "shipped!" | Crash-lands in soot, rocket in the ground, "FAIL" |
| **Build** | The `build` topic | "building…" | Hard hat, hammering in a loop with sparks; a little house goes up over time | The house done, with a flag, proud, "BUILT" | The house falls apart, hat tilted, "FAIL" |

The sign is what says what's running: it stays up for the whole run. The
helmet means tests only, so the ladder's helmet step becomes something else.

**The small version.** The full act, with voice, plays when that act hasn't
played fully in about 30 minutes, or it's the first of the day. Otherwise:
the prop (helmet, hard hat; none for a push) and the sign, then the result,
no scene and no voice. A failure after a long run may get the full ending.

**Voice through Jev.** The scene and sign play at once, by rule, as what is
happening now. What Boop says is Jev's, so a cross Boop may stay silent or
mutter. Use guidelines, not Examples. "We pushing!", "testing!", "phew!",
"shipped!" and "built it!" need recording: placeholders until then, in the
voice bank's list.

**Edges.**
- Several agents: one full act; the others get the small version or their
  word, by the queue's rule.
- A needs-you interrupts an act at once; Boop just reappears. After it, the
  act's look comes back if it's still running.
- An act lasts as long as its command, so what's running is true in `state`
  (the board times nothing), and the result ends it.
- A command with no end heard (the agent stops, the session goes): the act
  ends with the turn.
- Moods keep showing through the faces, as Boop acts.
- Pixel is frozen: an `as` it doesn't know lands, as today.

## What goes

The styles and their art: `stir` (the pot), `plane`, `phone`, `page`,
`stamp`, `poof`, `arrive`, `look`, `combo`, `stack`, `built`'s tower,
`topple`, and `cross`, `pass`, `hail` and `launch` as they become acts.
`shatter` (the big deletion) stays. Check the idle `tower` pastime: if
it's the same bricks and you can't tell what it is, say so in the report,
and leave it.

## The build

One act done properly first, the push, since the owner described it, then
tests, then build. Cut to the default in the same stretch. Then:

- Pack (SlimeBuddy first): the scenes, props, goldens; the steering's
  guidelines; the voice list.
- Engine: `WorkStream.swift`, the wire, the state's act, the first-in-a-while
  rule with a test that pins it (30 minutes, first of the day), `Behaviour`.
- Check the frame rate and heap against the budgets: the gel is tight, and
  each act's props must fit.
- Mirror rebuilt, `make -C internal demos ALL=1`; `characters/CHARACTER.md`,
  `linkkit` docs if what they say changes; CLAUDE.md's Words (`act`).
- Evals (`--only`): an act's start can get a voice; a cross Boop may not.

## For the owner in the morning

Simulator clips or frames of each act's start, middle, pass and fail, and
the small version, with paths in the report. If an act can't be made to look
right blind, stop at the push and say so, rather than ship all three rough.
