#!/usr/bin/env python3
"""Builds and stages character packs (characters/CHARACTER.md).

    characters/charactergen.py --check [PACK]
    characters/charactergen.py --stage [PACK]
    characters/charactergen.py --firmware-to=DIR [PACK]
    characters/charactergen.py --which

--check checks a pack's character.json: its moods are exactly the
universal ones (CHARACTER.md §5), and every move and default mood is
one of them; what it uses from other packs is there (§6); its
id and version fit the board's hello (§10); and its rig/ (§15): no
unknown key, channel or name, and every value in its range. Without
PACK, every pack in characters/.

--stage lays the chosen pack's files out in .character-build/ at the repo
root for the builds to read (§2), with what it uses from other packs (§6)
and two headers it makes for the firmware: moods.h from character.json,
the mood list in the pack's order with the board's startup mood, and
rig_tables.h from rig/, the rig's tables. It checks the pack as --check
does first. firmware/tools/pio.sh runs it before every PlatformIO build.

--firmware-to=DIR lays out only the firmware's files for a pack, as
--stage does, in DIR/firmware/, and changes nothing staged: for a second
build beside the staged pack's (simulator/web/build.sh PACK).

--which prints the folder of the pack in use: the one everything that runs
after a build reads (in_use()).

Every form but --which and --firmware-to also checks the board's states
where they're named (CHARACTER.md §9 and each pack's mac/faces.json), each
pack's studio entry (§12), references and review queue (§16), and writes
characters/studio/packs.js, the studio page's data for the packs in this
checkout, which git ignores. --check fails on a problem with any of them;
--stage only warns.

PACK is a pack's folder. Without one, the chosen pack is the first of:
$BOOP_CHARACTER (a folder), $CHARACTER (a name in characters/), the name or
folder in the repo's .character file, and characters/boop/. Staging
writes the staged pack's folder in .character-build/pack, the one pointer
to it; the pack in use is the one the environment chooses (staged, if it's
the one staged), else the staged one, else the chosen one (nothing staged
yet).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = ROOT / "characters"
STAGE = ROOT / ".character-build"
STUDIO = CHARACTERS / "studio"
FIRMWARE_STATES = ROOT / "firmware" / "src" / "render" / "types.cpp"
FIRMWARE_ACTS = ROOT / "firmware" / "src" / "app" / "behaviour.cpp"
# The rig's channels and the outfits the tags call for, as the firmware has them.
RIG_H = ROOT / "firmware" / "src" / "render" / "rig" / "rig.h"
TAGS_H = ROOT / "firmware" / "src" / "render" / "tags.h"
# The universal moods' one list, which the app's pack loader holds too.
UNIVERSAL = ROOT / "app" / "BoopKit" / "Character" / "Moods.swift"


def own_folder(folder: Path) -> Path:
    """A pack's own folder: the folder itself, or for the staged pack, whose
    files are links into its own, the folder its character.json is in."""
    return (folder / "character.json").resolve().parent if (folder / "character.json").exists() else folder.resolve()


def chosen() -> Path:
    if os.environ.get("BOOP_CHARACTER"):
        return own_folder(Path(os.environ["BOOP_CHARACTER"]))
    if os.environ.get("CHARACTER"):
        return CHARACTERS / os.environ["CHARACTER"]
    saved = ROOT / ".character"
    if saved.exists() and saved.read_text().strip():
        name = saved.read_text().strip()
        return own_folder(ROOT / name) if "/" in name else CHARACTERS / name
    return CHARACTERS / "boop"


def staged() -> Path | None:
    """The staged pack, which .character-build/pack names, if there is one."""
    pointer = STAGE / "pack"
    if pointer.exists() and pointer.read_text().strip():
        return Path(pointer.read_text().strip())
    return None


def in_use() -> Path:
    """The pack the tools, tests and simulator read: one the environment
    chooses ($BOOP_CHARACTER or $CHARACTER), else the one last staged
    (.character-build/pack), else the chosen one. A pack that is the one
    staged is read staged, with what it uses from other packs (§6). The
    Swift and C++ code keeps the same rule by reading the environment and
    the pointer."""
    last = staged()
    if os.environ.get("BOOP_CHARACTER") or os.environ.get("CHARACTER"):
        pack = chosen()
        return last if last and (last / "character.json").exists() and own_folder(last) == pack.resolve() else pack
    return last or chosen()


def camel(mood: str) -> str:
    return "k" + "".join(part.capitalize() for part in mood.split("_"))


def universal_moods(source: Path = UNIVERSAL) -> list[str]:
    """Every pack's moods: CharacterPack.universalMoods, one literal of
    quoted names in the app's source."""
    match = re.search(r"universalMoods = \[([^\]]*)\]", source.read_text())
    if not match:
        raise SystemExit(f"charactergen: no universalMoods in {source}")
    return re.findall(r'"([a-z_]+)"', match.group(1))


def mood_problems(character: dict, universal: list[str]) -> list[str]:
    """What's wrong with a pack's moods, as the app's loader refuses them:
    not exactly the universal moods, or a move, default or startup mood
    that isn't one."""
    ids = [m.get("id") for m in character.get("moods", [])]
    problems = []
    if len(ids) != len(set(ids)):
        problems.append("moods names a mood twice")
    if set(ids) != set(universal):
        missing, extra = sorted(set(universal) - set(ids)), sorted(set(ids) - set(universal))
        problems.append(f"moods aren't the universal ones (missing {missing}, extra {extra})")
    names = set(ids)
    for m in character.get("moods", []):
        if not m.get("meaning"):
            problems.append(f"{m.get('id')} has no meaning")
        moves = m.get("moves", {})
        for to in moves.get("ordinary", []) + moves.get("dramatic", []):
            if to not in names:
                problems.append(f"{m.get('id')} leads to {to}, which isn't a mood")
    for key in ("default_mood", "startup_mood"):
        if key in character and character[key] not in names:
            problems.append(f"{key} {character[key]} isn't a mood")
    return problems


