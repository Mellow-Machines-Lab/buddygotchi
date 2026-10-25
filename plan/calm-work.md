# Calm work

Updated 2026-10-25. The owner looked at the gel's working look and found
the body itself boring while the kit around it grew cluttered: a camp
with a fire, a sweatband, little gel helpers running out of it. Three
rounds of animated sketches settled the direction (the concept page is
the owner's artifact, "Boop Working Concepts"). The look is on screen
most of the day, so it stays calm: effort shows as the eyes settling,
never as strain, and now and then the whole body does something.

## What changes

**Cut.**
- The camp (tent, fire, pennant) and the pastimes that go with it:
  marshmallow, pizza, stargaze.
- The sweatband.
- Second wind (the shake and the huge eyes).
- The little ones: the helpers that run out of its sides while an agent
  delegates, and the one that carries a subagent's word off and back. A
  subagent's word lands like any other.

**Keep.**
- The mug, and the mug tower: a mug more every 10 minutes, up to four.
  It counted from when the camp came out; it counts from `tier5` now.
- The headphones at `tier3`, put on where you can see it.
- The falling commands, and the calm pastimes.

**Add.**
- Steady typing: the paws really type, on the recipe's key contacts,
  and the base settles by tier (the lids lower, it leans in, it sways
  slower), with a few slow motes around it in the zone (`tier5`).
- The done beat: Enter, a tick on the monitor, a sit back, a nod.
- Reading closely, in place of the tongue: it leans over the monitor and
  reads line by line, close enough to fog the glass from `tier4`.
- Three moves, rarer than a pastime (one every 90 s at most):
  - the coffee reach (`tier3`): it stays put, squeezes in on one side
    and stretches out the other to the mug tower, sips, puts it back;
  - the melt (`tier4`): it melts into a puddle with drips, then pulls
    itself back up tall and wobbles;
  - the stretch break (`tier5`): it walks off the edge, the desk empty
    for a moment while the screen works on, walks back, squeezes down,
    stretches up tall, and boings back to work.

## How

- The rig gets three channels the moves need: `x` (the body sideways,
  canvas px), `reach` (one side stretched out, the other pinched) and
  `melt` (flattened toward a puddle). Pixel's face ignores them.
- A look may name a base clip for each tier (`looks.json`'s `tiers`).
  The gel plays its look's base for the first time; Pixel's face keeps
  the look's one clip.
- The desk's paws are drawn where the pastime playing puts them: up for
  Enter, up to the head for the headphones, away while it walks off,
  spread while it melts.

## Steps

- [x] The cuts, and the mug tower from `tier5`.
- [x] The rig's `x`, `reach` and `melt`.
- [x] Steady typing: base clips by tier, typing paws, the zone's motes.
- [x] The done beat, reading closely, the headphones put on.
- [x] The three moves, and the gap between them.
- [x] The docs, the mirror, the board's frame rate: on the AMOLED, with
      the owner's app connected and the agents at work, the working look
      and every new pastime drew at 21 to 35 fps, its frames 42 to 48.5
      ms at the most, where main's drew at 18 to 20 (49 to 54 ms); both
      over the 40 ms the motion budget allows, and the least heap 49 KB
      on both, under its 60 KB.
- [ ] The owner, on the board: how each move and the typing feel, and
      whether the melt's flat slits for eyes read as peeking. The soft
      glow of the sketches is a few motes instead, which cost nearly
      nothing to draw.
