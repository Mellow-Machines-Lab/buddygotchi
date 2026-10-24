# Slime asset generator

Updated 2026-10-24.

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
The Mac's popover and onboarding show the board's own firmware, not this
engine: the pack's `mac/mirror/` is the firmware built to WebAssembly
(`firmware/tools/mirror.sh`, [CHARACTER.md](../../../CHARACTER.md) §9),
so a change here that changes what the board draws builds it again.
`check-headless.py --output FILE` exercises the real scripted
app against an isolated synthetic gel USB peer. Add `--native` to connect it
to the real gel firmware simulator and check hello, mood/attention updates
and device completion events. Both modes use temporary HOME/state directories.
See [verification](../../../../internal/VERIFICATION.md).

The generator also writes `characters/boop/firmware/include/slime.h` (expression profiles,
the idle gags and which expressions play them, scene recipes with each row's
takes and the two rows' fourth takes, the gesture state's ten takes, each
with a gag of its own and the face it borrows, the notice state's three
takes' faces, the looks' occasions with
their tags as `firmware/src/render/tags.h` numbers them, bridges and baked
cue clips) and `slime_art.h` (authored vector
face paths, and each art's groups' shapes: two arts of one shape there
morph, path by path and point by point). `slime_mesh.h` samples the reference dome geometry and analytic
studio lighting into a mesh and a dense material lookup. These are not animation
frames: the board deforms and projects geometry on every draw.
`check-port.py --output /tmp/boop-gel-port` builds the native
trace adapter and compares every saved script/trace against the C++ engine;
it needs `firmware/tools/pio.sh run -e native` first, for ArduinoJson and
the staged pack's `moods.h`.
After `firmware/tools/pio.sh run -e native`, `internal/tools/boopctl sim --face
gel` checks native RGB565 screenshots against the gel goldens. These checks
do not measure physical display throughput or speaker quality.
