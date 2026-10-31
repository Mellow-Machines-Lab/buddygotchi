# Dreaming: the plan (2026-10-27)

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
mark that stays (the bond, the answers Boop keeps). Facts Boop learns
about you are secondary: they make it know you, not become yours.

| Capability | What it is | What it gives first |
| --- | --- | --- |
| The reason | Every mood and reaction carries its cause in plain words, the app's voice under Boop's, and credits your care when it was the cause | "Boop is happy. You stroked it." in the popover; "stroked" on the board |
| Your company in NOW | The lines the brain reads say how long you've been away, and how long since you touched or talked to Boop | Lonely with a real reason to enter and leave |
| Dreaming | The night pass: it counts the day, grows the bond from your care, keeps what it learned about you, and the first wake tells the dream | The morning standup, about you first; a Boop that becomes cuddly or cheeky because of you |
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

Left out on purpose: temperament from the bond and growth from care
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
| bond trait earned | Boop got cuddly. You've stroked it most days for 2 weeks. | cuddly now |
| finish, failed, `length_ms` | "api"'s 40-minute turn failed. | none: the strip's cross says it |
| occasion, Day 50 | Boop is 50 days old today. | day 50 |
| the dream, yesterday's `Day` | Boop dreamed about yesterday: you stroked it 4 times. 7 turns on "api", 3 failed. Your care first, the agents' day second | stroked x4, else 3 failed |
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

## 2. Your company in NOW

The view keeps one fold of your company, `Company`: the seq and time
of the last of each thing you did (a poke, a gesture, a talk, a prompt,
a back), and one phrase renderer puts a span of it into a line when it
matters. Two spans first:

- **How long you've been away.** `Band.away` grows two bands: `a day`
  from 20 hours (more than a night) and `days` from 40 hours (a weekend
  or more). A night away stays `very long`. The line keeps its shape: `You came back
  to the Mac after a day away.`, with `away_ms` in its facts for the
  reason.
- **How long since you touched or talked to Boop.** The working
  check-ins and the idle check-ins say it once it passes 2 hours, while
  you're here: `Nothing has happened for 20 min; claude sits idle on
  "api". You haven't touched or talked to Boop in 2 h.` Two hours,
  because the idle check-ins stop 2 hours after the last activity and
  Boop dozes off an hour after: a sleeping Boop isn't lonely, and the
  hourly heartbeat stays held as it is. Nothing new is logged: the fold
  already sees those events.

**Lonely, written.** `lonely.md` gets Boop's voice, and `character.json`
gets its edges: calm, comfy, bored and tired move to lonely. It enters
when a check-in says you've been here 2 hours without a touch or a
word, or you're back after a day away, and never while an agent works
for you (then Boop has company). A stroke, a word, a poke or praise
ends it at once, as grumpy ends at sorry: affectionate, or happy. It
fades to calm after 20 minutes. Its faces lean lonely at the check-ins
and glad at anything you do. Back after a day away is one reaction, the
personality's Example: `→ lonely, wake up, says hello, small`, with the
reason "You've been away 26 hours"; back after days is the big hello.

**The morning is a reunion, not a guilt trip** (decided 2026-10-27).
Back after a night is the happy wake-up it is now, with the dream told
on it (§3): Boop is glad because you came back, and the reason says so
("You came back"). Lonely is kept for real absence, a day or more, and
for hours at the Mac with no touch or word. Daily guilt wears a bond
down; a daily reunion that you cause builds it.

**General because:** a span of your company is one key in the fold and
one phrase, as the to-do count and the tiers were; the phrase is code,
as every line for the brain is. "You've said thanks 3 times today" or
"day 12 in a row" are the same shape, not new mechanisms.

**Pins.** `TranscriptViewTests`: the untouched span counts from the
last poke, gesture or talk, and from the back when there has been none
since; it shows from 2 hours and never while away; the new bands at 20
and 40 hours. `LonelyEvals`: back after a night (10 hours) is a glad
wake-up, never lonely; back after 26 hours is a lonely wake-up with
`lonely` offered, then a stroke makes it affectionate; 2 hours at
the Mac untouched enters lonely and a word ends it; a working agent
keeps it out; nothing enters lonely inside an hour. The eval pins the
pick and the offered moves (`offered`), not the heading.

