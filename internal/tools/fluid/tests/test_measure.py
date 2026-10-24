"""internal/tools/fluid/measure.py: the change measure, on pixels either
side of its line (changed.json, which the studio's own copy of it is held
to too); each transition's start and end from the scenario that recorded
it; and --json, the jumpiest first. Needs Pillow (the tools' venv)."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import measure  # noqa: E402


def strip(pixels):
    image = Image.new("RGB", (len(pixels), 1))
    image.putdata([tuple(p) for p in pixels])
    return image


class MeasureTests(unittest.TestCase):
    def test_the_line_is_24_levels_of_the_differences_luma(self):
        pairs = json.loads((HERE / "changed.json").read_text())["pairs"]
        for a, b, counts in pairs:
            with self.subTest(a=a, b=b):
                self.assertEqual(measure.changed(strip([a]), strip([b])), int(counts))
        self.assertEqual(measure.changed(strip([a for a, _, _ in pairs]), strip([b for _, b, _ in pairs])),
                         sum(c for _, _, c in pairs))

    def test_each_transitions_start_and_end(self):
        """The everyday transitions' cells: a state's look, a do's reaction in its mood, a tap's poke and a stroke, from the look before."""
        cells = measure.cells(HERE.parent / "transitions.jsonl")
        self.assertEqual(cells["idle"], {"from": None, "to": {"mood": "calm", "state": "idle"}})
        self.assertEqual(cells["to-working"], {"from": {"mood": "calm", "state": "idle"}, "to": {"mood": "calm", "state": "working"}},
                         "an act the board doesn't draw is plain working")
        self.assertEqual(cells["finish"]["to"], {"mood": "excited", "state": "task_complete"})
        self.assertEqual(cells["to-idle"]["from"], {"mood": "happy", "state": "working"}, "the look before, not the reaction over it")
        self.assertEqual(cells["poke"]["to"], {"mood": "happy", "state": "poked"})
        self.assertEqual(cells["stroke"], {"from": {"mood": "happy", "state": "idle"}, "to": {"mood": "happy", "state": "gesture"}})

    def test_json_the_jumpiest_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots, scenario = Path(tmp) / "shots", Path(tmp) / "s.jsonl"
            shots.mkdir()
            scenario.write_text('{"t": "state", "base": "idle", "mood": "calm"}\n{"shot": "000040-rest"}\n'
                                '{"t": "state", "base": "asleep", "mood": "calm"}\n{"shot": "000080-nap"}\n')
            # Two frames of rest that barely change, then a nap whose second frame jumps.
            frames = [("000040-rest", 0), ("000080-rest", 1), ("000120-rest", 2), ("000160-nap", 3), ("000200-nap", 60), ("000240-nap", 61)]
            for name, lit in frames:
                strip([[255, 255, 255]] * lit + [[0, 0, 0]] * (100 - lit)).save(shots / f"{name}.png")
            out = Path(tmp) / "fluid-gel.json"
            subprocess.run([sys.executable, str(HERE.parent / "measure.py"), str(shots), "--scenario", str(scenario), "--json", str(out)],
                           check=True, capture_output=True)
            measured = json.loads(out.read_text())
        self.assertEqual(measured["recording"], str(shots))
        self.assertEqual([(t["name"], t["frames"], t["median"], t["largest"], t["ratio"], t["at"]) for t in measured["transitions"]],
                         [("nap", 3, 1, 57, 57.0, 40), ("rest", 2, 1, 1, 1.0, 0)])
        self.assertEqual(measured["transitions"][0]["from"], {"mood": "calm", "state": "idle"})
        self.assertEqual(measured["transitions"][0]["to"], {"mood": "calm", "state": "asleep"})


if __name__ == "__main__":
    unittest.main()
