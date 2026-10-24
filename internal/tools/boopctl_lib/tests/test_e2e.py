"""boopctl e2e's order check (internal/VERIFICATION.md L4) on a made-up app
log: a brain reaction comes after the rules' reaction, and the device's
`ended` says how it went: waiting in the queue behind another's `say`, or being
skipped for waiting too long, is fine; being cut short by the brain's own
next reaction, or a name the device doesn't play, isn't. And e2e and soak
--pipeline when the run can't start. Needs no board or app."""
import contextlib
import io
import json
import os
import socket
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from boopctl_lib import e2e  # noqa: E402
from boopctl_lib.device import DeviceError  # noqa: E402

# The app's boop.log lines as the Mac writes them (`link brain|rules → <line>`,
# `device: do N ended HOW (WHY)`), with the vocabulary's `do` lines.
LOG = """\
10:00:00.000 hook: claude UserPromptSubmit
10:00:00.001 link rules → {"t":"state","base":"working","mood":"calm"}
10:00:00.001 link rules → {"t":"do","id":6,"name":"starting","play":"if_free","args":{"variant":3,"ctx":"new_task"}}
10:00:00.002 link brain → {"t":"do","id":7,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d03"},"mood":"excited","loops":1}}
10:00:00.100 device: do 6 ended done
10:00:02.000 hook: claude Stop
10:00:02.001 link rules → {"t":"state","base":"idle","mood":"calm"}
10:00:02.002 link brain → {"t":"do","id":8,"name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","mood":"proud","loops":1}}
10:00:02.100 device: do 7 ended done
10:00:03.000 link brain → {"t":"do","id":9,"name":"react","play":"next","ttl":5000,"args":{"say":{"take":"new.d03"},"mood":"calm","loops":1}}
10:00:03.100 device: do 8 ended done
10:00:04.000 hook: claude UserPromptSubmit
10:00:04.001 link rules → {"t":"do","id":10,"name":"listening","play":"now"}
10:00:04.001 device: do 9 ended cut (now)
10:00:04.500 device: do 10 ended done
"""


class Recorder(SimpleNamespace):
    def __init__(self, log: str) -> None:
        super().__init__(app=SimpleNamespace(log_text=lambda: log), said=[], failed=[])

    def say(self, line: str) -> None:
        self.said.append(line)

    def fail(self, line: str) -> None:
        self.failed.append(line)


class OrderTests(unittest.TestCase):
    def test_each_brain_reaction_after_the_rules_reaction_with_how_it_ended(self):
        reactions = e2e.order(LOG)
        self.assertEqual([m["id"] for m in reactions], [7, 8, 9], "the brain's only")
        self.assertEqual([m["moment"] for m in reactions], ["line", "task_complete", "line"])
        self.assertEqual([m["after_reaction_ms"] for m in reactions], [1, 1, 999])
        self.assertEqual([m["ended"] for m in reactions], ["done", "done", "cut (now)"])
        self.assertEqual([m["next_by"] for m in reactions], ["brain", "brain", "rules"])
        self.assertEqual([m["now_by"] for m in reactions], ["rules", "rules", "rules"], "the next `now` was listening")

    def test_a_rules_now_may_cut_the_brain_short(self):
        run = Recorder(LOG)
        result = e2e.check_order(run)
        self.assertEqual((result["early"], result["unended"], result["skipped"]), (0, 0, 0))
        self.assertEqual(result["cut_by_newer"], ["10:00:03.000 line (9) by rules"])
        self.assertEqual(run.failed, [])

    def test_waiting_behind_another_and_being_refused_are_fine(self):
        """The device queues the brain's reactions (linkkit/SPEC.md §4): one
        that waited past its ttl behind another's line, or that the device
        refused while something needed you, is no failure."""
        log = LOG.replace("device: do 8 ended done", "device: do 8 ended skipped (late)").replace(
            "device: do 9 ended cut (now)", "device: do 9 ended skipped (needs_you)")
        run = Recorder(log)
        result = e2e.check_order(run)
        self.assertEqual((result["skipped"], result["cut_by_newer"], result["odd_ends"]), (2, [], []))
        self.assertEqual(run.failed, [])
        for how in ("skipped (busy)", "skipped (full)", "skipped (listening)", "skipped (mic_on)", "skipped (not_listening)", "skipped",
                    "cut (tap)", "cut (needs_you)", "cut (reset)", "skipped (reset)", "skipped (no_app)",
                    "skipped (nothing)"):
            with self.subTest(how):
                run = Recorder(LOG.replace("device: do 8 ended done", f"device: do 8 ended {how}"))
                e2e.check_order(run)
                self.assertEqual(run.failed, [])

    def test_the_brain_cutting_its_own_short_or_an_unknown_name_fails(self):
        mine = LOG.replace('{"t":"do","id":9,"name":"react","play":"next","ttl":5000,',
                           '{"t":"do","id":9,"name":"react","play":"now",').replace(
            "device: do 8 ended done", "device: do 8 ended cut (now)")
        run = Recorder(mine)
        self.assertEqual(e2e.check_order(run)["cut_by_newer"], ["10:00:02.002 task_complete (8) by brain",
                                                                "10:00:03.000 line (9) by rules"])
        self.assertEqual(len(run.failed), 1)
        self.assertIn("cut short by the brain's next one", run.failed[0])
        run = Recorder(LOG.replace("device: do 7 ended done", "device: do 7 ended skipped (unknown)"))
        self.assertEqual(e2e.check_order(run)["odd_ends"], ["10:00:00.002 line (7) skipped (unknown)"])
        self.assertEqual(len(run.failed), 1)

    def test_a_reaction_never_ended_fails(self):
        run = Recorder(LOG.split("10:00:04.001 device")[0])
        self.assertEqual(e2e.check_order(run)["unended"], 1)
        self.assertTrue(any("never got the device's `ended`" in f for f in run.failed))

    def test_a_reaction_before_any_rules_reaction_is_early(self):
        run = Recorder('10:00:00.000 link brain → {"t":"do","id":1,"name":"react","play":"next","args":{"mood":"calm"}}\n'
                       "10:00:01.000 device: do 1 ended done\n")
        self.assertEqual(e2e.check_order(run)["early"], 1)
        self.assertEqual(len(run.failed), 1)


