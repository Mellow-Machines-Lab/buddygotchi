"""`boopctl workday` (internal/EVALS.md §5): a scripted working day through the
headless app and its brain.

`plan` prints the day, `run` replays it through `Boop --headless` on a
compressed clock, `report` sums up what Boop did, hour by hour: how often
its mood changed (and whether after one routine turn), how often it
reacted, with which faces and what they said; and `check` holds a run to
the liveliness limits. The same seed always gives the same day, so a run
before a steering change and one after it can be compared; Jev itself
isn't deterministic, so run each at least twice.

`run` needs `make build` first. It starts the headless app with its own
state directory (keep it short and under /tmp: a Unix socket's path has
room for 103 bytes), a fake device on a Unix socket that says hello as
Boop's device does and says each `do` played to the end, and the brain (`--brain jev`, the
default, needs `BOOP_JEV_KEY`; `--brain scripted` needs nothing). It moves
the app's clock to 09:00 the next morning, then sends each step's hook
straight to the app's socket in the wire form `agent-hook` sends, moving the
clock between them with `{"dev":"advance"}`, and waits for every brain
pass and every reaction to finish before moving on, so no event is
replaced while Jev thinks.

The report reads debug.jsonl as `boopctl day` and the dashboard do
(dash/feed.py): a mood change's new mood, and a reaction's face, finish
and hold, from the answers of the pass whose action it is; what it said
from the takes its action recorded; never from an action's message."""
from __future__ import annotations

import datetime as dt
import json
import os
import random
import shutil
import socket
import sys
import threading
import time
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

from boopctl_lib import day as daylog
from boopctl_lib.common import DOES
from boopctl_lib.dash import feed
from boopctl_lib.device import DeviceError
from boopctl_lib.headless import Headless

# The resting mood: a new Boop starts in it and moods fade back toward it
# (`MoodOutput.initial`).
REST = "calm"

# A turn this long or longer, ending, is notable, not routine
# (the steering's "a very long turn": 5 minutes or more).
BIG_TURN_MS = 5 * 60_000


# ---------------------------------------------------------------- the day


@dataclass(frozen=True)
class Thread:
    agent: str
    session: str
    cwd: str


# The day's threads. Their places need no folders: `.worktrees/<name>` names
# itself.
API = Thread("claude", "s-api", "/tmp/tnp/api")
NAV = Thread("claude", "s-nav", "/tmp/tnp/landing/.worktrees/fix-nav")
DOCS = Thread("claude", "s-docs", "/tmp/tnp/landing/.worktrees/docs")
BOOP = Thread("codex", "s-boop", "/tmp/tnp/boop")


@dataclass
class Step:
    """One thing that happens at `at` seconds after 09:00: a hook line, or
    taps on the device."""
    at: float
    kind: str  # "hook" or "taps"
    line: dict[str, Any] = field(default_factory=dict)
    taps: int = 0
    note: str = ""


