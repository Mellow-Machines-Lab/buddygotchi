"""Builds the device's faces from the animation bank as C tables.

The designs are the animation bank's (characters/pixel/design/boop-sound-bank-v4/):
13 moods × 22 states, each mood and state with variations of its own, some
for a host fact (task_complete's outcome, starting's context). This runs the
bank's own generator (bank.mjs, beside this) to write every design's SVG into
build/, which git ignores, and lists the designs in design/manifest.json. It
reads each SVG as rectangles and step-wise timings and writes
the Pixel pack's characters/pixel/firmware/include/faces.h, plus the frames the firmware test checks the device's
player against (internal/firmware/test/test_scene/frames.h), and the Pixel
pack's characters/pixel/mac/faces.json (characters/CHARACTER.md §9): the
faces the Mac's popover shows, and each design's loop length and host fact
for the Mac, which faces.h has too, so both sides time a moment's loops
alike.

The bank's SVGs come in three dialects: V2, the first pack's (`boop-motion`,
and needs you's `alert-motion`); V3, the older moods' newer states
(`state-motion`); and V4, the new moods' flip-books (`motion`), where each step
shows a whole face of its own. Each has a still copy for reduced motion, which
isn't read. The older moods' designs, V2 and V3, must come out of the bank
byte for byte as they were captured (the bank's qa/v3-fingerprints.json).

Every shape ends up on whole pixels and every change is a step, so the
device draws each design as Chrome does: a scaled, rotated or fractional
shape is filled where a pixel's centre is inside it, a translucent group
is blended over black, and a colour that fades is a step each time its
RGB565 value changes. Rerun it when the designs change:

    internal/tools/.venv/bin/python characters/pixel/tools/facegen/facegen.py [--check]

--check also renders every design in Chrome at the same moments and
compares it with this file's own renderer, pixel for pixel in RGB565.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import zlib
from dataclasses import dataclass, field
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[3]
DESIGN = HERE / "design"
MANIFEST = DESIGN / "manifest.json"
BUILD = HERE / "build"  # the bank's SVGs, made afresh each run (ignored by git)
BANK = REPO / "characters" / "pixel" / "design" / "boop-sound-bank-v4"
OUT = REPO / "characters" / "pixel" / "firmware" / "include" / "faces.h"
FRAMES = REPO / "internal" / "firmware" / "test" / "test_scene" / "frames.h"
FACES_JSON = REPO / "characters" / "pixel" / "mac" / "faces.json"
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
NS = "{http://www.w3.org/2000/svg}"
W, H = 320, 240

# The pixel designs' moods and render::SceneState's order:
# the first seven of each keep the numbers they had before the rest came. faces.h
# carries these names for the device (kMoodNames, kStateNames); the device looks
# the character pack's moods up among them by name (characters/CHARACTER.md §9).
MOODS = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad",
         "calm", "engaged", "annoyed", "irritated", "whiny", "wounded"]
STATES = ["idle", "working", "needs_you", "task_complete", "asleep", "no_app", "listening",
          "starting", "planning", "terminal", "tool_use", "searching", "analyzing", "testing",
          "delegating", "helper_return", "waiting", "reply_ready", "error", "stopped", "poked", "tap_spam"]
# The host fact a design is for, as faces.h numbers it (render::Outcome,
# render::StartCtx): task_complete's outcome and starting's context; none for any.
OUTCOMES = [None, "success", "failure"]
CTXS = [None, "new_task", "session", "continuation", "compacted"]
# The group that holds a design's animation, by dialect; the still copy
# beside it is the reduced-motion picture, which the device never shows.
MOTION = ("boop-motion", "alert-motion", "state-motion", "motion")
# The faces the popover's tile shows, as mood and look, from each one's
# first variation. Asleep is one design for every mood, and the tile reads
# happy's (app/Boop/Views/BoopFace.swift).
TILES = [(mood, state) for mood in MOODS
         for state in ["idle", "working", "needs_you"] + (["asleep"] if mood == "happy" else [])]
# The palette index the scene colours start at (render/palette.h
# kPaletteUsed): scene colour 0 is the black field, the canvas's 0, and
# colour i the palette's SCENE_BASE + i - 1.
SCENE_BASE = 48
# What the device does with a group (render::faces::Role): the face it
# moves and the mouth it opens to talk; the first pack's eyes, open and
# shut, which it blinks on its own clock; and a flip-book's steps, each a
# face, one of them the face with its eyes shut, which it shows to hide a
# change of design, as it shuts the others' eyes (render/scene.cpp).
ROLES = ["none", "face", "mouth", "eyes_open", "eyes_closed", "step", "blink_step"]
# A blink's closed eyes show for at most this long in a loop.
BLINK_MAX_MS = 400
# Moments the check and the frames sample, in ms; each scene skips those
# within 4 ms of a step, where Chrome and the device could disagree by a
# rounding.
SAMPLES = [0, 150, 420, 700, 1100, 1650, 2300, 3100, 4200, 5500, 7300, 9900]
# A design with nothing moving but the blink, or nothing at all, still
# loops, in this time.
STILL_LOOP_MS = 1000
INHERIT = 255  # a rectangle's colour: its group's fill track decides
# A rectangle's colour from BLEND on is a translucent one, pair
# colour - BLEND of `BLENDS`, blended over what's beneath it.
BLEND = 128


class Blends:
    """The translucent colours: an RGB colour and how opaque it is, which
    the device blends over the pixel beneath through a table."""

    def __init__(self) -> None:
        self.pairs: list[tuple[tuple[int, int, int], int]] = []  # premultiplied colour, alpha: 8 bits each
        self.index: dict[tuple[tuple[int, int, int], int], int] = {}

    def of(self, pm: tuple[int, int, int], a: int) -> int:
        k = (pm, a)
        if k not in self.index:
            self.index[k] = len(self.pairs)
            self.pairs.append(k)
        assert len(self.pairs) + BLEND < INHERIT, "the translucent colours fit"
        return BLEND + self.index[k]

    def over(self, pair: int, dst: int) -> int:
        """The scene colour of `pair` blended over scene colour `dst`, as
        Chrome composites a group."""
        pm, a = self.pairs[pair]
        return COLORS.of(blend(pm, a, COLORS.rgb[dst]))


def a8(a: float) -> int:
    """An opacity as Chrome keeps it: 8 bits."""
    return int(a * 255 + 0.5)


def mul255(a: int, b: int) -> int:
    """a × b / 255, rounded as Skia does."""
    p = a * b + 128
    return (p + (p >> 8)) >> 8


def blend(pm: tuple[int, int, int], a: int, d: tuple[int, int, int]) -> tuple[int, int, int]:
    """A premultiplied colour of alpha `a` over the opaque `d`."""
    return tuple(min(255, pv + mul255(dv, 255 - a)) for pv, dv in zip(pm, d))


BLENDS = Blends()


class BlendTable:
    """Each translucent colour over each scene colour: what the device looks
    up for a pixel it blends over. While open, a blend facegen meets is
    worked out exactly, and its colour joins the scene colours; once frozen,
    one it never met takes the nearest colour there is."""

    def __init__(self) -> None:
        self.cache: dict[tuple[int, int], int] = {}
        self.frozen = False

    def get(self, pair: int, dst: int) -> int:
        k = (pair, dst)
        if k not in self.cache:
            if not self.frozen:
                self.cache[k] = BLENDS.over(pair, dst)
            else:
                pm, a = BLENDS.pairs[pair]
                want = blend(pm, a, COLORS.rgb[dst])
                self.cache[k] = min(range(len(COLORS.rgb)), key=lambda i: sum((p - q) ** 2 for p, q in zip(COLORS.rgb[i], want)))
        return self.cache[k]

    def freeze(self, scenes: "list[Scene]") -> None:
        """Meets every blend the scenes make, in every state they pass
        through, the eyes open and shut, then freezes."""
        for sc in scenes:
            if not any(c >= BLEND and c != INHERIT for g in sc.groups for *_, c in g.rects):
                continue
            for t in sc.step_times() or [0]:
                for shut in (False, True):
                    render(sc, t, shut=shut)
                render(sc, t, svg_blink=True)
        self.frozen = True


BLEND_TABLE = BlendTable()


def rgb565(c: tuple[int, int, int]) -> int:
    return ((c[0] >> 3) << 11) | ((c[1] >> 2) << 5) | (c[2] >> 3)


def hex_rgb(s: str) -> tuple[int, int, int]:
    s = s.strip()
    assert re.fullmatch(r"#[0-9A-Fa-f]{6}", s), s
    return int(s[1:3], 16), int(s[3:5], 16), int(s[5:7], 16)


class Colors:
    """The scene colours, in the order they're met; 0 is the black field."""

    def __init__(self) -> None:
        self.rgb: list[tuple[int, int, int]] = [(0, 0, 0)]
        self.index: dict[tuple[int, int, int], int] = {(0, 0, 0): 0}

    def of(self, c: tuple[int, int, int]) -> int:
        if c not in self.index:
            self.index[c] = len(self.rgb)
            self.rgb.append(c)
        return self.index[c]


