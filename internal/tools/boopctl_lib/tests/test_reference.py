"""boopctl reference (characters/CHARACTER.md §16): `new` takes the files
into a pack's references/<date>-<topic>/ with a reference.json; `read`
cuts a GIF and a video a frame every 40 ms (ffmpeg) and a still into one,
with a contact sheet of each, and writes frames and ms. On a GIF Pillow
draws, and an MP4 and a streamed WebM (a browser's recording) ffmpeg
makes, in a temporary pack. Needs ffmpeg."""
import contextlib
import datetime
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import cli, reference  # noqa: E402

try:
    HAS_FFMPEG = bool(reference.tool("ffmpeg"))
except FileNotFoundError:
    HAS_FFMPEG = False


class ReferenceTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.pack = self.dir / "characters" / "pal"
        self.pack.mkdir(parents=True)
        (self.pack / "character.json").write_text(json.dumps({"moods": [{"id": "calm"}]}))
        # A blob that rises over ten frames of 100 ms: 1 s, so 25 frames 40 ms apart.
        self.gif = self.dir / "perk.gif"
        frames = [Image.new("RGB", (64, 48), "white") for _ in range(10)]
        for i, frame in enumerate(frames):
            frame.paste((40, 160, 120), (24, 30 - i * 2, 40, 46 - i * 2))
        frames[0].save(self.gif, save_all=True, append_images=frames[1:], duration=100, loop=0)
        self.still = self.dir / "pose.png"
        Image.new("RGB", (1200, 600), "pink").save(self.still)

    def new(self, *files, topic="perk"):
        return reference.new(self.pack, topic, "inspiration", "Like a dog hearing its name.", list(files),
                             today=datetime.date(2026, 10, 23))

    def test_new_takes_the_files_in(self):
        folder = self.new(self.gif, self.still)
        self.assertEqual(folder, self.pack / "references" / "2026-10-23-perk")
        self.assertEqual(sorted(p.name for p in folder.iterdir()), ["perk.gif", "pose.png", "reference.json"])
        self.assertEqual(json.loads((folder / "reference.json").read_text()),
                         {"kind": "inspiration", "note": "Like a dog hearing its name.", "status": "new", "became": []})
        self.assertEqual(reference.problems(folder), [])

    def test_new_refuses(self):
        self.new(self.gif)
        with self.assertRaisesRegex(FileExistsError, "there already"):
            self.new(self.gif)
        with self.assertRaisesRegex(ValueError, "a topic is"):
            self.new(self.gif, topic="Perk Up")
        (self.dir / "notes.txt").write_text("")
        with self.assertRaisesRegex(ValueError, "isn't a still, a GIF or a video"):
            self.new(self.dir / "notes.txt", topic="notes")
        with self.assertRaisesRegex(FileNotFoundError, "no character pack"):
            reference.new(self.dir / "nobody", "perk", "direct", "x", [self.gif])

    @unittest.skipUnless(HAS_FFMPEG, "needs ffmpeg")
    def test_read_cuts_a_gif_and_a_still(self):
        folder = self.new(self.gif, self.still)
        said = reference.read(folder)
        self.assertEqual(said, ["perk.gif: 25 frames over 1000 ms in frames/perk.gif/, the sheet sheets/perk.gif.png",
                                "pose.png: 1 frame over 0 ms in frames/pose.png/, the sheet sheets/pose.png.png"])
        frames = sorted((folder / "frames" / "perk.gif").iterdir())
        self.assertEqual([f.name for f in frames[:2] + frames[-1:]], ["0000.png", "0001.png", "0024.png"])
        with Image.open(frames[0]) as first, Image.open(frames[-1]) as last:
            self.assertEqual(first.size, (64, 48), "no bigger than it was")
            self.assertNotEqual(first.convert("RGB").getpixel((30, 20)), last.convert("RGB").getpixel((30, 20)), "the blob rose")
        with Image.open(folder / "frames" / "pose.png" / "0000.png") as pose:
            self.assertEqual(pose.size, (512, 256), "a still, no bigger than 512 px a side")
        with Image.open(folder / "sheets" / "perk.gif.png") as sheet:
            self.assertEqual(sheet.size, (8 * 200, 4 * (150 + 24)), "8 frames a row, 4 rows for 25, each under its 24 px label")
        ref = json.loads((folder / "reference.json").read_text())
        self.assertEqual((ref["frames"], ref["ms"], ref["status"]), (26, 1000, "read"))
        self.assertEqual(reference.problems(folder), [])
        # Read again, it cuts afresh, and a later status stays.
        ref["status"] = "in review"
        (folder / "reference.json").write_text(json.dumps(ref))
        reference.read(folder)
        self.assertEqual(json.loads((folder / "reference.json").read_text())["status"], "in review")
        self.assertEqual(len(list((folder / "frames" / "perk.gif").iterdir())), 25)

    @unittest.skipUnless(HAS_FFMPEG, "needs ffmpeg")
    def test_read_cuts_a_video(self):
        video = self.dir / "hop.mp4"
        subprocess.run([reference.tool("ffmpeg"), "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=0.8:size=96x64:rate=50",
                        "-pix_fmt", "yuv420p", str(video)], check=True)
        folder = self.new(video, topic="hop")
        reference.read(folder)
        ref = json.loads((folder / "reference.json").read_text())
        self.assertEqual(ref["ms"], 800)
        self.assertEqual(ref["frames"], 20, "0.8 s, a frame every 40 ms")

    @unittest.skipUnless(HAS_FFMPEG, "needs ffmpeg")
    def test_read_cuts_a_browsers_webm_and_a_failed_cut_keeps_the_frames(self):
        """A browser's MediaRecorder .webm says no length of its own, as one ffmpeg streams out doesn't: its frames
        give its length. A cut that fails leaves the frames there before, and nothing half cut."""
        video = self.dir / "clip.webm"
        with video.open("wb") as out:
            subprocess.run([reference.tool("ffmpeg"), "-v", "error", "-f", "lavfi", "-i", "testsrc=duration=0.8:size=96x64:rate=25",
                            "-c:v", "libvpx", "-f", "webm", "pipe:1"], check=True, stdout=out)
        said = subprocess.run([reference.tool("ffprobe"), "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                               str(video)], check=True, capture_output=True, text=True).stdout.strip()
        self.assertEqual(said, "N/A")
        folder = self.new(video, topic="clip")
        reference.read(folder)
        ref = json.loads((folder / "reference.json").read_text())
        self.assertEqual((ref["frames"], ref["ms"]), (20, 800))
        (folder / "clip.webm").write_bytes(b"not a video")
        with self.assertRaises(subprocess.CalledProcessError):
            reference.read(folder)  # ffmpeg says why on stderr
        self.assertEqual([p.name for p in (folder / "frames").iterdir()], ["clip.webm"])
        self.assertEqual(len(list((folder / "frames" / "clip.webm").glob("*.png"))), 20)

    @unittest.skipUnless(HAS_FFMPEG, "needs ffmpeg")
    def test_the_command_line(self):
        folder = self.new(self.gif)
        with contextlib.redirect_stdout(io.StringIO()) as out, contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(cli.main(["reference", "read", str(folder)]), 0)
        self.assertIn("write " + str(folder.resolve()) + "/reading.md", out.getvalue())
        self.assertEqual(err.getvalue(), "")
        with contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(cli.main(["reference", "read", str(self.dir)]), 2)
        self.assertIn("has no reference.json", err.getvalue())


if __name__ == "__main__":
    unittest.main()