class Day:
    """Builds the steps, thread by thread; `steps()` merges them by time."""

    def __init__(self, seed: int) -> None:
        self.rng = random.Random(seed)
        self._steps: list[Step] = []
        self._ids = 0
        self.notes: list[tuple[float, str]] = []

    def steps(self) -> list[Step]:
        return sorted(self._steps, key=lambda s: s.at)

    def hook(self, at: float, th: Thread, hook: str, note: str = "", **fields: Any) -> None:
        line = {"agent": th.agent, "hook": hook, "session": th.session, "cwd": th.cwd}
        line.update({k: v for k, v in fields.items() if v is not None})
        self._steps.append(Step(at, "hook", line, note=note))

    def taps(self, at: float, count: int = 4, note: str = "pokes in a row") -> None:
        self._steps.append(Step(at, "taps", taps=count, note=note))
        self.notes.append((at, note))

    def session(self, at: float, th: Thread, end: bool = False) -> None:
        self.hook(at, th, "SessionEnd" if end else "SessionStart")

    def tool(self, at: float, th: Thread, name: str, took: float, topic: str | None = None,
             failed: bool = False) -> None:
        self._ids += 1
        tid = f"t{self._ids}"
        self.hook(at, th, "PreToolUse", tool=name, topic=topic, tool_use_id=tid)
        if th.agent == "codex":
            self.hook(at + took, th, "PostToolUse", tool=name, topic=topic, tool_use_id=tid)
        elif failed:
            self.hook(at + took, th, "PostToolUseFailure", tool=name, topic=topic, tool_use_id=tid,
                      tool_error="exit_code")
        else:
            self.hook(at + took, th, "PostToolUse", tool=name, topic=topic, tool_use_id=tid)

    def routine_tools(self, th: Thread, start: float, end: float, count: int,
                      tests: bool = False) -> None:
        """`count` everyday calls spread over [start, end), none of them
        notable; with `tests`, the last is a passing test run."""
        if count <= 0 or end - start < 2:
            return
        names = (["exec_command", "apply_patch", "exec_command"] if th.agent == "codex"
                 else ["Read", "Read", "Grep", "Edit", "Edit", "Bash", "Glob"])
        span = (end - start) / count
        for i in range(count):
            at = start + i * span + self.rng.uniform(0, span * 0.3)
            took = min(span * 0.5, self.rng.uniform(0.2, 4))
            if tests and i == count - 1 and th.agent != "codex":
                self.tool(at, th, "Bash", took, topic="tests")
            else:
                self.tool(at, th, self.rng.choice(names), took)

    def turn(self, th: Thread, at: float, length: float, tools: int | None = None, tests: bool = False,
             end: str = "done", error: str | None = None, approval: float | None = None,
             plays: Iterable[tuple[float, str, bool]] = (), note: str = "") -> float:
        """One turn from `at` for `length` seconds. `plays` are (offset,
        topic, failed) runs of a check that matter; the rest is routine.
        `approval` asks for permission at that offset and is answered 30–70 s
        later. `end` is done, failed (a StopFailure with `error`) or
        stopped (an interrupted call). Returns when it ended."""
        self.hook(at, th, "UserPromptSubmit")
        if note:
            self.notes.append((at, note))
        plays = sorted(plays)
        if tools is None:
            tools = 0 if length < 8 else int(min(30, max(1, length / 12 + self.rng.randint(0, 3))))
        marks = [at + 1] + [at + off for off, _, _ in plays] + [at + length - 1]
        routine_left = tools
        for i in range(len(marks) - 1):
            share = routine_left if i == len(marks) - 2 else round(tools / (len(marks) - 1))
            share = min(share, routine_left)
            self.routine_tools(th, marks[i], marks[i + 1] - 1, share, tests=tests and i == len(marks) - 2)
            routine_left -= share
            if i < len(plays):
                off, topic, failed = plays[i]
                self.tool(at + off, th, "Bash", self.rng.uniform(5, 25), topic=topic, failed=failed)
        if approval is not None:
            # The agent waits for you: none of its other calls while it asks.
            asked = at + approval
            waited = self.rng.uniform(30, 70)
            self._steps = [s for s in self._steps if not (
                s.line.get("session") == th.session and asked - 1 <= s.at <= asked + waited + 3)]
            self.hook(asked, th, "PermissionRequest", tool="Bash", tool_use_id=f"perm{int(asked)}")
            self.tool(asked + waited, th, "Bash", 1.5)
        finish = at + length
        if end == "done":
            self.hook(finish, th, "Stop")
        elif end == "failed":
            self.hook(finish, th, "StopFailure", error=error or "api_error")
        elif end == "stopped":
            self._ids += 1
            self.hook(finish - 3, th, "PreToolUse", tool="Bash", tool_use_id=f"t{self._ids}")
            self.hook(finish, th, "PostToolUseFailure", tool="Bash", tool_use_id=f"t{self._ids}",
                      interrupt=True)
        return finish

    def routine(self, th: Thread, at: float, until: float, mix: str = "normal", tests_every: int = 4) -> float:
        """Routine turns from `at` until about `until`, with gaps between
        them. `mix` picks their lengths: `quick` is mostly under a minute,
        `normal` a spread up to a few minutes."""
        n = 0
        t = at
        while True:
            if mix == "quick":
                length = self.rng.choice([self.rng.uniform(6, 14), self.rng.uniform(15, 45)])
                gap = self.rng.uniform(40, 150)
            else:
                length = self.rng.choice([self.rng.uniform(6, 14), self.rng.uniform(15, 58),
                                          self.rng.uniform(15, 58), self.rng.uniform(70, 240)])
                gap = self.rng.uniform(60, 360)
            if t + length > until:
                return t
            n += 1
            t = self.turn(th, t, length, tests=n % tests_every == 0) + gap


