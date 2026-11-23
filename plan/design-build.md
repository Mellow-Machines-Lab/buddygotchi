# Building the design

Updated 2026-11-22. The order to build
[documentation/design/](../documentation/design/README.md) in, one step at a
time. Nothing here is built. Tick a step in the commit that finishes it, and
say there what checked it.

## Before you start

1. Read `documentation/design/README.md`, `theory.md` and `screen-guide.md`,
   and open `animations.html` in a browser. The screen guide says what to
   build. The animations show how it should feel; Boop is a plain dome
   there and the positions were chosen by eye.
2. Read CLAUDE.md. The parts that matter most here:
   - The gel's drawing lives in SlimeBuddy
     (`characters/.repos/SlimeBuddy/character/firmware/src/render/gel/`), on
     branch `main-v2`. A change that spans both lands there first, then
     here, then the engine pin.
   - Only the owner pushes or says to. Ask before any push and before any
     flash of the board. Other sessions share the board.
   - The Mac decides and the board renders. Every "which" below (which
     agent, which picture, which energy) is a plain rule on the Mac, sent
     in the `state` message. The board never chooses.
   - A change to what the gel draws rebuilds the mirror
     (`firmware/tools/mirror.sh`).
   - New words go in CLAUDE.md's table in the commit that builds them:
     held picture, show, pips, pill, energy, speaking.
3. Do one step, run its checks, show the owner the simulator's pictures,
   and commit. Do not start the next step in the same commit.

Checks for every step: `make -C internal check`, the gel's own tests and
scenarios in SlimeBuddy, and new simulator scenarios for what the step
adds ([internal/VERIFICATION.md](../internal/VERIFICATION.md) §1). Each step
also updates the design docs where the build differs from them, and moves
its line in the design README from "Not built" to "Built".

## The steps

They go from small and safe to large. Steps 1 to 4 need no new messages on
the link. Each step can ship alone.

### 1. The strip's words ✓

The screen guide's section "The strip's words".

- `app/BoopKit/Core/WorkStream.swift`: `doing` gets plain verbs for known
  commands (build, compile, test, git, install), "using" and the spaced
  name for a tool it does not know, and never a bare tool or file name.
  The word that comes forward from the monitor (`word`, `shown`) uses the
  same phrase or goes.
- A "thinking" phrase when a turn runs and no call has come for a few
  seconds, and the time after a long call ("building Boop · 2 min").
- A phrase holds at least 1 s. Decide on the Mac, so the board and the
  drawer agree.
- Tests: `WorkStream` tests pin each row of the guide's table.

Done when: in a real session, every phrase in the strip reads as a verb
and its object, and nothing flickers.

### 2. The cuts ✓

The screen guide's "Small details: keep, fold or cut".

