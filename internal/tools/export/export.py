#!/usr/bin/env python3
"""Lays out the public repository from this one, and checks it for leaks
(characters/CHARACTER.md §11).

    python3 internal/tools/export/export.py OUT [--commit] [--report FILE]

OUT gets HEAD's tracked files, less what isn't published: every character
pack whose character.json says "private": true. The submodules stay
submodules: with --commit, each is recorded at the commit HEAD has.

A link in a Markdown file to something left out becomes its plain text.
--commit makes OUT a new git repository with one commit (nothing is
pushed).

Then it checks OUT for a private pack's content: a line of its steering,
or a mood's meaning or face wording. It also checks for anything that
looks like a key. Either fails the export. The voice isn't private: Pixel's
pack has its own copy of the takes. It prints what it finds, writes it to
--report if given, and exits 1 if anything fails.
OUT must not exist yet, or be empty.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TEXT = {".md", ".swift", ".py", ".mjs", ".cjs", ".js", ".json", ".jsonl", ".h", ".cpp", ".c", ".ini", ".sh",
        ".txt", ".yml", ".yaml", ".html", ".css", ".tsv", ""}
KEYLIKE = re.compile(r"(sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"
                     r"(?i:api[_-]?key|secret|token)\s*[:=]\s*['\"][A-Za-z0-9_\-]{16,}['\"])")


def private_packs() -> list[Path]:
    packs = []
    for file in sorted((ROOT / "characters").glob("*/character.json")):
        if json.loads(file.read_text()).get("private"):
            packs.append(file.parent)
    return packs


def fingerprints(pack: Path) -> set[str]:
    """Strings that only a private pack has, which must not ship: its
    steering's lines and its moods' wording."""
    found: set[str] = set()
    for md in (pack / "steering").rglob("*.md"):
        for line in md.read_text().splitlines():
            line = line.strip()
            if len(line) >= 40 and not line.startswith("<!--"):
                found.add(line)
    character = json.loads((pack / "character.json").read_text())
    for mood in character.get("moods", []) + character.get("moods_v2", []):
        for key in ("meaning", "face", "not_for", "face_not_for"):
            if len(mood.get(key) or "") >= 30:
                found.add(mood[key])
    return found


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0
    out = Path(argv[0]).resolve()
    report_file = Path(argv[argv.index("--report") + 1]) if "--report" in argv else None
    if out.exists() and any(out.iterdir()):
        print(f"export: {out} isn't empty", file=sys.stderr)
        return 1
    packs = private_packs()
    left_out = [str(p.relative_to(ROOT)) + "/" for p in packs]
    staged = subprocess.run(["git", "ls-files", "-s"], cwd=ROOT, capture_output=True, text=True, check=True).stdout
    # A submodule is a commit, not a file: recorded as one with --commit.
    submodules = {}
    files = []
    for entry in staged.splitlines():
        mode, sha, _, path = entry.split(None, 3)
        if mode == "160000":
            submodules[path] = sha
        else:
            files.append(path)
    kept = [f for f in files if f and not any(f.startswith(x) for x in left_out)]
    for f in kept:
        target = out / f
        target.parent.mkdir(parents=True, exist_ok=True)
        if (ROOT / f).is_symlink():
            target.symlink_to((ROOT / f).readlink())
        else:
            shutil.copy2(ROOT / f, target)

    # Links to what was left out become their text.
    unlinked = 0
    link = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
    for f in kept:
        if not f.endswith(".md"):
            continue
        path = out / f
        text = path.read_text()

        def plain(m: re.Match) -> str:
            nonlocal unlinked
            target = m.group(2).split("#")[0]
            if target.startswith(("http", "mailto")) or not target:
                return m.group(0)
            resolved = (ROOT / f).parent.joinpath(target).resolve()
            rel = str(resolved.relative_to(ROOT)) if resolved.is_relative_to(ROOT) else ""
            if any((rel + "/").startswith(x) or rel.startswith(x) for x in left_out):
                unlinked += 1
                return m.group(1)
            return m.group(0)

        new = link.sub(plain, text)
        if new != text:
            path.write_text(new)

    # Leaks: a private pack's content, or anything that looks like a key,
    # fails the export.
    marks: set[str] = set()
    for pack in packs:
        marks |= fingerprints(pack)
    findings: list[str] = []
    for f in kept:
        path = out / f
        if path.is_symlink() or path.suffix not in TEXT:
            continue
        try:
            text = path.read_text()
        except UnicodeDecodeError:
            continue
        hits = sorted(m for m in marks if m in text)
        if hits:
            findings.append(f"{f}: {len(hits)} lines of a private pack's: " + "; ".join(h[:60] for h in hits[:3]))
        if KEYLIKE.search(text):
            findings.append(f"{f}: something that looks like a key")

    if "--commit" in argv:
        subprocess.run(["git", "init", "-q"], cwd=out, check=True)
        # Committed as whoever commits here, never the global identity.
        for key in ("user.name", "user.email"):
            value = subprocess.run(["git", "config", key], cwd=ROOT, capture_output=True, text=True).stdout.strip()
            if value:
                subprocess.run(["git", "config", key, value], cwd=out, check=True)
        subprocess.run(["git", "add", "-A"], cwd=out, check=True)
        for path, sha in submodules.items():
            subprocess.run(["git", "update-index", "--add", "--cacheinfo", f"160000,{sha},{path}"], cwd=out, check=True)
        subprocess.run(["git", "commit", "-qm", "Boop, the open engine, and Pixel, its open character"], cwd=out, check=True)

    summary = (f"export: {len(kept)} files into {out}, leaving out {', '.join(left_out)}; "
               f"{unlinked} links made plain text; {len(findings)} files with something private")
    lines = [f"  private: {line}" for line in findings]
    print(summary)
    print("\n".join(lines))
    if report_file:
        report_file.write_text(summary + "\n" + "".join(f"{line}\n" for line in lines))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