def build_day(seed: int = 1) -> Day:
    """An 8-hour working day, 09:00 to about 17:40. The structure is fixed;
    the seed only moves lengths and gaps a little."""
    d = Day(seed)
    m = 60.0
    h = 3600.0

    # 09:00–10:00: warming up. Routine turns on api, one asks for approval;
    # codex starts on boop.
    d.session(2 * m, API)
    t = d.turn(API, 3 * m, 40, note="the day starts: routine turns on api")
    t = d.turn(API, t + 60, 150, approval=60, note="an approval mid-turn")
    d.routine(API, t + 90, 58 * m)
    d.session(28 * m, BOOP)
    t = d.turn(BOOP, 30 * m, 95, note="codex works on boop")
    d.routine(BOOP, t + 120, 55 * m)

    # 10:00–11:00: tests fight back on api (3 failures, then a comeback),
    # fix-nav starts, four pokes in a row, a turn that fails on a rate limit.
    d.turn(API, 1 * h + 5 * m, 9 * m, tools=25, tests=True,
           plays=[(60, "tests", True), (3 * m, "tests", True), (5 * m, "tests", True), (7 * m, "tests", False)],
           note="tests fail three times, then pass: a comeback in a 9-minute turn")
    t = d.routine(API, 1 * h + 16 * m, 1 * h + 44 * m)
    d.session(1 * h + 20 * m, NAV)
    d.routine(NAV, 1 * h + 21 * m, 1 * h + 58 * m, mix="quick")
    d.taps(1 * h + 47 * m)
    t = d.turn(API, 1 * h + 50 * m, 40, tools=2, end="failed", error="rate_limit",
               note="a turn fails on a rate limit")
    d.turn(API, t + 100, 80, note="and is run again")

    # 11:00–12:15: a big 22-minute turn on api with a build that fails and
    # comes back; fix-nav keeps going, one of its turns is stopped; codex.
    d.turn(API, 2 * h + 1 * m, 22 * m, tools=40, tests=True,
           plays=[(3 * m, "build", True), (6 * m, "build", False)],
           note="a 22-minute turn: build fails once and comes back")
    t = d.routine(NAV, 2 * h + 2 * m, 2 * h + 40 * m, mix="quick")
    d.turn(NAV, 2 * h + 49 * m, 70, end="stopped", note="you stop a fix-nav turn")
    d.routine(API, 2 * h + 26 * m, 3 * h + 13 * m)
    d.routine(BOOP, 2 * h + 30 * m, 3 * h + 10 * m)

    # 12:15–13:32: lunch. Nothing for over an hour: the heartbeat.
    d.notes.append((3 * h + 15 * m, "lunch: nothing happens until 13:32"))

    # 13:32–14:30: back after a long break; fix-nav's build fails twice,
    # then passes; two runs of pokes a minute and a half apart.
    d.routine(API, 4 * h + 32 * m, 5 * h + 28 * m)
    d.turn(NAV, 4 * h + 50 * m, 5 * m, tools=14,
           plays=[(60, "build", True), (2 * m, "build", True), (4 * m, "build", False)],
           note="build fails twice on fix-nav, then passes")
    d.routine(NAV, 4 * h + 57 * m, 5 * h + 15 * m, mix="quick")
    d.taps(5 * h + 20 * m)
    d.taps(5 * h + 21 * m + 30, note="more pokes, right after")

    # 14:30–15:30: a 14-minute turn on api ends with its tests still
    # failing; the next turn fails once more, then fixes them.
    d.turn(API, 5 * h + 34 * m, 14 * m, tools=30,
           plays=[(4 * m, "tests", True), (8 * m, "tests", True), (11 * m, "tests", True)],
           note="a 14-minute turn ends with tests still failing")
    d.turn(API, 5 * h + 51 * m, 4 * m, tools=10, tests=True,
           plays=[(60, "tests", True), (3 * m, "tests", False)],
           note="the next turn fails again, then fixes them")
    d.routine(NAV, 5 * h + 35 * m, 6 * h + 10 * m, mix="quick")
    d.routine(BOOP, 5 * h + 40 * m, 6 * h + 5 * m)
    d.routine(API, 6 * h + 2 * m, 6 * h + 29 * m)

    # 15:30–15:58: a coffee break, too short for a heartbeat.
    d.notes.append((6 * h + 31 * m, "a coffee break until 15:58"))

    # 16:00–17:00: in the flow. Many quick wins on api, a deploy that
    # passes, one api_error, approvals on fix-nav.
    t = d.routine(API, 6 * h + 58 * m, 7 * h + 28 * m, mix="quick", tests_every=2)
    d.notes.append((6 * h + 58 * m, "in the flow: quick wins on api"))
    t = d.turn(API, 7 * h + 30 * m, 25, tools=2, end="failed", error="api_error", note="an API error")
    d.routine(API, 7 * h + 32 * m, 7 * h + 44 * m, mix="quick", tests_every=2)
    d.turn(API, 7 * h + 46 * m, 3 * m, tools=8, tests=True, plays=[(150, "deploy", False)],
           note="a deploy that passes")
    d.turn(NAV, 7 * h + 5 * m, 100, approval=40)
    d.routine(NAV, 7 * h + 10 * m, 7 * h + 55 * m)

    # 17:00–17:40: wrapping up: a 16-minute docs turn, a few last api
    # turns, sessions end.
    d.session(8 * h, DOCS)
    d.turn(DOCS, 8 * h + 1 * m, 16 * m, tools=20, note="a 16-minute docs turn")
    d.routine(API, 8 * h + 3 * m, 8 * h + 30 * m)
    d.session(8 * h + 35 * m, API, end=True)
    d.session(8 * h + 36 * m, NAV, end=True)
    d.session(8 * h + 37 * m, DOCS, end=True)
    d.session(8 * h + 38 * m, BOOP, end=True)

    # Docs edits carry the docs topic: tag the docs thread's edits.
    for s in d._steps:
        if s.kind == "hook" and s.line.get("session") == DOCS.session and s.line.get("tool") == "Edit":
            s.line["topic"] = "docs"
    return d


def clock(seconds: float) -> str:
    total = int(seconds) + 9 * 3600
    return f"{total // 3600:02d}:{total % 3600 // 60:02d}:{total % 60:02d}"


def plan(seed: int) -> str:
    d = build_day(seed)
    steps = d.steps()
    turns = sum(1 for s in steps if s.line.get("hook") == "UserPromptSubmit")
    lines = [f"seed {seed}: {len(steps)} steps, {turns} turns, 09:00 to {clock(steps[-1].at)}"]
    for at, note in sorted(d.notes):
        lines.append(f"  {clock(at)}  {note}")
    return "\n".join(lines)


# ---------------------------------------------------------------- the run


# What the fake device says it is when the app first speaks
# (linkkit/SPEC.md §5): Boop's device, playing every name Boop sends. It
# names no voice file, so the app picks takes as for a device that has its
# own, as it did before devices said hello.
HELLO = {"t": "hello", "kit": 1, "app": "boop", "id": "b00p-fake", "fw": "workday", "does": DOES}
# The brain's reactions, which `run` counts as played.
REACTIONS = {"react", "task_complete", "reply_ready"}


