"""The device's face in the terminal: the native simulator, fed
the lines the app sends, screenshotted a dozen times a second and drawn
with half blocks."""
from __future__ import annotations

import queue
import sys
import threading
import time
from array import array
from itertools import groupby
from typing import Callable

from rich.style import Style
from rich.text import Text

from boopctl_lib.device import DeviceError, Sim
from boopctl_lib.image import rgb888

FPS = 12
# The face sends its whole panel in RGB565, no palette: it's sampled one
# pixel in every NATIVE_BLOCK×NATIVE_BLOCK block, a terminal's worth (about
# 100×66 blocks for the AMOLED's 502×410), above its lane, which starts
# 192/240 of the way down (render/screens.h kLaneTop on its 320×240 canvas).
NATIVE_BLOCK = 5
LANE_FROM = 192 / 240


def native_rows(pixels: bytes, size: tuple[int, int]) -> list[list[int]]:
    """The RGB565 colour at the middle of each NATIVE_BLOCK block of a
    native frame, above its lane."""
    width, height = size
    values = array("H", pixels)
    if sys.byteorder != "little":
        values.byteswap()
    lane, mid = int(height * LANE_FROM), NATIVE_BLOCK // 2
    return [[values[min(by + mid, lane - 1) * width + min(bx + mid, width - 1)] for bx in range(0, width, NATIVE_BLOCK)]
            for by in range(0, lane, NATIVE_BLOCK)]


def halfblocks(rows: list[list[int]]) -> Text:
    """Two block rows per line of ▀, each an RGB565 colour: its colour the
    top one, its background the bottom one. Runs of the same pair share one
    span."""
    styles: dict[tuple[int, int], Style] = {}

    def style(top: int, bottom: int) -> Style:
        if (top, bottom) not in styles:
            styles[top, bottom] = Style(color="#%02x%02x%02x" % rgb888(top),
                                        bgcolor="#%02x%02x%02x" % rgb888(bottom))
        return styles[top, bottom]

    text = Text(no_wrap=True, overflow="crop")
    for i in range(0, len(rows), 2):
        top, bottom = rows[i], rows[i + 1] if i + 1 < len(rows) else rows[i]
        for pair, run in groupby(zip(top, bottom)):
            text.append("▀" * len(list(run)), style(*pair))
        if i + 2 < len(rows):
            text.append("\n")
    return text


def render(shot: tuple[list[int] | None, bytes, tuple[int, int]]) -> Text:
    _, pixels, size = shot  # the panel in RGB565, with no palette
    return halfblocks(native_rows(pixels, size))


class SimFace:
    """The native simulator in a thread of its own, which alone touches it: lines queued
    with `send` reach it in order, and each frame is handed to `on_frame`
    (from that thread) as drawn text."""

    def __init__(self, program: str, on_frame: Callable[[Text], None], on_error: Callable[[str], None]) -> None:
        self.program = program
        self.on_frame = on_frame
        self.on_error = on_error
        self.lines: queue.Queue[dict | None] = queue.Queue()
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> None:
        self.lines.put(None)
        self.thread.join(timeout=2)

    def send(self, message: dict) -> None:
        self.lines.put(message)

    def restart(self, state: dict | None) -> None:
        """Forgets everything, lets the clock run, and shows `state`, if any."""
        for message in [{"t": "dbg.reset"}, {"t": "dbg.clock", "run": True}] + ([state] if state else []):
            self.send(message)

    def _run(self) -> None:
        try:
            with Sim(self.program) as sim:
                sim.send({"t": "dbg.clock", "run": True})
                drawn = None
                while True:
                    started = time.monotonic()
                    while not self.lines.empty():
                        message = self.lines.get()
                        if message is None:
                            return
                        sim.send(message)
                    shot = sim.shot()
                    if shot != drawn:  # most frames don't move
                        drawn = shot
                        self.on_frame(render(shot))
                    time.sleep(max(0.0, 1 / FPS - (time.monotonic() - started)))
        except (DeviceError, OSError, ValueError) as exc:
            self.on_error(f"the native simulator stopped: {exc}")
        except Exception as exc:  # noqa: BLE001 - a dead thread would leave the panel "starting" for good
            self.on_error(f"the native simulator's face failed: {type(exc).__name__}: {exc}")
