# Simplifying Boop's behaviour

Updated 2026-10-25. Boop's behaviour grew by trying things, and it's time
to comb it. This plan is how: fewer places that decide the same thing,
fewer words for one idea, and no change you'd notice on the board until
the last part, which the evals gate. The Character Studio's **Behavior**
tab (`make dev`, or [its README](../characters/studio/README.md)) maps
behaviour as it is today. Read it beside this plan.

## Where it stands

Three things decide what the board shows:

- **Mac rules** (the core): the look, needs you, the tags, the work
  stream, and four reactions of their own.
- **The brain** (Jev): the mood, and every reaction it picks. A pass asks
  up to nine questions: the mood's, six about a reaction (seven when a
  sign fits), and the diary's, once a day.
- **The board**: what a touch or a shake is, the queue, which variation
  plays, busy and frantic, and the screen with no Mac.

The map has 31 things that set something off. About a third are decided
in more than one place:

| One moment | Who answers it today |
| --- | --- |
| A tool fails | The stream's bonk ladder, and the brain if it was a check or the ladder's third or fourth rung (the `error` rule is gone, 2026-10-25) |
| A turn is stopped | The `stopped` rule, the stream's drop, and the brain's finish line |
| A helper comes back | The `helper_return` rule, the stream's "done", and the brain's "helper back" topic |
| A compaction | `starting/compacted`, the stream's compact, and the brain's line |
| A tap run | The board counts it (3 s, the third tap is spam), and the Mac counts it again with its own copy of the numbers |
| Push-to-talk | The board's 30 s and 8 s timers, and the Mac's copy of both |
| BOOT | The board decides hand-off or poke from `attn` and `idle`; the Mac decides again from its own line, dismissed requests included, so they can disagree |
| Face down | The board refuses reactions, and the Mac holds the brain from the events it folds; a lost `peekaboo` leaves the brain held |
| Tags | The Mac makes 28 of them, and the board makes `busy` and `frantic` |
| A mood's fade | Only in the mood's prose ("fades to calm after 10 min"); no code fades it |

Some words mean several things: **busy** (a count, a tag, a queue
holder, a skip reason), **hold** (five meanings), **idle** (a look, a
count, the tiers, a heartbeat, the Mac's idle time), **reading** (your
prompt's reading and a tag), **waiting** (an activity, and an agent
waiting on you), **sleep** (asleep, the doze tier, "while it slept",
the Mac asleep), **gag** (a work-stream word coming forward, and the
gel's idle comedy), and **moment** (the gel's code word for a
reaction, and a debug key).

## First pass: one owner each, nothing you'd see

Each of these takes away a duplicate without changing what plays.

1. **On a board that takes the work stream, the stream owns the agent's
   moments.** The `error` rule is gone (2026-10-25). Drop `stopped` and
   `helper_return` the same way: the stream shows each at the same
   moment, and as `if_free` reactions they're often skipped anyway. Keep
   `starting`, which has art of its own, and `listening`. Record a rule's
   reaction only once the board says it played (its `ended`), as a
   brain's is.
   *Removes:* two rule reactions on the gel.
2. **The board owns the tap run and push-to-talk's timing.** It already
   reports `poked` or `tap_spam`. Add the run's count to the `tap` event
   (`n`), and let `TranscriptView` read it in place of `inARowMs` and
   `answersRunFrom`. The Mac's listen timers then follow `talk_on`,
   `talk_off` and the reply. *Removes:* two copies of each number, and the
   comments asking to keep them in step.
3. **The Mac owns who's in line.** Send the line's length in `state`
   (`line`: shown, dismissed and idle). The board hands off when it's over
   0, and pokes otherwise. *Removes:* the board's own rule, and the case
   where they disagree.
