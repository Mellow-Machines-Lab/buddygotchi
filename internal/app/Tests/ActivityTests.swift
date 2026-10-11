import AgentHooks
import BoopDevKit
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
    var act: String? { state.act }
}

// MARK: - What the agents are doing

final class CoreActivityTests: XCTestCase {
    override func setUpWithError() throws { try requireBoopsPack() }

    /// A running call shows what it does, in working's
    /// place: its tool and topic decide, and a `Task` or `Agent` call
    /// delegates only from the main agent.
    func testEachCallShowsWhatItDoes() {
        let cases: [(Agent, String, String?, String)] = [
            (.claude, "Bash", nil, "terminal"), (.claude, "Bash", "build", "terminal"),
            (.claude, "Bash", "deploy", "terminal"), (.claude, "Bash", "tests", "testing"),
            (.claude, "Bash", "inspect", "analyzing"), (.claude, "Read", nil, "analyzing"),
            (.claude, "Grep", nil, "analyzing"), (.claude, "Glob", nil, "analyzing"),
            (.claude, "LS", nil, "analyzing"), (.claude, "WebSearch", nil, "searching"),
            (.claude, "WebFetch", nil, "searching"), (.claude, "Task", nil, "delegating"),
            (.claude, "Agent", nil, "delegating"), (.claude, "Edit", "docs", "tool_use"),
            (.claude, "Write", nil, "tool_use"), (.claude, "NotebookEdit", nil, "tool_use"),
            (.claude, "mcp__github__create_pr", nil, "tool_use"), (.claude, "Skill", nil, "tool_use"),
            (.claude, "TodoWrite", nil, "planning"), (.claude, "ExitPlanMode", nil, "planning"),
            (.codex, "shell", nil, "terminal"), (.codex, "exec_command", "tests", "testing"),
            (.codex, "local_shell", "inspect", "analyzing"), (.codex, "apply_patch", nil, "tool_use"),
            (.codex, "update_plan", nil, "planning"),
        ]
        for (agent, tool, topic, act) in cases {
            let rig = CoreRig()
            rig.send(.turnStart, agent)
            let fx = rig.send(.activity, agent, tool: tool, topic: topic)
            XCTAssertEqual(states(fx).last?.act, act, "\(tool) \(topic ?? "")")
            XCTAssertEqual(rig.state.visual, act, tool)
            XCTAssertEqual(rig.state.base, "working", "\(tool): the base stays working")
        }
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, subagent: "a1", tool: "Agent")
        XCTAssertEqual(rig.act, "tool_use", "a subagent doesn't delegate")
    }

    /// `act` goes out only while `base` is `working` and
    /// nothing needs you, and the variation is that visual's.
    func testTheActivityShowsOnlyInTheWorkingLook() {
        let rig = CoreRig()
        rig.send(.sessionStart)
        rig.send(.turnStart)
        let fx = rig.send(.activity, tool: "Bash", id: "b")
        let line = states(fx).last!.jsonLine
        let variant = rig.state.variant
        XCTAssertEqual(line, #"{"t":"state","base":"working","act":"terminal","mood":"calm","busy":1,"vol":6,"variant":"# + "\(variant)}")
        XCTAssertTrue((1...FaceLoops.count(mood: "calm", state: "terminal")).contains(variant))
        rig.send(.needsYou, tool: "Bash")
        XCTAssertNil(rig.act, "needs you covers it")
        XCTAssertEqual(rig.state.visual, "needs_you")
        rig.send(.turnStart, session: "b")
        rig.send(.activity, session: "b", tool: "Read", id: "r")
        XCTAssertEqual(rig.state.base, "working")
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
        XCTAssertFalse(rig.log.contains { if case .state(let s) = $0 { s.act != nil && s.base != "working" } else { false } })
    }

    /// With several calls running the highest shows,
    /// testing > delegating > terminal > searching > analyzing > tool_use
    /// > waiting > planning; a higher one at once, and a lower one only once
    /// the one showing is 1.5 s past its last call.
    func testTheHighestActivityShows() {
        XCTAssertEqual(Act.allCases.map(\.rawValue),
                       ["testing", "delegating", "terminal", "searching", "analyzing", "tool_use", "waiting", "planning"])
        let rig = CoreRig()
        rig.send(.turnStart, mode: "plan")
        XCTAssertEqual(rig.act, "planning", "plan mode, nothing running")
        let climb: [(tool: String, topic: String?, act: String)] = [
            ("Edit", nil, "tool_use"), ("Read", nil, "analyzing"), ("WebFetch", nil, "searching"), ("Bash", nil, "terminal"),
            ("Agent", nil, "delegating"), ("Bash", "tests", "testing"),
        ]
        for (n, call) in climb.enumerated() {
            let fx = rig.send(.activity, tool: call.tool, topic: call.topic, id: "c\(n)")
            XCTAssertEqual(states(fx).last?.act, call.act, "\(call.tool): at once")
        }
        for n in climb.indices.reversed() {
            rig.send(.activity, tool: climb[n].tool, id: "c\(n)", done: true)
            XCTAssertEqual(rig.act, climb[n].act, "\(climb[n].act) ended, and holds")
            rig.tick(after: Core.actHoldMs - 1)
            XCTAssertEqual(rig.act, climb[n].act, "\(climb[n].act): still")
            rig.tick(after: 1)
            XCTAssertEqual(rig.act, n > 0 ? climb[n - 1].act : "planning", "then the next one down")
        }
    }

    /// An activity shows at least 1.5 s
    /// (`Core.actHoldMs`) after its last call ends, so a burst of quick
    /// reads is one stretch of analyzing, not a flicker; then plain
    /// working.
    func testABurstOfQuickCallsIsOneStretch() {
        XCTAssertEqual(Core.actHoldMs, 1500)
        let rig = CoreRig()
        rig.send(.turnStart)
        var acts: [String?] = []
        func note(_ fx: Fx) { acts += states(fx).map(\.act) }
        for n in 0..<8 {  // a read of 50 ms every 600 ms
            note(rig.send(.activity, tool: "Read", id: "r\(n)"))
            rig.now += 50
            note(rig.send(.activity, tool: "Read", id: "r\(n)", done: true))
            note(rig.tick(after: 550))
        }
        XCTAssertEqual(acts, ["analyzing"], "one stretch")
        note(rig.tick(after: Core.actHoldMs - 550 - 1))
        XCTAssertEqual(rig.act, "analyzing", "1.5 s after the last read")
        note(rig.tick(after: 1))
        XCTAssertEqual(acts, ["analyzing", nil])
        XCTAssertEqual(rig.state.visual, "working")
    }

    /// A lower activity doesn't cut a higher one short.
    /// A command that starts during a read shows at once; when it ends it
    /// holds 1.5 s, then the read still running shows again.
    func testAHigherActivityShowsAtOnceAndHolds() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Read", id: "r")
        rig.now += 100
        XCTAssertEqual(states(rig.send(.activity, tool: "Bash", id: "b")).last?.act, "terminal")
        rig.now += 100
        rig.send(.activity, tool: "Bash", id: "b", done: true)
        rig.tick(after: 1499)
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
        XCTAssertEqual(rig.act, "testing")
        rig.wait(2000)
        XCTAssertEqual(rig.act, "waiting", "20 s quiet, then its 1.5 s")
        rig.send(.activity, subagent: "a1", tool: "Read", id: "r")
        XCTAssertEqual(rig.act, "testing", "heard from again")

        let helper = CoreRig()
        helper.send(.turnStart)
        helper.send(.activity, tool: "Agent", id: "A")
        helper.send(.activity, subagent: "a1", tool: "Bash", id: "b")
        helper.wait(60_000)
        XCTAssertEqual(helper.act, "delegating", "the helper's command waits; the helper works")
    }

    /// Planning shows only for Claude's plan
    /// mode (from any event that says it) and a planning call; never from
    /// the gap between a prompt and the first call.
    func testPlanningComesOnlyFromPlanModeOrAPlanningCall() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.wait(10_000)
        XCTAssertNil(rig.act, "a prompt and no call yet: plain working")
        rig.send(.activity, tool: "Read", id: "r", mode: "plan")
        XCTAssertEqual(rig.act, "analyzing", "a call shows over plan mode")
        rig.send(.activity, tool: "Read", id: "r", done: true, mode: "plan")
        rig.wait(2000)
        XCTAssertEqual(rig.act, "planning")
        rig.send(.activity, tool: "Edit", id: "e", mode: "acceptEdits")
        XCTAssertEqual(rig.act, "tool_use")
        rig.send(.activity, tool: "Edit", id: "e", done: true)
        rig.wait(2000)
        XCTAssertNil(rig.act, "out of plan mode; an event without a mode leaves it as it was")
        rig.send(.activity, tool: "TodoWrite", id: "t")
        XCTAssertEqual(rig.act, "planning", "a planning call")
    }

    /// Delegating from the main agent's `Task` or `Agent`
    /// call until it ends, or while a helper Boop saw start
    /// (`SubagentStart`) hasn't ended; never from a helper's end or its
    /// call alone. A helper's start isn't activity: it wakes no idle
    /// session.
    func testDelegatingLastsWhileAHelperWorks() {
        let rig = CoreRig()
        rig.send(.turnStart)
        for (call, helper) in [("A1", "h1"), ("A2", "h2")] {  // background helpers: their calls return at once
            rig.send(.activity, tool: "Agent", id: call)
            rig.send(.subagentStart, subagent: helper)
            rig.send(.activity, tool: "Agent", id: call, done: true)
        }
        rig.wait(5000)
        XCTAssertEqual(rig.act, "delegating")
        rig.send(.activity, subagent: "h1", tool: "Read", id: "h1r")
        XCTAssertEqual(rig.act, "delegating", "it outranks a helper's read")
        rig.send(.subagentEnd, subagent: "h1")
        rig.wait(5000)
        XCTAssertEqual(rig.act, "delegating", "h2 still works")
        rig.send(.subagentEnd, subagent: "h2")
        rig.wait(2000)
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
        XCTAssertEqual(idle.state.base, "idle")
    }

    /// A subagent that ended runs nothing more: its calls go with it, as
    /// they do when the turn ends.
    func testAHelpersCallsEndWithIt() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent", id: "A")
        rig.send(.subagentStart, subagent: "h")
        rig.send(.activity, subagent: "h", tool: "Bash", topic: "tests", id: "hb")
        XCTAssertEqual(rig.act, "testing")
        rig.send(.subagentEnd, subagent: "h")
        rig.wait(2000)
        XCTAssertEqual(rig.act, "delegating", "its Agent call runs on")

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
        rig.wait(2000)
        XCTAssertNil(rig.act, "not the denied command")

        rig.send(.activity, subagent: "a1", tool: "Bash", id: "s")
        rig.send(.needsYou, subagent: "a1", tool: "Bash")
        rig.send(.subagentEnd, subagent: "a1")
        rig.wait(2000)
        XCTAssertNil(rig.act, "a denied subagent ends, and its command with it")
    }

    /// With several sessions working, the one heard from
    /// last shows what it's doing, among those doing something, once the
    /// activity showing has shown 1.5 s.
    func testTheSessionHeardFromLastPicksTheActivity() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.turnStart, session: "b")
        rig.send(.activity, session: "a", tool: "Bash", topic: "tests", id: "t")
        XCTAssertEqual(rig.act, "testing")
        rig.now += 500
        rig.send(.activity, session: "b", tool: "Read", id: "r")
        XCTAssertEqual(rig.act, "testing", "testing has shown only 0.5 s")
        rig.tick(after: 1000)
        XCTAssertEqual(rig.act, "analyzing", "b was heard from last")
        rig.send(.activity, session: "b", tool: "Read", id: "r", done: true)
        rig.wait(2000)
        XCTAssertEqual(rig.act, "testing", "b is doing nothing now; a is")
        rig.send(.activity, session: "a", tool: "Bash", id: "t", done: true)
        rig.wait(2000)
        XCTAssertNil(rig.act)
        XCTAssertEqual(rig.state.busy, 2)
    }

    /// A new mood keeps the variation showing, unless it
    /// has fewer of that look; then one of its own, at random.
    func testANewMoodWithFewerVariationsPicksAgain() throws {
        let many = FaceLoops.moods.max { FaceLoops.count(mood: $0, state: "terminal") < FaceLoops.count(mood: $1, state: "terminal") }!
        let few = FaceLoops.moods.min { FaceLoops.count(mood: $0, state: "terminal") < FaceLoops.count(mood: $1, state: "terminal") }!
        let fewer = FaceLoops.count(mood: few, state: "terminal")
        try XCTSkipUnless(FaceLoops.count(mood: many, state: "terminal") > fewer, "every mood has as many terminal looks")
        let rig = CoreRig(seed: 7)
        _ = rig.core.setMood(many, at: rig.now)
        var n = 0
        repeat {
            rig.send(.turnEnd)
            rig.send(.turnStart)
            rig.send(.activity, tool: "Bash", id: "b\(n)")
            n += 1
        } while rig.state.variant <= fewer && n < 50
        XCTAssertEqual(rig.state.visual, "terminal")
        XCTAssertGreaterThan(rig.state.variant, fewer, "a variation \(few) hasn't")
        let fx = rig.core.setMood(few, at: rig.now)
        XCTAssertEqual(states(fx).last?.visual, "terminal")
        XCTAssertTrue((1...fewer).contains(rig.state.variant), "\(rig.state.variant) of \(fewer)")
    }
}

