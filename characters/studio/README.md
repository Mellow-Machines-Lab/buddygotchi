# Character Studio

Updated 2026-10-25. One page for everything a character pack makes its
character: who it is, how it feels, what it does and why, how it looks,
what it says, and the tests that hold it to all that. Pick a pack, and its
tabs show what's its own: its personality, its moods and what moves them,
what sets each thing it does off and who decides it, what its brain reads
and answers, every mood and state
as the device plays them, its signs, diary and voice, its evals and
demos. The page belongs to the engine and names no character: the
engine's lists (the states, the tags) only order what the pack fills in,
so another pack fills the same page. Each pack that wants a preview
declares one in its `character.json` ([CHARACTER.md](../CHARACTER.md)
§12), and a pack without one still gets everything else, and the board's
own preview of each face its boards have. It's also where the character
is worked on: transitions measured on the board, the references people
gave (§16), and what's up for review.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run but `--which` (`make -C internal build` stages, which writes it) for the packs in this checkout. Git
ignores it. From the repository root:

```sh
python3 characters/charactergen.py --check
```

The Behavior tab's Brain view also reads `prompts.js`, what the brain
reads and answers at every pass of the evals, which `boopdev prompts`
writes (`make dev` does it for you). Git ignores it too:

```sh
make -C internal app && .build/debug/boopdev prompts
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

The character first (**Boop** | **Pixel**, when there's more than one
pack here), then eight tabs, each opening on its first view; a tab with
more than one has a button for each, and leaves out a view the pack has
nothing for (Stills, for a pack with no golden frames):

- **Overview**: the character's card. Its face, in its resting mood,
  idle, on any of its previews; its name, version and what its first
  personality says it is; the mood it wakes up in and rests in, the face
  each board wears and what it borrows (§6). Then how much it has of
  each part, in rows by tab, each opening it, and **Worth a look**: what
  it's missing (moods a preview has no art for, moods with no steering
  file or no voice takes, one nature only, no signs or diary) or waiting
  on you (review).
- **Personality**: each personality (`steering/personality/`), its
  settings in plain words (`working_heartbeat` 90-180 is "checks in on a
  turn every 1½–3 min"), its words, a paragraph's first sentence and the
  rest as points, and its Examples as cards, what happened and after the
  arrow what it does, six at first. Then the natures, side by side, and
  the guide, folded.
- **Moods**: the moods in their families, and the one picked: its
  meaning and face, its preview idle in it, and its map, the moods it can
  move to (`moves`), ordinary ones on the inner ring and dramatic ones,
  dashed, on the outer, each opening its mood, with the moods it's
  reached from under it. Then its steering file in parts, by how each
  sentence starts (charactergen's `mood_steering()`): what it is, its
  faces, what it says, how it acts, what it stays through, each mood it
  leaves for and when, and when it fades. Its links open every state in
  it (Animations), its voice takes and the evals that expect it.
- **Behavior**: the engine's, not the pack's, so every pack shows the
  same, with its own personalities' settings and scenarios. **Map**: the
  screen's layers, top first (no Mac, listening, needs you, a reaction,
  the look), then everything that puts something on the screen, by what
  sets it off (your agents, you at the Mac, your hand on the board, time
  passing): who decides it, a rule on the Mac, the brain or the board,
  each state it plays (opening it in Animations), what the brain makes of
  it (its wake, from the transcript view's own table), its numbers, read
  from the code that keeps them, and what else the same moment sets off.
  Filtered by who decides, or to where several do. The map's words are
  `behavior.json`'s. **Brain**: when it's asked, its pacing and what wakes
  it, and an eval scenario's passes (`prompts.js`, above), each the prompt
  as Jev read it, in its sections, and every question asked with its
  options, the answer the expect brain gave marked. An eval in Tests
  links to its passes.
- **Animations**: **Scene**, **Matrix**, **Transitions** and
  **Stills**, below, with the pack's previews' cards over them: each
  preview the pack declares or uses (Boop's pack shows its gel board,
  with the slime's tools, and Pixel's pixel face), and then a board for
  each face its boards have that it hasn't declared (On the board,
  below). Switching keeps the mood and state, so the same moment can be
  compared on all of them.
- **Words**: **Signs**, each caption drawn as a sign with your words
  filled in (`{words}`, `{WORDS}`), filtered by a tag; **Diary**, each
  line filled in for a sample day; and **Voice**, how many takes the
  voice has in each mood, of each kind, a cell's takes (or those a
  search finds) each with its words, what it answers and the finish it
  needs, and a Play that reads the take from the voice file in part
  (`voice.bin`, by its index, with HTTP ranges), so it needs the
  studio's own server (the simulator's, `simulator/web/serve.py`,
  reads no ranges). A pack that uses another's voice (§6) shows that one.
- **Tests**: **Evals**, each scenario (`evals/`) with its case, why,
  and each step's event and what it expects, filtered by always or a
  search, or from Moods by the mood its steps expect; and **Demos**, each
  script (`demo/`) told step by step, the agent, you and what the brain
  answers, with the command that plays it.
- **Workbench**: **References** and **Review**, below.

The scene's own parts:

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
- **Matrix**, the other view (or <kbd>M</kbd> in Animations): every mood and state at
  once for the character shown, a cell each, made by its adapter as the
  stage is, silent, with a borrowed mood's cells dashed. Only the cells on
  screen play, at most 60 at once for a `clip` character and 12 for a
  `live` one, whose each holds one of the page's few WebGL contexts, a
  hovered cell first, then those wholly on screen. A cell shows its first variation; clicking
  it opens that scene. Served by the simulator's server (`make dev`, or `make -C internal simulator`)
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
- **Stills**: the frames the pack's tests hold its faces to
  (`tests/golden-*/<group>/`), a group at a time: what each face draws,
  occasions and gestures among them.
- **References**: each of the pack's references (CHARACTER.md §16), its
  status, kind and note, the agent's reading (its `reading.md`, rendered
  by `markdown.js`: headings, paragraphs, lists, tables and code) and
  what it became. Side by
  side, the reference's media and the board playing its `show`, recorded
  on the frozen clock over as many frames as the reference has, 25 (a
  second) at the least, with one scrubber and one Play for both, frame
  for frame: the reference's frames (`frames/<file>/`), or, before it's
  read or where its frames aren't cut (they aren't committed), the file
  itself, a video seeking to the frame's time.
- **Review**: the pack's `review/queue.json`, each item with its before
  and after, its verdicts so far and a comment box: Approve, or Ask for a
  change, which needs a comment. The server appends each to
  `review/notes.jsonl`, where the agents read them. From `file://` the
  page shows the queue and the notes charactergen last saw, and says to
  use the server to comment.

