#!/usr/bin/env python3
"""Builds and stages character packs (characters/CHARACTER.md).

    characters/charactergen.py [--check] [PACK]
    characters/charactergen.py --stage [PACK]
    characters/charactergen.py --which

The first form checks a pack's character.json (its moods are exactly the
universal ones, CHARACTER.md §5, and every move, outcome and default
mood is one of them) and builds its generated files from it: today the
firmware's moods.h, the mood list in the pack's order with the board's
startup mood. --check only checks that they're fresh, and fails if one
isn't.

--stage lays the chosen pack's files out in .character-build/ at the repo
root for the builds to read (§2). firmware/tools/pio.sh runs it before
every PlatformIO build.

--which prints the folder of the pack in use: the one everything that runs
after a build reads (in_use()).

Every form but --which also checks the board's states where they're
named (CHARACTER.md §9 and each pack's mac/faces.json), each pack's
studio entry (§12), and writes characters/studio/packs.js, the studio
page's data for the packs in this checkout, which git ignores. --check
fails on a problem with any of them; --stage and the first form only warn.

PACK is a pack's folder. Without one, the chosen pack is the first of:
$BOOP_CHARACTER (a folder), $CHARACTER (a name in characters/), the name or
folder in the repo's .character file, and characters/boop/. Staging
writes the chosen pack's folder in .character-build/pack, the one pointer
to it; the pack in use is the one the environment chooses, else that one,
else the chosen one (nothing staged yet).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHARACTERS = ROOT / "characters"
STAGE = ROOT / ".character-build"
STUDIO = CHARACTERS / "studio"
FIRMWARE_STATES = ROOT / "firmware" / "src" / "render" / "types.cpp"
# The universal moods' one list, which the app's pack loader holds too.
UNIVERSAL = ROOT / "app" / "BoopKit" / "Character" / "Moods.swift"


def chosen() -> Path:
    if os.environ.get("BOOP_CHARACTER"):
        return Path(os.environ["BOOP_CHARACTER"]).resolve()
    if os.environ.get("CHARACTER"):
        return CHARACTERS / os.environ["CHARACTER"]
    saved = ROOT / ".character"
    if saved.exists() and saved.read_text().strip():
        name = saved.read_text().strip()
        return (ROOT / name).resolve() if "/" in name else CHARACTERS / name
    return CHARACTERS / "boop"


def in_use() -> Path:
    """The pack the tools, tests and simulator read: one the environment
    chooses ($BOOP_CHARACTER or $CHARACTER), else the one last staged
    (.character-build/pack), else the chosen one. The Swift and C++ code
    keeps the same rule by reading the environment and the pointer."""
    if os.environ.get("BOOP_CHARACTER") or os.environ.get("CHARACTER"):
        return chosen()
    pointer = STAGE / "pack"
    if pointer.exists() and pointer.read_text().strip():
        return Path(pointer.read_text().strip())
    return chosen()


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
    not exactly the universal moods, or a move, outcome, default or
    startup mood that isn't one."""
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
    for kind, listed in character.get("outcomes", {}).items():
        problems += [f"outcomes.{kind} names {m}, which isn't a mood" for m in listed if m not in names]
    return problems


def moods_h(pack: Path, character: dict) -> str:
    moods = [m["id"] for m in character["moods"]]
    startup = character.get("startup_mood", character["default_mood"])
    if startup not in moods:
        raise SystemExit(f"{pack}: startup_mood {startup} isn't a mood")
    # The board's hello names both, and must fit in one line.
    if len(character["id"]) > 24 or len(character["version"]) > 16:
        raise SystemExit(f"{pack}: id is at most 24 characters, and version 16")
    # By the pack's folder name only, so a pack that moves (a copy, another
    # checkout) keeps the same file.
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


def load(pack: Path) -> dict:
    return json.loads((pack / "character.json").read_text())


def previews(character: dict) -> list[dict]:
    """The pack's studio entries (§12), one for each preview it brings."""
    return [dict(e) for e in character.get("studio", [])]


def states(studio: Path = STUDIO) -> dict:
    return json.loads((studio / "states.json").read_text())


def state_ids(table: dict) -> list[str]:
    return [s["id"] for g in table["groups"] for s in g["states"]]


def firmware_states(source: Path = FIRMWARE_STATES) -> list[str]:
    """The board's state names, kStateNames in the firmware's render types."""
    match = re.search(r"kStateNames\[\d+\]\s*=\s*\{([^}]*)\}", source.read_text())
    if not match:
        raise SystemExit(f"charactergen: no kStateNames in {source}")
    return re.findall(r'"([a-z_]+)"', match.group(1))


def wears(pack: Path, entry: dict) -> dict[str, str]:
    """The moods a studio preview has no art of its own for, each with the
    mood whose art it shows instead: its `wears` file's `borrows` table
    (Pixel's temporary one), or none."""
    if not entry.get("wears"):
        return {}
    return json.loads((pack / entry["wears"]).read_text())["borrows"]