// MARK: - The rules' one-shots

final class CoreOneShotTests: XCTestCase {
    /// A session starting plays starting, fresh (startup,
    /// clear), carrying on (resume) or with its context compacted
    /// (compact), and a prompt plays it for a new task: a one-shot of the rules', with no face of the brain's,
    /// which plays only if the device's turn is free.
    func testStartsPlayStarting() {
        for (source, ctx) in [("startup", "session"), ("clear", "session"), ("resume", "continuation"),
                              ("compact", "compacted"), (nil, "session")] {
            let rig = CoreRig()
            let fx = rig.send(.sessionStart, source: source)
            XCTAssertEqual(shots(fx), ["starting \(ctx)"], source ?? "no source")
            let moment = moments(fx)[0]
            XCTAssertNil(moment.mood)
            XCTAssertTrue(FaceLoops.variants(mood: MoodAction.initial, state: "starting", ctx: ctx).contains(moment.variant ?? 0))
        }
        let rig = CoreRig()
        let fx = rig.send(.turnStart)
        let start = moments(fx)
        XCTAssertEqual(start.count, 1)
        let variant = start[0].variant ?? 0
        XCTAssertTrue(FaceLoops.variants(mood: MoodAction.initial, state: "starting", ctx: "new_task").contains(variant))
        XCTAssertEqual(start[0].line(id: 1, play: .ifFree),
                       #"{"t":"do","id":1,"name":"starting","play":"if_free","args":{"variant":"# + "\(variant)" + #","ctx":"new_task"}}"#)
        XCTAssertEqual(fx.effects.firstIndex { if case .state = $0 { true } else { false } }, 0, "the look first")
        XCTAssertEqual(shots(CoreRig().send(.sessionStart, .codex, source: "resume")), ["starting continuation"])
        XCTAssertEqual(shots(CoreRig().send(.sessionStart, .codex, source: "compact")), ["starting compacted"])
        XCTAssertEqual(shots(rig.send(.sessionStart, subagent: "a1")), [], "a subagent's own start")
    }

    /// An interrupt that ends a turn plays stopped: Esc
    /// on a call, Claude's idle notice after Esc between calls, or Codex's
    /// `Interrupt`. The idle notice after a turn that finished, or one from
    /// before the last prompt, plays nothing.
    func testAnInterruptPlaysStopped() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Bash", id: "b")
        XCTAssertEqual(shots(rig.send(.turnStopped, tool: "Bash")), ["stopped"])
        rig.wait(61_000)
        XCTAssertEqual(shots(rig.send(.turnStopped, notice: true)), [], "the notice after it: the turn is over")
        rig.send(.turnStart)
        rig.wait(10_000)
        XCTAssertEqual(shots(rig.send(.turnStopped, notice: true)), [], "from before the prompt")
        rig.wait(60_000)
        XCTAssertEqual(shots(rig.send(.turnStopped, notice: true)), ["stopped"], "Esc between calls, a minute on")
        rig.send(.turnStart)
        rig.wait(5000)
        rig.send(.turnEnd)
        rig.wait(60_000)
        XCTAssertEqual(shots(rig.send(.turnStopped, notice: true)), [], "Claude sat at its prompt after finishing")

        let codex = CoreRig()
        codex.send(.turnStart, .codex)
        XCTAssertEqual(shots(codex.send(.turnStopped, .codex)), ["stopped"])
        XCTAssertEqual(shots(codex.send(.turnStopped, .codex)), [], "no turn open")
    }

