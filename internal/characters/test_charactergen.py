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

    def test_the_acts_are_the_boards(self):
        """What the board draws while working for a state's act, as the firmware's actFromName keeps them."""
        self.assertEqual(gen.firmware_acts(), ["planning", "terminal", "tool_use", "searching", "analyzing", "testing", "delegating", "waiting"])
        self.assertLess(set(gen.firmware_acts()), set(gen.firmware_states()))

    def test_the_everyday_transitions_are_cells_of_the_studios(self):
        """The studio's Rank records transitions.jsonl's transitions, each from and to a cell its address has: a
        universal mood, a state of the board's and, for a state with one, a fact it has."""
        table, moods = gen.states(), set(gen.universal_moods())
        transitions = gen.everyday()
        self.assertGreaterEqual(len(transitions), 5)
        for t in transitions:
            for cell in (t["from"], t["to"]):
                mood, state, *fact = cell.split("/")
                self.assertIn(mood, moods, cell)
                self.assertIn(state, gen.state_ids(table), cell)
                options = [o["id"] for o in table["facts"].get(state, {}).get("options", [])]
                self.assertEqual(len(fact), bool(options), cell)
                self.assertTrue(set(fact) <= set(options), cell)

    def test_the_everyday_transitions_are_the_recordings(self):
        """Each run of shots with one name after the first is a transition, named so, from what showed before its
        messages to what they ask for: a look (an act the board draws, else working), a reaction in its own mood, or
        a touch's, which leaves the look to the next."""
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "t.jsonl"
            steps = [{"t": "dbg.reset"}, {"clock": 0}, {"t": "state", "base": "idle", "mood": "calm"}, {"shot": "000040-idle"},
                     {"t": "state", "base": "working", "mood": "calm", "act": "testing"}, {"shot": "000080-to-tests"},
                     {"t": "state", "base": "working", "mood": "calm", "act": "typing"}, {"shot": "000120-typing"},
                     {"t": "do", "name": "task_complete", "args": {"outcome": "failure", "mood": "sad"}},
                     {"shot": "000160-a-finish"}, {"shot": "000200-a-finish"},
                     {"t": "dbg.touch", "x": 60, "y": 120, "ms": 60}, {"shot": "000240-a-poke"},
                     {"t": "dbg.touch", "x": 60, "y": 120, "to_x": 220, "to_y": 120, "ms": 500}, {"shot": "000280-a-stroke"}]
            source.write_text("// A recording.\n" + "\n".join(json.dumps(s) for s in steps) + "\n")
            self.assertEqual(gen.everyday(source), [
                {"name": "to tests", "from": "calm/idle", "to": "calm/testing"},
                {"name": "typing", "from": "calm/testing", "to": "calm/working"},
                {"name": "a finish", "from": "calm/working", "to": "sad/task_complete/failure"},
                {"name": "a poke", "from": "sad/task_complete/failure", "to": "calm/poked"},
                {"name": "a stroke", "from": "sad/task_complete/failure", "to": "calm/gesture"},
            ])

    def test_every_pack_here_is_clean(self):
        self.assertEqual(gen.studio_problems(gen.local_packs()), [])
        self.assertEqual(gen.state_problems(gen.local_packs()), [])
        for pack in gen.local_packs():
            self.assertEqual(gen.mood_problems(gen.load(pack), gen.universal_moods()), [], pack.name)
            self.assertEqual(gen.read_rig(pack)[1], [], pack.name)

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
        self.assertEqual((data["frame_ms"], data["states"]["acts"]), (40, gen.firmware_acts()),
                         "the board's frames 40 ms apart, as a reference's are cut, and the acts it draws while working")
        self.assertEqual(data["packs"]["art"]["studio"][0],
                         {"id": "art", "scripts": ["../art/studio/a.js"], "styles": [], "wears": {"sad": "calm"}})
        board = {"id": "board-face", "label": "Face on the board", "about": "its firmware, in WebAssembly", "icon": "board.svg",
                 "board": "face", "scripts": [], "styles": [], "wears": {}}
        self.assertEqual(data["packs"]["plain"], {"name": "Plain", "default_mood": "calm", "moods": [{"id": "calm", "family": "settled"}],
                                                  "studio": [board], "references": [], "review": {"queue": [], "notes": []}})

    def test_a_board_for_each_face(self):
        """The studio's own preview of each face a pack's boards have, once each, in the order the boards name them."""
        pack = self.pack("two", [{"id": "calm"}], faces={"cyd24": "pixel", "amoled206": "gel", "other": "pixel"})
        self.assertEqual([e["id"] for e in gen.studio_data([pack], pack, self.studio)["packs"]["two"]["studio"]], ["board-pixel", "board-gel"])
        clash = self.pack("clash", [{"id": "calm"}], [{"id": "board-face"}])
        self.assertEqual(self.problems(clash), ["clash: each of its studio entries needs an id of its own"])

    def test_a_pack_adds_to_its_own_board(self):
        """A pack's entry for one of its faces' boards is that board's card, in the entry's place, with what it adds."""
        pack = self.pack("own", [{"id": "calm"}], [{"id": "board-gel", "board": "gel", "scripts": ["studio/a.js"]}],
                         files=[("studio/a.js", "")], faces={"cyd24": "pixel", "amoled206": "gel"})
        self.assertEqual(self.problems(pack), [])
        cards = gen.studio_data([pack], pack, self.studio)["packs"]["own"]["studio"]
        self.assertEqual([e["id"] for e in cards], ["board-gel", "board-pixel"])
        self.assertEqual(cards[0], {"id": "board-gel", "label": "Gel on the board", "about": "its firmware, in WebAssembly",
                                    "icon": "board.svg", "board": "gel", "scripts": ["../own/studio/a.js"], "styles": [], "wears": {}})
        stray = self.pack("stray", [{"id": "calm"}], [{"id": "gel", "board": "gel"}, {"id": "board-lcd", "board": "lcd"}],
                          faces={"amoled206": "gel"})
        self.assertEqual(self.problems(stray), [
            "stray: studio entry gel is for a board, so its id is board-<face> for one of its faces (gel)",
            "stray: studio entry board-lcd is for a board, so its id is board-<face> for one of its faces (gel)"])

    def test_staging_takes_the_packs_own_files_only(self):
        """The firmware's files are the pack's alone, with moods.h made from character.json, and the app's copy leaves out what it doesn't read: the voice file and the pack's sources. What makes the pack isn't staged at all."""
        pack = self.pack("solo", [{"id": "calm", "meaning": "Settled."}],
                         files=[("firmware/include/face.h", ""), ("mac/takes.tsv", ""), ("voice/voice.bin", ""),
                                ("steering/guide.md", ""), ("design/art.txt", ""), ("rig/looks.json", {}),
                                ("references/2026-10-24-art/reference.json", {}), ("review/queue.json", [])])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        staged = sorted(p.relative_to(gen.STAGE).as_posix() for p in gen.STAGE.rglob("*") if p.is_file())
        self.assertEqual([n for n in staged if not n.startswith(("firmware-test/", "staged/"))],
                         ["firmware/include/face.h", "firmware/include/moods.h", "firmware/include/rig_tables.h",
                          "firmware/src/render/face/face.cpp", "pack", "packs/chosen", "packs/solo/character.json",
                          "packs/solo/mac/takes.tsv", "packs/solo/steering/guide.md"])
        self.assertEqual(sorted(n for n in staged if n.startswith("staged/")),
                         ["staged/solo/character.json", "staged/solo/firmware/include/face.h",
                          "staged/solo/firmware/src/render/face/face.cpp", "staged/solo/mac/takes.tsv",
                          "staged/solo/rig/looks.json", "staged/solo/steering/guide.md", "staged/solo/voice/voice.bin"],
                         "what makes the pack, its design/, references/ and review/, isn't staged")
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
        self.assertEqual(sorted(p.name for p in (gen.STAGE / "firmware" / "include").iterdir()), ["art.h", "moods.h", "rig_tables.h"])
        self.assertEqual((gen.STAGE / "packs" / "user" / "mac" / "takes.tsv").read_text(), "t")
        self.assertFalse((gen.STAGE / "packs" / "user" / "voice").exists())

    def test_staging_bundles_every_pack_beside_it_for_buddies(self):
        """CHARACTER.md §2: the app holds every pack beside the chosen one, each with what it uses, for buddies that run another; packs/chosen names the chosen one."""
        self.pack("lender", [{"id": "calm", "meaning": "Settled."}], files=[("mac/takes.tsv", "t"), ("steering/guide.md", "")],
                  shares={"voice": {"files": ["mac/takes.tsv"]}})
        self.pack("other", [{"id": "calm", "meaning": "Settled."}], files=[("steering/guide.md", "")], uses={"voice": "lender"})
        pack = self.pack("chosen-one", [{"id": "calm", "meaning": "Settled."}], files=[("steering/guide.md", "")])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        self.assertEqual((gen.STAGE / "packs" / "chosen").read_text().strip(), "chosen-one")
        self.assertEqual(sorted(p.name for p in (gen.STAGE / "packs").iterdir() if p.is_dir()), ["chosen-one", "lender", "other"])
        self.assertEqual((gen.STAGE / "packs" / "other" / "mac" / "takes.tsv").read_text(), "t", "with what it uses")

    def test_staging_again_changes_only_what_differs(self):
        """A build may be reading the staged files while another stages them: an unchanged file stays the same file
        with its date, a changed one is replaced whole and dated later than the one before, and one the pack no
        longer has goes. Nothing of the staging folder is left behind."""
        pack = self.pack("solo", [{"id": "calm", "meaning": "Settled."}],
                         files=[("firmware/include/art.h", "a"), ("firmware/include/old.h", "o"), ("tests/firmware/test_x/t.cpp", "")])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        include = gen.STAGE / "firmware" / "include"
        before = {p.name: p.stat() for p in include.iterdir()}
        write(pack / "firmware/include/art.h", "changed")
        (pack / "firmware/include/old.h").unlink()
        self.assertEqual(gen.stage(pack), 0)
        after = {p.name: p.stat() for p in include.iterdir()}
        self.assertEqual(sorted(after), ["art.h", "moods.h", "rig_tables.h"])
        for name in ("moods.h", "rig_tables.h"):
            self.assertEqual((after[name].st_ino, after[name].st_mtime_ns), (before[name].st_ino, before[name].st_mtime_ns), name)
        self.assertEqual((include / "art.h").read_text(), "changed")
        self.assertNotEqual(after["art.h"].st_ino, before["art.h"].st_ino)
        self.assertGreaterEqual(after["art.h"].st_mtime_ns, (pack / "firmware/include/art.h").stat().st_mtime_ns)
        self.assertEqual((gen.STAGE / "firmware-test" / "test_x" / "t.cpp").resolve(), (pack / "tests/firmware/test_x/t.cpp").resolve())
        self.assertEqual(sorted(p.name for p in gen.STAGE.iterdir()), ["firmware", "firmware-test", "pack", "packs", "staged"])

    def test_firmware_to_lays_out_one_packs_firmware_and_stages_nothing(self):
        """--firmware-to=DIR, for a second build beside the staged pack's (simulator/web/build.sh PACK): the firmware's files as staging lays them out, what the pack uses included, and nothing staged changes."""
        self.pack("lender", [{"id": "calm"}], files=[("firmware/include/art.h", "a")], shares={"art": {"files": ["firmware/include/art.h"]}})
        pack = self.pack("user", [{"id": "calm", "meaning": "Settled."}], uses={"art": "lender"})
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        out = self.dir / "out"
        self.assertEqual(gen.firmware_to(pack, out), 0)
        self.assertEqual(sorted(p.relative_to(out).as_posix() for p in out.rglob("*") if p.is_file()),
                         ["firmware/include/art.h", "firmware/include/moods.h", "firmware/include/rig_tables.h",
                          "firmware/src/render/face/face.cpp"])
        self.assertIn('kPackId = "user"', (out / "firmware" / "include" / "moods.h").read_text())
        self.assertFalse(gen.STAGE.exists())

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
        self.assertEqual(data["packs"]["user"]["studio"][0], {"id": "face", "scripts": ["../lender/studio/a.js"], "styles": [], "wears": {}})

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


