"""The dashboard's one source, the state dir's debug.jsonl: following it as
the app writes it, noticing when the app starts again,
and keeping what the panes show: Boop now, and its three columns, the mood,
the automatic reactions and the decided ones. It never reads boop.log or the
transcript, and never parses an action's message for a fact."""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from boopctl_lib.common import RULE_REACTIONS, Take, call, take
from boopctl_lib.device import DeviceError

Line = dict[str, Any]

# A debug-mode app writes a `sent` line at least every 10 s, the state
# keepalive, so a newest line older than this means no app
# is writing the file.
STALE_S = 15
# A view event written this soon after a reflex's `sent` line is what set it
# off: the app sends to the device first, then records the view event.
TRIGGER_MS = 1000
# A rule's reaction, a tap's poke or a `say` counts as what's showing for
# this long.
SHOWING_MS = 4000


class Follower:
    """The complete lines added to a file since the last read. The app
    empties the file in place at each launch and writes its `questions`
    line first, so when the file no longer starts with the first line read,
    the app has started again, and the file is read from the top."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.offset = 0
        self.partial = b""
        self.first = b""  # the file's first line, once read whole

    def read(self) -> tuple[bool, list[Line]]:
        """(started again, new lines). The first read is not a restart."""
        try:
            f = self.path.open("rb")
        except FileNotFoundError:
            return False, []
        with f:
            restarted = bool(self.first) and f.read(len(self.first)) != self.first
            if restarted:
                self.offset, self.partial, self.first = 0, b"", b""
            f.seek(self.offset)
            data = f.read()
        self.offset += len(data)
        *whole, self.partial = (self.partial + data).split(b"\n")
        if whole and not self.first:
            self.first = whole[0] + b"\n"
        lines = []
        for raw in whole:
            try:
                lines.append(json.loads(raw))
            except ValueError:
                continue
        return restarted, lines


def kind(line: Line) -> str:
    """`event` (a raw event the transcript recorded), `view` (what the brain
    may hear of), `pass`, `head` (the state's head, which the passes after
    it share), `sent`, `ended` (how the device said a `do` went), `status`
    or `questions`."""
    return next((k for k in line if k not in ("seq", "by", "received_at_ms")), "?")


def sent_by(line: Line) -> str:
    """Who a `sent` line's message is from: `brain` for the brain's
    reactions, `rule` for everything the rules send."""
    if "by" in line:
        return line["by"]
    # Logs from before `by` (and before `do`): a reaction's moment has its
    # face; a reflex's doesn't.
    msg = line.get("sent") or {}
    return "brain" if msg.get("t") == "moment" and msg.get("mood") else "rule"


def view_name(view: Line) -> str:
    """A view event's type and phase: `turn end`, `tool wait`, `poke`."""
    return view.get("type", "?") + (f" {view['phase']}" if view.get("phase") else "")


def _as_action(event: Line) -> tuple[str, str | None, Line] | None:
    """An action as (name, phase, data): the harness's `did` (its start
    while `open`) and `ended`, and "needs you"
    (`needs_you_start`, `needs_you_end`); or, in logs from before
    MellowHarness, an event of type `action`. None for any other event."""
    data = event.get("data", {})
    k = event.get("kind")
    if k == "did":
        return data.get("action"), "start" if data.get("open") else None, data
    if k == "ended":
        return data.get("action"), "end", data
    if k in ("needs_you_start", "needs_you_end"):
        return "needs_you", k.removeprefix("needs_you_"), {**data, "session": data.get("session")}
    if event.get("type") == "action":
        return event.get("specific_type"), event.get("phase"), {**data, "session": event.get("session")}
    return None


def action(event: Line) -> Line | None:
    """An action's start, or its only line, as the dashboard reads it: its
    name, whether it worked, its message, whether it's still going, who
    it's by (`dashboard`, `rule` or none for the brain), what it's for, and
    for a reaction the takes it sent. None for any
    other event, and for an action's end."""
    got = _as_action(event)
    if got is None or got[1] == "end":
        return None
    name, phase, data = got
    by = data.get("by")
    return {"name": name, "ok": bool(data.get("ok")), "message": data.get("message", ""),
            "pending": phase == "start", "by": None if by == "brain" else by, "for": data.get("for"),
            "session": data.get("session"), "takes": data.get("takes")}


