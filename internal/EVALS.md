# Boop: harness evals

Updated 2026-11-01. How we check that Jev decides as Boop should: short
scenarios of agent work, run through the real pipeline (the transcript,
the core and the view), MellowHarness's `Harness` and Boop's outputs,
each pass checked against what it should come to.

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
that a reaction goes to a fake device, which answers at once with the
`ended` the step names, `done` unless it says otherwise (`reaction`,
§3), read as the app reads the device's (`Reactions`), so HISTORY shows
it as played. A step's
`failed: cut short: you tapped Boop` is the device's `cut` by a tap,
held as the app holds it: in progress while the pokes go on, done once
they stop; `failed: waited too long` is its `skipped`, `late`.

For each step it moves the clock a second at a time to the step's time,
ticking the pipeline as the app does, so heartbeats and other timers
fire on the way, and hands each tick's view events that wake the brain
to the harness at that tick, so a heartbeat is answered when it comes.
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
| `command` | A `tool` start of a `Bash` call with the step's `topic`, then its end at the same moment: `failed` as given (default false), with `error: exit_code` when it failed |
| `turn finished` | A `turn` end, `done` (`Stop`) |
| `turn failed` | A `turn` end, `failed` (`StopFailure`), with the step's `error` (default `api_error`) |
| `poke` | One poke from the device, a pass: steps a second apart make pokes in a row |
| `hush` | The app's Hush button: Boop says nothing for `Core.hushMs`, a pass (it may sulk) |
| `press` | BOOT, the board having handed you an agent: the core opens the next one in line (no pass; check it with `expect.opens`) |
| `ask answered` | The board ends the buddy's last question: `pick` `a` (the left answer, the default), `b`, `touch` (a stroke, its first answer) or `ignored`. Nothing when it asked nothing, so a step that expects a pass then fails |
| `gesture` | What you did to the board, its `kind` (`stroke`, `ruffle`, `swipe`, a quick stroke, `nose`, `tickle`, `dizzy`, `pickup`, `putdown`, `startle`, `facedown`, `peekaboo`), which it already reacted to: a line, as a poke. `dismiss` is a finger held on the needs-you screen: the request that shows stops showing (`Core.dismiss`, named by its number, as the board does), though its agent still waits |
| `to-do list` | The agent writes its to-do list, the step's `todos` (`3/7`: done, of all): a `TodoWrite` call's start with the counts, then its end |
| `edit` | An edit that removes the step's `count` lines (100 unless it says) and adds none, as the hooks count them: a turn's finish says `, 1,200 lines gone` once its edits removed 500 or more net |
| `helper started`, `helper returned` | The agent sends a helper off (`SubagentStart`), and it comes back (`SubagentStop`), the step's `helper` (`h1` unless it says) |
| `pokes` | Four pokes at once from the device (the step's `count`, if it says), each a pass: the step checks the last, `You poked Boop 4 times in a row.`; `while it slept` for a run's first poke with no session open, `, again` for a run within 2 minutes of the last |
| `said` | What you said on push-to-talk, the step's `words`, after the device's button: a `talk` event, `You said to Boop: "…"` |
| `away` | You lock the screen and leave: a `presence` start, `locked`, since this moment, `You stepped away from the Mac.`, which wakes no pass |
| `back` | You unlock it: a `presence` end, `unlocked`, `You came back to the Mac after a long break.` with the break's band since the last `away` |
| `session started` | A Claude session opens with no turn (`SessionStart`, `startup`): Boop is awake and idle, not asleep. No line, so no pass |
| `compact` | The agent's context is compacted (`SessionStart`, `compact`): `claude's context on "landing" was compacted; it picks up where it left off.` |
| `needs you` | Claude asks to run a command: a `Bash` call's start, then its `PermissionRequest`. While it waits nothing wakes the brain but what you say |
| `answered` | The call you allowed finishes (`PostToolUse`): "needs you" clears, `You answered claude on "landing".` |
| `wait` | Nothing; only time passes: a heartbeat may come, the working one while a turn works, an idle check-in every 15 to 30 minutes for two hours after the last activity while a session is open, else hourly, which wakes the brain only while the mood has somewhere to settle when Boop sleeps or you're away |

Every event is Claude's, in project `landing`, in session `s1` or the
step's `session`, with the step's `workspace` if it has one.

**The check.** A step with `expect` is checked against the last pass
woken on the way to it and by it, so a `wait` checks the heartbeat its
ticks brought: an idle one, or while a thread works, the working
heartbeat. Each expectation is a set of acceptable values (`proud|happy`), so
a scenario holds wherever more than one answer is right. For `react`,
`mood` and `say`, a leading `!` takes values away from everything the
key may be: `!none` is any face, `!lonely` any lasting mood but lonely,
`!swear` anything but a swear. Write the set the scenario means, not a
long list that checks little:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react.face` question: `none` or a mood's face |
| `move` | The move the reaction played, Jev's `react.move` pick: at an event a finish (`success`, `failure` or `reply`), `wake up`, or `notice`, when your prompt says its name; to what you said the reply (`huh` below the floor); or `none` when it played none or Boop didn't react |
| `intensity` | How big the moment was, Jev's `react.intensity` pick (`small` to `huge`: how long the face held and how big what it said), or `none` when `react` didn't react |
| `say` | What it asked to say, `say`'s pick when it reached the floor (a feeling, `swear` or a topic), or `none` |
| `sign` | The sign the reaction held up: for a prompt's reading Jev's `react.sign` pick, from the pack's `signs.md`; for what you said, Jev's `react.sign` pick among the reply's lines in the pack's `replies.md` (your words played back included) or, for `status`, the agents' facts (`StatusReply`). `some` for any, `none` for none, or words any of which it says, in any case (`still broken` passes `still broken :(`) |
| `said` | A take Boop said, by its text as the bubble shows it (`Tsk...`): the step passes when any of the `say`'s takes is one listed; `some` when it said anything, `none` when it said nothing. A scenario that names a text no take has doesn't load |
| `mood` | Boop's mood after the pass |
| `offered` | Exactly the options the pass's `mood` question offered, as a set: staying in the mood it had, and every move the graph has from it, so a scenario can pin the graph |

A step fails if its pass was dropped (late, or an error), or if any
expectation doesn't hold. A step with `expect` that wakes no pass stops
the whole eval as broken. The evals ask Jev, so they need its key and
fail without it.

**The whole-run checks.** A scenario's `checks` are judged over every
pass of a run, checked or not, for how lively Boop stays: an animated
Boop that doesn't sit on one look, repeat itself or flail. Each is loose, there to catch a clear failure,
and to be tightened once Boop meets it (`Eval.judge`):

| Check | Fails when |
| --- | --- |
| `max_quiet_working` | The turn runs longer than this with no reaction played, counted from its start or the last reaction to the next or its end |
| `max_same_in_a_row` | More reactions than this in a row are the same face, animation and take (however long each held) |
| `mood_changes` | The mood changes a number of times outside this range (`1-3`, `2-` for 2 or more, `-2` for 2 at most) |
| `no_mood_bounce_within` | A mood changes back to the one it just left sooner than this |
| `reactions` | The run plays a number of reactions outside this range |
| `min_variety` | The run plays fewer different reactions (face, animation and take) than this |
| `words_said` | The share of the reactions played that said something falls outside this range |
| `moves_on_graph` | A pass's `mood` answer wasn't one of the options it offered (or Jev gave none it could use), or the mood changed along something that isn't a move on the graph |
| `signs_seen` | None of the signs it names (`"fav snack?|hat or bow?"`) was held up at any pass: for what Jev does now and then, such as asking, not at a given step |
| `moods_seen` | A mood it names (`"lonely"`, or several, each required, `"lonely|sad"`) was never the mood at any pass: one that came and faded between two steps still counts |

**Always and gaps.** An `always` scenario is Boop's character, not a
tuning target: it runs 3 times by default, and every steering change
keeps it passing. A scenario with a `gap` is one Boop can't pass today,
with why and what would fix it: its failures are reported as `GAP` and
don't fail the eval, and when it passes in every run the report says to
take the gap out.

## 2. Running them

```sh
BOOP_JEV_KEY=… .build/debug/boopdev eval --only apology   # while developing: the scenarios you touched, under the budget
BOOP_JEV_KEY=… .build/debug/boopdev eval --only tests --timeline
BOOP_JEV_KEY=… make eval                     # the final pass: every scenario, 3 runs for always and 1 for the rest
.build/debug/boopdev eval --list             # every scenario's case, runs and requests; no key needed
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

**The API budget.** Every pass is one request to Jev, and a full
`make eval` is about 660 of them (`--list` counts them), so it's the
final pass before a commit, once. While developing, run the scenarios
the change is about with `--only`. Before it asks Jev anything,
`boopdev eval` counts each
run's passes with the scripted brain (about right: what Jev answers can
move a later pass or two), times its runs, prints the total, and stops
with the costliest scenarios if that's over the budget: 100 requests,
or `--budget N`. `make eval` passes `--no-budget`.

Repeat runs are for the scenarios that need them: an `always` one runs
3 times, since it's Boop's character and a flaky pass there matters;
the rest run once. A scenario can say its own `runs` (§3), as `53` says
1: it's long, and the code already holds its moves to the graph.

| Flag | Does |
| --- | --- |
| `--runs N` | Runs each scenario N times (default its own `runs`, else 3 for an `always` scenario and 1 for the rest). It passes only if every run does |
| `--budget N` | Stops before asking Jev if the run would send more than about N requests (default 100) |
| `--no-budget` | No budget: the final pass (`make eval`) |
| `--only TEXT` | Only the scenarios whose name contains TEXT (any case) or whose file name does |
| `--always` | Only the `always` scenarios |
| `--timeline` | Prints every pass of every run: when, the line, what Boop did and the mood after |
| `--list` | Prints each scenario's file, name, runs, about how many requests a run sends, case, and whether it's `always` or a known gap, then the total, and runs nothing |
| `--scripted` | Runs each scenario once with the expect brain: no key, no budget |
| `--scenarios DIR`, `--steering DIR` | Other scenarios or steering files; by default the repo's, found from the working directory or from `boopdev`'s own place |

The report gives each scenario's verdict (`pass`, `FAIL`, or `GAP` for a
known gap), with how many runs passed (`2/3 runs`) when there's more than
one; for one that failed, its gap and case, then each failing step and
whole-run check once, with what was wanted and what came. Then it gives
how many scenarios passed in every run, and how many known gaps failed, and the median and slowest latency against the pass's
deadline. It exits 1 if any
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
| `case` | The situation and what Boop should do in it, in plain words and no harness terms, so the steps can be rewritten to fit it when the harness changes. Required |
| `why` | The spec or steering file that says so |
| `always` | `true` for Boop's character (§1): 3 runs by default, and `--always` runs these |
| `scripted` | `true` for a scenario that checks the code's rules rather than Jev's choices (the mood kept on the graph, the screen's counts, which agent BOOT opens): it runs only with the expect brain, in `--scripted` and the unit tests, and a Jev run leaves it out. Never `always` |
| `runs` | How many runs it gets without `--runs`, when its kind's default (§2) is too many or too few |
| `mood` | The mood the run starts in, any of the pack's moods: `calm` by default |
| `start` | When the run starts, a UTC date and time: `2026-10-31T09:00`. By default `Replay.defaultStart`, a Wednesday at 14:00 |
| `hatched` | The day Boop hatched, `2026-09-01`, for its milestone days (`Occasions`): none by default |
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
| `steps[].reaction` | How a reaction this step's passes start ends: `done` (the default), `in progress` (HISTORY keeps saying so), or `failed: <why>` (HISTORY leaves it out) |
| `steps[].brain` | The expect brain's answers for the step's passes, one choice a question as a demo's brain step has them (`{"react.face": "amused"}`), ahead of its `expect` |
| `steps[].expect.dream` | `told` when a pass of the step (a heartbeat's on the way included) answered the line that told the dream, `none` when none did |
| `steps[].expect.opens` | What a `press` opened, `agent thread` (`claude docs`), checked with no pass |
| `steps[].expect.idle`, `helpers`, `when`, `needs`, `todo` | What the screen shows after the step, from the core's `state`, checked with no pass: how many sessions sit idle, how many helpers work (each a `\|` set of counts), tags that must all be on (`halloween\|morning`), whether the needs-you screen shows (`shown` or `none`), and the working agent's to-do list (`3/7`, or `none`) |
| `steps[].expect` | Any of `react` (the face), `move`, `intensity`, `say`, `said` (a take's text, or `some` or `none`), `mood`, `offered` and `sign`, each a `\|`-separated list |

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

Each scenario's file says what it checks, in its `case`, so the list
lives there: `boopdev eval --list` prints them all. They come in four
kinds, all with the `boop` personality unless the file says otherwise:

- **Always** (`03`–`06`, `08`, `09`, `13`, `16`, `17`, `23`, `27`–`29`,
  `36`, `39`, `40`, `43`, `47`, `61`, `63`, `64`, `127`–`130`, `132`–`136`, `138`, `140`): Boop's character. It never swears
  at a win, a poke or the person (`16`, `61`). A failed check puts it
  out and the next makes it determined, the fix proud; a failed turn
  puts it out, a very long one failed makes it sad; a very long turn
  done is a success; poking it again and again makes it irritated or
  grumpy and keeps it so while it goes on, with one face per barrage,
  and it calms down a step at a time after; moods fade a step toward
  calm once their minutes are up, at the first check-in (`06`) or at
  whatever comes next, a win too (`13`, `47`); plain requests,
  matter-of-fact finishes and a streak of quick wins leave the mood
  alone, whatever faces they get (`28`);
  no face ever contradicts what happened; talked to, it always answers
  with a face and a reply (`36`, `39`, `40`),
  and asked about the agents it holds up what they're really doing, how
  long, a check's result, done, how many work and rest when asked about
  them all, or all quiet, never a guessed yes or no (`127`), and a
  reply's sign fits the moment: a nap after the work while claude works,
  "that's ur job" when you'd have it answer claude for you, a huffy
  "...fine" when you say sorry after an insult, and what claude is doing
  or how long you've been at it when you ask (`128`); told to hush, it
  says nothing for the half hour, still making faces, sulks a step, and
  talks again when the time's up or you say so (`129`); talked to, it
  mostly says something back, and its sign answers your words: "good,
  u?" to how are you, "right here!" to where are you, your good night
  played back (`130`); each
  finish is judged by what it says, done and working a success,
  couldn't finish or a failed turn a failure however upbeat its message
  (`27`, `29`, `43`); and its mood only moves along
  the graph, a step at a time (`05`, `47`); and coming back to the
  Mac, after ten minutes or hours, a night's sleep included, it cheers,
  glad to see you (`63`, `64`, `136`; a shorter break never reaches it),
  and after a day away it missed you: lonely, until a stroke or a word
  ends it at once (`135`).
- **Tuning** (`10`–`12`, `15`, `18`, `19`, `21`, `22`, `24`–`26`,
  `44`–`46`, `48`, `50`, `51`, `54`–`60`, `62`, `65`, `70`, `74`–`77`, `79`, `85`, `90`, `91`,
  `94`–`97`, `99`–`114`, `118`–`126`, `131`, `137`, `139`, `141`–`148`, `150`): single decisions (a failure that really stings swears, `60`; and Boop picks a face
  that can say what it means, at a failed check and at a finish, `62`),
  at the Mac for hours with no touch or word to it, Boop grows lonely,
  and a word ends it, `137`; with the memory of a long fight, its end is
  big, `138`, and a memory never turns a failure into a success, `139`),
  and the liveliness brief: Boop reacts often (every quick win, `19`;
  most of a busy half hour, `21`), never goes over 6 minutes of work
  with no reaction, even while another thread's quick turns keep waking
  the brain (`18`, `21`, `22`), and its mood drifts (calm → engaged →
  determined → excited), never flipping back within a minute; in a long
  grind it may ease back and return (`18`, `51`). Runs are ladders, not
  repeats: a streak of quick wins climbs from happy to excited to amused
  to comfy and round again (`19`), a round of check-ins on a long turn
  from engaged to hopeful to bored to determined (`85`), and a busy half hour never plays the same
  reaction three times running (`21`, `22`). The
  moods the words bring (`24`–`27`): a frustrated request annoyed, a
  step toward determined, thanks excited, a long turn's hard work done
  proud, an agent giving up sad. The finishes: a question back or an
  answer is a reply (`44`, `45`), and a finish is judged by its words
  whatever the mood (`46`). And the graph's moves: a small failure from
  calm is a small step and a big one may jump (`48`), thanks bring a
  sad or wounded Boop back (`50`), an
  irritated Boop answers as irritated, not grumpy (`54`), and hours of
  nothing fade excited through happy to calm (`55`). And talk moves
  the mood at once: one apology
  softens a fed-up Boop a step (`56`), a second is fair only after
  poking it again (`57`), sad news makes it sad and keeps it so until
  it's taken back, when it switches (`58`), and a plain question
  softens nothing (`59`). And work that finished while you were away
  from the Mac is celebrated as it ends, never replayed when you're
  back, when Boop cheers to see you (`65`). And, scripted, the rarer
  moods: quiet takes a surprised Boop at most an ordinary step (`68`), and
  new work moves a comfy one only to a mood on offer (`69`). And
  the ladder of failure: a failure after a fix is a bigger cuss than
  the first, held longer and said aloud (`70`). And the moments the view now says: you answering a request
  gets a small pleased face (`74`), a compacted context leaves Boop a
  little lost (`75`), idle check-ins get a small face or nothing
  (`76`), a poke while it sleeps startles it (`77`), and a barrage
  again gets a louder grumble (`16`); quiet fades an excited Boop a
  step at a time (`55`). And a Codex turn gets the same small
  cheer as Claude's (`14`). On an occasion CONTEXT's
  When row names, Boop plays along when you come back: on
  Halloween (`90`) and on its 50th day (`91`), a gladder, bigger hello,
  and the screen has the day's tags; on April Fools' Day it may play a
  good finish as a failure, for the joke (`98`). Its opinions: a please
  warms it (`94`), capitals make it flinch (`95`), an agent's "You're
  absolutely right!" gets an eye-roll (`96`). Once its day is over at
  5:00, it tells its dream about it the first time you show up, never to
  an agent's event while you're away, and only once (`97`). Touched like a
  pet: a stroke calms a fed-up Boop, a shake startles it, and a
  swipe, a quick stroke, is a stroke too (`99`); shakes in a row go
  from a startled whoa to cross, as pokes do (`151`). And, scripted, the screen with no pass: BOOT
  walks the line, who needs you first, then the newest idle (`92`), and
  the helpers and idle agents are counted under the face (`93`); a
  request still shows after a two-hour lunch, since its agent still
  runs, and a finger held on the needs-you screen dismisses it
  (`115`); a long turn and the quiet after it go through their tiers
  (`116`); and the to-do count under the face climbs with the list
  (`117`). And Boop meets the routine in silence: a plain prompt a
  minute after it reacted, in another thread, gets a small face that
  says nothing (`118`), though a frustrated one gets a face and its words
  however recently it reacted (`119`), and a turn done in seconds is
  back-and-forth, its finish played in silence, though one failed as
  quickly still gets its failure (`120`); in a busy stretch of several
  agents, plain prompts each a paragraph with a few of your words under
  it get at most a small face, with nothing said and no sign, while the
  polite and playful ones around them still get theirs (`121`). And
  how much it says, chosen in Settings: on Quiet routine work and
  finishes go by in silence and a bigger moment gets only a feeling,
  which the engine holds to in code (`122`), on
  Chatty almost every face comes with words and every prompt gets one
  (`123`), and on Normal a routine moment gets one small thing said (`124`). A turn that finally worked after its tests failed
  twice is a hard-won finish: a success, proud, held three or four times
  (`125`), which the gel plays big. And what you say gets the reply that
  answers what you meant: a hello, to a greeting that asks how it's
  going too, yes to a question about Boop itself, thanks at praise and
  at your own good news, love at affection and at a sorry, ouch at an
  insult, comfort at bad news or tiredness, hehe at a joke, huh at what
  it can't know or at nonsense, a nap or a dance when asked (or no, to a
  trick it won't do), notme when asked to answer an agent for you, bye,
  and status for a question about the agents, how many are running
  included, each with a face, a second thing said while it still makes
  its face for the first included (`126`).

Pixel has five scenarios of its own, in `characters/pixel/evals/`, in
its words and with its steering: a failed turn, pokes, a long finish,
back after a break and an idle check-in. PixelBuddy's `make eval` runs
them (`boopdev eval` reads the pack in use's scenarios and steering), or
from here `CHARACTER=pixel .build/debug/boopdev eval --runs 1`, once
each, about 18 requests.
- **Scripted** (`53`, `68`, `69`, `92`, `93`, `115`–`117`): the code's
  rules, which need no Jev: the mood kept on the graph through a busy
  day (`53`) and from the rarer moods (`68`, `69`), and the screen. They
  run only with the expect brain (§3, `scripted`).
- **Known gaps** (`14`, `20`, `98`, `149`): a few minutes' turn done is
  sometimes played big, flipping tests don't flip the mood, April Fools'
  Day gets no joke, and a cuddly Boop's lean to affectionate doesn't
  show. Each `gap` says why the steering can't get there alone.

A new decision or a change to the steering files gets a scenario that
shows it. Run the scenarios it touches with `--only` while you work, and
`make eval` once, as the final pass, before it's committed (§2).
