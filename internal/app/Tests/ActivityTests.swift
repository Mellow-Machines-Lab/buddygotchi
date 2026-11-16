import AgentHooks
import Foundation
import LinkKit
import XCTest
@testable import BoopKit

extension CoreRig {
    /// Moves the clock `ms` and ticks once, as the app's 1 s tick would
    /// then.
    @discardableResult
    func tick(after ms: Int64) -> Fx {
        now += ms
        return note(Fx(pipeline.tick(at: now)))
    }

    /// What the working look shows now: `state.act`.
    var act: String? { state.activity }
}

// MARK: - What the agents are doing

final class CoreActivityTests: XCTestCase {

    /// A running call shows what it does, in working's place, one of four:
    /// running (`terminal` on the wire), looking (`analyzing`), typing
    /// (`tool_use`) or waiting. Its tool and topic decide.
    func testEachCallShowsWhatItDoes() {
        let running = "terminal", looking = "analyzing", typing = "tool_use"
        let cases: [(Agent, String, String?, String)] = [
            (.claude, "Bash", nil, running), (.claude, "Bash", "build", running),
            (.claude, "Bash", "deploy", running), (.claude, "Bash", "tests", running),
            (.claude, "Task", nil, running), (.claude, "Agent", nil, running),
            (.claude, "Bash", "inspect", looking), (.claude, "Read", nil, looking),
            (.claude, "Grep", nil, looking), (.claude, "Glob", nil, looking),
            (.claude, "LS", nil, looking), (.claude, "WebSearch", nil, looking),
            (.claude, "WebFetch", nil, looking), (.claude, "Edit", "docs", typing),
            (.claude, "Write", nil, typing), (.claude, "NotebookEdit", nil, typing),
            (.claude, "mcp__github__create_pr", nil, typing), (.claude, "Skill", nil, typing),
            (.claude, "TodoWrite", nil, typing), (.claude, "ExitPlanMode", nil, typing),
            (.codex, "shell", nil, running), (.codex, "exec_command", "tests", running),
            (.codex, "local_shell", "inspect", looking), (.codex, "apply_patch", nil, typing),
            (.codex, "update_plan", nil, typing),
        ]
        for (agent, tool, topic, act) in cases {
            let rig = CoreRig()
            rig.send(.turnStart, agent)
            let fx = rig.send(.activity, agent, tool: tool, topic: topic)
            XCTAssertEqual(states(fx).last?.activity, act, "\(tool) \(topic ?? "")")
            XCTAssertEqual(rig.state.visual, act, tool)
            XCTAssertEqual(rig.state.doing, "working", "\(tool): the base stays working")
        }
    }

    /// `act` goes out only while `base` is `working` and
    /// nothing needs you. The device picks the look's variation itself.
    func testTheActivityShowsOnlyInTheWorkingLook() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.send(.turnStart)
        let fx = rig.send(.activity, tool: "Bash", id: "b")
        let line = states(fx).last!.jsonLine
        let when = rig.state.when.map { "\"\($0)\"" }.joined(separator: ",")
        XCTAssertEqual(line, #"{"t":"state","base":"working","act":"terminal","mood":"calm","busy":1,"vol":6,"when":["# + when + "]}")
        rig.send(.needsYou, tool: "Bash")
        XCTAssertNil(rig.act, "needs you covers it")
        XCTAssertEqual(rig.state.visual, "needs_you")
        rig.send(.turnStart, session: "b")
        rig.send(.activity, session: "b", tool: "Read", id: "r")
        XCTAssertEqual(rig.state.doing, "working")
        XCTAssertNil(rig.act, "another session's read too, while something needs you")
        rig.send(.turnEnd, session: "b")
        rig.wait(30_000)
        rig.send(.activity, tool: "Bash", id: "b", done: true)
        XCTAssertNil(rig.state.attn, "you approved: it ran")
        XCTAssertNil(rig.act, "and nothing is left of it once it has ended")
        XCTAssertEqual(rig.state.visual, "working")
        rig.send(.activity, tool: "Read", id: "r")
        rig.send(.turnEnd)
        XCTAssertNil(rig.act, "idle has none")
        XCTAssertEqual(rig.state.visual, "idle")
        XCTAssertFalse(rig.log.contains { if case .state(let s) = $0 { s.activity != nil && s.doing != "working" } else { false } })
    }

