"""`boopctl day` (internal/VERIFICATION.md §2): what Boop did in a day, and why,
from debug mode's logs. It reads the state dir's debug.jsonl and the
earlier launches' debug.<n>.jsonl, oldest first, and sums up one local day
by the hour: finishes, working chatter, the brain's reactions and their
faces, alerts, mood changes, passes, and the brain's reactions that didn't
happen; then each mood change with its cause, each time something needed
you and how long it took to clear, and why reactions didn't happen. What
the dashboard forced is counted apart from the brain.

It reads only the lines, like the dashboard (dash/feed.py): what was sent
to the device (`sent`) and how the device said each `do` went (`ended`),
the transcript's actions (`event`), what the brain heard (`view`), the
passes (`pass`) and `status`. A failed action's message is its reason,
so that one is shown; no other message is parsed."""
from __future__ import annotations

import json
import re
import statistics
import time
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from boopctl_lib.common import FINISHES, call
from boopctl_lib.dash.feed import action, action_end, kind, sent_by, view_name

Line = dict[str, Any]
LOG = "debug.jsonl"
KEPT = re.compile(r"debug\.(\d+)\.jsonl")


def launch_files(state_dir: Path) -> list[Path]:
    """The state dir's debug logs, oldest launch first: debug.<n>.jsonl from
    the highest n down, then debug.jsonl."""
    kept = sorted(((int(m.group(1)), p) for p in state_dir.glob("debug.*.jsonl") if (m := KEPT.fullmatch(p.name))),
                  reverse=True)
    return [p for _, p in kept] + ([state_dir / LOG] if (state_dir / LOG).exists() else [])


@dataclass
class Launch:
    """One run of the app: a file, or the part of one from a `questions` line
    (each launch writes one first) to the next."""
    name: str
    lines: list[Line]


def read_launches(paths: list[Path]) -> list[Launch]:
    launches: list[Launch] = []
    for path in paths:
        current = None
        with path.open("rb") as f:
            for raw in f:
                try:
                    line = json.loads(raw)
                except ValueError:
                    continue  # a line cut short by a crash
                if not isinstance(line, dict) or not isinstance(line.get("received_at_ms"), int):
                    continue
                if current is None or ("questions" in line and current.lines):
                    current = Launch(path.name, [])
                    launches.append(current)
                current.lines.append(line)
    return launches


def day_of(ms: int) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ms / 1000))


def day_bounds(date: str) -> tuple[int, int]:
    """[start, end) of a local day, in ms."""
    y, m, d = (int(x) for x in date.split("-"))
    start = time.mktime((y, m, d, 0, 0, 0, 0, 0, -1))
    end = time.mktime((y, m, d + 1, 0, 0, 0, 0, 0, -1))
    return int(start * 1000), int(end * 1000)


def hour_of(ms: int) -> int:
    return time.localtime(ms / 1000).tm_hour


def next_hour(ms: int) -> int:
    t = time.localtime(ms / 1000)
    return int(time.mktime((t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour + 1, 0, 0, 0, 0, -1)) * 1000)


@dataclass
class Hour:
    finishes: int = 0
    chatter: int = 0
    reactions: int = 0
    faces: Counter = field(default_factory=Counter)
    alerts: int = 0
    moods: int = 0
    passes: int = 0
    dropped: int = 0
    missed: int = 0
    pokes: int = 0
    needs_ms: int = 0
    lines: int = 0


@dataclass
class MoodChange:
    at: int
    before: str
    after: str
    why: str | None = None


@dataclass
class NeedsYou:
    """From a `state` bringing `attn` to the first one without it."""
    start: int
    end: int = 0
    who: list[str] = field(default_factory=list)
    alerts: int = 0
    open: bool = False  # still up when its launch's log ends


@dataclass
class Miss:
    at: int
    name: str
    why: str
    forced: bool = False


@dataclass
class Day:
    date: str
    launches: list[tuple[str, int, int, list[str]]] = field(default_factory=list)  # (file, first, last, brains)
    hours: dict[int, Hour] = field(default_factory=dict)
    moods: list[MoodChange] = field(default_factory=list)
    needs: list[NeedsYou] = field(default_factory=list)
    misses: list[Miss] = field(default_factory=list)
    drops: list[Miss] = field(default_factory=list)
    forced: int = 0  # passes forced from the dashboard
    held: Counter = field(default_factory=Counter)  # events held back when their turn came, by why
    forced_reacts: int = 0  # the reactions they asked for
    quiet: int = 0
    skipped: int = 0
    latencies: list[int] = field(default_factory=list)
    connected_ms: int = 0
    running_ms: int = 0

    def total(self) -> Hour:
        out = Hour()
        for h in self.hours.values():
            for name in vars(out):
                setattr(out, name, getattr(out, name) + getattr(h, name))
        return out


