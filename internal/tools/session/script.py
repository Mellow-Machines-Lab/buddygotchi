"""A demo script, as the session tool reads it, and what its pieces share.

The script is a character pack's `demo/<name>.jsonl`, the same one Boop
plays (`DemoScript` in app/BoopKit/Demo/, which describes every line).
Boop does the person's and the brain's lines and keeps to the agent's;
this tool needs only the agent's: what the model says and calls, for the
replay server and the `/demo` command, and which line each tool call is,
for the gate. A line's number, `n`, is its place among the script's lines,
from 0, as Boop counts them in its cursor file.

    script.py which NAME     prints the script `make demo NAME=…` plays
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional

REPO = Path(__file__).resolve().parents[3]

# The identity a demo project's commits are by.
GIT_ENV = {"GIT_AUTHOR_NAME": "Demo", "GIT_AUTHOR_EMAIL": "demo@example.com",
           "GIT_COMMITTER_NAME": "Demo", "GIT_COMMITTER_EMAIL": "demo@example.com"}


class ScriptError(Exception):
    pass


@dataclass
class Script:
    path: Path
    title: str
    lines: List[Dict[str, Any]] = field(default_factory=list)

    @property
    def name(self) -> str:
        return self.path.stem

    def agent_lines(self) -> List[Dict[str, Any]]:
        return [l for l in self.lines if "agent" in l]

    @property
    def prompt(self) -> Dict[str, Any]:
        return next(l for l in self.lines if l.get("agent") == "prompt")

    def replies(self) -> List[Dict[str, Any]]:
        """The model's replies: every agent line after the prompt, each one
        turn of the main thread's or, `"by": "reviewer"`, the subagent's."""
        return [l for l in self.agent_lines() if l["agent"] != "prompt"]


def said(l: Dict[str, Any]) -> Optional[str]:
    """What an agent line's model says: a reply's text, or what it says
    before it acts."""
    return l["text"] if l["agent"] == "reply" else l.get("say")


def target(l: Dict[str, Any]) -> Optional[str]:
    """What a tool call of this line names, to tell it from others: the
    file, the command, or nothing (a review: any subagent call)."""
    return l.get("file") or l.get("cmd")


def cursor_at(path: Path) -> int:
    """The line Boop's cursor file says is due: -1 before the script starts."""
    try:
        return int(path.read_text().strip())
    except (OSError, ValueError):
        return -1


def git(ws: Path, *argv: str) -> None:
    subprocess.run(["git", *argv], cwd=ws, env=dict(GIT_ENV, PATH=os.environ.get("PATH", "/usr/bin:/bin")),
                   check=True, stdout=subprocess.DEVNULL)


def load(path: Path) -> Script:
    if not path.exists():
        raise ScriptError(f"no script at {path}")
    title = ""
    lines: List[Dict[str, Any]] = []
    for number, raw in enumerate(path.read_text().split("\n"), 1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError as e:
            raise ScriptError(f"{path.name}:{number}: not JSON ({e})")
        if "demo" in obj:
            title = obj.get("title", "")
            continue
        obj["n"] = len(lines)
        obj["number"] = number
        lines.append(obj)
    if not any(l.get("agent") == "prompt" for l in lines):
        raise ScriptError(f"{path.name}: no prompt, so no agent can play it")
    return Script(path=path, title=title, lines=lines)


def find(name: str) -> Path:
    """A pack's demo by name: the chosen pack's (characters/CHARACTER.md
    §2), else the one pack in characters/ that has it."""
    chosen = subprocess.run([sys.executable, str(REPO / "characters/charactergen.py"), "--which"],
                            capture_output=True, text=True).stdout.strip()
    if chosen and (Path(chosen) / "demo" / f"{name}.jsonl").exists():
        return Path(chosen) / "demo" / f"{name}.jsonl"
    found = sorted(REPO.glob(f"characters/*/demo/{name}.jsonl"))
    if not found:
        have = sorted({p.stem for p in REPO.glob("characters/*/demo/*.jsonl")})
        raise ScriptError(f"no pack has demo/{name}.jsonl; there are: {', '.join(have)}")
    if len(found) > 1:
        raise ScriptError(f"more than one pack has demo/{name}.jsonl: choose one with CHARACTER=<pack>")
    return found[0]


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "which":
        try:
            print(find(sys.argv[2]))
        except ScriptError as e:
            sys.exit(f"demo: {e}")
    else:
        sys.exit(__doc__.split("\n\n")[1])
