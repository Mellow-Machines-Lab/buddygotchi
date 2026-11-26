"""Records Boop's sentences with ElevenLabs, from the bank's plan.

The plan is the bank's plans/sentences.json (character/design/assets/
boop-voice-v1/): each sentence's spoken words and the deliveries to record
it in (B bright, F flat, G glum), each delivery's bank mood, audio tag and
acting direction. A take is one sentence in one delivery, its id
`sentence.<id>__<mood>`. Run from anywhere, python 3.9, nothing to install:

    python3 characters/boop/tools/voicegen/record.py --tier 1 --dry-run
    ELEVENLABS_API_KEY=... python3 characters/boop/tools/voicegen/record.py --tier 1 --archive /abs/path/outside/the/repo

--dry-run prints each request (its script, direction and characters) and
the total, and calls nothing. --tier N records tiers 1 to N, --only ID,ID
only those sentences (or takes). A take the manifest already has is
skipped, so a rerun costs nothing and a run cut short goes on where it
stopped; --redo ID,ID records those again, in their old one's place.

The key is ELEVENLABS_API_KEY, else the one line of ~/.config/boop/
elevenlabs.key, which only you may read (it refuses a file group or others
can). It is never printed or logged.

Each fresh take also goes to a plain listening folder (--listen, default
<archive>/listen): the MP3 as ElevenLabs sent it and the 8-bit WAV made
from it, so you can judge them before recording the rest.

A real run asks ElevenLabs for each take with the bank's own settings
(the plan's `voiceId` and `modelId`, seed 42, language auto, no other
voice settings; the acting is the script's leading tag), keeps the MP3
master in --archive (the bank keeps its masters outside the repo), makes
the bank's `original` texture from it with tools/compress.py's recipe
(macOS afconvert to 16-bit 11.025 kHz, then 8-bit) and the `robot-soft`
one voicegen builds from, and files the take in the manifest with the
sentence as its entry (`sentence.<id>`), its delivery and `reviewStatus:
unreviewed-by-ear`. The robot-soft chain is provenance.json's words made
small (`robot_soft`): its original code isn't in this repo, and no
original/robot-soft pair is, so it can't be proven the same; listen first.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
import wave
from array import array
from pathlib import Path

BANK = Path(__file__).resolve().parents[2] / "design" / "assets" / "boop-voice-v1"
PLAN = BANK / "plans" / "sentences.json"
API = "https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_44100_128"
KEY = "ELEVENLABS_API_KEY"
KEY_FILE = Path.home() / ".config" / "boop" / "elevenlabs.key"
DOLLARS_PER_1000 = 0.08  # ElevenLabs' price a thousand characters, as the owner gave it
RECIPE = "pcm-u8-mono-11025-coreaudio-v1"
SOFT_RECIPE = "pcm-u8-mono-11025, robot-soft chain from record.py"


def takes(plan: dict, tier: int) -> list[dict]:
    """Every take of the plan's sentences up to `tier`: one a delivery."""
    out = []
    for s in plan["sentences"]:
        if s["tier"] > tier:
            continue
        for d in s["deliveries"]:
            delivery = plan["deliveries"][d]
            out.append({"id": f"sentence.{s['id']}__{delivery['mood']}", "sentence": s["id"], "tier": s["tier"], "delivery": d,
                        "mood": delivery["mood"], "script": f"{delivery['tag']} {s['spoken']}",
                        "direction": delivery["direction"]})
    return out


# The bank's own settings, so new takes match the old: one seed for every
# take, language auto (none sent), no voice settings but the defaults.
SEED = 42


def request(take: dict, key: str, voice: str, model: str) -> urllib.request.Request:
    """The text-to-speech request for one take: only its script (the acting
    as its leading tag, `[happy] Done! All yours.`), the model and the
    bank's seed, with the key in its header."""
    body = json.dumps({"text": take["script"], "model_id": model, "seed": SEED}).encode()
    return urllib.request.Request(API.format(voice=voice), data=body, method="POST",
                                  headers={"xi-api-key": key, "Content-Type": "application/json", "Accept": "audio/mpeg"})


