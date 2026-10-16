#!/usr/bin/env python3
"""Two Boops on two simulators, and four read-only windows on them, for
working with no board (`make dev-dashboard`).

`up` starts, for each of A and B, a simulator's server
(simulator/web/serve.py) with its page opened in the browser, and a
`Boop --headless --debug` on it, with its state in /tmp/boop-dev/A or B.
It lists both apps' hook sockets where agents' hooks send (agent-hooks'
HookSocket), so your real Claude Code and Codex sessions reach them, and
takes the links away when it stops. Then it opens four Terminal windows,
each running `follow`:

    A, B        that app's own log: hooks, the core's decisions, device messages
    transcript  both apps' transcript events as they're recorded
    jev         both apps' brain passes: the prompt, the questions and the answers

Every window only reads: the apps' boop.log, and the debug.jsonl each
writes in debug mode. Ctrl-C in the `up` terminal stops everything.

Until the app drives two buddies itself, A and B are two apps, each with
its own transcript; the transcript and jev windows show both, marked.

The standard library only, on the Mac's own Python.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import signal
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BOOP = REPO / ".build" / "debug" / "Boop"
DIST = REPO / "simulator" / "web" / "dist"
ROOT = Path("/tmp/boop-dev")  # short: a Unix socket's path has room for 103 bytes
# Each simulator's page port. Not make simulator's 8206, so both can run.
PORTS = {"A": 8216, "B": 8217}
PANES = ["A", "B", "transcript", "jev"]


# --- up ---------------------------------------------------------------------

def up(args: argparse.Namespace) -> int:
    sys.stdout.reconfigure(line_buffering=True)
    brain = args.brain or ("jev" if os.environ.get("BOOP_JEV_KEY") else "scripted")
    print(f"devdash: brain {brain}")
    hooks = Path(os.environ.get("AGENT_HOOKS_DIR") or Path.home() / ".agent-hooks") / "sockets"
    if not hooks.is_dir():
        print(f"devdash: no {hooks}, so no agent's hooks reach the apps (install them from Boop's Settings)")
    procs: list[tuple[str, subprocess.Popen]] = []
    links: list[Path] = []
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    try:
        for buddy in ("A", "B"):
            d = ROOT / buddy
            d.mkdir(parents=True, exist_ok=True)
            usb, sock = d / "usb.sock", d / "boop.sock"
            with (d / "sim.log").open("w") as out:
                procs.append((f"simulator {buddy}", subprocess.Popen(
                    [sys.executable, str(REPO / "simulator" / "web" / "serve.py"),
                     "--port", str(PORTS[buddy]), "--socket", str(usb)], stdout=out, stderr=subprocess.STDOUT)))
            # boop.log has the app's own lines; --debug's readable decisions
            # go to its stderr, so both go to the A or B window through it.
            with (d / "app.log").open("w") as out:
                procs.append((f"Boop {buddy}", subprocess.Popen(
                    [str(BOOP), "--headless", "--state-dir", str(d), "--link", f"usb:{usb}", "--socket", str(sock),
                     "--brain", brain, "--no-open", "--debug"], stdout=out, stderr=subprocess.STDOUT)))
            # Listed where agents' hooks send, as the menu-bar app lists its own.
            if hooks.is_dir():
                link = hooks / f"boop-dev-{buddy.lower()}.sock"
                if link.is_symlink():
                    link.unlink()
                link.symlink_to(sock)
                links.append(link)
        time.sleep(1)  # the servers are up before the pages ask for them
        for buddy in ("A", "B"):
            subprocess.run(["open", f"http://127.0.0.1:{PORTS[buddy]}/?face={args.face}"], check=False)
        windows(args.no_windows)
        print(f"devdash: running; state in {ROOT}. Ctrl-C stops everything.")
        while True:
            for name, p in procs:
                if p.poll() is not None:
                    print(f"devdash: {name} exited ({p.returncode}); see {ROOT}/*/*.log", file=sys.stderr)
                    return 1
            time.sleep(1)
    except KeyboardInterrupt:
        return 0
    finally:
        for _, p in procs:
            if p.poll() is None:
                p.terminate()
        for _, p in procs:
            try:
                p.wait(timeout=5)
            except subprocess.TimeoutExpired:
                p.kill()
        for link in links:
            if link.is_symlink():
                link.unlink()
        print("devdash: stopped")


def windows(print_only: bool) -> None:
    """A Terminal window for each pane, or with --no-windows the commands
    to run in windows of your own."""
    for pane in PANES:
        cmd = f"{sys.executable} {shlex.quote(str(Path(__file__).resolve()))} follow {pane}"
        if print_only:
            print("  " + cmd)
        else:
            subprocess.run(["osascript", "-e", f'tell application "Terminal" to do script "{cmd}"',
                            "-e", 'tell application "Terminal" to activate'], stdout=subprocess.DEVNULL, check=False)


# --- follow -----------------------------------------------------------------

class Tail:
    """The whole lines added to a file since the last read. The app empties
    its files in place when it starts again, so a file shorter than what
    was read is read from the top."""

    def __init__(self, path: Path) -> None:
        self.path, self.offset, self.partial = path, 0, b""

    def read(self) -> list[str]:
        try:
            with self.path.open("rb") as f:
                if f.seek(0, 2) < self.offset:
                    self.offset, self.partial = 0, b""
                f.seek(self.offset)
                data = f.read()
        except FileNotFoundError:
            return []
        self.offset += len(data)
        *whole, self.partial = (self.partial + data).split(b"\n")
        return [w.decode(errors="replace") for w in whole]


def clock(ms: object) -> str:
    if not isinstance(ms, (int, float)):
        return "--:--:--.---"
    return time.strftime("%H:%M:%S", time.localtime(ms / 1000)) + f".{int(ms) % 1000:03d}"


def compact(o: object) -> str:
    return json.dumps(o, ensure_ascii=False, separators=(",", ":"))


def bar(text: str) -> str:
    return "\n".join("    │ " + line for line in text.rstrip("\n").split("\n"))


def transcript_line(buddy: str, o: dict) -> str | None:
    e = o.get("event")
    if not isinstance(e, dict):
        return None
    what = "/".join(str(x) for x in (e.get("source"), e.get("kind")) if x)
    return f"{buddy} {clock(e.get('at'))} #{e.get('seq')} {what} {compact(e.get('data', {}))}"


class Jev:
    """A pass as the brain had it: the prompt's head when it changes, then
    the event it answered for, its HISTORY and NOW, and each question's
    choice. The `questions` line, at each launch, says what it's asked."""

    def __init__(self) -> None:
        self.head: dict[str, str] = {}

    def line(self, buddy: str, o: dict) -> str | None:
        at = clock(o.get("received_at_ms"))
        if "questions" in o:
            out = [f"══ {buddy} {at} started: the questions"]
            for q in o["questions"]:
                names = " | ".join(opt.get("name", "?") for opt in q.get("options", []))
                out.append(f"    {q.get('key')}: {q.get('text', '')}\n        {names}")
            return "\n".join(out)
        if "head" in o:
            if self.head.get(buddy) == o["head"]:
                return None
            self.head[buddy] = o["head"]
            return f"══ {buddy} {at} the prompt's head (until it changes)\n{bar(o['head'])}"
        p = o.get("pass")
        if not isinstance(p, dict):
            return None
        now = p.get("now") or {}
        who = p.get("brain") or p.get("by") or "?"
        out = [f"── {buddy} {at} pass for #{p.get('for')} {now.get('type', '')} {now.get('phase', '')}".rstrip()
               + f" · {who} {p.get('latency_ms', 0)} ms"]
        if now.get("line"):
            out.append(f"  now: {now['line']}")
        if p.get("held"):
            out.append(f"  held: {p['held']}")
        if p.get("dropped"):
            out.append(f"  dropped: {p['dropped']}")
        if p.get("state"):
            out.append(bar(p["state"]))
        answers = p.get("answers") or {}
        for key in p.get("questions") or sorted(answers):
            a = answers.get(key) or {}
            probs = a.get("p") or {}
            ranked = sorted(probs.items(), key=lambda kv: -kv[1])
            others = " ".join(f"{k} {v:.2f}" for k, v in ranked if k != a.get("choice") and v >= 0.01)
            out.append(f"  {key}: {a.get('choice')} {probs.get(a.get('choice'), 0):.2f}"
                       + (f"   ({others})" if others else ""))
        return "\n".join(out)


