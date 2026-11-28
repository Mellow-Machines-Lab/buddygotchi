"""Builds Boop's voice from the recorded voice bank.

The bank, character/design/assets/boop-voice-v1/, has whole recorded
takes, each a word, a sound, a phrase, a swear or a sentence said in one
delivery: bright (B), flat (F) or glum (G), the plan's `deliveries`
(plans/sentences.json), each with the faces it plays in. record.py records
them, all in one voice. Every take in the manifest is read from its
robot-soft WAV (8-bit, 11.025 kHz), the near-silence around it trimmed,
saturated and normalised so it's as loud on the small speaker, and stored
as 8-bit unsigned samples. Two files come out, into Boop's pack
(PACK_DIR), checked in there. Rerun this whenever the bank or a mapping
changes:

    python3 character/tools/voicegen/voicegen.py [--card /Volumes/CARD] [--wav-dir DIR]

- voice/voice.bin: the pack the board plays from its SD card
  (at /boop/voice.bin): every take's samples, bubble text
  and mouth (open or shut every 20 ms), found by id. `--card` also copies
  it onto a mounted card.
- mac/takes.tsv (characters/CHARACTER.md §8): each take Boop may say,
  its id, text, part and meaning, kind, the faces it plays in, an empty
  column (once the finish a take needed, kept so readers find eight) and
  its length, which the Mac picks from, and the pack's
  version, which the board reports.

Boop says three parts of take. A reply's, to what you said on
push-to-talk and at a lock's real wave: a dictionary entry of intent
`talk.<reply>` is that reply's own words, and another entry that fits one
counts for it too (REPLY_OF): "Yep" is a yes, "Tsk" a no. A skit's
(SKIT_OF, characters/CHARACTER.md §8): the few moments that always speak,
each from takes of its own, such as `win`'s "Done" and "Nailed it", the
skit's id their meaning. takes.tsv lists a take once for each reply and
skit it counts for, by the same id; the voice file has it once. And a
sentence: one of the pack's lines said whole, an aside's or a remark's
(`take=<id>` in signs.md's brackets), its words and deliveries the plan's;
a recording whose entryId is `sentence.<id>` is one, its meaning the id.

A word (`words`) is recorded flat and in the delivery its first meaning
leans to (LEANS); its flat take also plays in the faces of the delivery it
wasn't recorded in, so every face has every word. A sentence plays only in
the deliveries it was recorded in.

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

# The character pack the voice is built into, this script's own.
PACK_DIR = Path(__file__).resolve().parents[2]
BANK = PACK_DIR / "design" / "assets" / "boop-voice-v1"
PACK, TABLE = "voice/voice.bin", "mac/takes.tsv"  # in a character pack
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
# The longest take the board plays: its mouth holds this many frames
# (firmware voice::kMaxFrames, 3.2 s). A longer one it can't load, and says
# nothing, so the build stops at one.
MAX_FRAMES = 160
RECORD = struct.Struct(f"<{ID_BYTES}s{TEXT_BYTES}sIIII4x")  # id, text, samples at, len, mouth at, frames

# The replies that merged into another (their recorded words go with
# them), and the ones Boop no longer makes: their takes stay in voice.bin,
# which keeps its version, and are left out of takes.tsv.
REPLY_AS = {"love": "thanks", "notme": "no"}
UNMADE = {"dance", "nap", "unhush"}
# Entries that are also a reply's own words, to what you said on
# push-to-talk (MomentOutput's replies, and dunno, a huh to a question):
# each of their takes counts for those replies too, in its own mood.
REPLY_OF = {
    "word.poke.yep": ["yes"], "nonverbal.delight.mm-hm": ["yes"], "phrase.success.got-it": ["yes"],
    "phrase.return.at-your-service": ["yes"], "phrase.pride.naturally-naturally": ["yes"],
    "nonverbal.frustration.tsk": ["no"], "nonverbal.frustration.pfft": ["no"], "borrowed.basta": ["no"],
    "phrase.setback.not-quite": ["no"], "phrase.poke.personal-space": ["no"], "phrase.poke.easy-there": ["no"],
    "nonverbal.frustration.hmph": ["no", "hush"],
    "nonverbal.ponder.huh": ["huh"], "nonverbal.ponder.eh": ["huh"], "nonverbal.ponder.uh": ["huh"],
    "phrase.analyze.what-what": ["huh"], "phrase.analyze.brain-loading": ["huh"],
    "nonverbal.ponder.hm": ["dunno"], "nonverbal.ponder.hmm": ["dunno"], "phrase.plan.hmm-perhaps": ["dunno"],
    "word.poke.hi": ["hello"], "word.poke.howdy": ["hello"], "word.attention.hey": ["hello"],
    "word.attention.hello": ["hello"], "word.idle.hullo": ["hello"], "phrase.poke.oh-hello": ["hello"],
    "phrase.poke.hey-hey": ["hello"], "phrase.attention.hello-hello": ["hello"], "phrase.poke.you-rang": ["hello"],
    "borrowed.salut": ["hello", "bye"], "word.idle.peace": ["bye"],
    "word.celebrate.yay": ["thanks", "unhush"], "word.celebrate.sweet": ["thanks"], "word.celebrate.nice": ["thanks"],
    "phrase.pride.no-biggie": ["thanks"], "phrase.pride.heh-obviously": ["thanks"], "phrase.success.we-did-it": ["thanks"],
    "phrase.success.nice-one": ["thanks"], "phrase.success.good-stuff": ["thanks"],
    "phrase.poke.boop-back": ["thanks"], "phrase.celebrate.happy-circuits": ["thanks"], "nonverbal.delight.eep": ["thanks"],
    "word.poke.boop": ["thanks"],
    "word.setback.ouch": ["ouch"], "phrase.frustration.why-though": ["ouch"],
    "nonverbal.deflate.aww": ["comfort"], "nonverbal.deflate.mm": ["comfort"], "phrase.setback.oh-dear": ["comfort"],
    "nonverbal.delight.heh": ["hehe"], "nonverbal.delight.hehehe": ["hehe"], "nonverbal.delight.ha": ["hehe"],
    "word.poke.tickles": ["hehe"],
    "phrase.analyze.let-me-see": ["status"], "phrase.analyze.looky-look": ["status"], "phrase.reply.here-you-go": ["status"],
    "word.search.look": ["status"], "word.search.peek": ["status"], "phrase.return.tiny-report": ["status"],
    "phrase.return.mission-update": ["status"],
    "word.idle.quiet": ["hush"],
    "nonverbal.relief.ahh": ["unhush"], "nonverbal.relief.phew": ["unhush"],
}
# Entries that are a skit's own takes (the pack's `skits` in
# character.json, and code says when each plays): each of their takes
# counts for those skits, in its own mood, as REPLY_OF's do for a
# reply. Plain words a person understands at that moment, words and
# phrases both: win says the turn is done; upset is a failure, its swears
# (the `swear` kind) for when failures pile up and swearing is on; fix is
# relief at a check passing again, with every claims_a_fix word; back is
# the greetings, for you coming back.
SKIT_OF = {
    "word.success.done": ["win"], "word.success.finish": ["win"], "word.success.finished": ["win"],
    "word.success.complete": ["win"], "word.success.success": ["win"], "word.celebrate.victory": ["win"],
    "phrase.pride.nailed-it": ["win"], "phrase.celebrate.ta-da-da": ["win"], "phrase.success.all-done": ["win"],
    "phrase.success.job-done": ["win"], "phrase.success.and-done": ["win"], "phrase.success.we-did-it": ["win"],
    "explicit.fuck": ["upset"], "explicit.shit": ["upset"], "explicit.damn": ["upset"], "explicit.crap": ["upset"],
    "phrase.setback.oh-no": ["upset"], "phrase.frustration.not-again": ["upset"], "phrase.frustration.oh-come-on": ["upset"],
    "phrase.setback.aw-nuts": ["upset"], "word.setback.failed": ["upset"], "word.setback.broken": ["upset"],
    "word.setback.drat": ["upset"], "word.setback.uh-oh": ["upset"], "word.setback.oops": ["upset"],
    "nonverbal.relief.phew": ["fix"], "nonverbal.relief.whew": ["fix"], "nonverbal.relief.ahh": ["fix"],
    "nonverbal.relief.haa": ["fix"], "word.success.fixed": ["fix"], "word.success.passed": ["fix"],
    "word.success.cleared": ["fix"], "phrase.success.there-it-is": ["fix"],
    "word.attention.hello": ["back"], "word.attention.hey": ["back"], "phrase.attention.hello-hello": ["back"],
    "word.poke.hi": ["back"], "word.poke.howdy": ["back"], "borrowed.salut": ["back"], "phrase.poke.oh-hello": ["back"],
    "phrase.poke.hey-hey": ["back"], "word.idle.hullo": ["back"],
}


# A word's deliveries: every reply's and skit's word is recorded flat (F),
# and once more in the delivery its first meaning leans to, bright or glum.
# The faces of the delivery it wasn't recorded in play its flat take.
LEANS = {"yes": "B", "hello": "B", "bye": "B", "thanks": "B", "hehe": "B", "status": "B", "win": "B", "fix": "B", "back": "B",
         "no": "G", "huh": "G", "dunno": "G", "ouch": "G", "comfort": "G", "hush": "G", "upset": "G"}


def meanings(entry: dict) -> list[str]:
    """The replies and skits an entry's takes count for, its own reply first."""
    own = own_reply(entry)
    out = ([own] if own else []) + REPLY_OF.get(entry["id"], []) + SKIT_OF.get(entry["id"], [])
    return [m for m in out if m not in UNMADE]


