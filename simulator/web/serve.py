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
import hashlib
import os
import socket
import struct
import sys
import threading
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
# A write to a client that can't finish within this long drops the client,
# so one that stops reading can't stall the board's lines to the others for
# longer (the host's own rule for a stuck bridge, linkkit/SPEC.md §8).
SEND_TIMEOUT_S = 0.25


class Cable:
    """The board's lines to every client, and the clients' to the board."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.board = None  # the page's WebSocket: a callable that sends one line
        self.clients = set()

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
            clients = list(self.clients)
        for client in clients:
            try:
                client.sendall(line + b"\n")
            except OSError:
                self.drop(client)

    def drop(self, client: socket.socket) -> None:
        with self.lock:
            self.clients.discard(client)
        try:
            client.close()
        except OSError:
            pass

    def serve(self, path: str) -> None:
        if os.path.exists(path):
            os.unlink(path)
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(path)
        os.chmod(path, 0o600)
        server.listen(8)

        def client(conn: socket.socket) -> None:
            conn.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, struct.pack("ll", 0, int(SEND_TIMEOUT_S * 1e6)))
            with self.lock:
                self.clients.add(conn)
            buf = b""
            try:
                while True:
                    data = conn.recv(65536)
                    if not data:
                        break
                    buf += data
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        if line:
                            self.to_board(line)
            except OSError:
                pass
            self.drop(conn)

        def accept() -> None:
            while True:
                conn, _ = server.accept()
                threading.Thread(target=client, args=(conn,), daemon=True).start()

        threading.Thread(target=accept, daemon=True).start()


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
    parser.add_argument("--voice", default=str(REPO / ".build" / "voice" / "voice.bin"), help="the voice pack on the board's card (.build/voice/voice.bin, if it's been built)")
    args = parser.parse_args()
    if not (Path(args.dist) / "boop-sim.wasm").exists():
        print(f"simulator: nothing built in {args.dist}: run simulator/web/build.sh", file=sys.stderr)
        return 1
    cable = Cable()
    cable.serve(args.socket)

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

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Page)
    print(f"Boop Simulator: http://127.0.0.1:{args.port}/   (add ?face=gel for Boop's own face)")
    print(f"its USB, as a bridge's socket: {args.socket}")
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        if os.path.exists(args.socket):
            os.unlink(args.socket)
    return 0


if __name__ == "__main__":
    sys.exit(main())
