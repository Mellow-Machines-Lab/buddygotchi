#!/usr/bin/env python3
"""Builds and stages character packs (characters/CHARACTER.md).

    characters/charactergen.py --check [PACK]
    characters/charactergen.py --stage [PACK]
    characters/charactergen.py --firmware-to=DIR [PACK]
    characters/charactergen.py --which
    characters/charactergen.py --boards [PACK]

--check checks that a pack builds: its character.json has the moods and
the startup mood moods.h needs, and an id and version that fit the board's hello (§10); and its rig/
(§15) has no unknown key, channel or name, and every value in its range.
Without PACK, every pack in characters/. Whether a pack plays, its moods
and their graph included, is `boopdev check`'s, as the app loads it.

--stage lays the chosen pack's files out in .character-build/ at the repo
root for the builds to read (§2), and two headers it makes for the firmware: moods.h from character.json,
the mood list in the pack's order with the board's startup mood, and
rig_tables.h from rig/, the rig's tables. It checks the pack as --check
does first. firmware/tools/pio.sh runs it before every PlatformIO build.

--firmware-to=DIR lays out only the firmware's files for a pack, as
--stage does, in DIR/firmware/, and changes nothing staged: for a second
build beside the staged pack's (simulator/web/build.sh PACK).

--which prints the folder of the pack in use: the one everything that runs
after a build reads (in_use()).

--boards prints the boards a pack has a face for (its `faces`), the
envs its firmware builds for. It reads the chosen pack without PACK.

Every form but --which and --firmware-to also checks the board's states
against CHARACTER.md §9, each pack's studio entry (§12) and references
(§16), and writes characters/studio/packs.js, the studio page's data for
the packs in this checkout, which git ignores. --check fails on a problem
with any of them; --stage only warns. --check also prints each pack's
gaps, what it lacks that doesn't stop it (gaps()), and passes with them.

PACK is a pack's folder. Without one, the chosen pack is the first of:
$BOOP_CHARACTER (a folder), $CHARACTER (a name in characters/), the name or
folder in the repo's .character file, and characters/boop/. Staging
writes the staged pack's folder in .character-build/pack, the one pointer
to it; the pack in use is the one the environment chooses (staged, if it's
the one staged), else the staged one, else the chosen one (nothing staged
yet).
"""
from __future__ import annotations

import filecmp
import json
import math
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
# The rig's channels, and the tags an occasion may need, as the firmware has them.
RIG_H = ROOT / "firmware" / "src" / "render" / "rig" / "rig.h"
TAGS_H = ROOT / "firmware" / "src" / "render" / "tags.h"


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
    staged is read staged. The
    Swift and C++ code keeps the same rule by reading the environment and
    the pointer."""
    last = staged()
    if os.environ.get("BOOP_CHARACTER") or os.environ.get("CHARACTER"):
        pack = chosen()
        return last if last and (last / "character.json").exists() and own_folder(last) == pack.resolve() else pack
    return last or chosen()


def camel(mood: str) -> str:
    return "k" + "".join(part.capitalize() for part in mood.split("_"))


def board_moods(character: dict) -> list[str]:
    """Every face the board draws by name, the firmware's Mood order: the
    pack's `moods`, then its `board_faces`, which the Mac doesn't read, so
    no rule or brain picks one yet (§4)."""
    return [m.get("id") for m in character.get("moods", []) + character.get("board_faces", [])]


def moods_h(pack: Path, character: dict) -> str:
    """The firmware's moods.h, which staging writes: the mood list in the
    pack's order with the board's startup mood, and the pack's id and
    version for the board's hello. The app's loader checks the moods
    themselves (boopdev check); pack_problems() that there are some."""
    moods = board_moods(character)
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
// The name it goes by until the Mac says otherwise (`state`'s `buddy`).
constexpr const char* kBuddyName = {json.dumps(character["name"])};

}}  // namespace render
"""


EASES = {"linear": "kLinear", "in": "kIn", "out": "kOut", "inout": "kInOut"}
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


