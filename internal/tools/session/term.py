"""The agent's terminal: its real TUI in a pseudo-terminal, shown in yours.

What the agent draws goes to this terminal as it is, so a screen recording
of it is the agent as anyone sees it. The session tool types into it as a
person would, and can wait for words to appear on it, such as a permission
dialog. Your own keys still reach the agent, so Ctrl-C works as ever.
"""
from __future__ import annotations

import codecs
import fcntl
import os
import pty
import random
import re
import select
import signal
import struct
import sys
import termios
import threading
import time
import tty
from typing import Dict, List, Optional

# Escape sequences, so the screen's words can be searched: CSI, OSC and
# the two-byte ones.
ESCAPES = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b[@-Z\\-_]")


def words(text: str) -> str:
    """Text with escapes and every space gone, so it matches however the
    TUI spaced or redrew it."""
    return re.sub(r"\s+", "", ESCAPES.sub("", text))


class Terminal:
    def __init__(self, argv: List[str], cwd: str, env: Dict[str, str], mirror: str):
        """Starts `argv` in a pseudo-terminal. With this process on a
        terminal, the agent is shown there; else what it draws goes to the
        file `mirror`."""
        self.shown = sys.stdout.isatty() and sys.stdin.isatty()
        self.out = None if self.shown else open(mirror, "wb")
        rows, cols = self.size()
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execvpe(argv[0], argv, env)
        self.resize(rows, cols)
        # The screen's words so far (`words`), stripped as they come, and
        # how many were let go from its start; an escape a read cut in two
        # waits for the rest.
        self.screen = ""
        self.dropped = 0
        self.decode = codecs.getincrementaldecoder("utf-8")("replace").decode
        self.carry = ""
        self.lock = threading.Condition()
        self.done = False
        self.saved = None
        if self.shown:
            self.saved = termios.tcgetattr(sys.stdin.fileno())
            tty.setraw(sys.stdin.fileno())
            signal.signal(signal.SIGWINCH, lambda *_: self.resize(*self.size()))
        threading.Thread(target=self.pump, daemon=True).start()

    @staticmethod
    def size() -> tuple:
        try:
            rows, cols, _, _ = struct.unpack("HHHH", fcntl.ioctl(sys.stdout.fileno(), termios.TIOCGWINSZ, b"\0" * 8))
            if rows and cols:
                return rows, cols
        except OSError:
            pass
        return 40, 120

    def resize(self, rows: int, cols: int) -> None:
        try:
            fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        except OSError:
            pass

    def pump(self) -> None:
        """Copies the agent's screen out and your keys in, until it exits."""
        stdin = sys.stdin.fileno() if self.shown else None
        while True:
            ready, _, _ = select.select([self.fd] + ([stdin] if stdin is not None else []), [], [], 0.1)
            if self.fd in ready:
                try:
                    data = os.read(self.fd, 65536)
                except OSError:
                    data = b""
                if not data:
                    break
                if self.shown:
                    os.write(sys.stdout.fileno(), data)
                else:
                    self.out.write(data); self.out.flush()
                text = self.carry + self.decode(data)
                cut = text.rfind("\x1b", max(0, len(text) - 64))
                if cut >= 0 and not ESCAPES.match(text, cut):
                    text, self.carry = text[:cut], text[cut:]
                else:
                    self.carry = ""
                with self.lock:
                    self.screen += words(text)
                    # The recent screen is enough to look for a dialog in.
                    if len(self.screen) > 200_000:
                        self.dropped += len(self.screen) - 100_000
                        self.screen = self.screen[-100_000:]
                    self.lock.notify_all()
            if stdin is not None and stdin in ready:
                keys = os.read(stdin, 1024)
                if keys:
                    os.write(self.fd, keys)
        with self.lock:
            self.done = True
            self.lock.notify_all()

    def mark(self) -> int:
        """Where the screen is now: `wait_for` looks only after a mark."""
        with self.lock:
            return self.dropped + len(self.screen)

    def wait_for(self, text: str, since: int = 0, timeout: float = 120) -> bool:
        want = words(text)
        end = time.time() + timeout
        with self.lock:
            while True:
                if want in self.screen[max(0, since - self.dropped - len(want)):]:
                    return True
                left = end - time.time()
                if left <= 0 or self.done:
                    return False
                self.lock.wait(min(left, 0.5))

    def press(self, keys: str) -> None:
        os.write(self.fd, keys.encode())

    def type(self, text: str) -> None:
        """Types `text` at a person's pace, then Enter."""
        for ch in text:
            self.press(ch)
            time.sleep(random.uniform(0.03, 0.09) + (0.12 if ch in ".,?!" else 0))
        time.sleep(0.4)
        self.press("\r")

    def wait_exit(self, timeout: float) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            try:
                pid, _ = os.waitpid(self.pid, os.WNOHANG)
            except ChildProcessError:
                return True  # gone, and reaped already
            if pid:
                return True
            time.sleep(0.2)
        return False

    def close(self) -> None:
        if not self.wait_exit(0.1):
            try:
                os.kill(self.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            self.wait_exit(3)
        if self.saved is not None:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, self.saved)
            self.saved = None
        if self.out:
            self.out.close()
