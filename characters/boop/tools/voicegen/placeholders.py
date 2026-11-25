"""Speaks the voice bank's planned slots that have no recording yet, so Boop
can say them now, and keeps the list of what to record for real.

A slot is one line in one mood, in the bank's own shape (plans/deferred.json's),
in one of the plans named in PLANS. Each slot with no recording gets a
placeholder take, spoken by espeak-ng (`brew install espeak-ng`; its speech
is free to ship) in a robot voice, pitched and paced by the mood, and
converted with macOS's afconvert to the bank's 8-bit, 11.025 kHz WAV. It
goes into the manifest like any recording, but with `"placeholder": true`
in its `generation` and `reviewStatus: "placeholder"`, and its entry into
dictionary.json if it's new. Nothing in it is acted, so a mood is only its
pitch and pace.

plans/regenerate.json is the list to record for real: every placeholder's
slot, with its script and direction, rewritten on every run from the
manifest. To replace one, record its slot, put the take in the manifest
with the slot's id as its performanceId, and rerun this: the placeholder
and its file go, and so does its line in regenerate.json. Then rerun
voicegen. Run from anywhere:

    python3 character/tools/voicegen/placeholders.py [--force] [--voice VOICE]

--force speaks every placeholder again (with --voice, in another voice).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path

from voicegen import BANK, TEXTURE

# The bank's plans whose slots are spoken until they're recorded.
PLANS = ["replies.json"]
VOICE = "en-us+robosoft"
# A mood as espeak-ng speaks it: pitch (0 to 99, 50 its usual) and pace (words a minute).
TONE = {"happy": (75, 175), "excited": (88, 200), "proud": (62, 160), "curious": (80, 165), "determined": (52, 170),
        "grumpy": (30, 150), "sad": (38, 120), "calm": (55, 140), "engaged": (60, 170), "annoyed": (42, 160),
        "irritated": (40, 185), "whiny": (82, 130), "wounded": (45, 125)}
# Sounds respelled so espeak-ng says them, not their letters; the text stays.
SAY = {"mhm": "mm hmm", "mm-hm": "mm hmm", "uh-huh": "uh huh", "nuh-uh": "nuh uh", "hmm-mm": "mm mm",
       "nn-nn": "nn nn", "mm-mm": "mm mm", "hmm": "hmmm", "hm": "hmm", "pff": "pfff", "heyy": "heyyy",
       "bye-ee": "bye eee", "aww": "awww", "mmm": "mmmm", "mm": "mmm", "mmh": "mmm", "yawn": "aaaah hmm",
       "zzz": "zzzzz", "shh": "shhhh", "whee": "wheee", "doo-doo": "doo doo", "ahh": "aaah", "hehe": "heh heh",
       "ha": "hah", "oof": "oof", "ow": "ow", "lol": "lol"}
RECIPE = "espeak-ng placeholder, afconvert to pcm-u8-mono-11025"


def spoken(text: str) -> str:
    """What espeak-ng is given to say a line."""
    bare = re.sub(r"[.!?]+$", "", text.lower())
    return SAY.get(bare, text.replace("-", " "))


def speak(text: str, mood: str, voice: str, out: Path) -> None:
    pitch, pace = TONE[mood]
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "raw.wav"
        subprocess.run(["espeak-ng", "-v", voice, "-p", str(pitch), "-s", str(pace), "-w", str(raw), spoken(text)], check=True)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "UI8@11025", "-c", "1", str(raw), str(out)], check=True)


def entry(e: dict) -> dict:
    """A plan's entry as dictionary.json holds one."""
    nonverbal = e["category"] == "nonverbal"
    return {"id": e["id"], "text": e["text"], "category": e["category"], "intent": e["intent"], "states": [],
            "requires": "", "moods": e["moods"], "tier": "daily", "origin": "placeholder", "gloss": f"{e['intent']} expression",
            "explicit": False, "assembly": "nonverbal" if nonverbal else "anchor",
            "review": "A placeholder: record it for real.", "productionStatus": "placeholder",
            "repeatFamily": e["id"].split(".")[-1], "variantCount": 1, "variants": ["contained"],
            "semanticNote": "Context labels gate eligibility; the animation conveys detail. Mood never establishes facts."}


