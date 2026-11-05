"""The dashboard: its feed against debug.jsonl files
recorded from real headless runs, Boop now (Talk, growth and CONTEXT), its
three columns (the mood and memory, the automatic reactions and the decided
ones, with their signs, asks and reasons) and the stale-log banner, restart
detection, the face's downsampling and
crop against every golden frame, the dev lines its keys build, and the app
itself through Textual's pilot. Needs no board, app or sim."""
import asyncio
import io
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from PIL import Image  # noqa: E402
from rich.console import Console  # noqa: E402

from boopctl_lib.common import REPO, send_line  # noqa: E402
from boopctl_lib.dash import controls  # noqa: E402
from boopctl_lib.dash.app import PREVIEW_RESEND_S, Dash, StateView  # noqa: E402
from boopctl_lib.dash.face import CROP, NATIVE_BLOCK, SCALE, blocks, native_rows, render  # noqa: E402
from boopctl_lib.dash import feed  # noqa: E402
from boopctl_lib.dash.feed import STALE_S, Board, Follower, clock, kind  # noqa: E402
from boopctl_lib.scenario import GOLDEN  # noqa: E402
from pack import needs_voice  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "headless-debug.jsonl"
COLUMNS = Path(__file__).parent / "fixtures" / "dash-columns.jsonl"
MEMORY = Path(__file__).parent / "fixtures" / "dash-memory.jsonl"
LANE_TOP = 192  # firmware/src/render/screens.h kLaneTop: the design is above it


def fixture_lines(path: Path = FIXTURE) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def dashboard_action(line: dict) -> dict:
    """An action's start, if the dashboard forced it."""
    a = feed.action(line["event"]) if "event" in line else None
    return a if a and a["by"] == "dashboard" else {}


def at_by_seq(lines: list[dict]) -> dict[int, int]:
    """Each line's time by its raw event's seq, or its view event's id
    (the converted fixtures keep the old seqs as both)."""
    out = {}
    for line in lines:
        if "event" in line:
            out[line["event"]["seq"]] = line["received_at_ms"]
        elif "view" in line:
            out[line["view"]["id"]] = line["received_at_ms"]
    return out


def board_after(lines: list[dict]) -> tuple[Board, list[tuple[str, str]]]:
    board = Board()
    rows = [row for row in map(board.apply, lines) if row]
    return board, rows