class RigRuleTests(unittest.TestCase):
    """CHARACTER.md §15: a pack's rig/ files, checked and written as rig_tables.h."""

    MOODS, STATES = ["calm", "happy"], ["idle", "working", "asleep", "poked"]

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        # A pixel face that draws two moods, whose eyes and mouths are the styles.
        write(self.dir / gen.PIXEL_FACES, 'constexpr const char* kMoodNames[2] = {"happy", "sad"};\n')

    def rig(self, files):
        for rel, value in files.items():
            write(self.dir / "rig" / rel, value)
        return gen.read_rig(self.dir, self.MOODS, self.STATES)

    def test_a_style_is_a_mood_the_pixel_face_draws(self):
        """Its own pixel face's, or the one it uses (Boop's is Pixel's); a typo fails with its file and key."""
        self.assertEqual(gen.drawn_styles(self.dir), ["happy", "sad"])
        pixel = gen.drawn_styles(ROOT / "characters" / "pixel")
        self.assertEqual(len(pixel), 13)
        self.assertEqual(gen.drawn_styles(ROOT / "characters" / "boop"), pixel)
        _, problems = self.rig({"expressions.json": {"calm": {"eyes": "sad", "mouth": "hapy"}}})
        self.assertEqual(problems, ["rig/expressions.json: calm.mouth: 'hapy' isn't a mood the pixel face draws (happy, sad)"])
        (self.dir / gen.PIXEL_FACES).unlink()
        _, problems = self.rig({})
        self.assertEqual(problems, ["rig/expressions.json: calm.eyes: 'sad' isn't a mood the pixel face draws "
                                    "(the pack has no pixel face)",
                                    "rig/expressions.json: calm.mouth: 'hapy' isn't a mood the pixel face draws "
                                    "(the pack has no pixel face)"])

    def test_a_pack_without_a_rig_has_an_empty_one(self):
        rig, problems = self.rig({})
        self.assertEqual(problems, [])
        self.assertIn("inline constexpr Rig kRig = {{}, {}, {}};", gen.rig_h(self.dir, rig))

    def test_the_tables_are_the_files(self):
        """Each file's rows as rig.h's types hold them: an expression's styles by name, eyeOpen both eyes, a key's
        ease inout unless it says, clips in their files' order."""
        rig, problems = self.rig({
            "expressions.json": {"calm": {"eyes": "sad", "mouth": "happy"}},
            "clips/hop.json": {"ms": 400, "tracks": {"lift": [[0, 0], [100, 10, "out"], [400, 0]]}},
            "clips/sway.json": {"ms": 200, "loop": True, "additive": False,
                                "tracks": {"lean": [[0, 100], [200, 100]], "eyeOpen": [[0, 0], [200, 0]]}},
            "looks.json": {"idle": {"clip": "sway"}, "working": {"clip": None}},
        })
        self.assertEqual(problems, [])
        text = gen.rig_h(self.dir, rig)
        for row in ['{"calm", "sad", "happy"},',
                    "{0, 0, Ease::kInOut},", "{100, 10, Ease::kOut},", "{400, 0, Ease::kInOut},", "{0, 100, Ease::kInOut},",
                    "{Channel::kLift, {kKeys + 0, 3}},", "{Channel::kLean, {kKeys + 3, 2}},",
                    "{Channel::kEyeOpenL, {kKeys + 5, 2}},", "{Channel::kEyeOpenR, {kKeys + 7, 2}},",
                    '{"hop", 400, false, true, {kTracks + 0, 1}},',
                    '{"sway", 200, true, false, {kTracks + 1, 3}},',
                    "{SceneState::kIdle, kClips + 1},", "{SceneState::kWorking, nullptr},",
                    "inline constexpr Rig kRig = {{pack::kExpressions, 1}, {pack::kClips, 2}, {pack::kLooks, 2}};"]:
            self.assertIn(row, text)

    def test_a_bad_edit_fails_with_its_file_and_key(self):
        _, problems = self.rig({
            "expressions.json": {"happy": {"eyes": "Dot", "wiggle": 1}, "calm": {"mouth": "line"}, "giddy": {}},
            "clips/hop.json": {"id": "hop", "ms": 400, "cues": [[300, "pop"]],
                               "tracks": {"nose": [[0, 0]], "squash": [[0, 0], [10, 2500]],
                                          "lift": [[0, 0], [100, 300], [100, 0], [200, 0, "bouncy"]]}},
            "clips/sway.json": {"ms": 200, "loop": True, "tracks": {"lean": [[0, 0], [200, 100]]}},
            "clips/Bad Name.json": {"ms": 0},
            "looks.json": {"idle": {"clip": "hop", "scene": "desk"}, "working": {"clip": "nope"}, "dancing": {}},
        })
        self.assertEqual(problems, [
            "rig/expressions.json: giddy: isn't a mood",
            "rig/expressions.json: happy.eyes: 'Dot' isn't a mood the pixel face draws (happy, sad)",
            "rig/expressions.json: happy.wiggle: unknown key",
            "rig/expressions.json: happy.mouth: missing",
            "rig/expressions.json: calm.mouth: 'line' isn't a mood the pixel face draws (happy, sad)",
            "rig/expressions.json: calm.eyes: missing",
            "rig/clips/Bad Name.json: its name, the clip's id, isn't lower case, digits, - and _",
            "rig/clips/Bad Name.json: ms: 0 isn't a whole number from 1 to 60000",
            "rig/clips/hop.json: id: unknown key",
            "rig/clips/hop.json: cues: unknown key",
            "rig/clips/hop.json: tracks.nose: isn't a channel",
            "rig/clips/hop.json: tracks.squash[1]: its value, 2500, isn't a whole number from -2000 to 2000",
            "rig/clips/hop.json: tracks.lift[2]: its time, 100, isn't a whole ms after the key before's and at most 400",
            "rig/clips/hop.json: tracks.lift[3]: its ease, 'bouncy', isn't one of linear, in, out, inout",
            "rig/clips/sway.json: tracks.lean: loops, so it starts at 0 and ends at ms on the value it started on",
            "rig/looks.json: dancing: isn't a state the board has",
            "rig/looks.json: idle.scene: unknown key",
            "rig/looks.json: idle.clip: hop doesn't loop",
            "rig/looks.json: working.clip: 'nope' isn't a clip in rig/clips/",
        ])

    def test_a_bad_rig_stops_the_pack(self):
        """--check and --stage refuse a pack whose rig/ has a problem, naming it."""
        character = {"id": "x", "version": "1", "default_mood": "calm", "moods": [], "faces": {"cyd24": "face"}}
        write(self.dir / "firmware/src/render/face/face.cpp", "")
        write(self.dir / "rig" / "looks.json", {"idle": {"clip": "nope"}})
        self.assertIn("rig/looks.json: idle.clip: 'nope' isn't a clip in rig/clips/", gen.pack_problems(self.dir, character))


