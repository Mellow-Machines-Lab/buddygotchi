"""Copying the voice pack onto the board's microSD card over USB (`boopctl
card`): `dbg.card` `begin`, a `put` per chunk with its CRC-32, then `end`
with the whole file's size and CRC-32, which the board checks by reading the
file back before it swaps it in.

It's slow, hours for the whole pack, so a
card reader comes first (copy the file to the card's boop/voice.bin). A few `put`s are in flight
at once. Every reply says how much the card holds, so a line lost on the
way (the CH340 drops a run of bytes now and then) costs a resync, not the
copy; and a copy that was cut off goes on where it stopped."""
from __future__ import annotations

import base64
import binascii
import struct
import time
from collections import deque
from pathlib import Path
from typing import Callable

from boopctl_lib.common import PACK
from boopctl_lib.device import DeviceError, Link

# Bytes per `put`: with base64 and the rest of the message, the line stays
# under the 512 bytes the board reads (the board takes up to kCardChunk in
# firmware/src/app/device.cpp).
CHUNK = 324
# `put`s in flight: about 1.5 KB, under the board's 2 KB serial buffer.
WINDOW = 3
REPLY_S = 3.0


def pack_version(data: bytes) -> str:
    """The version in a pack's header (voicegen's HEADER)."""
    magic, version = struct.unpack_from("<8s16s", data)
    if magic != b"BOOPVOX1":
        raise DeviceError("not a voice pack")
    return version.split(b"\0")[0].decode()


def put_line(at: int, chunk: bytes) -> dict:
    return {"t": "dbg.card", "op": "put", "at": at, "c": binascii.crc32(chunk),
            "d": base64.b64encode(chunk).decode()}


def begin(link: Link, keep: bool, tries: int = 3) -> int:
    """What the card holds. The board answers in order, so the replies to
    `put`s still in flight come first, and are passed over. A lost `begin`
    or reply is asked again, so it costs a resync, not the copy."""
    for i in range(tries):
        link.send({"t": "dbg.card", "op": "begin", "keep": keep})
        try:
            r = link.wait_for(lambda m: m.get("t") == "dbg.card" and m.get("op") == "begin", 10)
            break
        except DeviceError:
            if i == tries - 1:
                raise
    if not r.get("ok"):
        raise DeviceError(f"the card can't take it: {r.get('why')}")
    return int(r["have"])


def push(link: Link, data: bytes, fresh: bool = False,
         progress: Callable[[int, int], None] | None = None) -> dict:
    """Copies `data` onto the card and swaps it in; returns the `end` reply.
    Goes on from what an earlier copy left unless `fresh`."""
    have = begin(link, keep=not fresh)
    if have > len(data):
        have = begin(link, keep=False)
    resyncs = 0
    at, inflight = have, deque()
    while at < len(data) or inflight:
        while len(inflight) < WINDOW and at < len(data):
            chunk = data[at:at + CHUNK]
            link.send(put_line(at, chunk))
            inflight.append(at + len(chunk))
            at += len(chunk)
        try:
            r = link.wait_for(lambda m: m.get("t") == "dbg.card" and m.get("op") == "put", REPLY_S)
        except DeviceError:
            r = {"ok": False}
        if r.get("ok") and int(r["have"]) == inflight[0]:
            inflight.popleft()
            if progress:
                progress(int(r["have"]), len(data))
            continue
        # A lost or refused line: go on from what the card holds.
        resyncs += 1
        at, inflight = begin(link, keep=True), deque()
    r = link.request({"t": "dbg.card", "op": "end", "size": len(data), "crc": binascii.crc32(data)}, timeout=120)
    if not r.get("ok") and r.get("why") == "wrong crc" and not fresh:
        # What an earlier copy left was another pack's: start again.
        return push(link, data, fresh=True, progress=progress)
    if not r.get("ok"):
        raise DeviceError(f"the card didn't take it: {r.get('why')}")
    r["resyncs"] = resyncs
    return r


def copy(link: Link, pack: Path = PACK, force: bool = False, fresh: bool = False,
         say: Callable[[str], None] = print) -> int:
    """`boopctl card`: copies the pack unless the board already has it."""
    if not pack.exists():
        raise DeviceError(f"no voice pack at {pack}: the chosen character pack has no voice")
    data = pack.read_bytes()
    want = pack_version(data)
    ping = link.request({"t": "dbg.ping"})
    if ping.get("voice") == want and not force:
        say(f"the card already has voice {want} ({ping.get('card')})")
        return 0
    say(f"copying voice {want}, {len(data):,} bytes, onto the card (it has {ping.get('voice')}, {ping.get('card')})")
    start = time.monotonic()
    shown: list[int] = []  # the first `have` reported, then the last shown

    def progress(have: int, total: int) -> None:
        if not shown:
            shown[:] = [have, have]
        if have - shown[1] >= 1 << 20 or have == total:
            shown[1] = have
            rate = (have - shown[0]) / max(time.monotonic() - start, 1e-3)
            say(f"  {have * 100 // total:3}%  {have >> 20} of {total >> 20} MB  {rate / 1024:.0f} KB/s"
                f"  about {(total - have) / max(rate, 1) / 60:.0f} min left")

    r = push(link, data, fresh=fresh, progress=progress)
    say(f"done in {(time.monotonic() - start) / 60:.1f} min, {r['resyncs']} resyncs: the board plays voice {r['voice']}")
    return 0 if r["voice"] == want else 1
