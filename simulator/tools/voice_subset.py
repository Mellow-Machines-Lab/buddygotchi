#!/usr/bin/env python3
"""Cuts a voice pack down to the takes a demo says, for a page to fetch.

    simulator/tools/voice_subset.py RECORDING.json [--pack VOICE.bin] --out demo-voice.bin

A whole voice is tens of megabytes; a demo says a handful of takes. The
recording lists them (`takes`, DemoRecording). The pack that comes out is
one the board reads like any other (firmware/src/voice/player.cpp): the
same header and version, an index of only those takes, and their mouths
and samples. A take the pack doesn't have stops it.
"""
import argparse
import json
import os
import struct
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MAGIC = b"BOOPVOX1"
# The pack's layout, as voice/player.cpp reads it: a 64-byte header (magic,
# version, count, record size, where the index is, rate, mouth ms), then a
# 128-byte record a take, sorted by id (id, text, samples at, their length,
# mouth at, its frames), then the mouths and samples.
HEADER = struct.Struct("<8s16sIIIII20x")
RECORD = struct.Struct("<72s36sIIII4x")


def chosen_voice() -> Path:
    """The chosen character pack's voice (characters/CHARACTER.md §8): the
    pack is `BOOP_CHARACTER`'s, else the one last staged
    (.character-build/pack), else Pixel."""
    staged = REPO / ".character-build" / "pack"
    pack = os.environ.get("BOOP_CHARACTER") or (staged.read_text().strip() if staged.exists() else REPO / "characters" / "pixel")
    return Path(pack) / "voice" / "voice.bin"


def subset(pack: bytes, ids: list) -> bytes:
    magic, version, count, record_size, index_at, rate, mouth_ms = HEADER.unpack_from(pack)
    if magic != MAGIC or record_size != RECORD.size:
        raise SystemExit("voice_subset: not a voice pack this tool knows")
    have = {}
    for i in range(count):
        record = RECORD.unpack_from(pack, index_at + i * RECORD.size)
        have[record[0].rstrip(b"\0")] = record
    missing = [i for i in ids if i.encode() not in have]
    if missing:
        raise SystemExit(f"voice_subset: the pack has no take {', '.join(missing)}")
    wanted = sorted({i.encode() for i in ids})  # the board finds a take by its place in the order
    at = HEADER.size + RECORD.size * len(wanted)
    records, data = [], []
    for take in wanted:
        tid, text, samples_at, samples, mouth_at, frames = have[take]
        records.append(RECORD.pack(tid, text, at + frames, samples, at, frames))
        data += [pack[mouth_at:mouth_at + frames], pack[samples_at:samples_at + samples]]
        at += frames + samples
    return HEADER.pack(MAGIC, version, len(wanted), RECORD.size, HEADER.size, rate, mouth_ms) + b"".join(records) + b"".join(data)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("recording", type=Path, nargs="+", help="a demo's recording; several share one pack")
    ap.add_argument("--pack", type=Path, default=chosen_voice(), help="the whole voice (the chosen character pack's voice/voice.bin)")
    ap.add_argument("--out", type=Path, required=True, help="the pack to write")
    args = ap.parse_args()
    ids = []
    for recording in args.recording:
        ids += json.loads(recording.read_text())["takes"]
    if not ids:
        print("voice_subset: the demo says nothing, so it needs no voice")
        return 0
    out = subset(args.pack.read_bytes(), ids)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(out)
    print(f"voice_subset: {len(set(ids))} takes, {len(out)} B → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
