# Memory and dreaming: the design (2026-10-27)

The detailed design behind [dreaming.md](dreaming.md) §3: what Boop
remembers, how a day becomes memory, and how memory reaches what Boop
does. [dreaming.md](dreaming.md) says why (your care is the cause of who
Boop is) and what the person sees; this file says how it is kept, so
that it is correct, survives crashes and upgrades, and grows with data
rather than code. Written and reviewed against the code on 2026-10-27;
the Review section at the end says what the review changed.

## What is wrong with memory today

Found in the code on 2026-10-27, before any of this is built:

1. **The diary loses yesterday's morning.** `DiaryOutput.due` recounts
   yesterday from the log in memory, and the log keeps only the last
   24 hours there (MellowHarness's `Log.Options.keepMs`; files keep 14
   days). At a first pass at 9:00, everything before 9:00 yesterday is
   out of view, so the counts are short. The diary eval (`97-diary`)
   starts at 15:00 and passes 18 hours later, inside the window, so it
   never sees this.
2. **Yesterday is "now minus 24 hours".** `DiaryOutput.yesterday` takes
   the day 24 hours back, not the calendar's day before. Just after
   midnight following a 23-hour day (summer time starting), that names
   the day before yesterday, which already has a line, so the short day
   never gets one. Its calendar tags are taken at that moment too, not
   at noon as its comment says.
3. **Only yesterday is ever written.** Back after a weekend, Friday and
   Saturday get no line, and nothing else remembers them.
4. **No brain, no diary.** The diary is the only record of a day, and
   it needs Jev's answer. Without a key only growth's XP and two weeks
   of transcript files remain.
5. **Midnight cuts a night owl's evening in two.** Work until 1:00
   counts on two days, and the night Boop dreams through is not the one
   you slept.

Growth alone counts as events arrive, with a cursor, so it is right
whatever the 24-hour window holds. That is the pattern to build on.

## The model: four layers, as people remember

| Layer | What it holds | Where it lives | How long | Who writes it |
| --- | --- | --- | --- | --- |
| Working memory | The last minutes and hours: HISTORY | The transcript, in memory | 24 h in memory, 14 days in files | Every event |
| Episodes | Each day as a `Day`: counts, nothing said | Key-value store, `day.<date>` | Care and work for good; the rest 60 days | The memory fold; sealed at night |
| Knowing | The bond, your facts, your answers | The bond latched and your answers in the key-value store; facts derived each night | The bond for good; facts while they hold | The night pass |
| Identity | Name, hatch day, seed | `long-term.md` | For good | Setup |

`diary.md` stays what it is: the written record, a line a day, for the
person to read.

The design in one line: **fold as it happens, seal at night, derive
the rest.**

- **Fold.** The open day grows with each event as it is logged, with a
  cursor. Nothing depends on the 24-hour window, on the app running at
  midnight, or on the brain.
- **Seal.** At the end of Boop's day, the open day is sealed. A sealed
  `Day` never changes.
- **Derive.** Your facts are pure functions of the sealed `Day`s. A
  rule changes, they are worked out again. Only what is a promise is
  latched: a bond trait, once on, never goes off.

## What counts as you

The most important definition here, and the one the first draft got
wrong: **an event is yours only if you did it.** The hourly heartbeat
fires all day on a Mac left awake, and agents log events overnight;
counting those as you would make a desk Mac "seen" every day, an
"early bird" at 5:00 and "here" while you are on holiday, and nothing
would flag it.

`Yours`, one set in code, used by the `Day` and by dreaming.md §2's
company fold alike:

| Yours | Not yours |
| --- | --- |
| A poke; a care gesture (below); a talk; a prompt; a `presence` end (you came back); an ask's answer | Heartbeats; every agent event but your prompt; Boop's own events (`did`, `reacted`, `dream`, `hush` by the app); the board's `handoff`, `dismiss`, `swipe` and drawer events |

