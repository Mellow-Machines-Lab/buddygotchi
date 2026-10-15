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
        # These packs' moods are the universal ones.
        from unittest import mock
        patch = mock.patch.object(gen, "universal_moods", lambda: ["calm"])
        patch.start()
        self.addCleanup(patch.stop)

    def pack(self, name, moods, studio=None, files=(), **extra):
        character = {"id": name, "name": name.title(), "version": "0.1.0", "default_mood": moods[0]["id"], "moods": moods,
                     "faces": {"cyd24": "face"}, **extra}
        if studio is not None:
            character["studio"] = studio
        write(self.dir / name / "character.json", character)
        if "faces" not in extra:
            write(self.dir / name / "firmware/src/render/face/face.cpp", "")
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
        """The firmware's files are the pack's alone, with moods.h made from character.json, and the app's copy leaves out what it doesn't read: the voice file and the pack's sources."""
        pack = self.pack("solo", [{"id": "calm", "meaning": "Settled."}],
                         files=[("firmware/include/face.h", ""), ("mac/takes.tsv", ""), ("voice/voice.bin", ""),
                                ("steering/guide.md", ""), ("design/art.txt", "")])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        staged = sorted(p.relative_to(gen.STAGE).as_posix() for p in gen.STAGE.rglob("*") if p.is_file())
        self.assertEqual([n for n in staged if not n.startswith(("firmware-test/", "staged/"))],
                         ["firmware/include/face.h", "firmware/include/moods.h", "firmware/src/render/face/face.cpp", "pack",
                          "packs/solo/character.json", "packs/solo/mac/takes.tsv", "packs/solo/steering/guide.md"])
        moods = (gen.STAGE / "firmware" / "include" / "moods.h").read_text()
        self.assertIn('kMoodNames[kMoodCount] = {"calm"}', moods)
        self.assertIn('kPackId = "solo"', moods)
        self.assertEqual((gen.STAGE / "pack").read_text().strip(), str(gen.STAGE / "staged" / "solo"))
        self.assertEqual(gen.own_folder(gen.STAGE / "staged" / "solo"), pack.resolve())

    def test_staging_takes_what_a_pack_uses(self):
        """CHARACTER.md §6: a pack that uses another's share is staged with the share's files, linked from that pack."""
        self.pack("lender", [{"id": "calm", "meaning": "Settled."}], files=[("voice/voice.bin", "v"), ("mac/takes.tsv", "t"), ("firmware/include/art.h", "a")],
                  shares={"voice": {"files": ["voice/voice.bin", "mac/takes.tsv"]}, "art": {"files": ["firmware/include/art.h"]}})
        pack = self.pack("user", [{"id": "calm", "meaning": "Settled."}], files=[("mac/mirror/index.html", "")],
                         uses={"voice": "lender", "art": "lender"})
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        view = gen.STAGE / "staged" / "user"
        self.assertEqual((view / "voice" / "voice.bin").resolve(), (self.dir / "lender" / "voice" / "voice.bin").resolve())
        self.assertEqual((view / "mac" / "takes.tsv").read_text(), "t")
        self.assertTrue((view / "mac" / "mirror" / "index.html").exists())
        self.assertEqual(sorted(p.name for p in (gen.STAGE / "firmware" / "include").iterdir()), ["art.h", "moods.h"])
        self.assertEqual((gen.STAGE / "packs" / "user" / "mac" / "takes.tsv").read_text(), "t")
        self.assertFalse((gen.STAGE / "packs" / "user" / "voice").exists())

    def test_each_board_has_a_face(self):
        """CHARACTER.md §9: `faces` names a face for some board, each a folder the pack has or uses."""
        self.assertEqual(gen.pack_problems(self.pack("plain", [{"id": "calm", "meaning": "Settled."}]), gen.load(self.dir / "plain")), [])
        self.pack("lender", [{"id": "calm"}], shares={"face": {"files": ["firmware/src/render/face"]}})
        user = self.pack("user", [{"id": "calm", "meaning": "Settled."}], faces={"cyd24": "face", "amoled206": "gel"}, uses={"face": "lender"})
        self.assertEqual(gen.pack_problems(user, gen.load(user)), ["faces gives amoled206 the gel face, and there's no firmware/src/render/gel/"])
        none = self.pack("none", [{"id": "calm", "meaning": "Settled."}], faces={})
        self.assertEqual(gen.pack_problems(none, gen.load(none)), ["faces names no board's face"])

    def test_what_a_pack_uses_must_be_there(self):
        """A share from no pack, one the pack doesn't share, a file it lacks, or one the user has itself fails."""
        self.pack("lender", [{"id": "calm"}], files=[("mac/takes.tsv", "t")],
                  shares={"voice": {"files": ["voice/voice.bin", "mac/takes.tsv"]}})
        pack = self.pack("user", [{"id": "calm"}], files=[("mac/takes.tsv", "")],
                         uses={"voice": "lender", "face": "lender", "art": "nobody"})
        self.assertEqual(gen.used(pack)[1], ["lender's voice names voice/voice.bin, which it doesn't have",
                                             "has mac/takes.tsv of its own, and uses lender's (voice)",
                                             "uses face from lender, which doesn't share it",
                                             "uses art from nobody, which isn't a pack beside it"])

    def test_the_studio_shows_the_previews_a_pack_uses(self):
        """A share's studio entries show on the pack that uses it, with paths into the pack that shares them."""
        self.pack("lender", [{"id": "calm"}], [{"id": "face", "scripts": ["studio/a.js"]}], files=[("studio/a.js", "")],
                  shares={"face": {"files": [], "studio": ["face"]}})
        user = self.pack("user", [{"id": "calm"}], uses={"face": "lender"})
        self.assertEqual(self.problems(user), [])
        data = gen.studio_data([user], user, self.studio)
        self.assertEqual(data["packs"]["user"]["studio"], [{"id": "face", "scripts": ["../lender/studio/a.js"], "styles": [], "wears": {}}])

    def test_the_pack_in_use(self):
        """CHARACTER.md §2: the environment's pack, else the one last staged, else the chosen one."""
        import os
        from unittest import mock
        staged, other = (self.pack(name, [{"id": "calm", "meaning": "Settled."}]) for name in ("staged", "other"))
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
            view = gen.STAGE / "staged" / "staged"
            self.assertEqual(gen.in_use(), view)  # .character waits for the next stage
            os.environ["CHARACTER"] = "other"
            self.assertEqual(gen.in_use(), other)
            os.environ["CHARACTER"] = "staged"
            self.assertEqual(gen.in_use(), view)  # the environment's pack, staged
            del os.environ["CHARACTER"]
            os.environ["BOOP_CHARACTER"] = str(other)
            self.assertEqual(gen.in_use(), other.resolve())
            os.environ["BOOP_CHARACTER"] = str(view)
            self.assertEqual(gen.chosen(), staged.resolve())  # a staged pack's folder chooses its own


if __name__ == "__main__":
    unittest.main()