def studio_problems(packs: list[Path], studio: Path = STUDIO, source: Path = FIRMWARE_STATES) -> list[str]:
    """What's wrong with the studio's data: the states it lists against the
    board's, each pack's declared files, and a preview that has a mood
    wear one that isn't the pack's."""
    problems = []
    table = states(studio)
    ids, board = state_ids(table), firmware_states(source)
    if sorted(ids) != sorted(board) or len(ids) != len(set(ids)):
        missing, extra = sorted(set(board) - set(ids)), sorted(set(ids) - set(board))
        problems.append(f"{studio / 'states.json'} doesn't list the board's states (missing {missing}, extra {extra})")
    for pack in packs:
        character = load(pack)
        entries = previews(character)
        names = [e.get("id") for e in entries]
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


def studio_data(packs: list[Path], chosen_pack: Path, studio: Path = STUDIO) -> dict:
    """The studio page's data: the engine's states and, for each pack, its
    moods and its studio entries, with paths from the page."""
    data = {"chosen": chosen_pack.name, "states": states(studio), "packs": {}}
    for pack in packs:
        character = load(pack)
        entries = previews(character)
        for entry in entries:
            borrows = wears(pack, entry)
            here = lambda name: Path(os.path.relpath(pack / name, studio)).as_posix()
            for key in ("scripts", "styles"):
                entry[key] = [here(name) for name in entry.get(key, [])]
            if entry.get("icon"):
                entry["icon"] = here(entry["icon"])
            entry["wears"] = dict(sorted(borrows.items()))
            entry.pop("captures", None)
        data["packs"][pack.name] = {
            "name": character["name"],
            "default_mood": character["default_mood"],
            "moods": [{k: m[k] for k in ("id", "meaning", "family") if k in m} for m in character["moods"]],
            "studio": entries,
        }
    return data


def local_packs(also: Path | None = None) -> list[Path]:
    packs = [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]
    if also and also not in packs and (also / "character.json").exists():
        packs.append(also)
    return packs


def write_studio(pack: Path, check: bool) -> int:
    """Checks the studio's data and writes characters/studio/packs.js, which
    opens on `pack`. Problems fail --check and only warn otherwise."""
    packs = local_packs(pack)
    problems = studio_problems(packs) + state_problems(packs)
    for problem in problems:
        print(("CHARACTERGEN FAIL: " if check else "charactergen: warning: ") + problem, file=sys.stderr)
    data = json.dumps(studio_data(packs, pack), indent=1)
    (STUDIO / "packs.js").write_text(f"// Generated by characters/charactergen.py. Do not edit.\nwindow.StudioData = {data};\n")
    return 1 if check and problems else 0


def build(pack: Path, check: bool) -> int:
    character = load(pack)
    problems = mood_problems(character, universal_moods())
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    if problems:
        return 1
    outputs = {pack / "firmware/include/moods.h": moods_h(pack, character)}
    for path, content in outputs.items():
        if check:
            if not path.exists() or path.read_text() != content:
                print(f"CHARACTERGEN FAIL: {path} is stale: run characters/charactergen.py {pack}", file=sys.stderr)
                return 1
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print(("CHARACTERGEN PASS: fresh" if check else "Generated") + f" {character['id']}'s files ({len(outputs)})")
    return 0


def stage(pack: Path) -> int:
    """The pack's firmware files (.character-build/firmware/); the pack as
    the Mac app bundles it, with what the app reads and no more
    (.character-build/packs/, that pack alone); and the pointer to the
    pack's folder (.character-build/pack), where the tests, boopdev and the
    device tools find the rest, the voice pack among it."""
    STAGE.mkdir(exist_ok=True)
    for old in ("firmware", "packs"):
        if (STAGE / old).exists():
            shutil.rmtree(STAGE / old)
    if (pack / "firmware").is_dir():
        shutil.copytree(pack / "firmware", STAGE / "firmware")
    shutil.copytree(pack, STAGE / "packs" / pack.name,
                    ignore=shutil.ignore_patterns(".git", "firmware", "voice", "Makefile", "tools", "tests", "design", "evals",
                                                  "studio"))
    # The firmware's test suites: the engine's, then the pack's own
    # (tests/firmware/test_*), linked so an edit lands in the real file.
    tests = STAGE / "firmware-test"
    if tests.exists():
        shutil.rmtree(tests)
    tests.mkdir(parents=True)
    for folder in [ROOT / "internal" / "firmware" / "test", pack / "tests" / "firmware"]:
        for suite in sorted(folder.glob("test_*")) if folder.is_dir() else []:
            if (tests / suite.name).is_symlink():
                (tests / suite.name).unlink()
            (tests / suite.name).symlink_to(suite.resolve())
    (STAGE / "pack").write_text(f"{pack}\n")
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
    if "--stage" in argv:
        return stage(pack) | write_studio(pack, check=False)
    status = 0
    for each in ([pack] if rest else [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]):
        status |= build(each, "--check" in argv)
    return status | write_studio(pack, "--check" in argv)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
