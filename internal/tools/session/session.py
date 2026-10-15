#!/usr/bin/env python3
"""Plays a demo script through a real agent, with Boop watching.

    internal/tools/session/session.py run NAME [--agent claude|codex] [--ui terminal|desktop] [--board sim|usb:SOCKET|none]
    internal/tools/session/session.py list

NAME is a character pack's demo script, `demo/NAME.jsonl` (the same one
`make demo` plays with no agent), and `internal/sessions/NAME/workspace/`
the project its agent works in, copied fresh for every run.

Boop plays the script (`Boop --headless --demo SCRIPT --live`): it does the
person's and the brain's lines, and waits for the agent's own hooks for the
agent's, so everything keeps in step. The agent is real:

- In this terminal (`--ui terminal`, the default), the real Claude Code or
  Codex, whose model is a local server that gives the script's replies
  (model.py), each when the script reaches it. This tool types the prompt
  and allows what the agent asks, as the script says.
- In the Claude desktop app (`--ui desktop`), your real Claude Code, whose
  model can't be replayed, so it performs the script openly as a `/demo`
  command (desktop.py). You type /demo, send it, and allow what it asks.

In the app, where the model can't be held, the project's settings add one
hook of the demo's own, the gate (gate.py), which holds each tool call
until the script reaches its line; in the terminal the replay server holds
each reply the same way. The agent's hooks go to the run's Boop alone
(`AGENT_HOOKS_SOCKET`), by Boop's own installer in the terminal and by the
project's settings in the app. The board is the simulator's page, or a
board on a USB bridge.

Nothing of yours is touched in the terminal: each run has its own HOME and
state under /tmp/boop-session-*, kept for its logs (session.log, boop.log,
requests/, agent.log when this isn't a terminal). In the app it's your own
Claude Code, in that folder only.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import desktop  # noqa: E402
import model  # noqa: E402
import script as scripts  # noqa: E402
from term import Terminal  # noqa: E402

REPO = HERE.parents[2]
SESSIONS = REPO / "internal" / "sessions"
SIM_SOCKET = "/tmp/boop-sim-usb.sock"
SIM_URL = "http://127.0.0.1:8206/"
# The key the agents are given for the replay server, which takes any.
REPLAY_KEY = "sk-ant-replay-0000-not-a-real-key-boop-demo"
CODEX_MODEL = "gpt-6-astra"
GATE = HERE / "gate.py"

# What each agent shows when it asks for permission, the key that allows
# it, and how to quit it.
DIALOGS = {"claude": ("Do you want to proceed?", "\r"), "codex": ("Would you like to run the following command?", "y")}
QUIT = {"claude": "/exit", "codex": "/quit"}


class Log:
    def __init__(self, path: Path):
        self.file = open(path, "a")
        self.start = time.time()
        self.lock = threading.Lock()

    def __call__(self, line: str) -> None:
        with self.lock:
            self.file.write(f"{time.time() - self.start:8.2f} {line}\n")
            self.file.flush()


def answers(path: str) -> bool:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(0.5)
    try:
        s.connect(path)
        return True
    except OSError:
        return False
    finally:
        s.close()


def wait_socket(path: str, seconds: float) -> bool:
    end = time.time() + seconds
    while not answers(path):
        if time.time() > end:
            return False
        time.sleep(0.1)
    return True


def run_quiet(argv: List[str], env: Optional[Dict[str, str]] = None, what: str = "") -> None:
    result = subprocess.run(argv, cwd=REPO, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stdout[-4000:])
        sys.exit(f"session: {what or ' '.join(argv)} failed")


def clean_env() -> Dict[str, str]:
    """This environment without anything an agent session put in it, so
    the agent starts as a fresh one, not as one nested in another."""
    return {k: v for k, v in os.environ.items()
            if not k.startswith(("CLAUDE", "CODEX", "ANTHROPIC", "OPENAI", "AGENT_HOOKS", "BOOP_JEV"))}


def make_workspace(source: Path, root: Path, name: str) -> Path:
    ws = root / name
    shutil.copytree(source, ws)
    for argv in (["init", "-q", "-b", "main"], ["add", "-A"], ["commit", "-qm", "Start"]):
        scripts.git(ws, *argv)
    return ws


def permissions(s: scripts.Script) -> Dict[str, List[str]]:
    """Claude Code's rules: it may do what the script does without asking,
    and asks, in any mode, about the commands the script asks about."""
    allow = {"Read", "Edit", "Agent", "Task"}
    ask = set()
    for l in s.agent_lines():
        if l["agent"] == "run":
            (ask if "ask" in l else allow).add(f"Bash({l['cmd']})")
            # A subagent words its own commands (`git -C DIR diff`): a
            # reviewer may run any git command.
            if l.get("by") == "reviewer" and l["cmd"].startswith("git "):
                allow.add("Bash(git:*)")
    return {"allow": sorted(allow), "ask": sorted(ask)}


def gate_hook(command: str) -> Dict[str, Any]:
    return {"hooks": [{"type": "command", "command": command, "timeout": 120}]}


def setup_agent(agent: str, home: Path, ws: Path, base_url: str, s: scripts.Script, env: Dict[str, str]) -> List[str]:
    """Makes the agent's settings in `home`, as if someone had set it up
    already, with Boop's hooks in by Boop's own installer, and returns the
    command line that starts it."""
    boopdev = str(REPO / ".build/debug/boopdev")
    hook = str(REPO / ".build/debug/agent-hook")
    if agent == "claude":
        (home / ".claude").mkdir(parents=True)
        run_quiet([boopdev, "hooks", "install", "claude", "--home", str(home), "--hook", hook], what="installing Claude's hooks")
        path = home / ".claude" / "settings.json"
        settings = json.loads(path.read_text())
        settings["permissions"] = permissions(s)
        path.write_text(json.dumps(settings, indent=2))
        (home / ".claude.json").write_text(json.dumps({
            "hasCompletedOnboarding": True, "theme": "dark", "numStartups": 5, "autoUpdates": False,
            "customApiKeyResponses": {"approved": [REPLAY_KEY[-20:]], "rejected": []},
            "projects": {str(ws): {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True, "allowedTools": []}},
        }, indent=2))
        env.update({"ANTHROPIC_BASE_URL": base_url, "ANTHROPIC_API_KEY": REPLAY_KEY,
                    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1", "DISABLE_AUTOUPDATER": "1"})
        return ["claude"]
    codex = home / ".codex"
    codex.mkdir(parents=True)
    # The settings first: the installer adds its own to the file after them.
    (codex / "config.toml").write_text(f'''model = "{CODEX_MODEL}"
model_provider = "replay"
approval_policy = "on-request"
sandbox_mode = "workspace-write"
check_for_update_on_startup = false

[model_providers.replay]
name = "Replay"
base_url = "{base_url}/v1"
wire_api = "responses"
env_key = "BOOP_REPLAY_KEY"

[projects."{ws}"]
trust_level = "trusted"
''')
    run_quiet([boopdev, "hooks", "install", "codex", "--home", str(home), "--hook", hook], what="installing Codex's hooks")
    env.update({"CODEX_HOME": str(codex), "BOOP_REPLAY_KEY": REPLAY_KEY})
    # Codex runs a hook only once someone has trusted it, and asks at the
    # start. These are Boop's own installer's, in a home made for this run.
    return ["codex", "--dangerously-bypass-hook-trust"]


class Cursor:
    """Boop's cursor file: the number of the script's line due now."""

    def __init__(self, path: Path, boop: subprocess.Popen):
        self.path, self.boop = path, boop

    @property
    def at(self) -> int:
        return scripts.cursor_at(self.path)

    def wait(self, n: int, nag: Optional[str] = None) -> bool:
        """Until line `n` is due, saying `nag` every 30 s meanwhile; false
        if Boop stopped first."""
        asked = time.time()
        while self.at < n:
            if self.boop.poll() is not None:
                return False
            if nag and time.time() - asked > 30:
                print(f"session: {nag}", file=sys.stderr)
                asked = time.time()
            time.sleep(0.1)
        return True


def drive(agent: str, s: scripts.Script, term: Terminal, cursor: Cursor, log: Log) -> None:
    """The person's part of the agent's side in the terminal: the prompt
    when it's due, and allowing each request the script has the agent
    make, after its seconds."""
    prompt = s.prompt
    if not cursor.wait(prompt["n"]):
        return
    time.sleep(0.5)
    log(f"you: the prompt (line {prompt['n']})")
    term.type(prompt["text"])
    text, key = DIALOGS[agent]
    for l in [l for l in s.agent_lines() if "ask" in l]:
        mark = term.mark()
        if not cursor.wait(l["n"]) or not term.wait_for(text, since=mark, timeout=180):
            log(f"you: no request for line {l['n']}")
            continue
        time.sleep(l["ask"])
        log(f"you: allow line {l['n']}")
        term.press(key)


def cmd_run(args: argparse.Namespace) -> int:
    path = scripts.find(args.name)
    s = scripts.load(path)
    source = SESSIONS / args.name / "workspace"
    if not source.is_dir():
        sys.exit(f"session: no project for {args.name}: make {source.relative_to(REPO)}/ with the files "
                 "the script's agent reads, edits and runs")
    if args.ui == "desktop" and args.agent != "claude":
        sys.exit("session: the desktop app runs Claude Code: --ui desktop is for --agent claude")
    if args.agent == "codex" and any(l["agent"] == "review" for l in s.agent_lines()):
        sys.exit(f"session: {args.name} sends a reviewer, and Codex has no subagents here: try --agent claude")
    if args.ui == "terminal" and shutil.which(args.agent) is None:
        sys.exit(f"session: {args.agent} isn't on PATH")
    pack = path.parents[1]
    env = clean_env()
    env["BOOP_CHARACTER"] = str(pack)
    if not args.no_build:
        print(f"session: building Boop with the {pack.name} pack…", file=sys.stderr)
        run_quiet(["make", "build"], env=env, what="make build")
    root = Path(os.path.realpath(tempfile.mkdtemp(prefix="boop-session-", dir="/tmp")))
    log = Log(root / "session.log")
    children: List[subprocess.Popen] = []
    term: Optional[Terminal] = None
    server = None
    boop: Optional[subprocess.Popen] = None
    cursor: Optional[Cursor] = None
    try:
        # The board.
        link = "none"
        if args.board == "sim":
            if not answers(SIM_SOCKET):
                print("session: building the simulator's page…", file=sys.stderr)
                # Its own process group, so stopping it stops its server too.
                children.append(subprocess.Popen(["make", "-s", "simulator"], cwd=REPO, env=env, start_new_session=True,
                                                 stdout=open(root / "simulator.log", "w"), stderr=subprocess.STDOUT))
                if not wait_socket(SIM_SOCKET, 300):
                    sys.exit(f"session: the simulator's page didn't start; see {root}/simulator.log")
            link = "usb:" + SIM_SOCKET
            print(f"session: open {SIM_URL} (the board), then it starts", file=sys.stderr)
            if sys.stdout.isatty() and shutil.which("open"):
                subprocess.run(["open", SIM_URL])
        elif args.board.startswith("usb:"):
            link = args.board

        # Boop plays the script, keeping to the live agent; it waits for
        # the board first, and stops when the script is over.
        state = root / "state"
        name = json.loads((pack / "character.json").read_text())["name"]
        boop_sock = str(root / "boop.sock")
        boop = subprocess.Popen(
            [str(REPO / ".build/debug/Boop"), "--headless", "--state-dir", str(state), "--socket", boop_sock,
             "--link", link, "--brain", "none", "--name", name, "--no-open", "--demo", str(path), "--live"],
            cwd=REPO, env=env, stdout=open(root / "boop.log", "w"), stderr=subprocess.STDOUT)
        cursor = Cursor(state / "demo-cursor", boop)
        if not wait_socket(boop_sock, 10):
            # Most often a script line the pack can't play: Boop says which.
            sys.exit(f"session: Boop didn't start:\n{(root / 'boop.log').read_text()[-2000:]}")
        # Boop starts the script once the board says hello (line 0 due);
        # nothing of the agent's starts before.
        if link != "none":
            print("session: waiting for the board…", file=sys.stderr)
        board = SIM_URL if args.board == "sim" else link
        if not cursor.wait(0, nag=f"still waiting for the board: is {board} open?"):
            sys.exit(f"session: Boop stopped before the script started; see {root}/boop.log")
        log(f"boop: playing {path.name}, board {link}")

        ws = make_workspace(source, root, s.project)
        if args.ui == "desktop":
            gate = f"/usr/bin/python3 {GATE} --script {path} --cursor {cursor.path}"
            settings = {"env": {"AGENT_HOOKS_SOCKET": boop_sock}, "permissions": permissions(s),
                        "hooks": {"PreToolUse": [gate_hook(gate)]}}
            desktop.prepare(ws, settings, desktop.script(s.replies(), s.title or s.name))
            print(f"session: {s.name} in the Claude app, logs in {root}", file=sys.stderr)
            desktop.open_session(ws)
            print("session: the Claude app has the session open. Type /demo and send it, and allow what it asks.",
                  file=sys.stderr)
            while boop.poll() is None:
                time.sleep(0.5)
        else:
            replay = model.Replay(s.replies(), str(ws), log, due=cursor.wait, keep=str(root / "requests"),
                                  title=s.title or s.name)
            server = model.start(replay)
            base_url = f"http://127.0.0.1:{server.server_address[1]}"
            home = root / "home"
            home.mkdir()
            env.update({"HOME": str(home), "AGENT_HOOKS_SOCKET": boop_sock})
            argv = setup_agent(args.agent, home, ws, base_url, s, env)
            print(f"session: {s.name} with {args.agent}, logs in {root}", file=sys.stderr)
            time.sleep(1)
            term = Terminal(argv, str(ws), env, mirror=str(root / "agent.log"))
            drive(args.agent, s, term, cursor, log)
            while boop.poll() is None and not term.done:
                time.sleep(0.5)
            time.sleep(2)
            if not term.done:
                term.type(QUIT[args.agent])
                if not term.wait_exit(15):
                    term.press("\x03"); term.press("\x03")
    finally:
        if term:
            term.wait_exit(10)
            term.close()
        if server:
            server.shutdown()
        for child in children:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
        if boop and boop.poll() is None:
            boop.terminate()
        for child in children + ([boop] if boop else []):
            try:
                child.wait(5)
            except subprocess.TimeoutExpired:
                child.kill()
    reached = max(0, cursor.at) if cursor else 0
    whole = reached >= len(s.lines)
    print(f"\nsession: {'done' if whole else 'stopped'}: line {min(reached, len(s.lines))} of {len(s.lines)}; logs in {root}",
          file=sys.stderr)
    return 0 if whole else 1


def cmd_list(args: argparse.Namespace) -> int:
    for folder in sorted(SESSIONS.iterdir()) if SESSIONS.exists() else []:
        if (folder / "workspace").is_dir():
            try:
                s = scripts.load(scripts.find(folder.name))
                print(f"{folder.name:12} {s.title}")
            except scripts.ScriptError as e:
                print(f"{folder.name:12} ({e})")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    run = sub.add_parser("run", help="play a demo script through a real agent")
    run.add_argument("name")
    run.add_argument("--agent", choices=("claude", "codex"), default="claude")
    run.add_argument("--ui", choices=("terminal", "desktop"), default="terminal",
                     help="where the agent runs: this terminal (the default), or Claude Code in the Claude desktop app")
    run.add_argument("--board", default="sim", help="sim (the simulator's page, the default), usb:SOCKET (a bridge) or none")
    run.add_argument("--no-build", action="store_true", help="skip make build")
    sub.add_parser("list", help="the demos that have a project for an agent")
    args = parser.parse_args()
    try:
        return {"run": cmd_run, "list": cmd_list}[args.cmd](args)
    except scripts.ScriptError as e:
        sys.exit(f"session: {e}")


if __name__ == "__main__":
    sys.exit(main())
