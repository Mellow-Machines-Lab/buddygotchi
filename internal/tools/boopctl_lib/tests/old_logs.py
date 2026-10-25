"""The fixtures are logs from before the device kept a queue: the Mac sent a
`moment`, which played at once, and `sent` lines had no `by`. `as_do`
rewrites such a line as the Mac writes it today, a `do` (linkkit/SPEC.md §3),
so a test can check that a reader makes the same of both. Their passes
ask today's reaction questions; `with_old_keys` asks them as logs did
before the questions were regrouped, so a test can check the same of
those. The tests put this folder on sys.path before importing it."""
from __future__ import annotations

from typing import Any

Line = dict[str, Any]


def as_do(line: Line) -> Line:
    """A debug.jsonl line with its `sent` moment as the `do` the Mac sends
    for it: the animation as the name, a face or a `say` with none as
    `react`, the empty moment (push-to-talk ending) as `stop_listening`,
    the rest in `args`; the brain's with their `id`, waiting in the queue for
    up to 5 s, the rules' only if nothing plays. Each gets the `by` the
    old reader guessed (a moment with a face was the brain's). Names are
    kept, older ones included, so what a reader shows of the two is the
    same. Any other line is left as it is."""
    msg = line.get("sent")
    if not isinstance(msg, dict) or msg.get("t") != "moment":
        return line
    args = {k: v for k, v in msg.items() if k not in ("t", "anim", "id")}
    by = line.get("by") or ("brain" if msg.get("mood") else "rule")
    do: Line = {"t": "do"}
    if "id" in msg:
        do["id"] = msg["id"]
    do["name"] = msg.get("anim") or ("react" if args else "stop_listening")
    do["play"] = "next" if by == "brain" else "if_free"
    if by == "brain":
        do["ttl"] = 5000
    if args:
        do["args"] = args
    return {**line, "sent": do, "by": by}


# Today's reaction keys and the ones a log had before them: the face was
# `react.mood`, the move `react.animation`, the intensity `react.loops` (how
# long it held), and what it says a feeling, `say.feeling`, or a topic,
# `say.about`, with how big a take, `say.kind`.
OLD_KEYS = {"react.face": "react.mood", "react.move": "react.animation", "react.intensity": "react.loops"}
HOLDS = {"small": "once", "medium": "twice", "big": "three times", "huge": "four times"}
FEELINGS = {"upset", "glad", "tickled"}


def with_old_keys(line: Line) -> Line:
    """A debug.jsonl line with its pass's answers under the keys logs had
    before the reaction's questions were regrouped; any other line is left
    as it is."""
    p = line.get("pass")
    if not isinstance(p, dict) or not p.get("answers"):
        return line
    answers: Line = {}
    for key, a in p["answers"].items():
        if key == "react.intensity":
            a = {"choice": HOLDS[a["choice"]], "p": {HOLDS[c]: v for c, v in a["p"].items()}}
        if key == "say":
            feeling = a["choice"] in FEELINGS
            answers["say.feeling" if feeling else "say.about"] = a
            answers["say.about" if feeling else "say.feeling"] = {"choice": "none", "p": {"none": 1}}
            answers["say.kind"] = {"choice": "word", "p": {"word": 1}}
            continue
        answers[OLD_KEYS.get(key, key)] = a
    questions = [k for key in p.get("questions", []) for k in
                 (["say.feeling", "say.about", "say.kind"] if key == "say" else [OLD_KEYS.get(key, key)])]
    return {**line, "pass": {**p, "answers": answers, **({"questions": questions} if "questions" in p else {})}}
