"""The replay server: the model's side of a session, from a demo script.

It speaks the two APIs the agents call, streamed as the real ones stream:
Anthropic's Messages API (`/v1/messages`) for Claude Code and OpenAI's
Responses API (`/v1/responses`) for Codex, which take it as their base
URL. Each request the agent makes for its next turn gets the script's next
agent step, once the script has reached it, translated into that agent's
own tools; everything after, running the tools and firing the hooks, the
agent does for real.

Requests that aren't a turn of the session, such as an agent asking a
model for a title, get the script's title and don't use up a step.

A compact step is the context filling up, and the agent compacts it for
real. Claude Code compacts when the API says the prompt is too long: the
request after the step before gets that answer, once the compact is due.
Codex compacts when a reply says the context holds more tokens than its
limit (`CODEX_COMPACT_LIMIT`, which the session tool sets in its config):
the reply before the compact says so. Either then asks the model for a
summary of the conversation, which gets the step's `summary`, and goes on
with the next step.
"""
from __future__ import annotations

import itertools
import json
import os
import shlex
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable, Dict, List, Optional, Tuple

from script import said

# How fast a reply's text streams, in characters a second: about as fast
# as a fast model, and slow enough to read.
CHARS_PER_SECOND = 90.0
# Seconds before a reply's first word, as a model thinks.
THINK = 0.8
# How much faster than that it all goes: tests set it high.
SPEED = 1.0

# What an agent's request for a summary of the conversation says when it
# compacts it: Claude Code's, then Codex's.
SUMMARY_ASKS = ("create a detailed summary of the conversation", "CONTEXT CHECKPOINT COMPACTION")
# The summary when a compact step doesn't give one, or the agent compacts
# when the script has no compact.
SUMMARY = "The work so far is in the files. Go on with the task from where it was."
# Seconds an agent's compaction takes when its step doesn't say, as
# DemoScript's default.
COMPACTING = 2.0
# The tokens Codex's context may hold before it compacts. The reply before
# a compact says it holds more.
CODEX_COMPACT_LIMIT = 200_000
# The API's answer to a prompt longer than the model's context, which
# Claude Code meets by compacting the conversation.
TOO_LONG = {"type": "error", "error": {"type": "invalid_request_error",
                                       "message": "prompt is too long: 1000001 tokens > 1000000 maximum"}}


def claude_call(l: Dict[str, Any], workspace: str, tools: List[str]) -> Tuple[str, Dict[str, Any]]:
    """An agent step's tool call as Claude Code's: (name, input)."""
    path = lambda p: p if p.startswith("/") else f"{workspace}/{p}"
    does = l["agent"]
    if does == "read":
        return "Read", {"file_path": path(l["file"])}
    if does == "edit":
        return "Edit", {"file_path": path(l["file"]), "old_string": l["old"], "new_string": l["new"]}
    if does == "run":
        return "Bash", {"command": l["cmd"], "description": l.get("about", l["cmd"])}
    # A review: the subagent tool, as this Claude Code names it.
    name = "Task" if "Task" in tools and "Agent" not in tools else "Agent"
    return name, {"description": l["task"], "prompt": l.get("prompt", l["task"]), "subagent_type": "general-purpose"}


def codex_item(l: Dict[str, Any], cid: str) -> Optional[Dict[str, Any]]:
    """An agent step's tool call as Codex's output item: a shell command for
    reading and running, apply_patch for an edit. None for a review: Codex
    has no subagents here."""
    def shell(cmd: str, **extra: Any) -> Dict[str, Any]:
        # Waits for the command, as a model does for one it expects to take
        # a while: else Codex hands it back after 10 s, running.
        args = dict({"cmd": cmd, "yield_time_ms": 60000}, **extra)
        return {"type": "function_call", "id": "fc_" + cid, "call_id": "call_" + cid, "name": "exec_command",
                "arguments": json.dumps(args)}
    does = l["agent"]
    if does == "read":
        return shell(f"sed -n '1,200p' {shlex.quote(l['file'])}")
    if does == "run":
        extra = {"sandbox_permissions": "require_escalated", "justification": l.get("about", l["cmd"])} if "ask" in l else {}
        return shell(l["cmd"], **extra)
    if does == "edit":
        minus = "".join("-" + line + "\n" for line in l["old"].split("\n"))
        plus = "".join("+" + line + "\n" for line in l["new"].split("\n"))
        return {"type": "custom_tool_call", "id": "ct_" + cid, "call_id": "call_" + cid, "name": "apply_patch",
                "input": f"*** Begin Patch\n*** Update File: {l['file']}\n@@\n{minus}{plus}*** End Patch\n"}
    return None