COLORS = Colors()


@dataclass
class Track:
    kind: str  # "move", "show" or "fill"
    dur: int  # ms
    keys: list[int]  # ms, the first 0
    values: list[tuple[int, int]]  # (dx, dy) to move; (1 or 0, 0) to show; (colour, 0) to fill

    def index(self, t: int) -> int:
        lt = t % self.dur
        return max(i for i, k in enumerate(self.keys) if k <= lt)


@dataclass
class Group:
    parent: int
    tx: int = 0
    ty: int = 0
    visible: bool = True
    move: Track | None = None
    show: Track | None = None
    fill: Track | None = None
    role: str = "none"
    part: str = ""
    blink: bool = False  # a flip-book step's face with its eyes shut (V4's data-blink)
    baking: bool = False  # a scaled or turned group, whose descendants are drawn into it
    rects: list[tuple[int, int, int, int, int]] = field(default_factory=list)  # x, y, w, h, colour


@dataclass
class Scene:
    groups: list[Group]
    clip: tuple[int, int, int, int]  # x, y, w, h

    def tracks(self) -> list[Track]:
        return [t for g in self.groups for t in (g.move, g.show, g.fill) if t]

    def boundaries(self, until: int) -> set[int]:
        out: set[int] = set()
        for tr in self.tracks():
            for r in range(until // tr.dur + 1):
                out.update(r * tr.dur + k for k in tr.keys)
                out.add(r * tr.dur + tr.dur)
        return out

    def samples(self) -> list[int]:
        bounds = self.boundaries(max(SAMPLES) + 1)
        return [t for t in SAMPLES if t == 0 or all(abs(t - b) > 4 for b in bounds)]

    def step_times(self) -> list[int]:
        """The moments something steps in one pass through the design's
        longest track, in order; none for a design with no tracks."""
        longest = max((tr.dur for tr in self.tracks()), default=0)
        return sorted(t for t in self.boundaries(longest) if t < longest)

    def key(self) -> str:
        return hashlib.sha1(repr((self.groups, self.clip)).encode()).hexdigest()

    def loop_ms(self) -> int:
        """How long the design takes to play once through: its longest
        animation, leaving out the blink, which the device times on its
        own. A moment's `loops` count these."""
        timed = [tr.dur for g in self.groups if g.role not in ("eyes_open", "eyes_closed")
                 for tr in (g.move, g.show, g.fill) if tr]
        return max(timed or [STILL_LOOP_MS])


# ---- Reading the SVGs --------------------------------------------------------


def seconds_ms(s: str) -> int:
    assert s.endswith("s"), s
    return round(float(s[:-1]) * 1000)


def parse_track(el: ET.Element) -> Track:
    assert el.get("repeatCount") == "indefinite" and el.get("begin", "0s") == "0s"
    dur = seconds_ms(el.get("dur"))
    raw = [float(k) for k in el.get("keyTimes").split(";")]
    values = el.get("values").split(";")
    assert len(values) == len(raw) and raw[0] == 0, "one value per key time, from 0"
    keys = [round(k * dur) for k in raw]
    if el.tag == NS + "animateTransform":
        assert el.get("type") == "translate" and el.get("calcMode") == "discrete"
        vals = [tuple(int(n) for n in v.split()) for v in values]
        return Track("move", dur, keys, vals)
    name = el.get("attributeName")
    if name == "opacity":
        assert el.get("calcMode") == "discrete"
        vals = [(int(float(v)), 0) for v in values]
        assert all(v in ((0, 0), (1, 0)) for v in vals), "opacity is 0 or 1"
        return Track("show", dur, keys, vals)
    assert name == "fill" and el.get("calcMode") == "linear", f"only a linear fill fades: {name}"
    return fade(dur, raw, [hex_rgb(v) for v in values])


def fade(dur: int, raw: list[float], cols: list[tuple[int, int, int]]) -> Track:
    """A linear fill as steps: a new one each millisecond its RGB565 value
    changes, holding the colour it has there, as Chrome interpolates each
    channel."""
    keys: list[int] = []
    vals: list[tuple[int, int]] = []
    last = None
    for t in range(dur):
        p = t / dur
        i = max(j for j in range(len(raw)) if raw[j] <= p)
        if i + 1 < len(raw) and raw[i + 1] > raw[i]:
            f = (p - raw[i]) / (raw[i + 1] - raw[i])
            c = tuple(round(a + (b - a) * f) for a, b in zip(cols[i], cols[i + 1]))
        else:
            c = cols[i]
        if rgb565(c) != last:
            keys.append(t)
            vals.append((COLORS.of(c), 0))
            last = rgb565(c)
    return Track("fill", dur, keys, vals)


Matrix = tuple[float, float, float, float, float, float]  # a b c d e f, as SVG's matrix()
IDENTITY: Matrix = (1, 0, 0, 1, 0, 0)


def mul(m: Matrix, n: Matrix) -> Matrix:
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2, a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def parse_transform(s: str | None) -> Matrix:
    m = IDENTITY
    for name, args in re.findall(r"(\w+)\(([^)]*)\)", s or ""):
        v = [float(x) for x in re.split(r"[\s,]+", args.strip())]
        if name == "translate":
            n = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0)
        elif name == "scale":
            n = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "rotate":
            assert len(v) == 1 and v[0] % 90 == 0, f"only quarter turns: {s}"
            q = int(v[0]) // 90 % 4
            n = [(1, 0, 0, 1, 0, 0), (0, 1, -1, 0, 0, 0), (-1, 0, 0, -1, 0, 0), (0, -1, 1, 0, 0, 0)][q]
        else:
            raise AssertionError(f"transform {name}")
        m = mul(m, n)
    return m