def tag_names(source: Path = TAGS_H) -> list[str]:
    """The tags in their bits' order: kTagNames in the firmware's tags.h."""
    match = re.search(r"kTagNames\[kTagCount\] = \{(.*?)\};", source.read_text(), re.S)
    if not match:
        raise SystemExit(f"charactergen: no kTagNames in {source}")
    return re.findall(r'"(\w+)"', match.group(1))


def read_rig(pack: Path, states: list[str] | None = None) -> tuple[dict, list[str]]:
    """A pack's rig/ (CHARACTER.md §15) as rig_tables.h has it, and what's
    wrong with it, each problem with its file and key. Every file is
    optional, and one that's missing is empty."""
    states = firmware_states() if states is None else states
    channels, folder, problems = rig_channels(), pack / "rig", []
    rig = {"clips": [], "looks": []}
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

    clips = sorted((folder / "clips").glob("*.json")) if (folder / "clips").is_dir() else []
    if len(clips) > MOST:
        problems.append(f"rig/clips: more than {MOST} clips")
    moves = []  # (rel, id, the clip it's a move of, its size, its ms)
    for path in clips:
        rel = f"clips/{path.name}"
        if not NAME.fullmatch(path.stem):
            fail(rel, "", "its name, the clip's id, isn't lower case, digits, - and _")
        # Another clip's move at a size and a pace: its keys and cues are
        # that one's, its values times size / 1000, played over its ms.
        try:
            given = json.loads((folder / rel).read_text())
        except ValueError:
            given = None
        if isinstance(given, dict) and "of" in given:
            move = read(rel, {"about": str, "of": str, "size": (1, 4000), "ms": (1, 60000)}, required=("of", "ms"))
            if {"of", "ms"} <= move.keys():
                moves.append((rel, path.stem, move["of"], move.get("size", 1000), move["ms"]))
            continue
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
            if i == MOST or not (isinstance(cue, list) and len(cue) == 2 and whole(cue[0], 0, ms - 1) and NAME.fullmatch(str(cue[1]))):
                fail(rel, f"cues[{i}]", f"isn't [ms before {ms}, a name] (at most {MOST} of them)")
            else:
                cues.append((cue[0], cue[1]))
        rig["clips"].append({"id": path.stem, "ms": ms, "loop": loop, "additive": additive, "tracks": tracks,
                             "cues": sorted(cues)})
    own = {c["id"]: c for c in rig["clips"]}
    for rel, id, of, size, ms in moves:
        base = own.get(of)
        if base is None:
            fail(rel, "of", f"{of!r} isn't a clip in rig/clips/ with keys of its own")
        elif size != 1000 and not base["additive"]:
            fail(rel, "size", f"{of} is absolute, so it has no size but 1000")
        else:
            rig["clips"].append({**base, "id": id, "ms": ms, "of": of, "size": size})
    # In the files' order, as looks.json's indices count them.
    rig["clips"].sort(key=lambda c: c["id"] + ".json")

    rel, ids, tags = "looks.json", [c["id"] for c in rig["clips"]], tag_names()
    a_clip = Rule("isn't a clip in rig/clips/", lambda v: v is None or v in ids)
    some_tags = Rule(f"isn't a list of tags, each once ({', '.join(tags)})",
                     lambda v: isinstance(v, list) and len(set(v)) == len(v) and all(t in tags for t in v))
    tiers = [t for t in tags if re.fullmatch(r"tier\d", t)]
    for state, look in read(rel, {s: dict for s in states}, unknown="isn't a state the board has").items():
        look = check(rel, look, {"clip": a_clip, "occasions": list, "tiers": dict, "acts": dict}, at=state)
        clip, occasions, tiered, acted = look.get("clip"), [], [], []
        if clip is not None and not rig["clips"][ids.index(clip)]["loop"]:
            fail(rel, f"{state}.clip", f"{clip} doesn't loop")
        # A base clip for each tier the look names, in place of its own while
        # that tier is the last reached.
        for tier, base in check(rel, look.get("tiers", {}), {t: a_clip for t in tiers}, at=f"{state}.tiers",
                                unknown="isn't a tier").items():
            if base is None:
                continue
            if not rig["clips"][ids.index(base)]["loop"]:
                fail(rel, f"{state}.tiers.{tier}", f"{base} doesn't loop")
            else:
                tiered.append({"clip": ids.index(base), "when": 1 << tags.index(tier)})
        # A base clip for each activity the look names, in place of its own
        # and of any tier's while the agents' activity is that state.
        for act, base in check(rel, look.get("acts", {}), {s: a_clip for s in states}, at=f"{state}.acts",
                               unknown="isn't a state the board has").items():
            if base is None:
                continue
            if not rig["clips"][ids.index(base)]["loop"]:
                fail(rel, f"{state}.acts.{act}", f"{base} doesn't loop")
            else:
                acted.append({"clip": ids.index(base), "act": act})
        for i, given in enumerate(look.get("occasions", [])):
            where = f"{state}.occasions[{i}]"
            if i == MOST:
                fail(rel, where, f"is one more than {MOST}")
                break
            occasion = check(rel, given, {"clip": a_clip, "when": some_tags, "after": (0, 65535)}, at=where,
                             required=("clip",))
            if occasion.get("clip") is None:
                continue
            if rig["clips"][ids.index(occasion["clip"])]["loop"]:
                fail(rel, f"{where}.clip", f"{occasion['clip']} loops, and an occasion plays once")
            elif not (given.get("when") or given.get("after")):
                fail(rel, where, "needs a tag or a wait, or it would always fit")
            elif occasion.keys() == given.keys():
                occasions.append({"clip": ids.index(occasion["clip"]),
                                  "when": sum(1 << tags.index(t) for t in occasion.get("when", [])),
                                  "after": occasion.get("after", 0)})
        rig["looks"].append({"state": state, "clip": None if clip is None else ids.index(clip), "occasions": occasions,
                             "tiers": tiered, "acts": acted})
    return rig, problems


