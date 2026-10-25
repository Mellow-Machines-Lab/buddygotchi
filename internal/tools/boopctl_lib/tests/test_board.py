"""The board's lock (board.py): one holder at a time across processes, a
waiter that gives up saying whose it is, nested and inherited holds that go
straight through, and uploads that build unlocked, then flash locked and
are logged. Needs no board: the lock lives in a temporary folder."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import board  # noqa: E402
from boopctl_lib.cli import build_parser  # noqa: E402

BOARD_PY = Path(board.__file__)


class BoardLockTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.env = {k: os.environ.get(k) for k in ("BOOP_BOARD_LOCK", "BOOP_BOARD_WAIT", board.HELD_ENV)}
        os.environ["BOOP_BOARD_LOCK"] = os.path.join(self.dir.name, "board.lock")
        os.environ.pop("BOOP_BOARD_WAIT", None)
        os.environ.pop(board.HELD_ENV, None)
        self.others: list[subprocess.Popen] = []

    def tearDown(self):
        for p in self.others:
            p.kill()
            p.wait()
        for k, v in self.env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.dir.cleanup()

    def held_elsewhere(self, seconds: float = 5) -> subprocess.Popen:
        """Another process holding the board, as `board.py hold -- sleep N`."""
        p = subprocess.Popen([sys.executable, str(BOARD_PY), "hold", "--", "sleep", str(seconds)])
        self.others.append(p)
        deadline = time.monotonic() + 5
        while not (board.holder() or {}).get("pid"):
            self.assertLess(time.monotonic(), deadline, "the other process never took the lock")
            time.sleep(0.05)
        return p

    def test_the_default_wait_is_a_minute(self):
        # Pins the rule: under an agent's two-minute command limit, so why it waited gets printed.
        self.assertEqual(board.WAIT_S, 60)
        self.assertEqual(board.wait_s(), 60)
        os.environ["BOOP_BOARD_WAIT"] = "5"
        self.assertEqual(board.wait_s(), 5)

    def test_a_waiter_gives_up_saying_who_holds_it(self):
        self.held_elsewhere()
        started = time.monotonic()
        with self.assertRaises(board.Busy) as caught:
            with board.Hold("boopctl ping", wait=0.6):
                self.fail("took a lock another process holds")
        self.assertGreaterEqual(time.monotonic() - started, 0.5)
        self.assertIn("sleep 5", str(caught.exception))
        self.assertIn(Path(board.worktree()).name, str(caught.exception))
        self.assertIn("BOOP_BOARD_WAIT", str(caught.exception))

    def test_a_waiter_gets_it_when_the_holder_lets_go(self):
        self.held_elsewhere(1)
        with board.Hold("boopctl ping", wait=10) as h:
            self.assertTrue(h.took)
            self.assertEqual(board.holder()["why"], "boopctl ping")
        self.assertIsNone(board.holder())

    def test_holds_nest_in_one_process(self):
        with board.Hold("outer", wait=0):
            with board.Hold("inner", wait=0):
                self.assertEqual(board.holder()["why"], "outer")
            self.assertIsNotNone(board.holder(), "the inner hold let go of the outer's lock")
        self.assertIsNone(board.holder())
        self.assertNotIn(board.HELD_ENV, os.environ)

    def test_a_holders_children_go_straight_through(self):
        # `boopctl board hold -- …` runs a flash, a test and a flash back, each of which takes the lock.
        inner = [sys.executable, str(BOARD_PY), "hold", "--", "true"]
        env = dict(os.environ, BOOP_BOARD_WAIT="0")
        done = subprocess.run([sys.executable, str(BOARD_PY), "hold", "--", *inner], env=env, timeout=20)
        self.assertEqual(done.returncode, 0)

    def test_an_unrelated_process_with_a_stale_token_still_waits(self):
        self.held_elsewhere()
        os.environ[board.HELD_ENV] = "123-not-the-holders"
        with self.assertRaises(board.Busy):
            with board.Hold("boopctl ping", wait=0.2):
                pass

    def test_the_simulator_needs_no_lock(self):
        self.held_elsewhere()
        controller, tty = os.openpty()
        try:
            with board.Hold("boopctl run", port=os.ttyname(tty), wait=0) as h:
                self.assertFalse(h.took)
        finally:
            os.close(controller)
            os.close(tty)

    def test_hold_exits_with_the_commands_status(self):
        self.assertEqual(board.hold("false", ["false"]), 1)
        self.assertIsNone(board.holder())

    def test_an_upload_builds_before_it_locks(self):
        self.assertEqual(board.build_only(["pio", "run", "-e", "amoled206", "-t", "upload", "--upload-port", "/dev/x"]),
                         ["pio", "run", "-e", "amoled206", "--upload-port", "/dev/x"])
        self.assertEqual(board.build_only(["pio", "run", "--target=upload", "-t", "size"]), ["pio", "run", "-t", "size"])
        self.assertEqual(board.build_only(["pio", "run", "-tuploadfs"]), ["pio", "run"])

    def test_an_upload_is_locked_and_logged(self):
        calls = Path(self.dir.name) / "calls"
        pio = Path(self.dir.name) / "pio"
        # A stand-in pio that notes each command line, and whether it ran holding the board.
        pio.write_text(f"""#!{sys.executable}
import json, os, sys
sys.path.insert(0, {str(BOARD_PY.parent)!r})
import board
h = board.holder()
open({str(calls)!r}, "a").write(json.dumps([sys.argv[1:], h and h["why"]]) + "\\n")
""")
        pio.chmod(0o755)
        status = board.main(["upload", "--", str(pio), "run", "-e", "amoled206_profile", "-t", "upload"])
        self.assertEqual(status, 0)
        seen = [json.loads(line) for line in calls.read_text().splitlines()]
        self.assertEqual(seen, [[["run", "-e", "amoled206_profile"], None],
                                [["run", "-e", "amoled206_profile", "-t", "upload"], "flash amoled206_profile"]])
        [entry] = board.flashes(5)
        self.assertEqual((entry["env"], entry["ok"], entry["worktree"]), ("amoled206_profile", True, board.worktree()))
        self.assertIn("amoled206_profile", board.status())
        self.assertTrue(board.status().startswith("board: free"))

    def test_an_upload_waits_for_another_sessions_test(self):
        self.held_elsewhere()
        os.environ["BOOP_BOARD_WAIT"] = "0.3"
        status = board.main(["upload", "--", "true", "run", "-e", "amoled206", "-t", "upload"])
        self.assertEqual(status, 75)
        self.assertEqual(board.flashes(5), [])

    def test_boopctl_board_parses(self):
        args = build_parser().parse_args(["board"])
        self.assertEqual((args.action, args.cmd, args.last), (None, [], 8))
        args = build_parser().parse_args(["board", "hold", "--", "make", "flash"])
        self.assertEqual(args.action, "hold")
        self.assertEqual([a for a in args.cmd if a != "--"], ["make", "flash"])
        self.assertEqual(build_parser().parse_args(["board", "--last", "3"]).last, 3)


if __name__ == "__main__":
    unittest.main()