**Care gestures** are an allow-list, as data: `stroke`, `nose`,
`tickle`, `pickup`, `ruffle` (care, if clumsy), `dizzy` (a shake: rough
care, which counts for `cheeky`). Never `handoff` (BOOT), `dismiss`
(holding the needs-you screen), `swipe` (the drawer), `putdown`,
`startle`, `facedown` or `peekaboo`.

## Boop's day: 5:00 to 5:00

A `Day` runs from 5:00 to 5:00 local time and is named for the date it
starts on. Work until 1:00 is the same day; the night after it is the
one Boop dreams through.

- **Its own constant,** `LocalTime.boopDayStartHour = 5`, not
  `Occasions.dayParts`: a later change to when "morning" starts must
  never re-key history.
- **Calendar arithmetic,** `LocalTime.boopDay(ms)`, through
  `Calendar`, never "minus 24 hours", so a 23- or 25-hour day is one
  day.
- **The calendar's tags** (holidays, Friday, the part of the day) keep
  the calendar's midnight, and a `Day`'s calendar tags are derived from
  its date at noon, never stored.
- **Time zones.** `LocalTime` fixes the zone at launch today, for the
  transcript's file names as well, so travel moves the cut at the next
  launch. This plan keeps that, pinned in a test. Following the zone
  live (`TimeZone.autoupdatingCurrent`) is a change to the transcript
  too, and a plan of its own.
- **The clock.** The seal cuts by the wall clock, as growth names its
  day (`options.wallClock`); event times serve only for durations. A
  clock set back never reopens a sealed day: an event dated inside one
  counts toward the open day. A clock set forward never seals more than
  a day past the wall clock.

## The `Day`

**The open day** is one row, `day.open`: the counts so far, the date it
started, and the fold's working state, which the seal strips:

```json
{"day": "2026-10-26",
 "care": {"stroke": 4, "ruffle": 0, "nose": 1, "tickle": 0, "poke": 2, "dizzy": 0, "pickup": 1,
          "talk": 3, "talk_replied": 3, "kind": 1, "rude": 0},
 "you": {"first_min": 192, "last_min": 1120, "here_min": 312, "back": 2, "answered": 1,
         "prompts": 16, "labeled": 0, "polite": 4, "frustrated": 1, "shouting": 0,
         "morning": 3, "day": 10, "evening": 2, "night": 1, "deploy": 0,
         "first_after_rest": 192},
 "work": {"turns": 7, "failed": 3, "longest_min": 42, "thread": "api", "helpers": 2},
 "_state": {"away_since": null, "here_since": 1080, "turns_open": {"claude:s1": 1080},
            "threads": {"api": 6, "web": 1}}}
```

**A sealed day** is `day.2026-10-26`, the same without `_state`. A row
exists only for a day the app logged something: **a missing row is a
day Boop didn't see**, and the derivations walk the dates, so a gap
needs no marker.

**What it keeps.** Counts, minutes since the day's start (never clock
strings, which don't sort across 5:00), and one thread name, the one
the diary already writes. Never a word you wrote, a command, a file or
a message: your prompts arrive only as their readings, so their counts
are by tone and kind.

**Unknown is not zero.** The open day is created with every key the
running app counts, at 0, and the fold counts only keys present in it.
So a key that a newer app adds mid-day stays absent, unknown, for that
day, and an older row never reads a new count as 0. A count that
changes its meaning gets a new key; there are no row versions.

**Counts that need something else carry their denominator**, so a rule
can tell "none" from "can't tell":
- `kind` and `rude` come from the react output's `did` for a talk (its
  `reply` fact: `love` and `thanks` are kind, `ouch` is rude), which
  exists only when the brain answered. `talk_replied` counts the talks
  that got one.
- `deploy` and the other kinds of prompt need a labeler, Apple
  Intelligence on macOS 26; tones such as `polite` are counted from cues
  on every Mac. `labeled` counts the prompts a labeler read.

**Care with several buddies.** One buddy first: v1 keeps care unkeyed.
A buddy's id today is its pack, or its place (`left`, `right`), and
events to the only buddy carry none, so neither is an identity a bond
can hang on. When several buddies ship, care is keyed by the board's
own id from its `hello`.