class WeekTests(unittest.TestCase):
    """`w`: what `Boop --counts` prints, whose text DailyCountsTests pins. A
    bad line in the file costs that line, in the app's own reading."""

    ROW = {"day": "2026-11-04", "touches": 5, "touchesNoWish": 2, "wishesMade": 1, "wishesMet": 1, "wishesGaveUp": 0,
           "wishWaitMs": 1_200_000, "threadsOpened": 3, "needsYou": 4, "answered": 2, "answerMs": 240_000, "spoken": 9,
           "hereMinutes": 180, "hushes": 1, "faceDown": 0, "unpluggedMinutes": 7, "disconnects": 2, "failures": 3,
           "quiet": False, "volume": 6, "stage": 2}

    @unittest.skipUnless(controls.BOOP.exists(), "needs Boop built (make -C internal app)")
    def test_a_week_from_the_app_with_bad_lines(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            old = {**self.ROW, "day": "2026-10-20", "touches": 100}
            rows = [old] + [{**self.ROW, "day": f"2026-11-0{i}"} for i in range(1, 8)]
            bad = ["not json", "5", "null", '{"day":"2026-11-08","touches":"lots"}', '{"touches":1}']
            (state / "daily-counts.jsonl").write_text("\n".join([json.dumps(r) for r in rows] + bad) + "\n")
            text = controls.week_text(state)
        self.assertNotIn("2026-10-20", text, "the last 7 days")
        self.assertIn("days touched: 7 of 7", text)
        self.assertIn("touches: 35, 14 with no wish open", text)
        self.assertIn("2026-11-07        5        2", text)

    def test_no_app_says_so(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            text = controls.week_text(Path(folder), boop=Path(folder) / "no-boop")
        self.assertIn("Can't read the daily counts", text)


class FeedTests(unittest.TestCase):
    """The fixture: a replay of the e2e Claude session into
    `Boop --headless --debug --brain scripted`, then the dashboard's dev
    lines and a few more hooks, rewritten into today's lines."""

    def test_the_fixture_has_every_kind_of_line(self):
        kinds = [kind(line) for line in fixture_lines()]
        self.assertEqual(kinds[0], "questions", "written first, once")
        self.assertEqual(kinds.count("questions"), 1)
        self.assertEqual(set(kinds), {"questions", "sent", "status", "view", "event", "pass"})

    def test_the_timeline(self):
        board, rows = board_after(fixture_lines())
        events = [text for style, text in rows if style == "event"]
        self.assertEqual([e.split(":")[0] for e in events][:5],
                         ["▸ 1 turn start", "▸ 4 tool wait (no pass)", "▸ 5 turn end", "▸ 8 turn start", "▸ 11 turn end"])
        self.assertIn(("ok", "  ✓ cheer (by rule): Boop cheered on its own."), rows, "a rule's action, under its view event")
        self.assertIn("failed (rate limit)", events[4])
        self.assertIn(("fail", "  ✗ react (by dashboard): something needs you"), rows)
        self.assertIn(("ok", "  ✓ mood (by dashboard): Boop's mood changed: happy → grumpy."), rows)
        self.assertIn(("pass", "  pass forced by dashboard: react.face grumpy · say retry"), rows)
        self.assertIn(("sent", "→ do wiggle"), rows)
        self.assertIn(("sent", "→ state idle grumpy · busy 0 · vol 6"), rows, "a state carries the mood")
        self.assertIn(("sent", "→ state idle happy · busy 0 · needs you: claude jetpack · vol 6"), rows)
        self.assertIn(("status", "status: sessions claude jetpack waiting"), rows, "a status row shows what changed")

    def test_the_state_joins_its_head(self):
        """A pass line carries HISTORY and NOW, and a `head` line before it
        the rest whenever that changes; an older log's passes carry the
        whole state."""
        board = Board()
        self.assertIsNone(board.apply({"head": "You are.\nMOOD\ncalm\n\n", "received_at_ms": 1}))
        board.apply({"pass": {"brain": "scripted", "answers": {}, "questions": [], "for": 1, "state": "HISTORY (oldest first)\nh\n\nNOW\nn"},
                     "received_at_ms": 2})
        self.assertEqual(board.jev_state, "You are.\nMOOD\ncalm\n\nHISTORY (oldest first)\nh\n\nNOW\nn")
        old, _ = board_after(fixture_lines())
        # The whole state: the guide, PERSONALITY and MOOD, then HISTORY and NOW.
        for part in ("PERSONALITY", "MOOD", "HISTORY", "NOW"):
            self.assertIn(part, old.jev_state)

    def test_keepalives_are_hidden(self):
        lines = fixture_lines()
        states = [line for line in lines if kind(line) == "sent" and line["sent"]["t"] == "state"]
        _, rows = board_after(lines)
        shown = [text for _, text in rows if text.startswith("→ state")]
        self.assertLess(len(shown), len(states), "the fixture has a state resent unchanged")
        for a, b in zip(shown, shown[1:]):
            self.assertNotEqual(a, b, "each shown state changed something")

    def test_the_facts(self):
        board, _ = board_after(fixture_lines())
        newest = board.newest_ms
        facts = dict(board.facts(newest + 10_000))
        self.assertEqual(facts["doing"], "idle")
        self.assertEqual(facts["mood"], "happy", "from the state line, never the transcript")
        self.assertEqual(facts["needs you"], "no")
        self.assertEqual(facts["sessions"], "0 working, 1 idle, 0 waiting", "from the status")
        self.assertEqual(facts["brain"], "scripted · 0 ms · dropped 0")
        self.assertEqual(facts["board"], "not connected (the sim shows what it would)")
        needs = next(i for i, line in enumerate(fixture_lines()) if line.get("view", {}).get("phase") == "wait")
        board, _ = board_after(fixture_lines()[: needs + 1])
        facts = dict(board.facts(board.newest_ms))
        self.assertEqual(facts["needs you"], "claude · jetpack")
        self.assertEqual(facts["doing"], "idle with the needs-you screen")
        self.assertEqual(facts["sessions"], "1 working, 0 idle, 0 waiting", "the status comes after the event")

    def test_the_counts_come_from_attn_and_the_sessions(self):
        board, _ = board_after([
            {"status": {"sessions": [{"agent": "claude", "project": "a", "status": "waiting"},
                                     {"agent": "codex", "project": "b", "status": "waiting"},
                                     {"agent": "claude", "project": "c", "status": "working"},
                                     {"agent": "claude", "project": "d", "status": "idle"},
                                     {"agent": "codex", "project": "e", "status": "idle"}]}, "received_at_ms": 1},
            {"sent": {"t": "state", "base": "working", "mood": "happy",
                      "attn": {"agent": "claude", "project": "a", "more": 1}, "busy": 1, "vol": 6}, "received_at_ms": 1},
        ])
        self.assertEqual(dict(board.facts(1))["sessions"], "1 working, 2 idle, 2 waiting")
        self.assertEqual(dict(board.facts(1))["needs you"], "claude · a (+1)")

    def test_a_started_action_and_its_end(self):
        """A started action is in progress until its end, an action event
        `for` its seq, says how it ended. The lines are the shapes
        HarnessTests pins."""
        board = Board()
        board.apply(next(line for line in fixture_lines() if kind(line) == "questions"))
        lines = [
            '{"pass":{"answers":{"react.face":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,'
            '"latency_ms":0,"questions":["react.face"]},"received_at_ms":1}',
            '{"event":{"seq":2,"at":2,"source":"self","kind":"did","data":{"action":"react","by":"dashboard","for":null,'
            '"latency_ms":0,"message":"Boop made a grumpy face and mumbled.","ok":true,"open":true}},"received_at_ms":2}',
        ]
        rows = [board.apply(json.loads(line)) for line in lines]
        self.assertEqual(rows[1], ("dim", "  … react (by dashboard): Boop made a grumpy face and mumbled."))
        self.assertEqual(board.decided_column()[-1], ("playing", "  ▶ playing"))
        self.assertEqual(dict(board.facts(2))["showing"], "a grumpy reaction face")
        row = board.apply(json.loads('{"event":{"seq":3,"at":3,"source":"self","kind":"ended","data":{"action":"react",'
                                     '"by":"dashboard","outcome":"failed","for":2,"why":"waited too long"}},'
                                     '"received_at_ms":3}'))
        self.assertEqual(row, ("fail", "  ✗ react (2) didn't happen: waited too long"))
        self.assertEqual(board.decided_column()[-1], ("fail", "  ✗ didn't happen: waited too long"))
        self.assertEqual(dict(board.facts(3))["showing"], "its ? look", "no state yet")
        row = board.apply(json.loads('{"event":{"seq":4,"at":4,"source":"self","kind":"ended","data":{"action":"react",'
                                     '"by":"brain","outcome":"done","for":2}},"received_at_ms":4}'))
        self.assertEqual(row, ("ok", "  ✓ react (2) done"))
        self.assertEqual(board.decided_column()[-1], ("ok", "  ✓ played"))


class ColumnsTests(unittest.TestCase):
    """The three columns, newest first, from
    `tests/fixtures/dash-columns.jsonl`. It was recorded from a real run
    (a headless app whose USB link is the native simulator, a forced mood, the e2e
    Claude session, a forced reaction that played, a forced pass that chose
    none, a cheer from the dashboard, and four taps on the sim's screen,
    then a poke streak), then edited, since the scripted brain answers
    everything at probability 1: the first pass's mood and the turn end's
    reaction, word and hold were given other probabilities, and the pass for
    the failed deploy was made a dropped one, its reaction's output, its `moment`
    and settle taken out. It was recorded before the raw transcript, and
    rewritten into today's lines, so its lines keep that run's words."""

    def setUp(self):
        self.board, _ = board_after(fixture_lines(COLUMNS))
        self.at = at_by_seq(fixture_lines(COLUMNS))

    def texts(self, rows):
        return [text for _, text in rows]

    def test_the_mood(self):
        """The mood now and since when, then each change with what made it:
        the event and the brain's probability for the new mood, or the
        dashboard, or the launch; and the pokes' pass sitting out, as that run's did."""
        mood = self.texts(self.board.mood_column())
        changes = [line for line in fixture_lines(COLUMNS) if line.get("sent", {}).get("t") == "state"]
        self.assertEqual(mood[0], f"happy since {clock(self.at[4])}", "the state sent with the mood output")
        poked = next(line for line in fixture_lines(COLUMNS) if line.get("pass", {}).get("for") == 31)
        self.assertEqual(mood[2], f"{clock(poked['received_at_ms'])} · mood sat out: You poked Boop 4 times in 3 s.")
        self.assertEqual(mood[3:6], [f"{clock(self.at[4])} grumpy → happy", '  ▸ claude started turn 1 on "jetpack".',
                                     "  scripted: happy 0.87"])
        self.assertEqual(mood[6:8], [f"{clock(self.at[1])} happy → grumpy", "  forced by dashboard"])
        self.assertEqual(mood[8:], [f"{clock(changes[0]['received_at_ms'])} happy", "  at launch"])

    def test_the_automatic_reactions(self):
        """Each reflex with what set it off: the cheer and its turn end, the
        needs you and the request, the taps' wiggles the board plays itself, the
        and a cheer the dashboard played, with no event."""
        rows = self.board.reflex_column()
        reflex = self.texts(rows)
        self.assertEqual(reflex[:2], [f"{clock(self.at[31])} Boop wiggled on its own.", "  ▸ You poked Boop 4 times in 3 s."])
        self.assertEqual(reflex.count("  ▸ You tapped Boop."), 3)
        cheers = [i for i, text in enumerate(reflex) if text.endswith(" cheer, loops 1")]
        self.assertEqual([reflex[i + 1] for i in cheers],
                         ["  no event: played from the dashboard",
                          '  ▸ claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. '
                          "Tests passing."])
        self.assertTrue(reflex[-3].endswith(" needs you cleared"))
        self.assertTrue(reflex[-2].endswith(" needs you: claude · jetpack"))
        self.assertEqual(reflex[-1], '  ▸ claude needs you on "jetpack".')
        self.assertEqual(rows[-2][0], "attn")

    def test_a_rules_action_with_no_board_is_named(self):
        """With no board nothing was sent ahead of a rule's `starting`, whose
        `did` has no message: the column names it rather than an empty row."""
        board = feed.Board()
        board.apply({"event": {"seq": 2, "at": 2, "source": "self", "kind": "did",
                               "data": {"action": "starting", "by": "rule", "for": 1, "ok": True}}, "received_at_ms": 2})
        self.assertEqual(board.reflexes[-1]["what"], "starting")

    def test_a_rules_reaction_and_the_activity(self):
        """A rule's reaction is named by the view event recorded right after
        it, never "played from the dashboard", and the working look shows
        its activity (`act`)."""
        t = 1_790_550_800_000
        state = {"t": "state", "base": "working", "act": "terminal", "mood": "calm", "busy": 1, "vol": 6}
        view = {"id": 9, "type": "turn", "from": [9], "line": 'claude started turn 2 on "jetpack".', "notes": [],
                "wakes_brain": True, "facts": {}, "phase": "start"}
        board, rows = board_after([
            {"sent": state, "received_at_ms": t},
            {"sent": {"t": "do", "name": "starting", "play": "if_free", "args": {"ctx": "new_task"}}, "by": "rule",
             "received_at_ms": t + 10},
            {"view": view, "received_at_ms": t + 20},
        ])
        reflex = self.texts(board.reflex_column())
        self.assertEqual(reflex, [f"{clock(t + 10)} starting (new_task)", '  ▸ claude started turn 2 on "jetpack".'])
        self.assertIn(("sent", "→ state working (terminal) calm · busy 1 · vol 6"), rows)
        self.assertEqual(dict(board.facts(t + 60_000))["showing"], "its terminal look")

    def test_what_the_mac_sends(self):
        """What the Mac sends since the device kept a queue: a rule's
        rule reaction is a reflex named by the view event right after it, as
        before; the Talk button's listening is one; the brain's finish
        isn't; and push-to-talk ending with no reply shows nothing, even as
        the first line."""
        t = 1_790_550_800_000
        view = {"id": 9, "type": "turn", "from": [9], "line": 'claude started turn 2 on "jetpack".', "notes": [],
                "wakes_brain": True, "facts": {}, "phase": "start"}
        sent = lambda at, by, msg: {"sent": msg, "by": by, "received_at_ms": at}  # noqa: E731
        board, rows = board_after([
            sent(t, "rule", {"t": "do", "id": 41, "name": "stop_listening", "play": "if_free"}),
            sent(t + 5, "rule", {"t": "state", "base": "working", "mood": "calm", "busy": 1, "vol": 6}),
            sent(t + 10, "rule", {"t": "do", "id": 42, "name": "starting", "play": "if_free",
                                  "args": {"variant": 3, "ctx": "new_task"}}),
            {"view": view, "received_at_ms": t + 20},
            sent(t + 30, "brain", {"t": "do", "id": 43, "name": "task_complete", "play": "next", "ttl": 5000,
                                   "args": {"outcome": "success", "variant": 2, "who": {"agent": "claude", "thread": "api"},
                                            "say": {"take": "new.d15"}, "mood": "proud"}}),
            sent(t + 40, "rule", {"t": "do", "id": 44, "name": "listening", "play": "now"}),
        ])
        reflex = self.texts(board.reflex_column())
        self.assertEqual(reflex, [f"{clock(t + 40)} listening", "  you pressed Talk on the Mac",
                                  f"{clock(t + 10)} starting (new_task)", '  ▸ claude started turn 2 on "jetpack".'])
        self.assertIn(("sent", "→ do stop_listening"), rows)
        self.assertIn(("sent", "→ do starting"), rows)
        self.assertIn(("sent", f"→ do task_complete + say {feed.say_text({'take': 'new.d15'})}"), rows)
        self.assertEqual(dict(board.facts(t + 1000))["showing"], "listening")

    def test_a_rule_reaction_the_device_skipped(self):
        """linkkit/SPEC.md §4: the device decides what plays, and says so
        (`ended`): a rule's reaction it skipped while a brain reaction played
        is marked on its reflex, and one it played isn't."""
        t = 1_790_550_800_000
        sent = lambda at, id, name: {"sent": {"t": "do", "id": id, "name": name, "play": "if_free"},  # noqa: E731
                                     "by": "rule", "received_at_ms": at}
        board, rows = board_after([
            sent(t, 51, "starting"),
            {"ended": {"id": 51, "how": "skipped", "why": "busy"}, "received_at_ms": t + 5},
            sent(t + 10, 52, "starting"),
            {"ended": {"id": 52, "how": "done"}, "received_at_ms": t + 900},
        ])
        self.assertIn(("fail", "  ⇠ do 51 skipped (busy)"), rows)
        self.assertIn(("dim", "  ⇠ do 52 done"), rows)
        reflex = board.reflex_column()
        self.assertEqual(reflex, [("ok", f"{clock(t + 10)} starting"), ("dim", f"{clock(t)} starting (skipped: busy)")])

    def test_a_held_pass_says_nothing_of_the_brains_latency(self):
        """A pass held back when its turn came never asked the brain:
        Boop now keeps the last real pass's time."""
        board, rows = board_after([
            {"pass": {"brain": "jev:jev-latest", "for": 1, "dropped": None, "latency_ms": 700, "answers": {},
                      "questions": []}, "received_at_ms": 1},
            {"pass": {"brain": "jev:jev-latest", "for": 2, "dropped": None, "held": "something needs you",
                      "latency_ms": 0, "answers": {}}, "received_at_ms": 2},
        ])
        self.assertEqual(dict(board.facts(2))["brain"], "? · 700 ms · dropped 0")
        self.assertEqual(rows[-1], ("dim", "  pass jev:jev-latest for 2: held: something needs you"))

    def test_who_sent_a_do(self):
        """A `sent` line's `by` says whose it is."""
        now = {"t": "do", "id": 3, "name": "task_complete", "play": "next", "args": {"mood": "proud"}}
        self.assertEqual(feed.sent_by({"sent": now, "by": "rule"}), "rule")
        self.assertEqual(feed.sent_by({"sent": now, "by": "brain"}), "brain")

    def test_takes_with_no_voice_pack(self):
        """With no voice file here, what a `say` said reads as its takes' ids."""
        with mock.patch.object(feed, "take", side_effect=feed.DeviceError("no voice file")):
            self.assertEqual(feed.said(["new.d15", "topic.x"]), "new.d15 topic.x")
            self.assertEqual(feed.say_text({"take": "new.d15", "then": "topic.x"}), "(new.d15, topic.x)")
            self.assertEqual(feed.say_text({}), "no take")

    @needs_voice
    def test_takes_with_the_voice_pack(self):
        """With the pack's voice, a `say` reads as its words, and a take it lacks as none."""
        self.assertEqual(feed.say_text({"take": "banana"}), "no take")
        self.assertTrue(feed.say_text({"take": "new.d15"}).endswith("” (new.d15)"))

    def test_the_decided_reactions(self):
        """Each pass that could react: its event, the face, move, intensity
        and what it says with their probabilities, and what became of it."""
        decided = self.texts(self.board.decided_column())
        blocks, block = [], []
        for text in decided:
            if not text.startswith("  ") and block:
                blocks.append(block)
                block = []
            block.append(text)
        blocks.append(block)
        blocks = [[text if text.startswith("  ") else text[9:] for text in b] for b in blocks]  # without the times
        self.assertEqual(blocks, [
            ["▸ You poked Boop 4 times in 3 s.", "  excited 1.00 · small 1.00 · glad 1.00", "  ✓ played",
             "  the mood sat this pass out"],
            ["forced by dashboard", "  stayed quiet · none 1.00"],
            ["forced by dashboard", "  proud 1.00 · big 1.00 · glad 1.00", "  ✓ played"],
            ['▸ claude finished turn 2 on "jetpack": failed (rate limit) after 41 s, a long turn, 1 tool (1 failed). '
             "Deploy failing.", "  excited 1.00 · small 1.00 · glad 1.00", "  ✓ played"],
            ['▸ claude\'s deploy failed on "jetpack".', "  ✗ pass dropped: late: no answer within 1500 ms"],
            ['▸ claude started turn 2 on "jetpack", right after its last one.', "  excited 1.00 · small 1.00 · glad 1.00",
             "  ✗ didn't happen: the device never said it ended"],
            ['▸ claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. Tests passing.',
             "  excited 0.82 · small 0.64 · glad 0.71", "  ✓ played"],
            ['▸ claude started turn 1 on "jetpack".', "  excited 1.00 · small 1.00 · glad 1.00", "  ✓ played"],
        ])
        self.assertEqual(self.board.dropped, 1)
        # A forced reaction refused while something needs you (the old fixture's).
        refused = [line for line in fixture_lines() if line.get("pass", {}).get("by") or dashboard_action(line)]
        board, _ = board_after(fixture_lines(COLUMNS) + refused[-2:])
        self.assertEqual(self.texts(board.decided_column())[1:3], ["  happy 1.00 · says nothing",
                                                                   "  ✗ didn't happen: something needs you"])

    @needs_voice
    def test_what_is_showing(self):
        """Boop now's `showing`: a reaction until its settle, a reflex for
        SHOWING_MS after it, else the look."""
        lines = fixture_lines(COLUMNS)
        forced = next(i for i, line in enumerate(lines) if dashboard_action(line).get("message", "").startswith(
            "Boop made a proud face"))
        board, _ = board_after(lines[: forced + 1])
        # What it said is the take its action recorded (new.d03), not the word it picked.
        self.assertEqual(dict(board.facts(board.newest_ms))["showing"], "a proud reaction face (big), “Done”")
        board = self.board
        self.assertEqual(dict(board.facts(self.at[31] + 1000))["showing"], "Boop wiggled on its own.")
        self.assertEqual(dict(board.facts(self.at[31] + 60_000))["showing"], "its idle look")

    def test_the_stale_log_banner(self):
        """A debug-mode app writes a `sent` line at least
        every 10 s, so a newest line older than 15 s means no live log, and
        the board's connection isn't shown as a fact."""
        self.assertEqual(STALE_S, 15)
        newest = self.board.newest_ms
        self.assertFalse(self.board.stale(newest + 15_000))
        self.assertTrue(self.board.stale(newest + 15_001))
        self.assertEqual(dict(self.board.facts(newest + 1000))["board"], "connected")
        self.assertEqual(dict(self.board.facts(newest + 16_000))["board"], "unknown: no live log")
        self.assertTrue(Board().stale(newest), "no lines at all")


class RestartTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.path = self.dir / "debug.jsonl"

    def tearDown(self):
        shutil.rmtree(self.dir)

    def write(self, text: str, mode: str = "a") -> None:
        with self.path.open(mode) as f:
            f.write(text)

    def test_following(self):
        follower = Follower(self.path)
        self.assertEqual(follower.read(), (False, []), "no file yet")
        self.write('{"questions":[]}\n{"seq":1,"event":{}}\n{"seq":2,"pa')
        self.assertEqual(follower.read(), (False, [{"questions": []}, {"seq": 1, "event": {}}]), "a partial line waits")
        self.write('ss":{}}\n')
        self.assertEqual(follower.read(), (False, [{"seq": 2, "pass": {}}]))
        self.assertEqual(follower.read(), (False, []))
        self.write('{"sent":{"t":"state"}}\n')
        self.assertEqual(follower.read(), (False, [{"sent": {"t": "state"}}]), "growing")

    def test_the_app_starting_again(self):
        """The app empties the file at each launch and writes
        its questions line, with that launch's time, first."""
        follower = Follower(self.path)
        self.write('{"questions":[],"received_at_ms":1}\n{"seq":1,"event":{}}\n{"seq":2,"pass":{}}\n')
        follower.read()
        for why, text in [
            ("shorter", '{"questions":[],"received_at_ms":2}\n'),
            ("longer, past where it had read", '{"questions":[],"received_at_ms":3}\n' + '{"sent":{"t":"state"}}\n' * 9),
            ("the same length", '{"questions":[],"received_at_ms":4}\n' + '{"sent":{"t":"state"}}\n' * 9),
        ]:
            with self.subTest(why):
                self.write(text, "w")
                self.assertEqual(follower.read(), (True, [json.loads(line) for line in text.splitlines()]))
        os.remove(self.path)
        self.assertEqual(follower.read(), (False, []), "gone: nothing to read yet")
        self.write('{"questions":[],"received_at_ms":5}\n', "w")
        self.assertEqual(follower.read(), (True, [{"questions": [], "received_at_ms": 5}]), "a new file")


def golden_shot(path: Path) -> tuple[list[int], bytes, tuple[int, int]]:
    """A golden PNG as a device screenshot: an RGB565 palette and indexes."""
    image = Image.open(path).convert("RGB")
    raw = image.tobytes()
    colours: dict[bytes, int] = {}
    indexes = bytes(colours.setdefault(raw[i : i + 3], len(colours)) for i in range(0, len(raw), 3))
    palette = [((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3) for r, g, b in colours] + [0] * (256 - len(colours))
    return palette, indexes, image.size


class FaceTests(unittest.TestCase):
    def test_the_sizes(self):
        self.assertEqual(SCALE, 3)
        shot = golden_shot(GOLDEN / "base" / "idle.png")
        crop = render(shot).plain.split("\n")
        self.assertEqual((len(crop[0]), len(crop)), (107, 32), "107×64 blocks, two per cell")

    def test_each_block_is_its_most_common_colour(self):
        # A 6×3 image: a block of five 1s and four 2s, then one of three
        # each of 0, 1 and 2 (the first counted wins a tie).
        pixels = bytes([1, 2, 1, 0, 1, 2,
                        2, 1, 2, 1, 2, 0,
                        1, 2, 1, 2, 0, 1])
        self.assertEqual(blocks(pixels, 6, (0, 0, 6, 3)), [[1, 0]])
        self.assertEqual(blocks(bytes(4), 2, (0, 0, 2, 2)), [[0]], "an edge block may be smaller")

    def test_a_native_face_draws_from_its_own_colours(self):
        """The gel draws natively and sends its panel in RGB565 with no
        palette: the face is sampled from it, above the lane, and a frame
        like that used to kill the face's thread, leaving it "starting"."""
        import struct
        w, h = 20, 20
        red, blue = 0xF800, 0x001F
        pixels = b"".join(struct.pack("<H", red if y < 8 else blue) for y in range(h) for _ in range(w))
        rows = native_rows(pixels, (w, h))
        self.assertEqual(len(rows[0]), w // NATIVE_BLOCK)
        self.assertEqual(len(rows), -(-int(h * 192 / 240) // NATIVE_BLOCK), "nothing below the lane")
        self.assertEqual(rows[0][0], red)
        self.assertEqual(rows[-1][0], blue)
        text = render((None, pixels, (w, h)))
        self.assertTrue(text.plain.startswith("▀"))

    def test_the_face_stays_in_the_crop(self):
        """Every golden frame's face (everything drawn above the bottom
        lane) is inside the crop, in pixels and in the downsampled blocks,
        so the crop loses none of it."""
        x0, y0, x1, y1 = CROP
        self.assertEqual(y1, LANE_TOP)
        frames = [p for p in sorted(GOLDEN.rglob("*.png")) if p.parent.name != "pattern"]
        self.assertTrue(frames, f"no golden frames in {GOLDEN}")
        for path in frames:
            with self.subTest(path.relative_to(GOLDEN)):
                palette, indexes, (w, h) = shot = golden_shot(path)
                background = indexes[0]
                outside = [(x, y) for y in range(LANE_TOP) for x in range(w)
                           if indexes[y * w + x] != background and not (x0 <= x < x1 and y0 <= y)]
                self.assertEqual(outside, [])
                grid = blocks(indexes, w, (0, 0, w, h))
                for by, row in enumerate(grid[: LANE_TOP // SCALE]):
                    for bx, index in enumerate(row):
                        inside = x0 <= bx * SCALE < x1 and y0 <= by * SCALE
                        self.assertTrue(inside or index == background, (bx, by))
                render(shot)


QUESTIONS = next(line["questions"] for line in fixture_lines() if "questions" in line)


class ControlsTests(unittest.TestCase):
    def test_the_pickers_come_from_the_questions_line(self):
        self.assertEqual(controls.options(controls.asked_by(QUESTIONS, "mood")[0]),
                         ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad"])
        react = controls.asked_by(QUESTIONS, "react")
        self.assertEqual([q["key"] for q in react], ["react.face", "react.move", "react.intensity", "say"])
        self.assertEqual(controls.options(react[0])[0], "none")

    def test_preview_lines(self):
        latest = {"t": "state", "base": "working", "attn": {"agent": "codex", "project": "x", "more": 0},
                  "busy": 1, "vol": 3}
        self.assertEqual(controls.preview_state(latest, "asleep"),
                         {"t": "state", "base": "asleep", "busy": 1, "vol": 3})
        self.assertEqual(controls.preview_state(latest, "idle", "sad")["mood"], "sad")
        needs = controls.preview_state(None, "needs you")
        self.assertEqual((needs["base"], needs["attn"]["agent"]), ("idle", "claude"))
        self.assertEqual(latest["base"], "working", "the app's state is left alone")

    def test_a_preview_reaction_says_its_take(self):
        """As the react output sends it, played `now` so
        it replaces what the sim shows; what react.move picks is its
        scene, with a finish's outcome (MomentOutput.scenes)."""
        line = controls.preview_reaction("grumpy", "new.d14", 3)
        self.assertEqual(line, {"t": "do", "name": "react", "play": "now",
                                "args": {"mood": "grumpy", "loops": 3, "say": {"take": "new.d14"}}})
        face = controls.preview_reaction("proud", None, 1, "success")
        self.assertEqual((face["name"], face["args"]["outcome"]), ("task_complete", "success"))
        woke = controls.preview_reaction("happy", None, 1, "wake up")
        self.assertEqual((woke["name"], "outcome" in woke["args"]), ("wake_up", False))
        self.assertEqual(face["args"]["say"], {}, "saying nothing still sends a say, as react does")
        self.assertEqual(controls.preview_reaction("sad", None, 1, "failure")["args"]["outcome"], "failure")
        reply = controls.preview_reaction("curious", None, 2, "reply")
        self.assertEqual((reply["name"], "outcome" in reply["args"]), ("reply_ready", False))
        self.assertEqual(controls.preview_reaction("happy", None, 1, "notice")["name"], "notice")

    def test_confirmations(self):
        pending = controls.Pending()
        pending.add({"dev": "mood", "mood": "grumpy"}, now=0)
        pending.add({"dev": "answer", "answers": {"react.face": "happy"}}, now=0)
        lines = fixture_lines()
        first = next(i for i, line in enumerate(lines) if dashboard_action(line))
        seen = [pending.seen(line) for line in lines[first:]]
        self.assertEqual([s for s in seen if s], ["mood", "answer"], "in the order they landed")
        pending.add({"dev": "mood", "mood": "grumpy"}, now=0)
        self.assertEqual(pending.late(now=1.9), [])
        self.assertEqual(pending.late(now=2.0), ["mood"], "nothing within 2 s")
        self.assertEqual(pending.waiting, [])

    def test_send(self):
        with Socket() as server:
            self.assertIsNone(send_line(server.path, {"dev": "mood", "mood": "grumpy"}))
            self.assertEqual(server.wait(1), [{"dev": "mood", "mood": "grumpy"}])
        self.assertIn("can't reach Boop's socket", send_line(server.path, {"dev": "mood", "mood": "grumpy"}))


class MemoryTests(unittest.TestCase):
    """What's new since dreaming and simplify, from
    `tests/fixtures/dash-memory.jsonl`, recorded unedited from a real run:
    `Boop --headless --debug --brain scripted` whose USB link is the native
    simulator (`program --live` behind linkkit-bridge), a Claude session
    through agent-hook (a prompt, a test run, a finish), a forced pass
    holding up the sign "please <3" at the prompt, a second turn, a forced
    pass asking "did it work?" and a touch on the sim's lane answering no,
    `{"dev":"close_day"}` (now `dream_now`), a tap that told the dream, and the night's write
    by Apple Intelligence on the Mac it ran on, which refused all four of
    its edits."""

    def setUp(self):
        self.board, self.rows = board_after(fixture_lines(MEMORY))

    def texts(self, rows):
        return [text for _, text in rows]

    def test_boop_now(self):
        """Talk from CONTEXT (normal: no Talk row), growth from the status
        line (the stage, the XP, today's from each pool against its cap),
        and CONTEXT as the last pass's prompt had it."""
        facts = dict(self.board.facts(self.board.newest_ms))
        self.assertEqual(facts["talk"], "normal")
        self.assertEqual(facts["growth"], "stage 1 · 16 XP · today: work 0/60, care 0/60",
                         "the day closed, so today's pools start again")
        self.assertEqual(facts["why"], "nothing has moved it yet", "the mood never moved")
        self.assertEqual(facts["CONTEXT"].splitlines()[1:], ["Pip: a Hatchling, hatched today.",
                                                             'Agents: claude idle on "jetpack" for 1 min.',
                                                             "Today: you touched Pip once."])
        self.assertRegex(facts["CONTEXT"], r"^When: \d\d:\d\d, Sunday, day\.")
        today = [line["status"]["today_xp"] for line in fixture_lines(MEMORY) if "status" in line]
        self.assertEqual(max(t["work"] for t in today), 11, "a tool call 1 and each turn done 5, before the close")
        self.assertEqual(max(t["care"] for t in today), 5, "the answered ask")
        self.assertNotIn("status: ", [text for _, text in self.rows], "a status where only XP moved has no row")

    def test_talk_and_growth_from_their_rows(self):
        """CONTEXT's Talk row, and a status line's XP; before any pass, and
        an older log's status with no XP."""
        talk = feed.talk_level
        self.assertEqual(talk(None), "no pass yet")
        self.assertEqual(talk(["When: 09:02, Saturday, morning."]), "normal")
        self.assertEqual(talk(["Talk: chatty. You asked Pip to say something at every face."]), "chatty")
        self.assertEqual(talk(["Talk: quiet. You asked Pip to say less."]), "quiet")
        self.assertEqual(talk(["Talk: silent for 4 more min, then quiet again: Pip says nothing till then."]),
                         "silent for 4 more min, then quiet again")
        self.assertEqual(feed.context_rows("You are.\n\nCONTEXT (how things stand. x)\nWhen: 9.\nTalk: quiet.\n\n"
                                           "HISTORY (oldest first)\nh"), ["When: 9.", "Talk: quiet."])
        self.assertIsNone(feed.context_rows("You are.\nMOOD\ncalm"), "an older log's prompt")
        self.assertEqual(feed.growth_text({"stage": 2}), "stage 2")
        self.assertEqual(feed.growth_text({"stage": 3, "xp": 1234, "today_xp": {"work": 60, "work_cap": 60,
                                                                                "care": 9, "care_cap": 60}}),
                         "stage 3 · 1234 XP · today: work 60/60, care 9/60")
        board = Board()
        board.apply({"status": {"brain": "jev", "mood_reason": "Pip is lonely. You came back after a day away."},
                     "received_at_ms": 1})
        self.assertEqual(dict(board.facts(1))["why"], "Pip is lonely. You came back after a day away.")

    def test_the_decided_signs_asks_and_reasons(self):
        """A sign as the device got it, an ask with its two answers and the
        one picked, and each reaction's reason."""
        decided = self.texts(self.board.decided_column())
        sign = decided.index("  sign: “please <3”")
        self.assertEqual(decided[sign - 2:sign], [decided[sign - 2], "  happy 1.00 · small 1.00 · says nothing"])
        self.assertTrue(decided[sign - 2].endswith("forced by dashboard"))
        self.assertEqual(decided[sign + 1:sign + 3],
                         ["  ✓ played", '  why: Pip is happy. You asked claude on "jetpack" in a sentence, politely.'])
        ask = decided.index("  asks “did it work?”: yes or no")
        self.assertEqual(decided[ask + 1], "  you picked no (b)")
        reasons = [r["react"]["reason"] for r in self.board.decided if r["react"]]
        self.assertEqual([text[len("  why: "):] for text in decided if text.startswith("  why: ")], reasons[::-1],
                         "every reaction's, newest first")

    def test_an_ask_nobody_or_a_touch_answered(self):
        board = Board()
        lines = [{"pass": {"answers": {"react.face": {"choice": "curious", "p": {"curious": 1}}}, "by": "dashboard",
                           "for": None, "questions": ["react.face", "react.sign"]}, "received_at_ms": 1},
                 {"sent": {"t": "do", "id": 9, "name": "react", "play": "next",
                           "args": {"sign": "pet me?", "ask": {"q": "pet", "a": "ok", "b": "later", "touch": True}}},
                  "by": "brain", "received_at_ms": 1},
                 {"event": {"seq": 2, "at": 2, "source": "self", "kind": "did",
                            "data": {"action": "react", "by": "dashboard", "for": None, "ok": True, "open": True,
                                     "ask": "pet", "question": "pet me?", "answers": ["ok", "later"]}},
                  "received_at_ms": 2}]
        for line in lines:
            board.apply(line)
        self.assertEqual(self.texts(board.decided_column())[3], "  … no answer yet")
        nobody = {"event": {"seq": 3, "at": 3, "source": "device", "kind": "ask",
                            "data": {"q": "pet", "specific_type": "ignored", "question": "pet me?"}}, "received_at_ms": 3}
        self.assertIsNone(board.apply(nobody), "its view event says it in the timeline")
        self.assertEqual(self.texts(board.decided_column())[3], "  nobody answered")
        board.decided[-1]["answered"] = None
        board.apply({"event": {**nobody["event"], "data": {"q": "pet", "specific_type": "touch", "answer": "ok"}},
                     "received_at_ms": 4})
        self.assertEqual(self.texts(board.decided_column())[3], "  a touch answered ok (touch)")
        self.assertNotIn("  sign: “pet me?”", self.texts(board.decided_column()), "an ask's sign is its question")

    def test_memory_in_the_mood_column(self):
        """A dream and the line that told it, and the dream's write,
        changed and refused, newest first."""
        mood = self.texts(self.board.mood_column())
        night = next(i for i, text in enumerate(mood) if "☾ the dream's write for 2026-11-01" in text)
        self.assertTrue(mood[night].endswith(": 0 changed, 4 refused"))
        self.assertEqual(mood[night + 1], "  Recently's line: the dream's sentence, as the writer's didn't pass")
        self.assertEqual([t.split(")")[0] for t in mood[night + 2:night + 6]],
                         ["  ✗ refused (ungrounded", "  ✗ refused (form", "  ✗ refused (form", "  ✗ refused (ungrounded"])
        self.assertTrue(all(len(t) <= feed.REFUSED_CHARS + 20 for t in mood[night + 2:night + 6]), "a long line is cut")
        dream = night + 6
        self.assertTrue(mood[dream].endswith("☾ dreamed about Sunday (2026-11-01)"))
        self.assertEqual(mood[dream + 1], '  dream: you poked it once; 2 turns on "jetpack" [answered, clean]')
        self.assertRegex(mood[dream + 2], r"^  told at \d\d:\d\d:\d\d: ▸ You poked Pip again\.$")
        self.assertIn(("mood", '☾ dreamed about Sunday (2026-11-01): you poked it once; 2 turns on "jetpack"'),
                      self.rows)
        self.assertIn(("mood", "☾ the dream's write: 0 changed, 4 refused"), self.rows)
        untold = Board()
        for line in fixture_lines(MEMORY):
            if line.get("view", {}).get("facts", {}).get("dream_day"):
                break
            untold.apply(line)
        self.assertIn("  not told yet: at your next coming back or touch", self.texts(untold.mood_column()))

    def test_the_night_in_counts(self):
        self.assertEqual(feed.night_text({"added": ["m1"], "updated": ["m2", "m3"], "aged": ["m4"], "refused": []}),
                         "4 changed (1 added, 2 updated, 1 aged), 0 refused")

    def test_the_pack_s_lasting_moods(self):
        """`m` offers the lasting moods: those with a `meaning`, 16 in
        Boop's pack of 42 faces."""
        from boopctl_lib.common import MOODS, REPO, lasting_moods
        boop = lasting_moods(REPO / "characters" / "boop")
        self.assertEqual(len(boop), 16)
        self.assertIn("lonely", boop)
        self.assertNotIn("crying", boop, "a face only, which settles into sad")
        self.assertEqual(len(MOODS), 42, "Preview keeps every face")

    def test_dreaming_now_lands_with_its_dream(self):
        pending = controls.Pending()
        pending.add({"dev": "dream_now"}, now=0)
        self.assertEqual([x for x in map(pending.seen, fixture_lines(MEMORY)) if x], ["dream_now"])
        self.assertIn("nothing new since the last dream", controls.late_text("dream_now"))

    def test_a_dreams_preview_reads_as_words(self):
        pending = controls.Pending()
        pending.add({"dev": "dream_preview"}, now=0)
        line = {"dream_preview": {"dream": {"about": "Thursday to Saturday", "range": "Thursday 2026-10-29 to Saturday 2026-10-31",
                                            "tags": ["fond"], "sentence": "you stroked it 3 times", "fact": "stroked x3"},
                                  "edits": {"kept": [], "updated": [], "added": ["m1"], "dropped": [], "aged": [],
                                            "refused": [{"line": "add you: x", "why": "ungrounded"}]},
                                  "before": "# Boop's memory\n", "after": "# Boop's memory\n- You stroke Boop.\n"},
                "received_at_ms": 1}
        self.assertEqual(pending.seen(line), "dream_preview")
        text = controls.preview_text(line["dream_preview"])
        self.assertIn("Nothing was kept", text)
        self.assertIn("you stroked it 3 times", text)
        self.assertIn("added: m1", text)
        self.assertIn("add you: x  (ungrounded)", text)
        self.assertIn("+- You stroke Boop.", text)
        self.assertIn("the dream alone", controls.preview_text({"dream": line["dream_preview"]["dream"], "edits": None}))
        self.assertIn("Nothing new", controls.preview_text({"dream": None}))
        self.assertIn("Is Boop running with --debug?", controls.late_text("mood"))


class Socket:
    """A Unix socket that collects the JSON lines written to it, as the
    app's hook socket would."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(dir="/tmp")
        self.path = os.path.join(self.dir, "s.sock")
        self.got: list[dict] = []
        self.lock = threading.Lock()

    def __enter__(self) -> "Socket":
        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.path)
        self.server.listen()
        threading.Thread(target=self._serve, daemon=True).start()
        return self

    def _serve(self) -> None:
        while True:
            try:
                conn, _ = self.server.accept()
            except OSError:
                return
            with conn:
                data = b""
                while chunk := conn.recv(4096):
                    data += chunk
            with self.lock:
                self.got += [json.loads(line) for line in data.splitlines() if line]

    def wait(self, n: int, timeout: float = 2) -> list[dict]:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            with self.lock:
                if len(self.got) >= n:
                    return list(self.got)
            time.sleep(0.01)
        with self.lock:
            return list(self.got)

    def __exit__(self, *_: object) -> None:
        self.server.close()
        shutil.rmtree(self.dir)


class FakeFace:
    def __init__(self) -> None:
        self.sent: list[dict] = []
        self.restarts: list[dict | None] = []
        self.running = False

    def start(self) -> None:
        self.running = True

    def stop(self) -> None:
        self.running = False

    def send(self, message: dict) -> None:
        self.sent.append(message)

    def restart(self, state: dict | None) -> None:
        self.restarts.append(state)


def plain(widget) -> str:
    """A Static's content as the terminal shows it, without colour."""
    console = Console(width=200, record=True, file=io.StringIO())
    console.print(widget.content)
    return console.export_text()


class AppTests(unittest.TestCase):
    """The app through Textual's pilot: its panes from the fixture, and every
    key."""

    @needs_voice
    def test_the_panes_and_keys(self):
        with mock.patch.object(controls, "CONFIRM_S", 60):  # the pilot's pauses add up
            asyncio.run(self.drive())

    async def drive(self) -> None:
        state_dir = Path(tempfile.mkdtemp())
        log = state_dir / "debug.jsonl"
        shutil.copy(FIXTURE, log)
        face = FakeFace()
        with Socket() as server:
            app = Dash(log, server.path, make_face=lambda on_frame, on_error: face)
            async with app.run_test(size=(170, 60)) as pilot:
                await pilot.pause()
                self.assertTrue(face.running)
                latest = next(line["sent"] for line in reversed(fixture_lines()) if line.get("sent", {}).get("t") == "state")
                self.assertEqual(face.restarts, [latest], "the sim starts on the latest state, and no old reactions")
                self.assertEqual(face.sent, [])
                self.assertRegex(plain(app.query_one("#facts")), r"mood +happy")
                # The fixture is days old: no live log, so the board's link isn't a fact.
                self.assertTrue(app.query_one("#stale").has_class("shown"))
                self.assertRegex(plain(app.query_one("#stale")), r"No live log: the newest line is from .*make dev")
                self.assertRegex(plain(app.query_one("#facts")), r"board +unknown: no live log")
                app.now = lambda: app.board.newest_ms / 1000 + 5
                app.poll()
                self.assertFalse(app.query_one("#stale").has_class("shown"))
                self.assertRegex(plain(app.query_one("#facts")), r"board +not connected")
                self.assertIn("happy since", plain(app.query_one("#mood")))
                self.assertIn("cheer", plain(app.query_one("#reflexes")))
                self.assertIn("excited 1.00 · small 1.00 · glad 1.00", plain(app.query_one("#decided")))
                self.assertEqual(app.query_one("#timeline").size.height, 0, "the timeline waits for t")
                await pilot.press("t")
                await pilot.pause()
                self.assertGreater(app.query_one("#timeline").size.height, 5)
                self.assertGreater(len(app.query_one("#timeline").lines), 40)
                await pilot.press("t")
                await pilot.pause()
                self.assertEqual(app.query_one("#timeline").size.height, 0)

                async def pick(key: str, *downs: int) -> None:
                    await pilot.press(key)
                    for down in downs:
                        await pilot.pause()
                        await pilot.press(*["down"] * down, "enter")
                    await pilot.pause()

                from boopctl_lib.common import MOODS, lasting_moods
                await pilot.press("m")
                await pilot.pause()
                self.assertEqual(app.screen.choices, lasting_moods(), "the pack's lasting moods")
                await pilot.press("escape")
                await pick("m", lasting_moods().index("grumpy"))
                await pick("r", 6, 0, 1, 8)  # grumpy, no move, medium, retry
                got = server.wait(2)
                self.assertEqual(got, [{"dev": "mood", "mood": "grumpy"},
                                       {"dev": "answer", "answers": {"react.face": "grumpy", "react.move": "none",
                                                                     "react.intensity": "medium", "say": "retry"}}])
                self.assertEqual(len(app.pending.waiting), 2)
                with log.open("a") as f:
                    f.write('{"event":{"seq":28,"at":1790498700000,"source":"self","kind":"did","data":{"action":"mood",'
                            '"by":"dashboard","for":null,"latency_ms":0,"message":"already grumpy","ok":false}},'
                            '"received_at_ms":1790498700000}\n')
                    f.write('{"sent":{"t":"do","id":5,"name":"starting","play":"if_free"},"by":"rule",'
                            '"received_at_ms":1790498700001}\n')
                app.poll()
                self.assertEqual([name for _, name, _ in app.pending.waiting], ["answer"])
                self.assertEqual(face.sent, [{"t": "do", "id": 5, "name": "starting", "play": "if_free"}],
                                 "live lines reach the sim as sent")

                # Preview: the dashboard's own lines, to its sim only.
                await pick("p", 1)
                self.assertEqual(face.sent[-1]["base"], "working")
                self.assertIn("PREVIEW: working", app.query_one("#face").border_title)
                await pilot.press("m")
                await pilot.pause()
                self.assertEqual(app.screen.choices, list(MOODS), "Preview offers every face")
                await pilot.press("escape")
                await pick("m", MOODS.index("sad"))  # the mood's faces, on the sim only
                self.assertEqual((face.sent[-1]["base"], face.sent[-1]["mood"]), ("working", "sad"))
                self.assertEqual(len(server.wait(3, timeout=0.3)), 2, "nothing went to the app")
                with log.open("a") as f:
                    f.write('{"sent":{"t":"do","id":6,"name":"starting","play":"if_free"},"by":"rule",'
                            '"received_at_ms":1790498700002}\n')
                app.poll()
                self.assertEqual(face.sent[-1]["mood"], "sad", "the app's lines wait")
                await pick("r", 5, 0, 2, 0)  # grumpy's face, no move, big, saying nothing: a `react` with its `mood`
                for _ in range(100):
                    if face.sent[-1]["t"] == "do":
                        break
                    await pilot.pause(0.05)
                self.assertEqual((face.sent[-1]["name"], face.sent[-1]["args"]["mood"]), ("react", "grumpy"))
                self.assertEqual(face.sent[-1]["args"]["loops"], 3, "big holds three times")
                self.assertEqual(face.sent[-1]["args"]["say"], {}, "saying nothing, as react sends it")
                # Resent well inside the device's 30 s no-app timeout.
                self.assertEqual(PREVIEW_RESEND_S, 10)
                app.keep_preview()
                self.assertEqual(face.sent[-1]["base"], "working")
                await pick("p", len(controls.LOOKS))
                self.assertEqual(face.restarts[-1], latest, "leaving Preview replays the latest state")
                self.assertIn("live", app.query_one("#face").border_title)

                # `d` dreams now: landed with the dream, in the mood column.
                await pick("d")
                self.assertEqual(server.wait(3)[-1], {"dev": "dream_now"})
                with log.open("a") as f:
                    f.write('{"event":{"seq":29,"at":1790498700003,"source":"boop","kind":"dream","data":{"day":"2026-09-27",'
                            '"weekday":"Sunday","sentence":"a quiet day","tags":["quiet"],"fact":"quiet day",'
                            '"specific_type":"dream"}},"received_at_ms":1790498700003}\n')
                app.poll()
                self.assertNotIn("dream_now", [name for _, name, _ in app.pending.waiting])
                self.assertIn("☾ dreamed about Sunday (2026-09-27)", plain(app.query_one("#mood")))

                # This week's counts, from `Boop --counts` on the folder of the log.
                self.assertEqual({b.key: b.description for b in Dash.BINDINGS}["w"], "week")
                await pilot.press("w")
                await pilot.pause()
                self.assertIsInstance(app.screen, StateView)
                self.assertRegex(app.screen.state, "days touched: 0 of 0|Can't read the daily counts")
                await pilot.press("w")
                await pilot.pause()
                self.assertNotIsInstance(app.screen, StateView)

                self.assertEqual({b.key: b.description for b in Dash.BINDINGS}["s"], "prompt")
                await pilot.press("s")
                await pilot.pause()
                self.assertIsInstance(app.screen, StateView)
                await pilot.press("escape")
                await pilot.pause()
                self.assertNotIsInstance(app.screen, StateView)

                # The app starts again: the file is emptied in place.
                log.write_text('{"questions":[],"received_at_ms":2}\n'
                               '{"sent":{"t":"state","base":"idle","busy":0,"vol":6},'
                               '"received_at_ms":2}\n'
                               '{"sent":{"t":"do","id":7,"name":"starting","play":"if_free"},"by":"rule",'
                               '"received_at_ms":3}\n')
                sent_before = len(face.sent)
                app.poll()
                self.assertEqual(face.restarts[-1]["base"], "idle", "the new app's latest state")
                self.assertEqual(len(face.sent), sent_before, "and none of its reactions")
                self.assertIn("Boop restarted", " ".join(strip.text for strip in app.query_one("#timeline").lines))
                await pilot.press("q")
            self.assertFalse(face.running)
        shutil.rmtree(state_dir)


if __name__ == "__main__":
    unittest.main()


class ReactionKeysTests(unittest.TestCase):
    """A reaction is `react.face`, `react.move`, `react.intensity` and
    `say`."""

    @needs_voice
    def test_the_face_and_its_move(self) -> None:
        from boopctl_lib.dash.feed import picks_text, reaction_text
        a = lambda c, p=1.0: {"choice": c, "p": {c: p}}  # noqa: E731
        now = {"answers": {"react.face": a("proud", 0.82), "react.move": a("success", 0.9),
                           "react.intensity": a("big", 0.64), "say": a("glad", 0.71)},
               "questions": ["react.face", "react.move", "react.intensity", "say"]}
        self.assertEqual(picks_text(now), "proud 0.82 · success 0.90 · big 0.64 · glad 0.71")
        self.assertEqual(reaction_text({"pass": now}), "a success in a proud face (big)", "no takes recorded")
        self.assertEqual(reaction_text({"pass": now}, ["new.d03", "gone"]),
                         "a success in a proud face (big), “Done gone”", "a take the pack lacks, by its id")
        quiet = {"answers": {"react.face": a("calm"), "react.move": a("none"), "react.intensity": a("small"),
                             "say": a("none")}, "questions": ["react.face", "react.move", "react.intensity", "say"]}
        self.assertEqual(picks_text(quiet), "calm 1.00 · small 1.00 · says nothing")
        talk = {"answers": {"react.face": a("happy"), "react.move": a("hello", 0.8), "react.intensity": a("small"),
                            "say": a("none")}, "questions": ["react.face", "react.move", "react.intensity", "say"]}
        self.assertEqual(reaction_text({"pass": talk}), "a happy reaction face (small), replying hello",
                         "to what you said, the move is the reply")
        shrug = {"answers": {**talk["answers"], "react.move": a("huh")}, "questions": talk["questions"]}
        self.assertEqual(reaction_text({"pass": shrug, "react": {"reply": "dunno"}}),
                         "a happy reaction face (small), replying dunno", "the reply as it played, a huh at a question")
