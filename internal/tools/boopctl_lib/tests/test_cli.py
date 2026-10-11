"""boopctl's command line: every subcommand parses and has help, and the
set stays the one internal/VERIFICATION.md §2 lists. Needs no board."""
import contextlib
import io
import json
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "characters" / "pixel" / "tools"))

from boopctl_lib import cli, common  # noqa: E402
from facegen import facegen  # noqa: E402
from fake_board import FakeBoard  # noqa: E402

COMMANDS = ["ping", "state", "shot", "send", "play", "takes", "card", "sim", "run", "perf", "latency", "soak", "e2e",
            "bridge", "cam", "dash", "day", "workday", "calibrate"]


def firmware_names(path: str, start: str, item: str = r'"(\w+)"', end: str = "};") -> list:
    """What `item` matches in firmware/src/`path`, from `start` to the next
    `end`: by default, the names in a C table."""
    src = (cli.REPO / "firmware" / "src" / path).read_text()
    body = src[src.index(start):]
    return re.findall(item, body[:body.index(end)])


class CLITests(unittest.TestCase):
    def subcommands(self) -> list[str]:
        parser = cli.build_parser()
        action = next(a for a in parser._actions if a.dest == "command")
        return list(action.choices)

    def test_the_commands_are_the_documented_ones(self):
        self.assertEqual(self.subcommands(), COMMANDS)
        table = (cli.REPO / "internal" / "VERIFICATION.md").read_text()
        for command in COMMANDS:
            self.assertTrue(f"| `{command}" in table, f"VERIFICATION.md §2 doesn't list boopctl {command}")

    def test_every_command_has_help(self):
        for command in COMMANDS:
            with self.subTest(command), contextlib.redirect_stdout(io.StringIO()) as out:
                with self.assertRaises(SystemExit) as done:
                    cli.build_parser().parse_args([command, "--help"])
                self.assertEqual(done.exception.code, 0)
                self.assertIn("usage: boopctl", out.getvalue())

    def test_the_hand_driven_commands_parse(self):
        parse = cli.build_parser().parse_args
        self.assertEqual(parse(["play", "cheer", "--take", "previous.yay"]).take, "previous.yay")
        self.assertEqual(parse(["play", "needs", "--seconds", "3"]).seconds, 3)
        self.assertEqual(parse(["takes", "--levels", "1", "10"]).levels, [1, 10])
        self.assertTrue(parse(["takes", "--only", "Go", "--board-volume"]).board_volume)
        self.assertTrue(parse(["soak", "--pipeline", "--minutes", "30", "--brain", "jev"]).pipeline)
        self.assertEqual(parse(["cam", "clip", "cheer", "--camera", "X"]).camera, "X")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            parse(["takes", "--levels", "1", "--board-volume"])
        # A take the pack lacks is refused before the board is touched,
        # not by argparse, so --help works with no pack.
        with self.assertRaisesRegex(cli.DeviceError, "no take 'banana'"):
            cli.cmd_play(parse(["play", "cheer", "--take", "banana"]))


