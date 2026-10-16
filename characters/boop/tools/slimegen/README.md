# Slime asset generator

Updated 2026-10-15.

Run `node characters/boop/tools/slimegen/slimegen.mjs` at the repo root; `--check`
checks freshness without writing. No dependencies, device or network.

The slime design's `emotion-graph.json` is the source for Boop's moods
in its character pack, `characters/boop/character.json`
([CHARACTER.md](../../../CHARACTER.md) §5): the `moods` key, each mood's
id, meaning and family, in the design's order. It keeps every other key,
and any key a mood has that the design doesn't set, such as `face`; a
mood's `moves` are the pack's own, and the design's edges seed only a
mood the pack doesn't have yet. The design's pixel `fallback`s, `brief`
markers and `hostPolicy` aren't written: every pack has every mood, and
pacing is the steering's.
The same tool bundles the reference engine, WebGL/Canvas renderer and a
silent adapter into Boop's character pack, `characters/boop/mac/mirror/`. The shipped files have no
dependency on this tool at runtime. `check-mirror.mjs` checks interruption and
resource policy, and runs the generated `slime.js` on stubs to check its
drawing: none while the popover is closed, a frame at once when it opens,
60 frames a second while it is open on a 120 Hz display as on a 60 Hz
one, and the renderer's supersampling tiers. Edit
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