    /// Pins the four activities, their wire names and their order: with
    /// several calls running the highest shows, running > looking > typing
    /// > waiting; a higher one at once, and a lower one only once the one
    /// showing is its hold past its last call: 3 s for running and looking
    /// (`Core.poseHoldMs`), 1.5 s for typing (`Core.actHoldMs`).
    func testTheHighestActivityShows() {
        XCTAssertEqual(Act.allCases, [.running, .looking, .typing, .waiting])
        XCTAssertEqual(Act.allCases.map(\.rawValue), ["terminal", "analyzing", "tool_use", "waiting"])
        XCTAssertEqual(Act.allCases.map(\.holdMs), [3000, 3000, 1500, 1500])
        let rig = CoreRig()
        rig.send(.turnStart, mode: "plan")
        XCTAssertEqual(rig.act, "tool_use", "plan mode, nothing running: typing")
        let climb: [(tool: String, act: Act)] = [("Edit", .typing), ("Read", .looking), ("Bash", .running)]
        for (n, call) in climb.enumerated() {
            rig.send(.activity, tool: call.tool, id: "c\(n)", mode: "plan")
            XCTAssertEqual(rig.act, call.act.rawValue, "\(call.tool): at once")
        }
        for n in climb.indices.reversed() {
            let act = climb[n].act
            rig.send(.activity, tool: climb[n].tool, id: "c\(n)", done: true)
            XCTAssertEqual(rig.act, act.rawValue, "\(act) ended, and holds")
            rig.tick(after: act.holdMs - 1)
            XCTAssertEqual(rig.act, act.rawValue, "\(act): still")
            rig.tick(after: 1)
            XCTAssertEqual(rig.act, n > 0 ? climb[n - 1].act.rawValue : "tool_use", "then the next one down")
        }
    }

    /// Looking shows at least 3 s (`Core.poseHoldMs`) after its last call
    /// ends, so a burst of quick reads is one stretch of looking, not a
    /// flicker, and reads between edits don't rock the body back and
    /// forth; then plain working.
    func testABurstOfQuickCallsIsOneStretch() {
        XCTAssertEqual(Core.actHoldMs, 1500)
        XCTAssertEqual(Core.poseHoldMs, 3000)
        let rig = CoreRig()
        rig.send(.turnStart)
        var acts: [String?] = []
        func note(_ fx: Fx) { acts += states(fx).map(\.activity) }
        for n in 0..<8 {  // a read of 50 ms, then an edit of 50 ms, every 1.2 s
            for (tool, id) in [("Read", "r\(n)"), ("Edit", "e\(n)")] {
                note(rig.send(.activity, tool: tool, id: id))
                rig.now += 50
                note(rig.send(.activity, tool: tool, id: id, done: true))
                note(rig.tick(after: 550))
            }
        }
        XCTAssertEqual(acts, ["analyzing"], "one stretch")
        note(rig.tick(after: Core.poseHoldMs - 1150 - 1))
        XCTAssertEqual(rig.act, "analyzing", "3 s after the last read")
        note(rig.tick(after: 1))
        XCTAssertEqual(acts, ["analyzing", nil])
        XCTAssertEqual(rig.state.visual, "working")
    }