class FakeDevice:
    """The app's USB link connects here as it would to a bridge's.
    It answers the first message on each connection, and every `hello` the
    app sends, with a `hello` (linkkit/SPEC.md §3, §5), says every
    `do` with an `id` played to the end at once (the brain's reactions
    and the rules' reactions alike), and `tap` sends a tap as the board
    would."""

    def __init__(self, path: str) -> None:
        self.path = path
        self.conn: socket.socket | None = None
        self.reactions = 0
        self.greeted = False  # said hello on this connection
        self.lock = threading.Lock()
        if os.path.exists(path):
            os.unlink(path)
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(path)
        self.server.listen(1)
        threading.Thread(target=self._serve, daemon=True).start()

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with self.lock:
                self.conn = conn
            self.greeted = False
            buf = b""
            while True:
                try:
                    data = conn.recv(65536)
                except OSError:
                    break
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    raw, buf = buf.split(b"\n", 1)
                    self._line(raw)

    def _line(self, raw: bytes) -> None:
        try:
            msg = json.loads(raw)
        except ValueError:
            return
        if not isinstance(msg, dict):
            return
        # A hello for the app's first message, and for every hello it sends.
        first = not self.greeted and not str(msg.get("t", "")).startswith("dbg.")
        if first or msg.get("t") == "hello":
            self.greeted = True
            self.send(HELLO)
        if msg.get("t") == "do" and isinstance(msg.get("id"), int):
            self.reactions += msg.get("name") in REACTIONS
            self.send({"t": "ev", "kind": "ended", "data": {"id": msg["id"], "how": "done"}})

    def send(self, msg: dict[str, Any]) -> None:
        with self.lock:
            if self.conn:
                try:
                    self.conn.sendall(json.dumps(msg, separators=(",", ":")).encode() + b"\n")
                except OSError:
                    pass

    def tap(self) -> None:
        """A tap the device answered with its own poke."""
        self.send({"t": "ev", "kind": "tap", "did": "poked"})

    def close(self) -> None:
        self.server.close()
        with self.lock:
            if self.conn:
                self.conn.close()


