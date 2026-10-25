"""boopctl day (internal/VERIFICATION.md §2): a day's summary from debug mode's
logs, against a simulated day recorded from a real headless run with a
relaunch mid-day (fixtures/day, since rewritten into today's lines), and
against small made-up logs for the rules. Needs no board, app or sim."""
import contextlib
import io
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli, day  # noqa: E402
from boopctl_lib.common import FINISHES  # noqa: E402
from old_logs import as_do  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "day"
TZ = os.environ.get("TZ")


def setUpModule():
    # The fixture was recorded in Seoul; its hours are Seoul's.
    os.environ["TZ"] = "Asia/Seoul"
    time.tzset()


def tearDownModule():
    if TZ is None:
        os.environ.pop("TZ", None)
    else:
        os.environ["TZ"] = TZ
    time.tzset()


def at(clock: str, date: str = "2026-09-28") -> int:
    """Local time → ms."""
    return int(time.mktime(time.strptime(f"{date} {clock}", "%Y-%m-%d %H:%M:%S")) * 1000)


def state(t: int, attn: tuple | None = None, mood: str = "happy", more: int = 0, id: int | None = None) -> dict:
    s = {"t": "state", "base": "idle", "mood": mood, "busy": 0, "vol": 6}
    if attn:
        s["attn"] = {"agent": attn[0], "project": attn[1], "more": more}
        if id is not None:
            s["attn"]["id"] = id
    return {"sent": s, "received_at_ms": t}


def launch(*lines: dict) -> day.Launch:
    return day.Launch("debug.jsonl", [{"questions": [], "received_at_ms": lines[0]["received_at_ms"]}, *lines])


class FilesTests(unittest.TestCase):
    def test_the_state_dirs_logs_oldest_launch_first(self):
        with tempfile.TemporaryDirectory() as d:
            for name in ["debug.jsonl", "debug.1.jsonl", "debug.2.jsonl", "debug.10.jsonl", "debug.x.jsonl", "boop.log"]:
                (Path(d) / name).write_text("")
            self.assertEqual([p.name for p in day.launch_files(Path(d))],
                             ["debug.10.jsonl", "debug.2.jsonl", "debug.1.jsonl", "debug.jsonl"])

    def test_each_file_is_a_launch_and_a_questions_line_starts_another(self):
        launches = day.read_launches(day.launch_files(FIXTURE))
        self.assertEqual([x.name for x in launches], ["debug.1.jsonl", "debug.jsonl"])
        self.assertTrue(all("questions" in x.lines[0] for x in launches))
        with tempfile.TemporaryDirectory() as d:
            both = Path(d) / "both.jsonl"
            both.write_text((FIXTURE / "debug.1.jsonl").read_text() + "{not json\n" + (FIXTURE / "debug.jsonl").read_text())
            self.assertEqual([len(x.lines) for x in day.read_launches([both])], [len(x.lines) for x in launches],
                             "a line cut short is skipped")


