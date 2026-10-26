"""Turns the replies' lines in plan/voice-range.md (step 4's table) into
recording slots in the voice bank's own shape (plans/deferred.json's): each
sound and word in every mood of its reply, and the phrases dealt out two to
a mood. A line a recorded take already says in that mood is left out.
Writes the bank's plans/replies.json, which placeholders.py speaks until
the real takes come. Run from the repo root after editing the table:

    python3 characters/boop/tools/voicegen/reply_slots.py
"""
import json
import re

from voicegen import BANK, REPLY_OF, mood, text as shown

dictionary = json.loads((BANK / "dictionary.json").read_text())
moods, by_id = dictionary["moods"], {e["id"]: e for e in dictionary["entries"]}
# What a reply already says, recorded, in each mood: (reply, words, mood).
said = {(reply, shown(by_id[r["entryId"]]).rstrip(".").lower(), mood(r))
        for r in json.loads((BANK / "manifest.json").read_text())["recordings"]
        if not r.get("generation", {}).get("placeholder") for reply in REPLY_OF.get(r["entryId"], [])}

doc = (BANK.parents[4] / "plan" / "voice-range.md").read_text()
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

json.dump({"note": "The replies' own words, from plan/voice-range.md step 4, as recording slots: "
                   "placeholders.py speaks each until a real take replaces it.", "entries": entries, "slots": slots},
          open(BANK / "plans" / "replies.json", "w"), indent=1)
by = {}
for s in slots:
    r = s["entry"].split(".")[1]
    by[r] = by.get(r, 0) + 1
print(f"{len(entries)} lines, {len(slots)} slots:", ", ".join(f"{k[5:]} {v}" for k, v in by.items()))