def dry_run(todo: list[dict], out=sys.stdout) -> int:
    """Prints each take's request, and returns the characters in all."""
    total = 0
    for t in todo:
        n = len(t["script"])
        total += n
        print(f"{t['id']}  ({t['delivery']}, {n} chars)\n  script:    {t['script']}\n  direction: {t['direction']}", file=out)
    print(f"{len(todo)} takes, {total} characters, about ${total * DOLLARS_PER_1000 / 1000:.2f}", file=out)
    return total


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pcm8(master: Path, target: Path) -> dict:
    """The bank's `original` texture from an MP3 master: afconvert to 16-bit
    mono 11.025 kHz, then 8-bit unsigned, as tools/compress.py does; with
    the 16-bit samples as floats, for the robot-soft chain."""
    with tempfile.TemporaryDirectory(prefix="boop-record-") as d:
        decoded = Path(d) / "decoded.wav"
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@11025", "-c", "1", "-r", "127", str(master), str(decoded)], check=True)
        with wave.open(str(decoded)) as w:
            x = array("h", w.readframes(w.getnframes()))
    if sys.byteorder != "little":
        x.byteswap()
    target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(11025)
        w.writeframes(bytes(max(0, min(255, round(v / 256) + 128)) for v in x))
    return {"seconds": len(x) / 11025, "samples": [v / 32768 for v in x]}


class KeyError_(Exception):
    """No key to use, and why, never the key itself."""


def read_key(environment: dict, key_file: Path = KEY_FILE) -> str:
    """The key: the environment's, else the key file's one line, which
    only its owner may read."""
    key = environment.get(KEY, "").strip()
    if key:
        return key
    if not key_file.is_file():
        raise KeyError_(f"set {KEY}, or put the key in {key_file}")
    if key_file.stat().st_mode & 0o077:
        raise KeyError_(f"{key_file} can be read by others: chmod 600 it")
    key = key_file.read_text().strip()
    if not key:
        raise KeyError_(f"{key_file} is empty")
    return key


def pick(plan: dict, tier: int, have: set, only: list, redo: list) -> list:
    """The takes to record: `only`'s sentences or takes if any, else tiers
    1 to `tier`, but those the manifest has; and `redo`'s, again."""
    def named(t: dict, ids: list) -> bool:
        return t["id"] in ids or t["id"][len("sentence."):] in ids or t["sentence"] in ids
    every = takes(plan, 99)
    scope = [t for t in every if named(t, only)] if only else [t for t in every if t["tier"] <= tier]
    again = [t for t in every if named(t, redo)]
    return again + [t for t in scope if t["id"] not in have and t not in again]


# The robot-soft chain, as provenance.json words it: 150 Hz high-pass; 8%
# mild saturation; 8% 12-bit/sample-hold texture; 12% 92 Hz ring
# modulation; 4.2 kHz low-pass; then under rms 0.07 and peak 0.55. Its
# original code isn't in this repo, so this is that description made
# small, at the bank's 11.025 kHz; no original/robot-soft pair is kept to
# prove it the same.
RATE = 11025
HIGH_PASS, LOW_PASS = 150.0, 4200.0
SATURATION, HOLD, RING = 0.08, 0.08, 0.12
RING_HZ, HOLD_SAMPLES, HOLD_BITS = 92.0, 2, 12
RMS_CEILING, PEAK_CEILING = 0.07, 0.55


