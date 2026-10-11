# Characters: the pack spec

Updated 2026-10-11. **Draft.** This is the contract a character pack
meets so that any character can be dropped into the engine. The
split plan moves Boop's
character behind this spec phase by phase. Each phase updates this page
with what it delivers.

**What works so far.**
- **The Mac** reads its moods from `characters/boop/character.json`
  (§4–5): `CharacterPack`, in `app/BoopKit/Character/`. The app bundles
  that file and loads it at start; the tests and `boopdev` take
  `BOOP_CHARACTER`, else the repo's copy.
- **The firmware** takes its mood list from the pack's generated
  `firmware/include/moods.h` (§9), which `firmware/platformio.ini` puts
  on the include path.
- **A pack stands alone** (§6). Everything the engine reads of a pack is
  in the pack's own folder, and nothing is looked for in another pack.
  `characters/pixel/` holds the Pixel pack: its moods, with plain
  wording of its own, the pixel face and the voice. Boop's pack has its
  own copy of what the two share.
- **The Mac reads the rest of a pack at run time** from the pack's
  folder (`CharacterPack.directory`):
  - its steering (`steering/`, §7)
  - its voice's take table (`mac/takes.tsv`, §8)
  - the pixel face's designs (`mac/faces.json`, §9), which facegen writes
  - Boop's slime mirror (`mac/mirror/`, §9), which slimegen writes
  The app bundles those folders and `character.json`.

- **The firmware's faces are the packs'.** Pixel's code and art are in
  `characters/pixel/firmware/`, the gel slime's in
  `characters/boop/firmware/`. The chosen pack is staged into
  `.character-build/` (§2), and the firmware builds from there.

