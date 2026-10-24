"""A board's factory test, `boopctl factory`: pass or fail, a line a check.

What a machine can check, from the board's dbg.ping: it runs the
firmware VERSION says, it didn't last restart after trouble, its card
reads, the voice on the card is the chosen pack's, Bluetooth advertises,
and its heap is above the floor. Then, unless --auto, a person checks what
only a person can: the bring-up pattern on the screen, a take from the
speaker, and a tap and BOOT poking back. Muted until the speaker check,
which plays one take at a low volume.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from boopctl_lib.card import voice_version
from boopctl_lib.common import REPO, VOICE_FILE, do, takes

# Restarts that mean something went wrong (the Mac's
# DeviceInfo.troubledResets says the same).
TROUBLED_RESETS = {"panic", "watchdog", "brownout", "other"}
# The least free heap a board may have, napping, in bytes: the CYD runs
# with about 50 KB and the AMOLED about 75 KB, and under 20 KB a board
# starts failing to draw or connect.
HEAP_FLOOR = 20_000
# The speaker check's volume, of 10: heard on a bench, not across a room.
SPEAKER_VOL = 3
MUTED = {"t": "state", "base": "idle", "busy": 0, "vol": 0}


@dataclass
class Check:
    name: str
    ok: bool
    why: str


def machine_checks(ping: dict, version: str, voice: str) -> list[Check]:
    """The checks a machine makes, from one dbg.ping."""
    reset = ping.get("reset")
    return [
        Check("firmware", ping.get("fw") == version, f"runs {ping.get('fw')} ({ping.get('sha')}), VERSION says {version}"),
        Check("restart", reset not in TROUBLED_RESETS, f"last restarted after {reset or 'an unknown reason'}"),
        Check("card", ping.get("card") == "ok", f"card {ping.get('card')}"),
        Check("voice", ping.get("voice") == voice, f"voice {ping.get('voice')}, the pack's {voice}"),
        Check("bluetooth", ping.get("ble") in ("adv", "conn"), f"Bluetooth {ping.get('ble')}, as {ping.get('name')}"),
        Check("memory", (ping.get("heap_min") or 0) >= HEAP_FLOOR, f"heap at least {ping.get('heap_min')} bytes free"),
    ]


def person_checks(dev, ask: Callable[[str], bool]) -> list[Check]:
    """What only a person can see, hear and feel, each shown, then asked."""
    found = []
    dev.request({"t": "dbg.pattern"})
    found.append(Check("screen", ask("Six colour blocks, labelled corners and an UP arrow at the top?"), "the pattern"))
    dev.send(MUTED)
    first = takes()[0]
    dev.send({**MUTED, "vol": SPEAKER_VOL})
    dev.send(do("react", say={"take": first.id}))
    found.append(Check("speaker", ask(f"Did Boop say {first.text!r}?"), f"take {first.id} at volume {SPEAKER_VOL}"))
    dev.send(MUTED)
    found.append(Check("touch", ask("Tap the screen, then press BOOT: did the face poke back both times?"), "a tap and BOOT"))
    return found


def run(dev, auto: bool, ask: Callable[[str], bool], say: Callable[[str], None] = print) -> int:
    dev.send(MUTED)
    version = (REPO / "VERSION").read_text().strip()
    checks = machine_checks(dev.request({"t": "dbg.ping"}), version, voice_version(VOICE_FILE.read_bytes()))
    if not auto:
        checks += person_checks(dev, ask)
    dev.send(MUTED)
    for check in checks:
        say(f"{'pass' if check.ok else 'FAIL'}  {check.name:<9} {check.why}")
    failed = [c.name for c in checks if not c.ok]
    say("factory: " + ("pass" if not failed else "FAIL: " + ", ".join(failed)))
    return 0 if not failed else 1