    /// A command that fails with an exit
    /// code or times out plays error, at most once every 30 s
    /// (`Core.errorEveryMs`). A denied call or another failure never does,
    /// nor a result that landed after its turn stopped, nor Codex, which
    /// reports no failures.
    func testAFailedCommandPlaysErrorAtMostEveryThirtySeconds() {
        XCTAssertEqual(Core.errorEveryMs, 30_000)
        let rig = CoreRig()
        rig.send(.turnStart)
        func fail(_ error: String, _ id: String) -> [String] {
            rig.send(.activity, tool: "Bash", id: id)
            return shots(rig.send(.activity, tool: "Bash", failed: true, id: id, error: error))
        }
        XCTAssertEqual(fail("exit_code", "1"), ["error"])
        rig.wait(29_999)
        XCTAssertEqual(fail("timeout", "2"), [], "within 30 s of the last")
        rig.wait(1)
        XCTAssertEqual(fail("timeout", "3"), ["error"])
        rig.wait(31_000)
        XCTAssertEqual(fail("denied", "4"), [], "you said no")
        XCTAssertEqual(fail("other", "5"), [])
        rig.send(.activity, tool: "Bash", id: "6")
        XCTAssertEqual(shots(rig.send(.activity, tool: "Bash", failed: false, id: "6")), [])
        rig.send(.activity, tool: "Bash", id: "7")
        rig.send(.turnStopped, tool: "Bash")
        XCTAssertEqual(shots(rig.send(.activity, tool: "Bash", failed: true, id: "7", error: "exit_code")), [],
                       "landed after the stop")

        let codex = CoreRig()
        codex.send(.turnStart, .codex)
        codex.send(.activity, .codex, tool: "shell")
        XCTAssertEqual(shots(codex.send(.activity, .codex, tool: "shell", done: true)), [])
    }