- **The Mac app follows the same choice.** `make build` stages the
  chosen pack, with what the app reads and no more (not its firmware or
  its voice pack), into `.character-build/packs/`, which the app
  bundles; its `chosen` file names the pack the app loads. The tests,
  `boopdev` and the device tools use the staged choice
  (`.character-build/pack`, the pack's own folder).
- **Each pack holds what it's made from,** but for the voice. Pixel's
  `design/` (the animation bank and mood graph) and `tools/` (facegen,
  sfxgen). Boop's `design/` (the gel slime, and the voice's
  recordings), `tools/` (slimegen, gel-trace, voicegen, which writes
  both packs' voice files, and pixelsync, which copies Pixel's face into
  Boop's pack), `evals/` and `tests/` (its golden states and the gel
  face's simulator scenarios and goldens). Everything in
  `characters/boop/` is private; everything else is public.
- **Each pack can show itself in the Character Studio** (§12),
  `characters/studio/`: Pixel's preview is its animation bank, and
  Boop's pack has two, its gel slime and its copy of the pixel face.

- **Pixel stands on its own.** It has its own steering (a guide, its
  one personality and a file for each of its 13 moods), plain wording
  written for it, and the voice. `CHARACTER=pixel make app` builds the
  app as Pixel, and `CHARACTER=pixel make -C internal fw-test` runs the
  firmware's tests as Pixel. Personalities are the pack's, not a fixed
  list. The brain's questions and lines name the creature by the pack's
  `name`, so Boop's read as before.
- **A pack's tests join the run.** `--stage` links the engine's
  suites and the pack's `tests/firmware/test_*` into
  `.character-build/firmware-test/`, which is `platformio.ini`'s
  `test_dir`. `make -C internal tools-test` runs the Python tests in a
  pack's `tests/tools/`.

The board's report (§10) comes in a later phase. Today a pack's AMOLED
build needs a gel face, which only Boop's pack has.

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
- When states change (the core's rules).
- *That* a mood is picked after events.
- The protocol.

**Decided by the pack:**
- How each state looks and sounds.
- Its moods, any number from one up, with what each means and how they
  connect.
- Its prompts, and whether it has a voice.

One pack comes with the engine's repo: **`characters/pixel/`**, the
default, with Pixel Boop's faces and sound effects, 13 moods, plain
prompts and a recorded voice. It's the example to copy.

Any other pack can live in a git repository of its own and be installed
into `characters/` (§2). Boop's own pack, the slime, is one: it's
private, so only those with access to its repository have it.

## 2. Choosing a pack

The first of these wins:

1. `BOOP_CHARACTER=<path>` for a pack anywhere, or `CHARACTER=<name>`
   for `characters/<name>/`, in the environment or on a `make` command
   line.
2. The name or path in `.character` at the repo root, a one-line file
   that git ignores. It's how `make run` remembers your choice.
3. The first pack installed from a repository of its own, by name
   (below).
4. `characters/pixel/`.

`python3 characters/charactergen.py --which` prints the one chosen, and
`--stage` lays it out in `.character-build/` at the repo root (also
ignored): the pack's `firmware/`, the folders the app bundles, and the
pack's own path. The builds read only from there.
`firmware/tools/pio.sh` stages before every PlatformIO run.

### Packs from their own repositories

A pack can live in a git repository of its own and be installed here,
as a checkout at `characters/<name>/` that this repository never
tracks. You work in it, commit and push as in any repository:

```sh
python3 characters/packs.py add NAME URL   # install a pack
python3 characters/packs.py sync           # in a new worktree: check out every installed pack
python3 characters/packs.py list           # what's installed, and on which branch
python3 characters/packs.py remove NAME    # take it out of this worktree
```

What's installed, and from where, stays in this clone's own `.git`
folder, never in a commit: a shared copy of each pack's repository, the
list, and the rule that ignores the packs' folders. So nothing of a
private pack, not even its address, reaches this repository. Every
worktree sees the same list; `sync` gives it its own checkout of each
pack, on a branch named after the worktree's (the main checkout's are on
`main`).

The Mac reads its pack when it starts, so switching means restarting.
The board's face is compiled into its firmware, so switching faces means
flashing again. A voice lives on the board's microSD card: copy the
pack's `voice/voice.bin` to the card as `boop/voice.bin` with a card
reader, or over USB with `internal/tools/boopctl card`, which is slow.

## 3. The folder

```
<pack>/
  character.json     who it is, its moods and how they connect (§4–5)
  LICENSE            the pack's own licence (§11)
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

Pixel's, `characters/pixel/character.json`, cut to the first of its 13 moods:

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
      "id": "happy",
      "meaning": "Pleased: things are going well, or something small went right.",
      "face": "A happy face: something went fine.",
      "moves": {
        "ordinary": [
          "calm",
          "excited",
          "proud",
          "curious",
          "engaged",
          "annoyed"
        ],
        "dramatic": [
          "wounded",
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
| `private` | no | `true` for a pack that isn't published with the engine: the public export leaves its folder out (§11). Boop's is |
| `default_mood` | yes | The resting mood: a new state folder starts in it, every mood fades toward it, and an unknown mood reads as it |
| `startup_mood` | no | What the board shows before the Mac sends a mood, and for a name it doesn't know. Without it, `default_mood`. Boop's is `happy`, as the board always started |
| `aliases` | no | Old names for moods, read as the mood: a saved mood from an older version (Boop's `cheerful` is happy) |
| `pacing` | no | The mood policy's four timings in ms: `ordinary_dwell_ms`, `reverse_cooldown_ms`, `brief_exit_ms`, `fresh_evidence_ms` (§5) |
| `personalities` | yes | The personalities, each a name or `{"id": name, "about": one line}`, with a file each in `steering/personality/`. The first is the default. `about` is what Settings says it does |
| `moods` | yes | The mood list, in order (§5). Its order is the firmware's `Mood` order |
| `outcomes` | no | Which moods a big finish may jump to, by kind (§5) |
| `growth` | no | The six growth stages' names. The engine's plain defaults otherwise |
| `natures` | no | The two answers to setup's one question (sweet or cheeky). The engine's plain defaults otherwise |
| `studio` | no | The pack's preview in the Character Studio (§12). Only the studio reads it |

Unknown keys are ignored, so a newer pack still loads in an older engine.

## 5. Moods

Each mood in `moods`:

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Its name, as the brain and the protocol see it: lower case and `_` |
| `meaning` | yes | When the character is in it: the option text when the brain picks a mood |
| `face` | no | What this mood's face means for a single moment: the option text when the brain picks a reaction's face. A mood without one isn't offered as a face |
| `not_for` | no | When the mood isn't meant, added to the `mood` question's option |
| `face_not_for` | no | When the face isn't meant, added to the face's option |
| `family` | no | A group of related moods (`joy`, `frustration`…), for designers; the engine doesn't read it |
| `moves` | yes | `ordinary` and `dramatic` neighbours: the moods it can move to in one step. Staying is always allowed. A dramatic move needs a fresh, big event |
| `fallback` | no | The mood to draw, and speak in, on a face or voice that lacks this one. Without it, `default_mood` |
| `brief` | no | `true` for a mood that only passes through, like surprised: it leaves for its fallback soon after |
| `quiet_never` | no | `true` for a mood routine work never leads to, only a fresh, strong event, like scared |

`outcomes` names the moods a very long turn's finish may jump to:
`big_success` and `big_failure`. Without them, a finish may only take
ordinary moves.

The engine owns the pacing rules: one step per pass, how long a mood
holds before it may move, cooldowns, and what counts as fresh evidence.
The pack owns the moods and the graph, and may tune the rules' four
timings with `pacing`. Without it, they're 30 s, 60 s, 5 s and 15 s.

**For now, Boop's pack has two mood lists.** `moods` is v3's 42 and
`moods_v2` is v2's 13, with each face's wording. The `moodGraph` setting
picks one.
`moods_v2` goes when Boop's pack takes v3 alone, and becomes Pixel's
`moods` (the split plan). Other packs have `moods` only.

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
- `mood/<mood>.md` (one per mood): how it acts while in that mood. A
  missing file reads as `default_mood`'s.

The budgets are the same for every pack. The engine logs a
file over budget and still uses it.

## 8. Voice (optional)

A pack with a voice has recorded takes, each tagged with a mood, a
feeling, a topic and a kind:

- `voice/voice.bin` is the microSD card's pack.
- `mac/takes.tsv` is its table, which the Mac reads to pick a take. Its
  first line holds the pack's version, the same one the board reports.

Both are built files and checked in. Pixel's pack and Boop's each have a
copy of the same voice, 2,722 takes. What they're built from stays out
of both: the recordings, and voicegen, the tool that turns them into the
two files, are kept in Boop's private pack, and one run of it writes
both packs' copies.

A pack without a voice leaves both out. The brain is then never asked
what to say (`react` drops its `say.*` questions), and reactions play
faces and sound effects only. A mood
with no takes of its own speaks in its `fallback`'s.

## 9. Faces

**On the board.** The staged `firmware/` (§2) is part of the firmware's
build. `firmware/platformio.ini` compiles its `src/` and puts `include/`
and `src/` on the include path. It provides:

- `include/moods.h`: `enum class Mood`, in `character.json`'s order,
  with `kMoodCount`, `kStartupMood` and `kMoodNames`.
  `characters/charactergen.py` generates it from
  `character.json`, and it's never edited by hand. Engine code may assume
  nothing else about moods. A face looks a mood up by its name, never its
  number (the pixel face with `render::pixelIndex`).
- One or more faces behind `render::Face`,
  and `render::makeFace()` in `src/render/make_face.cpp`, which picks one
  by the board's build flags. Pixel's always makes the pixel face. Boop's
  replaces it and makes the gel face on the AMOLED.
- Today, every pack's faces draw with the palette of the pixel face's
  `faces.h` (`render/palette.h` includes it). So a pack's firmware
  carries that file until the palette is split from the art.
- Each face's sound effects (`Face::clips()`).
- Each face's name for the board's `hello`, and the moods it draws. A
  face may draw only some moods: the rest draw their `fallback`.

A state the face has no design for draws a broader one: what the agents
are doing → `working` → `idle`. A one-shot it has no design for plays
nothing. A pack that draws idle, working and needs you is complete.

**On the Mac.** `mac/faces.json` is what the Mac knows of the pixel face.
facegen writes it into the Pixel pack. It holds:
- `moods` and `states`, in the designs' order
- `designs`: each design's loop length, voice window and host fact, the
  numbers `faces.h` and `sfx.h` give the board, which the core times
  moments and picks variations by. The host facts are task_complete's
  `outcome` (`success`, `failure`) and starting's `ctx` (`new_task`,
  `session`, `continuation`, `compacted`, the last an agent's context made
  smaller mid-work). A fact no design is for plays any of the state's
  designs
- `box`, `colors` and `faces`: the popover's still face per mood and look

`mac/mirror/`, if present, is a web page the popover shows instead, fed
the same state the board gets (the gel slime has one).

Faces are code for now: both of today's faces implement `render::Face`
in C++. A picture-based face is planned, with frames per state and mood
drawn by an engine renderer, so a character can be drawn with no code.

## 10. Who's on the board

The board's `hello` names its pack's `id` and `version`
beside its `face` and `voice`. When the
Mac's pack isn't the board's, the Mac:

- sends only moods both packs have
- sends nothing to say
- says so in the popover

It never sends a mood or take the board can't play.

## 11. Licence and the public repository

A pack carries its own `LICENSE`, and the engine's MIT licence doesn't
cover it. Pixel is open. Boop's own pack is private: it lives in a
private repository of its own (§2), so this repository never has it.

`python3 internal/tools/export/export.py OUT [--commit]` lays out the
repository as the public would get it, as a last check that nothing
private is tracked. It writes HEAD's files without:
- every pack whose `character.json` says `"private": true`

The submodules (`agent-hooks/`, `mellowharness/`) stay submodules,
each at the commit HEAD has; `--commit` records them and makes the
commit as this repository's git identity, never the global one.

Links to what's left out become their text. Then it checks the result
for a private pack's content (a line of its steering, a mood's meaning
or face wording) and anything that looks like a key, and fails on
either. The voice isn't private: Pixel's pack has its own copy.

Without Boop's pack, the public repository builds and tests as Pixel:
- The Swift tests that need Boop's pack (its goldens, evals, wording
  and moods) skip, saying so (`requireBoopsPack()`).
- The tests that play takes run, on Pixel's voice. With a pack that has
  none they skip (`NEEDS_VOICE_PACK()` in the firmware's).

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
    "coverage": "design/boop-sound-bank-v4/coverage.json"
  }
]
```

- `scripts` and `styles`: files the page loads, in order. One script
  registers the entry's adapter ([the studio's README](studio/README.md),
  Writing an adapter). The adapter's own files go in the pack's
  `studio/` folder, which the app doesn't bundle.
