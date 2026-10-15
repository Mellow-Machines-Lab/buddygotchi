# Boop: harness evals

Updated 2026-10-15. How we check that Jev decides as Boop should: short
scenarios of agent work, run through the real pipeline (the transcript,
the core and the view), MellowHarness's `Harness` and Boop's outputs,
each pass checked against what it should come to.

The mood question offers staying and every move from the mood on the
pack's graph ([characters/CHARACTER.md](../characters/CHARACTER.md) §5),
and how long a mood holds is the steering's.

## 1. What an eval is

A scenario is a few hook-level steps on a virtual clock. Each run starts
fresh: a new core and view, an empty transcript kept in memory, and the
scenario's mood (`calm`, the resting mood, unless the file says), set as
the dashboard would set it just before the first step, so HISTORY can
say how long Boop has been in it. The runner (`Eval` in
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
Wednesday 14:00 UTC and stands still while Jev answers.

| Step | Fed to the pipeline as (the transcript's raw events) |
| --- | --- |
| `turn started` | A `turn` start (`UserPromptSubmit`) |
| `command` | A `tool` start of a `Bash` call with the step's `topic`, then its end at the same moment: `failed` as given (default false), with `error: exit_code` when it failed |
| `turn finished` | A `turn` end, `done` (`Stop`) |
| `turn failed` | A `turn` end, `failed` (`StopFailure`), with the step's `error` (default `api_error`) |
| `poke` | One poke from the device, a pass: steps a second apart make pokes in a row |
| `pokes` | Four pokes at once from the device, each a pass: the step checks the last, `You poked Boop 4 times in a row.` |
| `said` | What you said on push-to-talk, the step's `words`, after the device's button: a `talk` event, `You said to Boop: "…"` |
| `away` | You lock the screen and leave: a `presence` start, `locked`, since this moment, `You stepped away from the Mac.`, which wakes no pass |
| `back` | You unlock it: a `presence` end, `unlocked`, `You came back to the Mac after a long break.` with the break's band since the last `away` |
| `wait` | Nothing; only time passes |

Every event is Claude's, in project `landing`, in session `s1` or the
step's `session`, with the step's `workspace` if it has one.

**The check.** A step with `expect` is checked against the last pass
woken on the way to it and by it, so a `wait` checks the heartbeat its
ticks brought: an idle one, or while a thread works, the working
heartbeat. Each expectation is a set of acceptable values (`proud|happy`), so
a scenario holds wherever more than one answer is right:

| Checked | Against |
| --- | --- |
| `react` | Jev's pick for the `react.mood` question: `none` or a mood's face |
| `animation` | The finish the reaction played, Jev's `react.animation` pick (`success`, `failure` or `reply`), or `none` when it played none or Boop didn't react |
| `feeling` | How Boop felt, `say.feeling`'s pick when it reached the floor, or `none` |
| `about` | What NOW was about, `say.about`'s pick when it reached the floor, or `none` |
| `kind` | How it asked to say it, `say.kind`'s pick (`sound` when missing), or `none` when `react` didn't react |
| `said` | A take Boop said, by its text as the bubble shows it (`Tsk...`): the step passes when any of the `say`'s takes is one listed; `some` when it said anything, `none` when it said nothing. A scenario that names a text no take has doesn't load |
| `loops` | How long the face held, Jev's `react.loops` pick (`once` to `four times`), or `none` when `react` didn't react |
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
| `moves_on_graph` | A pass's `mood` answer wasn't one of the options it offered (or Jev gave none it could use), or the mood changed along something that isn't a move on the graph |

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
```

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

## 3. The scenario file

One JSON file per scenario in `characters/boop/evals/`, run in
file-name order:

`05-pokes-glad-miffed-grumpy.json`:

```json
{
  "name": "Pokes make Boop curious, then miffed, then fed up",
  "case": "The person pokes Boop once, again a second later, and a third time a second after that. The first poke makes Boop curious or glad: a curious or happy face, and its mood turns curious or happy. The second, two in a row, leaves it a little miffed: an annoyed face, maybe a huff, and its mood turns annoyed. The third, three in a row, makes it fed up: an irritated or grumpy face, maybe a grumble, never a swear, and its mood turns irritated or grumpy. Four minutes later, when the agent starts a new turn, it has calmed down a step, to annoyed (or irritated, from grumpy), and doesn't react to the start with anything but a calm or annoyed face.",
  "always": true,
  "why": "PERSONALITY's Examples and the react question: one poke gets a curious face, two in a row an annoyed huff, three or more an irritated or grumpy face. characters/boop/steering/mood/: a poke moves calm to happy or curious, two in a row to annoyed, three to irritated or, a jump a barrage earns, grumpy; irritated and grumpy fade a step toward calm after their minutes. The first two pokes' reactions don't hold back the third. Taps play the device's own animations, so no reaction plays one",
  "steps": [
    {"event": "poke", "at": "0s", "expect": {"react": "curious|happy|excited", "animation": "none", "mood": "curious|happy"}},
    {"event": "poke", "at": "1s", "expect": {"react": "annoyed|irritated", "animation": "none", "feeling": "upset|tickled|none", "kind": "sound|word|phrase", "mood": "annoyed"}},
    {"event": "poke", "at": "2s", "expect": {"react": "irritated|grumpy|annoyed", "animation": "none", "feeling": "upset|tickled|none", "kind": "sound|word|phrase", "mood": "irritated|grumpy"}},
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
| `runs` | How many runs it gets without `--runs`, when its kind's default (§2) is too many or too few |
| `mood` | The mood the run starts in, any of the pack's moods: `calm` by default |
| `gap` | A known gap (§1): why Boop can't pass it today, and what would fix it. Never on an `always` scenario |
| `checks` | Whole-run checks (§1), any of `max_quiet_working` and `no_mood_bounce_within` (times, like `6m`), `max_same_in_a_row` and `min_variety` (counts), `mood_changes` and `reactions` (ranges, like `1-3`), and `moves_on_graph` (`true`) |
| `personality` | `boop` (the default) or `chatter` |
| `steps[].event` | One of the steps in §1 |
| `steps[].at` | Virtual time since the start, in `h`, `m` and `s`: `0s`, `2m30s`, `1h5m` |
| `steps[].topic`, `failed` | A command's topic and whether it failed |
| `steps[].error` | A failed turn's error class |
| `steps[].prompt` | What the person asked, on a `turn started`: NOW's `You asked:` note |
| `steps[].message` | The agent's last message, on a `turn finished`: NOW's `Its last message:` note. A failed turn has none, as with Claude's `StopFailure` |
| `steps[].workspace` | The thread's workspace, when it has one |
| `steps[].session` | Claude's session, `s1` unless it says: another session is another thread, working at the same time |
| `steps[].reaction` | How a reaction this step's passes start ends: `done` (the default), `in progress` (HISTORY keeps saying so), or `failed: <why>` (HISTORY leaves it out) |
| `steps[].expect` | Any of `react`, `animation`, `feeling`, `about`, `kind`, `said`, `loops`, `mood` and `offered`, each a `\|`-separated list |

A file with no `case`, an unknown key, event, personality, `expect` key
or check, a starting `mood`, or an expected `react`, `mood` or `offered`,
that isn't a mood (`none` is a `react` too), an `animation` that isn't
`none`, `success`, `failure` or `reply`, a bad `at`, `reaction` or check
value, a `prompt` or `message` on a step that can't carry it, or nothing
to check (no `expect` and no `checks`) doesn't load, and the error names
the file and step.

## 4. The scenarios

Each scenario's file says what it checks, in its `case`, so the list
lives there: `boopdev eval --list` prints them all. They come in three
kinds, all with the `boop` personality unless the file says otherwise:

- **Always** (`02`–`06`, `08`, `09`, `13`, `16`, `17`, `23`, `28`,
  `35`–`43`, `47`, `49`, `53`, `61`, `63`, `64`): Boop's character. It never swears
  at a win, a poke or the person (`16`, `61`). A failed check puts it
  out and the next makes it determined, the fix proud; a failed turn
  puts it out, a very long one failed makes it sad; a very long turn
  done is a success; poking it again and again makes it irritated or
  grumpy and keeps it so while it goes on, with one face per barrage,
  and it calms down a step at a time after; moods fade a step toward
  calm; plain requests and matter-of-fact finishes leave the mood alone;
  no face ever contradicts what happened; talked to, it always answers
  with a face (`35`–`40`); each finish is judged by what it says, done
  and working a success, couldn't finish or a failed turn a failure
  however upbeat its message (`41`–`43`); and its mood only moves along
  the graph, a step at a time (`47`, `49`, `53`); and coming back to the
  Mac, after ten minutes or hours, it cheers, glad to see you (`63`,
  `64`; a shorter break never reaches it).
- **Tuning** (`01`, `07`, `10`–`12`, `14`, `15`, `18`, `19`, `21`,
  `22`, `24`–`27`, `29`, `44`–`46`, `48`, `50`–`52`, `54`–`60`,
  `62`, `65`, `68`, `69`): single decisions (a long turn done says it went well,
  `29`; a failure that really stings swears, `60`; and Boop picks a face
  that can say what it means, at a failed check and at a finish, `62`),
  and the liveliness brief: Boop reacts often (every quick win, `19`;
  most of a busy half hour, `21`), never goes over 6 minutes of work
  with no reaction, even while another thread's quick turns keep waking
  the brain (`18`, `21`, `22`), and its mood drifts (calm → engaged →
  determined → excited), never flipping back within a minute; in a long
  grind it may ease back and return (`18`, `51`). Repeats are fine. The
  moods the words bring (`24`–`27`): a frustrated request annoyed, a
  step toward determined, thanks excited, a long turn's hard work done
  proud, an agent giving up sad. The finishes: a question back or an
  answer is a reply (`44`, `45`), and a finish is judged by its words
  whatever the mood (`46`). And the graph's moves: a small failure from
  calm is a small step and a big one may jump (`48`), thanks bring a
  whiny or wounded Boop back (`50`), routine work holds calm (`52`), an
  irritated Boop answers as irritated, not grumpy (`54`), and hours of
  nothing fade excited through happy to calm (`55`). And talk moves
  the mood at once: one apology
  softens a fed-up Boop a step (`56`), a second is fair only after
  poking it again (`57`), sad news makes it sad and keeps it so until
  it's taken back, when it switches (`58`), and a plain question
  softens nothing (`59`). And work that finished while you were away
  from the Mac is celebrated as it ends, never replayed when you're
  back, when Boop cheers to see you (`65`). And the rarer
  moods: quiet takes a frightened Boop at most an ordinary step (`68`), and
  new work moves a comfy one only to a mood on offer (`69`).
- **Known gaps** (`20`): flipping tests don't flip the mood. Its `gap`
  says why the steering can't get there alone.

A new decision or a change to the steering files gets a scenario that
shows it. Run the scenarios it touches with `--only` while you work, and
`make eval` once, as the final pass, before it's committed (§2).

## 5. The working day

The scenarios check single decisions; the working day checks how they
add up over a day: how often Boop's mood changes, whether a routine
line changes it, and how often, and with which faces, Boop reacts.
`boopctl workday` replays a scripted 8-hour day
through the whole headless app and Jev on a compressed clock, in about
five minutes:

```sh
make build
BOOP_JEV_KEY=… internal/tools/boopctl workday run --state /tmp/tn-1 --out /tmp/tn-out/1
internal/tools/boopctl workday report /tmp/tn-out/1/debug.jsonl /tmp/tn-out/2/debug.jsonl
internal/tools/boopctl workday check /tmp/tn-out/1/debug.jsonl
internal/tools/boopctl workday plan    # the day's story
```

**The day** (`--seed 1` by default; the seed only moves lengths and
gaps) runs from 09:00 to about 17:40: about 190 turns on four threads
(Claude on `api`, and on `fix-nav` and `docs` in `landing`; Codex on
`boop`), mostly routine turns of seconds to a few minutes, with two
approvals; tests failing three times, then passing, in a 9-minute turn;
a turn failing on a rate limit; a 22-minute turn whose build fails once
and comes back; a stopped turn; lunch, over an hour with nothing, for
the heartbeat; a build failing twice, then passing; four pokes in a
row, and later two more runs of four a minute and a half apart; a 14-minute turn ending with its
tests still failing, and the next turn fixing them; a coffee break; an
hour of quick wins with an API error and a passing deploy; and a
16-minute docs turn. An hour of nothing after it brings the evening's
heartbeat.

**The run** starts `Boop --headless --brain jev --debug` with a fresh
state directory and a fake device on a Unix socket (`--link usb:`) that
says hello as Boop's device does and each `do` played to the end, so HISTORY reads as
it would with a board, and whose taps make the pokes. It moves
the app's clock to 09:00 the next morning, sends each step's hook straight
to the app's socket in `agent-hook`'s wire form, moves the clock between
them with `{"dev":"advance"}` (a minute at a time over a long gap, so the
heartbeat comes when it would), and waits for every pass and the brain's
reactions to end before the next step, so no view event waits behind
Jev (a rule's needs-you, which lasts until the day answers the request
steps later, isn't waited for). `--brain
scripted` runs it without a key, and `--personality chatter` with the
other text.

**The report** reads `debug.jsonl` as `boopctl day` and the dashboard
do: a mood change's new mood and a reaction's face, finish and hold from
the answers of the pass it ran for, and what it said from the takes its
output recorded, never
from an output's message. It gives, for each hour of the app's clock: turns ended,
passes (and how many dropped), mood changes, with those on a routine
step (a turn start, or a finish done under 5 minutes) split into back
to calm, the resting mood (a mood fading, as the guide says), and any
other (which a routine step shouldn't cause); and reactions, as reacted/all for each
kind of step that woke the brain: notable (a failure, a fix, a failed or
stopped turn, a turn of 5 minutes or more, a poke), a finish
done in 1 to 5 minutes, one under a minute, a turn start, and a
heartbeat; and the faces used. Then how long the reactions held and
the takes they said over the day (`none` for a reaction that said
nothing), how long each mood
lasted, and every mood change with the step that brought it. `--json`
gives all that and every reaction.

**Liveliness.** The report also gives, for the day: the longest stretch
of work (any agent in a turn) with no reaction, and how many went over
6 minutes; reactions per turn ended; how many reactions were the same
as the one before, and the longest run of the same (reported, with no
limit: repeats are fine); mood bounces (a mood changing back to the one
it left within a minute); and the longest stretch of work with Boop
calm, the resting mood, all through. `boopctl workday check FILE…` holds each run to loose
limits (`LIMITS` in `internal/tools/boopctl_lib/workday.py`) and exits 1 if one fails:

| Limit | Holds |
| --- | --- |
| `longest_quiet_min` | 8 at most |
| `quiet_over_6_min` | 3 at most |
| `min_reactions_per_turn` | 0.8 at least (reactions over turns ended) |
| `mood_bounces` | 1 at most |
| `min_mood_changes` | 10 at least |
| `longest_rest_working_min` | 45 at most |

```sh
internal/tools/boopctl workday check /tmp/tn-out/1/debug.jsonl
```

Jev is stochastic, so run each side of a change at least twice. Warm it
up on new steering first with a whole `boopdev eval --runs 1
--no-budget` (one scenario warms only the moods it passes through): its
first passes on text it hasn't seen can go over the deadline (1500 ms,
MellowHarness's `Harness.Options.deadlineMs`) and drop. A few can drop in
a run that is warm too, so compare runs by their dropped passes as well.

`internal/tools/boopctl_lib/tests/test_workday.py` checks the day and
the report without the app (`make -C internal tools-test`).
