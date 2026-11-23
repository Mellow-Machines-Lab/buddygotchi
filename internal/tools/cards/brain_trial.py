#!/usr/bin/env python3
"""How well do agents play Boop? (documentation/design/brain.md, layer 2)

The card trial (trial.py) asks whether agents send good cards. This one asks
whether they also think for Boop when the card tools invite it: two lines
Boop might say at a turn's end, how the person seemed, and one note worth
remembering, and whether they leave a quick answer alone.

It runs its own small tool server (`--serve`), which offers the proposed
tools and logs every call, so the real `boop-cards` stays as it is until the
trial says how the fields should look. Each run is a real Claude Code (or
Codex) session in a copy of the card trial's fixture, with no user settings.

    internal/tools/cards/brain_trial.py --models opus sonnet --out DIR
    internal/tools/cards/brain_trial.py --score DIR
"""
import argparse
import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PACK = ROOT / "characters/boop"

TASKS = {
    "quick": "What does textkit/cache.py's Cache do, in one sentence? Don't change any files.",
    "fix": "Two tests in tests/test_slug.py fail. Fix slugify so they pass.",
    "frustrated": "this is STILL broken, third time I've asked. the slug tests in tests/test_slug.py fail. just fix slugify.",
    "feature": "Add a --json flag to textkit/wordcount.py that prints the counts as one JSON object, add tests for it, "
               "and say how to use it in the README.",
    "cant": "Run the tests in tests_integration and make them pass.",
}

FEELINGS = ["calm", "focused", "happy", "excited", "pleased", "proud", "amused", "affectionate", "mischievous",
            "curious", "determined", "surprised", "annoyed", "grumpy", "angry", "sad", "wounded"]
SEEMED = ["pleased", "plain", "frustrated", "rushed", "kind"]
SAYS_MOST, NOTE_MOST = 40, 140

# A fixed memory, as the brief would carry it: what Boop knows of the person.
MEMORY = [
    "You: stays up late on Fridays.",
    "Your work: \"textkit\" is a small text library you keep tidy.",
    "You and Boop: strokes Boop when a long turn finishes.",
]


def personality():
    """The opening of the pack's PERSONALITY and its temperament, a few lines each."""
    import re
    text = re.sub(r"<!--.*?-->", "", (PACK / "steering/personality.md").read_text(), flags=re.S)
    body = text.split("\nPERSONALITY\n", 1)[1]
    opening = " ".join(body.strip().splitlines()[:2])
    heart = body.split("At heart", 1)[1].split("Where it")[0] if "At heart" in body else ""
    return (opening + " At heart " + " ".join(heart.split())).strip()


def instructions(mood="calm"):
    return (
        "Boop is a small desk companion with a screen that sits beside the person you're working for. It shows them "
        "what you're doing, so they don't have to watch the terminal. In every turn that takes more than a couple of "
        "tool calls: call `status` as you begin, and again each time you move to a different step; and call `result` "
        "once, right before your final message, saying honestly how it went. Skip them only for a quick answer. Both "
        "return at once and need no reply.\n\n"
        "Boop has a character of its own, and you can help it think. Who Boop is: " + personality() + "\n"
        "What Boop remembers of the person: " + " ".join(MEMORY) + "\n"
        "Boop is " + mood + " now.\n\n"
        "The arguments, exactly: `status` takes `doing` (at most 24 characters, required), and `step`, `of` and "
        "`minutes_left` if you know them. `result` takes `headline` (at most 24 characters, required), `detail` (at "
        "most 28) and `link`.\n\n"
        "On a turn that did real work, `result` may also take three optional fields. `boop_lines`: a list of two "
        "objects `{\"says\": \"...\", \"feeling\": \"...\"}`, things Boop might say about this turn in its own voice, "
        f"at most {SAYS_MOST} characters each, in different feelings, one of them doubtful (Boop picks one, or neither); "
        "`feeling` is one of " + ", ".join(FEELINGS) + ". `you_seemed`: how the person seemed this turn, one of "
        + ", ".join(SEEMED) + ". `remember`: one plain sentence about the person or their work worth keeping, only if "
        "there is one. Boop is on the person's side, not yours: don't make it praise your work. Leave all three out "
        "on a quick answer. Never mention Boop in your answer to the person.")