The address keeps the selection
(`#pack=boop&c=pixel&mood=grumpy&state=working&v=2`), so a link opens the
same scene, and `&view=` any view by its name (`scene`, `matrix`,
`moods`, `behavior`, `brain`, `voice`…; none is the overview), and a view's own choice with it:
the map's row (`&view=behavior&row=tool-failed`), a scenario's pass
(`&view=brain&scenario=03-turn-failed&pass=2`),
Voice's mood and kind (`&view=voice&takes=grumpy&kind=word`), the evals
expecting a mood (`&view=evals&expects=grumpy`), a still's group
(`&view=stills&group=gel/occasions`), a transition with its pair
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

A pack may add to one of its boards' cards with an entry of its own for
that board (`"board": FACE`, its id `board-FACE`, [CHARACTER.md](../CHARACTER.md)
§12): its label, icon, families and the clips the server may save for it,
and scripts whose adapter, registered under the board's id, takes the
board's (`StudioBoard.adapter(pack, face)`) and adds to it. Boop's
(`characters/boop/studio/adapter.js`) fills the drawer with the slime's
review sets, recorded from the board on its frozen clock (`record`) and
played into silent WebM clips, and its sound sketches, each played on its
own.

## Kept in sync

Nothing about a character is written here. `packs.js` comes from the
packs' `character.json` files, their steering (the personalities,
natures, guide, each mood's file, signs and diary), the voice each has or
uses (its `mac/takes.tsv`, once for every pack that uses it), their
demos, evals and golden frames, references, review queues and notes,
`states.json`, the acts the board draws while working (the firmware's
`actFromName`), the frames' 40 ms (charactergen's `FRAME_MS`, a
reference's too) and the everyday transitions Rank records (those
`internal/tools/fluid/transitions.jsonl` records, `everyday()`), the
behaviour map (`behavior.json`, the engine's, with each number's value
from its code, each brain's wake from the transcript view's `wakes` and
`quiet`, and the personality settings Personality reads), and
`python3 characters/charactergen.py --check`
fails when:

- `states.json` doesn't list the board's states (the firmware's
  `kStateNames`), each once;
- a file a studio entry names doesn't exist, or an entry's id is
  another's (a board's is `board-<face>`);
- a character's `wears` file lends or borrows a mood the pack doesn't
  have. Without one, a character has art for every mood;
- a reference, review item or note breaks CHARACTER.md §16's rules;
- `behavior.json` names a decider, state (or a fact of one), row, kind
  of event or personality setting that isn't one, or a number its code
  doesn't declare (a number names its file and its constant, or a
  `find` pattern for one in a table, and charactergen reads the value
  there, so the page never says one the code doesn't); or a state of the
  board's has nothing that plays it.

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

`check.cjs` drives the character's own views in a headless browser, for
both packs: the page opening on the overview, each tab opening its first
view with its buttons (Stills only for a pack with golden frames), each
view drawing, a mood's map opening another, its links opening its voice
takes, the address keeping them, and a take played from the voice file,
and the evals that expect it; the behaviour map's rows, all and the
brain's, a personality's setting in words, a row naming another opening
it, a state opening its scene, and an eval opening its passes in Brain,
each pass's HISTORY and NOW and every question it asked. Then the matrix, for every
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
again under it, and Boop's three characters' cards two to a row, its gel
board first. And Boop's gel board's drawer: its two review sets, one clip
recorded from the board and stopped after it, and its eleven sound
sketches. It needs Playwright (`BOOP_PLAYWRIGHT_MODULE` points at another
copy, `BOOP_QA_BROWSER` at a browser), the simulator built (above),
`boopdev prompts` run (above) and the server; `BOOP_QA_SHOTS=DIR` saves a screenshot of each view:

```sh
node characters/studio/serve.cjs --port 4190
node characters/studio/check.cjs
```

The logic needs no browser: the change measure and its summary, held to
the rule `measure.py`'s test is (`internal/tools/fluid/tests/changed.json`),
how each state is asked of the board, the server, in a copy of it
beside a pack of its own (its verdicts, which charactergen's review
check then takes, its files in part, and the review clips it saves: only
with `--capture-dir`, only those a pack names, from its own page with its
token, a WebM by its header, at most 8 MiB, never over a file, and an
upload gone quiet closed at 15 s), and `markdown.js`'s rendering
(`make -C internal tools-test` runs it):

```sh
node --test characters/studio/tests/*.test.cjs
```
