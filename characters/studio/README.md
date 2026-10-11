# Character Studio

Updated 2026-10-11. One page for looking at and listening to any
character pack: pick a pack, a mood and a state, and the stage plays what
the device would. The page belongs to the engine and names no character.
Each pack that wants a preview declares one in its `character.json`
([CHARACTER.md](../CHARACTER.md) §12), and a pack without one still gets
its moods, their meanings and the states.

## Open it

The page reads `packs.js`, which `characters/charactergen.py` writes on
every run (`make build` runs it) for the packs in this checkout. Git
ignores it. From the repository root:

```sh
python3 characters/charactergen.py
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
  it: each preview the pack declares (Boop's pack shows its gel slime
  and its copy of the pixel face). Switching keeps the mood and state,
  so the same moment can be compared on both.
- **Mood**: the pack's moods in their families, each with the colour its
  studio entry gives the family. When a character has no art for a mood,
  its chip is dashed with an arrow, and the stage plays the mood the
  arrow names: the mood's `fallback`, the one the app uses.
- **State**: the engine's states ([states.json](states.json)), grouped,
  each with a sentence. Task complete adds a success or failure choice;
  starting adds new task, new session or continuing.
- **Under the stage**: the mood and state, what each means, the
  variations, and the transport. A `clip` character has Play, Loop and a
  frame scrubber; a `live` one has Pause, Replay state, Poke and Shake.
- **Sound**: off until you turn it on.
- **Tools** (closed by default), when the character has any.

The address keeps the selection
(`#pack=boop&c=pixel&mood=grumpy&state=working&v=2`), so a link opens the
same scene. Keys: ←/→ variation, ↑/↓ state, Space play or pause, S sound,
P poke.

## Kept in sync

Nothing about a character is written here. `packs.js` comes from the
packs' `character.json` files and `states.json`, and
`python3 characters/charactergen.py --check` fails when:

- `states.json` doesn't list the board's states (the firmware's
  `kStateNames`), each once;
- a file a studio entry names doesn't exist;
- a character can't play one of the pack's moods in some state, even
  through the mood's `fallback`. A pack's `coverage` file says which
  pairs it has art for; without one, it has them all.

The other forms only warn. The rules' tests are in
`internal/characters/` (`make -C internal tools-test`).

## Writing an adapter

A pack's `scripts` load in order as plain scripts, so they work from
`file://`. One of them registers the entry's adapter under the entry's
`id`, which is the pack's id unless the pack declares several previews:

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
| `select({mood, face, state, outcome, context, variant})` | Shows that scene and returns `{variants, caption}`: the variation picker's labels and a line under the title. `mood` is what this character plays, its fallback already applied |
| `status()` | The line under the stage |
| `setSound()` | Applies `ctx.sound` and `ctx.volume` |
| `destroy()` | Removes what it added to the stage and the drawer |
| `play()`, `stop()`, `playing`, `seek(t)`, `time()`, `duration` | A `clip` character's transport |
| `paused`, `setPaused(on)` | A `live` character's transport |
| `replay()`, `poke()`, `shake()` | Optional: each shows its button |
| `faces(mood)` | Optional: `[{id, label}]`, alternate faces for a mood, with ids `mood:name` |
| `busy()` | Optional: true while the selection mustn't move, as while recording |
| `find(id)` | Optional: the selection for one of its scene ids, for `selectAsset` |

`root.studio` on the page (`document.getElementById('studio').studio`) is
the hook browser checks drive: `ready` (a promise), `select({...})`,
`selectAsset(id, character)`, `sel` and `adapter` (the instance).
