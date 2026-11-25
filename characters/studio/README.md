# Character Studio

Updated 2026-11-25. The owner's working page for the character: its
moves, its faces and its moments, each played by the board's own
firmware, with the mood at the top and the motion layer's switches under
the board. Everything it lists comes from the pack's files, which
`charactergen.py` reads for it; nothing in the page names a clip, a face
or a skit.

What a pack lacks that doesn't stop it (clips with no group, lasting
moods with no steering file, moods with no voice takes, no signs or dream
signs) is not on the page: `charactergen.py --check` prints it as
`CHARACTERGEN GAP` lines.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run but `--which` (`make -C internal build` stages, which writes
it). Git ignores it. From the repository root:

```sh
python3 characters/charactergen.py --check
simulator/web/build.sh
python3 simulator/web/serve.py
```

Then open `http://127.0.0.1:8206/characters/studio/`. The server serves
`characters/` at `/characters/`, the simulator's build at `/simulator/`
and the staged pack's voice at `/voice.bin`. `make dev` and
`make -C internal simulator` start the same server. From `file://` the
page opens, but the board can't run there.

## What's on the page

The chosen pack's board on the stage, as big as the column allows, and
under it what plays now and why. Above everything, **Mood**: the face
every move and Moment plays in, which also sets its timing. Then three
views:

- **Moves**, where the page opens: every rig clip of the pack
  (`rig/clips/`), in the groups its `group` names, in charactergen's
  order: bases, work poses, moments, touch answers, pastimes, with you;
  a clip with no group last. ↻ marks one that loops. Type in **Find a
  move** to keep the moves whose id or `about` has your words. A base
  (`rig/looks.json`'s clip for a state, an activity or a tier) plays as
  that look, by a `state`. Any other plays by name (`dbg.clip`) over a
  look, **Over**: idle, or working for a work pose, until you pick
  another.
- **Faces**: every face the board draws, each a still at rest, at about
  the board's own size: the Mac's (the pack's `moods`) and then the
  board's own (`board_faces`), marked. The stills are drawn once, on the
  board's frozen clock, when the view first opens. A click plays the
  change to that face from the one the board shows.
- **Moments**: the pack's `skits`. Play sends a skit's Moment as the Mac
  does (`logic.js`, `momentOf`), in the mood, at the size you pick, with
  one of its takes in that face (they play with Sound on) or none: its
  `do`, its clip and its invite. Then **Answer** sends the invite's touch,
  a tap or a stroke, and **Miss** lets the wait run out, after which
  Answer is late. The line under them follows the invite on the board
  (`dbg.state`'s `invite`), and the page shows the `do` it sent and the
  `ev invite` the board reported. One Moment plays at a time, so one
  invite shows: playing another resets the board first.

**Motion** is a switch for each rule of the face's motion layer, read
from the pack's firmware (`kRules`), and **All**. A switch sends
`dbg.motion`; the board keeps it until a reset, so the page sends the
rules that are off again after each one.

**Tools**, closed, when the pack's entry adds any (below).

The address keeps the selection
(`#view=moments&mood=sad&skit=upset&size=big&off=face`), so a link opens
the same thing. Keys: <kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd> the views,
<kbd>↑</kbd>/<kbd>↓</kbd> the move, face or skit before or after,
<kbd>Space</kbd> play again, <kbd>/</kbd> find a move, <kbd>A</kbd>
answer, <kbd>M</kbd> miss, <kbd>S</kbd> sound.

## On the board

The board (`board.js`) is its firmware: the simulator's `Board`
([simulator/README.md](../../simulator/README.md)) with the staged pack's
build and its voice on the card, checked by its `hello`. Each thing the
page shows is a list of `[ms, message]` pairs (`logic.js`), which the
board plays from a `dbg.reset`, the look said again every 8 s as the Mac
does. A board that can't run says why in its pane.

## A pack's tools

A pack may add to its board's card with an entry of its own
(`"board": FACE`, its id `board-FACE`, [CHARACTER.md](../CHARACTER.md)
§12). Its `scripts` load in order, as plain scripts, and one registers
the entry's adapter, which takes the board's and adds to it:

```js
const board = StudioBoard.adapter('boop', 'gel');
Studio.register('board-gel', {...board, create(ctx) {
  const instance = board.create(ctx);
  ctx.tools.append(/* its tools */);
  return instance;
}});
```

`ctx` has `stage`, `tools` (the drawer's body), `root`, `sound`,
`volume`, `setSound(on)`, `onChange()` (call it when the status should
redraw) and `selection`. The board's instance has:

| Call | What it does |
| --- | --- |
| `play(steps)` | Plays `[ms, message]` pairs from a reset |
| `send(steps)` | Sends them now, with no reset: a touch, a switch |
| `ask(message)` | The board's answer to a message |
| `record({from, before, after})` | Frames of one of the engine's states ([states.json](states.json)), on the board's frozen clock, `StudioBoard.FRAME_MS` apart; the board is the recording's until it ends |
| `stills(faces, each)` | Each face at rest, a still to `each(face, picture)` |
| `paused`, `setPaused(on)` | Pauses the board's clock; after a recording, gives the board back to the stage |
| `setSound()`, `status()` | Applies the sound, and the line under the stage |

A tool sets `busy()` on the instance while the page mustn't change.
Boop's fills the drawer with review sets, recorded into silent WebM clips,
and sound sketches. With `--capture-dir DIR` the server saves the clips
the entry's `captures` file names into `DIR`, only from its own page,
never over one.

`document.getElementById('studio').studio` is the hook browser checks
drive: `ready` (a promise), `sel`, `select({...})`, `play()`, `answer()`,
`miss()`, `switchMotion(rule)`, `adapter` (the board's instance),
`moment` (the one playing: its invite, its stage and what the board said)
and `stills` (a promise, once the faces are drawn).

## Checking it

`charactergen.py --check` fails when `states.json` doesn't list the
board's states (the firmware's `kStateNames`), each once; when a clip's
`group` isn't one of the engine's; when a file a studio entry names
doesn't exist, or an entry's id is another's (a board's is
`board-<face>`). Its tests are in `internal/characters/`.

The page's logic with no browser is in `tests/` (`make -C internal
tools-test` runs it): the moves from the pack's clips, the faces sheet's
24, each skit's `do`, the motion switches' messages, an invite answered
and missed on the simulator's build (skipped until
`simulator/web/build.sh` has made it), how each state is asked for a
review clip, and the clips the server saves. A skit's `do` is pinned on
both sides to `tests/moments.json`: here against `logic.js`, and in
`StudioMomentTests` against what the Mac's `MomentOutput` sends.

```sh
node --test characters/studio/tests/*.test.cjs
```
