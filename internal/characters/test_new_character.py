"""internal/tools/new_character.py: the copy takes its id and name."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import new_character  # noqa: E402


class NewCharacterTests(unittest.TestCase):
    def test_the_copy_takes_its_id_and_name(self):
        with tempfile.TemporaryDirectory() as d:
            old, new = Path(d) / "old", Path(d) / "new" / "character"
            (old / "steering").mkdir(parents=True)
            (old / "demo" / "recordings").mkdir(parents=True)
            (old / "evals").mkdir()
            (old / "character.json").write_text(json.dumps({"id": "pixel", "name": "Pixel", "version": "2.0.0"}))
            (old / "steering" / "guide.md").write_text("You are the mind of Pixel, not a Pixels.\n")
            (old / "demo" / "recordings" / "a.json").write_text("{}")
            new_character.copy(old, new, "fern", "Fern")
            pack = json.loads((new / "character.json").read_text())
            self.assertEqual((pack["id"], pack["name"], pack["version"]), ("fern", "Fern", "0.1.0"))
            self.assertEqual((new / "steering" / "guide.md").read_text(), "You are the mind of Fern, not a Pixels.\n")
            self.assertFalse((new / "demo" / "recordings").exists(), "the old pack's recordings stay behind")


if __name__ == "__main__":
    unittest.main()
