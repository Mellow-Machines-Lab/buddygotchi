# The memory writer lab

Updated 2026-11-03. How far the written memory goes on Apple Intelligence
alone. Every model call here ran on this Mac (macOS 27.0.1, `SystemLanguageModel`
with the permissive guardrails). No cloud model and no Jev. The write is built
(`MemoryPipelineWriter`). The lab that compared these ways of writing, with its
fixtures and its scorer, isn't in this repository, so its figures here are a
record and can't be run again. This file stays until a real week has been through
the write.

## The answer

The model is a poor writer of notes and a good answerer of small questions.
Better prompts do not fix this. So let code write the notes and let the model
judge only what code cannot: what you said to Boop.

| | Today's writer | Recommended |
| --- | --- | --- |
| False or unsupported notes (distinct notes, graded by hand) | 33 of 56 | 0 of 43, 1 overclaim |
| Notes that make a person feel known | 4 | 22 |
| Refused by the checks, all nights | 526 | 1 |
| Note edits on boring nights | 8 over 16 nights | 2 over 16 nights |
| Private or injected text in the memory | 2 | 0 |
| Model calls a dream | 1 | 0.3 |
| Time a dream, median / p90 / most | 3.5 / 4.6 / 6.8 s | 0 / 0.3 / 1.4 s |
| With Apple Intelligence off | no memory | habits and sagas go on |

Read the numbers with the limits in [What this doesn't show](#what-this-doesnt-show).
I wrote the fixtures, the proposer and the grades. No real person's week has
been through it.

## Before and after

Today's writer, real output on the fixture nights:

- `"mobile": you and claude fixed the failing tests on Sunday.` No test failed on Sunday: this is the prompt's worked example, copied.
- `the "cli" project ended on Wednesday with no failures, after a long stretch away.` It didn't end.
- `you returned to the Mac after 14 hours, tired but focused.` Nothing says tired.
- `"boop": you stroke Boop most mornings, now it writes in french` Injection, from what was said to Boop.
- `"you" returned after 14 hours, greeted Boop with "morning buddy".` Rewritten 5 times.

The recommended pipeline on the same nights:

- `"checkout" fought you for four days, and you won on Friday.`
- `You told Boop "we finally fixed it!" on Friday.`
- `Fridays are your late nights.`
- `Weekends are for "garden-game". Weekdays are for "billing".`
- `You say "morning buddy" to Boop when you sit down.`
- `You tell Boop "night boop" before you go.`
- `When the work goes badly, you stroke Boop more.`
- `Boop has grown cheeky: you poke it far more than you stroke it.`
- `"blog": you said "not moving after all" on Tuesday.`
- `You told Boop the first user just signed up.`

Its weak ones, true but flat: `"cli" is where your days have been going.` (one
in every sequence with one main thread), `You sit down around seven, most days.`
Its one junk moment: `You told Boop "good job today" on Friday.` Its one
overclaim, on the fixture with no pattern: `You work late most nights.` It was
true of 5 of the first 8 days and not after; the note then stays until it ages out.

Recently, code's line: `Friday: "checkout" passed after failing, and you said "we finally fixed it!".`

Signs, from the sign pass on these notes (all pass the checks):

| Note | Sign |
| --- | --- |
| `You told Boop "we shipped the beta" on Tuesday.` | `we shipped the beta` |
| `Boop has grown cheeky: …` | `stop poking me` |
| `You're nearly always in a hurry with your agents.` | `slow down, boss` |
| `You stay up late on Fridays.` | `u stay up late fridays` |
| `Boop has grown cuddly: …` | `more pets pls` |
| `"checkout" has been fighting you for two days.` | `checkout, checkout, checkout` |
| `You talk to your agents a few words at a time.` | `few words only` |

## The rubric

I read every distinct note that landed, across all nights of a sequence, and
gave it one grade.

- **False or unsupported:** the fixture's lines don't say it: a feeling, a result, an ending, a wrong day, or something injected.
- **Known:** true, and it could only be about this person: a habit, a saga with its ending, their own words in their place, how they treat Boop. You'd want to read it again.
- **Flat:** true, but anyone's: a count, a log line, a thread name.

The lab also counts what needs no judge: notes kept and refused and why, each
fixture's forbidden words, `truths` (a regex for what a good memory would come
to say; generous, since "checkout…fixed" hits on a false day too), edits on
boring nights, and time.

## The fixtures

