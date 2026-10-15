import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

final class AdapterTests: XCTestCase {
    func line(_ agent: String, _ hook: String, tool: String? = nil, topic: String? = nil, error: String? = nil,
              kind: String? = nil, cwd: String? = "/w/landing") -> HookLine {
        HookLine(agent: agent, hook: hook, session: "s1", cwd: cwd, tool: tool, topic: topic, error: error, kind: kind, ts: 7)
    }

    /// A hook's type and phase, as `turn end`, or nil for one ignored.
    func kind(_ agent: String, _ hook: String, kind k: String? = nil) -> String? {
        Adapter.event(from: line(agent, hook, kind: k)).map { e in e.type!.rawValue + (e.phase.map { " " + $0.rawValue } ?? "") }
    }

    func testClaudeMapping() {
        let table: [(String, String?)] = [
            ("SessionStart", "session start"), ("UserPromptSubmit", "turn start"), ("PreToolUse", "tool start"),
            ("PostToolUse", "tool end"), ("PostToolUseFailure", "tool end"), ("PermissionRequest", "tool wait"),
            ("Elicitation", "tool wait"), ("ElicitationResult", "tool end"), ("Stop", "turn end"),
            ("StopFailure", "turn end"), ("SessionEnd", "session end"), ("PreCompact", nil),
        ]
        for (hook, expected) in table {
            XCTAssertEqual(kind("claude", hook), expected, hook)
            if expected != nil { XCTAssertEqual(Adapter.event(from: line("claude", hook))?.specificType, hook) }
        }
        XCTAssertEqual(kind("claude", "Notification", kind: "permission_prompt"), "tool wait")
        XCTAssertEqual(kind("claude", "Notification", kind: "elicitation_dialog"), "tool wait")
        XCTAssertEqual(kind("claude", "Notification", kind: "idle_prompt"), "turn end", "sat at its prompt")
        XCTAssertEqual(Adapter.event(from: line("claude", "Notification", kind: "idle_prompt"))?["outcome"], "stopped")
        XCTAssertNil(kind("claude", "Notification"))
        var interrupted = line("claude", "PostToolUseFailure", tool: "Bash")
        interrupted.interrupt = true
        let stop = Adapter.event(from: interrupted)
        XCTAssertEqual(stop?.type, .turn, "Esc sends no Stop")
        XCTAssertEqual(stop?["outcome"], "stopped")
        XCTAssertEqual(stop?["tool"], "Bash", "an interrupted call keeps its tool")
        XCTAssertEqual(stop?.specificType, "PostToolUseFailure")
        XCTAssertNil(Adapter.event(from: line("claude", "Notification", kind: "idle_prompt"))?["tool"])
        XCTAssertEqual(Adapter.event(from: line("claude", "Stop"))?["outcome"], "done")
        XCTAssertEqual(Adapter.event(from: line("claude", "StopFailure"))?["outcome"], "failed")
        for hook in ["SubagentStart", "SubagentStop"] {
            XCTAssertNil(kind("claude", hook), "\(hook) names no subagent here")
        }
    }