class Replay:
    """The script's agent steps, handed out in order, each once the script
    has reached it (`due`), and a log of what was asked."""

    def __init__(self, steps: List[Dict[str, Any]], workspace: str, log: Callable[[str], None],
                 due: Callable[[int], Any] = lambda n: None, keep: Optional[str] = None, title: str = "A coding session"):
        # The main thread's turns, and a subagent's: a subagent runs beside
        # the main thread, so each has its own turn.
        self.queues = {"main": [l for l in steps if l.get("by") != "reviewer"],
                       "agent": [l for l in steps if l.get("by") == "reviewer"]}
        self.prompts = [l.get("prompt", l["task"]) for l in steps if l["agent"] == "review"]
        self.total = len(steps)
        self.served = 0
        self.workspace, self.log, self.due, self.keep, self.title = workspace, log, due, keep, title
        self.lock = threading.Lock()
        self.ids = itertools.count(1)

    def ident(self) -> str:
        return f"replay{next(self.ids):04d}"

    def kept(self, raw: bytes) -> None:
        """Keeps each request as it came, as requests/<id>.json, for when a
        script and an agent disagree."""
        if self.keep:
            os.makedirs(self.keep, exist_ok=True)
            with open(os.path.join(self.keep, f"{next(self.ids):04d}.json"), "wb") as f:
                f.write(raw)

    def thread(self, body: Dict[str, Any]) -> str:
        """Whose turn a request is: a subagent's starts with its prompt."""
        first = (body.get("messages") or [{}])[0].get("content", "")
        text = first if isinstance(first, str) else " ".join(b.get("text", "") for b in first if isinstance(b, dict))
        return "agent" if any(p in text for p in self.prompts) else "main"

    def next(self, thread: str = "main") -> Optional[Dict[str, Any]]:
        with self.lock:
            queue = self.queues[thread]
            # A turn where a compact is due: the agent went on without
            # compacting, so the script does too.
            while queue and queue[0]["agent"] == "compact":
                self.log(f"model: the agent didn't compact at step {queue[0]['n']}; going on")
                queue.pop(0)
                self.served += 1
            if not queue:
                self.log("model: the script has no more replies; ending the turn")
                return None
            step = queue.pop(0)
            self.served += 1
        self.due(step["n"])
        self.log(f"model: reply {self.served} of {self.total} (step {step['n']}, {thread})")
        return step

    def compacts_next(self) -> bool:
        """Whether the main thread's next step is a compact."""
        with self.lock:
            queue = self.queues["main"]
            return bool(queue) and queue[0]["agent"] == "compact"

    def wall(self) -> bool:
        """Whether this turn's request meets a full context: once, when the
        next step is a compact, after waiting until it's due."""
        with self.lock:
            queue = self.queues["main"]
            if not queue or queue[0]["agent"] != "compact" or queue[0].get("walled"):
                return False
            step = queue[0]
            step["walled"] = True
        self.due(step["n"])
        self.log(f"model: the context is full (step {step['n']})")
        return True

    def summary(self) -> Tuple[Optional[Dict[str, Any]], str]:
        """The answer to a request for a summary: the compact step due, if
        it's next, and its summary. One the script has no compact for
        costs no step."""
        with self.lock:
            queue = self.queues["main"]
            step = queue.pop(0) if queue and queue[0]["agent"] == "compact" else None
            if step:
                self.served += 1
        if not step:
            self.log("model: a summary the script has no compact for")
            return None, SUMMARY
        self.due(step["n"])
        self.log(f"model: the summary, reply {self.served} of {self.total} (step {step['n']})")
        return step, step.get("summary") or SUMMARY

    @staticmethod
    def wait(seconds: float) -> None:
        if seconds > 0:
            time.sleep(seconds / SPEED)

    @staticmethod
    def chunks(text: str) -> List[str]:
        """The text in a few words a chunk, as a model streams it."""
        words = text.split(" ")
        return [" ".join(words[i:i + 3]) + (" " if i + 3 < len(words) else "") for i in range(0, len(words), 3)]


