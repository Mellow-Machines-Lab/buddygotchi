"""How fluid a recording is: each frame's change from the one before, per
transition. Record first (the face is `gel` or `pixel`):

    internal/tools/boopctl sim --face gel internal/tools/fluid/transitions.jsonl

then, with the tools' venv (Pillow):

    internal/tools/.venv/bin/python internal/tools/fluid/measure.py [/tmp/boop-sim/gel/transitions]

Shots are named `<ms>-<transition>`, 40 ms apart. For each transition it
prints the median and the largest changes (pixels that moved by more than
24 levels) and the ratio of the largest to the median: a cut shows as a
frame several times the median. With `--sheets DIR` it also writes a
contact sheet of each transition's first 640 ms."""
import argparse
import glob
import os
from collections import defaultdict

from PIL import Image, ImageChops, ImageDraw


def changed(a: Image.Image, b: Image.Image) -> int:
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 24 else 0)
    return diff.histogram()[255]


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dir", nargs="?", default="/tmp/boop-sim/gel/transitions")
    p.add_argument("--sheets", help="write a contact sheet of each transition here")
    args = p.parse_args()
    files = sorted(glob.glob(os.path.join(args.dir, "*.png")))
    if not files:
        raise SystemExit(f"no shots in {args.dir}; record them first (boopctl sim)")
    rows, prev = defaultdict(list), None
    for f in files:
        ms, _, name = os.path.basename(f)[:-4].partition("-")
        im = Image.open(f).convert("RGB")
        if prev is not None:
            rows[name].append((int(ms), changed(im, prev), f))
        prev = im
    print(f"{'transition':12s} {'frames':>6s} {'median':>7s} {'largest':>8s} {'ratio':>6s}  at")
    for name, r in rows.items():
        counts = sorted(c for _, c, _ in r)
        median, (at, top, _) = counts[len(counts) // 2], max(r, key=lambda x: x[1])
        print(f"{name:12s} {len(r):6d} {median:7d} {top:8d} {top / max(median, 1):6.1f}  {at} ms")
        if args.sheets:
            sheet(r[:16], os.path.join(args.sheets, f"{name}.png"))


def sheet(frames: list, out: str, cols: int = 8, scale: float = 0.4) -> None:
    w, h = Image.open(frames[0][2]).size
    tw, th = int(w * scale), int(h * scale)
    img = Image.new("RGB", (cols * tw, ((len(frames) + cols - 1) // cols) * (th + 14)), "white")
    draw = ImageDraw.Draw(img)
    for i, (ms, _, f) in enumerate(frames):
        x, y = (i % cols) * tw, (i // cols) * (th + 14)
        img.paste(Image.open(f).convert("RGB").resize((tw, th)), (x, y + 14))
        draw.text((x + 2, y), str(ms), fill="black")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)


if __name__ == "__main__":
    main()