class PlayTests(unittest.TestCase):
    def play(self, what: str, *more: str, playing: str | None = None) -> tuple[int, list]:
        """Plays `what` on a board whose dbg.state says `playing` (by
        default the name play sends); returns play's exit code and the
        names of the `do`s it sent."""
        name = cli.OLD_ANIMS.get(what, what)
        board = FakeBoard.by_type({"dbg.ping": {"ble": "adv"}, "dbg.clock": {},
                                   "dbg.state": {"moment": {"anim": playing or name, "left_ms": 900, "variant": 1}}})
        self.board = board
        with mock.patch.object(cli, "Device", lambda port: board), contextlib.redirect_stdout(io.StringIO()):
            code = cli.cmd_play(cli.build_parser().parse_args(["play", what, *more]))
        return code, [m["name"] for m in self.dos()]

    def dos(self) -> list[dict]:
        return [m for m in self.board.sent if m["t"] == "do"]

    def args(self) -> list[dict]:
        return [m.get("args", {}) for m in self.dos()]

    def test_play_sets_the_mood(self):
        self.play("cheer", "--mood", "determined")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["determined"])
        self.play("cheer", "--mood", "wounded")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["wounded"])
        self.play("wiggle")
        self.assertEqual([m["mood"] for m in self.board.sent if m["t"] == "state"], ["happy"])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--mood", "cheerful"])

    def test_the_moods_are_the_devices(self):
        """The moods boopctl sends are facegen's, which it writes into the
        Pixel pack's faces.h, in the device's order."""
        self.assertEqual(cli.MOODS, facegen.MOODS)
        self.assertEqual(cli.MOODS, firmware_names("../../characters/pixel/firmware/include/faces.h", "kMoodNames["))

    def test_play_sends_just_the_animation_now(self):
        """A `do` with the animation's name, played `now` so it replaces
        whatever plays, with no id: play reads dbg.state, not `ended`
        (linkkit/SPEC.md §3)."""
        for anim in cli.ANIMS:
            self.assertEqual(self.play(anim), (0, [anim]))
            self.assertEqual(self.dos(), [{"t": "do", "name": anim, "play": "now"}])
        self.assertEqual(self.play("task_complete", playing="poked")[0], 1, "something else playing")

    def test_the_older_names_are_sent_by_todays(self):
        """The device no longer knows `cheer` or `wiggle`: play sends
        task_complete's success and poked."""
        self.assertEqual(self.play("cheer"), (0, ["task_complete"]))
        self.assertEqual(self.args(), [{"outcome": "success"}])
        self.assertEqual(self.play("wiggle"), (0, ["poked"]))
        self.assertEqual(self.args(), [{}])
        with self.assertRaisesRegex(cli.DeviceError, "task_complete --outcome failure"):
            self.play("cheer", "--outcome", "failure")

    def test_play_sends_a_take(self):  # `say` is {"take": id}
        self.assertEqual(self.play("cheer", "--take", "new.d15")[0], 0)
        self.assertEqual(self.args()[0]["say"], {"take": "new.d15"})

    def test_play_sends_the_facts(self):  # outcome, ctx, variant
        self.play("task_complete", "--outcome", "failure", "--variant", "2")
        self.assertEqual(self.args(), [{"outcome": "failure", "variant": 2}])
        self.play("starting", "--ctx", "session")
        self.assertEqual([a.get("ctx") for a in self.args()], ["session"])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "task_complete", "--outcome", "win"])

    def test_the_animations_are_the_devices(self):
        """The names boopctl plays are the device's own, the names of the
        states whose designs they play (firmware/src/render/scene.cpp
        animState; faces.h names them), and all of them are in Boop's
        `hello.does`. The older two are play's own, sent by today's names."""
        names = firmware_names("../../characters/pixel/firmware/include/faces.h", "kStateNames[")
        self.assertEqual(names, facegen.STATES)
        states = dict(zip(firmware_names("render/types.h", "enum class SceneState", r"\bk\w+"), names))
        plays = firmware_names("render/types.cpp", "SceneState animState(Anim a) {",
                               r"case Anim::k\w+:\s*return SceneState::(k\w+);", end="\n}\n")
        self.assertEqual(cli.ANIMS + ["listening"], [states[s] for s in plays])
        self.assertTrue(set(cli.ANIMS + ["listening"]) <= set(common.DOES))
        self.assertEqual(set(common.DOES) - set(cli.ANIMS), {"react", "listening", "stop_listening"})
        self.assertTrue(set(cli.OLD_ANIMS.values()) <= set(cli.ANIMS))

    def test_the_do_names_are_the_devices(self):
        """The names the tools send are the ones the firmware puts in
        `hello.does`, in its order, and the ones it plays with no animation
        are the tools' NO_ANIM."""
        names = firmware_names("app/device.cpp", "kDoNames[kDoCount] =")
        self.assertEqual(common.DOES, names)
        anims = firmware_names("app/device.cpp", "kDoAnims[kDoCount] =", r"render::Anim::k(\w+)")
        self.assertEqual(len(anims), len(names))
        self.assertEqual(common.NO_ANIM, {n for n, a in zip(names, anims) if a == "None"})

    def test_play_sends_its_loops(self):  # 1-6, none reads as 1
        self.play("cheer", "--loops", "3")
        self.assertEqual([a.get("loops") for a in self.args()], [3])
        self.play("cheer")
        self.assertEqual([a.get("loops") for a in self.args()], [None])
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["play", "cheer", "--loops", "7"])


