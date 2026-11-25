#!/usr/bin/env python3
"""Every character pack's demos: asks which one and where it plays, or
lists, plays, records and checks them (characters/DEMOS.md).

    simulator/tools/demos.py                  asks which demo and where (make demo)
    simulator/tools/demos.py list             every demo: its title and length
    simulator/tools/demos.py play NAME [--board usb:SOCKET]
                                              one demo in the simulator's page, or live on a board
    simulator/tools/demos.py all              every recorded demo in the page, one after another
    simulator/tools/demos.py record [NAME...] [--all] [--jobs N]
                                              records the demos whose recording is missing or out of
                                              date (or those named, or all), several at once
    simulator/tools/demos.py check            fails when a demo's recording is missing or out of date

The page plays a demo from its recording, which is checked in beside its
script (characters/PACK/demo/recordings/NAME.json), so it starts at once.
A recording is every message the app sent the board, made by playing the
script through the real headless app with the simulator's board as its
device. It keeps the hash of
the script it was made from, and it's out of date when the script changes.
The standard library only, for the Mac's own Python.
"""
import argparse
import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import textwrap
import time
import webbrowser
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import List, Optional

REPO = Path(__file__).resolve().parents[2]
CHARACTERS = REPO / "characters"
DIST = REPO / "simulator" / "web" / "dist"
BOOP = REPO / ".build" / "debug" / "Boop"
BRIDGE = REPO / ".build" / "debug" / "linkkit-bridge"
CORE = REPO / "firmware" / ".pio" / "build" / "native" / "program"
sys.path.insert(0, str(REPO / "simulator" / "tools"))
from voice_subset import pack_voice, subset  # noqa: E402

# Recording a demo takes as long as it runs; this many at once.
JOBS = 6
# When a recording's clock starts, for a script that doesn't say: an
# ordinary weekday afternoon, so no part of the day, weekend or holiday
# dresses it, and it looks the same whenever it's recorded.
START = "2026-10-20T14:00"


class Demo:
    def __init__(self, path: Path):
        self.path = path
        self.pack = path.parents[1].name
        self.name = path.stem
        self.title, self.about, self.header, self.steps = self.name.replace("-", " "), [], {}, []
        for line in path.read_text().splitlines():
            if line.startswith("//"):
                if not self.steps and not self.header:
                    self.about.append(line[2:].strip())
                continue
            if not line.strip():
                continue
            try:
                step = json.loads(line)
            except ValueError:
                continue  # boopdev check says why
            if "demo" in step:
                self.header = step
                self.title = step.get("title", self.title)
            else:
                self.steps.append(step)

    @property
    def id(self) -> str:
        return f"{self.pack}/{self.name}"

    @property
    def recording(self) -> Path:
        return self.path.parent / "recordings" / f"{self.name}.json"

    def to_record(self, folder: Path) -> Path:
        """The script as it's recorded: with the clock's start, if it has
        none, in a copy of the same name in the folder."""
        if "start" in self.header:
            return self.path
        lines = self.path.read_text().splitlines()
        first = next(i for i, l in enumerate(lines) if l.strip() and not l.startswith("//"))
        header = json.loads(lines[first]) if "demo" in json.loads(lines[first]) else None
        started = json.dumps({**(header or {"demo": 1}), "start": START}, ensure_ascii=False)
        lines[first:first + 1] = [started] if header else [started, lines[first]]
        copy = folder / self.path.name
        copy.write_text("\n".join(lines) + "\n")
        return copy

    def hash(self) -> str:
        return hashlib.sha256(self.path.read_bytes()).hexdigest()

    def recorded(self) -> Optional[dict]:
        try:
            return json.loads(self.recording.read_text())
        except (OSError, ValueError):
            return None

    def fresh(self) -> bool:
        recorded = self.recorded()
        return bool(recorded) and recorded.get("script") == self.hash()

    def length(self) -> str:
        seconds = (self.recorded() or {}).get("length")
        return f"{int(seconds) // 60}:{int(seconds) % 60:02d}" if seconds is not None else ""


def demos() -> List[Demo]:
    return [Demo(p) for p in sorted(CHARACTERS.glob("*/demo/*.jsonl"))]


def find(name: str) -> Demo:
    """A demo by name, or by PACK/NAME, as the page names it."""
    pack, _, name = name.rpartition("/")
    found = [d for d in demos() if d.name == name and (not pack or d.pack == pack)]
    if not found:
        sys.exit(f"demos: no demo called {name}" + (f" in {pack}" if pack else "") + ": `make demo` lists them")
    return found[0]


def creature(pack: str) -> str:
    return json.loads((CHARACTERS / pack / "character.json").read_text())["name"]


