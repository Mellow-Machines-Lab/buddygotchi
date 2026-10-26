"""Turns the replies' lines in plan/voice-range.md (step 4's table) into
recording slots in the voice bank's own shape (plans/deferred.json's), for
the owner to generate: each sound and word in every mood of its reply, and
the phrases dealt out two to a mood. A line a recorded take already says
in that mood is left out. Writes reply-slots.json. Run from the repo root:

    python3 plan/evidence/2026-10-25-voice-range/reply_slots.py plan/evidence/2026-10-25-voice-range/reply-slots.json
"""
import json
import re
import sys

BANK = "characters/boop/design/assets/boop-voice-v1/"
moods = json.load(open(BANK + "dictionary.json"))["moods"]
table = [l.split("\t") for l in open("characters/pixel/mac/takes.tsv") if not l.startswith("#")][1:]
said = {(r[3], r[1].rstrip(".").lower(), r[5].split()[0]) for r in table if len(r) == 8 and r[2] == "reply"}

doc = open("plan/voice-range.md").read()
step = doc[doc.index("## 4. Talking back"):doc.index("## What it adds up to")]
rows = [[c.strip() for c in l.strip().strip("|").split("|")] for l in step.splitlines()
        if l.startswith("| ") and l.count("|") == 6 and not l.startswith(("| Reply", "| ---"))]

VARIANT = {"sound": "A lighter exhaled gesture, no hiss or breath blast.",
           "word": "One compact contained gesture. Small, rounded, never projected.",
           "phrase": "One compact contained gesture. Small, rounded, never projected."}
CATEGORY = {"sound": "nonverbal", "word": "word", "phrase": "phrase"}
entries, slots = [], []


def slug(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"\(.*?\)", "", text).lower()).strip("-")


for reply, in_moods, sounds, words, phrases in rows:
    ms = [m.strip() for m in in_moods.split(",")]
    lines = [("sound", t) for t in sounds.split(", ")] + [("word", t) for t in words.split(", ")] \
        + [("phrase", t) for t in phrases.split(" · ")]
    dealt = 0
    for kind, text in lines:
        text = re.sub(r"\s*\(.*?\)", "", text).strip()
        entry = f"{CATEGORY[kind]}.talk-{reply}.{slug(text)}"
        if kind == "phrase":
            # Two phrases to a mood: each phrase in the next one or two.
            per = max(1, round(2 * len(ms) / max(1, sum(k == "phrase" for k, _ in lines))))
            take = [ms[(dealt + i) % len(ms)] for i in range(per)]
            dealt += per
        else:
            take = ms
        take = [m for m in take if (reply, text.rstrip(".").lower(), m) not in said]
        if not take:
            continue
        entries.append({"id": entry, "text": text, "category": CATEGORY[kind], "intent": f"talk.{reply}", "moods": take})
        for m in take:
            tag, direction = moods[m]
            end = "" if text[-1] in "?!." else "."
            slots.append({"id": f"{entry}__{m}__contained", "entry": entry, "mood": m, "variant": "contained",
                          "script": f"{tag} {text}{end}", "direction": f"{direction} {VARIANT[kind]}", "status": "planned"})

json.dump({"note": "Draft: the replies' own words from plan/voice-range.md step 4, as recording slots. "
                   "Not authorized for generation.", "entries": entries, "slots": slots},
          open(sys.argv[1], "w"), indent=1)
by = {}
for s in slots:
    r = s["entry"].split(".")[1]
    by[r] = by.get(r, 0) + 1
print(f"{len(entries)} lines, {len(slots)} slots:", ", ".join(f"{k[5:]} {v}" for k, v in by.items()))