    /// A `Notification` carries its type as `notice`.
    /// Claude's asking notices repeat a request its own hook makes, so the
    /// core can tell a late one from an `Elicitation`, which is a request
    /// of its own. A wait says what it's for.
    func testANotificationIsMarkedAsANotice() {
        for k in ["permission_prompt", "elicitation_dialog", "idle_prompt"] {
            XCTAssertEqual(Adapter.event(from: line("claude", "Notification", kind: k))?["notice"]?.string, k)
        }
        for hook in ["Elicitation", "PermissionRequest", "PreToolUse", "Stop"] {
            XCTAssertNil(Adapter.event(from: line("claude", hook, tool: hook == "PermissionRequest" ? "Bash" : nil))?["notice"],
                         hook)
        }
        XCTAssertEqual(Adapter.event(from: line("claude", "Notification", kind: "permission_prompt"))?.jsonLine,
                       #"{"seq":0,"at":7,"source":"claude","kind":"tool_wait","data":{"asking":"permission","cwd":"/w/landing","notice":"permission_prompt","session":"s1","specific_type":"Notification"}}"#)
        XCTAssertEqual(Adapter.event(from: line("claude", "Elicitation"))?["asking"], "input")
        XCTAssertEqual(Adapter.event(from: line("claude", "Notification", kind: "elicitation_dialog"))?["asking"], "input")
        XCTAssertEqual(Adapter.event(from: line("codex", "PermissionRequest", tool: "shell"))?["asking"], "permission")
    }

    /// Every event carries its thread's name, for the
    /// strip, the popover and a cheer.
    func testEveryEventCarriesItsThreadsName() {
        for (agent, hook) in [("claude", "PermissionRequest"), ("claude", "Notification"), ("codex", "PermissionRequest"),
                              ("claude", "UserPromptSubmit"), ("claude", "PreToolUse"), ("claude", "Stop"),
                              ("codex", "SessionStart"), ("codex", "PostToolUse")] {
            var l = line(agent, hook, tool: "Bash", kind: hook == "Notification" ? "permission_prompt" : nil)
            l.name = "Fix the hero image"
            XCTAssertEqual(Adapter.event(from: l)?["name"], "Fix the hero image", "\(agent) \(hook)")
        }
        XCTAssertNil(Adapter.event(from: line("claude", "Stop"))?["name"], "none found, none sent")
    }

    /// Every event carries the app its agent runs in,
    /// for opening the thread.
    func testEveryEventCarriesItsApp() {
        var l = line("claude", "PreToolUse", tool: "Bash")
        l.app = "com.anthropic.claudefordesktop"
        l.appSession = "local_1"
        let e = Adapter.event(from: l)
        XCTAssertEqual(e?["app"], "com.anthropic.claudefordesktop")
        XCTAssertEqual(e?["app_session"], "local_1")
        XCTAssertNil(Adapter.event(from: line("codex", "Stop"))?["app"], "none said, none sent")
    }

    /// A Claude subagent's id rides on the event; Codex
    /// has none.
    func testASubagentsEventsSayWhichSubagent() {
        var sub = line("claude", "PreToolUse", tool: "Read")
        sub.agentID = "a1"
        XCTAssertEqual(Adapter.event(from: sub)?.subagent, "a1")
        XCTAssertEqual(Adapter.event(from: sub)?.session, "s1", "the parent's session")
        XCTAssertTrue(Adapter.event(from: sub)?.jsonLine.contains(#""subagent":"a1""#) == true)
        XCTAssertNil(Adapter.event(from: line("claude", "PreToolUse", tool: "Read"))?.subagent)
        var codex = line("codex", "PreToolUse", tool: "shell")
        codex.agentID = "a1"
        XCTAssertNil(Adapter.event(from: codex)?.subagent)
    }

    /// `SubagentStop` becomes a `subagent` end with the
    /// subagent's `agent_id` and type. Without an `agent_id` it's ignored,
    /// since it would pass for the main agent. Codex has no subagents.
    func testSubagentStopSaysWhichSubagentEnded() throws {
        var stop = line("claude", "SubagentStop")
        stop.agentID = "a1"
        stop.agentType = "Explore"
        let event = try XCTUnwrap(Adapter.event(from: stop))
        XCTAssertEqual(event.jsonLine, #"{"seq":0,"at":7,"source":"claude","kind":"subagent_end","data":{"agent_type":"Explore","cwd":"/w/landing","session":"s1","specific_type":"SubagentStop","subagent":"a1"}}"#)
        XCTAssertEqual(event.summary, "subagent end SubagentStop claude s1 · agent_type Explore")
        XCTAssertNil(Adapter.event(from: line("claude", "SubagentStop")), "no agent_id")
        var codex = line("codex", "SubagentStop")
        codex.agentID = "a1"
        XCTAssertNil(Adapter.event(from: codex))
    }

    /// `SubagentStart` says which helper started, by its
    /// `agent_id`; one without it is ignored, and Codex has none.
    func testSubagentStartSaysWhichSubagentStarted() throws {
        var start = line("claude", "SubagentStart")
        start.agentID = "a1"
        start.agentType = "Explore"
        let event = try XCTUnwrap(Adapter.event(from: start))
        XCTAssertEqual(event.jsonLine, #"{"seq":0,"at":7,"source":"claude","kind":"subagent_start","data":{"agent_type":"Explore","cwd":"/w/landing","session":"s1","specific_type":"SubagentStart","subagent":"a1"}}"#)
        var codex = line("codex", "SubagentStart")
        codex.agentID = "a1"
        XCTAssertNil(Adapter.event(from: codex))
    }

    /// A session's start carries its `source`, Claude's
    /// and Codex's; Claude's events carry its permission mode as `mode`,
    /// which Codex's don't.
    func testSourceAndPermissionModeRideOnTheEvent() throws {
        for agent in ["claude", "codex"] {
            var start = line(agent, "SessionStart")
            start.source = "resume"
            XCTAssertEqual(Adapter.event(from: start)?["source"], "resume", agent)
            XCTAssertNil(Adapter.event(from: line(agent, "UserPromptSubmit"))?["source"], agent)
        }
        for hook in ["PreToolUse", "UserPromptSubmit", "Stop", "SessionStart"] {
            var claude = line("claude", hook, tool: hook == "PreToolUse" ? "Read" : nil)
            claude.mode = "plan"
            XCTAssertEqual(Adapter.event(from: claude)?["mode"], "plan", hook)
        }
        var codex = line("codex", "PreToolUse", tool: "shell")
        codex.mode = "plan"
        XCTAssertNil(Adapter.event(from: codex)?["mode"])
        XCTAssertNil(Adapter.event(from: line("claude", "Stop"))?["mode"], "none said, none sent")
    }

    func testCodexMapping() {
        let table: [(String, String?)] = [
            ("SessionStart", "session start"), ("UserPromptSubmit", "turn start"), ("PreToolUse", "tool start"),
            ("PostToolUse", "tool end"), ("PermissionRequest", "tool wait"), ("Stop", "turn end"),
            ("Interrupt", "turn end"), ("SessionEnd", "session end"), ("StopFailure", nil), ("Notification", nil),
        ]
        for (hook, expected) in table {
            XCTAssertEqual(kind("codex", hook), expected, hook)
        }
        XCTAssertEqual(Adapter.event(from: line("codex", "Stop"))?.agent, .codex)
        XCTAssertEqual(Adapter.event(from: line("codex", "Stop"))?.from, .codex)
        XCTAssertNil(Adapter.event(from: line("cursor", "Stop")))
    }

    func testDataCarriesToolTopicAndErrorClassOnly() throws {
        let start = try XCTUnwrap(Adapter.event(from: line("claude", "PreToolUse", tool: "Bash", topic: "tests")))
        XCTAssertEqual(start.fields, ["tool": "Bash", "topic": "tests"])
        let asking = try XCTUnwrap(Adapter.event(from: line("claude", "PermissionRequest", tool: "Bash")))
        XCTAssertEqual(asking.fields, ["tool": "Bash", "asking": "permission"])
        let failed = try XCTUnwrap(Adapter.event(from: line("claude", "StopFailure", error: "rate_limit")))
        XCTAssertEqual(failed["error"], "rate_limit")
        XCTAssertEqual(Adapter.event(from: line("claude", "StopFailure", error: "weird thing"))?["error"], "other")
        XCTAssertEqual(start.cwd, "/w/landing", "the view and the core name the place")
        XCTAssertEqual(start.ts, 7)
        XCTAssertEqual(Adapter.event(from: line("claude", "Stop"), receivedAt: 99)?.ts, 99)
    }

    /// What you asked and what the agent said last are the
    /// words that get through.
    func testPromptAndLastMessage() throws {
        var prompt = line("claude", "UserPromptSubmit")
        prompt.prompt = "fix the nav"
        XCTAssertEqual(Adapter.event(from: prompt)?["prompt"], "fix the nav")
        var stop = line("codex", "Stop")
        stop.message = "Fixed it."
        XCTAssertEqual(Adapter.event(from: stop)?.fields, ["outcome": "done", "message": "Fixed it."])
    }

    /// Every `error` Claude's StopFailure can carry maps to
    /// a class the brain can make sense of.
    func testClaudesErrorsMapToTheirClasses() {
        let classes = [
            "rate_limit": "rate_limit", "overloaded": "overloaded", "server_error": "api_error",
            "invalid_request": "api_error", "model_not_found": "api_error", "max_output_tokens": "context_limit",
            "authentication_failed": "auth", "oauth_org_not_allowed": "auth", "account_on_hold": "auth",
            "verification_required": "auth", "cloud_credential_error": "auth", "billing_error": "billing",
            "unknown": "other",
        ]
        for (error, expected) in classes {
            XCTAssertEqual(Adapter.event(from: line("claude", "StopFailure", error: error))?["error"]?.string, expected, error)
        }
        XCTAssertEqual(Mapping.errorClass("Request timeout"), "timeout", "other text by what it contains")
    }

    /// Claude's PostToolUse and PostToolUseFailure say
    /// whether the call failed; an interrupted call and Codex say nothing.
    func testClaudeSaysWhetherACallFailed() throws {
        func failed(_ agent: String, _ hook: String, interrupt: Bool = false) -> Bool? {
            var l = line(agent, hook, tool: "Bash", topic: "tests")
            l.interrupt = interrupt
            return Adapter.event(from: l)?["failed"]?.bool
        }
        XCTAssertEqual(failed("claude", "PostToolUse"), false)
        XCTAssertEqual(failed("claude", "PostToolUseFailure"), true)
        XCTAssertNil(failed("claude", "PostToolUseFailure", interrupt: true))
        XCTAssertNil(failed("claude", "PreToolUse"))
        XCTAssertNil(failed("codex", "PostToolUse"))
        let event = try XCTUnwrap(Adapter.event(from: line("claude", "PostToolUseFailure", tool: "Bash", topic: "tests")))
        XCTAssertEqual(event.type, .tool)
        XCTAssertEqual(event.fields, ["error": "other", "failed": true, "tool": "Bash", "topic": "tests"], event.jsonLine)
    }

    /// An adapter output, as one JSON line, and how it reads back.
    func testEventJSONShape() throws {
        let line = HookLine(agent: "claude", hook: "PreToolUse", session: "a1b2", cwd: "/Users/me/src/landing",
                            tool: "Bash", topic: "tests", toolUseID: "toolu_1", ts: 1_790_000_000_123)
        var event = try XCTUnwrap(Adapter.event(from: line))
        event.seq = 102
        XCTAssertEqual(event.jsonLine, #"{"seq":102,"at":1790000000123,"source":"claude","kind":"tool_start","data":{"cwd":"/Users/me/src/landing","session":"a1b2","specific_type":"PreToolUse","tool":"Bash","tool_use_id":"toolu_1","topic":"tests"}}"#)
        XCTAssertEqual(Event(jsonLine: event.jsonLine), event, "it reads back")
    }

    func testRecordedClaudeSessionMapsInOrder() throws {
        let file = HookFixtures.agentHooks.appendingPathComponent("claude-code/2026-09-08/tenth-try.jsonl")
        let events = try String(contentsOf: file, encoding: .utf8).split(separator: "\n").compactMap { raw in
            HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0).flatMap { Adapter.event(from: $0) }
        }
        XCTAssertEqual(events.first?.type, .session)
        XCTAssertEqual(events[1].type, .turn)
        XCTAssertEqual(events[1].phase, .start)
        XCTAssertEqual(events.last?.type, .turn)
        XCTAssertEqual(events.last?.phase, .end)
        XCTAssertTrue(events.dropFirst(2).dropLast().allSatisfy { $0.type == .tool })
        XCTAssertEqual(events.filter { $0["topic"] == "tests" }.count, 10)
        XCTAssertTrue(events.allSatisfy { $0.cwd == "/tmp/fixture-project" && $0.session == "fixture-claude-code" })
        // Your prompt and the agent's last message are the only words kept.
        let text = events.map(\.jsonLine).joined()
        XCTAssertEqual(text.components(separatedBy: "PRIVATE").count - 1,
                       events.filter { $0["prompt"] != nil || $0["message"] != nil }.count, text)

        let failures = try String(contentsOf: HookFixtures.agentHooks.appendingPathComponent("claude-code/2026-09-08/rate-limit.jsonl"), encoding: .utf8)
            .split(separator: "\n").compactMap { raw in
                HookLine.extract(agent: "claude", payload: Data(raw.utf8), ts: 0).flatMap { Adapter.event(from: $0) }
            }
        XCTAssertEqual(failures.map { $0["outcome"]?.string ?? $0.type!.rawValue }, ["session", "failed", "failed", "failed"])
        XCTAssertEqual(failures[1]["error"], "rate_limit")
    }

    func testRecordedCodexSessionStart() throws {
        let data = try Data(contentsOf: HookFixtures.agentHooks.appendingPathComponent("codex/2026-09-08/SessionStart-1.json"))
        let event = try XCTUnwrap(HookLine.extract(agent: "codex", payload: data, ts: 0).flatMap { Adapter.event(from: $0) })
        XCTAssertEqual(event.type, .session)
        XCTAssertEqual(event.agent, .codex)
        XCTAssertEqual(event.session, "abc123")
        XCTAssertEqual(event.cwd.map { Place.at(cwd: $0).project }, "project")
    }

    /// A failed call keeps its error class and ID; Codex's `Interrupt` stops
    /// the turn; a subagent's type comes through.
    func testToolErrorIDsInterruptsAndSubagentTypes() throws {
        var failure = line("claude", "PostToolUseFailure", tool: "Bash", topic: "tests")
        failure.toolError = "timeout"
        failure.toolUseID = "toolu_1"
        let event = try XCTUnwrap(Adapter.event(from: failure))
        XCTAssertEqual(event["error"], "timeout")
        XCTAssertEqual(event["tool_use_id"], "toolu_1")
        XCTAssertEqual(Adapter.event(from: line("claude", "PostToolUseFailure", tool: "Bash"))?["error"], "other")
        XCTAssertEqual(Adapter.event(from: line("codex", "Interrupt"))?["outcome"], "stopped")
        var sub = line("claude", "PreToolUse", tool: "Read")
        sub.agentID = "a1"
        sub.agentType = "Explore"
        XCTAssertEqual(Adapter.event(from: sub)?["agent_type"], "Explore")
    }

    /// The transcript keeps every fact of an agent's event,
    /// so a launch that folds the sessions again from it reads back the
    /// same event.
    func testAnAgentEventReadsBackWholeFromTheTranscript() throws {
        let full = AgentEvent(agent: .claude, kind: .tool, phase: .wait, hook: "PermissionRequest", session: "s1", at: 7,
                              subagent: "a1", subagentType: "Explore", cwd: "/w/landing", name: "Fix the nav",
                              app: "com.anthropic.claudefordesktop", appSession: "local_1", mode: "plan", source: "startup",
                              prompt: "Run the tests", tool: "Bash", toolUseID: "toolu_1", topic: "tests", failed: true,
                              error: "timeout", asking: .input, notice: "elicitation_dialog", outcome: .stopped,
                              message: "Done.")
        var event = Event(full)
        event.seq = 3
        let read = try XCTUnwrap(Event(jsonLine: event.jsonLine))
        XCTAssertEqual(AgentEvent(read), full)
        XCTAssertNil(read["for"], "`for` is the seq an event answers, MellowHarness's `about`")
    }

    /// Older transcripts kept what a request asks for under `for`: a
    /// string there still reads as it, and a seq there isn't one.
    func testAnOlderTranscriptsStringForReadsAsAsking() throws {
        let older = Event(ts: 1, source: .claude, type: .tool, phase: .wait, specificType: "PermissionRequest",
                          session: "b1", data: ["for": "permission", "tool": "Bash"])
        let read = try XCTUnwrap(AgentEvent(try XCTUnwrap(Event(jsonLine: older.jsonLine))))
        XCTAssertEqual(read.asking, .permission)
        let answering = Event(ts: 1, source: .claude, type: .tool, phase: .wait, specificType: "PermissionRequest",
                              session: "s", data: ["for": 3])
        let answers = try XCTUnwrap(AgentEvent(answering))
        XCTAssertNil(answers.asking)
    }

    /// Boop's installer counts the entries Boop wrote before
    /// agent-hooks as its own, so the first launch's repair replaces them
    /// with `agent-hook … --keep-text`, and leaves everyone else's alone.
    func testTheFirstLaunchReplacesBoopHookEntries() throws {
        let home = tempDir("migrate")
        let fm = FileManager.default
        let hook = home.appendingPathComponent("Boop/bin/agent-hook")
        try fm.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: hook.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let old = #""/Users/me/Library/Application Support/Boop/bin/boop-hook" claude"#
        let older = "~/.boop/boop-hook.sh claude"
        let theirs = "/usr/local/bin/other-tool --hook"
        let settings: [String: Any] = ["hooks": [
            "Stop": [["hooks": [["type": "command", "command": old, "timeout": 5], ["type": "command", "command": theirs]]]],
            "PreToolUse": [["hooks": [["type": "command", "command": older]]]],
        ]]
        let url = home.appendingPathComponent(".claude/settings.json")
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: settings).write(to: url)

        let installer = HookInstaller.boop(home: home, hookPath: hook.path)
        XCTAssertEqual(installer.health(.claude), .outdated)
        XCTAssertEqual(installer.repair(), [.claude])
        XCTAssertEqual(installer.health(.claude), .installed)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let groups = (root["hooks"] as? [String: Any] ?? [:]).values.flatMap { $0 as? [[String: Any]] ?? [] }
        let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
        XCTAssertEqual(Set(commands), [installer.command(.claude), theirs])
        XCTAssertEqual(commands.filter { $0 == installer.command(.claude) }.count, Mapping.claude.count)
        XCTAssertTrue(installer.command(.claude).hasSuffix(" claude --keep-text"), installer.command(.claude))
    }
}

final class Received: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [HookLine] = []
    func add(_ line: HookLine) { lock.withLock { stored.append(line) } }
    var lines: [HookLine] { lock.withLock { stored } }
    var count: Int { lines.count }

}

/// Hook payloads: the Claude and Codex recordings agent-hooks keeps
/// (agent-hooks/Tests/AgentHooksTests/Fixtures), and Boop's pipeline check's
/// own sessions (Fixtures/hooks/e2e, VERIFICATION.md L4).
enum HookFixtures {
    static let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let agentHooks = here.appendingPathComponent("../../../agent-hooks/Tests/AgentHooksTests/Fixtures").standardized
    static let e2e = here.appendingPathComponent("Fixtures/hooks/e2e")
}
