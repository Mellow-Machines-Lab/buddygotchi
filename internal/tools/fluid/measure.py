"""How fluid a recording is: each frame's change from the one before, per
transition. Record first (the face is `gel` or `pixel`):

    internal/tools/boopctl sim --face gel internal/tools/fluid/transitions.jsonl

then, with the tools' venv (Pillow):

    internal/tools/.venv/bin/python internal/tools/fluid/measure.py [/tmp/boop-sim/gel/transitions]

Shots are named `<ms>-<transition>`, 40 ms apart. For each transition it
prints the median and the largest changes (pixels that moved by more than
24 levels) and the ratio of the largest to the median: a cut shows as a
frame several times the median. With `--sheets DIR` it also writes a
contact sheet of each transition's first 640 ms. With `--json FILE` it
writes the same numbers, the jumpiest first, each with its start and end as
the Character Studio's cells, from the scenario that recorded it
(`--scenario`): the studio's Transitions lists them from
`characters/<pack>/review/fluid-<face>.json`."""
import argparse
import glob
import json
import os
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw


LEVELS = 24  # a pixel changed: its difference's luma is over this (the studio's board.js counts the same)
# What the board shows while working for an `act` (the firmware's actFromName); any other is plain working.
ACTS = {"planning", "terminal", "tool_use", "searching", "analyzing", "testing", "delegating", "waiting"}


def changed(a: Image.Image, b: Image.Image) -> int:
    diff = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > LEVELS else 0)
    return diff.histogram()[255]


def cells(scenario: Path) -> dict:
    """Each transition's start and end as the studio's cells ({mood,
    state}), by its name: the look the last `state` showed before it, and
    what the messages since the shot before asked for, a `state`'s look, a
    `do`'s reaction, or a touch's poke or stroke. The first has no start."""
    out, look, ask, shown = {}, None, None, None
    for raw in scenario.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("//"):
            continue
        step = json.loads(raw)
        mood = (shown or {}).get("mood")
        if step.get("t") == "state":
            state = ("needs_you" if step.get("attn") else step["act"] if step.get("base") == "working" and step.get("act") in ACTS
                     else step.get("base", "idle"))
            ask = shown = {"mood": step.get("mood"), "state": state}
        elif step.get("t") == "do":
            ask = {"mood": step.get("args", {}).get("mood") or mood, "state": step["name"]}
        elif step.get("t") in ("dbg.touch", "dbg.press"):
            ask = {"mood": mood, "state": "gesture" if "to_x" in step else "poked"}
        elif "shot" in step and ask:
            out.setdefault(step["shot"].partition("-")[2], {"from": look, "to": ask})
            look, ask = shown, None
    return out


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("dir", nargs="?", default="/tmp/boop-sim/gel/transitions")
    p.add_argument("--sheets", help="write a contact sheet of each transition here")
    p.add_argument("--json", metavar="FILE", help="write each transition's numbers, start and end here, the jumpiest first")
    p.add_argument("--scenario", default=str(Path(__file__).with_name("transitions.jsonl")),
                   help="the scenario the shots were recorded with (default: transitions.jsonl, beside this)")
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
    measured, starts = [], cells(Path(args.scenario)) if args.json else {}
    for name, r in rows.items():
        counts = sorted(c for _, c, _ in r)
        median, (at, top, _) = counts[len(counts) // 2], max(r, key=lambda x: x[1])
        print(f"{name:12s} {len(r):6d} {median:7d} {top:8d} {top / max(median, 1):6.1f}  {at} ms")
        # `at` from the transition's first frame, the first after it was asked for, as the studio counts.
        measured.append({"name": name, "frames": len(r), "median": median, "largest": top, "ratio": round(top / max(median, 1), 1),
                         "at": at - r[0][0], **starts.get(name, {"from": None, "to": None})})
        if args.sheets:
            sheet(r[:16], os.path.join(args.sheets, f"{name}.png"))
    if args.json:
        Path(args.json).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json).write_text(json.dumps({"recording": args.dir, "transitions": sorted(measured, key=lambda m: -m["ratio"])},
                                              indent=1) + "\n")


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
