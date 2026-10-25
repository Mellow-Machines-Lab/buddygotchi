"""The dashboard: its feed against debug.jsonl files
recorded from real headless runs, its three columns (the mood, the
automatic reactions and the decided ones) and the stale-log banner, restart
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
from boopctl_lib.dash.face import CROP, SCALE, blocks, render  # noqa: E402
from boopctl_lib.dash import feed  # noqa: E402
from boopctl_lib.dash.feed import STALE_S, Board, Follower, clock, kind  # noqa: E402
from boopctl_lib.scenario import GOLDEN  # noqa: E402
from old_logs import as_do, with_old_keys  # noqa: E402
from pack import needs_voice  # noqa: E402

FIXTURE = Path(__file__).parent / "fixtures" / "headless-debug.jsonl"
COLUMNS = Path(__file__).parent / "fixtures" / "dash-columns.jsonl"
LANE_TOP = 192  # firmware/src/render/screens.h kLaneTop: the design is above it


def fixture_lines(path: Path = FIXTURE) -> list[dict]:
    return [json.loads(line) for line in path.read_text().splitlines()]


def dashboard_action(line: dict) -> dict:
    """An action's start, if the dashboard forced it: the fixture is a
    launch from before MellowHarness, so it also checks that older logs'
    actions still read."""
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
        self.assertIn(("sent", "→ moment wiggle"), rows)
        self.assertIn(("sent", "→ state idle grumpy · busy 0 · vol 6"), rows, "a state carries the mood")
        self.assertIn(("sent", "→ state idle happy · busy 0 · needs you: claude jetpack · vol 6"), rows)
        self.assertIn(("status", "status: sessions claude jetpack waiting"), rows, "a status row shows what changed")

    def test_the_timeline_of_do_lines(self):
        """The Mac sends a `do` where it sent a `moment` (old_logs.as_do):
        the timeline names it, and every other row is the same."""
        _, old = board_after(fixture_lines())
        _, now = board_after([as_do(line) for line in fixture_lines()])
        self.assertIn(("sent", "→ do wiggle"), now)
        self.assertIn(("sent", "→ do react + say no take"), now, "an old log's line, which had no take")
        self.assertEqual([row for row in now if not row[1].startswith("→ do")],
                         [row for row in old if not row[1].startswith("→ moment")])

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
        self.assertEqual(facts["look"], "idle")
        self.assertEqual(facts["mood"], "happy", "from the state line, never the transcript")
        self.assertEqual(facts["needs you"], "no")
        self.assertEqual(facts["sessions"], "0 working, 1 idle, 0 waiting", "from the status")
        self.assertEqual(facts["brain"], "scripted · 0 ms · dropped 0")
        self.assertEqual(facts["board"], "not connected (the sim shows what it would)")
        needs = next(i for i, line in enumerate(fixture_lines()) if line.get("view", {}).get("phase") == "wait")
        board, _ = board_after(fixture_lines()[: needs + 1])
        facts = dict(board.facts(board.newest_ms))
        self.assertEqual(facts["needs you"], "claude · jetpack")
        self.assertEqual(facts["look"], "idle with the needs-you strip")
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
            '{"pass":{"answers":{"react":{"choice":"grumpy","p":{"grumpy":1}}},"by":"dashboard","dropped":null,"for":null,'
            '"latency_ms":0,"questions":["react"]},"received_at_ms":1}',
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
        working chatter, and a cheer the dashboard played, with no event."""
        rows = self.board.reflex_column()
        reflex = self.texts(rows)
        self.assertEqual(reflex[:2], [f"{clock(self.at[31])} Boop wiggled on its own.", "  ▸ You poked Boop 4 times in 3 s."])
        self.assertEqual(reflex.count("  ▸ You tapped Boop."), 3)
        cheers = [i for i, text in enumerate(reflex) if text.endswith(" cheer, loops 1")]
        self.assertEqual([reflex[i + 1] for i in cheers],
                         ["  no event: played from the dashboard",
                          '  ▸ claude finished turn 1 on "jetpack": done after 6 min, a very long turn, 3 tools. '
                          "Tests passing."])
        chatter = next(line["sent"]["say"] for line in fixture_lines(COLUMNS)
                       if line.get("sent", {}).get("say") and not line["sent"].get("mood"))
        at = reflex.index(next(t for t in reflex if t.endswith(f"working chatter {feed.say_text(chatter)}")))
        self.assertEqual(reflex[at + 1], "  an agent is working")
        self.assertTrue(reflex[-3].endswith(" needs you cleared"))
        self.assertTrue(reflex[-2].endswith(" needs you: claude · jetpack · alert"))
        self.assertEqual(reflex[-1], '  ▸ claude needs you on "jetpack".')
        self.assertEqual(rows[-2][0], "attn")

    def test_a_rules_reaction_and_the_activity(self):
        """A rule's reaction, in an older log's `moment` (test_what_the_mac_sends
        has today's `do`), is named by the view event recorded right after
        it, never "played from the dashboard", and the working look shows
        its activity (`act`)."""
        t = 1_790_550_800_000
        state = {"t": "state", "base": "working", "act": "terminal", "mood": "calm", "busy": 1, "vol": 6}
        view = {"id": 9, "type": "turn", "from": [9], "line": 'claude started turn 2 on "jetpack".', "notes": [],
                "wakes_brain": True, "facts": {}, "phase": "start"}
        board, rows = board_after([
            {"sent": state, "received_at_ms": t},
            {"sent": {"t": "moment", "anim": "starting", "ctx": "new_task"}, "received_at_ms": t + 10},
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
            sent(t, 51, "stopped"),
            {"ended": {"id": 51, "how": "skipped", "why": "busy"}, "received_at_ms": t + 5},
            sent(t + 10, 52, "error"),
            {"ended": {"id": 52, "how": "done"}, "received_at_ms": t + 900},
        ])
        self.assertIn(("fail", "  ⇠ do 51 skipped (busy)"), rows)
        self.assertIn(("dim", "  ⇠ do 52 done"), rows)
        reflex = board.reflex_column()
        self.assertEqual(reflex, [("ok", f"{clock(t + 10)} error"), ("dim", f"{clock(t)} stopped (skipped: busy)")])

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

    def test_who_sent_a_moment(self):
        """A `sent` line's `by` says whose it is:
        a brain's moment is no reflex, face or not, and a rule's is one. A
        log from before `by` (and before `do`) guesses from the face."""
        t = 1_790_550_800_000
        brain = {"t": "moment", "anim": "cheer", "mood": "proud", "say": {"take": "new.d15"}}
        rule = {"t": "moment", "anim": "wiggle"}
        now = {"t": "do", "id": 3, "name": "task_complete", "play": "next", "args": {"mood": "proud"}}
        self.assertEqual(feed.sent_by({"sent": now, "by": "rule"}), "rule", "today's lines always say")
        lines = [{"sent": brain, "by": "brain", "received_at_ms": t}, {"sent": rule, "by": "rule", "received_at_ms": t}]
        self.assertEqual([(kind(line), feed.sent_by(line)) for line in lines], [("sent", "brain"), ("sent", "rule")])
        self.assertEqual(feed.sent_by({"sent": {"t": "moment", "anim": "wiggle"}, "by": "brain"}), "brain")
        self.assertEqual(feed.sent_by({"sent": {**rule, "mood": "calm"}, "by": "rule"}), "rule")
        self.assertEqual([feed.sent_by({"sent": m}) for m in (brain, rule)], ["brain", "rule"])
        board, _ = board_after([{**line, "received_at_ms": t + i} for i, line in enumerate(lines)])
        self.assertEqual(self.texts(board.reflex_column())[0], f"{clock(t + 1)} wiggle")
        self.assertFalse([r for r in self.texts(board.reflex_column()) if "cheer" in r])

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

    def test_the_same_columns_from_do_lines(self):
        """The Mac sends a `do` where it sent a `moment` (old_logs.as_do):
        Boop now and the three columns read the same from either."""
        lines = [as_do(line) for line in fixture_lines(COLUMNS)]
        self.assertTrue([line for line in lines if line.get("sent", {}).get("t") == "do"])
        board, _ = board_after(lines)
        for column in ("mood_column", "reflex_column", "decided_column"):
            self.assertEqual(getattr(board, column)(), getattr(self.board, column)(), column)
        for at in (self.board.newest_ms, self.at[31] + 1000):
            self.assertEqual(board.facts(at), self.board.facts(at))

    def test_the_same_columns_from_older_keys(self):
        """Logs from before the reaction's questions were regrouped
        (old_logs.with_old_keys) ask `react.mood`, `react.animation`,
        `react.loops`, `say.feeling` and `say.about`: Boop now and the three
        columns read the same from them."""
        lines = [with_old_keys(line) for line in fixture_lines(COLUMNS)]
        self.assertTrue([line for line in lines if "react.loops" in line.get("pass", {}).get("answers", {})])
        board, _ = board_after(lines)
        for column in ("mood_column", "reflex_column", "decided_column"):
            self.assertEqual(getattr(board, column)(), getattr(self.board, column)(), column)
        for at in (self.board.newest_ms, self.at[31] + 1000):
            self.assertEqual(board.facts(at), self.board.facts(at))

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
        scene, with a finish's outcome (ReactOutput.scenes)."""
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

                from boopctl_lib.common import MOODS
                await pick("m", MOODS.index("grumpy"))
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
    `say`; older logs name them otherwise, and read the same."""

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

    def test_older_keys(self) -> None:
        """`react.mood`, `react.animation` or `react.reply`, `react.loops`
        (its hold as the intensity it is now), `say.feeling` and
        `say.about`; and before them `react` and the words, `word.*`."""
        from boopctl_lib.dash.feed import FACE, INTENSITY, choice, move, picks_text, reaction_text
        a = lambda c, p=1.0: {"choice": c, "p": {c: p}}  # noqa: E731
        before = {"answers": {"react.mood": a("proud", 0.82), "react.animation": a("success", 0.9),
                              "react.loops": {"choice": "twice", "p": {"twice": 0.6, "once": 0.4}},
                              "say.feeling": a("glad", 0.7), "say.about": a("none"), "say.kind": a("sound")},
                  "questions": ["react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"]}
        self.assertEqual(picks_text(before), "proud 0.82 · success 0.90 · medium 0.60 · glad 0.70")
        self.assertEqual(reaction_text({"pass": before}), "a success in a proud face (medium)")
        talked = {"answers": {"react.mood": a("happy"), "react.animation": a("none"), "react.reply": a("love")}}
        self.assertEqual(move(talked), "love", "an older log's reply to what you said")
        self.assertEqual(reaction_text({"pass": talked}), "a happy reaction face, replying love")
        oldest = {"answers": {"react": a("grumpy"), "react.loops": a("once"), "word.feeling": a("again")},
                  "questions": ["react", "react.loops", "word.feeling"]}
        self.assertEqual((choice(oldest, FACE), choice(oldest, INTENSITY)), ("grumpy", "small"))
        self.assertEqual(picks_text(oldest), "grumpy 1.00 · small 1.00 · “again” 1.00")
        self.assertEqual(reaction_text({"pass": oldest}), "a grumpy reaction face (small)")
