# Characters: the pack spec

Updated 2026-11-25. The contract a character pack meets, so that any
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
| `rig/` | no | Its clips and looks on the rig (§15) |
| `mac/mirror/` | no | The board's firmware in a web page, the face the popover and onboarding show (§9) |
| `mac/passing.tsv` | no | The popover's words for what the face does to pass the time and between Doings, by the name `Face::passing` says: `pastime` or `doing`, the name, the words after "Boop's" |
| `mac/takes.tsv` and `voice/voice.bin` | no, both or neither | Its recorded voice (§8) |
| `demo/<name>.jsonl` | no | Its demos ([DEMOS.md](DEMOS.md)) |
| `demo/recordings/<name>.json` | one for each demo of one buddy | What the board was sent as the demo played, which the simulator's page plays (§13) |
| `studio/` and `studio` in `character.json` | no | Its preview in the Character Studio (§12) |
| `references/` | no | What people gave to make it from (§16) |
| `LICENSE` | no | The pack's own licence; without one, the repository's MIT licence (§11) |
| `design/`, `tools/`, `tests/`, `evals/` | no | What its art and sounds are made from, and its own tests |

To make one, see §14. To check one, from the engine's repository:

```sh
make -C internal build && .build/debug/boopdev check # every pack in characters/
.build/debug/boopdev check path/to/pack             # one pack, anywhere
```

- `boopdev check` says whether a pack plays. It reads the pack as the app
  does: `character.json` with its faces and lasting moods, the steering and
  its budgets, the faces' files, the voice and every demo.
- `charactergen.py --check` says whether it builds: the moods and startup
  mood `moods.h` needs, the rig, the studio entry and the references. It
  also prints the pack's gaps, what it lacks that doesn't stop it: moods a
  preview has no art for, lasting moods with no steering file, moods with
  no voice takes, no signs or dream signs.
- `CHARACTER=<name> make -C internal fw-test` builds its faces on the Mac
  and runs the engine's firmware tests and the pack's own.

A pack that passes all three plugs in.

