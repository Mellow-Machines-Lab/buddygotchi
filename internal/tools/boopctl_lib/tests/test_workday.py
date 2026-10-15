"""boopctl workday (internal/EVALS.md §5): the day is the same for a seed,
well formed, and tells the story it says; the report counts what it says,
from the passes' answers and the takes the actions recorded, never an
action's message; and the fake device speaks the device's wire. No app, no
brain."""
from __future__ import annotations

import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import workday  # noqa: E402
from pack import needs_voice  # noqa: E402


class DayTests(unittest.TestCase):
    def test_same_seed_same_day(self) -> None:
        a = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(1).steps()]
        b = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(1).steps()]
        c = [(s.at, s.kind, s.line, s.taps) for s in workday.build_day(2).steps()]
        self.assertEqual(a, b)
        self.assertNotEqual(a, c)

    def test_turns_never_overlap_on_one_thread(self) -> None:
        open_turn: dict[str, float] = {}
        for s in workday.build_day(1).steps():
            session, hook = s.line.get("session"), s.line.get("hook")
            if hook == "UserPromptSubmit":
                self.assertNotIn(session, open_turn, f"{session} starts a turn at {workday.clock(s.at)} inside another")
                open_turn[session] = s.at
            elif hook in ("Stop", "StopFailure") or s.line.get("interrupt"):
                self.assertIn(session, open_turn, f"{session} ends a turn it never started at {workday.clock(s.at)}")
                del open_turn[session]
        self.assertEqual(open_turn, {})

    def test_the_story(self) -> None:
        steps = workday.build_day(1).steps()
        hooks = Counter(s.line.get("hook") for s in steps)
        failures = [s for s in steps if s.line.get("hook") == "PostToolUseFailure" and not s.line.get("interrupt")]
        self.assertEqual({s.line["topic"] for s in failures}, {"tests", "build"})
        self.assertEqual(len([s for s in failures if s.line["topic"] == "tests"]), 7)
        self.assertEqual(len([s for s in failures if s.line["topic"] == "build"]), 3)
        self.assertEqual(hooks["StopFailure"], 2)
        self.assertEqual(hooks["PermissionRequest"], 2)
        self.assertEqual(sum(s.taps for s in steps if s.kind == "taps"), 12)
        self.assertGreater(hooks["UserPromptSubmit"], 150)
        # Lunch: over an hour with nothing, for the heartbeat.
        gaps = [b.at - a.at for a, b in zip(steps, steps[1:])]
        self.assertGreater(max(gaps), 3600)
        # 09:00 to about 17:40.
        self.assertLess(steps[-1].at, 9 * 3600)

    def test_the_plan_names_the_story(self) -> None:
        text = workday.plan(1)
        self.assertIn("tests fail three times, then pass", text)
        self.assertIn("lunch", text)


def entry(seq: int, at_min: int, view: dict | None = None, action: dict | None = None, settle: dict | None = None,
          **body) -> str:
    """A debug.jsonl line: a view event made by the raw event `seq`, an
    action (the kit's `did`, open if pending) or a started one's `ended`,
    or a pass or a `sent` line as given. An action's message is
    nonsense: the report must not read it."""
    base = 1_791_990_000_000  # any time; the report reads local hours
    at = base + at_min * 60_000
    if view is not None:
        body = {"view": {"id": seq, "from": [seq], "notes": [], **view}}
    elif action is not None:
        data = {"for": action["for"], "ok": action["ok"], "message": "not a fact → sad held four times, said \"Nope\".",
                "by": action.get("by", "brain"), **({"takes": action["takes"]} if "takes" in action else {})}
        data.update({"action": action["name"], **({"open": True} if action.get("pending") else {})})
        body = {"event": {"seq": seq, "at": at, "source": "self", "kind": "did", "data": data}}
    elif settle is not None:
        body = {"event": {"seq": seq, "at": at, "source": "self", "kind": "ended",
                          "data": {"for": settle["for"], "outcome": settle["end"], "by": "brain", "action": "react"}}}
    return json.dumps({"received_at_ms": at, **body})