    /// A helper Boop saw start plays helper_return when
    /// it ends while its turn goes on; with hooks that don't say when
    /// helpers start, its `Task` or `Agent` call's end does. Never twice
    /// for one helper, for one Boop didn't see start, for a helper that
    /// failed, or after the turn ended.
    func testAHelperReturning() {
        let rig = CoreRig()
        rig.send(.turnStart)
        rig.send(.activity, tool: "Agent", id: "A")
        rig.send(.subagentStart, subagent: "h1")
        XCTAssertEqual(shots(rig.send(.subagentEnd, subagent: "h1")), ["helper_return"])
        XCTAssertEqual(shots(rig.send(.activity, tool: "Agent", id: "A", done: true)), [], "not twice")
        XCTAssertEqual(shots(rig.send(.subagentEnd, subagent: "h2")), [], "never seen starting")
        rig.send(.activity, tool: "Task", id: "T")
        XCTAssertEqual(shots(rig.send(.activity, tool: "Task", id: "T", done: true)), ["helper_return"], "older hooks")
        rig.send(.activity, tool: "Task", id: "F")
        XCTAssertEqual(shots(rig.send(.activity, tool: "Task", failed: true, id: "F", error: "other")), [], "it failed")
        rig.send(.subagentStart, subagent: "bg")
        rig.send(.turnEnd)
        XCTAssertEqual(shots(rig.send(.subagentEnd, subagent: "bg")), [], "after the turn ended")
    }

