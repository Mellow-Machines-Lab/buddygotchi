# Characters: the pack spec

Updated 2026-10-24. The contract a character pack meets, so that any
character can be dropped into the engine. The engine never knows *who*
the creature is: the pack says its moods, how it looks and sounds, and
who it is. Choose a pack (§2), and the Mac app, the board's firmware and
the simulator all use it.

## At a glance

What a pack holds, and what it must have:

| Path | Must have | What it is |
| --- | --- | --- |
| `character.json` | yes | Its id, name, moods and how they connect (§4–5) |
| `steering/guide.md` | yes | How it reads what happens, for the brain (§7) |
| `steering/personality/<id>.md` | yes, one for each personality | Who it is (§7) |
| `steering/nature/sweet.md`, `cheeky.md` | no | What the nature chosen at setup adds to who it is (§7) |
| `steering/mood/<mood>.md` | no | How it acts in a mood; a missing one reads as the resting mood's (§7) |
| `firmware/` | yes | Its faces' code and art for the board (§9) |
| `rig/` | no | Its expressions, clips and looks on the rig the faces are moving to (§15) |
| `mac/faces.json` | yes, or used (§6) | The pixel face's timings and the popover's still faces (§9) |
| `mac/mirror/` | no | A web page the popover shows as the face (§9) |
| `mac/takes.tsv` and `voice/voice.bin` | no, both or neither, or used (§6) | Its recorded voice (§8) |
| `demo/<name>.jsonl` | no | Its demos ([DEMOS.md](DEMOS.md)) |
| `studio/` and `studio` in `character.json` | no | Its preview in the Character Studio (§12) |
| `references/`, `review/` | no | What people gave to make it from, and what's up for review (§16) |
| `LICENSE` | no | The pack's own licence; without one, the repository's MIT licence (§11) |
| `design/`, `tools/`, `tests/`, `evals/` | no | What its art and sounds are made from, and its own tests |

To make one, copy Pixel's (§14). To check one:

```sh
make build && .build/debug/boopdev check            # every pack in characters/
.build/debug/boopdev check path/to/pack             # one pack, anywhere
```

`boopdev check` reads a pack as the engine does: `character.json`, the
steering, the faces' files, the voice, every demo, and its moods, what
it uses and its studio entry (`charactergen.py --check`). A pack that passes plugs in. Then
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
  from. It uses Pixel's face and voice (§6).
- **`characters/pixel/`**, with Pixel Boop's faces and sound effects,
  plain prompts and a recorded voice. It's the example to copy. Its art
  and the voice cover 13 of the moods; each of the others borrows one of
  those 13's (§8, §9).

## 2. Choosing a pack

The first of these wins:

1. `BOOP_CHARACTER=<path>` for a pack anywhere, or `CHARACTER=<name>`
   for `characters/<name>/`, in the environment or on a `make` command
   line.
2. The name or path in `.character` at the repo root, a one-line file
   you write and git ignores, so every `make` keeps your choice.
3. `characters/boop/`.