def picks(event: int, at_min: int, mood: str = "calm", face: str = "none", held: str = "once",
          finish: str = "none") -> str:
    """The brain's pass for `event`, with its answers."""
    answers = {"mood": mood, "react.mood": face, "react.animation": finish, "react.loops": held,
               "say.feeling": "none", "say.about": "none", "say.kind": "sound"}
    return entry(0, at_min, **{"pass": {"for": event, "dropped": None, "brain": "scripted",
                                        "questions": list(answers),
                                        "answers": {k: {"choice": v, "p": {v: 1}} for k, v in answers.items()}}})


def state(at_min: int, mood: str = "calm") -> str:
    return entry(0, at_min, sent={"t": "state", "mood": mood})


class ReportTests(unittest.TestCase):
    def test_counts_by_kind_of_line(self) -> None:
        start = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True, "facts": {}}
        short = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a short turn.",
                 "wakes_brain": True, "facts": {"outcome": "done", "length_ms": 8000, "tools_failed": 0}}
        fail = {"type": "tool", "phase": "end", "line": "claude's tests failed on \"api\".", "wakes_brain": True, "facts": {}}
        lines = [
            state(0),
            entry(1, 0, view=start),
            picks(1, 0, mood="excited"),
            entry(3, 0, action={"for": 1, "name": "mood", "ok": True}),
            entry(4, 1, view=short),
            picks(4, 1, mood="excited"),
            entry(6, 2, view=fail),
            picks(6, 2, mood="grumpy", face="grumpy", held="twice"),
            entry(8, 2, action={"for": 6, "name": "react", "ok": True, "pending": True, "takes": ["no-such-take"]}),
            entry(9, 2, settle={"for": 8, "end": "done"}),
            entry(10, 2, action={"for": 6, "name": "mood", "ok": True}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            r = workday.summarize(path)
        t = workday.total(r)
        self.assertEqual(t["passes"], 3)
        self.assertEqual(t["mood_changes"], 2)
        self.assertEqual(t["mood_after_routine"], 1, "the change on a turn start counts, the one on a failure doesn't")
        self.assertEqual(t["back_to_rest"], 0)
        self.assertEqual(t["reactions"], 1)
        self.assertEqual(t["reacted"], Counter({"notable": 1}))
        self.assertEqual(t["lines"], Counter({"start": 1, "short": 1, "notable": 1}))
        self.assertEqual(t["faces"], Counter({"grumpy": 1}))
        self.assertEqual(t["loops"], Counter({"twice": 1}))
        self.assertEqual(t["words"], Counter({"no-such-take": 1}), "a take the pack doesn't have, by its id")
        self.assertEqual(r["reactions"][0]["word"], "no-such-take")
        # Excited from the first event to the failure 2 minutes later, then
        # grumpy to the last event, the same failure.
        self.assertEqual(r["mood_minutes"], {"excited": 2, "calm": 0, "grumpy": 0})

    def test_a_finish_is_its_passs_animation(self) -> None:
        """A reaction's finish is `react.animation`'s pick: success, failure
        or reply; a face alone has none."""
        end = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a short turn.",
               "wakes_brain": True, "facts": {"outcome": "done", "length_ms": 50_000, "tools_failed": 0}}
        lines = [entry(1, 0, view=end), picks(1, 0, face="calm", finish="success"),
                 entry(2, 0, action={"for": 1, "name": "react", "ok": True, "pending": True}),
                 entry(3, 1, view=end), picks(3, 1, face="happy"),
                 entry(4, 1, action={"for": 3, "name": "react", "ok": True, "pending": True})]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            self.assertEqual([r["finish"] for r in workday.summarize(path)["reactions"]], ["success", None])

    @needs_voice
    def test_the_takes_are_the_actions_and_a_reaction_that_said_nothing_is_none(self) -> None:
        """What a reaction said is the takes its action's start records:
        Voice picks a take for the meaning, so the answers can't say which."""
        end = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a short turn.",
               "wakes_brain": True, "facts": {"outcome": "done", "length_ms": 50_000, "tools_failed": 0}}
        lines = [
            entry(1, 0, view=end), picks(1, 0, face="happy"),
            entry(2, 0, action={"for": 1, "name": "react", "ok": True, "pending": True, "takes": []}),
            entry(3, 1, view=end), picks(3, 1, face="excited"),
            entry(4, 1, action={"for": 3, "name": "react", "ok": True, "pending": True, "takes": ["new.d03"]}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            self.assertEqual(workday.total(workday.summarize(path))["words"], Counter({"none": 1, "Done": 1}))
            self.assertIn("Takes said (none: a reaction that said nothing): none 1, Done 1", workday.report([path]))

    def test_a_mood_fading_on_a_routine_line_is_counted_apart(self) -> None:
        start = {"type": "turn", "phase": "start", "line": "claude started turn 2 on \"api\".", "wakes_brain": True, "facts": {}}
        lines = [
            state(0, mood="proud"),
            entry(1, 0, view=start),
            picks(1, 0, mood="calm"),
            entry(2, 0, action={"for": 1, "name": "mood", "ok": True}),
            entry(3, 5, view=start),
            picks(3, 5, mood="proud"),
            entry(4, 5, action={"for": 3, "name": "mood", "ok": True}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            t = workday.total(workday.summarize(path))
        self.assertEqual((t["mood_changes"], t["back_to_rest"], t["mood_after_routine"]), (2, 1, 1))

    def test_liveliness_and_its_check(self) -> None:
        """A 20-minute turn with the same happy face at 1 and 3 minutes and
        nothing after: quiet for 17 minutes at the end, two the same in a
        row; calm → grumpy → calm inside a minute is a bounce
        (EVALS.md §5)."""
        thread = {"session": "s-api"}
        start = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True,
                 "facts": {"thread": thread}}
        beat = {"type": "heartbeat", "line": "claude is still working on \"api\", a long turn.", "wakes_brain": True,
                "facts": {"thread": thread}}
        end = {"type": "turn", "phase": "end", "line": "claude finished turn 1 on \"api\": done, a very long turn.",
               "wakes_brain": True, "facts": {"thread": thread, "outcome": "done", "length_ms": 1_200_000}}
        lines = [
            entry(1, 0, view=start),
            entry(2, 1, view=beat),
            picks(2, 1, face="happy"),
            entry(3, 1, action={"for": 2, "name": "react", "ok": True, "pending": True}),
            entry(4, 3, view=beat),
            picks(4, 3, mood="grumpy", face="happy"),
            entry(5, 3, action={"for": 4, "name": "react", "ok": True, "pending": True}),
            entry(6, 3, action={"for": 4, "name": "mood", "ok": True}),
            entry(9, 3, view=beat),
            picks(9, 3, mood="calm"),
            entry(7, 3, action={"for": 9, "name": "mood", "ok": True}),
            entry(8, 20, view=end),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            lv = workday.summarize(path)["lively"]
            text, ok = workday.check([path])
        self.assertEqual(lv["longest_quiet_min"], 17.0)
        self.assertEqual(lv["quiet_over_6_min"], 1)
        self.assertEqual((lv["longest_same_run"], lv["longest_same_what"], lv["repeat_pct"]), (2, "happy", 100),
                         "reported, not held to a limit")
        self.assertEqual(lv["mood_bounces"], 1)
        self.assertEqual(lv["min_mood_changes"], 2)
        self.assertEqual(lv["longest_rest_working_min"], 17.0)
        self.assertFalse(ok)
        self.assertIn("FAIL  longest_quiet_min ≤ 8: 17.0", text)
        self.assertIn("ok    quiet_over_6_min ≤ 3: 1", text)
        self.assertEqual(lv["min_reactions_per_turn"], 2.0, "two reactions, one turn ended")
        self.assertIn("ok    min_reactions_per_turn ≥ 0.8: 2.0", text)
        self.assertIn("(repeats, not held to a limit: 100% the same as the one before, at most 2 in a row)", text)

    def test_held_and_forced_passes_arent_the_brains(self) -> None:
        """A pass held back when its turn came never asked the brain,
        and a forced one is the dashboard's: the
        report counts neither as a pass, and says how many were held."""
        start = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True,
                 "facts": {}}
        lines = [
            entry(1, 0, view=start), picks(1, 0),
            entry(2, 1, view=start),
            entry(0, 1, **{"pass": {"for": 2, "dropped": None, "brain": "scripted", "held": "something needs you",
                                    "answers": {}}}),
            entry(0, 2, **{"pass": {"for": None, "dropped": None, "by": "dashboard", "questions": ["react.mood"],
                                    "answers": {"react.mood": {"choice": "happy", "p": {"happy": 1}}}}}),
        ]
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / "debug.jsonl"
            path.write_text("\n".join(lines) + "\n")
            t = workday.total(workday.summarize(path))
            self.assertEqual((t["passes"], t["held"], t["dropped"]), (1, 1, 0))
            self.assertIn("| all | 0 | 1 (1 held back) |", workday.report([path]))

    def test_classes(self) -> None:
        def end(**facts) -> dict:
            return {"type": "turn", "phase": "end", "facts": {"outcome": "done", "tools_failed": 0, **facts}}
        self.assertEqual(workday.classify(end(length_ms=59_000)), "short")
        self.assertEqual(workday.classify(end(length_ms=60_000)), "minutes")
        # A turn of 5 minutes or more is a big moment.
        self.assertEqual(workday.classify(end(length_ms=5 * 60_000 - 1)), "minutes")
        self.assertEqual(workday.classify(end(length_ms=5 * 60_000)), "notable")
        # The line says only the outcome and length, so failures along the way don't count.
        self.assertEqual(workday.classify(end(length_ms=5_000, tools_failed=1)), "short")
        self.assertEqual(workday.classify(end(length_ms=5_000, comeback="tests")), "short")
        self.assertEqual(workday.classify(end(length_ms=5_000, outcome="failed")), "notable")
        self.assertEqual(workday.classify({"type": "heartbeat"}), "quiet")
        self.assertEqual(workday.classify({"type": "poke"}), "notable")
        self.assertIsNone(workday.classify({"type": "tool", "phase": "wait"}))


class SettleTests(unittest.TestCase):
    def test_a_pass_is_looked_at_again_behind_a_barrier(self) -> None:
        """The app writes a pass before its actions: settling on the pass
        alone would let the next clock move end a reaction as never
        played. So `settle` moves the clock 1 ms as a barrier, and waits
        for the reaction it then finds."""
        wakes = {"type": "tool", "phase": "end", "line": "claude's tests failed on \"api\".", "wakes_brain": True, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.app.debug.write_text(entry(1, 0, view=wakes) + "\n" + picks(1, 0) + "\n")
            barriers: list[int] = []
            ended = threading.Event()

            def advance(ms: int) -> None:
                barriers.append(ms)
                with open(run.app.debug, "a") as f:
                    f.write(entry(3, 0, action={"for": 1, "name": "react", "ok": True, "pending": True}) + "\n")

                def device_says_ended() -> None:
                    with open(run.app.debug, "a") as f:
                        f.write(entry(4, 0, settle={"for": 3, "end": "done"}) + "\n")
                    ended.set()
                threading.Timer(0.1, device_says_ended).start()

            run.advance = advance  # type: ignore[method-assign]
            run.settle()
            self.assertEqual(barriers, [1])
            self.assertTrue(ended.is_set(), "settle returned before the reaction ended")
            self.assertEqual((run.waiting_passes, run.waiting_settles), (set(), set()))
            # Nothing new since: no second barrier.
            run.settle()
            self.assertEqual(barriers, [1])

    def test_a_rules_needs_you_isnt_waited_for(self) -> None:
        """A rule's needs-you stays started until the day answers the
        request, steps later: `settle` waits only for the brain's."""
        wait = {"type": "tool", "phase": "wait", "line": "claude needs you on \"api\".", "wakes_brain": False, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.app.debug.write_text(entry(1, 0, view=wait) + "\n"
                                 + entry(2, 0, action={"for": 1, "name": "needs_you", "ok": True, "pending": True,
                                                       "by": "rule"}) + "\n")
            began = time.monotonic()
            run.settle()
            self.assertLess(time.monotonic() - began, 1)
            self.assertEqual(run.waiting_settles, set())

    def test_a_held_or_forced_pass_is_no_pass_and_needs_no_barrier(self) -> None:
        """A held pass answers its event without asking the brain and runs
        nothing; a forced one is the dashboard's."""
        wakes = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.app.debug.write_text(entry(1, 0, view=wakes) + "\n"
                                 + entry(2, 0, **{"pass": {"for": 1, "dropped": None, "brain": "scripted",
                                                           "held": "something needs you"}}) + "\n"
                                 + entry(3, 0, **{"pass": {"for": None, "dropped": None, "by": "dashboard"}}) + "\n")
            barriers: list[int] = []
            run.advance = barriers.append  # type: ignore[method-assign]
            run.settle()
            self.assertEqual((barriers, run.passes, run.dropped, run.waiting_passes), ([], 0, 0, set()))

    def test_a_dropped_pass_needs_no_barrier(self) -> None:
        wakes = {"type": "turn", "phase": "start", "line": "claude started turn 1 on \"api\".", "wakes_brain": True, "facts": {}}
        with tempfile.TemporaryDirectory() as d:
            run = workday.Run(Path(d), "scripted", None, False)
            run.app.debug.write_text(entry(1, 0, view=wakes) + "\n"
                                 + entry(2, 0, **{"pass": {"for": 1, "dropped": "late", "brain": "scripted"}}) + "\n")
            barriers: list[int] = []
            run.advance = barriers.append  # type: ignore[method-assign]
            run.settle()
            self.assertEqual(barriers, [])
            self.assertEqual(run.dropped, 1)


class FakeDeviceTests(unittest.TestCase):
    """The fake device the app's USB link connects to speaks the device's
    wire (linkkit/SPEC.md §3–5): a `hello` for the first line
    the app sends and for every `hello` it sends, an `ended` for every
    request with an id, and taps as `ev`."""

    def test_it_says_hello_and_ends_every_request(self) -> None:
        d = tempfile.mkdtemp(dir="/tmp")
        path = os.path.join(d, "d.sock")
        device = workday.FakeDevice(path)
        self.addCleanup(lambda: (device.close(), os.path.exists(path) and os.unlink(path), os.rmdir(d)))
        app = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        app.connect(path)
        app.settimeout(2)
        self.addCleanup(app.close)
        got: list[dict] = []
        buf = b""

        def read(n: int) -> list[dict]:
            nonlocal buf
            while len(got) < n:
                buf += app.recv(65536)
                *lines, buf = buf.split(b"\n")
                got.extend(json.loads(line) for line in lines if line)
            return got

        def send(msg: dict) -> None:
            app.sendall(json.dumps(msg).encode() + b"\n")

        send({"t": "dbg.ping"})  # a tool's line isn't the app speaking
        send({"t": "hello"})  # the app's first line on connect
        send({"t": "state", "base": "idle", "mood": "calm", "busy": 0, "vol": 6})
        send({"t": "state", "base": "idle", "mood": "calm", "busy": 0, "vol": 6})
        send({"t": "do", "name": "react", "play": "now", "args": {"say": {}}})  # no id: no answer
        send({"t": "do", "id": 558386701, "name": "starting", "play": "if_free", "args": {"variant": 3}})
        send({"t": "do", "id": 558386702, "name": "task_complete", "play": "next", "ttl": 5000,
              "args": {"outcome": "success", "mood": "proud"}})
        send({"t": "hello"})  # asked again: said again
        read(4)
        device.tap()
        read(5)
        self.assertEqual(got[0], {"t": "hello", "kit": 1, "app": "boop", "id": "b00p-fake", "fw": "workday",
                                  "does": ["react", "task_complete", "reply_ready", "starting", "stopped", "error",
                                           "helper_return", "listening", "stop_listening", "poked", "tap_spam"]},
                         "once for the app's first line, its hello; no voice, so the app's lines are taken as played")
        self.assertEqual(got[1:], [{"t": "ev", "kind": "ended", "data": {"id": 558386701, "how": "done"}},
                                   {"t": "ev", "kind": "ended", "data": {"id": 558386702, "how": "done"}},
                                   got[0],
                                   {"t": "ev", "kind": "tap", "did": "poked"}])
        self.assertEqual(device.reactions, 1, "the brain's finish; the rules' one-shot isn't a reaction")


if __name__ == "__main__":
    unittest.main()
