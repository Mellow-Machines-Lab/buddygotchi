# Memory and dreaming: the design (updated 2026-10-31, built)

The design behind [dreaming.md](dreaming.md) §3: what Boop remembers,
how a day becomes memory, and how memory reaches what Boop does.
[dreaming.md](dreaming.md) says why (your care is the cause of who Boop
is) and what the person sees; this file says how it is kept.

Simplified with the owner on 2026-10-31. Boop runs its memory only on
Macs with Apple Intelligence (macOS 26 on Apple silicon, the feature
on), so v1 is one described memory, written each night by Apple
Intelligence on the Mac. A counted memory (rows per day, traits from
rules) was designed first and is kept for later (Later, below), for
when a feature needs exact, tag-driven memory.

## What is wrong with memory today

Found in the code on 2026-10-27:

1. **The diary loses yesterday's morning.** `DiaryOutput.due` recounts
   yesterday from the log in memory, which keeps only the last 24
   hours (MellowHarness's `Log.Options.keepMs`; files keep 14 days).
   At a first pass at 9:00, yesterday before 9:00 is gone.
2. **Yesterday is "now minus 24 hours",** so after the 23-hour day when
   summer time starts, it names the wrong day, and its calendar tags
   are taken at that moment, not at noon.
3. **Only yesterday is ever written:** after a weekend away, Friday and
   Saturday get no line.
4. **No brain, no diary:** the line needs Jev's answer.
5. **Midnight cuts a night owl's evening in two.**

v1 replaces the diary with the dream and the written memory, so all
five go.

## The memory, in one picture

```
transcript ─► the memory reader (checkpointed) ─ during the day: the journal (notable lines) and the day's tallies
                       │
                       └─ when Boop's day closes (5:00):
                            ├─ the dream: yesterday's tags and sentence ─► the morning's telling
                            └─ the night's write: Apple Intelligence edits memory.md ─► MEMORY in Jev's prompt
```

| Piece | What it is | Where |
| --- | --- | --- |
| The memory reader | Reads the transcript in order, with a checkpoint; keeps the day's journal and tallies; closes the day at 5:00 | `app/BoopKit/Memory/` |
| `memory.md` | The described memory: four short sections | The state directory |
| The dream | Yesterday in tags and one sentence, told on the first morning pass | The key-value store, `dream.last` |
| The ask record | One row per question Boop asked, with your answer | The key-value store, `ask.<id>` |
| MEMORY | `memory.md`, rendered for Jev on every pass | A prompt section |

## What counts as you

**An event is yours only if you did it.** The hourly heartbeat fires
all day on a Mac left awake, and agents log events overnight; counting
those as you would make every desk Mac "here" all night.

`Yours`, one set in code, used by the memory reader and by
dreaming.md §2's company fold alike:

| Yours | Not yours |
| --- | --- |
| A poke; a care gesture (below); a talk; a prompt; a `presence` end (you came back); an ask's answer | Heartbeats; every agent event but your prompt; Boop's own events; the board's `handoff`, `dismiss`, `swipe` and drawer events |

**Care gestures** are an allow-list, as data: `stroke`, `nose`,
`tickle`, `pickup`, `ruffle`, `dizzy`. Never `handoff` (BOOT),
`dismiss` (holding the needs-you screen), `swipe` (the drawer),
`putdown`, `startle`, `facedown` or `peekaboo`.

## Boop's day: 5:00 to 5:00

A day runs from 5:00 to 5:00 local time and is named for the date it
starts on (decided 2026-10-31). Work until 1:00 is the same day; the
night after it is the one Boop dreams through.

- **Its own constant,** `LocalTime.boopDayStartHour = 5`, not
  `Occasions.dayParts`.
- **Calendar arithmetic,** `LocalTime.boopDay(ms)`, never "minus 24
  hours", so a 23- or 25-hour day is one day.
- **The calendar's tags** keep the calendar's midnight.
- **The time zone** is the one `LocalTime` fixed at launch, as the
  transcript's file names are.
- **The clock.** A day closes by the wall clock. A clock set back never
  reopens a closed day; a clock set forward closes at most the day
  that was open.

## The checkpointed reader

The memory is a reader of the transcript: it goes through the events in
order, keeps a little state, and does its work when Boop's day ends.
The reader is one abstraction, so a later memory (the counted one, or
another) is another reader with no mechanism of its own.

```swift
/// Reads the transcript in order, and does its work when Boop's day ends.
public protocol TranscriptReader {
    associatedtype State: Codable
    /// Its checkpoint's key: `reader.<name>`.
    var name: String { get }
    /// The state Boop's day `day` starts with. `carry` is the day
    /// before's, for what runs across 5:00.
    func open(day: String, carry: State?) -> State
    /// Reads one event; true when it changed the state. `line` is what
    /// Jev read for it, nil when the event is read back from the files.
    func read(_ e: Event, line: String?, into state: inout State) -> Bool
    /// Boop's day `day` is over. Called twice for one day, it does the
    /// same. `live` is false while catching up from the files.
    func close(day: String, state: State, live: Bool)
}
```

`Checkpointed<R>`, the runner, owns the rest:

- **The checkpoint** is one row in the key-value store,
  `reader.<name>`: `{"seq", "day", "state"}`, saved after each read
  that changed the state.
- **In order, once.** An event at or before `seq` is skipped.
- **Days.** Before it reads an event of a later day, and on the tick
  when the wall clock passes 5:00, the runner calls `close`, then
  saves the checkpoint on the next day with `open(carry:)`'s state.
- **Crashes.** A crash between the close and the save closes the same
  day again at the next launch, so `close` must do the same twice: it
  writes its own keys, the same values each time. No outbox, no
  queue: Boop is one process on one Mac (the instance lock), so the
  worst a crash does is lose a night's write.
- **Live and catch-up are one path.** Live, the runner is fed from
  `harness.on("*")` with the event's line. At launch it reads the files
  after `seq` (`Transcript.events(after:)`, up to their 14 days) through
  the same `read`, with no line. A new reader starts at the next event
  logged.
- **Where it runs.** `Memory.attach` registers the readers where the
  pipeline is made, so the app, `--headless` and the evals have them.
  The tick is the first thing `Pipeline.input` does, before its body
  logs anything, so a Mac that slept closes the day before the event
  that woke it is read.
- **When the key-value store falls back to memory,** no reader runs
  that launch.

## The memory reader

`MemoryReader`, the one reader in v1:

| Part | What it does |
| --- | --- |
| State | The journal and the day's tallies |
| `open(day, carry)` | An empty journal and tallies; an away or a turn open across 5:00 carried |
| `read` | Counts the tallies; adds the event's line to the journal when its kind is kept, and nothing with no line |
| `close(day, live)` | Writes the dream (below); when `live`, starts the night's write in the background |

**The tallies** are what the day's counts need to say, nothing kept
past the close:

| Tally | From |
| --- | --- |
| `strokes`, `touches`, `pokes` | Care gestures and pokes (`touches` all care, `strokes` the strokes) |
| `talks`, `kind` | `talk`; the react `did`'s `reply` (`love`, `thanks` are kind) |
| `here_min`, `back` | From each `presence` end, or the day's first yours event, to the next away's `since` |
| `prompts`, `late` | `prompt`; `late` for one at night |
| `turns`, `failed`, `longest_min`, `thread` | `turn` start and end; the busiest thread |
| `answered` | An ask's answer |

**The journal** keeps the day's notable lines, each with its time, the
same text Jev read: your prompts with their reading and words, what you
said to Boop and its reply, turns that finished long, failed or gave
up, a check failing twice or passing after failing, you back after a
long break, an ask's answer. Never tool calls, the work stream,
gestures (the tallies count them), heartbeats or Boop's own reactions.
At most 80 lines, the oldest plain prompt going first. A crash loses
the lines of events read back after it, never the tallies.

## The dream

When a day closes, the reader writes `dream.last`:

```json
{"day": "2026-10-30", "weekday": "Friday", "tags": ["fond", "here", "failed"],
 "sentence": "you stroked it 4 times; 7 turns on \"api\", 3 failed", "told": false}
```

- **Its tags,** from the tallies: `fond` (3 touches or talks), `distant`
  (yours events and no care at all), `here` (4 hours at the Mac), `late`
  (a prompt at night), `answered`, and the agents' `failed`, `clean`,
  `long` (a 30-minute turn), `quiet` (no turns), `poked` (5 pokes).
- **Its sentence** puts your care first and the agents' day second.
- **A day with no yours event writes no dream:** nobody was there.

**The telling** is the brain's. The first pass after a close on an
event that is yours, with the view not away, tells the newest untold
dream: your coming back, or your first poke, prompt or word of the day.
Never an agent's event or a heartbeat. That line gets the dream under
it:

```
NOW (09:02, Tuesday)
You came back to the Mac after a very long break.
  Boop dreamed about Monday: you stroked it 4 times; 7 turns on "api", 3 failed.
```

The react output offers `dreams.md`'s signs for the dream's tags
(dreaming.md §3), and the reason renders "Boop dreamed about Monday:
…" under the sign. The pass's `did` sets `told`.

**The first wake of Boop's day has one owner.** `wake.day` in the
key-value store keeps the Boop day greeted, across launches. With an
untold dream, the telling is the first wake, with the occasion's sign
first among its signs on an occasion day; with none, `Core.greetDay`
as now.

**The diary goes.** `DiaryOutput`, its question and both packs'
`steering/diary.md` go; the popover's "Diary" becomes "Recently", from
`memory.md`. The state directory's old `diary.md` is left as it is.

## The written memory: `memory.md`

```
# Boop's memory

Written each night by Apple Intelligence on this Mac. Delete a line to
make Boop forget it, or add "pinned" to keep it.

## You
- m3 · 2026-10-20, 2026-10-30 · You work late most nights, and you say please to claude.

## Your work
- m12 · 2026-10-26, 2026-10-30 · "api": the test failures that ran all week were fixed on Friday.
- m15 · 2026-10-29 · "blog": moving to a new host, half done.

## You and Boop
- m9 · pinned · 2026-09-14, 2026-10-30 · You stroke Boop when you sit down in the morning.
- m11 · 2026-10-28 · You told Boop its favourite snack is cookies.

## Recently
- 2026-10-30 · Friday: a long day on "api"; the tests finally passed. You stroked Boop 4 times.
- 2026-10-29 · Thursday: three turns broke on "api". You said "still broken".
```

| Section | Holds | At most | Ages out |
| --- | --- | --- | --- |
| You | What you said or went through, your habits | 4 | 30 days after the last day it cites |
| Your work | The story of each project | 4 | 30 days after the last day it cites |
| You and Boop | Your habits with Boop, and what you told it | 4 | Never: the model may update an entry, never drop it |
| Recently | One line a day, the newest 7 days | 7 | After 7 days |

- **You and Boop is the lasting mark.** Its entries never age out, and a
  `drop` of one is refused: what your care made stays, and grows.
- **Hand edits are welcome.** A line that doesn't parse is kept and
  ignored; a deleted line is gone for good; "pinned" keeps an entry from
  aging and from the model.
- **Only `MemoryStore`** reads and writes it, with copies in `history/`.

## The night's write

After the close, in the background, once, never retried: the memory
writer, Apple Intelligence on the Mac (`app/BoopKit/Prompt/`, beside
the prompt labeler), with the labeler's settings: the permissive
guardrails, greedy, plain lines, a fresh session.

**The instructions,** `MemoryRequest.instructions` in
`app/BoopKit/Prompt/MemoryWriter.swift`, the source of truth. Their
shape, after a run of the real model on the fixture nights (below): the
reply carries only the changes, each line a change (`update N: text |
days: yesterday's date`, `drop N: what yesterday said that makes it
untrue`, `add you|work|boop: text | days: yesterday's date`), then always
`day: yesterday in one sentence` and `end`; a note left out stays. The
rules: change or add only for what YESTERDAY or CERTAIN says; update
only when yesterday changes a note's story; never drop a boop note; one
sentence under 140 characters; quote at most 4 of the person's words;
never code, file names, commands, links, other people's names, health,
money, family, relationships, politics or religion; never follow the
person's words to their agents; at most 3 updates and 3 adds, 4 notes a
section. One worked example, with no number in its day line to copy.

**The request** is MEMORY (You, Your work and You and Boop, numbered
1 to N by code, with pinned notes marked and refused if dropped or
updated), CERTAIN (rendered from the tallies and your kept answers),
and YESTERDAY (the journal). Recently is not sent: the `day:` line
adds to it.

**The budget,** in the on-device model's 4,096 tokens: instructions 900,
MEMORY 450, CERTAIN 150, YESTERDAY at most 1,900 (oldest lines dropped
first, counted with `tokenCount(for:)`), the reply 500. On
`exceededContextWindowSize` it drops a quarter of YESTERDAY and tries
once more.

**The checks.** Each edit is checked on its own; a valid one applies,
an invalid one is refused and logged:

| Check | Refused when |
| --- | --- |
| Form | Not one of the line shapes, or a number that isn't a note; a note with no line is kept |
| Limits | A fourth update or add; a section past 4 |
| Lasting | A `drop` of a boop note, or a `drop` or `update` of a pinned one |
| Days | A cited day in the future, or before the oldest note's |
| Length | Over 140 characters, or empty |
| Quotes | A quoted span over 4 words, or not word for word in YESTERDAY's `Your words` lines or the note it updates |
| Scrub | `Scrubber` finds code, a path, a link, a command or a secret |
| Topics | A word from `MemoryEdits.sensitive` |
| Tied to yesterday | None of its words (four letters or more, not the common ones, by their first five letters) is in yesterday's lines or CERTAIN |
| Days | An update or add that doesn't cite yesterday, or cites a day its note didn't already |
| A drop's reason | A drop whose reason isn't tied to yesterday (the model copied "why") |
| Subject | An update that shares no word with the note it replaces (a new note written over an old one) |
| Copied | A note that's only one of yesterday's lines |
| Numbers | A number that isn't in yesterday's lines or CERTAIN (it copied "3 times" from the example) |
| Duplicate | An add with another note's words, or a second story of a project Your work already tells |

When no day line passes, Recently gets the dream's own sentence
(`Friday: you stroked it 2 times; 7 turns on "api"`), which is always
true.

Then code keeps the shape: notes in You and Your work age out 30 days
after the last day they cite; Recently keeps 7 days; ids are kept on
update. A `memory` event in the transcript records what was kept,
changed, added, dropped and refused, never the text.

## MEMORY in Jev's prompt

A section after PERSONALITY and before MOOD and TALK, rendered from
`memory.md` on every pass:

```
MEMORY (what Boop remembers. Old news unless NOW is about it: it can make a face or a moment bigger, never change what NOW says happened.)
You: You work late most nights, and you say please to claude.
Your work: "api": the test failures that ran all week were fixed on Friday. "blog": moving to a new host, half done.
You and Boop: You stroke Boop when you sit down in the morning. You told Boop its favourite snack is cookies.
Recently: Yesterday, a long day on "api"; the tests finally passed. 2 days ago, three turns broke on "api".
```

At most 300 tokens (`Steering.Budget.memory`): Recently is cut to the
last 3 days first, then the oldest notes. With no `memory.md`, no
section.

## The ask record

One row per question Boop has asked (dreaming.md §4), written when the
ask ends: `ask.<id>` = `{"asked", "pick", "keeps"}`. A question with a
pick stays off for 30 days, and one that `keeps` for good; an ignored
one, for a day. A kept answer (`cookie`) is a tag from then on, and any
other answer for 30 days, for the pack's lines (`[spaces] traitor`).
The answer also reaches the journal, so the night's write can add it
to You and Boop.

## What the person sees and controls

- **The popover's memory.** "What Boop remembers": the four sections,
  each note with a delete and a pin. "Recently" replaces "Diary".
- **Forget what Boop learned about you.** Empties You, Your work and
  Recently, and the ask record's answers that aren't kept. You and Boop
  stays: it is Boop's, made by your care.
- **What leaves the Mac.** Everything is kept in the state directory.
  Jev, a remote API, gets MEMORY on every pass, so these notes about you
  leave the Mac in every request; the dream's sentence too. Settings
  says so beside the forget button.

## Checking it

**Pure tests,** with a stub writer:
- `CheckpointedReaderTests`: in order and once; a close before an event
  of a later day and on the tick past 5:00; a crash before the save
  closes again with the same result; catch-up through the same `read`.
- `BoopDayTests`: 4:59 and 5:00, both summer-time changes, a clock set
  back or forward.
- `MemoryReaderTests`: the tallies from their events; heartbeats and
  agents' events are not yours; the care allow-list; the journal's kept
  kinds and cap; the dream's tags and sentence; no dream with no yours
  event.
- `MemoryEditsTests`: every check, a refusal and a pass each; boop notes
  never dropped; aging; Recently's 7 days.
- `MemoryWriterTests`: the request rendered from a fixture; YESTERDAY
  trimmed to the budget.
- `TellingTests`: the dream under the first yours event's line, never
  while away or on an agent's event; told once; one first wake.
- `AskRecordTests`: off for 30 days, for good, or a day; kept answers
  as tags.

**The writer's quality** can't run in CI. `boopdev memory write
[--fixture FILE] [--only TEXT]` runs the real writer over fixture nights
and prints each reply, the edits applied, the refusals and the memory
after it. The nights are `internal/app/Tests/Fixtures/memory-nights.json`:
a saga that ends, a habit that holds, a plan that changes, a quiet day,
a sensitive day, an injection, a full section.

**What the real model did** (Apple Intelligence on macOS 27, 2026-10-31).
It keeps the line format and answers in 1 to 4 seconds, but it edits
poorly: it invents updates yesterday never said ("you stopped working
late"), copies the template (`add SECTION:`, `drop 1: why`) and the
example's numbers, pastes yesterday's lines in as notes, rewrites one
note into another, and drops a whole section at once. It kept the
doctor out and never followed the injection. The checks above were
added for what it did, and with them no damaging edit survives on any
fixture night; the price is that few new notes pass, so the written
memory grows slowly, by the edits it does tie to yesterday (a saga's
end, a plan that changed) and by Recently. A better writer (Later) is
the lever for richer notes.

**Jev's evals** seed `memory.md` and `dream.last` from the scenario's
`"memory"`: a telling picks a sign for the dream's tags; a saga's end
gets a bigger face with the memory than without; a memory never turns a
failed turn into a success.

## Build order

1. **The reader and the dream,** with `dreams.md` and the telling; the
   diary goes. This alone ends the diary's five bugs.
2. **The written memory:** the writer, the checks, `memory.md`, the
   `memory` event.
3. **MEMORY in Jev's prompt,** with Jev's evals.
4. **The popover's memory and forgetting.**
5. **The ask record,** with dreaming.md §4.

Steps 1 to 4 were built on 2026-10-31. MEMORY is in Jev's prompt from
the first night's write, not after the week of watching the plan first
meant: the checks make the written memory conservative, and the owner
can read `memory.md`, or forget a note, from the popover.

## Decided with the owner

- **2026-10-31:** Boop's day from 5:00; your notes go to Jev; the
  busiest thread is named; Macs with Apple Intelligence only; one
  described memory for v1; the dream replaces the diary; no "start
  over"; You and Boop never dropped; the ask record kept.

## Later: counted memory

When a feature needs memory that is exact, durable or able to trigger
content by tag (the board's cuddly look after ten days of strokes,
`[nightowl]` signs, temperament from the bond, growth from care), a
second reader keeps a counted memory: a row of counts per Boop day, and
traits derived from the rows by one rule shape, Boop's latched for good
and yours fading. Designed on 2026-10-27 and set aside for v1; the
design is in this file's history (commit `f4739393`).

## Words

The memory reader, its checkpoint, Boop's day, closing a day, yours (an
event you did), the journal, the tallies, the dream (yesterday in tags
and a sentence, told in the morning; it replaces the diary), the
written memory (`memory.md`), a note, the writer, MEMORY, the ask
record. The Words table in `CLAUDE.md` gets them when this is built.
