"""Canvas screenshots as PNGs, exact pixel diffs between them, and contact
sheets of frames."""
from __future__ import annotations

from pathlib import Path
import struct

from PIL import Image, ImageDraw

# A screenshot as Link.shot() returns it: 256 RGB565 palette entries, one
# index per pixel, and the (width, height) the device reported.
Shot = tuple[list[int] | None, bytes, tuple[int, int]]


def rgb888(c: int) -> tuple[int, int, int]:
    r, g, b = (c >> 11) & 31, (c >> 5) & 63, c & 31
    return (r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)


def to_image(shot: Shot) -> Image.Image:
    palette, pixels, size = shot
    if palette is None:
        rgb = bytes(channel for (color,) in struct.iter_unpack("<H", pixels) for channel in rgb888(color))
        return Image.frombytes("RGB", size, rgb)
    img = Image.frombytes("P", size, pixels)
    flat: list[int] = []
    for c in palette:
        flat.extend(rgb888(c))
    img.putpalette(flat)
    return img.convert("RGB")


def save_shot(shot: Shot, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    to_image(shot).save(path)
    return path


def diff(a: Path, b: Path, out: Path | None = None) -> int:
    """Number of differing pixels. If any differ and `out` is given, writes a
    diff image there: a in grey with the changed pixels in magenta. Pictures
    of different sizes differ everywhere, with no diff image."""
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return max(ia.width * ia.height, ib.width * ib.height)
    pa, pb = ia.tobytes(), ib.tobytes()
    changed = [i // 3 for i in range(0, len(pa), 3) if pa[i : i + 3] != pb[i : i + 3]]
    if out is not None and changed:
        hl = ia.convert("L").convert("RGB")
        px = hl.load()
        w = ia.size[0]
        for i in changed:
            px[i % w, i // w] = (255, 0, 255)
        out.parent.mkdir(parents=True, exist_ok=True)
        hl.save(out)
    return len(changed)


def sheet(frames: list, out: Path, columns: int = 8, width: int | None = 200, label: int = 16, pad: int = 0,
          background="white", ink="black") -> Path:
    """A contact sheet of frames, each (its label, an image or its file):
    `columns` a row, each `width` px wide (as it is, with None) under its
    label, with `pad` px either side and below."""
    def drawn(frame, size=None):
        if not isinstance(frame, Image.Image):
            with Image.open(frame) as im:
                return drawn(im, size)
        rgb = frame.convert("RGB")
        return rgb.resize(size) if size and rgb.size != size else rgb

    first = drawn(frames[0][1])
    w, h = first.size if width is None else (width, max(1, round(first.height * width / first.width)))
    cw, ch = w + 2 * pad, label + h + pad
    image = Image.new("RGB", (columns * cw, -(-len(frames) // columns) * ch), background)
    draw = ImageDraw.Draw(image)
    for i, (text, frame) in enumerate(frames):
        x, y = (i % columns) * cw, (i // columns) * ch
        image.paste(drawn(frame, (w, h)), (x + pad, y + label))
        draw.text((x + pad + 3, y + 2), text, fill=ink)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    return out
