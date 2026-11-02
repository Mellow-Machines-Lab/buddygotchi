# Characters: the pack spec

Updated 2026-11-02. The contract a character pack meets, so that any
character can be dropped into the engine. The engine never knows *who* the
buddy is: the pack says its moods, how it looks and sounds, and who it is.
Choose a pack (§2), and the Mac app, the board's firmware and the simulator
all use it.

## At a glance

What a pack holds, and what it must have:

| Path | Must have | What it is |
| --- | --- | --- |
| `character.json` | yes | Its id, name, moods and how they connect (§4–5) |
| `steering/guide.md` | yes | How it reads what happens, for the brain (§7) |
| `steering/personality.md` | yes | Who it is (§7) |
| `steering/mood/<mood>.md` | no | How it acts in a Mood; a missing one reads as the resting mood's (§7) |
| `firmware/` | yes | Its faces' code and art for the board (§9) |
| `rig/` | no | Its expressions, clips and looks on the rig (§15) |
| `mac/faces.json` | with the pixel face | The pixel face's moods and the popover's still faces (§9) |
| `mac/mirror/` | no | The board's firmware in a web page, the face the popover and onboarding show (§9) |
| `mac/takes.tsv` and `voice/voice.bin` | no, both or neither | Its recorded voice (§8) |
| `demo/<name>.jsonl` | no | Its demos ([DEMOS.md](DEMOS.md)) |
| `demo/recordings/<name>.json` | one for each demo of one buddy | What the board was sent as the demo played, which the simulator's page plays (§13) |
| `studio/` and `studio` in `character.json` | no | Its preview in the Character Studio (§12) |
| `references/`, `review/` | no | What people gave to make it from, and what's up for review (§16) |
| `LICENSE` | no | The pack's own licence; without one, the repository's MIT licence (§11) |
| `design/`, `tools/`, `tests/`, `evals/` | no | What its art and sounds are made from, and its own tests |

To make one, copy Pixel's (§14). To check one, from the engine's repository:

```sh
make -C internal build && .build/debug/boopdev check # every pack in characters/
.build/debug/boopdev check path/to/pack             # one pack, anywhere
```

- `boopdev check` says whether a pack plays. It reads the pack as the app
  does: `character.json` with its moods and their graph, the steering and
  its budgets, the faces' files, the voice and every demo.
- `charactergen.py --check` says whether it builds: the moods and startup
  mood `moods.h` needs, the rig, the studio entry and the references.
- `CHARACTER=<name> make -C internal fw-test` builds the firmware with it,
  to check its faces.

A pack that passes all three plugs in.

