# Boop: harness evals

Updated 2026-11-02. How we check that Jev decides as Boop should: short
scenarios of agent work, run through the real pipeline (the transcript,
the core and the view), MellowHarness's `Harness` and Boop's outputs. A must
scenario checks each pass exactly; a feel scenario goes to a judge (§4, §5).

The mood question offers staying and every move from the mood on the
pack's graph ([characters/CHARACTER.md](../characters/CHARACTER.md) §5),
and how long a mood holds is the steering's.

## 1. What an eval is

A scenario is a few hook-level steps on a virtual clock. Each run starts
fresh: a new core and view, an empty transcript kept in memory, the
scenario's mood (`calm`, the resting mood, unless the file says), set as
the dashboard would set it just before the first step, so HISTORY can
say how long Boop has been in it, and how much it says (normal unless the file says quiet
or chatty), told in CONTEXT's Talk row and held in code. The runner (`Eval` in
`internal/app/BoopDevKit/Eval/Eval.swift`) wires them as the app does
(`Runtime.harness`), with the real `mood` and `react` outputs, except
that a Moment goes to a fake device, which answers at once with the
`ended` the step names, `done` unless it says otherwise (`reaction`,
§3), read as the app reads the device's (`Reactions`), so HISTORY shows
it as played. A step's
`failed: cut short: you tapped Boop` is the device's `cut` by a poke,
held as the app holds it: in progress while the pokes go on, done once
they stop; `failed: waited too long` is its `skipped`, `late`.

For each step it moves the clock a second at a time to the step's time,
ticking the pipeline as the app does, so check-ins and other timers
fire on the way, and hands each tick's view events that wake the brain
to the harness at that tick, so a check-in is answered when it comes.
Then it feeds the step's raw events to the pipeline, one input at a
time, and hands every view event that wakes the brain to the harness as
it's made, straight through without MellowHarness's loop (`Harness.respond`,
with `loop` off). The
clock starts at a fixed
Wednesday 14:00 UTC and stands still while Jev answers. Every hook
names the agent's process, as a real agent's hooks do, one made up for
each session, as each Remote Control thread has its own, and the
scenario's agents run all through it, their threads never archived, so
a request waits however long a step's `at` jumps, up to a silent day.