def recording(slot: dict, path: Path, voice: str) -> dict:
    data = path.read_bytes()
    with wave.open(str(path)) as w:
        frames = w.getnframes()
    return {"id": f"placeholder.{slot['id']}", "entryId": slot["entry"], "mood": slot["mood"], "moodStatus": "placeholder",
            "variant": slot["variant"], "script": slot["script"], "seconds": frames / 11025, "routineDurationEligible": True,
            "reviewStatus": "placeholder", "performanceId": slot["id"], "sourceBatch": "placeholder",
            "generation": {"engine": "espeak-ng", "voice": voice, "placeholder": True},
            "files": {TEXTURE: {"path": str(path.relative_to(BANK)), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                                "recipe": RECIPE}}}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="speak every placeholder again")
    ap.add_argument("--voice", default=VOICE, help=f"espeak-ng's voice and variant (default {VOICE})")
    args = ap.parse_args()
    if not shutil.which("espeak-ng") or not shutil.which("afconvert"):
        raise SystemExit("placeholders: needs espeak-ng (brew install espeak-ng) and macOS's afconvert")

    dictionary = json.loads((BANK / "dictionary.json").read_text())
    manifest = json.loads((BANK / "manifest.json").read_text())
    known = {e["id"] for e in dictionary["entries"]}
    real = {r["performanceId"] for r in manifest["recordings"] if not r.get("generation", {}).get("placeholder")}
    held = {r["performanceId"]: r for r in manifest["recordings"] if r.get("generation", {}).get("placeholder")}
    slots = []
    for plan in PLANS:
        p = json.loads((BANK / "plans" / plan).read_text())
        dictionary["entries"] += [entry(e) for e in p["entries"] if e["id"] not in known]
        known |= {e["id"] for e in p["entries"]}
        slots += [s for s in p["slots"] if s["id"] not in real]
    wanted = {s["id"] for s in slots}

    # Placeholders a real take replaced, or whose slot left the plans, go.
    for pid, r in held.items():
        if pid not in wanted:
            (BANK / r["files"][TEXTURE]["path"]).unlink(missing_ok=True)
    spoke = 0
    out = []
    for s in slots:
        path = BANK / "audio-pcm8" / TEXTURE / f"placeholder.{s['id']}.wav"
        old = held.get(s["id"])
        if old and path.exists() and not args.force:
            out.append(old)
            continue
        speak(next(e["text"] for e in dictionary["entries"] if e["id"] == s["entry"]), s["mood"], args.voice, path)
        out.append(recording(s, path, args.voice))
        spoke += 1
    manifest["recordings"] = [r for r in manifest["recordings"] if not r.get("generation", {}).get("placeholder")] + out

    (BANK / "dictionary.json").write_text(json.dumps(dictionary, indent=2, ensure_ascii=False) + "\n")
    (BANK / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    regenerate = {"note": "Every placeholder take, by its slot: record each for real, then rerun placeholders.py "
                          "(character/tools/voicegen/), which rewrites this list.",
                  "slots": [{"slot": s["id"], "take": f"placeholder.{s['id']}", "entry": s["entry"], "mood": s["mood"],
                             "variant": s["variant"], "script": s["script"], "direction": s["direction"]} for s in slots]}
    (BANK / "plans" / "regenerate.json").write_text(json.dumps(regenerate, indent=1) + "\n")
    print(f"placeholders: {len(slots)} placeholder takes ({spoke} spoken now), listed in plans/regenerate.json; "
          "rerun voicegen")


if __name__ == "__main__":
    main()