def moods_h(pack: Path, character: dict) -> str:
    """The firmware's moods.h, which staging writes: the mood list in the
    pack's order with the board's startup mood, and the pack's id and
    version for the board's hello. pack_problems() has checked them."""
    moods = [m["id"] for m in character["moods"]]
    startup = character.get("startup_mood", character["default_mood"])
    source = f"characters/{pack.name}/character.json"
    rows = ",\n".join(f"  {camel(m)}" for m in moods)
    names = ", ".join(f'"{m}"' for m in moods)
    return f"""// Generated by characters/charactergen.py from {source}. Do not edit.
// The character's moods in its pack's order, and the pack's id and version
// (characters/CHARACTER.md §9).
#pragma once
#include <cstdint>

namespace render {{

enum class Mood : uint8_t {{
{rows},
  kCount
}};
constexpr int kMoodCount = {len(moods)};
// What the board shows before the Mac sends a mood, and for a name it
// doesn't know: the pack's startup_mood, else its default_mood.
constexpr Mood kStartupMood = Mood::{camel(startup)};
constexpr const char* kMoodNames[kMoodCount] = {{{names}}};
// The pack the board's hello names, for the Mac to tell its own from another.
constexpr const char* kPackId = {json.dumps(character["id"])};
constexpr const char* kPackVersion = {json.dumps(character["version"])};

}}  // namespace render
"""


EASES = {"linear": "kLinear", "in": "kIn", "out": "kOut", "inout": "kInOut"}
ANCHORS = {"crown": "kCrown", "brim": "kBrim", "hands": "kHands", "eyes": "kEyes"}
NAME = re.compile(r"[a-z0-9][a-z0-9_-]*")
# One file's rows in a List (rig.h): at most this many.
MOST = 255


# ── A file's keys, by a schema ──────────────────────────────────────────────
class Rule:
    """A rule for a value that no range, type or choices say, with what's
    wrong with a value that breaks it: Rule("isn't a name", test)."""

    def __init__(self, wrong: str, test) -> None:
        self.wrong, self.test = wrong, test


def whole(value, lo: int, hi: int | None = None) -> bool:
    """A whole number from lo to hi (or more, with no hi), and not a bool."""
    return type(value) is int and lo <= value and (hi is None or value <= hi)


A_NAME = Rule("isn't a name", lambda v: isinstance(v, str) and bool(NAME.fullmatch(v)))
TEXT = Rule("is empty", lambda v: isinstance(v, str) and bool(v.strip()))
TYPES = {bool: "true or false", str: "text", list: "a JSON list", dict: "a JSON object"}


def wrong(value, rule) -> str | None:
    """What's wrong with a value by its rule (fields()), or None."""
    shown = "" if isinstance(value, (dict, list)) else f"{value!r} "
    if isinstance(rule, Rule):
        return None if rule.test(value) else shown + rule.wrong
    if isinstance(rule, type):
        return None if isinstance(value, rule) and (rule is bool or not isinstance(value, bool)) else f"{shown}isn't {TYPES[rule]}"
    if len(rule) == 2 and type(rule[0]) is int:
        lo, hi = rule
        return None if whole(value, lo, hi) else f"{shown}isn't a whole number from {lo} " + (f"to {hi}" if hi is not None else "up")
    return None if value in rule else f"{shown}isn't one of {', '.join('null' if c is None else str(c) for c in rule)}"


def fields(rel: str, obj, schema: dict, problems: list[str], at: str = "", required=(), unknown: str = "unknown key") -> dict:
    """The keys of a file's object that its schema has, each with a value
    its rule passes, and a problem for each other, `rel: at.key: what's
    wrong`. A key's rule is (lo, hi), a whole number from lo to hi (or
    more, hi None); a type; a tuple of the values it may be; or a Rule. A
    key the schema hasn't is `unknown`, and one in `required` is missing
    without it."""
    def fail(key, what):
        where = ".".join(k for k in (at, key) if k)
        problems.append(f"{rel}: {where}: {what}" if where else f"{rel}: {what}")

    if not isinstance(obj, dict):
        fail("", "isn't a JSON object")
        return {}
    out = {}
    for key, value in obj.items():
        what = unknown if key not in schema else wrong(value, schema[key])
        if what:
            fail(key, what)
        else:
            out[key] = value
    for key in required:
        if key not in obj:
            fail(key, "missing")
    return out


def rig_channels(source: Path = RIG_H) -> dict[str, tuple[int, int, int]]:
    """The rig's channels in order, each with its lowest, highest and rest
    value: kChannelInfo in the firmware's rig.h."""
    match = re.search(r"kChannelInfo\[kChannelCount\] = \{(.*?)\};", source.read_text(), re.S)
    if not match:
        raise SystemExit(f"charactergen: no kChannelInfo in {source}")
    rows = re.findall(r'\{"(\w+)", (-?\d+), (-?\d+), (-?\d+)\}', match.group(1))
    return {name: (int(lo), int(hi), int(rest)) for name, lo, hi, rest in rows}


def outfits(source: Path = TAGS_H) -> dict[str, str]:
    """The outfits render::outfitFor picks from, by their names in a pack's
    files, each with its enumerator: {"witch_hat": "kWitchHat", ...}."""
    match = re.search(r"enum class Outfit : uint8_t \{([^}]*)\}", source.read_text())
    if not match:
        raise SystemExit(f"charactergen: no Outfit in {source}")
    names = [e for e in re.findall(r"\bk\w+", match.group(1)) if e != "kNone"]
    return {re.sub(r"(?<!^)(?=[A-Z])", "_", e[1:]).lower(): e for e in names}


