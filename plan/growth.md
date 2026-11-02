# Growth

Updated 2026-11-02. Decided with the owner on 2026-11-01. Boop is whole from
the first minute. Growth only adds delight.

## One bar, fed by XP

XP stays the one number, shown as a growth bar that appears when it changes
and lives in the popover. Normal use (agents' work, up to 60 a day), care
(up to 60), and a met wish (+40, once a day). The wish's heart flies into
the bar. The thresholds stay (`Growth.stages`).

## Going backwards

After 3 days with no XP at all, Boop loses 5% of its XP a day. It can shrink
a stage (`Growth`'s "never goes back" goes), and can't reach zero. On
return, the reason says so: "Boop shrank a little. You were gone 2 weeks."

## What a stage changes

**Every feature is there from day one.** The drawer, the to-do count,
talking, touches and all that's useful are never locked, and nobody has to
keep using Boop to earn them. They're taught by onboarding and the first
wishes, not by stages.

A stage changes only:

1. **Body settings,** one row per stage, applied to every animation: size,
   eyes, how it moves, voice pitch, and at most one feature (the sprout). No animation is drawn per stage.
2. **Which pastimes and tricks it knows:** one stage number on each row of
   the existing table, so the show unfolds with no new art. The Character
   Studio's Behavior tab groups them by stage. Asked for a trick it doesn't
   know yet, a small Boop tries and flops.

Going backwards affects only these.

Four stages, to start with (the owner, 2026-11-01): Pal and Legend go, and
more can come later from real use.

| Stage | XP | About when | Look |
| --- | --- | --- | --- |
| Hatchling | 0 | Day 1 | Small, huge eyes, clumsy, squeaky |
| Sprout | 200 | Day 2 | A little bigger, bouncy, a sprout |
| Buddy | 1,000 | Week 2 | Full size |
| Chonk | 5,000 | Week 6 or so | Big, slow, deep |

At Chonk the bar stays full. Going backwards still applies.

Growing plays a ceremony: a glow, a pop, the new shape, and a sign ("i
grew!", "new: dance!"), with the voice through Jev. The popover shows the
next stage as a silhouette.

## The scaling test (2026-11-02)

The gel can do it, on the simulator; the board is owed. The finishes already
scale the body, its face and its anchors about a point
(`PaintControls::scale`), so a stage's body is that one scale, multiplied in,
about where it stands on the desk (`BodySettings`, the gel's `painter.h`).
Every frame of `tests/scenarios-gel/growth.jsonl` shows the four stages side
by side, over faces, hats, the desk, pastimes, finishes, acts, the wish, the
drawer and both signs.

| Stage | Size | Eyes | Body's pixels | Rows from the top (Buddy's 92) |
| --- | --- | --- | --- | --- |
| Hatchling | 0.55 | 1.55 | 0.31 of Buddy's | 195 |
| Sprout | 0.70 | 1.25 | 0.49 | 161 |
| Buddy | 1 | 1 | 1 | 92 |
| Chonk | 1.12, squashed | 0.85 | 1.21 | 90 |

What broke, and what fixes it:

- **A Chonk at a plain 1.2 leaves the screen.** Its hats, the trophy and its
  crown are cut at the top. So it's about 1.19 wide and no taller than Buddy,
  which reads as big and round, and is the plan's "Big" within what fits.
- **The keyboard and the paws** hid a small body's mouth: they scale with
  it now, about the desk's front. The desk and the monitor stay.
- **The nose** was a fixed spot on the canvas, above a small body's face.
  The face now says how far it's dropped (`Face::noseDrop`).

What didn't break: the hats, the kit, the shades, the wish's bubble, the work
stream, the acts and the finishes all sit on the anchors, and the low sign and
the needs-you card sit on the screen. Two smaller things stay as they are, for
the owner to judge: a Hatchling's Mega Boop doesn't fill the screen, and the
reaction's sign is as wide as ever, so it crosses a Hatchling's mouth, as it
does Buddy's.

The cost: no new memory, as it's a few integers a frame and no buffer, and
smaller stages shade fewer pixels. A Chonk shades 21% more of the body. A
frame's time on the host didn't separate the stages from the noise (2.0 to
2.5 ms a frame), so **the Chonk's frames a second on the AMOLED are unmeasured**;
`boopctl perf --scenes` with a saved XP past Chonk's is owed there. Mega Boop
already draws far more of the screen than any Chonk.

Still to look at on the board: whether a Hatchling's face reads at arm's length.

Storyboard: `/tmp/boop-storyboard/stages.html`.

## What's built, and what isn't (2026-11-02)

Built on the `growth` branches: the stages, the wish's +40, going backwards
and the reason, the body by stage tags, the ceremony on the board, the
sprout, a stage on each pastime row (Hatchling, Sprout or Buddy), the flop, the
silhouette in the popover, and the studio's grouping.

Not built:

- The board's growth bar, and the wish's heart flying into it: it needs a
  new field on `state`, for the XP's share. The bar is only in the popover.
- A voice for growing through Jev: the sign is the rule's, "I'm a Sprout!".
- Voice pitch and how it moves, by stage: the body settings are size, eyes and
  squash.
- A pastime only a Chonk knows: a Buddy would deal differently, as a board
  with no tag is a Buddy.