class WireTests(unittest.TestCase):
    """The requests the tools send and read (linkkit/SPEC.md §3), and
    the older logs' moments read the same way."""

    def test_a_do_as_the_tools_send_it(self):
        self.assertEqual(json.dumps(common.do("react", id=44, play="next", ttl=5000, mood="calm")),
                         '{"t": "do", "id": 44, "name": "react", "play": "next", "ttl": 5000, "args": {"mood": "calm"}}',
                         "in the vocabulary's order")
        self.assertEqual(common.do("poked"), {"t": "do", "name": "poked", "play": "now"}, "now, no id, no args")

    def test_what_a_request_asks(self):
        call = common.call
        finish = call({"t": "do", "id": 7, "name": "task_complete", "play": "next", "ttl": 5000,
                       "args": {"outcome": "success", "say": {"take": "a"}}})
        self.assertEqual((finish["anim"], finish["id"], finish["play"], finish["outcome"], finish["say"]),
                         ("task_complete", 7, "next", "success", {"take": "a"}))
        self.assertEqual({k: call({"t": "do", "name": k})["anim"] for k in ("react", "stop_listening", "listening")},
                         {"react": None, "stop_listening": None, "listening": "listening"})
        self.assertEqual(call({"t": "do", "name": "starting"})["play"], "next", "the kit's default")
        # Older logs: a moment played at once; the empty one ended push-to-talk.
        cheer = call({"t": "moment", "anim": "cheer", "loops": 1})
        self.assertEqual((cheer["name"], cheer["anim"], cheer["play"], cheer["loops"]), ("cheer", "cheer", "now", 1))
        self.assertEqual(call({"t": "moment", "say": {}, "mood": "calm", "id": 3})["name"], "react")
        self.assertEqual(call({"t": "moment"})["name"], "stop_listening")
        self.assertIsNone(call({"t": "state", "base": "idle"}))

    def test_what_says_a_request_ended(self):
        self.assertEqual(common.ended({"t": "ev", "kind": "ended", "data": {"id": 44, "how": "cut", "why": "tap"}}),
                         {"id": 44, "how": "cut", "why": "tap"})
        self.assertIsNone(common.ended({"t": "ev", "kind": "tap", "did": "dip", "data": {"on": 44}}))
        self.assertIsNone(common.ended({"t": "ended", "id": 44, "how": "done"}), "the old wire is gone")


