# The finish's sign

Updated 2026-11-01. Decided with the owner on 2026-11-01. The hanging
ticket can't say which thread finished, so Boop holds up its name, low,
after the cheer.

## Why

- Beside a success's trophy the ticket has room for about 9–10 characters
  (`kBesideTrophyTo`, `done.cpp`); otherwise 20 at most (`kMostGlyphs`).
- The Mac cuts every name to 23 bytes (`maxNameBytes`), and the board keeps
  24 (`Done::thread`).
- The strip repeats the same name, cut too.
- The reaction's sign can't carry it: it crosses the lower face, and would
  hide the cheer.

## The moment

A finish that names a thread:

1. At once: the rim glow and the reaction. Tapping anywhere opens the
   thread from here on (`plan/tap-on-a-finish.md`).
2. During the cheer and Boop's words: the words in the strip, as today,
   nothing in front of Boop.
3. When its words end, at once if it says nothing, and after about 3 s at
   most even if the cheer goes on: Boop lifts the thread's sign.
4. The sign stays for the linger, which goes from 3 s to about 5 s to
   read it. A new reaction still takes it down.

## The sign

- Held low, **in place of the strip**, in Boop's hands, not across its
  face: the whole face stays clear. It may rise a little above the strip
  for two lines, and a big cheer may touch it.
- The thread's name, with the finish's mark and colour: a tick, a cross or
  dots. No agent's name; with no thread's name, the agent's, as today.
- One line when it fits, else two. Aim for about 50 characters; check what
  actually fits at this font, and cut at about 40 if it's tight.
- Raise the Mac's cut for `who.thread` and the board's `Done::thread` to
  match. `maxNameBytes` stays for what else uses it.

## What goes

- The hanging ticket and its string. The trophy and the big finishes stay,
  and so does the rim glow.
- The strip's repeat of the name while the sign is up.
- **No sign from Jev at a finish that names a thread.** "Did it work?"
  goes for good: its lines in `asks.md`, the `finished` moment of
  `Asks.moment`, and eval 148. Wishes no longer come at a finish, only at
  check-ins and the dream's telling (this replaces that part of
  `plan/wish.md`).

## The build

- Pack (SlimeBuddy first): the sign in `done.cpp` and `lane.cpp`, the
  order above in time, new goldens. Pixel is frozen and keeps its ticketless
  lane.
- Engine: the longer name on the wire and in `Behaviour`; the longer
  linger, with the tests that pin it; the moments in `Asks`.
- Mirror rebuilt, `make -C internal demos ALL=1`, `characters/CHARACTER.md`
  and `linkkit` docs if what they say changes.

## For the owner in the morning

Simulator screenshots, with their paths in the report: a short name, a long
name on two lines, a failure, and a big cheer before and after the sign
rises. The board check: can you read it at arm's length, and does a cheer
still read?