def rig_h(pack: Path, rig: dict) -> str:
    """The firmware's rig_tables.h, which staging writes from a pack's rig/,
    read_rig() having checked it: its rows, then kRig, which lists them."""
    out, keys, tracks, cues, clips = [], [], [], [], []

    def table(kind, name, rows):
        if rows:
            out.append(f"inline constexpr {kind} {name}[] = {{\n" + "".join(f"    {row},\n" for row in rows) + "};")
        return f"{{pack::{name}, {len(rows)}}}" if rows else "{}"

    def run(name, start, count):
        return f"{{{name} + {start}, {count}}}" if count else "{}"

    # Each clip's tracks and cues, where they start in their tables: a move
    # of another's is that one's.
    runs = {}
    for c in rig["clips"]:
        if "of" in c:
            continue
        runs[c["id"]] = len(tracks), len(cues)
        for channel, rows in c["tracks"]:
            tracks.append(f"{{Channel::k{channel[0].upper()}{channel[1:]}, {run('kKeys', len(keys), len(rows))}}}")
            keys += [f"{{{t}, {v}, Ease::{EASES[e]}}}" for t, v, e in rows]
        cues += [f"{{{t}, {json.dumps(name)}}}" for t, name in c["cues"]]
    by_id = {c["id"]: c for c in rig["clips"]}
    for c in rig["clips"]:
        first, cue = runs[c.get("of", c["id"])]
        row = (f"{{{json.dumps(c['id'])}, {c['ms']}, {str(c['loop']).lower()}, {str(c['additive']).lower()}, "
               f"{run('kTracks', first, len(c['tracks']))}")
        if "of" in c:
            row += f", {run('kCues', cue, len(c['cues']))}, {c['size']}, {by_id[c['of']]['ms']}"
        elif c["cues"]:
            row += f", {run('kCues', cue, len(c['cues']))}"
        clips.append(row + "}")
    occasions, tiers, acts, looks = [], [], [], []
    for l in rig["looks"]:
        first, tier, act = len(occasions), len(tiers), len(acts)
        acts += [f"{{kClips + {a['clip']}, SceneState::{camel(a['act'])}}}" for a in l.get("acts", [])]
        some_tiers, some_acts = l.get("tiers"), l.get("acts")
        occasions += [f"{{kClips + {o['clip']}, {o['when']}u, {o['after']}}}" for o in l["occasions"]]
        tiers += [f"{{kClips + {t['clip']}, {t['when']}u}}" for t in l.get("tiers", [])]
        looks.append(f"{{SceneState::{camel(l['state'])}, {'nullptr' if l['clip'] is None else 'kClips + ' + str(l['clip'])}, "
                     f"{run('kOccasions', first, len(l['occasions']))}"
                     + (f", {run('kTiers', tier, len(l['tiers'])) if some_tiers else '{}'}" if some_tiers or some_acts else "")
                     + (f", {run('kActs', act, len(l['acts']))}" if some_acts else "") + "}")
    table("Key", "kKeys", keys)
    table("Track", "kTracks", tracks)
    table("Cue", "kCues", cues)
    # The rig's expressions are none: only the pixel face drew them.
    lists = ["{}", table("Clip", "kClips", clips)]
    table("Occasion", "kOccasions", occasions)
    table("TierClip", "kTiers", tiers)
    table("ActClip", "kActs", acts)
    lists.append(table("Look", "kLooks", looks))
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


