"""`Boop --headless` for the commands that drive it (internal/VERIFICATION.md
§2): `boopctl e2e` and `soak --pipeline` against the bridge, and `boopctl
workday` against its own fake device. It starts the app with throwaway
state on short sockets under /tmp (a Unix socket's path has room for 103
bytes), waits until it reaches the device link, sends it dev and hook
lines, and stops it. It passes --no-open: a tap while something needs you
only logs where it would have opened the thread."""
from __future__ import annotations

import signal
import subprocess
import time
from pathlib import Path
from typing import Any, Callable

from boopctl_lib.common import REPO, send_line
from boopctl_lib.device import DeviceError

BIN = REPO / ".build" / "debug"


class Headless:
    def __init__(self, state: Path, socket: str, link: str, brain: str, extra: list[str] | None = None) -> None:
        self.state = state
        self.socket = socket
        self.link = link
        self.brain = brain
        self.extra = extra or []
        self.debug = state / "debug.jsonl"
        self.log = state / "boop.log"
        self.proc: subprocess.Popen | None = None

    def start(self, stdout: Any = subprocess.DEVNULL, seconds: float = 10, poll: float = 0.05) -> None:
        """Launches the app, which makes `state` if it's missing, and waits
        until its log says it reached the device link."""
        if len(self.socket) > 100:
            raise DeviceError(f"{self.socket} is too long for a Unix socket; use a shorter state directory")
        if not (BIN / "Boop").exists():
            raise DeviceError(f"no {BIN / 'Boop'}; run make -C internal build")
        cmd = [str(BIN / "Boop"), "--headless", "--state-dir", str(self.state), "--link", self.link,
               "--socket", self.socket, "--brain", self.brain, "--name", "Pip", "--no-open", "--debug"] + self.extra
        self.proc = subprocess.Popen(cmd, stdout=stdout, stderr=subprocess.STDOUT)
        self.wait_for(lambda: "device link: connected" in self.log_text(), seconds, "the app to reach the device link",
                      poll)

    def wait_for(self, ok: Callable[[], bool], seconds: float, what: str, poll: float = 0.05) -> None:
        """Polls `ok` every `poll` s for `seconds`; fails at once if the app
        has exited."""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if self.proc and self.proc.poll() is not None:
                raise DeviceError(f"the app exited ({self.proc.returncode}) waiting for {what}")
            if ok():
                return
            time.sleep(poll)
        raise DeviceError(f"timed out waiting for {what}")

    def log_text(self) -> str:
        return self.log.read_text(errors="replace") if self.log.exists() else ""

    def send(self, line: dict[str, Any]) -> None:
        """One line to the hook socket: a dev line or a hook's wire form."""
        if why := send_line(self.socket, line):
            raise DeviceError(why)

    def alive(self) -> bool:
        return bool(self.proc) and self.proc.poll() is None

    def stop(self) -> int | str | None:
        """Stops the app (`stop_proc`); None if it wasn't running."""
        return stop_proc(self.proc) if self.alive() else None


def stop_proc(proc: subprocess.Popen) -> int | str:
    """SIGTERM, then a kill after 10 s; its exit code, or `killed`."""
    proc.send_signal(signal.SIGTERM)
    try:
        return proc.wait(10)
    except subprocess.TimeoutExpired:
        proc.kill()
        return "killed"