def is_translate(m: Matrix) -> bool:
    return m[:4] == (1, 0, 0, 1) and m[4] == int(m[4]) and m[5] == int(m[5])


def path_polys(d: str) -> list[list[tuple[float, float]]]:
    """An outline of straight lines, as closed polygons."""
    assert re.fullmatch(r"(?:\s*(?:[MmHhVvLlZz]|-?\d*\.?\d+(?:e-?\d+)?)[\s,]*)*", d), f"only M, H, V, L and Z: {d}"
    tokens = re.findall(r"[MmHhVvLlZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    polys: list[list[tuple[float, float]]] = []
    cur: list[tuple[float, float]] = []
    x = y = 0.0
    i = 0
    cmd = ""

    def num() -> float:
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    while i < len(tokens):
        if re.fullmatch(r"[A-Za-z]", tokens[i]):
            cmd = tokens[i]
            i += 1
        if cmd in "Mm":
            nx, ny = num(), num()
            x, y = (nx, ny) if cmd == "M" else (x + nx, y + ny)
            if cur:
                polys.append(cur)
            cur = [(x, y)]
            cmd = "L" if cmd == "M" else "l"
            continue
        if cmd in "Zz":
            if cur:
                polys.append(cur)
                x, y = cur[0]
            cur = []
            continue
        if cmd in "Hh":
            nx = num()
            x = nx if cmd == "H" else x + nx
        elif cmd in "Vv":
            ny = num()
            y = ny if cmd == "V" else y + ny
        else:
            nx, ny = num(), num()
            x, y = (nx, ny) if cmd == "L" else (x + nx, y + ny)
        cur.append((x, y))
    if cur:
        polys.append(cur)
    return polys


def fill_polys(polys: list[list[tuple[float, float]]]) -> list[tuple[int, int, int, int]]:
    """Polygons filled nonzero, as rectangles: a pixel is filled when its
    centre is inside; a centre exactly on an edge belongs to the shape on the
    edge's left, or above it, as Chrome draws it (it rounds a half-pixel edge
    up)."""
    edges = []
    for p in polys:
        for k in range(len(p)):
            (x0, y0), (x1, y1) = p[k], p[(k + 1) % len(p)]
            if y0 != y1:
                edges.append((x0, y0, x1, y1))
    if not edges:
        return []
    ys = [v for e in edges for v in (e[1], e[3])]
    xs = [v for p in polys for v, _ in p]
    rows: list[list[tuple[int, int]]] = []
    top = int(min(ys) // 1)
    for py in range(top, int(-(-max(ys) // 1))):
        cy = py + 0.5
        cross = []
        for x0, y0, x1, y1 in edges:
            if min(y0, y1) < cy <= max(y0, y1):
                cross.append((x0 + (cy - y0) * (x1 - x0) / (y1 - y0), 1 if y1 > y0 else -1))
        run: list[tuple[int, int]] = []
        start = None
        for px in range(int(min(xs) // 1), int(-(-max(xs) // 1)) + 1):
            cx = px + 0.5
            wind = sum(w for x, w in cross if x >= cx)
            if wind and start is None:
                start = px
            if not wind and start is not None:
                run.append((start, px))
                start = None
        rows.append(run)
    return merge_runs(rows, top)


def merge_runs(rows: list[list[tuple[int, int]]], y0: int) -> list[tuple[int, int, int, int]]:
    """Runs of pixels, row by row, as rectangles: a run that repeats on the next row grows down."""
    out: list[tuple[int, int, int, int]] = []
    open_: dict[tuple[int, int], int] = {}  # run → the row it started on
    for r, runs in enumerate(rows + [[]]):
        now = set(runs)
        for run, top in list(open_.items()):
            if run not in now:
                out.append((run[0], y0 + top, run[1] - run[0], r - top))
                del open_[run]
        for run in runs:
            open_.setdefault(run, r)
    return sorted(out, key=lambda q: (q[1], q[0]))


def apply(m: Matrix, p: tuple[float, float]) -> tuple[float, float]:
    a, b, c, d, e, f = m
    return a * p[0] + c * p[1] + e, b * p[0] + d * p[1] + f


def shape_rects(el: ET.Element, m: Matrix) -> list[tuple[int, int, int, int]]:
    """A rect or path under `m`, as whole-pixel rectangles."""
    tag = el.tag[len(NS):]
    if tag == "rect":
        x, y, w, h = (float(el.get(a, "0")) for a in ("x", "y", "width", "height"))
        if is_translate(m) and all(v == int(v) for v in (x, y, w, h)):
            return [(int(x + m[4]), int(y + m[5]), int(w), int(h))] if w > 0 and h > 0 else []
        polys = [[(x, y), (x + w, y), (x + w, y + h), (x, y + h)]]
    else:
        polys = path_polys(el.get("d"))
    return fill_polys([[apply(m, p) for p in poly] for poly in polys])


def read_scene(path: Path) -> Scene:
    root = ET.parse(path).getroot()
    motion = next(el for el in root.iter() if el.get("class") in MOTION)
    clip = (0, 0, W, H)
    clipped = next((el for el in root.iter() if el.get("clip-path")), None)
    if clipped is not None:
        ref = re.fullmatch(r"url\(#([\w-]+)\)", clipped.get("clip-path"))[1]
        box = next(el for el in root.iter() if el.get("id") == ref).find(NS + "rect")
        clip = tuple(int(float(box.get(a, "0"))) for a in ("x", "y", "width", "height"))
    scene = Scene([], clip)

    def walk(el: ET.Element, parent: int, fill: tuple[int, int, int] | int | None, alpha: float,
             bake: Matrix | None) -> None:
        """A group and what's in it. `bake` is the transform a scaled or
        turned ancestor started, whose shapes and groups are drawn into it."""
        m = parse_transform(el.get("transform"))
        tracks = [parse_track(c) for c in el if c.tag in (NS + "animate", NS + "animateTransform")]
        opacity = float(el.get("opacity", "1"))
        if bake is None and not is_translate(m):
            bake = IDENTITY  # this group bakes its shapes from here down
        if bake is not None:
            assert not tracks, f"{path.name}: an animation inside a scaled group"
            assert opacity in (0, 1) or opacity > 0, path.name
            bake = mul(bake, m)
        if bake is not None and parent >= 0 and scene.groups[parent].baking:
            me = parent  # flattened into the baking group
            if opacity == 0:
                return
        else:
            g = Group(parent)
            if bake is None:
                g.tx, g.ty = int(m[4]), int(m[5])
            else:
                g.baking = True
            g.visible = opacity != 0
            g.part = el.get("data-part") or ""
            g.blink = el.get("data-blink") == "1"
            for tr in tracks:
                assert getattr(g, tr.kind) is None, f"{path.name}: one animation of each kind a group"
                setattr(g, tr.kind, tr)
            me = len(scene.groups)
            scene.groups.append(g)
        if 0 < opacity < 1 and bake is None:
            # A translucent group: its shapes, flattened as Chrome draws the
            # group into a layer of its own, then that layer at its opacity.
            scene.groups[me].visible = True
            layer(el, fill, opacity, scene.groups[me])
            return
        if 0 < opacity < 1:
            alpha *= opacity
        if el.get("fill"):
            fill = hex_rgb(el.get("fill"))
        if scene.groups[me].fill and me == len(scene.groups) - 1 and not scene.groups[me].baking:
            fill = INHERIT  # its rectangles take the fill track's colour
        # Shapes draw in document order: those after a child group go in a
        # group of their own, after that child's.
        sink = me
        for child in el:
            tag = child.tag[len(NS):]
            if tag in ("animate", "animateTransform"):
                continue
            if tag == "g":
                walk(child, me, fill, alpha, bake)
                if not scene.groups[me].baking:
                    sink = -1
            elif tag in ("rect", "path") and any(c.tag in (NS + "animate", NS + "animateTransform") for c in child):
                # An animated shape is a group of its own around a plain one.
                wrap = ET.Element(NS + "g", {k: v for k, v in child.attrib.items() if k in ("fill", "opacity")})
                for c in child:
                    wrap.append(c)
                plain = ET.Element(child.tag, {k: v for k, v in child.attrib.items() if k not in ("fill", "opacity")})
                wrap.append(plain)
                walk(wrap, me, fill, alpha, bake)
                if not scene.groups[me].baking:
                    sink = -1
            elif tag in ("rect", "path"):
                c = hex_rgb(child.get("fill")) if child.get("fill") else fill
                assert c is not None, f"{path.name}: a shape with no fill"
                if c == INHERIT:
                    assert alpha == 1, f"{path.name}: a translucent fade"
                    color = INHERIT
                else:
                    color = COLORS.of(tuple(round(v * alpha) for v in c))  # over black
                if sink < 0:
                    sink = len(scene.groups)
                    scene.groups.append(Group(me))
                for q in shape_rects(child, bake or IDENTITY):
                    scene.groups[sink].rects.append((*q, color))
            else:
                raise AssertionError(f"{path.name}: unexpected <{tag}>")

    walk(motion, -1, None, 1.0, None)
    for g in scene.groups:
        g.baking = False  # only for reading: two scenes that draw alike are one
    assign_roles(scene, path.name)
    return scene


def layer(el: ET.Element, fill, opacity: float, g: Group) -> None:
    """A translucent group's layer, as rectangles of one translucent colour
    each in the group's own space: its shapes painted in order into a layer
    of its own, a nested translucent group into one of its own composited in
    turn, then all of it at `opacity`, as Chrome (Skia) draws groups: in
    premultiplied 8-bit colour."""
    Layer = dict[tuple[int, int], tuple[int, int, int, int]]  # premultiplied r, g, b and alpha

    def over(dst: Layer, xy: tuple[int, int], src: tuple[int, int, int, int]) -> None:
        d = dst.get(xy, (0, 0, 0, 0))
        dst[xy] = tuple(min(255, sv + mul255(dv, 255 - src[3])) for sv, dv in zip(src, d))

    def build(e: ET.Element, m: Matrix, fill) -> Layer:
        out: Layer = {}
        for child in e:
            tag = child.tag[len(NS):]
            assert tag not in ("animate", "animateTransform"), "nothing moves inside a translucent group"
            if tag == "g":
                o = float(child.get("opacity", "1"))
                if o == 0:
                    continue
                cm = mul(m, parse_transform(child.get("transform")))
                cf = hex_rgb(child.get("fill")) if child.get("fill") else fill
                sub = build(child, cm, cf)
                k = a8(o)
                for xy, p in sub.items():
                    over(out, xy, tuple(mul255(v, k) for v in p))
            elif tag in ("rect", "path"):
                c = hex_rgb(child.get("fill")) if child.get("fill") else fill
                assert c not in (None, INHERIT)
                k = a8(float(child.get("opacity", "1")))
                src = tuple(mul255(v, k) for v in c) + (k,)
                for x, y, w, h in shape_rects(child, m):
                    for yy in range(y, y + h):
                        for xx in range(x, x + w):
                            over(out, (xx, yy), src)
        return out

    px = build(el, IDENTITY, hex_rgb(el.get("fill")) if el.get("fill") else fill)
    if not px:
        return
    k = a8(opacity)
    ys = [y for _, y in px]
    y0 = min(ys)
    by_row: dict[int, dict[int, list[int]]] = {}
    for (x, y), p in px.items():
        r, gg, b, a = (mul255(v, k) for v in p)
        pair = BLENDS.of((r, gg, b), a)
        by_row.setdefault(pair, {}).setdefault(y, []).append(x)
    for pair, rows_of in by_row.items():
        rows = []
        for y in range(y0, max(ys) + 1):
            xs = sorted(rows_of.get(y, []))
            run, start, last = [], None, None
            for x in xs:
                if start is None:
                    start = last = x
                elif x == last + 1:
                    last = x
                else:
                    run.append((start, last + 1))
                    start = last = x
            if start is not None:
                run.append((start, last + 1))
            rows.append(run)
        g.rects += [(x, y, w, h, pair) for x, y, w, h in merge_runs(rows, y0)]


def assign_roles(scene: Scene, name: str) -> None:
    groups = scene.groups
    for g in groups:
        if g.part == "face":
            g.role = "face"
        elif g.part == "mouth":
            g.role = "mouth"
    # A blink: two sibling groups, one showing but for a short window in its
    # loop and the other only in that window. The device blinks on its own
    # clock, so it shows the open eyes, or the closed ones while it blinks.
    for i, a in enumerate(groups):
        if not a.show or a.role != "none":
            continue
        for j in range(i + 1, len(groups)):
            b = groups[j]
            if b.parent != a.parent or not b.show or b.role != "none" or b.show.dur != a.show.dur:
                continue
            if b.show.keys != a.show.keys or any(x[0] == y[0] for x, y in zip(a.show.values, b.show.values)):
                continue
            shut = sum(a.show.keys[k + 1] - a.show.keys[k] if k + 1 < len(a.show.keys) else a.show.dur - a.show.keys[k]
                       for k, v in enumerate(a.show.values) if v[0] == 0)
            if 0 < shut <= BLINK_MAX_MS and a.visible and not b.visible:
                a.role, b.role = "eyes_open", "eyes_closed"
                break
    # A flip-book (V4) has a face in each step, each with its mouth, and only
    # one step shows at a time: the device moves, and talks with, the face
    # that shows (render/scene.cpp). It blinks in a step of its own, whose
    # face the bank tags; to hide a change of design, the device shows that
    # step in place of the others, as it shuts the first pack's eyes.
    faces = [i for i, g in enumerate(groups) if g.role == "face"]
    if any(groups[i].blink for i in faces):
        for i in faces:
            step = groups[i].parent
            while step >= 0 and not groups[step].show:
                step = groups[step].parent
            assert step >= 0 and groups[step].role == "none", f"{name}: each face in a step of its own"
            groups[step].role = "blink_step" if groups[i].blink else "step"
        assert [g.role for g in groups].count("blink_step") == 1, f"{name}: one step blinks"
    roles = [g.role for g in groups]
    assert roles.count("face") >= 1, f"{name}: a face"
    assert roles.count("mouth") >= 1, f"{name}: a mouth"
    for t in scene.step_times() or [0]:
        _, shown, _ = place(scene, t, svg_blink=True, shut=False)
        for role in ("face", "mouth"):
            assert sum(shown[i] for i, r in enumerate(roles) if r == role) <= 1, f"{name}: one {role} at a time ({t} ms)"


# ---- Drawing, as the device does and as the SVG does -------------------------


def place(scene: Scene, t: int, svg_blink: bool, shut: bool) -> tuple[list[tuple[int, int]], list[bool], list[int]]:
    offset: list[tuple[int, int]] = []
    shown: list[bool] = []
    fills: list[int] = []
    for g in scene.groups:
        ox, oy = offset[g.parent] if g.parent >= 0 else (0, 0)
        on = shown[g.parent] if g.parent >= 0 else True
        fl = fills[g.parent] if g.parent >= 0 else 0
        ox, oy = ox + g.tx, oy + g.ty
        if g.move:
            dx, dy = g.move.values[g.move.index(t)]
            ox, oy = ox + dx, oy + dy
        vis = g.visible
        if g.show and (svg_blink or g.role not in ("eyes_open", "eyes_closed")):
            vis = bool(g.show.values[g.show.index(t)][0])
            if shut and not svg_blink and g.role in ("step", "blink_step"):
                vis = g.role == "blink_step"  # the flip-book's own shut eyes, in every step's place
        elif g.role == "eyes_open":
            vis = not shut
        elif g.role == "eyes_closed":
            vis = shut
        if g.fill:
            fl = g.fill.values[g.fill.index(t)][0]
        offset.append((ox, oy))
        shown.append(on and vis)
        fills.append(fl)
    return offset, shown, fills


def render(scene: Scene, t: int, svg_blink: bool = False, face_only: bool = False, shut: bool = False,
           blended: set[int] | None = None) -> bytes:
    """The scene colour of every pixel at t ms. The device blinks on its own
    clock, so it shows the open eyes, or the closed ones when `shut`; with
    `svg_blink` the eyes blink on the design's clock, as Chrome draws it.
    `face_only` leaves out everything outside the face's group."""
    px = bytearray(W * H)
    offset, shown, fills = place(scene, t, svg_blink, shut)
    in_face: list[bool] = []
    for g in scene.groups:
        in_face.append(g.role == "face" or (g.parent >= 0 and in_face[g.parent]))
    cx0, cy0, cw, ch = scene.clip
    for i, g in enumerate(scene.groups):
        if not shown[i] or (face_only and not in_face[i]):
            continue
        ox, oy = offset[i]
        for x, y, w, h, c in g.rects:
            color = fills[i] if c == INHERIT else c
            x0, y0 = max(cx0, x + ox), max(cy0, y + oy)
            x1, y1 = min(cx0 + cw, x + ox + w), min(cy0 + ch, y + oy + h)
            if color >= BLEND:
                for yy in range(y0, y1):
                    for xx in range(x0, x1):
                        px[yy * W + xx] = BLEND_TABLE.get(color - BLEND, px[yy * W + xx])
                        if blended is not None:
                            blended.add(yy * W + xx)
                continue
            if blended is not None:
                for yy in range(y0, y1):
                    blended.difference_update(range(yy * W + x0, yy * W + x1))
            for yy in range(y0, y1):
                px[yy * W + x0:yy * W + x1] = bytes([color]) * max(0, x1 - x0)
    return bytes(px)


def canvas_index(color: int) -> int:
    """The device palette's index for a scene colour."""
    return 0 if color == 0 else SCENE_BASE + color - 1


# ---- Writing -----------------------------------------------------------------


def emit(scenes: list[Scene], table: dict[tuple[int, int, int], int], meta: dict[tuple[int, int, int], tuple[int, int, int]],
         sources: dict[int, str], counts: dict[tuple[int, int], int]) -> str:
    # The designs share much: the same rectangles, the same tracks, the same
    # key times and values. Each is stored once, however many use it.
    tracks: list[str] = []
    track_of: dict[tuple, int] = {}
    keys: list[int] = []
    key_lists: dict[tuple[int, ...], int] = {}
    vals: list[int] = []
    val_lists: dict[tuple[int, ...], int] = {}
    # Groups and rectangles are stored once each too: a scene's groups, and a
    # group's list of rectangles, are indexes into them.
    groups: list[str] = []
    group_of: dict[str, int] = {}
    scene_groups: list[int] = []
    rects: list[str] = []
    rect_of: dict[str, int] = {}
    rect_slots: list[int] = []
    lists: dict[tuple, tuple[int, int]] = {}
    scene_rows: list[str] = []
    max_groups = 0
    for n, s in enumerate(scenes):
        g0 = len(scene_groups)
        for g in s.groups:
            ids = []
            for tr in (g.move, g.show, g.fill):
                # The device blinks on its own clock, so the design's blink
                # timing isn't kept.
                if tr is None or g.role in ("eyes_open", "eyes_closed"):
                    ids.append(0xFFFF)
                    continue
                kt = tuple(tr.keys)
                vt = tuple(x for v in tr.values for x in (v if tr.kind == "move" else v[:1]))
                if (tr.dur, kt, vt) not in track_of:
                    if kt not in key_lists:
                        key_lists[kt] = len(keys)
                        keys.extend(kt)
                    if vt not in val_lists:
                        val_lists[vt] = len(vals)
                        vals.extend(vt)
                    track_of[(tr.dur, kt, vt)] = len(tracks)
                    tracks.append(f"{{{tr.dur}, {len(tr.keys)}, {key_lists[kt]}, {val_lists[vt]}}}")
                ids.append(track_of[(tr.dur, kt, vt)])
            key = tuple(g.rects)
            if key not in lists:
                lists[key] = (len(rect_slots), len(g.rects))
                for x, y, w, h, c in g.rects:
                    assert 0 < w < 65536 and 0 < h < 256 and -32768 <= x < 32768
                    rect = f"{{{x}, {y}, {w}, {h}, {c}}}"
                    rect_of.setdefault(rect, len(rects))
                    if rect_of[rect] == len(rects):
                        rects.append(rect)
                    rect_slots.append(rect_of[rect])
            r0, rn = lists[key]
            parent = 0xFFFF if g.parent < 0 else g.parent
            group = (f"{{{g.tx}, {g.ty}, {parent}, {ROLES.index(g.role)}, {int(g.visible)}, "
                     f"{ids[0]}, {ids[1]}, {ids[2]}, {r0}, {rn}}}")
            group_of.setdefault(group, len(groups))
            if group_of[group] == len(groups):
                groups.append(group)
            scene_groups.append(group_of[group])
        max_groups = max(max_groups, len(s.groups))
        assert 0 < s.loop_ms() < 65536, "a loop fits a uint16_t"
        cx, cy, cw, ch = s.clip
        scene_rows.append(f"{{{g0}, {len(s.groups)}, {s.loop_ms()}, {cx}, {cy}, {cw}, {ch}}},  // {n}: {sources[n]}")
    assert all(-128 <= v <= 127 for v in vals) and all(k < 65536 for k in keys)
    assert len(tracks) < 0xFFFF and len(rect_slots) < 65536, "tracks and rectangle lists fit a group's indexes"
    assert len(groups) < 65536 and len(rects) < 65536, "groups and rectangles fit their indexes"
    assert len(COLORS.rgb) + SCENE_BASE - 1 <= 256, "the scene colours fit the palette"
    size = (len(rects) * 8 + len(rect_slots) * 2 + len(groups) * 18 + len(scene_groups) * 2 + len(tracks) * 12 + len(keys) * 2 + len(vals)
            + len(scenes) * 16 + len(BLENDS.pairs) * len(COLORS.rgb) + len(table) * 4 + len(counts) * 3)
    maxv = max(counts.values())

    def block(name: str, ctype: str, rows: list[str], per_line: int = 1) -> list[str]:
        # The colours are constexpr: the palette is worked out at compile time.
        kind = "constexpr" if name == "kColors" else "static const"
        out = [f"{kind} {ctype} {name}[{len(rows)}] = {{"]
        for i in range(0, len(rows), per_line):
            out.append("  " + ", ".join(rows[i:i + per_line]) + ",")
        out.append("};")
        return out

    lines = [
        "// Generated by characters/pixel/tools/facegen/facegen.py from the animation bank in",
        "// characters/pixel/design/boop-sound-bank-v4/. Do not edit.",
        f"// {len(table)} designs, {len(scenes)} scenes, {len(groups)} groups, {len(rects)} rectangles, "
        f"{len(tracks)} tracks, {len(COLORS.rgb)} colours: about {size // 1024 + 1} KB.",
        "#pragma once",
        "#include <cstdint>",
        "",
        "namespace render {",
        "namespace faces {",
        "",
        "// What the device does with a group besides drawing it (render/scene.cpp).",
        "enum Role : uint8_t { " + ", ".join("kRole" + "".join(w.title() for w in r.split("_")) for r in ROLES) + " };",
        "",
        "// The designs' colours: 0 is the black field, the canvas's 0, and colour i",
        "// is the palette's kSceneBase + i - 1 (render/palette.h).",
        f"constexpr int kSceneBase = {SCENE_BASE};",
        f"constexpr int kColorCount = {len(COLORS.rgb)};",
        "struct Color { uint8_t r, g, b; };",
    ]
    lines += block("kColors", "Color", [f"{{{r}, {g}, {b}}}" for r, g, b in COLORS.rgb], 6)
    blend_rows = []
    for k in range(len(BLENDS.pairs)):
        blend_rows.append("{" + ", ".join(str(BLEND_TABLE.get(k, d)) for d in range(len(COLORS.rgb))) + "}")
    lines += [
        f"constexpr uint8_t kInherit = {INHERIT};  // a rectangle's colour: its group's fill",
        f"// A rectangle's colour from kBlend on is translucent: each pixel it covers",
        f"// becomes kBlendOver[colour - kBlend][the colour beneath].",
        f"constexpr uint8_t kBlend = {BLEND};",
        f"constexpr int kBlendCount = {len(BLENDS.pairs)};",
        f"static const uint8_t kBlendOver[{max(1, len(BLENDS.pairs))}][{len(COLORS.rgb)}] = {{",
    ] + ["  " + r + "," for r in blend_rows] + ["};",
        "",
        "// A group moves and shows its rectangles and its child groups. Its",
        "// offset is its parent's plus (tx, ty) plus its move track's step; it",
        "// shows while its parent does and, with a show track, while that says so;",
        "// and it fills its kInherit rectangles with its fill track's colour, or",
        "// its parent's.",
        "struct Group {",
        "  int16_t tx, ty;",
        "  uint16_t parent;  // within the scene; 0xFFFF for the top",
        "  uint8_t role;",
        "  uint8_t visible;  // before any show track",
        "  uint16_t move, show, fill;  // into kTracks: tracks many groups can share; 0xFFFF for none",
        "  uint16_t rect0, rects;  // into kRectIdx: a list many groups can share",
        "};",
        "struct Rect {",
        "  int16_t x, y;  // from the group's offset",
        "  uint16_t w;",
        "  uint8_t h;",
        "  uint8_t color;",
        "};",
        "// A step-wise animation: key k holds from kKeys[key0 + k] ms into each",
        "// run of `dur` ms. Its values, from kValues[val0], are two a key (dx and",
        "// dy) to move, and one a key to show (1 or 0) or to fill (a colour).",
        "// Tracks with the same key times, or the same values, share them.",
        "struct Track {",
        "  uint16_t dur, n;",
        "  uint32_t key0, val0;",
        "};",
        "// A scene's groups are kGroups[kSceneGroups[group0]] on, parents first. Its `loopMs` is",
        "// how long it takes to play once through: its longest track but the",
        "// blink, which the device times itself. A moment's loops count these.",
        "// Nothing is drawn outside its clip.",
        "struct Scene {",
        "  uint32_t group0;",
        "  uint16_t groups;",
        "  uint16_t loopMs;",
        "  int16_t clipX, clipY, clipW, clipH;",
        "};",
        "",
        f"constexpr int kMaxGroups = {max_groups};",
        f"constexpr int kSceneCount = {len(scenes)};",
        "",
        "// The moods the designs draw, by name (render::pixelIndex looks the pack's",
        "// moods up here), and the states in render::SceneState's order.",
        f"constexpr int kMoodCount = {len(MOODS)};",
        f"constexpr const char* kMoodNames[{len(MOODS)}] = {{" + ", ".join(f'"{m}"' for m in MOODS) + "};",
        f"constexpr int kStateCount = {len(STATES)};",
        f"constexpr const char* kStateNames[{len(STATES)}] = {{" + ", ".join(f'"{s}"' for s in STATES) + "};",
        f"constexpr int kMaxVariants = {maxv};",
        f"constexpr int kDesignCount = {len(table)};",
        "// A design: a mood and state's variation, the scene it draws, and the host",
        "// fact it's for, if any, as render::Outcome and",
        "// render::StartCtx number them: task_complete's outcome, 1 success or",
        "// 2 failure, and starting's context, 1 new_task, 2 session,",
        "// 3 continuation or 4 compacted; 0 when it's for any.",
        "struct Design {",
        "  uint16_t scene;",
        "  uint8_t outcome, ctx;",
        "};",
        "",
    ]
    lines += block("kScenes", "Scene", scene_rows)
    first, rows_first, rows_count, design_rows = 0, [], [], []
    for m in range(len(MOODS)):
        row_first, row_count = [], []
        for st in range(len(STATES)):
            n = counts[(m, st)]
            row_first.append(str(first))
            row_count.append(str(n))
            for v in range(n):
                o, c, _ = meta[(m, st, v)]
                design_rows.append(f"{{{table[(m, st, v)]}, {o}, {c}}}")
            first += n
        rows_first.append("{" + ", ".join(row_first) + "},  // " + MOODS[m])
        rows_count.append("{" + ", ".join(row_count) + "},  // " + MOODS[m])
    assert first == len(table) < 65536
    lines += ["// Each mood and state's variations, in order: kVariants[m][s] designs from",
              "// kDesigns[kFirst[m][s]] on.",
              f"static const uint8_t kVariants[kMoodCount][kStateCount] = {{"] + ["  " + r for r in rows_count] + ["};"]
    lines += [f"static const uint16_t kFirst[kMoodCount][kStateCount] = {{"] + ["  " + r for r in rows_first] + ["};"]
    lines += block("kDesigns", "Design", design_rows, 8)
    lines += block("kGroups", "Group", groups, 2)
    lines += block("kSceneGroups", "uint16_t", [str(i) for i in scene_groups], 16)
    lines += block("kRects", "Rect", rects, 5)
    lines += block("kRectIdx", "uint16_t", [str(i) for i in rect_slots], 16)
    lines += block("kTracks", "Track", tracks, 6)
    lines += block("kKeys", "uint16_t", [str(k) for k in keys], 16)
    lines += block("kValues", "int8_t", [str(v) for v in vals], 32)
    lines += ["", "}  // namespace faces", "}  // namespace render", ""]
    return "\n".join(lines)


def tile_face(scene: Scene, shut: bool) -> bytes:
    """A tile's face: the design's face as it starts, its eyes open, or shut.
    A flip-book (V4) shuts them in a step of its own, whose face is the one
    tagged as its blink, so a shut tile shows that step's face."""
    if not shut or any(g.role == "eyes_open" for g in scene.groups):
        return render(scene, 0, face_only=True, shut=shut)
    blinks = [i for i, g in enumerate(scene.groups) if g.blink]
    for t in scene.step_times():
        _, shown, _ = place(scene, t, svg_blink=True, shut=False)
        if any(shown[i] for i in blinks):
            return render(scene, t, svg_blink=True, face_only=True)
    return render(scene, 0, face_only=True)


def tile_faces(scenes: list[Scene], table: dict[tuple[int, int, int], int]):
    """Each tile look's face at rest (the moment its first variation starts),
    open and shut, as rectangles of one colour each: the box they sit in,
    their colours as 0xRRGGBB, and by "mood/look" the base64 of five bytes a
    rectangle (x and y from the box's corner, width, height and colour)."""
    import base64

    faces: dict[str, tuple[str, str]] = {}
    boxes = []
    rects_of: dict[tuple[int, bool], list[tuple[int, int, int, int, int]]] = {}
    for mood, state in TILES:
        n = table[(MOODS.index(mood), STATES.index(state), 0)]
        for shut in (False, True):
            if (n, shut) in rects_of:
                continue
            px = tile_face(scenes[n], shut)
            out = []
            for color in sorted(set(px) - {0}):
                rows = []
                for y in range(H):
                    run, start = [], None
                    for x in range(W + 1):
                        on = x < W and px[y * W + x] == color
                        if on and start is None:
                            start = x
                        if not on and start is not None:
                            run.append((start, x))
                            start = None
                    rows.append(run)
                out += [(x, y, w, h, color) for x, y, w, h in merge_runs(rows, 0)]
            rects_of[(n, shut)] = out
            boxes += out
    x0 = min(r[0] for r in boxes)
    y0 = min(r[1] for r in boxes)
    x1 = max(r[0] + r[2] for r in boxes)
    y1 = max(r[1] + r[3] for r in boxes)
    assert x1 - x0 < 256 and y1 - y0 < 256
    used = sorted({r[4] for r in boxes})
    for mood, state in TILES:
        n = table[(MOODS.index(mood), STATES.index(state), 0)]
        enc = []
        for shut in (False, True):
            data = bytes(v for x, y, w, h, c in rects_of[(n, shut)] for v in (x - x0, y - y0, w, h, used.index(c)))
            enc.append(base64.b64encode(data).decode())
        faces[f"{mood}/{state}"] = (enc[0], enc[1])
    colors = [(r << 16) | (g << 8) | b for r, g, b in (COLORS.rgb[c] for c in used)]
    return (x0, y0, x1 - x0, y1 - y0), colors, faces


def emit_faces_json(scenes: list[Scene], table: dict[tuple[int, int, int], int],
                    meta: dict[tuple[int, int, int], tuple[int, int, int]], counts: dict[tuple[int, int], int]) -> str:
    """The Pixel pack's mac/faces.json (characters/CHARACTER.md §9): what
    the Mac needs of the pixel face. The popover's still faces (`box`,
    `colors`, `faces`), and each mood, state and variation's loop length,
    voice window and host fact (`designs`): the numbers faces.h and sfx.h
    give the device."""
    box, colors, faces = tile_faces(scenes, table)

    def design(m: int, st: int, v: int) -> dict:
        o, c, w = meta[(m, st, v)]
        d = {"ms": scenes[table[(m, st, v)]].loop_ms(), "voice_ms": w}
        if o:
            d["outcome"] = OUTCOMES[o]
        if c:
            d["ctx"] = CTXS[c]
        return d

    data = {
        "moods": MOODS,
        "states": STATES,
        "designs": {mood: [[design(m, st, v) for v in range(counts[(m, st)])] for st in range(len(STATES))]
                    for m, mood in enumerate(MOODS)},
        "box": list(box),
        "colors": colors,
        "faces": {k: {"open": o, "shut": s} for k, (o, s) in faces.items()},
    }
    return json.dumps(data, indent=1) + "\n"


def emit_frames(frames: list[tuple[int, int, int, int, int]]) -> str:
    lines = [
        "// Generated by characters/pixel/tools/facegen/facegen.py. Do not edit.",
        "// Each design at moments away from its steps, as facegen draws it for",
        "// the device: CRC-32 of the palette index of every pixel.",
        "#pragma once",
        "#include <cstdint>",
        "",
        "struct FacegenFrame {",
        "  uint8_t mood, state, variant;",
        "  uint32_t t, crc;",
        "};",
        f"static const FacegenFrame kFacegenFrames[{len(frames)}] = {{",
    ]
    for m, s, v, t, crc in frames:
        lines.append(f"  {{{m}, {s}, {v}, {t}, 0x{crc:08x}u}},  // {MOODS[m]} {STATES[s]} {v + 1}")
    lines += ["};", ""]
    return "\n".join(lines)


# ---- Checking against Chrome ---------------------------------------------------


def chrome_frames(files: list[Path], t_ms: int, tmp: Path) -> list[list[int]]:
    """Each file drawn by Chrome at t ms, as RGB565."""
    from PIL import Image

    cols = 8
    rows = (len(files) + cols - 1) // cols
    cells = []
    for i, f in enumerate(files):
        svg = f.read_text().split("?>")[-1]
        cells.append(f'<div style="position:absolute;left:{i % cols * W}px;top:{i // cols * H}px;width:{W}px;height:{H}px">{svg}</div>')
    page = tmp / f"t{t_ms}.html"
    page.write_text(
        "<!doctype html><html><body style='margin:0;background:#000'>" + "".join(cells) +
        f"<script>for(const s of document.querySelectorAll('svg')){{s.setAttribute('data-motion','on');"
        f"s.pauseAnimations();s.setCurrentTime({t_ms / 1000});}}</script></body></html>")
    shot = tmp / f"t{t_ms}.png"
    cmd = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
           f"--window-size={cols * W},{rows * H}", f"--screenshot={shot}", page.as_uri()]
    # Chrome's output isn't captured, since a helper it leaves running would
    # hold the pipe open; and it gets no --user-data-dir, whose first run
    # hangs headless Chrome on macOS. It still hangs now and then.
    for attempt in (1, 2, 3):
        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
            break
        except subprocess.TimeoutExpired:
            if attempt == 3:
                raise
    img = Image.open(shot).convert("RGB")
    out = []
    for i in range(len(files)):
        crop = img.crop((i % cols * W, i // cols * H, i % cols * W + W, i // cols * H + H))
        out.append([rgb565(p) for p in crop.get_flattened_data()])
    return out


def near565(a: int, b: int) -> bool:
    """At most one RGB565 step apart in each channel: how close a blended
    pixel must come to Chrome's, whose rounding inside nested groups isn't
    reproduced exactly."""
    return (abs((a >> 11) - (b >> 11)) <= 1 and abs(((a >> 5) & 63) - ((b >> 5) & 63)) <= 1
            and abs((a & 31) - (b & 31)) <= 1)


def check(scenes: list[Scene], files: dict[int, Path]) -> None:
    by_time: dict[int, list[int]] = {}
    for n in sorted(files):
        for t in scenes[n].samples():
            by_time.setdefault(t, []).append(n)
    compared = 0
    pal = [rgb565(c) for c in COLORS.rgb]
    bad_scenes: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        for t, ns in sorted(by_time.items()):
            for k in range(0, len(ns), 48):
                chunk = ns[k:k + 48]
                got = chrome_frames([files[n] for n in chunk], t, Path(tmp))
                for n, chrome in zip(chunk, got):
                    blended: set[int] = set()
                    mine = [pal[c] for c in render(scenes[n], t, svg_blink=True, blended=blended)]
                    wrong = [i for i, (a, b) in enumerate(zip(mine, chrome)) if a != b
                             and not (i in blended and near565(a, b))]
                    if wrong:
                        bad = len(wrong)
                        first = wrong[0]
                        bad_scenes.append(f"{files[n].name} at {t} ms: {bad} pixels differ from Chrome, "
                                          f"first at ({first % W}, {first // W})")
                    compared += 1
    if bad_scenes:
        raise SystemExit("\n".join(bad_scenes[:40]) + f"\n{len(bad_scenes)} of {compared} frames differ")
    print(f"check: {compared} frames of {len(scenes)} scenes match Chrome pixel for pixel "
          f"(blended pixels within one RGB565 step)")


def export() -> list[dict]:
    """Runs the bank's generator (bank.mjs) into build/ and returns its
    designs in the device's order, after checking that the older moods'
    come out as they were, and lists them in design/manifest.json."""
    try:
        subprocess.run(["node", str(HERE / "bank.mjs"), "--out", str(BUILD)], check=True, stdout=subprocess.DEVNULL)
    except FileNotFoundError:
        raise SystemExit("facegen needs node: the bank's generator is JavaScript")
    designs = json.loads((BUILD / "designs.json").read_text())
    designs.sort(key=lambda a: (MOODS.index(a["mood"]), STATES.index(a["state"]), a["variation"]))
    # The older moods' designs were captured before the new moods came
    # (the bank's qa/v3-fingerprints.json): the first pack's (V2), which the
    # device drew before, and the newer states' (V3). Each must come out
    # byte for byte as it was. Their COMPACTED start card came after the
    # capture, so it has no fingerprint there.
    prints = json.loads((BANK / "qa" / "v3-fingerprints.json").read_text())["hashes"]
    older = [a for a in designs if a["dialect"] != "v4" and a.get("ctx") != "compacted"]
    changed = [a["id"] for a in older
               if hashlib.sha256((BUILD / a["svg"]).read_bytes()).hexdigest() != prints.get(a["id"], {}).get("svg")]
    if changed or len(older) != len(prints):
        raise SystemExit(f"the bank's older designs changed: {', '.join(changed) or 'their number'} "
                         "(characters/pixel/design/boop-sound-bank-v4/qa/check.mjs says more)")
    rows = [json.dumps({k: a[k] for k in ("id", "mood", "state", "variation", "name", "seconds", "outcome", "ctx",
                                          "voiceMs", "dialect") if k in a}) for a in designs]
    MANIFEST.write_text(
        "{\n"
        ' "about": "The device\'s designs, from the animation bank\'s generator '
        '(characters/pixel/design/boop-sound-bank-v4/), in the device\'s order. Written by facegen.py; do not edit.",\n'
        f' "moods": {json.dumps(MOODS)},\n'
        f' "states": {json.dumps(STATES)},\n'
        ' "designs": [\n  ' + ",\n  ".join(rows) + "\n ]\n}\n")
    v2 = sum(a["dialect"] == "v2" for a in designs)
    print(f"bank: {len(designs)} designs; the older moods' {v2} V2 and {len(older) - v2} V3 come out as captured")
    return designs


def load() -> tuple[list[Scene], dict[tuple[int, int, int], int], dict[tuple[int, int, int], tuple[int, int, int]],
                    dict[int, str], dict[int, Path], dict[tuple[int, int], int]]:
    scenes: list[Scene] = []
    seen: dict[str, int] = {}
    table: dict[tuple[int, int, int], int] = {}  # mood, state, variation (from 0) → scene
    meta: dict[tuple[int, int, int], tuple[int, int, int]] = {}  # the same → outcome and context, as numbered, and voice window
    sources: dict[int, str] = {}
    files: dict[int, Path] = {}
    counts: dict[tuple[int, int], int] = {}  # mood, state → how many variations
    for a in export():
        m, s, v = MOODS.index(a["mood"]), STATES.index(a["state"]), a["variation"] - 1
        path = BUILD / a["svg"]
        scene = read_scene(path)
        k = scene.key()
        if k not in seen:
            seen[k] = len(scenes)
            scenes.append(scene)
            sources[seen[k]] = path.name
            files[seen[k]] = path
        table[(m, s, v)] = seen[k]
        meta[(m, s, v)] = (OUTCOMES.index(a.get("outcome")), CTXS.index(a.get("ctx")), a["voiceMs"])
        counts[(m, s)] = max(counts.get((m, s), 0), v + 1)
    for m in range(len(MOODS)):
        for s in range(len(STATES)):
            n = counts.get((m, s), 0)
            assert n and all((m, s, v) in table for v in range(n)), f"{MOODS[m]} {STATES[s]}: every variation"
    BLEND_TABLE.freeze(scenes)
    return scenes, table, meta, sources, files, counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true", help="compare every scene with Chrome's rendering first")
    args = parser.parse_args()
    scenes, table, meta, sources, files, counts = load()
    if args.check:
        check(scenes, files)
    # canvas_index as a table, for bytes.translate to map a whole frame at
    # once: a frame's pixels are scene colours, so the padding is never read.
    canvas = bytes(canvas_index(c) for c in range(len(COLORS.rgb))).ljust(256, b"\0")
    frames = []
    for (m, s, v), n in sorted(table.items()):
        if sources[n] != f"{MOODS[m]}.{STATES[s]}.{v + 1:02d}.svg":
            continue  # a shared design, checked once
        for t in scenes[n].samples():
            frames.append((m, s, v, t, zlib.crc32(render(scenes[n], t).translate(canvas))))
    OUT.write_text(emit(scenes, table, meta, sources, counts))
    FACES_JSON.parent.mkdir(parents=True, exist_ok=True)
    FACES_JSON.write_text(emit_faces_json(scenes, table, meta, counts))
    FRAMES.parent.mkdir(parents=True, exist_ok=True)
    FRAMES.write_text(emit_frames(frames))
    print(f"wrote {OUT.relative_to(REPO)} ({len(table)} designs, {len(scenes)} scenes), "
          f"{FRAMES.relative_to(REPO)} ({len(frames)} frames), {FACES_JSON.relative_to(REPO)} "
          f"and {MANIFEST.relative_to(REPO)}")


if __name__ == "__main__":
    sys.exit(main())
