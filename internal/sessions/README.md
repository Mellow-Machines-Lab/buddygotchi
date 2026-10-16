# Demos with a real agent

Updated 2026-10-16. How a character pack's demo script plays through a
real Claude Code or Codex with Boop watching, for recording videos
(`make demo IN=…`; the commands are in
[characters/DEMOS.md](../../characters/DEMOS.md), Play it). Here the
agent really reads, edits and runs things in a fresh copy of a small
project, and its real hooks reach Boop, which keeps the person's pokes
and talk and its brain's answers in step with it.

`make demo IN=…` builds Boop with the script's character pack, serves the simulator's
page (unless one is running) and opens it, waits for the board, then
starts the agent. Put the agent and the page side by side and record the
screen. Your keys reach the agent as ever: quit it (Ctrl-C twice) and the
run stops with it.

## One script, three parts

A script is one list of steps, each by one of three: the agent, you, or
Boop's brain. They happen in order, and three things keep them so:

```
 demo/NAME.jsonl ──► Boop --headless --demo NAME.jsonl --live
                       │  you and the brain: a poke, talk, an answer, each in turn
                       │  the agent's steps: waits for the agent's own hooks for each
                       │  writes the step due now to its cursor file
                       ▼
                   cursor ──► in the terminal, the replay server: each model reply waits for its step
                          └─► in the app, the gate: each of the agent's tool calls waits for its step
 real claude / codex ── real hooks ──► Boop (AGENT_HOOKS_SOCKET) ──► board
```

- **Boop plays the script.** With `--live`, the agent's steps aren't sent
  by Boop, as `make demo` does, but waited for: each ends when the agent's
  own hook for it arrives (a tool's end, the turn's end). Then Boop does
  the steps after it, the person's and the brain's, and moves on. A hook
  the script doesn't have passes by, and if the agent leaves a step out,
  the next step's hook moves the script on to it.
- **One pacing point a mode.** In the terminal the replay server gives
  each reply only when its step is due, so no tool call can come early.
  In the app, where the model is real, **the gate**
  (`internal/tools/session/gate.py`) does it: one hook of the demo's own,
  in the project's settings beside Boop's, that before each tool call
  finds the call's step and waits until Boop's cursor says it's due.
  Either way the agent can't run ahead of the talk and pokes before a step.
  The gate never holds a call for good: one the script doesn't have goes
  at once, and so does any call when the cursor stops moving for 90 s. It
  logs what it held, and for how long, to `gate.log`.
- **The agent's side** is the tool's (`internal/tools/session/`):
  - In the terminal (`IN=simulated-claude-terminal` or `IN=simulated-codex-terminal`), the real agent's model is
    a local server (`model.py`) that speaks Anthropic's Messages API to
    Claude Code and OpenAI's Responses API to Codex, streamed, and gives
    the script's next reply when its step is due, in that agent's own
    tools. A title request gets the script's title and costs no reply. The
    tool types the prompt and allows what the agent asks, after the
    script's seconds (`term.py` runs the agent in a pty shown here).
    The pty is this terminal's size, or `DEMO_ROWS` × `DEMO_COLS` when
    both are set, for recordings of the same size every time
    (`DEMO_ROWS=40 DEMO_COLS=120 make demo NAME=… IN=…`; size your
    terminal to match).
  - **A compact** is real in the terminal: the agent compacts its own
    conversation. Claude Code compacts when the API answers that the
    prompt is too long, so once the compact is due the replay server
    answers the next request so. Codex compacts when a reply says its
    context holds more than its config's `model_auto_compact_token_limit`,
    so the reply before the compact says so. Either agent then asks the
    model for a summary, which gets the step's `summary` and doesn't
    count as a turn, and goes on with the next step. Every demo runs
    Claude Code's classic renderer (`"tui": "default"`), so every clip
    looks the same; it also clears the screen at a compaction to its
    "Conversation compacted" line, where the default fullscreen one keeps
    the conversation on the screen.
  - In the Claude desktop app (`IN=claude`), the app sets its own model
    address, so the model can't be replayed: your real Claude performs the
    script openly instead, as a `/demo` command in the project, word for
    word (`desktop.py`). The app opens a new Code session in the folder;
    you type `/demo`, send it, and allow what it asks. The
    project's settings, in its first commit since the app runs each session
    in a git worktree of its own, send that session's hooks to the run's
    Boop alone, add the gate, and make Claude ask about the commands the
    script asks about in any mode. A script with a compact doesn't play
    here: a real model can't be made to fill its context on cue.

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
made (`hello`, `landing`, `context-wall`), or that runs the command it asks you about
(`hanging`, whose story is the wait before you allow it). Its copy is
named after the script's title (`deploy-the-docs`), as the player with
no agent names its project, so the board's sign says the same either way.
A real model reads what it runs, so the
project and the script must agree, and the script must say only what's
true: a reviewer asked to say "nothing else changed" when something did
won't. `make -C internal tools-test` holds the landing and context-wall
projects to their stories.

**When an agent changes,** a new Claude Code or Codex can name a tool, a
hook or a dialog differently: `boop.log` says which step was left out or
waited for, and `gate.log` and `requests/` what the agent did. Tested with
Claude Code 2.1.282 (replayed, and a real model performing `/demo` from the
command line) and Codex 0.153.4 (replayed).