def action_end(event: Line) -> Line | None:
    """An action's end: how the action it's `for` went."""
    got = _as_action(event)
    if got is None or got[1] != "end":
        return None
    name, _, data = got
    by = data.get("by")
    return {"name": name, "for": data.get("for"), "end": data.get("outcome"), "why": data.get("why"),
            "by": None if by == "brain" else by}


def _takes(ids: list[str]) -> list[Take | None] | None:
    """The takes with these ids, None for one the voice file lacks; None
    with no voice file here."""
    try:
        return [take(i) for i in ids]
    except DeviceError:
        return None


def said(ids: list[str] | None) -> str | None:
    """What a reaction said: its takes' texts in order (an older log's
    feeling's then topic's), or their ids with no voice file here; None
    for no line."""
    if not ids:
        return None
    found = _takes(ids) or [None] * len(ids)
    return " ".join(t.text if t else i for t, i in zip(found, ids))


def clock(ms: int) -> str:
    return time.strftime("%H:%M:%S", time.localtime(ms / 1000))


class Board:
    """What the panes show, built from debug.jsonl's lines in order."""

    def __init__(self) -> None:
        self.questions: list[Line] = []
        self.status: Line = {}
        self.state: Line | None = None  # the latest `state` sent to the device
        self.events: dict[int, Line] = {}  # view events by the raw event that made them
        self.names: dict[int, str] = {}  # each action's name by its seq, for its end
        self.latency_ms: int | None = None  # Jev's last
        self.dropped = 0
        self.jev_state: str | None = None  # the latest state a brain read, for `s`
        self.head = ""  # the state's head, from the latest `head` line
        self.newest_ms: int | None = None  # the newest line's received_at_ms
        # The three columns, oldest first; each row a dict.
        self.moods: list[Line] = []
        self.reflexes: list[Line] = []
        self.decided: list[Line] = []
        self._pass_for: dict[int | None, Line] = {}  # the latest decided row by its event (None: forced)
        self._decided_by_action: dict[int, Line] = {}  # a decided row by its react output's seq
        self._reflex: tuple[int, str] | None = None  # the latest rule reaction, poke or chatter: (time, what)

    def apply(self, line: Line) -> tuple[str, str] | None:
        """Takes one line, and returns its timeline row as (style, text), or
        None for a `state` resent unchanged (the 10 s keepalive) and for a
        `head`."""
        k = kind(line)
        body, seq, at = line.get(k), line.get("seq"), line.get("received_at_ms", 0)
        if at:
            self.newest_ms = max(self.newest_ms or 0, at)
        if k == "questions":
            self.questions = body
            return "status", "questions: " + ", ".join(q["key"] for q in body)
        if k == "status":
            before, self.status = self.status, body
            return "status", "status: " + status_text(body, before)
        if k == "sent":
            return self._sent(body, sent_by(line), at)
        if k == "ended":
            return self._ended(body)
        if k == "view":
            self.events[(body.get("from") or [0])[-1]] = body
            self._event(body, at)
            text = f"▸ {body.get('id')} {view_name(body)}{'' if body.get('wakes_brain') else ' (no pass)'}: {body['line']}"
            return "event", text + "".join(f"  [{note}]" for note in body.get("notes") or [])
        if k == "event":
            return self._raw(body, at)
        if k == "head":
            self.head = body
            return None
        if k == "pass":
            if body.get("brain") and body.get("state"):
                # A pass carries HISTORY and NOW; older logs' carry the whole state.
                self.jev_state = self.head + body["state"]
            self._pass(body, seq, at)
            if body.get("brain") and not body.get("held"):
                # A held pass never asked the brain: its 0 ms says nothing of it.
                self.latency_ms = body.get("latency_ms")
            who = body.get("brain") or f"forced by {body.get('by')}"
            if body.get("held"):
                # Held back when its turn came: the brain wasn't asked.
                return "dim", f"  pass {who} for {body.get('for')}: held: {body['held']}"
            if body.get("dropped"):
                self.dropped += 1
                return "fail", f"  pass {who} for {body.get('for')}: dropped: {body['dropped']}"
            picks = " · ".join(f"{key} {a['choice']}" for key, a in answers(body))
            return "pass", f"  pass {who}" + (f" for {body['for']}" if body.get("for") else "") + f": {picks}"
        return None

    def _raw(self, event: Line, at: int) -> tuple[str, str] | None:
        """A raw event: only actions have a row; the view says the rest."""
        seq = event.get("seq")
        if a := action(event):
            if a["name"] == "needs_you":
                return None  # the state's strip shows it, and the view its line
            self.names[seq] = a["name"]
            if a["by"] == "rule":
                self._rule(a, at)
            else:
                self._action(a, seq, at)
            by = f" (by {a['by']})" if a.get("by") else ""
            style, mark = ("fail", "✗") if not a["ok"] else ("dim", "…") if a.get("pending") else ("ok", "✓")
            return style, f"  {mark} {a['name']}{by}: {a['message']}"
        if end := action_end(event):
            if end["name"] == "needs_you":
                return None
            if row := self._decided_by_action.get(end["for"]):
                row["settle"] = end
            name = f"{self.names.get(end['for'], '?')} ({end['for']})"
            if end["end"] == "done":
                return "ok", f"  ✓ {name} done"
            return "fail", f"  ✗ {name} didn't happen: {end.get('why')}"
        return None

    # Sorting lines into the columns.

    def _sent(self, msg: Line, by: str, at: int) -> tuple[str, str] | None:
        if msg.get("t") == "state":
            unchanged = msg == self.state
            before, self.state = self.state, msg
            self._state_changed(before, msg, at)
            return None if unchanged else ("sent", "→ state " + state_text(msg))
        if c := call(msg):
            if by == "rule":
                what = None
                if c["anim"] in RULE_REACTIONS:
                    # The rules' reactions: the view event
                    # recorded right after names what set it off.
                    fact = c.get("ctx") or c.get("outcome")
                    what = c["anim"] + (f" ({fact})" if fact else "")
                    self.reflexes.append({"at": at, "what": what, "anim": True, "rule": True, "trigger": None,
                                          "id": c.get("id")})
                elif c["anim"] == "listening":
                    # The Mac's Talk button; BOOT's push-to-talk the device
                    # starts itself.
                    what = "listening"
                    self.reflexes.append({"at": at, "what": what, "trigger": "you pressed Talk on the Mac",
                                          "id": c.get("id")})
                elif c["anim"]:
                    what = c["anim"] + (f", loops {c['loops']}" if c.get("loops") else "")
                    self.reflexes.append({"at": at, "what": what, "anim": True, "trigger": None, "id": c.get("id")})
                elif c.get("say"):
                    # Older logs: the rules' chatter while an agent worked.
                    what = "working chatter " + say_text(c["say"])
                    self.reflexes.append({"at": at, "what": what, "trigger": "an agent is working"})
                if what:  # not the end of push-to-talk, which shows nothing
                    self._reflex = (at, what)
            if msg.get("t") == "moment":  # logs from before `do`
                parts = ([c["anim"]] if c["anim"] else []) + (["say " + say_text(c["say"])] if c.get("say") else [])
                return "sent", "→ moment " + " + ".join(parts)
            return "sent", f"→ do {c['name']}" + (f" + say {say_text(c['say'])}" if c.get("say") else "")
        return "sent", "→ " + json.dumps(msg)

    def _ended(self, ended: Line) -> tuple[str, str]:
        """How the device said a `do` went (linkkit/SPEC.md §4). The device
        decides what plays, so a rule's reaction it skipped (`busy`, while
        a brain reaction played) is marked on its reflex: it didn't
        happen."""
        how, why = ended.get("how"), ended.get("why")
        said = f"⇠ do {ended.get('id')} {how}" + (f" ({why})" if why else "")
        if how == "skipped" and (r := next((r for r in reversed(self.reflexes) if r.get("id") == ended.get("id")), None)):
            r["skipped"] = why or "?"
        return ("dim" if how == "done" else "fail"), "  " + said

    def _state_changed(self, before: Line | None, now: Line, at: int) -> None:
        mood = now.get("mood")
        if before is None:
            self.moods.append({"at": at, "mood": mood, "from": None, "cause": "at launch"})
        elif mood != before.get("mood"):
            self.moods.append({"at": at, "mood": mood, "from": before.get("mood"), "cause": None})
        # Needs you: a new request, or a different one, alerts.
        old, new = (before or {}).get("attn"), now.get("attn")
        ident = lambda a: (a.get("id", 0), a.get("agent"), a.get("project"))  # noqa: E731
        if new and (not old or ident(old) != ident(new)):
            more = f" (+{new['more']})" if new.get("more") else ""
            what = ("needs you: " if not old else "needs you now: ") + f"{new['agent']} · {new['project']}{more} · alert"
            self.reflexes.append({"at": at, "what": what, "attn": True, "trigger": None})
        elif old and not new:
            self.reflexes.append({"at": at, "what": "needs you cleared", "attn": True, "trigger": None})

    def _event(self, view: Line, at: int) -> None:
        """A view event of a request that waits on you names the needs-you
        strip just sent before it; any view event names a rule's reaction
        just sent before it."""
        waiting = [r for r in self.reflexes[-3:] if r["trigger"] is None and at - r["at"] <= TRIGGER_MS]
        match = next((r for r in waiting if r.get("rule")), None)
        if not match and view_name(view) == "tool wait":
            match = next((r for r in waiting if r.get("attn")), None)
        if match:
            match["trigger"] = "▸ " + view["line"]

    def _rule(self, a: Line, at: int) -> None:
        """A rule's action names what set off the animation just sent before
        it; one the device plays by itself (a tap's poke, which the rules
        record as `wiggle`) is a reflex of its own. Either way its trigger is
        the view event it's for."""
        event = self.events.get(a.get("for"))
        trigger = "▸ " + event["line"] if event else None
        waiting = [r for r in self.reflexes[-3:] if r["trigger"] is None and at - r["at"] <= TRIGGER_MS]
        match = next((r for r in waiting if r.get("anim")), None)
        if match:
            match["trigger"] = trigger
            return
        self.reflexes.append({"at": at, "what": a["message"], "trigger": trigger})
        self._reflex = (at, a["message"])

    def _pass(self, body: Line, seq: int, at: int) -> None:
        mood_keys = {q["key"] for q in self.questions if q["action"] == "mood"}
        row = {"at": at, "seq": seq, "pass": body, "event": self.events.get(body.get("for")), "react": None,
               "settle": None,
               # A pass that asks no mood question: the mood sat it out.
               "sat_out": bool(body.get("brain") and "questions" in body and mood_keys
                               and not mood_keys & set(body["questions"]))}
        self.decided.append(row)
        self._pass_for[body.get("for")] = row
        if row["sat_out"]:
            line = row["event"]["line"] if row["event"] else f"the pass for {body.get('for')}"
            self.moods.append({"at": at, "sat_out": line})

    def _action(self, body: Line, seq: int, at: int) -> None:
        if body["name"] == "react":
            row = self._pass_for.get(body.get("for"))
            if row and (row["pass"].get("by") or None) == (body.get("by") or None) and row["react"] is None:
                row["react"] = body
                self._decided_by_action[seq] = row
        elif body["name"] == "mood":
            if not body["ok"]:
                self.moods.append({"at": at, "refused": body["message"], "by": body.get("by")})
                return
            last = next((r for r in reversed(self.moods) if "mood" in r), None)
            if not last or last["cause"] is not None:
                return
            if body.get("by"):
                last["cause"] = f"forced by {body['by']}"
                return
            row = self._pass_for.get(body.get("for"))
            event = self.events.get(body.get("for"))
            last["cause"] = f"▸ {event['line']}" if event else f"the pass for {body.get('for')}"
            if row:
                a = row["pass"].get("answers", {}).get("mood")
                if a and a.get("p", {}).get(last["mood"]) is not None:
                    last["p"] = a["p"][last["mood"]]
                last["brain"] = row["pass"].get("brain")

    # The panes, as text.

    def stale(self, now_ms: int) -> bool:
        """No app is writing the file: its newest line is older than
        STALE_S, or it has none."""
        return self.newest_ms is None or now_ms - self.newest_ms > STALE_S * 1000

    def facts(self, now_ms: int | None = None) -> list[tuple[str, str]]:
        """Boop now, as (name, value)."""
        now_ms = (self.newest_ms or 0) if now_ms is None else now_ms
        s, st = self.state or {}, self.status
        attn = s.get("attn")
        count = lambda status: sum(x["status"] == status for x in st.get("sessions", []))  # noqa: E731
        look = s.get("base", "?") + (" with the needs-you strip" if attn else "")
        live = not self.stale(now_ms)
        return [
            ("look", look),
            ("mood", s.get("mood", "?")),
            ("showing", self.showing(now_ms)),
            ("needs you", f"{attn['agent']} · {attn['project']}" + (f" (+{attn['more']})" if attn.get("more") else "")
             if attn else "no"),
            ("sessions", f"{count('working')} working, {count('idle')} idle, {count('waiting')} waiting"),
            ("board", ("connected" if st.get("connected") else "not connected (the sim shows what it would)")
             if live else "unknown: no live log"),
            ("brain", f"{st.get('brain', '?')} · "
             + (f"{self.latency_ms} ms" if self.latency_ms is not None else "no pass yet") + f" · dropped {self.dropped}"),
        ]

    def showing(self, now_ms: int) -> str:
        """What the face is doing: a decided reaction still playing, a
        reflex just sent, or the look."""
        playing = next((r for r in reversed(self.decided) if r["react"]), None)
        if playing and playing["react"]["ok"] and playing["react"].get("pending") and not playing["settle"]:
            return reaction_text(playing, playing["react"].get("takes"))
        if self._reflex and now_ms - self._reflex[0] <= SHOWING_MS:
            return self._reflex[1]
        s = self.state or {}
        look = s.get("act") if s.get("base") == "working" and s.get("act") and not s.get("attn") else s.get("base", "?")
        return f"its {look} look" + (" with the needs-you strip" if s.get("attn") else "")

    def mood_column(self) -> list[tuple[str, str]]:
        """The mood now, then its changes, newest first."""
        changes = [r for r in self.moods if "mood" in r]
        if not changes:
            return [("dim", "no state yet")]
        now = changes[-1]
        out = [("head", f"{now['mood']} since {clock(now['at'])}"), ("dim", "")]
        for r in reversed(self.moods):
            if "sat_out" in r:
                out.append(("dim", f"{clock(r['at'])} · mood sat out: {r['sat_out']}"))
            elif "refused" in r:
                out.append(("fail", f"{clock(r['at'])} ✗ forced mood refused: {r['refused']}"))
            else:
                change = f"{r['from']} → {r['mood']}" if r["from"] else f"{r['mood']}"
                out.append(("mood", f"{clock(r['at'])} {change}"))
                out.append(("dim", f"  {r['cause'] or '…'}"))
                if r.get("p") is not None:
                    out.append(("pass", f"  {brain_name(r.get('brain'))}: {r['mood']} {r['p']:.2f}"))
        return out

    def reflex_column(self) -> list[tuple[str, str]]:
        if not self.reflexes:
            return [("dim", "none yet")]
        out = []
        for r in reversed(self.reflexes):
            style = "attn" if r.get("attn") else "dim" if r.get("skipped") else "ok"
            skipped = f" (skipped: {r['skipped']})" if r.get("skipped") else ""
            out.append((style, f"{clock(r['at'])} {r['what']}{skipped}"))
            trigger = r["trigger"] or ("" if r.get("rule") else "no event: played from the dashboard" if r.get("anim") else "")
            if trigger:
                out.append(("dim", f"  {trigger}"))
        return out

    def decided_column(self) -> list[tuple[str, str]]:
        if not self.decided:
            return [("dim", "no pass yet")]
        out = []
        for r in reversed(self.decided):
            p = r["pass"]
            if p.get("held") or not p.get("dropped") and choice(p, FACE) is None:
                continue  # a pass that asked no reaction couldn't react
            if r["event"]:
                out.append(("event", f"{clock(r['at'])} ▸ {r['event']['line']}"))
            elif p.get("by"):
                out.append(("event", f"{clock(r['at'])} forced by {p['by']}"))
            else:
                out.append(("event", f"{clock(r['at'])} the pass for {p.get('for')}"))
            if not p.get("dropped") and choice(p, FACE) not in (None, "none"):
                out.append(("pass", "  " + picks_text(p)))
            out.append(fate(r))
            if r["sat_out"]:
                out.append(("dim", "  the mood sat this pass out"))
        return out