**Where each count comes from**, one table, `DayFold.counts`:

| Count | Event |
| --- | --- |
| `care.<gesture>` | `gesture` in the care allow-list; `poke` |
| `care.talk`, `talk_replied`, `kind`, `rude` | `talk`; the react output's `did` with a `reply` |
| `you.back` | A `presence` end |
| `you.here_min` | From each `presence` end, or the day's first yours event with no away open, to the next away's `since` (not its `at`: an away is logged 10 to 30 minutes after it began), or the day's last yours event |
| `you.first_min`, `last_min` | The day's first and last yours event |
| `you.first_after_rest` | The first yours event after an away of 4 hours or more, for `earlybird` |
| `you.answered` | An ask's end with a pick (dreaming.md §4) |
| `you.prompts`, `labeled`, tones, parts of the day, kinds | `prompt`, its reading's facts, and the part of the day at its time |
| `work.turns`, `failed`, `longest_min`, `thread` | `turn` start and end, as `DiaryOutput.count` counts them today; a turn open across 5:00 counts on the day it ends, from its start in `_state` |
| `work.helpers` | `subagent` end (new) |

The diary's `{pokes}` reads `care.poke`.

## The fold

`Memory`, in `app/BoopKit/Memory/`, the memory store's, as growth is:

- **One driver, one cursor.** `memory.seq`, the `seq` of the last event
  counted. Reducers, the open day and your answers, each take an event
  and return the keys it changed. An event at or before the cursor is
  left alone, so a replay counts nothing twice.
- **One transaction per event that changes something**: the changed
  keys and the cursor, in one `KeyValueStore.set`, which is atomic
  across keys. An event that changes nothing saves nothing.
- **Attached once,** `Memory.attach(pipeline:store:)`, called where the
  pipeline is made, so the app, `--headless` and the evals all have it.
  Today growth's fold is wired in `Runtime.init` alone, which the evals
  never call.
- **Growth stays as it is.** It could move onto the driver, but that is
  risk with nothing the person sees; maybe last, maybe never.
- **A clean quit saves the cursor** at the transcript's last `seq`.
  At launch, a cursor behind the files means a crash: the driver reads
  the files after it (one new reader, `Transcript.events(after: seq)`,
  over the files rather than the log in memory), up to their 14 days.
  A cursor ahead of the files (a power loss that lost the file's tail
  after SQLite committed, or files deleted) moves back, as
  `GrowthStore.follow` does.
- **The key-value store needs** a prefix scan (`key >= 'day.' AND key <
  'day/'` on the primary key), a delete, and a `busy_timeout`.