def read_rig(pack: Path, moods: list[str] | None = None, states: list[str] | None = None) -> tuple[dict, list[str]]:
    """A pack's rig/ (CHARACTER.md §15) as rig_tables.h has it, and what's
    wrong with it, each problem with its file and key. Every file is
    optional, and one that's missing is empty."""
    moods = universal_moods() if moods is None else moods
    states = firmware_states() if states is None else states
    channels, folder, problems = rig_channels(), pack / "rig", []
    rig = {"eyes": [], "mouth": [], "scenes": [], "expressions": [], "clips": [], "looks": [], "accessories": []}
    # Each name a file may set, with its channel's range: eyeOpen sets both eyes.
    ranges = {**{c: (lo, hi) for c, (lo, hi, _) in channels.items()}, "eyeOpen": channels["eyeOpenL"][:2]}

    def fail(rel, key, what):
        problems.append(f"rig/{rel}: {key}: {what}" if key else f"rig/{rel}: {what}")

    def check(rel, obj, schema, **how):
        return fields(f"rig/{rel}", obj, schema, problems, **how)

    def read(rel, schema, **how):
        """A file's keys, by its schema; a missing file is empty."""
        if not (folder / rel).is_file():
            return {}
        try:
            return check(rel, json.loads((folder / rel).read_text()), schema, **how)
        except ValueError as e:
            fail(rel, "", f"isn't JSON ({e})")
            return {}

    def named(name):
        """The channels a name in a file sets."""
        return ["eyeOpenL", "eyeOpenR"] if name == "eyeOpen" else [name]

    rel = "expressions.json"
    data = read(rel, {"styles": dict, "expressions": dict})
    styles = check(rel, data.get("styles", {}), {"eyes": list, "mouth": list}, at="styles", required=("eyes", "mouth") if data else ())
    for slot, names in styles.items():
        if not (all(A_NAME.test(n) for n in names) and 0 < len(names) == len(set(names)) <= MOST):
            fail(rel, f"styles.{slot}", "isn't a list of names, each once")
            names = []
        rig[slot] = names
    pose = {**ranges, "eyes": tuple(rig["eyes"]), "mouth": tuple(rig["mouth"])}
    for mood, values in check(rel, data.get("expressions", {}), {m: dict for m in moods}, at="expressions", unknown="isn't a mood").items():
        where, said = f"expressions.{mood}", {}
        for key, value in check(rel, values, pose, at=where).items():
            if key in ("eyes", "mouth"):
                continue
            if any(c in said for c in named(key)):
                fail(rel, f"{where}.{key}", "sets a channel twice")
            else:
                said.update({c: value for c in named(key)})
        rig["expressions"].append({"mood": mood, "values": [said.get(c, rest) for c, (_, _, rest) in channels.items()],
                                   **{k: rig[k].index(values[k]) if values.get(k) in rig[k] else 0 for k in ("eyes", "mouth")}})

    clips = sorted((folder / "clips").glob("*.json")) if (folder / "clips").is_dir() else []
    if len(clips) > MOST:
        problems.append(f"rig/clips: more than {MOST} clips")
    for path in clips:
        rel = f"clips/{path.name}"
        if not NAME.fullmatch(path.stem):
            fail(rel, "", "its name, the clip's id, isn't lower case, digits, - and _")
        clip = read(rel, {"about": str, "ms": (1, 60000), "loop": bool, "additive": bool, "tracks": dict, "cues": list},
                    required=("ms",))
        if "ms" not in clip:
            continue
        ms, loop, additive = clip["ms"], clip.get("loop", False), clip.get("additive", True)
        tracks, cues = [], []
        for name, keys in check(rel, clip.get("tracks", {}), {c: list for c in ranges}, at="tracks", unknown="isn't a channel").items():
            where = f"tracks.{name}"
            if any(c == done for c in named(name) for done, _ in tracks):
                fail(rel, where, "sets a channel twice")
                continue
            lo, hi = ranges[name]
            if additive:
                lo, hi = lo - hi, hi - lo  # an offset spans the whole range, either way
            if not 0 < len(keys) <= MOST:
                fail(rel, where, f"has {len(keys)} keys, not 1 to {MOST}")
            rows = []
            for i, key in enumerate(keys):
                at = f"{where}[{i}]"
                t, value, ease = (key + ["inout"])[:3] if isinstance(key, list) and len(key) in (2, 3) else (None,) * 3
                if t is None:
                    fail(rel, at, "isn't [ms, value] or [ms, value, ease]")
                elif not whole(t, rows[-1][0] + 1 if rows else 0, ms):
                    fail(rel, at, f"its time, {t!r}, isn't a whole ms after the key before's and at most {ms}")
                elif not whole(value, lo, hi):
                    fail(rel, at, f"its value, {value!r}, isn't a whole number from {lo} to {hi}")
                elif ease not in EASES:
                    fail(rel, at, f"its ease, {ease!r}, isn't one of {', '.join(EASES)}")
                else:
                    rows.append((t, value, ease))
            if loop and rows and (rows[0][0], rows[-1][0], rows[-1][1]) != (0, ms, rows[0][1]):
                fail(rel, where, "loops, so it starts at 0 and ends at ms on the value it started on")
            tracks += [(c, rows) for c in named(name)]
        for i, cue in enumerate(clip.get("cues", [])):
            if i == MOST or not (isinstance(cue, list) and len(cue) == 2 and whole(cue[0], 0, ms - 1) and A_NAME.test(cue[1])):
                fail(rel, f"cues[{i}]", f"isn't [ms before {ms}, a name] (at most {MOST} of them)")
            else:
                cues.append((cue[0], cue[1]))
        rig["clips"].append({"id": path.stem, "ms": ms, "loop": loop, "additive": additive, "tracks": tracks, "cues": sorted(cues)})

    rel, ids = "looks.json", [c["id"] for c in rig["clips"]]
    look_schema = {"clip": Rule("isn't a clip in rig/clips/", lambda v: v is None or v in ids),
                   "scene": Rule("isn't a name, or null", lambda v: v is None or A_NAME.test(v)), "dresses": bool}
    for state, look in read(rel, {s: dict for s in states}, unknown="isn't a state the board has").items():
        look = check(rel, look, look_schema, at=state)
        clip, scene = look.get("clip"), look.get("scene")
        if clip is not None and not rig["clips"][ids.index(clip)]["loop"]:
            fail(rel, f"{state}.clip", f"{clip} doesn't loop")
        if scene and scene not in rig["scenes"]:
            rig["scenes"].append(scene)
        rig["looks"].append({"state": state, "clip": None if clip is None else ids.index(clip),
                             "scene": rig["scenes"].index(scene) + 1 if scene else 0, "dresses": look.get("dresses", False)})

    rel, worn = "accessories.json", outfits()
    for outfit, accessory in read(rel, {o: dict for o in worn}, unknown=f"isn't an outfit ({', '.join(worn)})").items():
        accessory = check(rel, accessory, {"anchor": tuple(ANCHORS), "art": A_NAME}, at=outfit, required=("anchor",))
        rig["accessories"].append({"outfit": worn[outfit], "anchor": ANCHORS.get(accessory.get("anchor")),
                                   "art": accessory.get("art", outfit)})
    return rig, problems