def fate(row: Line) -> tuple[str, str]:
    """What became of a pass's reaction."""
    p, react, settle = row["pass"], row["react"], row["settle"]
    if p.get("dropped"):
        return "fail", f"  ✗ pass dropped: {p['dropped']}"
    if choice(p, FACE) == "none":
        return "dim", f"  stayed quiet · none {prob(p, FACE):.2f}"
    if react is None:
        return "dim", "  … waiting for the reaction"
    if not react["ok"]:
        return "fail", f"  ✗ didn't happen: {react['message']}"
    if settle:
        return ("ok", "  ✓ played") if settle["end"] == "done" else ("fail", f"  ✗ didn't happen: {settle.get('why')}")
    if react.get("pending"):
        return "playing", "  ▶ playing"
    return "ok", "  ✓ played"


# A reaction's four questions: its face, its move (a finish, a wake-up or
# a notice, or to what you said the reply), how big the moment is (how
# long the face held and how big what it said) and what it says.
FACE, MOVE, INTENSITY, SAY = "react.face", "react.move", "react.intensity", "say"
# What older logs name them, which `answer` reads after today's: the face
# `react.mood`, and before that `react` (for a while carrying the cheer
# too, `proud-cheer`); the move `react.animation`, or to what you said
# `react.reply`; the intensity `react.loops`, by how long it held.
OLDER = {FACE: ("react.mood", "react"), MOVE: ("react.animation", "react.reply"), INTENSITY: ("react.loops",)}
# The intensities, smallest first, and how long each held, as
# `react.loops` named them.
INTENSITIES = ["small", "medium", "big", "huge"]
HOLDS = ["once", "twice", "three times", "four times"]
# The moves at an event (ReactOutput.animations); any other move is a
# reply to what you said.
MOVES = ["success", "failure", "reply", "wake up", "notice"]