    /// A lower activity doesn't cut a higher one short.
    /// A command that starts during a read shows at once; when it ends it
    /// holds 3 s, then the read still running shows again.
    func testAHigherActivityShowsAtOnceAndHolds() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Read", id: "r")
        rig.now += 100
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", id: "b")).last?.activity, "terminal")
        rig.now += 100
        rig.send(.activity, tool: "Bash", id: "b", done: true)
        rig.tick(after: 2999)
        XCTAssertEqual(rig.act, "terminal")
        rig.tick(after: 1)
        XCTAssertEqual(rig.act, "analyzing")
    }

    /// A call running with nothing heard from its session
    /// for 20 s (`Core.waitingMs`) shows as waiting, until the session is
    /// heard from again. A helper at work never does: it isn't the
    /// machine.
    func testALongQuietCallShowsWaiting() {
        XCTAssertEqual(Core.waitingMs, 20_000)
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", topic: "tests", id: "t")
        rig.wait(19_000)
        XCTAssertEqual(rig.act, "terminal")
        rig.wait(4000)
        XCTAssertEqual(rig.act, "waiting", "20 s quiet, then running's 3 s")
        rig.send(.activity, subagent: "a1", tool: "Read", id: "r")
        XCTAssertEqual(rig.act, "terminal", "heard from again")

        let helper = CoreRig()
        helper.send(.turnStart)
        helper.send(.activity, tool: "Agent", id: "A")
        helper.send(.activity, subagent: "a1", tool: "Bash", id: "b")
        helper.wait(60_000)
        XCTAssertEqual(helper.act, "terminal", "the helper's command waits; the helper works")

        let plan = CoreRig()
        plan.send(.turnStart, mode: "plan")
        plan.send(.activity, tool: "Read", id: "r", mode: "plan")
        plan.wait(24_000)
        XCTAssertEqual(plan.act, "waiting", "plan mode doesn't hide a call gone quiet")
    }

    /// Plan mode is typing, with no call running: from Claude's plan mode
    /// (from any event that says it) or a planning call; never from the
    /// gap between a prompt and the first call.
    func testPlanModeTypesWhileNothingRuns() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(10_000)
        XCTAssertNil(rig.act, "a prompt and no call yet: plain working")
        rig.send(.activity, tool: "Read", id: "r", mode: "plan")
        XCTAssertEqual(rig.act, "analyzing", "a call shows over plan mode")
        rig.send(.activity, tool: "Read", id: "r", done: true, mode: "plan")
        rig.wait(4000)
        XCTAssertEqual(rig.act, "tool_use")
        rig.send(.activity, tool: "Edit", id: "e", mode: "acceptEdits")
        XCTAssertEqual(rig.act, "tool_use")
        rig.send(.activity, tool: "Edit", id: "e", done: true)
        rig.wait(2000)
        XCTAssertNil(rig.act, "out of plan mode; an event without a mode leaves it as it was")
        rig.send(.activity, tool: "TodoWrite", id: "t")
        XCTAssertEqual(rig.act, "tool_use", "a planning call")
    }

    /// Running from the main agent's `Task` or `Agent`
    /// call until it ends, or while a helper Boop saw start
    /// (`SubagentStart`) hasn't ended; never from a helper's end or its
    /// call alone. A helper's start isn't activity: it wakes no idle
    /// session.
    func testRunningLastsWhileAHelperWorks() {
        let rig = CoreRig()
        rig.send(.turnStart)
        for (call, helper) in [("A1", "h1"), ("A2", "h2")] {  // background helpers: their calls return at once
            rig.send(.activity, tool: "Agent", id: call)
            rig.send(.subagentStart, subagent: helper)
            rig.send(.activity, tool: "Agent", id: call, done: true)
        }
        rig.wait(5000)
        XCTAssertEqual(rig.act, "terminal")
        rig.send(.activity, subagent: "h1", tool: "Read", id: "h1r")
        XCTAssertEqual(rig.act, "terminal", "it outranks a helper's read")
        rig.send(.subagentEnd, subagent: "h1")
        rig.wait(5000)
        XCTAssertEqual(rig.act, "terminal", "h2 still works")
        rig.send(.subagentEnd, subagent: "h2")
        rig.wait(4000)
        XCTAssertNil(rig.act)

        let other = CoreRig()
        other.send(.turnStart)
        other.send(.subagentEnd, subagent: "x")
        XCTAssertNil(other.act, "an end alone")
        other.send(.activity, subagent: "y", tool: "Read", id: "y1")
        XCTAssertEqual(other.act, "analyzing", "a subagent first seen by its call shows the call")

        let idle = CoreRig()
        idle.send(.sessionStart)
        XCTAssertEqual(states(idle.send(.subagentStart, subagent: "z")), [], "not activity")
        XCTAssertEqual(idle.state.doing, "idle")
    }

    /// A subagent that ended runs nothing more: its calls go with it, as
    /// they do when the turn ends.
    func testAHelpersCallsEndWithIt() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.subagentStart, subagent: "h")
        rig.send(.activity, subagent: "h", tool: "Read", id: "hr")
        XCTAssertEqual(rig.act, "terminal", "a helper at work")
        rig.send(.subagentEnd, subagent: "h")
        rig.wait(4000)
        XCTAssertNil(rig.act, "its read went with it")

        rig.send(.activity, tool: "Bash", id: "lost")
        rig.send(.turnEnd)
        rig.send(.turnStart)
        XCTAssertNil(rig.act, "a call whose end never came is over with its turn")
    }

    /// A call you deny sends no hook, and the agent moving
    /// on answers the request; the denied call shows nothing more.
    func testADeniedCallShowsNothingMore() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", id: "b")
        rig.send(.needsYou, tool: "Bash")
        rig.wait(5000)
        rig.send(.activity, tool: "Read", id: "r")
        XCTAssertNil(rig.state.attn, "moved on")
        rig.send(.activity, tool: "Read", id: "r", done: true)
        rig.wait(4000)
        XCTAssertNil(rig.act, "not the denied command")

        rig.send(.activity, subagent: "a1", tool: "Bash", id: "s")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.subagentEnd, subagent: "a1")
        rig.wait(4000)
        XCTAssertNil(rig.act, "a denied subagent ends, and its command with it")
    }

    /// With several sessions working, the one heard from
    /// last shows what it's doing, among those doing something, once the
    /// activity showing has shown its hold.
    func testTheSessionHeardFromLastPicksTheActivity() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.send(.activity, session: "a", tool: "Bash", topic: "tests", id: "t")
        XCTAssertEqual(rig.act, "terminal")
        rig.now += 500
        rig.send(.activity, session: "b", tool: "Read", id: "r")
        XCTAssertEqual(rig.act, "terminal", "running has shown only 0.5 s")
        rig.tick(after: 2500)
        XCTAssertEqual(rig.act, "analyzing", "b was heard from last")
        rig.send(.activity, session: "b", tool: "Read", id: "r", done: true)
        rig.wait(4000)
        XCTAssertEqual(rig.act, "terminal", "b is doing nothing now; a is")
        rig.send(.activity, session: "a", tool: "Bash", id: "t", done: true)
        rig.wait(4000)
        XCTAssertNil(rig.act)
        XCTAssertEqual(rig.state.working, 2)
    }
}

