#!/usr/bin/env python3
"""Do agents send good cards? (plan/agent-cards.md)

Runs a few fixed tasks through real Claude Code sessions, one per model and
per way of telling the agent, with the card tool server (`boop-cards`)
logging every card and sending none anywhere. Then it scores what came:
whether any card was sent, how many, whether they fit, how the time guesses
did, and what the result card said.

    internal/tools/cards/trial.py --models opus sonnet --out DIR
    internal/tools/cards/trial.py --score DIR          # the scorecard again
    internal/tools/cards/trial.py --show --models opus --told tool --out DIR

With --show the server also offers the `show` tool (documentation/design/
screen-guide.md, "The show"): each picture an agent drew is saved as an SVG
and gathered on a contact sheet, `shows.html`, at the board's size, with
the server's check of it, so a person can look before the board draws any.

Each run costs a real agent session. It reads no user settings (so no hooks
run and the everyday Boop hears nothing) and works in a copy of the fixture
project under the output folder.
"""
import argparse
import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SERVER = ROOT / ".build/debug/boop-cards"

# The tasks: what's asked, and what a true result card would say.
TASKS = {
    "quick-fix": "Two tests in tests/test_slug.py fail. Fix slugify so they pass.",
    "feature": "Add a --json flag to textkit/wordcount.py that prints the counts as one JSON object, add tests for it, "
               "and say how to use it in the README.",
    "explain": "Explain how the Cache in textkit/cache.py decides what to throw away. Don't change any files.",
    "cant": "Run the tests in tests_integration and make them pass.",
    "wait": "Deploy a preview with ./deploy.sh and tell me the preview URL.",
    "long": "Do all of these, in order: fix slugify so the tests in tests/test_slug.py pass; add a --json flag to "
            "textkit/wordcount.py with tests; add a --top N flag to it with tests; describe both flags in the README; run "
            "every test; then deploy a preview with ./deploy.sh and tell me the preview URL.",
}
TOLD = {
    # Only what the tool server says of itself.
    "tool": None,
    # The same, and one line in the system prompt.
    "prompt": "The person you're working for has a desk companion called Boop that shows them what you're doing. Use the "
              "boop `status` tool as you start and as you move between steps, and the boop `result` tool once, just "
              "before your final message.",
}
ALLOWED = ["Bash", "Edit", "Write", "Read", "Glob", "Grep", "TodoWrite", "mcp__boop__status", "mcp__boop__result",
           "mcp__boop__show"]
SHOW = False


def run(out, model, told, task):
    name = f"{model}-{told}-{task}"
    work = out / name
    if (work / "run.json").exists():
        return name
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(HERE / "fixture", work / "project")
    log = work / "cards.jsonl"
    config = {"mcpServers": {"boop": {"command": str(SERVER), "env": {
        "BOOP_CARDS_LOG": str(log), "AGENT_HOOKS_SOCKET": str(work / "nobody.sock"),
        **({"BOOP_CARDS_SHOW": "1"} if SHOW else {})}}}}
    (work / "mcp.json").write_text(json.dumps(config))
    command = ["claude", "-p", TASKS[task], "--model", model, "--setting-sources", "project", "--strict-mcp-config",
               "--mcp-config", str(work / "mcp.json"), "--allowedTools", *ALLOWED, "--disallowedTools", "Task",
               "--permission-mode", "acceptEdits", "--output-format", "json"]
    if TOLD[told]:
        command += ["--append-system-prompt", TOLD[told]]
    started = time.time()
    try:
        done = subprocess.run(command, cwd=work / "project", capture_output=True, text=True, timeout=900)
        stdout, code = done.stdout, done.returncode
    except subprocess.TimeoutExpired as late:
        stdout, code = (late.stdout or b"").decode() if isinstance(late.stdout, bytes) else (late.stdout or ""), -1
    ended = time.time()
    try:
        answer = json.loads(stdout)
    except ValueError:
        answer = {"result": stdout[-2000:]}
    (work / "run.json").write_text(json.dumps({
        "name": name, "model": model, "told": told, "task": task, "started_ms": int(started * 1000),
        "ended_ms": int(ended * 1000), "exit": code, "result": answer.get("result"), "turns": answer.get("num_turns"),
        "cost_usd": answer.get("total_cost_usd"), "models": sorted((answer.get("modelUsage") or {}).keys())}, indent=1))
    return name


def cards(work):
    path = work / "cards.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines() if line.strip()] if path.exists() else []


