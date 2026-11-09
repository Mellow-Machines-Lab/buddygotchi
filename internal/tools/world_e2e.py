#!/usr/bin/env python3
"""Two buddies in the world, end to end: two headless Boops, each in a
state folder of its own, join the world, see each other, boop each other,
and leave, so nothing stays.

    internal/tools/world_e2e.py URL     the world at URL: http://localhost:8787
                                        (`npm run dev` in internal/world), or
                                        the live one only when the owner asks

It needs .build/debug/Boop (make -C internal build). Each Boop runs with
--brain scripted, --link none and a temporary folder under /tmp, and its
own HOME, in a time zone where it's midday (at night, gestures wait for
the morning): nothing of the everyday app's is touched.
"""
from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOP = ROOT / ".build" / "debug" / "Boop"


def get(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=15) as r:
        return json.load(r)


RUNNING: list[subprocess.Popen] = []


def wait(what: str, check, seconds: float = 60) -> object:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if any(p.poll() is not None for p in RUNNING):
            raise SystemExit(f"world e2e: FAIL, a Boop quit while waiting for: {what}")
        got = check()
        if got:
            return got
        time.sleep(0.5)
    raise SystemExit(f"world e2e: FAIL, {what}")


class Buddy:
    def __init__(self, name: str, url: str) -> None:
        self.name = name
        self.dir = Path(tempfile.mkdtemp(prefix=f"w{name[:3].lower()}", dir="/tmp"))
        self.home = Path(tempfile.mkdtemp(prefix="home", dir="/tmp"))
        self.sock = self.dir / "boop.sock"
        # A time zone where it's midday now: at night, gestures wait for the morning.
        hour = time.gmtime().tm_hour
        shift = (12 - hour + 12) % 24 - 12
        zone = "Etc/GMT" + ("+" if shift <= 0 else "-") + str(abs(shift)) if shift else "UTC"
        env = {**os.environ, "HOME": str(self.home), "BOOP_WORLD_URL": url, "CHARACTER": "boop", "TZ": zone}
        env.pop("BOOP_JEV_KEY", None)
        # Set up, then told of the world as onboarding would.
        self.proc = subprocess.Popen([str(BOOP), "--headless", "--state-dir", str(self.dir), "--name", name, "--link", "none",
                                      "--brain", "scripted", "--no-open", "--debug"],
                                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        RUNNING.append(self.proc)
        wait(f"{name}'s socket", self.sock.exists, 30)

    def send(self, line: dict) -> None:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            s.connect(str(self.sock))
            s.sendall((json.dumps(line) + "\n").encode())

    def dev(self, line: dict) -> None:
        self.send({"dev": "world", **line})

    def identity(self) -> dict | None:
        f = self.dir / "world.json"
        return json.loads(f.read_text()) if f.exists() else None

    def world_events(self) -> list[dict]:
        out = []
        for f in sorted((self.dir / "transcript").glob("*.jsonl")):
            for line in f.read_text().splitlines():
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if e.get("kind") == "world":
                    out.append(e)
        return out

    def log(self) -> str:
        f = self.dir / "boop.log"
        return f.read_text() if f.exists() else ""

    def stop(self) -> None:
        RUNNING.remove(self.proc)
        self.proc.terminate()
        try:
            self.proc.wait(10)
        except subprocess.TimeoutExpired:
            self.proc.kill()

    def clean(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)
        shutil.rmtree(self.home, ignore_errors=True)


def main(argv: list[str]) -> int:
    if len(argv) != 1 or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 2
    url = argv[0].rstrip("/")
    if not BOOP.exists():
        print("world e2e: build first (make -C internal build)")
        return 2
    print(f"world e2e: {url}, {get(url + '/v1/health')}")
    a, b = Buddy("Mochi", url), Buddy("Bean", url)
    try:
        for x in (a, b):
            x.dev({"shown": True})
        ida = wait("Mochi joins", a.identity)["id"]
        idb = wait("Bean joins", b.identity)["id"]
        print(f"world e2e: joined, Mochi {ida[:8]}…, Bean {idb[:8]}…")

        def both_seen():
            ids = {x["id"] for x in get(url + "/v1/world")["buddies"]}
            return ida in ids and idb in ids
        wait("both in the world's snapshot", both_seen, 90)
        print("world e2e: each sees the other in the world")
        a.dev({"tab": True})
        a.dev({"to": idb, "gesture": "boop"})
        b.dev({"to": ida, "gesture": "wave"})
        wait("Mochi's boop went", lambda: "the boop went" in a.log(), 30)
        wait("Bean's wave went", lambda: "the wave went" in b.log(), 30)
        # Each asks for what's waiting on its next send or check: an unlock asks at once.
        for x in (a, b):
            x.send({"dev": "presence", "signal": "unlocked"})
        got_b = wait("Bean gets the boop", lambda: [e for e in b.world_events() if e["data"]["specific_type"] == "boop"], 90)
        got_a = wait("Mochi gets the wave", lambda: [e for e in a.world_events() if e["data"]["specific_type"] == "wave"], 90)
        print(f"world e2e: Bean got {got_b[0]['data']}, Mochi got {got_a[0]['data']}")
        for x in (a, b):
            x.dev({"on": False})
        wait("both left", lambda: not a.identity() and not b.identity(), 30)

        def gone():
            ids = {x["id"] for x in get(url + "/v1/world")["buddies"]}
            return ida not in ids and idb not in ids
        wait("both gone from the world", gone, 90)
        print("world e2e: PASS, both left and nothing stays")
        return 0
    finally:
        for x in (a, b):
            x.stop()
        if os.environ.get("KEEP") != "1":
            for x in (a, b):
                x.clean()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
