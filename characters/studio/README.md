# Character Studio

Updated 2026-11-14. One contact sheet for a character pack: every mood
against every state, each cell drawn by the character's own preview, and
one cell large when you click it. The page belongs to the engine and
names no character: the engine's states only order what the pack fills
in. A pack that wants a preview declares one in its `character.json`
([CHARACTER.md](../CHARACTER.md) §12). Every pack gets the board's own
preview of each face its boards have.

What a pack lacks that doesn't stop it (moods a preview has no art for,
lasting moods with no steering file, moods with no voice takes, no signs
or dream signs) is not on the page: `charactergen.py --check` prints it
as `CHARACTERGEN GAP` lines.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run but `--which` for the packs in this checkout (`make -C internal
build` stages, which writes it). Git ignores it. From the repository root:

```sh
python3 characters/charactergen.py --check
python3 simulator/web/serve.py
```

Then open `http://127.0.0.1:8206/characters/studio/`. The server serves
`characters/` at `/characters/` and the simulator's build at
`/simulator/` (`simulator/web/build.sh` makes it for the staged pack,
`simulator/web/build.sh PACK` for another). `make dev` and
`make -C internal simulator` start the same server. Opened from
`file://`, the page works too, but a board can't run there.

## What's on the page

The character first (**Boop** | **Pixel**, when there's more than one
pack here), then a card for each of its previews: each one the pack
declares, then a board for each face it hasn't declared. Switching keeps
the mood and state.

- **The matrix**, where the page opens: a row for each mood in its
  family, a column for each of the engine's states
  ([states.json](states.json)). A cell is made by the preview's adapter,
  silent, and a mood the preview has no art for is dashed. Only the cells
  on screen play, at most 60 at once for a `clip` character and 12 for a
  `live` one (each holds one of the page's few WebGL contexts), a hovered
  cell first.
- **The scene**, a clicked cell: the stage, the mood and state pickers,
  what each means, the variations, the transport (Play, Loop and a
  scrubber for `clip`; Pause, Replay state, Poke and Shake for `live`),
  and sound, off until you turn it on. **Tools**, closed, when the
  character has any. "Every mood and state", or <kbd>M</kbd>, goes back.

Served by the simulator's server, the matrix also marks the cell the
simulated board shows now, from the board's `dbg.state` once a second:
no app or needs you, else a Moment playing, else its Doing, in the mood
its face wears. The simulator's link names the board to ask,
`&board=/board` (`/board/NAME` for one of several); without it the page
asks nothing.

The address keeps the selection
(`#pack=boop&c=board-gel&mood=grumpy&state=working&v=2&view=scene`), so a
link opens the same cell; `view` is `matrix` or `scene`. Keys in a cell:
←/→ variation, ↑/↓ state, Space play or pause, S sound, P poke.

## On the board

The board's preview (`board.js`) is its firmware: the simulator's
`Board` ([simulator/README.md](../../simulator/README.md)) with the
pack's build, checked by its `hello`, powered on with the face. It asks
for each state as the Mac and a finger would: a Doing is a `state`, a
Moment a `do` over working (idle for waking up), a poke or a stroke a
touch where the simulator taps, and no app 30 s with no state. On the
stage it plays from a `dbg.reset` and picks its own variations; a matrix
cell steps its clock 100 ms ten times a second, so twelve play at once.
A board that can't run says why in its pane.

A pack may add to one of its boards' cards with an entry of its own
(`"board": FACE`, its id `board-FACE`, [CHARACTER.md](../CHARACTER.md)
§12). Its adapter takes the board's (`StudioBoard.adapter(pack, face)`)
and adds to it. Boop's fills the Tools drawer with review sets, recorded
on the board's frozen clock (`record({from, to, before, after})`, frames
`StudioBoard.FRAME_MS` apart) into silent WebM clips, and sound sketches.
With `--capture-dir DIR` the server saves the clips the entry's
`captures` file names into `DIR`, only from its own page, never over one.

## Writing an adapter

A pack's `scripts` load in order as plain scripts. One of them registers
the entry's adapter under the entry's `id`:

```js
Studio.register('pixel', {
  transport: 'clip',            // or 'live'
  variantLabel: 'Variation',    // what the variation picker is called
  create(ctx) { return instance; }
});
```

`ctx` has `stage` (the element to draw in), `tools` (the drawer's body,
to fill or leave empty), `root`, `onChange()` (call it when the status
should redraw), `sound`, `volume` and `loop`, `setSound(on)`, and
`selection`.

| Call | What it does |
| --- | --- |
| `select({mood, face, state, outcome, context, variant})` | Shows that cell and returns `{variants, caption}`. `mood` is what this character plays: the mood it wears, already applied |
| `status()` | The line under the stage |
| `setSound()` | Applies `ctx.sound` and `ctx.volume` |
| `destroy()` | Removes what it added to the stage and the drawer |
| `play()`, `stop()`, `playing`, `seek(t)`, `time()`, `duration` | A `clip` character's transport |
| `preview()` | Optional: plays silently on a loop, for a matrix cell |
| `paused`, `setPaused(on)` | A `live` character's transport |
| `replay()`, `poke()`, `shake()` | Optional: each shows its button |
| `faces(mood)` | Optional: `[{id, label}]`, alternate faces for a mood, with ids `mood:name` |
| `busy()` | Optional: true while the selection mustn't move, as while recording |
| `find(id)` | Optional: the selection for one of its scene ids, for `selectAsset` |

A matrix cell gets a context of its own: its cell as `stage`, a `tools`
element nobody sees, no sound. So `create` may run many times at once,
and `destroy` must leave the page as it found it.

`document.getElementById('studio').studio` is the hook browser checks
drive: `ready` (a promise), `select({...})`, `selectAsset(id, character)`
(which opens the scene), `sel`, `adapter` (the instance), `view` and
`setView(name)`, `matrix` (`{cells, playing, transport, board}`), and
`boardCell(dbgState)`.

## Checking it

`charactergen.py --check` fails when `states.json` doesn't list the
board's states (the firmware's `kStateNames`), each once; when a file a
studio entry names doesn't exist, or an entry's id is another's (a
board's is `board-<face>`); and when a `wears` file lends or borrows a
mood the pack doesn't have. Its tests are in `internal/characters/`.

The page's logic with no browser, how each state is asked of the board
and the clips the server saves, is in `tests/` (`make -C internal
tools-test` runs both):

```sh
node --test characters/studio/tests/*.test.cjs
```
