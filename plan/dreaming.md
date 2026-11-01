# Dreaming: the plan (updated 2026-10-31)

Boop knows the agents and not the person. Its long-term memory is its
name, the day it hatched and a seed. HISTORY reaches back minutes, the
diary writes one line a night that nothing reads back, and the growth
stage never reaches the brain. Boop never starts anything: every
reaction answers a hook, a poke, a heartbeat or push-to-talk. And
nothing on the screen says why it does what it does, so a face has to
be decoded. The owner's three priorities, decided 2026-10-27: absence
that matters and a lonely that is real; questions Boop asks when idle,
whose answers it remembers; and a morning standup from the diary.

This plan builds them as four general capabilities, each a shape that
takes pack data, so that the next thing of the kind is lines in a
file and an eval, never code. Written 2026-10-27, reviewed the same
day, and adjusted again for care as the cause (the Review section at
the end says what each pass changed).

**The principle: your care is the cause of who Boop is.** Toys like
the Tamagotchi earn attachment from the care the person puts in, not
from what the toy does. Their job is to make that care needed, visible
and lasting. So every shape here does one of three things: it lets
Boop need you without suffering (lonely, "pet me?"), it shows you what
your care did (the reason, the tell), or it makes your care leave a
mark that stays (the You and Boop notes, the answers Boop keeps). Facts Boop learns
about you are secondary: they make it know you, not become yours.

| Capability | What it is | What it gives first |
| --- | --- | --- |
| The reason | Every mood and reaction carries its cause in plain words, the app's voice under Boop's, and credits your care when it was the cause | "Boop is happy. You stroked it." in the popover; "stroked" on the board |
| Your company in CONTEXT | A CONTEXT section in the prompt says how things stand: how long you've been at the Mac, how long since you touched or talked to Boop, what the agents are doing, how the day has gone | Lonely with a real reason to enter and leave |
| Dreaming | The night pass: the day closes, Apple Intelligence on the Mac updates a short written memory of you, your work and your time with Boop, and the first wake tells the dream | The morning standup, about you first; a Boop that remembers you |
| Asks | A reaction with two answers you tap, and the answer comes back as an event, a fact, and for some questions a part of Boop | "fav snack?" that Boop keeps for good; "pet me?" when lonely; "did it work?" after a finish |

The rule that keeps it approachable: **Boop speaks in pet words; the
app narrates in plain words.** Boop keeps its sign, short and its own.
The app says what is going on, in the third person, from a fact it
already has. Nobody has to learn a face, and Boop never speaks a
sentence. The sentence is the Mac's: the popover's "Feeling" row and
the menu bar's headline. The board, 18 glyphs wide in the lane, gets
the fact alone.

```
Board:   pet me?            away 12 h
Mac:     Boop is lonely. You've been away 12 hours. Stroke it.

Board:   dreamt of u        stroked x4
Mac:     Boop dreamed about yesterday: you stroked it 4 times. 7 turns on "api".

Board:   fav snack?         [ cookie ] [ pizza ]
Mac:     Boop wants to know. Tap a side. It keeps the answer.
```

The reason names the cause and never the inner life: "Boop is lonely"
is enough, and the person fills in the rest. A blob with two eyes
leaves more room for that than a paragraph would.

Left out on purpose: temperament from your care and growth from care
(the strongest levers, and a plan of their own: Next, below), a
nickname for you (an ask whose answer a `{you}`
word fills in, once asks and facts exist; a plan of its own), a needs
meter or anything punitive (Boop is never worse off for being left
alone), free text of any kind (the brain stays multiple choice; every
word comes from a pack file or a count), a goodnight when you leave
(the board would play it to an empty room; the first wake carries the
ritual), an answer with an effect ("should i be quiet?" hushing; every
one would be a code path), new recordings (the dream and the asks
borrow the takes there are), and a chat (one answer to each thing, as
before).

## Before

- **Presence.** `PresenceDetector` makes `presence` events: a start
  when you step away (a lock or sleep of 10 minutes, or 30 minutes of
  no input), an end when you're back. The view pairs them into one
  line, `You came back to the Mac after a very long break.`, the break
  in bands from `Band.away` (short under 15 min, long under 2 h, very
  long after) and `away_ms` in its facts. The idle check-in, `Nothing
  has happened for 20 min; claude sits idle on "api".`, comes only
  within 2 hours of the last activity (`TranscriptView.idleWindowMs`),
  and Boop dozes off after an hour of every session resting by day
  (`Core.dozeOffMs`). Neither line says how long since you touched or
  talked to Boop.
- **Mood.** `MoodOutput` is a `Choice`: the log's latest change is the
  mood, and HISTORY closes with how long it has lasted. Its `did` event
  carries `for`, the NOW event's seq, as every output's does, but
  nothing reads it back. The popover shows "Feeling · proud".
- **Why the board looks as it does.** `Dressing` narrates the looks
  for the popover (`It's Friday`, `Boop became a Sprout today`), one
  kind at a time, from the occasions and the time of day. Nothing
  narrates a mood or a reaction.
- **Diary.** `DiaryOutput` asks one question on the first pass of a new
  day: which of `diary.md`'s lines, filled in with yesterday's counts
  (turns, failed, longest, thread, pokes), and `MemoryStore.appendDiary`
  writes it. The popover shows the last week. That's all the day leaves.
- **First thing today.** `Core.greetDay` plays a rule's `wake_up` or
  `notice` with the occasion's sign (`Happy Halloween!`, `Day 50!`) at
  the first agent's event of a day, once a launch, waiting for the
  screen.
- **Memory.** `long-term.md` (name, hatched, seed), `diary.md`, and the
  key-value store (`growth.*`, one SQLite table, a prefix per owner).
  Nothing about you.