    /// No one-shot while something needs you or while
    /// `listening` holds the screen, from any session; the event that
    /// answers a request plays its own.
    func testNoOneShotWhileSomethingHoldsTheScreen() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.send(.activity, session: "a", tool: "Bash", id: "b")
        rig.send(.needsYou, session: "a", tool: "Bash")
        XCTAssertEqual(shots(rig.send(.turnStart, session: "b")), [], "needs you shows")
        XCTAssertEqual(shots(rig.send(.sessionStart, session: "c")), [])
        XCTAssertEqual(shots(rig.send(.activity, session: "a", tool: "Bash", failed: true, id: "b", error: "exit_code")),
                       ["error"], "it ran, and answered the request")
        rig.talk(true)
        XCTAssertEqual(shots(rig.send(.turnStart, session: "c")), [], "the mic is on")
        rig.talk(false)
        XCTAssertEqual(shots(rig.send(.sessionStart, session: "d")), [], "listening waits for the reply")
        rig.core.listeningEnded()
        XCTAssertEqual(shots(rig.send(.turnStart, session: "d")), ["starting new_task"])
    }

    /// Each one-shot is drawn in Boop's mood, a
    /// variation at random among those for its context, never the one it
    /// played last when there's another.
    func testOneShotsTakeTheMoodsVariations() {
        let rig = CoreRig(seed: 5)
        _ = rig.core.setMood("calm", at: rig.now)
        let fit = FaceLoops.variants(mood: "calm", state: "starting", ctx: "new_task")
        var last: Int?
        for _ in 0..<12 {
            let moment = moments(rig.send(.turnStart))[0]
            XCTAssertTrue(fit.contains(moment.variant ?? 0), "\(String(describing: moment.variant)) of \(fit)")
            if fit.count > 1 { XCTAssertNotEqual(moment.variant, last) }
            last = moment.variant
            rig.send(.turnEnd)
        }
    }
}