class Run:
    def __init__(self, state: Path, brain: str, personality: str | None, verbose: bool) -> None:
        self.state = state
        self.verbose = verbose
        self.dev_sock = str(state / "d.sock")
        self.app = Headless(state, str(state / "b.sock"), f"usb:{self.dev_sock}", brain,
                            ["--personality", personality] if personality else [])
        self.device: FakeDevice | None = None
        self.log_pos = 0
        self.debug_pos = 0
        self.advances = 0
        self.log_advances = 0
        self.waiting_passes: set[int] = set()
        self.waiting_settles: set[int] = set()
        self.passes = 0
        self.dropped = 0
        # A pass was read and nothing has been read behind a barrier since
        # (`settle`).
        self.passes_unchecked = False

    def start(self) -> None:
        if self.app.brain == "jev" and not os.environ.get("BOOP_JEV_KEY"):
            raise DeviceError("--brain jev needs BOOP_JEV_KEY")
        if self.state.exists():
            shutil.rmtree(self.state)
        self.state.mkdir(parents=True)
        self.device = FakeDevice(self.dev_sock)
        with open(self.state / "stdout.txt", "wb") as out:
            self.app.start(stdout=out, seconds=15, poll=0.02)
        self.app.wait_for(self._brain_ready, 15, "the app to read its brain", poll=0.02)

    def _brain_ready(self) -> bool:
        """debug.jsonl's `status` lines name the brain once it's set."""
        if not self.app.debug.exists():
            return False
        for raw in self.app.debug.read_text(errors="replace").splitlines():
            if raw.startswith('{"status"'):
                brain = json.loads(raw)["status"].get("brain")
                if brain and brain != "none":
                    return True
        return False

    def _advanced(self) -> int:
        """How many clock moves the app has logged so far, read on from
        where the last look stopped."""
        with open(self.app.log, "rb") as f:
            f.seek(self.log_pos)
            data = f.read()
        end = data.rfind(b"\n")
        if end >= 0:
            self.log_pos += end + 1
            self.log_advances += data[:end].count(b"dev: clock advanced")
        return self.log_advances

    def stop(self) -> None:
        self.app.stop()
        if self.device:
            self.device.close()

    def advance(self, ms: int) -> None:
        """Moves the app's clock and waits until the app has done so: its
        log says so, after everything sent before it."""
        self.app.send({"dev": "advance", "ms": max(1, int(ms))})
        self.advances += 1
        want = self.advances
        self.app.wait_for(lambda: self._advanced() >= want, 10, "the clock to move", poll=0.02)

    def settle(self) -> None:
        """Waits for every pass the new events woke, and every reaction
        the brain started, to finish. The app writes a pass before its actions, so
        after a pass nothing waiting isn't enough: a clock move of 1 ms,
        which the app takes up only once the pass's actions are written,
        is a barrier, and the look after it counts. Without it the next
        step's clock move could land before a reaction's `ended` and end
        it as never played."""
        deadline = time.monotonic() + 30
        while True:
            self._read_debug()
            if not self.waiting_passes and not self.waiting_settles:
                if not self.passes_unchecked:
                    return
                self.passes_unchecked = False
                self.advance(1)
                continue
            if time.monotonic() > deadline:
                print(f"  warning: still waiting for passes {sorted(self.waiting_passes)} "
                      f"and settles {sorted(self.waiting_settles)}", file=sys.stderr)
                self.waiting_passes.clear()
                self.waiting_settles.clear()
                return
            time.sleep(0.02)

    def _read_debug(self) -> None:
        if not self.app.debug.exists():
            return
        with open(self.app.debug, "rb") as f:
            f.seek(self.debug_pos)
            data = f.read()
        end = data.rfind(b"\n")
        if end < 0:
            return
        self.debug_pos += end + 1
        for raw in data[:end].splitlines():
            try:
                line = json.loads(raw)
            except ValueError:
                continue
            k = feed.kind(line)
            body = line.get(k)
            if k == "view" and body.get("wakes_brain"):
                self.waiting_passes.add(body["from"][-1])
            elif k == "pass":
                # A held pass answers its event without asking the brain
                # and runs nothing; a forced one
                # (`by`) is the dashboard's. Neither is a brain pass.
                self.waiting_passes.discard(body.get("for"))
                if body.get("held") or not body.get("brain"):
                    continue
                self.passes += 1
                if body.get("dropped"):
                    self.dropped += 1
                else:
                    self.passes_unchecked = True
            elif k == "event" and (act := feed.action(body)) and act["pending"] and act["by"] is None:
                # The brain's reactions only: a rule's needs-you lasts
                # until the day answers the request, steps later.
                self.waiting_settles.add(body["seq"])
            elif k == "event" and (ended := feed.action_end(body)):
                self.waiting_settles.discard(ended["for"])
            if self.verbose:
                if k == "view":
                    print(f"  {feed.view_name(body)}: {body['line']}")
                elif k == "event" and (act := feed.action(body)):
                    print(f"    {act['name']}: {act['message']}")

    def replay(self, steps: list[Step]) -> None:
        # 09:00 tomorrow, local time, on the app's clock.
        now = dt.datetime.now()
        start = (now + dt.timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
        self.advance(int((start - now).total_seconds() * 1000))
        self.settle()
        t = 0.0
        began = time.monotonic()
        for i, step in enumerate(steps):
            # A long gap goes a minute at a time, so the core's timers (the
            # heartbeat) fire when they would, not all at the end.
            while step.at > t:
                move = min(step.at - t, 60.0) if step.at - t > 120 else step.at - t
                self.advance(int(move * 1000))
                t += move
                self.settle()
            if step.kind == "hook":
                line = dict(step.line)
                line["ts"] = int(time.time() * 1000)
                self.app.send(line)
            else:
                for _ in range(step.taps):
                    assert self.device
                    self.device.tap()
                    time.sleep(0.1)
                time.sleep(0.2)
            self.advance(1)  # a barrier: the app has handled the step
            self.settle()
            if not self.verbose and i % 200 == 0:
                print(f"  {clock(step.at)}  step {i}/{len(steps)}, {self.passes} passes, "
                      f"{time.monotonic() - began:.0f} s", flush=True)
        # The tail: an hour and a bit more, for the evening's heartbeat.
        for _ in range(65):
            self.advance(60_000)
            self.settle()


def run(state: Path, seed: int, brain: str, personality: str | None, out: Path | None, verbose: bool) -> int:
    steps = build_day(seed).steps()
    r = Run(state, brain, personality, verbose)
    print(plan(seed).splitlines()[0])
    try:
        r.start()
        r.replay(steps)
    finally:
        r.stop()
    print(f"done: {r.passes} passes, {r.dropped} dropped, {r.device.reactions if r.device else 0} reactions played")
    if out:
        out.mkdir(parents=True, exist_ok=True)
        shutil.copy(r.app.debug, out / "debug.jsonl")
        shutil.copy(r.app.log, out / "boop.log")
    print(report([r.app.debug]))
    return 0


# ---------------------------------------------------------------- the report


# What a step is, for the report: `notable` steps should almost always get
# a reaction; `minutes` (a finish done in 1 to 5 minutes) often; `short`
# (a finish done under a minute) and `start` now and then; `quiet` is the
# heartbeat. The mood shouldn't move for `start`, `short` or `minutes`.
# A finish is judged by what its step's line says: its outcome and length.
CLASSES = ["notable", "minutes", "short", "start", "quiet"]
ROUTINE = {"start", "short", "minutes"}


def classify(event: dict[str, Any]) -> str | None:
    kind, f = feed.view_name(event), event.get("facts", {})
    if kind == "turn start":
        return "start"
    if kind == "heartbeat":
        return "quiet"
    if kind == "turn end":
        done = f.get("outcome") == "done"
        length = f.get("length_ms") or 0
        if done and length < 60_000:
            return "short"
        if done and length < BIG_TURN_MS:
            return "minutes"
        return "notable"
    if kind in ("tool end", "poke"):
        return "notable"
    return None  # tool wait: never a pass


def new_hour() -> dict[str, Any]:
    return {"turns": 0, "passes": 0, "dropped": 0, "held": 0, "reactions": 0, "mood_changes": 0, "mood_after_routine": 0,
            "back_to_rest": 0, "check_ins": 0, "lines": Counter(), "reacted": Counter(), "faces": Counter(),
            "loops": Counter(), "words": Counter()}


def reaction(p: dict[str, Any]) -> dict[str, Any]:
    """A reaction's face, finish (success, failure or reply; None for a
    face alone) and hold, from its pass's answers as the dashboard reads
    them (dash/feed.py). What it said is the takes its action recorded."""
    return {"face": feed.choice(p, feed.FACE) or "?", "finish": feed.animation(p),
            "held": feed.choice(p, "react.loops") or "once"}


def summarize(path: Path) -> dict[str, Any]:
    """One run's debug.jsonl, by the hour of each event's time on the app's
    clock (local time): what woke the brain, what Boop did about it."""
    events: dict[int, dict[str, Any]] = {}
    passes: dict[int, dict[str, Any]] = {}  # the latest pass for each event
    hours: dict[int, dict[str, Any]] = defaultdict(new_hour)
    changes: list[dict[str, Any]] = []
    reactions: list[dict[str, Any]] = []
    # Boop's mood: the first `state` sent says it, and each mood output
    # changes it to its pass's answer.
    mood: str | None = None
    # When any agent works: [start, end] spans, from turn starts and ends.
    open_turns: dict[str, int] = {}
    working: list[list[int]] = []
    lines = [line for launch in daylog.read_launches([path]) for line in launch.lines]
    for line in lines:
        k, at = feed.kind(line), line["received_at_ms"]
        body = line.get(k)
        if k == "sent" and body.get("t") == "state" and mood is None:
            mood = body.get("mood")
        elif k == "view":
            ev = {**body, "at": at, "class": classify(body)}
            events[ev["from"][-1]] = ev
            hr = hours[daylog.hour_of(at)]
            name = feed.view_name(ev)
            session = (ev.get("facts", {}).get("thread") or {}).get("session")
            if name == "turn start" and session:
                if not open_turns:
                    working.append([at, at])
                open_turns[session] = at
            if name == "turn end" and session and open_turns.pop(session, None) is not None and not open_turns:
                working[-1][1] = at
            if name == "turn end":
                hr["turns"] += 1
            if ev.get("wakes_brain") and ev["class"]:
                hr["lines"][ev["class"]] += 1
            if ev.get("wakes_brain") and "idle_minutes" in ev.get("facts", {}):
                hr["check_ins"] += 1
        elif k == "pass" and body.get("for") in events and body.get("brain"):
            # The brain's passes; a forced one (`by`) is the dashboard's.
            passes[body["for"]] = body
            hr = hours[daylog.hour_of(events[body["for"]]["at"])]
            if body.get("held"):
                # Held back when its turn came: the brain wasn't asked.
                hr["held"] += 1
            else:
                hr["passes"] += 1
                hr["dropped"] += bool(body.get("dropped"))
        if k == "event" and (act := feed.action(body)) and act["by"] is None and act["ok"]:
            ev = events.get(act["for"])
            if ev is None:
                continue
            hr = hours[daylog.hour_of(ev["at"])]
            routine = ev["class"] in ROUTINE
            if act["name"] == "mood":
                before, mood = mood or REST, feed.choice(passes.get(act["for"], {}), "mood") or "?"
                hr["mood_changes"] += 1
                # On a routine step, going back to the resting mood is a
                # mood fading (the guide); any other change is one the step
                # shouldn't have caused.
                if routine and mood == REST:
                    hr["back_to_rest"] += 1
                elif routine:
                    hr["mood_after_routine"] += 1
                changes.append({"at": daylog.clock(ev["at"]), "ms": ev["at"], "from": before, "to": mood,
                                "after": ev["line"], "class": ev["class"]})
            elif act["name"] == "react":
                r = reaction(passes.get(act["for"], {}))
                hr["reactions"] += 1
                hr["reacted"][ev["class"]] += 1
                hr["faces"][r["face"]] += 1
                hr["loops"][r["held"]] += 1
                # What it said: the takes its action's start records.
                word = feed.said(act["takes"])
                hr["words"][word or "none"] += 1
                reactions.append({"at": daylog.clock(ev["at"]), "ms": ev["at"], "class": ev["class"], **r,
                                  "after": ev["line"], "word": word})
    # How long each mood lasted, from the first event to the last.
    spans: Counter = Counter()
    if events:
        at, now = min(ev["at"] for ev in events.values()), changes[0]["from"] if changes else mood or REST
        for c in changes:
            spans[now] += c["ms"] - at
            at, now = c["ms"], c["to"]
        spans[now] += max(ev["at"] for ev in events.values()) - at
    if open_turns and working and events:
        working[-1][1] = max(ev["at"] for ev in events.values())
    return {"hours": {k: hours[k] for k in sorted(hours)}, "changes": changes, "reactions": reactions,
            "mood_minutes": {k: round(v / 60_000) for k, v in spans.most_common()},
            "lively": {**liveliness(working, reactions, changes),
                       "min_reactions_per_turn": round(len(reactions) / max(1, sum(h["turns"] for h in hours.values())), 2)}}


# ------------------------------------------------------------- liveliness

# The loose limits `check` holds a day to (internal/EVALS.md §5): each catches
# a clear failure of the owner's brief (2026-09-28, and its fun brief of
# 2026-10-21), an animated Boop that reacts often, never idles for long,
# doesn't flail, doesn't say the same thing again and again, and says
# something more often than not; each is to be tightened once the day
# meets it.
LIMITS = {
    "longest_quiet_min": 8,       # the longest stretch of work with no reaction
    "quiet_over_6_min": 3,        # stretches of work over 6 minutes with no reaction
    "min_reactions_per_turn": 0.8,  # reactions over turns ended
    "mood_bounces": 1,            # a mood changing back to the one it left within a minute
    "min_mood_changes": 10,       # over the day
    "longest_rest_working_min": 45,  # the longest stretch of work in the resting mood all through
    "repeat_pct": 40,             # reactions the same as the one before (face, finish and what it said)
    "longest_same_run": 3,        # the same reaction in a row
    "min_words_said": 0.5,        # the share of reactions that said something
}


def liveliness(working: list[list[int]], reactions: list[dict[str, Any]],
               changes: list[dict[str, Any]]) -> dict[str, Any]:
    """How lively a day was: quiet stretches of work, repeats, and how the
    mood moved (internal/EVALS.md §5)."""
    times = [r["ms"] for r in reactions]
    gaps: list[tuple[int, int]] = []  # (ms, from)
    for a, b in working:
        marks = [a] + [t for t in times if a < t < b] + [b]
        gaps += [(y - x, x) for x, y in zip(marks, marks[1:])]
    longest = max(gaps, default=(0, 0))
    same = lambda x, y: (x["face"], x["finish"], x["word"]) == (y["face"], y["finish"], y["word"])
    run, best, best_what, repeats = 0, 0, "", 0
    for i, r in enumerate(reactions):
        again = i > 0 and same(reactions[i - 1], r)
        repeats += again
        run = run + 1 if again else 1
        if run > best:
            best, best_what = run, r["face"] + (f" {r['finish']}" if r["finish"] else "") + (f' "{r["word"]}"' if r["word"] else "")
    bounces = [f'{a["at"]} {a["from"]} → {a["to"]}, back at {b["at"]}' for a, b in zip(changes, changes[1:])
               if b["to"] == a["from"] and b["ms"] - a["ms"] < 60_000]
    # The longest stretch of work with Boop in the resting mood all through.
    rest: list[tuple[int, int]] = []
    mood_at = [(c["ms"], c["to"]) for c in changes]
    for a, b in working:
        mood = REST
        for t, m in mood_at:
            if t <= a:
                mood = m
        start = a if mood == REST else None
        for t, m in [(t, m) for t, m in mood_at if a < t < b] + [(b, "end")]:
            if start is not None and m != REST:
                rest.append((t - start, start))
                start = None
            elif start is None and m == REST:
                start = t
    longest_rest = max(rest, default=(0, 0))
    return {
        "longest_quiet_min": round(longest[0] / 60_000, 1), "longest_quiet_at": daylog.clock(longest[1]) if gaps else "–",
        "quiet_over_6_min": sum(1 for g, _ in gaps if g > 6 * 60_000),
        "longest_same_run": best, "longest_same_what": best_what,
        "repeat_pct": round(100 * repeats / max(1, len(reactions) - 1)),
        "mood_bounces": len(bounces), "bounces": bounces, "min_mood_changes": len(changes),
        "longest_rest_working_min": round(longest_rest[0] / 60_000, 1),
        "longest_rest_working_at": daylog.clock(longest_rest[1]) if rest else "–",
        "min_words_said": round(sum(1 for r in reactions if r["word"]) / max(1, len(reactions)), 2),
    }


def ledger(reactions: list[dict[str, Any]], hours: dict[int, dict[str, Any]]) -> list[str]:
    """The fun ledger, an hour a row: reactions, how many said something,
    how many kinds (face, finish and what it said), the longest run of the
    same, and the idle check-ins."""
    out = ["| Hour | Reactions | Said something | Kinds | Longest same run | Idle check-ins |",
           "| --- | --- | --- | --- | --- | --- |"]
    key = lambda r: (r["face"], r["finish"], r["word"])
    for h in sorted(hours):
        rs = [r for r in reactions if daylog.hour_of(r["ms"]) == h]
        run = best = 0
        for i, r in enumerate(rs):
            run = run + 1 if i and key(rs[i - 1]) == key(r) else 1
            best = max(best, run)
        out.append(f"| {h:02d}:00 | {len(rs)} | {sum(1 for r in rs if r['word'])} | {len({key(r) for r in rs})} | {best} "
                   f"| {hours[h]['check_ins']} |")
    return out


def check(paths: list[Path]) -> tuple[str, bool]:
    """Each run's liveliness against LIMITS: every line, and whether all held."""
    out, ok = [], True
    for p in paths:
        lv = summarize(p)["lively"]
        out.append(f"## {p}")
        for key, limit in LIMITS.items():
            got = lv[key]
            held = got >= limit if key.startswith("min_") else got <= limit
            ok &= held
            note = {"longest_quiet_min": f' (from {lv["longest_quiet_at"]})',
                    "mood_bounces": "".join(f"; {b}" for b in lv["bounces"]),
                    "longest_rest_working_min": f' (from {lv["longest_rest_working_at"]})',
                    "longest_same_run": f' ({lv["longest_same_what"] or "–"})'}.get(key, "")
            out.append(f'{"ok  " if held else "FAIL"}  {key} {"≥" if key.startswith("min_") else "≤"} {limit}: {got}{note}')
    return "\n".join(out), ok


def total(r: dict[str, Any]) -> dict[str, Any]:
    t = new_hour()
    for v in r["hours"].values():
        for k, x in v.items():
            t[k] += x
    return t


def report(paths: list[Path], as_json: bool = False) -> str:
    runs = [summarize(p) for p in paths]
    if as_json:
        return json.dumps([{"file": str(p), "all": total(r), **r} for p, r in zip(paths, runs)], indent=1)
    out = []
    for p, r in zip(paths, runs):
        out += [f"## {p}", "",
                "Reactions are to each kind of step that woke the brain, reacted/all: notable (failures, "
                "fixes, failed or stopped turns, turns of 5 min or more, pokes), finishes done in 1–5 min, "
                "finishes done under a minute, turn starts, heartbeats.", "",
                "Mood changes on a routine step (a turn start, or a finish done under 5 min) are split: back "
                f"to {REST}, the resting mood (a mood fading), and any other (which the step shouldn't cause).", "",
                f"| Hour | Turns | Passes | Mood changes | … routine, to {REST} | … routine, other | Reactions "
                "| notable | 1–5 min | short | starts | quiet | Faces |",
                "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
        all_hours = total(r)
        rows = [(f"{h:02d}:00", v) for h, v in r["hours"].items()] + [("all", all_hours)]
        for name, v in rows:
            rate = " | ".join(f"{v['reacted'][c]}/{v['lines'][c]}" for c in CLASSES)
            held = [f"{v['dropped']} dropped"] * bool(v["dropped"]) + [f"{v['held']} held back"] * bool(v["held"])
            out.append(f"| {name} | {v['turns']} | {v['passes']}" + (f" ({', '.join(held)})" if held else "")
                       + f" | {v['mood_changes']} | {v['back_to_rest']} | {v['mood_after_routine']}"
                       f" | {v['reactions']} | {rate}"
                       f" | {fmt(v['faces'])} |")
        lv = r["lively"]
        out += ["", f'Liveliness: longest quiet stretch of work {lv["longest_quiet_min"]} min (from {lv["longest_quiet_at"]}), '
                f'{lv["quiet_over_6_min"]} over 6 min; {lv["repeat_pct"]}% of reactions the same as the one before, '
                f'at most {lv["longest_same_run"]} in a row ({lv["longest_same_what"] or "–"}); '
                f'{lv["mood_bounces"]} mood bounces; longest stretch of work {REST} all through '
                f'{lv["longest_rest_working_min"]} min (from {lv["longest_rest_working_at"]})']
        out += ["", "Fun ledger:", ""] + ledger(r["reactions"], r["hours"])
        out += ["", "Holds: " + fmt(all_hours["loops"]),
                "", "Takes said (none: a reaction that said nothing): " + fmt(all_hours["words"]),
                "", "Time in each mood: " + ", ".join(f"{k} {v} min" for k, v in r["mood_minutes"].items()),
                "", "Mood changes:"]
        for c in r["changes"]:
            out.append(f"- {c['at']} {c['from']} → {c['to']} ({c['class']}): {c['after']}")
        out.append("")
    return "\n".join(out)


def fmt(c: Counter) -> str:
    return ", ".join(f"{k} {n}" for k, n in c.most_common()) or "–"


# ---------------------------------------------------------------- the command


def add_parser(sub: Any) -> None:
    """`boopctl workday` and its own subcommands."""
    p = sub.add_parser("workday", help="a scripted working day through the headless app and its brain, and "
                                       "what Boop did in it (EVALS.md §5)")
    days = p.add_subparsers(dest="workday", required=True, metavar="step")
    q = days.add_parser("plan", help="print the day's story")
    q.add_argument("--seed", type=int, default=1)
    q = days.add_parser("run", help="replay the day through Boop --headless, then report")
    q.add_argument("--state", required=True, help="a fresh state directory, short, under /tmp (it's deleted first)")
    q.add_argument("--seed", type=int, default=1)
    q.add_argument("--brain", choices=["jev", "scripted"], default="jev",
                   help="jev (the default) needs BOOP_JEV_KEY; scripted needs nothing")
    q.add_argument("--personality", choices=["boop", "chatter"])
    q.add_argument("--out", help="copy debug.jsonl and boop.log here")
    q.add_argument("--verbose", action="store_true", help="print every event and action")
    q = days.add_parser("report", help="sum up one or more runs' debug.jsonl, hour by hour")
    q.add_argument("files", nargs="+")
    q.add_argument("--json", action="store_true")
    q = days.add_parser("check", help="hold one or more runs' debug.jsonl to the liveliness limits; exits 1 if any fails")
    q.add_argument("files", nargs="+")
    p.set_defaults(func=main)


def main(args: Any) -> int:
    if args.workday == "plan":
        print(plan(args.seed))
    elif args.workday == "run":
        return run(Path(args.state), args.seed, args.brain, args.personality, Path(args.out) if args.out else None,
                   args.verbose)
    elif args.workday == "check":
        text, ok = check([Path(f) for f in args.files])
        print(text)
        return 0 if ok else 1
    else:
        print(report([Path(f) for f in args.files], args.json))
    return 0
