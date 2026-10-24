"""boopctl factory: the machine's checks and the person's, on a scripted
board. Needs no board."""
import contextlib
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import factory  # noqa: E402
from boopctl_lib.card import voice_version  # noqa: E402
from boopctl_lib.common import REPO, VOICE_FILE  # noqa: E402
from fake_board import FakeBoard  # noqa: E402
from pack import needs_voice  # noqa: E402


def good_ping() -> dict:
    return {"fw": (REPO / "VERSION").read_text().strip(), "sha": "abc", "reset": "power", "card": "ok",
            "voice": voice_version(VOICE_FILE.read_bytes()), "ble": "adv", "name": "Boop-01DD", "heap_min": 75_000}


@needs_voice
class FactoryTests(unittest.TestCase):
    def run_on(self, ping: dict, auto: bool = True, answers: bool = True) -> tuple[int, list[str], FakeBoard]:
        board = FakeBoard.by_type({"dbg.ping": ping, "dbg.pattern": {}})
        lines: list[str] = []
        with contextlib.redirect_stdout(io.StringIO()):
            code = factory.run(board, auto=auto, ask=lambda _: answers, say=lines.append)
        return code, lines, board

    def test_a_good_board_passes(self):
        code, lines, _ = self.run_on(good_ping())
        self.assertEqual(code, 0)
        self.assertEqual(lines[-1], "factory: pass")
        self.assertEqual(len(lines), 7, "six checks, then the verdict")

    def test_each_machine_check_fails_on_its_own(self):
        # The rule: firmware must be VERSION's, the last restart not
        # trouble, the card read, the voice the pack's, Bluetooth up, and the
        # heap at least HEAP_FLOOR.
        spoilt = {"firmware": {"fw": "0.9.0"}, "restart": {"reset": "watchdog"}, "card": {"card": "no card"},
                  "voice": {"voice": "none"}, "bluetooth": {"ble": "off"}, "memory": {"heap_min": factory.HEAP_FLOOR - 1}}
        for name, change in spoilt.items():
            code, lines, _ = self.run_on({**good_ping(), **change})
            self.assertEqual(code, 1, name)
            self.assertEqual(lines[-1], f"factory: FAIL: {name}")

    def test_the_person_checks_and_the_board_ends_muted(self):
        code, lines, board = self.run_on(good_ping(), auto=False, answers=True)
        self.assertEqual(code, 0)
        self.assertEqual([l.split()[1] for l in lines[6:9]], ["screen", "speaker", "touch"])
        states = [m for m in board.sent if m["t"] == "state"]
        self.assertEqual(states[0]["vol"], 0, "muted first")
        self.assertEqual(states[-1]["vol"], 0, "and last")
        self.assertEqual(max(s["vol"] for s in states), factory.SPEAKER_VOL, "never louder than the speaker check")
        code, lines, _ = self.run_on(good_ping(), auto=False, answers=False)
        self.assertEqual(lines[-1], "factory: FAIL: screen, speaker, touch")


if __name__ == "__main__":
    unittest.main()
