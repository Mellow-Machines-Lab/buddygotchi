"""The board's lock: one for every board on this Mac, which everything that
talks to a board over USB takes first (boopctl's serial link, e2e's bridge,
every PlatformIO upload through firmware/tools/pio.sh), so no session
flashes or resets the board under another session's test. A session that
wants the board through several steps (flash, test, flash back) holds it
across them with `boopctl board hold -- CMD`.

Whoever holds it is written in the lock file, so a tool that has to wait
says who it's waiting for, and every upload is logged beside it, so
`boopctl board` says what's on the board and who put it there.

Standard library only, on Python 3.9: pio.sh runs this file as a script
with whatever `python3` there is (`board.py upload -- PIO ARGS…`).
"""
from __future__ import annotations

import argparse
import datetime
import fcntl
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

# How long a tool waits for another's hold before giving up and saying
# whose it is: long enough for a flash or a short check, shorter than an
# agent's two-minute command limit, so the reason gets printed.
WAIT_S = 60
POLL_S = 0.5
HELD_ENV = "BOOP_BOARD_HELD"  # the holder's token, which its children inherit


class Busy(Exception):
    pass


def lock_path() -> Path:
    return Path(os.environ.get("BOOP_BOARD_LOCK") or "/tmp/boop-board.lock")


def flashes_path() -> Path:
    return lock_path().with_name("boop-board-flashes.log")


def wait_s() -> float:
    try:
        return float(os.environ.get("BOOP_BOARD_WAIT", WAIT_S))
    except ValueError:
        return WAIT_S


def simulated(port: str | None) -> bool:
    """The simulator's port is a pseudo-terminal, no board's."""
    return bool(port) and os.path.realpath(port).startswith(("/dev/ttys", "/dev/pts/"))


def _git(*args: str, cwd: str | None = None) -> str:
    try:
        return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=5).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def worktree(cwd: str | None = None) -> str:
    return _git("rev-parse", "--show-toplevel", cwd=cwd) or os.getcwd()


def holder() -> dict[str, Any] | None:
    """Who holds the lock now, or None while nobody does."""
    path = lock_path()
    try:
        fd = os.open(path, os.O_RDONLY)
    except FileNotFoundError:
        return None
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
        except BlockingIOError:
            try:
                return json.loads(path.read_text() or "{}") or {"why": "an unnamed tool"}
            except (OSError, ValueError):
                return {"why": "an unnamed tool"}
        fcntl.flock(fd, fcntl.LOCK_UN)
        return None
    finally:
        os.close(fd)


def describe(h: dict[str, Any]) -> str:
    since = h.get("since")
    about = [f"pid {h['pid']}"] if h.get("pid") else []
    about += [Path(h["worktree"]).name] if h.get("worktree") else []
    about += [f"for {_duration(time.time() - since)}"] if isinstance(since, (int, float)) else []
    return h.get("why", "an unnamed tool") + (f" ({', '.join(about)})" if about else "")


def _duration(s: float) -> str:
    s = int(max(0, s))
    return f"{s // 60}m{s % 60:02d}s" if s >= 60 else f"{s}s"


def _alive(pid: Any) -> bool:
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, TypeError, ValueError):
        return False


_depth = 0
_fd: int | None = None


class Hold:
    """The lock while the `with` lasts. Nested holds in one process, and a
    holder's children (through HELD_ENV), go straight through."""

    def __init__(self, why: str, port: str | None = None, wait: float | None = None) -> None:
        self.why = why
        self.wait = wait_s() if wait is None else wait
        self.noop = simulated(port)
        self.took = False

    def __enter__(self) -> "Hold":
        global _depth, _fd
        if self.noop:
            return self
        if _depth:
            _depth += 1
            return self
        token = os.environ.get(HELD_ENV)
        if token:
            h = holder()
            if h and h.get("token") == token and _alive(h.get("pid")):
                self.noop = True
                return self
        fd = os.open(lock_path(), os.O_CREAT | os.O_RDWR, 0o666)
        deadline = time.monotonic() + self.wait
        said = False
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                h = holder() or {"why": "a tool that just let go"}
                if time.monotonic() >= deadline:
                    os.close(fd)
                    raise Busy(f"the board is in use by {describe(h)}; try again when it's done, "
                               f"or wait longer with BOOP_BOARD_WAIT=SECONDS (`boopctl board` shows who has it)")
                if not said:
                    print(f"board: in use by {describe(h)}; waiting up to {self.wait:g} s", file=sys.stderr, flush=True)
                    said = True
                time.sleep(POLL_S)
        token = f"{os.getpid()}-{time.time():.6f}"
        record = {"token": token, "pid": os.getpid(), "worktree": worktree(), "why": self.why, "since": time.time()}
        os.ftruncate(fd, 0)
        os.pwrite(fd, json.dumps(record).encode() + b"\n", 0)
        os.environ[HELD_ENV] = token
        _fd, _depth, self.took = fd, 1, True
        return self

    def __exit__(self, *_: object) -> None:
        global _depth, _fd
        if self.noop:
            return
        _depth -= 1
        if _depth or _fd is None:
            return
        os.ftruncate(_fd, 0)
        fcntl.flock(_fd, fcntl.LOCK_UN)
        os.close(_fd)
        _fd = None
        os.environ.pop(HELD_ENV, None)


