import AgentHooks
import Foundation
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// `boopdev replay` on the fixtures prints the expected `state` snapshots
/// and rules' one-shots.
final class ReplayTests: XCTestCase {
    /// Each snapshot as `+time base attn waiting`, e.g. `+3.0s idle claude/jetpack 1`,
    /// counting 1 + `attn.more` waiting, with `/act` after the base while
    /// there's one (`+2.0s working/terminal - 0`); each rule's one-shot as
    /// `+time name`, with its `ctx` (`+1.0s starting new_task`).
    func summary(_ fixture: String, agent: String) throws -> [String] {
        let path = HookFixtures.agentHooks.appendingPathComponent(fixture).path
        let lines = Replay(agent: agent).run(try Replay.steps(fromFile: path), statesOnly: true)
        return try lines.map { line in
            let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: Any])
            if parts[1] == "do" {
                let args = object["args"] as? [String: Any] ?? [:]
                XCTAssertNil(args["mood"], "a rule's one-shot has no face of the brain's")
                return ([parts[0], object["name"] as? String ?? "-"] + [args["ctx"] as? String].compactMap { $0 })
                    .joined(separator: " ")
            }
            XCTAssertEqual(parts[1], "state")
            let attn = object["attn"] as? [String: Any]
            let who = attn.map { "\($0["agent"]!)/\($0["project"]!)" } ?? "-"
            let waiting = attn.map { ($0["more"] as! Int) + 1 } ?? 0
            let look = (object["base"] as! String) + ((object["act"] as? String).map { "/" + $0 } ?? "")
            return "\(parts[0]) \(look) \(who) \(waiting)"
        }
    }

    /// Claude has no hook for the moment you approve, so
    /// "needs you" clears when the approved two-minute build finishes.
    /// The build shows as a terminal until "needs you"
    /// covers it, and nothing is left of it once it has finished.
    func testClaudePermissionShowsAtOnceAndClearsWhenTheApprovedToolFinishes() throws {
        let got = try summary("claude-code/synthetic/permission.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/terminal - 0",
            "+3.0s idle claude/jetpack 1",
            "+125.0s working - 0",
            "+526.0s idle - 0",
        ])
    }

    /// Two parallel subagents in one session; a1 waits on
    /// a permission prompt while a2 keeps reading and editing. "Needs you"
    /// stays until a1's call runs.
    /// The fixture's a2 starts an edit that never ends, which shows once
    /// the request clears; a1's command, which had no `tool_use_id`, ends
    /// its own call, not a2's.
    func testASiblingSubagentKeepsWorkingWhileOneWaits() throws {
        let got = try summary("claude-code/synthetic/subagents.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/terminal - 0",
            "+3.0s idle claude/landing 1",
            "+71.0s working/tool_use - 0",
            "+72.0s idle - 0",
        ])
    }

    /// Two parallel subagents; a1 asks and you deny it, and
    /// it ends without another tool call. a2's end leaves a1's request up,
    /// a1's own `SubagentStop` answers it while the main agent works on,
    /// and a subagent that ends after the turn leaves the session idle.
    /// With no `SubagentStart` in its hooks, the main agent's `Agent`
    /// calls show delegating, and the one that returns after the request
    /// clears plays helper_return; a1's denied command shows nothing more.
    func testADeniedSubagentsEndAnswersItsRequest() throws {
        let got = try summary("claude-code/synthetic/subagent-denied.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/delegating - 0",
            "+5.0s idle claude/landing 1",
            "+31.0s working/delegating - 0",
            "+32.0s helper_return",
            "+34.0s working/tool_use - 0",
            "+35.0s idle - 0",
        ])
    }

    /// The tests show as testing, then waiting while the reviewer looks,
    /// once testing has shown 1.5 s.
    func testCodexRequestItsReviewerHandlesNeverShows() throws {
        let got = try summary("codex/synthetic/approval-reviewed.jsonl", agent: "codex")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/testing - 0",
            "+4.5s working/waiting - 0",
            "+6.5s working - 0",
            "+25.5s idle - 0",
        ])
    }

    func testCodexRequestThatWaitsShowsAfterTwoSeconds() throws {
        let got = try summary("codex/synthetic/approval-asked.jsonl", agent: "codex")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/terminal - 0",
            "+5.0s idle codex/landing 1",
            "+14.0s working - 0",
            "+55.0s idle - 0",
        ])
    }

    /// One Claude session through every activity
    /// and every one-shot of the rules: plan mode, a read, a web search,
    /// a shell read, an edit, failing tests, a helper sent off and back, a
    /// build that goes quiet, Esc, then a resume and a new task.
    func testAClaudeSessionShowsEveryActivityAndOneShot() throws {
        let got = try summary("claude-code/synthetic/states.jsonl", agent: "claude")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting session",
            "+1.0s working/planning - 0",
            "+1.0s starting new_task",
            "+2.0s working/analyzing - 0",
            "+4.0s working/searching - 0",
            "+7.0s working/planning - 0",
            "+9.0s working - 0",
            "+11.0s working/analyzing - 0",
            "+14.0s working - 0",
            "+15.0s working/tool_use - 0",
            "+17.0s working/testing - 0",
            "+18.0s error",
            "+20.0s working/delegating - 0",
            "+23.0s helper_return",
            "+26.0s working/terminal - 0",
            "+46.0s working/waiting - 0",
            "+51.0s idle - 0",
            "+51.0s stopped",
            "+52.0s starting continuation",
            "+53.0s working - 0",
            "+53.0s starting new_task",
            "+54.0s idle - 0",
        ])
    }

    /// What a Codex session shows, its context compacted mid-turn
    /// included. Its hooks report no web search, helpers or failures, so
    /// none of those.
    func testACodexSessionShowsWhatItsHooksReport() throws {
        let got = try summary("codex/synthetic/states.jsonl", agent: "codex")
        XCTAssertEqual(got, [
            "+0.0s idle - 0",
            "+0.0s starting continuation",
            "+1.0s working - 0",
            "+1.0s starting new_task",
            "+2.0s working/analyzing - 0",
            "+4.0s starting compacted",
            "+5.0s working - 0",
            "+7.0s working/testing - 0",
            "+10.0s working/tool_use - 0",
            "+11.0s working/terminal - 0",
            "+32.0s working/waiting - 0",
            "+37.0s idle - 0",
            "+37.0s stopped",
        ])
    }

    func testRecordedClaudeSession() throws {
        let path = HookFixtures.agentHooks.appendingPathComponent("claude-code/2026-09-08/tenth-try.jsonl").path
        var replay = Replay(agent: "claude")
        replay.gapMs = 5000
        let lines = replay.run(try Replay.steps(fromFile: path))
        let effects = lines.filter { $0.hasPrefix("+") }.map { $0.split(separator: " ", maxSplits: 1)[1] }
        XCTAssertEqual(effects.filter { $0.hasPrefix("do ") }.map { $0.contains(#""name":"starting""#) }, [true, true],
                       "the rules play the starts; the finish is the brain's")
        XCTAssertTrue(effects.contains(#"view turn end · claude finished turn 1 on "fixture-project": done, a long turn, 10 tool calls. · Its last message: "PRIVATE_CLOSING_7182 fixed the failing tests""#), "\(effects)")
        let states = effects.filter { $0.hasPrefix("state") }
        XCTAssertEqual(states.filter { $0.contains(#""act":"testing""#) }.count, 10, "each of the ten test runs")
        let bases = states.compactMap { line -> String? in
            line.range(of: #""base":"[a-z]+""#, options: .regularExpression).map { String(line[$0]) }
        }
        XCTAssertEqual(bases.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } },
                       [#""base":"idle""#, #""base":"working""#, #""base":"idle""#])
        XCTAssertFalse(lines.joined().contains("PRIVATE_OUTPUT"), "no tool output")
    }

    /// The J1 fixtures carry boopctl e2e checkpoints; replay skips them and
    /// treats a clock jump as time passing.
    func testE2ECheckpointsAreSkipped() throws {
        let path = HookFixtures.e2e.appendingPathComponent("claude/session.jsonl").path
        let steps = try Replay.steps(fromFile: path)
        XCTAssertTrue(steps.contains(.advance(400_000)))
        let lines = Replay(agent: "claude").run(steps)
        XCTAssertFalse(lines.contains { $0.hasPrefix("# skipped") })
        XCTAssertTrue(lines.contains { $0.contains("view turn end") && $0.contains(": done, a ") })
        XCTAssertTrue(lines.contains { $0.contains(": failed, a ") })
        XCTAssertFalse(lines.contains { $0.contains(#"do {"name":"stopped""#) }, "a failed turn has no one-shot")
    }
}
