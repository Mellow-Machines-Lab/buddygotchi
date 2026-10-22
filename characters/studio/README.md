# Character Studio

Updated 2026-10-21. One page for looking at and listening to any
character pack: pick a pack, a mood and a state, and the stage plays what
the device would. The page belongs to the engine and names no character.
Each pack that wants a preview declares one in its `character.json`
([CHARACTER.md](../CHARACTER.md) §12), and a pack without one still gets
its moods, their meanings and the states.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run but `--which` (`make build` stages, which writes it) for the packs in this checkout. Git
ignores it. From the repository root:

```sh
python3 characters/charactergen.py --check
```

Then open [index.html](index.html) in a browser. It works from `file://`
with no network. To record and save review clips, use the server
instead:

```sh
node characters/studio/serve.cjs --port 4190
```

Then open `http://127.0.0.1:4190/`. `--capture-dir DIR` lets a pack's
tools save the clips its studio entry names (`captures`) into `DIR`.

## What's on the page

- **Pack**, when there's more than one here, and the **characters** for
  it: each preview the pack declares or uses (Boop's pack shows its gel slime
  and Pixel's pixel face). Switching keeps the mood and state,
  so the same moment can be compared on both.
- **Mood**: the pack's moods in their families, each with the colour its
  studio entry gives the family. When a character has no art of its own
  for a mood, its chip is dashed with an arrow, and the stage plays the
  mood the arrow names: the one its studio entry's `wears` file says it
  wears, as its faces do.
- **State**: the engine's states ([states.json](states.json)), grouped,
  each with a sentence. Task complete adds a success or failure choice;
  starting adds new task, new session or continuing.
- **Under the stage**: the mood and state, what each means, the
  variations, and the transport. A `clip` character has Play, Loop and a
  frame scrubber; a `live` one has Pause, Replay state, Poke and Shake.
- **Sound**: off until you turn it on.
- **Tools** (closed by default), when the character has any.
- **Matrix**, the other view (or <kbd>M</kbd>): every mood and state at
  once for the character shown, a cell each, made by its adapter as the
  stage is, silent, with a borrowed mood's cells dashed. Only the cells on
  screen play, at most 60 at once for a `clip` character and 12 for a
  `live` one, whose each holds one of the page's few WebGL contexts, and
  a hovered cell plays first. A cell shows its first variation; clicking
  it opens that scene. Served by `make simulator`
  ([simulator/README.md](../../simulator/README.md)), the matrix also
  marks the cell the simulated board shows now, from the board's own
  `dbg.state` once a second: no app or needs you, else a reaction
  playing, else its look (the agents' activity while working), in the
  mood its face wears, with the variation it plays; clicking the marked
  cell opens that variation. The simulator's link names the board to ask,
  `&board=/board` (`/board/NAME` for one of several); without it the page
  asks nothing.

The address keeps the selection
(`#pack=boop&c=pixel&mood=grumpy&state=working&v=2`), so a link opens the
same scene, and `&view=matrix` the matrix. Keys: ←/→ variation, ↑/↓
state, Space play or pause, S sound, P poke, M the matrix.

## Kept in sync

Nothing about a character is written here. `packs.js` comes from the
packs' `character.json` files and `states.json`, and
`python3 characters/charactergen.py --check` fails when:

- `states.json` doesn't list the board's states (the firmware's
  `kStateNames`), each once;
- a file a studio entry names doesn't exist;
- a character's `wears` file lends or borrows a mood the pack doesn't
  have. Without one, a character has art for every mood.

The other forms only warn. The rules' tests are in
`internal/characters/` (`make -C internal tools-test`).

## Writing an adapter

A pack's `scripts` load in order as plain scripts, so they work from
`file://`. One of them registers the entry's adapter under the entry's
`id`:

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

The instance has:

| Call | What it does |
| --- | --- |
| `select({mood, face, state, outcome, context, variant})` | Shows that scene and returns `{variants, caption}`: the variation picker's labels and a line under the title. `mood` is what this character plays: the mood it wears, already applied |
| `status()` | The line under the stage |
| `setSound()` | Applies `ctx.sound` and `ctx.volume` |
| `destroy()` | Removes what it added to the stage and the drawer |
| `play()`, `stop()`, `playing`, `seek(t)`, `time()`, `duration` | A `clip` character's transport |
| `preview()` | Optional: plays the scene silently on a loop, with no sound engine, for a matrix cell. Without it a `clip` cell shows its first frame; a `live` character plays by itself |
| `paused`, `setPaused(on)` | A `live` character's transport |
| `replay()`, `poke()`, `shake()` | Optional: each shows its button |
| `faces(mood)` | Optional: `[{id, label}]`, alternate faces for a mood, with ids `mood:name` |
| `busy()` | Optional: true while the selection mustn't move, as while recording |
| `find(id)` | Optional: the selection for one of its scene ids, for `selectAsset` |

A matrix cell gets a context of its own: its cell as `stage`, a `tools`
element nobody sees, no sound, and `onChange()` that does nothing. So
`create` may run many times at once, and `destroy` must leave the page
as it found it; the studio also lets go of any WebGL context left on a
cell's canvases.

`root.studio` on the page (`document.getElementById('studio').studio`) is
the hook browser checks drive: `ready` (a promise), `select({...})`,
`selectAsset(id, character)`, `sel`, `adapter` (the instance), `view`
and `setView('scene' | 'matrix')`, `matrix` (`{cells, playing,
transport, board}`), and `boardCell(dbgState)`, the cell a board's
`dbg.state` marks.

## Checking it

`check.cjs` drives the matrix in a headless browser, for every
character of every pack here: a cell for each mood and state, only cells
on screen playing and never more than the limit, the playing cells
following the scroll and a hovered one, no page errors, a click
opening the scene, and which cell a board's `dbg.state` marks. It needs Playwright (`BOOP_PLAYWRIGHT_MODULE` points
at another copy, `BOOP_QA_BROWSER` at a browser) and the server:

```sh
node characters/studio/serve.cjs --port 4190
node characters/studio/check.cjs
```
