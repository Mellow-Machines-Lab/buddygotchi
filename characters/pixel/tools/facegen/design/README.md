# The designs

The device's faces come from the animation bank,
[`characters/pixel/design/boop-sound-bank-v4/`](../../../design/boop-sound-bank-v4/README.md):
its generator makes every design's SVG, and `facegen` turns them into
`characters/pixel/firmware/include/faces.h` (with the rig face's parts, cut from each
mood's first idle at rest), the popover's tiles and the Mac's loop lengths.
Nothing here is drawn
by hand, and no SVG is checked in: `facegen` runs `../bank.mjs` into
`../build/` (ignored) each time.

- `manifest.json`: the designs, in the device's order, which `facegen`
  writes and `sfxgen` reads: each one's mood, state, variation (from 1
  within its mood and state), name, length in seconds, the host fact it's
  for (`outcome`, success or failure, for task_complete; `ctx`, new_task,
  session or continuation, for starting), its voice window (`voiceMs`,
  when a line that comes with its animation starts, which `sfxgen` puts in
  `sfx.h` and `facegen` in the Mac's `FaceLoops`), and its SVG dialect
  (`v2`, the first pack's; `v3`, the older moods' newer states; `v4`, the
  new moods' flip-books, and every mood's wake_up and comedy).

13 moods × 23 states, 876 designs. The older seven moods keep the first
pack's designs byte for byte (the bank's `qa/v3-fingerprints.json`, which
`facegen` checks) and have one or two of most newer states, with one start for each of the
four contexts, the last (compacted) added after the capture; the six new
moods have three of each. Every mood has one wake_up, drawn after the
capture, and the comedy after that (the bank's `runtime/comedy-art.mjs`):
three more idles, a fourth asleep and one more success each, proud a
second (the gift) and excited a working and an idle (the zoomies). Asleep
and no app look the same in every older mood, and in every new one, and
the snore in all of them.

What picks a design is the mood and the state, and a variation is picked
at random, never the last one, among those for the host fact if there
is one. To take a
new version of the bank, update it in `characters/pixel/design/`, run its
checks, then `make -C internal faces` and `node characters/pixel/tools/sfxgen/sfxgen.mjs`.