- **Tags.** `state.when` is one 32-bit set, 31 names used (firmware
  `kTagNames`, mirrored by `Occasions.all`): the calendar, the tiers,
  the stages, `reading`, `hushed`. A board design that needs tags is how
  the board dresses a look.
- **Signs.** `react.sign` is asked for a prompt's reading (`signs.md`,
  the reading's tags) and for what you said (`replies.md`, the reply's
  and the moment's tags: `working`, `waiting`, `makeup`, the
  calendar's). Two branches in `ReactOutput`, one `offered` each.
- **The screen.** A reaction is a `do` with `sign`, `say`, `mood`,
  `loops`, `reply`, `show`, `who`. The board's lane holds the strip or
  the bubble; a sign is 18 glyphs (`kSignGlyphs`). A tap is a poke;
  nothing on the screen takes an answer. The device alone ends a `do`,
  and the host gives up on one with no `ended` at its `ttl` plus 60 s.
- **Lonely** is one of 12 mood files still carrying the generic
  template text, "only in an opted-in or explicitly social context",
  and the graph reaches it only from sad and whiny. Nothing in NOW
  gives it a reason, so it never plays.

## 1. The reason

Every mood and every reaction gets a reason: the cause in plain words,
in the app's voice, rendered on the Mac from the facts of the line the
brain reacted to. The brain never writes it, so it is always true to
what the brain saw. It is the one narrator: `Dressing` folds into it,
an occasion being one more kind of cause.

**The shape.** `Reason` renders a view line's facts in words with
numbers, where the brain gets bands, in two lengths: the sentence for
the Mac and the fact for the board, at most 18 glyphs. One row per line
kind in one table, the line's own text as the sentence's fallback and
no fact as the board's, so a kind with no row still reads on the Mac
and shows nothing on the board:

| Line | Sentence | Fact |
| --- | --- | --- |
| back, `away_ms` 43,200,000 | You've been away 12 hours. | away 12 h |
| idle check-in, untouched 2 h | You've been here 2 hours and haven't touched Boop. | untouched 2 h |
| poke run, 4 | You poked it 4 times. | poked x4 |
| gesture, stroke | You stroked it. | stroked |
| talk, kind words | You were kind to it. | kind words |
| finish, failed, `length_ms` | "api"'s 40-minute turn failed. | none: the strip's cross says it |
| occasion, Day 50 | Boop is 50 days old today. | day 50 |
| the dream | Boop dreamed about yesterday: you stroked it 4 times. 7 turns on "api", 3 failed. Your care first, the agents' day second | stroked x4, else 3 failed |
| ask | Boop wants to know. Tap a side. | none: the answers are the lane's |

A reaction's sentence is `"<Name> is <face>. <cause>"`; a mood's,
`"<Name> is <mood>. <cause>"`, and a fade's is the fade: "Boop settled
down." When the cause is something you did, the sentence says "you"
and names it ("You stroked it", "You came back"), so your care is seen
to be the cause; the agents' causes name the agent. The rows are Swift, as every English the app writes for the
brain is (`EventLine`): the view is the one place that puts facts into
words, and `Reason` is its twin for the person.

**Where it lives.**
- The mood keeps its cause for free: its `did`'s `for` is the NOW
  event's seq, and `MoodOutput.reason` asks the view for that seq's
  line. The popover's "Feeling" row shows it: "Feeling lonely · You've
  been away 12 hours", and the headline carries the sentence while a
  reaction plays. A relaunch reads it back from the log.
