# Slime asset generator

Updated 2026-10-25.

Run `node characters/boop/tools/slimegen/slimegen.mjs` at the repo root; `--check`
checks freshness without writing. No dependencies, device or network.

It reads the slime's design (`characters/boop/design/slime-blob/`:
`emotion-graph.json`, `expressions.json` and `sound/`), checks it
(`check.mjs`: what fails is in the design's
[VALIDATION.md](../../design/slime-blob/VALIDATION.md)), and writes the gel
engine's tables and the pack's moods. Its own modules hold what the design
is as code, the one source of each:

| Module | What it is | What it writes |
| --- | --- | --- |
| `scenes.mjs` | Every state's scene recipes, by mood and take (their contacts, timed in ms, leans and labels), the gestures' and occasions' recipes and gags, the notice's recipe, timed by the pack's rig clip for it (`rig/clips/notice.json`), and each expression's traits | `slime.h`'s recipes, gags and occasions (`recipes.mjs`, `catalog.mjs`) |
| `face.mjs` | Each expression's face as the board's controls: where its eyes and mouth sit, and the sizes its art draws them at | `slime.h`'s profiles |
| `painter.mjs` | Each expression's art at rest, as Canvas calls | `slime_art.h`: vector paths, and each art's groups' shapes (`art.mjs`) |
| `mesh.mjs` | The dome and its studio material, from equations | `slime_mesh.h`: a mesh and a dense material lookup, 1025 × 513 texels (under a pixel each across the dome; the AMOLED reads a copy in PSRAM) |
| `moods.mjs` | The moods to read | the design's `MOODS.md` |

The design's `emotion-graph.json` is the source for Boop's moods
in its character pack, `characters/boop/character.json`
([CHARACTER.md](../../../CHARACTER.md) §5): the `moods` key, each mood's
id, meaning and family, in the design's order. It keeps every other key,
and any key a mood has that the design doesn't set, such as `face`; a
mood's `moves` are the pack's own, and the design's edges seed only a
mood the pack doesn't have yet. The design's pixel `fallback`s, `brief`
markers and `hostPolicy` aren't written: every pack has every mood, and
pacing is the steering's.

`slime.h` holds the expression profiles, the idle gags and which
expressions play them, the scene recipes with each row's takes and the two
rows' fourth takes, the gesture state's ten takes, each with a gag of its
own and the face it borrows, the notice state's three takes' faces, the
contact kinds' names (a rig clip's cues name them), the looks' occasions
with their tags as `firmware/src/render/tags.h` numbers them, the mood graph's edges (the bridges the gel draws), and the sound
effects, three takes of each sketch (`sound/sfx.js`) at 11,025 Hz.
`slime_art.h` gives each art's groups (each eye, the mouth, the tears, the
cheeks with the strain mark) a shape from their paths' point counts, fill
or stroke and colour: two arts of one shape there morph, path by path and
point by point, and others cross-fade. `slime_mesh.h` samples the dome's
geometry and analytic studio lighting. None of these are animation frames:
the board deforms and projects geometry on every draw.

The Mac's popover and onboarding show the board's own firmware: the pack's
`mac/mirror/` is the firmware built to WebAssembly
(`firmware/tools/mirror.sh`, [CHARACTER.md](../../../CHARACTER.md) §9), so
a change here that changes what the board draws builds it again, in the
same commit.

`check-headless.py --output FILE` exercises the real scripted app against
an isolated synthetic gel USB peer. Add `--native` to connect it to the
real gel firmware simulator and check hello, mood/attention updates and
device completion events. Both modes use temporary HOME/state directories.
See [verification](../../../../internal/VERIFICATION.md).

After `firmware/tools/pio.sh run -e native`, `internal/tools/boopctl sim
--face gel` checks native RGB565 screenshots against the gel goldens, and
`make -C internal fw-test` runs `test_gel`, the engine's rules. These
checks do not measure physical display throughput or speaker quality.
