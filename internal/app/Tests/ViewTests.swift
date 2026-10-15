import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The view: raw events folded into what the brain hears.
final class ViewTests: XCTestCase {

    var rig = CoreRig()

    @discardableResult
    func hook(_ kind: Hook, agent: Agent = .claude, session: String = "s1", workspace: String? = "fix-nav",
              tool: String? = nil, topic: String? = nil, failed: Bool? = nil, done: Bool = false,
              id: String? = nil, error: String? = nil, message: String? = nil, prompt: String? = nil) -> [ViewEvent] {
        events(rig.send(kind, agent, session: session, workspace: workspace, tool: tool, topic: topic, failed: failed,
                        id: id, done: done, error: error, message: message, prompt: prompt))
    }

    /// One test run: its `PreToolUse`, `ms` later its result.
    @discardableResult
    func tests(failed: Bool, after ms: Int64 = 40_000, id: String) -> [ViewEvent] {
        hook(.activity, tool: "Bash", topic: "tests", id: id)
        rig.wait(ms)
        return hook(.activity, tool: "Bash", topic: "tests", failed: failed, done: true, id: id, error: failed ? "exit_code" : nil)
    }

    /// The tests-fail-then-pass turn, line by line, with the
    /// thread named after its workspace and its project. A repeat failure
    /// reads as the first did; streaks are left to the facts.
    func testATurnOfFailuresAndAComeback() throws {
        let start = hook(.turnStart, prompt: "fix the nav\nplease")
        XCTAssertEqual(start.map(\.line), [#"claude started turn 1 on "fix-nav" (landing)."#])
        XCTAssertEqual(start.map(\.name), ["turn start"])
        XCTAssertEqual(start[0].notes, [#"You asked: "fix the nav please""#], "on one line")
        XCTAssertTrue(start[0].wakesBrain)

        XCTAssertEqual(tests(failed: true, id: "t1").map(\.line), [#"claude's tests failed on "fix-nav" (landing)."#])
        XCTAssertEqual(tests(failed: true, id: "t2").map(\.line),
                       [#"claude's tests failed on "fix-nav" (landing)."#])
        let third = try XCTUnwrap(tests(failed: true, id: "t3").first)
        XCTAssertEqual(third.name, "tool end")
        XCTAssertEqual(third.line, #"claude's tests failed on "fix-nav" (landing)."#)
        XCTAssertEqual(third.facts["failed_before"], .int(2))
        XCTAssertEqual(third.facts["took"], "short", "40 s is short")
        XCTAssertEqual(third.facts["took_ms"], .int(40_000))
        XCTAssertEqual(third.about, "claude/s1")

        XCTAssertEqual(tests(failed: false, id: "t4").map(\.line),
                       [#"claude's tests passed on "fix-nav" (landing) after failing."#])
        XCTAssertEqual(tests(failed: false, id: "t5"), [], "a pass with no failures before isn't notable")

        rig.wait(60_000)
        let end = try XCTUnwrap(hook(.turnEnd, message: "All green now.").first)
        XCTAssertEqual(end.line, #"claude finished turn 1 on "fix-nav" (landing): done, a long turn, 5 tool calls."#,
                       "4 min is long; failed calls count the same")
        XCTAssertEqual(end.notes, [#"Its last message: "All green now.""#])
        XCTAssertTrue(end.did.isEmpty, "no rule cheers")
        XCTAssertEqual(end.facts["comeback"], "tests", "the facts keep what the line leaves out")
        XCTAssertEqual(end.facts["tools_failed"], .int(3))
        XCTAssertEqual(end.facts["outcome"], "done")
        XCTAssertEqual(end.facts["message"], "All green now.")
    }

    /// A long prompt or message is cut, on one line.
    func testLongWordsAreCut() {
        let long = String(repeating: "word ", count: 200)
        let note = EventLine.lastMessage(long)!
        XCTAssertEqual(note.count, "Its last message: \"\"".count + EventLine.messageMax)
        XCTAssertTrue(note.hasSuffix("…\""))
        XCTAssertNil(EventLine.prompt("  \n "))
        XCTAssertEqual(EventLine.turnEnd(agent: "claude", turn: 1, thread: "\"x\"", outcome: "done", lengthMs: 0, tools: 1),
                       #"claude finished turn 1 on "x": done, a short turn, 1 tool call."#)
        XCTAssertEqual(EventLine.turnEnd(agent: "claude", turn: 1, thread: "\"x\"", outcome: "done", lengthMs: 0, tools: 0),
                       #"claude finished turn 1 on "x": done, a short turn, no tool calls."#)
    }

    /// Which view events are kept. By default a tool call's
    /// start is read but not kept, its wait on you is, and its end only
    /// when notable; sessions and subagents are never kept.
    func testTheKeepRule() {
        func keeps(_ type: Event.Kind, _ phase: Event.Phase?, notable: Bool, all: Bool = false) -> Bool {
            TranscriptView.keeps(type, phase, notable: notable, allToolEnds: all)
        }
        XCTAssertTrue(keeps(.turn, .start, notable: false))
        XCTAssertFalse(keeps(.tool, .start, notable: true))
        XCTAssertTrue(keeps(.tool, .wait, notable: false))
        XCTAssertFalse(keeps(.tool, .end, notable: false))
        XCTAssertTrue(keeps(.tool, .end, notable: true))
        XCTAssertFalse(keeps(.session, .start, notable: true))
        XCTAssertFalse(keeps(.subagent, .start, notable: true))
        XCTAssertFalse(keeps(.subagent, .end, notable: true))
        XCTAssertTrue(keeps(.poke, nil, notable: false))
        XCTAssertTrue(keeps(.tool, .end, notable: false, all: true))
        XCTAssertFalse(keeps(.tool, .start, notable: false, all: true))

        hook(.sessionStart)
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Bash", topic: "tests", id: "t"), [], "a start isn't kept")
    }

    /// A helper starting (`SubagentStart`), like one ending,
    /// makes no view event and isn't the thread's turn: the turn it came in
    /// ends as its own.
    func testASubagentsStartIsNoViewEvent() {
        hook(.turnStart)
        XCTAssertEqual(events(rig.send(.subagentStart, subagent: "a1")), [])
        rig.wait(1000)
        XCTAssertEqual(hook(.turnEnd).map(\.line), [#"claude finished turn 1 on "fix-nav" (landing): done, a short turn, no tool calls."#])
    }

    /// Routine tool uses are only counted, unless the personality asks for
    /// all of them.
    func testRoutineToolUsesAreCountedOrWithAllBecomeEvents() {
        hook(.turnStart)
        XCTAssertEqual(hook(.activity, tool: "Edit", done: true), [])
        rig.view.setRules(Personality.Rules(toolUses: .all))
        XCTAssertEqual(hook(.activity, tool: "Edit", failed: false, done: true).map(\.line),
                       [#"claude edited a file on "fix-nav" (landing)."#])
        XCTAssertEqual(hook(.activity, tool: "mcp__x__y", failed: true, done: true, error: "other").map(\.line),
                       [#"claude used a tool on "fix-nav" (landing). It failed."#])
        XCTAssertEqual(hook(.turnEnd).first!.facts["tools_failed"], .int(1), "counted in the facts, not the line")
    }

    /// Codex says nothing about failures, so its tool uses are `unknown`
    /// and never notable.
    func testCodexToolUsesAreUnknown() {
        hook(.turnStart, agent: .codex, session: "c1")
        XCTAssertEqual(hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true), [])
        rig.view.setRules(Personality.Rules(toolUses: .all))
        let e = hook(.activity, agent: .codex, session: "c1", tool: "shell", topic: "tests", done: true)
        XCTAssertEqual(e.first?.facts["result"], "unknown")
    }

    /// A failed check's error is in its facts, not its line.
    func testAToolErrorIsLeftOutOfTheLine() {
        hook(.turnStart)
        hook(.activity, tool: "Bash", topic: "build", id: "b")
        let failed = hook(.activity, tool: "Bash", topic: "build", failed: true, done: true, id: "b", error: "timeout")
        XCTAssertEqual(failed.map(\.line), [#"claude's build failed on "fix-nav" (landing)."#])
        XCTAssertEqual(failed.first?.facts["error"], "timeout")
    }

    /// A failed turn, a stopped one, and a very long one; turn starts say
    /// nothing of the gap; a thread with no workspace is named by its
    /// project.
    func testTurnEnds() {
        hook(.turnStart, workspace: nil)
        rig.wait(5000)
        let failed = hook(.turnFailed, workspace: nil, error: "rate_limit").first
        XCTAssertEqual(failed?.line, #"claude finished turn 1 on "landing": failed, a short turn, no tool calls."#)
        XCTAssertEqual(failed?.facts["error"], "rate_limit")
        XCTAssertEqual(TranscriptView.wakes[failed!.name.replacingOccurrences(of: " ", with: "_")], 1,
                       "a finish keeps its pass while it waits")
        rig.wait(30_000)
        let start = hook(.turnStart, workspace: nil).first
        XCTAssertEqual(start?.line, #"claude started turn 2 on "landing"."#)
        XCTAssertEqual(TranscriptView.wakes[start!.name.replacingOccurrences(of: " ", with: "_")], 0)
        rig.wait(90_000)
        let stopped = hook(.turnStopped, workspace: nil, tool: "Bash")
        XCTAssertEqual(stopped.first?.line, #"claude finished turn 2 on "landing": stopped, a long turn, no tool calls."#)
        rig.wait(20 * 60_000)
        XCTAssertEqual(hook(.turnStart, workspace: nil).first?.line, #"claude started turn 3 on "landing"."#)
        rig.wait(6 * 60_000)
        XCTAssertEqual(hook(.turnEnd, workspace: nil).first?.line,
                       #"claude finished turn 3 on "landing": done, a very long turn, no tool calls."#)
    }

    /// The view lets late hooks go as the
    /// core does (`SessionFold`). Claude's idle notice within 30 s of a
    /// prompt ends no turn; a call's result that lands after its turn
    /// stopped opens none, so no working heartbeat comes; and a session
    /// that ended isn't back until it starts again.
    func testLateHooksAreLetGoAsTheCoreLetsThemGo() {
        XCTAssertEqual(SessionFold.idleNoticeMinMs, 30_000)
        rig = CoreRig(seed: 7, rules: .chatty)
        hook(.turnStart)
        rig.wait(10_000)
        XCTAssertEqual(events(rig.send(.turnStopped, workspace: "fix-nav", notice: true)), [], "a stale idle notice")
        hook(.activity, tool: "Bash", id: "t1")
        rig.wait(1000)
        XCTAssertEqual(hook(.turnStopped, tool: "Bash").map(\.name), ["turn end"])
        hook(.activity, tool: "Bash", done: true, id: "t1")
        XCTAssertEqual(workBeats(rig.wait(10 * 60_000)), [], "the late result opened no turn")
        hook(.sessionEnd)
        hook(.activity, tool: "Bash", id: "t2")
        XCTAssertEqual(workBeats(rig.wait(10 * 60_000)), [], "a call from before the end")
        XCTAssertEqual(hook(.turnStart).first?.line, #"claude started turn 1 on "fix-nav" (landing)."#, "back, from turn 1")
    }

    /// The view's sessions are agent-hooks' `SessionTracker`, as the core's
    /// are, so the working heartbeat comes only while the core shows the
    /// session working. Here a request waits, a subagent's call goes on
    /// beside it, and then the safety net's 10 silent minutes expire the
    /// request: the session is idle, and no working heartbeat says
    /// otherwise. Before, the view kept a fold of its own, which counted
    /// the safety net from the request only, and so worked on for the
    /// hour.
    func testTheViewWorksOnlyWhenTheCoreDoes() {
        rig = CoreRig(seed: 7, rules: .chatty)
        hook(.turnStart)
        hook(.activity, tool: "Bash", id: "t1")
        hook(.needsYou, tool: "Bash")
        rig.wait(1000)
        rig.send(.activity, subagent: "a1", tool: "Read", id: "r1")
        XCTAssertNotNil(rig.state.attn, "the subagent's call doesn't answer the request")
        rig.wait(SessionFold.safetyNetMs)
        XCTAssertEqual(rig.state.base, "idle")
        XCTAssertEqual(workBeats(rig.wait(20 * 60_000)), [], "no working heartbeat")
        XCTAssertNil(rig.view.workingSince(at: rig.now, rig.pipeline.transcript.view(now: rig.now)))
    }

    /// Nothing but what you say wakes the brain while
    /// something needs you, a poke included (the tap opens the thread),
    /// and nothing with no brain; the view events still come.
    /// "Needs you" is kept as the tool call's wait, from the core's action.
    func testGates() {
        hook(.turnStart)
        let asked = hook(.needsYou, tool: "Bash")
        XCTAssertEqual(asked.map(\.line), [#"claude needs you on "fix-nav" (landing)."#])
        XCTAssertEqual(asked.map(\.name), ["tool wait"])
        XCTAssertFalse(asked[0].wakesBrain)
        XCTAssertEqual(rig.ruleActions, ["starting", "needs_you start"])
        XCTAssertFalse(hook(.turnStart, session: "s2").first!.wakesBrain, "something needs you")
        XCTAssertFalse(events(rig.poke()).first!.wakesBrain, "a poke opens the thread instead")
        hook(.activity, tool: "Bash")
        XCTAssertEqual(rig.ruleActions, ["starting", "needs_you start", "open_thread", "needs_you end"], "answered")
        XCTAssertTrue(hook(.turnStart, session: "s3").first!.wakesBrain)
        rig.pipeline.brain = false
        XCTAssertFalse(hook(.turnStart, session: "s4").first!.wakesBrain, "no key")
        XCTAssertFalse(events(rig.poke()).first!.wakesBrain, "no key, not even a poke")
    }

    /// A thread silent for a day is let go at any session's next event, as
    /// the core lets its session go, not only at its own: a session killed
    /// without its `SessionEnd` doesn't stay in the view for good. One that
    /// comes back starts again from turn 0.
    func testASilentThreadIsLetGo() {
        hook(.turnStart)
        hook(.turnEnd)
        rig.now += SessionFold.forgetMs
        hook(.turnStart, session: "s2")
        XCTAssertNil(rig.pipeline.threads["claude/s1"])
        XCTAssertNil(rig.core.sessions["claude/s1"])
        XCTAssertEqual(hook(.turnStart).map(\.line), [#"claude started turn 1 on "fix-nav" (landing)."#])
    }

    /// Pokes: every one wakes the brain,
    /// counted in a row, and its wiggle goes under it.
    func testPokes() {
        XCTAssertEqual(TranscriptView.inARowMs, 3000)
        let one = events(rig.poke())
        XCTAssertEqual(one.map(\.line), ["You poked \(creature)."])
        XCTAssertEqual(one.map(\.name), ["poke"])
        XCTAssertTrue(one[0].wakesBrain)
        XCTAssertEqual(rig.pipeline.viewEvent(one[0].id)?.did.map(\.message), ["\(creature) wiggled on its own."])
        XCTAssertEqual(rig.pipeline.viewEvent(one[0].id)?.did.map(\.by), ["rule"])
        var last: [ViewEvent] = []
        for _ in 0..<3 { rig.wait(1000); last = events(rig.poke()) }
        XCTAssertEqual(last.map(\.line), ["You poked \(creature) 4 times in a row."])
        XCTAssertEqual(last[0].facts["in_a_row"], .int(4))
        XCTAssertTrue(last[0].wakesBrain, "no limit")
        rig.wait(3000)
        XCTAssertEqual(events(rig.poke()).map(\.line), ["You poked \(creature)."], "3 s apart starts again")
        // While something needs you there's no wiggle: the tap opens the
        // thread, and doesn't wake the brain.
        hook(.turnStart)
        hook(.needsYou, tool: "Bash")
        let seen = events(rig.poke())
        XCTAssertEqual(rig.pipeline.viewEvent(seen[0].id)?.did.map(\.message), ["\(creature) opened the thread that needs you on the Mac."])
        XCTAssertFalse(seen[0].wakesBrain)
    }

    /// What you say to Boop: one line, quoted and cut to
    /// 300 characters like your prompt, that always wakes the brain, even
    /// while something needs you. The raw event keeps 2,000 characters, and
    /// words that are only space make no view event.
    func testWhatYouSay() throws {
        let said = events(rig.said("are the tests\npassing yet?"))
        XCTAssertEqual(said.map(\.line), [#"You said to \#(creature): "are the tests passing yet?""#])
        XCTAssertEqual(said.map(\.name), ["talk"])
        XCTAssertTrue(said[0].wakesBrain)
        XCTAssertEqual(TranscriptView.wakes[said[0].name], 2, "it goes ahead of a finish waiting")
        XCTAssertNil(said[0].about)
        XCTAssertEqual(said[0].facts["words"], "are the tests\npassing yet?")
        XCTAssertEqual(said[0].facts["by"], "device")
        let raw = try XCTUnwrap(rig.pipeline.transcript.events.last)
        XCTAssertEqual(raw.from, .mic)
        XCTAssertEqual(raw.type, .talk)
        XCTAssertEqual(raw.specificType, "device")

        let long = try XCTUnwrap(events(rig.said(String(repeating: "a", count: 2500), by: .app)).first)
        XCTAssertEqual(long.line.count, #"You said to \#(creature): """#.count + EventLine.messageMax)
        XCTAssertTrue(long.line.hasSuffix(#"…""#))
        XCTAssertEqual(rig.pipeline.transcript.events.last?["words"]?.string?.count, 2000)
        XCTAssertEqual(long.facts["by"], "app")

        XCTAssertEqual(events(rig.said(" \n ")), [])

        hook(.turnStart)
        hook(.needsYou, tool: "Bash")
        XCTAssertEqual(events(rig.said("ok")).map(\.wakesBrain), [true], "even while something needs you")
    }

    /// A reaction a tap cut short stays in
    /// progress while the pokes go on (3 s apart at most), so the barrage
    /// gets it once: `Reactions` holds it, and ends it as done once
    /// an event stops the pokes: anything but another poke of the run,
    /// "needs you", or MellowHarness's own events.
    func testWhatStopsThePokes() {
        func stops(_ e: Event) -> Bool { TranscriptView.stopsThePokes(e, rig.pipeline.transcript.view(before: e)) }
        func last(_ type: Event.Kind) -> Event { rig.pipeline.transcript.events.last { $0.type == type }! }
        rig.poke()
        XCTAssertTrue(stops(last(.poke)), "the first poke starts a run")
        rig.wait(2900)
        rig.poke()
        XCTAssertFalse(stops(last(.poke)), "the pokes go on")
        rig.wait(3000)
        rig.poke()
        XCTAssertTrue(stops(last(.poke)), "3 s apart is a new run")
        hook(.turnStart)
        XCTAssertTrue(stops(last(.turn)), "something else happened")
        hook(.needsYou, tool: "Bash")
        XCTAssertFalse(stops(last(.needsYou)), "\"needs you\" is the rules', not something happening")
        let did = rig.pipeline.transcript.events.last { $0.kind == Event.did }!
        XCTAssertFalse(stops(did), "nor are MellowHarness's own events")
    }

    /// A poke doesn't wake the brain while the brain's
    /// reaction to its run's pokes in a row, from the third
    /// (`answersRunFrom`), is in progress, a tap-cut one included, unless
    /// the mood changed since it started. The first two pokes' reactions
    /// don't count, and a new run (3 s apart) wakes it.
    func testAPokeWaitsWhileItsRunIsBeingAnswered() {
        XCTAssertEqual(TranscriptView.answersRunFrom, 3)
        func react(to poke: ViewEvent, _ name: String = "react", started: Bool = true) -> Int {
            rig.pipeline.record(Event.action(at: rig.now, phase: started ? .start : nil,
                                      name: name, data: ["for": .int(Int64(poke.seq)), "by": "brain", "ok": true,
                                                                 "message": "Boop did it."])).seq
        }
        func end(_ seq: Int, _ why: String? = nil) {
            rig.pipeline.record(Event.action(at: rig.now, phase: .end, name: "react",
                                      data: ["for": .int(Int64(seq)), "by": "brain", "outcome": why == nil ? "done" : "failed",
                                             "why": why.map { .string($0) } ?? .null]))
        }
        let answering = "\(creature) is answering these pokes"
        // A reaction a tap cut short stays open while the pokes go on
        // (`Reactions`).
        let single = events(rig.poke())[0]
        XCTAssertTrue(single.wakesBrain)
        _ = react(to: single)
        rig.wait(500)
        let second = events(rig.poke())[0]
        XCTAssertTrue(second.wakesBrain, "a single poke's reaction doesn't answer the run")
        _ = react(to: second)
        rig.wait(500)
        let third = events(rig.poke())[0]
        XCTAssertEqual(third.facts["in_a_row"], .int(3))
        XCTAssertTrue(third.wakesBrain, "nor does two pokes' reaction")
        let happy = react(to: third)
        rig.wait(500)
        var next = events(rig.poke())[0]
        XCTAssertFalse(next.wakesBrain, "three pokes' reaction is playing")
        XCTAssertEqual(rig.pipeline.whyNotWake(rig.pipeline.transcript.event(next.seq)!), answering)
        _ = happy  // a tap cuts it short: it stays in progress while the pokes go on
        rig.wait(500)
        next = events(rig.poke())[0]
        XCTAssertFalse(next.wakesBrain, "cut short by a tap, it's still in progress")

        _ = react(to: next, MoodAction.actionName, started: false)
        rig.wait(500)
        next = events(rig.poke())[0]
        XCTAssertTrue(next.wakesBrain, "the mood changed since")
        let grumpy = react(to: next)
        rig.wait(500)
        XCTAssertFalse(events(rig.poke())[0].wakesBrain, "the new reaction answers the run")
        end(grumpy)
        rig.wait(500)
        XCTAssertTrue(events(rig.poke())[0].wakesBrain, "it played out")

        let last = events(rig.poke())[0]
        _ = react(to: last)  // cut short by a tap
        rig.wait(2900)
        XCTAssertFalse(events(rig.poke())[0].wakesBrain, "within 3 s, the same run")
        rig.wait(3000)
        XCTAssertTrue(events(rig.poke())[0].wakesBrain, "3 s apart is a new run")
    }

    /// An hour with nothing happening, and no thread working,
    /// brings a heartbeat, and so does every hour after that. While a
    /// thread works, the working heartbeat comes instead.
    func testHeartbeats() {
        XCTAssertEqual(TranscriptView.heartbeatMs, 60 * 60_000)
        let idle = { (views: [ViewEvent]) in views.filter { $0.type == .heartbeat && $0.facts["idle_hours"] != nil } }
        hook(.turnStart)
        rig.wait(50 * 60_000)
        XCTAssertEqual(idle(rig.views), [], "a thread was working")
        let working = rig.views.filter { $0.type == .heartbeat }
        XCTAssertGreaterThan(working.count, 10, "the working heartbeat instead")
        XCTAssertTrue(working.allSatisfy { $0.line.hasPrefix(#"claude is still working on "fix-nav" (landing), a "#) && $0.wakesBrain })
        XCTAssertEqual(working.last?.line, #"claude is still working on "fix-nav" (landing), a very long turn."#)
        hook(.turnEnd)
        let beats = idle(events(rig.wait(2 * 60 * 60_000 + 1000)))
        XCTAssertEqual(beats.map(\.line), ["Nothing has happened for 1 hour.", "Nothing has happened for 2 hours."])
        XCTAssertTrue(beats.allSatisfy(\.wakesBrain))
        rig.poke()
        XCTAssertEqual(idle(events(rig.wait(59 * 60_000))), [], "a poke starts the hour again")
    }

    /// The length band, at its edges: short under a minute,
    /// long under 5, very long from 5, as the moods read it.
    func testBands() {
        XCTAssertEqual(Band.length(ms: 59_999), "short")
        XCTAssertEqual(Band.length(ms: 60_000), "long")
        XCTAssertEqual(Band.length(ms: 299_999), "long")
        XCTAssertEqual(Band.length(ms: 300_000), "very long")
    }

    /// The transcript keeps a file a day, reads the last two
    /// back, and a fresh view folded from them says what the old one did:
    /// turn numbers go on across a restart. An action left in progress is
    /// ended as failed; older files are deleted.
    func testTheTranscriptPersistsAndReplays() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time)), view: TranscriptView(), transcript: Transcript.log(folder: dir, time: time))
        }
        let first = pipeline()
        rig = CoreRig()
        first.agent(rig.event(.turnStart))  // and its starting one-shot's did, 2
        let start = first.record(Event.action(at: rig.now, phase: .start, name: "react",
                                       data: ["for": 1, "by": "brain", "ok": true, "message": "Boop smiled."]))
        XCTAssertEqual(start.seq, 3)
        first.agent(rig.event(.turnEnd))
        let old = dir.appendingPathComponent("2026-09-01.jsonl")
        try "{}\n".write(to: old, atomically: true, encoding: .utf8)

        let file = dir.appendingPathComponent(time.day(rig.now) + ".jsonl")
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        XCTAssertTrue(lines[0].hasPrefix(#"{"seq":1,"at":"#), String(lines[0]))
        try (String(contentsOf: file, encoding: .utf8) + #"{"seq":5,"at":"#).write(to: file, atomically: true, encoding: .utf8)

        let second = pipeline()
        var recorded: [Event] = []
        second.onRecord = { recorded.append($0) }
        XCTAssertEqual(second.readBack(now: rig.now), 4, "the torn line is skipped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "past 14 days")
        let restarted = try XCTUnwrap(recorded.last)
        XCTAssertEqual(restarted.data["why"], .string(Harness.restarted))
        XCTAssertEqual(restarted.seq, 5, "seq goes on")
        XCTAssertEqual(second.transcript.lastSeq, 5)
        XCTAssertEqual(second.transcript.events.map(\.seq), [1, 2, 3, 4, 5], "the last day stays in memory, the end included")
        XCTAssertEqual(second.views.first?.did.map(\.by), ["rule"], "a reaction that can't end now isn't shown; the one-shot is")
        rig.wait(1000)
        let next = second.agent(rig.event(.turnStart)).views
        XCTAssertEqual(next.map(\.line), [#"claude started turn 2 on "landing"."#])
        let third = pipeline()
        XCTAssertEqual(third.readBack(now: rig.now), 7, "the torn line was ended, so the next launch's aren't glued to it")
    }

    /// A write a full disk cut short inside a multi-byte
    /// character loses only its own line. The rest of the day is read,
    /// `seq` goes on from it, and the torn line is ended.
    func testATearInsideACharacterLosesOnlyItsLine() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let written = Transcript.log(folder: dir, time: rig.time)
        written.append(rig.event(.turnStart, prompt: "a café"), now: rig.now)
        written.append(rig.event(.turnEnd), now: rig.now)
        var torn = rig.event(.turnStart, prompt: "un café")
        torn.seq = 3
        let whole = Data(torn.jsonLine.utf8)
        let cut = try XCTUnwrap(whole.firstIndex(of: 0xC3), "é is two bytes")
        let file = try XCTUnwrap(written.file(for: rig.now))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: whole[...cut])
        try handle.close()

        let read = Transcript.log(folder: dir, time: rig.time)
        XCTAssertEqual(read.load(now: rig.now).map(\.seq), [1, 2])
        XCTAssertEqual(read.lastSeq, 2, "seq goes on from the day's file")
        try XCTAssertEqual(try Data(contentsOf: file).last, 0x0A, "the torn line is ended")
        XCTAssertEqual(read.append(rig.event(.turnEnd), now: rig.now).seq, 3)
        XCTAssertEqual(Transcript.log(folder: dir, time: rig.time).load(now: rig.now).count, 3)
    }

    /// A relaunch folds the transcript into the core too: a request still
    /// waiting shows again, and isn't recorded as
    /// starting twice; its end is recorded, so the view hears it, and so
    /// is that of a Codex request a tick let through its grace; a turn
    /// still going works, so Boop doesn't sleep while the brain hears
    /// it's working.
    func testARelaunchPicksTheSessionsUp() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        rig = CoreRig()
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time), lastActiveDay: time.day(rig.now)),
                     view: TranscriptView(), transcript: Transcript.log(folder: dir, time: time))
        }
        func needs(_ step: Pipeline.Step) -> [Event] { step.recorded.filter { $0.specificType == Core.needsYou } }
        let first = pipeline()
        first.agent(rig.event(.turnStart, session: "s2"))
        first.agent(rig.event(.turnStart, .codex, session: "c1"))
        first.agent(rig.event(.needsYou, .codex, session: "c1", tool: "shell"))
        rig.now += 1000
        first.agent(rig.event(.turnStart))
        first.agent(rig.event(.activity, tool: "Bash", id: "t1"))
        first.agent(rig.event(.needsYou, tool: "Bash"))
        rig.now += 2000
        XCTAssertEqual(needs(first.tick(at: rig.now)).map(\.phase), [.start], "Codex's, past its grace")
        XCTAssertEqual(first.core.snapshot(at: rig.now).attn?.more, 1)

        // Codex's request has had 10 silent minutes, and Claude's not quite.
        rig.now += SessionFold.safetyNetMs - 2500
        let second = pipeline()
        second.readBack(now: rig.now)
        let relaunched = needs(second.tick(at: rig.now))
        XCTAssertEqual(relaunched.map(\.phase), [.end], "Codex's request ends, and no request starts again")
        XCTAssertEqual(relaunched.first?.data["why"], "nothing for 10 minutes")
        XCTAssertNil(second.threads["codex/c1"]?.needsSince, "the view's sessions agree")
        let shown = second.core.snapshot(at: rig.now)
        XCTAssertEqual(shown.attn?.agent, "claude", "its request still waits")
        XCTAssertEqual(shown.busy, 1, "s2 still works")
        let answered = second.agent(rig.event(.activity, tool: "Bash", id: "t1", done: true))
        XCTAssertEqual(needs(answered).map(\.phase), [.end])
        XCTAssertNil(second.threads["claude/s1"]?.needsSince, "the view folds the answer too")
        XCTAssertEqual(second.core.snapshot(at: rig.now).busy, 2, "s1 works again")
        XCTAssertNotNil(second.view.workingSince(at: rig.now, second.transcript.view(now: rig.now)))
    }

    /// A relaunch takes which requests were shown from the transcript's
    /// `needs_you` records, not from folding the sessions again with this
    /// launch's rules (`replay`): where the two disagree, the
    /// first publish records what's missing, so the transcript says what
    /// the sessions do. Here a launch whose core started empty, as every
    /// launch's did before 2026-09-29, never recorded the end of a request
    /// answered after it. The view folds the sessions itself, so it never
    /// waited on that end.
    func testARelaunchTakesTheRequestsShownFromTheTranscript() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        rig = CoreRig()
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time), lastActiveDay: time.day(rig.now)),
                     view: TranscriptView(), transcript: Transcript.log(folder: dir, time: time))
        }
        func needs(_ step: Pipeline.Step) -> [Event] { step.recorded.filter { $0.specificType == Core.needsYou } }
        let first = pipeline()
        first.agent(rig.event(.turnStart))
        first.agent(rig.event(.activity, tool: "Bash", id: "t1"))
        XCTAssertEqual(needs(first.agent(rig.event(.needsYou, tool: "Bash"))).map(\.phase), [.start])
        rig.now += 1000
        let emptyCore = pipeline()  // the log read back, but not into the core or the view
        emptyCore.transcript.load(now: rig.now)
        XCTAssertEqual(needs(emptyCore.agent(rig.event(.activity, tool: "Bash", id: "t1", done: true))), [])
        rig.now += 1000
        let third = pipeline()
        third.readBack(now: rig.now)
        XCTAssertNil(third.threads["claude/s1"]?.needsSince, "the view folds the answer, with no end in the transcript")
        let ended = needs(third.tick(at: rig.now))
        XCTAssertEqual(ended.map(\.phase), [.end])
        XCTAssertEqual(ended.first?.data["outcome"], "done")
        XCTAssertNil(third.core.snapshot(at: rig.now).attn)
    }

    /// A request the read-back
    /// clears, which the transcript never ended, is ended by the first
    /// publish with why it cleared. Here the safety net, at another
    /// session's event that a launch whose core started empty recorded
    /// 10 minutes on. Before, the read-back let go of why, and the end
    /// said the request was answered: `done`.
    func testARequestTheReadBackClearsEndsWithWhy() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        rig = CoreRig()
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time), lastActiveDay: time.day(rig.now)),
                     view: TranscriptView(), transcript: Transcript.log(folder: dir, time: time))
        }
        func needs(_ step: Pipeline.Step) -> [Event] { step.recorded.filter { $0.specificType == Core.needsYou } }
        let first = pipeline()
        first.agent(rig.event(.turnStart))
        first.agent(rig.event(.activity, tool: "Bash", id: "t1"))
        XCTAssertEqual(needs(first.agent(rig.event(.needsYou, tool: "Bash"))).map(\.phase), [.start])
        rig.now += SessionFold.safetyNetMs + 1000
        let emptyCore = pipeline()  // the log read back, but not into the core or the view
        emptyCore.transcript.load(now: rig.now)
        XCTAssertEqual(needs(emptyCore.agent(rig.event(.turnStart, session: "s2"))), [])
        rig.now += 1000
        let third = pipeline()
        third.readBack(now: rig.now)
        let ended = needs(third.tick(at: rig.now))
        XCTAssertEqual(ended.map(\.phase), [.end])
        XCTAssertEqual(ended.first?.data["outcome"], "failed")
        XCTAssertEqual(ended.first?.data["why"], "nothing for 10 minutes")
        XCTAssertNil(third.threads["claude/s1"]?.needsSince, "the view's sessions agree")
    }

    /// A session's first event each day carries its
    /// name, app, app session and mode again, so a relaunch, which reads
    /// back only the last two days' files, still finds them. Here a long
    /// thread in the Claude app that sent them first two days ago, and has
    /// worked on since with gaps under a day, asks for you, and Boop
    /// relaunches: a tap still opens the thread in its app. Before, every
    /// line since the first left them out, so the relaunched core had
    /// none, and the tap opened nowhere until the thread's next hook.
    func testARelaunchDaysLaterStillKnowsWhereAThreadIs() throws {
        let dir = tempDir("boop-tr")
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = rig.time
        rig = CoreRig()
        func pipeline() -> Pipeline {
            Pipeline(core: Core(config: .init(time: time), lastActiveDay: time.day(rig.now)),
                     view: TranscriptView(), transcript: Transcript.log(folder: dir, time: time))
        }
        let first = pipeline()
        func hook(_ kind: Hook, tool: String? = nil, done: Bool? = nil) {
            var e = rig.event(kind, tool: tool, done: done, mode: "default", app: "com.anthropic.claudefordesktop",
                              appSession: "local_s1")
            e.data["name"] = "Fix the nav"
            first.agent(e)
        }
        hook(.turnStart)  // day D, 14:00
        for _ in 0..<2 {  // D+1, 02:00 and 14:00
            rig.now += 12 * 3600 * 1000
            hook(.activity, tool: "Bash", done: true)
        }
        rig.now += 12 * 3600 * 1000
        hook(.needsYou, tool: "Bash")  // D+2, 02:00
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 3, "three days' files")
        rig.now += 60_000
        let second = pipeline()
        second.readBack(now: rig.now)
        XCTAssertEqual(second.core.sessions["claude/s1"]?.name, "Fix the nav")
        XCTAssertEqual(opened(Fx(second.poke(at: rig.now))),
                       [ThreadRef(agent: "claude", session: "s1", app: "com.anthropic.claudefordesktop", appSession: "local_s1")])
    }
}