class SetupFailureTests(unittest.TestCase):
    """No board, no build or an app that exits: the run fails with the
    reason and still writes its result."""

    def setUp(self):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        tmp, leak = Path(d.name), []
        self.out, self.leak = tmp / "out", leak
        self.out.mkdir()
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

        class NoBoard(e2e.Run):
            """Its throwaway state in the test's folder, and no board."""

            def __init__(self, root, out, brain, port):
                super().__init__(tmp / root.name, out, brain, port)

            def start(self):
                if leak:  # the log of an app that got partway
                    self.state.mkdir(parents=True)
                    (self.state / "boop.log").write_text(leak[0])
                raise DeviceError("no board on /dev/cu.usbserial-*")

        patch = mock.patch.object(e2e, "Run", NoBoard)
        patch.start()
        self.addCleanup(patch.stop)

    def test_e2e_writes_its_result(self):
        self.assertEqual(e2e.main(self.out, "scripted", None, None), 1)
        result = json.loads((self.out / "e2e-scripted.json").read_text())
        self.assertFalse(result["ok"])
        self.assertIn("no board on /dev/cu.usbserial-*", result["failures"])

    def test_soak_writes_its_result(self):
        self.assertEqual(e2e.soak(self.out, "scripted", None, 0.01), 1)
        result = json.loads((self.out / "soak-scripted.json").read_text())
        self.assertFalse(result["ok"])
        self.assertEqual((result["heap_min_after_2min"], result["series"]), (None, []))
        self.assertIn("no board on /dev/cu.usbserial-*", result["failures"])

    def test_named_fixtures_are_still_checked_for_private_words(self):
        self.leak.append("hook: claude PostToolUse PRIVATE_OUTPUT_9823\n")
        self.assertEqual(e2e.main(self.out, "scripted", None, ["claude/session.jsonl"]), 1)
        failures = json.loads((self.out / "e2e-scripted.json").read_text())["failures"]
        self.assertTrue(any(f.startswith("PRIVATE_ markers") for f in failures), failures)
        self.assertFalse(any("the harness saw an event" in f for f in failures), "the whole run's events aren't expected")


class HookEnvironmentTests(unittest.TestCase):
    """A fixture's hook carries nothing of whoever runs the check: run from
    an agent, the hook took the agent's app, its Claude session and its
    process for the fixture's."""

    AGENT = {"__CFBundleIdentifier": "com.anthropic.claudefordesktop", "CLAUDE_CODE_ENVIRONMENT_KIND": "bridge",
             "CLAUDE_CODE_HOST_SESSION_ID": "local_agent", "CODEX_INTERNAL_ORIGINATOR_OVERRIDE": "x",
             "TERM_PROGRAM": "iTerm.app", "ITERM_SESSION_ID": "w0t0p0:ABCDEF12-3456-7890-ABCD-EF1234567890",
             "TMUX": "/tmp/tmux-501/default,1,0", "TMUX_PANE": "%3"}

    def setUp(self):
        d = tempfile.TemporaryDirectory(dir="/tmp")  # a socket's path has room for 103 bytes
        self.addCleanup(d.cleanup)
        self.run_ = e2e.Run(Path(d.name), Path(d.name) / "out", "scripted", None)
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        # The agent's own process is above the check's.
        self.enterContext(mock.patch.dict("os.environ", self.AGENT, CLAUDE_PID=str(os.getppid())))

    def test_only_the_runs_own_variables(self):
        env = self.run_.hook_env()
        self.assertEqual(sorted(env), ["AGENT_HOOKS_DIR", "AGENT_HOOKS_SOCKET", "CODEX_HOME", "HOME"])
        self.assertTrue(all(value.startswith(str(self.run_.root)) for value in env.values()), env)

    @unittest.skipUnless((e2e.BIN / "agent-hook").exists(), "agent-hook isn't built: make build")
    def test_the_real_hook_sends_no_app_session_or_terminal_of_its_own(self):

        server = socket.socket(socket.AF_UNIX)
        self.addCleanup(server.close)
        server.bind(self.run_.hook_sock)
        server.listen(4)
        server.settimeout(5)
        dev = SimpleNamespace(request=lambda message: {"rx": {"state": 0}})
        for agent in ("claude", "codex"):
            with mock.patch.object(e2e, "STATE_WAIT", 0):
                self.run_.hook(dev, agent, json.dumps({"hook_event_name": "UserPromptSubmit", "session_id": "e2e-env",
                                                       "cwd": "/tmp/e2e-env", "prompt": "hi"}))
            conn, _ = server.accept()
            with conn:
                line = json.loads(conn.makefile().readline())
            self.assertEqual(self.run_.failures, [])
            self.assertEqual((line["agent"], line["session"]), (agent, "e2e-env"))
            for key in ("app", "app_session"):
                self.assertNotIn(key, line, agent)
            # The terminal's tty comes from the processes above the hook,
            # which no environment changes; the rest of it from variables.
            self.assertEqual(set(line.get("terminal", {})) - {"tty"}, set(), agent)
            self.assertEqual(line["pid"], os.getpid(), "the agent is the process running the fixture, not CLAUDE_PID's")


if __name__ == "__main__":
    unittest.main()
