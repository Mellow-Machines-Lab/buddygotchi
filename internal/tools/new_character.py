#!/usr/bin/env python3
"""Starts a new character from a working pack: copies Pixel's, the open
example, gives it its id and name, links it into characters/ and checks it.

    internal/tools/new_character.py ID NAME [--to DIR] [--from PACK]

The copy goes in DIR/character/ (by default ../ID beside this repository),
the layout a character's own repository has. Its demo recordings stay
behind: they're the old pack's, so record its own. What makes it a new
character is what comes next: characters/new-character-playbook.md.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
# Where the old name is the character's own words, and is said to Jev.
NAMED = ("steering", "evals", "demo")
LEFT_BEHIND = ("recordings", "__pycache__", "node_modules", ".pio")


def copy(source: Path, to: Path, pack_id: str, name: str) -> None:
    """The pack at `source`, as `name`, in `to`."""
    shutil.copytree(source, to, symlinks=True, ignore=shutil.ignore_patterns(*LEFT_BEHIND))
    path = to / "character.json"
    pack = json.loads(path.read_text())
    old = pack["name"]
    pack["id"], pack["name"], pack["version"] = pack_id, name, "0.1.0"
    path.write_text(json.dumps(pack, indent=2, ensure_ascii=False) + "\n")
    word = re.compile(rf"\b{re.escape(old)}\b")
    for folder in NAMED:
        for f in (to / folder).rglob("*"):
            if f.is_file() and f.suffix in (".md", ".json", ".jsonl"):
                text = f.read_text()
                if word.search(text):
                    f.write_text(word.sub(name, text))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("id", help="the pack's id: lowercase letters and digits")
    parser.add_argument("name", help="the character's name")
    parser.add_argument("--to", type=Path, help="the new repository's folder (default ../ID)")
    parser.add_argument("--from", dest="source", default="pixel", help="the pack to copy (default pixel)")
    args = parser.parse_args(argv)
    if not re.fullmatch(r"[a-z][a-z0-9]*", args.id):
        parser.error(f"{args.id!r} isn't an id: lowercase letters and digits, a letter first")
    source = ROOT / "characters" / args.source
    if not (source / "character.json").is_file():
        print(f"new-character: no pack {args.source} in characters/: run make -C internal packs", file=sys.stderr)
        return 2
    folder = (args.to or ROOT.parent / args.id).resolve()
    to = folder / "character"
    if to.exists():
        print(f"new-character: {to} is there already", file=sys.stderr)
        return 2
    folder.mkdir(parents=True, exist_ok=True)
    copy(source.resolve(), to, args.id, args.name)
    subprocess.run([sys.executable, str(ROOT / "internal/tools/packs.py"), f"{args.id}={to}"], check=True)
    checked = subprocess.run([str(ROOT / ".build/debug/boopdev"), "check", f"characters/{args.id}"], cwd=ROOT)
    print(f"\n{args.name} is in {to}, linked as characters/{args.id}.")
    print("It's still Pixel under the name: characters/new-character-playbook.md says what to make its own.")
    return checked.returncode


if __name__ == "__main__":
    sys.exit(main())