| Step | Fed to the pipeline as (the transcript's raw events) |
| --- | --- |
| `turn started` | A `turn` start (`UserPromptSubmit`) |
| `command` | A `tool` start of a `Bash` call with the step's `topic`, then its end at the same moment: `failed` as given (default false), with `error: exit_code` when it failed. `program` gives it a program (`git push`), and `half` plays only its `start` or `end`, for a command that runs a while: only then is it a work act, whose start is a pass of its own |
| `turn finished` | A `turn` end, `done` (`Stop`) |
| `turn failed` | A `turn` end, `failed` (`StopFailure`), with the step's `error` (default `api_error`) |
| `poke` | One poke from the device, a pass: steps a second apart make pokes in a row |
| `hush` | The app's Hush button: Boop says nothing for `Core.hushMs`, a pass (it may sulk) |
| `press` | BOOT, the board having handed you an agent: the core opens the next one in line (no pass; check it with `expect.opens`) |
| `ask answered` | The board ends the buddy's last question: `pick` `a` (the left answer, the default), `b`, `touch` (a stroke, its first answer) or `ignored`. Nothing when it asked nothing, so a step that expects a pass then fails |
| `gesture` | A touch on the board, its `kind` (`stroke`, `ruffle`, `swipe`, a quick stroke, `nose`, `tickle`, `dizzy`, `pickup`, `putdown`, `startle`, `facedown`, `peekaboo`), which it already reacted to: a line, as a poke. `dismiss` is a finger held on the needs-you screen: the request that shows stops showing (`Core.dismiss`, named by its number, as the board does), though its agent still waits |
| `to-do list` | The agent writes its to-do list, the step's `todos` (`3/7`: done, of all): a `TodoWrite` call's start with the counts, then its end |
| `edit` | An edit that removes the step's `count` lines (100 unless it says) and adds none, as the hooks count them: a turn's finish says `, 1,200 lines gone` once its edits removed 500 or more net |
| `helper started`, `helper returned` | The agent sends a helper off (`SubagentStart`), and it comes back (`SubagentStop`), the step's `helper` (`h1` unless it says) |
| `pokes` | Four pokes at once from the device (the step's `count`, if it says), each a pass: the step checks the last, `You poked Boop 4 times in a row.`; `while it slept` for a run's first poke with no session open, `, again` for a run within 2 minutes of the last |
| `said` | What you said on push-to-talk, the step's `words`, after the device's button: a `talk` event, `You said to Boop: "…"` |
| `away` | You lock the screen and leave: a `presence` start, `locked`, since this moment, `You stepped away from the Mac.`, which wakes no pass |
| `back` | You unlock it: a `presence` end, `unlocked`, `You came back to the Mac after a long break.` with the break's band since the last `away` |
| `lock`, `unlock` | The screen locks or unlocks, however short: a `lock` start, or end since the last `lock`, each waking a pass: `You locked the Mac, first time in a while.`, `You unlocked the Mac after 2 min.`. After an `away` the unlock has no line, so no pass: its `back` is the one reaction |
| `session started` | A Claude session opens with no turn (`SessionStart`, `startup`): Boop is awake and idle, not asleep. No line, so no pass |
| `compact` | The agent's context is compacted (`SessionStart`, `compact`): `claude's context on "landing" was compacted; it picks up where it left off.` |
| `needs you` | Claude asks to run a command: a `Bash` call's start, then its `PermissionRequest`. While it waits nothing wakes the brain but what you say |
| `answered` | The call you allowed finishes (`PostToolUse`): "needs you" clears, `You answered claude on "landing".` |
| `wait` | Nothing; only time passes: a check-in may come, the working one while a turn works, an idle check-in every 15 to 30 minutes for two hours after the last activity, twice that gap with no session open, else hourly, which wakes the brain only while the mood has somewhere to settle when Boop sleeps or you're away |

Every event is Claude's, in project `landing`, in session `s1` or the
step's `session`, with the step's `workspace` if it has one.

**The check.** A step with `expect` is checked against the last pass
woken on the way to it and by it, so a `wait` checks the check-in its
ticks brought: an idle one, or while a thread works, the working
one. Each expectation is a set of acceptable values (`proud|happy`), so
a scenario holds wherever more than one answer is right. For `react`,
`mood` and `say`, a leading `!` takes values away from everything the
key may be: `!none` is any face, `!lonely` any lasting mood but lonely,
`!swear` anything but a swear. Write the set the scenario means, not a
long list that checks little:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react.face` question: `none` or an emotion |
| `move` | The move the Moment played, Jev's `react.move` pick: at an event a finish (`success`, `failure` or `reply`), `wake up`, or `notice`, when your prompt says its name; to what you said the reply (`huh` below the floor); at your lock or unlock `wave`, or at a night's lock `nap`; or `none` when it played none or Boop didn't react |
| `intensity` | The Moment's size, Jev's `react.intensity` pick (`small` to `huge`: how long the emotion held and how big what it said), or `none` when `react` didn't react |
| `say` | What it asked to say, `say`'s pick when it reached the floor (a feeling, `swear` or a topic), or `none` |
| `sign` | The sign the Moment held up: for a prompt's reading Jev's `react.sign` pick, from the pack's `signs.md`; for what you said, Jev's `react.sign` pick among the reply's lines in the pack's `replies.md` (your words played back included) or, for `status`, the agents' facts (`StatusReply`). `some` for any, `none` for none, or words any of which it says, in any case (`still broken` passes `still broken :(`) |
| `said` | A take Boop said, by its text as the bubble shows it (`Tsk...`): the step passes when any of the `say`'s takes is one listed; `some` when it said anything, `none` when it said nothing. A scenario that names a text no take has doesn't load |
| `mood` | Boop's mood after the pass |
| `offered` | Exactly the options the pass's `mood` question offered, as a set: staying in the mood it had, and every move the graph has from it, so a scenario can pin the graph |

A step fails if its pass was dropped (late, or an error), or if any
expectation doesn't hold. A step with `expect` that wakes no pass stops
the whole eval as broken. The evals ask Jev, so they need its key and
fail without it.

**The whole-run checks.** A scenario's `checks` are judged over every
pass of a run, checked or not, for how lively Boop stays: an animated
Boop that doesn't sit on one emotion, repeat itself or flail. Each is loose, there to catch a clear failure,
and to be tightened once Boop meets it (`Eval.judge`):

| Check | Fails when |
| --- | --- |
| `max_quiet_working` | The turn runs longer than this with no Moment played, counted from its start or the last Moment to the next or its end |
| `max_same_in_a_row` | More Moments than this in a row are the same emotion, animation and take (however long each held) |
| `mood_changes` | The mood changes a number of times outside this range (`1-3`, `2-` for 2 or more, `-2` for 2 at most) |
| `no_mood_bounce_within` | A mood changes back to the one it just left sooner than this |
| `reactions` | The run plays a number of Moments outside this range |
| `min_variety` | The run plays fewer different Moments (emotion, animation and take) than this |
| `words_said` | The share of the Moments played that said something falls outside this range |
| `moves_on_graph` | A pass's `mood` answer wasn't one of the options it offered (or Jev gave none it could use), or the mood changed along something that isn't a move on the graph |
| `signs_seen` | None of the signs it names (`"fav snack?|hat or bow?"`) was held up at any pass: for what Jev does now and then, such as asking, not at a given step |
| `moods_seen` | A mood it names (`"lonely"`, or several, each required, `"lonely|sad"`) was never the mood at any pass: one that came and faded between two steps still counts |

**Always and gaps.** An `always` scenario is a must that's Boop's character,
not a tuning target: it runs 3 times at the full level. A scenario with a `gap` is one Boop can't pass today,
with why and what would fix it: its failures are reported as `GAP` and
don't fail the eval, and when it passes in every run the report says to
take the gap out.

## 2. Running them

```sh
BOOP_JEV_KEY=… .build/debug/boopdev eval --only apology   # while working: the scenarios you touched
BOOP_JEV_KEY=… .build/debug/boopdev eval --only tests --timeline
BOOP_JEV_KEY=… .build/debug/boopdev eval     # quick: the default
BOOP_JEV_KEY=… .build/debug/boopdev eval --level standard   # before a branch merges
BOOP_JEV_OVER_LIMIT=1 BOOP_JEV_KEY=… make eval   # full: only when the owner asks, or before a release
.build/debug/boopdev eval --list             # every scenario's case, runs and requests, the three levels' totals and today's count; no key needed
.build/debug/boopdev eval --scripted         # every scenario with the expect brain: everything but Jev, free
.build/debug/boopdev prompts                 # what Jev reads and is asked at every pass, for the Character Studio's Brain view
BOOP_JEV_KEY=… .build/debug/boopdev eval --only please --labeler apple   # the prompt read by Apple Intelligence, not the step's reading
.build/debug/boopdev read-check              # Apple Intelligence's readings of sample prompts and last messages, scored; fails under its floors or on a leaked secret
```

**The expect brain, and a demo for every scenario.** A demo is an eval
with its brain's answers written in. The expect brain (`ExpectBrain`)
answers each pass as its step expects: the step's own `brain` answers
first, else the first value of each `expect` set that the question
offers, else what the pipeline check would. The mood moves a step a pass
on the graph, so when the wanted mood isn't a move away, it takes the
move on the shortest path there, and a step that wants no mood starts
toward the next mood a later step wants if that's more than a move off.
It prices every run (`--list`), and `--scripted` runs every scenario
once with it, with no key: what it checks is everything but Jev, that
each step wakes the brain as it says, that the moods it expects lie on
the graph's paths, and the whole-run checks a run can fail without Jev
(`max_quiet_working`, `moves_on_graph`).

**The levels.** Every request to Jev costs, so a run asks only what it
needs. `--list` gives each level's total for the suite as it stands.

| Level | Runs | Jev answers |
| --- | --- | --- |
| `quick`, the default | The must scenarios (§4). `--only` also runs a named feel scenario, in full | Only the passes of steps whose `expect` is about a pass, unless whole-run `checks` read them all. The expect brain answers the setup in between, a step's own `brain` answers and the mood's path on the graph included |
| `standard` | Every scenario, once | Every pass |
| `full` | The same, `always` ones 3 times | Every pass |

A scenario's own `runs` (§3) holds at every level, and `--runs N` overrides
both. Each pass in the run's file says which brain answered it, and
`--timeline` marks the expect brain's. A scripted setup hides what Jev would
have done there: its moods and HISTORY are the scenario's, not Jev's. Quick
judges nothing, so it says only that the musts hold.

**Which to run.**

- A code-only change that leaves prompts unchanged: no Jev run.
- While working: `--only` on the scenarios the change touches.
- A change that touches steering or prompts broadly: quick.
- Before a branch merges: standard.
- Only when the owner asks, or before a release: full (`make eval`).

**The daily limit.** Evals may send Jev `JevAllowance.dailyLimit` real
requests a local day, across every command and worktree. The count is in
`~/.boopdev/jev-requests.json`. The expect brain's passes and the Boop app's
own don't count. A retry inside one answer isn't counted apart from it.
Before it asks Jev anything, `boopdev eval` counts each run's passes with
the expect brain (about right: what Jev answers can move a later pass or
two), and refuses the whole run if that's more than what's left, printing
used, left and the estimate. A run that reaches the limit partway stops,
drops the run it was in, reports the scenarios that finished, and exits 1. A file
that can't be read refuses too: with no count, no requests.

A whole full run is refused without `BOOP_JEV_OVER_LIMIT=1`, even when it
would fit in what's left; `--level full --only TEXT` isn't, while it fits.
The variable also goes past the limit, for that command, and the run's output
says so; its requests still count. `make eval` doesn't set it. An agent sets it only when the owner
says so in that request. The limit replaced the old budget per command.

| Flag | Does |
| --- | --- |
| `--level L` | `quick` (the default), `standard` or `full`, above |
| `--runs N` | Runs each scenario N times (default its own `runs`, else 1, or 3 for an `always` scenario at `full`). It passes only if every run does |
| `--only TEXT` | Only the scenarios whose name contains TEXT (any case) or whose file name does |
| `--always` | Only the `always` scenarios |
| `--timeline` | Prints every pass of every run: when, the line, what Boop did and the mood after |
| `--list` | Prints each scenario at the level with its file, name, runs, about how many requests a run sends, case, and whether it's `always` or a known gap, then all three levels' totals and today's count, and runs nothing |
| `--scripted` | Runs each scenario once with the expect brain: no key, no Jev requests |
| `--scenarios DIR`, `--steering DIR` | Other scenarios or steering files; by default the repo's, found from the working directory or from `boopdev`'s own place |

The report gives each scenario's verdict (`pass`, `FAIL`, or `GAP` for a
known gap), with how many runs passed (`2/3 runs`) when there's more than
one; for one that failed, its gap and case, then each failing step and
whole-run check once, with what was wanted and what came. Then it gives
how many scenarios passed in every run, and how many known gaps failed, the median and slowest latency against the pass's
deadline, and the requests the run really sent to Jev beside the estimate and today's count. It exits 1 if any
scenario failed that isn't a known gap.
Every event, view event and pass of every run goes to a file of its own
in `/tmp/boop-eval` (files over a day old are cleared), one JSON
object a line, each pass with its whole state. `--timeline` prints every
pass as the eval runs.

`EvalTests` checks the runner without Jev: every scenario file reads and
has a case, a scripted brain that answers as `04-tests-fight-back` wants
passes it, one that stays quiet fails `05-pokes-glad-miffed-grumpy` with the report
saying why, a step's `reaction` shows in HISTORY as in progress, or not
at all when it didn't happen, a scenario starts in its `mood` and a
step's `offered` is what its pass offered, and each whole-run check
catches what it should, `moves_on_graph` an answer that wasn't offered.
Every scenario passes with the expect brain and plays as a demo the pack
can play, a scenario's `start` shows in CONTEXT's When row, and its
`talk` shows that level's Talk row in CONTEXT (none for normal).

## 3. The scenario file

One JSON file per scenario in `characters/boop/evals/`, run in
file-name order:

`05-pokes-glad-miffed-grumpy.json`:

```json
{
  "name": "Pokes make Boop curious, then miffed, then fed up",
  "case": "The person pokes Boop once, again a second later, and a third time a second after that. The first poke makes Boop curious or glad: a curious or happy face, and its mood turns curious or happy. The second, two in a row, leaves it a little miffed: an annoyed face, maybe a huff, and its mood turns annoyed. The third, three in a row, makes it fed up: an irritated or grumpy face, maybe a grumble, never a swear, and its mood turns irritated or grumpy. Four minutes later, when the agent starts a new turn, it has calmed down a step, to annoyed (or irritated, from grumpy), and doesn't react to the start with anything but a calm or annoyed face.",
  "always": true,
  "why": "PERSONALITY's Examples and react.face: one poke gets a curious face, two in a row an annoyed huff, three or more an irritated or grumpy face. characters/boop/steering/mood/: a poke moves calm to happy or curious, two in a row to annoyed, three to irritated or, a jump a barrage earns, grumpy; irritated and grumpy fade a step toward calm after their minutes. The first two pokes' reactions don't hold back the third. Taps play the device's own animations, so no reaction plays one",
  "steps": [
    {"event": "session started", "at": "0s"},
    {"event": "poke", "at": "0s", "expect": {"react": "curious|happy|excited|mischievous|amused", "move": "none", "mood": "curious|happy", "said": "some"}},
    {"event": "poke", "at": "1s", "expect": {"react": "annoyed|irritated", "move": "none", "say": "upset|tickled", "mood": "annoyed", "said": "some"}},
    {"event": "poke", "at": "2s", "expect": {"react": "irritated|grumpy|annoyed", "move": "none", "say": "upset|tickled", "mood": "irritated|grumpy", "said": "some"}},
    {"event": "turn started", "at": "4m", "expect": {"react": "none|calm|annoyed", "mood": "annoyed|irritated"}}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `name` | What it checks, in a line |
| `judge`, `reasonable`, `unreasonable` | A feel scenario's brief, in place of `case` and `why`: what matters, a range of fine answers, and what would be wrong (§4). Its steps check no choice of Jev's |
| `case` | A must's situation and what Boop should do in it, in plain words and no harness terms, so the steps can be rewritten to fit it when the harness changes |
| `why` | A must's reason: the spec or steering file that says so |
| `always` | `true` for Boop's character (§1): 3 runs at the full level, and `--always` runs these |
| `scripted` | `true` for a scenario that checks the code's rules rather than Jev's choices (the mood kept on the graph, the screen's counts, which agent BOOT opens): it runs only with the expect brain, in `--scripted` and the unit tests, and a Jev run leaves it out. Never `always` |
| `runs` | How many runs it gets without `--runs`, at every level, when the default (§2) is too many or too few |
| `mood` | The mood the run starts in, any of the pack's moods: `calm` by default |
| `start` | When the run starts, a UTC date and time: `2026-10-31T09:00`. By default `Replay.defaultStart`, a Wednesday at 14:00 |
| `hatched` | The day Boop hatched, `2026-09-01`, for its milestone days (`Days`): none by default |
| `memory` | The written memory the run starts with, as Jev reads it in MEMORY: `notes`, each as `memory.md` writes it without its id (`work · 2026-10-25 · "api" kept failing`), and `recently`, each a day and its line (`2026-10-25 · a long day`): none by default |
| `gap` | A known gap (§1): why Boop can't pass it today, and what would fix it. Never on an `always` scenario |
| `checks` | Whole-run checks (§1), any of `max_quiet_working` and `no_mood_bounce_within` (times, like `6m`), `max_same_in_a_row` and `min_variety` (counts), `mood_changes` and `reactions` (ranges, like `1-3`), `words_said` (a range of shares, like `0.5-`), `moves_on_graph` (`true`), `moods_seen` (moods, like `lonely`) and `signs_seen` (signs, any one of them) |
| `talk` | `normal` (the default), `quiet` or `chatty`: how much it says, chosen in Settings |
| `steps[].event` | One of the steps in §1 |
| `steps[].at` | Virtual time since the start, in `h`, `m` and `s`: `0s`, `2m30s`, `1h5m` |
| `steps[].topic`, `failed` | A command's topic and whether it failed |
| `steps[].error` | A failed turn's error class |
| `steps[].prompt` | What the person asked, on a `turn started`. Jev never sees it: it reaches NOW as its reading, counted (its length, whether it says the buddy's name, a tone its words plainly show) and labelled with the step's `reading` |
| `steps[].reading` | What Apple Intelligence would make of the prompt, standing in for it: its `kind` (`fix`, `feature`, `cleanup`, `refactor`, `tests`, `deploy`, `docs`, `question`, `carry_on`, `other`), its `tone` (`calm`, `frustrated`, `rushed`, `polite`, `playful`, `shouting`, `careful`) and its `phrases`, kept only if they're in the prompt. On a `turn finished`, the same for its `message`, from the message's lists: its `kind` (`done`, `stuck`, `question`, `answer`, `other`) and `tone` (`calm`, `upbeat`, `apologetic`, `fawning`). `--labeler apple` reads both for real instead |
| `steps[].message` | The agent's last message, on a `turn finished`. Jev never sees it: it reaches NOW as its reading, in the finish's line (`…, 1 tool call, fawning.`), counted (a stock line, an apology, a plain claim of done or stuck, a question at its end) and labelled with the step's `reading`, with its phrases under `Its words:`. A failed turn has none, as with Claude's `StopFailure` |
| `steps[].workspace` | The thread's workspace, when it has one |
| `steps[].session` | Claude's session, `s1` unless it says: another session is another thread, working at the same time |
| `steps[].agent` | Whose step it is: `claude` (the default) or `codex`, whose hooks it then sends (a failed turn is Claude's alone: Codex has no hook for it) |
| `steps[].count` | How many pokes a `pokes` step makes, 4 unless it says |
| `steps[].todos` | A `to-do list` step's list, `3/7`: done, of all |
| `steps[].reaction` | How a Moment this step's passes start ends: `done` (the default), `in progress` (HISTORY keeps saying so), or `failed: <why>` (HISTORY leaves it out) |
| `steps[].brain` | The expect brain's answers for the step's passes, one choice a question as a demo's brain step has them (`{"react.face": "amused"}`), ahead of its `expect` |
| `steps[].expect.dream` | `told` when a pass of the step (a check-in's on the way included) answered the line that told the dream, `none` when none did |
| `steps[].expect.opens` | What a `press` opened, `agent thread` (`claude docs`), checked with no pass |
| `steps[].expect.idle`, `helpers`, `when`, `needs`, `todo`, `doing` | What the screen shows after the step, from the core's `state`, checked with no pass: how many sessions sit idle, how many helpers work (each a `\|` set of counts), tags that must all be on (`halloween\|morning`), whether the needs-you screen shows (`shown` or `none`), the working agent's to-do list (`3/7`, or `none`), and the Doing (`asleep`, `idle`, `working`) |
| `steps[].expect` | Any of `react` (the emotion), `move`, `intensity`, `say`, `said` (a take's text, or `some` or `none`), `mood`, `offered` and `sign`, each a `\|`-separated list |

A file with no `case`, an unknown key, event, personality, `expect` key
or check, a starting `mood`, or an expected `react`, `mood` or `offered`,
that isn't a mood (`none` is a `react` too), a `move`, `intensity` or
`say` that isn't one of its question's options or `none` (a `move` may
be a reply), a `said` that isn't a take's text, `some` or `none`, a bad
`at`, `reaction` or check value, a `prompt`, `reading` or `message` on a step that can't carry it, a
finish's `reading` with no `message`, a
`reading` whose kind or tone isn't one of its lists, or nothing
to check (no `expect` and no `checks`) doesn't load, and the error names
the file and step.

## 4. The scenarios

`boopdev eval --list` prints them all. They come in three groups. Pixel's
packs keep strict scenarios of their own, in their words: a scenario with no
brief is a must.

- **Code checks** (`53`, `68`, `69`, `92`, `93`, `115`–`117`, `164`, `166`, `168`):
  `scripted`, the code's rules, which need no Jev: the mood kept on the graph
  and the screen, one reaction at a long unlock, the nap asleep at once, a wish
  on offer with no agents open.
- **Must** (`03`, `17`, `24`, `27`, `36`, `40`, `43`, `61`, `122`, `123`, `126`,
  `127`, `129`, `136`, `139`, `143`, `150`, `155`): would be plain wrong, so
  exact checks stay. A failed turn is never celebrated, and neither is an agent
  giving up. No wrong face, and no swearing at the person. Talked to, Boop
  answers, and rightly about agents. Hush, Quiet and Chatty hold. The moments
  the owner loves stay. Never lonely after a night or while agents work, and
  never sad about a wish you couldn't answer.
- **Feel** (everything else): each has a brief, `judge`, `reasonable` and
  `unreasonable`. It checks no choice of Jev's, and a step's `brain` answers
  stand in for Jev where it isn't asked. What the code decides stays exact:
  the screen, what's offered, a dream told, moves on the graph, the quiet
  while working.

## 5. The judge

A run writes each scenario's trajectory beside its file in `/tmp/boop-eval`,
`….trajectories.jsonl`: per pass, the line Jev read, the mood, face, move, what
it said, the sign, the narration and which brain answered. A fresh Claude
session agent judges the feel ones against their briefs with
[judge/JUDGE.md](judge/JUDGE.md): reasonable, odd or unreasonable, with one line
why. It also looks across the runs for Boop going flat or passive, for sameness,
and for wishes made too often or never. It isn't an API call, it needs no key,
and nothing of it is in CI. It isn't whoever wrote the prompt, and it reads no
steering.

Jev runs each scenario once. A must's failed run gets one re-run from the
runner, and an unreasonable verdict gets one by `--only`, to confirm before it
blocks.

Test the judge before you trust it: `judge/test/runs.jsonl` is made-up runs,
some plainly wrong (Boop celebrating a failed turn), and `expected.json` says
which. If it passes a bad one, fix that first.