def biquad(x: list, kind: str, hz: float) -> list:
    """A Butterworth second-order high- or low-pass (RBJ's cookbook)."""
    import math
    w = 2 * math.pi * hz / RATE
    a = math.sin(w) / math.sqrt(2)
    c = math.cos(w)
    if kind == "high":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    y, x1, x2, y1, y2 = [], 0.0, 0.0, 0.0, 0.0
    for v in x:
        out = (b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1, y2, y1 = x1, v, y1, out
        y.append(out)
    return y


def robot_soft(x: list) -> list:
    """The robot-soft texture of `x` (floats at RATE, -1 to 1)."""
    import math
    y = biquad(x, "high", HIGH_PASS)
    y = [(1 - SATURATION) * v + SATURATION * math.tanh(2 * v) / math.tanh(2) for v in y]
    step = 2 ** (HOLD_BITS - 1)
    held = [round(y[i - i % HOLD_SAMPLES] * step) / step for i in range(len(y))]
    y = [(1 - HOLD) * v + HOLD * h for v, h in zip(y, held)]
    y = [(1 - RING) * v + RING * v * math.sin(2 * math.pi * RING_HZ * i / RATE) for i, v in enumerate(y)]
    y = biquad(y, "low", LOW_PASS)
    rms = math.sqrt(sum(v * v for v in y) / len(y)) if y else 0.0
    peak = max((abs(v) for v in y), default=0.0)
    gain = min(RMS_CEILING / rms if rms else 1.0, PEAK_CEILING / peak if peak else 1.0)
    return [v * gain for v in y]


def write_u8(samples: list, target: Path) -> None:
    """8-bit unsigned mono WAV at RATE, as the bank's files are."""
    target.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(target), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(RATE)
        w.writeframes(bytes(max(0, min(255, round(v * 128) + 128)) for v in samples))


def record(todo: list[dict], plan: dict, key: str, archive: Path, bank: Path = BANK, opener=urllib.request.urlopen,
           listen: Path | None = None) -> int:
    """Records each take, files it in the manifest as it comes (a retake in
    its old one's place), copies it to `listen`, and returns how many it
    recorded."""
    manifest_file = bank / "manifest.json"
    manifest = json.loads(manifest_file.read_text())
    done = 0
    for t in todo:
        with opener(request(t, key, plan["voiceId"], plan["modelId"])) as answer:
            audio = answer.read()
        master = archive / "masters" / f"{t['id']}.mp3"
        master.parent.mkdir(parents=True, exist_ok=True)
        master.write_bytes(audio)
        relative = f"audio-pcm8/original/{t['id']}.wav"
        soft = f"audio-pcm8/robot-soft/{t['id']}.wav"
        decoded = pcm8(master, bank / relative)
        write_u8(robot_soft(decoded["samples"]), bank / soft)
        if listen:
            listen.mkdir(parents=True, exist_ok=True)
            (listen / master.name).write_bytes(audio)
            (listen / f"{t['id']}.original.wav").write_bytes((bank / relative).read_bytes())
            (listen / f"{t['id']}.robot-soft.wav").write_bytes((bank / soft).read_bytes())
        manifest["recordings"] = [r for r in manifest["recordings"] if r["id"] != t["id"]]
        manifest["recordings"].append({
            "id": t["id"], "entryId": f"sentence.{t['sentence']}", "delivery": t["delivery"], "mood": t["mood"],
            "moodStatus": "intended; listening review pending", "variant": "contained", "script": t["script"],
            "seconds": decoded["seconds"], "routineDurationEligible": True, "reviewStatus": "unreviewed-by-ear",
            "performanceId": t["id"][len("sentence."):], "sourceBatch": "sentences",
            "generation": {"voiceId": plan["voiceId"], "modelId": plan["modelId"], "seed": SEED, "language": "auto"},
            "master": {"sha256": hashlib.sha256(audio).hexdigest()},
            "files": {texture: {"path": path, "bytes": (bank / path).stat().st_size, "sha256": sha(bank / path), "recipe": recipe}
                      for texture, path, recipe in (("original", relative, RECIPE), ("robot-soft", soft, SOFT_RECIPE))},
        })
        tmp = manifest_file.with_suffix(".tmp")
        tmp.write_text(json.dumps(manifest, indent=1) + "\n")
        tmp.replace(manifest_file)
        done += 1
        print(f"recorded {t['id']}")
    return done


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tier", type=int, default=1, help="record tiers 1 to this (default 1)")
    ap.add_argument("--dry-run", action="store_true", help="print each request and the total; call nothing")
    ap.add_argument("--only", default="", metavar="ID,ID", help="only these sentences or takes")
    ap.add_argument("--redo", default="", metavar="ID,ID", help="record these sentences or takes again")
    ap.add_argument("--archive", type=Path, help="where the MP3 masters go, outside the repo (a real run needs it)")
    ap.add_argument("--listen", type=Path, help="the listening folder (default <archive>/listen)")
    args = ap.parse_args(argv)
    plan = json.loads(PLAN.read_text())
    have = {r["id"] for r in json.loads((BANK / "manifest.json").read_text())["recordings"]}
    split = lambda ids: [i for i in ids.split(",") if i]
    todo = pick(plan, args.tier, have, split(args.only), split(args.redo))
    if args.dry_run:
        dry_run(todo)
        return 0
    try:
        key = read_key(dict(os.environ))
    except KeyError_ as why:
        print(f"record: {why}", file=sys.stderr)
        return 2
    if not args.archive or not args.archive.is_absolute() or BANK.parents[4] in args.archive.resolve().parents:
        print("record: --archive must be an absolute folder outside the repo", file=sys.stderr)
        return 2
    n = record(todo, plan, key, args.archive, listen=args.listen or args.archive / "listen")
    print(f"record: {n} takes recorded. Make their robot-soft texture, then run voicegen.py.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