def rig_h(pack: Path, rig: dict) -> str:
    """The firmware's rig_tables.h, which staging writes from a pack's rig/,
    read_rig() having checked it: its rows, then kRig, which lists them."""
    out, keys, tracks, cues = [], [], [], []

    def table(kind, name, rows):
        if rows:
            out.append(f"inline constexpr {kind} {name}[] = {{\n" + "".join(f"    {row},\n" for row in rows) + "};")
        return f"{{pack::{name}, {len(rows)}}}" if rows else "{}"

    def run(name, start, count):
        return f"{{{name} + {start}, {count}}}" if count else "{}"

    def enum(name):
        return "k" + name[0].upper() + name[1:]

    clips = []
    for c in rig["clips"]:
        first, cue = len(tracks), len(cues)
        for channel, rows in c["tracks"]:
            tracks.append(f"{{Channel::{enum(channel)}, {run('kKeys', len(keys), len(rows))}}}")
            keys += [f"{{{t}, {v}, Ease::{EASES[e]}}}" for t, v, e in rows]
        cues += [f"{{{t}, {json.dumps(name)}}}" for t, name in c["cues"]]
        clips.append(f"{{{json.dumps(c['id'])}, {c['ms']}, {str(c['loop']).lower()}, {str(c['additive']).lower()}, "
                     f"{run('kTracks', first, len(c['tracks']))}, {run('kCues', cue, len(c['cues']))}}}")
    lists = [table("const char*", "kEyeStyles", [json.dumps(s) for s in rig["eyes"]]),
             table("const char*", "kMouthStyles", [json.dumps(s) for s in rig["mouth"]]),
             table("const char*", "kScenes", [json.dumps(s) for s in rig["scenes"]])]
    table("Key", "kKeys", keys)
    table("Track", "kTracks", tracks)
    table("Cue", "kCues", cues)
    lists += [table("Expression", "kExpressions",
                    [f"{{{json.dumps(e['mood'])}, {{{{{', '.join(map(str, e['values']))}}}}}, {e['eyes']}, {e['mouth']}}}"
                     for e in rig["expressions"]]),
              table("Clip", "kClips", clips),
              table("Look", "kLooks", [f"{{SceneState::{camel(l['state'])}, "
                                       f"{'nullptr' if l['clip'] is None else 'kClips + ' + str(l['clip'])}, "
                                       f"{l['scene']}, {str(l['dresses']).lower()}}}" for l in rig["looks"]]),
              table("Accessory", "kAccessories", [f"{{Outfit::{a['outfit']}, Anchor::{a['anchor']}, {json.dumps(a['art'])}}}"
                                                  for a in rig["accessories"]])]
    body = "\n".join(out)
    return f"""// Generated by characters/charactergen.py from characters/{pack.name}/rig/. Do not edit.
// The pack's rig (characters/CHARACTER.md §15): its rows, and kRig.
#pragma once
#include "render/rig/rig.h"

namespace render::rig {{
namespace pack {{
{body}
}}  // namespace pack

inline constexpr Rig kRig = {{{', '.join(lists)}}};

}}  // namespace render::rig
"""


# ── References and review (CHARACTER.md §16) ────────────────────────────────
# A reference is a folder, references/<YYYY-MM-DD>-<topic>/: the media a
# person gave (a still is one frame; a GIF or a video is cut a frame every
# FRAME_MS), reference.json, the agent's reading.md, and what `boopctl
# reference read` makes of each file, frames/<file>/NNNN.png and
# sheets/<file>.png.
FRAME_MS = 40  # 25 fps: a reference's frames, and the board's that the studio records beside them, frame for frame
MEDIA = {".png": "still", ".jpg": "still", ".jpeg": "still", ".webp": "still", ".gif": "gif",
         ".mp4": "video", ".mov": "video", ".m4v": "video", ".webm": "video"}
REFERENCE_FOLDER = re.compile(r"\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*")
KINDS = ("inspiration", "direct")
STATUSES = ("new", "read", "translated", "in review", "approved")
BECOMES = ("clip", "expression", "art")
# What an item agents put up for review (review/queue.json) may be, and a
# verdict on one, as the studio's server appends it to review/notes.jsonl.
REVIEW_STATUSES = ("in review", "changes", "approved")
NOTE = {"at": str, "id": str, "verdict": ("approve", "change"), "text": str}


def reference_folders(pack: Path) -> list[Path]:
    folder = pack / "references"
    return sorted(p for p in folder.iterdir() if not p.name.startswith(".")) if folder.is_dir() else []


def media(folder: Path) -> list[Path]:
    """A reference's media files."""
    return sorted(p for p in folder.iterdir() if p.is_file() and p.suffix.lower() in MEDIA)


def frame_count(folder: Path, name: str) -> int:
    """How many frames `boopctl reference read` cut from one of a reference's files."""
    return len(list((folder / "frames" / name).glob("*.png")))