def answer(p: Line, key: str) -> Line:
    """A question's answer, under its key or an older one: the first that
    picked something, else the first there; `react.loops`' as the
    intensity of its hold."""
    answers = p.get("answers") or {}
    found = [(k, answers[k]) for k in (key, *OLDER.get(key, ())) if k in answers]
    k, a = next(((k, a) for k, a in found if a.get("choice") not in (None, "none")), found[0] if found else (key, {}))
    if k == "react.loops":
        size = lambda c: INTENSITIES[HOLDS.index(c)] if c in HOLDS else c  # noqa: E731
        a = {"choice": size(a.get("choice")), "p": {size(c): v for c, v in a.get("p", {}).items()}}
    return a


def choice(p: Line, key: str) -> str | None:
    return answer(p, key).get("choice")


def prob(p: Line, key: str) -> float:
    a = answer(p, key)
    return a.get("p", {}).get(a.get("choice"), 0.0)


def move(p: Line) -> str | None:
    """The move a reaction played: at an event a finish (success, failure
    or reply), a wake up or a notice; to what you said its reply (yes,
    hello, status…); None for a face alone."""
    pick = choice(p, MOVE)
    return None if pick in (None, "none") else pick


def say_keys(p: Line) -> list[str]:
    """A pass's questions of what it says: `say`; older logs asked a
    feeling and a topic, `say.feeling` and `say.about`, and before that
    for words, `word.feeling` and `word.about`."""
    return [k for k in p.get("questions") or p.get("answers", {})
            if k == SAY or k.startswith(("word.", "say.")) and k != "say.kind"]