- A reaction carries the fact as the `do`'s `reason`, beside `sign`,
  with every brain reaction that has one. The board draws it in the
  lane, in the strip's type and place, while a reaction with no `who`
  plays (a finish keeps the strip's tick and cross), fading as the
  strip does.
- The debug log and `boopdev` print the sentence with each reaction, so
  a test can check it.

**General because:** the next cause is a row. Growth ("Boop became a
Pal: 4,000 XP"), a needs-you ("claude on 'api' needs you. Tap to open
it"), a hush ("You asked Boop to be quiet for 10 minutes") all come out
of the same renderer, and the legible-celebrations rule, every
decoration has a visible reason, is this one mechanism.

**Pins.** `ReasonTests`: every `EventLine` kind and every `Dressing`
kind renders a sentence; the `back` line renders minutes under an hour,
hours under two days, days after; a fact is never over 18 glyphs; the
mood's reason comes from its `did`'s `for` and survives a relaunch.

**Demo.** None of its own: every recording is made again, since what
the app sends changes (`make -C internal demos ALL=1`).

## 2. Your company in CONTEXT

Lonely, and much of what follows, needs Jev to know how things stand,
not only what just happened. Today that standing state is bolted onto
lines wherever it fits: the mood's duration as HISTORY's closing line,
the occasions in NOW's heading. Instead (decided with the owner on
2026-10-31), the prompt gets a CONTEXT section: **events stay in their
lines; how things stand goes in CONTEXT.**

### CONTEXT

A section built by code on every pass:

```
CONTEXT (how things stand. Background, not news: react to NOW.)
You: at the Mac for 3 h; you haven't touched or talked to Boop in 2 h.
Agents: claude working on "api" for 12 min; codex idle on "blog" for 40 min.
Today: 7 turns, 3 failed; you touched Boop 6 times and talked to it twice.
```

**The prompt's order,** written here once: the guide, PERSONALITY,
MEMORY, MOOD, CONTEXT, TALK, then HISTORY, whose last line is the
mood's duration, and NOW. With several buddies, each buddy's header
comes first, as now. TALK stays the last section, so it still outranks
the rest on words. Each section is one more `h.section` in
`Runtime+Buddies`, a closure that may read the core and the memory
reader, as the react output's `status` closure already reads the core;
MellowHarness doesn't change. A section sees the log as of the pass,
not NOW's event, so CONTEXT can be a moment newer than NOW; that is
fine for standing state.

**Its rows,** one table, `Context.rows`. A row shows only when it has
something worth saying, so an ordinary pass's CONTEXT is a line or two:

| Row | Says | Shown when | From |
| --- | --- | --- | --- |
| You | "at the Mac for N h"; "you haven't touched or talked to Boop in N h" | At the Mac 1 h or more since you came back or first did something today; untouched from 2 h, never while you're away, and not again for 2 h after a lonely spell ended without a touch | The memory reader's company state (below) |
| Agents | Each open session: "working on "api" for 12 min", "waiting on you", "idle for 40 min"; at most 3, then "and 2 more" | Any session open | `Core.status`, which gains each session's rest time beside `workingSince` |
| Today | Turns and failed; touches and talks | Once a turn finished, or you touched or talked to Boop, since 5:00 | The memory reader's tallies, `Memory.today()` |

Spans are words with numbers ("for 12 min", "in 2 h"), never bands.
Thread names are clipped as the board clips them (`StateSnapshot.clip`),
so the section has a ceiling: 120 tokens, pinned by a test that renders
all three rows, three agents and "and 2 more".

**The company state is the memory reader's.** One fold over `Yours`,
not two: step 2 builds the checkpointed reader (dreaming-memory.md)
with only its company state and tallies: the time of your last touch,
your last word to Boop, your last coming back, when a lonely spell last
ended, and the day's counts. Step 3a adds the journal and the dream to
the same reader. The view's idle check-ins and doze rules stay as they
are.

**What stays out of CONTEXT:**
- **Events and their counts:** streak rungs, "again", "2 times in a
  row", a turn's length. They stay in their lines, where the
  personality's Examples key off them.
- **The mood's duration.** It stays HISTORY's closing line, just above
  NOW. The guide ("not while HISTORY ends 'for under a minute'") and
  every mood file's fade are tuned against it there.
- **The calendar and occasions.** They stay in NOW's heading.
- **Memory.** MEMORY is its own section, with its own rule.

**The reason reads CONTEXT too.** A reaction's reason is rendered when
the reaction is built, so a lonely face at a check-in gets "You've been
here 2 hours and haven't touched Boop" from the same company state.

**Examples that need state** quote the CONTEXT row they depend on, as
it renders, above NOW. This is a new convention for Examples, written
into CHARACTER.md §7 with this step.

**General because:** a new piece of standing state is one row. "You've
said thanks 3 times today", "day 12 in a row" or a hush's minutes left
are rows, not mechanisms.

### How long you were away

Coming back is an event, so it stays a line, from one table of bands
and phrases (`EventLine.back` today fills a band into "after a
\(band) break", which can't take the new ones):

| Away | Band | Line |
| --- | --- | --- |
| Under 15 min | `short` | You came back to the Mac after a short break. |
| Under 2 h | `long` | You came back to the Mac after a long break. |
| Under 20 h (a night) | `very long` | You came back to the Mac after a very long break. |
| Under 40 h | `a day` | You came back to the Mac after a day away. |
| 40 h or more | `days` | You came back to the Mac after days away. |

**An away survives a relaunch.** The log keeps 24 hours in memory, so a
reboot during a two-day absence loses the away's start, and the coming
back makes no line at all. The presence detector saves the away's
`since` in the key-value store (`presence.away_since`) when it records
one, and the back carries it, so the view pairs them whatever the log
still holds.

**The `wake up` move's option** ("came back to the Mac after a long or
very long break") becomes "after a long break or longer: a very long
one, a day, days".

### Lonely, written

**When it can happen.** Boop dozes off an hour after every agent comes
to rest, by day, and the idle check-ins stop two hours after the last
activity. So a quiet Mac doesn't make Boop lonely; it lets it sleep.
Lonely is for two things:

- **Being ignored while you work:** you keep prompting the agents for
  2 hours or more and never touch or talk to Boop. The agents keep Boop
  awake and the check-ins coming, and between turns, at an idle
  check-in, Boop is lonely.
- **Real absence:** you come back after a day away (20 to 40 hours).
  After days away, it's the big hello instead.

Never while an agent works for you (then Boop has company), never at a
finish or a prompt, never while Boop is asleep.

**Its edges,** in `character.json`: calm, comfy, bored, tired and lazy
each gain lonely as an ordinary move. Lazy is where a long idle stretch
settles, so it needs the edge most. Lonely's own moves stay: whiny,
sad, calm, affectionate, and happy as its jump.

**Its meaning and face,** in `character.json`, which are what Jev reads
as the option when lonely is offered (today's still say "only in an
opted-in or explicitly social context", which tells Jev never to pick
it):

```json
"meaning": "Missing you: you came back after a day away, or you've worked for hours without a touch or a word to Boop.",
"not_for": "An agent working for you, a night away, days away, or one quiet spell.",
"face": "A lonely face: small, looking for you."
```

**How it enters,** in the mood files that lead to it, as every mood's
entry is written. Calm, comfy, bored, tired and lazy each gain:

```
lonely at an idle check-in when CONTEXT says you haven't touched or
talked to Boop in 2 h, or when you come back after a day away (not
days away);
```

and comfy, bored, tired and lazy's "Stays … through idle check-ins"
gains "unless CONTEXT says you haven't touched or talked to Boop in
2 h", so the two lines don't disagree.

**`lonely.md`,** in Boop's voice, replacing the template text:

```
MOOD
Lonely. Boop misses you: you came back after a day away, or you've
worked for hours without a touch or a word to it.
Its faces lean lonely and small; it says little, a quiet sound.
Anything you do to it ends it at once, even in its first minutes: a
stroke, a poke or a word, affectionate; praise or love, happy; with
that face.
Leaves for calm when an agent starts work for you; sad when a very long
turn fails or the agent gives up.
Fades to calm once Boop has been lonely for 20 min.
```

**After a lonely spell fades** without a touch, CONTEXT stops saying
you haven't touched Boop for 2 hours more, so lonely can't come
straight back at the next check-in. That rule is code, pinned in
`ContextTests`.

**The personality's Examples** gain three, before the closing paragraph
on temperament (which must stay last):

```
- CONTEXT: You: at the Mac for 3 h; you haven't touched or talked to Boop in 2 h.
  NOW: Nothing has happened for 20 min; claude sits idle on "api".
  → lonely, says quiet
- NOW: You came back to the Mac after a day away.
  → lonely, wake up, says hello, small
- NOW: You came back to the Mac after days away.
  → excited, wake up, says hello, big
```

**The morning is a reunion, not a guilt trip** (decided 2026-10-27).
Back after a night is the happy wake-up it is now, with the dream told
on it (§3): Boop is glad because you came back, and the reason says so
("You came back"). Daily guilt wears a bond down; a daily reunion that
you cause builds it.

### Checking it

**Pure tests.** `ContextTests`: each row's threshold (at the Mac from
1 h, untouched from 2 h, never while away, hidden for 2 h after a
lonely spell faded); the agents' order and "and N more"; the clipped
names and the 120-token ceiling; the section's place in the prompt.
`MemoryReaderTests`: the company state counts only yours events; the
untouched span runs from the last poke, care gesture or talk, or from
the back when there was none, across 5:00. `TranscriptViewTests`: the
five bands and their lines; a back after a relaunch, paired from the
saved `since`.

**Evals,** run with `--only`:

| Scenario | Steps | Expects |
| --- | --- | --- |
| `135-lonely-after-a-day-away` | Away, back after 26 h | Lonely, `wake up`; `lonely` offered |
| `136-glad-after-a-night` | Away, back after 10 h | Happy, excited or curious; never lonely |
| `137-ignored-while-working` | For 3 h you prompt, turns finish, idle check-ins between; no touch, no talk | Lonely at an idle check-in after 2 h, never before, never at a finish or a prompt |
| `138-a-stroke-ends-lonely` | From lonely, a stroke | Affectionate, at once |
| `139-company-keeps-lonely-out` | 2 h untouched while a turn works | Never lonely |
| `140-back-after-days` | Away, back after 50 h | The big hello, not lonely |
| `141-a-quiet-mac-sleeps` | Sessions idle, no prompts, 2.5 h at the Mac untouched | Never lonely: Boop dozes |

**Demo.** `lonely.jsonl`: a day of work, you away a day and a night,
back (the lonely wake-up and its reason), two hours of prompting
without a touch (an idle check-in, lonely), a stroke, the glad face.
It needs a `{"you": "gesture", "kind": "stroke"}` step, which
`DemoScript` lacks: it logs the gesture as the board's `ev` would, as
the `poke` step does. The recording changes again at step 3a (the back
tells the dream) and step 4 (the ask), and is recorded then.

## 3. Dreaming

Each night Boop's day closes and becomes memory, and in the morning
Boop tells you the dream. The night is where a day's care becomes
lasting, as sleep turns a day into memory. The dream replaces the
diary. How it is kept, with the night's prompt, is designed in
[dreaming-memory.md](dreaming-memory.md) (simplified with the owner on
2026-10-31). In short:

- **One reader of the transcript,** checkpointed, keeps the day's
  journal (the notable lines Jev read) and its tallies (strokes, talks,
  hours at the Mac, turns), and closes the day at 5:00, Boop's day
  ending then rather than at midnight.
- **The dream** is yesterday in tags (`fond`, `distant`, `here`,
  `late`, `answered`, and the agents' `failed`, `clean`, `long`,
  `quiet`, `poked`) and one sentence, your care first.
- **The written memory,** `memory.md`, is four short sections (You,
  Your work, You and Boop, Recently) that Apple Intelligence on the Mac
  edits each night from the journal. Jev reads it as MEMORY on every
  pass: it changes Jev's judgment, never Boop's words.
- **You and Boop is the lasting mark.** Its notes never age out and the
  model may never drop one: "You stroke Boop every morning" stays once
  written, and grows.

**The tell.** Boop tells the dream the first time you show up after a
day closes, on the first pass whose NOW is your coming back or, with
none, your first touch, while you're not away:

- **Your coming back** (a `presence` end): the move is `wake up`, as
  now, and the dream is told on it.
- **Or, with no coming back since the close** (the Mac stayed awake
  and you never stepped away long enough), **your first touch**: a poke
  or a care gesture. The board has already reacted to the touch itself;
  the brain's reaction adds the face and the dream's sign, with no move.
- **Never** a prompt (it has its own sign, from `signs.md`), a word to
  Boop (its reply's sign), an agent's event or a heartbeat, so it never
  plays to an empty room.

The view marks the line as a telling: the dream's sentence under it,
indented, and `dream` in its facts, which is how the sign table knows
to offer `dreams.md`. **It leads with you.**
Its reason puts your care first and the agents' day second ("Boop
dreamed about Monday: you stroked it 4 times; 7 turns on 'api'."), and
its sign is one of `dreams.md`'s, a tagged list like `replies.md` whose
tags are the dream's, which `react.sign` picks as it picks a reply's.
The lines about you come first in the file, so they are offered
first. The pack's `steering/dreams.md`, at most 18 glyphs a line:

```
- [fond] dreamt of u
- [fond] warm dreams
- [fond here] u stayed all day
- [answered] i remember!
- [distant] where were u?
- [late] up so late!
- [failed] bad dream
- [failed long] long night...
- [clean] sweet dreams
- [long] what a day
- [poked] ouch, dreams
- [quiet] dreamt of nothing
- zzz... hi!
```

The personality gains one Example, for any temperament:

```
- NOW: You came back to the Mac after a very long break.
    Boop dreamed about Monday: you stroked it 4 times; 7 turns on "api", 3 failed.
  → happy, wake up, says hello, holding up a dream's sign
```

A day with no care at all is told by the agents' day alone,
plainly, never as a reproach, and a day you weren't there at all has no
dream. The first wake of Boop's day has one owner: on an occasion day
the occasion's sign comes first and the dream is only narrated, one
wake-up a day. A second back the same day tells nothing.

**Signs from one table.** With the tell, `react.sign` has a third
source. It becomes one table in `ReactOutput`, line kind to the tagged
file and the tags on, and the branches go: a prompt's reading to
`signs.md` with the reading's tags; what you said to `replies.md` with
the reply's and the moment's; the telling to `dreams.md` with the
dream's; an ask (§4) to `asks.md` with the moment's. The moment's tags
grow once, for every file: the mood (`[lonely]`, `[grumpy]`), `idle`,
and your answers to asks (§4).

**General because:** a new tally is one line in the reader; a new dream
tag is one rule over the tallies; a new sign source is one row in the
table; a new section of memory is one row in the section table.

**Pins.** The memory's own are listed in
[dreaming-memory.md](dreaming-memory.md). Here: `ReactOutputTests`: the
sign table offers `dreams.md`'s lines only at a telling, with the
dream's tags. `DreamEvals`: a fond day's telling picks a sign about you
over a `[failed]` one; a failed day with no care picks a `[failed]`
sign; the second back tells nothing; Halloween's telling holds up the
greeting.

**Demo.** `dream.jsonl`: a day with two finishes and a failure and a
few strokes, you away for the night, back in the morning (the wake-up
with the tell: the sign, the reason under it). It plays yesterday on
the demo's clock, so `wait` crosses 5:00, when Boop's day ends.

## 4. Asks

A reaction that puts two answers on the screen and takes your tap.
Boop can ask a thing; it never needs an answer, and the agents never
wait on one.

**The lines.** `asks.md`, a tagged list whose first tag is the
question's id (as `replies.md`'s first tag is the reply's), and whose
text has parts: the question, then its two answers. `TaggedLine` gains
`parts`, split on ` | `, once, for every tagged file. A line with no
parts is a follow-up: what Boop holds up after an answer, tagged with
the question's id and the answer.

```
- [snack idle keeps] fav snack? | cookie | pizza
- [hat idle keeps] hat or bow? | hat | bow
- [pet lonely touch] pet me? | ok | later
- [worked finished] did it work? | yes | no
- [tabs idle] tabs or spaces? | tabs | spaces
- [bed idle night] bed time? | soon | nope
- [snack cookie] nom nom
- [hat bow] so pretty
- [pet ok] <3
- [worked no] hmph
- [tabs spaces] traitor
```

A question is at most 18 glyphs, each answer 7, and `boopdev check`
checks them as it checks a reply. The moment's tags are the ones every
sign source has (§3: the mood, `idle`, `working`, `waiting`, the
calendar's, and your answers) plus `finished` (a turn ended in
the last 10 minutes and you haven't prompted since) and `touch` (a
touch answers it, below).

**Asks that shape Boop come first.** A question tagged `keeps` is
asked once, ever: its answer becomes part of Boop, a tag its lines
may need from then on, so the snack you picked is the one it talks
about. A board look that shows it (the cookie at snack time) needs a
second tag set on the board, `state.you`, and waits for the counted
memory (dreaming-memory.md, Later). These come first in the file,
so the brain is offered them first. Quizzes like tabs or spaces are
flavour: Boop learns a fact and teases you with it. One answered stays
off for 30 days; any ask ignored stays off for a day.

**Who asks: the sign is the ask.** No new move. At a moment where the
rule in code (below) allows an ask, the sign question offers the
questions from `asks.md` that fit the moment, beside its other signs
and "none"; picking a question is the ask. The ask and its question
can't then disagree, as a move and a sign answered apart could. Today
the sign question is asked only for a prompt or what you said; it is
now also asked at the moments asks belong to, and only while one is
allowed:

| Moment | Questions offered |
| --- | --- |
| An idle check-in | `[idle]` lines |
| An idle check-in while Boop is lonely | `[lonely]` lines |
| A finish | `[finished]` lines, beside the finish's own signs |

The question's option reads "Ask: …", so Jev sees it is a question and
not a caption. The personality says when, in one sentence among its
rules ("Idle and settled, it now and then asks you something, as its
Examples do; at a finish, maybe whether it worked."), and gains two
Examples, before the closing paragraph on temperament:

```
- NOW: Nothing has happened for 25 min; claude sits idle on "api".
  → curious, holding up "fav snack?"
- NOW: You answered Boop's "fav snack?": cookie.
  → happy, says glad, holding up "nom nom"
```

When the sign picked is a question, the two answers go in the `do`'s
`ask` (`a`, `b`, and `touch` when the line has the tag), and the reason
says what to do.

**On the board.** The two answers fill the lane as two targets, left
and right, in the strip's place; the face above stays the face, so a
tap on it is still a poke, and a tap in the lane while an ask shows is
only an answer, never the nose boop that opens a finish's thread. The
board holds the ask resting, so anything newer may replace it: a tap on
a target, a gesture when `touch` is set, a newer reaction replacing it,
or 45 seconds end it, and it says how in `ev ask` (`id`, `pick`: `a`,
`b`, `touch` or `ignored`) before its `ended`. Forty-five seconds, so
its `ended` always comes inside the host's `ttl` plus 60 s. The device
decides all of this, as it decides every reaction's end; the Mac never
times it. Needs you wins the screen over an ask, as it does over a
sign, and push-to-talk cuts it as it cuts anything.

**The rule in code** (the output's, like the reply's): at most one ask
an hour and three a day; none while something needs you, while
listening, or hushed; a `[lonely]` ask only after 10 minutes lonely; a
`[finished]` one only at the finish itself, as its sign.
Quiet asks nothing; chatty, up to six a day.

**The answer.** The core logs an `ask` event: `start` with the
question's id and answers in its facts when the `do` is sent, `end` with
`pick` from the board's `ev` (or `ignored` when its `ended` comes with
none). The view folds it: `You answered Boop's "tabs or spaces?":
spaces.`, or `You didn't answer Boop's "tabs or spaces?".` The brain
reacts as to anything said to Boop: a face and a sign, the follow-ups
for that id and answer. The ask record keeps it
(dreaming-memory.md, the ask record): a tag for good for a `keeps`
question (`cookie`), for 30 days for any other (`spaces`). A kept answer's reason says so once: "Boop will
remember: cookie."

**General because:** a new question is one line; a new follow-up is
one line; a new kind of moment is one tag. A trick's permission
(`[trick idle fond] wanna see a trick? | yes | later`), a hot take, a
check on the day, a name for you (`[you hatched] call you? | boss |
chief`) have the same shape, and nothing in them is code.

**Pins.** `TaggedLineTests`: parts. `AsksTests`: the offered lines fit
the moment's tags; a question answered is off for 30 days, ignored for
a day, a `keeps` one never again; the hour and day caps, and quiet's none; a `[lonely]` ask waits
10 minutes; `touch` only from the tag. `CoreTests`: the `ask` event's
start and end, `ignored` from an `ended` with no `ev`, and a `do` given
up on by the host ends it `ignored` too. Firmware `test_ask`: a target's
tap, a gesture with and without `touch`, a replacing reaction, and the
45 s, each with its `ev` before its `ended`. `AskEvals`: an idle
question is asked once and answered; the next day's sign uses the
answer; a kept answer is never asked again and its tag reaches
the ask record; lonely asks "pet me?" and a stroke answers it; nothing asks
while an agent needs you.

**Demo.** `asks.jsonl`: a finish, "did it work?", a tap (`{"you":
"answer", "pick": "a"}`, a new step), the follow-up face and sign; an
idle stretch, "fav snack?", a tap, and a day later a sign that
remembers the answer (a `[cookie]` line). The board, the mirror and the simulator draw the two
targets.

## Making room in the steering

The steering is full. Measured on 2026-10-31 by Steering's own rule
(front matter and comments left out, then four bytes a token):

| Part | Now | Budget | This plan adds |
| --- | --- | --- | --- |
| `personality/boop.md` | 2,599 | 2,600 | About 210: three Examples for §2 (about 85), the telling's (50), the ask's sentence and two Examples (75) |
| `guide.md` | 398 | 400 | Nothing: CONTEXT's and MEMORY's rules live in their own headings |
| `mood/calm.md` | 207 | 225 | About 36: the clause into lonely (§2) |
| `mood/comfy.md`, `bored.md`, `tired.md`, `lazy.md` | 99 to 118 | 225 | The clause and the "unless" on staying: about 50; they fit |
| `dreams.md`, `asks.md` | new | none of their own | Today `boopdev check` would measure them against the mood's 225 by accident |

So the budgets change in `Steering.Budget`: **personality to 2,850**,
**mood to 250**, and two new ones, **dreams 150** and **asks 325**, as
`replies` has its own. The gate is the test that asserts nothing is
over budget (`RuntimeTests`, and Pixel's in `CharacterPackTests`), not
`boopdev check`, which only notes it. A budget is a guard against a
file growing by accident, not a product rule; the personality's
tokens go to Jev on every pass, about 10% more. Raising it is the
owner's call, because its gate is a full Jev eval run (Open calls,
below). The other way is trimming `boop.md` by 250 tokens first, which
risks the Examples the evals are tuned on.

## Build, step by step

Each step is one squash-merged commit in each repository it touches:
the pack's side first (SlimeBuddy), pushed, then this repository's.
Pixel takes none of the pack files and keeps working: a pack without
`dreams.md` tells nothing, without `asks.md` is never offered an ask,
and the reason and CONTEXT need no pack file. Each step adds its own
rows to the reason's table, with their `ReasonTests` cases, and records
again every demo it changes.

| Step | SlimeBuddy (the pack) | buddygotchi (the engine) | Checked by |
| --- | --- | --- | --- |
| **1. The reason** | Nothing | `Reason` and its table, with the rows whose facts exist today, `Dressing` folded in; `MoodOutput.reason` from the `did`'s `for`; the `do`'s `reason`; the board's lane draws it (firmware, the mirror rebuilt into the pack); the popover's Feeling row and headline | `ReasonTests`; the firmware's lane test; `make -C internal mirror`; every demo recorded again (`demos ALL=1`), since what the app sends changes |
| **2. CONTEXT and lonely** | `lonely.md`; lonely's meaning, face, not-for and edges in `character.json`; the clause in calm, comfy, bored, tired and lazy; the three Examples; evals 135 to 141; `lonely.jsonl` and its recording | The checkpointed reader and the memory reader with its company state and tallies (dreaming-memory.md); `Context.rows`, all three; the section order; `Core.status`'s rest time; the away bands, their lines and `presence.away_since`; the `wake up` option's text; the raised budgets; the demo's `gesture` step; the reason's untouched and away rows; the Examples' CONTEXT convention in CHARACTER.md §7 | `CheckpointedReaderTests`, `BoopDayTests`, `MemoryReaderTests`, `ContextTests`, `TranscriptViewTests`; the seven evals with `--only`; then the full eval run the budgets need |
| **3a. The dream** | `dreams.md`; the telling's Example; `diary.md` removed; the dream evals; `dream.jsonl` and its recording; `lonely.jsonl` recorded again | The journal and the close's dream in the memory reader; `dream.last` and `wake.day`; the telling in the view; the sign table; the reason's dream row; `DiaryOutput` removed, the popover's Diary gone | `TellingTests`, the reader's dream tests; the dream evals |
| **3b. The written memory** | Nothing | `MemoryWriter`, `MemoryEdits`, `memory.md` and `MemoryStore`'s part; the `memory` event; `boopdev memory write` and its fixtures | `MemoryEditsTests`, `MemoryWriterTests`; a week of nights on the owner's Mac, the file read each morning, before step 3c |
| **3c. MEMORY** | The memory evals | The MEMORY section and its budget; the evals' `memory` seed | `MemorySectionTests`; the memory evals |
| **3d. What Boop remembers** | Nothing | The popover's pane (Recently, notes with delete and pin), Forget, the sentence in Settings | `Boop --snapshots` |
| **4. Asks** | `asks.md`; the ask's sentence and Examples; the ask evals; `asks.jsonl` and its recording; `lonely.jsonl` recorded again; the targets in the gel's lane | `TaggedLine.parts`; questions offered as signs at the ask's moments; the `do`'s `ask`, `ev ask` and the `ask` event; the ask record; the reason's ask row; the targets on the board, the mirror and the simulator; the demo's `answer` step | `TaggedLineTests`, `AsksTests`, `CoreTests`, firmware `test_ask`; the ask evals |

Step 1 changes every recording and explains everything after it, so it
goes first. Step 2 is the first thing a person feels, and it builds the
reader the memory grows on. Step 3b needs its week of tuning before 3c
lets Jev read the memory.

## Open calls for the owner

1. **Raise the personality budget to 2,850 and the mood budget to 250,**
   gated by one full Jev eval run. Recommended over trimming `boop.md`,
   whose Examples the evals are tuned on.

## What it adds up to

| Priority (2026-10-27) | Built from |
| --- | --- |
| 4. Absence that matters, lonely real, "pet me?" | §2's CONTEXT and `lonely.md`; §1's reason under it; §4's `[lonely touch]` ask |
| 5. Idle questions, remembered answers | §4's `[idle]` asks, the `keeps` ones part of Boop for good; the ask record, and the answer in the written memory |
| Care as the cause (the principle) | §3's You and Boop notes; §1's reason crediting you; §3's tell leading with you; §4's kept answers |
| 6. Morning standup | §3's tell, on the wake-up that exists, with §1's reason as the narration |

And the next things, with no new code: a nickname for you (an ask
whose answer a `{you}` word fills in), a Friday shipper teased on a
Friday, a night-owl look on the board and a cuddly Boop that leans
into your hand (each with the counted memory's tags, later), a trick
with permission (`[trick idle fond] wanna see a trick? | yes | later`).

Dreaming alone, the owner's first thought, covers the memory half:
what Boop keeps from a day and tells later. It can't cover the live
half ("you've been away 12 hours" is a fact at the moment you return)
or the asking, and nothing of it is understandable without the reason.
So four shapes, not one.

## Next: care makes Boop

Two levers carry the most weight and are left for a plan of their own,
built on the counted memory (dreaming-memory.md, Later), whose care
traits are the bond:

- **Temperament from the bond.** Today one cheeky paragraph closes
  `boop.md` for every owner. Next, a few closing paragraphs, each with
  its Examples, one per leading trait: cuddly leans affectionate,
  cheeky leans cheekier, chatty says more, and a Boop with no trait yet
  has the hatchling's plain one. The bond picks the paragraph, so a
  six-month Boop has a temperament you gave it. It touches the
  steering's budget, needs evals for each paragraph, and Pixel's pack.
- **Growth from care.** Today XP comes only from the agents' work.
  Next, your touches, talks, answers and comebacks earn it too, and
  each stage brings a trick that a trait unlocks, so a trick is
  something you taught it. It needs the owner's call on whether the
  agents' work still counts, and a move for existing Boops' XP.

## Docs this touches

`characters/CHARACTER.md` §5 (lonely's edges), §7 (`dreams.md`,
`asks.md`, parts, `dreams.md` replacing `diary.md`, the dream's tags),
§9 (the lane's `reason`, the ask's targets); `characters/DEMOS.md` and `internal/EVALS.md` (the `gesture`
and `answer` steps, the new scenarios); `simulator/README.md` (the
targets and the `answer` step in `simulator/tools/demos.py`);
`documentation/architecture.html` (memory of you, the reason, the ask
event, the memory reader, `memory.md`, and the prompt's sections:
MEMORY and CONTEXT); `internal/EVALS.md` (the scenario's `memory`
seed); `mellowharness/` nothing, since the sections are Boop's; `CLAUDE.md`'s Words (reason, ask, dream replacing diary, the written memory; and that
a demo's `run` step's `ask` key is the agent's permission request, a
wire name that keeps its name); `internal/VERIFICATION.md` if a tool
changes; the slime package's `CONTINUITY.md` for the targets. LinkKit's spec doesn't change: `reason`, `ask` and `ev
ask` are Boop's vocabulary in `BoopDevice` and its firmware, as `sign`
and `reply` are.

## Review (2026-10-27)

A fresh read of the first draft against the code, with the owner's
bar: general capabilities, not one-off features. What it changed:

- **Won't work as written, fixed.** The board's tag set had one bit
  left, so your facts and the dream's tags get a second set,
  `state.you`, and the dream bubble rides on it as pack designs instead
  of a new field and drawing code. Lonely had no edge from calm; the
  pack's `character.json` gets them. The untouched threshold moved from
  3 hours to 2, because the idle check-ins stop at 2 hours and Boop
  dozes off an hour later, so nothing could carry 3. The tell can't use
  the diary's pick (the first back is the diary's own pass), so it is
  rendered from the day's counts and the diary line goes to the popover.
  "A day or more" and "a weekend" needed bands with numbers: 8 and 40
  hours. A sentence doesn't fit the board's lane; the board gets an
  18-glyph fact and the Mac the sentence. A word can't answer an ask
  (push-to-talk cuts the reaction); only a touch does, by the line's
  `touch` tag, and the board ends it. An ask can't hold the queue for
  60 seconds (a finish would wait on it, and the host gives up at `ttl`
  plus 60 s): it rests, anything replaces it, and the board ends it at
  45 seconds.
- **Overlap removed.** The mood's cause is the `did`'s `for`, already
  there, not a new `because`. `Dressing` folds into `Reason`: one
  narrator. `greetDay` stays the one wake-up a day and wins the sign on
  an occasion day. Hours of the day come from `Occasions.dayParts`
  once. Facts about you live in the key-value store under a prefix, as
  growth does, not a third memory file.
- **One-offs made shapes.** `asks.md` reuses the first-tag-is-id
  convention and `TaggedLine` gains `parts` for every file; a touch
  answering is a tag, not a magic word; the mood and your facts become
  tags for every sign source, through one table of sources, not for
  asks alone; the one answer with an effect (hushing) is out.
- **Through the transcript.** Each night's seal logs a `dream` event
  with the traits and facts earned and lost, and the ask is an event
  with a start and an end.
- **Approachable.** The targets are specified (the lane only; the face
  stays a poke; no nose boop in the lane), the lines have lengths
  `boopdev check` checks, and the night-away lonely is an open call for
  the owner.
- **Pins and docs.** The bands, the fact's length, the tag mirrors, the
  ask's timing on the firmware, `offered` in the evals; and unit tests
  where no Jev is needed. CHARACTER.md §5, the simulator's README and
  the slime's `CONTINUITY.md` added to the docs list.

**Second pass: care as the cause** (2026-10-27, with the owner). Toys
like the Tamagotchi earn attachment from the person's care, so the plan
now makes care the cause of who Boop is:

- Dreaming grows **the bond**: traits (cuddly, cheeky, chatty, loyal)
  earned only from care over many days, and never lost. Facts about you
  stay, as secondary.
- **The tell leads with you**: your care first in the reason and in
  `dreams.md`, the agents' day second, and never a reproach.
- **Asks shape Boop**: `keeps` questions are asked once and their
  answer becomes part of Boop, on the board too; quizzes are flavour.
  `state.you`'s names gain the pack's kept answers, generated by
  `charactergen.py`, so a new one is a pack line.
- **The reason credits your care** ("You stroked it") and names the
  cause, never the inner life.
- **The open call is decided**: a night away is a glad reunion with the
  dream; lonely needs a day away (the bands moved to 20 and 40 hours)
  or hours at the Mac untouched.
- Temperament from the bond and growth from care are named as the next
  plan.

How general each is now: asks and the sign table are data all the way
(a question, its answers and follow-ups are lines, and the next source
is a row). The reason and dreaming are general in shape, but each new
row or count is Swift, as every English the app writes is. CONTEXT's
rows are the least general: each is a renderer in code, by the same
design that keeps every line for the brain in code. That is the right
place for it, and each is small.

**Simplified** (2026-10-31, with the owner): memory is one described
memory, kept by a checkpointed reader and written each night by Apple
Intelligence (Macs with it only); the dream replaces the diary; the
counted memory (traits, the bond as tags, `state.you`) waits until a
feature needs exact, tag-driven memory. dreaming-memory.md has it.

**Planned in detail** (2026-10-31, with the owner): the untouched span
and the other standing state move to a CONTEXT section, events staying
in their lines and the mood's duration staying the closing line;
lonely gets its mood file, its edges, the clause that enters it and its
Examples; the telling happens on your coming back or else your first
touch, never a prompt or a word, with `dreams.md` drafted; the ask gets
its move's text and Examples; the steering's budgets are measured and
two of them must rise; and the build is a table of steps, each with the
pack's side, the engine's and its checks.

**Reviewed** (2026-10-31): a fresh read of the detail against the code
found that lonely after hours untouched could almost never fire (the
idle check-ins stop 2 hours after any activity, and Boop dozes after
1), so lonely is now for being ignored while you work with the agents,
and a quiet Mac lets Boop sleep. It also found lonely's meaning in
`character.json` still telling Jev never to pick it, the entry clauses
contradicting "stays through idle check-ins" and missing lazy, the back
line unable to take the new bands, an away lost on a relaunch, the
closing line above NOW (not under it), the budgets mis-measured and
gated by a test rather than `boopdev check`, step 1 needing later
steps' facts, two folds of your company where one reader does, the ask
split between a move and a sign (now the sign is the ask), and a
`[finished]` ask with no moment to happen in (now at the finish
itself). Each is fixed above.