`python3 characters/charactergen.py --stage` lays the chosen pack out in
`.character-build/` at the repo root (also ignored): `staged/<name>/`,
the staged pack, its own files and those it uses from another pack (§6),
each a link to the file in its pack; `pack`, the one pointer to it; and
from it, the pack's `firmware/`, with the two headers staging makes
(`moods.h`, §9, and `rig_tables.h`, §15), and the folder the app bundles
(`packs/`). The builds read only from there. `firmware/tools/pio.sh` stages before every PlatformIO run,
and `make build` before every app build. The app bundles only what it
reads of a pack (not its firmware, rig, voice file, tools or tests): the
chosen pack's, which `packs/chosen` names, and beside it every other
pack in the chosen one's folder, each with what it uses, for buddies
that run another pack. Several buddies run side by side, each a board
with its own pack, and the app loads each buddy's pack by its `id`
(`Buddy`, internal/VERIFICATION.md §2's `--buddies`).
`charactergen.py --firmware-to=DIR PACK` lays out one pack's `firmware/`
alone in `DIR/firmware/`, as a stage would, and changes nothing staged:
the simulator builds a second pack beside the staged one that way
(`simulator/web/build.sh pixel`, [simulator/README.md](../simulator/README.md)).

Everything that runs after a build, the tests, `boopdev`, the device
tools and the simulator, reads the **pack in use**: the one the
environment chooses (`BOOP_CHARACTER` or `CHARACTER`), staged if it's
the one staged, else the one `pack` points to, else the chosen one
(nothing staged yet). So a change
to `.character` waits for the next stage. `charactergen.py` keeps this
rule (`in_use()`), and `--which` prints its answer; the Python tools
import it, the shell and Node call `--which`, the Swift tests read the
environment and then the pointer, and the C++ tests, which run only
after a stage, read the pointer. `Boop` itself takes `BOOP_CHARACTER`
when it starts, else its bundled pack, so one build can play any pack's
demo. Staging also links the staged pack's firmware
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
    nature/sweet.md, cheeky.md
    mood/<mood>.md
  mac/               what the app reads at run time (§9)
    faces.json       the popover's face designs
    mirror/          optional: a web page the popover shows as the face
    takes.tsv        optional: the voice's take table (§8)
  firmware/          what the firmware compiles in (§9)
    include/…        the faces' generated art and sounds
    src/render/…     each face's code in a folder of its own, and
                     make_face.cpp, which makes the board's (§9)
  rig/               optional: what its moods wear and its moves on the rig (§15)
    expressions.json, looks.json
    clips/<id>.json
  voice/voice.bin    optional: the voice file, for the microSD card (§8)
  studio/            optional: the studio's preview adapter (§12)
  references/        optional: what people gave to make it from (§16)
  review/            optional: what's up for review, and the verdicts (§16)
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
| `faces` | yes | The face each board draws, by the board's name: `cyd24`, `amoled206` (§9). A board it names none for won't build with it |
| `uses` | no | What it takes from another pack: each share's name, and the pack that has it (§6) |
| `shares` | no | What it lends: each share's name, with its `files` and its `studio` previews (§6) |

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
| `face` | no | What this mood's face means for a single reaction: the option text when the brain picks a reaction's face. Without it, `meaning` |
| `not_for` | no | When the mood isn't meant, added to the `mood` question's option |
| `face_not_for` | no | When the face isn't meant, added to the face's option |
| `family` | no | A group of related moods (`joy`, `frustration`…), for designers; the engine doesn't read it |
| `moves` | yes | `ordinary` and `dramatic` neighbours: the moods it can move to in one step. Staying is always allowed. A dramatic move needs a fresh, big event |

The `mood` question offers staying and every move from the current
mood, the dramatic ones saying they need a fresh, big event; pacing, how
long a mood holds and when it fades, is the steering's (§7). Pixel's
moves are the same as Boop's.

## 6. A pack stands alone or names what it uses

A pack has every file the engine reads in its own folder, or names the
pack it takes some of them from. The engine never knows: it reads the
staged pack (§2), where staging has laid them out together, and never
falls back to another pack on its own.

A pack that lends files lists them in `shares`, by a name for each
share: the files and folders it takes in, and the studio previews that
show it (§12). A pack that takes them names each share it uses, and the
pack beside it in the same folder that has it, in `uses`. Pixel's
shares its face and its voice, and Boop's uses both:

```json
"shares": {
  "pixel_face": {
    "files": ["firmware/include/faces.h", "firmware/include/sfx.h", "firmware/src/render/pixel", "mac/faces.json",
              "tests/firmware/test_scene", "tests/firmware/test_rig_face"],
    "studio": ["pixel"]
  },
  "voice": {
    "files": ["voice/voice.bin", "mac/takes.tsv"]
  }
}
```

```json
"uses": {
  "pixel_face": "pixel",
  "voice": "pixel"
}
```

So the pixel face, which Boop wears on the CYD (on the AMOLED it brings
its own, the gel slime), and the voice (§8) are in Pixel's pack only,
and change for both at once. A pack takes only the lender's own files,
not what the lender uses in turn, and never a file it has itself.
`charactergen.py` refuses a share that isn't there, or a file it names
that isn't, and `boopdev check` reads a pack's files as staging lays
them out.

## 7. Steering

What the brain reads, in plain Markdown:

- `guide.md` (required): how the creature reads what happens, read on
  every pass.
- `personality/<name>.md` (one per name in `personalities`): who it is,
  with front matter for the view's rules: `working_heartbeat` (seconds
  between check-ins on a turn), `idle_heartbeat` (seconds between idle
  check-ins while you're around and no agent works; without it, only
  the hourly heartbeat) and `tool_uses`.
- `nature/sweet.md` and `nature/cheeky.md` (optional): the nature the
  person chose at setup, saved in `long-term.md`. The chosen one goes
  into the prompt right after the personality's PERSONALITY section,
  whatever the personality: sweet is warm and gentle with failures,
  cheeky playful and teasing, never mean to the person. A file may end
  with Examples, as a personality does, where the two natures answer
  the same moment differently. A pack without
  the file adds nothing; `boopdev check` notes a pack with only one.

  So a **personality** is the pack's: a file in `personality/` (Boop's
  pack has `boop` and `chatter`), picked in Settings. A **nature** is the
  person's: sweet or cheeky, chosen at setup, a file in `nature/` laid
  over whichever personality is on.