def reference_problems(folder: Path, moods: set[str], states: list[str], rig: dict) -> list[str]:
    """What's wrong with one reference: reference.json's keys and values,
    what it became against the pack's rig (read_rig's), its files, and
    what its status says is there: the tool's frames and sheets once it's
    read, and the agent's reading.md and what it became once it's
    translated."""
    rel = "reference.json"
    try:
        raw = json.loads((folder / rel).read_text())
    except FileNotFoundError:
        return ["it has no reference.json"]
    except ValueError as e:
        return [f"{rel}: isn't JSON ({e})"]
    problems = []
    ref = fields(rel, raw, {"kind": KINDS, "note": TEXT, "status": STATUSES, "became": list, "show": dict,
                            "frames": (0, None), "ms": (0, None)}, problems, required=("kind", "note", "status"))
    made = {"clip": {c["id"] for c in rig["clips"]}, "expression": {e["mood"] for e in rig["expressions"]},
            "art": set(rig["eyes"] + rig["mouth"] + rig["scenes"]) | {a["art"] for a in rig["accessories"]}}
    for i, b in enumerate(ref.get("became", [])):
        b = fields(rel, b, {"what": BECOMES, "id": A_NAME}, problems, at=f"became[{i}]", required=("what", "id"))
        if len(b) == 2 and b["id"] not in made[b["what"]]:
            problems.append(f"it became {b['what']} {b['id']}, which rig/ hasn't")
    state = Rule("isn't one of the board's states", lambda v: v in states)
    if "show" in ref:
        fields(rel, ref["show"], {"mood": Rule("isn't one of the pack's moods", lambda v: v in moods), "state": state, "anim": state},
               problems, at="show", required=("mood", "state"))
    files, own = media(folder), {"reference.json", "reading.md", "frames", "sheets"}
    problems += [f"it has {p.name}, which isn't media ({' '.join(MEDIA)}) or the reference's own"
                 for p in sorted(folder.iterdir()) if p.name not in own and p not in files and not p.name.startswith(".")]
    if not files:
        problems.append("it has no media")
    status = STATUSES.index(ref.get("status", "new"))
    if status >= STATUSES.index("read"):
        unread = [p.name for p in files if not frame_count(folder, p.name) or not (folder / "sheets" / f"{p.name}.png").is_file()]
        cut = sum(frame_count(folder, p.name) for p in files)
        if unread:
            problems.append(f"it's {ref['status']}, and {', '.join(unread)} has no frames or sheet (boopctl reference read)")
        elif ref.get("frames") != cut or "ms" not in ref:
            problems.append(f"it's {ref['status']}, and its frames and ms aren't what frames/ holds ({cut} frames; boopctl reference read)")
    if status >= STATUSES.index("translated"):
        if not (folder / "reading.md").is_file():
            problems.append(f"it's {ref['status']}, and has no reading.md")
        if not ref.get("became"):
            problems.append(f"it's {ref['status']}, and became nothing")
    return problems


def review(pack: Path) -> tuple[list, list, list[str]]:
    """A pack's review queue (review/queue.json, which agents write), the
    notes on it (review/notes.jsonl, which the studio's server appends),
    and what's wrong with them. An item's before and after are images in
    the characters folder, by their paths from the repository's root."""
    folder, queue, notes, problems = pack / "review", [], [], []
    if (folder / "queue.json").is_file():
        try:
            queue = json.loads((folder / "queue.json").read_text())
        except ValueError as e:
            return [], [], [f"queue.json: isn't JSON ({e})"]
        if not isinstance(queue, list) or not all(isinstance(item, dict) for item in queue):
            return [], [], ["queue.json isn't a list of items"]
        def still(path):
            """A still in the characters folder, by its path from the repository's root."""
            file = pack.parent.parent / path
            return file.is_file() and MEDIA.get(file.suffix.lower()) == "still" and pack.parent.resolve() in file.resolve().parents

        image = Rule("isn't an image in the characters folder", lambda v: isinstance(v, str) and still(v))
        item_schema = {"id": A_NAME, "title": TEXT, "what": TEXT, "before": image, "after": image, "status": REVIEW_STATUSES}
        for i, item in enumerate(queue):
            fields("queue.json", item, item_schema, problems, at=item["id"] if A_NAME.test(item.get("id")) else f"[{i}]",
                   required=("id", "title", "what", "status"))
        ids = [item.get("id") for item in queue]
        if len(ids) != len(set(map(str, ids))):
            problems.append("queue.json has two items with one id")
    if (folder / "notes.jsonl").is_file():
        for number, line in enumerate((folder / "notes.jsonl").read_text().splitlines(), 1):
            rel, said = f"notes.jsonl:{number}", len(problems)
            try:
                note = json.loads(line)
            except ValueError:
                problems.append(f"{rel}: isn't JSON")
                continue
            fields(rel, note, NOTE, problems, required=tuple(NOTE))
            if len(problems) == said:
                notes.append(note)
    return queue, notes, problems


class Reads:
    """Each pack's rig/ (read_rig()) and review/ (review()), read once for
    as long as one of these is kept: main() keeps one for its run and
    hands it on, and a call given none reads afresh."""

    def __init__(self) -> None:
        self.seen: dict = {}

    def rig(self, pack: Path) -> tuple[dict, list[str]]:
        return self.once(read_rig, pack)

    def review(self, pack: Path) -> tuple[list, list, list[str]]:
        return self.once(review, pack)

    def once(self, read, pack: Path):
        key = (read, pack.resolve())
        if key not in self.seen:
            self.seen[key] = read(pack)
        return self.seen[key]


def load(pack: Path) -> dict:
    return json.loads((pack / "character.json").read_text())


