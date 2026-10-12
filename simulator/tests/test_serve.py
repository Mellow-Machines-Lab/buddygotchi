"""The simulator's server and its USB socket (web/serve.py): a second copy
leaves the first's socket alone, a stale socket is replaced, and a server
stopped by a signal takes its socket with it. Each test runs its own servers
on a free port and a socket of its own, never the everyday ones."""
from __future__ import annotations

import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SERVE = REPO / "simulator" / "web" / "serve.py"


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def answers(path: str) -> bool:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        try:
            s.connect(path)
            return True
        except OSError:
            return False


class ServeSocket(unittest.TestCase):
    def setUp(self) -> None:
        # A short directory: a socket's path has room for 103 bytes.
        self.dir = tempfile.mkdtemp(prefix="bsim", dir="/tmp")
        self.socket = os.path.join(self.dir, "usb.sock")
        self.dist = os.path.join(self.dir, "dist")
        os.mkdir(self.dist)
        Path(self.dist, "boop-sim.wasm").write_bytes(b"")
        self.procs = []

    def tearDown(self) -> None:
        for proc in self.procs:  # only the servers this test started
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=5)
            proc.stdout.close()
            proc.stderr.close()
        for name in os.listdir(self.dir):
            path = os.path.join(self.dir, name)
            if os.path.isdir(path):
                for f in os.listdir(path):
                    os.unlink(os.path.join(path, f))
                os.rmdir(path)
            else:
                os.unlink(path)
        os.rmdir(self.dir)

    def start(self, port: int) -> subprocess.Popen:
        proc = subprocess.Popen([sys.executable, str(SERVE), "--port", str(port), "--socket", self.socket,
                                 "--dist", self.dist, "--voice", os.devnull],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.procs.append(proc)
        return proc

    def running(self, port: int) -> subprocess.Popen:
        proc = self.start(port)
        line = proc.stdout.readline().decode()
        self.assertIn(f":{port}/", line, proc.stderr.read().decode() if not line else line)
        proc.stdout.readline()  # where its socket is: listening by now
        self.assertTrue(answers(self.socket))
        return proc

    def test_second_server_on_the_same_port_leaves_the_first_socket(self) -> None:
        port = free_port()
        first = self.running(port)
        inode = os.lstat(self.socket).st_ino
        second = self.start(port)
        self.assertEqual(second.wait(timeout=10), 1)
        self.assertIn("is a simulator already running?", second.stderr.read().decode())
        self.assertIsNone(first.poll())
        self.assertEqual(os.lstat(self.socket).st_ino, inode)
        self.assertTrue(answers(self.socket))

    def test_second_server_on_another_port_leaves_a_live_socket(self) -> None:
        first = self.running(free_port())
        inode = os.lstat(self.socket).st_ino
        second = self.start(free_port())
        self.assertEqual(second.wait(timeout=10), 1)
        self.assertIn("is a simulator already running?", second.stderr.read().decode())
        self.assertIsNone(first.poll())
        self.assertEqual(os.lstat(self.socket).st_ino, inode)
        self.assertTrue(answers(self.socket))

    def test_a_stale_socket_is_replaced(self) -> None:
        stale = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        stale.bind(self.socket)  # bound, never listening: what a killed server leaves
        stale.close()
        self.assertFalse(answers(self.socket))
        inode = os.lstat(self.socket).st_ino
        self.running(free_port())
        self.assertNotEqual(os.lstat(self.socket).st_ino, inode)

    def test_a_file_that_isnt_a_socket_is_left(self) -> None:
        Path(self.socket).write_text("not a socket")
        proc = self.start(free_port())
        self.assertEqual(proc.wait(timeout=10), 1)
        self.assertEqual(Path(self.socket).read_text(), "not a socket")

    def test_sigterm_and_sighup_remove_the_socket(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGHUP):
            with self.subTest(signal=sig.name):
                proc = self.running(free_port())
                proc.send_signal(sig)
                self.assertEqual(proc.wait(timeout=10), 0)
                self.assertFalse(os.path.lexists(self.socket))

    def test_a_newer_servers_socket_stays_when_the_old_one_stops(self) -> None:
        old = self.running(free_port())
        os.unlink(self.socket)  # as if a newer simulator took the path
        newer = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        newer.bind(self.socket)
        newer.listen(1)
        try:
            old.send_signal(signal.SIGTERM)
            self.assertEqual(old.wait(timeout=10), 0)
            self.assertTrue(answers(self.socket))
        finally:
            newer.close()


if __name__ == "__main__":
    unittest.main()
