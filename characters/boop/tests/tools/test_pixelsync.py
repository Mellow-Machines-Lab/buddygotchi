"""Boop's copies of Pixel's face are Pixel's (tools/pixelsync)."""
import importlib.util
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[2] / "tools" / "pixelsync" / "pixelsync.py"
spec = importlib.util.spec_from_file_location("pixelsync", TOOL)
pixelsync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixelsync)


class PixelSyncTests(unittest.TestCase):
    def test_the_copies_are_pixels(self):
        self.assertEqual(pixelsync.stale(), [], "rerun characters/boop/tools/pixelsync/pixelsync.py")

    def test_it_copies_the_face_and_leaves_boops_own(self):
        copies = pixelsync.copies()
        self.assertIn("firmware/include/faces.h", copies)
        self.assertIn("mac/faces.json", copies)
        self.assertEqual(copies["studio/adapter.js"], "studio/pixel/adapter.js")
        for own in ("firmware/include/moods.h", "firmware/src/render/make_face.cpp"):
            self.assertNotIn(own, copies)


if __name__ == "__main__":
    unittest.main()
