# Demos

Updated 2026-10-26. A demo is a short, scripted stretch of work that a
character lives through: an agent gets a task, you poke and talk to the
creature, and it reacts. Use demos to record videos, to show the
creature off, and to check that everything works end to end.

One script plays four ways: in the simulator's page, on a real board,
with Claude Code or Codex replayed in a terminal, and with your real
Claude in the desktop app. The script is the same in each.

## Write one

1. Make `characters/<pack>/demo/<name>.jsonl`. Copy a short one to
   start, such as `characters/pixel/demo/hello.jsonl`.
2. Write one step, a line of the file, for each thing that happens
   (below).
3. Check it: `.build/debug/boopdev check` (after `make -C internal build`). It
   names each step the pack can't play, and the choices it can.
4. Record it: `make -C internal demos`. It records every demo whose
   script has changed since its recording, or has none, into
   `characters/<pack>/demo/recordings/<name>.json` (below, The same every
   time). Commit the recording with the script:
   `make -C internal tools-test` and CI fail until you do.
5. Watch it: `make demo NAME=<name>`.

This is all of `hello.jsonl`:

```json
// Half a minute: a read, an approved test run, done. A quick check that a demo plays end to end.
{"demo": 1, "title": "Run the tests"}
{"agent": "prompt", "text": "Run the tests"}
{"brain": {"react.face": "curious", "say": "start", "react.intensity": "medium"}}
{"agent": "read", "file": "README.md", "say": "Let me look at the project first."}
{"agent": "run", "cmd": "npm test", "about": "Run the tests", "ask": 2, "say": "I'll run the tests."}
{"agent": "reply", "text": "The one test passes."}
{"brain": {"react.face": "proud", "react.move": "success", "say": "done", "react.intensity": "medium"}, "mood": "proud"}
```

## Steps

Each line of the file is one JSON object. A line that starts with `//`
is a comment. The first line may be a header: `{"demo": 1, "title": "…"}`, and
`"agent": "codex"` if the script is Codex's (Claude is the default), and
`"start": "2026-10-31T09:00"` to start the demo's clock at that date and
time on the Mac playing it (a morning, a Friday, a holiday).

Every other line is a step, by one of three: the agent, you, or the
creature's brain.

| Step | What it does | Keys |
| --- | --- | --- |
| `{"agent": "prompt"}` | You give the agent its task | `text`; `reading`, what Apple Intelligence would make of it (`kind`, `tone`, `phrases`), so it reads the same on any Mac |
| `{"agent": "read"}` | The agent reads a file | `file` |
| `{"agent": "edit"}` | The agent edits a file: its size in lines, as agent-hook counts it from `old` and `new`, is the work stream's word (`edit +2 -140`) | `file`, `old`, `new` |
| `{"agent": "run"}` | The agent runs a command, tagged as agent-hook tags it (a check's topic, or `inspect` for one that only looks) | `cmd`, `about` (what it's for), `fails` (true or false), `ask` (it asks you first, and you allow it after this many seconds), `waits` (true: the step ends as it asks, and the steps after it play while it waits, such as a `hold`) |
| `{"agent": "todo"}` | The agent writes its to-do list (Claude's `TodoWrite`, Codex's `update_plan`): the line under the face counts it | `todos`, done of all (`"2/4"`) |
| `{"agent": "review"}` | The agent sends a subagent: a helper at work (on Pixel, a mini under the face) until a `reply` `"by": "reviewer"` brings the first one still out back. Claude's only: Codex's hooks report no helpers | `task`, `prompt` |
| `{"agent": "compact"}` | The agent's context is full, so it compacts the conversation and goes on | `summary` (what its model writes of the work so far; required) |
| `{"agent": "reply"}` | The agent's turn ends with this message, which Boop reads as it reads any agent's last message: only its reading reaches the brain | `text`, `fails` (the turn failed: Claude's `StopFailure`; Codex has none) |
| `{"you": "poke"}` | You tap the creature | |
| `{"you": "press"}` | You press BOOT while an agent waits for you or sits idle: the board hands you the next one, and it opens on the Mac | |
| `{"you": "hold"}` | You hold a finger on the needs-you screen for a second: the screen goes, though the agent still waits, and its next request shows again | |
| `{"you": "talk"}` | You hold the talk button, then it hears `text` | `text`, `hold` (seconds, 1.5) |
| `{"you": "back"}` | You come back to the Mac after `minutes` away: the clock jumps on by that long, as a `wait`'s does | `minutes` (60) |
| `{"you": "wait"}` | `minutes` pass at once: the demo's clock jumps on (headless Boop's, which every `make demo` plays on), so a long turn reaches its tiers (the headphones at 2 minutes, the melt at 5, the mugs stacking up at 10) and the quiet after it its own. The agent's process, one made up for each session, runs all through the demo, as its hooks say, so a request still waits however long passes, up to a silent day | `minutes` |
| `{"brain": {…}}` | How the creature reacts to the step above | the answers; `mood` sets its mood. After a prompt, `react.sign` is the caption it holds up, one its `signs.md` offers for the prompt's reading. After a `talk`, `react.move` is its reply (`hello`, `status`, `nap`…): the board plays the reply's clip, and its sign is `react.sign`, one of the pack's `replies.md` lines for that reply, else one looked up, or, for `status`, what the demo's agents are really doing, and asked about all of several, the board shows them in its drawer |
| `{"mood": "proud"}` | The creature's mood changes | |