# ── References (CHARACTER.md §16) ───────────────────────────────────────────
# A reference is a folder, references/<YYYY-MM-DD>-<topic>/: the media a
# person gave (a still is one frame; a GIF or a video is cut a frame every
# FRAME_MS), reference.json, the agent's reading.md, and what `boopctl
# reference read` makes of each file, frames/<file>/NNNN.png and
# sheets/<file>.png. The sheets are committed; the frames, heavy for a
# video, stay where they were cut, so a checkout may have none.
FRAME_MS = 40  # 25 fps: a reference's frames, and the board's that a pack's studio tools record
MEDIA = {".png": "still", ".jpg": "still", ".jpeg": "still", ".webp": "still", ".gif": "gif",
         ".mp4": "video", ".mov": "video", ".m4v": "video", ".webm": "video"}
REFERENCE_FOLDER = re.compile(r"\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*")
KINDS = ("inspiration", "direct")
STATUSES = ("new", "read", "translated", "in review", "approved")
BECOMES = ("clip",)


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
    what its status says is there: the tool's sheets once it's read, with
    frames and ms that count its frames where this checkout has cut them,
    and the agent's reading.md and what it became once it's translated."""
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
    made = {"clip": {c["id"] for c in rig["clips"]}}
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
        unread = [p.name for p in files if not (folder / "sheets" / f"{p.name}.png").is_file()]
        cut = all(frame_count(folder, p.name) for p in files)
        count = sum(frame_count(folder, p.name) for p in files)
        if unread:
            problems.append(f"it's {ref['status']}, and {', '.join(unread)} has no sheet (boopctl reference read)")
        elif "frames" not in ref or "ms" not in ref:
            problems.append(f"it's {ref['status']}, and reference.json has no frames or ms (boopctl reference read)")
        elif cut and ref["frames"] != count:
            problems.append(f"it's {ref['status']}, and its frames aren't what frames/ holds ({count} frames; boopctl reference read)")
    if status >= STATUSES.index("translated"):
        if not (folder / "reading.md").is_file():
            problems.append(f"it's {ref['status']}, and has no reading.md")
        if not ref.get("became"):
            problems.append(f"it's {ref['status']}, and became nothing")
    return problems


class Reads:
    """Each pack's rig/ (read_rig()), read once for as long as one of these
    is kept: main() keeps one for its run and hands it on, and a call given
    none reads afresh."""

    def __init__(self) -> None:
        self.seen: dict = {}

    def rig(self, pack: Path) -> tuple[dict, list[str]]:
        return self.once(read_rig, pack)

    def once(self, read, pack: Path):
        key = (read, pack.resolve())
        if key not in self.seen:
            self.seen[key] = read(pack)
        return self.seen[key]


def load(pack: Path) -> dict:
    return json.loads((pack / "character.json").read_text())


def files_in(folder: Path) -> dict[str, Path]:
    """Every file in a folder or a file itself, by its path in it."""
    if folder.is_file():
        return {"": folder}
    return {p.relative_to(folder).as_posix(): p for p in sorted(folder.rglob("*"))
            if p.is_file() and ".git" not in p.relative_to(folder).parts}


# What makes a pack that nothing staged reads (§2): its art's sources, and
# its references, which boopctl reference reads from the pack itself.
UNSTAGED = ("design", "references")


def overlay(dest: Path, own: Path) -> None:
    """Lays dest out as own's files, each a link to its source in folders
    of their own: Foundation won't list a folder through a link to it.
    UNSTAGED stays out."""
    files = files_in(own)
    for rel, src in files.items():
        if rel.split("/", 1)[0] in UNSTAGED:
            continue
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
    mood whose art it shows instead: its `wears` file's `borrows` table,
    or none."""
    if not entry.get("wears"):
        return {}
    return json.loads((pack / entry["wears"]).read_text())["borrows"]


