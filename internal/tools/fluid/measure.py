"""How fluid a recording is: each frame's change from the one before, per
transition. Record first (the face is `gel` or `pixel`):

    internal/tools/boopctl sim --face gel internal/tools/fluid/transitions.jsonl

then, with the tools' venv (Pillow):

    internal/tools/.venv/bin/python internal/tools/fluid/measure.py [DIR]

DIR is where `boopctl sim` saved them, by default this checkout's
/tmp/boop-sim/<checkout>/gel/transitions (its line for each shot names it).

Shots are named `<ms>-<transition>`, 40 ms apart; a frame is measured
against the one 40 ms before it, so a recording may leave gaps between its
transitions (`idle-swipes.jsonl` does). For each transition it
prints the median and the largest changes (pixels that moved by more than
24 levels) and the ratio of the largest to the median: a cut shows as a
frame several times the median. With `--sheets DIR` it also writes a
contact sheet of each transition's first 640 ms. The Character Studio's
Transitions measures the board in the page the same way, and ranks its
everyday transitions there."""
import argparse
import glob
import os
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageChops

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from boopctl_lib.common import checkout_tmp  # noqa: E402
from boopctl_lib.image import sheet  # noqa: E402

LEVELS = 24  # a pixel changed: its difference's luma is over this (the studio's board.js counts the same)
STEP_MS = 40  # the shots' spacing: a frame further from the one before starts afresh


def changed(a: Image.Image, b: Image.Image) -> int:
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > LEVELS else 0)
    return diff.histogram()[255]


def summary(changes: list) -> dict:
    """A transition's changes, frame by frame: the median (the upper of the
    middle two), the largest and where (the first, by index), and the ratio
    of the largest to the median (or to 1), several times for a cut. The
    studio's board.js keeps the same rule (tests/changed.json pins both)."""
    median, at = sorted(changes)[len(changes) // 2], changes.index(max(changes))
    return {"median": median, "largest": changes[at], "at": at, "ratio": changes[at] / max(median, 1)}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dir", nargs="?", default=str(checkout_tmp("boop-sim") / "gel" / "transitions"))
    p.add_argument("--sheets", help="write a contact sheet of each transition here")
    args = p.parse_args()
    files = sorted(glob.glob(os.path.join(args.dir, "*.png")))
    if not files:
        raise SystemExit(f"no shots in {args.dir}; record them first (boopctl sim)")
    rows, prev, prev_ms = defaultdict(list), None, None
    for f in files:
        ms, _, name = os.path.basename(f)[:-4].partition("-")
        im = Image.open(f).convert("RGB")
        if prev is not None and int(ms) - prev_ms == STEP_MS:
            rows[name].append((int(ms), changed(im, prev), f))
        prev, prev_ms = im, int(ms)
    print(f"{'transition':12s} {'frames':>6s} {'median':>7s} {'largest':>8s} {'ratio':>6s}  at")
    for name, r in rows.items():
        m = summary([c for _, c, _ in r])
        print(f"{name:12s} {len(r):6d} {m['median']:7d} {m['largest']:8d} {m['ratio']:6.1f}  {r[m['at']][0]} ms")
        if args.sheets:
            sheet([(f"{ms} ms", f) for ms, _, f in r[:16]], Path(args.sheets) / f"{name}.png")


if __name__ == "__main__":
    main()