def used(pack: Path, character: dict | None = None) -> tuple[dict[str, Path], list[str]]:
    """What a pack takes from others (§6): each path its `uses` brings in,
    with that file or folder in the pack that shares it, and what's wrong
    with them. `uses` names, for each share, the pack beside this one whose
    `shares` lists the share's files. A pack takes another's own files
    only, never what that one uses, and never a path it has itself."""
    character = load(pack) if character is None else character
    paths, problems = {}, []
    for share, name in character.get("uses", {}).items():
        provider = pack.parent / name
        if not (provider / "character.json").is_file():
            problems.append(f"uses {share} from {name}, which isn't a pack beside it")
            continue
        listed = load(provider).get("shares", {}).get(share)
        if listed is None:
            problems.append(f"uses {share} from {name}, which doesn't share it")
            continue
        for rel in listed.get("files", []):
            if not (provider / rel).exists():
                problems.append(f"{name}'s {share} names {rel}, which it doesn't have")
            elif (pack / rel).exists():
                problems.append(f"has {rel} of its own, and uses {name}'s ({share})")
            else:
                paths[rel] = provider / rel
    return paths, problems


def files_in(folder: Path) -> dict[str, Path]:
    """Every file in a folder or a file itself, by its path in it."""
    if folder.is_file():
        return {"": folder}
    return {p.relative_to(folder).as_posix(): p for p in sorted(folder.rglob("*"))
            if p.is_file() and ".git" not in p.relative_to(folder).parts}


def overlay(dest: Path, own: Path, extra: dict[str, Path]) -> None:
    """Lays dest out as own's files plus extra's (path: its file or folder),
    each file a link to its source in folders of their own: Foundation
    won't list a folder through a link to it."""
    files = files_in(own)
    for rel, src in extra.items():
        files.update({f"{rel}/{inner}".rstrip("/"): path for inner, path in files_in(src).items()})
    for rel, src in files.items():
        (dest / rel).parent.mkdir(parents=True, exist_ok=True)
        (dest / rel).symlink_to(src.resolve())


def previews(character: dict) -> list[dict]:
    """The pack's studio entries (§12), one for each preview it brings."""
    return [dict(e) for e in character.get("studio", [])]


def states(studio: Path = STUDIO) -> dict:
    return json.loads((studio / "states.json").read_text())


def state_ids(table: dict) -> list[str]:
    return [s["id"] for g in table["groups"] for s in g["states"]]


def firmware_states(source: Path = FIRMWARE_STATES) -> list[str]:
    """The board's state names, kStateNames in the firmware's render types."""
    match = re.search(r"kStateNames\[\d*\]\s*=\s*\{([^}]*)\}", source.read_text())
    if not match:
        raise SystemExit(f"charactergen: no kStateNames in {source}")
    return re.findall(r'"([a-z_]+)"', match.group(1))


def firmware_acts(source: Path = FIRMWARE_ACTS) -> list[str]:
    """The states the board draws while working for what the agent does, a
    `state` message's `act`: those the firmware's actFromName keeps (any
    other is plain working)."""
    match = re.search(r"SceneState actFromName\(.*?\{(.*?)return s;", source.read_text(), re.S)
    if not match:
        raise SystemExit(f"charactergen: no actFromName in {source}")
    return [re.sub(r"(?<!^)(?=[A-Z])", "_", e).lower() for e in re.findall(r"case SceneState::k(\w+):", match.group(1))]


def wears(pack: Path, entry: dict) -> dict[str, str]:
    """The moods a studio preview has no art of its own for, each with the
    mood whose art it shows instead: its `wears` file's `borrows` table
    (Pixel's temporary one), or none."""
    if not entry.get("wears"):
        return {}
    return json.loads((pack / entry["wears"]).read_text())["borrows"]


def studio_problems(packs: list[Path], studio: Path = STUDIO, source: Path = FIRMWARE_STATES, reads: Reads | None = None) -> list[str]:
    """What's wrong with the studio's data: the states it lists against the
    board's, each pack's declared files, a preview that has a mood
    wear one that isn't the pack's, and its references and review queue."""
    problems, reads = [], reads or Reads()
    table = states(studio)
    ids, board = state_ids(table), firmware_states(source)
    if sorted(ids) != sorted(board) or len(ids) != len(set(ids)):
        missing, extra = sorted(set(board) - set(ids)), sorted(set(ids) - set(board))
        problems.append(f"{studio / 'states.json'} doesn't list the board's states (missing {missing}, extra {extra})")
    for pack in packs:
        character = load(pack)
        moods, rig = {m["id"] for m in character["moods"]}, reads.rig(pack)[0]
        for folder in reference_folders(pack):
            if not folder.is_dir() or not REFERENCE_FOLDER.fullmatch(folder.name):
                problems.append(f"{pack.name}: references/{folder.name} isn't a folder named <YYYY-MM-DD>-<topic>")
                continue
            problems += [f"{pack.name}: references/{folder.name}: {p}" for p in reference_problems(folder, moods, ids, rig)]
        problems += [f"{pack.name}: review/{p}" for p in reads.review(pack)[2]]
        entries = previews(character)
        names = [e.get("id") for e in entries + [e for _, e in shared_previews(pack, character)] + boards(character)]
        if None in names or len(names) != len(set(names)):
            problems.append(f"{pack.name}: each of its studio entries needs an id of its own")
            continue
        for entry in entries:
            absent = [n for n in files(entry) + [entry.get("wears")] if n and not (pack / n).is_file()]
            problems += [f"{pack.name}: studio file {name} doesn't exist" for name in absent]
            if absent:
                continue
            moods = {m["id"] for m in character["moods"]}
            for mood, worn in wears(pack, entry).items():
                if mood not in moods or worn not in moods:
                    problems.append(f"{pack.name}: {entry['id']}'s preview has {mood} wear {worn}, which isn't a mood of its")
    return problems