def studio_problems(packs: list[Path], studio: Path = STUDIO, source: Path = FIRMWARE_STATES, reads: Reads | None = None) -> list[str]:
    """What's wrong with the studio's data: the states it lists against the
    board's, each pack's declared files, a preview that has a mood
    wear one that isn't the pack's, and its references."""
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
        entries = previews(character)
        names = [e.get("id") for e in entries + boards(character)]
        if None in names or len(names) != len(set(names)):
            problems.append(f"{pack.name}: each of its studio entries needs an id of its own")
            continue
        faces = set(character.get("faces", {}).values())
        for entry in entries:
            if entry.get("board") and (entry["board"] not in faces or entry.get("id") != f"board-{entry['board']}"):
                problems.append(f"{pack.name}: studio entry {entry.get('id')} is for a board, so its id is board-<face> for one of its faces ({', '.join(sorted(faces))})")
            absent = [n for n in files(entry) + [entry.get("wears")] if n and not (pack / n).is_file()]
            problems += [f"{pack.name}: studio file {name} doesn't exist" for name in absent]
            if absent:
                continue
            moods = {m["id"] for m in character["moods"]}
            for mood, worn in wears(pack, entry).items():
                if mood not in moods or worn not in moods:
                    problems.append(f"{pack.name}: {entry['id']}'s preview has {mood} wear {worn}, which isn't a mood of its")
    return problems


def state_problems(source: Path = FIRMWARE_STATES, spec: Path = CHARACTERS / "CHARACTER.md") -> list[str]:
    """The board's states against CHARACTER.md's tables of every state a
    face is asked for (§9)."""
    board = firmware_states(source)
    problems = []
    text = spec.read_text()
    start = text.find("### Every state a face is asked for")
    section = text[start:text.find("\n### ", start + 1)] if start >= 0 else ""
    listed = re.findall(r"^\| `([a-z_]+)` \|", section, re.M)
    if sorted(listed) != sorted(board):
        missing, extra = sorted(set(board) - set(listed)), sorted(set(listed) - set(board))
        problems.append(f"{spec.name} §9 doesn't list the board's states (missing {missing}, extra {extra})")
    return problems


def files(entry: dict) -> list[str]:
    """The files a studio entry has the page load or show."""
    return entry.get("scripts", []) + entry.get("styles", []) + [entry[k] for k in ("icon", "captures") if entry.get(k)]


def boards(character: dict) -> list[dict]:
    """The studio's own preview of each face the pack's boards have (§9):
    the board's firmware itself, built to WebAssembly (simulator/README.md).
    A face's board the pack gives an entry of its own (`board`) is that
    entry's, which the page shows in its place."""
    faces = list(dict.fromkeys(character.get("faces", {}).values()))
    own = {e.get("board") for e in previews(character)}
    return [board(face) for face in faces if face not in own]


def board(face: str) -> dict:
    return {"id": f"board-{face}", "label": f"{face.title()} on the board", "about": "its firmware, in WebAssembly",
            "icon": "board.svg", "board": face, "scripts": [], "styles": [], "wears": {}}