def summarise(launches: list[Launch], date: str) -> Day:
    start, end = day_bounds(date)
    day = Day(date)

    def hour(ms: int) -> Hour | None:
        return day.hours.setdefault(hour_of(ms), Hour()) if start <= ms < end else None

    def clip(a: int, b: int) -> tuple[int, int]:
        return max(a, start), min(b, end)

    mood = None  # carried across launches: the mood outlives them, in the transcript
    for launch in launches:
        times = [line["received_at_ms"] for line in launch.lines]
        first, last = min(times), max(times)
        a, b = clip(first, last)
        if a <= b:
            day.running_ms += b - a
        brains: list[str] = []
        attn = None  # (agent, project, id) shown
        episode: NeedsYou | None = None
        changed: MoodChange | None = None  # waiting for the mood output that made it
        seen_state = False
        events: dict[int, Line] = {}
        event_at: dict[int, int] = {}
        passed: set[int] = set()
        names: dict[int, str] = {}
        last_pass: Line = {}  # an action's pass: its entries follow the pass's
        finish_hour: dict[int, Hour] = {}  # each finish sent, by its `do` id, until the device says how it went
        up_since = None
        for line in launch.lines:
            t, k = line["received_at_ms"], kind(line)
            body, seq = line.get(k), line.get("seq")
            h = hour(t)
            if h:
                h.lines += 1
            if k == "sent" and body.get("t") == "state":
                a = body.get("attn")
                # A missing id reads as 0, as on the device.
                shown = (a.get("agent"), a.get("project"), a.get("id", 0)) if a else None
                if shown and shown != attn:  # a new one, or a different one: one alert
                    if episode is None:
                        episode = NeedsYou(t)
                    who = " · ".join(map(str, shown[:2]))
                    if not episode.who or episode.who[-1] != who:
                        episode.who.append(who)
                    if h:
                        h.alerts += 1
                        episode.alerts += 1
                if not shown and episode:
                    episode.end = t
                    day.needs.append(episode)
                    episode = None
                attn = shown
                now = body.get("mood")
                if mood is not None and now != mood:
                    # The mood output saves the mood, the state carries it
                    # at once, and the action's entry follows with its cause.
                    changed = MoodChange(t, mood, now, None if seen_state else "between launches")
                    if h:
                        h.moods += 1
                        day.moods.append(changed)
                mood, seen_state = now, True
            elif k == "sent" and (c := call(body)) and h:
                # A `do`, or an older log's `moment`. The brain's is a
                # reaction, counted from its react output below; an older
                # log's rules' moment with a line is chatter.
                if c["anim"] in FINISHES:
                    h.finishes += 1
                    if c.get("id"):
                        finish_hour[c["id"]] = h
                if c.get("say") and sent_by(line) == "rule":
                    h.chatter += 1
            elif k == "ended" and (fh := finish_hour.pop(body.get("id"), None)):
                # The device decides what plays: a finish it skipped, or one
                # something other than your tap cut, didn't play.
                if body.get("how") == "skipped" or (body.get("how") == "cut" and body.get("why") != "tap"):
                    fh.finishes -= 1
            elif k == "view":
                seq = (body.get("from") or [0])[-1]  # the raw event that made it, which a pass is for
                events[seq], event_at[seq] = body, t
                if h and body.get("type") == "poke":
                    h.pokes += 1
            elif k == "pass":
                last_pass = body
                passed.add(body.get("for"))
                if not h:
                    continue
                if not body.get("brain"):
                    day.forced += 1
                    continue
                if body.get("held"):
                    # Held back when its turn came (something needed you):
                    # the brain wasn't asked.
                    day.held[body["held"]] += 1
                    continue
                h.passes += 1
                if not body.get("dropped"):
                    # A dropped pass's latency is the deadline's, or 0 for
                    # one that never asked: it says nothing of the brain.
                    day.latencies.append(body.get("latency_ms", 0))
                if body.get("dropped"):
                    h.dropped += 1
                    day.drops.append(Miss(t, body["brain"], body["dropped"]))
                elif face(body) == "none":
                    day.quiet += 1
            elif k == "event" and (act := action(body)) and act["by"] != "rule":
                seq, body = body.get("seq"), act
                names[seq] = body.get("name", "?")
                forced = bool(body.get("by"))
                if body.get("name") == "mood" and body.get("ok") and changed and changed.why is None \
                        and t - changed.at < 1000:
                    changed.why = cause(body, events)
                if body.get("name") == "react" and h:
                    # Started, or refused by the action's own rule: either
                    # way the brain (or the dashboard) asked for this face.
                    if forced:
                        day.forced_reacts += 1
                    else:
                        h.reactions += 1
                        h.faces[face(last_pass) or "?"] += 1
                    if not body.get("ok"):
                        h.missed += not forced
                        day.misses.append(Miss(t, "react", body.get("message", "?"), forced))
            elif k == "event" and (ended := action_end(body)) and ended["by"] != "rule":
                body = ended
                if body.get("end") != "done" and h:
                    forced = bool(body.get("by"))
                    h.missed += not forced
                    day.misses.append(Miss(t, names.get(body.get("for"), "?"), body.get("why") or "?", forced))
            elif k == "status":
                if body.get("brain") not in (None, "none") and body["brain"] not in brains:
                    brains.append(body["brain"])
                if body.get("connected") and up_since is None:
                    up_since = t
                elif not body.get("connected") and up_since is not None:
                    a, b = clip(up_since, t)
                    day.connected_ms += max(0, b - a)
                    up_since = None
        if up_since is not None:
            a, b = clip(up_since, last)
            day.connected_ms += max(0, b - a)
        if episode:
            episode.end, episode.open = last, True
            day.needs.append(episode)
        day.skipped += sum(1 for seq, event in events.items()
                           if event.get("wakes_brain") and seq not in passed and start <= event_at[seq] < end)
        if start <= last and first < end:
            day.launches.append((launch.name, max(first, start), min(last, end - 1), brains))

    day.needs = [n for n in day.needs if n.start < end and n.end >= start]
    for n in day.needs:
        a, b = clip(n.start, n.end)
        while a < b:
            cut = min(next_hour(a), b)
            day.hours.setdefault(hour_of(a), Hour()).needs_ms += cut - a
            a = cut
    return day