def words(dictionary: dict) -> list[dict]:
    """Every word to record: each entry a reply or a skit says, with its
    deliveries (flat, then the one its first meaning leans to)."""
    return [{"id": e["id"], "spoken": e["text"], "deliveries": ["F", LEANS[m[0]]]}
            for e in dictionary["entries"] if (m := meanings(e))]



# The sentences' plan: each sentence's spoken words, and each delivery's
# faces (record.py records from the same file).
SENTENCES = BANK / "plans" / "sentences.json"
SENTENCE = "sentence."  # a sentence's recordings' entryId, before its id


def sentence_entries(plan: dict) -> dict[str, dict]:
    """The plan's sentences as dictionary entries, by `sentence.<id>`."""
    return {SENTENCE + s["id"]: {"id": SENTENCE + s["id"], "text": s["spoken"], "category": "phrase", "intent": "sentence",
                                 "explicit": s.get("kind") == "swear"} for s in plan["sentences"]}


def kind(entry: dict) -> str:
    if entry["explicit"]:
        return "swear"
    return {"word": "word", "phrase": "phrase", "nonverbal": "sound"}[entry["category"]]


def own_reply(entry: dict) -> str | None:
    """The reply a `talk.<reply>` entry is the own words of, or None."""
    intent = entry["intent"]
    if not intent.startswith("talk."):
        return None
    reply = intent[len("talk."):]
    return REPLY_AS.get(reply, reply)


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


