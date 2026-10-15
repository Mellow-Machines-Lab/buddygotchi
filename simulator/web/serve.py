#!/usr/bin/env python3
"""Serves the simulator's page on this Mac, and gives the board in it a USB
cable (simulator/README.md).

The page is simulator/web/dist/, which build.sh makes. The cable is a Unix
socket that keeps a bridge's rules (linkkit/SPEC.md §8): every whole line
from the board goes to every client, and every whole line from a client
goes to the board whole. So the Mac app (`Boop --link usb:SOCKET`) and
`boopctl` (`BOOP_BRIDGE=SOCKET`) reach the board in the browser as they
reach one on a bridge. The page's end of it is a WebSocket at /usb, one
line a message; the newest page to connect is the board.

Only this Mac can reach it: the page is served on 127.0.0.1 and the socket
is its user's alone. The standard library only, so it runs on the Mac's
own Python.
"""
import argparse
import base64
import errno
import hashlib
import os
import select
import signal
import socket
import stat
import struct
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "simulator" / "tools"))
from voice_subset import chosen_voice  # noqa: E402  the pack in use's voice
sys.path.pop(0)


# A client this far behind on the board's lines (it stopped reading) is
# dropped, so it can't stall them to the others; and a line from a client
# longer than this is dropped whole, as the board drops it (linkkit/SPEC.md
# §8, §9). The board's own lines may be longer: a screenshot's is.
MAX_BEHIND = 4 * 1024 * 1024
MAX_LINE = 512


class Cable:
    """The board's lines to every client, and the clients' to the board,
    by a bridge's rules (linkkit/SPEC.md §8). One thread serves the
    clients and never waits on one: each has its own backlog, sent as it
    reads."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.board = None  # the page's WebSocket: a callable that sends one line
        self.backlog = {}  # each client's lines it hasn't read yet
        self.wake_r, self.wake_w = os.pipe()  # wakes the clients' thread for new lines
        os.set_blocking(self.wake_w, False)

    def plug(self, send) -> None:
        with self.lock:
            self.board = send

    def unplug(self, send) -> None:
        with self.lock:
            if self.board is send:
                self.board = None

    def to_board(self, line: bytes) -> None:
        with self.lock:
            send = self.board
        if send:
            try:
                send(line)
            except OSError:
                self.unplug(send)

    def to_clients(self, line: bytes) -> None:
        with self.lock:
            for out in self.backlog.values():
                out.extend(line + b"\n")
        try:
            os.write(self.wake_w, b"x")
        except BlockingIOError:  # already woken
            pass

    def serve(self, path: str) -> tuple:
        """Listens at the path, and returns what identifies the socket made
        there, so it's removed at the end only if it's still this one. A
        socket that something answers on is another simulator's, and is left
        alone; one nothing answers on is a stale one's, and goes."""
        if os.path.lexists(path):
            if not stat.S_ISSOCK(os.lstat(path).st_mode):
                raise InUse(f"{path} is there and isn't a socket")
            probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                probe.connect(path)
                raise InUse(f"something answers on {path}: is a simulator already running?")
            except OSError as e:
                if e.errno not in (errno.ECONNREFUSED, errno.ENOENT):
                    raise
            finally:
                probe.close()
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        os.chmod(path, 0o600)
        server.listen(8)
        made = os.lstat(path)
        ours = (made.st_dev, made.st_ino)

        def clients() -> None:
            server.setblocking(False)
            partial = {}  # what each client has sent since its last newline; None while dropping a long line

            def drop(conn: socket.socket) -> None:
                with self.lock:
                    self.backlog.pop(conn, None)
                partial.pop(conn, None)
                conn.close()

            while True:
                with self.lock:
                    behind = [c for c, out in self.backlog.items() if len(out) > MAX_BEHIND]
                    waiting = [c for c, out in self.backlog.items() if out and c not in behind]
                for conn in behind:
                    drop(conn)
                readable, writable, _ = select.select([server, self.wake_r, *partial], waiting, [])
                for conn in writable:
                    with self.lock:
                        out = self.backlog.get(conn)
                        try:
                            del out[:conn.send(out)]
                        except BlockingIOError:
                            pass
                        except OSError:
                            out = None
                    if out is None:
                        drop(conn)
                for r in readable:
                    if r is server:
                        try:
                            conn, _ = server.accept()
                        except BlockingIOError:
                            continue
                        conn.setblocking(False)
                        partial[conn] = b""
                        with self.lock:
                            self.backlog[conn] = bytearray()
                    elif r == self.wake_r:
                        os.read(self.wake_r, 4096)
                    elif r in partial:
                        try:
                            data = r.recv(65536)
                        except BlockingIOError:
                            continue
                        except OSError:
                            data = b""
                        if not data:
                            drop(r)
                            continue
                        *lines, rest = data.split(b"\n")
                        for line in lines:
                            if partial[r] is not None and len(partial[r]) + len(line) <= MAX_LINE:
                                line, partial[r] = partial[r] + line, b""
                                if line:
                                    self.to_board(line)
                            else:
                                partial[r] = b""
                        if partial[r] is not None:
                            partial[r] += rest
                            if len(partial[r]) > MAX_LINE:
                                partial[r] = None  # dropped whole, up to its newline

        threading.Thread(target=clients, daemon=True).start()
        return ours