def state_problems(packs: list[Path], source: Path = FIRMWARE_STATES, spec: Path = CHARACTERS / "CHARACTER.md") -> list[str]:
    """The board's states against what names them elsewhere: CHARACTER.md's
    tables of every state a face is asked for (§9), and each pack's
    mac/faces.json, whose designs have a row for each."""
    board = firmware_states(source)
    problems = []
    text = spec.read_text()
    start = text.find("### Every state a face is asked for")
    section = text[start:text.find("\n### ", start + 1)] if start >= 0 else ""
    listed = re.findall(r"^\| `([a-z_]+)` \|", section, re.M)
    if sorted(listed) != sorted(board):
        missing, extra = sorted(set(board) - set(listed)), sorted(set(listed) - set(board))
        problems.append(f"{spec.name} §9 doesn't list the board's states (missing {missing}, extra {extra})")
    for pack in packs:
        faces = pack / "mac" / "faces.json"
        if not faces.is_file():
            continue
        table = json.loads(faces.read_text())
        if table.get("states") != board:
            problems.append(f"{pack.name}: mac/faces.json's states aren't the board's, in its order")
        rows = {m: len(r) for m, r in table.get("designs", {}).items()}
        short = sorted(m for m in table.get("moods", []) if rows.get(m) != len(board))
        if short:
            problems.append(f"{pack.name}: mac/faces.json has no row for each state in {', '.join(short)}")
    return problems


def files(entry: dict) -> list[str]:
    """The files a studio entry has the page load or show."""
    return entry.get("scripts", []) + entry.get("styles", []) + [entry[k] for k in ("icon", "captures") if entry.get(k)]


def shared_previews(pack: Path, character: dict) -> list[tuple[Path, dict]]:
    """The studio entries a pack takes with what it uses (§6): each share's
    `studio` ids, with the pack that shares them."""
    out = []
    for share, name in character.get("uses", {}).items():
        provider = pack.parent / name
        if (provider / "character.json").is_file():
            ids = load(provider).get("shares", {}).get(share, {}).get("studio", [])
            out += [(provider, e) for e in previews(load(provider)) if e.get("id") in ids]
    return out


def boards(character: dict) -> list[dict]:
    """The studio's own preview of each face the pack's boards have (§9):
    the board's firmware itself, built to WebAssembly (simulator/README.md)."""
    faces = list(dict.fromkeys(character.get("faces", {}).values()))
    return [{"id": f"board-{face}", "label": f"{face.title()} on the board", "about": "its firmware, in WebAssembly",
             "icon": "board.svg", "board": face, "scripts": [], "styles": [], "wears": {}} for face in faces]


def references_data(pack: Path, here) -> list[dict]:
    """Each reference, as the studio shows it: reference.json, the reading,
    and each file with the frames cut from it."""
    out = []
    for folder in reference_folders(pack):
        try:
            ref = json.loads((folder / "reference.json").read_text())
        except (OSError, ValueError):
            continue  # --check says why
        reading = folder / "reading.md"
        out.append({**ref, "id": folder.name, "path": here(folder) + "/", "became": ref.get("became", []),
                    "reading": reading.read_text() if reading.is_file() else None,
                    "media": [{"file": p.name, "kind": MEDIA[p.suffix.lower()], "frames": frame_count(folder, p.name)}
                              for p in media(folder)]})
    return out


def studio_data(packs: list[Path], chosen_pack: Path, studio: Path = STUDIO, reads: Reads | None = None) -> dict:
    """The studio page's data: the engine's states, with the acts the board
    draws while working; the frames' interval; the staged pack; and, for
    each pack, its moods, its studio entries (its own, those it uses and a
    board for each face), its references, and its review queue and notes,
    with paths from the page."""
    last, reads = staged(), reads or Reads()
    data = {"chosen": chosen_pack.name, "staged": own_folder(last).name if last else None,
            "states": {**states(studio), "acts": firmware_acts()}, "frame_ms": FRAME_MS, "packs": {}}
    page = lambda path: Path(os.path.relpath(path, studio)).as_posix()
    for pack in packs:
        character = load(pack)
        entries = [(pack, e) for e in previews(character)] + shared_previews(pack, character)
        for home, entry in entries:
            borrows = wears(home, entry)
            for key in ("scripts", "styles"):
                entry[key] = [page(home / name) for name in entry.get(key, [])]
            if entry.get("icon"):
                entry["icon"] = page(home / entry["icon"])
            entry["wears"] = dict(sorted(borrows.items()))
            entry.pop("captures", None)
        queue, notes, _ = reads.review(pack)
        data["packs"][pack.name] = {
            "name": character["name"],
            "default_mood": character["default_mood"],
            "moods": [{k: m[k] for k in ("id", "meaning", "family") if k in m} for m in character["moods"]],
            "studio": [entry for _, entry in entries] + boards(character),
            "references": references_data(pack, page),
            "review": {"queue": [{**item, **{k: page(pack.parent.parent / item[k]) for k in ("before", "after")
                                             if isinstance(item.get(k), str)}} for item in queue], "notes": notes},
        }
    return data


def local_packs(also: Path | None = None) -> list[Path]:
    packs = [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]
    if also and also not in packs and (also / "character.json").exists():
        packs.append(also)
    return packs


def write_studio(pack: Path, check: bool, reads: Reads | None = None) -> int:
    """Checks the studio's data and writes characters/studio/packs.js, which
    opens on `pack`. Problems fail --check and only warn otherwise."""
    packs, reads = local_packs(pack), reads or Reads()
    problems = studio_problems(packs, reads=reads) + state_problems(packs)
    for problem in problems:
        print(("CHARACTERGEN FAIL: " if check else "charactergen: warning: ") + problem, file=sys.stderr)
    data = json.dumps(studio_data(packs, pack, reads=reads), indent=1)
    (STUDIO / "packs.js").write_text(f"// Generated by characters/charactergen.py. Do not edit.\nwindow.StudioData = {data};\n")
    return 1 if check and problems else 0