def follow(args: argparse.Namespace) -> int:
    pane = args.pane
    sys.stdout.write(f"\033]0;boop {pane}\007")  # the window's title
    if pane in ("A", "B"):
        tail = Tail(ROOT / pane / "app.log")
        print(f"boop {pane}: following {tail.path}", flush=True)
        try:
            while True:
                for line in tail.read():
                    print(line, flush=True)
                time.sleep(0.2)
        except KeyboardInterrupt:
            return 0
    tails = {b: Tail(ROOT / b / "debug.jsonl") for b in ("A", "B")}
    show = transcript_line if pane == "transcript" else Jev().line
    print(f"boop {pane}: following {', '.join(str(t.path) for t in tails.values())}", flush=True)
    try:
        while True:
            lines = []
            for buddy, t in tails.items():
                for line in t.read():
                    try:
                        lines.append((buddy, json.loads(line)))
                    except ValueError:
                        pass
            # A's and B's in time order; stable, so each file's own order holds.
            lines.sort(key=lambda bo: (bo[1].get("event") or {}).get("at") or bo[1].get("received_at_ms") or 0)
            for buddy, o in lines:
                out = show(buddy, o)
                if out:
                    print(out, flush=True)
            time.sleep(0.2)
    except KeyboardInterrupt:
        return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("up", help="start both simulators and both apps, and open the four windows")
    p.add_argument("--brain", choices=["jev", "scripted"],
                   help="the apps' brain: jev with BOOP_JEV_KEY set, else scripted")
    p.add_argument("--face", default="pixel", choices=["pixel", "gel"], help="the simulators' face (pixel)")
    p.add_argument("--no-windows", action="store_true", help="print the four windows' commands, don't open them")
    p.set_defaults(func=up)
    p = sub.add_parser("follow", help="one window: A, B, transcript or jev")
    p.add_argument("pane", choices=PANES)
    p.set_defaults(func=follow)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