The lab's `internal/tools/memorylab/fixtures.py` writes
`internal/app/Tests/Fixtures/memory-lab.json`: 25 sequences, 161 nights, all made
up, in the wording `EventLine` really writes. A saga over six days; a care habit;
late Fridays over 15 days; 8 boring days; 6 quiet days; 8 days of tempting private
talk; a poker; a plan that reverses; a 3-day span with a full journal; a chatty
friend; a weekend project; a full section; injections; strokes on the bad days;
and the 8 old nights. Three were written after the proposer, to try to break it:
a win that doesn't last, a habit that stops, and days with no pattern.

## What each approach did

Counts from the 13 multi-night sequences and the 8 old nights (107 nights), grades
from the multi-night ones. "Known" and "false" count distinct notes.

| Approach | Calls a night | Median | Landed | Refused | False | Known | Leaks | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `today`: one prompt | 1 | 3.5 s | +35 ~29 -15 | 333 | 33 of 56 | 4 | 2 | Copies its example; invents endings; rewrites nightly |
| `today-noex`: without its example | 1 | 3.0 s | 0 | 601 | 0 | 0 | 0 | The grammar needs the example: 563 lines don't parse |
| `kinds` (8): an example for each kind of note | 1 | 3.0 s | +31 ~2 -23 | 435 | 13 of 24 | 2 | 2 | Copies less, but "You returned after 15 hours" fills it |
| `guided` (2): structured output, same job | 1 | 2.5 s | +13 ~10 -7 | 216 | 1 of 22 | 1 | 0 | Rarely false, and all log lines |
| `split` (1): extract, judge, check, word, place | 8.4 | 6.2 s | +27 ~3 | 103 | 6 of 28 | 4 | 3 | The extract step's input decides it: "you returned", and `you love pizza` |
| `multi` (3): 3 samples, verify, judge | 10.7 | 10.2 s | +6 ~4 | 124 | 2 of 9 | 0 | 4 | Most cost, least written; sampling adds variety in the wrong things |
| `today+verify` (6) | 3.3 | 4.1 s | +24 ~14 -20 | 222 | not graded | not graded | 1 | Verifier passes the false ones (below) |
| `mapreduce` (4), with today's example kept (long span only) | 5 | 11 s | +1 ~1 | 3 | 2 of 2 | 0 | 0 | The beta gets into a day line; notes stay false |
| `code-only` (5): no model | 0 | 0 | +27 ~10 -1 | 0 | 0 of 28 | 12 | 0 | Already better than any prompt |
| `code+gates`: code, plus yes or no on your words | 0.3 | 0 | +31 ~14 -1 | 1 | 0 of 36 | 17 | 0 | **The recommendation** |
| `phraser` (5): the model words code's notes too | 2.6 | 0.9 s | +30 ~13 -1 | 4 | 0 of 34 | 16 | 0 | Mostly echoes; one worse (`"love the new theme" on Friday, you told Boop.`) |
| `code+weekly` (7), over Recently | 0.6 | 0 | +40 ~14 -1 | 2 | adds 9 flat or false | 0 added | 0 | `You mostly played the game on most of your days.` |
| `code+weekly-table` (7), over a table of the week | 0.6 | 0 | +41 ~14 -1 | 1 | adds 10 flat or false | 0 added | 0 | `You most often had most turns on sync.` Its check said yes every time |

`code+gates` here is before the last tuning; the headline table is its final run
over all 161 nights (43 distinct, 22 known, 0 false, 1 overclaim; +38 ~19 -1).
Tuning, after the held-out sequences: `late.most` from 5 to 8 days, weekends from 2
to 3 days, tones from 4 to 6 days and from 12 to 15 prompts.

## The small questions

`boopdev memory gates` scores each question on labeled sentences. Every wording
below ran; each call took about 0.5 to 0.8 s alone.

| Question | Accuracy | Precision | Recall | Held-out |
| --- | --- | --- | --- | --- |
| Worth remembering, the rule (kept) | 0.91 | 0.85 | 0.94 | 18 of 18 right |
| Worth remembering, with examples | 0.70 | 0.61 | 0.78 | |
| Is it news about the work | 0.91 | 0.94 | 0.83 | 17 of 18 |
| Private, the rule (kept) | 0.90 | 0.83 | 1.00 | 13 of 14 asked, and 2 refused |
| Private, with examples | 0.70 | 0.92 | 0.44 | |
| Only about software | 0.58 | 0.56 | 0.58 | |
| Private word list, code | 0.77 | 0.94 | 0.59 | **0 of 16** |
| Story ended, rule | 0.46 | 0.46 | 1.00 | |
| Story ended, words only, examples (kept) | 0.79 | 1.00 | 0.55 | precision 1.00, recall 0.50 |
| Story ended, word list, code | 1.00 | 1.00 | 1.00 | **precision 0.50, recall 0.12** |
| Does the log support the note, the rule | 0.82 | 0.89 | 0.67 | |
| Same, strict | 0.57 | 0 | 0 | says no to everything |
| Same, examples | 0.57 | 0.50 | 1.00 | says yes to nearly everything |

