"""boopctl's Link on a scripted fake board: a debug request whose reply is
lost is asked for again when `retries` allows, and a short screenshot
always is. Needs no board."""
import base64
import json
import sys
import zlib
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib.device import DeviceError  # noqa: E402
from fake_board import FakeBoard  # noqa: E402


PING = b'{"t":"dbg.ping","fw":"t","up":5,"heap":90000,"heap_min":80000,"fps":21,"draw_us":812,"push_us":2690}\n'


class LinkTests(unittest.TestCase):
    def test_a_lost_reply_fails_without_retries(self):
        with self.assertRaises(DeviceError):
            FakeBoard.in_turn([b'{"t":"dbg.pi']).request({"t": "dbg.ping"})

    def test_a_lost_reply_is_asked_for_again(self):
        board = FakeBoard.in_turn([b'{"t":"dbg.pi', PING])  # the first reply loses its end
        seen: list[Exception] = []
        board.retries, board.on_retry = 1, seen.append
        self.assertEqual(board.vitals(), {"up": 5, "heap": 90000, "heap_min": 80000, "fps": 21, "draw_us": 812, "push_us": 2690})
        self.assertEqual(len(board.sent), 2)
        self.assertEqual(len(seen), 1)

    def test_retries_run_out(self):
        board = FakeBoard.in_turn([b"", b""])
        board.retries = 1
        with self.assertRaises(DeviceError):
            board.request({"t": "dbg.state"})
        self.assertEqual(len(board.sent), 2)

    def test_a_short_screenshot_is_asked_for_again_without_retries(self):
        """Link.shot_retries: a shot that lost bytes is asked for again even
        with `retries` at 0, which stays as it was for other requests."""
        raw = bytes(range(256)) * 2 + bytes(range(8))  # a palette and 8 pixels
        head = json.dumps({"t": "dbg.shot", "w": 4, "h": 2, "bytes": len(raw), "crc": zlib.crc32(raw)}).encode()
        data = base64.b64encode(raw)
        board = FakeBoard.in_turn([head + b"\n" + data[:-8] + b"\n", head + b"\n" + data + b"\n"])
        palette, pixels, size = board.shot()
        self.assertEqual((size, pixels, len(palette)), ((4, 2), bytes(range(8)), 256))
        self.assertEqual(len(board.sent), 2)
        self.assertEqual(board.retries, 0)

    def test_listening_hears_what_comes_unasked(self):
        """Link.listen reads while it waits, so an `ended` that comes then is
        heard (a simulator's port forgets what sits unread), torn lines too."""
        board = FakeBoard.in_turn([])
        board.pending = b'{"t":"ev","kind":"ended","data":{"id":1,"how":"done"}}\nboot noise\n{"t":"ev","ki\n'
        heard: list[dict] = []
        board.heard = heard.append
        board.listen(0.05)
        self.assertEqual([m["t"] for m in heard], ["ev", "torn"])
        self.assertEqual(heard[0]["data"], {"id": 1, "how": "done"})


if __name__ == "__main__":
    unittest.main()