- `id`: the name the adapter registers under and the preview's card
  goes by, its own among the pack's entries.
- `coverage`: optional, a JSON file whose `perPair` table gives, for
  each mood, how many variations each state has. Without it, the preview
  plays every pair.
- `families`: optional, a label and colour for each `family` the moods
  name.
- `label`, `about` and `icon` (an image): optional, for the character's
  card.
- `captures`: optional, a JSON file of `{"cases": [{"id": ...}]}`, the
  only clip names the studio's server will save for the pack.

Boop's pack has two entries: `boop`, its gel slime, and
`pixel`, its copy of the pixel face, whose `coverage` names the 13 moods
it draws; the rest of Boop's moods play their `fallback`.
`charactergen.py` writes the page's data (`characters/studio/packs.js`)
from the packs, and `--check` fails when a declared file is missing or
a preview can't play one of a pack's moods in some state, itself or
through its `fallback`.

## 13. A demo (optional)

A pack can carry a demo: a scripted stretch of work for its creature to
live through, `demo/demo.jsonl`. The engine plays it as if it were
happening (`Runtime.play`, `app/BoopKit/Demo/`), through the same doors
as real work, so the rules do what they always do; and the script says
how the creature reacts, in the pack's own moods and words. That's why
it's the pack's: the engine has the player, and the character has the
story. The app bundles the folder.

