"""What boopctl's commands and the dashboard share: the repo, the
animations and moods, the messages to and from the board, the board's voice
takes, a line to the app's hook socket, and noticing a board reset."""
from __future__ import annotations

import json
import os
import socket
import struct
from dataclasses import dataclass
from functools import cache
from pathlib import Path
from typing import Any

from boopctl_lib.device import DeviceError

REPO = Path(__file__).resolve().parents[3]

# The moods the pixel face draws, as `state` carries them, in the device's
# order: the Pixel pack's, as facegen writes them into its mac/faces.json
# (characters/CHARACTER.md §9).
MOODS = json.loads((REPO / "characters" / "pixel" / "mac" / "faces.json").read_text())["moods"]

# The animations a `do` plays by name:
# the brain's finish, the rules' one-shots and a tap's, each its design's
# state.
ANIMS = ["task_complete", "reply_ready", "starting", "stopped", "error", "helper_return", "poked", "tap_spam"]
# Every name Boop's device plays, its `hello.does`:
# the animations, the brain's reaction with no animation of its own
# (`react`), and push-to-talk's start and its end with no reply.
DOES = ["react", "task_complete", "reply_ready", "starting", "stopped", "error", "helper_return", "listening",
        "stop_listening", "poked", "tap_spam"]
# The `do` names that play no animation: a face and a line, and ending
# push-to-talk.
NO_ANIM = {"react", "stop_listening"}
# The older names of two animations, which older logs have and `boopctl
# play` still takes; the device doesn't know them: `cheer` is
# task_complete's success, `wiggle` is poked.
OLD_ANIMS = {"cheer": "task_complete", "wiggle": "poked"}
# The one-shots the rules send, never the brain.
RULE_ONE_SHOTS = {"starting", "stopped", "error", "helper_return"}
# The animations that play a turn's finish: the brain's
# task_complete and reply_ready, and their older names in older logs (the
# cheer).
FINISHES = {"task_complete", "reply_ready"}
FINISHES |= {old for old, anim in OLD_ANIMS.items() if anim in FINISHES}
# The facts that pick an animation's variations.
OUTCOMES = ["success", "failure"]
CTXS = ["new_task", "session", "continuation"]
# How long the Mac lets a `next` wait for its turn (the kit's default,
# linkkit/SPEC.md §3).
TTL_MS = 5000


def do(name: str, play: str = "now", id: int | None = None, ttl: int | None = None, **args: Any) -> dict[str, Any]:
    """A request to play `name` (linkkit/SPEC.md §3 `do`), with Boop's
    fields (`say`, `mood`, `loops`, `variant`, `outcome`, `ctx`) in `args`.
    The tools play `now` by default, so each replaces the last at once, as
    every moment did before the device took turns; a request with no `id`
    plays but gets no `ended`, and only the ones a tool waits on have one."""
    msg: dict[str, Any] = {"t": "do"}
    if id is not None:
        msg["id"] = id
    msg.update(name=name, play=play)
    if ttl is not None:
        msg["ttl"] = ttl
    if args:
        msg["args"] = args
    return msg


def call(msg: dict[str, Any]) -> dict[str, Any] | None:
    """What a message to the device asks it to play, in one shape for the
    tools that read the lines the Mac sent: its `name`, its `anim` (None for
    a face or a line alone), `id`, `play`, and Boop's fields (`say`, `mood`,
    `loops`, `variant`, `outcome`, `ctx`, `who`) as they are. A `do`, or in
    logs from before the device took turns a `moment`, which played at
    once; None for anything else."""
    if msg.get("t") == "do":
        args = msg.get("args") if isinstance(msg.get("args"), dict) else {}
        name = msg.get("name")
        return {**args, "name": name, "anim": None if name in NO_ANIM else name, "id": msg.get("id"),
                "play": msg.get("play") or "next"}
    if msg.get("t") == "moment":
        fields = {k: v for k, v in msg.items() if k != "t"}
        anim = msg.get("anim")
        name = anim or ("react" if msg.get("say") is not None or msg.get("mood") else "stop_listening")
        return {**fields, "name": name, "anim": anim, "id": msg.get("id"), "play": "now"}
    return None


def ended(msg: dict[str, Any]) -> dict[str, Any] | None:
    """The device's word that a `do` is over (linkkit/SPEC.md §3–4): an
    `ev` of kind `ended`, as its data, `{"id", "how", "why"}`; None for any
    other message."""
    if msg.get("t") == "ev" and msg.get("kind") == "ended" and isinstance(msg.get("data"), dict):
        return msg["data"]
    return None


def chosen_pack() -> Path:
    """The character pack in use, as the Swift tests and the simulator
    take it: `BOOP_CHARACTER`'s, else the one last staged
    (.character-build/pack, characters/CHARACTER.md §2), else Pixel."""
    if os.environ.get("BOOP_CHARACTER"):
        return Path(os.environ["BOOP_CHARACTER"])
    staged = REPO / ".character-build" / "pack"
    return Path(staged.read_text().strip()) if staged.exists() else REPO / "characters" / "pixel"


# The chosen pack's voice, the file a board's card has as boop/voice.bin
# (characters/CHARACTER.md §8).
PACK = chosen_pack() / "voice" / "voice.bin"


@dataclass(frozen=True)
class Take:
    """One of the board's recorded takes: its id (a `say`'s `take`), the
    bubble's text, and how long it plays, in ms rounded down."""
    id: str
    text: str
    ms: int


@cache
def takes() -> tuple[Take, ...]:
    """The takes in the voice pack the board plays from its card
    (the chosen character pack's voice/voice.bin), by id."""
    if not PACK.exists():
        raise DeviceError(f"no voice pack at {PACK}: the chosen character pack has no voice")
    data = PACK.read_bytes()
    magic, _, count, size, index, rate, _ = struct.unpack_from("<8s16sIIIII", data)
    if magic != b"BOOPVOX1":
        raise DeviceError(f"{PACK} isn't a voice pack")
    out = []
    for i in range(count):
        rec = data[index + i * size:index + (i + 1) * size]
        key, text = (rec[a:b].split(b"\0")[0].decode() for a, b in ((0, 72), (72, 108)))
        out.append(Take(key, text, struct.unpack_from("<I", rec, 112)[0] * 1000 // rate))
    return tuple(out)


@cache
def _takes_by_id() -> dict[str, Take]:
    return {t.id: t for t in takes()}


def take(key: str) -> Take | None:
    """A take by its id."""
    return _takes_by_id().get(key)


def send_line(path: str, line: dict[str, Any]) -> str | None:
    """Writes one JSON line to the app's hook socket, which never replies;
    returns the problem, if it can't."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(1)
            s.connect(path)
            s.sendall(json.dumps(line, separators=(",", ":")).encode() + b"\n")
    except OSError as exc:
        return f"can't reach Boop's socket {path}: {exc.strerror or exc}"
    return None


def restarted(ups: list[int]) -> bool:
    """Whether the board reset between samples of its uptime: one didn't rise."""
    return any(b <= a for a, b in zip(ups, ups[1:]))