class PerfScenesTests(unittest.TestCase):
    """perf --scenes: each scene's slowest second against
    its frames-a-second budget, working's worst frame, the least internal
    heap and the DAC, from a profiling build's one-second lines, the first
    of each scene left out."""

    def scenes(self, fps: dict[str, int], frame_ms: int = 40, internal_min: int = 60000, errors: int = 0,
               lines: bool = True) -> dict:
        class Clock:
            now = 0.0

            def monotonic(self) -> float:
                return self.now

            def sleep(self, s: float) -> None:
                self.now += s

        clock = Clock()
        scene = ["working"]

        def answer(msg: dict) -> bytes:
            if msg["t"] == "state":
                scene[0] = ("attention" if "attn" in msg else "frightened" if msg.get("mood") == "frightened"
                            else "asleep" if msg["base"] == "asleep" else scene[0] if scene[0] == "pokes" else "working")
            elif msg["t"] == "do":
                scene[0] = "pokes"
            if msg["t"].startswith("dbg."):
                return json.dumps({"t": msg["t"]}).encode() + b"\n"
            return b""

        class Board(FakeBoard):
            second = 0

            def _read(self) -> bytes:
                out = super()._read()
                if out:
                    return out  # a reply comes at once
                clock.now += 0.01  # otherwise time passes while it waits
                if lines and int(clock.now) > self.second:
                    self.second = int(clock.now)
                    # The first second of a scene is the last one's: it's left out.
                    rate = 1 if self.second % 10 == 1 else fps.get(scene[0], 31)
                    out += (f"gel_profile fps_milli={rate * 1000} draw_us=26000 push_us=9000 wait_us=100 "
                            f"push_px=70000 internal_free=90000 internal_min={internal_min} psram_free=7000000 "
                            f"audio_write_errors={errors} cpu_mhz=240 press_ms=41/55 tap_ms=60/70 state_ms=40/50 "
                            f"do_ms=40/50 frame_ms=33/{frame_ms}\ngel_parts engine_us=2700 sync_us=500 "
                            f"body_us=15000 art_us=1300 props_us=500 clear_us=3000\n").encode()
                return out

        board = Board(answer)
        out = io.StringIO()
        with mock.patch.object(cli, "Device", lambda port: board), mock.patch.object(cli, "time", clock), \
                mock.patch("boopctl_lib.device.time", clock), contextlib.redirect_stdout(out):
            code = cli.cmd_perf(cli.build_parser().parse_args(["perf", "--scenes", "--seconds", "10"]))
        result = json.loads(out.getvalue())
        self.assertEqual(code, 0 if result["ok"] else 1)
        return result

    def test_each_scene_against_its_budget(self):
        result = self.scenes({"working": 31, "attention": 28, "pokes": 20, "frightened": 29, "asleep": 10})
        self.assertTrue(result["ok"], result)
        self.assertEqual(sorted(result["scenes"]), sorted(name for name, *_ in cli.PERF_SCENES))
        working = result["scenes"]["working"]
        self.assertEqual((working["fps_min"], working["body_us"], working["frame_ms_max"]), (31, 15000, 40))
        self.assertIn(working["samples"], (8, 9))  # ten seconds, the first left out, the last maybe cut
        self.assertEqual((cli.PERF_FRAME_MS, cli.PERF_HEAP_MIN), (50, 50000))

    def test_a_slow_scene_frame_heap_or_dac_fails(self):
        self.assertFalse(self.scenes({"working": 29})["ok"])
        self.assertFalse(self.scenes({"attention": 27})["ok"])
        self.assertFalse(self.scenes({}, frame_ms=51)["ok"])
        self.assertFalse(self.scenes({}, internal_min=49000)["ok"])
        self.assertFalse(self.scenes({}, errors=1)["ok"])

    def test_an_everyday_build_says_to_flash_the_profiling_one(self):
        with self.assertRaisesRegex(cli.DeviceError, "amoled206_profile"):
            self.scenes({}, lines=False)


