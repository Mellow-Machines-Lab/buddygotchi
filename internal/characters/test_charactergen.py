"""characters/charactergen.py's rules: a pack's moods (characters/CHARACTER.md §5), the studio's
data (§12), and the board's states where the spec and the packs name them (§9)."""
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
        self.assertEqual(gen.state_problems(gen.local_packs()), [])
        for pack in gen.local_packs():
            self.assertEqual(gen.mood_problems(gen.load(pack), gen.universal_moods()), [], pack.name)

    def test_the_universal_moods_are_the_apps(self):
        """The one list, CharacterPack.universalMoods in the app's source: 42 moods, each once."""
        moods = gen.universal_moods()
        self.assertEqual(len(moods), 42)
        self.assertEqual(len(set(moods)), 42)
        self.assertIn("calm", moods)


class MoodRuleTests(unittest.TestCase):
    """A pack's moods against a small universal list, as the app's loader checks them."""

    UNIVERSAL = ["calm", "sad", "glad"]

    def character(self, moods, **extra):
        return {"default_mood": "calm", "moods": [{"id": m, "meaning": m.title() + "."} for m in moods], **extra}

    def test_exactly_the_universal_moods(self):
        self.assertEqual(gen.mood_problems(self.character(["calm", "glad", "sad"]), self.UNIVERSAL), [])
        self.assertEqual(gen.mood_problems(self.character(["calm", "sad", "giddy"]), self.UNIVERSAL),
                         ["moods aren't the universal ones (missing ['glad'], extra ['giddy'])"])
        self.assertEqual(gen.mood_problems(self.character(["calm", "sad", "glad", "sad"]), self.UNIVERSAL),
                         ["moods names a mood twice"])

    def test_moves_and_defaults_name_moods(self):
        c = self.character(["calm", "sad", "glad"], startup_mood="giddy")
        c["moods"][0]["moves"] = {"ordinary": ["sad"], "dramatic": ["sulky"]}
        self.assertEqual(gen.mood_problems(c, self.UNIVERSAL),
                         ["calm leads to sulky, which isn't a mood", "startup_mood giddy isn't a mood"])


class StateRuleTests(unittest.TestCase):
    """CHARACTER.md §9 and a pack's mac/faces.json list the board's states."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.firmware = self.dir / "types.cpp"
        write(self.firmware, 'constexpr const char* kStateNames[2] = {"idle", "poked"};')
        self.spec = self.dir / "CHARACTER.md"
        write(self.spec, "### Every state a face is asked for\n\n| `idle` | x |\n| `poked` | x |\n\n### What else\n| `other` | x |\n")

    def problems(self, *packs):
        return gen.state_problems(list(packs), self.firmware, self.spec)

    def test_the_spec_lists_every_state(self):
        self.assertEqual(self.problems(), [])
        write(self.firmware, 'constexpr const char* kStateNames[3] = {"idle", "poked", "asleep"};')
        [problem] = self.problems()
        self.assertIn("missing ['asleep']", problem)

    def test_a_packs_faces_have_a_row_for_each_state(self):
        pack = self.dir / "pal"
        write(pack / "mac" / "faces.json", {"moods": ["calm"], "states": ["idle", "poked"], "designs": {"calm": [[], []]}})
        self.assertEqual(self.problems(pack), [])
        write(pack / "mac" / "faces.json", {"moods": ["calm"], "states": ["poked", "idle"], "designs": {"calm": [[]]}})
        self.assertEqual(len(self.problems(pack)), 2)


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

    def test_a_preview_wears_only_the_packs_moods(self):
        """A preview's `wears` table must exist and lend only the pack's moods to the pack's moods."""
        pack = self.pack("art", [{"id": "calm"}, {"id": "sad"}], [{"id": "art", "wears": "wears.json"}])
        self.assertEqual(self.problems(pack), ["art: studio file wears.json doesn't exist"])
        pack = self.pack("art", [{"id": "calm"}, {"id": "sad"}], [{"id": "art", "wears": "wears.json"}],
                         files=[("wears.json", {"borrows": {"sad": "calm"}})])
        self.assertEqual(self.problems(pack), [])
        pack = self.pack("art", [{"id": "calm"}, {"id": "sad"}], [{"id": "art", "wears": "wears.json"}],
                         files=[("wears.json", {"borrows": {"sad": "giddy"}})])
        self.assertEqual(self.problems(pack), ["art: art's preview has sad wear giddy, which isn't a mood of its"])
        pack = self.pack("top", [{"id": "calm"}], [{"id": "own"}, {"id": "own"}])
        self.assertEqual(self.problems(pack), ["top: each of its studio entries needs an id of its own"])

    def test_data_has_paths_from_the_page(self):
        art = self.pack("art", [{"id": "calm", "meaning": "Settled."}, {"id": "sad"}],
                        [{"id": "art", "scripts": ["studio/a.js"], "wears": "w.json"}],
                        files=[("studio/a.js", ""), ("w.json", {"why": "", "borrows": {"sad": "calm"}})])
        plain = self.pack("plain", [{"id": "calm", "family": "settled"}])
        data = gen.studio_data([art, plain], plain, self.studio)
        self.assertEqual(data["chosen"], "plain")
        self.assertEqual(data["packs"]["art"]["studio"],
                         [{"id": "art", "scripts": ["../art/studio/a.js"], "styles": [], "wears": {"sad": "calm"}}])
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
                         ["firmware/include/moods.h", "pack", "packs/solo/character.json", "packs/solo/mac/takes.tsv",
                          "packs/solo/steering/guide.md"])
        self.assertEqual((gen.STAGE / "pack").read_text().strip(), str(pack))

    def test_the_pack_in_use(self):
        """CHARACTER.md §2: the environment's pack, else the one last staged, else the chosen one."""
        import os
        from unittest import mock
        staged, other = self.pack("staged", [{"id": "calm"}]), self.pack("other", [{"id": "calm"}])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        env = {k: v for k, v in os.environ.items() if k not in ("BOOP_CHARACTER", "CHARACTER")}
        with mock.patch.dict(os.environ, env, clear=True):
            (self.dir / ".character").write_text("other")
            root, gen.ROOT = gen.ROOT, self.dir  # .character, the remembered choice
            characters, gen.CHARACTERS = gen.CHARACTERS, self.dir
            self.addCleanup(setattr, gen, "ROOT", root)
            self.addCleanup(setattr, gen, "CHARACTERS", characters)
            self.assertEqual(gen.in_use(), other)  # nothing staged: the chosen one
            gen.stage(staged)
            self.assertEqual(gen.in_use(), staged)  # .character waits for the next stage
            os.environ["CHARACTER"] = "other"
            self.assertEqual(gen.in_use(), other)
            del os.environ["CHARACTER"]
            os.environ["BOOP_CHARACTER"] = str(other)
            self.assertEqual(gen.in_use(), other.resolve())


if __name__ == "__main__":
    unittest.main()