# Listing and asking.

def table(all_demos: List[Demo], numbered: bool) -> None:
    width = max(len(d.name) for d in all_demos)
    title = max(len(d.title) for d in all_demos)
    n = 0
    for pack in sorted({d.pack for d in all_demos}, key=lambda p: (p != "boop", p)):
        print(f"\n  {creature(pack)}'s demos")
        for d in (d for d in all_demos if d.pack == pack):
            n += 1
            stale = "" if d.fresh() else "not recorded yet"
            number = f"{n:3}  " if numbered else "  "
            print(f"  {number}{d.name:{width}}  {d.title:{title}}  {d.length():>5}  {stale}")


def ask(question: str, choices: List[str], default: Optional[str] = None) -> str:
    while True:
        try:
            said = input(f"\n{question} " + (f"[{default}] " if default else "")).strip().lower()
        except (EOFError, KeyboardInterrupt):
            print()
            sys.exit(0)
        said = said or (default or "")
        if said in choices:
            return said
        print("  That isn't one of them.")


def menu() -> int:
    all_demos = demos()
    print("Boop's demos. Pick one, then where it plays.")
    table(all_demos, numbered=True)
    print("\n    a  All of them, one after another, in your browser")
    numbers = [str(i) for i in range(1, len(all_demos) + 1)]
    chose = ask(f"Which demo? (1-{len(all_demos)}, a for all, q to quit)", numbers + ["a", "q"])
    if chose == "q":
        return 0
    if chose == "a":
        return play_all()
    d = all_demos[int(chose) - 1]
    print(f"\n  {d.id}: {d.title}")
    if d.about:
        print(textwrap.fill(" ".join(d.about), 78, initial_indent="  ", subsequent_indent="  "))
    print("    1  The simulator, in your browser (recorded: starts at once)")
    print("    2  The real board, over USB")
    return play_page(d) if ask("Where? (1-2)", ["1", "2"], "1") == "1" else play_board(d, None)


# Building what a demo plays on.