On any agent step, `say` is what the agent says before it acts,
`"by": "reviewer"` makes it the subagent's step, and `"session": "docs"`
makes it another session's of the same agent: a thread of its own,
working beside the first, started before its first step. A demo plays
several agents at once this way.

**Any eval is a demo too.** `boopdev eval --to-demo DIR` writes each of
the pack's eval scenarios as a script (a `needs you` becomes a run that
`waits`, a held finger a `hold`, a to-do list a `todo`), its brain
steps the answers the scenario expects ([internal/EVALS.md](../internal/EVALS.md) §2), so
`make demo` can play what an eval checks.

**A compact** comes in the middle of a turn, after the prompt and before
the reply, with more of the agent's steps after it. It needs its
`summary` and has no `say`: the context is full before the model can
speak, so put the words on the step after it. Every agent says the same
when it has compacted, and the rules show it: the creature shows its
compacted card, and a reaction after it waits on the board until the card
has played. With no agent, Boop sends that hook. A replayed Claude Code or
Codex compacts for real, and its model writes the `summary`. The desktop
app can't play a compact, since its real model can't be made to fill its
context on cue.

A back records the away, moves the clock on by the time away, then
records the back, as the Mac would after that long: being away shows
nothing on the board (no check-in greets the empty chair), and the
Mac's own keys and mouse would end an away left open. `good-morning.jsonl` comes
back after a night away, and Pixel wakes up.

**Timing.** Steps happen in order. `after` is how many seconds a step
waits after the one before it ends. An agent step also `takes` some
seconds. Without them, each takes about as long as it would.