class InUse(Exception):
    """Another simulator has the port or the socket."""


def remove_if_ours(path: str, ours: tuple) -> None:
    """Removes the socket only if it's still the one this server made: a
    newer simulator's, made after a stale one was taken, stays."""
    try:
        now = os.lstat(path)
        if (now.st_dev, now.st_ino) == ours:
            os.unlink(path)
    except FileNotFoundError:
        pass


def websocket(handler: SimpleHTTPRequestHandler, cable: Cable) -> None:
    """The page's end of the cable: text messages, one line each."""
    key = handler.headers.get("Sec-WebSocket-Key", "")
    accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    handler.send_response(101)
    handler.send_header("Upgrade", "websocket")
    handler.send_header("Connection", "Upgrade")
    handler.send_header("Sec-WebSocket-Accept", accept)
    handler.end_headers()
    conn, rfile, lock = handler.connection, handler.rfile, threading.Lock()

    def send(line: bytes, op: int = 1) -> None:
        n = len(line)
        head = bytes([0x80 | op]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack(">H", n) if n < 65536
                                     else bytes([127]) + struct.pack(">Q", n))
        with lock:
            conn.sendall(head + line)

    cable.plug(send)
    message = b""
    try:
        while True:
            head = rfile.read(2)
            if len(head) < 2:
                break
            op, n = head[0] & 0x0F, head[1] & 0x7F
            if n == 126:
                n = struct.unpack(">H", rfile.read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", rfile.read(8))[0]
            mask = rfile.read(4) if head[1] & 0x80 else b"\0\0\0\0"
            data = rfile.read(n)
            if any(mask):  # all at once: a screenshot's line is most of a megabyte
                key = int.from_bytes((mask * (n // 4 + 1))[:n], "big")
                data = (int.from_bytes(data, "big") ^ key).to_bytes(n, "big")
            if op == 8:  # close
                break
            if op == 9:  # ping
                send(data, 10)
                continue
            if op in (0, 1, 2):
                message += data
                if head[0] & 0x80:  # the last piece
                    for line in message.split(b"\n"):
                        if line:
                            cable.to_clients(line)
                    message = b""
    except OSError:
        pass
    cable.unplug(send)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--port", type=int, default=8206, help="the page's port on 127.0.0.1 (8206)")
    parser.add_argument("--socket", default="/tmp/boop-sim-usb.sock", help="the board's USB, as a bridge's socket (/tmp/boop-sim-usb.sock)")
    parser.add_argument("--dist", default=str(HERE / "dist"), help="the built page (simulator/web/dist)")
    parser.add_argument("--voice", default=str(chosen_voice()), help="the voice pack on the board's card (the chosen character pack's, if it has one)")
    args = parser.parse_args()
    if not (Path(args.dist) / "boop-sim.wasm").exists():
        print(f"simulator: nothing built in {args.dist}: run simulator/web/build.sh", file=sys.stderr)
        return 1
    cable = Cable()

    class Page(SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=args.dist, **k)

        def do_GET(self):
            if self.path == "/usb" and self.headers.get("Upgrade", "").lower() == "websocket":
                websocket(self, cable)
                self.close_connection = True
                return
            super().do_GET()

        def translate_path(self, path):
            if path.split("?")[0] == "/voice.bin":
                return args.voice
            return super().translate_path(path)

        def end_headers(self):
            if not self.path.endswith(".bin"):  # a rebuild shows at the next reload; a voice is big, and keeps
                self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def log_message(self, *a):
            pass

    # The port first: a second copy fails on it before it touches the first's
    # socket.
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), Page)
    except OSError as e:
        if e.errno != errno.EADDRINUSE:
            raise
        print(f"simulator: port {args.port} is in use: is a simulator already running?", file=sys.stderr)
        return 1
    try:
        ours = cable.serve(args.socket)
    except InUse as e:
        server.server_close()
        print(f"simulator: {e}", file=sys.stderr)
        return 1

    # Stopped any way but a kill, it takes its socket with it, so the app
    # doesn't go on finding a simulator that's gone.
    def stop(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    print(f"Boop Simulator: http://127.0.0.1:{args.port}/   (add ?face=gel for Boop's own face)")
    print(f"its USB, as a bridge's socket: {args.socket}")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        server.server_close()
        remove_if_ours(args.socket, ours)
    return 0


if __name__ == "__main__":
    sys.exit(main())