// MARK: - The rules' reactions

final class CoreRuleReactionTests: XCTestCase {
    /// A session or a turn starting plays no reaction of the rules': the
    /// look changes, and the work stream's first word says the rest.
    func testAStartPlaysNoRuleReaction() {
        for source in ["startup", "clear", "resume", "compact", nil] {
            XCTAssertEqual(reactionNames(CoreRig().send(.sessionStart, source: source)), [], source ?? "no source")
        }
        let rig = CoreRig()
        let fx = rig.send(.turnStart)
        XCTAssertEqual(moments(fx).map { "\($0.name) \($0.args)" }, [#"react {"reason":"claude woke Boop"}"#], "only the caption for why it woke")
        XCTAssertEqual(fx.effects.firstIndex { if case .state = $0 { true } else { false } }, 0, "the look")
    }

    /// An interrupt that ends a turn stops it, which reaches the brain
    /// (no rule reaction plays): Esc on a call, Claude's idle notice after
    /// Esc between calls, or Codex's `Interrupt`. The idle notice after a
    /// turn that finished, or one from before the last prompt, ends nothing.
    func testAnInterruptStopsTheTurn() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", id: "b")
        let esc = rig.send(.turnStopped, tool: "Bash")
        XCTAssertEqual(finished(esc), ["stopped"])
        XCTAssertEqual(reactionNames(esc), [], "the stream and the brain have it")
        rig.wait(61_000)
        XCTAssertEqual(finished(rig.send(.turnStopped, notice: true)), [], "the notice after it: the turn is over")
        rig.send(.turnStart)
        rig.wait(10_000)
        XCTAssertEqual(finished(rig.send(.turnStopped, notice: true)), [], "from before the prompt")
        rig.wait(60_000)
        XCTAssertEqual(finished(rig.send(.turnStopped, notice: true)), ["stopped"], "Esc between calls, a minute on")
        rig.send(.turnStart)
        rig.wait(5000)
        rig.send(.turnEnd)
        rig.wait(60_000)
        XCTAssertEqual(finished(rig.send(.turnStopped, notice: true)), [], "Claude sat at its prompt after finishing")

        let codex = CoreRig()
        codex.send(.turnStart, .codex)
        XCTAssertEqual(finished(codex.send(.turnStopped, .codex)), ["stopped"])
        XCTAssertEqual(finished(codex.send(.turnStopped, .codex)), [], "no turn open")
    }

    /// A failed call plays no rule reaction of its own, however it
    /// failed: its word hits Boop in the work stream instead, and a
    /// reaction card is only ever a turn's. Nor does a call that worked,
    /// nor Codex, which reports no failures.
    func testAFailedCallPlaysNoRuleReaction() {
        let rig = CoreRig()
        rig.send(.turnStart)
        for (id, error) in [("1", "exit_code"), ("2", "timeout"), ("3", "denied"), ("4", "other")] {
            rig.send(.activity, tool: "Bash", id: id)
            XCTAssertEqual(reactionNames(rig.send(.activity, tool: "Bash", failed: true, id: id, error: error)), [], error)
        }
        rig.send(.activity, tool: "Bash", id: "6")
        XCTAssertEqual(reactionNames(rig.send(.activity, tool: "Bash", failed: false, id: "6")), [])

        let codex = CoreRig()
        codex.send(.turnStart, .codex)
        codex.send(.activity, .codex, tool: "shell")
        XCTAssertEqual(reactionNames(codex.send(.activity, .codex, tool: "shell", done: true)), [])
    }

    /// A helper coming back plays no rule reaction: the work stream's
    /// "back" and the brain have it. Its own `SubagentStop`, or with hooks
    /// that don't say when helpers start, its `Task` or `Agent` call's end.
    func testAHelperReturningPlaysNoRuleReaction() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent", id: "A")
        rig.send(.subagentStart, subagent: "h1")
        XCTAssertEqual(reactionNames(rig.send(.subagentEnd, subagent: "h1")), [])
        XCTAssertEqual(reactionNames(rig.send(.activity, tool: "Agent", id: "A", done: true)), [])
        rig.send(.activity, tool: "Task", id: "T")
        XCTAssertEqual(reactionNames(rig.send(.activity, tool: "Task", id: "T", done: true)), [], "older hooks")
    }

    /// A start, a helper back and a stop record no `did` of the rules':
    /// the brain has them.
    func testStartsAndStopsRecordNoRuleReaction() {
        let rig = CoreRig()
        func did(_ fx: Fx) -> [String] {
            let seq = rig.pipeline.transcript.events.last { $0.agent != nil }!.seq
            return rig.pipeline.transcript.view(now: rig.now).dids(for: seq)
                .map { "\($0.action ?? "") \($0["by"]?.string ?? "") \($0["message"]?.string ?? "")" }
        }
        XCTAssertEqual(did(rig.send(.sessionStart, source: "resume")), [])
        XCTAssertEqual(did(rig.send(.turnStart)), [])
        rig.send(.subagentStart, subagent: "h1")
        XCTAssertEqual(did(rig.send(.subagentEnd, subagent: "h1")), [], "a helper back is the brain's")
        rig.send(.activity, tool: "Bash", id: "3")
        XCTAssertEqual(did(rig.send(.turnStopped, tool: "Bash")), [], "and a stop")
    }
}