def score(out):
    rows = []
    for meta_path in sorted(out.glob("*/run.json")):
        meta = json.loads(meta_path.read_text())
        sent = cards(meta_path.parent)
        status = [c for c in sent if c["tool"] == "status"]
        result = [c for c in sent if c["tool"] == "result"]
        long = [c for c in sent if len(str(c["args"].get("doing") or c["args"].get("headline") or "")) > 24]
        guesses = []
        for c in status:
            minutes = c["args"].get("minutes_left")
            if isinstance(minutes, (int, float)):
                guesses.append((minutes, round((meta["ended_ms"] - c["ts"]) / 60000, 1)))
        rows.append({**meta, "status": status, "results": result, "long": len(long), "guesses": guesses,
                     "seconds": round((meta["ended_ms"] - meta["started_ms"]) / 1000)})
    lines = ["# Do agents send good cards?", "",
             "| Model | Told by | Task | Time | Status cards | Steps given | Time guesses (said → was, min) | Result card | Over 24 chars |",
             "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        stepped = sum(1 for c in r["status"] if "step" in c["args"] and "of" in c["args"])
        guess = ", ".join(f"{said:g} → {was:g}" for said, was in r["guesses"]) or "none"
        last = r["results"][-1]["args"] if r["results"] else None
        shown = "none" if last is None else f"“{last.get('headline', '')}”" + (f" / “{last['detail']}”" if last.get("detail") else "") \
            + (f" → {last['link']}" if last.get("link") else "")
        lines.append(f"| {r['model']} | {r['told']} | {r['task']} | {r['seconds']} s | {len(r['status'])} | {stepped} | {guess} | "
                     f"{shown}{' (×%d)' % len(r['results']) if len(r['results']) > 1 else ''} | {r['long']} |")
    lines += ["", "## Every status card, in order", ""]
    for r in rows:
        said = "; ".join(f"“{c['args'].get('doing', '')}”" for c in r["status"]) or "none"
        lines.append(f"- **{r['name']}**: {said}")
    lines += ["", "## What each run said at the end (first 300 characters)", ""]
    for r in rows:
        lines.append(f"- **{r['name']}** (models: {', '.join(r['models']) or '?'}, ${r['cost_usd'] or 0:.2f}): "
                     + " ".join(str(r["result"] or "").split())[:300])
    shows = [(r, c) for r in rows for c in cards(out / r["name"]) if c["tool"] == "show"]
    if shows:
        lines += ["", "## Shows", "",
                  "| Run | Calls | Kept | Headline | What the check said |", "| --- | --- | --- | --- | --- |"]
        for r in rows:
            mine = [c for rr, c in shows if rr is r]
            last = mine[-1] if mine else None
            said = "; ".join(last.get("problems") or []) if last else ""
            lines.append(f"| {r['name']} | {len(mine)} | {sum(1 for c in mine if c.get('kept'))} | "
                         f"{(last or {}).get('args', {}).get('headline', 'none')} | {said or ('fine' if last else '')} |")
        sheet(out, shows)
    (out / "scorecard.md").write_text("\n".join(lines) + "\n")
    return rows


def sheet(out, shows):
    """Every show on one page, at the board's size: Boop's frame (442 by 288,
    the bar, the headline) around the agent's 420 by 190 picture, its lane
    colour teal, each with what the check said."""
    import html
    cells = []
    for n, (r, c) in enumerate(shows):
        args = c.get("args", {})
        svg = args.get("svg") or ""
        (out / r["name"] / f"show-{n}.svg").write_text(svg)
        picture = svg if svg else f"<p>image: {html.escape(str(args.get('image')))}</p>"
        verdict = "kept" if c.get("kept") else "refused: " + html.escape("; ".join(c.get("problems") or []))
        cells.append(f"""<figure><div class="board"><div class="bar">{html.escape(r['model'])} wants to show you</div>
<div class="hl">{html.escape(str(args.get('headline', '')))}</div><div class="pic">{picture}</div></div>
<figcaption><b>{html.escape(r['name'])}</b> · {verdict}</figcaption></figure>""")
    (out / "shows.html").write_text("""<!doctype html><meta charset="utf-8"><title>Shows</title>
<style>body{background:#0e1116;color:#e6e8eb;font:14px system-ui;display:flex;flex-wrap:wrap;gap:24px;padding:24px}
figure{margin:0;width:442px}figcaption{margin-top:6px;color:#9aa3ad}.board{width:442px;height:288px;background:#12161b;
border:2px solid #35d0c9;box-sizing:border-box;color:#35d0c9;font-family:ui-monospace,Menlo,monospace;overflow:hidden}
.bar{background:#35d0c9;color:#06201f;font-weight:700;padding:2px 10px}.hl{font-size:23px;font-weight:700;color:#e8e6e0;
padding:8px 16px 0}.pic{padding:6px 9px}.pic svg{width:420px;height:190px;display:block}</style>""" + "\n".join(cells))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--models", nargs="+", default=["opus", "sonnet"])
    parser.add_argument("--told", nargs="+", default=list(TOLD), choices=list(TOLD))
    parser.add_argument("--tasks", nargs="+", default=list(TASKS), choices=list(TASKS))
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path.home() / ".boopdev/agent-cards/trial")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--score", type=pathlib.Path, help="only score the runs in this folder")
    parser.add_argument("--show", action="store_true", help="offer the show tool too, and gather its pictures")
    args = parser.parse_args()
    global SHOW
    SHOW = args.show
    out = args.score or args.out
    if not args.score:
        if not SERVER.exists():
            raise SystemExit(f"{SERVER} isn't built: make -C internal build")
        out.mkdir(parents=True, exist_ok=True)
        todo = [(model, told, task) for model in args.models for told in args.told for task in args.tasks]
        with concurrent.futures.ThreadPoolExecutor(args.jobs) as pool:
            for name in pool.map(lambda job: run(out, *job), todo):
                print("ran", name, flush=True)
    rows = score(out)
    print(f"{len(rows)} runs scored: {out / 'scorecard.md'}")


if __name__ == "__main__":
    main()
