"""The session tool's own tests: demo scripts read as the agent's side,
each reply becomes each agent's tools, the replay server speaks both APIs
as the agents read them and waits for the script, a compact makes each
agent compact and gets its summary, the gate holds a call until its step
is due, and the landing and context-wall demos' edits still fit their
projects and give their stories' test results. None of it runs an agent;
`make demo IN=…` does."""
from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import unittest.mock
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import desktop  # noqa: E402
import gate  # noqa: E402
import model  # noqa: E402
import script as scripts  # noqa: E402
import session  # noqa: E402
import term  # noqa: E402

SESSIONS = HERE.parents[3] / "internal" / "sessions"


def write(folder: Path, lines: list) -> Path:
    path = folder / "demo.jsonl"
    path.write_text("\n".join(lines) + "\n")
    return path


def post(url: str, body: dict) -> list:
    """The server's answer: each SSE event's data, or the one JSON body."""
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        text = r.read().decode()
    if not text.startswith("event:"):
        return [json.loads(text)]
    return [json.loads(line[6:]) for line in text.split("\n") if line.startswith("data: ")]


class ScriptTests(unittest.TestCase):
    def test_every_session_has_a_script_whose_calls_claude_can_make(self):
        for folder in sorted(SESSIONS.iterdir()):
            if not (folder / "workspace").is_dir():
                continue
            s = scripts.load(scripts.find(folder.name))
            replies = s.replies()
            self.assertTrue(replies, folder.name)
            for l in replies:
                if l["agent"] not in ("reply", "compact"):
                    self.assertTrue(model.claude_call(l, "/ws", ["Read", "Edit", "Bash", "Agent"]), f"{folder.name}: {l}")

    def test_steps_are_numbered_as_boop_counts_them(self):
        with tempfile.TemporaryDirectory() as d:
            s = scripts.load(write(Path(d), [
                "// a comment", '{"demo": 1, "title": "T"}', "",
                '{"agent": "prompt", "text": "Go"}', '{"brain": {}}',
                '{"agent": "read", "file": "a.js", "say": "Reading."}',
                '{"agent": "run", "cmd": "git diff", "by": "reviewer"}',
                '{"agent": "reply", "text": "Done."}',
            ]))
        self.assertEqual([l["n"] for l in s.steps], [0, 1, 2, 3, 4], "from 0, without the header and comments")
        self.assertEqual(s.title, "T")
        self.assertEqual([(l["n"], l["agent"]) for l in s.replies()], [(2, "read"), (3, "run"), (4, "reply")],
                         "the agent's steps after the prompt")
        self.assertEqual([scripts.said(l) for l in s.replies()], ["Reading.", None, "Done."])

    def test_claude_asks_only_about_what_the_script_asks_about(self):
        s = scripts.load(scripts.find("landing"))
        rules = session.permissions(s)
        self.assertIn("Bash(npm test)", rules["allow"])
        self.assertEqual(rules["ask"], ["Bash(npm run setup:browser)"])
        self.assertIn("Bash(git:*)", rules["allow"], "the reviewer words its own git commands")

    def test_the_project_is_named_as_the_player_with_no_agent_names_it(self):
        # The sign on the board shows the project, so a live run and the
        # recorded one must agree (Runtime+Demo's slug).
        self.assertEqual("deploy-the-docs", scripts.load(scripts.find("hanging")).project)
        self.assertEqual("keyboard-shortcuts", scripts.load(scripts.find("landing")).project)
        self.assertEqual("a-b-2", scripts.Script(path=Path("x.jsonl"), title=" A, b--2! ").project)
        self.assertEqual("project", scripts.Script(path=Path("x.jsonl"), title="").project)

    def test_a_compact_plays_only_where_the_model_is_replayed(self):
        # A real model can't be made to fill its context on cue.
        s = scripts.load(scripts.find("context-wall"))
        self.assertIn("IN=simulated-claude-terminal", session.refusal(s, "claude", "desktop"))
        self.assertIsNone(session.refusal(s, "claude", "terminal"))
        self.assertIsNone(session.refusal(s, "codex", "terminal"))
        self.assertIn("no subagents", session.refusal(scripts.load(scripts.find("landing")), "codex", "terminal"))

    def test_the_demo_command_is_the_scripts_replies_in_order(self):
        s = scripts.load(scripts.find("landing"))
        text = desktop.script(s.replies(), s.title)
        main = [l for l in s.replies() if l.get("by") != "reviewer"]
        self.assertEqual(text.count("### Step "), len(main))
        said = [scripts.said(l) for l in main if scripts.said(l)]
        self.assertEqual(sorted(said, key=text.index), said, "the steps are out of order")
        # The reviewer doesn't see /demo: its part is in its own prompt.
        self.assertIn("This is part of a scripted demo: Run exactly `git diff`", text)