One JSON object a line, each a beat: `at`, the seconds since the start,
and one thing that happens then. A line starting `//` is a comment.
From Pixel's:

```json
{"at": 2, "agent": "claude", "hook": "UserPromptSubmit", "session": "demo", "cwd": "/demo/shortcuts", "prompt": "Add keyboard shortcuts", "answer": {"react.mood": "curious", "say.about": "start", "say.kind": "word"}}
{"at": 17, "tap": true}
{"at": 30, "agent": "claude", "hook": "PreToolUse", "session": "demo", "cwd": "/demo/shortcuts", "tool": "Bash", "topic": "deploy", "tool_use_id": "t2", "note": "You approve it"}
{"at": 42, "talk": "how's it going?", "answer": {"react.mood": "determined", "say.about": "work", "say.kind": "phrase"}, "after": 2.2}
{"at": 60, "advance": 300}
{"at": 72, "mood": "proud", "note": "A good day's work"}
```

| A beat with | Is |
| --- | --- |
| `hook` | An agent's hook, in the form `agent-hook` sends ([agent-hooks](../agent-hooks/README.md)): `agent`, `hook`, `session`, and whichever of `cwd`, `tool`, `topic`, `tool_use_id`, `tool_error`, `prompt`, `message`, `error`, `kind` that hook carries |
| `tap` | A tap on the creature |
| `talk` | Push-to-talk: the button held for `hold` seconds (1.5), then those words heard |
| `mood` | The mood, set |
| `advance` | The clock moved on that many seconds, so a long turn needn't be waited out. Only where the clock can be moved: headless |