- **When the store falls back to memory** (a file from a newer app, or
  one that won't open), the memory fold is off for that launch: no
  backfill, no seal, no dream. The next good launch repairs from the
  files.

## The seal and the night pass

The seal is a rule on the Mac. It needs no brain, no key and no board.

**When.** At the start of `Pipeline.input`, before its body logs
anything, and at launch after repair: every input and every tick goes
through `input`, so a Mac awake all night seals on the first tick
after 5:00, and one asleep seals on waking. Sealing there, not inside
an event's rules, means the event that follows already sees the dream
in the log (`view(before:)`), and no rule ever logs an event.

**One transaction** writes the whole night:
1. The sealed `day.<date>`, and a new, empty `day.open`, its keys at 0
   and its `_state` carried over (an away or a turn open across 5:00).
2. Each bond trait newly on: `bond.<trait>` = `{"day", "told": false}`.
3. Your facts as now derived: `fact.<tag>` = `{"since"}`, and those gone,
   deleted.
4. The diary's line for the day, the rules' pick (below), unless the
   brain writes it first.
5. `dream.pending.<date>`, the dream to log.
6. Your `you.*` counts in rows older than 60 days, blanked.

**Then** it logs each pending dream as a `dream` event, Boop's own, with
no wake, so a seal at 5:00 costs no request: `{"day": "2026-10-26",
"tags": ["fond", "failed"], "earned": ["cuddly"], "facts_on":
["nightowl"], "facts_off": [], "tell": true}`, and deletes its
`dream.pending`. A crash between the two leaves the pending row, and
the next launch or tick logs it, unless the log already has a `dream`
for that day. The event is the record for `boopdev`, the view and the
evals; the key-value store is the truth.

**The telling** is the brain's, and later. Whether a dream is told
lives in the key-value store, never in the 24-hour view: `told.day` is
the newest day told. The telling happens on the first pass after a
seal on an event that is yours, with the view not away: your coming
back, or your first poke, prompt or word of the day. Never an agent's
event, never a heartbeat, so it never plays to an empty room. That
line gets the dream under it, as a reading is:

```
NOW (09:02, Tuesday; Boop got cuddly)
You came back to the Mac after a very long break.
  Boop dreamed about Monday: you stroked it 4 times; 7 turns on "api", 3 failed.
```

The pass offers `dreams.md`'s signs for the day's tags, the reason
renders the sentence, and the diary asks its question for that day.
Its `did` sets `told.day` and every untold trait's `told`. A trait
earned on a day that is never told itself (back after a long weekend,
or backfill) is still told at the next telling, so nothing is latched
without the person hearing of it.

**The first wake of Boop's day has one owner.** Today `Core.greetDay`
greets an occasion on the first agent's event of the calendar day,
once a launch, so after work past midnight on Halloween it greets at
00:01, and the morning's dream would then be a second wake-up. Instead,
`wake.day` in the key-value store keeps the Boop day greeted, across
launches, and one decision makes the first wake: with an untold dream,
the telling, with the occasion's sign first in the sign table, so
Halloween's morning holds up "Happy Halloween!" and narrates the dream;
with none, `greetDay` as now, on Boop's day.

**The diary, without the recount.** Every line is written from a sealed
`Day`, never the log, so the counts are whole.
- The seal writes the rules' pick (the first line that fits, by the
  seed) for every day it seals but the newest, oldest first, so the
  diary stays in order.
- The newest day waits for the telling, where the brain picks its line.
  If no telling comes before the next seal, or there's no brain, the
  next seal writes the rules' pick for it.
- `diary.md` is the record of which days have a line (`appendDiary`
  already refuses a second line for a day), not the 24-hour `did` scan.
- The popover's week runs on Boop's day.

## Deriving what Boop knows

**One rule shape** for the bond and your facts:

```
Rule(tag, window, day: (Day) -> Bool?, on: Int, off: Int)
```

The tag comes on when at least `on` days in `window` make `day` true,
and goes off when fewer than `off` do: a gap between the two keeps a
fact from flickering on the board night after night. `day` returns nil
when it can't tell (a key absent, a denominator at 0), and that day
counts for nothing. Two windows: `all` (every sealed day) and
`last(n)` (the newest `n` sealed days, missing days skipped). The bond's
`off` is never reached: a trait, once on, is latched.

| Tag | Kind | Window | A day counts when | On | Off |
| --- | --- | --- | --- | --- | --- |
| `cuddly` | bond | all | strokes ≥ 3 | 10 | latched |
| `cheeky` | bond | all | pokes + tickles + dizzy ≥ 5 | 10 | latched |
| `chatty` | bond | all | talks ≥ 3 | 10 | latched |
| `loyal` | bond | all | back ≥ 1 and any care | 30 | latched |
| `nightowl` | fact | last 7 | a prompt at night | 3 | 2 |
| `earlybird` | fact | last 7 | `first_after_rest` before 7:00 | 3 | 2 |
| `fridayshipper` | fact | last 14 | a Friday with a deploy prompt (nil with none labeled) | 2 | 1 |
| `polite` | fact | last 7 | polite ≥ 3 in 10 prompts (nil with no prompts) | 3 | 2 |
| `poker` | fact | last 7 | pokes ≥ 5 | 3 | 2 |
| `distant` | fact | last 7 | yours events and no care at all | 5 | 3 |