class GateTests(unittest.TestCase):
    STEPS = [
        {"n": 0, "agent": "prompt", "text": "Go"},
        {"n": 1, "agent": "read", "file": "src/a.js"},
        {"n": 2, "you": "poke"},
        {"n": 3, "agent": "run", "cmd": "npm test"},
        {"n": 4, "agent": "review", "task": "Review"},
        {"n": 5, "agent": "run", "cmd": "npm test"},
    ]

    def test_a_call_is_the_first_step_from_the_one_due_that_names_it(self):
        step = lambda call, since: gate.step_for(call, self.STEPS, since)
        self.assertEqual(step({"tool_name": "Read", "tool_input": {"file_path": "/ws/src/a.js"}}, 0), 1)
        self.assertEqual(step({"tool_name": "Bash", "tool_input": {"command": "npm test"}}, 0), 3)
        self.assertEqual(step({"tool_name": "Bash", "tool_input": {"command": "npm test"}}, 4), 5, "the second run")
        self.assertEqual(step({"tool_name": "Agent", "tool_input": {"prompt": "x"}}, 0), 4)
        self.assertIsNone(step({"tool_name": "Bash", "tool_input": {"command": "ls"}}, 0), "not in the script")

    def test_a_todo_is_the_agents_list_call(self):
        l = {"n": 6, "agent": "todo", "todos": "2/4"}
        self.assertEqual([t["status"] for t in scripts.todos(l)], ["completed", "completed", "in_progress", "pending"])
        self.assertEqual(gate.step_for({"tool_name": "TodoWrite", "tool_input": {}}, self.STEPS + [l], 0), 6)
        self.assertEqual(gate.step_for({"tool_name": "update_plan", "tool_input": {}}, self.STEPS + [l], 0), 6)
        name, args = model.claude_call(l, "/ws", ["TodoWrite"])
        self.assertEqual((name, len(args["todos"])), ("TodoWrite", 4))
        item = model.codex_item(l, "1")
        self.assertEqual(item["name"], "update_plan")
        self.assertEqual([p["status"] for p in json.loads(item["arguments"])["plan"]].count("completed"), 2)
        self.assertIn("TodoWrite", desktop.call_words(l))

    def test_it_holds_a_call_until_its_step_is_due(self):
        with tempfile.TemporaryDirectory() as d:
            path = write(Path(d), [json.dumps({k: v for k, v in l.items() if k != "n"}) for l in self.STEPS])
            cursor = Path(d) / "demo-cursor"
            cursor.write_text("0\n")
            run = subprocess.Popen([sys.executable, str(HERE.parent / "gate.py"), "--script", str(path), "--cursor", str(cursor)],
                                   stdin=subprocess.PIPE, text=True)
            run.stdin.write(json.dumps({"tool_name": "Bash", "tool_input": {"command": "npm test"}}))
            run.stdin.close()
            time.sleep(0.6)
            self.assertIsNone(run.poll(), "step 3 isn't due")
            cursor.write_text("3\n")
            self.assertEqual(run.wait(5), 0, "it lets the call run")
            self.assertIn("Bash: step 3, held", (Path(d) / "gate.log").read_text())

    def test_it_never_holds_for_good(self):
        with tempfile.TemporaryDirectory() as d:
            path = write(Path(d), ['{"agent": "prompt", "text": "Go"}', '{"agent": "run", "cmd": "make"}'])
            cursor = Path(d) / "demo-cursor"
            cursor.write_text("0\n")
            run = subprocess.run([sys.executable, str(HERE.parent / "gate.py"), "--script", str(path), "--cursor", str(cursor),
                                  "--patience", "0.5"], input='{"tool_name": "Bash", "tool_input": {"command": "make"}}',
                                 text=True, timeout=10)
            self.assertEqual(run.returncode, 0)
            self.assertIn("let it go", (Path(d) / "gate.log").read_text())


