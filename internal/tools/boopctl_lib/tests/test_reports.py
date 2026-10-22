"""The dashboard and bug reports: `b` asks the app for one and copies its
path when it comes, and a report the app saved with its device on a socket
(the simulator's, or a board's bridge) gets that device's screen as
screen.png; with the device on Bluetooth, or none, it gets none. Needs no
board, app or sim: a socket answers dbg.shot as a board does."""
import asyncio
import base64
import json
import os
import shutil
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from PIL import Image  # noqa: E402

from boopctl_lib.dash import app as dash  # noqa: E402
from boopctl_lib.dash.app import Dash  # noqa: E402
from test_dash import Socket  # noqa: E402

# A 4×2 canvas: the palette's entry 1 is red, and the top-left pixel uses it.
W, H = 4, 2
PALETTE = struct.pack("<256H", *([0, 0xF800] + [0] * 254))
PIXELS = bytes([1] + [0] * (W * H - 1))


class ShotBridge:
    """A bridge's socket with a board behind it that answers dbg.shot."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(dir="/tmp")
        self.path = os.path.join(self.dir, "b.sock")
        self.asked: list[str] = []

    def __enter__(self) -> "ShotBridge":
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
                while b"\n" not in data and (chunk := conn.recv(4096)):
                    data += chunk
                line = data.split(b"\n")[0].decode()
                self.asked.append(line)
                if json.loads(line)["t"] == "dbg.shot":
                    raw = PALETTE + PIXELS
                    head = {"t": "dbg.shot", "w": W, "h": H, "bytes": len(raw), "crc": zlib.crc32(raw)}
                    conn.sendall(b'{"t":"ev","k":"tap"}\n' + json.dumps(head).encode() + b"\n" + base64.b64encode(raw) + b"\n")
                    time.sleep(0.2)

    def __exit__(self, *_: object) -> None:
        self.server.close()
        shutil.rmtree(self.dir)


def report(state: Path, name: str, about: dict | None) -> Path:
    """A report as the app saves it: the folder, then about.json last."""
    folder = state / "bug-reports" / name
    folder.mkdir(parents=True)
    (folder / "debug.jsonl").write_text("")
    if about is not None:
        (folder / "about.json").write_text(json.dumps(about))
    return folder


class ReportTests(unittest.TestCase):
    def test_reports(self):
        asyncio.run(self.drive())

    async def drive(self) -> None:
        state = Path(tempfile.mkdtemp())
        (state / "debug.jsonl").write_text("")
        report(state, "2026-10-20-090000", {"link": "usb:/nowhere", "connected": True})  # from before: left alone
        copied: list[str] = []
        with Socket() as hooks, ShotBridge() as bridge:
            app = Dash(state / "debug.jsonl", hooks.path)
            app.copy = copied.append
            async with app.run_test(size=(170, 50)) as pilot:
                await pilot.pause()
                await pilot.press("b")
                self.assertEqual(hooks.wait(1), [{"dev": "report"}])
                # The app's device is the simulator: the dashboard asks it for its screen.
                folder = report(state, "2026-10-21-101500", None)
                app.poll()
                self.assertEqual(copied, [str(folder)], "b copies the new report's path")
                self.assertFalse((folder / "screen.png").exists(), "it waits for about.json")
                (folder / "about.json").write_text(json.dumps({"link": f"usb:{bridge.path}", "connected": True}))
                app.poll()
                for _ in range(100):
                    if (folder / "screen.png").exists():
                        break
                    await pilot.pause(0.05)
                await pilot.pause(0.2)
                self.assertEqual(bridge.asked, ['{"t":"dbg.shot"}'])
                with Image.open(folder / "screen.png") as png:
                    self.assertEqual(png.size, (W, H))
                    self.assertEqual(png.convert("RGB").getpixel((0, 0)), (255, 0, 0))
                    self.assertEqual(png.convert("RGB").getpixel((1, 0)), (0, 0, 0))
                # A board on Bluetooth, and no device at all: no screen to ask for.
                ble = report(state, "2026-10-21-101600", {"link": "ble", "connected": True})
                none = report(state, "2026-10-21-101700", {"link": f"usb:{bridge.path}", "connected": False})
                app.poll()
                await pilot.pause(0.3)
                self.assertFalse((ble / "screen.png").exists())
                self.assertFalse((none / "screen.png").exists())
                self.assertEqual(len(bridge.asked), 1)
                self.assertFalse((state / "bug-reports" / "2026-10-20-090000" / "screen.png").exists())
                self.assertEqual(app.unread, {})
                await pilot.press("q")
        shutil.rmtree(state)

    def test_a_report_that_never_comes_and_one_without_about(self):
        state = Path(tempfile.mkdtemp())
        app = Dash(state / "debug.jsonl", "/nonexistent")
        notes: list[str] = []
        app.notify = lambda message, **_: notes.append(message)
        app.watch_reports(now=100.0)
        app.report_asked = 100.0
        app.watch_reports(now=100.0 + dash.REPORT_S + 1)
        self.assertIsNone(app.report_asked)
        self.assertIn("no bug report", notes[-1])
        folder = report(state, "2026-10-21-120000", None)
        app.watch_reports(now=200.0)
        self.assertIn(folder, app.unread)
        app.watch_reports(now=200.0 + dash.REPORT_S + 1)
        self.assertEqual(app.unread, {})
        self.assertIn("no about.json", notes[-1])
        shutil.rmtree(state)


if __name__ == "__main__":
    unittest.main()
