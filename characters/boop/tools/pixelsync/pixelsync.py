#!/usr/bin/env python3
"""Copies what Boop's pack takes from Pixel's, so the pack stands alone.

    python3 characters/boop/tools/pixelsync/pixelsync.py [--check]

Boop wears Pixel's face on the CYD board, so its pack carries its own copy
of that face: the firmware's pixel renderer, faces and sound effects, the
Mac's list of the face's designs, and the Character Studio's preview of it.
They're Pixel's built files, copied as they are; nothing here is edited by
hand. Rerun this when Pixel's change. --check copies nothing: it says
which of Boop's differ, and fails if any do, as the pack's tests
(tests/tools/) do.
"""
from __future__ import annotations

import filecmp
import shutil
import sys
from pathlib import Path

BOOP = Path(__file__).resolve().parents[2]
PIXEL = BOOP.parent / "pixel"

# Pixel's firmware files that Boop has its own of.
OWN = {"firmware/include/moods.h", "firmware/src/render/make_face.cpp"}
# The studio's preview of the pixel face: Pixel's file, and where Boop keeps it.
STUDIO = {
    "design/boop-sound-bank-v4/dist/boop-runtime.js": "studio/pixel/boop-runtime.js",
    "design/boop-sound-bank-v4/coverage.json": "studio/pixel/coverage.json",
    "studio/adapter.js": "studio/pixel/adapter.js",
    "studio/adapter.css": "studio/pixel/adapter.css",
    "studio/icon.svg": "studio/pixel/icon.svg",
}


def copies() -> dict[str, str]:
    """Each of Pixel's files Boop copies, and its place in Boop's pack."""
    firmware = sorted(p.relative_to(PIXEL).as_posix() for p in (PIXEL / "firmware").rglob("*") if p.is_file())
    out = {name: name for name in firmware if name not in OWN}
    out["mac/faces.json"] = "mac/faces.json"
    out.update(STUDIO)
    return out


def stale() -> list[str]:
    """Boop's copies that are missing or differ from Pixel's."""
    return [to for source, to in copies().items()
            if not (BOOP / to).is_file() or not filecmp.cmp(PIXEL / source, BOOP / to, shallow=False)]


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    if not (PIXEL / "character.json").is_file():
        print(f"pixelsync: no Pixel pack at {PIXEL}", file=sys.stderr)
        return 1
    old = stale()
    if "--check" in argv:
        for name in old:
            print(f"PIXELSYNC FAIL: {name} isn't Pixel's: run characters/boop/tools/pixelsync/pixelsync.py", file=sys.stderr)
        if not old:
            print(f"PIXELSYNC PASS: {len(copies())} files are Pixel's")
        return 1 if old else 0
    for source, to in copies().items():
        (BOOP / to).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PIXEL / source, BOOP / to)
    print(f"pixelsync: {len(copies())} files, {len(old)} changed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