class ServerTests(unittest.TestCase):
    def setUp(self):
        model.SPEED = 1000
        self.addCleanup(setattr, model, "SPEED", 1.0)

    def serve(self, replies, due=lambda n: None):
        lines = []
        replay = model.Replay(replies, "/ws", lines.append, due=due, title="Shortcuts")
        server = model.start(replay)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return replay, f"http://127.0.0.1:{server.server_address[1]}", lines

    def test_claude_gets_tool_calls_then_text_and_a_title_costs_nothing(self):
        replay, url, _ = self.serve([
            {"n": 1, "agent": "run", "cmd": "npm test", "about": "Run the tests", "say": "Let me look."},
            {"n": 2, "agent": "reply", "text": "Done."},
        ])
        title = post(url + "/v1/messages", {"model": "haiku", "max_tokens": 50, "messages": [{"role": "user", "content": "name it"}]})
        self.assertEqual(title[0]["content"][0]["text"], "Shortcuts")
        self.assertEqual(replay.served, 0)
        turn = {"stream": True, "max_tokens": 1000, "tools": [{"name": "Read"}, {"name": "Bash"}],
                "messages": [{"role": "user", "content": "go"}]}
        events = post(url + "/v1/messages", turn)
        starts = [e["content_block"] for e in events if e["type"] == "content_block_start"]
        self.assertEqual([b["type"] for b in starts], ["text", "tool_use"])
        inputs = [json.loads(e["delta"]["partial_json"]) for e in events if e.get("delta", {}).get("type") == "input_json_delta"]
        self.assertEqual(inputs, [{"command": "npm test", "description": "Run the tests"}])
        self.assertEqual(model.claude_call({"agent": "read", "file": "src/a.js"}, "/ws", ["Read"]),
                         ("Read", {"file_path": "/ws/src/a.js"}))
        self.assertEqual([e for e in events if e["type"] == "message_delta"][0]["delta"]["stop_reason"], "tool_use")
        events = post(url + "/v1/messages", turn)
        text = "".join(e["delta"]["text"] for e in events if e.get("delta", {}).get("type") == "text_delta")
        self.assertEqual(text, "Done.")

    def test_a_reply_waits_for_its_step(self):
        due = threading.Event()
        asked = []
        replay, url, _ = self.serve([{"n": 7, "agent": "reply", "text": "Now."}], due=lambda n: (asked.append(n), due.wait(5)))
        got = []
        t = threading.Thread(target=lambda: got.append(post(url + "/v1/messages", {
            "stream": True, "tools": [{"name": "Read"}], "messages": [{"role": "user", "content": "go"}]})))
        t.start()
        time.sleep(0.3)
        self.assertEqual((asked, got), ([7], []), "held until step 7 is due")
        due.set()
        t.join(5)
        self.assertTrue(got)

    def test_codex_gets_shell_and_patch_items_and_a_title_costs_nothing(self):
        replay, url, _ = self.serve([{"n": 1, "agent": "run", "cmd": "npm run setup", "ask": 2, "about": "Install it"},
                                     {"n": 2, "agent": "edit", "file": "src/a.js", "old": "a", "new": "b"}])
        title = post(url + "/v1/responses", {"text": {"format": {"type": "json_schema"}}, "input": []})
        done = [e["item"] for e in title if e["type"] == "response.output_item.done"]
        self.assertEqual(json.loads(done[0]["content"][0]["text"]), {"title": "Shortcuts"})
        self.assertEqual(replay.served, 0)
        item = lambda: [e["item"] for e in post(url + "/v1/responses", {"input": [], "stream": True})
                        if e["type"] == "response.output_item.done"][0]
        run, edit = item(), item()
        args = json.loads(run["arguments"])
        self.assertEqual((run["name"], args["cmd"], args["sandbox_permissions"]), ("exec_command", "npm run setup", "require_escalated"))
        self.assertIn("*** Update File: src/a.js\n@@\n-a\n+b\n", edit["input"])

    # Claude Code's request for a summary when it compacts, as 2.1.282 words it.
    CLAUDE_SUMMARY = ("CRITICAL: Respond with TEXT ONLY. Do NOT call any tools.\n\nYour task is to create a detailed "
                      "summary of the conversation so far, paying close attention to the user's explicit requests")
    # Codex's, as 0.153.4 words it.
    CODEX_SUMMARY = "You are performing a CONTEXT CHECKPOINT COMPACTION. Create a handoff summary for another LLM"

    def test_claude_meets_a_full_context_then_gets_the_summary_then_goes_on(self):
        asked = []
        replay, url, _ = self.serve([
            {"n": 1, "agent": "edit", "file": "a.js", "old": "a", "new": "b"},
            {"n": 2, "agent": "compact", "summary": "The edit is in."},
            {"n": 3, "agent": "run", "cmd": "npm test", "say": "Now the tests."},
        ], due=asked.append)
        turn = {"stream": True, "max_tokens": 1000, "tools": [{"name": "Bash"}], "messages": [{"role": "user", "content": "go"}]}
        post(url + "/v1/messages", turn)
        # The request after the edit: the context is full, once the compact is due.
        with self.assertRaises(urllib.error.HTTPError) as wall:
            post(url + "/v1/messages", turn)
        self.assertEqual(wall.exception.code, 400)
        self.assertIn("prompt is too long", json.loads(wall.exception.read())["error"]["message"])
        self.assertEqual((asked, replay.served), ([1, 2], 2), "the compact was due, and is under way")
        summary = dict(turn, messages=[{"role": "user", "content": [{"type": "text", "text": self.CLAUDE_SUMMARY}]}])
        events = post(url + "/v1/messages", summary)
        text = "".join(e["delta"]["text"] for e in events if e.get("delta", {}).get("type") == "text_delta")
        self.assertIn("<summary>\nThe edit is in.\n</summary>", text)
        self.assertNotIn("tool_use", [e.get("content_block", {}).get("type") for e in events], "a summary is text only")
        self.assertEqual(replay.served, 2, "the summary is the compact's")
        events = post(url + "/v1/messages", turn)
        self.assertEqual([json.loads(e["delta"]["partial_json"]) for e in events if e.get("delta", {}).get("type") == "input_json_delta"],
                         [{"command": "npm test", "description": "npm test"}], "then the next step")

    def test_a_summary_the_script_has_no_compact_for_costs_nothing(self):
        replay, url, lines = self.serve([{"n": 1, "agent": "reply", "text": "Done."}])
        post(url + "/v1/messages", {"stream": True, "max_tokens": 1000, "tools": [{"name": "Bash"}],
                                    "messages": [{"role": "user", "content": self.CLAUDE_SUMMARY}]})
        self.assertEqual(replay.served, 0)
        self.assertIn("model: a summary the script has no compact for", lines)

    def test_an_agent_that_doesnt_compact_moves_the_script_on(self):
        replay, url, lines = self.serve([{"n": 1, "agent": "compact"}, {"n": 2, "agent": "reply", "text": "Done."}])
        self.assertEqual(replay.next()["n"], 2)
        self.assertIn("model: the agent didn't compact at step 1; going on", lines)

    def test_codex_hears_its_context_is_past_its_limit_then_gets_the_summary(self):
        replay, url, _ = self.serve([
            {"n": 1, "agent": "run", "cmd": "npm test"},
            {"n": 2, "agent": "compact", "summary": "The tests ran."},
            {"n": 3, "agent": "reply", "text": "Done."},
        ])
        usage = lambda events: [e["response"]["usage"] for e in events if e["type"] == "response.completed"][0]
        self.assertGreater(usage(post(url + "/v1/responses", {"input": [], "stream": True}))["total_tokens"],
                           model.CODEX_COMPACT_LIMIT, "the reply before the compact fills the context")
        summary = post(url + "/v1/responses", {"stream": True, "input": [
            {"type": "message", "role": "user", "content": [{"type": "input_text", "text": self.CODEX_SUMMARY}]}]})
        done = [e["item"] for e in summary if e["type"] == "response.output_item.done"]
        self.assertEqual([i["content"][0]["text"] for i in done], ["The tests ran."], "text only")
        self.assertLess(usage(summary)["total_tokens"], model.CODEX_COMPACT_LIMIT)
        self.assertEqual(replay.served, 2)

    def test_a_subagent_gets_its_own_replies(self):
        replay, url, _ = self.serve([
            {"n": 1, "agent": "review", "task": "Review", "prompt": "Review the diff", "say": "Sending a reviewer."},
            {"n": 2, "agent": "reply", "by": "reviewer", "text": "Looks good."},
            {"n": 3, "agent": "reply", "text": "I'll wait for it."},
        ])
        tools = [{"name": "Agent"}]
        post(url + "/v1/messages", {"stream": True, "tools": tools, "messages": [{"role": "user", "content": "go"}]})
        main = post(url + "/v1/messages", {"stream": True, "tools": tools, "messages": [{"role": "user", "content": "go"}]})
        sub = post(url + "/v1/messages", {"stream": True, "tools": tools, "messages": [{"role": "user", "content": [{"type": "text", "text": "Review the diff"}]}]})
        said = lambda events: "".join(e["delta"]["text"] for e in events if e.get("delta", {}).get("type") == "text_delta")
        self.assertEqual((said(main), said(sub)), ("I'll wait for it.", "Looks good."))



