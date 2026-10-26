#!/usr/bin/env python3
"""Puts the character packs the engine is tested with in characters/.

Each pack is in a repository of its own, which characters/packs.json
names by the pack's id; the pack is that repository's character/ folder.
A pack fetched goes in characters/.repos/<repository>/, a clone, with
characters/<id> a link to its pack, so every path the engine and its
tests use is the same as when the packs were here.

    internal/tools/packs.py                 fetch every pack that's missing
    internal/tools/packs.py --update        and pull those fetched before
    internal/tools/packs.py --chosen        only the chosen pack, if it's missing (the
                                            root make's targets run this first)
    internal/tools/packs.py ID=PATH ...     link characters/ID to the pack at PATH
                                            instead, and fetch nothing (a character
                                            repository's make does this for its own)
    internal/tools/packs.py --fetch ID=PATH and fetch the others too

A pack already in characters/ (a folder of its own, or a link) stays
as it is, but for a link ID=PATH replaces. BOOP_PACKS_URL is where the
repositories are, https://github.com/ by default. A clone pushes as any
other: give it the push URL that can write to its repository.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHARACTERS = ROOT / "characters"
REPOS = CHARACTERS / ".repos"


def run(*args: str) -> None:
    subprocess.run(args, check=True)


def fetch(pack: str, repo: str, update: bool) -> int:
    link, clone = CHARACTERS / pack, REPOS / repo.split("/")[-1]
    if link.exists() and not (link.is_symlink() and os.readlink(link) == os.path.relpath(clone / "character", CHARACTERS)):
        return 0  # a pack of its own here, or linked elsewhere: leave it
    if not (clone / ".git").exists():
        url = os.environ.get("BOOP_PACKS_URL", "https://github.com/").rstrip("/") + f"/{repo}.git"
        print(f"packs: fetching {pack} from {url}", file=sys.stderr)
        REPOS.mkdir(parents=True, exist_ok=True)
        run("git", "clone", "--quiet", url, str(clone))
    elif update:
        run("git", "-C", str(clone), "pull", "--quiet", "--ff-only")
    if not (clone / "character" / "character.json").is_file():
        print(f"packs: {repo} has no character/character.json", file=sys.stderr)
        return 1
    if link.is_symlink() or not link.exists():
        link.unlink(missing_ok=True)
        link.symlink_to(os.path.relpath(clone / "character", CHARACTERS))
    return 0


def main(argv: list[str]) -> int:
    if "--help" in argv or "-h" in argv:
        print(__doc__.strip())
        return 0
    known = json.loads((CHARACTERS / "packs.json").read_text())
    given = dict(a.split("=", 1) for a in argv if "=" in a)
    for pack, path in given.items():
        target = Path(path).resolve()
        if not (target / "character.json").is_file():
            print(f"packs: {path} isn't a character pack (no character.json)", file=sys.stderr)
            return 1
        link = CHARACTERS / pack
        if link.exists() and not link.is_symlink():
            print(f"packs: characters/{pack} is a folder of its own; move it away to link it", file=sys.stderr)
            return 1
        link.unlink(missing_ok=True)
        link.symlink_to(os.path.relpath(target, CHARACTERS))
    if given and "--fetch" not in argv:
        return 0
    wanted = known
    if "--chosen" in argv:
        sys.path.insert(0, str(CHARACTERS))
        import charactergen
        chosen = charactergen.chosen()
        wanted = {chosen.name: known[chosen.name]} if chosen.parent == CHARACTERS and chosen.name in known else {}
    status = 0
    for pack, repo in wanted.items():
        if pack in given:
            continue
        if (CHARACTERS / pack).exists() and not (CHARACTERS / pack / "character.json").is_file():
            print(f"packs: characters/{pack} isn't a pack (no character.json): move it away, then run this again",
                  file=sys.stderr)
            status = 1
            continue
        status |= fetch(pack, repo, "--update" in argv)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
