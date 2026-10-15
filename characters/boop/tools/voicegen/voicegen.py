"""Builds Boop's voice from the recorded voice bank.

The bank, characters/boop/design/assets/boop-voice-v1/, has whole recorded
takes, each a word, a sound, a phrase or a swear performed in one mood.
Every take in its manifest is read from its robot-soft WAV (8-bit,
11.025 kHz), the near-silence around it trimmed, saturated and normalised
so it's as loud on the small speaker, and stored as 8-bit unsigned
samples. Two files come out, into one character pack, Pixel's (PACK_DIR),
checked in there; Boop's pack uses Pixel's voice (characters/CHARACTER.md
§6). Rerun this whenever the bank or a mapping changes:

    python3 characters/boop/tools/voicegen/voicegen.py [--card /Volumes/CARD] [--wav-dir DIR]

- voice/voice.bin: the pack the board plays from its SD card
  (at /boop/voice.bin): every take's samples, bubble text
  and mouth (open or shut every 20 ms), found by id. `--card` also copies
  it onto a mounted card.
- mac/takes.tsv (characters/CHARACTER.md §8): each take's id,
  text, part and answer, kind, the moods it plays in, the finish it needs
  and its length, which the Mac picks from, and the pack's version, which
  the board reports.

The recordings stay here, in Boop's pack; Pixel's holds only the two
built files, so it stands alone.

Every take answers one of the brain's two questions: how Boop feels
(`say.feeling`) or what NOW is about (`say.about`),
by the bank's intent (FEELING, ABOUT), or for a few entries by their
words (ABOUT_OF_ENTRY): the greetings are the `hello` topic. Needs you's
other takes (`attention`) are in the pack, but Boop never says them. Six takes were recorded in
moods Boop doesn't have; MOOD_OF gives them one, by the owner's word
(2026-09-29).

The takes were recorded in 13 of the universal moods. Every mood needs
takes, so each of the others plays the takes of the one it borrows, by
the temporary table in characters/pixel/tools/borrowed.json, which also
says whose faces Pixel's art lends: a take's moods are the one it was
recorded in, then those that borrow it. Only takes.tsv says so; the
audio and the version don't change.

`--wav-dir` also writes every converted take as a WAV, for listening.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import shutil
import struct
import unicodedata
import wave
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
BANK = REPO / "characters" / "boop" / "design" / "assets" / "boop-voice-v1"
# The character pack the voice is built into; any other uses it from there.
PACK_DIR = REPO / "characters" / "pixel"
PACK, TABLE = "voice/voice.bin", "mac/takes.tsv"  # in a character pack
# TEMPORARY: the moods with no takes of their own, and the one each borrows.
BORROWS = json.loads((REPO / "characters" / "pixel" / "tools" / "borrowed.json").read_text())["borrows"]
CARD_PATH = "boop/voice.bin"  # where the board looks on its card

RATE = 11025        # the takes' sample rate on the board
TEXTURE = "robot-soft"
TRIM_DB = 45        # near-silence: 10 ms frames quieter than this, in dBFS
PAD_BEFORE_MS = 30  # kept before the first sound and after the last, so
PAD_AFTER_MS = 80   # breaths and decays aren't clipped
DRIVE = 2.2         # soft saturation before normalising: louder on a tiny speaker
PEAK = 0.92
MOUTH_MS = 20       # the mouth's resolution
MOUTH_OPEN = 0.2    # open while a frame is this loud, of the take's loudest frame

# The pack's layout, little-endian: a 64-byte header, then an
# index of fixed-size records sorted by id, so the board can find a take
# by binary search without holding the index, then each take's mouth (one
# byte per MOUTH_MS) and samples.
MAGIC = b"BOOPVOX1"
HEADER = struct.Struct("<8s16sIIIII20x")  # magic, version, count, record size, index at, rate, mouth ms
ID_BYTES, TEXT_BYTES = 72, 36
RECORD = struct.Struct(f"<{ID_BYTES}s{TEXT_BYTES}sIIII4x")  # id, text, samples at, len, mouth at, frames

MOODS = ["happy", "excited", "proud", "curious", "determined", "grumpy", "sad",
         "calm", "engaged", "annoyed", "irritated", "whiny", "wounded"]
# Takes recorded in a mood Boop doesn't have, by the bank's label or, for
# the two with none, by id: the mood they're used in.
MOOD_OF = {"relieved": "happy", "weary": "whiny", "amused": "happy",
           "previous.go": "calm", "previous.oi": "curious"}

# The bank's intents, as answers to the brain's two questions.
FEELING = {"frustration": "upset", "setback": "upset", "deflate": "upset",
           "celebrate": "glad", "delight": "glad", "relief": "glad", "pride": "glad", "insight": "glad",
           "poke": "tickled"}
ABOUT = {"begin": "start", "delegate": "helpers", "return": "helper back", "retry": "retry",
         "work": "work", "effort": "work", "test": "tests", "terminal": "command", "tool": "tool",
         "search": "looking", "analyze": "looking", "ponder": "looking", "plan": "planning",
         "success": "done", "reply": "answer", "stop": "stopped", "wait": "waiting", "idle": "quiet"}
# Entries whose words name a fact that belongs to another topic, whatever
# the bank's intent: "Passed" is about tests, so it's only said about them
# (and only on a success); the greetings, recorded for pokes and needs you,
# are Boop's hello when you come back to the Mac.
ABOUT_OF_ENTRY = {"word.success.passed": "tests",
                  "word.attention.hello": "hello", "word.attention.hey": "hello",
                  "phrase.attention.hello-hello": "hello", "word.poke.hi": "hello",
                  "word.poke.howdy": "hello", "borrowed.salut": "hello",
                  "phrase.poke.oh-hello": "hello", "phrase.poke.hey-hey": "hello"}
# The facts the bank says a take needs that the Mac can check: a success
# word only on a success. Swears play only on a failed turn.
SUCCESS = {"success_confirmed", "fix_confirmed", "tests_passed", "insight_confirmed"}


def kind(entry: dict) -> str:
    if entry["explicit"]:
        return "swear"
    return {"word": "word", "phrase": "phrase", "nonverbal": "sound"}[entry["category"]]


def answer(entry: dict) -> tuple[str, str]:
    """The take's part (feeling, about or attention) and its answer."""
    intent = entry["intent"]
    if entry["id"] in ABOUT_OF_ENTRY:
        return "about", ABOUT_OF_ENTRY[entry["id"]]
    if intent in FEELING:
        return "feeling", FEELING[intent]
    if intent in ABOUT:
        return "about", ABOUT[intent]
    if intent == "attention":
        return "attention", "attention"
    raise SystemExit(f"voicegen: {entry['id']} has intent {intent!r}, which answers neither question; map it in FEELING or ABOUT")


