# Character Studio

Updated 2026-10-24. One page for looking at and listening to any
character pack: pick a pack, a mood and a state, and the stage plays what
the device would. The page belongs to the engine and names no character.
Each pack that wants a preview declares one in its `character.json`
([CHARACTER.md](../CHARACTER.md) §12), and a pack without one still gets
its moods, their meanings and the states, and the board's own preview of
each face its boards have. Beside the scene and the matrix it's where
the character is worked on: transitions measured on the board, the
references people gave (§16), and what's up for review.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run but `--which` (`make build` stages, which writes it) for the packs in this checkout. Git
ignores it. From the repository root:

```sh
python3 characters/charactergen.py --check
```

Then open [index.html](index.html) in a browser. It works from `file://`
with no network, but for the board, whose firmware a page opened from a
file can't load, and saving a verdict. For those, and to record and save
review clips, use the server instead:

```sh
node characters/studio/serve.cjs --port 4190
```

Then open `http://127.0.0.1:4190/`. It serves `characters/`, and the
simulator's build at `/simulator/` (`simulator/web/dist/`, which
`simulator/web/build.sh` makes for the staged pack and
`simulator/web/build.sh PACK` for another; `make -C internal sim-test`
makes both of this checkout's). `--capture-dir DIR` lets a pack's tools
save the clips its studio entry names (`captures`) into `DIR`. `make
simulator`'s server serves the studio too, the board included, but
saves no verdicts.

## What's on the page

- **Pack**, when there's more than one here, and the **characters** for
  it, two a row: each preview the pack declares or uses (Boop's pack
  shows its gel slime and Pixel's pixel face), and then a board for each
  face its boards have (On the board, below). Switching keeps the mood
  and state, so the same moment can be compared on all of them.
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
  `live` one, whose each holds one of the page's few WebGL contexts, a
  hovered cell first, then those wholly on screen. A cell shows its first variation; clicking
  it opens that scene. Served by `make simulator`
  ([simulator/README.md](../../simulator/README.md)), the matrix also
  marks the cell the simulated board shows now, from the board's own
  `dbg.state` once a second: no app or needs you, else a reaction
  playing, else its look (the agents' activity while working), in the
  mood its face wears, with the variation it plays; clicking the marked
  cell opens that variation. The simulator's link names the board to ask,
  `&board=/board` (`/board/NAME` for one of several); without it the page
  asks nothing.

- **Transitions** (on the board): a start, a mood and a state, and an
  end, a mood and a state or a reaction (task complete, notice…), on the
  board's own firmware. It plays the start for 2 s on the board's frozen
  clock, asks for the end as the Mac would, and records a frame every
  40 ms, 5 before the change and 100 after: the frame under a scrubber,
  a bar for each frame's change from the one before (pixels whose
  difference's luma is over 24 levels, as `internal/tools/fluid/measure.py`
  counts them, the change's bar marked), and the frames in a strip. A
  frame several times the median is a jump. Beside it, **Rank** records
  the everyday transitions, `internal/tools/fluid/transitions.jsonl`'s
  so that the two measures compare (to working, a mood change, a finish
  in its own mood, back to idle from it, a poke, a stroke, to asleep:
  its shots' names, which charactergen reads for the page,
  `everyday()`), on the same board, their changes only, and
  lists them as each comes, the **jumpiest** first: by the ratio of the
  largest frame to the median, the same rule as `measure.py`'s; clicking
  one records it here.
- **References**: each of the pack's references (CHARACTER.md §16), its
  status, kind and note, the agent's reading (its `reading.md`, rendered
  by `markdown.js`: headings, paragraphs, lists, tables and code) and
  what it became. Side by
  side, the reference's media and the board playing its `show`, recorded
  on the frozen clock over as many frames as the reference has, 25 (a
  second) at the least, with one scrubber and one Play for both, frame
  for frame: the reference's frames (`frames/<file>/`), or before it's
  read the file itself, a video seeking to the frame's time.
- **Review**: the pack's `review/queue.json`, each item with its before
  and after, its verdicts so far and a comment box: Approve, or Ask for a
  change, which needs a comment. The server appends each to
  `review/notes.jsonl`, where the agents read them. From `file://` the
  page shows the queue and the notes charactergen last saw, and says to
  use the server to comment.

The address keeps the selection
(`#pack=boop&c=pixel&mood=grumpy&state=working&v=2`), so a link opens the
same scene, and `&view=matrix`, `transitions`, `references` or `review`
that view: a transition with its pair
(`&view=transitions&from=calm/working&to=excited/task_complete/failure`,
mood/state and a fact for a state with one) and a reference by its
folder (`&view=references&ref=2026-10-24-notice-perk`). The board's views
run on the character shown when it's a board, else on the pack's first
board. Keys: ←/→ variation, ↑/↓ state, Space play or pause, S sound, P
poke (in the scene), M the matrix.

## On the board

The board's preview (`board.js`) is its firmware itself: the simulator's
`Board` ([simulator/README.md](../../simulator/README.md)), the pack's
build (`boop-sim-PACK.js`, or `boop-sim.js` for the staged pack, checked
by its `hello`), powered on with the face; the page compiles each
build's WebAssembly once for all its boards. It takes each of the
studio's states as the Mac and a finger would ask for it: a look is a
`state` (the activity while working, an act the firmware draws, needs
you an `attn`), a reaction a `do` over working (idle for waking up), or
as a transition's end over its start's look, in its own mood, a poke or
taps in a row or a stroke a touch, where the simulator taps, and no Mac
30 s with no state. On the stage it plays from a
`dbg.reset`, its clock running, says its state again as often as the
simulator's page does, and picks its own variations; a matrix cell
steps its clock 100 ms ten times a second, so twelve can play at once.
Its sound is the firmware's own effects (the board has no voice file on
its card here). A board that can't run (from `file://`, or with no build)
says why in its pane, where it would be. The views record on the stage's board, which rests while
they're shown, one recording at a time, and back in the scene it plays
the selection from a reset again, paused if it was paused before.
Recording, they freeze its clock and step it a frame at a time, as the
simulator's scenarios do, so a recording is
the same every time; each frame's change is counted as it comes, and its
picture kept as an `ImageBitmap`.

