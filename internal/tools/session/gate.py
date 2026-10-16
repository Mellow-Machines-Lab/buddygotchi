#!/usr/bin/env python3
"""The demo's gate: a PreToolUse hook that holds each of the agent's tool
calls until the script reaches its step, so a live agent can't run ahead of
the person's and the brain's steps in between.

    gate.py --script DEMO.jsonl --cursor STATE/demo-cursor

Only a demo's project has it, in its own settings, apart from Boop's hooks,
which only report. It reads the hook's input, finds the first step from the
one due that this call is (its file or command, or any subagent call for a
review), and waits until Boop's cursor file says that step is due. A call
the script doesn't have goes at once, and so does every call if the cursor
stays put for `--patience` seconds: the gate never holds an agent for good.
It says nothing and exits 0, which lets the call run.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import script as scripts  # noqa: E402

SUBAGENT_TOOLS = ("Agent", "Task")


def step_for(call: dict, steps: list, since: int):
    """The number of the script's step this call is, from `since` on: a
    review's for a subagent call, else the first whose file or command it
    names."""
    text = json.dumps(call.get("tool_input", call))
    tool = call.get("tool_name", "")
    for l in steps[max(0, since):]:
        if l.get("agent") == "review" and tool in SUBAGENT_TOOLS:
            return l["n"]
        if l.get("agent") in ("read", "edit", "run") and scripts.target(l) in text:
            return l["n"]
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--script", required=True)
    parser.add_argument("--cursor", required=True)
    parser.add_argument("--patience", type=float, default=90)
    args = parser.parse_args()
    try:
        call = json.load(sys.stdin)
        steps = scripts.load(Path(args.script)).steps
    except Exception:
        return 0  # never stand in the way
    cursor = Path(args.cursor)
    tool = call.get("tool_name", "?")
    n = step_for(call, steps, scripts.cursor_at(cursor))
    if n is None:
        note(cursor, f"{tool}: not in the script, goes at once")
        return 0
    start = time.time()
    last, still = scripts.cursor_at(cursor), start
    while last < n:
        time.sleep(0.15)
        now = scripts.cursor_at(cursor)
        if now != last:
            last, still = now, time.time()
        elif time.time() - still > args.patience:
            note(cursor, f"{tool}: step {n}, but the script stayed at {last}: let it go")
            return 0
    note(cursor, f"{tool}: step {n}, held {time.time() - start:.1f} s")
    return 0


def note(cursor: Path, text: str) -> None:
    """A line in gate.log beside the cursor, for whoever checks a recording."""
    try:
        with open(cursor.parent / "gate.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {text}\n")
    except OSError:
        pass


if __name__ == "__main__":
    sys.exit(main())
