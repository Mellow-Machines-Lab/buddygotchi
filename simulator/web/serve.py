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

With `--cable NAME=SOCKET`, once for each, there are several boards, each
with its own cable: a WebSocket at /usb/NAME and its socket, and no /usb.
The page shows them side by side with ?boards=NAME,NAME.

It also serves characters/ at /characters/, so the Character Studio is at
/characters/studio/, and the page's own files again at /simulator/, where
the studio's board previews look for them under either server; and
/board (or /board/NAME) is what the board says it
shows: its reply to a `dbg.state` the server sends it, as a tool on the
cable would, or null with no board; the studio's matrix marks it.

Only this Mac can reach it: the page is served on 127.0.0.1 and the socket
is its user's alone. The standard library only, so it runs on the Mac's
own Python.
"""
import argparse
import base64
import errno
import hashlib
import os
import posixpath
import re
import select
import signal
import socket
import stat
import struct
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
sys.path.insert(0, str(REPO / "simulator" / "tools"))
from voice_subset import chosen_voice, pack_voice  # noqa: E402  the pack in use's voice, and any pack's
sys.path.pop(0)


# A client this far behind on the board's lines (it stopped reading) is
# dropped, so it can't stall them to the others; and a line from a client
# longer than this is dropped whole, as the board drops it (linkkit/SPEC.md
# §8, §9). The board's own lines may be longer: a screenshot's is.
MAX_BEHIND = 4 * 1024 * 1024
MAX_LINE = 512
# How long /board waits for the board's dbg.state.
ASK_S = 1.0


class Cable:
    """The board's lines to every client, and the clients' to the board,
    by a bridge's rules (linkkit/SPEC.md §8). One thread serves the
    clients and never waits on one: each has its own backlog, sent as it
    reads."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.board = None  # the page's WebSocket: a callable that sends one line
        self.backlog = {}  # each client's lines it hasn't read yet
        self.hanging_up = False  # the clients are to be dropped (hang_up)
        self.asking = []  # (the start of the line awaited, an Event, its line once heard) for ask()
        self.wake_r, self.wake_w = os.pipe()  # wakes the clients' thread for new lines
        os.set_blocking(self.wake_w, False)

    # A board that comes or goes hangs up on the clients, as a board that
    # restarts drops its Bluetooth link: the app connects again within a
    # second and greets the board that's there now, where a socket it kept
    # would leave it waiting for its next heartbeat. The page plugs its
    # cable in afresh at every power-on and reset.
    def plug(self, send) -> None:
        with self.lock:
            self.board = send
        self.hang_up()

    def unplug(self, send) -> None:
        with self.lock:
            if self.board is not send:
                return
            self.board = None
        self.hang_up()

    def hang_up(self) -> None:
        with self.lock:
            self.hanging_up = True
        self.wake()

    def wake(self) -> None:
        try:
            os.write(self.wake_w, b"x")
        except BlockingIOError:  # already woken
            pass

    def to_board(self, line: bytes) -> None:
        with self.lock:
            send = self.board
        if send:
            try:
                send(line)
            except OSError:
                self.unplug(send)

    def ask(self, line: bytes, reply: bytes, timeout: float = ASK_S):
        """Sends the board a line and returns the first of its lines that
        starts with `reply`, or None with no board or no reply in time. The
        reply goes to every client too, as a bridge's do."""
        waiting = [reply, threading.Event(), None]
        with self.lock:
            if not self.board:
                return None
            self.asking.append(waiting)
        self.to_board(line)
        waiting[1].wait(timeout)
        with self.lock:
            if waiting in self.asking:
                self.asking.remove(waiting)
        return waiting[2]

    def to_clients(self, line: bytes) -> None:
        with self.lock:
            for waiting in self.asking:
                if waiting[2] is None and line.startswith(waiting[0]):
                    waiting[2] = line
                    waiting[1].set()
            for out in self.backlog.values():
                out.extend(line + b"\n")
        self.wake()

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
                    hanging_up, self.hanging_up = self.hanging_up, False
                if hanging_up:
                    for conn in list(partial):
                        drop(conn)
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


def unwire(ours: dict) -> None:
    """Removes every socket this server made that's still its own."""
    for socket_path, made in ours.items():
        remove_if_ours(socket_path, made)


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


# A cable's name, which is also the end of its WebSocket's path and, on the
# page, of its board's id; and a pack's name in characters/.
NAME = re.compile(r"[a-z0-9][a-z0-9_-]{0,15}")