class FixtureTests(unittest.TestCase):
    """The simulated day: a Claude turn in the first launch; then Codex and
    Claude working, both needing you, a tap, three failed tests and a
    rate limit; a quiet midday with the board unplugged a while; pokes and
    reactions forced from the dashboard; and a long Claude turn."""

    @classmethod
    def setUpClass(cls):
        cls.day = day.summarise(day.read_launches(day.launch_files(FIXTURE)), "2026-09-28")

    def test_what_boop_did_by_the_hour(self):
        t = self.day.total()
        self.assertEqual((t.finishes, t.chatter, t.reactions, t.alerts, t.moods, t.passes, t.dropped, t.missed, t.pokes),
                         (3, 17, 15, 4, 6, 15, 0, 2, 5))
        self.assertEqual(sorted(self.day.hours), [1, 2, 3, 4, 5, 6])
        self.assertEqual([self.day.hours[h].reactions for h in range(1, 7)], [5, 5, 1, 3, 1, 0])
        self.assertEqual(dict(t.faces), {"excited": 15}, "the scripted brain always answers excited")
        self.assertEqual((self.day.forced, self.day.forced_reacts), (9, 8))

    def test_the_brains_reactions_are_its_react_actions_and_forced_ones_are_apart(self):
        """20 moments with a face were sent (counted by hand): 14 of the
        brain's 15 reactions (02:11's never reached the device) and 6 of the
        8 forced (01:48's was refused and 04:48's excited one waited too
        long). Chatter and finishes are the sent moments."""
        sent = [json.loads(line)["sent"] for f in ("debug.1.jsonl", "debug.jsonl")
                for line in (FIXTURE / f).read_text().splitlines() if line.startswith('{"sent":{"t":"moment"')]
        t = self.day.total()
        faces = [s["mood"] for s in sent if s.get("say") and s.get("mood")]
        self.assertEqual(len(faces), (t.reactions - 1) + (self.day.forced_reacts - 2))
        self.assertEqual(sorted(f for f in faces if f != "excited"), ["curious", "curious", "determined", "happy",
                                                                      "proud", "sad"], "the forced ones")
        self.assertEqual(t.chatter, sum(1 for s in sent if s.get("say") and not s.get("mood")))
        self.assertEqual(t.finishes, sum(1 for s in sent if s.get("anim") in FINISHES))

    def test_needs_you_from_attn_appearing_to_clearing(self):
        needs = [(day.clock(n.start), n.end - n.start, n.who, n.alerts, n.open) for n in self.day.needs]
        self.assertEqual(needs, [
            ("01:34", 12028, ["claude · jetpack"], 1, False),
            ("01:47", 363666, ["codex · landing", "claude · jetpack"], 2, False),
            ("05:13", 421612, ["claude · jetpack"], 1, False),
        ])
        self.assertEqual(self.day.hours[1].needs_ms, 12028 + 363666)
        self.assertEqual(self.day.total().needs_ms, 12028 + 363666 + 421612)

    def test_each_mood_change_with_what_made_it(self):
        moods = [(m.before, m.after, m.why.split(":")[0]) for m in self.day.moods]
        self.assertEqual(moods, [
            ("happy", "proud", "forced from the dashboard"),
            ("proud", "happy", "turn start"),
            ("happy", "determined", "forced from the dashboard"),
            ("determined", "happy", "turn end"),
            ("happy", "grumpy", "forced from the dashboard"),
            ("grumpy", "happy", "turn start"),
        ])

    def test_reactions_that_didnt_happen_and_why(self):
        # Every end a reaction can have that the run could bring about, and
        # the action's own refusal.
        self.assertEqual(sorted((m.forced, m.why) for m in self.day.misses), [
            (False, "no device connected"), (False, "no word it finished"),
            (True, "cut short: you tapped Boop"), (True, "something needs you"), (True, "the device disconnected"),
            (True, "the device never said it ended"), (True, "waited too long")])

    def test_the_relaunch_keeps_the_morning(self):
        """Without debug.1.jsonl (before the app kept it), the first
        launch's needs-you, cheer and proud mood are gone."""
        alone = day.summarise(day.read_launches([FIXTURE / "debug.jsonl"]), "2026-09-28")
        self.assertEqual(len(alone.needs), 2)
        self.assertEqual(alone.total().finishes, 2)
        self.assertEqual(self.day.launches[0][0], "debug.1.jsonl")
        self.assertEqual(self.day.running_ms, sum(b - a for _, a, b, _ in self.day.launches))

    def test_the_same_day_from_do_lines(self):
        """The Mac sends a `do` where it sent a `moment` (old_logs.as_do):
        the day reads the same from either."""
        with tempfile.TemporaryDirectory() as d:
            for f in ("debug.1.jsonl", "debug.jsonl"):
                lines = [as_do(json.loads(line)) for line in (FIXTURE / f).read_text().splitlines()]
                self.assertTrue(any(line.get("sent", {}).get("t") == "do" for line in lines))
                (Path(d) / f).write_text("".join(json.dumps(line) + "\n" for line in lines))
            now = day.summarise(day.read_launches(day.launch_files(Path(d))), "2026-09-28")
        self.assertEqual(day.render(now), day.render(self.day))
        self.assertEqual((now.total().finishes, now.total().chatter), (3, 17))

    def test_the_table(self):
        text = day.render(self.day)
        lines = text.splitlines()
        self.assertEqual(lines[0], "Boop's day: Monday 2026-09-28, 01:34–06:01, 2 launches")
        head = next(i for i, x in enumerate(lines) if x.startswith("hour"))
        self.assertEqual(lines[head].split(), ["hour", "finishes", "chatter", "reacts", "said", "alerts", "moods", "passes",
                                               "dropped", "missed", "pokes", "needs", "you", "faces"])
        self.assertEqual([x.split()[0] for x in lines[head + 1:head + 8]], ["01", "02", "03", "04", "05", "06", "all"])
        self.assertIn("  01:47  codex · landing → claude · jetpack  6 min 4 s, 2 alerts", lines)
        self.assertIn("  1× cut short: you tapped Boop (forced): 01:53", lines)
        self.assertIn("Reactions that didn't happen: 2 of the brain's 15, and 5 of the 8 forced from the dashboard",
                      lines)