def cause(action: Line, events: dict[int, Line]) -> str:
    """What made a mood output run: a forced pass or mood, or its event."""
    if action.get("by"):
        return f"forced from the {action['by']}"
    event = events.get(action.get("for"))
    return f"{view_name(event)}: {event['line']}" if event else "?"


# Text.

def clock(ms: int) -> str:
    return time.strftime("%H:%M", time.localtime(ms / 1000))


def span(ms: int) -> str:
    s = round(ms / 1000)
    if s < 60:
        return f"{s} s"
    if s < 3600:
        return f"{s // 60} min" + (f" {s % 60} s" if s % 60 and s < 600 else "")
    return f"{s // 3600} h {s % 3600 // 60:02d} min"


def face(p: dict) -> str | None:
    """A pass's reaction face: `react.mood`, which older logs name
    `react`."""
    answers = p.get("answers") or {}
    return (answers.get("react.mood") or answers.get("react") or {}).get("choice")


def minutes(ms: int) -> str:
    return "" if not ms else f"{ms / 60000:.0f} min" if ms >= 60000 else "<1 min"


def faces(c: Counter) -> str:
    return ", ".join(f"{name} {n}" for name, n in sorted(c.items(), key=lambda kv: (-kv[1], kv[0])))


COLUMNS = [("finishes", "finishes"), ("chatter", "chatter"), ("reactions", "reacts"), ("alerts", "alerts"),
           ("moods", "moods"), ("passes", "passes"), ("dropped", "dropped"), ("missed", "missed"), ("pokes", "pokes")]


