# Demos

Updated 2026-10-15. A demo is a short, scripted stretch of work that a
character lives through: an agent gets a task, you poke and talk to the
creature, and it reacts. Use demos to record videos, to show the
creature off, and to check that everything works end to end.

One script plays four ways: in the simulator's page, on a real board,
with Claude Code or Codex replayed in a terminal, and with your real
Claude in the desktop app. The script is the same in each.

## Write one

1. Make `characters/<pack>/demo/<name>.jsonl`. Copy a short one to
   start, such as `characters/pixel/demo/hello.jsonl`.
2. Write one line for each thing that happens (below).
3. Check it: `.build/debug/boopdev check` (after `make build`). It
   names each line the pack can't play, and the choices it can.
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

## Lines

Each line is one JSON object. A line that starts with `//` is a comment.
The first line may be a header: `{"demo": 1, "title": "…"}`, and
`"agent": "codex"` if the script is Codex's (Claude is the default).

Every other line is by one of three: the agent, you, or the creature's
brain.

| Line | What it does | Keys |
| --- | --- | --- |
| `{"agent": "prompt"}` | You give the agent its task | `text` |
| `{"agent": "read"}` | The agent reads a file | `file` |
| `{"agent": "edit"}` | The agent edits a file | `file`, `old`, `new` |
| `{"agent": "run"}` | The agent runs a command | `cmd`, `about` (what it's for), `fails` (true or false), `ask` (it asks you first, and you allow it after this many seconds) |
| `{"agent": "review"}` | The agent sends a subagent | `task`, `prompt` |
| `{"agent": "reply"}` | The agent's turn ends with this message | `text` |
| `{"you": "poke"}` | You tap the creature | |
| `{"you": "talk"}` | You hold the talk button, then it hears `text` | `text`, `hold` (seconds, 1.5) |
| `{"brain": {…}}` | How the creature reacts to the line above | the answers; `mood` sets its mood |
| `{"mood": "proud"}` | The creature's mood changes | |

On any agent line, `say` is what the agent says before it acts, and
`"by": "reviewer"` makes it the subagent's line.

**Timing.** Lines happen in order. `after` is how many seconds a line
waits after the one before it ends. An agent line also `takes` some
seconds. Without them, each takes about as long as it would.

**Captions.** Any line can have a `note`: words for the viewer that
replace the words Boop makes from the line ("You poke Pixel three times
while it's busy").

A key that a line doesn't take, or a value of the wrong type, stops the
demo with the line's number. So does a brain answer the pack can't play.

## The brain's answers

A demo has no real brain. The creature does only what the rules do
(working, needs you, done) and what the script's brain lines say. Put a
brain line where a real brain would be asked: a turn that starts or
ends, a poke, talk, or a check that fails or passes.

A brain line answers the questions that the real brain gets:

| Key | Choices |
| --- | --- |
| `react.mood` | a mood of the pack that has a face, or `none` |
| `react.animation` | `success`, `failure` or `reply` for a turn that ended, else `none` |
| `react.loops` | `once`, `twice`, `three times`, `four times` |
| `say.feeling`, `say.about`, `say.kind` | what it says; only a pack with a voice says it |

The choices and what each means are in
`app/BoopKit/Actions/ReactAction.swift`. `boopdev check` lists them when
an answer is wrong. A pack with no voice ignores the `say.*` answers, so
one script plays with or without a voice.

## Play it

```sh
make demo NAME=?                                       # list the demos
make demo NAME=hello                                   # the simulator's page, no agent
make demo NAME=hello BOARD=usb:/tmp/boop-bridge.sock   # a real board, no agent
make demo NAME=hello IN=simulated-claude-terminal      # Claude Code in this terminal, replies replayed
make demo NAME=hello IN=simulated-codex-terminal       # the same with Codex
make demo NAME=hello IN=claude                         # your real Claude, in the Claude desktop app
```

- **A real board** needs the bridge first:
  `internal/tools/boopctl bridge` in another terminal. Quit the menu-bar
  app, so that only one app talks to the board. `BOARD` works with every
  `IN` too.
- **With no agent,** Boop plays the agent: it sends the hooks that the
  agent would send, at the script's times.
- **With an agent,** the agent goes at its own pace. Boop waits for the
  agent's own hook for each agent line, then plays your lines and the
  brain's after it. How this works:
  [internal/sessions/README.md](../internal/sessions/README.md).
- `make demo` plays the demo as its pack. If two packs have a demo with
  the same name, choose one with `CHARACTER=<pack>`.

## The same every time

- **The simulator's page plays a recording.** The first time, `make
  demo` plays the script through the real app and records every line the
  board gets. The page then plays that recording, so each viewing is the
  same. It records again when the script changes, or with `FRESH=1`.
  This is what the landing page shows.
- **A board or an agent plays live.** The lines come in the same order,
  each at its time or at the agent's pace.
- **In the terminal, the agent's model is replayed** from the script, so
  it says and does what the script says.
- **In the desktop app, a real Claude follows the script openly** (as a
  `/demo` command). A real model won't say what isn't true, so keep the
  agent's words true to what it does.

## A project for a real agent

With `IN=…`, a real Claude Code or Codex does the work in a fresh copy of
`internal/sessions/<name>/workspace/`. Make that folder with the files the
script's agent reads, edits and runs, and with tests that give the
script's results (`hello` and `landing` are examples). With no `IN`, a
demo needs no project.