def event(t: int, seq: int, kind: str, wakes: bool = True) -> dict:
    """A view event, `turn start` say, made by the raw event `seq`."""
    type_, _, phase = kind.partition(" ")
    view = {"id": seq, "type": type_, "from": [seq], "line": f"a {kind}.", "notes": [], "wakes_brain": wakes, "facts": {}}
    if phase:
        view["phase"] = phase
    return {"view": view, "received_at_ms": t}


def a_pass(t: int, seq: int, for_: int | None, face: str | None = None, **choices: str) -> dict:
    """A pass's answers: its reaction `face` (`react.face`) and any other
    answer by its key."""
    choices = {**choices, **({"react.face": face} if face else {})}
    body = {"for": for_, "dropped": None, "latency_ms": 0 if for_ is None else 700,
            "answers": {k: {"choice": v, "p": {v: 1}} for k, v in choices.items()}}
    body.update({"by": "dashboard"} if for_ is None else {"brain": "jev:jev-latest"})
    return {"pass": body, "received_at_ms": t}


def raw_action(t: int, seq: int, name: str, phase: str | None, data: dict) -> dict:
    """An action as the log has it: a `did`, open
    while it plays, or its `ended`."""
    data = {**data, "action": name, **({"open": True} if phase == "start" else {})}
    e = {"seq": seq, "at": t, "source": "self", "kind": "ended" if phase == "end" else "did", "data": data}
    return {"event": e, "received_at_ms": t}


def action(t: int, seq: int, for_: int | None, name: str, ok: bool = True, message: str = "", pending: bool = False):
    return raw_action(t, seq, name, "start" if pending else None,
                      {"for": for_, "ok": ok, "message": message, "latency_ms": 0,
                       "by": "dashboard" if for_ is None else "brain"})


def settle(t: int, seq: int, for_: int, end: str, why: str | None = None) -> dict:
    """A started action's end."""
    return raw_action(t, seq, "react", "end", {"for": for_, "outcome": end, "by": "brain", **({"why": why} if why else {})})


def status(t: int, connected: bool) -> dict:
    return {"status": {"brain": "jev:jev-latest", "connected": connected, "personality": "boop", "sessions": []},
            "received_at_ms": t}


