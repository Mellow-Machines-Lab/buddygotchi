# Characters: the pack spec

Updated 2026-10-15. The contract a character pack meets, so that any
character can be dropped into the engine. The engine never knows *who*
the creature is: the pack says its moods, how it looks and sounds, and
who it is. Choose a pack (§2), and the Mac app, the board's firmware and
the simulator all use it.

## At a glance

What a pack holds, and what it must have:

| Path | Must have | What it is |
| --- | --- | --- |
| `character.json` | yes | Its id, name, moods and how they connect (§4–5) |
| `steering/guide.md` | yes | How it reads the moment, for the brain (§7) |
| `steering/personality/<id>.md` | yes, one for each personality | Who it is (§7) |
| `steering/mood/<mood>.md` | no | How it acts in a mood; a missing one reads as the resting mood's (§7) |
| `firmware/` | yes | Its faces' code and art for the board, and `include/moods.h`, which `charactergen.py` makes (§9) |
| `mac/faces.json` | yes | The pixel face's timings and the popover's still faces (§9) |
| `mac/mirror/` | no | A web page the popover shows as the face (§9) |
| `mac/takes.tsv` and `voice/voice.bin` | no, both or neither | Its recorded voice (§8) |
| `demo/<name>.jsonl` | no | Its demos ([DEMOS.md](DEMOS.md)) |
| `studio/` and `studio` in `character.json` | no | Its preview in the Character Studio (§12) |
| `LICENSE` | no | The pack's own licence; without one, the repository's MIT licence (§11) |
| `design/`, `tools/`, `tests/`, `evals/` | no | What its art and sounds are made from, and its own tests |

To make one, copy Pixel's (§14). To check one:

```sh
make build && .build/debug/boopdev check            # every pack in characters/
.build/debug/boopdev check path/to/pack             # one pack, anywhere
```

`boopdev check` reads a pack as the engine does: `character.json`, the
steering, the faces' files, the voice, every demo, and the generated
files (`charactergen.py --check`). A pack that passes plugs in. Then
build the firmware with it, to check its faces:
`CHARACTER=<name> make -C internal fw-test`. The engine's own Swift tests
(`make -C internal test`) run on whichever pack is chosen, using its
name, moods and steering. Every pack has the same moods (§5), so they run
them all. A test of one pack's own content (Boop's evals, goldens and
graph) skips for any other pack, and a test that plays recorded takes
skips for a pack with no voice; each says why.

## 1. The idea

The engine is the code: the hooks, the core's rules, the brain's
harness, the device link and the drawing loop. It never knows *who* the
creature is. It knows what's happening, and at a few fixed points it asks
the loaded character:

1. **Which moods can you be in, and what does each mean?** The brain
   picks one.
2. **How do you look in this state, in this mood?** The screen draws it.
3. **How do you sound?** Sound effects, and a voice if it has one.
4. **Who are you?** The prompts that shape the brain's choices.

A character pack is a folder that answers those four questions in the
shapes below. The engine carries the pack's answers between the brain and
the face, and never reads their meaning. A mood is a name it passes
along.

**Fixed by the engine, the same for every character:**
- The **states**: what the agents are doing (`idle`, `working`,
  `needs_you`, `testing` and the rest).
