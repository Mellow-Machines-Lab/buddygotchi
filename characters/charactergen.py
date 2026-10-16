#!/usr/bin/env python3
"""Builds and stages character packs (characters/CHARACTER.md).

    characters/charactergen.py --check [PACK]
    characters/charactergen.py --stage [PACK]
    characters/charactergen.py --firmware-to=DIR [PACK]
    characters/charactergen.py --which

--check checks a pack's character.json: its moods are exactly the
universal ones (CHARACTER.md §5), and every move and default mood is
one of them; what it uses from other packs is there (§6); and its
id and version fit the board's hello (§10). Without PACK, every pack in
characters/.

--stage lays the chosen pack's files out in .character-build/ at the repo
root for the builds to read (§2), with what it uses from other packs (§6)
and the firmware's moods.h, which it makes from character.json: the mood
list in the pack's order with the board's startup mood. It checks the
pack as --check does first. firmware/tools/pio.sh runs it before every
PlatformIO build.

--firmware-to=DIR lays out only the firmware's files for a pack, as
--stage does, in DIR/firmware/, and changes nothing staged: for a second
build beside the staged pack's (simulator/web/build.sh PACK).

--which prints the folder of the pack in use: the one everything that runs
after a build reads (in_use()).

Every form but --which and --firmware-to also checks the board's states
where they're named (CHARACTER.md §9 and each pack's mac/faces.json), each
pack's studio entry (§12), and writes characters/studio/packs.js, the studio
page's data for the packs in this checkout, which git ignores. --check
fails on a problem with any of them; --stage only warns.

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
        names = [e.get("id") for e in entries + [e for _, e in shared_previews(pack, character)]]
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


def studio_data(packs: list[Path], chosen_pack: Path, studio: Path = STUDIO) -> dict:
    """The studio page's data: the engine's states and, for each pack, its
    moods and its studio entries, its own and those it uses, with paths
    from the page."""
    data = {"chosen": chosen_pack.name, "states": states(studio), "packs": {}}
    for pack in packs:
        character = load(pack)
        entries = [(pack, e) for e in previews(character)] + shared_previews(pack, character)
        for home, entry in entries:
            borrows = wears(home, entry)
            here = lambda name, home=home: Path(os.path.relpath(home / name, studio)).as_posix()
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
            "studio": [entry for _, entry in entries],
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


def pack_problems(pack: Path, character: dict) -> list[str]:
    """What stops a pack from staging: its moods (§5), what it uses (§6),
    and an id or version too long for the board's hello (§10)."""
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
    return problems


def check(pack: Path) -> int:
    character = load(pack)
    problems = pack_problems(pack, character)
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
                                                  "studio"))


def stage(pack: Path) -> int:
    """The pack staged (.character-build/staged/<name>/): its own files and
    what it uses from other packs (§6), as links, the one folder the tests,
    boopdev and the device tools read, and the pointer to it
    (.character-build/pack); from it, the firmware's files
    (.character-build/firmware/) with the generated moods.h, and the pack
    as the Mac app bundles it, with what the app reads and no more
    (.character-build/packs/<name>/), beside every other pack in characters/
    for buddies that run one, with packs/chosen naming this one."""
    character = load(pack)
    paths = used(pack, character)[0]
    problems = pack_problems(pack, character)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    if problems:
        return 1
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
        if other.resolve() == own_folder(pack) or pack_problems(other, load(other)):
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
    """The firmware's files from a pack's staged view: its firmware/ folder
    and the moods.h made from character.json."""
    if (view / "firmware").is_dir():
        shutil.copytree(view / "firmware", dest)
    (dest / "include").mkdir(parents=True, exist_ok=True)
    (dest / "include" / "moods.h").write_text(moods_h(pack, character))


def firmware_to(pack: Path, dest: Path) -> int:
    """Only the firmware's files for a pack, in dest/firmware/, as --stage
    lays them out, and nothing else: the staged pack and the pack in use
    stay as they are. For a second build beside the staged one (the
    simulator's page with a board for each pack)."""
    character = load(pack)
    paths = used(pack, character)[0]
    problems = pack_problems(pack, character)
    for problem in problems:
        print(f"CHARACTERGEN FAIL: {pack.name}: {problem}", file=sys.stderr)
    if problems:
        return 1
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
    if "--stage" in argv:
        return stage(pack) | write_studio(pack, check=False)
    to = [a.split("=", 1)[1] for a in argv if a.startswith("--firmware-to=")]
    if to:
        return firmware_to(pack, Path(to[0]).resolve())
    if "--check" not in argv:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    status = 0
    for each in ([pack] if rest else [p.parent for p in sorted(CHARACTERS.glob("*/character.json"))]):
        status |= check(each)
    return status | write_studio(pack, check=True)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