4. **The board owns face down, and says so.** Drop the Mac's face-down
   hold (`TranscriptView.hold`'s `facedown`/`peekaboo` fold). The board
   already refuses reactions with `skipped facedown`. A brain pass while
   it's face down costs a request, and that's rare. *Removes:* a mirrored
   state that can get stuck.
5. **The Mac owns every tag.** Make `busy` and `frantic` in `Occasions`
   from the working count, as the tiers are. The board keeps the pace
   (125%, 160%) and reads the tags. *Removes:* the one pair of tags the
   board made itself.
6. **Delete the paths nothing reaches:**
   - the gel `Router`'s `stop`, non-`hold` reactions and overlay timeout;
   - `GelFace::pick`'s gesture branch;
   - `Kit::cut`;
   - `rig::Layer::kScene`.

   Rename the debug keys `dbg.state.turn` to `queue` and `moment` to
   `reaction`. Either make `dbg.look` work on the gel or say it doesn't.
   Fix the doc drift the inventory found:
   - `behaviour.h`'s refuse reasons are missing `facedown`;
   - BOOT "plays its hand-off" while needs you shows, but nothing plays;
   - SPEC §4 doesn't list Boop's skip reasons.

## Second pass: the brain, gated by the evals

These change what Jev is asked. Run `make eval` before and after each
one. Keep a change only if the scenarios hold.

7. **A mood's fade is data, and code does it.** Today a mood says where
   it leaves for in two places: `character.json`'s `moves`, and the
   prose's "Leaves for…". Its fade is only prose. Instead:
   - Give each mood `fades: {to, after_min}` in `character.json`.
   - Let `MoodOutput` move it there by itself once the time is up and no
     pass has moved it.
   - Drop "Leaves for" and "Fades to" from the prose, and keep the prose
     to what the mood is like.

   The studio's Moods view already parses those sentences, so it would
   read the data instead. *Removes:* the prose that duplicates the graph,
   and fades that happen only when Jev notices. You'd see fades come on
   time.
8. **One "how big" in place of `react.loops` and `say.kind`.** Both
   answer the same question: how much the moment matters. Ask it once:
   small, stands out, big, biggest. Derive the loops (1–4) and the size
   of what it says (sound, word, phrase; a swear only for biggest and
   bad) from the answer. The pass keeps `say.feeling` and `say.about`.
   *Removes:* a question from every pass, and combinations like held
   four times but only a grunt.
9. **Drop the hourly idle heartbeat.** The idle check-in, at the
    personality's pace within 2 h of activity, already covers a quiet
    stretch. After that, the board's idle tiers keep it alive without a
    request. *Removes:* the third heartbeat.
10. **Say "don't repeat what's playing" once, in code.** The guide, the
    `none` option's text and the personality all say it. The poke run is
    the only place code holds it. Make it general: while a reaction about
    an event is in progress, a newer event of the same kind doesn't wake
    the brain. Then cut the sentences.

## Third pass: one word for one idea

Rename only where it's cheap. The wire's keys and the art's tags keep
their names.

| Today | Proposed | Where |
| --- | --- | --- |
| act `waiting` (a slow tool) vs needs you | Keep the state; call the idea "a slow tool" in code and docs | `Activity.swift`, the studio |
| `WorkStream.holdMs`, `ReactOutput.holds`, view `hold` | `showMs`, `loops`, `hold` (the brain's only) | Swift |
| `busy` the count vs the tag | `state.busy` stays (wire); call the count "working" in code | `Core.swift`, firmware |
| the doze idle tier vs asleep | "nap" in code and docs, `doze` on the wire | `Occasions.swift` |
| the gel's "gag" (idle comedy) vs the stream's gag | "bit" for the gel's | gel engine |
| "moment" in the gel's router | "reaction" | gel engine |

## What stays

- The three deciders. Each keeps what it's best placed for: the Mac,
  what it knows about agents and you; the brain, taste; the board, your
  hand and the frame.
- `starting`, `listening` and the board's own touches.
- The queue.
- Signs, the voice and the diary, as three ways of saying things.

## How we'll know

- The Behavior map gets shorter: fewer rows decided by several, and no
  number in two places. charactergen's check fails on a number the code
  doesn't declare. A rule that's removed takes its row with it, or the
  check says nothing plays a state.
- After the first pass, every eval passes unchanged
  (`boopdev eval --scripted`, then `make eval`). So do the simulator's
  scenarios and the goldens (`make -C internal check`).
