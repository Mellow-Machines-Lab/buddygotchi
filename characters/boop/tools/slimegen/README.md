# Slime asset generator

Updated 2026-10-05.

Run `node characters/boop/tools/slimegen/slimegen.mjs` at the repo root; `--check`
checks freshness without writing. No dependencies, device or network.

The slime design's `emotion-graph.json` is the source for v3's moods in
Boop's character pack, `characters/boop/character.json`
([CHARACTER.md](../../../CHARACTER.md) §5): the `moods` key
(ordered adjacency, meanings, families, pixel fallbacks and brief markers)
and `pacing` (provisional host pacing). It rewrites only those two keys,
and keeps any key a mood has that the design doesn't set, such as
`quiet_never`.
The same tool bundles the reference engine, WebGL/Canvas renderer and a
silent adapter into Boop's character pack, `characters/boop/mac/mirror/`. The shipped files have no
dependency on this tool at runtime. `check-mirror.mjs` checks interruption and
resource policy, and runs the generated `slime.js` on stubs to check its
drawing: none while the popover is closed, at most 60 frames a second while
it is open, and the renderer's supersampling tiers. Edit
`mirror.mjs` or the design's `render/` sources, never `slime.js`, and
regenerate. `check-headless.py --output FILE` exercises the real scripted
app against an isolated synthetic gel USB peer. Add `--native` to connect it
to the real gel firmware simulator and check hello, mood/attention updates
and device completion events. Both modes use temporary HOME/state directories.
See [verification](../../../../internal/VERIFICATION.md).

The generator also writes `characters/boop/firmware/include/slime.h` (expression profiles,
scene recipes, bridges and baked cue clips) and `slime_art.h` (authored vector
face paths). `slime_mesh.h` samples the reference dome geometry and analytic
studio lighting into a mesh and a dense material lookup. These are not animation
frames: the board deforms and projects geometry on every draw.
`check-port.py --output /tmp/boop-gel-port` builds the native
trace adapter and compares every saved script/trace against the C++ engine.
After `firmware/tools/pio.sh run -e native`, `internal/tools/boopctl sim --face
gel` checks native RGB565 screenshots against the gel goldens. These checks
do not measure physical display throughput or speaker quality.