def picks_text(p: Line) -> str:
    """The face, its move, how big and what it says (an older log's words
    in quotes), each with its probability: `proud 0.82 · success 0.90 ·
    big 0.64 · glad 0.71`. What it said is the reaction's takes (`said`):
    Voice picks a take of that meaning."""
    parts = [f"{choice(p, FACE)} {prob(p, FACE):.2f}"]
    if move(p):
        parts.append(f"{move(p)} {prob(p, MOVE):.2f}")
    if choice(p, INTENSITY):
        parts.append(f"{choice(p, INTENSITY)} {prob(p, INTENSITY):.2f}")
    words = [(k, choice(p, k), prob(p, k)) for k in say_keys(p) if choice(p, k) not in (None, "none")]
    parts += [(f"“{w}”" if k.startswith("word.") else w) + f" {v:.2f}" for k, w, v in words] or ["says nothing"]
    return " · ".join(parts)


def reaction_text(row: Line, takes: list[str] | None = None) -> str:
    """A playing reaction as HISTORY says it: `a proud reaction face (big),
    “Done”`, `a success in a proud face (big), …` or `a glad reaction face
    (small), replying hello`, saying what its takes said."""
    p = row["pass"]
    size = choice(p, INTENSITY)
    face, _, anim = (choice(p, FACE) or "?").partition("-")
    picked = move(p)
    anim = (picked if picked in MOVES else None) or anim
    reply = picked if picked and picked not in MOVES else None
    what = (f"a {anim} in " if anim else "") + f"{'an' if face[0] in 'aeiou' else 'a'} {face}"
    what += " face" if anim else " reaction face"
    words = said(takes)
    return (what + (f" ({size})" if size else "") + (f", replying {reply}" if reply else "")
            + (f", “{words}”" if words else ""))


