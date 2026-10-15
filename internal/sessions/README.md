# Demos

Updated 2026-10-15. A character pack's demo script
([characters/DEMOS.md](../../characters/DEMOS.md)), played
through a real Claude Code or Codex with Boop watching, for recording
videos. The same script `make demo` plays with no agent: here the agent
really reads, edits and runs things in a fresh copy of a small project,
and its real hooks reach Boop, which keeps the person's pokes and talk and
its brain's answers in step with it.

## Every way to run one

All of it is `make demo` from the repo root, and these variables:

| Variable | Value | What it does |
| --- | --- | --- |
| `NAME` | a script's name (`landing` when left out), or `?` | Plays `demo/NAME.jsonl` from the pack that has one (`CHARACTER=…` picks when two packs share a name). `?` lists them |
| `IN` | nothing | No agent: Boop plays the agent's part too, on the simulator's page in a browser, as it records it for the website |
| | `simulated-claude-terminal` | Claude Code in this terminal, its model a local server that replays the script's replies |
| | `simulated-codex-terminal` | The same with Codex (a script with no reviewer: Codex has no subagents here) |
| | `claude` | Your real Claude, in the Claude desktop app, performing the script as `/demo` |
| `BOARD` | `sim` (when left out), or `usb:SOCKET` | With an agent: where Boop shows, the simulator's page or a real board through `internal/tools/boopctl bridge` |
| `FACE` | `pixel` (when left out), or `gel` | With no agent: the face on the simulator's page |
| `FRESH` | `1` | With no agent: record the demo again, though the script hasn't changed |

```sh
make demo NAME=?                                          # the demos there are
make demo NAME=hanging                                    # no agent, in the browser
make demo NAME=hanging IN=simulated-claude-terminal       # Claude Code replayed, Boop in the browser
make demo NAME=hello IN=claude                            # half a minute: a quick check that it all works
```

On a real board, plugged in over USB, quit the Boop menu-bar app first
(it would draw over the demo by Bluetooth), then:

```sh
internal/tools/boopctl bridge                                                          # one terminal: it holds the board's port
make demo NAME=hanging IN=simulated-claude-terminal BOARD=usb:/tmp/boop-bridge.sock    # another
```

With an agent, it builds Boop with the script's character pack, serves
the simulator's page (unless one is running) and opens it, waits for the
board, then starts the agent. Put the agent and the page side by side and record the
screen. Your keys reach the agent as ever: quit it (Ctrl-C twice) and the
run stops with it.

## One script, three parts

A script is one list of lines, each by one of three: the agent, you, or
Boop's brain. They happen in order, and three things keep them so:

```
 demo/NAME.jsonl ──► Boop --headless --demo NAME.jsonl --live
                       │  you and the brain: a poke, talk, an answer, each in turn
                       │  the agent's lines: waits for the agent's own hooks for each
                       │  writes the line due now to its cursor file
                       ▼
                   cursor ──► in the terminal, the replay server: each model reply waits for its line
                          └─► in the app, the gate: each of the agent's tool calls waits for its line
 real claude / codex ── real hooks ──► Boop (AGENT_HOOKS_SOCKET) ──► board
```

- **Boop plays the script.** With `--live`, the agent's lines aren't sent
  by Boop, as `make demo` does, but waited for: each ends when the agent's
  own hook for it arrives (a tool's end, the turn's end). Then Boop does
  the lines after it, the person's and the brain's, and moves on. A hook
  the script doesn't have passes by, and if the agent leaves a step out,
  the next step's hook moves the script on to it.
- **One pacing point a mode.** In the terminal the replay server gives
  each reply only when its line is due, so no tool call can come early.
  In the app, where the model is real, **the gate**
  (`internal/tools/session/gate.py`) does it: one hook of the demo's own,
  in the project's settings beside Boop's, that before each tool call
  finds the call's line and waits until Boop's cursor says it's due.
  Either way the agent can't run ahead of the talk and pokes before a step.
  The gate never holds a call for good: one the script doesn't have goes
  at once, and so does any call when the cursor stops moving for 90 s. It
  logs what it held, and for how long, to `gate.log`.
- **The agent's side** is the tool's (`internal/tools/session/`):
  - In the terminal (`IN=simulated-claude-terminal` or `IN=simulated-codex-terminal`), the real agent's model is
    a local server (`model.py`) that speaks Anthropic's Messages API to
    Claude Code and OpenAI's Responses API to Codex, streamed, and gives
    the script's next reply when its line is due, in that agent's own
    tools. A title request gets the script's title and costs no reply. The
    tool types the prompt and allows what the agent asks, after the
    script's seconds (`term.py` runs the agent in a pty shown here).
  - In the Claude desktop app (`IN=claude`), the app sets its own model
    address, so the model can't be replayed: your real Claude performs the
    script openly instead, as a `/demo` command in the project, word for
    word (`desktop.py`). The app opens a new Code session in the folder;
    you type `/demo`, send it, and allow what it asks. The
    project's settings, in its first commit since the app runs each session
    in a git worktree of its own, send that session's hooks to the run's
    Boop alone, add the gate, and make Claude ask about the commands the
    script asks about in any mode.

Boop is `Boop --headless --brain none`: its answers are the script's. In
the terminal nothing of yours is touched: each run has its own HOME,
with the agent's settings, trust and Boop's hooks made there by
`boopdev hooks install`, and no API key or network is used. In the app
it's your own Claude Code, with your settings and your account, in that
folder only.

Each run keeps its logs in its `/tmp/boop-session-*` folder:
`session.log`, `boop.log` (every line as it happened), `state/gate.log` (in the app),
`requests/` (every request the agent made, in the terminal), and
`agent.log` when this isn't a terminal.

## A demo's project

`NAME/workspace/` here is the project the script's agent works in: its
files, and tests that give the story's results when the script's edits are
made (`hello`, `landing`), or that runs the command it asks you about
(`hanging`, whose story is the wait before you allow it). Its copy is
named after the script's title (`deploy-the-docs`), as the player with
no agent names its project, so the board's sign says the same either way.
A real model reads what it runs, so the
project and the script must agree, and the script must say only what's
true: a reviewer asked to say "nothing else changed" when something did
won't. `make -C internal tools-test` holds the landing project to its
story.

**When an agent changes,** a new Claude Code or Codex can name a tool, a
hook or a dialog differently: `boop.log` says which line was left out or
waited for, and `gate.log` and `requests/` what the agent did. Tested with
Claude Code 2.1.282 (replayed, and a real model performing `/demo` from the
command line) and Codex 0.153.4 (replayed).
