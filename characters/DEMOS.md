# Demos

Updated 2026-10-16. A demo is a short, scripted stretch of work that a
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
3. Check it: `.build/debug/boopdev check` (after `make build`). It
   names each step the pack can't play, and the choices it can.
4. Watch it: `make demo NAME=<name>`.

This is all of `hello.jsonl`:

```json
// Half a minute: a read, an approved test run, done. A quick check that a demo plays end to end.
{"demo": 1, "title": "Run the tests"}
{"agent": "prompt", "text": "Run the tests"}
{"brain": {"react.mood": "curious", "say.about": "start", "say.kind": "word"}}
{"agent": "read", "file": "README.md", "say": "Let me look at the project first."}
{"agent": "run", "cmd": "npm test", "about": "Run the tests", "ask": 2, "say": "I'll run the tests."}
{"agent": "reply", "text": "The one test passes."}
{"brain": {"react.mood": "proud", "react.animation": "success", "say.about": "done", "say.kind": "word"}, "mood": "proud"}
```

## Steps

Each line of the file is one JSON object. A line that starts with `//`
is a comment. The first line may be a header: `{"demo": 1, "title": "…"}`, and
`"agent": "codex"` if the script is Codex's (Claude is the default).

Every other line is a step, by one of three: the agent, you, or the
creature's brain.

| Step | What it does | Keys |
| --- | --- | --- |
| `{"agent": "prompt"}` | You give the agent its task | `text` |
| `{"agent": "read"}` | The agent reads a file | `file` |
| `{"agent": "edit"}` | The agent edits a file | `file`, `old`, `new` |
| `{"agent": "run"}` | The agent runs a command | `cmd`, `about` (what it's for), `fails` (true or false), `ask` (it asks you first, and you allow it after this many seconds) |
| `{"agent": "review"}` | The agent sends a subagent | `task`, `prompt` |
| `{"agent": "compact"}` | The agent's context is full, so it compacts the conversation and goes on | `summary` (what its model writes of the work so far; required) |
| `{"agent": "reply"}` | The agent's turn ends with this message | `text` |
| `{"you": "poke"}` | You tap the creature | |
| `{"you": "talk"}` | You hold the talk button, then it hears `text` | `text`, `hold` (seconds, 1.5) |
| `{"you": "back"}` | You come back to the Mac after `minutes` away | `minutes` (60) |
| `{"brain": {…}}` | How the creature reacts to the step above | the answers; `mood` sets its mood |
| `{"mood": "proud"}` | The creature's mood changes | |

On any agent step, `say` is what the agent says before it acts, and
`"by": "reviewer"` makes it the subagent's step.

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

A back is the away and the back at once, as the Mac would record them
after that long: being away shows nothing on the board, and the Mac's own
keys and mouse would end an away left open. `good-morning.jsonl` comes
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
{"brain": {"react.mood": "curious", "say.about": "start", "say.kind": "word"}, "buddy": "left"}
```

Play it headless on two simulated boards, each on its own cable
([simulator/README.md](../simulator/README.md)):

```sh
python3 simulator/web/serve.py --cable left=/tmp/boop-sim-left.sock --cable right=/tmp/boop-sim-right.sock
# open http://127.0.0.1:8206/?boards=left,right&packs=pixel,boop
.build/debug/Boop --headless --state-dir /tmp/two --demo pack:not-my-turn \
    --links usb:/tmp/boop-sim-left.sock,usb:/tmp/boop-sim-right.sock
```

A live agent plays only a script of one buddy.

## The brain's answers

A demo has no real brain. The creature does only what the rules do
(working, needs you, done) and what the script's brain steps say. Put a
brain step where a real brain would be asked: a turn that starts or
ends, a poke, talk, you coming back, or a check that fails or passes.

A brain step answers the questions that the real brain gets:

| Key | Choices |
| --- | --- |
| `react.mood` | a mood of the pack that has a face, or `none` |
| `react.animation` | `success`, `failure` or `reply` for a turn that ended, `wake up` for you back after a long or very long break, else `none` |
| `react.loops` | `once`, `twice`, `three times`, `four times` |
| `say.feeling`, `say.about`, `say.kind` | what it says; only a pack with a voice says it |

The choices and what each means are in
`app/BoopKit/Outputs/ReactOutput.swift`. `boopdev check` lists them when
an answer is wrong. A pack with no voice ignores the `say.*` answers, so
one script plays with or without a voice.

## Play it

```sh
make demo 'NAME=?'                                     # list the demos (quoted for zsh)
make demo NAME=hello                                   # the simulator's page, no agent
make demo NAME=hello FACE=gel                          # the same, on Boop's gel face
make demo NAME=hello BOARD=usb:$TMPDIR/linkkit-bridge.sock   # a real board, no agent
make demo NAME=hello IN=simulated-claude-terminal      # Claude Code in this terminal, replies replayed
make demo NAME=hello IN=simulated-codex-terminal       # the same with Codex (no reviewer steps: Codex has no subagents here)
make demo NAME=hello IN=claude                         # your real Claude, in the Claude desktop app
```

- **A real board** needs the bridge first:
  `.build/debug/linkkit-bridge` in another terminal. Quit the menu-bar
  app, so that only one app talks to the board. `BOARD` works with every
  `IN` too.
- **With no agent,** Boop plays the agent: it sends the hooks that the
  agent would send, at the script's times.
- **With an agent,** the agent goes at its own pace. Boop waits for the
  agent's own hook for each agent step, then plays your steps and the
  brain's after it. How this works:
  [internal/sessions/README.md](../internal/sessions/README.md).
- `make demo` plays the demo as its pack. If two packs have a demo with
  the same name, choose one with `CHARACTER=<pack>`. With no `NAME`, it
  plays `landing`.

## The same every time

- **The simulator's page plays a recording.** The first time, `make
  demo` plays the script through the real app and records every message
  the board gets. The page then plays that recording, so each viewing is the
  same. It records again when the script changes, or with `FRESH=1`.
  This is what the landing page shows. The recording's format is in
  [simulator/README.md](../simulator/README.md), Demos.
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