def pack_problems(pack: Path, character: dict, reads: Reads | None = None) -> list[str]:
    """What stops a pack from staging: its moods (§5), what it uses (§6),
    an id or version too long for the board's hello (§10), and its rig
    (§15)."""
    paths, problems = used(pack, character)
    problems = mood_problems(character, universal_moods()) + problems
    if len(character.get("id", "")) > 24 or len(character.get("version", "")) > 16:
        problems.append("id is at most 24 characters, and version 16")
    # Each board's face (§9): a folder of the pack's, or one it uses.
    if not character.get("faces"):
        problems.append("faces names no board's face")
    for board, face in character.get("faces", {}).items():
        folder = f"firmware/src/render/{face}"
        if not (pack / folder).is_dir() and not (folder in paths and paths[folder].is_dir()):
            problems.append(f"faces gives {board} the {face} face, and there's no {folder}/")
    return problems + (reads or Reads()).rig(pack)[1]


def check(pack: Path, reads: Reads | None = None) -> int:
    character = load(pack)
    problems = pack_problems(pack, character, reads)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    if not problems:
        print(f"CHARACTERGEN PASS: {character['id']}")
    return 1 if problems else 0


def bundle(view: Path, name: str) -> None:
    """A staged pack as the Mac app bundles it, with what the app reads and
    no more: .character-build/packs/<name>/."""
    shutil.copytree(view, STAGE / "packs" / name,
                    ignore=shutil.ignore_patterns(".git", "firmware", "voice", "Makefile", "tools", "tests", "design", "evals",
                                                  "studio", "rig", "references", "review"))


def checked_pack(pack: Path, reads: Reads | None = None) -> tuple[dict, dict[str, Path]] | None:
    """A pack's character.json and what it uses from other packs (§6), or
    None, its problems printed, for a pack that can't be staged."""
    character = load(pack)
    problems = pack_problems(pack, character, reads)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    return None if problems else (character, used(pack, character)[0])


def stage(pack: Path, reads: Reads | None = None) -> int:
    """The pack staged (.character-build/staged/<name>/): its own files and
    what it uses from other packs (§6), as links, the one folder the tests,
    boopdev and the device tools read, and the pointer to it
    (.character-build/pack); from it, the firmware's files
    (.character-build/firmware/) with the generated moods.h and
    rig_tables.h, and the pack
    as the Mac app bundles it, with what the app reads and no more
    (.character-build/packs/<name>/), beside every other pack beside it
    for buddies that run one, with packs/chosen naming this one."""
    reads = reads or Reads()
    checked = checked_pack(pack, reads)
    if checked is None:
        return 1
    character, paths = checked
    STAGE.mkdir(exist_ok=True)
    for old in ("staged", "firmware", "packs"):
        if (STAGE / old).exists():
            shutil.rmtree(STAGE / old)
    view = STAGE / "staged" / pack.name
    overlay(view, pack, paths)
    firmware_from(view, pack, character, STAGE / "firmware")
    bundle(view, pack.name)
    # Every other pack beside it goes in the app too, for buddies that run
    # another pack (CHARACTER.md §2). The chosen one is named in
    # packs/chosen.
    for other in sorted(p.parent for p in own_folder(pack).parent.glob("*/character.json")):
        if other.resolve() == own_folder(pack) or pack_problems(other, load(other), reads):
            continue
        with tempfile.TemporaryDirectory() as temp:
            overlay(Path(temp) / other.name, other, used(other)[0])
            bundle(Path(temp) / other.name, other.name)
    (STAGE / "packs" / "chosen").write_text(f"{pack.name}\n")
    # The firmware's test suites: the engine's, then the staged pack's
    # (tests/firmware/test_*), linked so an edit lands in the real file.
    tests = STAGE / "firmware-test"
    if tests.exists():
        shutil.rmtree(tests)
    tests.mkdir(parents=True)
    for folder in [ROOT / "internal" / "firmware" / "test", view / "tests" / "firmware"]:
        for suite in sorted(folder.glob("test_*")) if folder.is_dir() else []:
            if (tests / suite.name).is_symlink():
                (tests / suite.name).unlink()
            (tests / suite.name).symlink_to(suite.resolve())
    (STAGE / "pack").write_text(f"{view}\n")
    return 0


def firmware_from(view: Path, pack: Path, character: dict, dest: Path) -> None:
    """The firmware's files from a pack's staged view: its firmware/ folder,
    the moods.h made from character.json and the rig_tables.h from rig/."""
    if (view / "firmware").is_dir():
        shutil.copytree(view / "firmware", dest)
    (dest / "include").mkdir(parents=True, exist_ok=True)
    (dest / "include" / "moods.h").write_text(moods_h(pack, character))
    (dest / "include" / "rig_tables.h").write_text(rig_h(pack, read_rig(view)[0]))


def firmware_to(pack: Path, dest: Path) -> int:
    """Only the firmware's files for a pack, in dest/firmware/, as --stage
    lays them out, and nothing else: the staged pack and the pack in use
    stay as they are. For a second build beside the staged one (the
    simulator's page with a board for each pack)."""
    checked = checked_pack(pack)
    if checked is None:
        return 1
    character, paths = checked
    if dest.exists():
        shutil.rmtree(dest)
    overlay(dest / "view", pack, paths)
    firmware_from(dest / "view", pack, character, dest / "firmware")
    shutil.rmtree(dest / "view")
    return 0


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    rest = [a for a in argv if not a.startswith("--")]
    pack = Path(rest[0]).resolve() if rest else in_use() if "--which" in argv else chosen()
    if not (pack / "character.json").exists():
        print(f"charactergen: {pack} isn't a character pack (no character.json)", file=sys.stderr)
        return 1
    if "--which" in argv:
        print(pack)
        return 0
    reads = Reads()  # each pack's rig/ and review/, read once this run
    if "--stage" in argv:
        return stage(pack, reads) | write_studio(pack, False, reads)
    to = [a.split("=", 1)[1] for a in argv if a.startswith("--firmware-to=")]
    if to:
        return firmware_to(pack, Path(to[0]).resolve())
    if "--check" not in argv:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    status = 0
    for each in ([pack] if rest else [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]):
        status |= check(each, reads)
    return status | write_studio(pack, True, reads)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
