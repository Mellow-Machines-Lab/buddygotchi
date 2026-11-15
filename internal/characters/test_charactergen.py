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

    def test_every_pack_here_is_clean(self):
        self.assertEqual(gen.studio_problems(gen.local_packs()), [])
        self.assertEqual(gen.state_problems(), [])
        for pack in gen.local_packs():
            self.assertEqual(gen.pack_problems(pack, gen.load(pack)), [], pack.name)
            self.assertEqual(gen.read_rig(pack)[1], [], pack.name)

    def test_a_pack_builds_only_with_moods_and_a_startup_mood(self):
        """moods.h needs the pack's moods and its startup mood; whether they play is boopdev check's."""
        c = {"id": "x", "version": "1", "default_mood": "calm", "faces": {}, "moods": [{"id": "calm"}]}
        self.assertNotIn("isn't one of its moods", " ".join(gen.pack_problems(Path("/nowhere"), c)))
        c["startup_mood"] = "giddy"
        self.assertIn("its startup_mood, else its default_mood, isn't one of its moods", gen.pack_problems(Path("/nowhere"), c))
        c["moods"] = []
        self.assertIn("moods names no mood, or one without an id", gen.pack_problems(Path("/nowhere"), c))


class StateRuleTests(unittest.TestCase):
    """CHARACTER.md §9 lists the board's states."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.firmware = self.dir / "types.cpp"
        write(self.firmware, 'constexpr const char* kStateNames[2] = {"idle", "poked"};')
        self.spec = self.dir / "CHARACTER.md"
        write(self.spec, "### Every state a face is asked for\n\n| `idle` | x |\n| `poked` | x |\n\n### What else\n| `other` | x |\n")

    def problems(self):
        return gen.state_problems(self.firmware, self.spec)

    def test_the_spec_lists_every_state(self):
        self.assertEqual(self.problems(), [])
        write(self.firmware, 'constexpr const char* kStateNames[3] = {"idle", "poked", "asleep"};')
        [problem] = self.problems()
        self.assertIn("missing ['asleep']", problem)


class StudioRuleTests(unittest.TestCase):
    """Small packs in a temporary characters/ folder, against two states."""

    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        self.studio = self.dir / "studio"
        write(self.studio / "states.json", {"groups": [{"label": "All", "states": [{"id": "idle", "about": ""}, {"id": "working", "about": ""}]}], "facts": {}})
        self.firmware = self.dir / "types.cpp"
        write(self.firmware, 'constexpr const char* kStateNames[2] = {"idle", "working"};')

    def pack(self, name, moods, studio=None, files=(), **extra):
        moods = [{**m, "face": m.get("face", "A face.")} for m in moods]
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
                                                  "studio": [board]},
                         "only what the matrix and the scene draw: the moods' meanings and families, and the previews")

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

    def test_staging_bundles_only_the_chosen_pack(self):
        """CHARACTER.md §2: the app holds the chosen pack alone, which packs/chosen names."""
        self.pack("lender", [{"id": "calm", "meaning": "Settled."}], files=[("steering/guide.md", "")])
        self.pack("other", [{"id": "calm", "meaning": "Settled."}], files=[("mac/takes.tsv", "t"), ("steering/guide.md", "")])
        pack = self.pack("chosen-one", [{"id": "calm", "meaning": "Settled."}], files=[("steering/guide.md", "")])
        stage, gen.STAGE = gen.STAGE, self.dir / "stage"
        self.addCleanup(setattr, gen, "STAGE", stage)
        self.assertEqual(gen.stage(pack), 0)
        self.assertEqual((gen.STAGE / "packs" / "chosen").read_text().strip(), "chosen-one")
        self.assertEqual(sorted(p.name for p in (gen.STAGE / "packs").iterdir() if p.is_dir()), ["chosen-one"])

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
        """--firmware-to=DIR, for a second build beside the staged pack's (simulator/web/build.sh PACK): the firmware's files as staging lays them out, and nothing staged changes."""
        pack = self.pack("user", [{"id": "calm", "meaning": "Settled."}], files=[("firmware/include/art.h", "a")])
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
        """CHARACTER.md §9: `faces` names a face for some board, each a folder the pack has."""
        self.assertEqual(gen.pack_problems(self.pack("plain", [{"id": "calm", "meaning": "Settled."}]), gen.load(self.dir / "plain")), [])
        user = self.pack("user", [{"id": "calm", "meaning": "Settled."}], faces={"cyd24": "face", "amoled206": "gel"},
                         files=[("firmware/src/render/face/face.cpp", "")])
        self.assertEqual(gen.pack_problems(user, gen.load(user)), ["faces gives amoled206 the gel face, and there's no firmware/src/render/gel/"])
        none = self.pack("none", [{"id": "calm", "meaning": "Settled."}], faces={})
        self.assertEqual(gen.pack_problems(none, gen.load(none)), ["faces names no board's face"])

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


class GapTests(unittest.TestCase):
    """What --check prints that a pack lacks and that doesn't stop it. Small packs as StudioRuleTests makes them."""

    setUp, pack = StudioRuleTests.setUp, StudioRuleTests.pack

    def test_a_bare_pack_has_every_gap(self):
        pack = self.pack("bare", [{"id": "calm"}, {"id": "sad"}, {"id": "glum", "settles": "sad"}],
                         [{"id": "art", "wears": "w.json"}], files=[("w.json", {"borrows": {"sad": "calm"}})])
        self.assertEqual(gen.gaps(pack, gen.load(pack)), [
            "Bare has art for 2 of 3 moods; the rest wear another's",
            "2 of 2 lasting moods have no steering file, so they act as calm: calm, sad",
            "no signs (steering/signs.md), so it never holds one up",
            "no dream signs (steering/dreams.md), so it tells its dreams with none"])

    def test_a_whole_pack_has_none(self):
        """A face only (`settles`) needs no steering file; a reply's words don't count as a mood's take."""
        takes = "# a comment\nv1\nhi\tHi\tabout\tstart\tword\tcalm\t\t100\nyo\tYo\treply\tok\tword\tsad\t\t100\n"
        files = [("steering/mood/calm.md", "Calm."), ("steering/mood/sad.md", "Sad."), ("mac/takes.tsv", takes),
                 ("steering/signs.md", "<!-- - not one -->\n- hello\n"), ("steering/dreams.md", "- [night] zzz\n")]
        pack = self.pack("whole", [{"id": "calm"}, {"id": "sad"}, {"id": "glum", "settles": "sad"}], files=files)
        self.assertEqual(gen.gaps(pack, gen.load(pack)), ["2 of 3 moods have no voice takes: sad, glum"])


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
        """Its own pixel face's; a typo fails with its file and key."""
        self.assertEqual(gen.drawn_styles(self.dir), ["happy", "sad"])
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
        ease inout unless it says, a clip's cues in order of time, clips in their files' order."""
        rig, problems = self.rig({
            "expressions.json": {"calm": {"eyes": "sad", "mouth": "happy"}},
            "clips/hop.json": {"ms": 400, "tracks": {"lift": [[0, 0], [100, 10, "out"], [400, 0]]},
                               "cues": [[300, "squish"], [50, "pop"]]},
            "clips/sway.json": {"ms": 200, "loop": True, "additive": False,
                                "tracks": {"lean": [[0, 100], [200, 100]], "eyeOpen": [[0, 0], [200, 0]]}},
            "looks.json": {"idle": {"clip": "sway"},
                           "working": {"clip": None, "occasions": [{"clip": "hop", "when": ["night", "tier4"]},
                                                                   {"clip": "hop", "after": 90}],
                                       "tiers": {"tier2": "sway"}}},
        })
        self.assertEqual(problems, [])
        text = gen.rig_h(self.dir, rig)
        for row in ['{"calm", "sad", "happy"},',
                    "{0, 0, Ease::kInOut},", "{100, 10, Ease::kOut},", "{400, 0, Ease::kInOut},", "{0, 100, Ease::kInOut},",
                    "{Channel::kLift, {kKeys + 0, 3}},", "{Channel::kLean, {kKeys + 3, 2}},",
                    "{Channel::kEyeOpenL, {kKeys + 5, 2}},", "{Channel::kEyeOpenR, {kKeys + 7, 2}},",
                    '{50, "pop"},', '{300, "squish"},',
                    '{"hop", 400, false, true, {kTracks + 0, 1}, {kCues + 0, 2}},',
                    '{"sway", 200, true, false, {kTracks + 1, 3}},',
                    # An occasion's tags as tags.h's bits (night 3, tier4 17), its wait in seconds.
                    f"{{kClips + 0, {(1 << 3) | (1 << 17)}u, 0}},", "{kClips + 0, 0u, 90},",
                    # A tier's base clip, its tag as tags.h's bit (tier2 15).
                    f"{{kClips + 1, {1 << 15}u}},",
                    "{SceneState::kIdle, kClips + 1, {}},",
                    "{SceneState::kWorking, nullptr, {kOccasions + 0, 2}, {kTiers + 0, 1}},",
                    "inline constexpr Rig kRig = {{pack::kExpressions, 1}, {pack::kClips, 2}, {pack::kLooks, 2}};"]:
            self.assertIn(row, text)

    def test_a_bad_edit_fails_with_its_file_and_key(self):
        _, problems = self.rig({
            "expressions.json": {"happy": {"eyes": "Dot", "wiggle": 1}, "calm": {"mouth": "line"}, "giddy": {}},
            "clips/hop.json": {"id": "hop", "ms": 400, "cues": [[300, "pop"], [400, "pop"], [10, "Thud"]],
                               "tracks": {"nose": [[0, 0]], "squash": [[0, 0], [10, 2500]],
                                          "lift": [[0, 0], [100, 300], [100, 0], [200, 0, "bouncy"]]}},
            "clips/sway.json": {"ms": 200, "loop": True, "tracks": {"lean": [[0, 0], [200, 100]]}},
            "clips/Bad Name.json": {"ms": 0},
            "looks.json": {"idle": {"clip": "hop", "scene": "desk"},
                           "working": {"clip": "nope", "tiers": {"tier1": "hop", "night": "sway", "tier3": "nope"}},
                           "dancing": {},
                           "asleep": {"occasions": [{"clip": "sway", "when": ["night"]}, {"clip": "hop"},
                                                    {"clip": "hop", "when": ["nighttime"], "after": -1}, {"when": []}]}},
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
            "rig/clips/hop.json: tracks.nose: isn't a channel",
            "rig/clips/hop.json: tracks.squash[1]: its value, 2500, isn't a whole number from -2000 to 2000",
            "rig/clips/hop.json: tracks.lift[2]: its time, 100, isn't a whole ms after the key before's and at most 400",
            "rig/clips/hop.json: tracks.lift[3]: its ease, 'bouncy', isn't one of linear, in, out, inout",
            "rig/clips/hop.json: cues[1]: isn't [ms before 400, a name] (at most 255 of them)",
            "rig/clips/hop.json: cues[2]: isn't [ms before 400, a name] (at most 255 of them)",
            "rig/clips/sway.json: tracks.lean: loops, so it starts at 0 and ends at ms on the value it started on",
            "rig/looks.json: dancing: isn't a state the board has",
            "rig/looks.json: idle.scene: unknown key",
            "rig/looks.json: idle.clip: hop doesn't loop",
            "rig/looks.json: working.clip: 'nope' isn't a clip in rig/clips/",
            "rig/looks.json: working.tiers.night: isn't a tier",
            "rig/looks.json: working.tiers.tier3: 'nope' isn't a clip in rig/clips/",
            "rig/looks.json: working.tiers.tier1: hop doesn't loop",
            "rig/looks.json: asleep.occasions[0].clip: sway loops, and an occasion plays once",
            "rig/looks.json: asleep.occasions[1]: needs a tag or a wait, or it would always fit",
            f"rig/looks.json: asleep.occasions[2].when: isn't a list of tags, each once ({', '.join(gen.tag_names())})",
            "rig/looks.json: asleep.occasions[2].after: -1 isn't a whole number from 0 to 65535",
            "rig/looks.json: asleep.occasions[3].clip: missing",
        ])

    def test_a_bad_rig_stops_the_pack(self):
        """--check and --stage refuse a pack whose rig/ has a problem, naming it."""
        character = {"id": "x", "version": "1", "default_mood": "calm", "moods": [], "faces": {"cyd24": "face"}}
        write(self.dir / "firmware/src/render/face/face.cpp", "")
        write(self.dir / "rig" / "looks.json", {"idle": {"clip": "nope"}})
        self.assertIn("rig/looks.json: idle.clip: 'nope' isn't a clip in rig/clips/", gen.pack_problems(self.dir, character))


class ReferenceRuleTests(unittest.TestCase):
    """CHARACTER.md §16: a pack's references, in a temporary repo."""

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

    def uncut(self):
        """A checkout that hasn't cut the frames: git doesn't keep them."""
        shutil.rmtree(self.ref / "frames")

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
        """Read: the tool's sheet for each file, frames and ms, and, where this checkout has cut the frames, frames that
        count them. Translated and on: a reading, and what it became."""
        self.assertEqual(self.reference(status="read"),
                         ["it's read, and perk.gif has no sheet (boopctl reference read)"])
        self.read(3)
        self.assertEqual(self.reference(status="read"),
                         ["it's read, and reference.json has no frames or ms (boopctl reference read)"])
        self.assertEqual(self.reference(status="read", frames=2, ms=80),
                         ["it's read, and its frames aren't what frames/ holds (3 frames; boopctl reference read)"])
        self.assertEqual(self.reference(status="read", frames=3, ms=80), [])
        self.uncut()
        self.assertEqual(self.reference(status="read", frames=3, ms=80), [], "a checkout without the frames: the sheet is enough")
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

    def test_a_run_reads_each_pack_once(self):
        """One run's Reads reads a pack's rig/ once, however many steps ask, by its folder however it's named."""
        reads = gen.Reads()
        self.assertIs(reads.rig(self.pack), reads.rig(self.pack.parent / "pal"))


if __name__ == "__main__":
    unittest.main()