def hold(why: str, cmd: list[str]) -> int:
    """Runs `cmd` holding the board; its exit status."""
    with Hold(why):
        try:
            return subprocess.call(cmd)
        except KeyboardInterrupt:
            return 130


def _value(args: list[str], *flags: str) -> str | None:
    """The value of the last of `flags` in a command line (`-e X` or `--environment=X`)."""
    found = None
    for i, a in enumerate(args):
        for f in flags:
            if a == f and i + 1 < len(args):
                found = args[i + 1]
            elif a.startswith(f + "=") and f.startswith("--"):
                found = a.split("=", 1)[1]
    return found


def build_only(cmd: list[str]) -> list[str]:
    """A PlatformIO command line without its upload targets: what builds
    the firmware before the lock is taken, so a build never holds the board."""
    out: list[str] = []
    skip = False
    for i, a in enumerate(cmd):
        if skip:
            skip = False
            continue
        if a in ("-t", "--target") and i + 1 < len(cmd) and cmd[i + 1].startswith("upload"):
            skip = True
            continue
        if a.startswith(("-tupload", "--target=upload")):
            continue
        out.append(a)
    return out


def log_flash(cmd: list[str], status: int) -> dict[str, Any]:
    """Appends one upload to the flash log: when, which env, where from, ok or not."""
    here = os.getcwd()
    entry = {
        "at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "env": _value(cmd, "-e", "--environment") or "?",
        "port": _value(cmd, "--upload-port") or "?",
        "worktree": worktree(here),
        "branch": _git("rev-parse", "--abbrev-ref", "HEAD", cwd=here),
        "commit": _git("describe", "--always", "--dirty", "--abbrev=10", cwd=here),
        "ok": status == 0,
    }
    with open(flashes_path(), "a") as f:
        f.write(json.dumps(entry) + "\n")
    return entry


def upload(cmd: list[str]) -> int:
    """Builds without the lock, then uploads holding it, and logs the upload."""
    build = build_only(cmd)
    if build != cmd:
        status = subprocess.call(build)
        if status:
            return status
    env = _value(cmd, "-e", "--environment")
    with Hold(f"flash {env or 'firmware'}", port=_value(cmd, "--upload-port")):
        status = subprocess.call(cmd)
        log_flash(cmd, status)
    return status


def flashes(n: int) -> list[dict[str, Any]]:
    try:
        lines = flashes_path().read_text().splitlines()
    except FileNotFoundError:
        return []
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except ValueError:
            pass
    return out


def status(n: int = 8) -> str:
    """Who has the board now, and the last `n` uploads, newest last."""
    h = holder()
    lines = [f"board: in use by {describe(h)}" if h else "board: free"]
    recent = flashes(n)
    if recent:
        lines.append("flashed:")
        for e in recent:
            lines.append(f"  {e.get('at', '?')}  {e.get('env', '?'):<18} {e.get('commit', '?'):<18} "
                         f"{Path(e.get('worktree') or '?').name} ({e.get('branch', '?')})"
                         + ("" if e.get("ok") else "  FAILED"))
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="board.py", description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("upload", "hold"):
        p = sub.add_parser(name)
        p.add_argument("cmd", nargs=argparse.REMAINDER)
    sub.add_parser("status")
    args = parser.parse_args(argv)
    if args.command == "status":
        print(status())
        return 0
    cmd = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
    if not cmd:
        parser.error("no command to run")
    try:
        return upload(cmd) if args.command == "upload" else hold(" ".join(cmd), cmd)
    except Busy as exc:
        print(f"board: {exc}", file=sys.stderr)
        return 75  # EX_TEMPFAIL


if __name__ == "__main__":
    sys.exit(main())