class SmallDayTests(unittest.TestCase):
    """Three launches counted by hand. The first ends while something
    needs you; the second starts disconnected and connects later; the
    third starts in a mood set while no debug log ran."""

    @classmethod
    def setUpClass(cls):
        first = [
            {"questions": [], "received_at_ms": at("09:00:00")}, status(at("09:00:00"), True), state(at("09:00:00")),
            event(at("09:05:00"), 1, "turn start"),
            a_pass(at("09:05:01"), 2, 1, mood="grumpy", face="grumpy"),
            state(at("09:05:01"), mood="grumpy"),  # the mood output's state goes out before its entry
            action(at("09:05:01"), 3, 1, "mood", message="Boop's mood changed: happy → grumpy."),
            action(at("09:05:01"), 4, 1, "react", pending=True),
            settle(at("09:05:03"), 5, 4, "done"),
            state(at("09:10:00"), ("claude", "a"), mood="grumpy"),  # needs you: an alert
            state(at("09:20:00"), ("claude", "a"), mood="excited"),  # the dashboard's mood line
            action(at("09:20:00"), 6, None, "mood", message="Boop's mood changed: grumpy → excited."),
            a_pass(at("09:30:00"), 7, None, face="happy"),
            action(at("09:30:00"), 8, None, "react", ok=False, message="something needs you"),
            state(at("09:40:00"), ("claude", "a"), mood="excited"),  # the launch ends: still up
        ]
        second = [
            {"questions": [], "received_at_ms": at("10:00:00")}, status(at("10:00:00"), False),
            state(at("10:00:00"), mood="excited"),  # carried over: no change
            status(at("10:10:00"), True),
            state(at("10:15:00"), ("claude", "a"), mood="excited"),  # an alert again: 10:00's state had no attn
            state(at("10:20:00"), mood="excited"),
            event(at("10:30:00"), 1, "tool end"),
            a_pass(at("10:30:01"), 2, 1, **{"react.mood": "curious"}),  # an older log's face
            action(at("10:30:01"), 3, 1, "react", pending=True),
            settle(at("10:30:07"), 4, 3, "failed", "waited too long"),
            state(at("10:45:00"), mood="excited"),
        ]
        third = [{"questions": [], "received_at_ms": at("11:00:00")}, state(at("11:00:00"), mood="sad"),
                 state(at("11:05:00"), mood="sad")]
        cls.tmp = tempfile.TemporaryDirectory()
        for name, lines in (("debug.2.jsonl", first), ("debug.1.jsonl", second), ("debug.jsonl", third)):
            (Path(cls.tmp.name) / name).write_text("".join(json.dumps(x) + "\n" for x in lines))
        cls.day = day.summarise(day.read_launches(day.launch_files(Path(cls.tmp.name))), "2026-09-28")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_the_hours(self):
        row = lambda h: (h.reactions, dict(h.faces), h.alerts, h.moods, h.passes, h.missed, h.needs_ms // 60_000)
        self.assertEqual({hr: row(h) for hr, h in self.day.hours.items()}, {
            9: (1, {"grumpy": 1}, 1, 2, 1, 0, 30),
            10: (1, {"curious": 1}, 1, 0, 1, 1, 5),
            11: (0, {}, 0, 1, 0, 0, 0),
        })
        self.assertEqual((self.day.forced, self.day.forced_reacts), (1, 1))

    def test_moods_by_the_brain_the_dashboard_and_between_launches(self):
        self.assertEqual([(day.clock(m.at), m.before, m.after, m.why) for m in self.day.moods], [
            ("09:05", "happy", "grumpy", "turn start: a turn start."),
            ("09:20", "grumpy", "excited", "forced from the dashboard"),
            ("11:00", "excited", "sad", "between launches"),
        ])

    def test_needs_you_across_the_relaunch(self):
        self.assertEqual([(day.clock(n.start), n.end - n.start, n.alerts, n.open) for n in self.day.needs], [
            ("09:10", 30 * 60_000, 1, True), ("10:15", 5 * 60_000, 1, False)])

    def test_running_and_connected(self):
        self.assertEqual([(name, day.clock(a), day.clock(b)) for name, a, b, _ in self.day.launches], [
            ("debug.2.jsonl", "09:00", "09:40"), ("debug.1.jsonl", "10:00", "10:45"), ("debug.jsonl", "11:00", "11:05")])
        self.assertEqual((self.day.running_ms, self.day.connected_ms), (90 * 60_000, 75 * 60_000))

    def test_what_didnt_happen(self):
        text = day.render(self.day).splitlines()
        self.assertIn("Reactions that didn't happen: 1 of the brain's 2, and 1 of the 1 forced from the dashboard", text)
        self.assertIn("  1× waited too long: 10:30", text)
        self.assertIn("  1× something needs you (forced): 09:30", text)
        self.assertIn("  09:10  claude · a  30 min (still up when the log ends)", text)
        self.assertIn("Needs you: 2 times, 35 min in all; cleared in 5 min", text)
        self.assertIn("Brain: 2 passes (answered in a median 700 ms, the slowest 700 ms), 0 dropped, 0 chose no reaction; "
                      "and 1 forced from the dashboard, asking for 1 reaction", text)


class RuleTests(unittest.TestCase):
    def test_finishes_are_the_brains_task_complete_and_reply_ready(self):
        """A finish is task_complete or reply_ready; a reaction with no
        animation and a rule's reaction aren't. The rules' requests aren't
        chatter."""
        do = lambda t, by, name, play="next", **args: {  # noqa: E731
            "sent": {"t": "do", "id": t % 1000, "name": name, "play": play, "args": args}, "by": by, "received_at_ms": t}
        d = day.summarise([launch(
            state(at("09:00:00")),
            do(at("09:01:00"), "brain", "task_complete", outcome="success", mood="calm", loops=1, say={"take": "a"}),
            do(at("09:02:00"), "brain", "reply_ready", mood="curious", loops=1, say={}),
            do(at("09:03:00"), "brain", "react", mood="proud", loops=2, say={"take": "a"}),
            do(at("09:04:00"), "rule", "starting", "if_free", variant=1, ctx="new_task"),
            do(at("09:05:00"), "rule", "listening", "now"),
            do(at("09:05:05"), "rule", "stop_listening", "if_free"),
        )], "2026-09-28")
        self.assertEqual((d.total().finishes, d.total().chatter), (2, 0))

    def test_a_finish_the_device_didnt_play_isnt_one(self):
        """linkkit/SPEC.md §4: the device decides what plays, and says how
        each `do` went (`ended`). A finish it skipped, or one cut short by
        anything but your tap, didn't play; one your tap cut did, and one
        with no word yet counts as sent."""
        do = lambda t, id, name: {  # noqa: E731
            "sent": {"t": "do", "id": id, "name": name, "play": "next", "ttl": 5000, "args": {"mood": "calm"}},
            "by": "brain", "received_at_ms": t}
        ended = lambda t, id, how, why=None: {  # noqa: E731
            "ended": {"id": id, "how": how, **({"why": why} if why else {})}, "received_at_ms": t}
        d = day.summarise([launch(
            state(at("09:00:00")),
            do(at("09:01:00"), 1, "task_complete"), ended(at("09:01:06"), 1, "done"),
            do(at("09:02:00"), 2, "reply_ready"), ended(at("09:02:05"), 2, "skipped", "late"),
            do(at("09:03:00"), 3, "task_complete"), ended(at("09:03:02"), 3, "cut", "tap"),
            do(at("09:04:00"), 4, "task_complete"), ended(at("09:04:01"), 4, "cut", "now"),
            do(at("09:59:59"), 5, "reply_ready"), ended(at("10:00:01"), 5, "skipped", "needs_you"),
            do(at("10:05:00"), 6, "reply_ready"),
            ended(at("10:06:00"), 99, "skipped", "busy"),
        )], "2026-09-28")
        self.assertEqual(d.total().finishes, 3)
        self.assertEqual((d.hours[9].finishes, d.hours[10].finishes), (2, 1), "a finish counts in the hour it was sent")

    def test_finishes_in_logs_from_before_do(self):
        """Older logs sent a `moment`: a finish is task_complete or
        reply_ready, and a cheer in logs from before them; a rule's
        rule reaction isn't one."""
        moment = lambda t, **m: {"sent": {"t": "moment", **m}, "received_at_ms": t}
        d = day.summarise([launch(
            state(at("09:00:00")),
            moment(at("09:01:00"), anim="task_complete", outcome="success", mood="calm", loops=1, id=1),
            moment(at("09:02:00"), anim="reply_ready", mood="curious", loops=1, id=2),
            moment(at("09:03:00"), anim="cheer", loops=1),
            moment(at("09:04:00"), anim="starting", variant=1, ctx="new_task"),
        )], "2026-09-28")
        self.assertEqual(d.total().finishes, 3)

    def test_a_alert_is_a_new_needs_you_or_a_different_one(self):
        """A new attn, or a different agent or project, alerts once; the
        keepalive's repeats and a changed `more` don't."""
        d = day.summarise([launch(
            state(at("09:00:00")),
            state(at("09:01:00"), ("claude", "a")),
            state(at("09:01:10"), ("claude", "a")),
            state(at("09:02:00"), ("claude", "a"), more=1),
            state(at("09:03:00"), ("codex", "b")),
            state(at("09:04:00")),
            state(at("09:10:00"), ("claude", "a")),
            state(at("09:12:00"), ("claude", "a")),
        )], "2026-09-28")
        self.assertEqual(d.total().alerts, 3)
        self.assertEqual([(n.end - n.start, n.alerts, n.open) for n in d.needs], [(180_000, 2, False), (120_000, 1, True)],
                         "one still up when its launch's log ends")
        self.assertIn("(still up when the log ends)", day.render(d))

    def test_a_different_request_with_the_same_names_alerts(self):
        """A different `attn.id` alerts even with the same agent and project
        (two worktrees of one repo); the same id again doesn't."""
        d = day.summarise([launch(
            state(at("09:00:00")),
            state(at("09:01:00"), ("claude", "a"), id=1),
            state(at("09:01:10"), ("claude", "a"), id=1),
            state(at("09:02:00"), ("claude", "a"), id=2),
            state(at("09:02:10"), ("claude", "a"), id=2, more=1),
            state(at("09:03:00")),
        )], "2026-09-28")
        self.assertEqual(d.total().alerts, 2)
        self.assertEqual([(n.who, n.alerts) for n in d.needs], [(["claude · a"], 2)])
        self.assertIn("  09:01  claude · a  2 min, 2 alerts", day.render(d).splitlines())

    def test_needs_you_across_midnight_counts_on_each_day(self):
        lines = launch(state(at("23:50:00", "2026-09-27"), ("claude", "a")), state(at("00:10:00")))
        before, after = (day.summarise([lines], d) for d in ("2026-09-27", "2026-09-28"))
        self.assertEqual((before.hours[23].needs_ms, after.hours[0].needs_ms), (600_000, 600_000))
        self.assertEqual((before.total().alerts, after.total().alerts), (1, 0))

    def test_dropped_passes_and_skipped_events(self):
        t = at("10:00:00")
        d = day.summarise([launch(
            state(t),
            event(t, 1, "turn start"),
            event(t + 10, 2, "tool end"),
            event(t + 20, 3, "turn end"),
            {"pass": {"brain": "jev:jev-latest", "for": 1, "dropped": "timed out after 8000 ms", "answers": {},
                      "latency_ms": 8000}, "received_at_ms": t + 8000},
            {"pass": {"brain": "jev:jev-latest", "for": 3, "dropped": None, "latency_ms": 900,
                      "answers": {"react": {"choice": "none", "p": {"none": 0.9}}}}, "received_at_ms": t + 9000},
        )], "2026-09-28")
        self.assertEqual((d.total().passes, d.total().dropped, d.quiet, d.skipped), (2, 1, 1, 1))
        text = day.render(d)
        self.assertIn("Brain: 2 passes (answered in a median 900 ms, the slowest 900 ms), 1 dropped, 1 chose no reaction; "
                      "none forced from the dashboard", text.splitlines())
        self.assertIn("  dropped 1×: timed out after 8000 ms", text)
        self.assertIn("  1 events woke it but got no pass", text)

    def test_held_passes_asked_no_brain(self):
        # An event held back when its turn came has a
        # pass that says why, and the brain wasn't asked: not a brain pass,
        # not dropped, and not an event that got no pass.
        t = at("10:00:00")
        d = day.summarise([launch(
            state(t),
            event(t, 1, "turn start"),
            {"pass": {"brain": "jev:jev-latest", "for": 1, "dropped": None, "held": "something needs you", "answers": {},
                      "latency_ms": 0}, "received_at_ms": t + 10},
        )], "2026-09-28")
        self.assertEqual((d.total().passes, d.total().dropped, d.skipped), (0, 0, 0))
        self.assertIn("  held back 1×, the brain not asked: something needs you", day.render(d))

    def test_an_hour_with_no_lines_is_one_boop_wasnt_logging(self):
        d = day.summarise([launch(state(at("09:00:00"))), launch(state(at("11:30:00")))], "2026-09-28")
        row = next(x for x in day.render(d).splitlines() if x.startswith("10"))
        self.assertIn("no log", row)


class CLITests(unittest.TestCase):
    def test_day_on_a_state_dir(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cli.main(["day", "--state-dir", str(FIXTURE)]), 0)
        self.assertTrue(out.getvalue().startswith("Boop's day: Monday 2026-09-28"))

    def test_a_day_with_nothing_logged(self):
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(cli.main(["day", "--date", "2026-9-27", str(FIXTURE / "debug.jsonl")]), 1)
        self.assertIn("Nothing in the debug logs on 2026-09-27: they run from 2026-09-28 01:35", out.getvalue())


if __name__ == "__main__":
    unittest.main()


class FaceKeyTests(unittest.TestCase):
    def test_either_key(self) -> None:  # react.mood, or react in older logs
        self.assertEqual(day.face({"answers": {"react.mood": {"choice": "proud"}}}), "proud")
        self.assertEqual(day.face({"answers": {"react": {"choice": "grumpy"}}}), "grumpy")
        self.assertIsNone(day.face({"answers": {}}))
