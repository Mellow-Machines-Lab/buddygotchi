# Building the brain

Written 2026-11-22. The order to build
[documentation/design/brain.md](../documentation/design/brain.md) in. That
file says what Boop should do and why; this one says how to get there, one
step at a time. Nothing here is built. This file is a working plan for the
agent that builds it. It does not need to be committed.

## Before you start

1. Read `documentation/design/brain.md`, then
   `documentation/architecture.html` ("The model", "What Jev reads",
   "Memory", "The rules"), then CLAUDE.md.
2. The rules from CLAUDE.md that matter most here:
   - **Only the owner pushes or says to.** Ask before any push and before
     any flash of the board. Work in a worktree, one branch for each step.
   - **Never touch `~/.claude`, `~/.codex` or the everyday app's state from
     a test.** Use a temporary `HOME` and a state directory under `/tmp`.
   - **Boop never blocks an agent.** `boop-cards` answers at once and works
     with Boop closed. Keep both true. Do not use a Stop hook to make an
     agent do anything.
   - **No Jev key is needed for any step.** Do not look for one.
     `Boop --headless --brain scripted` and `boopdev eval --scripted` run
     with none.
   - **Docs change in the same commit as the code** (the table "Docs stay
     in sync"). New words go in CLAUDE.md's Words table in the commit that
     builds them, then `cp CLAUDE.md AGENTS.md`.
3. Three architecture rules in CLAUDE.md change meaning with this work.
   Reword each in the commit that makes it untrue, and in
   `architecture.html#rules`:
   - "The brain ... answers multiple choice only." Still true of the brain
     (Jev and the rules brain). The agent's offered line is not the brain's:
     it is checked text, as a remembered line is.
   - "An agent's card goes to the screen and the transcript, never to the
     brain." Keep it true: nothing an agent writes may reach Jev's prompt.
     `CardsTests` pins this; extend the pin to the new fields.
   - "No code ... or agent transcripts go to the brain." The dream's digest
     now goes to the buyer's agent tool. Say so there and in the README.
4. Do one step, run its checks, report to the owner, and commit. Do not
   start the next step in the same commit.

Checks for every step: `make -C internal build`, `make -C internal check`,
and the tests the step names. Report only checks that ran and passed.

## The order

| Step | What | Gate |
| --- | --- | --- |
| 0 | Three trials, no product change | The owner reads each report and says go |
| 1 | The rules brain | Trial 0c passed its bar |
| 2 | The calling agent | Trial 0a passed its bar |
| 3 | The dream by the agent tool | Trial 0b passed its bar, and the owner has checked the provider's terms |
| 4 | Babble | The owner, with the board |
| 5 | Jev on top, and the cleanup | Steps 1 to 3 have run a week on the owner's desk |

Steps 1, 2 and 3 do not depend on each other and may be built in any order
once their trial has passed. Step 2 is the one the owner most wants to see.

---

## Step 0: the three trials

Each trial ends with a short report in `~/.boopdev/brain-trials/<name>/`
(`report.md` and the raw output). Stop after each and show the owner.

### 0a. How well do agents play Boop?

The question: when asked, do real agents send good lines, a read of the
person and a note, and do they leave short turns alone?

1. Add the new fields to the card tool, **logged only**. Nothing plays yet.
   In `app/BoopKit/Cards/Card.swift`:
   - `CardTool.instructions`: after today's text, add the brief (see "The
     brief" in step 2 for its final shape). For the trial, build it from a
     fixed sample: three lines of `steering/personality.md` and three sample
     memory notes.
   - `result`'s schema gets three optional properties:
     - `boop_lines`: an array of at most 2 objects `{says, feeling}`. `says`
       is at most 40 characters. `feeling` is an enum of the pack's emotions
       that fit a finish. The description asks for two lines in different
       feelings, one of them doubtful, in Boop's voice, about this turn.
     - `you_seemed`: an enum: `pleased`, `plain`, `frustrated`, `rushed`,
       `kind`.
     - `remember`: a string of at most 140 characters
       (`MemoryEdits.maxLength`): one plain sentence about the person or
       their work worth keeping, or left out.
   - `status` returns the sample mood line in place of `ok` ("Boop is
     cross."). Keep `isError` false.
   - `Card.make` keeps the new fields, held to their limits, in `args`, so
     `BOOP_CARDS_LOG` records them.
2. Extend `internal/tools/cards/trial.py`. It already runs fixed tasks
   through real Claude Code sessions with no user settings. Add to its
   scorecard, for each task and model:
   - whether `result` came, and whether each new field came with it;
   - each line's length, and whether it is printable ASCII;
   - the lines, feelings, `you_seemed` and `remember` as text, for reading;
   - for the `explain` task (a quick answer): the new fields should be
     absent.
   Add one task with a frustrated prompt ("this is still broken, third time
   I've asked") to see whether `you_seemed` says so. Add a Codex run if
   `codex exec` can be given the server the same way; if not, say so in the
   report.
3. Run it for `opus` and `sonnet`. Each run costs a real session on the
   owner's plan: say the count before you start, and keep it under 30.
4. Report: the rates, every line that came, and your own reading of whether
   they sound like Boop (short, lower case, a coworker on the person's side)
   or like the agent praising itself.

The bar, for the owner to confirm: on turns that used tools, lines come
with at least 70% of results; at least 90% of lines fit 40 characters; the
quick task carries none; and the owner likes at least half the lines.

If lines come but two is too many or too few, change the count before step
2. If agents ignore the fields unless told harder, try the wording twice
more, then report. Do not make any field required.

### 0b. Is a dream by the agent tool good?

The question: can Boop run `claude -p` (and `codex exec`) by itself, unseen,
with only a plan's login, and are its memory notes better than today's?

1. Find the flags. Start from what `trial.py` already uses
   (`--setting-sources`, `--strict-mcp-config`). Candidates: `--bare`,
   `--no-session-persistence`, `--tools ""`, `--model`. Check by test, with
   a temporary `HOME` where that is possible and the owner's login where it
   is not, and write down for each:
   - does it run with a plan login and no API key? (`--bare` may not.)
   - do the user's hooks stay silent? (The everyday Boop must not see it.)
   - does the session stay out of the session list?
   - how long does it take, and what does one run use?
2. Add a `MemoryModel` that runs the tool:
   `app/BoopKit/Prompt/AgentToolModel.swift`, conforming to `MemoryModel`
   (`text`, `yes`) in `MemoryPipeline.swift`. One process for each call, the
   prompt on stdin, a timeout, no tools, the answer on stdout. For the trial
   it may live in `internal/app/BoopDevKit`.
3. Run the dream's write on real days. `Memory.ask` and
   `MemoryPipeline.write` take a `MemoryModel`; the dashboard's `D` previews
   a dream and keeps nothing. Use that path, on a **copy** of the owner's
   state (`~/Library/Application Support/Boop/memory-days.json`,
   `memory.md`), in a temporary state directory. Never write to the real
   one.
4. Also try the wider job the design wants: one request that gets the whole
   digest and writes the notes itself, in place of today's small yes-or-no
   questions that were shaped for a weak model. Keep `MemoryEdits`' checks
   on whatever comes back.
5. Report: the notes from Apple Intelligence, from the tool on today's
   pipeline, and from the tool with the wider job, side by side for the same
   days. And the answers to the four questions in 1.

The bar: the owner prefers the tool's notes, the run is unseen, and it works
with a plan login.

The owner checks the provider's terms for an app that runs a buyer's agent
tool. Do not ship step 3 before that answer.

### 0c. Does a rules brain hold up?

This is the product review's test (`plan/product-review.md` §9.1).

1. Find the recorded passes. The review tallied nine Jev runs, 6,363
   passes; its tables are in `~/.boopdev/product-review-2026-11-09/`
   (`traj-tables.md`, `frequency.md`, `scripts/`). Trajectories are written
   to `/tmp/boop-eval/*.trajectories.jsonl` by a run and may be gone. If
   they are, say so and ask the owner before any new Jev run: those cost.
2. Build the table: for each slot (the event's kind, the mood, and a few
   facts: the turn's tier, failures in a row, the time since the last
   Moment), the answers Jev gave and how often.
3. Write `RulesBrain` (step 1 below, first draft) and run every scenario
   with it: `boopdev eval --brain rules`, no Jev request.
4. Judge the feel scenarios as `internal/EVALS.md` §5 says, with a fresh
   session and `judge/JUDGE.md`. Test the judge first, as that section says.

The bar, from the review: musts pass at least 125 of 131, and "reasonable"
is within 10 points of Jev's 99 of 110. Check both numbers against the
current scenario count before you quote them.

---

## Step 1: the rules brain

The aim: with no key, Boop has its mood, an emotion at every event and a
whole answer to a touch.

**The seam.** `MellowHarness.Brain` (`mellowharness/Sources/MellowHarness/Brain.swift`)
is one function: a prompt and questions in, answers out. `Runtime.useBrain`
(`app/BoopKit/App/Runtime+Brain.swift`) installs Jev when there is a key and
nothing when there is not, and `Pipeline.brain` then holds every wake back
("no brain"). Put the rules brain in that empty place, so every output's
code rules (`MomentOutput`, `MoodOutput`, Talk, needs you, takes) still
apply unchanged.

1. `app/BoopKit/Brains/RulesBrain.swift`, a `Brain` with id `rules`. It
   answers the same questions Jev is asked: `mood` (`MoodOutput`),
   `react.face`, `say`, the sign question (`Signs.questionKey`) and
   `react.reply` (`MomentOutput`).
   - It needs the event as facts, not as prose. Do not parse the prompt's
     English. Give it a structured side input from `TranscriptView` (the
     event's kind, the outcome, the tier, in-a-row counts, the mood and its
     age). If `Brain`'s signature must grow for that, do it in MellowHarness
     in a generic way, in its own commit there, and update its
     `ARCHITECTURE.md`.
   - Emotion: a weighted pick from the slot's short list, seeded, and never
     the one shown last for that slot.
   - Mood: **keep the mood map exactly.** Do not design new moods or moves.
     The map is the pack's `character.json` (`lasting`: the seven moods,
     each `meaning` and `not_for`, cross's `levels`, each `fade` with its
     `minutes`, `to` and `holds`) and the seven files in `steering/mood/`,
     which say for each mood what keeps it, what ends it at once, and what
     moves it to which other mood. Transcribe those moves into a table the
     rules read, one row for each move a file names (for cross: sorry or
     thanks to calm; a stroke while annoyed to calm; a check failing while
     the agent works on, or the person sounding frustrated, to focused; a
     pass after a fail or a done turn to calm; the agent giving up, a very
     long failure, sad news or rude words to sad). An event no row names
     leaves the mood where it is. `MoodOutput.fade` and `MoodOutput.level`
     stay code's and unchanged. `lonely` keeps its guard
     (`MoodOutput.options`' `mayMiss`).
   - Where a mood file's prose is unclear or two files disagree, list the
     cases for the owner. Do not settle them yourself.
   - Write one test for each row, named for the move it pins, so a change
     to the map shows as a failing test. The mood files stay the source: a
     pack's check fails when a file names a move the table lacks.
   - Sign: from the offered lines, the one shown longest ago.
   - Reply to your words: extend the word matching in
     `Outputs/StatusReply.swift` to the reply kinds; no match is `huh`.
2. The table lives in the pack, since the moods and faces are the pack's:
   `mac/brain.json` in SlimeBuddy and PixelBuddy, with its builder in the
   pack's tools. Document it in `characters/CHARACTER.md`. A pack without
   one gets a small default table in the engine.
3. `Runtime.useBrain`: Jev with a key, else `RulesBrain`. `Pipeline.brain`
   is then always true; remove the "no brain" hold and the log line that
   says Boop does only its rule reactions.
4. `Boop --brain` gains `rules`; headless with no key defaults to it.
5. Evals: a scenario's musts become table tests that run in
   `make -C internal check` with no key. Update `internal/EVALS.md`.
6. The app's words: remove or soften the no-brain notices in the popover and
   onboarding. Do not remove the key's Settings field (step 5 decides).

Checks: `make -C internal check`; `boopdev eval --brain rules` at the bar of
trial 0c; a headless day (`Boop --headless --brain rules --debug`) with hook
events, read in `boopctl dash`, showing mood moves and no repeat of an
emotion twice running. Latency of a touch's answer under 100 ms in
`debug.jsonl`.

Docs: `architecture.html` (the model's "Decided by" column, "How Boop
works" step 5, the rules), README ("A Jev key" row, "What leaves your Mac"),
CLAUDE.md (Words: `pass`, `wake, hold`, `mood`, `moment`; "Jev is asked only
where it earns its place"), `mellowharness` docs if it changed,
`documentation/design/brain.md` (add a "What is built" section).

---

## Step 2: the calling agent

The aim: at the end of a real turn Boop says a line the agent offered, the
agent's read of you can move the mood one step, and a note waits for the
dream.

### 2a. The brief

`boop-cards` is one-way today: it writes a line to the hook socket and
answers `ok`. Keep it so. The agent learns about Boop from a file.

1. Boop writes `agent-brief.json` in its state directory whenever the mood,
   the memory or the setting changes (`MemoryStore` is the only reader of
   the memory files, so the brief is built from it on the runtime's queue):
   the buddy's name, a short product line, the personality's opening lines
   from the pack's `steering/personality.md`, the memory's notes (You, Your
   work, You and Boop; not Recently's quotes), the mood now in a plain
   sentence, and whether the agent's part is on.
2. `boop-cards` reads it at `initialize` and builds `instructions`: today's
   text, then the brief, then the ask. With no file, or the part turned off,
   it sends today's text and nothing about memory. It reads it again at each
   `status` and answers with the mood's sentence in place of `ok`.
3. The ask, in the instructions and nowhere else: with `result`, on a turn
   that did real work, you may offer two lines Boop could say, say how the
   person seemed, and note one thing worth remembering. Skip all of it on a
   quick answer. Do not mention Boop in your answer to the person.
4. Keep the whole instructions text small. Measure it and put the token
   count in the commit message.

### 2b. The fields

Make the trial's fields real, with the count and wording the trial settled.
`CardTool.line` already carries a card's `args` to the hook socket with the
agent's process; the new fields go the same way. Boop holds every field to
its limit again as it reads the line, since anything may write to the
socket.

### 2c. The offered line

1. `Core.card` (`app/BoopKit/Core/Core+Cards.swift`) finds the session. Keep
   the offered lines with the session's turn until its finish. A result with
   no finish within 15 s drops them.
2. Checks before a line may play, all existing code:
   `MemoryPipeline.signIsValid` (length, printable ASCII) with
   `signRoom(face:)` for the room, and `mayKeep` (no secret, no order, not
   private by the list). A refused line is dropped silently and logged in
   `debug.jsonl` with why.
3. The pick is a rule in `MomentRule`, beside the finish's move and size:
   given the finish's emotion (from the brain in use), the mood and what
   Boop saw (the outcome, failed checks in the turn), take the offered line
   whose feeling fits, or none. A failed or stopped turn never takes a proud
   or happy line. A chat turn plays no finish and so no line.
4. It plays as the finish's sign: on the gel the low sign, under the
   thread's name; on a face with no low sign, only if it fits
   `Signs.maxLength`. The narration for the popover says whose words they
   were ("claude offered it") and may carry a longer line whole.
5. Talk's rules apply as to any sign: Quiet, on a call, face down, and the
   one-Moment-at-a-time queue.
6. The transcript keeps the line as part of the finish's `did`. No line Jev
   reads carries it: extend `CardsTests`.

### 2d. The read of you

`you_seemed` becomes a fact on the finish's event. It adds no move to the
mood map. It only supplies facts the map already names, such as "the person
sounding frustrated" or kind words, beside the prompt's own reading; the
map's rows (step 1) decide the move, or none. With Jev in
use it is one more word in the finish's line of NOW, as a reading is.
Without step 1 built, keep the fact in the transcript and stop there.

### 2e. The note

`remember` does not go into `memory.md`. It becomes a journal line for the
dream (`MemoryReader.Tallies.journal`): "claude noted: …". The dream's write
decides, and `MemoryEdits` checks it like any other candidate. Notes from
agents are capped at a few a day, the newest kept.

### 2f. The switch and the promise

1. Settings: one switch, on by default, "Agents help Boop think". Off: the
   brief carries no memory and no ask, and the fields are ignored.
2. Onboarding says the same in one friendly sentence where it installs the
   hooks.
3. README "What leaves your Mac": Boop's personality and memory go into
   your agent's context, and so to its provider. Notes and lines an agent
   writes stay on the Mac.

Checks: unit tests for each field's limits and each refusal; a test that a
failed turn never plays a proud line; `CardsTests`' pin extended; a headless
run with `boop-cards` driven by hand over stdio (a script that sends
`initialize`, `status`, `result`) showing the line on the simulator's low
sign; `trial.py` again, now with Boop headless listening, to see real lines
play end to end. Show the owner the simulator's pictures.

Docs: `plan/agent-cards.md`, `architecture.html` ("An agent's card", the
rules), CLAUDE.md (Words: `card`, and new words `brief`, `offered line`;
the architecture rules above), README, `documentation/design/brain.md`.

---

## Step 3: the dream by the agent tool

The aim: Boop's memory is written by a strong model with no setup, and the
dream leaves fresh lines for the next day.

1. Move `AgentToolModel` into `app/BoopKit/Prompt/` with the flags trial 0b
   settled. It finds `claude` and `codex` as the installers do
   (`CardInstaller`, the hooks' installer): only a tool whose hooks Boop
   installed is used. One run at a time, a timeout of two minutes, no
   tools, never while a turn of the person's is running.
2. The writer's order, chosen where `Memory` gets its writer today: the
   agent tool, then Apple Intelligence, then code alone. The setting from
   step 2 turns the agent tool off here too.
3. The dream's write uses the wider job from the trial if it won: one
   request with the digest, the journal (with the agents' notes) and the
   memory as it stands; edits back in the plain lines `MemoryEdits` reads.
   Every check in `MemoryEdits` stays.
4. Tomorrow's lines. The same run, or a second one, writes lines in Boop's
   voice for the slots that have no agent: a hello, an idle musing, an
   answer to a stroke, a bye. Up to a handful for each slot, each within the
   sign's room, each through `signIsValid` and `mayKeep`. Keep them in the
   state directory through `MemoryStore`, with the day they were written;
   drop them after a week.
5. Dealing them is a rule, where each slot's line is picked today
   (`IdleBeat` for musings, `MomentRule.hello` and `bye`, the touch's
   reply): a dream's line first, the one shown longest ago, and the pack's
   line when none is left. The same caps and rests apply.
6. "Forget" removes these lines with the rest (`Memory.forgetAboutYou`).
7. The fallback inside a long turn is **not built in this step.** Build it
   only if trial 0b fails on a plan login, or the owner asks. If built: a
   third tool, `dream`, offered only in the session's opening instructions,
   taken only when Boop marks a dream as waiting in the `status` answer of a
   turn already past three minutes, at most once a Boop day.

Checks: unit tests with a stub `MemoryModel`; a test that a line failing a
check never reaches a slot; a headless dream on a copied state with the
real tool, read in `boopctl dash` (`D` previews); a test that the run's
flags keep hooks silent, using a temporary `HOME`.

Docs: `architecture.html` ("Memory", "Memory you feel"), README ("What
leaves your Mac": the digest goes to your agent's provider at each dream),
CLAUDE.md (Words: `the dream's write`, `remembered line`; a new word for a
dream's line), `characters/CHARACTER.md` if the pack's `dreams.md` changes.

---

## Step 4: babble

The aim: every line Boop holds up has a voice in Boop's own sounds.

This step needs the board, the pack and the owner's ears. Do the Mac's part
and the simulator first, and stop before any flash.

1. Read `characters/CHARACTER.md` §8. The voice is recorded takes in
   `voice/voice.bin`, picked on the Mac from `mac/takes.tsv`.
2. The pack gains a bank of syllable takes, each short, in a few pitches.
   Until they are recorded, voicegen's espeak-ng placeholders stand in, as
   they do for other lines.
3. The Mac turns a line into a babble: a count of syllables from the line's
   vowel groups, capped; takes chosen by a seed from the line, so the same
   line babbles the same way; the mood sets the pitch set and the gap. This
   is Voice's job: only Voice knows what Boop can say.
4. The wire: a `do` carries the order of takes. This is a LinkKit change
   (`linkkit/SPEC.md`, its `ARCHITECTURE.md`), and firmware for both
   boards. A board with an older voice file says its version in `hello`;
   the Mac then sends the single sound it sends today.
5. Start with medium and big Moments only. Small Moments keep their sound.
   On a call, on Quiet and face down, nothing plays, as today.
6. A reply to your words: with step 3's `AgentToolModel`, a short reply to
   what you said, within the sign's room, checked the same way. While it
   waits Boop holds a thinking face; past ten seconds it answers by rule.
   This is the last part to build and may be left for later.

Checks: simulator scenarios for a babbled finish and a silenced one; the
gel's own tests in SlimeBuddy; `make -C internal boards`. Then the owner
flashes and listens: is it a charm or a noise at each finish, and does it
sound looped?

---

## Step 5: Jev on top, and the cleanup

After steps 1 to 3 have run a week on the owner's desk.

1. With a key, Jev answers the emotion questions and the rules brain
   answers the rest. Keep `JevBrain` as it is; compose the two brains.
2. Onboarding loses its brain card. Settings keeps one optional line for
   the key, with a link that leads somewhere a person can get one.
3. Remove the out-of-credit and "Jev isn't answering" notices that a buyer
   with no key can never see. Keep the ones a key's owner needs.
4. The evals keep a Jev level for the owner; the default level is the
   rules brain's and is free.

---

## What to tell the owner at each stop

Start with the result and what you need. Name the files you changed. Say
which checks ran and passed, and which did not run. Show pictures from the
simulator for anything on the screen. Ask before a push, a flash, a Jev run
or more than 30 agent sessions.
