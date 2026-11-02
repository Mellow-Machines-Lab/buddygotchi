# Growth

Updated 2026-11-01. Decided with the owner on 2026-11-01. Boop is whole from
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

## To check first

- Whether the gel can scale its body and eyes without breaking props, the
  desk and faces; nothing in the engine does yet. Voice pitch exists
  (`voice/effects.h`).
- Whether a Hatchling's face reads at arm's length (the owner liked it as drawn), and Chonk fits with the
  low sign and the desk.

Storyboard: `/tmp/boop-storyboard/stages.html`.

## The build

The scaling comes first, as its own commit. If the gel can't scale well in
the time there is, build everything else on one size with the sprout and
Chonk's look left out, and say so.

- Core: `Growth` with four stages (5,000 for Chonk), the wish's +40, the
  decay and its test; the highest stage is no longer kept for good, and a
  saved XP or stage past the new table is clamped.
- Board: body settings by the stage tags, the ceremony, the bar; a stage
  number on each pastime row, and the first spread of them. Pixel is frozen.
- Mac: the bar and the silhouette in the popover; the reason for shrinking.
- The Character Studio's Behavior tab groups pastimes by stage.
- Grep for Pal and Legend: CONTEXT's Boop row, `Days`, evals and docs.
- Evals (`--only`), tests that pin the numbers, the mirror, demos, docs.
- Frames of the four stages and the ceremony for the owner.