def studio_data(packs: list[Path], chosen_pack: Path, studio: Path = STUDIO) -> dict:
    """The studio page's data: the engine's states, with the acts the board
    draws while working; the frames' interval; the staged pack; and, for
    each pack, its moods and its studio entries (its own and a board for
    each face), with paths from the page."""
    last = staged()
    # The staged pack by the name the page and the board's hello know it by (its staged folder's, its id),
    # not its own folder's, which a character repository calls character/.
    data = {"chosen": chosen_pack.name, "staged": last.name if last else None,
            "states": {**states(studio), "acts": firmware_acts()}, "frame_ms": FRAME_MS, "packs": {}}
    page = lambda path: Path(os.path.relpath(path, studio)).as_posix()
    for pack in packs:
        character = load(pack)
        entries = [(pack, e) for e in previews(character)]
        for i, (home, entry) in enumerate(entries):
            borrows = wears(home, entry)
            for key in ("scripts", "styles"):
                entry[key] = [page(home / name) for name in entry.get(key, [])]
            if entry.get("icon"):
                entry["icon"] = page(home / entry["icon"])
            entry["wears"] = dict(sorted(borrows.items()))
            entry.pop("captures", None)
            if entry.get("board"):  # its board's card, with what the pack adds
                entries[i] = (home, {**board(entry["board"]), **entry})
        data["packs"][pack.name] = {
            "name": character["name"],
            "default_mood": character["default_mood"],
            # Each face, with the meaning of the lasting mood it's the own face of.
            "moods": [{k: v for k in ("id", "meaning", "family", "settles") if (v := m.get(k, means.get(m["id"]) if k == "meaning" else None))}
                      for means in [{l["id"]: l["meaning"] for l in character.get("lasting", [])}] for m in character["moods"]],
            "studio": [entry for _, entry in entries] + boards(character),
        }
    return data


def known_packs() -> dict[str, str]:
    """The packs the engine is tested with, each in a repository of its own
    (characters/packs.json), which internal/tools/packs.sh fetches."""
    listed = CHARACTERS / "packs.json"
    return json.loads(listed.read_text()) if listed.is_file() else {}


def local_packs(also: Path | None = None) -> list[Path]:
    packs = [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]
    if also and also not in packs and (also / "character.json").exists():
        packs.append(also)
    return packs


def write_studio(pack: Path, check: bool, reads: Reads | None = None) -> int:
    """Checks the studio's data and writes characters/studio/packs.js, which
    opens on `pack`. Problems fail --check and only warn otherwise."""
    packs, reads = local_packs(pack), reads or Reads()
    problems = studio_problems(packs, reads=reads) + state_problems()
    for problem in problems:
        print(("CHARACTERGEN FAIL: " if check else "charactergen: warning: ") + problem, file=sys.stderr)
    data = json.dumps(studio_data(packs, pack), indent=1)
    (STUDIO / "packs.js").write_text(f"// Generated by characters/charactergen.py. Do not edit.\nwindow.StudioData = {data};\n")
    return 1 if check and problems else 0


def pack_problems(pack: Path, character: dict, reads: Reads | None = None) -> list[str]:
    """What stops a pack from building: moods.h's moods and default mood,
    an id or version too long for the board's hello (§10), and its rig
    (§15). Whether it plays, its moods
    and their graph included, is boopdev check's (PackCheck), as the app
    loads it."""
    problems = []
    if not character.get("moods") or not all(m.get("id") for m in character["moods"]):
        problems.append("moods names no mood, or one without an id")
    if character.get("startup_mood", character.get("default_mood")) not in [m.get("id") for m in character.get("moods", [])]:
        problems.append("its startup_mood, else its default_mood, isn't one of its moods")
    faces = {m.get("id") for m in character.get("moods", [])}
    drawn = board_moods(character)
    if not all(drawn) or len(drawn) != len(set(drawn)):
        problems.append("moods and board_faces name a face twice, or one without an id")
    lasting_ids = [m.get("id") for m in character.get("lasting", [])]
    for m in character.get("board_faces", []):
        if m.get("settles") not in lasting_ids:
            problems.append(f"board face {m.get('id')} settles into no lasting mood")
    for m in character.get("lasting", []):
        missing = [f for f in m.get("levels") or [m.get("id")] if f not in faces]
        if missing:
            problems.append(f"lasting mood {m.get('id')} rests in {', '.join(map(str, missing))}, not one of its moods' faces")
        if "fade" in m and not whole(m["fade"].get("minutes"), 1):
            problems.append(f"lasting mood {m.get('id')}'s fade has no whole minutes")
    if len(character.get("id", "")) > 24 or len(character.get("version", "")) > 16:
        problems.append("id is at most 24 characters, and version 16")
    # Each board's face (§9): a folder of the pack's.
    if not character.get("faces"):
        problems.append("faces names no board's face")
    for board, face in character.get("faces", {}).items():
        folder = f"firmware/src/render/{face}"
        if not (pack / folder).is_dir():
            problems.append(f"faces gives {board} the {face} face, and there's no {folder}/")
    return problems + (reads or Reads()).rig(pack)[1]


