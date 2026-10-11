"""The simulator's core on the Mac, live (simulator/README.md): a board in
real time whose USB is the serial port a tool opens, driven the way a real
board is. Needs the core built: firmware/tools/pio.sh run -e native."""
from __future__ import annotations

import base64
import json
import os
import select
import subprocess
import tempfile
import time
import tty
import unittest
import zlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CORE = REPO / "firmware" / ".pio" / "build" / "native" / "program"
# The chosen character pack's voice, as the core takes it (core/file_card.h).
STAGED = REPO / ".character-build" / "pack"
VOICE = Path(STAGED.read_text().strip() if STAGED.exists() else REPO / "characters" / "pixel") / "voice" / "voice.bin"

WORKING = {"t": "state", "base": "working", "mood": "calm", "busy": 1, "vol": 6}


class Board:
    """boop-sim --live, with its serial port opened as a tool opens a board's."""

    def __init__(self, face: str = "pixel", **env: str) -> None:
        self.proc = subprocess.Popen([str(CORE), "--live"], stdout=subprocess.PIPE,
                                     env={**os.environ, "BOOP_SIM_FACE": face, **env})
        said = self.proc.stdout.readline().decode().split()
        assert said[:1] == ["port"], f"the core didn't say where its port is: {said}"
        self.port = said[1]
        self.usb = b""
        self.serial = -1
        self.plug()

    def plug(self) -> None:
        self.serial = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        tty.setraw(self.serial)

    def unplug(self) -> None:
        os.close(self.serial)
        self.serial = -1

    def close(self) -> None:
        if self.proc.poll() is None:
            if self.serial >= 0:
                self.unplug()
            self.proc.terminate()
            self.proc.wait(timeout=5)
            self.proc.stdout.close()

    def send(self, message: dict) -> None:
        os.write(self.serial, json.dumps(message).encode() + b"\n")

    def pump(self, seconds: float) -> None:
        """Reads everything the board says for this long."""
        end = time.monotonic() + seconds
        while (left := end - time.monotonic()) > 0:
            if self.serial < 0:
                time.sleep(left)
            elif select.select([self.serial], [], [], left)[0]:
                self.usb += os.read(self.serial, 65536)

    def lines(self) -> list[dict]:
        # The lines that are messages: a screenshot's data is a line of its own.
        return [json.loads(line) for line in self.usb.split(b"\n") if line.startswith(b"{")]

    def events(self) -> list[str]:
        return [m.get("kind") for m in self.lines() if m["t"] == "ev"]

    def request(self, message: dict, seconds: float = 0.3) -> dict:
        before = len(self.lines())
        self.send(message)
        self.pump(seconds)
        replies = [m for m in self.lines()[before:] if m.get("t") == message["t"]]
        assert replies, f"no reply to {message}"
        return replies[-1]


@unittest.skipUnless(CORE.exists(), "the core isn't built: firmware/tools/pio.sh run -e native")
class CoreTests(unittest.TestCase):
    def board(self, *args: str, **env: str) -> Board:
        board = Board(*args, **env)
        self.addCleanup(board.close)
        # Up once it answers; a new build's first start is slow.
        for _ in range(50):
            board.send({"t": "hello"})
            board.pump(0.1)
            if board.lines():
                return board
        self.fail("the board didn't start")

    def test_it_says_hello_and_draws_in_real_time(self) -> None:
        board = self.board()
        hello = board.request({"t": "hello"})
        self.assertEqual((hello["app"], hello["fw"], hello["face"]), ("boop", "sim", "pixel"))
        board.send(WORKING)
        board.pump(1.5)
        self.assertGreater(board.request({"t": "dbg.ping"})["fps"], 0, "the working face moves on its own, with no line asking")

    def test_the_native_face_fills_the_panel_it_is_given(self) -> None:
        board = self.board("gel")
        if board.request({"t": "hello"})["face"] != "gel":
            self.skipTest("this checkout's pack has only the pixel face")
        shot = board.request({"t": "dbg.shot"}, 1.5)
        self.assertEqual((shot["w"], shot["h"]), (502, 410), "the AMOLED's panel, by default")
        small = self.board("gel", BOOP_SIM_NATIVE="400x300")
        shot = small.request({"t": "dbg.shot"}, 1.5)
        self.assertEqual((shot["w"], shot["h"]), (400, 300))

    def test_every_power_on_is_a_new_boot(self) -> None:
        first = self.board().request({"t": "hello"})
        second = self.board().request({"t": "hello"})
        self.assertTrue(first["boot"])
        self.assertNotEqual(first["boot"], second["boot"])

    @unittest.skipUnless(VOICE.exists(), "the chosen character pack has no voice")
    def test_a_line_plays_at_the_pace_a_dac_would(self) -> None:
        board = self.board()
        self.assertEqual(board.request({"t": "dbg.ping"})["card"], "ok")
        board.send({**WORKING, "base": "idle", "busy": 0})  # a quiet face: only the line sounds
        board.pump(0.3)
        board.send({"t": "do", "id": 1, "name": "react", "play": "now", "args": {"say": {"take": "previous.go"}}})
        board.pump(3.0)
        state = board.request({"t": "dbg.state"})
        out = state["audio"]["out"]
        self.assertTrue(out["ready"])
        self.assertEqual(out["lines"], 1)
        self.assertGreater(out["out_ms"], 100)
        # The output's time for the line is the line's own length: the
        # board's takes check holds it within 10%.
        self.assertAlmostEqual(out["wall_ms"] / out["out_ms"], 1, delta=0.1)
        self.assertFalse(state["amp"], "the amp goes off about a second after the last sound")

    def test_the_port_is_a_serial_port_at_the_path_asked_for(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            link = os.path.join(tmp, "board.port")
            board = self.board(BOOP_SIM_PORT=link)
            self.assertEqual(os.path.realpath(link), os.path.realpath(board.port))
            self.assertTrue(os.isatty(board.serial))
            board.close()
            self.assertFalse(os.path.lexists(link), "the path goes when the board does")

    def test_what_nobody_heard_is_forgotten(self) -> None:
        # Pins Port::kStaleMs: with nothing reading, what the board said
        # 500 ms ago is thrown away, so a tool that opens the port later
        # hears only what's said from then on.
        board = self.board()
        board.send({"t": "dbg.touch", "x": 160, "y": 120, "ms": 100})
        board.pump(0.01)
        board.unplug()
        board.pump(1.2)  # the tap happens, and is said, with nobody listening
        board.usb = b""
        board.plug()
        board.pump(0.3)
        self.assertEqual(board.usb, b"")
        self.assertEqual(board.request({"t": "hello"})["app"], "boop")
        # Heard, when someone is there.
        board.request({"t": "dbg.touch", "x": 160, "y": 120, "ms": 100})
        board.pump(0.6)
        self.assertIn("tap", board.events())

    def test_a_long_reply_arrives_whole(self) -> None:
        # A screenshot is far more than the port holds at once: the board
        # waits for the reader, and drops nothing.
        board = self.board()
        head = board.request({"t": "dbg.shot"}, 2.0)
        lines = board.usb.split(b"\n")
        raw = base64.b64decode(lines[max(i for i, line in enumerate(lines) if b'"dbg.shot"' in line) + 1])
        self.assertEqual(len(raw), head["bytes"])
        self.assertEqual(zlib.crc32(raw), head["crc"])


if __name__ == "__main__":
    unittest.main()