class SoakCutShortTests(unittest.TestCase):
    """A soak whose port goes (the board unplugged or reset) reports the
    minutes it ran and the heap so far, fails, and leaves --out holding
    every sample it took (VERIFICATION.md L2)."""

    def test_a_soak_cut_short_keeps_what_it_saw(self):
        class Clock:
            now = 0.0

            def monotonic(self) -> float:
                return self.now

            def sleep(self, s: float) -> None:
                self.now += s

        clock = Clock()
        pings = [0]

        def answer(msg: dict) -> bytes:
            t = msg["t"]
            if t == "dbg.ping":
                pings[0] += 1
                reply = {"t": t, "up": 1000 + pings[0] * 5000, "heap": 74000, "heap_min": 73000 - pings[0],
                         "fps": 30, "draw_us": 28000, "push_us": 9000}
            elif t == "dbg.state":
                reply = {"t": t, "rx": {"state": 0, "do": 0}}
            elif t.startswith("dbg."):
                reply = {"t": t}
            else:
                return b""
            return json.dumps(reply).encode() + b"\n"

        class Board(FakeBoard):
            def _write(self, data: bytes) -> None:
                if pings[0] >= 20:  # about 95 s in
                    raise OSError(6, "Device not configured")
                super()._write(data)

        board = Board(answer)
        out, path = io.StringIO(), Path(self.enterContext(tempfile.TemporaryDirectory())) / "soak.json"
        with mock.patch.object(cli, "Device", lambda port: board), mock.patch.object(cli, "time", clock), \
                contextlib.redirect_stdout(out):
            code = cli.cmd_soak(cli.build_parser().parse_args(["soak", "--minutes", "30", "--vol", "0",
                                                                "--out", str(path)]))
        result = json.loads(out.getvalue())
        self.assertEqual(code, 1)
        self.assertFalse(result["ok"])
        self.assertIn("Device not configured", result["interrupted"])
        self.assertEqual((result["samples"], result["heap_min_end"]), (20, 72980))
        self.assertTrue(1.5 <= result["minutes_run"] <= 2.0, result["minutes_run"])  # the 20th sample, about 100 s in
        kept = json.loads(path.read_text())
        self.assertEqual(len(kept["series"]), 20)
        self.assertEqual(kept["interrupted"], result["interrupted"])


class LatencyTests(unittest.TestCase):
    """latency's budgets (internal/VERIFICATION.md §8): a press, a state and a do count
    from when they were sent, against the board's clock found by pinging;
    a tap from the release the board times. A board that's slow at any of
    them, or loses one, fails."""

    OFFSET = 5000.0  # the board's millis less the host's

    def latency(self, ms: dict[str, int], lose: str = "") -> dict:
        class Clock:  # latency's waits pass at once
            now = 0.0

            def monotonic(self) -> float:
                return self.now

            def sleep(self, s: float) -> None:
                self.now += s

        clock = Clock()
        stats = {k: {"n": 0, "p95": 0, "max": 0, "at": 0, "shown": 0} for k in ("press", "tap", "state", "do", "frame")}

        def now() -> float:
            return clock.now * 1000 + self.OFFSET

        def sample(kind: str, at: float) -> None:
            if kind != lose:
                stats[kind].update(n=stats[kind]["n"] + 1, at=round(at), shown=round(at) + ms[kind])

        def answer(msg: dict) -> bytes:
            t = msg["t"]
            if t == "hello":
                reply = {"t": t, "kit": 1, "app": "boop", "face": "gel"}
            elif t == "dbg.ping":
                reply = {"t": t, "up": round(now())}
            elif t == "dbg.latency":
                reply = {"t": t, "now": round(now()), **stats}
            elif t in ("dbg.press", "dbg.touch"):
                sample("press", now())
                sample("tap", now() + msg["ms"])
                reply = {"t": t}
            elif t in ("state", "do"):
                sample(t, now())
                return b""
            elif t.startswith("dbg."):
                reply = {"t": t}
            else:
                return b""
            return json.dumps(reply).encode() + b"\n"

        board = FakeBoard(answer)
        out = io.StringIO()
        with mock.patch.object(cli, "Device", lambda port: board), mock.patch.object(cli, "time", clock), \
                contextlib.redirect_stdout(out):
            code = cli.cmd_latency(cli.build_parser().parse_args(["latency", "--rounds", "4", "--pings", "5"]))
        result = json.loads(out.getvalue())
        self.assertEqual(code, 0 if result["ok"] else 1)
        self.sent = board.sent
        return result

    def test_it_runs_muted(self):
        """A state with no vol plays at 6, and its taps and pokes click."""
        self.latency({"press": 40, "tap": 70, "state": 60, "do": 60})
        states = [m for m in self.sent if m["t"] == "state"]
        self.assertTrue(states)
        self.assertTrue(all(m.get("vol") == 0 for m in states), states)

    def test_each_kind_is_timed_from_its_send_or_release(self):
        result = self.latency({"press": 40, "tap": 70, "state": 60, "do": 90})
        self.assertTrue(result["ok"])
        self.assertEqual(result["lost"], 0)
        for kind, ms in (("press", 40), ("state", 60), ("do", 90)):
            self.assertEqual(result[kind]["n"], 8 if kind == "press" else 4)
            self.assertAlmostEqual(result[kind]["p95"], ms, delta=1)  # the clock's offset, to the ms
        self.assertEqual(result["tap"]["max"], 70)
        # The p95 and the worst.
        self.assertEqual({k: result[k]["budget"] for k in cli.LATENCY_BUDGETS},
                         {"press": [80, 100], "tap": [80, 80], "state": [100, 100], "do": [100, 100]})

    def test_a_slow_kind_or_a_lost_one_fails(self):
        self.assertFalse(self.latency({"press": 85, "tap": 70, "state": 60, "do": 60})["ok"])  # p95 over 80
        self.assertFalse(self.latency({"press": 40, "tap": 90, "state": 60, "do": 60})["ok"])
        self.assertFalse(self.latency({"press": 40, "tap": 70, "state": 120, "do": 60})["ok"])
        lost = self.latency({"press": 40, "tap": 70, "state": 60, "do": 60}, lose="state")
        self.assertFalse(lost["ok"])
        self.assertEqual(lost["lost"], 4)