- Remove the nightcap (`layers.{h,cpp}`, `nightcapFor`, the hat's
  recording), the busy and frantic typing and the other work pastimes
  except the stretch (`pastimes.{h,cpp}`, the `busy` and `frantic` tags if
  nothing else reads them), and the copied pose (`Along.swift`'s `copied`,
  the gel's pose).
- Leave the tiers' tag; step 3 reads `tier3`. Remove the looks that only
  the tiers switched.
- Follow "Removed code takes its docs with it": CLAUDE.md's words
  (dressing, pace, copied), `characters/CHARACTER.md`, SlimeBuddy's
  `CONTINUITY.md`.

Done when: the scenarios pass with those designs gone and no doc names
them.

### 3. Energy

The screen guide's "Energy".

- Mac: one rule gives the level: bright for the first hour after the
  day's first hello, tired at night or at `tier3`, else normal. Send it as
  a tag. The two numbers are guesses; make them easy to change and ask the
  owner after a day of use.
- Gel: tired draws heavy lids, half tempo for the idle sway and the
  blink, a yawn now and then, and a droop between calls at work. Bright
  draws wide eyes and a quick sway. The first hello of the day plays a
  stretch and a yawn. Energy never touches the monitor, the strip or a
  card, and never slows a reaction to a touch.
- Mac app: the popover says it in a few warm words under Boop's face when
  the level is not normal, for example "Boop's getting sleepy." and
  "Boop's wide awake." Follow CLAUDE.md's "The UI's words". The mirror
  shows the lids by itself, since it is the board's firmware.

Done when: the owner can tell the three levels apart on the board from a
chair, and the popover's line matches the board.

### 4. Speaking along

The screen guide's "Going with you".

- `app/BoopKit/Presence/Along.swift`: a camera alone means on a call.
  Another app recording with no camera becomes a new `speaking` tag.
  Boop's own push-to-talk stays out of it, as today. `Tags.swift` and the
  firmware's tag list get the tag last, so no pack's numbering moves.
- Gel: one hand leaves the keys and cups an ear, the body leans toward
  the Mac's side, and rings pulse by the ear on a 1.6 s beat. No band, no
  reply, no sound.
- Speaking wins over typing.

Done when: dictating into any app makes Boop listen, and a video call
still makes it still and silent.

### 5. Going with you in every pose

The theory's "One body, three channels".

- Gel (`face.cpp`: `showAlong`, `showWithYou`; `gaze.cpp`; `motion.cpp`):
  the rhythm and the gaze become a layer added to the pose, not a pose
  that must win the body. Light size in all four work poses and with a
  card held: the pose sways at your speed, the eyes follow the pointer and
  step down as you scroll, a card bobs. Full size stays for idle.
- A held card no longer blocks the lean under a resting finger.
- Only the needs-you screen, listening, face down and sleep turn the
  layer off.

Done when: the 15 clips pass at arm's length: four work poses and a held
card, each with typing, fast typing and speaking. If a sway cannot be
seen, make it bigger.

### 6. The end of a chat turn

The screen guide's "How a turn ends", the chat row.

- `MomentRule.swift`, `MomentOutput.swift`: a chat turn still plays no
  finish. New: the strip says "your turn" for that agent, and Boop turns
  to you once.

Done when: after an answer, one glance at the board tells you it is your
move.

### 7. Several agents

The screen guide's map (5, 7, 9) and "Who wins the space".

- Mac: one rule picks the agent the screen follows, in this order: needs
  you; a result to show (once, then back); your swipe (kept until that
  agent goes idle or you swipe again); an agent with a card over one with
  plain work; the agent you last prompted. `StateSnapshot.swift` sends the
  watched agent, and each agent's lane colour and state for the pips.
- Gel (`lane.cpp`, `drawer.cpp`, `props.cpp`): the pips on the strip's
  line in place of the handle, the agent's name at the strip's right in
  place of the counts, a sideways slide of the monitor, card and strip on
  a switch while Boop stays, and two faint arrows at the sides when the
  set of agents changes. A pull up still opens the drawer.
- Touch (`firmware/src/app/device.cpp`, the gel's gestures): a swipe left
  or right anywhere on the desk asks the Mac for the next agent. Today a
  swipe works only on a card.
- The pill: a round note in the agent's lane colour for news from an
  agent you are not watching (finished, waiting for you). One at a time,
  about 4 s, a tap goes to that agent. Its pip pulses.

Done when: with three sessions open, the owner can always tell which
agent the screen shows, reach the others by swipe, and is told when
another one finishes.

### 8. Held pictures

The screen guide's "Held pictures".

- Mac (`app/BoopKit/Cards/`, `WorkStream.swift`, `Core+Cards.swift`): a
  card's status becomes one of three pictures built from the hooks, with
  no word from the agent: plan (the to-do, with the current step's name),
  changes (lines added and removed for each file this turn), helpers (one
  lane each). The kind of work picks which. A picture whose data has not
  changed for a while is put down. The `boop-cards` `status` tool stops
  showing text; keep it answering, so agents that call it do not fail,
  and use its time guess for the plan's ring.
- Gel (`card.{h,cpp}`): the larger window, 454 by 188, and the three
  drawings. Boop stands higher behind it.
- `plan/agent-cards.md` is rewritten or removed in this step.

Done when: a real coding turn shows the plan, then the changes growing,
then nothing once the work stops.

### 9. The show

The screen guide's "The show". Do it in three parts, and stop after each.

1. **Can agents draw?** Extend `internal/tools/cards/trial.py` with a
   `show` tool that takes the guide's fields. Run fixed tasks through real
   sessions, save each picture, and score it: true to the turn, readable,
   inside the rules. View them on the Mac only. Show the owner the
   pictures and the scores before going on. Tune the tool's instructions
   here.
2. **The Mac.** `app/BoopCards/main.swift` gets the `show` tool. The Mac
   checks the SVG against the rules, answers the agent with what is
   wrong, draws it to an image, and shows it in the popover with its
   headline. An `image` path is read the same way.
3. **The board.** A new LinkKit message carries the picture
   (`linkkit/SPEC.md` first): 420 by 190 at 16 colours, packed. The gel
   draws the frame, the headline and the picture. The order of an ending
   is: the hop or flinch, the show for 30 s, then the low sign. A show
   from an agent you are not watching takes the screen once, then the
   screen returns. Several shows go one at a time, at least 8 s each.

Done when: a finished turn puts a picture on the board that the owner
understands from a chair without opening the Mac.

## Not in this plan

XP, the ring, the world, the wish and the idle beats are another
conversation; this plan changes none of them.