def brain_name(brain: str | None) -> str:
    name = (brain or "the brain").split(":")[0]
    return "Jev" if name == "jev" else name


def state_text(s: Line) -> str:
    attn = s.get("attn")
    more = f" +{attn['more']}" if attn and attn.get("more") else ""
    act = f" ({s['act']})" if s.get("act") else ""
    return (f"{s.get('base')}{act} {s.get('mood')} · busy {s.get('busy', 0)}"
            + (f" · needs you: {attn['agent']} {attn['project']}{more}" if attn else "") + f" · vol {s.get('vol')}")


def say_text(say: Line) -> str:
    """A line as the board plays it: its takes' words, and their ids (a
    `say` has up to two), or just the ids with no voice
    pack here. `no take` for a `say` without a take the pack has."""
    ids = [i for i in (say.get("take"), say.get("then")) if i]
    found = _takes(ids)
    if found is None:
        return f"({', '.join(ids)})" if ids else "no take"
    takes = [t for t in found if t]
    if not say.get("take") or not found[0]:
        return "no take"
    return "“" + " ".join(t.text for t in takes) + "” (" + ", ".join(t.id for t in takes) + ")"


def answers(p: Line) -> list[tuple[str, Line]]:
    """A pass's answers in the order it asked its questions."""
    return [(key, p["answers"][key]) for key in p["questions"] if key in p["answers"]]


def sessions_text(sessions: list[Line]) -> str:
    return ", ".join(f"{x['agent']} {x['project']} {x['status']}" for x in sessions) or "none"


def status_text(st: Line, before: Line | None = None) -> str:
    """What changed since `before`; everything the first time."""
    shown = {
        "personality": lambda v: f"personality {v}",
        "brain": lambda v: f"brain {v}",
        "sessions": lambda v: "sessions " + sessions_text(v),
        "connected": lambda v: "device " + ("connected" if v else "not connected"),
        "stage": lambda v: f"stage {v}",
    }
    # A key the line doesn't have (`stage`, before 2026-10-01) isn't shown.
    return " · ".join(show(st[key]) for key, show in shown.items()
                      if key in st and (not before or st.get(key) != before.get(key)))
