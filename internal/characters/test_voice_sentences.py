"""Boop's recorded voice (characters/CHARACTER.md §8): voicegen files a
sentence's recordings in the voice and its table with no other change, a
word's in every face, and record.py builds its requests and picks its takes
as the plan says. On a small fake bank and a stub, never the API."""
import io
import json
import os
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "characters" / "boop" / "tools" / "voicegen"))
import record  # noqa: E402
import voicegen  # noqa: E402

PLAN = {
    "voiceId": "voice-x", "modelId": "model-y",
    "deliveries": {
        "B": {"name": "bright", "mood": "happy", "tag": "[cheerfully]", "faces": ["happy", "proud"], "direction": "Bright."},
        "F": {"name": "flat", "mood": "calm", "tag": "[calmly]", "faces": ["calm"], "direction": "Flat."},
        "G": {"name": "glum", "mood": "sad", "tag": "[tiredly]", "faces": ["sad", "grumpy"], "direction": "Glum."},
    },
    "sentences": [
        {"id": "win.all-yours", "tier": 1, "when": "win", "spoken": "Done! All yours.", "kind": "phrase", "deliveries": ["B"]},
        {"id": "upset.it-broke", "tier": 1, "when": "a turn failed", "spoken": "Aw. It broke.", "kind": "phrase", "deliveries": ["B", "G"]},
        {"id": "upset.shit", "tier": 2, "when": "swearing", "spoken": "Oh, shit. It broke.", "kind": "swear", "deliveries": ["G"]},
    ],
}