def finish(entry: dict) -> str | None:
    if entry["explicit"]:
        return "failure"
    return "success" if entry["requires"] in SUCCESS else None


def mood(rec: dict) -> str:
    m = MOOD_OF.get(rec["id"]) or MOOD_OF.get(rec["mood"]) or rec["mood"]
    if m not in MOODS:
        raise SystemExit(f"voicegen: {rec['id']} is in mood {rec['mood']!r}, which isn't one of Boop's; add it to MOOD_OF")
    return m


def text(entry: dict) -> str:
    """The bubble's text: the bank's, folded into the board font's ASCII."""
    t = unicodedata.normalize("NFKD", entry["text"]).encode("ascii", "ignore").decode()
    t = t.replace("....", "...")
    return t[:-1] if t.endswith(".") and not t.endswith("...") else t


def load(path: Path) -> list[float]:
    with wave.open(str(path)) as w:
        assert w.getnchannels() == 1 and w.getframerate() == RATE, path
        width, raw = w.getsampwidth(), w.readframes(w.getnframes())
    if width == 1:
        return [(b - 128) / 128 for b in raw]
    assert width == 2, path
    return [v / 32768 for v in struct.unpack(f"<{len(raw) // 2}h", raw)]


def rms(x: list[float]) -> float:
    return math.sqrt(sum(v * v for v in x) / len(x)) if x else 0.0