def quiet(argv: List[str], what: str) -> None:
    out = subprocess.run(argv, cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if out.returncode:
        sys.exit(f"demos: {what} failed:\n{out.stdout[-3000:]}")


def newest(*folders: Path) -> float:
    """The newest file under the folders (or a file itself), skipping hidden
    ones (.pio, the packages)."""
    latest = 0.0
    for folder in folders:
        if folder.is_file():
            latest = max(latest, folder.stat().st_mtime)
        for root, dirs, files in os.walk(folder):
            dirs[:] = [d for d in dirs if not d.startswith(".")]
            for f in files:
                latest = max(latest, os.stat(os.path.join(root, f)).st_mtime)
    return latest


def build_page() -> None:
    """The page, and the board's build (web/build.sh) with the pack staged,
    when the firmware is newer than it."""
    sources = newest(REPO / "firmware" / "src", REPO / "firmware" / "include", REPO / "linkkit" / "device",
                     REPO / "simulator" / "core", *CHARACTERS.glob("*/firmware"), *CHARACTERS.glob("*/rig"),
                     *CHARACTERS.glob("*/character.json"))
    built = DIST / "boop-sim.wasm"
    if not built.exists() or built.stat().st_mtime < sources:
        print("demos: building the simulator (a minute or so)…")
        quiet([sys.executable, str(CHARACTERS / "charactergen.py"), "--stage"], "staging the pack")
        quiet([str(REPO / "simulator/web/build.sh")], "simulator/web/build.sh")
    for page in ("boop-simulator.js", "index.html"):
        shutil.copy2(REPO / "simulator" / "web" / page, DIST / page)


def build_app() -> None:
    print("demos: building the app (make -C internal build)…")
    quiet(["make", "-C", "internal", "build"], "make -C internal build")


def build_core(into: Path) -> Path:
    """The simulator's board on the Mac (PlatformIO's native env, which
    stages the pack first), copied so a build meanwhile leaves it as it is."""
    print("demos: building the simulator's board…")
    quiet([str(REPO / "firmware/tools/pio.sh"), "run", "-e", "native"], "firmware/tools/pio.sh run -e native")
    core = into / "core"
    shutil.copy2(CORE, core)
    return core


# Recording.

def wait_for(path: Path, seconds: float) -> bool:
    end = time.time() + seconds
    while time.time() < end:
        if path.exists():
            return True
        time.sleep(0.1)
    return False


def record_one(d: Demo, core: Path) -> Optional[str]:
    """Plays the demo through the headless app, on the simulator's board
    on the Mac, and writes its recording with the script's hash. Its log's
    tail if it fails, else None."""
    # Short, for the sockets' sake: a Unix socket's path has room for 103 bytes.
    work = Path(tempfile.mkdtemp(prefix="boop-rec.", dir="/tmp"))
    env = dict(os.environ, BOOP_SIM_PORT=str(work / "port"))
    children = []
    try:
        children.append(subprocess.Popen([str(core), "--live"], env=env, stdout=subprocess.DEVNULL,
                                         stderr=subprocess.DEVNULL))
        if not wait_for(work / "port", 10):
            return "the simulator's board didn't start"
        children.append(subprocess.Popen([str(BRIDGE), "--port", str(work / "port"), "--socket", str(work / "usb.sock")],
                                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
        if not wait_for(work / "usb.sock", 10):
            return "the bridge didn't start"
        out = work / "recording.json"
        log = work / "boop.log"
        with open(log, "w") as f:
            status = subprocess.call(
                [str(BOOP), "--headless", "--state-dir", str(work / "state"), "--link", f"usb:{work}/usb.sock",
                 "--socket", str(work / "boop.sock"), "--no-open", "--name", creature(d.pack), "--demo", str(d.to_record(work)),
                 "--record", str(out)],
                cwd=REPO, env=dict(os.environ, BOOP_CHARACTER=str(CHARACTERS / d.pack)), stdout=f,
                stderr=subprocess.STDOUT, timeout=30 * 60)
        if status or not out.exists():
            lines = log.read_text().splitlines()
            return "\n".join(l for l in lines if "demo:" in l or not l[:1].isdigit())[-1500:] or "nothing was recorded"
        recording = json.loads(out.read_text())
        recording["script"] = d.hash()
        d.recording.parent.mkdir(exist_ok=True)
        d.recording.write_text(json.dumps(recording, indent=2, sort_keys=True, ensure_ascii=False) + "\n")
        return None
    finally:
        for child in children:
            child.terminate()
        for child in children:
            try:
                child.wait(5)
            except subprocess.TimeoutExpired:
                child.kill()
        shutil.rmtree(work, ignore_errors=True)


def record(chosen: List[Demo], jobs: int = JOBS) -> int:
    if not chosen:
        print("demos: every recording is up to date")
        return 0
    build_app()
    with tempfile.TemporaryDirectory(prefix="boop-cores.", dir="/tmp") as into:
        core = build_core(Path(into))
        print(f"demos: recording {len(chosen)} demo{'s' * (len(chosen) > 1)}, {jobs} at a time; "
              "each takes as long as it runs")
        failed = []

        def one(d: Demo) -> None:
            why = record_one(d, core)
            if why:
                failed.append(d)
                print(f"  {d.id}: failed\n    " + why.replace("\n", "\n    "))
            else:
                print(f"  {d.id}: recorded, {d.length()}")
            sys.stdout.flush()

        with ThreadPoolExecutor(jobs) as pool:
            list(pool.map(one, chosen))
    if failed:
        print(f"demos: {len(failed)} failed: {', '.join(d.id for d in failed)}")
        return 1
    print("demos: done. Commit the recordings with their scripts.")
    return 0


def check() -> int:
    stale = [d for d in demos() if not d.fresh()]
    for d in stale:
        why = "has no recording" if not d.recording.exists() else "has changed since it was recorded"
        print(f"demos: {d.path.relative_to(REPO)} {why}")
    loose = [r for r in CHARACTERS.glob("*/demo/recordings/*.json") if not r.parents[1].joinpath(f"{r.stem}.jsonl").exists()]
    for r in loose:
        print(f"demos: {r.relative_to(REPO)} is a recording of no script")
    if stale or loose:
        print("demos: record them with `make -C internal demos`, then commit the recordings")
        return 1
    return 0


# Playing.

def free_port(start: int = 8206) -> int:
    for port in range(start, start + 20):
        with socket.socket() as s:
            if s.connect_ex(("127.0.0.1", port)):
                return port
    sys.exit("demos: no free port from 8206 to 8225")


def lay_out(chosen: List[Demo]) -> None:
    """Each demo's recording, and a voice file of only the takes it says,
    in the page's demo/PACK/ folder."""
    voices = {}
    for d in chosen:
        folder = DIST / "demo" / d.pack
        folder.mkdir(parents=True, exist_ok=True)
        recording = d.recorded()
        (folder / f"{d.name}.json").write_text(json.dumps(recording))
        voice = pack_voice(d.pack)
        if recording.get("takes") and voice.exists():
            if voice not in voices:
                voices[voice] = voice.read_bytes()
            (folder / f"{d.name}-voice.bin").write_bytes(subset(voices[voice], recording["takes"]))


def serve(query: str) -> int:
    """Serves the page until Ctrl-C, and opens it at the query."""
    port = free_port()
    work = Path(tempfile.mkdtemp(prefix="boop-page.", dir="/tmp"))
    argv = [sys.executable, str(REPO / "simulator/web/serve.py"), "--port", str(port)]
    argv += ["--socket", str(work / "usb.sock")]
    server = subprocess.Popen(argv, cwd=REPO, stdout=subprocess.DEVNULL, start_new_session=True)
    url = f"http://127.0.0.1:{port}/?{query}"
    try:
        time.sleep(1)
        if server.poll() is not None:
            return 1
        print(f"demos: {url}   (Ctrl-C stops it)")
        # Opened only for someone at a terminal, not for a script or an agent.
        if sys.stdout.isatty():
            webbrowser.open(url)
        server.wait()
        return 0
    except KeyboardInterrupt:
        print()
        return 0
    finally:
        if server.poll() is None:
            os.killpg(server.pid, signal.SIGTERM)
        shutil.rmtree(work, ignore_errors=True)


def play_page(d: Demo) -> int:
    if not d.fresh():
        print(f"demos: {d.id} isn't recorded yet, so it's recorded first, as long as it runs")
        if record([d]):
            return 1
    build_page()
    lay_out([d])
    return serve(f"demo={d.id}")


def play_all() -> int:
    stale = [d for d in demos() if not d.fresh()]
    if stale:
        print(f"demos: {len(stale)} demo{'s' * (len(stale) > 1)} aren't recorded yet: they're recorded first")
        if record(stale):
            return 1
    chosen = demos()
    build_page()
    lay_out(chosen)
    playlist = [{"id": d.id, "title": d.title, "length": d.length()} for d in chosen]
    (DIST / "demo" / "playlist.json").write_text(json.dumps(playlist))
    return serve("demos=all")


def play_board(d: Demo, board: Optional[str]) -> int:
    """Live on a real board over USB: the bridge's socket, or a bridge
    started for it."""
    build_app()
    bridge = None
    if not board:
        board = os.path.join(tempfile.gettempdir(), "linkkit-bridge.sock")
        if not os.path.exists(board):
            print("demos: starting the USB bridge (quit the Boop app first, so only one app talks to the board)")
            bridge = subprocess.Popen([str(BRIDGE), "--socket", board])
            if not wait_for(Path(board), 10):
                bridge.terminate()
                return 1
        board = f"usb:{board}"
    if not board.startswith("usb:"):
        sys.exit("demos: --board is usb:SOCKET")
    print(f"demos: playing {d.id} on the board at {board}")
    try:
        return subprocess.call([str(BOOP), "--headless", "--state-dir", tempfile.mkdtemp(prefix="boop-demo.", dir="/tmp"),
                                "--link", board, "--no-open", "--name", creature(d.pack), "--demo", str(d.path)],
                               cwd=REPO, env=dict(os.environ, BOOP_CHARACTER=str(CHARACTERS / d.pack)))
    except KeyboardInterrupt:
        return 0
    finally:
        if bridge:
            bridge.terminate()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("list")
    play = sub.add_parser("play")
    play.add_argument("name", help="NAME, or PACK/NAME; all plays every one in the page")
    play.add_argument("--board", help="usb:SOCKET, a real board on a bridge's socket")
    sub.add_parser("all")
    rec = sub.add_parser("record")
    rec.add_argument("names", nargs="*", help="these, recorded again")
    rec.add_argument("--all", action="store_true", help="every demo, recorded again")
    rec.add_argument("--jobs", type=int, default=JOBS, help=f"how many at once ({JOBS})")
    sub.add_parser("check")
    args = parser.parse_args()
    # Stopped any way but a kill, it stops what it started (the page's
    # server, the boards, the bridge) on its way out.
    for each in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(each, lambda *_: sys.exit(1))
    if args.command is None:
        if sys.stdin.isatty() and sys.stdout.isatty():
            return menu()
        args.command = "list"
    if args.command == "list":
        table(demos(), numbered=False)
        print("\n  make demo asks which and where; make demo NAME=<name> plays one in the browser")
        return 0
    if args.command == "all" or getattr(args, "name", None) == "all":
        return play_all()
    if args.command == "play":
        d = find(args.name)
        return play_board(d, args.board) if args.board else play_page(d)
    if args.command == "record":
        chosen = demos() if args.all else [find(n) for n in args.names] if args.names else \
            [d for d in demos() if not d.fresh()]
        return record(chosen, args.jobs)
    return check()


if __name__ == "__main__":
    sys.exit(main())