def convert(path: str, bank: Path = BANK) -> tuple[bytes, bytes]:
    y = shape(trim(load(bank / path)))
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
        if len(mouths[i]) > MAX_FRAMES:
            raise SystemExit(f"voicegen: {t['id']} is {len(mouths[i]) * MOUTH_MS} ms, longer than the board plays "
                             f"({MAX_FRAMES * MOUTH_MS} ms): trim or re-record it")
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


def faces(rec: dict, deliveries: dict, recorded: set) -> list[str]:
    """The faces a take plays in: its delivery's, and, for a word's flat
    take, those of each delivery the word wasn't recorded in. A sentence
    plays only in the deliveries it was recorded in."""
    out = list(deliveries[rec["delivery"]]["faces"])
    if rec["delivery"] == "F" and not rec["entryId"].startswith(SENTENCE):
        out += [f for d, delivery in deliveries.items() if d not in recorded for f in delivery["faces"]]
    return out


def write_table(ver: str, takes: list[dict]) -> str:
    """takes.tsv, the Mac's table in a character pack
    (characters/CHARACTER.md §8): two comment lines, the pack's version,
    then every take as one line of tab-separated fields. The app reads it at
    start (`Take.all`)."""
    for t in takes:
        assert not any(c in t["text"] for c in '\t\n'), t["id"]
    rows = ["\t".join([t["id"], t["text"], t["part"], t["meaning"], t["kind"], " ".join(t["faces"]), "",
                       str(t["ms"])])
            for t in takes]
    return "\n".join([
        "# The voice's takes (characters/CHARACTER.md §8): the pack's version, then a take a line: "
        "id, text, part, meaning, kind, moods (space separated), an empty column (once a finish) and ms, tab separated.",
        "# Generated by voicegen from the recorded voice bank. Don't edit; rerun the tool.",
        ver,
        *rows,
        "",
    ])