def trim(x: list[float]) -> list[float]:
    step, floor = RATE // 100, 10 ** (-TRIM_DB / 20)
    loud = [i for i in range(0, len(x), step) if rms(x[i:i + step]) > floor]
    if not loud:
        return x
    return x[max(0, loud[0] - RATE * PAD_BEFORE_MS // 1000):min(len(x), loud[-1] + step + RATE * PAD_AFTER_MS // 1000)]


def shape(x: list[float]) -> list[float]:
    """Saturate, normalise and fade the ends."""
    p = max(map(abs, x)) or 1
    y = [math.tanh(DRIVE * v / p) for v in x]
    p = max(map(abs, y)) or 1
    y = [PEAK * v / p for v in y]
    fin, fout = RATE * 3 // 1000, RATE * 12 // 1000
    for i in range(min(fin, len(y))):
        y[i] *= i / fin
    for i in range(min(fout, len(y))):
        y[-1 - i] *= i / fout
    return y


def to_u8(y: list[float]) -> bytes:
    return bytes(max(0, min(255, 128 + round(127 * v))) for v in y)


def mouth(y: list[float]) -> bytes:
    """1 for each MOUTH_MS the take is loud, else 0."""
    n = RATE * MOUTH_MS // 1000
    frames = [rms(y[i:i + n]) for i in range(0, len(y), n)]
    top = max(frames) or 1
    return bytes(1 if f >= MOUTH_OPEN * top else 0 for f in frames)


def convert(path: str) -> tuple[bytes, bytes]:
    y = shape(trim(load(BANK / path)))
    return to_u8(y), mouth(y)


def version(takes: list[dict], clips: list[bytes], mouths: list[bytes]) -> str:
    h = hashlib.sha256()
    for t, c, m in zip(takes, clips, mouths):
        h.update(t["id"].encode() + b"\0" + t["text"].encode() + b"\0" + m + c)
    return h.hexdigest()[:12]


def write_pack(path: Path, ver: str, takes: list[dict], clips: list[bytes], mouths: list[bytes]) -> None:
    order = sorted(range(len(takes)), key=lambda i: takes[i]["id"].encode())
    index_at = HEADER.size
    at = index_at + RECORD.size * len(takes)
    records, data = [], []
    for i in order:
        t = takes[i]
        if len(t["id"].encode()) >= ID_BYTES or len(t["text"].encode()) >= TEXT_BYTES:
            raise SystemExit(f"voicegen: {t['id']}'s id or text is too long for the pack")
        records.append(RECORD.pack(t["id"].encode(), t["text"].encode(), at + len(mouths[i]), len(clips[i]), at, len(mouths[i])))
        data += [mouths[i], clips[i]]
        at += len(mouths[i]) + len(clips[i])
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "wb") as f:
        f.write(HEADER.pack(MAGIC, ver.encode(), len(takes), RECORD.size, index_at, RATE, MOUTH_MS))
        f.writelines(records)
        f.writelines(data)
    tmp.replace(path)


def lent(mood: str) -> list[str]:
    """The moods a take recorded in `mood` plays in: that one, then those
    that borrow its takes."""
    return [mood] + [m for m, lender in BORROWS.items() if lender == mood]


def write_table(ver: str, takes: list[dict]) -> str:
    """takes.tsv, the Mac's table in a character pack
    (characters/CHARACTER.md §8): two comment lines, the pack's version,
    then every take as one line of tab-separated fields. The app reads it at
    start (`Take.all`)."""
    for t in takes:
        assert not any(c in t["text"] for c in '\t\n'), t["id"]
    rows = ["\t".join([t["id"], t["text"], t["part"], t["meaning"], t["kind"], " ".join(lent(t["mood"])), t["finish"] or "",
                       str(t["ms"])])
            for t in takes]
    return "\n".join([
        "# The voice's takes (characters/CHARACTER.md §8): the pack's version, then a take a line: "
        "id, text, part, meaning, kind, moods (space separated), finish (empty for any) and ms, tab separated.",
        "# Generated by voicegen from the recorded voice bank. Don't edit; rerun the tool.",
        ver,
        *rows,
        "",
    ])


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", type=Path, default=PACK_DIR, metavar="DIR",
                    help="the character pack to write it into (default: Pixel's)")
    ap.add_argument("--card", type=Path, help="also copy the pack onto the card mounted here, as boop/voice.bin")
    ap.add_argument("--wav-dir", type=Path, help="also write every converted take as a WAV here")
    args = ap.parse_args()

    manifest = json.loads((BANK / "manifest.json").read_text())
    entries = {e["id"]: e for e in json.loads((BANK / "dictionary.json").read_text())["entries"]}
    recs = manifest["recordings"]
    with ProcessPoolExecutor(max_workers=os.cpu_count()) as pool:
        out = list(pool.map(convert, [r["files"][TEXTURE]["path"] for r in recs], chunksize=16))
    takes, clips, mouths = [], [], []
    for rec, (clip, mo) in zip(recs, out):
        e = entries[rec["entryId"]]
        part, meaning = answer(e)
        takes.append({"id": rec["id"], "text": text(e), "part": part, "meaning": meaning, "kind": kind(e),
                      "mood": mood(rec), "finish": finish(e), "ms": len(clip) * 1000 // RATE})
        clips.append(clip)
        mouths.append(mo)
    ver = version(takes, clips, mouths)
    table = write_table(ver, takes)
    write_pack(args.pack / PACK, ver, takes, clips, mouths)
    (args.pack / TABLE).write_text(table)
    built = args.pack / PACK
    if args.card:
        # Through voice.tmp, as the board copies one: a copy cut short
        # leaves the last pack, not a short one the board takes for whole.
        dest = args.card / CARD_PATH
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(".tmp")
        shutil.copyfile(built, tmp)
        tmp.replace(dest)
    if args.wav_dir:
        args.wav_dir.mkdir(parents=True, exist_ok=True)
        for t, c in zip(takes, clips):
            with wave.open(str(args.wav_dir / f"{t['id']}.wav"), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(1)
                w.setframerate(RATE)
                w.writeframes(c)
    ms = [t["ms"] for t in takes]
    where = f", copied to {args.card / CARD_PATH}" if args.card else ""
    print(f"voicegen: {len(takes)} takes, version {ver}, {built.stat().st_size} B pack "
          f"({min(ms)}–{max(ms)} ms) → {PACK} and {TABLE} in {args.pack.name}{where}")
    if args.card:
        print("voicegen: put the card back in the board and press its reset button: it mounts the card only at boot")


if __name__ == "__main__":
    main()