- The **moods**' names: the same 42 for every character (§5).
- When states change (the core's rules).
- *That* a mood is picked after events.
- The protocol.

**Decided by the pack:**
- How each state looks and sounds.
- What each mood means, how the moods connect and how fast they move.
- Its prompts, and whether it has a voice.

Two packs come with the engine's repo, and both are public:
- **`characters/boop/`**, the default: Boop's own, the gel slime, with
  its prompts, evals and goldens, and what its art and voice are made
  from.
- **`characters/pixel/`**, with Pixel Boop's faces and sound effects,
  plain prompts and a recorded voice. It's the example to copy. Its art
  and the voice cover 13 of the moods for now; each of the others borrows
  one of those 13's (§8, §9).

## 2. Choosing a pack

The first of these wins:

1. `BOOP_CHARACTER=<path>` for a pack anywhere, or `CHARACTER=<name>`
   for `characters/<name>/`, in the environment or on a `make` command
   line.
2. The name or path in `.character` at the repo root, a one-line file
   that git ignores. It's how `make run` remembers your choice.
3. `characters/boop/`.

`python3 characters/charactergen.py --stage` lays the chosen pack out in
`.character-build/` at the repo root (also ignored): the pack's
`firmware/`, the folder the app bundles (`packs/`, that pack alone), and
`pack`, the one pointer to the pack's own folder. The builds read only
from there. `firmware/tools/pio.sh` stages before every PlatformIO run,
and `make build` before every app build. The app bundles only what it
reads of the pack (not its firmware, voice pack, tools or tests).

Everything that runs after a build, the tests, `boopdev`, the device
tools and the simulator, reads the **pack in use**: the one the
environment chooses (`BOOP_CHARACTER` or `CHARACTER`), else the one
`pack` points to, else the chosen one (nothing staged yet). So a change
to `.character` waits for the next stage. `charactergen.py` keeps this
rule (`in_use()`), and `--which` prints its answer; the Python tools
import it, the shell and Node call `--which`, the Swift tests read the
environment and then the pointer, and the C++ tests, which run only
after a stage, read the pointer. `Boop` itself takes `BOOP_CHARACTER`
when it starts, else its bundled pack, so one build can play any pack's
demo. Staging also links the pack's own firmware
tests (`tests/firmware/test_*`) beside the engine's, so
`make -C internal fw-test` runs both; `make -C internal tools-test` runs
the Python tests in a pack's `tests/tools/`.

The Mac reads its pack when it starts, so switching means restarting.
The board's face is compiled into its firmware, so switching faces means
flashing again. A voice lives on the board's microSD card: copy the
pack's `voice/voice.bin` to the card as `boop/voice.bin` with a card
reader, or over USB with `internal/tools/boopctl card`, which is slow.

## 3. The folder

```
<pack>/
  character.json     who it is, its moods and how they connect (§4–5)
  LICENSE            optional: the pack's own licence (§11)
  steering/          what the brain reads (§7)
    guide.md
    personality/<name>.md
    mood/<mood>.md
  mac/               what the app reads at run time (§9)
    faces.json       the popover's face designs
    mirror/          optional: a web page the popover shows as the face
    takes.tsv        optional: the voice's take table (§8)
  firmware/          what the firmware compiles in (§9)
    include/moods.h  the mood list, generated (§9)
    include/…        the faces' generated art and sounds
    src/render/…     the faces' code, and make_face.cpp, which picks one
  voice/voice.bin    optional: the microSD card's voice pack (§8)
  studio/            optional: the studio's preview adapter (§12)
  design/, tools/    optional: what the pack's art and sounds are
                     made from, and the tools that make them
  tests/, evals/     optional: the pack's own goldens, eval scenarios
                     and tests (tests/firmware/, tests/tools/)
```

The engine reads built files only. How a pack makes them (by hand, a
script or a design tool) is the pack's business. A pack commits its built
files, so building the engine never needs the pack's own tools, or what
they were made from: the voice's recordings are in neither pack's built
files (§8).

## 4. `character.json`

Pixel's, `characters/pixel/character.json`, cut to the first of its 42 moods:

```json
{
  "id": "pixel",
  "name": "Pixel",
  "version": "0.1.0",
  "default_mood": "calm",
  "startup_mood": "happy",
  "personalities": [
    {
      "id": "pixel",
      "about": "Reacts to what stands out, and stays quiet otherwise."
    }
  ],
  "moods": [
    {
      "id": "calm",
      "meaning": "Settled, the resting mood: nothing much is happening.",
      "face": "A calm face: all quiet.",
      "family": "settled",
      "moves": {
        "ordinary": [
          "comfy",
          "curious",
          "engaged",
          "pleased",
          "tired",
          "uneasy",
          "happy",
          "annoyed"
        ],
        "dramatic": [
          "surprised",
          "wounded",
          "excited",
          "sad"
        ]
      }
    }
  ]
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lower case, digits and `-`. The board reports it (§10) |
| `name` | yes | What the app shows |
| `version` | yes | The pack's version. A Mac and a board with different versions of the same pack fall back safely (§10) |
| `default_mood` | yes | The resting mood: a new state folder starts in it, every mood fades toward it, and an unknown mood reads as it |
| `startup_mood` | no | What the board shows before the Mac sends a mood, and for a name it doesn't know. Without it, `default_mood`. Boop's is `happy`, as the board always started |
| `personalities` | yes | The personalities, each a name or `{"id": name, "about": one line}`, with a file each in `steering/personality/`. The first is the default. `about` is what Settings says it does |
| `moods` | yes | Every universal mood, once, in any order (§5). Its order is the firmware's `Mood` order |
| `studio` | no | The pack's preview in the Character Studio (§12). Only the studio reads it |

Unknown keys are ignored, so a newer pack still loads in an older engine.

## 5. Moods

Every pack has the same moods: the universal list,
`CharacterPack.universalMoods` in `app/BoopKit/Character/Moods.swift`,
the one place the names are written (`charactergen.py` reads them from
there). A pack has each of them once, and no other: the app's loader,
`boopdev check` and `charactergen.py` refuse a pack that doesn't. What
each means, how they connect and how each looks and sounds is the pack's.
The engine never stands one mood in for another.

Each mood in `moods`:

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Its name, as the brain and the protocol see it: lower case and `_` |
| `meaning` | yes | When the character is in it: the option text when the brain picks a mood |
| `face` | no | What this mood's face means for a single moment: the option text when the brain picks a reaction's face. Without it, `meaning` |
| `not_for` | no | When the mood isn't meant, added to the `mood` question's option |
| `face_not_for` | no | When the face isn't meant, added to the face's option |
| `family` | no | A group of related moods (`joy`, `frustration`…), for designers; the engine doesn't read it |
| `moves` | yes | `ordinary` and `dramatic` neighbours: the moods it can move to in one step. Staying is always allowed. A dramatic move needs a fresh, big event |

The `mood` question offers staying and every move from the current
mood, the dramatic ones saying they need a fresh, big event; pacing, how
long a mood holds and when it fades, is the steering's (§7). Pixel's
moves are a copy of Boop's for now.

## 6. A pack stands alone

A pack is self-contained. The engine reads every file of a pack from the
pack's own folder, and never falls back to another pack's. Two packs
that share something each carry a copy, and each copy can change without
the other.

Boop's pack shares two things with Pixel's, and has its own copy of
both:

- **The pixel face**, which Boop wears on the CYD (on the AMOLED it
  brings its own, the gel slime): the firmware's pixel renderer, faces
  and sound effects, `mac/faces.json`, and the studio's preview of the
  face. They're Pixel's built files as they are.
  `characters/boop/tools/pixelsync/pixelsync.py` copies them again when
  Pixel's change and Boop should follow, and its `--check`, which the
  pack's tests run, says which differ.
- **The voice** (§8).

## 7. Steering

What the brain reads, in plain Markdown, as now:

- `guide.md` (required): how the creature reads the moment, read on
  every pass.
- `personality/<name>.md` (one per name in `personalities`): who it is,
  with front matter for the view's rules (`working_heartbeat`,
  `tool_uses`).
- `mood/<mood>.md` (one per mood): how it acts while in that mood,
  what moves it, and when it fades. A missing file reads as
  `default_mood`'s.

The budgets are the same for every pack. The engine logs a
file over budget and still uses it.

## 8. Voice (optional)

A pack with a voice has recorded takes, each tagged with the moods it
plays in, a feeling, a topic and a kind:

- `voice/voice.bin` is the microSD card's pack.
- `mac/takes.tsv` is its table, which the Mac reads to pick a take. Its
  first line holds the pack's version, the same one the board reports.

Both are built files and checked in. Pixel's pack and Boop's each have a
copy of the same voice, 2,722 takes. What they're built from stays out
of both: the recordings, and voicegen, the tool that turns them into the
two files, are kept in Boop's pack, and one run of it writes
both packs' copies.

A pack without a voice leaves both out. The brain is then never asked
what to say (`react` drops its `say.*` questions), and reactions play
faces and sound effects only. A pack with a voice has takes for every
mood: Voice picks only takes whose moods include the face's. A take
recorded in one mood may play in others: the table's moods column lists
them all. The takes were recorded in 13 moods, so for now voicegen lends
each to the moods that borrow its mood in Pixel's temporary table,
`characters/pixel/tools/borrowed.json`. Only the table changes: the
audio and the version stay the same.

## 9. Faces

A face is what the board draws and the sounds it makes. The engine says
*what* to show: a mood and a state. The face decides how that looks.

### Every state a face is asked for

The engine asks a face for any of the pack's moods (§5) with any of
these 22 states. A face must answer for all of them, in every mood. It may draw the same design for several: the pixel face has art
for all 22, and the gel face maps some to others in its own code
(`router.cpp`). The names are the firmware's (`firmware/src/render/types.cpp`),
and `charactergen.py --check` holds this table to them.

**Looks** last until the next one. They show when no moment plays.

| State | When it shows | Sent by |
| --- | --- | --- |
| `idle` | Agents are open, and none is working | the Mac |
| `asleep` | No agent sessions at all | the Mac |
| `working` | An agent works, with nothing more specific to show | the Mac |
| `planning` | An agent is planning | the Mac |
| `terminal` | An agent runs a shell command | the Mac |
| `tool_use` | An agent uses a tool, such as an edit | the Mac |
| `searching` | An agent searches the web | the Mac |
| `analyzing` | An agent reads or searches files | the Mac |
| `testing` | An agent runs tests | the Mac |
| `delegating` | An agent hands work to a helper | the Mac |
| `waiting` | A tool takes its time; nothing is asked of you | the Mac |
| `needs_you` | An agent waits for your approval or answer on the Mac | the Mac |
| `no_app` | The board has lost the Mac | the board |

**Moments** play once over the look, or `loops` times (1 to 6), then go.

| State | When it plays | Sent by |
| --- | --- | --- |
| `starting` | An agent starts; `ctx` says how: `new_task`, `session`, `continuation` or `compacted` (its context made smaller) | the Mac |
| `task_complete` | A turn ends; `outcome` is `success` or `failure` | the Mac (the brain) |
| `reply_ready` | A turn ends with an answer, or a question back | the Mac (the brain) |
| `stopped` | A turn is interrupted | the Mac |
| `error` | A tool fails (the task may still succeed) | the Mac |
| `helper_return` | A helper agent comes back | the Mac |
| `poked` | A tap on the screen | the board |
| `tap_spam` | The third tap in a row, and each after | the board |
| `listening` | You hold the button to talk; it plays until the reply (at most 30 s, then 8 s) | the board |

A state a face doesn't know draws `idle`. A moment whose design has no
length (`loopMs` of 0) plays nothing.

**A reaction** (`react`, the brain's) is no state of its own: the face
draws the look in another mood for a moment, and the voice may speak.

### What else a face does

The engine's interface is `render::Face` (`firmware/src/render/face.h`).
Besides drawing each mood and state, a face:

- **Has variations.** A state may have several designs, numbered from 1.
  The Mac picks one, and a moment's facts (`outcome`, `ctx`) pick among
  them. A face says how many it has (`variants`).
- **Times them.** Each design's loop length (`loopMs`), which sets how
  long a moment plays, and its voice window (`voiceMs`), when a line may
  start.
- **Moves with the engine.** It blinks, opens its mouth while the voice
  speaks (`mouthOpen`), and presses down under a finger (`dy`).
- **Leaves room for the lane.** On the CYD's 320 × 240 screen, the
  bottom 48 px are the engine's: the status strip (who needs you, how
  many sessions work, a finished turn's tick or cross) and the speech
  bubble. The face calls `drawLane` to draw them.
- **Makes its own sounds.** A bank of clips (`clips`) and when each plays
  (`cues`). The engine mixes them under the voice.
- **May ask harder the longer you wait.** Needs you is drawn on the
  request's own clock (`designMs`, from the moment the request came) for
  as long as it waits, and its `cues` follow the same clock, so a face
  can make it a performance that grows, and the engine knows nothing of
  it. Pixel holds up a sign with who's asking and peeks over it, then
  sways it and waves a mitt, then shakes it and waves both, then lowers
  it and stares at you, and at last gives up and peeks calmly
  (`render/pixel/sign.h`). Answer at any point and the face goes straight
  back to its look.
- **Has a name** for the board's `hello` (`name`). It draws every mood,
  so the Mac sends each as it is. The board shows its startup mood only
  for a name it doesn't know: a malformed message, or a Mac on another
  version of the moods.

### The pack's files

**On the board.** The staged `firmware/` (§2) is part of the firmware's
build. `firmware/platformio.ini` compiles its `src/` and puts `include/`
and `src/` on the include path. It holds:

- `include/moods.h`: `enum class Mood`, in `character.json`'s order,
  with `kMoodCount`, `kStartupMood` and `kMoodNames`.
  `characters/charactergen.py` makes it from `character.json`; never
  edit it by hand. Engine code assumes nothing else about moods: no mood
  name is in the engine. A face looks a mood up by its name, never its
  number (the pixel face with `render::pixelIndex`).
- Pixel's `faces.h` (facegen's) draws 13 moods (`kMoodNames`), and names
  every mood (`kNames`) with the drawn one whose designs it wears
  (`kWears`): itself, or the one Pixel's temporary table,
  `characters/pixel/tools/borrowed.json`, lends it until it has art of
  its own. The borrowers point at the same designs, so they cost no
  frames.
- One or more faces behind `render::Face`, and `render::makeFace()` in
  `src/render/make_face.cpp`, which picks one by the board's build
  flags. Pixel's always makes the pixel face. Boop's makes the gel face
  on the AMOLED.
- Today, every pack's faces draw with the palette of the pixel face's
  `faces.h` (`render/palette.h` includes it). So a pack's firmware
  carries that file until the palette is split from the art.

**On the Mac.** `mac/faces.json` is what the Mac knows of the pixel face.
facegen writes it into the Pixel pack. It holds:

- `moods` and `states`: every mood, in the pack's order, and the 22
  states above, in the designs' order.
- `designs`: for each mood, a row for each state (a borrowing mood has
  the designs it wears), with each variation's
  loop length (`ms`), voice window (`voice_ms`) and fact (`outcome` or
  `ctx`). The board has the same numbers (`faces.h`, `sfx.h`). The Mac
  times moments and picks variations by them. A fact no design is for
  plays any of the state's designs.
- `box`, `colors` and `faces`: the popover's still faces, each as
  `<mood>/<look>` for `idle`, `working` and `needs_you`, and
  `<startup_mood>/asleep`. A face it lacks shows the mood's idle one.

`mac/mirror/`, if present, is a web page the popover shows instead, fed
the same state the board gets (the gel slime has one).

Today a pack's AMOLED build needs a gel face, which only Boop's pack
has. Pixel's face is for the CYD board.

Faces are code for now: both of today's faces implement `render::Face`
in C++. A picture-based face is planned, with frames per state and mood
drawn by an engine renderer, so a character can be drawn with no code.

## 10. Who's on the board

The board's `hello` names the pack its firmware was built with, beside
its `face` and its card's `voice`: `"pack":"boop","pack_version":"0.1.0"`
(`kPackId` and `kPackVersion` in the generated `moods.h`). So keep the id
to 24 characters and the version to 16: `hello` must fit in one line.

When that isn't the Mac's pack, another id or another version, the Mac:

- says so in its log, and in the popover ("Other character"), until the
  board is flashed with the app's pack
- keeps working: the board draws its startup mood for a mood it doesn't
  have, and plays a reaction whose face it doesn't have in the look's
  mood
- speaks only when the card's voice is the app's (§8), a check of its own

Firmware too old to name its pack counts as the Mac's.

## 11. Licence

Every pack here is public, under the repository's MIT licence
([LICENSE](../LICENSE)), unless it carries a `LICENSE` of its own. A
pack from elsewhere brings its own.

Every pack builds and tests on its own. With another pack chosen
(`CHARACTER=pixel`):
- The Swift tests of Boop's pack's own content (its goldens, evals and
  graph) skip, saying so (`requirePack("boop")`); the rest run.
- The tests that play takes run on that pack's voice. With a pack that
  has none they skip (`NEEDS_VOICE_PACK()` in the firmware's).

## 12. The studio (optional)

The [Character Studio](studio/README.md), `characters/studio/`, is one
page for any pack: its moods and the engine's states, and a preview of
each pair when the pack brings one. A pack opts in with `studio` in
`character.json`, a list with an entry for each preview it brings.
Pixel's:

```json
"studio": [
  {
    "id": "pixel",
    "label": "Pixel Boop",
    "about": "CYD board",
    "icon": "studio/icon.svg",
    "scripts": [
      "design/boop-sound-bank-v4/dist/boop-runtime.js",
      "studio/adapter.js"
    ],
    "styles": [
      "studio/adapter.css"
    ],
    "wears": "tools/borrowed.json"
  }
]
```

- `scripts` and `styles`: files the page loads, in order. One script
  registers the entry's adapter ([the studio's README](studio/README.md),
  Writing an adapter). The adapter's own files go in the pack's
  `studio/` folder, which the app doesn't bundle.
- `id`: the name the adapter registers under and the preview's card
  goes by, its own among the pack's entries.
- `wears`: optional, a JSON file whose `borrows` table names, for each
  mood the preview has no art of its own for, the mood whose art it
  shows. The studio marks those moods with the one they wear.
- `families`: optional, a label and colour for each `family` the moods
  name.
- `label`, `about` and `icon` (an image): optional, for the character's
  card.
- `captures`: optional, a JSON file of `{"cases": [{"id": ...}]}`, the
  only clip names the studio's server will save for the pack.

Boop's pack has two entries: `boop`, its gel slime, and
`pixel`, its copy of the pixel face, which wears the borrowed art its
copy of Pixel's table says. `charactergen.py` writes the page's data
(`characters/studio/packs.js`) from the packs, and `--check` fails when
a declared file is missing or a preview wears a mood the pack doesn't
have.

## 13. Demos (optional)

A pack can carry demos: scripted stretches of work for its creature to
live through, `demo/<name>.jsonl`. Pixel's `landing.jsonl` is the story
the landing page plays (mellowmachines.com). A demo is the pack's because
the creature's reactions in it are in the pack's own moods and words: the
engine has the player (`app/BoopKit/Demo/`), and the pack has the story.
The app bundles the folder. How to write and play one:
[DEMOS.md](DEMOS.md).

## 14. Making your own

1. Copy `characters/pixel/` to `characters/<yours>/`, and set `id` and
   `name` in `character.json`. Leave out `design/`, `tools/` and the
   `studio` entry until you need them.
2. Change the moods' meanings and moves (§5). Every pack has
   the same moods, so keep every one; its faces must draw them all.
3. Rewrite `steering/guide.md` and `steering/personality/` in its voice,
   and a `steering/mood/` file for each mood that needs one.
4. Change the faces, or keep Pixel's, which the copy already has. Keep
   its voice too, or delete `voice/` and `mac/takes.tsv` for a creature
   that doesn't speak.
5. Run `characters/charactergen.py characters/<yours>` to make
   `firmware/include/moods.h`, then `make build` and
   `.build/debug/boopdev check`.
6. Try it: `CHARACTER=<yours> make demo NAME=hello` plays Pixel's short
   demo, which the copy carries, in the simulator's page.
7. Flash it: `make flash CHARACTER=<yours>`.
8. Optionally, write it demos ([DEMOS.md](DEMOS.md)), and give it a
   studio entry (§12) to look at every mood and state in
   `characters/studio/index.html`.