**Demo.** `lonely.jsonl`: a day of work, you away a day and a night,
back (the lonely wake-up, its reason), two hours untouched (the check-in, and
the ask of §4 once built), a stroke, the glad face. Needs a
`{"you": "gesture", "kind": "stroke"}` step, which the evals have and
`DemoScript` lacks.

## 3. Dreaming

Each night Boop's day closes and becomes memory, and in the morning
Boop tells you the dream. The night is where a day's care becomes
lasting, as sleep turns a day into memory. The dream replaces the
diary: one concept for Boop's take on a day, a sign it holds up in the
morning and a line it keeps.

**How it is kept** is designed in
[dreaming-memory.md](dreaming-memory.md): one checkpointed reader of
the transcript that runs both memories, counted and written; a `Day`
of counts read as events arrive and closed at the end of Boop's day
(5:00 to 5:00) by a rule on the Mac that needs no brain; traits derived
from the closed `Day`s by one rule shape, Boop's latched once told;
the dream, kept in its `Day`; and the person's view and forgetting.
In short:

- **Traits** are everything Boop knows, as tags: Boop's own, which
  last for good, and yours, which fade.
- **The bond** is Boop's care traits, what your care did to Boop (`cuddly`,
  `cheeky`, `chatty`, `loyal`) that come on after enough days of a kind
  of care, need not be in a row, and never go off once Boop has told
  you. Only care counts; the agents' work never does. A trait earned is
  told once in words, at the next wake-up ("Boop got cuddly. You've
  stroked it most days for 2 weeks."), and after that shows only in
  what Boop does: lines and designs that need it. A Boop after six
  months is one only you could have made.
- **Your traits** (`nightowl`, `earlybird`, `fridayshipper`, `polite`,
  `poker`, `distant`, and your answers to asks) fade when the habit or
  the month does. Your traits make Boop know you; the bond makes it
  yours.
- **The day's tags** for the lines and the dream (`here`, `fond`,
  `distant`, `late`, `answered`, and the agents' `failed`, `clean`,
  `long`, `quiet`, `poked`) come from the closed `Day`.
- **The dream** is one line of `dreams.md`, a sign and a line, picked
  for each day: by Jev at the morning's telling for the newest day, by
  the rules for any day not told. It is kept in its `Day`, and the
  popover shows the week's.
- **The written memory** is stage 2: after the day closes, Apple Intelligence
  on the Mac edits a list of at most 12 one-line entries ("you and
  claude finally fixed the 'api' tests"), which Jev reads as MEMORY.
  It changes Jev's judgment, never Boop's words, and is designed with
  its exact prompt in [dreaming-memory.md](dreaming-memory.md).

**Where the traits go.** Traits are tags from one place, `MemoryStore.tags()`, the way the calendar's are from `Occasions`:
into the prompt's heading as words (`NOW (23:40, Tuesday, you're a
night owl)`), beside the occasions'; into every tagged file as tags a
line may need (`[nightowl] up again?` in `signs.md`, `[cuddly love]
more pets pls` and `[polite] you're welcome` in `replies.md`, and
`dreams.md`, `asks.md`); the personality's Examples may
quote them; and to the board as `state.you`, a second 32-bit set,
since `when` has one bit left. Its names are the engine's (the ten
rules' traits and the five dream tags: 15) followed by the
answers the pack's board designs need (§4's `keeps` questions, up to
17), which `charactergen.py` writes into the firmware and the Mac
mirrors (`Occasions.you`), so an answer a design needs is a pack line,
never an engine change. A cuddly Boop's look can lean into your hand;
a Boop that keeps `cookie` holds one at snack time. `state.you` also
carries yesterday's shape while Boop sleeps (`dreamfailed`,
`dreamclean`, `dreamlong`, `dreamquiet`, `dreampoked`), so the pack's
`asleep` look can dress a dream bubble as its own designs that need
those tags, with no new field and no drawing code of the engine's. A
design's `when` may name a tag of either set.