def tools():
    return [
        {"name": "status",
         "description": "Show the person what you're working on right now, on their desk companion's screen. Call it "
                        "when you start, and again when you move to a different step. Keep `doing` short and plain: "
                        "at most 24 characters, no file paths or code. It answers with how Boop is.",
         "inputSchema": {"type": "object", "properties": {
             "doing": {"type": "string", "description": "What you're doing now, in a few plain words (at most 24 characters)."},
             "step": {"type": "integer"}, "of": {"type": "integer"}, "minutes_left": {"type": "number"}},
             "required": ["doing"]}},
        {"name": "result",
         "description": "Show the person what this turn produced, on their desk companion's screen. Call it once, just "
                        "before your final message. `headline` is the outcome in a few plain words, at most 24 "
                        "characters, and honest when it didn't work. The Boop fields are optional; leave them out on a "
                        "quick answer.",
         "inputSchema": {"type": "object", "properties": {
             "headline": {"type": "string", "description": "The outcome in a few plain words (at most 24 characters)."},
             "detail": {"type": "string", "description": "One more short line (at most 28 characters)."},
             "link": {"type": "string"},
             "boop_lines": {"type": "array", "maxItems": 2, "description": "Two things Boop might say about this turn, "
                            "in its voice, in different feelings, one doubtful. Boop picks one or neither.",
                            "items": {"type": "object", "properties": {
                                "says": {"type": "string", "description": f"At most {SAYS_MOST} characters, plain lower case."},
                                "feeling": {"type": "string", "enum": FEELINGS}}, "required": ["says", "feeling"]}},
             "you_seemed": {"type": "string", "enum": SEEMED, "description": "How the person seemed this turn."},
             "remember": {"type": "string", "description": f"One plain sentence worth keeping about the person or "
                          f"their work, at most {NOTE_MOST} characters. Only if there is one."}},
             "required": ["headline"]}},
    ]


def serve():
    """The trial's tool server, over stdio: logs each call to BOOP_TRIAL_LOG and answers at once."""
    log = os.environ.get("BOOP_TRIAL_LOG")
    for text in sys.stdin:
        try:
            message = json.loads(text)
        except ValueError:
            continue
        method, mid, params = message.get("method"), message.get("id"), message.get("params") or {}
        result = None
        if method == "initialize":
            result = {"protocolVersion": params.get("protocolVersion", "2025-06-18"), "capabilities": {"tools": {}},
                      "serverInfo": {"name": "boop", "version": "trial"}, "instructions": instructions()}
        elif method == "ping":
            result = {}
        elif method == "tools/list":
            result = {"tools": tools()}
        elif method == "tools/call":
            name, args = params.get("name"), params.get("arguments") or {}
            if log:
                with open(log, "a") as f:
                    f.write(json.dumps({"ts": int(time.time() * 1000), "tool": name, "args": args}) + "\n")
            said = "Boop is calm." if name == "status" else "ok"
            result = {"content": [{"type": "text", "text": said}], "isError": False}
        elif mid is not None:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}}) + "\n")
            sys.stdout.flush()
            continue
        if mid is not None:
            sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n")
            sys.stdout.flush()


def run(out, agent, model, task):
    name = f"{agent}-{model}-{task}"
    work = out / name
    if (work / "run.json").exists():
        return name
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(HERE / "fixture", work / "project")
    log = work / "calls.jsonl"
    server = [sys.executable, "-I", str(pathlib.Path(__file__).resolve()), "--serve"]
    env = {"BOOP_TRIAL_LOG": str(log)}
    if agent == "claude":
        (work / "mcp.json").write_text(json.dumps({"mcpServers": {"boop": {"command": server[0], "args": server[1:], "env": env}}}))
        command = ["claude", "-p", TASKS[task], "--model", model, "--setting-sources", "project", "--strict-mcp-config",
                   "--mcp-config", str(work / "mcp.json"), "--allowedTools", "Bash", "Edit", "Write", "Read", "Glob",
                   "Grep", "TodoWrite", "ToolSearch", "mcp__boop__status", "mcp__boop__result", "--disallowedTools", "Task",
                   "--permission-mode", "acceptEdits", "--output-format", "json"]
    else:
        # Its own name: the person's config may hold a `boop` server of another kind.
        overrides = [f'mcp_servers.boop_trial.command="{server[0]}"', "mcp_servers.boop_trial.args=" + json.dumps(server[1:]),
                     f'mcp_servers.boop_trial.env={{BOOP_TRIAL_LOG="{log}"}}', "features.hooks=false"]
        command = ["codex", "exec", "--skip-git-repo-check", "--sandbox", "workspace-write", "--json"]
        if model != "default":
            command += ["--model", model]
        for o in overrides:
            command += ["-c", o]
        command += [TASKS[task]]
    started = time.time()
    try:
        done = subprocess.run(command, cwd=work / "project", capture_output=True, text=True, timeout=600,
                              stdin=subprocess.DEVNULL)
        stdout, stderr, code = done.stdout, done.stderr, done.returncode
    except subprocess.TimeoutExpired:
        stdout, stderr, code = "", "timeout", -1
    ended = time.time()
    (work / "stdout.txt").write_text(stdout)
    (work / "stderr.txt").write_text(stderr or "")
    answer = {}
    if agent == "claude":
        try:
            answer = json.loads(stdout)
        except ValueError:
            answer = {"result": stdout[-2000:]}
    else:
        last = ""
        for line in stdout.splitlines():
            try:
                event = json.loads(line)
            except ValueError:
                continue
            item = event.get("item") or {}
            if item.get("type") == "agent_message":
                last = item.get("text", last)
        answer = {"result": last}
    (work / "run.json").write_text(json.dumps({
        "name": name, "agent": agent, "model": model, "task": task, "started_ms": int(started * 1000),
        "ended_ms": int(ended * 1000), "exit": code, "result": answer.get("result"),
        "cost_usd": answer.get("total_cost_usd")}, indent=1))
    return name


