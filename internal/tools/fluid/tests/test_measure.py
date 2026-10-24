"""internal/tools/fluid/measure.py: the change measure and its summary,
pinned once in changed.json, which the studio's own copy of them is held
to too; and its table and contact sheets. Needs Pillow (the tools' venv)."""
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

PINNED = json.loads((HERE / "changed.json").read_text())


def strip(pixels):
    image = Image.new("RGB", (len(pixels), 1))
    image.putdata([tuple(p) for p in pixels])
    return image


class MeasureTests(unittest.TestCase):
    def test_the_line_is_24_levels_of_the_differences_luma(self):
        pairs = PINNED["pairs"]
        for a, b, counts in pairs:
            with self.subTest(a=a, b=b):
                self.assertEqual(measure.changed(strip([a]), strip([b])), int(counts))
        self.assertEqual(measure.changed(strip([a for a, _, _ in pairs]), strip([b for _, b, _ in pairs])),
                         sum(c for _, _, c in pairs))

    def test_the_summary_is_the_studios(self):
        """The median (the upper of the middle two), the first largest, and their ratio."""
        for case in PINNED["summaries"]:
            with self.subTest(changes=case["changes"]):
                self.assertEqual(measure.summary(case["changes"]), {k: case[k] for k in ("median", "largest", "at", "ratio")})

    def test_the_table_and_its_sheets(self):
        with tempfile.TemporaryDirectory() as tmp:
            shots, sheets = Path(tmp) / "shots", Path(tmp) / "sheets"
            shots.mkdir()
            # Two frames of rest that barely change, then a nap whose second frame jumps.
            frames = [("000040-rest", 0), ("000080-rest", 1), ("000120-rest", 2), ("000160-nap", 3), ("000200-nap", 60), ("000240-nap", 61)]
            for name, lit in frames:
                strip([[255, 255, 255]] * lit + [[0, 0, 0]] * (100 - lit)).save(shots / f"{name}.png")
            out = subprocess.run([sys.executable, str(HERE.parent / "measure.py"), str(shots), "--sheets", str(sheets)],
                                 check=True, capture_output=True, text=True).stdout.splitlines()
            self.assertEqual([line.split() for line in out[1:]], [["rest", "2", "1", "1", "1.0", "80", "ms"],
                                                                  ["nap", "3", "1", "57", "57.0", "200", "ms"]])
            with Image.open(sheets / "nap.png") as sheet:
                self.assertEqual(sheet.size, (8 * 200, 24 + 2), "8 frames a row, each 200 px wide under its 24 px label of its ms")


if __name__ == "__main__":
    unittest.main()