**The tell.** Boop tells the dream the first time you show up after a
day closes: your coming back, or your first poke, prompt or word,
never an agent's event or while you're away (when and how:
[dreaming-memory.md](dreaming-memory.md), the telling). Its reason is
rendered from the closed `Day`, and its sign and line are one of
`dreams.md`'s, a tagged list like `replies.md` whose tags are the
`Day`'s, which `react.sign` picks as it picks a reply's. **It leads
with you.** The reason puts your care first and the agents' day second
("Boop dreamed about yesterday: you stroked it 4 times. 7 turns on
'api'."), and `dreams.md`'s lines about you come first in the file, so
they are offered first: `[fond] dreamt of u`, `[fond cuddly] warm
dreams`, `[answered] i remember!`, `[distant] where were u?`; then the
agents': `[failed] bad dream`, `[clean] sweet dreams`, `[long] what a
day`, `[quiet] dreamt of nothing`. A day with no care at all is told by
the agents' day alone, plainly, never as a reproach. A trait earned
overnight wins the reason (above). The
dream's line goes into its `Day` and the popover. The first wake of
Boop's day has one owner: on an occasion day the occasion's sign comes
first and the dream is only narrated, one wake-up a day. A second back
the same day tells nothing.

**Signs from one table.** With the tell, `react.sign` has a third
source. It becomes one table in `ReactOutput`, line kind to the tagged
file and the tags on, and the branches go: a prompt's reading to
`signs.md` with the reading's tags; what you said to `replies.md` with
the reply's and the moment's; the telling to
`dreams.md` with the day's; an ask (§4) to `asks.md` with the
moment's. The moment's tags grow once, for every file: the mood
(`[lonely]`, `[grumpy]`), `idle`, and the traits.

**General because:** a new count is one line in `count` and one `{…}`
word; a new trait is one row in `Traits.rules`; a new sign
source is one row
in the table; a new place for facts is one more tag reader, which every
tagged file and every board design already is.

**Pins.** The memory's own (the readers, closing, the rules, repair) are
listed in [dreaming-memory.md](dreaming-memory.md). Here:
`OccasionsTests`: `Occasions.you` matches the firmware's generated
names in order, as `all` matches `kTagNames`, and a pack with more than
17 kept answers fails `boopdev check`. `ReactOutputTests`: the sign
table offers `dreams.md`'s lines only at a telling with
a `Day`, and with the day's tags; a night owl's facts and a cuddly
Boop's trait reach the heading. `DreamEvals`: a fond day's telling
picks a sign about you over a `[failed]` one; a failed day with no care
picks a `[failed]` sign; the second back tells nothing; Halloween's
telling holds up the greeting.

**Demo.** `dream.jsonl`: a day with two finishes and a failure, you
away for the night (the dream bubble over the sleeping face), back in
the morning (the wake-up with the tell: the sign, the fact under it).
It plays yesterday on the demo's clock, so `wait` crosses 5:00, when
Boop's day ends.

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
calendar's, and the traits) plus `finished` (a turn ended in
the last 10 minutes and you haven't prompted since) and `touch` (a
touch answers it, below).

**Asks that shape Boop come first.** A question tagged `keeps` is
asked once, ever: its answer becomes part of Boop, a tag its lines and
the board's designs may need (§3's `state.you`), so the snack you
picked is the one it holds from then on. These come first in the file,
so the brain is offered them first. Quizzes like tabs or spaces are
flavour: Boop learns a fact and teases you with it. One answered stays
off for 30 days; any ask ignored stays off for a day.

**Who asks.** The brain: `react.move` gains `ask`, "Boop asks you
something, from what it may ask now", offered only when `asks.md` has
a line for the moment and the output's rule allows one, and
`react.sign` picks the question, from the sign table (§3). The question
is the sign; the two answers go in the `do`'s `ask` (`a`, `b`, and
`touch` when the line has the tag), and the reason says what to do.

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
`[finished]` one only while the finish's strip still names the thread.
Quiet asks nothing; chatty, up to six a day.

**The answer.** The core logs an `ask` event: `start` with the
question's id and answers in its facts when the `do` is sent, `end` with
`pick` from the board's `ev` (or `ignored` when its `ended` comes with
none). The view folds it: `You answered Boop's "tabs or spaces?":
spaces.`, or `You didn't answer Boop's "tabs or spaces?".` The brain
reacts as to anything said to Boop: a face and a sign, the follow-ups
for that id and answer. The answer becomes a trait (dreaming-memory.md,
traits): Boop's for good for a `keeps` question (`cookie`), yours for
30 days for any other (`spaces`), and a tag wherever traits are. A kept answer's reason says so once: "Boop will
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
`state.you`; lonely asks "pet me?" and a stroke answers it; nothing asks
while an agent needs you.

**Demo.** `asks.jsonl`: a finish, "did it work?", a tap (`{"you":
"answer", "pick": "a"}`, a new step), the follow-up face and sign; an
idle stretch, "fav snack?", a tap, and a day later the cookie in
Boop's snack-time look. The board, the mirror and the simulator draw the two
targets.

## Order

1. **The reason.** Everything after it is explained by it, and it
   changes every recording, so it goes first.
2. **Your company in NOW, and lonely.** Small, and the first thing a
   person feels.
3. **Dreaming, with the tell and `state.you`.** The memory the rest
   reads, and the second tag set the board needs.
4. **Asks.** The largest: the board, the mirror, a new event and a new
   demo step.
5. **The written memory** (dreaming-memory.md, stage 2). It reads
   stage 1's counts, and needs a week of tuning on the owner's Mac.

Each lands as one squash-merged commit: the pack's side first
(SlimeBuddy: `lonely.md` and its edges, `dreams.md`, `asks.md`, the
Examples, the evals, the demo, its recording, the asleep look's dream
designs, the mirror), then this repository's. Pixel takes none of the
files and keeps working: a pack without `asks.md` is never offered an
ask, without `dreams.md` tells nothing, and the reason and the company
in NOW need no pack file.

## What it adds up to

| Priority (2026-10-27) | Built from |
| --- | --- |
| 4. Absence that matters, lonely real, "pet me?" | §2's spans and `lonely.md`; §1's reason under it; §4's `[lonely touch]` ask |
| 5. Idle questions, remembered answers | §4's `[idle]` asks, the `keeps` ones part of Boop for good; answers as traits, and so as tags |
| Care as the cause (the principle) | §3's bond; §1's reason crediting you; §3's tell leading with you; §4's kept answers |
| 6. Morning standup | §3's tell, on the wake-up that exists, with §1's reason as the narration |

And the next things, with no new code: a nickname for you (an ask
whose answer a `{you}` word fills in), a Friday shipper teased on a
Friday (`[fridayshipper friday] again?!` in `signs.md`), a night-owl
look on the board (`state.you` has `nightowl`), a cuddly Boop that
leans into your hand (a design that needs `cuddly`), a trick with
permission (`[trick idle fond] wanna see a trick? | yes | later`).

Dreaming alone, the owner's first thought, covers the memory half:
what Boop keeps from a day and tells later. It can't cover the live
half ("you've been away 12 hours" is a fact at the moment you return)
or the asking, and nothing of it is understandable without the reason.
So four shapes, not one.

## Next: care makes Boop

Two levers carry the most weight and are left for a plan of their own,
built on this one's bond:

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
`asks.md`, parts, `dreams.md` replacing `diary.md`, the new counts and tags, traits as tags),
§9 (the lane's `reason`, the ask's targets, `state.you` and the dream
designs); `characters/DEMOS.md` and `internal/EVALS.md` (the `gesture`
and `answer` steps, the new scenarios); `simulator/README.md` (the
targets and the `answer` step in `simulator/tools/demos.py`);
`documentation/architecture.html` (memory of you, the reason, the ask
event); `CLAUDE.md`'s Words (reason, ask, dream replacing diary, trait, bond; and that
a demo's `run` step's `ask` key is the agent's permission request, a
wire name that keeps its name); `internal/VERIFICATION.md` if a tool
changes; the slime package's `CONTINUITY.md` for the dream designs and
the targets. LinkKit's spec doesn't change: `reason`, `ask` and `ev
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
row or count is Swift, as every English the app writes is. Your company
in NOW is the least general: a span is a fold key and a phrase, both
code, by the same design that keeps every line for the brain in the
view. That is the right place for it, and it is small.
