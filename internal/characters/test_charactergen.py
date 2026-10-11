"""The studio's data rules in characters/charactergen.py (characters/CHARACTER.md §12)."""
import importlib.util
import json
import shutil
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("charactergen", ROOT / "characters" / "charactergen.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def write(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value if isinstance(value, str) else json.dumps(value))


class RepoTests(unittest.TestCase):
    def test_states_are_the_boards(self):
        """The studio lists the board's states, each once (the firmware's kStateNames)."""
        ids = gen.state_ids(gen.states())
        self.assertEqual(sorted(ids), sorted(gen.firmware_states()))
        self.assertEqual(len(ids), len(set(ids)))

    def test_every_pack_here_is_clean(self):
        self.assertEqual(gen.studio_problems(gen.local_packs()), [])


class StudioRuleTests(unittest.TestCase):
    """Small packs in a temporary characters/ folder, against two states."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.studio = self.dir / "studio"
        write(self.studio / "states.json", {"groups": [{"label": "All", "states": [{"id": "idle", "about": ""}, {"id": "working", "about": ""}]}], "facts": {}})
        self.firmware = self.dir / "types.cpp"
        write(self.firmware, 'constexpr const char* kStateNames[2] = {"idle", "working"};')

    def pack(self, name, moods, studio=None, files=()):
        character = {"id": name, "name": name.title(), "default_mood": moods[0]["id"], "moods": moods}
        if studio is not None:
            character["studio"] = studio
        write(self.dir / name / "character.json", character)
        for path, value in files:
            write(self.dir / name / path, value)
        return self.dir / name

    def problems(self, *packs):
        return gen.studio_problems(list(packs), self.studio, self.firmware)

    def test_a_pack_without_a_studio_entry_is_fine(self):
        self.assertEqual(self.problems(self.pack("plain", [{"id": "calm"}])), [])

    def test_states_must_match_the_board(self):
        """A state the board has and the studio doesn't fails the check."""
        write(self.firmware, 'constexpr const char* kStateNames[3] = {"idle", "working", "asleep"};')
        [problem] = self.problems()
        self.assertIn("missing ['asleep']", problem)

    def test_declared_files_must_exist(self):
        pack = self.pack("art", [{"id": "calm"}], [{"id": "art", "scripts": ["studio/adapter.js"]}])
        self.assertEqual(self.problems(pack), ["art: studio file studio/adapter.js doesn't exist"])

    def test_every_mood_and_state_needs_a_preview(self):
        """Every pair a pack's coverage leaves out fails, unless the mood's fallback covers it."""
        coverage = {"perPair": {"calm": {"idle": 2, "working": 1}, "sad": {"idle": 1, "working": 0}}}
        pack = self.pack("art", [{"id": "calm"}, {"id": "sad"}], [{"id": "art", "coverage": "cover.json"}], files=[("cover.json", coverage)])
        self.assertEqual(self.problems(pack), ["art: art's preview can't play sad in working"])
        pack = self.pack("art", [{"id": "calm"}, {"id": "sad", "fallback": "calm"}], [{"id": "art", "coverage": "cover.json"}], files=[("cover.json", coverage)])
        self.assertEqual(self.problems(pack), [])

    def test_each_of_a_packs_previews_plays_its_moods_through_fallbacks(self):
        """A pack with several previews names each, and each must play every one of the pack's moods, itself or through its fallback."""
        coverage = {"perPair": {"calm": {"idle": 1, "working": 1}}}
        two = [{"id": "own"}, {"id": "borrowed", "coverage": "cover.json"}]
        pack = self.pack("top", [{"id": "calm"}, {"id": "giddy"}], two, files=[("cover.json", coverage)])
        self.assertEqual(self.problems(pack), ["top: borrowed's preview can't play giddy in idle, working"])
        pack = self.pack("top", [{"id": "calm"}, {"id": "giddy", "fallback": "calm"}], two, files=[("cover.json", coverage)])
        self.assertEqual(self.problems(pack), [])
        pack = self.pack("top", [{"id": "calm"}], [{"id": "own"}, {"id": "own"}])
        self.assertEqual(self.problems(pack), ["top: each of its studio entries needs an id of its own"])

    def test_data_has_paths_from_the_page(self):
        coverage = {"perPair": {"calm": {"idle": 1, "working": 1}}}
        art = self.pack("art", [{"id": "calm", "meaning": "Settled."}], [{"id": "art", "scripts": ["studio/a.js"], "coverage": "c.json"}],
                        files=[("studio/a.js", ""), ("c.json", coverage)])
        plain = self.pack("plain", [{"id": "calm", "family": "settled"}])
        data = gen.studio_data([art, plain], plain, self.studio)
        self.assertEqual(data["chosen"], "plain")
        self.assertEqual(data["packs"]["art"]["studio"],
                         [{"id": "art", "scripts": ["../art/studio/a.js"], "styles": [], "covers": {"calm": ["idle", "working"]}}])
        self.assertEqual(data["packs"]["plain"], {"name": "Plain", "default_mood": "calm", "moods": [{"id": "calm", "family": "settled"}], "studio": []})

    def test_staging_takes_the_packs_own_files_only(self):
        """The firmware's files are the pack's alone, and the app's copy leaves out what it doesn't read: the voice pack and the pack's sources."""
        pack = self.pack("solo", [{"id": "calm"}], files=[("firmware/include/moods.h", ""), ("mac/takes.tsv", ""), ("voice/voice.bin", ""),
                                                           ("steering/guide.md", ""), ("design/art.txt", "")])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        staged = sorted(p.relative_to(gen.STAGE).as_posix() for p in gen.STAGE.rglob("*") if p.is_file())
        self.assertEqual([n for n in staged if not n.startswith("firmware-test/")],
                         ["firmware/include/moods.h", "pack", "packs/chosen", "packs/solo/character.json", "packs/solo/mac/takes.tsv",
                          "packs/solo/steering/guide.md"])
        self.assertEqual((gen.STAGE / "pack").read_text().strip(), str(pack))


if __name__ == "__main__":
    unittest.main()