class PerfTests(unittest.TestCase):
    """perf --motion's rule (VERIFICATION.md L2): a frame drawn in every
    second and none over 40 ms. fps follows the design, so 6 a second, a
    second of the cheer, passes."""

    def perf(self, fps: int, frame_us: int, face: str = "pixel", draw_us: int = 1000) -> dict:
        up = [0]

        def answer(msg: dict) -> bytes:
            if msg["t"] == "hello":
                reply = {"t": "hello", "kit": 1, "app": "boop", "face": face}
            elif msg["t"] == "dbg.ping":
                up[0] += 1000
                reply = {"t": "dbg.ping", "up": up[0], "heap": 74000, "heap_min": 73800, "fps": fps,
                         "draw_us": draw_us, "push_us": frame_us - draw_us}
            elif msg["t"].startswith("dbg."):
                reply = {"t": msg["t"]}
            else:
                return b""
            return json.dumps(reply).encode() + b"\n"

        class Clock:  # perf's seconds pass at once
            now = 0.0

            def monotonic(self) -> float:
                return self.now

            def sleep(self, s: float) -> None:
                self.now += s

        board = FakeBoard(answer)
        out = io.StringIO()
        with mock.patch.object(cli, "Device", lambda port: board), mock.patch.object(cli, "time", Clock()), \
                contextlib.redirect_stdout(out):
            cli.cmd_perf(cli.build_parser().parse_args(["perf", "--motion", "--seconds", "5"]))
        self.sent = board.sent
        return json.loads(out.getvalue())

    def test_it_runs_muted(self):
        """Its pokes would click at the default volume, 6."""
        self.perf(6, 14200)
        states = [m for m in self.sent if m["t"] == "state"]
        self.assertTrue(states and all(m.get("vol") == 0 for m in states))

    def test_a_slow_design_passes_and_a_stalled_or_slow_board_fails(self):
        self.assertTrue(self.perf(6, 14200)["ok"])
        self.assertFalse(self.perf(0, 14200)["ok"])  # nothing drawn in a second of motion
        self.assertFalse(self.perf(20, 41000)["ok"])  # a frame over 40 ms

    def test_a_gel_board_sends_while_it_draws(self):
        # The gel draws the next frame while the last is sent,
        # so a 30 ms draw and a 15 ms push take 30 ms, not 45.
        self.assertTrue(self.perf(30, 45000, face="gel", draw_us=30000)["ok"])
        self.assertFalse(self.perf(30, 45000, face="pixel", draw_us=30000)["ok"])
        self.assertFalse(self.perf(20, 52000, face="gel", draw_us=41000)["ok"])  # its draw alone is over 40 ms