def render(day: Day) -> str:
    out: list[str] = []
    weekday = time.strftime("%A", time.strptime(day.date, "%Y-%m-%d"))
    first, last = day.launches[0][1], day.launches[-1][2]
    out.append(f"Boop's day: {weekday} {day.date}, {clock(first)}–{clock(last)}, {len(day.launches)} launch"
               + ("es" if len(day.launches) != 1 else ""))
    for name, a, b, brains in day.launches:
        out.append(f"  {name:<15} {clock(a)}–{clock(b)}  brain {', '.join(brains) or 'none'}")
    out.append(f"  running {span(day.running_ms)}, the device connected for {span(day.connected_ms)} of it")
    out.append("")

    head = ["hour"] + [title for _, title in COLUMNS] + ["needs you", "faces"]
    rows = []
    hours = sorted(day.hours)
    for hr in range(hours[0], hours[-1] + 1) if hours else []:
        h = day.hours.get(hr)
        if not h or not h.lines:
            rows.append([f"{hr:02d}"] + [""] * len(COLUMNS) + ["", "(no log: Boop wasn't running with --debug)"])
            continue
        rows.append([f"{hr:02d}"] + [str(getattr(h, name) or "") for name, _ in COLUMNS]
                    + [minutes(h.needs_ms), faces(h.faces)])
    t = day.total()
    rows.append(["all"] + [str(getattr(t, name)) for name, _ in COLUMNS] + [span(t.needs_ms), faces(t.faces)])
    widths = [max(len(r[i]) for r in rows + [head]) for i in range(len(head) - 1)]
    for r in [head] + rows:
        cells = [r[0].ljust(widths[0])] + [c.rjust(w) for c, w in zip(r[1:-1], widths[1:])]
        out.append("  ".join(cells + [r[-1]]).rstrip())
    out.append("")
    out.append("reacts are the reactions the brain asked for, with their faces, and missed the ones of them that "
               "didn't happen (below);")
    out.append("finishes are every finish played, task_complete or reply_ready (the brain's), not one the device "
               "skipped or cut short but by your tap, and cheers in logs from "
               "before 2026-09-29; chatter is the rules' working chatter, "
               "which only logs from before then have;")
    out.append("alerts are states bringing a new needs-you or a different one.")

    out.append("")
    passes = day.total().passes
    lat = f" (answered in a median {statistics.median(day.latencies):.0f} ms, the slowest {max(day.latencies)} ms)" \
        if day.latencies else ""
    forced = "none forced from the dashboard" if not day.forced else \
        f"and {day.forced} forced from the dashboard, asking for {day.forced_reacts} " \
        + ("reaction" if day.forced_reacts == 1 else "reactions")
    out.append(f"Brain: {passes} passes{lat}, {len(day.drops)} dropped, {day.quiet} chose no reaction; {forced}")
    for why, n in Counter(d.why for d in day.drops).most_common():
        out.append(f"  dropped {n}×: {why}")
    for why, n in day.held.most_common():
        out.append(f"  held back {n}×, the brain not asked: {why}")
    if day.skipped:
        out.append(f"  {day.skipped} events woke it but got no pass: a newer one took their place while a pass ran")

    out.append("")
    out.append(f"Mood changes: {len(day.moods)}")
    for m in day.moods:
        out.append(f"  {clock(m.at)}  {m.before} → {m.after}  ({m.why or '?'})")

    out.append("")
    cleared = [n.end - n.start for n in day.needs if not n.open]
    stats = "" if not cleared else f"; cleared in {span(cleared[0])}" if len(cleared) == 1 else \
        f"; cleared in {span(min(cleared))} to {span(max(cleared))}, median {span(statistics.median(cleared))}"
    out.append(f"Needs you: {len(day.needs)} times, {span(t.needs_ms)} in all{stats}")
    who = max((len(" → ".join(n.who)) for n in day.needs), default=0)
    for n in day.needs:
        took = f"{span(n.end - n.start)}" + (" (still up when the log ends)" if n.open else "")
        out.append(f"  {clock(n.start)}  {' → '.join(n.who):<{who}}  {took}" + (f", {n.alerts} alerts" if n.alerts > 1 else ""))

    out.append("")
    forced = sum(m.forced for m in day.misses)
    out.append(f"Reactions that didn't happen: {len(day.misses) - forced} of the brain's {t.reactions}"
               + (f", and {forced} of the {day.forced_reacts} forced from the dashboard" if day.forced_reacts else ""))
    for why, group in group_by_why(day.misses):
        out.append(f"  {len(group)}× {why}: " + ", ".join(clock(m.at) for m in group))
    return "\n".join(out)


def group_by_why(misses: list[Miss]) -> list[tuple[str, list[Miss]]]:
    """The brain's first, then the forced ones, each by how often."""
    groups: dict[tuple[bool, str], list[Miss]] = {}
    for m in misses:
        why = m.why if m.name == "react" else f"{m.name}: {m.why}"
        groups.setdefault((m.forced, why), []).append(m)
    ordered = sorted(groups.items(), key=lambda kv: (kv[0][0], -len(kv[1]), kv[0][1]))
    return [(why + (" (forced)" if forced else ""), group) for (forced, why), group in ordered]


def run(paths: list[Path], date: str | None) -> tuple[int, str]:
    """(exit status, text) for the files, oldest launch first."""
    launches = read_launches(paths)
    if not launches:
        return 1, "No debug log lines in " + ", ".join(map(str, paths)) + ". Is Boop running with --debug?"
    newest = max(line["received_at_ms"] for line in launches[-1].lines)
    summary = summarise(launches, date or day_of(newest))
    if not summary.launches:
        oldest = min(line["received_at_ms"] for line in launches[0].lines)
        stamp = "%Y-%m-%d %H:%M"
        return 1, (f"Nothing in the debug logs on {summary.date}: they run from "
                   f"{time.strftime(stamp, time.localtime(oldest / 1000))} to "
                   f"{time.strftime(stamp, time.localtime(newest / 1000))}.")
    return 0, render(summary)