`earlybird` reads the first yours event after a rest of 4 hours, so a
night owl working to 5:30 is not an early bird. `distant` needs a day
you were there: a holiday is a missing day, not a distant one.

**Where the rules live.** In code, one table, `Knowing.rules`, each row
pinned in a test: the engine's promises about care, the same for every
character. A pack never defines a trait; it uses the tags in its lines
and designs.

**Your answers** are not derived. The answers reducer writes each ask's
end as `answer.<id>`: the pick, the day, and whether the question
`keeps`. A kept answer is a tag for good; another, for 30 days.

## How memory reaches Boop

Through two doors, and only two:

1. **Tags.** `MemoryStore.tags()` gives the bond's traits, your facts,
   your answers that are tags, and the last sealed day's dream tags
   while Boop sleeps. They join the one tag provider (dreaming.md §3):
   the heading, every tagged pack file and the board's `state.you`.
2. **The dream line**, once, at the telling.

The heading names at most three, the bond first: `NOW (09:02, Tuesday;
Boop is cuddly; you're a night owl)`. The `Day`s and their counts never
go to the brain, except the dream line's few.

## What the person sees and controls

- **The popover's memory.** Under Growth, "What Boop remembers": each
  trait with its day and its reason ("Cuddly since 30 Oct: you stroked
  it on 12 days"), your facts ("Night owl: you worked late 4 of the
  last 7 days"), the answers it keeps, and the diary's week. Every line
  is a `Reason` row.
- **Forget what Boop learned about you.** One button. It deletes your
  answers and facts, and blanks `you.*` in every `Day`, so the facts
  cannot come straight back from the evidence. The bond and the care
  counts stay: they are Boop's, made by your care, not a record of you.
- **Starting over** (a new hatch, everything gone) doesn't exist today:
  setup refuses once a Boop exists, and Uninstall keeps the memory. It
  is new work, below.
- **What leaves the Mac.** Everything is kept in the state directory.
  The brain is a remote API, and it gets your facts as words in the
  heading on every pass ("you're a night owl"): inferences about you,
  where every other line is about the moment. The dream line sends a
  few counts and the thread's name, as finished turns' lines already
  do. Settings says this beside the forget button.
- **What is kept for good** is only care and work: `you.*` is blanked
  after 60 days, so Boop doesn't keep a log of your hours.

## Backfill

The first launch with memory folds the 14 days of transcript files,
once, gated on `memory.backfilled`:
- It skips the oldest file's day: the files are calendar days, so its
  Boop day is partial.
- It seals every complete day and leaves today open.
- It logs no `dream` events and tells nothing, but a trait it latches
  is told at the first telling.
- It counts `kind` and `rude` only where the react `did` is in the
  files, which it is for two weeks.

## Checking it

**Pure tests**, no clock or brain:
- `DayFoldTests`: each count from its event, table-driven; the care
  allow-list leaves out `handoff`, `dismiss` and `swipe`; heartbeats and
  agents' events make no day seen, no first and no here; an away counts
  from its `since`; `kind` unknown with no brain, `deploy` with no
  labeler; a key added mid-day stays absent; a turn across 5:00.
- `BoopDayTests`: the cut at 4:59 and 5:00, over both summer-time
  changes, and at 00:30 after a 23-hour day; a clock set back; a clock
  set forward.
- `SealTests`: on the first tick after 5:00 and on waking; one
  transaction; a crash between it and the `dream` (the pending dream
  logged at launch, once); no seal, no backfill and no dream when the
  store fell back to memory.
- `KnowingTests`: each rule's `on` and `off`; nil days count for
  nothing; a night owl is no early bird; a latch surviving a rule raised
  past it; forgetting.
- `RepairTests`: a cursor behind the files after a crash; ahead after a
  lost tail; none at a clean quit; backfill skipping the partial day.
- `DiaryTests`: an 08:00 start, its first pass the next day at 09:00,
  with whole counts (the bug, pinned); the rules' picks for days not
  told, in order; no brain, still a diary.
- `TellingTests`: the dream under the next yours event's line; never
  while away, never on an agent's event; an untold trait carried to the
  next telling; one first wake on Halloween.

**Evals** seed memory instead of playing ten days. The scenario file
gets `"memory": {"days": [...], "answers": {...}, "bond": {...}}`,
written before the first step; `Eval.run` makes an in-memory key-value
store and attaches `Memory`; and `expect` gets `dream` and `told`.
`97-diary`'s case changes: a check-in at 1:00 no longer starts a new
day.

**Tools.** `boopdev memory --state-dir DIR` prints the `Day`s, the bond,
the facts and the answers, each with its reason. `boopdev dream
--state-dir DIR` seals now and prints the `dream` event. Both take the
instance lock, so they refuse a state directory the app has open.

## Build order

1. **The fold, the seal and the diary from sealed `Day`s.** This alone
   fixes the five bugs above, and nobody sees it but a whole diary.
2. **The `dream` event, the telling and the one first wake,** with
   `dreams.md`.
3. **Knowing:** the rules, the latch, the tags, the heading.
4. **The answers reducer,** with dreaming.md §4's asks.
5. **The popover's memory and forgetting.**
6. **Starting over,** if the owner wants it.

## Open calls for the owner

1. **Boop's day at 5:00,** not midnight. Recommended: it keeps a late
   evening whole and makes the dream the night you slept.
2. **Forgetting keeps the bond.** Recommended: the bond is Boop's, and
   your care made it.
3. **Your facts go to the brain as words.** Recommended, with the
   sentence in Settings: they are what lets Boop act on knowing you.
   The other way is tags in the pack's lines only, never in the heading.
4. **A `Day` keeps the busiest thread's name.** Recommended: the diary
   already writes it.
5. **Backfill for existing Boops.** Recommended: no Boop starts its
   memory from nothing.

## Words

`Day` (a day of Boop's as kept), Boop's day, yours (an event you did),
fold, seal, the bond, your facts, knowing (the bond, facts and answers
together), dream (the `dream` event and its telling). The Words table in
`CLAUDE.md` gets them when this is built.

## Review (2026-10-27)

A fresh read of the first draft against the code. It confirmed the
diary's lost morning, and changed:

- **"You" is defined.** The first draft read any event as you; heartbeats
  and overnight agents would have made every day seen, every desk Mac an
  early bird and every holiday distant. Now one `Yours` set, a care
  allow-list (there is no `shake` gesture; it's `dizzy`), and an away
  counted from its `since`.
- **Where the seal runs.** Inside an event's rules, the dream would land
  after the line it should sit under; now at the start of
  `Pipeline.input`, so the next event sees it.
- **Told lives in the key-value store,** not the 24-hour view, and a
  trait latched on an untold day is told later; the event's field is
  `tell`. A crash mid-seal is covered by one transaction and a pending
  dream.
- **The first wake has one owner,** so Halloween's greeting and the
  dream are one wake-up, kept across launches.
- **Simpler data.** No unseen rows or gap markers (a missing row is an
  unseen day), no row versions (a new meaning is a new key), no stored
  calendar, minutes instead of clock strings, an explicit open row, and
  denominators for counts that need the brain or a labeler.
- **One driver, one cursor,** attached where the pipeline is made, so
  the evals have it; growth stays as it is; repair only after a crash;
  memory off when the store falls back.
- **Corrections:** two more diary bugs (24 hours back; tags not at
  noon); the transcript keeps its numbering across two weeks away (the
  newest file is always read); the time zone is fixed at launch, not
  followed; there is no "start over" yet; care can't be keyed by buddy
  yet.
- **Privacy said plainly:** your facts go to the brain as inferences,
  `you.*` is kept 60 days, and forgetting blanks the evidence.
- **Facts have hysteresis,** so a 3-of-7 fact doesn't flicker on the
  board.