class TakesTests(unittest.TestCase):
    """The takes boopctl plays are the board's, from the voice pack on its
    card (the chosen character pack's voice/voice.bin)."""

    def test_the_takes_are_the_boards(self):
        takes = cli.takes()
        self.assertEqual(len(takes), 2722)
        self.assertEqual([t.id for t in takes], sorted((t.id for t in takes), key=str.encode), "the pack's order: by id")
        go = cli.take("previous.go")
        self.assertEqual((go.id, go.text, go.ms), ("previous.go", "Go", 638))
        self.assertEqual(cli.take("new.d15").text, "Bada bing bada boom")
        self.assertIsNone(cli.take("banana"))

    def test_only_picks_by_id_or_text(self):
        gos = cli.chosen_takes("Go")
        self.assertTrue({"previous.go", "new.d01", "new.d02"} <= {t.id for t in gos})
        self.assertTrue(all(t.text == "Go" or "go" in t.text.lower().split() for t in gos), [t.text for t in gos])
        self.assertEqual([t.id for t in cli.chosen_takes("new.d15")], ["new.d15"])
        self.assertTrue(all("again" in t.text.lower() for t in cli.chosen_takes("again")))
        self.assertEqual([t.id for t in cli.chosen_takes("mamma mia")], ["new.d14"])
        self.assertEqual({t.text for t in cli.chosen_takes("boom")}, {"Bada bing bada boom", "Boom shakalaka"})
        self.assertEqual(len(cli.chosen_takes(None)), 2722)
        with self.assertRaises(cli.DeviceError):
            cli.chosen_takes("banana")

    def test_a_take_is_checked_against_audio_out(self):
        t = cli.take("previous.go")
        states = iter([{"audio": {"out": {"lines": 3}}, "amp": False},
                       {"amp": True, "vol": 6, "audio": {"out": {"lines": 4, "take": "previous.go", "plan_ms": 638,
                                                                  "out_ms": 638, "wall_ms": 648, "cut": False}}}])
        board = FakeBoard(lambda msg: json.dumps({"t": msg["t"], **next(states)}).encode() + b"\n"
                          if msg["t"] == "dbg.state" else b"")
        r = cli.check_take(board, t)
        self.assertTrue(r["ok"], r)
        self.assertIn({"t": "do", "name": "react", "play": "now", "args": {"say": {"take": "previous.go"}}}, board.sent,
                      "a line on its own: a reaction with no face, played at once")