def listed(path: Path) -> int:
    """How many `- ` lines a steering list has (signs.md, dreams.md), its
    comments left out; 0 with no file."""
    if not path.is_file():
        return 0
    text = re.sub(r"<!--.*?-->", "", path.read_text(), flags=re.S)
    return sum(1 for line in text.splitlines() if line.strip().startswith("- "))


def gaps(pack: Path, character: dict) -> list[str]:
    """What a pack lacks that doesn't stop it: moods a studio preview has no
    art of its own for, moods with no steering file, moods its voice has no
    take for (its own mac/takes.tsv, a reply's words left out), and no signs
    or dream signs."""
    ids, out = [m["id"] for m in character["moods"]], []
    for entry in previews(character):
        worn = wears(pack, entry) if not entry.get("wears") or (pack / entry["wears"]).is_file() else {}
        if worn:
            out.append(f"{entry.get('label') or character['name']} has art for {len(ids) - len(worn)} of {len(ids)} moods; "
                       f"the rest wear another's")
    # A pack's `lasting`, else (a pack from before it) its faces that settle into no other (§5).
    lasting = [m["id"] for m in character.get("lasting") or [m for m in character["moods"] if "settles" not in m]]
    unsteered = [m for m in lasting if not (pack / "steering" / "mood" / f"{m}.md").is_file()]
    if unsteered:
        out.append(f"{len(unsteered)} of {len(lasting)} lasting moods have no steering file, so they act as "
                   f"{character['default_mood']}: {', '.join(unsteered)}")
    table = pack / "mac" / "takes.tsv"
    if table.is_file():
        rows = [l.split("\t") for l in table.read_text().splitlines() if l and not l.startswith("#")][1:]
        said = {mood for row in rows if len(row) == 8 and row[2] != "reply" for mood in row[5].split()}
        mute = [m for m in ids if m not in said]
        if mute:
            out.append(f"{len(mute)} of {len(ids)} moods have no voice takes: {', '.join(mute)}")
    if not listed(pack / "steering" / "signs.md"):
        out.append("no signs (steering/signs.md), so it never holds one up")
    if not listed(pack / "steering" / "dreams.md"):
        out.append("no dream signs (steering/dreams.md), so it tells its dreams with none")
    return out


def check(pack: Path, reads: Reads | None = None) -> int:
    character = load(pack)
    problems = pack_problems(pack, character, reads)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    if not problems:
        print(f"CHARACTERGEN PASS: {character['id']}")
        for gap in gaps(pack, character):
            print(f"CHARACTERGEN GAP: {pack.name}: {gap}")
    return 1 if problems else 0


def bundle(view: Path, dest: Path) -> None:
    """A staged pack as the Mac app bundles it, with what the app reads and
    no more, in dest (.character-build/packs/<name>/): its demos' scripts,
    say, and not their recordings, which only the simulator's page plays."""
    shutil.copytree(view, dest,
                    ignore=shutil.ignore_patterns(".git", "firmware", "voice", "Makefile", "tools", "tests", "design", "evals",
                                                  "studio", "rig", "references", "recordings"))


def checked_pack(pack: Path, reads: Reads | None = None) -> tuple[dict, dict[str, Path]] | None:
    """A pack's character.json, or None, its problems printed, for a pack
    that can't be staged."""
    character = load(pack)
    problems = pack_problems(pack, character, reads)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    return None if problems else character


