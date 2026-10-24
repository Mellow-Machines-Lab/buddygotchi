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
sits at each step, so the rig face draws it in the design's place. A design
drawn here with the resting face (`ownFace`, or the first idle's face) and
its decorations over it stays one the rig face can draw; a face drawn some
other way stays baked. `node characters/pixel/tools/sfxgen/sfxgen.mjs` then bakes
the timelines, in the voice-first mix, into `characters/pixel/firmware/include/sfx.h`. Nothing
is copied out of the bank by hand. The older moods' designs must come out as
`qa/v3-fingerprints.json` has them; change one only deliberately, with the
fingerprints in the same commit. The generator tags each flip-book step's
face and mouth (`data-part`) and its blink (`data-blink`), which facegen and
the device use; `qa/check.mjs` must pass after any change.

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