def tone(path: Path, seconds: float = 0.6) -> None:
    """A short 8-bit, 11.025 kHz WAV with a sound in it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    n = int(11025 * seconds)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(11025)
        w.writeframes(bytes(128 + (40 if (i // 20) % 2 else -40) for i in range(n)))


class VoicegenTests(unittest.TestCase):
    def bank(self, root: Path, files: bool = True) -> Path:
        bank = root / "bank"
        (bank / "plans").mkdir(parents=True)
        (bank / "plans" / "sentences.json").write_text(json.dumps(PLAN))
        (bank / "dictionary.json").write_text(json.dumps({"entries": []}))
        recs = []
        for sid, delivery, mood in [("win.all-yours", "B", "happy"), ("upset.it-broke", "G", "sad")]:
            rid = f"sentence.{sid}__{mood}"
            path = f"audio-pcm8/robot-soft/{rid}.wav"
            tone(bank / path)
            recs.append({"id": rid, "entryId": f"sentence.{sid}", "delivery": delivery, "mood": mood,
                         "files": {"robot-soft": {"path": path}} if files else {}})
        (bank / "manifest.json").write_text(json.dumps({"recordings": recs}))
        return bank

    def test_a_recorded_sentence_goes_in_both_files(self):
        """A sentence's recording is a take of part sentence, its meaning
        the sentence's id, its text the spoken words, playing in its
        delivery's faces; and it's in the voice file."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            bank, pack = self.bank(root), root / "pack"
            ver, takes, clips, said = voicegen.build(bank, pack, complete=False)
            rows = [line.split("\t") for line in (pack / voicegen.TABLE).read_text().splitlines() if "\t" in line]
            self.assertEqual(sorted((r[0], r[1], r[2], r[3], r[4], r[5]) for r in rows), [
                ("sentence.upset.it-broke__sad", "Aw. It broke", "sentence", "upset.it-broke", "phrase", "sad grumpy"),
                ("sentence.win.all-yours__happy", "Done! All yours", "sentence", "win.all-yours", "phrase", "happy proud"),
            ])
            blob = (pack / voicegen.PACK).read_bytes()
            self.assertEqual(blob[:8], voicegen.MAGIC)
            self.assertEqual(struct.unpack_from("<I", blob, 24)[0], 2, "two takes in the voice file")
            self.assertIn(ver, (pack / voicegen.TABLE).read_text())

    def test_a_sentence_without_its_texture_stops_the_build(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            with self.assertRaises(SystemExit) as stop:
                voicegen.build(self.bank(root, files=False), root / "pack", complete=False)
            self.assertIn("robot-soft", str(stop.exception))

    def test_a_take_longer_than_the_board_plays_stops_the_build(self):
        """The board loads a take of at most MAX_FRAMES mouth frames and
        says nothing for a longer one, so voicegen refuses it."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            bank = self.bank(root)
            tone(bank / "audio-pcm8/robot-soft/sentence.win.all-yours__happy.wav",
                 seconds=(voicegen.MAX_FRAMES + 20) * voicegen.MOUTH_MS / 1000)
            with self.assertRaises(SystemExit) as stop:
                voicegen.build(bank, root / "pack", complete=False)
            self.assertIn("sentence.win.all-yours__happy", str(stop.exception))

    def test_the_real_plan_is_tiers_one_and_two(self):
        """The bank's plan: 50 sentences, each delivery one of the three,
        every face it plays in one of Boop's, every sentence named by a
        line of signs.md and every such line's sentence in the plan."""
        plan = json.loads((voicegen.BANK / "plans" / "sentences.json").read_text())
        ids = [s["id"] for s in plan["sentences"]]
        self.assertEqual(len(ids), 50)
        self.assertEqual(len(set(ids)), 50)
        self.assertEqual(sorted(plan["deliveries"]), ["B", "F", "G"])
        signs = (voicegen.PACK_DIR / "steering" / "signs.md").read_text()
        named = {part[len("take="):].rstrip("]") for line in signs.splitlines() if line.startswith("- ") for part in line.split() if part.startswith("take=")}
        self.assertEqual(named, set(ids))
        faces = {m["id"] for m in json.loads((voicegen.PACK_DIR / "character.json").read_text())["moods"]}
        self.assertEqual(sorted(d["mood"] for d in plan["deliveries"].values()), ["calm", "happy", "sad"], "the takes' ids end in these")
        covered = set().union(*(d["faces"] for d in plan["deliveries"].values()))
        self.assertTrue(faces <= covered, f"faces no delivery plays in: {faces - covered}")
        for s in plan["sentences"]:
            self.assertLessEqual(len(s["spoken"].encode()), voicegen.TEXT_BYTES - 1, s["id"])


class WordTests(unittest.TestCase):
    """A word a reply or a skit says is recorded flat and in the delivery
    its first meaning leans to; its flat take fills in for the delivery it
    lacks. A sentence plays only as recorded."""

    DELIVERIES = {"B": {"faces": ["happy", "proud"]}, "F": {"faces": ["calm"]}, "G": {"faces": ["sad", "grumpy"]}}

    def test_a_word_is_recorded_flat_and_as_it_leans(self):
        dictionary = {"entries": [
            {"id": "word.talk-yes.yes", "text": "Yes", "category": "word", "intent": "talk.yes", "explicit": False},
            {"id": "nonverbal.frustration.tsk", "text": "Tsk...", "category": "nonverbal", "intent": "frustration", "explicit": False},
            {"id": "word.idle.zzz", "text": "Zzz", "category": "word", "intent": "idle", "explicit": False},
        ]}
        self.assertEqual(voicegen.words(dictionary), [
            {"id": "word.talk-yes.yes", "spoken": "Yes", "deliveries": ["F", "B"]},
            {"id": "nonverbal.frustration.tsk", "spoken": "Tsk...", "deliveries": ["F", "G"]},
        ], "a yes leans bright, a no glum; a word nothing says isn't recorded")

    def test_a_words_flat_take_fills_in_where_a_sentences_does_not(self):
        word, sentence = {"entryId": "word.talk-yes.yes"}, {"entryId": "sentence.win.all-yours"}
        self.assertEqual(voicegen.faces({**word, "delivery": "F"}, self.DELIVERIES, {"F", "B"}), ["calm", "sad", "grumpy"])
        self.assertEqual(voicegen.faces({**word, "delivery": "B"}, self.DELIVERIES, {"F", "B"}), ["happy", "proud"])
        self.assertEqual(voicegen.faces({**sentence, "delivery": "F"}, self.DELIVERIES, {"F", "B"}), ["calm"])

    def test_the_bank_has_every_word_as_planned(self):
        """The real manifest: each word's takes are the deliveries `words`
        gives it, the rest the plan's sentences, 500 in all."""
        bank = voicegen.BANK
        recs = json.loads((bank / "manifest.json").read_text())["recordings"]
        words = {w["id"]: sorted(w["deliveries"]) for w in voicegen.words(json.loads((bank / "dictionary.json").read_text()))}
        recorded = {}
        for r in recs:
            recorded.setdefault(r["entryId"], []).append(r["delivery"])
        self.assertEqual({e: sorted(d) for e, d in recorded.items() if not e.startswith(voicegen.SENTENCE)}, words)
        plan = json.loads((bank / "plans" / "sentences.json").read_text())
        self.assertEqual({e: sorted(d) for e, d in recorded.items() if e.startswith(voicegen.SENTENCE)},
                         {voicegen.SENTENCE + s["id"]: sorted(s["deliveries"]) for s in plan["sentences"]})
        self.assertEqual(len(recs), 500)


class RecordTests(unittest.TestCase):
    def test_the_takes_and_their_requests(self):
        takes = record.takes(PLAN, 1)
        self.assertEqual([t["id"] for t in takes],
                         ["sentence.win.all-yours__happy", "sentence.upset.it-broke__happy", "sentence.upset.it-broke__sad"])
        r = record.request(takes[2], "sk-test", PLAN["voiceId"], PLAN["modelId"])
        self.assertEqual(r.full_url, "https://api.elevenlabs.io/v1/text-to-speech/voice-x?output_format=mp3_44100_128")
        self.assertEqual(r.get_method(), "POST")
        self.assertEqual(r.get_header("Xi-api-key"), "sk-test")
        body = json.loads(r.data)
        self.assertEqual(set(body), {"text", "model_id", "seed"}, "only the script, the model and a seed")
        self.assertEqual(body["text"], "[tiredly] Aw. It broke.")
        self.assertEqual(body["model_id"], "model-y")
        self.assertEqual(body["seed"], 42, "the bank's seed")

    def test_what_a_run_records(self):
        have = {"sentence.win.all-yours__happy"}
        ids = lambda todo: [t["id"] for t in todo]
        self.assertEqual(ids(record.pick(PLAN, 1, have, [], [])), ["sentence.upset.it-broke__happy", "sentence.upset.it-broke__sad"],
                         "what's recorded is skipped: a rerun costs nothing")
        self.assertEqual(len(record.pick(PLAN, 2, have, [], [])), 3, "tier 2 adds its own")
        self.assertEqual(ids(record.pick(PLAN, 1, have, ["upset.it-broke__sad"], [])), ["sentence.upset.it-broke__sad"])
        self.assertEqual(ids(record.pick(PLAN, 1, have, ["win.all-yours"], [])), [], "only, and already recorded")
        self.assertEqual(ids(record.pick(PLAN, 1, have, ["win.all-yours"], ["win.all-yours"])), ["sentence.win.all-yours__happy"],
                         "a retake")

    def test_a_dry_run_prints_and_counts(self):
        out = io.StringIO()
        total = record.dry_run(record.takes(PLAN, 1), out=out)
        self.assertEqual(total, len("[cheerfully] Done! All yours.") + len("[cheerfully] Aw. It broke.") + len("[tiredly] Aw. It broke."))
        self.assertIn("direction: Glum.", out.getvalue())
        self.assertIn(f"3 takes, {total} characters", out.getvalue())

    def test_the_robot_soft_chain(self):
        """provenance.json's chain, as far as it can be checked with no
        original/robot-soft pair in the repo: under its ceilings, no DC
        (the high-pass), the high end cut (the low-pass), the same length."""
        import math
        n = 11025
        x = [0.2 + 0.4 * math.sin(2 * math.pi * 440 * i / n) + 0.2 * math.sin(2 * math.pi * 5000 * i / n) for i in range(n)]
        y = record.robot_soft(x)
        self.assertEqual(len(y), n)
        tail = y[n // 2:]
        rms = math.sqrt(sum(v * v for v in tail) / len(tail))
        self.assertLessEqual(rms, record.RMS_CEILING + 1e-9)
        self.assertLessEqual(max(abs(v) for v in y), record.PEAK_CEILING + 1e-9)
        self.assertLess(abs(sum(tail) / len(tail)), 0.005, "the 150 Hz high-pass takes the offset out")
        def level(hz):
            return abs(sum(v * complex(math.cos(2 * math.pi * hz * i / n), -math.sin(2 * math.pi * hz * i / n)) for i, v in enumerate(tail)))
        self.assertLess(level(5000), level(440) / 4, "the 4.2 kHz low-pass cuts the top")

    def test_the_key(self):
        with tempfile.TemporaryDirectory() as d:
            key = Path(d) / "elevenlabs.key"
            self.assertEqual(record.read_key({"ELEVENLABS_API_KEY": " sk-env\n"}, key), "sk-env", "the environment's first")
            with self.assertRaises(record.KeyError_):
                record.read_key({}, key)
            key.write_text("sk-file\n")
            os.chmod(key, 0o644)
            with self.assertRaises(record.KeyError_) as why:
                record.read_key({}, key)
            self.assertNotIn("sk-file", str(why.exception), "never the key in a message")
            os.chmod(key, 0o600)
            self.assertEqual(record.read_key({}, key), "sk-file")

    def test_a_run_files_each_take_and_a_listening_copy(self):
        """Against a stub: each answer is kept as its master, made 8-bit,
        filed in the manifest (a retake in its old one's place) and copied
        to the listening folder."""
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            bank, archive, listen = root / "bank", root / "archive", root / "listen"
            bank.mkdir()
            (bank / "manifest.json").write_text(json.dumps({"recordings": [{"id": "sentence.upset.it-broke__sad", "old": True}]}))
            sent = []

            class Answer(io.BytesIO):
                def __enter__(self):
                    return self

            def opener(req):
                sent.append(json.loads(req.data)["text"])
                return Answer(b"ID3 mp3 bytes")

            def pcm8(master, target):
                tone(target)
                return {"seconds": 0.6, "samples": [0.3 if (i // 20) % 2 else -0.3 for i in range(6615)]}

            real = record.pcm8
            record.pcm8 = pcm8
            try:
                n = record.record(record.takes(PLAN, 1)[1:], PLAN, "sk-test", archive, bank=bank, opener=opener, listen=listen)
            finally:
                record.pcm8 = real
            self.assertEqual(n, 2)
            self.assertEqual(sent, ["[cheerfully] Aw. It broke.", "[tiredly] Aw. It broke."])
            recs = json.loads((bank / "manifest.json").read_text())["recordings"]
            self.assertEqual([r["id"] for r in recs], ["sentence.upset.it-broke__happy", "sentence.upset.it-broke__sad"])
            self.assertNotIn("old", recs[1])
            self.assertEqual(recs[1]["entryId"], "sentence.upset.it-broke")
            self.assertEqual(recs[1]["delivery"], "G")
            self.assertTrue((archive / "masters" / "sentence.upset.it-broke__sad.mp3").is_file())
            self.assertEqual(sorted(p.name for p in listen.iterdir()), [
                "sentence.upset.it-broke__happy.mp3", "sentence.upset.it-broke__happy.original.wav",
                "sentence.upset.it-broke__happy.robot-soft.wav",
                "sentence.upset.it-broke__sad.mp3", "sentence.upset.it-broke__sad.original.wav",
                "sentence.upset.it-broke__sad.robot-soft.wav"])
            self.assertEqual(sorted(recs[1]["files"]), ["original", "robot-soft"], "voicegen's texture too")
            self.assertEqual(recs[1]["generation"]["seed"], 42)


if __name__ == "__main__":
    unittest.main()