def asks_for_summary(body: Dict[str, Any]) -> bool:
    """Whether a request is the agent asking for a summary of the
    conversation, to compact it: its last message, the person's, says so."""
    items = body.get("messages") or body.get("input") or []
    last = next((i for i in reversed(items) if isinstance(i, dict) and i.get("role") == "user"), {})
    content = last.get("content", "")
    text = content if isinstance(content, str) else " ".join(
        b.get("text", "") for b in content if isinstance(b, dict))
    return any(ask in text for ask in SUMMARY_ASKS)


def sse(handler: BaseHTTPRequestHandler, name: str, data: Dict[str, Any]) -> None:
    handler.wfile.write(f"event: {name}\ndata: {json.dumps(data)}\n\n".encode())
    handler.wfile.flush()


def serve_anthropic(h: BaseHTTPRequestHandler, replay: Replay, body: Dict[str, Any]) -> None:
    tools = [t.get("name") for t in body.get("tools") or []]
    model = body.get("model", "claude")
    # A turn of the session offers tools; a title or a probe doesn't.
    turn = bool(tools) and (body.get("max_tokens") or 2) > 1
    summary = asks_for_summary(body)
    if summary:
        step, words = replay.summary()
        # Claude Code keeps what's in the summary tags.
        text, calls = f"<analysis>\nWhere the work stands.\n</analysis>\n\n<summary>\n{words}\n</summary>", []
        pause = (step or {}).get("takes", COMPACTING)
    else:
        if turn and replay.thread(body) == "main" and replay.wall():
            data = json.dumps(TOO_LONG).encode()
            h.send_response(400); h.send_header("content-type", "application/json")
            h.send_header("content-length", str(len(data))); h.end_headers(); h.wfile.write(data)
            return
        step = replay.next(replay.thread(body)) if turn else None
        text = (said(step) or "") if step else replay.title
        calls = [claude_call(step, replay.workspace, tools)] if step and step["agent"] != "reply" else []
        pause = THINK if step else 0
    blocks: List[Tuple[str, Any]] = ([("text", text)] if text else []) + [("tool", c) for c in calls]
    stop = "tool_use" if calls else "end_turn"
    if not body.get("stream"):
        content = [{"type": "text", "text": text}] if text else []
        h.send_response(200); h.send_header("content-type", "application/json"); h.end_headers()
        h.wfile.write(json.dumps({"id": "msg_" + replay.ident(), "type": "message", "role": "assistant", "model": model,
                                  "content": content, "stop_reason": "end_turn", "stop_sequence": None,
                                  "usage": {"input_tokens": 100, "output_tokens": 10}}).encode())
        return
    h.send_response(200); h.send_header("content-type", "text/event-stream"); h.send_header("cache-control", "no-cache"); h.end_headers()
    sse(h, "message_start", {"type": "message_start", "message": {
        "id": "msg_" + replay.ident(), "type": "message", "role": "assistant", "model": model, "content": [],
        "stop_reason": None, "stop_sequence": None, "usage": {"input_tokens": 100, "output_tokens": 1}}})
    replay.wait(pause)
    for i, (kind, value) in enumerate(blocks):
        if kind == "text":
            sse(h, "content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "text", "text": ""}})
            # A summary, which nobody reads as it streams, comes at once.
            for piece in [value] if summary else replay.chunks(value):
                sse(h, "content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "text_delta", "text": piece}})
                replay.wait(len(piece) / CHARS_PER_SECOND)
        else:
            name, args = value
            sse(h, "content_block_start", {"type": "content_block_start", "index": i, "content_block": {
                "type": "tool_use", "id": "toolu_" + replay.ident(), "name": name, "input": {}}})
            sse(h, "content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps(args)}})
            replay.wait(0.3)
        sse(h, "content_block_stop", {"type": "content_block_stop", "index": i})
    sse(h, "message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 50}})
    sse(h, "message_stop", {"type": "message_stop"})


def serve_openai(h: BaseHTTPRequestHandler, replay: Replay, body: Dict[str, Any]) -> None:
    # A request for structured output, such as the thread's title, isn't a
    # turn of the session.
    tokens, summary = 100, False
    if (body.get("text") or {}).get("format"):
        step, text, pause = None, json.dumps({"title": replay.title}), 0.0
    elif asks_for_summary(body):
        (step, text), summary = replay.summary(), True
        pause = (step or {}).get("takes", COMPACTING)
    else:
        step = replay.next()
        text = (said(step) or "") if step else ""
        pause = THINK if step else 0.0
        # The reply before a compact fills the context past Codex's limit.
        if step and replay.compacts_next():
            tokens = CODEX_COMPACT_LIMIT + 1000
    item = codex_item(step, replay.ident()) if step and not summary and step["agent"] != "reply" else None
    rid = "resp_" + replay.ident()
    h.send_response(200); h.send_header("content-type", "text/event-stream"); h.send_header("cache-control", "no-cache"); h.end_headers()
    sse(h, "response.created", {"type": "response.created", "response": {"id": rid}})
    replay.wait(pause)
    index = 0
    if text:
        mid = "msg_" + replay.ident()
        message = {"type": "message", "id": mid, "role": "assistant", "content": [{"type": "output_text", "text": text}]}
        sse(h, "response.output_item.added", {"type": "response.output_item.added", "output_index": index,
                                              "item": dict(message, content=[])})
        for piece in [text] if summary else replay.chunks(text):
            sse(h, "response.output_text.delta", {"type": "response.output_text.delta", "item_id": mid, "output_index": index,
                                                  "content_index": 0, "delta": piece})
            replay.wait(len(piece) / CHARS_PER_SECOND)
        sse(h, "response.output_item.done", {"type": "response.output_item.done", "output_index": index, "item": message})
        index += 1
    if item:
        sse(h, "response.output_item.done", {"type": "response.output_item.done", "output_index": index, "item": item})
        replay.wait(0.3)
    sse(h, "response.completed", {"type": "response.completed", "response": {"id": rid, "usage": {
        "input_tokens": tokens, "input_tokens_details": None, "output_tokens": 50, "output_tokens_details": None,
        "total_tokens": tokens + 50}}})


def start(replay: Replay, port: int = 0) -> ThreadingHTTPServer:
    """Starts the server on 127.0.0.1 (a free port unless one is given), in
    a thread of its own. Its address is `server.server_address`."""

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args: Any) -> None:
            pass

        def do_GET(self) -> None:
            data = b"{}"
            self.send_response(200); self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)

        do_HEAD = do_GET

        def do_POST(self) -> None:
            raw = self.rfile.read(int(self.headers.get("content-length") or 0))
            replay.kept(raw)
            try:
                body = json.loads(raw or b"{}")
            except json.JSONDecodeError:
                body = {}
            # Streams end when the connection does.
            self.close_connection = True
            try:
                if "count_tokens" in self.path:
                    data = b'{"input_tokens": 100}'
                    self.send_response(200); self.send_header("content-type", "application/json")
                    self.send_header("content-length", str(len(data))); self.end_headers(); self.wfile.write(data)
                elif "/messages" in self.path:
                    serve_anthropic(self, replay, body)
                elif "/responses" in self.path:
                    serve_openai(self, replay, body)
                else:
                    replay.log(f"model: nothing serves POST {self.path}")
                    self.send_response(404); self.send_header("content-length", "0"); self.end_headers()
            except (BrokenPipeError, ConnectionResetError):
                replay.log("model: the agent hung up mid-reply")

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        def handle_error(self, request: Any, address: Any) -> None:
            replay.log("model: a connection broke")  # the agent hung up, or quit

    server = Server(("127.0.0.1", port), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server