**Captions.** Any step can have a `note`: words for the viewer that
replace the words Boop makes from the step ("You poke Pixel three times
while it's busy").

A key that a step doesn't take, or a value of the wrong type, stops the
demo with its line number. So does a brain answer the pack can't play.

**Two buddies or more.** A header with `buddies` plays on several
buddies side by side, each a board with its own pack, and each step
with `"buddy": PLACE` is that buddy's: its agent's step, a poke on its
board, talk to it alone, or its brain's answers. A step with no `buddy`
is the first's, and talk with none goes to them all. Each buddy is
written as `settings.json`'s `buddies` are: its `place`, its `pack`,
its `agents` (the first is whose hooks its steps are, `claude` by
default, in a session of its own) and maybe its `name`. Boop's
`not-my-turn.jsonl` is one:

```json
{"demo": 1, "title": "Not my turn", "buddies": [{"place": "left", "pack": "pixel", "agents": ["claude"]}, {"place": "right", "pack": "boop", "agents": ["codex"]}]}
{"agent": "prompt", "buddy": "left", "text": "Add a dark mode toggle"}
{"brain": {"react.face": "curious", "say": "start", "react.intensity": "medium"}, "buddy": "left"}
```

`make demo NAME=not-my-turn` plays it live on two simulated boards, side
by side in the page, each on its own cable
([simulator/README.md](../simulator/README.md)). A demo of several
buddies has no recording.

A live agent plays only a script of one buddy.

## The brain's answers

A demo has no real brain. The creature does only what the rules do
(working, needs you, done) and what the script's brain steps say. Put a
brain step where a real brain would be asked: a turn that starts or
ends, a poke, talk, you coming back, or a check that fails or passes.

A brain step answers the questions that the real brain gets:

| Key | Choices |
| --- | --- |
| `react.face` | a mood of the pack that has a face, or `none` |
| `react.move` | `success`, `failure` or `reply` for a turn that ended, `wake up` for you back after a long or very long break, `notice` for a prompt that says its name, else `none`; after talk, its reply (`yes`, `hello`, `status`, `nap`…) |
| `react.intensity` | `small`, `medium`, `big`, `huge`: how long the face holds and how big what it says is |
| `say` | what it says: `none`, a feeling (`glad`, `upset`, `tickled`), `swear`, or a topic (`start`, `tests`, `done`…); only a pack with a voice says it |

The choices and what each means are in
`app/BoopKit/Outputs/ReactOutput.swift`. `boopdev check` lists them when
an answer is wrong. A pack with no voice ignores the `say` answer, so
one script plays with or without a voice.

## Play it

```sh
make demo                                              # asks which demo, then where it plays
make demo NAME=hello                                   # the simulator's page, from its recording, at once
make demo NAME=all                                     # every recorded demo in the page, one after another
make demo NAME=hello BOARD=usb:$TMPDIR/linkkit-bridge.sock   # a real board, no agent
make demo NAME=hello IN=simulated-claude-terminal      # Claude Code in this terminal, replies replayed
make demo NAME=hello IN=simulated-codex-terminal       # the same with Codex (no reviewer steps: Codex has no subagents here)
make demo NAME=hello IN=claude                         # your real Claude, in the Claude desktop app
```

`make demo` with nothing else lists every demo, numbered, with its
title and length, and asks which one; then it lists only the places
that demo can play, and asks where. Given no terminal to ask in (an
agent's shell), it prints the list. `simulator/tools/demos.py list`
prints it too.

Where a demo plays, and what plays the agent:

| Where | The agent | Its model |
| --- | --- | --- |
| The simulator's page (the default) | none: Boop sends the hooks the agent would, at the script's times | none |
| A real board (`BOARD=usb:…`) | the same | none |
| This terminal (`IN=simulated-claude-terminal`, `simulated-codex-terminal`) | the real Claude Code or Codex | a local server that replays the script's replies: no API key, no network |
| The Claude desktop app (`IN=claude`) | your Claude Code | your real Claude, following the script as a `/demo` command |

- **A real board** needs a bridge. The menu starts one when there's
  none; with `BOARD`, start `.build/debug/linkkit-bridge` in another
  terminal first. Quit the menu-bar app, so that only one app talks to
  the board. `BOARD` works with every `IN` too.
- **With an agent,** the agent goes at its own pace. Boop waits for the
  agent's own hook for each agent step, then plays your steps and the
  brain's after it. Only a demo with a project plays with an agent
  (below, A project for a real agent). How this works:
  [internal/sessions/README.md](../internal/sessions/README.md).
- **Two buddies or more** play live on a simulated board each, side by
  side in the page: they have no recording.
- `make demo` plays the demo as its pack, on the face its pack gives the
  AMOLED board (Boop's gel, Pixel's pixel face). If two packs have a demo
  with the same name, choose one with `CHARACTER=<pack>`; the menu shows
  both.

## The same every time

- **The simulator's page plays a recording,** checked in beside its
  script: `characters/<pack>/demo/recordings/<name>.json`, every message
  the board was sent, with when. So a demo starts at once, the same each
  time. The firmware in the page draws it, so a change to the firmware
  shows at once; a change to what the app sends needs the demos recorded
  again, `make -C internal demos ALL=1`. The recording's format is in
  [simulator/README.md](../simulator/README.md), Demos.
- **A recording keeps the hash of its script.** When the script changes,
  the recording is out of date: `make -C internal tools-test` and CI
  fail, and `make demo` records it before it plays. `make -C internal
  demos` records every one that's out of date, several at once, each as
  long as it runs.
- **A recording's clock** starts at the script's `start`, else at 14:00
  on Tuesday 20 October 2026: an afternoon with no weekend or holiday to
  dress it, whenever it's recorded.
- **A board or an agent plays live.** The steps come in the same order,
  each at its time or at the agent's pace.
- **In the terminal, the agent's model is replayed** from the script, so
  it says and does what the script says.
- **In the desktop app, a real Claude follows the script openly** (as a
  `/demo` command). A real model won't say what isn't true, so keep the
  agent's words true to what it does.

## A project for a real agent

With `IN=…`, the agent works in a fresh copy of
`internal/sessions/<name>/workspace/`: the files the script's agent
reads, edits and runs, and tests that give the script's results. How to
make one: [internal/sessions/README.md](../internal/sessions/README.md),
A demo's project. With no `IN`, a demo needs no project.
