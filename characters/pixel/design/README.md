# Pixel's design: the animation bank and mood graph

Updated 2026-10-24. The code-based animation/SFX bank and approved mood-graph
handover. The bank is the one source of the device's designs and sounds:
`facegen` runs its generator for the faces and `sfxgen` imports its
timelines and synthesiser, so a change here changes the firmware once
they're rerun.

- [Animation bank](boop-sound-bank-v4/README.md): editable SVG generators,
  procedural sounds, portable browser player and coverage index.
- [Mood graph and JEV handover](boop-mood-spectrum-v2/HANDOVER.md):
  the 13-mood graph's design history (neighbor choices, dramatic-edge
  gating, migration and voice guidance). The graph a pack runs is in its
  `character.json` (characters/CHARACTER.md §5); Pixel's is a copy of
  Boop's for now.

Boop's own design, in its pack's `design/` (characters/CHARACTER.md),
is the rest: the voice bank and the gel slime.

From the **repository root**, with Node.js:

```sh
node characters/pixel/design/boop-sound-bank-v4/source/build.mjs
node characters/pixel/design/boop-sound-bank-v4/qa/check.mjs
```

The generated player is checked in for immediate use; the
[Character Studio](../../studio/README.md) plays it as Pixel's preview
(`../studio/adapter.js`).
The larger per-scene manifest and expanded SVG copies are reproducible and
ignored, rather than duplicating the compact source in Git. Use the builder's
`--svg` option to write **every** SVG selection to
`boop-sound-bank-v4/dist/svg/`. Each selection's procedural sound score and
new-scene voice window are in the generated `boop-sound-bank-v4/manifest.json`.

Browser QA is optional and needs Playwright, pngjs and Chromium. It drives the
studio, so run `python3 characters/charactergen.py --check` first:

```sh
npm --prefix characters/pixel/design install --no-save --package-lock=false playwright pngjs
cd characters/pixel/design
npx playwright install chromium
cd ../../..
node characters/pixel/design/boop-sound-bank-v4/qa/browser.mjs
```

Alternatively point BOOP_PLAYWRIGHT_MODULE and BOOP_PNGJS_MODULE at existing
module files, and BOOP_QA_BROWSER at an installed Chromium executable.
These dependencies are QA-only; building and playing the bank needs none of
them. The checks do not launch Boop, touch Bluetooth, call JEV, use ElevenLabs
or consume credits. Each script supports `--help`.

The imported bank is self-contained: no absolute workstation paths and no
dependency on the design workspace's V3 folder. Independent V3 fingerprints
check preservation of the older SVGs and scores.

## How the device uses it

`make -C internal faces` runs the bank's generator
(`characters/pixel/tools/facegen/bank.mjs` calls `makeScene` for every design) into
`characters/pixel/tools/facegen/build/`, which git ignores, and turns the SVGs into
`characters/pixel/firmware/include/faces.h`, with the rig face's parts: each
mood's eyes (open and shut), mouth and cheeks, cut from its first idle at rest
([CHARACTER.md](../../CHARACTER.md) §15), so its plain face is the art drawn
here; and, for every design whose face is that resting face moved, where it
sits at each step, so the rig face draws it in the design's place.
`node characters/pixel/tools/sfxgen/sfxgen.mjs` then bakes
the timelines, in the voice-first mix, into `characters/pixel/firmware/include/sfx.h`. Nothing
is copied out of the bank by hand. The older moods' designs must come out as
`qa/v3-fingerprints.json` has them; change one only deliberately, with the
fingerprints in the same commit (their SVGs were re-captured once, when the
faces were tagged, every frame drawn as before). The generator tags each
flip-book step's face and mouth (`data-part`) and its blink (`data-blink`),
which facegen and the device use; `qa/check.mjs` must pass after any change.

**The resting face's tags.** Whether the rig face draws a design is the
design's own say. Wherever a design draws its mood's resting face, moved
(its first idle's: `ownFace`, `own(dx, dy)`, a flip-book's step), the
generator tags the face's parts where it places them, with `part` in
`runtime/visual/base.mjs`: `data-part` is the part, `eye-l` and `eye-r`
(`shut-l` and `shut-r` when the eyes are shut), `mouth` or `cheeks`, and
`data-at="dx,dy"` where its art is drawn, in px from where the resting face
draws it, before the transforms and moves above it carry it: `0,0`, or an
eye's glance where the art draws the eyes aside (calm's and engaged's
flip-books). An eye's tag holds what glances with it (a lid, a brow, a tear
pool). Anything else on that face is its decoration, in
`data-part="decor"`, which the design keeps drawing over the rig face: a
sparkle, a falling tear, grumpy's anger mark, engaged's brows (which hold
still while its eyes glance). A face drawn some other way is untagged and
stays baked: curious's eyes looking about (the first pose, its resting one,
is tagged), sad's own tears pouring from its eyes, irritated's twitch, a
failure's straight mouth, a face on gold, the shared quiet face, the
wake-up's and the comedy's sleepy faces, and the zoomies' (`rig: false`),
which leave the screen. Facegen reads the tags: a design whose face is
tagged at every step is the rig face's, and facegen fails unless the rig
face, drawn where the tags say, then draws it pixel for pixel at every
step.

A new design is a new variation after a state's others, never a redrawn
one: the device turns a look's variations by itself at the end of a loop,
and picks a finish's for its outcome, never the last again, so the Mac
needs no change. The comedy (`boop-sound-bank-v4/runtime/comedy-art.mjs`:
a yawn, nodding off, a sneeze, a snore, hiccups after a cheer, proud's
gift and excited's zoomies) came that way, with the only sounds a quiet
look makes.

The mood graph belongs to the Mac's Mood action, never the generic harness.
Integration is not visual approval: new art and sounds are reviewed by
eye and ear before they merge to main.

The original animation publication contained no recordings.
