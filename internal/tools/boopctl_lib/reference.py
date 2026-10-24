"""boopctl reference (characters/CHARACTER.md §16): a reference a person
gave, taken in and cut up to be read. `new` makes a pack's
references/<today>-<topic>/ with the files and a reference.json; `read`
cuts each GIF or video into a frame every 40 ms (ffmpeg), copies a still
as one frame, makes a contact sheet of each, and says where they are, for
an agent to look at them and write reading.md."""
from __future__ import annotations

import datetime
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image

from boopctl_lib.common import REPO
from boopctl_lib.image import sheet

sys.path.insert(0, str(REPO / "characters"))
try:
    import charactergen as gen  # the format's one definition: its media, kinds, statuses, frames' interval and problems
finally:
    sys.path.pop(0)

LONGEST = 512  # a frame's longest side at most, in pixels: a little over the gel's 502×410 panel


def tool(name: str) -> str:
    found = shutil.which(name) or (f"/opt/homebrew/bin/{name}" if Path(f"/opt/homebrew/bin/{name}").exists() else None)
    if not found:
        raise FileNotFoundError(f"no {name} here: brew install ffmpeg")
    return found


def problems(folder: Path) -> list[str]:
    """The reference's problems, as charactergen.py --check finds them."""
    pack = folder.parent.parent
    moods = {m["id"] for m in json.loads((pack / "character.json").read_text())["moods"]}
    return gen.reference_problems(folder, moods, gen.state_ids(gen.states()), gen.read_rig(pack)[0])


def new(pack: Path, topic: str, kind: str, note: str, files: list[Path], today: datetime.date | None = None) -> Path:
    """The reference's folder, made with copies of the files and a new reference.json."""
    if not (pack / "character.json").is_file():
        raise FileNotFoundError(f"no character pack at {pack}")
    folder = pack / "references" / f"{(today or datetime.date.today()).isoformat()}-{topic}"
    if not gen.REFERENCE_FOLDER.fullmatch(folder.name):
        raise ValueError(f"a topic is a few words in lowercase letters and digits, with dashes: not {topic!r}")
    if folder.exists():
        raise FileExistsError(f"{folder} is there already")
    for f in files:
        if not f.is_file() or f.suffix.lower() not in gen.MEDIA:
            raise ValueError(f"{f} isn't a still, a GIF or a video ({' '.join(gen.MEDIA)})")
    if len({f.name for f in files}) != len(files):
        raise ValueError("two of the files have one name")
    folder.mkdir(parents=True)
    for f in files:
        shutil.copy2(f, folder / f.name)
    (folder / "reference.json").write_text(json.dumps({"kind": kind, "note": note, "status": "new", "became": []}, indent=2) + "\n")
    return folder


def cut(source: Path, out: Path) -> int:
    """The file's frames in out/, 0000.png on, a frame every gen.FRAME_MS,
    no bigger than LONGEST; returns its length in ms (a still's is 0)."""
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    if gen.MEDIA[source.suffix.lower()] == "still":
        with Image.open(source) as image:
            image.thumbnail((LONGEST, LONGEST))
            image.save(out / "0000.png")
        return 0
    seconds = subprocess.run([tool("ffprobe"), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(source)],
                             check=True, capture_output=True, text=True).stdout.strip()
    fit = f"scale='min({LONGEST},iw)':'min({LONGEST},ih)':force_original_aspect_ratio=decrease"
    subprocess.run([tool("ffmpeg"), "-v", "error", "-i", str(source), "-vf", f"fps={1000 // gen.FRAME_MS},{fit}",
                    "-start_number", "0", str(out / "%04d.png")], check=True)
    return round(float(seconds) * 1000)


def read(folder: Path) -> list[str]:
    """Cuts every file of the reference and makes its sheet, writes
    reference.json's frames and ms, and moves its status from new to
    read; returns what it made, a line a file."""
    ref = json.loads((folder / "reference.json").read_text())
    said, frames, ms = [], 0, 0
    for source in gen.media(folder):
        length = cut(source, folder / "frames" / source.name)
        # 8 frames a row, each 200 px wide under its ms
        sheet([(f"{i * gen.FRAME_MS} ms", f) for i, f in enumerate(sorted((folder / "frames" / source.name).glob("*.png")))],
              folder / "sheets" / f"{source.name}.png")
        n = gen.frame_count(folder, source.name)
        frames, ms = frames + n, max(ms, length)
        said.append(f"{source.name}: {n} frame{'s' * (n != 1)} over {length} ms in frames/{source.name}/, "
                    f"the sheet sheets/{source.name}.png")
    ref.update(frames=frames, ms=ms, status="read" if ref.get("status") == "new" else ref.get("status"))
    (folder / "reference.json").write_text(json.dumps(ref, indent=2) + "\n")
    return said


def add_parser(sub: Any) -> None:
    p = sub.add_parser("reference", help="take in a reference a person gave, and cut it into frames and contact sheets "
                                         "to read (characters/CHARACTER.md §16)")
    steps = p.add_subparsers(dest="reference", required=True, metavar="step")
    q = steps.add_parser("new", help="make characters/PACK/references/<today>-TOPIC/ with copies of the files and a "
                                     "reference.json")
    q.add_argument("pack", help="a pack's name in characters/")
    q.add_argument("topic", help="what it's of, in lowercase-words-with-dashes")
    q.add_argument("--kind", required=True, choices=gen.KINDS, help="inspiration, or direct: make this")
    q.add_argument("--note", required=True, help="the person's line about it")
    q.add_argument("files", nargs="+", type=Path, help=f"stills, GIFs or videos ({' '.join(gen.MEDIA)})")
    q = steps.add_parser("read", help="cut each GIF or video into a frame every 40 ms and a still into one, with a "
                                      "contact sheet of each; then look at them and write DIR/reading.md")
    q.add_argument("dir", type=Path, help="the reference's folder")
    p.set_defaults(func=main)


def main(args: Any) -> int:
    if args.reference == "new":
        try:
            folder = new(REPO / "characters" / args.pack, args.topic, args.kind, args.note, args.files)
        except (ValueError, FileExistsError) as e:
            print(f"boopctl: {e}", file=sys.stderr)
            return 2
        print(folder)
        print(f"Next: internal/tools/boopctl reference read {folder.relative_to(REPO)}")
    else:
        folder = args.dir.resolve()
        if not (folder / "reference.json").is_file():
            raise FileNotFoundError(f"{args.dir} has no reference.json: make one with boopctl reference new")
        for line in read(folder):
            print(line)
        print(f"Look at the sheets, then write {folder}/reading.md: the beats and their timing, the poses, squash and "
              "stretch, the eyes' and mouth's shapes, the colours and the silhouette.")
    for problem in problems(folder):
        print(f"boopctl: {folder.name}: {problem}", file=sys.stderr)
    return 0