def cables(given: list, default_socket: str) -> dict:
    """Each cable's WebSocket path and its socket: /usb and the default
    socket with no --cable, else /usb/NAME for each NAME=SOCKET."""
    if not given:
        return {"/usb": default_socket}
    paths = {}
    for each in given:
        name, _, path = each.partition("=")
        if not NAME.fullmatch(name) or not path:
            raise ValueError(f"--cable {each}: give NAME=SOCKET, the name in lowercase letters, digits, - and _")
        if f"/usb/{name}" in paths or path in paths.values():
            raise ValueError(f"--cable {each}: each cable needs its own name and socket")
        paths[f"/usb/{name}"] = path
    return paths


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--port", type=int, default=8206, help="the page's port on 127.0.0.1 (8206)")
    parser.add_argument("--socket", default="/tmp/boop-sim-usb.sock", help="the board's USB, as a bridge's socket (/tmp/boop-sim-usb.sock)")
    parser.add_argument("--cable", action="append", default=[], metavar="NAME=SOCKET",
                        help="a board of its own, its USB at /usb/NAME and SOCKET; once for each board, in place of --socket")
    parser.add_argument("--dist", default=str(HERE / "dist"), help="the built page (simulator/web/dist)")
    parser.add_argument("--voice", default=str(chosen_voice()), help="the voice file on the board's card (the chosen character pack's, if it has one)")
    args = parser.parse_args()
    if not any(Path(args.dist).glob("boop-sim*.wasm")):
        print(f"simulator: nothing built in {args.dist}: run simulator/web/build.sh", file=sys.stderr)
        return 1
    try:
        sockets = cables(args.cable, args.socket)
    except ValueError as e:
        print(f"simulator: {e}", file=sys.stderr)
        return 2
    wired = {path: Cable() for path in sockets}

    class Page(SimpleHTTPRequestHandler):
        def __init__(self, *a, **k):
            super().__init__(*a, directory=args.dist, **k)

        def do_GET(self):
            cable = wired.get(self.path)
            if cable and self.headers.get("Upgrade", "").lower() == "websocket":
                websocket(self, cable)
                self.close_connection = True
                return
            board = wired.get(self.path.split("?")[0].replace("/board", "/usb", 1)) if self.path.startswith("/board") else None
            if board:
                # null with no board or no reply: a page polling this shouldn't fill its console with errors.
                said = board.ask(b'{"t":"dbg.state"}', b'{"t":"dbg.state"')
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(said or b"null")
                return
            super().do_GET()

        def translate_path(self, path):
            # /characters/: the packs and the Character Studio, as they are in
            # the repository; tidied first, so a .. can't climb out of it.
            tidy = posixpath.normpath(unquote(path.split("?", 1)[0].split("#", 1)[0]))
            if tidy.startswith("/characters/"):
                here, self.directory = self.directory, str(REPO)
                try:
                    return super().translate_path(tidy)
                finally:
                    self.directory = here
            path = path.split("?")[0]
            # /simulator/: the page's files again, where the studio finds the
            # board under either server (characters/studio/serve.cjs too).
            if path.startswith("/simulator/"):
                path = path[len("/simulator"):]
            if path == "/voice.bin":
                return args.voice
            # /voice/PACK.bin: a pack's own voice, for a board built for it.
            pack = re.fullmatch(r"/voice/(.+)\.bin", path)
            if pack and NAME.fullmatch(pack[1]):
                return str(pack_voice(pack[1]))
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
    ours = {}
    try:
        for path, socket_path in sockets.items():
            ours[socket_path] = wired[path].serve(socket_path)
    except InUse as e:
        server.server_close()
        unwire(ours)
        print(f"simulator: {e}", file=sys.stderr)
        return 1

    # Stopped any way but a kill, it takes its socket with it, so the app
    # doesn't go on finding a simulator that's gone.
    def stop(signum, frame):
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGHUP, stop)
    if args.cable:
        names = ",".join(path.rsplit("/", 1)[1] for path in sockets)
        print(f"Boop Simulator: http://127.0.0.1:{args.port}/?boards={names}   (add &packs=boop,pixel for a pack each)")
        for path, socket_path in sockets.items():
            print(f"{path.rsplit('/', 1)[1]}'s USB, as a bridge's socket: {socket_path}")
    else:
        print(f"Boop Simulator: http://127.0.0.1:{args.port}/   (?face=gel picks the gel, for a pack with both faces)")
        print(f"its USB, as a bridge's socket: {args.socket}")
        print(f"every mood and state, the board's marked: http://127.0.0.1:{args.port}/characters/studio/#view=matrix&board=/board")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        server.server_close()
        unwire(ours)
    return 0


if __name__ == "__main__":
    sys.exit(main())