def play_project(case: unittest.TestCase, name: str, tests: str) -> list:
    """Plays a script's edits on a copy of its project, running `tests`
    with node at each `npm test` step: each run's exit code and last line."""
    s = scripts.load(scripts.find(name))
    with tempfile.TemporaryDirectory() as d:
        ws = Path(d) / "ws"
        shutil.copytree(SESSIONS / name / "workspace", ws)
        results = []
        for l in s.agent_steps():
            if l["agent"] == "edit":
                path = ws / l["file"]
                text = path.read_text()
                case.assertEqual(text.count(l["old"]), 1, f"line {l['number']}: old isn't there once")
                path.write_text(text.replace(l["old"], l["new"]))
            elif l.get("cmd") == "npm test":
                run = subprocess.run(["node", tests], cwd=ws, capture_output=True, text=True)
                results.append((run.returncode, run.stdout.strip().split("\n")[-1]))
        return results


@unittest.skipUnless(shutil.which("node"), "needs node")
class ProjectTests(unittest.TestCase):
    def test_landing_fails_one_then_passes(self):
        """The first version fails only the nested-editable test, and the
        fix passes them all."""
        self.assertEqual(play_project(self, "landing", "test/shortcuts.test.js"),
                         [(1, "5 passed, 1 failed"), (0, "6 passed, 0 failed")])

    def test_the_context_wall_fails_four_then_two_then_none(self):
        """The discount and tax tests fail, the discount edit leaves the
        two tax tests failing, and the tax edit passes them all."""
        self.assertEqual(play_project(self, "context-wall", "test/invoice.test.js"),
                         [(1, "2 passed, 4 failed"), (1, "4 passed, 2 failed"), (0, "6 passed, 0 failed")])


if __name__ == "__main__":
    unittest.main()