The engine's own Swift tests (`make -C internal test`) run with Boop's pack,
as its firmware tests run with Pixel's face. Run with another
(`CHARACTER=<name> .build/debug/BoopTests`), a test of one pack's own
content skips (`requirePack("boop")`), and a test that plays recorded takes
skips for a pack with no voice (`NEEDS_VOICE_PACK()` in the firmware's);
each says why. `CharacterPackTests` and `boopdev check` check every pack's
own files.

## 1. The idea

The engine is the code: the hooks, the core's rules, the brain's harness,
the device link and the drawing loop. At a few fixed points it asks the
loaded character:

1. **Which moods can you be in, and what does each mean?** The brain picks
   one.
2. **How do you look in this state, in this mood?** The screen draws it.
3. **How do you sound?** Sound effects, and a voice if it has one.
4. **Who are you?** The prompts that shape the brain's choices.

A pack is a folder that answers those four in the shapes below. The engine
carries the answers between the brain and the face, and never reads their
meaning.

**Fixed by the engine, the same for every character:**
- The **states**: what the agents are doing (`idle`, `working`, `needs_you`,
  `testing` and the rest, §9).
- The **moods**' names: the same 42 for every character (§5).
- When states change (the core's rules).
- *That* a mood is picked after events.
- The protocol.

**Decided by the pack:**
- How each state looks and sounds.
- What each mood means, how the moods connect and how fast they move.
- Its prompts, and whether it has a voice.

Boop has two packs, each in a public repository of its own, its pack the
repository's `character/` folder and the engine beside it as the `engine/`
submodule:
- **`boop`**, the default, in
  [SlimeBuddy](https://github.com/Mellow-Machines-Lab/SlimeBuddy): the gel
  slime, on the AMOLED.
- **`pixel`**, in
  [PixelBuddy](https://github.com/Mellow-Machines-Lab/PixelBuddy): Pixel
  Boop on the CYD, the example to copy.

`make -C internal packs` fetches each pack that's missing
(`internal/tools/packs.py`, from the repositories `characters/packs.json`
names): a clone in `characters/.repos/`, and `characters/<id>` a link to its
pack; git ignores them. A character repository's `make` links its own pack
in the same way (`engine/characters/<id>`, a link to `character/`) and
chooses it in `engine/.character`, so every engine command there runs with
it. Only what is the character's own goes in its repository.

## 2. Choosing a pack

The first of these wins:

1. `BOOP_CHARACTER=<path>` for a pack anywhere, or `CHARACTER=<name>` for
   `characters/<name>/`, in the environment or on a `make` command line.
2. The name or path in `.character` at the repo root, a one-line file you
   write and git ignores.
3. `characters/boop/`. The root `make`'s targets fetch the chosen pack first
   if it's one of `characters/packs.json`'s and missing (`packs.py
   --chosen`).

`python3 characters/charactergen.py --stage` lays the chosen pack out in
`.character-build/` at the repo root (also ignored). The builds read only
from there:

- `staged/<name>/`: the pack's files, each a link, but for what no build
  reads (`design/`, `references/`, `review/`).
- `pack`: the one pointer to it.
- `firmware/`: the pack's, with the two headers staging makes (`moods.h`,
  §9, and `rig_tables.h`, §15).
- `packs/`: what the app bundles, which leaves out a pack's firmware, rig,
  voice file, tools and tests. It holds the chosen pack, which
  `packs/chosen` names, and every other pack in the chosen one's folder, for
  buddies that run another pack. The app loads each buddy's pack by its `id`
  (`Buddy`, internal/VERIFICATION.md §2's `--buddies`).

`firmware/tools/pio.sh` stages before every PlatformIO run, and
`make -C internal build` before every app build. A stage changes only what
differs: a changed file is replaced whole, so a build reading while another
stages finds every file there. Staging also links the pack's firmware tests
(`tests/firmware/test_*`) beside the engine's, so `make -C internal fw-test`
runs both; `make -C internal tools-test` runs the Python tests in a pack's
`tests/tools/`.

`charactergen.py --firmware-to=DIR PACK` lays out one pack's `firmware/`
alone in `DIR/firmware/`, and changes nothing staged
(`simulator/web/build.sh pixel`,
[simulator/README.md](../simulator/README.md)).

Everything that runs after a build (the tests, `boopdev`, the device tools,
the simulator) reads the **pack in use**: the one the environment chooses,
staged if it's the one staged, else the one `pack` points to, else the
chosen one. So a change to `.character` waits for the next stage.
`charactergen.py --which` prints the answer (`in_use()`). `Boop` itself
takes `BOOP_CHARACTER` when it starts, else its bundled pack.

The Mac reads its pack when it starts, so switching means restarting. The
board's face is compiled into its firmware, so switching faces means
flashing again. A voice lives on the board's microSD card: copy the pack's
`voice/voice.bin` to the card as `boop/voice.bin` with a card reader, or
over USB with `internal/tools/boopctl card`, which is slow.

## 3. The folder

The table above says what each is. Laid out:

```
<pack>/
  character.json
  LICENSE
  steering/   guide.md  personality.md  mood/<mood>.md
              dreams.md  signs.md  replies.md  asks.md
  mac/        faces.json  mirror/  takes.tsv
  firmware/   include/…  src/render/<face>/…  src/render/make_face.cpp
  rig/        expressions.json  looks.json  clips/<id>.json
  voice/      voice.bin
  demo/       <name>.jsonl  recordings/<name>.json
  studio/  references/  review/  design/  tools/  evals/
  tests/      firmware/  tools/  mirror/
```

The engine reads built files only. How a pack makes them is its business. A
pack commits its built files, so building the engine never needs the pack's
own tools or what they were made from.

## 4. `character.json`

Pixel's, cut to the first of its 42 moods, a lasting one, and a face-only
one:

```json
{
  "id": "pixel",
  "name": "Pixel",
  "version": "0.1.0",
  "default_mood": "calm",
  "startup_mood": "happy",
  "moods": [
    {
      "id": "calm",
      "meaning": "Settled, the resting mood: nothing much is happening.",
      "family": "settled",
      "moves": {
        "ordinary": ["comfy", "curious", "engaged", "happy", "lazy", "annoyed", "lonely"],
        "dramatic": ["surprised", "wounded", "excited", "sad"]
      },
      "face": "A calm face: all quiet."
    },
    {
      "id": "tired",
      "family": "energy",
      "settles": "lazy",
      "face": "A tired face: a long stretch."
    }
  ]
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lower case, digits and `-`, at most 24 characters. The board reports it (§10) |
| `name` | yes | What the app shows |
| `version` | yes | The pack's version, at most 16 characters. A Mac and a board with different versions of the same pack fall back safely (§10) |
| `default_mood` | yes | The resting mood: a new state folder starts in it, every mood fades toward it, and an unknown mood reads as it |
| `startup_mood` | no | What the board shows before the Mac sends a mood, and for a name it doesn't know. Without it, `default_mood` |
| `moods` | yes | Every universal mood, once, in any order (§5). Its order is the firmware's `Mood` order |
| `acts` | no | What the pack draws for each work act, as Jev reads it: by kind (`push`, `tests`, `build`), then by `start`, `pass` and `fail`, a sentence with `{name}` for the creature's name. The engine says what the agent did and adds this. Without it, Jev reads the agent's clause alone |
| `studio` | no | The pack's preview in the Character Studio (§12). Only the studio reads it |
| `faces` | yes | The face each board draws, by the board's name: `cyd24`, `amoled206` (§9). A board it names none for won't build with it |

Unknown keys are ignored, so a newer pack still loads in an older engine.

## 5. Moods

Every pack has the same moods: the universal list,
`CharacterPack.universalMoods` in `app/BoopKit/Character/Moods.swift`. A
pack has each of them once, and no other: the app's loader and
`boopdev check` refuse a pack that doesn't. What each means, how they
connect and how each looks and sounds is the pack's.

Every mood is an emotion a Moment can show. Only some are lasting moods, the
ones the buddy settles into: they have a `meaning` and `moves`, a file in
`steering/mood/`, and the `mood` question offers only them. Each other mood
is a face only, and names the lasting mood it `settles` into: a log from
before reads it as that one, and the dashboard setting it sets that one.
Boop and Pixel each have 16 lasting moods (calm, comfy, lazy, happy, proud,
annoyed, irritated, grumpy, sad, wounded, engaged, curious, surprised,
determined, excited and lonely) and 26 faces only.

Each mood in `moods`:

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Its name, as the brain and the protocol see it: lower case and `_` |
| `face` | yes | What this mood's face means for a single Moment: the option text when the brain picks a Moment's emotion |
| `meaning` | for a lasting mood | When the buddy is in it: the option text when the brain picks a mood, in plain words |
| `moves` | for a lasting mood | Its neighbours, `ordinary` and `dramatic`: the lasting moods it can move to in one step. Staying is always allowed. A `dramatic` one needs a fresh, big event |
| `settles` | for a face only | The lasting mood it settles into |
| `not_for` | no | When the mood isn't meant, added to the `mood` question's option |
| `face_not_for` | no | When the face isn't meant, added to the face's option |
| `family` | no | A group of related moods (`joy`, `frustration`…), for designers; the engine doesn't read it |

The moves are the pack's one mood graph: the brain is offered them, and a
face may draw its transitions by them (slimegen bakes them into the gel's
`slime.h`, a face-only mood moving as the one it settles into). The `mood`
question offers staying and every neighbour. Staying, in any mood but the
resting one, says it ends when the minutes the mood's file gives are up.
Pacing, how long a mood holds and when it fades, is the steering's (§7).

## 6. A pack stands alone

A pack has every file the engine reads in its own folder. The engine reads
the staged pack (§2) and never falls back to another. Two packs that want
the same voice or face copy it, each in its own repository.

## 7. Steering

What the brain reads, in plain Markdown. Each file has a budget in tokens,
the same for every pack (`Steering.Budget`, in
`app/BoopKit/Harness/Steering.swift`). The app logs a file over its budget
and still uses it.

The prompt's order is the buddy's header (several buddies only), the guide,
PERSONALITY, MEMORY, MOOD, CONTEXT, HISTORY (closed by how long the mood has
lasted) and NOW.

**`guide.md`** (required): how the buddy reads what happens, read on every
pass.

**`personality.md`** (required): who it is, the whole of it, temperament
included.

- Its front matter sets the check-ins: `working_heartbeat` (seconds between
  check-ins on a turn) and `idle_heartbeat` (seconds between idle check-ins
  while you're around and no agent works, twice that with no agent open;
  without it, only the hourly one).
  Pixel's: `working_heartbeat: 120-240`.
- Its Examples quote NOW's lines as the view writes them, where your prompt
  and the agent's last message are only their readings:
  `You asked claude on "api" for a fix, in a sentence, frustrated.`, and a
  finish `…, 8 tool calls, saying it's done, apologetic.`, each with a few
  of the words under it (`Your words:`, `Its words:`).
- An Example that needs how things stand quotes the CONTEXT row it depends
  on, as the engine renders it, on a line above NOW (`- CONTEXT: You: at the
  Mac for 3 h; you haven't touched or talked to Boop in 2 h.`).
- CONTEXT's rows (`ContextSection`), each only when it has something to say:
  When (the time, the weekday, the part of the day, the special days), Talk
  (the setting, when it isn't normal, or a hush's minutes left), the buddy
  (its stage and age), You (at the Mac and untouched, each from an hour,
  never while away, and how long ago it was last lonely, for three hours
  after), Agents (each open session, at most three) and Today (turns and
  failed; touches and talks). They hold facts only: when they make the buddy
  lonely, or anything else, is the steering's. Events stay in their lines;
  the back line says how long you were away.
- A paragraph of temperament closes the file, after its Examples, with a few
  Examples of its own, so it has the last word. The Examples before it play
  the same for any temperament, so a new temperament rewrites only the
  closing part. It says how a moment looks, never that more moments get a
  Moment.

How much it says is the Talk setting, held in code (`Talk`). A pack has no
file for it.

**`mood/<mood>.md`** (one per lasting mood): how it acts while in that mood,
what moves it, and when it fades. A missing file reads as `default_mood`'s.

**`dreams.md`** (optional): the signs it may hold up as it tells its dream.
A dream is everything since the last one, in tags and a sentence
(`DreamReader`), made once a sleep or after two days. You coming back after
it, or with none your first touch (a poke or a stroke), tells it; never a
prompt or your words, which have signs of their own.

- Each line is `- [tags] words`. The tags (optional) must all be on: yours
  (`fond`, `distant`, `here`, `late`, `answered`), the agents' (`failed`,
  `clean`, `long`, `quiet`, `poked`) and the calendar's.
- The lines with tags come first, in the file's order, so put the lines
  about you first. The brain picks one (`react.sign`), at most six offered,
  each at most 18 characters.
- A pack without the file tells its dreams with no sign.

A line tagged `wish` in `asks.md` is its one want a day, not a question:
`[wish pet] pet me?` is the sign that makes it, `[wish pet met] <3` what it
holds up as it's met, for the kinds `pet`, `chat` and `work`; code says what
meets each. `[wish pet how] stroke my face?`, optional, is the sign that makes
it until you've met that kind once: it says what to do. A pack with no such
line makes no wish. The gel draws the thought bubble (`state.wish`), its icon
moving while it shows how (`state.wish_how`), and a lane with none says
`wants: pet`.

**`asks.md`** (optional): what it may ask you, with two answers you tap
(`Asks`). Ask only what does something with the answer: it becomes part of
the buddy (`keeps`), it gets a touch (`touch`), or it goes into memory; idle
chatter is a musing instead (`signs.md`). A pack without the file never
asks.

- `- [id tags] question | a | b` is a question. Its first tag is its id,
  then the tags it needs:
  - its moment: `idle` (an idle check-in) or `lonely` (an idle check-in where
    the buddy is lonely, or CONTEXT says you haven't touched it for an hour
    or more). Never a finish, whose thread the face names;
  - the calendar's, and your kept answers;
  - `daily`: it may come back the next day, whatever the answer;
  - `keeps`: asked once, ever, and its answer becomes a tag for good, as
    `cookie`;
  - `touch`: a stroke or a nose boop answers it too, as its first answer.
- `- [id answer] words` is a follow-up it may hold up after that answer.
- A question is at most 18 characters, an answer 7, a follow-up 18 (`boopdev
  check`).
- The sign question (`react.sign`) offers the questions that fit, as "Ask:
  …", the file's first ones first, and it may always pass. Caps: one an
  hour, three a day, six on Chatty, none on Quiet, never while something
  needs you.
- The board holds the question up as its sign and the two answers in its
  lane. After 45 seconds, or a newer Moment, it ends unanswered (`ev ask`).
  One answered stays off for 30 days, one ignored for a day.

**`signs.md`** (optional): the captions it may hold up when it reacts to
your prompt (`Signs`, the `react.sign` question, asked only when NOW is a
prompt's reading, not a message's). A pack without the file holds up no
signs.

- Each line is `- [tags] words`. The tags (optional) must all be on: the
  reading's kind, tone and length, `named` when you said this buddy's own
  name, and the calendar's.
- `{words}` (or `{WORDS}`, in capitals) is filled in once for each of your
  phrases.
- Offered: your words first, at most three, then tagged lines, then the
  rest: at most six, each at most 18 characters.
- A line's own words are printable ASCII. Your phrases are kept as the
  board's fonts draw them (curly quotes made straight, accents precomposed),
  and one with anything the fonts lack is dropped.
- Lines tagged `[idle]` are its musings instead: held up at an idle
  check-in, beside any question it may ask, at most once an hour
  (`Signs.musingEveryMs`), never on Quiet, and Jev may pass. `{turns}` is
  today's turns and `{thread}` the busiest session's thread name (a line
  that needs one is left out without it). A line may need a kept answer's
  tag (`[idle cookie] snack time?`).

**`replies.md`** (optional): what it holds up replying to your words
(`Signs.replies`). A pack without the file holds up nothing for a reply but
the facts.

- The brain picks a reply (`react.move`'s options for your words): yes, no,
  huh, hello, bye, thanks, love, ouch, comfort, hehe, status, nap, hush,
  dance or notme (`MomentOutput.replies`), and while hushed unhush. A `huh`
  to a question plays as `dunno`, a shrug.
- Each line is `- [reply tags] words`. Its first tag is the reply; any more
  are the calendar's or the moment's: `working` (an agent works), `waiting`
  (something waits on you), `makeup` (within 10 minutes of an `ouch`, until
  a `love` makes up), `nobrain` (the `huh` Boop shrugs with when it has no
  brain to answer, `Core.shrug`).
- `{words}` is a phrase of what you said, at most 12 characters
  (`Signs.maxPhrase`): the whole of it or a part between marks, lowercased,
  the buddy's name taken out, so "Hello!" can come back as `hello 2 u!`.
- For each reply only the lines with the most of the moment's tags that fit
  are offered, the calendar's among the plain ones, never the one shown last
  while another fits, each at most 18 characters once filled. The brain sees
  every reply's lines at once (`react.sign`) and the buddy holds up the one
  it likes best of those for its reply; with none liked, one of the reply's
  lines at random.
- A `status` reply holds up a fact about the agents instead (`StatusReply`),
  so it needs no line. With several sessions it may count them (`2 working,
  1 idle`) and open the drawer (the `do`'s `show`).
- A `hush` silences the buddy for as long as the moment is big
  (`Core.hushMsBySize`: 15 minutes small to two hours huge; the app's Hush
  button, 30), and the board shows the `hushed` tag. `unhush` or the popover
  ends it.
- The board plays the reply's clip (§15). If `say` says something, Voice
  says the reply's own words, its takes in the voice (§8): a yes says "Yep",
  a no "Tsk". With none in the voice, it says a feeling `say` picked, else
  one the reply borrows (`MomentOutput.replyWords`: thanks a glad sound),
  and never a topic.

## 8. Voice (optional)

A pack with a voice has recorded takes, each tagged with the moods it plays
in, a feeling or a topic (what the brain's `say` picks), or a reply it's the
words of (§7), and a kind (sound, word, phrase or swear). The Moment's size
picks the kind: a sound small, a word medium, a phrase big or huge.

- `voice/voice.bin` is the voice file, for the board's microSD card.
- `mac/takes.tsv` is its table, which the Mac reads to pick a take: the
  voice file's version on its first line after the comments, the same one
  the board reports, then a take a line, tab separated: id, text, part,
  meaning, kind, moods (space separated), finish (empty for any) and ms. A
  take that's also a reply's words is in it again, by the same id, as part
  `reply`, and one that's also a second feeling (the slime's `shaken`, from
  its startled and cross words) again as that feeling: the voice file has
  it once. `say` offers a pack only the feelings its table has takes of.

Both are built files and checked in, and a pack has both or neither. Boop's
pack holds the recordings and voicegen, the tool that makes the two files;
espeak-ng placeholders stand in for lines not recorded yet
(`plans/regenerate.json` in its `design/assets/boop-voice-v1/`). Pixel's has
a copy of the two built files.

A pack without a voice leaves both out. The brain is then never asked what
to say (`react` drops its `say` question), and Moments play faces and sound
effects only.

A pack with a voice has takes for every mood: Voice picks only takes whose
moods include the emotion's. The table's moods column lists every mood a
take plays in, so a take recorded in one mood may lend itself to others
(`tools/voicegen/borrowed.json`), with no change to the audio or the
version.

## 9. Faces

A face is what the board draws and the sounds it makes. The engine says
*what* to show: a mood and a state. The face decides how that looks.

### Every state a face is asked for

The engine asks a face for any of the pack's moods (§5) with any of these 22
states. A face must answer for all of them, in every mood. It may draw the
same design for several. The names are the firmware's
(`firmware/src/render/types.cpp`), and `charactergen.py --check` holds this
table to them.

**Looks** draw a Doing or an activity. They last until the next one, and
show when no Moment plays.

| State | When it shows | Sent by |
| --- | --- | --- |
| `idle` | Agents are open, and none is working | the Mac |
| `asleep` | No agent sessions at all, or every one resting with nothing waiting on you, at night 10 minutes and by day an hour (`Core.dozeOffNightMs`, `dozeOffMs`) | the Mac |
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
| `no_app` | The engine no longer shows this look: with the Mac lost, the board shows `idle` with the strip's plug, then `asleep` with no plug. A touch gets the board's own reaction | the board |

**Moments' animations** play once over the look, or `loops` times (1 to 6),
then go.

| State | When it plays | Sent by |
| --- | --- | --- |
| `starting` | An agent starts; `ctx` says how: `new_task`, `session`, `continuation` or `compacted` (its context made smaller). One card for a start: a session's first prompt within a minute of its start card shows none, nor does a follow-up within 5 minutes of its last turn (`Core.startCardMs`, `followUpMs`) | the Mac |
| `task_complete` | A turn ends: the finish. `outcome` is `success` or `failure`, and `turn` the tier it reached: 0 short of `tier1`, then 1 to 5 (`Moment.turn`) | the Mac (the brain) |
| `reply_ready` | A turn ends with an answer, or a question back | the Mac (the brain) |
| `wake_up` | You come back to the Mac after a long break | the Mac (the brain) |
| `wish_met`, `wish_gone` | The rules': a wish given, which plays `notice`'s design under the thought bubble's heart, unless a touch's `gesture` plays, which stays; a wish left, which fades the bubble and plays the rig's silent `wish-gone` clip, a sigh and a slump of about a second; the feeling after it is Jev's | the Mac's rules |
| `notice` | You named it in your prompt: it looks up at you, surprised and pleased, as if it heard its name | the Mac (the brain) |
| `gesture` | The board's own Moment for a touch, its variations in this order (`render::Gesture`): `handoff` (BOOT hands you an agent), `stroke`, `ruffle` (stroked the wrong way), `nose` (a tap on the face's middle; on the brain's finish that names whose turn it was, a tap on that opens the thread), `tickle`, `dizzy` (shaken), `pickup`, `putdown`, `startle` (a thump on the desk), `peekaboo` (turned face up again). A face with fewer draws its first | the board |
| `poked` | A poke | the board |
| `tap_spam` | The third poke in a row, and each after | the board |
| `listening` | You hold the button to talk; it plays until the reply (at most 30 s, then 8 s) | the board |

A state a face doesn't know draws `idle`. A Moment whose design has no
length (`loopMs` of 0) plays nothing.

Some touches are no animation of the face's. A quick swipe plays the stroke
or ruffle it would be, unless the face only feels it go by (`playsSwipe`),
and goes to the Mac as `swipe`. A finger that starts on the strip and goes
up pulls out the drawer, if the face has one. A finger held still a second
on the needs-you screen dismisses it: the board tells the Mac (`dismiss`,
with the request's number, `data.attn`) and plays nothing.

**A Moment with no animation** (`react`) is no state of its own: the face
draws the look in another emotion for a while, and the voice may speak.

**A word of the work stream** (`call`) is no state of its own either
(`render/stream.h`), and never a Moment: `w` the word, `a` its lane's slot,
`as` its style (`bonk`, `shrug`, `land`… `render::CallStyle`). It plays at once over the agents' work and holds nothing up, its
`ended` sent as it starts. With no lane working, or while something needs
you, it's skipped `hidden`. A failed call is one of its styles.

**A work act** (`wact` in `state`, `render::Stream::ActIn`) is a command the
face plays out while it runs, part of Doing and never a Moment:
`[kind, words, full, result]`, the kind `push`, `tests` or `build`, the words its low sign's, `full`
1 for the whole scene or 0 for the small version (the words alone), and the
result `p` or `f` once the command has ended, as the words change to say so.
The Mac holds a result for the board's `actLeadMs`, less what's run of it, and
`actResultMs`. A face that doesn't draw it ignores it, as Pixel does. The gel's
scenes are `render/gel/act.h`.

### What else a face does

The engine's interface is `render::Face` (`firmware/src/render/face.h`).
Besides drawing each mood and state, a face:

- **Draws the work stream, if it can.** Before each frame the device hands
  it the stream (`Face::watch`): each working lane's latest word and call
  count from `state`'s `calls`, the words falling and the word a `call`
  brought forward. A face that doesn't draw it ignores it.
- **Has variations.** A state may have several designs, numbered from 1. The
  face picks a look's itself: a new look starts on its first, and at the end
  of a loop it may turn to another. It picks a Moment's too, among those for
  its facts (`outcome`, `ctx`), never the last one when there's another. A
  face says how many it has (`variants`). It may size a finish by its size
  and the tier its turn reached (`pick`'s `loops` and `turn`), and play a
  design they sized once (`plays`).
- **Reads the tags.** A design may need tags (`when`: every one on) or a
  wait (`after`: seconds its look has shown). The board's tags are in
  `firmware/src/render/tags.h`:
  - The part of the day: `morning`, `day`, `evening`, `night`.
  - Special days: `friday`, `newyear`, `valentines`, `halloween`, `winter`,
    `programmers`, `lunar`, and `party` (a milestone day since hatching, New
    Year's Day, the day a growth stage was reached, but never the day it
    hatched). The Mac greets a special day with its sign, and celebrates a
    stage the moment it's reached.
  - The tiers (`Tags.tiers`): `tier1` from 30 seconds, `tier2` from a
    minute, `tier3` from 2, `tier4` from 5, `tier5` from 10. They count how
    long the agents' working stretch has run, from its first turn, a rest of
    under 30 seconds carrying it on; or, once nothing works, how long since
    the latest session came to rest. The Mac sends the last reached and the
    board takes every one below it as on (`render::reached`), so a design
    for `tier2` shows from then on, at work or idle as its look says.
  - `sprout` from the first growth stage reached on, and `hushed` while the
    buddy is hushed (`Core.Hush`).
  - `busy` (2–3 sessions working) and `frantic` (4 or more), which the board
    adds from `state.busy`. The working looks also play at 125% and 160%
    then (`render::workPace`, `FaceContext::pace`).
  - The Mac has more (`weekend`, `friday13`, `piday`, `aprilfools`, `may4`
    and the later growth stages), for its signs and the brain, and sends the
    board none of them (`Tags.macOnly`).

  A design that needs tags shows only while they're on. A look starts on one
  while it fits and turns to one two times in three, and a Moment always
  takes one. A pack's rig may name clips by tags too (§15).
- **May dress for the tags.** One rule says what's worn, so the board and
  the Mac's popover (`Narration.Dressing`) agree: `render::outfitFor` (first
  that fits: Halloween's witch hat, a party hat, a nightcap at night, a
  bobble hat in winter), `render::eyewearFor` (shades on a Friday from noon
  to night) and `render::airFor` (snow, confetti, hearts). The gel draws its
  dressing at the anchors its pose gives (`rig::Anchors`, §15), so it moves
  with the body, and through the rig's layer stack (§15).
- **Times them.** Each design's loop length (`loopMs`), which sets how long
  a Moment plays, and its voice window (`voiceMs`), when a take may start.
- **Moves with the engine.** It blinks, opens its mouth while the voice
  speaks (`mouthOpen`), presses down under a finger (`dy`), and may follow
  one (`finger`, and `letGo` with how fast it was moving).
- **Leaves room for the lane.** On the CYD's 320 × 240 screen, the bottom 48
  px are the engine's: the strip and the bubble, their text cut by
  `render::cutAt`. The face calls `drawLane` to draw them.
  - The bubble shows the voice's words, or an ask's answers.
  - The face also gets the `caption`: the Moment's narration, at most 18
    characters (the `do`'s `reason`: "you picked Boop up"). It is not
    speech. Pixel shows it in the bubble when nothing is said; the gel small
    and grey on the lane's last line.
  - The strip fades over the rig's 200 ms and the face gets its opacity
    (`Strip::opacity`): `drawLane` dithers it on the canvas, and a face that
    draws its own lane draws it at that opacity.
- **Has a drawer, if it can** (`Face::hasDrawer`, `render/drawer.h`). The
  device keeps the finger, the spring, the scroll and the clock, and hands
  the face the drawer before each frame (`Face::drawer`). The face lays it
  out and says where its rows are and how far they scroll (`drawerTravel`,
  `drawerRow`, `drawerScrollMax`, `drawerSnap`, `drawerShown`). Each row is
  a session the Mac lists (`state`'s `list`, in a window, `skip` before and
  `unlisted` after): its thread's name, its agent and project, and whether
  it needs you, works or rests. A Moment can ask for it (the `do`'s
  `"show": "drawer"`). A face with none: a swipe up its strip is a swipe.
- **Holds up a sign.** Any Moment may carry words in `sign` (the `do`'s
  args), at most 18 glyphs of the fonts (accents folded, and past that cut
  at a word with `..`, `render::foldText`). A face gets them as `SignShow`
  (the words, how long they've shown, and their opacity) and draws them as
  its own, sliding up by `render::signLift`. They stay up while any part of
  the Moment plays, and at least 2.5 s (`Behaviour::kSignMinMs`). A newer
  Moment's animation or voice, `listening` and needs you take them down; a
  poke doesn't. A reply with an emotion is the one Moment whose face and
  sign show over the needs-you screen, as `listening` does.
- **May mark a finished turn.** The brain's Moment for a finished turn names
  whose turn it was (the `do`'s `who`, its thread at most 50 bytes). The
  engine names it in the strip, and opens its thread on a tap, while any
  part of the Moment plays and 5 s after (`Behaviour::kFinishLingerMs`); it
  leaves in 0.4 s (`kDoneLeaveMs`). A face gets it as `DoneShow` and may mark
  it as its own, and one that holds up the name (`holdsUpFinish`, as its
  words end, `DoneShow::signMs`, by 3 s at the latest) takes it out of the
  strip: the gel's rim glows, and the low sign rises in the strip's place.
- **Answers your words.** A Moment with an emotion may carry its reply
  (`reply`, the `do`'s args, `FaceContext::reply`): a face that can plays a
  move for it, once, as the emotion starts. The gel plays the pack's clip
  for it (§15, `reply-<name>`).
- **Makes its own sounds.** A bank of clips (`clips`) and when each plays
  (`cues`). The engine mixes them under the voice.
- **May ask harder the longer you wait.** Needs you is drawn on the
  request's own clock (`designMs`, from when the request came), and its
  `cues` follow the same clock, so a face can make it a performance that
  grows. Answer at any point and the face goes straight back to its look.
- **Has a name** for the board's `hello` (`name`). It draws every mood, so
  the Mac sends each as it is. The board shows its startup mood only for a
  name it doesn't know.

### The pack's files

**On the board.** The staged `firmware/` (§2) is part of the firmware's
build. `firmware/tools/pack_face.py` compiles its `src/` into each env's own
build folder, and `firmware/platformio.ini` puts `include/` and `src/` on
the include path. It holds:

- `include/moods.h`: `enum class Mood`, in `character.json`'s order, with
  `kMoodCount`, `kStartupMood` and `kMoodNames`. Staging makes it from
  `character.json`; it isn't in the pack. A face looks a mood up by its
  name, never its number (the pixel face with `render::pixelIndex`).
- One or more faces behind `render::Face`, each in its own folder,
  `src/render/<face>/`, and `render::makeFace()` in
  `src/render/make_face.cpp`, which makes one. `faces` in `character.json`
  names the face each board draws: Boop's `{"amoled206": "gel"}`, Pixel's
  `{"cyd24": "pixel"}`. A board's build compiles that face's folder and no
  other, and defines `BOOP_FACE_<FACE>` (`BOOP_FACE_GEL`) for `makeFace()`.
  The simulator builds every face, and `makeFace()` picks by
  `BOOP_SIM_FACE`.
- `include/rig_tables.h`: the pack's rig (§15), which staging also makes.
- The canvas palette (`render/palette.h`) is the engine's colours. A face
  that draws the canvas writes its own in as it's made
  (`render::useFaceColors`).

A board a pack names no face for doesn't build with it.

**On the Mac.** A pack with the pixel face has `mac/faces.json`: its moods
and the popover's still faces (the pixel face's README, in Pixel's pack).

`mac/mirror/`, if present, is the board's own firmware in a web page. The
popover shows it as the face in place of the still one, whether or not a
board is connected (unless the one connected draws the pixel face), and
onboarding shows it in its tiles and its demo.

- `board.js`: the firmware for a board with no hardware
  (`firmware/src/board/mirror/`) with the face the pack gives the AMOLED, as
  WebAssembly inside a script. Build it with `firmware/tools/mirror.sh`, and
  rebuild it when what the board draws changes: `make -C internal mirror`
  fails until it's the build of its sources.
- `index.html`, `mirror.css` and `mirror.js`: the page, written by hand. The
  app hands it every line the board's link sends the board, and a tap on the
  board as a tap on the mirror's screen or BOOT (`SlimeFeed`). It makes no
  sound, and nothing the board says leaves the page, so it can't answer the
  Mac.
- `tests/mirror/` holds the page's own tests (`node --test`), and
  `internal/tools/boopctl mirror` plays the gel's scenarios on the mirror
  and the simulator and checks every shot is the same, pixel for pixel.

## 10. Who's on the board

The board's `hello` names the pack its firmware was built with, beside its
`face` and its card's `voice`: `"pack":"boop 0.1.0"` (`kPackId` and
`kPackVersion` in the staged `moods.h`). The limits on the id and the
version (§4) are so that `hello` fits in one line.

When that isn't the Mac's pack, another id or another version, the Mac:

- says so in its log, and in the popover ("Other character"), until the
  board is flashed with the app's pack
- keeps working: the board draws its startup mood for a mood it doesn't
  have, and plays a Moment whose emotion it doesn't have in the look's mood
- speaks only when the card's voice is the app's (§8), a check of its own
- offers, in Boop.app's Settings, the app's own firmware for the board,
  built with the app's pack, even at the same version
  ([firmware/README.md](../firmware/README.md#updating-from-the-app))

Firmware too old to name its pack counts as the Mac's.

## 11. Licence

Every pack here is public, under the repository's MIT licence
([LICENSE](../LICENSE)), unless it carries a `LICENSE` of its own. A pack
from elsewhere brings its own.

## 12. The studio (optional)

The [Character Studio](studio/README.md), `characters/studio/`, is one page
for any pack: its moods and the engine's states, and a preview of each pair
when the pack brings one. A pack opts in with `studio` in `character.json`,
a list with an entry for each preview it brings. Pixel's:

```json
"studio": [
  {
    "id": "pixel",
    "label": "Pixel Boop",
    "about": "CYD board",
    "icon": "studio/icon.svg",
    "scripts": ["design/boop-sound-bank-v4/dist/boop-runtime.js", "studio/adapter.js"],
    "styles": ["studio/adapter.css"],
    "wears": "tools/borrowed.json"
  }
]
```

- `scripts` and `styles`: files the page loads, in order. One script
  registers the entry's adapter ([the studio's README](studio/README.md),
  Writing an adapter). The adapter's own files go in the pack's `studio/`
  folder, which the app doesn't bundle.
- `id`: the name the adapter registers under and the preview's card goes by,
  its own among the pack's entries.
- `wears`: optional, a JSON file whose `borrows` table names, for each mood
  the preview has no art of its own for, the mood whose art it shows.
- `families`: optional, a label and colour for each `family` the moods name.
- `label`, `about` and `icon` (an image): optional, for the character's
  card.
- `captures`: optional, a JSON file of `{"cases": [{"id": ...}]}`, the only
  clip names the studio's server will save for the pack.
- `board`: optional, one of the pack's faces (§9): the entry is that face's
  board's card, its id `board-<face>`, and adds to it. Its adapter,
  registered under that id, takes the board's (`StudioBoard.adapter`) and
  adds to it; with none, the card is the board's own.

With no entry, every pack gets the board's own preview of each face its
boards have (`faces`, §9), its id `board-<face>`, which the studio's
Transitions and References run on too (§16), and shows its steering, moods,
signs, takes, demos, evals and golden frames (`tests/golden-*/`).

`charactergen.py` writes the page's data (`characters/studio/packs.js`) from
the packs, and `--check` fails when a declared file is missing, a preview
wears a mood the pack doesn't have, or a board's entry isn't `board-<face>`
for one of its faces.

## 13. Demos (optional)

A pack can carry demos, `demo/<name>.jsonl`: the engine has the player
(`app/BoopKit/Demo/`), and the pack has the story, in its own moods and
words. The app bundles the scripts. Each demo of one buddy has its recording
beside it, `demo/recordings/<name>.json`, made from the script (`make -C
internal demos`) and checked in, which the simulator's page plays at once;
the app leaves the recordings out. How to write, record and play one:
[DEMOS.md](DEMOS.md).

## 14. Making your own

1. `make -C internal new-character ID=<id> NAME=<Name>` copies Pixel's pack
   to `../<id>/character/`, gives it its id and name, links it as
   `characters/<id>` and checks it. Leave out `design/`, `tools/` and the `studio` entry
   until you need them.
2. Change the moods' meanings and moves (§5). Every pack has the same moods,
   so keep every one; its faces must draw them all.
3. Rewrite `steering/guide.md` and `steering/personality.md` in its voice,
   and a `steering/mood/` file for each mood that needs one.
4. Change the faces, or keep Pixel's, which the copy already has. Keep its
   voice too, or delete `voice/` and `mac/takes.tsv` for a buddy that
   doesn't speak.
5. Run `make -C internal build` and `.build/debug/boopdev check`.
6. Try it: `CHARACTER=<yours> make demo NAME=hello` plays Pixel's short
   demo, which the copy carries, in the simulator's page.
7. Flash it: `make flash CHARACTER=<yours>`.
8. Optionally, write it demos ([DEMOS.md](DEMOS.md)), and give it a studio
   entry (§12) to look at every mood and state in
   `characters/studio/index.html`.

How the last new character ran, step by step, is
[new-character-playbook.md](new-character-playbook.md).

## 15. The rig (optional)

The rig is the one set of numbers every pack and face shares: at any instant
a character is a value on each of its channels. A pack's `rig/` says what
they do: what each mood wears, its moves and its looks. The engine's half is
`firmware/src/render/rig/`: the channels, the tables' types, the ramp its
fades ease on and the anchors a face reports (`rig.h`), the mixer that plays
them (`mixer.h`) and the layer stack (`layers.h`). A clip in a pack's
`clips/` plays on every face the pack has. Pixel's rig is the small one to
copy: expressions for its 13 drawn moods, the looks `idle`, `working` and
`asleep`, a `blink` and a stretch from `tier4`.

**Channels.** The body's `squash`, `lean`, `lift`, `x` (sideways, far enough
to leave the screen), `reach` (one side stretched out, the other pinched in)
and `melt` (let down into a puddle); the eyes' `eyeOpenL`, `eyeOpenR`,
`eyeSize`, `gazeX` and `gazeY`; and the mouth's `mouthOpen`. Each is a whole
number, in thousandths but for `lift` and `x` (px), with a range and a value
at rest, where a face draws its art as drawn: `kChannelInfo` in `rig.h` says
what each means, and `charactergen.py` checks the files by it. In the files,
`eyeOpen` sets both eyes. A face may draw only some: the gel draws them all,
and Pixel's neither `x`, `reach` nor `melt`.

A face also has two **styles**, the eyes' and the mouth's: which of its
drawings it draws, for the shapes no channel reaches (hearts, X eyes). A new
style cross-fades in. The pixel face's styles are its drawn moods' names: a
style is that mood's eyes, or its mouth.

**`expressions.json`**: for each mood the pack has one for, the styles it
wears, `eyes` and `mouth` both. Pixel's, cut to two of its moods:

```json
{
  "happy": {"eyes": "happy", "mouth": "happy"},
  "excited": {"eyes": "excited", "mouth": "excited"}
}
```

A mood without one has none of its own, and the face decides what it wears.

**`clips/<id>.json`**: a clip each, its id the file's name: keyframed curves
on some channels, timed in ms, with cues. Boop's notice, cut to two of its
tracks:

```json
{
  "about": "notice: it heard its name, from the notice-perk reference. Its eyes snap open, wide and up, and it perks up tall; it winds up, hops beaming with its eyes squeezed happy, lands flat with a squish and wobbles, looking at you.",
  "ms": 1000,
  "tracks": {
    "lift": [[0, 0], [200, 0], [280, 6, "out"], [400, 0], [460, 2], [560, 30, "out"], [760, 0, "in"], [1000, 0]],
    "gazeY": [[0, 0], [190, 0], [230, -600, "out"], [420, -400], [520, 0], [1000, 0]]
  },
  "cues": [[460, "body_contact"], [760, "body_contact"]]
}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `ms` | yes | Its length, 1 to 60000 |
| `loop` | no | Whether it loops, `false` without it. A looping clip's tracks start at 0 and end at `ms` on the value they started on |
| `additive` | no | `true` without it: its values are offsets on what's there, so it plays in any mood, each up to the channel's whole span either way. `false`: values to blend toward, each in the channel's range |
| `tracks` | no | For each channel, its keys in order of time, `[ms, value]` or `[ms, value, ease]`, the ease into the key from the one before: `linear`, `in`, `out` or `inout`, which a key without one has. Before its first key a track holds that key's value, and after its last the last's |
| `cues` | no | `[ms, name]`, each before `ms`: a sound the face plays by name as it crosses it. The gel's are its contacts' kinds (`body_contact` and the rest, slimegen's `recipes.mjs`); Pixel's face sounds no clip's cues |
| `about` | no | What it is, for people |

A pack has at most 255 clips, a track 255 keys, a clip 255 cues and a look
255 occasions (`MOST` in `charactergen.py`).

Some clips' ids mean something to a face:

- `blink`: Pixel's face plays it at each blink, but in a design that blinks
  on its own.
- `reply-wave`: the gel plays it for a small wave at your lock or unlock
  of the Mac, a slighter motion than `reply-bye` or `reply-hello`.
- `reply-<name>`: the gel plays it for that reply, one for each of
  `MomentOutput.replies` and `dunno`. A `nap` or a `dance` while the look is
  idle or asleep plays the gel's own pastime instead.
- A clip named for a Moment's state (Boop's `notice`): the gel plays it once
  as the Moment starts. The gel's recipe for that state times it.

**`looks.json`**: for each look (§9), keys `clip`, `occasions` and `tiers`:

- `clip`: the clip it loops under the Moments, one that loops, or null.
- `occasions`: pastimes the look plays now and then, each a `clip` that
  doesn't loop, and a tag list `when` (§9) or a wait `after` in seconds, at
  least one of them. Pixel's face gives them a chance at the end of each
  pass of the look's loop, while none plays and its design is the rig
  face's: while some fit, one of them plays 67% of the time
  (`rig::kOccasionPct`). It fades out when the look gives way. The gel plays
  none: its are rows of its pastimes.
- `tiers`: for a tier (`tier1` to `tier5`), a clip that loops in place of
  `clip` while that's the last tier reached. The gel plays them; Pixel's
  face doesn't.

Boop's:

```json
{
  "idle": {"clip": "breathe"},
  "working": {"clip": "work",
              "tiers": {"tier1": "work-easy", "tier2": "work-leaning", "tier3": "work-focused",
                        "tier4": "work-content", "tier5": "work-zone"}},
  "asleep": {"clip": "doze"}
}
```

Every file is optional, and one that's missing is empty.
`charactergen.py --check` fails on an unknown key, channel, mood, state,
clip or tag, a style that isn't a mood the pixel face the pack has draws
(its `faces.h`'s), a value out of its range, keys out of order, a loop that
doesn't close, an occasion that loops or would always fit, a tier's clip
that doesn't loop or a key of `tiers` that isn't a tier and a cue that isn't
a name before `ms`, each with its file and key (`rig/clips/hop.json:
tracks.lift[2]: …`). Staging writes the files as `rig_tables.h` in the
staged `firmware/include/`: `render::rig::kRig`, with a lookup by mood, clip
and look. The app doesn't bundle `rig/`.

**How it plays.** The mixer holds a damped spring on each channel, at rest.
The look's clip loops over the springs, and Moments' clips over that, a few
at once, each easing in and out over 150 ms (a quarter of a shorter clip).
With the mixer full, the oldest gives way, but the look's own. A poke or a
stroke kicks a spring. A new style cross-fades over the rig's fade
(`kFadeMs`, 200 ms). The face reports where the body is each frame
(`rig::Anchors`: the crown, a ring for a brim, the front lower down for the
hands, the eyes), so what's worn or held rides it.

**Pixel's face on the rig.** The pixel face draws its face from the rig
(`render/pixel/rig_face.h`) wherever a design's face is its mood's resting
face, in every mood whose expression's styles it has, and the design draws
the rest. The animation bank tags the resting face's parts ([Pixel's design
guide](https://github.com/Mellow-Machines-Lab/PixelBuddy/blob/main/character/design/README.md),
The resting face's tags), and facegen writes the moves into `faces.h`. Drawn
at rest, a tagged design must be the design as drawn, pixel for pixel, at
every step, or facegen fails, and `test_rig_face` checks it again. Untagged
designs are baked. On the rig face, `lift`, `squash` and `lean` move the
whole face; `eyeOpen` closes each eye, its shut art below a third open;
`eyeSize` scales the eyes, `gazeX` and `gazeY` shift them; `mouthOpen` opens
the mouth. A look's `clip` plays over a look's design's moves; a Moment's
design plays its own moves alone.

**The layer stack.** A face may draw what comes and goes around the body
through the rig's stack (`render/rig/layers.h`), back to front: the scene
behind the body, what's worn over the eyes or on the body, the hat, the air
and what's beside it. Each shows a content, the face's own number for what
it draws there, at an opacity that eases over `kFadeMs`; a new content waits
for the old to fade out.

**The gel on the rig.** The gel keeps its own engine for what no channel
reaches: each mood's face is its own art, and its scenes, bits (`gags` in
its design's JSON) and springs move its body (the slime's `CONTINUITY.md`).
It lays the channels over the engine's pose (`applyRig`), so at rest a frame
is the engine's alone. `lift` and `x` are canvas px, 85 a body unit. Its
expressions aren't the rig's. Its pastimes (`render/gel/pastimes.h`,
`pastimes` in its design's `expressions.json`) are one table, a row each,
whose body is a clip of the rig, a bit or a take: each for one look, at work
and idle from a tier, while something needs you or asleep from a wait, or
whenever a tag is on. Its kit stays out while its tier lasts. `dbg.pastime`
plays one by its name, for scenarios and tools.

## 16. References and review (optional)

A person gives a short reference, a sketch, a still, a GIF or a video, with
a line: inspiration, or "make this". An agent reads it and turns it into the
pack's data, and the studio (§12) shows the two side by side. Each reference
is a folder, `references/<YYYY-MM-DD>-<topic>/`, Boop's worked one:

```
references/2026-10-24-notice-perk/
  perk.gif              what was given: stills (.png .jpg .jpeg .webp), GIFs, videos (.mp4 .mov .m4v .webm)
  reference.json        what it is, and what became of it
  frames/perk.gif/      0000.png on, a frame every 40 ms (a still is one); kept where they're cut, not committed
  sheets/perk.gif.png   the frames on one sheet, 8 a row, each with its ms; committed
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
   sheet, and moves the status to `read`. The sheets are committed and the
   frames aren't: in another checkout, run it again for the studio to play
   the reference frame by frame. The agent looks at the sheets and writes
   `reading.md`: the beats and their timing, the poses, squash and stretch,
   the eyes' and mouth's shapes, the colours and the silhouette. A reference
   that needs more than the character has (arms, ears, a new body) says so,
   for the owner, and is never faked.
3. **Translate.** The agent makes it into the rig's data (§15), sets
   `became` and `show`, and puts it up for review.
4. **Review.** Agents list what's up in `review/queue.json`, each item
   `{"id", "title", "what", "before", "after", "status"}`: `before` and
   `after` are images in `characters/`, by their paths from the repository's
   root, and the status is `in review`, `changes` or `approved`. The owner
   approves or asks for a change in the studio's Review, and its server
   appends each verdict to `review/notes.jsonl`, a line each:
   `{"at", "id", "verdict": "approve" | "change", "text"}`. Agents read the
   notes, act on them, and update the item and the reference.

`charactergen.py --check` fails on a reference:

- whose folder isn't named so, or whose `reference.json` has a key or a
  value it doesn't take;
- whose `show` names a mood the pack hasn't or a state the board hasn't;
- that has no media, or a file that isn't media or its own;
- that's read without the sheet of every file or without `frames` and `ms`,
  or, where this checkout has cut the frames, with `frames` that don't count
  them;
- that's translated or later without `reading.md` or a `became`, or became
  something the rig hasn't.

It checks the queue's items and their images, and the notes, the same way,
each problem with its file and key (`reference.json: show.mood: …`,
`queue.json: perk.status: …`, `notes.jsonl:2: verdict: …`). None of it stops
a pack staging. The app doesn't bundle either folder.

## Not yet

- Pixel draws and voices 13 of the moods; the others borrow theirs
  (`characters/pixel/tools/borrowed.json`) until they have art and takes of
  their own.
- Pixel's mood moves are Boop's; they become Pixel's own.
- Pixel's rig face draws only the designs whose face is its mood's resting
  face (§15); a design whose face changes shape is still baked, since the
  rig's parts are one drawing of each eye. The gel's expressions, recipes,
  bits and springs are still its own.
- A face is C++ code. A picture-based face, with frames per state and mood
  drawn by an engine renderer, would let a character be drawn with no code.
