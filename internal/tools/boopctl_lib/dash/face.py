"""The device's face in the terminal: the native simulator, fed
the lines the app sends, screenshotted a dozen times a second and drawn
with half blocks at exactly 1/3 scale, the face's 3-px grid."""
from __future__ import annotations

import queue
import threading
import time
from collections import Counter
from itertools import groupby
from typing import Callable

from rich.style import Style
from rich.text import Text

from boopctl_lib.device import DeviceError, Sim
from boopctl_lib.image import rgb888

SCALE = 3
# (x0, y0, x1, y1), end exclusive: the band above the bottom lane, where the
# strip and the bubble go (render/screens.h kLaneTop), which the animation
# bank's designs fill edge to edge (a successful finish's backdrop, needs
# you's panel, the props that show what the agents are doing), 107×64
# blocks, so 107×32 cells.
CROP = (0, 0, 320, 192)
FPS = 12


def blocks(indexes: bytes, width: int, box: tuple[int, int, int, int]) -> list[list[int]]:
    """The palette index of each SCALE×SCALE block in `box`: the most common
    one in it. Blocks at the box's edge may be narrower."""
    x0, y0, x1, y1 = box
    rows = []
    for by in range(y0, y1, SCALE):
        row = []
        for bx in range(x0, x1, SCALE):
            w = min(SCALE, x1 - bx)
            px = b"".join(indexes[y * width + bx : y * width + bx + w] for y in range(by, min(by + SCALE, y1)))
            row.append(px[0] if px.count(px[0]) == len(px) else Counter(px).most_common(1)[0][0])
        rows.append(row)
    return rows


def halfblocks(rows: list[list[int]], palette: list[int]) -> Text:
    """Two block rows per line of ▀: its colour the top one, its background
    the bottom one. Runs of the same pair share one span."""
    styles: dict[tuple[int, int], Style] = {}

    def style(top: int, bottom: int) -> Style:
        if (top, bottom) not in styles:
            styles[top, bottom] = Style(color="#%02x%02x%02x" % rgb888(palette[top]),
                                        bgcolor="#%02x%02x%02x" % rgb888(palette[bottom]))
        return styles[top, bottom]

    text = Text(no_wrap=True, overflow="crop")
    for i in range(0, len(rows), 2):
        top, bottom = rows[i], rows[i + 1] if i + 1 < len(rows) else rows[i]
        for pair, run in groupby(zip(top, bottom)):
            text.append("▀" * len(list(run)), style(*pair))
        if i + 2 < len(rows):
            text.append("\n")
    return text


def render(shot: tuple[list[int], bytes, tuple[int, int]]) -> Text:
    palette, indexes, (width, _) = shot
    return halfblocks(blocks(indexes, width, CROP), palette)


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