## Kept in sync

Nothing about a character is written here. `packs.js` comes from the
packs' `character.json` files, references, review queues and notes,
`states.json`, the acts the board draws while working (the firmware's
`actFromName`), the frames' 40 ms (charactergen's `FRAME_MS`, a
reference's too) and the everyday transitions Rank records (those
`internal/tools/fluid/transitions.jsonl` records, `everyday()`), and
`python3 characters/charactergen.py --check`
fails when:

- `states.json` doesn't list the board's states (the firmware's
  `kStateNames`), each once;
- a file a studio entry names doesn't exist, or an entry's id is
  another's (a board's is `board-<face>`);
- a character's `wears` file lends or borrows a mood the pack doesn't
  have. Without one, a character has art for every mood;
- a reference, review item or note breaks CHARACTER.md §16's rules.

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
and `setView(name)`, `matrix` (`{cells, playing, transport, board}`),
`views` (each other view's state: `transitions`' `frames`, `changes`,
`ranked` and `ranking`, `references`' `board`, `review`'s `notes`), and
`boardCell(dbgState)`, the cell a board's `dbg.state` marks.

The server streams each file, a part of it for a `Range` (as a video
seeks), and caches nothing. Its `POST /review` takes `{"pack", "id",
"verdict": "approve" | "change", "text"}` from the studio's own page
(its origin, as JSON): an id in the pack's queue, and a comment for a
change. It appends the note with its time, `{"at", "id", "verdict",
"text"}`, and answers with it; `GET /review?pack=PACK` is the notes so
far.

## Checking it

`check.cjs` drives the matrix in a headless browser, for every
character of every pack here, the boards included: a cell for each mood
and state, only cells on screen playing and never more than the limit,
the playing cells following the scroll and a hovered one, no page
errors, each build's WebAssembly fetched once, a click opening the
scene, and which cell a board's `dbg.state` marks. Then the board's
views on Boop's gel: a transition's 106 frames and their changes, the
address keeping the pair, Rank listing the everyday transitions as they
come, the jumpiest first, and the jumpiest opened, measuring as it
ranked; the stage's board back in the scene after a view recorded on
it, playing, and paused if it was; a reference with the board recorded
beside it, one scrubber
moving both, and its reading rendered from its Markdown (a heading and a
table for each of its own, no marks left); a review item's images and a
verdict through the page (the server's answer stood in for, so nothing
is saved); and the page from `file://`, the reading shown, the comment
box saying to use the server, the board saying so in its pane and not
again under it, and Boop's four characters' cards two by two. It needs Playwright (`BOOP_PLAYWRIGHT_MODULE` points at another
copy, `BOOP_QA_BROWSER` at a browser), the simulator built (above) and
the server; `BOOP_QA_SHOTS=DIR` saves a screenshot of each view:

```sh
node characters/studio/serve.cjs --port 4190
node characters/studio/check.cjs
```

The logic needs no browser: the change measure and its summary, held to
the rule `measure.py`'s test is (`internal/tools/fluid/tests/changed.json`),
how each state is asked of the board, the server, in a copy of it
beside a pack of its own (its verdicts, which charactergen's review
check then takes, and its files in part), and `markdown.js`'s rendering
(`make -C internal tools-test` runs it):

```sh
node --test characters/studio/tests/*.test.cjs
```
