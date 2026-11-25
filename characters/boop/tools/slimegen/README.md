# Slime asset generator

Updated 2026-11-25.

Run `node character/tools/slimegen/slimegen.mjs` at the repo root; `--check`
checks freshness without writing. No dependencies, device or network.

It reads the slime's design (`character/design/slime-blob/`:
`expressions.json` and `sound/`) and the pack's `character.json`, checks it
(`check.mjs`: what fails is in the design's
[VALIDATION.md](../../design/slime-blob/VALIDATION.md)), and writes the gel
engine's tables. Its own modules hold what the design
is as code, the one source of each:

| Module | What it is | What it writes |
| --- | --- | --- |
| `scenes.mjs` | Every state's scene recipes, one set of takes for each state (their contacts, timed in ms, and leans; which are `moody`, which the board times by the mood's traits as it deals them; and `standsIn`, the activities the desk shows as another's, which have no row of their own), the gestures' recipes and bits and the pastimes' bodies, the notice's recipe, timed by the pack's rig clip for it (`rig/clips/notice.json`), needs you's one knock, timed by `rig/clips/knock.json` (`knock`: where it climbs), and each expression's traits (the reviewed moods' table, else its own `traits` in `expressions.json`) | `slime.h`'s recipes, bits and pastime takes (`recipes.mjs`, `catalog.mjs`) |
| `face.mjs` | Each expression's face as the board's controls: where its eyes and mouth sit, and the sizes its art draws them at | `slime.h`'s profiles |
| `painter.mjs` | Each expression's art at rest, as Canvas calls | `slime_art.h`: vector paths, and each art's groups' shapes (`art.mjs`) |
| `mesh.mjs` | The dome and its studio material, from equations | `slime_mesh.h`: a mesh and a dense material lookup, 1025 × 513 texels over the sphere, kept down to the lowest ring the camera sees, ring 18 (385 rows; under a pixel each across the dome; the AMOLED reads a copy in PSRAM) |

The faces and the lasting moods are the pack's own,
`character/character.json`
([CHARACTER.md](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/CHARACTER.md) §5):
`moods` names the 18 faces the Mac picks from and `board_faces` the six
meme faces only the board draws so far, each of which needs an expression
of its own here, and `lasting` the 7 moods and the faces each rests in. slimegen reads
it and never writes it. An expression whose id has a colon
(`calm:asleep`, the board's sleeping face) is an alternate of the face
before the colon, and no mood.

`slime.h` holds the expression profiles, the bits and which
expressions play them, the scene recipes, one row of takes for each
state the same in every mood, with each state's row (`kRecipeRow`), each
row's takes and the two rows' fourth takes, each expression's traits the
board times a moody take by, the gesture state's ten takes, each with a bit of its
own and the face it borrows, which moods keep their own face through a
gesture, the notice state's three takes' faces, the
contact kinds' names (a rig clip's cues name them), the pastimes' takes
by name, the lasting mood each face is of (`kMoodOf`: the body gives its
beat only when that changes), each face's idle move (`kIdleMoves`: its own
move, `rig/clips/face-<face>.json`, where it has one, the meme faces,
else its lasting mood's rig clip, `rig/clips/idle-<mood>.json`, which must
exist),
and the sound
effects, three takes of each sketch (`sound/sfx.js`) at 11,025 Hz.
`slime_art.h` gives each art's groups (each eye, the mouth, the tears, the
cheeks with the strain mark) a shape from their paths' point counts, fill
or stroke and colour: two arts of one shape there morph, path by path and
point by point, and others cross-fade. `slime_mesh.h` samples the dome's
geometry and analytic studio lighting. None of these are animation frames:
the board deforms and projects geometry on every draw.

Needs you's recipe is one knock for every mood and take, timed by the
pack's rig clip for it (`rig/clips/knock.json`), and lasts until the
climbing knock (`knock-climb.json`) is over; `scenes.mjs`'s `knock` says
whether the climb follows the knock at once (`'replaces'`) or after
`followsMs` with nobody come (`'follows'`, 20 s), baked into `slime.h` as
`kKnockClimbAtMs`. An invite's poses and payoffs are the pack's rig clips,
the back's and the spin's on the rig's `turn`, and take nothing from
here; nor do the keys' contacts sound. Only the sketches the board names
are baked into the bank, three takes each (`catalog.mjs`); the others stay
design material.

The Mac's popover and onboarding show the board's own firmware: the pack's
`mac/mirror/` is the firmware built to WebAssembly
(`firmware/tools/mirror.sh`, [CHARACTER.md](https://github.com/Mellow-Machines-Lab/buddygotchi/blob/main/characters/CHARACTER.md) §9), so
a change here that changes what the board draws builds it again, in the
same commit.

After `firmware/tools/pio.sh run -e native`, `internal/tools/boopctl sim`
checks native RGB565 screenshots against the gel goldens (one
or two pinned shots a scenario, a set frozen small on purpose until the
gel's redesign settles; design/slime-blob/VALIDATION.md), and
`make -C internal fw-test` runs `test_gel`, the engine's rules. These
checks do not measure physical display throughput or speaker quality.