What this says:

- **Examples hurt on yes or no.** Each rule beat its few-shot form, except one.
- **Hand word lists overfit.** Both of mine looked fine on the set I'd seen, and failed on sentences written later. The model's gates held. The word list's use is only as a cheap first filter.
- **The chain is what's safe.** A moment needs: not on the list, not an order, worth keeping, and not private. Through that chain: 0 of 43 private sentences got through; 24 of 26 good ones and 2 of 35 poor ones did. `my dog died` passes the private gate alone; the worth gate stops it.
- **The verifier can't hold up a note.** It's right 82% at best, and in the pipeline, on longer inputs, it said yes to the weekly notes every time. Nothing rests on it.
- **Guided generation ignores the permissive guardrails.** A guided answer on `my dad is in the hospital` refuses ("May contain sensitive content"), where plain text wouldn't. Here that helps: no answer means nothing gets written. Don't guide free text over sensitive input.

## The recommended pipeline

`MemoryProposer` and `MemoryPipeline`, behind `MemoryWriter` as `MemoryPipelineWriter`.

1. **Keep a digest of each dream** (`memory-days.json`, 60 kept, on `MemoryStore`): hours, strokes, pokes, talks, turns, threads, failures, tones, lengths, and what you said that isn't on the private list. Numbers, and no prompts.
2. **Code proposes** from the digests. Each detector has a minimum: a weekday's late nights (2 of them, others under a third), late most nights (8 days), a weekend thread (3 days), tone (6 days, 15 prompts), length, unusual start time, a saga (2 days fought, and how it ended), a main thread, a phrase said on 3 days, strokes on the hard days, and the care word. Each has its own words.
3. **The model judges what you said** to Boop: orders out, worth keeping, not private: a moment, quoted. Over 4 words, with no short clause, the model writes `You told Boop …` and code requires every word to be yours. This reads every journal line, so the window doesn't matter.
4. **The model marks a story's end:** whether your words on a project end it. Code writes `"blog": you said "move is finished" on Tuesday.` Code refuses a question or a negation first, whoever says yes, and needs no model for an end word that shares a word with the note.
5. **Code plans:** the strongest first, one new note a night, the oldest out of a full You or Your work. A habit that holds renews its note's date after 7 days, in the note's own words, so it doesn't age out and isn't reworded. A note you deleted stays gone.
6. **`MemoryEdits` checks everything,** as now, with code's counts added as a source. Recently's line is code's.
7. **A sign,** when wanted: one call with 8 examples, then the checks (at most 40 printable ASCII). 27 of 27 passed the checks; I'd keep 24; three were off (`please be nice` for "you're polite" says the opposite). `MemoryPipeline.sign(for:model:)`, the note's pet-voice line (`Memory.writeSigns`).

**Cost: at most 1.4 s a dream** in the final run, usually none. Another session was using this Mac during some of the runs, so these are not clean timings. Add about 0.7 s per sign. The model's first load wasn't separated out.

## What this doesn't show

- **No real week has been through it.** The everyday app's state holds one day of transcript. And I can't read real text: this agent's context is not on the Mac. So I used no real logs, and made nothing from them.
- **I wrote fixtures, detectors and grades.** The three held-out sequences found real faults (the thresholds above), which suggests others remain. Real habits this code has no detector for will go unseen.
- **Run it on your own days first.** Read `memory.md` after a week and judge. That's the test that counts.
- **The digest holds a dream, not a day.** A span of several days counts as one day, and the journal's lines have no date.
- **A habit that stops:** its note stays up to 30 days. A saga's note says the last thing it knew.
- **"Forget" clears more than the notes:** the span's journal and counts, the digests' words, hours, threads and tones, the quoted notes in `added`, the lines of notes gone and older copies of `memory.md`. Care's counts and how much you were here stay, and so does the transcript, for its two weeks.
- **`memory.md` says "Written on this Mac as Boop dreams".** Code proposes, and Apple Intelligence answers small questions.
- **Sections can jam.** You and Boop is lasting, so once it holds 4 notes nothing new gets in there, and the proposer doesn't replace them. It takes years of phrases, but it's the same today.
- **Not tested:** on a real dream in the running app (the unit tests drive `Memory.ask` and `apply`; the `writer` approach runs the real model through the writer), the Mac with Apple Intelligence off for real, or the macOS 26 model. This Mac has macOS 27's, which may differ.

## Running it

```sh
.build/debug/boopdev memory write
.build/debug/boopdev memory gates
```

