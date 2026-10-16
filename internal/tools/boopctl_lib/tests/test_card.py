"""`boopctl card`: the voice file copied onto the card over `dbg.card`,
against the simulator's card folder."""
from __future__ import annotations

import binascii
import os
import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import card, cli  # noqa: E402
from boopctl_lib.device import Sim  # noqa: E402


def tiny_pack(version: str, samples: bytes = bytes(range(256)) * 20) -> bytes:
    """A pack of one take, "Hi", in voicegen's layout."""
    header = struct.pack("<8s16sIIIII20x", b"BOOPVOX1", version.encode(), 1, 128, 64, 11025, 20)
    mouth = bytes([0, 1, 1, 0])
    at = 64 + 128
    record = struct.pack("<72s36sIIII4x", b"test.hi", b"Hi", at + len(mouth), len(samples), at, len(mouth))
    return header + record + mouth + samples


class Lossy(Sim):
    """The simulator, but every `drop`-th `put` never arrives, as when the
    CH340 loses a run of bytes."""
    drop = 0
    puts = 0

    def send(self, message):  # type: ignore[override]
        if isinstance(message, dict) and message.get("op") == "put":
            self.puts += 1
            if self.drop and self.puts % self.drop == 0:
                return
        super().send(message)


class CardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cli.build_sim()

    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        os.environ["BOOP_SIM_CARD"] = self.dir.name
        self.addCleanup(os.environ.pop, "BOOP_SIM_CARD")
        self.addCleanup(self.dir.cleanup)

    def sim(self, cls=Sim):
        return cls(str(cli.SIM_PROGRAM))

    def test_a_pack_is_copied_checked_and_played(self):
        data = tiny_pack("aaaaaaaaaaaa")
        with self.sim() as sim:
            self.assertEqual(sim.request({"t": "dbg.ping"})["card"], "no pack")
            r = card.push(sim, data)
            self.assertEqual(r["voice"], "aaaaaaaaaaaa")
            ping = sim.request({"t": "dbg.ping"})
            self.assertEqual((ping["voice"], ping["card"]), ("aaaaaaaaaaaa", "ok"))
            sim.send({"t": "state", "base": "idle"})  # the board starts in no app, which plays nothing
            sim.send({"t": "do", "name": "react", "play": "now", "args": {"say": {"take": "test.hi"}}})
            self.assertEqual(sim.request({"t": "dbg.state"})["audio"]["take"], "test.hi")
        self.assertEqual((Path(self.dir.name) / "boop" / "voice.bin").read_bytes(), data)
        # The next launch plays it from the card.
        with self.sim() as sim:
            self.assertEqual(sim.request({"t": "dbg.ping"})["voice"], "aaaaaaaaaaaa")

    def test_lost_lines_and_a_cut_off_copy_carry_on(self):
        data = tiny_pack("bbbbbbbbbbbb", bytes(range(256)) * 60)
        with self.sim(Lossy) as sim:
            sim.drop = 7
            r = card.push(sim, data)
            self.assertGreater(r["resyncs"], 0)
            self.assertEqual(r["voice"], "bbbbbbbbbbbb")
        # Half a copy of another pack, then this one: it goes on, and a
        # file that isn't this pack's start is caught at the end and redone.
        other = tiny_pack("cccccccccccc", bytes(reversed(range(256))) * 60)
        with self.sim() as sim:
            card.begin(sim, keep=False)
            for at in range(0, len(other) // 2, card.CHUNK):
                sim.request(card.put_line(at, other[at:at + card.CHUNK]))
            self.assertEqual(card.push(sim, data)["voice"], "bbbbbbbbbbbb")

    def test_a_bad_chunk_is_refused(self):
        with self.sim() as sim:
            card.begin(sim, keep=False)
            bad = card.put_line(0, b"hello") | {"c": 1}
            r = sim.request(bad)
            self.assertEqual((r["ok"], r["why"], r["have"]), (False, "wrong crc", 0))
            r = sim.request(card.put_line(5, b"hello"))
            self.assertEqual((r["ok"], r["why"]), (False, "not where the card is"))
            r = sim.request({"t": "dbg.card", "op": "end", "size": 5, "crc": binascii.crc32(b"hello")})
            self.assertEqual((r["ok"], r["why"]), (False, "wrong size"))


if __name__ == "__main__":
    unittest.main()