class SoakTests(unittest.TestCase):
    """The soak's requests, and how it holds the board to one `ended` for
    each reaction (linkkit/SPEC.md §3–4)."""

    def test_reactions_are_waited_requests_with_loops(self):
        import random
        rng = random.Random(1)
        for i in range(1, 50):
            m = cli.soak_reaction(rng, i)
            self.assertEqual((m["t"], m["id"], m["name"], m["play"], m["ttl"]), ("do", i, "react", "next", 5000),
                             "as the Mac sends the brain's")
            self.assertIn(m["args"]["mood"], cli.MOODS)
            self.assertTrue(1 <= m["args"]["loops"] <= 6)
            self.assertTrue(m["args"]["say"] == {} or cli.take(m["args"]["say"]["take"]))
        dos = [cli.soak_do(rng) for _ in range(300)]
        self.assertTrue({m["name"] for m in dos} == set(cli.ANIMS) | {"react"}, "every animation, and lines")
        finishes = [m["args"] for m in dos if m["name"] == "task_complete"]
        self.assertTrue(finishes)
        self.assertTrue(all(1 <= a["loops"] <= 3 and a["outcome"] in cli.OUTCOMES for a in finishes))
        self.assertTrue(all(m["args"]["ctx"] in cli.CTXS for m in dos if m["name"] == "starting"))
        self.assertTrue(all(m["args"]["say"] is not None for m in dos if m["name"] == "react"), "a line says something")
        self.assertFalse(any("id" in m or "mood" in m.get("args", {}) for m in dos), "the rest aren't waited on")
        # Each asks for its turn as the Mac or a tool would.
        plays = {m["name"]: (m["play"], m.get("ttl")) for m in dos}
        self.assertEqual(plays, {"starting": ("if_free", None), "stopped": ("if_free", None), "error": ("if_free", None),
                                 "helper_return": ("if_free", None), "poked": ("now", None), "tap_spam": ("now", None),
                                 "task_complete": ("next", 5000), "reply_ready": ("next", 5000), "react": ("next", 5000)})

    def test_each_reaction_ends_once(self):
        ended = [{"id": 1, "how": "done"}, {"id": 2, "how": "cut", "why": "tap"}, {"id": 3, "how": "skipped"}]
        r = cli.ended_report([1, 2, 3], ended, 0)
        self.assertTrue(r["ended_ok"])
        self.assertEqual(r["ended_how"], {"done": 1, "cut (tap)": 1, "skipped": 1})
        self.assertFalse(cli.ended_report([1, 2, 3], ended + [ended[0]], 0)["ended_ok"])  # twice
        self.assertFalse(cli.ended_report([1, 2], ended, 0)["ended_ok"])  # an id never sent
        # A missing one only when a line was lost on the way.
        self.assertFalse(cli.ended_report([1, 2, 3, 4], ended, 0)["ended_ok"])
        self.assertTrue(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_ok"])
        self.assertEqual(cli.ended_report([1, 2, 3, 4], ended, 1)["ended_missing"], [4])

    def test_waiting_behind_another_is_an_answer_and_an_unknown_name_fails(self):
        """The device queues the reactions: one that waited past its ttl, or
        was refused, ended as surely as one that played. A name the device
        doesn't play means the soak and the firmware disagree."""
        ended = [{"id": 1, "how": "skipped", "why": "late"}, {"id": 2, "how": "cut", "why": "now"},
                 {"id": 3, "how": "skipped", "why": "needs_you"}, {"id": 4, "how": "skipped", "why": "full"}]
        r = cli.ended_report([1, 2, 3, 4], ended, 0)
        self.assertTrue(r["ended_ok"], r)
        self.assertEqual(r["ended_how"], {"skipped (late)": 1, "cut (now)": 1, "skipped (needs_you)": 1,
                                          "skipped (full)": 1})
        r = cli.ended_report([1, 2, 3, 4, 5], ended + [{"id": 5, "how": "skipped", "why": "unknown"}], 0)
        self.assertEqual((r["ended_ok"], r["names_unknown"]), (False, 1))

    def test_the_link_hears_what_comes_unasked(self):
        board = FakeBoard.in_turn([b'{"t":"hello","kit":1,"app":"boop","id":"b00p-54fe","fw":"1.0.0","does":[]}\n'
                                   b'{"t":"ev","kind":"ended","data":{"id":7,"how":"done"}}\n'
                                   b'{"t":"ev","kind":"ended","data":{"id":8\n'
                                   b'{"t":"ev","kind":"tap","did":"poked"}\n{"t":"dbg.ping","up":1}\n'])
        heard: list[dict] = []
        board.heard = heard.append
        board.request({"t": "dbg.ping"})
        self.assertEqual([m["t"] for m in heard], ["hello", "ev", "torn", "ev"])
        self.assertEqual([cli.ended(m) for m in heard], [None, {"id": 7, "how": "done"}, None, None],
                         "only an `ev` of kind `ended` is one")


if __name__ == "__main__":
    unittest.main()