Any beat may also carry:

- **`answer`:** how the creature reacts, as the brain's answers to its
  questions, given `after` seconds later (0.3, about as long as the brain
  takes): `react.mood` (a mood's face, or `none`), `react.animation`
  (`success`, `failure` or `reply`, for a turn that finished),
  `react.loops`, and for a pack with a voice `say.feeling`, `say.about`
  and `say.kind` (§8). A demo plays with no brain, so a beat with no
  answer gets what the rules do and nothing more.
- **`note`:** what happened, in words for whoever is watching, in place
  of the words the engine finds for the beat (`You ask Claude: “…”`,
  `Claude ran the tests`, `You poke Pixel`).

`DemoTests` holds the chosen pack's demo to its pack: every answer is to
a question the brain is asked, with a choice it's offered, and every
mood is one the pack has.

```sh
.build/debug/Boop --headless --state-dir /tmp/boop-demo --demo pack                     # play it, with no device
simulator/tools/record-demo.sh pixel                                                    # record it for the simulator's page
```

The second plays it on the simulator's board and keeps every line the
board was sent, with when and what was happening
([simulator/README.md](../simulator/README.md), Demos): the page plays
that back into the firmware itself, with no app behind it.

## 14. Making your own

1. Copy `characters/pixel/` to `characters/<yours>/` and set `id` and
   `name` in `character.json`. To keep it in a repository of its own,
   push that folder to one and install it with `packs.py add` (§2).
2. Change the moods: their names, meanings and moves. Write a
   `steering/mood/` file for each.
3. Rewrite `steering/personality/` and `guide.md` in its voice.
4. Change the faces, or keep Pixel's, which the copy already has. Keep
   its voice too, or leave out `voice/` and `mac/takes.tsv` for a
   creature that doesn't speak.
5. `make build CHARACTER=<yours>`, then flash with the same.
6. Optionally, write it a demo (§13).
7. Optionally, give it a studio entry (§12) and look at every mood and
   state in `characters/studio/index.html`.