The engine's own Swift tests (`make -C internal test`) run with Boop's pack.
Its firmware tests run on a small stub face, whatever the pack
(`internal/firmware/stub_face.h`). Run with another
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
- When states change (the core's rules).
- *That* a mood is picked after events.
- The protocol.

**Decided by the pack:**
- How each state looks and sounds.
- What each mood means, how the moods connect and how fast they move.
- Its prompts, and whether it has a voice.

Boop has one pack, **`boop`**, in a public repository of its own,
[SlimeBuddy](https://github.com/Mellow-Machines-Lab/SlimeBuddy): the gel
slime, on the AMOLED. Its pack is the repository's `character/` folder, and
the engine is beside it as the `engine/` submodule.

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
  reads (`design/` and `references/`).
- `pack`: the one pointer to it.
- `firmware/`: the pack's, with the two headers staging makes (`moods.h`,
  §9, and `rig_tables.h`, §15).
- `packs/`: what the app bundles, which leaves out a pack's firmware, rig,
  voice file, tools and tests. It holds the chosen pack, which
  `packs/chosen` names.

`firmware/tools/pio.sh` stages before every PlatformIO run, and
`make -C internal build` before every app build. A stage changes only what
differs: a changed file is replaced whole, so a build reading while another
stages finds every file there. Staging also links the pack's firmware tests
(`tests/firmware/test_*`) beside the engine's, so `make -C internal fw-test`
runs both; `make -C internal tools-test` runs the Python tests in a pack's
`tests/tools/`.

`charactergen.py --firmware-to=DIR PACK` lays out one pack's `firmware/`
alone in `DIR/firmware/`, and changes nothing staged
(`simulator/web/build.sh boop`,
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
  mac/        mirror/  passing.tsv  takes.tsv
  firmware/   include/…  src/render/<face>/…  src/render/make_face.cpp
  rig/        looks.json  clips/<id>.json
  voice/      voice.bin
  demo/       <name>.jsonl  recordings/<name>.json
  studio/  references/  design/  tools/  evals/
  tests/      firmware/  tools/  mirror/
```

The engine reads built files only. How a pack makes them is its business. A
pack commits its built files, so building the engine never needs the pack's
own tools or what they were made from.

## 4. `character.json`

Boop's, cut to two of its 7 lasting moods and two of its 18 faces:

```json
{
  "id": "boop",
  "name": "Boop",
  "version": "0.1.0",
  "default_mood": "calm",
  "startup_mood": "happy",
  "lasting": [
    {"id": "calm", "meaning": "Settled, the resting mood: nothing much is happening."},
    {
      "id": "cross",
      "meaning": "Cross: a failure, pokes or shakes that keep coming, an interruption, or being hushed.",
      "levels": ["annoyed", "grumpy", "angry"],
      "fade": {"minutes": 3}
    }
  ],
  "moods": [
    {"id": "calm", "family": "settled", "face": "A calm face: all is well, and nothing stands out."},
    {"id": "annoyed", "family": "frustration", "settles": "cross", "face": "An annoyed face: a small failure…", "face_not_for": "A win."}
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
| `claims_a_fix` | no | The words of its voice that say something was fixed. Boop says one only on a turn that got past a failed check, or at the check passing again |
| `skits` | no | The few moments that always speak, each from takes of its own, by the slots they play at (§8). Without it, its Moments say nothing but your replies' and its waves' words |
| `moods` | yes | Every face the Mac may ask for, once (§5). Its order is the firmware's `Mood` order |
| `board_faces` | no | Faces only the board draws so far, after `moods` in the firmware's `Mood` order, each with `id`, `face`, `settles` and `family` as in `moods` (§5). The Mac doesn't read it, so no rule or brain picks one; a `do`, a `state` or a scenario may name one, and the board draws it |
| `lasting` | yes | The moods the buddy settles into, with their fades (§5). A pack without it doesn't load |
| `acts` | no | What the pack draws for each work act, as Jev reads it: by kind (`push`, `tests`, `build`), then by `start`, `pass` and `fail`, a sentence with `{name}` for the creature's name. The engine says what the agent did and adds this. Without it, Jev reads the agent's clause alone |
| `studio` | no | The pack's preview in the Character Studio (§12). Only the studio reads it |
| `faces` | yes | The face each board draws, by the board's name: `amoled206` (§9). A board it names none for won't build with it |

Unknown keys are ignored, so a newer pack still loads in an older engine.

## 5. Moods

A pack names its own faces and its own moods; the engine names none. Boop
has 18 faces the Mac picks from, six more only its board draws (its meme
faces, `board_faces`: deadpan, side_eye, squint, smug, silent_scream,
faint), and 7 lasting moods, and `character.json` is the one place that
says which: read it there. For a rule or the brain to pick a board face,
move it into `moods`; the Mac's tests pin Boop's 18.

**A face** (`moods`) is what the board draws under one name: the emotion a
Moment can show, and the name the wire's `mood` carries. **A lasting mood**
(`lasting`) is what the buddy settles into: it has a file in
`steering/mood/`, and the `mood` question offers staying in the one it has
and every other. There is no graph: Jev may move to any mood when NOW
gives a reason. A mood named `lonely` is offered only when it may begin
(`MoodOutput.mayMiss`): no agent working, and either an idle check-in with
the wish waiting an hour or your coming back after 20 to 40 hours.

Each face in `moods`:

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Its name, as the brain and the protocol see it: lower case and `_` |
| `face` | yes | What this face means for a single Moment: the option text when the brain picks a Moment's emotion |
| `settles` | unless a lasting mood has its name | The lasting mood a word for it reads as: a log from before, or the dashboard setting it |
| `face_not_for` | no | When the face isn't meant, added to the face's option |
| `family` | no | A group of related faces (`joy`, `frustration`…), for designers; the engine doesn't read it |

Each mood in `lasting`:

| Key | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Its name. It rests in the face of the same name, unless it has `levels` |
| `meaning` | yes | When the buddy is in it: the option text when the brain picks a mood, in plain words |
| `not_for` | no | When the mood isn't meant, added to its option |
| `fade` | no | How it settles by itself: after `minutes` in it, to `to` (the resting mood for none). `holds` stops the clock while it's so: `working` (an agent works; the minutes count from the turn's end) or `away` (you're away; they count from your coming back). The resting mood has none |
| `levels` | no | For a mood with levels, the face it rests in at each, mildest first. Code counts the level; a fade takes it a level down before it leaves |

Two things are code's, never Jev's (`MoodOutput`, `Runtime.moodRules`), and
each is a change of the mood in the transcript, by `rule`:

- **The fade.** On the Mac's clock, a mood that has lasted its `minutes`
  since its latest change goes to its `to`.
- **The level.** A levelled mood starts as cross as what caused it and
  goes a level up at each thing that provokes it: a poke that's the second
  or more in a row, a shake, a failed check, a failed turn, rude words (a
  reply of `ouch`). A stroke, a swipe or a finger at rest takes it a level
  down, never below the first. The MOOD section ends with the level's
  face, so Jev knows it without picking it.

The wire's `mood` is the face the mood rests in: `focused` for focused,
and `annoyed`, `grumpy` or `angry` for cross. On the gel, the body gives a
small beat when the mood changes, and none for a change of face within one
mood.

## 6. A pack stands alone

A pack has every file the engine reads in its own folder. The engine reads
the staged pack (§2) and never falls back to another. Two packs that want
the same voice or face copy it, each in its own repository.

## 7. Steering

What the brain reads, in plain Markdown. Each file has a budget in tokens,
the same for every pack (`Steering.Budget`, in
`app/BoopKit/Harness/Steering.swift`). The app logs a file over its budget
and still uses it.

The prompt's order is the guide,
PERSONALITY, MEMORY, MOOD, CONTEXT, HISTORY (closed by how long the mood has
lasted) and NOW.

**`guide.md`** (required): how the buddy reads what happens, read on every
pass.

**`personality.md`** (required): who it is, the whole of it, temperament
included.

- Its front matter sets the check-ins: `working_heartbeat` (seconds between
  check-ins on a turn) and `idle_heartbeat` (seconds between idle check-ins
  while you're around and no agent works, twice that with no agent open;
  without it, none).
  Boop's: `working_heartbeat: 240-360`.
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
  (only while it's quiet, with the minutes left when that's for a while), the buddy
  (its level and age), You (at the Mac and untouched, each from an hour,
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
and what moves it. No minutes: the app fades a mood by its clock (§5). A
missing file reads as `default_mood`'s.

**`dreams.md`** (optional): the signs it may hold up as it tells its dream.
A dream is everything since the last one, in tags and a sentence
(`DreamReader`), made once a sleep, 2 h into one begun at night or 5 h into one begun by day, or after two days. You coming back after
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
`[wish pet] pet me?` is the sign that makes it, a kind's lines taking turns by the day, `[wish pet met] <3` what it
holds up as it's met, for the kinds `pet`, `chat` and `work`; code says what
meets each, and deals it as an idle beat (`IdleBeat`). A pack with no such
line makes no wish. The gel draws the thought bubble (`state.wish`), and a
lane with none says `wants: pet`.

**`asks.md`** (optional): what it may ask you, with two answers you tap
(`Asks`). Ask only what does something with the answer: it becomes part of
the buddy (`keeps`), or it goes into memory; idle
chatter is a musing instead (`signs.md`). A pack without the file never
asks.

- `- [id tags] question | a | b` is a question. Its first tag is its id,
  then the tags it needs:
  - its moment: `idle` (an idle check-in). Never a finish, whose thread
    the face names;
  - the calendar's, and your kept answers;
  - `keeps`: asked once, ever, and its answer becomes a tag for good, as
    `cookie`.
- `- [id answer] words` is a follow-up it may hold up after that answer.
- A question is at most 18 characters, an answer 7, a follow-up 18 (`boopdev
  check`).
- An ask is dealt as an idle beat (`IdleBeat`): the sign question
  (`react.sign`) offers the first question that fits, when nothing before it
  is due, and Jev may always pass. The beat's one cap: one an hour, four a
  day, none on Quiet, never while something needs you.
- The board holds the question up as its sign and the two answers in its
  lane. After 45 seconds, or a newer Moment, it ends unanswered (`ev ask`).
  One answered stays off for 30 days, one ignored for a day.

**`signs.md`** (optional): the captions it may hold up when it reacts to
your prompt (`Signs`, the `react.sign` question, asked only when NOW is a
prompt's reading, not a message's). A pack without the file holds up no
signs.

Its `[invite tap]` and `[invite stroke]` lines are the word the board shows
by the place to touch when a skit invites that touch (`Signs.invite`, the
first of each; Boop's say `tap` and `pet`). A pack with none
shows the glow alone.

Its `[remark fast]`, `[remark slow]`, `[remark run]`, `[remark count]`,
`[remark early]`, `[remark late]`, `[remark soon]` and `[remark longBreak]`
lines are what it holds up for a remark: how now differs from your usual,
which code picks, no brain (`Remarks`, `Signs.remark`). `{n}` is the run
for `run` and today's wins for `count`. A remark shows as text only: on a
`win` a low Moment after the finish, on a `back` the Moment's sign. A pack
with no line for a remark shows none; Boop's has
one line each ("that was fast", "{n} in a row", "you're early").

Its `[world]` lines, and `[world boop]`, `[world wave]`, `[world heart]` and
`[world cheer]`, the kind's first, are what it may hold up when another buddy
reaches out from the world (`Signs.world`): Jev picks one at the `world` event.
A pack with none holds up nothing then. A level-up holds `level 12!` low in
gold (the `do`'s `gold`; a face that holds nothing low holds it up as its
sign), and today's ring closing holds `100 XP today, day 12` low in gold
behind a full ring (the `do`'s `mark`: `ring`; `gold`, `silver` or `bronze`
for a league's medal; none for a star), one moment when both come at once,
the level then held up: the rules' own, needing nothing of the pack's.

**XP** shows only on low signs (plan/xp-league.md §5): a `do`'s `xp`, what its
event earned, is a chip at the right end of the finish's sign or of a low
sign, `+5 XP`. There is no bar, and a `state` carries no XP.

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
- Lines tagged `[idle]` are its musings instead: the idle beat dealt at an
  idle check-in when nothing else is due (`IdleBeat`), up to three to choose
  among, never on Quiet, and Jev may pass. `{turns}` is
  today's turns and `{thread}` the busiest session's thread name (a line
  that needs one is left out without it). A line may need a kept answer's
  tag (`[idle cookie] snack time?`).
- Lines tagged `[notice waiting]`, `[notice stretch]`, `[notice rough]` or
  `[notice late]` are what it may hold up for a notice (`Notices`): only at
  an idle check-in, dealt as the idle beat (`waiting` first), by name. `{agent}` is the agent's name. A pack with no
  lines for a notice never has it.

**`replies.md`** (optional): what it holds up replying to your words
(`Signs.replies`). A pack without the file holds up nothing for a reply but
the facts. A line's `{turns}` is today's turns (left out under 2).

- The brain picks a reply (`react.reply`, asked only of your words): yes,
  no, huh, hello, bye, thanks, ouch, comfort, hehe, status or hush
  (`MomentOutput.replies`). A `huh` to a question
  plays as `dunno`, a shrug. Thanks takes affection and making up too, and
  no a trick turned down or anything asked for an agent.
- The `bye` lines are also what it holds up at your lock of the Mac, when
  the rule gives it a real wave (`MomentRule.bye`): `[bye night]` at
  night, `[bye working]` while an agent works.
- Each line is `- [reply tags] words`. Its first tag is the reply; any more
  are the calendar's or the moment's: `working` (an agent works), `waiting`
  (something waits on you).
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
- A `hush` makes Talk quiet for half an hour (`Core.quiet`), as the app's
  Hush button does. Talking to the buddy, the popover or choosing a Talk
  ends it.
- The board plays the reply's clip (§15), and Voice says the reply's own
  words, its takes in the voice (§8): a yes says "Yep", a no "Tsk". With
  none in the face, it says nothing: never another reply's words, nor a
  skit's.

## 8. Voice (optional)

A pack with a voice has recorded takes, each tagged with the moods it plays
in, a part and a meaning, and a kind (sound, word, phrase or swear). The
brain never picks whether the buddy speaks: a rule does, at three kinds of
moment, and everything else plays in silence:

- A skit: one of the few moments that always speak, each from takes of its
  own (`skits`, below). The brain can't veto one: when it picks no face,
  the Moment plays in the rules brain's first face for the moment, as the
  mood colours it. With more than one thing it may say, Jev may pick which
  (`skit.take`): its options are the texts of the skit's takes of the kind
  the size asks, at most 6, those not said lately first. The rules leave
  it unanswered, so with no key Voice picks. A text the chosen face has no
  take of says Voice's own pick.
- Your words: the reply's own words (§7).
- A real wave at your lock or unlock: the `hello` or `bye` reply's own
  takes (part `reply`), as to your words.

The Moment's size, which the app's rules pick (`MomentRule.size`), picks
the kind: a sound small, a word medium, a phrase big. With none of that
kind in the face, Voice takes the nearest, plainer first. A swear plays
only in the `upset` skit, once failures pile up (the third failed check in
a row, or a failed turn with two or more failed checks), and only when the
person has turned swearing on in Settings (it's off by default); on Quiet
nothing swears. With no swear in the face, it says a plain take, never
nothing.

A take's part says what it is, one of two:

| Part | Its meaning | Said |
| --- | --- | --- |
| `skit` | The skit's id | At the skit |
| `reply` | The reply's name, or `dunno`, a huh to a question | To your words, and at a lock's real wave |

`skits` in `character.json` names each skit and the slots it plays at,
the rules' readings of an event (`RulesBrain.Slot`); code says when each
plays and whether it swears (`Skits.play`). A skit may have a `clip`, a
clip of the pack's rig (§15) that its Moment plays as its face starts: the
`do`'s `clip`, which a Moment with a clip of its own keeps. A skit may have
an `invite`:
after it plays, Boop turns to you in a `pose` (`palm`, `lean` or `back`)
and waits for one `touch` (`tap` or `stroke`), which pays off
(`highfive`, `purr` or `sigh`), each a name the board plays (`Skit.Invite`).
A skit with both plays the clip first, then the invite. An id missing, or
one that isn't a name of 15 letters, digits or dashes at most (what the
board keeps of one to name the invite it ends, `Skit.idBytes`), a slot that isn't one, a slot in two skits, a clip that isn't a name of 11
letters, digits or dashes at most (what the board keeps of one,
`Skit.clipBytes`), or an invite whose pose, touch or payoff isn't one, and
the pack doesn't load. Boop's:

```json
"skits": [
  {"id": "win",   "slots": ["doneLong", "doneVeryLong"],
   "invite": {"pose": "palm", "touch": "tap", "payoff": "highfive"}},
  {"id": "upset", "slots": ["failed", "failedVeryLong", "gaveUp", "checkFailing"],
   "invite": {"pose": "back", "touch": "stroke", "payoff": "sigh"}},
  {"id": "fix",   "slots": ["checkFixed"], "clip": "flop"},
  {"id": "back",  "slots": ["back", "backDays", "backAfterADay"],
   "invite": {"pose": "lean", "touch": "stroke", "payoff": "purr"}}
]
```

Code asks a skit's invite (`MomentOutput`, `InviteLedger`): only of a board
whose `hello` says `"invites":1`, never on a call or while something needs
you, at most 10 a Boop day, and after 3 misses in a row of a pose only
every second time. It rides the `do`'s `args` as `invite` (`skit`, `pose`,
`touch`, `payoff`, the `label` by the place to touch, the wait `ms`, 4000,
or 12000 for the very first, and the `xp` the touch earns), and the board
plays it inside that `do` and reports how it ended with `ev invite`
(`answered`, `missed`, `late` or `cut`). The label is the pack's (`signs.md`'s
`[invite tap]` and `[invite stroke]`), shown until the pose was answered 5
times, and again after 3 misses in a row of it.

`win` is a turn of a minute or more done ("Done", "Nailed it"), `upset` a
failed turn, the agent giving up, or the third failed check in a row ("Oh
no", "Not again"), `fix` a check passing after it failed ("Phew...",
"Fixed", and the flop of relief against the glass), and `back` you back at
the Mac after a break ("Hello", "Hey").
Every other moment has none.

A `win` or a `back` may also carry a remark, the pack's `[remark …]` line
in `signs.md` (`Remarks`): text, never a take, at most one skit in three.

- `voice/voice.bin` is the voice file, for the board's microSD card.
- `mac/takes.tsv` is its table, which the Mac reads to pick a take: the
  voice file's version on its first line after the comments, the same one
  the board reports, then a take a line, tab separated: id, text, part,
  meaning, kind, moods (space separated), a column kept empty (it once said
  the finish a take needed; none does, and readers still find eight) and ms. It
  lists only what a reply or a skit says: a take that's the words of
  several is in it once for each, by the same id (voicegen's `REPLY_OF`,
  `SKIT_OF`), and the voice file has it once. The table may list fewer
  takes than the voice file holds: Boop's card keeps every take it was
  built with, 2,995, and the table lists 957 of them, so the voice file
  and its version stayed as they were when the table had the rest.

Both are built files and checked in, and a pack has both or neither. Boop's
pack holds the recordings and voicegen, the tool that makes the two files;
espeak-ng placeholders stand in for lines not recorded yet
(`plans/regenerate.json` in its `design/assets/boop-voice-v1/`).

A pack without a voice leaves both out, and its Moments play faces and
sound effects only.

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
| `tool_use` | Typing: an agent edits, uses any other tool, or plans | the Mac |
| `analyzing` | Looking: an agent reads or searches files, or the web | the Mac |
| `terminal` | Running: an agent runs a command, the tests or a build, or its helpers work | the Mac |
| `waiting` | A tool takes its time; nothing is asked of you | the Mac |
| `planning` | No longer sent: the Mac's activities are the four above (`Act`). The board still knows it; the gel shows it as typing, with typing's takes (it has no recipe of its own, nor has `tool_use`: both play `working`'s) | no one |
| `searching` | No longer sent, as `planning`; the gel shows it as looking | no one |
| `testing` | No longer sent, as `planning`; the gel shows it as running | no one |
| `delegating` | No longer sent, as `planning`; the gel shows it as running | no one |
| `needs_you` | An agent waits for your approval or answer on the Mac | the Mac |
| `no_app` | The engine no longer shows this look: with the Mac lost, the board shows `idle` with the strip's plug, then `asleep` with no plug. A touch gets the board's own reaction | the board |

**Moments' animations** play once over the look, or `loops` times (1 to 6),
then go.

| State | When it plays | Sent by |
| --- | --- | --- |
| `starting` | An agent starts; `ctx` may say how: `new_task`, `session`, `continuation` or `compacted`. The board's firmware knows it | a tool (`boopctl`); the Mac sends none |
| `task_complete` | A turn ends: the finish. `outcome` is `success` or `failure`, and `turn` the tier it reached: 0 short of `tier1`, then 1 to 3 (`Moment.turn`) | the Mac (the brain) |
| `reply_ready` | A turn ends with an answer, or a question back | the Mac (the brain) |
| `wake_up` | You come back to the Mac after a long break | the Mac (the brain) |
| `wish_met`, `wish_gone` | The rules': a wish given, which plays `notice`'s design under the thought bubble's heart, unless a touch's `gesture` plays, which stays, or `listening` holds the face, when only the heart goes; a wish left, which fades the bubble and plays the rig's silent `wish-gone` clip, a sigh and a slump of about a second; the feeling after it is Jev's | the Mac's rules |
| `notice` | You named it in your prompt: it looks up at you, surprised and pleased, as if it heard its name | the Mac (the brain) |
| `gesture` | The board's own Moment for a touch, its variations in this order (`render::Gesture`): `handoff` (BOOT hands you an agent), `stroke`, `ruffle` (stroked the wrong way), `nose` (a tap on the face's middle; on the brain's finish that names whose turn it was, a tap on that opens the thread), `tickle`, `dizzy` (shaken), `pickup`, `putdown`, `startle` (a thump on the desk), `peekaboo` (turned face up again). A face with fewer draws its first. The Mac reads these as its seven touches (`Touch.read`): a ruffle is a stroke, a nose boop and a tickle pokes, a thump a shake, a put-down and a peekaboo the ends of a pick-up and of face down | the board |
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
with the request's number, `data.attn`) and plays nothing. Anywhere else, on a
face that can (`leans`, `lean`), a finger at rest for a second leans the face
into it, and past 5 s dozes it (`app/touch_gesture.h`'s `kLeanMs`, `kDozeMs`);
as it lifts, the board tells the Mac `lean`, care like a stroke, and no animation
plays. On a face that can't, it stays the tap it was.

**A board tilted.** On a board with a motion sensor, a face may follow its steady
tilt (`tilt`, in milli-g across the screen, `app/motion_gesture.h`'s `Tilt`): how
far it's tipped against how it's been resting, so one set down at an angle comes
back to none. It sends nothing to the Mac and counts as no touch. The gel's body
sloshes that way while nothing else moves it; a face that doesn't override it does nothing.

**A Moment with no animation** (`react`) is no state of its own: the face
draws the look in another emotion for a while, and the voice may speak.

**A word of the work stream** (`call`) is no state of its own either
(`render/stream.h`), and never a Moment: `w` the word, `a` its lane's slot,
`as` its style (`bonk`, `shrug`, `land`… `render::CallStyle`). It plays at once over the agents' work and holds nothing up, its
`ended` sent as it starts. With no lane working, or while something needs
you, it's skipped `hidden`. A failed call is one of its styles.

**A work act** (`wact` in `state`, `render::Stream::ActIn`) is a command
worth naming while it runs, part of Doing and never a Moment: `[kind, words]`,
then `[kind, words, result]`, the kind `push`, `tests` or `build`, the words
what the strip says while it runs, and the result `p` or `f` once the command
has ended. The Mac holds a result for the board's `kActLeadMs`, less what's
run of it, and `kActResultMs`. A face that doesn't draw it ignores it. On the
gel, the monitor's icon (a flask for tests) and the strip's term say what's
running, then a tick or a cross and the strip says `tests passed` or `tests
failed`, the kind's name in the board's words; never a card or a low sign.
Its body hops at a pass and flinches at a fail (the gel's `termFor`,
`GelFace::answerAct`).

### What else a face does

The engine's interface is `render::Face` (`firmware/src/render/face.h`).
Besides drawing each mood and state, a face:

- **Draws the work stream, if it can.** Before each frame the device hands
  it the stream (`Face::watch`): each working lane's latest word and call
  count from `state`'s `calls`, the newest of those words, and the word a
  `call` brought forward. A face that doesn't draw it ignores it.
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
    `programmers`, `lunar`, and `party` (a milestone day since hatching or New
    Year's Day, but never the day it hatched). The Mac greets a special day
    with its sign.
  - The tiers (`Tags.tiers`): `tier1` from a minute, `tier2` from 5,
    `tier3` from 15. The board's table also lists `tier4` and `tier5`,
    which the Mac never sends: they keep their place, so no pack's
    numbering of the others moves. The tiers count how
    long the agents' working stretch has run, from its first turn, a rest of
    under a minute carrying it on; or, once nothing works, how long since
    the latest session came to rest. The Mac sends the last reached and the
    board takes every one below it as on (`render::reached`), so a design
    for `tier2` shows from then on, at work or idle as its look says.
  - Your hands at the
    Mac, `typing` or `reading` (`Hands`); the Mac's side, `macleft` or
    `macright` (from where Boop sits, `Anchor.side`); and, last in the table
    so no pack's numbering of the others moves, the rest of you at the Mac
    (`Along`): `scrolling`, `typingfast`, `music` or `video` and `oncall`
    (`copied` keeps its place but is no longer sent); `macup`, the screen above the board (its anchor in the middle
    third of its display); and `speaking`, another app recording with no camera. Boop's level puts no tag on: its body is one
    size at every level. A board with no Mac keeps none of the Mac's tags,
    as they go stale.
  - Not a tag: the way to your pointer while it moves (`state.ptr`, `[x,
    y]` each in -10…10, `[x, y, 1]` at the edge of the screen nearest the
    board), handed to the face as `FaceContext::pointer`. A face may follow
    it or not; none while the Mac sends none.
  - `busy` (2–3 sessions working) and `frantic` (4 or more), which the board
    adds from `state.busy`. The working looks also play at 125% and 160%
    then (`render::workPace`, `FaceContext::pace`).

  A design that needs tags shows only while they're on. A look starts on one
  while it fits and turns to one two times in three, and a Moment always
  takes one. A pack's rig may name clips by tags too (§15).
- **May dress for the tags.** The board and the Mac's popover
  (`Narration.Dressing`) agree on what's worn. The gel wears nothing, at
  night or on a special day,
  and has nothing in the air: its lids say the night. The gel draws its
  dressing at the anchors its pose gives (`rig::Anchors`, §15), so it moves
  with the body, and through the rig's layer stack (§15).
- **Times them.** Each design's loop length (`loopMs`), which sets how long
  a Moment plays, and its voice window (`voiceMs`), when a take may start.
- **Moves with the engine.** It blinks, opens its mouth while the voice
  speaks (`mouthOpen`), presses down under a finger (`dy`), and may follow
  one (`finger`, and `letGo` with how fast it was moving).
- **Leaves room for the lane.** On the face's 320 × 240 canvas, the bottom
  48 px are the lane: the strip and the bubble, their text cut by
  `render::cutAt`. The device hands both to the face (`Face::draw`), and
  the face draws them.
  - The bubble shows the voice's words, or an ask's answers.
  - The face also gets the `caption`: the Moment's narration, at most 18
    characters (the `do`'s `reason`: "you picked Boop up"). It is not
    speech. The gel shows it small and grey on the lane's last line.
  - A face that says `captionsTouches` gets a caption for its board's own
    touches too, as they play ("you poked Boop", `app/touch_reason.h`). Its
    name is the pack's, or `state`'s `buddy` for one you gave it. The gel's does.
  - The strip fades over the rig's 200 ms and the face gets its opacity
    (`Strip::opacity`), and the face draws its lane at that opacity.
- **Has a drawer, if it can** (`Face::hasDrawer`, `render/drawer.h`). The
  device keeps the finger, the spring, the scroll and the clock, and hands
  the face the drawer before each frame (`Face::drawer`). The face lays it
  out and says where its rows are and how far they scroll (`drawerTravel`,
  `drawerRow`, `drawerScrollMax`, `drawerSnap`, `drawerShown`). Each row is
  a session the Mac lists (`state`'s `list`, in a window, `skip` before and
  `unlisted` after): its thread's name, its agent and project, and whether
  it needs you, works or rests. A Moment can ask for it (the `do`'s
  `"show": "drawer"`). A face with none: a swipe up its strip is a swipe.
- **Holds an agent's card, if it can** (`Face::card`, `Face::cardAt`,
  `render::CardShow`). Before each frame, and as a finger goes down, the
  device hands the face the card the Mac's `state` carries: a status or a
  result, its main thing (24 glyphs at most), its small line (28), its
  session's lane slot, which card of how many, and how long it has shown.
  It's on only while nothing above Doing has the screen. The face draws it
  and says where it is (`cardAt`), only while it's drawn: a touch that begins there is the card's,
  and the device sends the Mac a swipe or a tap, playing nothing. A face
  with no card ignores it, and every touch stays the face's.
- **Holds up a sign.** Any Moment may carry words in `sign` (the `do`'s
  args), at most 18 glyphs of the fonts (accents folded, and past that cut
  at a word with `..`, `render::foldText`). A face gets them as `SignShow`
  (the words, how long they've shown, and their opacity) and draws them as
  its own, sliding up by `render::signLift`. The gel holds its card under the
  mouth, and a body too small to clear it stands up on the card
  (`SignLayer::kHopPx`). They stay up while any part of
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
  for it (§15, `reply-<name>`). A Moment's `clip` goes the same way, and
  the gel plays a clip of that very name when there's no `reply-<clip>`.
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
  name, never its number.
- One or more faces behind `render::Face`, each in its own folder,
  `src/render/<face>/`, and `render::makeFace()` in
  `src/render/make_face.cpp`, which makes one. `faces` in `character.json`
  names the face each board draws: Boop's `{"amoled206": "gel"}`. A board's
  build compiles that face's folder and no other. The simulator
  builds the AMOLED's face. The board's face must draw natively, into the
  panel's own surfaces (`Face::drawsNative`), or the firmware stops at
  start.
- `include/rig_tables.h`: the pack's rig (§15), which staging also makes.
- The canvas palette (`render/palette.h`) is the engine's colours only.

A board a pack names no face for doesn't build with it.

**On the Mac.** `mac/mirror/`, if present, is the board's own firmware in a
web page. The popover shows it as the face, whether or not a board is
connected, and onboarding shows it in its tiles and its demo. Without it,
the popover draws only the eyes (`BoopFace`).

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

The [Character Studio](studio/README.md), `characters/studio/`, plays the
chosen pack on its board's firmware: its moves (every rig clip, in the
groups the clips name, §15), its faces (every one the board draws, the
board's own marked), its moments (each of its `skits` as the Mac sends
it, with its invite answered or missed) and its face's motion switches,
with the mood at the top. It reads all of them from the pack's files.
A pack adds to its board's card with `studio` in `character.json`, a
list with an entry for each preview it brings. Boop's, cut to one of its
families:

```json
"studio": [
  {
    "id": "board-gel",
    "board": "gel",
    "icon": "studio/icon.svg",
    "scripts": ["design/slime-blob/sound/sfx.js", "studio/adapter.js"],
    "captures": "studio/review-sets.json",
    "families": {"settled": {"label": "Settled · low stimulation", "colour": "#7fb7a4"}}
  }
]
```

- `scripts` and `styles`: files the page loads, in order. One script
  registers the entry's adapter ([the studio's README](studio/README.md),
  A pack's tools). The adapter's own files go in the pack's `studio/`
  folder, which the app doesn't bundle.
- `id`: the name the adapter registers under and the preview's card goes by,
  its own among the pack's entries.
- `families`: optional, a label and colour for each `family` the moods
  name, which the mood picker groups them by.
- `label`, `about` and `icon` (an image): optional, for the character's
  card.
- `captures`: optional, a JSON file of `{"cases": [{"id": ...}]}`, the only
  clip names the studio's server will save for the pack.
- `board`: optional, one of the pack's faces (§9): the entry is that face's
  board's card, its id `board-<face>`, and adds to it. Its adapter,
  registered under that id, takes the board's (`StudioBoard.adapter`) and
  adds to it; with none, the card is the board's own.

With no entry, every pack gets the board's own preview of each face its
boards have (`faces`, §9), its id `board-<face>`.

`charactergen.py` writes the page's data (`characters/studio/packs.js`) from
the packs, and `--check` fails when a declared file is missing, or a board's
entry isn't `board-<face>`
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

No tool makes a new character now. To make one by hand:

1. Copy Boop's pack to a folder of its own, give it its own id and name
   (§4), and link it as `characters/<id>`.
2. Change the faces and the lasting moods, their meanings and fades (§5);
   its board's face must draw every face it names.
3. Rewrite `steering/guide.md` and `steering/personality.md` in its voice,
   and a `steering/mood/` file for each mood that needs one.
4. Keep the voice, or delete `voice/` and `mac/takes.tsv` for a buddy that
   doesn't speak.
5. Run `make -C internal build` and `.build/debug/boopdev check`.
6. Flash it: `make flash CHARACTER=<yours>`.
7. Optionally, write it demos ([DEMOS.md](DEMOS.md)). To look at its
   moves, faces and moments on its board, open the Character Studio
   (§12), and give each clip a `group` (§15) so it's listed with its kind.

## 15. The rig (optional)

The rig is the one set of numbers every pack and face shares: at any instant
a character is a value on each of its channels. A pack's `rig/` says what
they do: its moves and its looks. The engine's half is
`firmware/src/render/rig/`: the channels, the tables' types, the ramp its
fades ease on and the anchors a face reports (`rig.h`), the mixer that plays
them (`mixer.h`) and the layer stack (`layers.h`). A clip in a pack's
`clips/` plays on every face the pack has.

**Channels.** The body's `squash`, `lean`, `lift`, `x` (sideways, far enough
to leave the screen), `reach` (one side stretched out, the other pinched in)
and `melt` (let down into a puddle); the eyes' `eyeOpenL`, `eyeOpenR`,
`eyeSize`, `gazeX` and `gazeY`; the mouth's `mouthOpen`; the glass's, the
screen as a pane Boop lives behind: `glass` (the whole body up at it) and
the pale patch where the body touches it, `patch` (its size), `patchX` and
`patchY`; and two hands, part of the body, hidden in it at rest:
`handLX`, `handLY`, `handLSize`, `handLShape` (a fist, a ball or an open
palm) and `handLGlass` (pressed flat on the glass), and the right's the
same; and `turn`, how far round the body has turned, in thousandths of a
whole turn (500 its back to you, 1000 all the way round, a spin), which
moves only what's on its front round it, its outline staying. Each is a
whole number, in thousandths but for `lift`, `x` and the
hands' `X` and `Y` (px), with a range and a value at rest, where a face
draws its art as drawn: `kChannelInfo` in `rig.h` says what each means,
and `charactergen.py` checks the files by it. In the files, `eyeOpen` sets
both eyes. A face may draw only some: the gel draws them all.

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
| `cues` | no | `[ms, name]`, each before `ms`: a sound the face plays by name as it crosses it. The gel's are its contacts' kinds (`body_contact` and the rest, slimegen's `recipes.mjs`) |
| `about` | no | What it is, for people |
| `group` | no | Where the [Character Studio](studio/README.md) lists it: `bases` (a look's clip, and the moves between them), `work_poses`, `moments` (a reply's, a meme face's, the knock), `touch_answers` (an invite's poses, payoffs, misses and late returns), `pastimes` or `with_you` (`MOVE_GROUPS` in `charactergen.py`). Without one it's listed last, and `--check` says so as a gap |

A clip may be another's move at a size and a pace: a file with `of`, the
other clip's id, its `ms` and a `size`, and no tracks or cues of its own.
It plays that clip's keys and cues, each value times `size` / 1000 (1000
without it), their time stretched or squeezed to its `ms`, and loops and
adds as that clip does. Boop's bye is its `wave` as it is, and its small
wave the same at a third of the size, over a second:

```json
{"about": "A wave at your lock or unlock, a small moment.", "of": "wave", "size": 350, "ms": 1000}
```

| Key | Required | Meaning |
| --- | --- | --- |
| `of` | yes | The clip it plays, one with keys of its own |
| `ms` | yes | Its length, 1 to 60000 |
| `size` | no | Its values, in thousandths of that clip's, 1 to 4000; only 1000 for an absolute clip |
| `about` | no | What it is, for people |

The face plays it by its own id like any clip (`Clip::value`, `played`).

A pack has at most 255 clips, a track 255 keys and a clip 255 cues (`MOST`
in `charactergen.py`).

Some clips' ids mean something to a face:

- The gel's moves, which it plays by what shows and how long, not on its
  mixer: `invite-<pose>`, then `invite-<pose>-wait` looping, for an
  invite's pose, `invite-<payoff>` for the touch, `invite-<pose>-miss` and
  `invite-<pose>-late`; `knock` as something needs you and `knock-climb`
  when nobody comes. Their cues are where something hits the glass, which
  rings there. A pose or payoff with no clip doesn't move the body. Boop's
  back (`invite-back`…) and the high five's spin are on `turn`.
- `idle-<mood>`, one for each lasting mood (§7): the gel's idle move for
  that mood, which it plays now and then in idle, each face its lasting
  mood's (slimegen's `kIdleMoves`); slimegen fails without one.
- `face-<face>` (a face's `_` a `-`): a face's own move, which the gel
  plays in idle in place of its mood's, and once as a Moment shows the
  face; Boop's six meme faces have one each (`face-deadpan`…).
- `reply-wave`: the gel plays it for a small wave at your lock or unlock
  of the Mac, a slighter motion than `reply-bye` or `reply-hello`: Boop's
  is its `wave` at a third of the size over a second, and its `reply-bye`
  the same `wave` whole.
- `reply-<name>`: the gel plays it for that reply, one for each of
  `MomentOutput.replies` and `dunno`, and for a Moment's `clip` of that
  name (`remember`, as it brings up a remembered line). A Moment's `clip`
  with no `reply-<clip>` plays the clip of that name itself.
- `flop`: the `fix` skit's `clip`, the flop of relief, which the gel plays
  as the fix's Moment starts.
- A clip named for a Moment's state (Boop's `notice`): the gel plays it once
  as the Moment starts. The gel's recipe for that state times it.
- You at the Mac: the gel loops `type-along` while it types with you, and
  `type-along-fast` over it while you type fast; `read-along` (then
  `read-along-settled`), `video`, `groove`, `speak-along` and `on-call`
  while it's with you so (its `GelFace::showWithYou`); and once, `stretch` as a call ends, `look-around` as the
  music stops.

**`looks.json`**: for each look (§9), keys `clip`, `tiers` and `acts`:

- `clip`: the clip it loops under the Moments, one that loops, or null.
- `tiers`: for a tier (`tier1` to `tier3`), a clip that loops in place of
  `clip` while that's the last tier reached. The gel plays them.
- `acts`: for an activity, by its state (§9), a clip that loops in place of
  `clip` and of any tier's while the agents' activity is that one: the pose
  the whole body takes for it. The gel plays them, each coming over 400 ms
  (`gel::kPoseMs`, the mixer's `setLook`), so a change of activity is a
  move and not a jump.

Boop's:

```json
{
  "idle": {"clip": "breathe"},
  "working": {"clip": "work",
              "tiers": {"tier1": "work-easy", "tier2": "work-focused", "tier3": "work-zone"},
              "acts": {"analyzing": "work-looking", "terminal": "work-running", "waiting": "work-waiting"}},
  "asleep": {"clip": "doze"}
}
```

Every file is optional, and one that's missing is empty.
`charactergen.py --check` fails on an unknown key, channel, state,
clip or tag, a value out of its range, keys out of order, a loop that
doesn't close, a tier's or
an activity's clip that doesn't loop, a key of `tiers` that isn't a tier or
of `acts` that isn't a state, and a cue that isn't
a name before `ms`, each with its file and key (`rig/clips/hop.json:
tracks.lift[2]: …`). Staging writes the files as `rig_tables.h` in the
staged `firmware/include/`: `render::rig::kRig`, with a lookup by clip
and look. The app doesn't bundle `rig/`.

**How it plays.** The mixer holds a damped spring on each channel, at rest.
The look's clip loops over the springs, and Moments' clips over that, a few
at once, each easing in and out over 150 ms (a quarter of a shorter clip);
a look's clip may ask for longer as it changes.
With the mixer full, the oldest gives way, but the look's own. A poke or a
stroke kicks a spring. The face reports where the body is each frame
(`rig::Anchors`: the crown, a ring for a brim, the front lower down for the
hands, the eyes), so what's worn or held rides it.

**The layer stack.** A face may draw what comes and goes around the body
through the rig's stack (`render/rig/layers.h`), back to front: the scene
behind the body, what's worn over the eyes or on the body, the hat, the air
and what's beside it. Each shows a content, the face's own number for what
it draws there, at an opacity that eases over the rig's fade (`kFadeMs`,
200 ms); a new content waits
for the old to fade out.

**The gel on the rig.** The gel keeps its own engine for what no channel
reaches: each mood's face is its own art, and its scenes, bits (`gags` in
its design's JSON) and springs move its body (the slime's `CONTINUITY.md`).
It lays the channels over the engine's pose (`applyRig`), so at rest a frame
is the engine's alone. `lift` and `x` are canvas px, 85 a body unit. Its
expressions aren't the rig's. Its pastimes (`render/gel/pastimes.h`,
`pastimes` in its design's `expressions.json`) are one table, a row each,
whose body is a clip of the rig, a bit or a take: each for one look, at work
and idle from a tier, asleep from a wait, or whenever a tag is on, and
none while something needs you. Each is the body's own move, with nothing
brought out beside it. `dbg.pastime`
plays one by its name, for scenarios and tools, and `dbg.clip` any clip of
the pack's by its id, over what shows (the gel's flop, which no Moment
names yet). Under every clip the gel runs its motion layer (motion V2:
stretch with speed, overshoot and settle, the crown's drag, the face's lag
and the hands following; the slime's `CONTINUITY.md`, The motion layer),
so a clip keys only its main pose, and its own "prepare", a small opposite
move before a big one; `{"t":"dbg.motion","rule":"face","on":false}` turns
a rule off (or `"all"`) until the next reset, to judge each on the board.

## 16. References (optional)

A person gives a short reference, a sketch, a still, a GIF or a video, with
a line: inspiration, or "make this". An agent reads it and turns it into the
pack's data. Each reference
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
| `became` | What it became on the rig (§15): each a `clip`, by its file's name in `id` |
| `show` | Optional: what it shows on the board, a `mood` and a `state`, and then `anim`, a state asked for at the reference's 0 ms |
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
   frames aren't: in another checkout, run it again to cut them. The agent looks at the sheets and writes
   `reading.md`: the beats and their timing, the poses, squash and stretch,
   the eyes' and mouth's shapes, the colours and the silhouette. A reference
   that needs more than the character has (arms, ears, a new body) says so,
   for the owner, and is never faked.
3. **Translate.** The agent makes it into the rig's data (§15), sets
   `became` and `show`, and moves the status to `in review`, for the owner
   to approve.

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

Each problem comes with its file and key (`reference.json: show.mood: …`).
None of it stops a pack staging. The app doesn't bundle the folder.

## Not yet

- The gel's expressions, recipes, bits and springs are still its own,
  not the rig's (§15).
- A face is C++ code. A picture-based face, with frames per state and mood
  drawn by an engine renderer, would let a character be drawn with no code.
