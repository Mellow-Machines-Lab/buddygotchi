"""The simulator's core with a window's end of the panel held by the test
(simulator/README.md): frames, sound, the board's parts and the inputs, in
real time, and its USB as the serial port a tool opens. Needs the core
built: firmware/tools/pio.sh run -e native."""
from __future__ import annotations

import json
import os
import select
import socket
import struct
import subprocess
import tempfile
import time
import tty
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CORE = REPO / "firmware" / ".pio" / "build" / "native" / "program"
VOICE = REPO / ".build" / "voice" / "voice.bin"
OUT_RATE = 22050  # voice::kOutRate
CHUNK = 512  # app::Sound::kChunk


class Board:
    """boop-sim --live, with the panel on a socket (or no window at all)
    and USB on its serial port, opened as a tool opens a board's."""

    def __init__(self, face: str = "pixel", window: bool = True, **env: str) -> None:
        self.panel, theirs = socket.socketpair()
        env = {**os.environ, "BOOP_SIM_FACE": face, **env}
        if window:
            env["BOOP_SIM_PANEL"] = str(theirs.fileno())
        self.proc = subprocess.Popen([str(CORE), "--live"], stdout=subprocess.PIPE,
                                     pass_fds=[theirs.fileno()] if window else [], env=env)
        theirs.close()
        said = self.proc.stdout.readline().decode().split()
        assert said[:1] == ["port"], f"the core didn't say where its port is: {said}"
        self.port = said[1]
        self.usb = b""
        self.raw = b""
        self.frames: list[tuple[int, int]] = []
        self.sound: list[float] = []  # when each chunk came
        self.parts: list[dict] = []
        self.serial = -1
        self.open()

    def open(self) -> None:
        """Plugs a tool into the port."""
        self.serial = os.open(self.port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
        tty.setraw(self.serial)

    def unplug(self) -> None:
        os.close(self.serial)
        self.serial = -1

    def close(self) -> None:
        if self.serial >= 0:
            self.unplug()
        self.proc.terminate()
        self.proc.wait(timeout=5)
        self.proc.stdout.close()
        self.panel.close()

    def send(self, message: dict) -> None:
        os.write(self.serial, json.dumps(message).encode() + b"\n")

    def input(self, line: str) -> None:
        self.panel.sendall(line.encode() + b"\n")

    def pump(self, seconds: float) -> None:
        """Reads everything the board says for this long."""
        end = time.monotonic() + seconds
        while (left := end - time.monotonic()) > 0:
            ready, _, _ = select.select([self.panel] + ([self.serial] if self.serial >= 0 else []), [], [], left)
            if self.serial in ready:
                self.usb += os.read(self.serial, 65536)
            if self.panel in ready:
                self.raw += self.panel.recv(1 << 20)
                self._messages()

    def _messages(self) -> None:
        while len(self.raw) >= 8:
            tag, n = self.raw[:4], struct.unpack("<I", self.raw[4:8])[0]
            if len(self.raw) < 8 + n:
                return
            body, self.raw = self.raw[8:8 + n], self.raw[8 + n:]
            if tag == b"FRM1":
                w, h = struct.unpack("<HH", body[:4])
                assert len(body) == 4 + w * h * 2, "a frame is its size and its RGB565 pixels"
                self.frames.append((w, h))
            elif tag == b"AUD1":
                assert len(body) == CHUNK
                self.sound.append(time.monotonic())
            elif tag == b"STA1":
                self.parts.append(json.loads(body))
            else:
                raise AssertionError(f"unknown message {tag!r}")

    def lines(self) -> list[dict]:
        # The lines that are messages: a screenshot's data is a line of its own.
        return [json.loads(line) for line in self.usb.split(b"\n") if line.startswith(b"{")]

    def request(self, message: dict, seconds: float = 0.3) -> dict:
        before = len(self.lines())
        self.send(message)
        self.pump(seconds)
        replies = [m for m in self.lines()[before:] if m.get("t") == message["t"]]
        assert replies, f"no reply to {message}"
        return replies[-1]


WORKING = {"t": "state", "base": "working", "mood": "calm", "busy": 1, "vol": 6}


@unittest.skipUnless(CORE.exists(), "the core isn't built: firmware/tools/pio.sh run -e native")
class CoreTests(unittest.TestCase):
    def board(self, *args: str, **env: str) -> Board:
        board = Board(*args, **env)
        self.addCleanup(board.close)
        # Up once it has said what its parts are; a new build's first start is slow.
        for _ in range(100):
            if board.parts:
                return board
            board.pump(0.05)
        self.fail("the board didn't start")

    def test_the_port_is_a_serial_port_at_the_path_asked_for(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            link = os.path.join(tmp, "board.port")
            board = self.board(BOOP_SIM_PORT=link)
            self.assertEqual(os.path.realpath(link), os.path.realpath(board.port))
            self.assertTrue(os.isatty(board.serial))
            board.close()
            self.assertFalse(os.path.lexists(link), "the path goes when the board does")
            self.doCleanups()

    def test_a_board_nobody_is_looking_at_still_answers_on_usb(self) -> None:
        board = Board(window=False)
        self.addCleanup(board.close)
        self.assertEqual(board.request({"t": "hello"}, 1.0)["app"], "boop")
        board.send(WORKING)
        board.pump(1.0)
        self.assertGreater(board.request({"t": "dbg.ping"})["fps"], 0, "it draws with no window to draw for")

    def test_what_nobody_heard_is_forgotten(self) -> None:
        # Pins Port::kStaleMs: with nothing reading, what the board said
        # 500 ms ago is thrown away, so a tool that opens the port later
        # hears only what's said from then on.
        board = self.board()
        board.pump(0.2)
        board.usb = b""
        board.unplug()
        board.input("touch 160 120")
        board.pump(0.15)
        board.input("release")
        board.pump(1.0)
        board.open()
        board.pump(0.3)
        self.assertEqual(board.usb, b"", "the tap happened with nobody listening")
        self.assertEqual(board.request({"t": "hello"})["app"], "boop")

    def test_a_long_reply_arrives_whole(self) -> None:
        # A screenshot is far more than the port holds at once: the board
        # waits for the reader, and drops nothing.
        board = self.board()
        head = board.request({"t": "dbg.shot"}, 2.0)
        lines = board.usb.split(b"\n")
        data = lines[[i for i, line in enumerate(lines) if b'"dbg.shot"' in line][-1] + 1]
        import base64
        import zlib
        raw = base64.b64decode(data)
        self.assertEqual(len(raw), head["bytes"])
        self.assertEqual(zlib.crc32(raw), head["crc"])

    def test_it_says_hello_and_draws_in_real_time(self) -> None:
        board = self.board()
        hello = board.request({"t": "hello"})
        self.assertEqual((hello["app"], hello["fw"], hello["face"]), ("boop", "sim", "pixel"))
        board.send(WORKING)
        board.pump(1.0)
        self.assertTrue(board.frames, "the working face moves on its own, with no line asking")
        self.assertEqual(set(board.frames), {(320, 240)})
        self.assertEqual(board.parts[0]["backlight"] > 0, True)

    def test_the_native_face_fills_the_panel_it_is_given(self) -> None:
        board = self.board("gel")
        board.send(WORKING)
        board.pump(0.5)
        self.assertEqual(set(board.frames), {(502, 410)}, "the AMOLED's panel, by default")
        small = self.board("gel", BOOP_SIM_NATIVE="400x300")
        small.send(WORKING)
        small.pump(0.5)
        self.assertEqual(set(small.frames), {(400, 300)})

    def test_a_touch_is_a_tap_and_boot_held_is_talking(self) -> None:
        board = self.board()
        board.send(WORKING)
        board.pump(0.3)
        board.input("touch 160 120")
        board.pump(0.15)
        board.input("release")
        board.pump(0.4)
        self.assertIn("tap", [m.get("kind") for m in board.lines() if m["t"] == "ev"])
        board.input("boot 1")
        board.pump(1.2)
        board.input("boot 0")
        board.pump(0.4)
        kinds = [m.get("kind") for m in board.lines() if m["t"] == "ev"]
        self.assertIn("talk_on", kinds)
        self.assertIn("talk_off", kinds)

    @unittest.skipUnless(VOICE.exists(), "needs a voice pack: make -C internal voice")
    def test_a_line_plays_at_the_pace_a_dac_would(self) -> None:
        board = self.board()
        board.send({**WORKING, "base": "idle", "busy": 0})  # a quiet face: only the line sounds
        board.pump(0.3)
        self.assertEqual(board.parts[-1]["card"], "ok")
        self.assertFalse(board.sound, "silence isn't sent")
        board.send({"t": "do", "id": 1, "name": "react", "play": "now", "args": {"say": {"take": "previous.go"}}})
        board.pump(3.0)
        out = board.request({"t": "dbg.state"})["audio"]["out"]
        self.assertTrue(out["ready"])
        self.assertEqual(out["lines"], 1)
        self.assertGreater(out["out_ms"], 100)
        # The output's time for the line is the line's own length: the
        # board's takes check holds it within 10%.
        self.assertAlmostEqual(out["wall_ms"] / out["out_ms"], 1, delta=0.1)
        # The chunks came as fast as they play, not all at once.
        span = board.sound[-1] - board.sound[0]
        played = (len(board.sound) - 1) * CHUNK / OUT_RATE
        self.assertAlmostEqual(span, played, delta=0.15)
        amps = [p["amp"] for p in board.parts]
        self.assertIn(True, amps)
        self.assertFalse(amps[-1], "the amp goes off about a second after the last sound")

    @unittest.skipUnless(VOICE.exists(), "needs a voice pack: make -C internal voice")
    def test_the_card_comes_out_and_goes_back(self) -> None:
        board = self.board()
        board.pump(0.2)
        board.input("card out")
        board.pump(0.2)
        self.assertEqual(board.parts[-1]["card"], "no card")
        self.assertEqual(board.request({"t": "dbg.ping"})["card"], "no card")
        board.input("card in")
        board.pump(0.2)
        self.assertEqual(board.parts[-1]["card"], "ok")

    def test_every_power_on_is_a_new_boot(self) -> None:
        first = self.board().request({"t": "hello"})
        second = self.board().request({"t": "hello"})
        self.assertTrue(first["boot"])
        self.assertNotEqual(first["boot"], second["boot"])


if __name__ == "__main__":
    unittest.main()