def stage(pack: Path, reads: Reads | None = None) -> int:
    """The pack staged (.character-build/staged/<name>/): its own files, as links, the one folder the tests,
    boopdev and the device tools read, and the pointer to it
    (.character-build/pack); from it, the firmware's files
    (.character-build/firmware/) with the generated moods.h and
    rig_tables.h, and the pack
    as the Mac app bundles it, with what the app reads and no more
    (.character-build/packs/<name>/), with packs/chosen naming it.

    It's all laid out afresh in a folder of its own, and then only what
    differs changes in .character-build (sync()): a build reading the
    staged files meanwhile, as one make target's does while another's
    stages, finds each file whole, and an unchanged one as it was."""
    reads = reads or Reads()
    checked = checked_pack(pack, reads)
    if checked is None:
        return 1
    character = checked
    STAGE.mkdir(exist_ok=True)
    # Named by its id, whatever its folder's called.
    name = character["id"]
    view = STAGE / "staged" / name
    with tempfile.TemporaryDirectory(dir=STAGE, prefix=".staging-") as temp:
        new = Path(temp)
        overlay(new / "staged" / name, pack)
        firmware_from(new / "staged" / name, pack, character, new / "firmware")
        bundle(new / "staged" / name, new / "packs" / name)
        (new / "packs" / "chosen").write_text(f"{name}\n")
        # The firmware's test suites: the engine's, then the staged pack's
        # (tests/firmware/test_*), linked so an edit lands in the real file.
        tests = new / "firmware-test"
        tests.mkdir()
        engine = ROOT / "internal" / "firmware" / "test"
        for folder, there in [(engine, engine), (new / "staged" / name / "tests" / "firmware", view / "tests" / "firmware")]:
            for suite in sorted(folder.glob("test_*")) if folder.is_dir() else []:
                if (tests / suite.name).is_symlink():
                    (tests / suite.name).unlink()
                (tests / suite.name).symlink_to(there / suite.name)
        (new / "pack").write_text(f"{view}\n")
        for part in ("staged", "firmware", "packs", "firmware-test", "pack"):
            sync(new / part, STAGE / part)
    return 0


def sync(new: Path, old: Path) -> None:
    """Makes old what new is, changing only what differs: a file or link
    that's new or changed moves in from new in one step, the file dated now,
    later than anything built from the one before, and what new hasn't goes.
    An unchanged file keeps its date."""
    folder = old.is_dir() and not old.is_symlink()
    if new.is_dir() and not new.is_symlink():
        if not folder:
            old.unlink(missing_ok=True)
            old.mkdir(parents=True, exist_ok=True)
        keep = {entry.name for entry in new.iterdir()}
        for entry in old.iterdir():
            if entry.name in keep:
                continue
            if entry.is_dir() and not entry.is_symlink():
                shutil.rmtree(entry, ignore_errors=True)
            else:
                entry.unlink(missing_ok=True)
        for entry in new.iterdir():
            sync(entry, old / entry.name)
        return
    if new.is_symlink():
        same = old.is_symlink() and os.readlink(new) == os.readlink(old)
    else:
        same = old.is_file() and not old.is_symlink() and filecmp.cmp(new, old, shallow=False)
    if not same:
        if folder:
            shutil.rmtree(old)
        if not new.is_symlink():
            os.utime(new)
        os.replace(new, old)


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
    character = checked
    if dest.exists():
        shutil.rmtree(dest)
    overlay(dest / "view", pack)
    firmware_from(dest / "view", pack, character, dest / "firmware")
    shutil.rmtree(dest / "view")
    return 0


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    rest = [a for a in argv if not a.startswith("--")]
    pack = Path(rest[0]).absolute() if rest else in_use() if "--which" in argv else chosen()
    if not (pack / "character.json").exists():
        print(f"charactergen: {pack} isn't a character pack (no character.json)", file=sys.stderr)
        if pack.parent == CHARACTERS and pack.name in known_packs():
            print(f"charactergen: {pack.name}'s pack is in a repository of its own: fetch it with "
                  f"`make -C internal packs`", file=sys.stderr)
        return 1
    if "--which" in argv:
        print(pack)
        return 0
    if "--boards" in argv:
        print(" ".join(load(pack).get("faces", {})))
        return 0
    reads = Reads()  # each pack's rig/, read once this run
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
