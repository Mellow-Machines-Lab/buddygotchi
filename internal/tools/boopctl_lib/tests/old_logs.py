"""The fixtures are logs from before the device kept a queue: the Mac sent a
`moment`, which played at once, and `sent` lines had no `by`. `as_do`
rewrites such a line as the Mac writes it today, a `do` (linkkit/SPEC.md §3),
so a test can check that a reader makes the same of both. The tests put
this folder on sys.path before importing it."""
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