class ReferenceRuleTests(unittest.TestCase):
    """CHARACTER.md §16: a pack's references and review queue, in a temporary repo."""

    STATES = ["idle", "notice"]

    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        self.pack = self.repo / "characters" / "pal"
        write(self.pack / "character.json", {"moods": [{"id": "calm"}, {"id": "happy"}]})
        self.ref = self.pack / "references" / "2026-10-23-perk"
        self.rig = {"expressions": [{"mood": "happy", "eyes": "dot", "mouth": "smile"}], "clips": [{"id": "notice"}]}

    def reference(self, files=("perk.gif",), **ref):
        for name in files:
            write(self.ref / name, "")
        write(self.ref / "reference.json", {"kind": "inspiration", "note": "Like a dog hearing its name.", "status": "new", **ref})
        return gen.reference_problems(self.ref, {"calm", "happy"}, self.STATES, self.rig)

    def read(self, frames=3):
        for i in range(frames):
            write(self.ref / "frames" / "perk.gif" / f"{i:04d}.png", "")
        write(self.ref / "sheets" / "perk.gif.png", "")

    def test_a_new_reference(self):
        self.assertEqual(self.reference(), [])
        self.assertEqual(self.reference(became=[], show={"mood": "happy", "state": "idle", "anim": "notice"}), [])

    def test_unknown_keys_and_values_fail(self):
        self.assertEqual(self.reference(kind="copy", status="done", note=" ", colour="red"), [
            "reference.json: kind: 'copy' isn't one of inspiration, direct",
            "reference.json: note: ' ' is empty",
            "reference.json: status: 'done' isn't one of new, read, translated, in review, approved",
            "reference.json: colour: unknown key"])
        self.assertEqual(self.reference(became=[{"what": "dance", "id": "x"}], show={"mood": "giddy", "state": "nap", "anim": "notice"}, frames=-1), [
            "reference.json: frames: -1 isn't a whole number from 0 up",
            "reference.json: became[0].what: 'dance' isn't one of clip, expression, art",
            "reference.json: show.mood: 'giddy' isn't one of the pack's moods",
            "reference.json: show.state: 'nap' isn't one of the board's states"])
        self.assertEqual(self.reference(show={"state": "idle"}), ["reference.json: show.mood: missing"])

    def test_what_it_became_is_in_the_rig(self):
        """CHARACTER.md §15: a clip by its file's name, an expression by its mood, art by a style an expression wears."""
        became = [{"what": "clip", "id": "notice"}, {"what": "expression", "id": "happy"}, {"what": "art", "id": "dot"},
                  {"what": "art", "id": "smile"}]
        self.assertEqual(self.reference(became=became), [])
        self.assertEqual(self.reference(became=[{"what": "clip", "id": "hop"}, {"what": "expression", "id": "calm"}]),
                         ["it became clip hop, which rig/ hasn't", "it became expression calm, which rig/ hasn't"])

    def test_its_files(self):
        self.assertEqual(self.reference(files=("perk.gif", "notes.txt")),
                         ["it has notes.txt, which isn't media (.png .jpg .jpeg .webp .gif .mp4 .mov .m4v .webm) or the reference's own"])
        shutil.rmtree(self.ref)
        self.assertEqual(self.reference(files=()), ["it has no media"])
        (self.ref / "reference.json").write_text("{")
        self.assertIn("reference.json: isn't JSON", gen.reference_problems(self.ref, set(), [], self.rig)[0])

    def test_what_its_status_says_is_there(self):
        """Read: the tool's frames and sheet for each file, and frames and ms that count them. Translated and on: a reading, and what it became."""
        self.assertEqual(self.reference(status="read"),
                         ["it's read, and perk.gif has no frames or sheet (boopctl reference read)"])
        self.read(3)
        self.assertEqual(self.reference(status="read", frames=2, ms=80),
                         ["it's read, and its frames and ms aren't what frames/ holds (3 frames; boopctl reference read)"])
        self.assertEqual(self.reference(status="read", frames=3, ms=80), [])
        self.assertEqual(self.reference(status="in review", frames=3, ms=80),
                         ["it's in review, and has no reading.md", "it's in review, and became nothing"])
        write(self.ref / "reading.md", "Beats.")
        self.assertEqual(self.reference(status="approved", frames=3, ms=80, became=[{"what": "clip", "id": "notice"}]), [])

    def test_a_badly_named_folder(self):
        write(self.pack / "references" / "perk" / "reference.json", "{}")
        studio = self.repo / "studio"
        write(studio / "states.json", {"groups": [{"label": "All", "states": [{"id": "idle", "about": ""}]}], "facts": {}})
        firmware = self.repo / "types.cpp"
        write(firmware, 'constexpr const char* kStateNames[1] = {"idle"};')
        self.assertEqual(gen.studio_problems([self.pack], studio, firmware), ["pal: references/perk isn't a folder named <YYYY-MM-DD>-<topic>"])

    def test_the_review_queue(self):
        """Items with their keys and a status, before and after images in the characters folder; notes as the server writes them."""
        write(self.pack / "review" / "shot.png", "")
        write(self.repo / "outside.png", "")
        item = {"id": "perk", "title": "Notice", "what": "A perk.", "before": "characters/pal/review/shot.png", "status": "in review"}
        write(self.pack / "review" / "queue.json", [item])
        self.assertEqual(gen.review(self.pack), ([item], [], []))
        write(self.pack / "review" / "queue.json", [{**item, "after": "outside.png", "status": "done", "colour": 1}, {"id": "perk"}])
        self.assertEqual(gen.review(self.pack)[2], [
            "queue.json: perk.status: 'done' isn't one of in review, changes, approved",
            "queue.json: perk.after: 'outside.png' isn't an image in the characters folder",
            "queue.json: perk.colour: unknown key",
            "queue.json: perk.title: missing", "queue.json: perk.what: missing", "queue.json: perk.status: missing",
            "queue.json has two items with one id"])
        note = {"at": "2026-10-23T08:00:00Z", "id": "perk", "verdict": "approve", "text": ""}
        write(self.pack / "review" / "notes.jsonl", json.dumps(note) + '\n{"at": "", "id": "perk", "verdict": "maybe"}\nnot json\n')
        self.assertEqual(gen.review(self.pack)[1], [note])
        self.assertEqual(gen.review(self.pack)[2][-3:], ["notes.jsonl:2: verdict: 'maybe' isn't one of approve, change",
                                                         "notes.jsonl:2: text: missing", "notes.jsonl:3: isn't JSON"])

    def test_the_studio_shows_them(self):
        """packs.js has each reference with its reading and files, and the queue with its images' paths from the page."""
        self.reference(status="read", frames=3, ms=80, show={"mood": "happy", "state": "idle"})
        self.read(3)
        write(self.ref / "reading.md", "Beats.")
        write(self.pack / "review" / "shot.png", "")
        write(self.pack / "review" / "queue.json", [{"id": "perk", "title": "Notice", "what": "A perk.", "after": "characters/pal/review/shot.png", "status": "in review"}])
        studio = self.repo / "characters" / "studio"
        write(studio / "states.json", {"groups": [], "facts": {}})
        write(self.pack / "character.json", {"id": "pal", "name": "Pal", "default_mood": "calm", "moods": [{"id": "calm"}], "faces": {}})
        data = gen.studio_data([self.pack], self.pack, studio)["packs"]["pal"]
        self.assertEqual(data["references"], [{
            "kind": "inspiration", "note": "Like a dog hearing its name.", "status": "read", "frames": 3, "ms": 80,
            "show": {"mood": "happy", "state": "idle"}, "id": "2026-10-23-perk", "path": "../pal/references/2026-10-23-perk/",
            "became": [], "reading": "Beats.", "media": [{"file": "perk.gif", "kind": "gif", "frames": 3}]}])
        self.assertEqual(data["review"]["queue"][0]["after"], "../pal/review/shot.png")

    def test_a_run_reads_each_pack_once(self):
        """One run's Reads reads a pack's rig/ and review/ once, however many steps ask; without one, each call reads afresh."""
        reads = gen.Reads()
        self.assertIs(reads.review(self.pack), reads.review(self.pack))
        self.assertIs(reads.rig(self.pack), reads.rig(self.pack.parent / "pal"))
        write(self.pack / "review" / "queue.json", "{")
        self.assertEqual(reads.review(self.pack)[2], [], "what it read first")
        self.assertEqual(gen.review(self.pack)[2][0][:24], "queue.json: isn't JSON (")


if __name__ == "__main__":
    unittest.main()