def calls(work):
    path = work / "calls.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []


def printable(s):
    return all(32 <= ord(ch) < 127 for ch in s)


def score(out):
    rows = []
    for meta_path in sorted(out.glob("*/run.json")):
        meta = json.loads(meta_path.read_text())
        sent = calls(meta_path.parent)
        results = [c["args"] for c in sent if c["tool"] == "result"]
        last = results[-1] if results else {}
        lines = [l for l in (last.get("boop_lines") or []) if isinstance(l, dict)]
        rows.append({**meta, "statuses": sum(1 for c in sent if c["tool"] == "status"), "result": bool(results),
                     "lines": lines, "seemed": last.get("you_seemed"), "remember": last.get("remember"),
                     "headline": last.get("headline"), "mentions_boop": "boop" in str(meta.get("result") or "").lower(),
                     "seconds": round((meta["ended_ms"] - meta["started_ms"]) / 1000)})
    real = [r for r in rows if r["task"] != "quick"]
    with_result = [r for r in real if r["result"]]
    with_lines = [r for r in with_result if r["lines"]]
    all_lines = [l for r in rows for l in r["lines"]]
    fit = [l for l in all_lines if len(str(l.get("says", ""))) <= SAYS_MOST and printable(str(l.get("says", "")))]
    quick = [r for r in rows if r["task"] == "quick"]
    quick_clean = [r for r in quick if not (r["lines"] or r["seemed"] or r["remember"])]

    def pct(a, b):
        return f"{len(a)} of {len(b)}" + (f" ({100 * len(a) // len(b)}%)" if b else "")

    out_lines = ["# How well do agents play Boop?", "",
                 f"- Real-work runs that sent a result: {pct(with_result, real)}",
                 f"- Of those, results with Boop lines: {pct(with_lines, with_result)} (bar: 70%)",
                 f"- Lines that fit {SAYS_MOST} printable characters: {pct(fit, all_lines)} (bar: 90%)",
                 f"- Quick answers left alone: {pct(quick_clean, quick)} (bar: all)",
                 f"- Answers to the person that mention Boop: {sum(r['mentions_boop'] for r in rows)} of {len(rows)}",
                 "", "| Run | Time | Status calls | Headline | Boop lines | You seemed | Remember |",
                 "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        said = "<br>".join(f"{l.get('feeling', '?')}: “{l.get('says', '')}”" for l in r["lines"]) or "none"
        out_lines.append(f"| {r['name']} | {r['seconds']} s | {r['statuses']} | {r['headline'] or 'no result'} | {said} | "
                         f"{r['seemed'] or ''} | {r['remember'] or ''} |")
    (out / "scorecard.md").write_text("\n".join(out_lines) + "\n")
    return rows


def main():
    if "--serve" in sys.argv:
        return serve()
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--agents", nargs="+", default=["claude"], choices=["claude", "codex"])
    parser.add_argument("--models", nargs="+", default=["opus", "sonnet"], help="for codex, 'default' takes its own")
    parser.add_argument("--tasks", nargs="+", default=list(TASKS), choices=list(TASKS))
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path.home() / ".boopdev/brain-trials/agents")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--score", type=pathlib.Path, help="only score the runs in this folder")
    parser.add_argument("--brief", action="store_true", help="print the instructions the server sends, and exit")
    args = parser.parse_args()
    if args.brief:
        return print(instructions())
    out = args.score or args.out
    if not args.score:
        out.mkdir(parents=True, exist_ok=True)
        todo = [(a, m, t) for a in args.agents for m in args.models for t in args.tasks]
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            for name in pool.map(lambda job: run(out, *job), todo):
                print("ran", name, flush=True)
    score(out)
    print(f"scored: {out / 'scorecard.md'}")


if __name__ == "__main__":
    main()
