"""Claude Code in the Claude desktop app, in place of a terminal.

The app sets its own model address for every Claude Code it starts, so its
model can't be replayed. Instead the real model performs the script,
openly: the run's copy of the project gets a `/demo` command that is the
script's agent steps, word for word (`script`), and settings that send that
session's hooks to the run's Boop and add the gate (`prepare`). Both go
into the project's first commit, since the app runs each session in a git
worktree of its own. The session opens through the app's link,
`claude://code/new?folder=…`; you type `/demo`, send it, and allow what
it asks, in the app.
"""
from __future__ import annotations

import json
import subprocess
import urllib.parse
from pathlib import Path
from typing import Any, Dict, List

from script import git, said


def prepare(ws: Path, settings: Dict[str, Any], demo: str) -> None:
    """Writes the run's settings and its `/demo` command into the project,
    and folds them into its first commit, so a worktree made from it has
    them and the agent's diff doesn't show them."""
    folder = ws / ".claude"
    (folder / "commands").mkdir(parents=True, exist_ok=True)
    (folder / "settings.json").write_text(json.dumps(settings, indent=2))
    (folder / "commands" / "demo.md").write_text(demo)
    git(ws, "add", "-A")
    git(ws, "commit", "-q", "--amend", "--no-edit")


def open_session(ws: Path) -> None:
    """A new Code session in the app, in the project. You type /demo: the
    app's prompt box turns a /demo its link fills in into "/ demo"."""
    url = "claude://code/new?" + urllib.parse.urlencode({"folder": str(ws)})
    subprocess.run(["open", url], check=False)


def fence(text: str) -> str:
    return "````\n" + text + "\n````"


def call_words(l: Dict[str, Any], prompt: str = "") -> str:
    """An agent step's tool call, as an exact instruction."""
    does = l["agent"]
    if does == "read":
        return f"Use the Read tool on `{l['file']}`."
    if does == "edit":
        return (f"Use the Edit tool on `{l['file']}`, replacing exactly this text:\n\n{fence(l['old'])}\n\n"
                f"with exactly this text:\n\n{fence(l['new'])}")
    if does == "run":
        return f"Use the Bash tool to run exactly `{l['cmd']}`, with the description \"{l.get('about', l['cmd'])}\"."
    return (f"Use the Agent tool, with the description \"{l['task']}\" and exactly this prompt:\n\n"
            f"{fence(prompt)}\n\nIt runs in the background.")


def script(replies: List[Dict[str, Any]], title: str) -> str:
    """The script's agent steps as the `/demo` command: what to say and
    which tool to call, in order, word for word. The person runs it,
    knowing it's a demo; nothing in it is hidden."""
    reviewer = [l for l in replies if l.get("by") == "reviewer"]
    main = [l for l in replies if l.get("by") != "reviewer"]
    lines = [
        "---",
        f"description: Perform the scripted demo: {title}",
        "---",
        "",
        "I'm recording a scripted demo of this project, and I'd like you to perform it with me. The",
        "steps below are the script: please perform them exactly, in order, one at a time.",
        "",
        "- For each step, write its words as your message, exactly as given, then make its tool",
        "  call, exactly as given, and nothing else. When the result comes back, go straight on to",
        "  the next step.",
        "- Make no other tool calls and say nothing else: no plans, no summaries, no comments on",
        "  results, and no other files.",
        "- Whatever a tool returns, go on to the next step: the results are part of the demo. Some",
        "  of the project is a stand-in made for it, such as the browser checks.",
        "- A step with no tool call ends your turn.",
        "",
        "## Your steps",
        "",
    ]
    for n, l in enumerate(main, 1):
        lines.append(f"### Step {n}")
        if said(l):
            lines += ["", "Say exactly:", "", fence(said(l))]
        if l["agent"] == "reply":
            lines += ["", "Then end your turn" + (" and wait." if n < len(main) else ".")]
        else:
            prompt = reviewer_prompt(l.get("prompt", l.get("task", "")), reviewer) if l["agent"] == "review" else ""
            lines += ["", call_words(l, prompt)]
        lines.append("")
    if reviewer:
        lines += [
            "After the Agent call, the reviewer works in the background. Do the next step at once,",
            "which ends your turn. When the reviewer's report arrives, do the step after it.",
        ]
    return "\n".join(lines)


def reviewer_prompt(prompt: str, reviewer: List[Dict[str, Any]]) -> str:
    """A subagent's prompt with its part of the script in it, since it
    doesn't see the /demo command."""
    steps = []
    for l in reviewer:
        if l["agent"] == "reply":
            steps.append(f"Then reply with exactly: \"{l['text']}\"")
        else:
            if l.get("say"):
                steps.append(f"Say: \"{l['say']}\"")
            steps.append(call_words(l).replace("Use the Bash tool to run", "Run"))
    return prompt + " This is part of a scripted demo: " + " ".join(steps)