- `mood/<mood>.md` (one per mood): how it acts while in that mood,
  what moves it, and when it fades. A missing file reads as
  `default_mood`'s.
- `diary.md` (optional): the lines the creature may write in its diary,
  one a day about yesterday, on the first pass of a new day
  (`DiaryOutput`). Each is `- [tags] words`: the tags (optional) a day
  must all have (`failed`, `clean`, `long`, `quiet`, `poked` and the
  calendar's), and the words may fill in `{weekday}`, `{turns}`,
  `{failed}`, `{longest}` (minutes), `{thread}` and `{pokes}`. The brain
  picks one of those that fit, at most eight; the memory store keeps it
  in `diary.md` in the state directory, and the popover shows the last
  week. A pack without the file keeps no diary.
- `signs.md` (optional): the captions the creature may hold up on a
  sign when it reacts to your prompt (`Signs`, the `react.sign`
  question, asked only when NOW is a prompt's reading). Each is
  `- [tags] words`: the tags (optional) the reading must all have (its
  kind, tone and length, `named`, `words`, and the calendar's), and
  `{words}` (or `{WORDS}`, in capitals) is filled in once for each of
  your phrases, so your own words come back in the creature's way. Your
  words come first, then tagged captions, then the rest: at most six,
  each at most 18 printable ASCII characters. The board draws the one
  picked on a sign (the `do`'s `sign`). A pack without the file holds up
  no signs.

Each file has a budget in tokens, the same for every pack
(`Steering.Budget`, in `app/BoopKit/Harness/Steering.swift`). The app
logs a file over its budget and still uses it.

## 8. Voice (optional)

A pack with a voice has recorded takes, each tagged with the moods it
plays in, a feeling, a topic and a kind:

- `voice/voice.bin` is the voice file, for the board's microSD card.
- `mac/takes.tsv` is its table, which the Mac reads to pick a take. Its
  first line holds the voice file's version, the same one the board
  reports.

A pack may have them, or use another's (§6). Both are built files and
checked in. The one voice there is, 2,722 takes, is in Pixel's pack,
and Boop's uses it. What it's built from stays out of Pixel's: the
recordings, and voicegen, the tool that turns them into the two files,
are kept in Boop's pack, and write into Pixel's. So Pixel's pack needs
nothing of Boop's, and Boop's needs Pixel's for its face and its voice,
one way only.

A pack without a voice leaves both out. The brain is then never asked
what to say (`react` drops its `say.*` questions), and reactions play
faces and sound effects only. A pack with a voice has takes for every
mood: Voice picks only takes whose moods include the face's. A take
recorded in one mood may play in others: the table's moods column lists
them all. The takes were recorded in 13 moods, so voicegen lends each
to the moods that borrow its mood in Pixel's table,
`characters/pixel/tools/borrowed.json`. Only the table changes: the
audio and the version stay the same.

## 9. Faces

A face is what the board draws and the sounds it makes. The engine says
*what* to show: a mood and a state. The face decides how that looks.

### Every state a face is asked for

The engine asks a face for any of the pack's moods (§5) with any of
these 25 states. A face must answer for all of them, in every mood. It may draw the same design for several: the pixel face has art
for all 25, and the gel face maps some to others in its own code
(`router.cpp`). The names are the firmware's (`firmware/src/render/types.cpp`),
and `charactergen.py --check` holds this table to them.

**Looks** last until the next one. They show when no reaction plays.

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

**Reactions** play once over the look, or `loops` times (1 to 6), then go:
the brain's, a rule's, or the board's own.

| State | When it plays | Sent by |
| --- | --- | --- |
| `starting` | An agent starts; `ctx` says how: `new_task`, `session`, `continuation` or `compacted` (its context made smaller) | the Mac |
| `task_complete` | A turn ends; `outcome` is `success` or `failure` | the Mac (the brain) |
| `reply_ready` | A turn ends with an answer, or a question back | the Mac (the brain) |
| `wake_up` | You come back to the Mac after a long break | the Mac (the brain) |
| `notice` | You named it in your prompt: it looks up at you, surprised and pleased, as if it heard its name. Pixel's has three variations (`notice-art.mjs`), the gel's three takes under a face it borrows, as a gesture's (`notices` in its `expressions.json`) | the Mac (the brain) |
| `gesture` | The board's own reaction to what you do to it, its variations in this order (`render::Gesture`): `handoff` (BOOT hands you an agent), `stroke`, `ruffle` (stroked the wrong way), `nose`, `tickle`, `dizzy` (shaken), `pickup`, `putdown`, `startle` (a thump on the desk), `peekaboo` (turned face up again). A face with fewer draws its first | the board |
| `stopped` | A turn is interrupted | the Mac |
| `error` | A tool fails (the task may still succeed) | the Mac |
| `helper_return` | A helper agent comes back | the Mac |
| `poked` | A tap on the screen | the board |
| `tap_spam` | The third tap in a row, and each after | the board |
| `listening` | You hold the button to talk; it plays until the reply (at most 30 s, then 8 s) | the board |

A state a face doesn't know draws `idle`. A reaction whose design has no
length (`loopMs` of 0) plays nothing.

**A brain reaction with no animation** (`react`) is no state of its own:
the face draws the look in another mood for a while, and the voice may
speak.

### What else a face does

The engine's interface is `render::Face` (`firmware/src/render/face.h`).
Besides drawing each mood and state, a face:

- **Has variations.** A state may have several designs, numbered from 1.
  The face picks a look's itself: a new look starts on its first, and at
  the end of a loop it may turn to another. It picks a reaction's too,
  among those for its facts (`outcome`, `ctx`), never the last one when
  there's another. A face says how many it has (`variants`).
- **Has occasions.** A design may need tags (`when`: every one on) or a
  wait (`after`: seconds its look has shown). The tags are the engine's
  (`firmware/src/render/tags.h`): the part of the day (`morning`, `day`,
  `evening`, `night`), `friday`, `weekend`, `friday13`, the holidays
  (`newyear`, `valentines`, `piday`, `aprilfools`, `may4`, `halloween`,
  `winter`, `programmers`, `lunar`), `party` (a milestone day since
  hatching, New Year's Day, a growth stage reached) from the Mac's
  `state.when`, and `busy` (2–3 sessions working) and `frantic` (4 or
  more), which the board adds from `state.busy`. A design that fits
  only while its tags are on shows only then; a look starts on one while
  it fits, turns to one two times in three, and a reaction always takes
  one. Pixel's are `occasion-art.mjs` in its bank: coffee in the
  morning, a nightcap at night, a party hat, Halloween, winter,
  Valentine's, Friday's shades, a frantic sweat, a stretch after twenty
  minutes' work, a dream after half an hour's sleep. Over idle's and
  asleep's other variations Pixel draws the same hats and air itself, by
  the tags (`render/pixel/outfit.h`, `render::outfitFor` in
  `render/tags.h` the one rule for which hat), so it's dressed whichever
  variation shows; its working looks and reactions draw their own props
  where a hat would go, and stay as they are. The working looks
  also play 125% quicker while the agents are busy and 160% while
  frantic (`render::workPace`, which each face gets as
  `FaceContext::pace`). The gel's are takes its engine deals
  by the same tags and waits (`occasions` in its design's
  `expressions.json`, which slimegen bakes into `slime.h`): idle drowses
  at night, stretches in the morning, bounces on a party day or a New
  Year, sways on a Friday, shivers in winter, wobbles at Halloween,
  swoons on Valentine's and nods off after twenty minutes; busy and
  frantic work type faster, twenty minutes' work ends in a stretch, and
  sleep snores deeper at night and dreams after half an hour. Its idle
  picks one in place of a gesture. Over every state the board also draws
  layers on the gel by the tags (`render/gel/layers.h`), at anchors the
  pose that drew its body gives (`rig::Anchors`, from
  `render/gel/painter.h`: the dome's top, a ring for a hat's brim, its
  front lower down for its hands, its eyes),
  so they move, squash and leave the screen with it: a nightcap at night
  (and its lids a little lower), a party hat on a party day, New Year's
  Day, Lunar New Year and Programmers' Day, a witch hat at Halloween, a
  bobble hat in winter, shades on a Friday's day; snow in winter,
  confetti on a party day and New Year's Day, hearts on Valentine's, Zs
  while it sleeps at night. Peekaboo's gesture takes the hat off. The
  Mac's mirror of the gel doesn't draw them yet.
- **Times them.** Each design's loop length (`loopMs`), which sets how
  long a reaction plays, and its voice window (`voiceMs`), when a take may
  start.
- **Moves with the engine.** It blinks, opens its mouth while the voice
  speaks (`mouthOpen`), presses down under a finger (`dy`), and may follow
  one (`finger`): the gel's dome leans after a stroke, and Pixel's plain
  face, drawn from the rig (§15), squashes under a press and leans after
  a stroke.
- **Leaves room for the lane.** On the CYD's 320 × 240 screen, the
  bottom 48 px are the engine's: the status strip (who needs you, how
  many sessions work, a mini for each helper at work, up to four and
  then +N, a parcel and the count of agents idle for BOOT to hand over,
  a finished turn's tick or cross) and the speech bubble. The face calls
  `drawLane` to draw them. The engine fades the strip in as it comes and
  out as it goes, over the rig's 200 ms fade, from the moment it came or
  went, and hands the face its opacity with it (`Strip::opacity`):
  `drawLane` dithers it on the canvas, and a face that draws its own
  lane, as the gel does, draws it at that opacity.
- **Holds up a sign.** Any reaction may carry words in `sign` (the `do`'s
  args), at most 18 glyphs of the fonts (accents folded, cut with `..`
  past that, `render::foldText`). The engine keeps them up from the
  reaction's start for as long as any part of it plays, and at least
  2.5 s to be read (`Behaviour::kSignMinMs`); a newer reaction's
  animation or `say`, listening and needs you take them down, a tap's
  poke doesn't. A face gets them as `SignShow` (the words, and how long
  they've shown) and draws them as its own: Pixel's a card under its face
  gripped by two mitts (`render/pixel/held.h`), the gel's a card in front
  of its body with a little gel hand at either side
  (`render/gel/layers.h`). Each slides up as it starts and bobs while
  it's held.
- **Makes its own sounds.** A bank of clips (`clips`) and when each plays
  (`cues`). The engine mixes them under the voice.
- **May ask harder the longer you wait.** Needs you is drawn on the
  request's own clock (`designMs`, from when the request came) for
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
build. `firmware/tools/pack_face.py` compiles its `src/` into each env's
own build folder, and `firmware/platformio.ini` puts `include/` and
`src/` on the include path. It holds:

- `include/moods.h`: `enum class Mood`, in `character.json`'s order,
  with `kMoodCount`, `kStartupMood` and `kMoodNames`. It isn't in the
  pack: staging makes it from `character.json` (§2), into the staged
  `firmware/include/`. Engine code assumes nothing else about moods: no mood
  name is in the engine. A face looks a mood up by its name, never its
  number (the pixel face with `render::pixelIndex`).
- Pixel's `faces.h` (facegen's) draws 13 moods (`kMoodNames`), and names
  every mood (`kNames`) with the drawn one whose designs it wears
  (`kWears`): itself, or the one Pixel's table,
  `characters/pixel/tools/borrowed.json`, lends it. The borrowers point
  at the same designs, so they cost no frames.
- One or more faces behind `render::Face`, each in its own folder,
  `src/render/<face>/`, and `render::makeFace()` in
  `src/render/make_face.cpp`, which makes one. `faces` in
  `character.json` names the face each board draws: Boop's
  `{"cyd24": "pixel", "amoled206": "gel"}`, Pixel's
  `{"cyd24": "pixel"}`. A board's build compiles that face's folder and
  no other, and defines `BOOP_FACE_<FACE>` (`BOOP_FACE_GEL`) for
  `makeFace()` (`firmware/tools/pack_face.py`). The simulator builds
  every face, and `makeFace()` picks by `BOOP_SIM_FACE`.
- `include/rig_tables.h`: the pack's rig (§15), which staging also
  makes, from `rig/`.
- Every pack's faces draw with the palette of the pixel face's
  `faces.h` (`render/palette.h` includes it). So a pack's firmware
  carries that file, or uses it.

**On the Mac.** `mac/faces.json` is what the Mac knows of the pixel face.
facegen writes it into the Pixel pack. It holds:

- `moods` and `states`: every mood, in the pack's order, and the 25
  states above, in the designs' order.
- `designs`: for each mood, a row for each state (a borrowing mood has
  the designs it wears), with each variation's
  loop length (`ms`), voice window (`voice_ms`), fact (`outcome` or
  `ctx`), tags (`when`) and wait (`after`, in seconds). The board has the
  same numbers (`faces.h`, `sfx.h`). The Mac times reactions and picks
  their variations by them, never one with tags or a wait (the board
  swaps one in itself). A fact no design is for plays any of the state's
  designs.
- `box`, `colors` and `faces`: the popover's still faces, each as
  `<mood>/<look>` for `idle`, `working` and `needs_you`, and
  `<startup_mood>/asleep`. A face it lacks shows the mood's idle one.

`mac/mirror/`, if present, is a web page the popover shows instead, fed
the same state the board gets (the gel slime has one).

A board a pack names no face for doesn't build with it: Pixel's names
only the CYD, as the gel face, Boop's own, is the AMOLED's only one.

## 10. Who's on the board

The board's `hello` names the pack its firmware was built with, beside
its `face` and its card's `voice`: `"pack":"boop","pack_version":"0.1.0"`
(`kPackId` and `kPackVersion` in the staged `moods.h`). So keep the id
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

Every pack builds and tests on its own (At a glance): a Swift test of
Boop's own content skips for another pack (`requirePack("boop")`), and a
test that plays takes skips for a pack with no voice
(`NEEDS_VOICE_PACK()` in the firmware's).

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

A pack also shows the previews of each share it uses (§6). So Boop's
shows two: its own, `boop`, its gel slime, and Pixel's, `pixel`, which
comes with the pixel face. And every pack gets, with no entry, the
board's own preview of each face its boards have (`faces`, §9), its id
`board-<face>`: the firmware itself, built to WebAssembly, which the
studio's Transitions and References run on too (§16). `charactergen.py` writes the page's data
(`characters/studio/packs.js`) from the packs, and `--check` fails when
a declared file is missing or a preview wears a mood the pack doesn't
have.

## 13. Demos (optional)

A pack can carry demos, `demo/<name>.jsonl`: the engine has the player
(`app/BoopKit/Demo/`), and the pack has the story, in its own moods and
words. The app bundles the folder. How to write and play one:
[DEMOS.md](DEMOS.md).

## 14. Making your own

1. Copy `characters/pixel/` to `characters/<yours>/`, and set `id` and
   `name` in `character.json`. Leave out `design/`, `tools/` and the
   `studio` entry until you need them.
2. Change the moods' meanings and moves (§5). Every pack has
   the same moods, so keep every one; its faces must draw them all.
3. Rewrite `steering/guide.md`, `steering/personality/` and `steering/nature/`
   in its voice, and a `steering/mood/` file for each mood that needs one.
4. Change the faces, or keep Pixel's, which the copy already has. Keep
   its voice too, or delete `voice/` and `mac/takes.tsv` for a creature
   that doesn't speak.
5. Run `make build` and `.build/debug/boopdev check`.
6. Try it: `CHARACTER=<yours> make demo NAME=hello` plays Pixel's short
   demo, which the copy carries, in the simulator's page.
7. Flash it: `make flash CHARACTER=<yours>`.
8. Optionally, write it demos ([DEMOS.md](DEMOS.md)), and give it a
   studio entry (§12) to look at every mood and state in
   `characters/studio/index.html`.

## 15. The rig (optional)

The rig is the one set of numbers every pack and face shares
([plan/character-engine.md](../plan/character-engine.md)): at any instant
a character is a value on each of its channels. A pack's `rig/` says
what they do: what each mood wears, its moves and its looks. The
engine's half is `firmware/src/render/rig/`: the channels, the tables'
types, the ramp its fades ease on and the anchors a face reports
(`rig.h`), and the mixer that plays them (`mixer.h`). The pixel face
draws its face from it wherever a design's face is its mood's resting
face (below, Pixel's face on the rig); the gel moves onto it next.
Pixel's rig has expressions for its 13 drawn moods, each wearing its own
mood's eyes and mouth, the looks idle, working and asleep, and a blink.
Boop's is the same, since Boop wears Pixel's face on the CYD, with its
notice besides (§16's reference became it).

**Channels.** The body's `x`, `y`, `squash`, `lean`, `tilt` and `lift`;
the eyes' `eyeOpenL`, `eyeOpenR`, `eyeSize`, `gazeX` and `gazeY`; and
the mouth's `mouthWidth` and `mouthOpen`. Each is a whole number, in
thousandths but for `x`, `y` and `lift` (px), with a range and a value
at rest, where a face draws its art as drawn: `kChannelInfo` in `rig.h`
says what each means, and `charactergen.py` checks the files by it. In
the files, `eyeOpen` sets both eyes. A face also has two **styles**, the
eyes' and the mouth's: which of its drawings it draws, for the shapes no
channel reaches (hearts, X eyes). A new style cross-fades in. The pixel
face's styles are its drawn moods' names: a style is that mood's eyes,
or its mouth, as its art draws them.

**`expressions.json`**: for each mood the pack has one for, the styles
it wears. Pixel's, cut to two of its moods:

```json
{
  "happy": {"eyes": "happy", "mouth": "happy"},
  "excited": {"eyes": "excited", "mouth": "excited"}
}
```

A mood without one has none of its own, and the face decides what it
wears (Pixel's borrows, §9).

**`clips/<id>.json`**: a clip each, its id the file's name: keyframed
curves on some channels, timed in ms. Boop's notice:

```json
{
  "about": "notice: it heard its name and looks up at you, eyes wide, then settles (Pixel's perk).",
  "ms": 900,
  "tracks": {
    "lift": [[0, 0], [120, 10, "out"], [300, 12], [600, 10], [820, 0]],
    "gazeY": [[0, 0], [120, -500, "out"], [700, -500], [900, 0]],
    "eyeSize": [[0, 0], [120, 200, "out"], [600, 150], [900, 0]]
  }
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `ms` | yes | Its length, 1 to 60000 |
| `loop` | no | Whether it loops, `false` without it. A looping clip's tracks start at 0 and end at `ms` on the value they started on |
| `additive` | no | `true` without it: its values are offsets on what's there, so it plays in any mood, each up to the channel's whole span either way. `false`: values to blend toward, each in the channel's range |
| `tracks` | no | For each channel, its keys in order of time, `[ms, value]` or `[ms, value, ease]`, the ease into the key from the one before: `linear`, `in`, `out` or `inout`, which a key without one has. Before its first key a track holds that key's value, and after its last the last's |
| `about` | no | What it is, for people |

**`looks.json`**: for each look (§9's Looks), the clip it loops under
the reactions (`clip`, one that loops, or null). Boop's:

```json
{
  "idle": {"clip": "breathe"},
  "working": {"clip": "work"},
  "asleep": {"clip": "doze"}
}
```

Every file is optional, and one that's missing is empty.
`charactergen.py --check` fails on an unknown key, channel, mood, state
or clip, a style that isn't a name, a value out of its range, keys out
of order and a loop that doesn't close, each with its file and key
(`rig/clips/hop.json: tracks.lift[2]: …`). Staging writes the files as
`rig_tables.h` in the staged `firmware/include/`: `render::rig::kRig`,
with a lookup by mood, clip and look. The app doesn't bundle `rig/`.

**How it plays.** The mixer (`mixer.h`) holds a critically damped spring
on each channel, the face's quicker than the body's, at rest: a channel
within half a unit of rest and all but still is at rest exactly, and a
step of a second or more sets every spring at rest at once. The look's
clip loops over the springs, and reactions' clips over that, a few at
once, each with a weight that eases in and out over 150 ms (a quarter of
a shorter clip, so a 180 ms blink still shuts): an additive clip adds
its offsets, an absolute one blends toward its values. A poke or a
stroke kicks a spring. A new style cross-fades over the rig's fade
(`kFadeMs`, 200 ms). The face reports where the body is each frame from
the pose it draws (`rig::Anchors`: the crown, a ring for a brim, the
front lower down for the hands, the eyes), so what's worn or held rides
the body.

**Pixel's face on the rig.** Most of Pixel's designs draw its mood's
resting face, moved about, over a desk, props or decorations of their
own. Wherever one does, at every step of its loop, the pixel face draws
its face from the rig (`render/pixel/rig_face.h`) in the design's place,
in every mood whose expression's styles it has, and the design draws the
rest: in its looks (working's included), its occasions and its
reactions alike. Facegen decides which
(`rig_faces`): for each design it finds where the resting face sits at
each step, the whole face moved and its eyes moved within it (a
glance), and splits what the face draws besides it (a sparkle, a
falling tear) into decorations of their own, which the design keeps
drawing over the rig face. It takes a design only if, drawn so at rest,
it is the design as drawn, pixel for pixel; idle's first two variations,
a blink and a look-around, Pixel's plain face, it takes near enough,
missing what the rig face can't draw (sad's trembling lip, irritated's
twitch), since the morphs into and out of a mood are worth it. The rest
are baked: the finishes and wake-ups, the comedy, asleep, a face that
changes shape (curious's eyes, whose big eye moves side to side, a
yawn), tears pouring from the eyes (sad at work). Each design's moves
are a track of `faces.h` (a scene's `face`), which the rig face follows
as the design's clock runs, so its sounds, timing and outcome are the
design's still. Its parts are each drawn mood's own art, which facegen
cuts from the mood's first idle at rest: each eye open and shut, the
mouth and the cheeks (`faces.h`'s `kParts`, about 6 KB). At rest each
part draws as its art has it, and the channels' offsets from rest move
it: `x`, `y`, `lift`, `squash` and `lean` the whole face; `eyeOpen`
closes each eye onto the line it shuts on, its shut art below a third
open; `eyeSize` scales the eyes, `gazeX`, `gazeY` and `tilt` shift them;
`mouthWidth` and `mouthOpen` widen and open the mouth. A new style
dissolves in over the mixer's 200 ms, a 4 × 4 ordered dither (the canvas
has no alpha), each part morphing from its box to the next one's. The clip of the look it's
in (idle, working or asleep: the state's `base`) plays over the
design's moves (Pixel's breathe lifts it a pixel and glances to either
side; working's looks down at the desk), the `blink` clip at each blink;
a press kicks the squash and a stroke the lean. Every switch of design
dissolves over the rig's 200 ms fade, through the same dither, with no
blink: the whole picture, or between two designs the rig face draws,
their desks while the face stays whole, moving from where the one had
it to where the other has it. Into and out of the needs-you sign it
cuts: the sign rises in and drops away on its own. The hat
(`render/pixel/outfit.h`) and the sign (`held.h`) ride the rig face's
brim and hands.

## 16. References and review (optional)

A person gives a short reference, a sketch, a still, a GIF or a video,
with a line: inspiration, or "make this". An agent reads it and turns it
into the pack's data, and the studio (§12) shows the two side by side.
Each reference is a folder, `references/<YYYY-MM-DD>-<topic>/`, Boop's
worked one:

```
references/2026-10-24-notice-perk/
  perk.gif              what was given: stills (.png .jpg .jpeg .webp), GIFs, videos (.mp4 .mov .m4v .webm)
  reference.json        what it is, and what became of it
  frames/perk.gif/      0000.png on, a frame every 40 ms (a still is one)
  sheets/perk.gif.png   the frames on one sheet, 8 a row, each with its ms
  reading.md            the agent's reading of it
```

```json
{
  "kind": "inspiration",
  "note": "Inspiration for notice: like a dog hearing its name.",
  "status": "in review",
  "became": [{"what": "clip", "id": "notice"}],
  "show": {"mood": "calm", "state": "idle", "anim": "notice"},
  "frames": 25,
  "ms": 1000
}
```

| Key | What |
| --- | --- |
| `kind` | `inspiration`, what it's like, in the character's own style; or `direct`, its beats and poses made as the rig allows |
| `note` | The person's line about it |
| `status` | `new`, then `read` (cut into frames), `translated` (read and turned into data), `in review`, `approved` |
| `became` | What it became on the rig (§15): each a `clip`, by its file's name, an `expression`, by its mood, or `art`, a style an expression wears, by its `id` |
| `show` | Optional: what the studio plays beside it on the board, a `mood` and a `state`, and then `anim`, a state asked for at the reference's 0 ms |
| `frames`, `ms` | Written by the tool: the frames cut from all its files, and the longest file's length |

The steps, each by a tool or an agent:

```sh
internal/tools/boopctl reference new PACK TOPIC --kind inspiration --note "LINE" FILE...
internal/tools/boopctl reference read characters/boop/references/2026-10-24-notice-perk
```

1. **Intake.** `reference new` makes the folder, with today's date, and
   copies the files in.
2. **Read.** `reference read` cuts each file into frames (ffmpeg) and a
   sheet, and moves the status to `read`. The agent looks at the sheets
   and writes `reading.md`: the beats and their timing, the poses, squash
   and stretch, the eyes' and mouth's shapes, the colours and the
   silhouette. A reference that needs more than the character has (arms,
   ears, a new body) says so, for the owner, and is never faked.
3. **Translate.** The agent makes it into the rig's data (§15), sets `became` and `show`,
   and puts it up for review.
4. **Review.** Agents list what's up in `review/queue.json`, each item
   `{"id", "title", "what", "before", "after", "status"}`: `before` and
   `after` are images in `characters/`, by their paths from the
   repository's root, and the status is `in review`, `changes` or
   `approved`. The owner approves or asks for a change in the studio's
   Review, and its server appends each verdict to `review/notes.jsonl`,
   a line each: `{"at", "id", "verdict": "approve" | "change", "text"}`.
   Agents read the notes, act on them, and update the item and the
   reference.

`charactergen.py --check` fails on a reference whose folder isn't named
so, whose `reference.json` has a key or a value it doesn't take, whose
`show` names a mood the pack hasn't or a state the board hasn't, that has
no media or a file that isn't media or its own; that's read without the
frames and sheet of every file, or with `frames` that don't count them;
or that's translated or later without `reading.md` or a `became`, or
became something the rig hasn't. It checks the queue's items and their
images, and the notes, each as the studio's server writes them, the
same way: a key, a value or one missing, with its file and key
(`reference.json: show.mood: …`, `queue.json: perk.status: …`,
`notes.jsonl:2: verdict: …`), as for the rig (§15). None of it stops a
pack staging. The app doesn't bundle either folder.

## Not yet

- Pixel draws and voices 13 of the moods; the others borrow theirs
  (`characters/pixel/tools/borrowed.json`) until they have art and takes
  of their own.
- Pixel's mood moves are Boop's; they become Pixel's own.
- Pixel's rig face draws only the designs whose face is its mood's
  resting face (§15); a design whose face changes shape (curious's
  look-around, a yawn, a finish's face) is still baked, since the rig's
  parts are one drawing of each eye. The gel doesn't draw from the rig
  yet.
- The palette lives in the pixel face's `faces.h`; it moves out of the
  art, so a face needs no file of Pixel's.
- A face is C++ code. A picture-based face, with frames per state and
  mood drawn by an engine renderer, would let a character be drawn with
  no code.