def build(bank: Path, pack: Path, complete: bool = True) -> tuple[str, list[dict], list[bytes], list[dict]]:
    """Builds `pack`'s voice file and table from `bank`: its version, every
    take with its audio, and the table's rows. `complete` checks that every
    entry REPLY_OF and SKIT_OF name has a recording (a test's small bank
    has few)."""
    manifest = json.loads((bank / "manifest.json").read_text())
    entries = {e["id"]: e for e in json.loads((bank / "dictionary.json").read_text())["entries"]}
    plan_file = bank / "plans" / SENTENCES.name
    plan = json.loads(plan_file.read_text()) if plan_file.is_file() else {"sentences": [], "deliveries": {}}
    entries.update(sentence_entries(plan))
    recs = manifest["recordings"]
    recorded: dict[str, set] = {}
    for r in recs:
        recorded.setdefault(r["entryId"], set()).add(r["delivery"])
    bare = [r["id"] for r in recs if TEXTURE not in r["files"]]
    if bare:
        raise SystemExit(f"voicegen: no {TEXTURE} file yet for {', '.join(bare)}: make it, then run this again")
    with ProcessPoolExecutor(max_workers=os.cpu_count()) as pool:
        out = list(pool.map(convert, [r["files"][TEXTURE]["path"] for r in recs], [bank] * len(recs), chunksize=16))
    takes, clips, mouths = [], [], []
    for rec, (clip, mo) in zip(recs, out):
        e = entries[rec["entryId"]]
        takes.append({"id": rec["id"], "text": text(e), "kind": kind(e), "ms": len(clip) * 1000 // RATE,
                      "faces": faces(rec, plan["deliveries"], recorded[rec["entryId"]])})
        clips.append(clip)
        mouths.append(mo)
    ver = version(takes, clips, mouths)
    # The table's rows, each a recorded take again: a reply's own words,
    # then the takes that count for a reply, then a skit's, then a
    # sentence's, in its delivery's faces.
    own = [{**t, "part": "reply", "meaning": reply} for rec, t in zip(recs, takes)
           if (reply := own_reply(entries[rec["entryId"]])) is not None]
    replies = [{**t, "part": "reply", "meaning": reply}
               for rec, t in zip(recs, takes) for reply in REPLY_OF.get(rec["entryId"], [])]
    skits = [{**t, "part": "skit", "meaning": skit}
             for rec, t in zip(recs, takes) for skit in SKIT_OF.get(rec["entryId"], [])]
    sentences = [{**t, "part": "sentence", "meaning": rec["entryId"][len(SENTENCE):]}
                 for rec, t in zip(recs, takes) if rec["entryId"].startswith(SENTENCE)]
    for name, table_of in (("REPLY_OF", REPLY_OF), ("SKIT_OF", SKIT_OF)):
        missing = set(table_of) - {rec["entryId"] for rec in recs}
        if missing and complete:
            raise SystemExit(f"voicegen: {name} names entries with no recording: {', '.join(sorted(missing))}")
    said = [t for t in own + replies + skits + sentences if not (t["part"] == "reply" and t["meaning"] in UNMADE)]
    write_pack(pack / PACK, ver, takes, clips, mouths)
    (pack / TABLE).parent.mkdir(parents=True, exist_ok=True)
    (pack / TABLE).write_text(write_table(ver, said))
    return ver, takes, clips, said


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--pack", type=Path, default=PACK_DIR, metavar="DIR",
                    help="the character pack to write it into (default: this one, Boop's)")
    ap.add_argument("--card", type=Path, help="also copy the pack onto the card mounted here, as boop/voice.bin")
    ap.add_argument("--wav-dir", type=Path, help="also write every converted take as a WAV here")
    args = ap.parse_args()

    ver, takes, clips, said = build(BANK, args.pack)
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
    print(f"voicegen: {len(takes)} takes ({len(said)} rows in the table, as replies, skits and sentences), version {ver}, {built.stat().st_size} B pack "
          f"({min(ms)}–{max(ms)} ms) → {PACK} and {TABLE} in {args.pack.name}{where}")
    if args.card:
        print("voicegen: put the card back in the board and press its reset button: it mounts the card only at boot")


if __name__ == "__main__":
    main()
