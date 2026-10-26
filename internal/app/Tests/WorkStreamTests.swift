import AgentHooks
import Foundation
import LinkKit
import MellowHarness
import XCTest
@testable import BoopKit

/// The work stream: each call's word in its lane, and which calls come
/// forward to hit Boop, one at a time.
final class WorkStreamTests: XCTestCase {
    /// A call's start or end, with what agent-hooks adds to it: its
    /// program and an edit's lines.
    func call(_ rig: CoreRig, _ id: String, tool: String = "Bash", topic: String? = nil, program: String? = nil,
              glimpse: String? = nil, added: Int? = nil, removed: Int? = nil, failed: Bool? = nil, error: String? = nil,
              session: String = "s1") -> Event {
        var e = rig.event(.activity, session: session, tool: tool, topic: topic, failed: failed, id: id, error: error)
        if let program { e.data["program"] = .string(program) }
        if let glimpse { e.data["glimpse"] = .string(glimpse) }
        if let added { e.data["lines_added"] = .int(Int64(added)) }
        if let removed { e.data["lines_removed"] = .int(Int64(removed)) }
        return e
    }

    /// The `call`s sent, as `word as`.
    func calls(_ fx: Fx) -> [String] {
        fx.effects.compactMap {
            guard case .call(let args) = $0 else { return nil }
            return "\(args["w"]?.string ?? "") \(args["as"]?.string ?? "")"
        }
    }

    /// One whole call: its start, then its end `ms` later; the calls both
    /// sent.
    @discardableResult
    func run(_ rig: CoreRig, _ id: String, ms: Int64 = 200, tool: String = "Bash", topic: String? = nil,
             program: String? = nil, added: Int? = nil, removed: Int? = nil, failed: Bool? = false,
             error: String? = nil, session: String = "s1") -> [String] {
        var sent = calls(rig.send(call(rig, id, tool: tool, topic: topic, program: program, added: added, removed: removed,
                                       session: session)))
        rig.now += ms
        sent += calls(rig.send(call(rig, id, tool: tool, topic: topic, program: program, added: added, removed: removed,
                                    failed: failed, error: error, session: session)))
        return sent
    }

    /// A call shows its word or a piece of its glimpse, each as likely,
    /// the same at its start and end; an edit shows its file and lines.
    func testACallShowsItsWordOrAPieceOfItsGlimpse() {
        let rig = CoreRig(workStream: true)
        func shown(_ e: Event) -> String {
            AgentEvent(e).map { WorkStream.shown($0, word: WorkStream.word($0, program: e["program"]?.string)) } ?? "?"
        }
        var seen: Set<String> = []
        for id in 0..<40 {
            let e = call(rig, "t\(id)", program: "sed", glimpse: "WorkStream.swift maxWordBytes")
            seen.insert(shown(e))
            XCTAssertEqual(shown(e), shown(call(rig, "t\(id)", program: "sed", glimpse: "WorkStream.swift maxWordBytes")))
        }
        XCTAssertEqual(seen, ["sed", "WorkStream", "maxWordBytes"], "a piece over 14 bytes loses its extension")
        XCTAssertEqual(shown(call(rig, "1", program: "sed")), "sed", "no glimpse, the word")
        let edits = Set((0..<20).map { shown(call(rig, "e\($0)", tool: "Edit", glimpse: "Core.swift", added: 12)) })
        XCTAssertEqual(edits, ["edit +12", "Core +12"])
        XCTAssertEqual(WorkStream.fit("averyveryverylongname.swift"), "averyveryveryl")
    }

    func testEachCallsWord() {
        let rig = CoreRig(workStream: true)
        func word(_ e: Event) -> String { AgentEvent(e).map { WorkStream.word($0, program: e["program"]?.string) } ?? "?" }
        XCTAssertEqual(word(call(rig, "1", program: "git log")), "git log")
        XCTAssertEqual(word(call(rig, "1")), "bash", "an older agent-hook names no program")
        XCTAssertEqual(word(call(rig, "1", topic: "tests", program: "make")), "tests", "a check says its topic")
        XCTAssertEqual(word(call(rig, "1", topic: "tests", program: "make fw-test")), "make fw-test",
                       "unless its program says more")
        XCTAssertEqual(word(call(rig, "1", tool: "Edit", added: 18, removed: 2)), "edit +18 -2")
        XCTAssertEqual(word(call(rig, "1", tool: "Write", added: 40)), "edit +40")
        XCTAssertEqual(word(call(rig, "1", tool: "Edit", added: 0, removed: 140)), "edit -140")
        XCTAssertEqual(word(call(rig, "1", tool: "Edit", topic: "docs", added: 3)), "docs")
        XCTAssertEqual(word(call(rig, "1", tool: "Read")), "read")
        XCTAssertEqual(word(call(rig, "1", tool: "Grep")), "grep")
        XCTAssertEqual(word(call(rig, "1", tool: "WebFetch")), "web")
        XCTAssertEqual(word(call(rig, "1", tool: "Agent")), "helper")
        XCTAssertEqual(word(call(rig, "1", tool: "mcp__linear__create_issue")), "linear", "the server you named")
        XCTAssertEqual(word(call(rig, "1", tool: "SendMessage")), "send message", "a tool Boop doesn't know")
        XCTAssertEqual(word(call(rig, "1", tool: "AskUserQuestion")), "ask user", "cut at a word, 14 bytes")
        XCTAssertEqual(WorkStream.maxWordBytes, 14)
    }

    /// A turn's first call arrives; then, with nothing notable, a call
    /// comes forward at most once every 8 s, and the same word at most once
    /// every 30 s (`ambientGapMs`, `sameWordGapMs`).
    func testAmbientCallsComeForwardNowAndThen() {
        XCTAssertEqual([WorkStream.ambientGapMs, WorkStream.sameWordGapMs, WorkStream.holdMs], [8000, 30_000, 2500])
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        XCTAssertEqual(run(rig, "1", program: "grep"), ["grep arrive"])
        rig.now += 3000
        XCTAssertEqual(run(rig, "2", program: "sed"), [], "within 8 s of the arrival")
        rig.now += 5000
        XCTAssertEqual(run(rig, "3", program: "python"), ["python stir"])
        rig.now += 9000
        XCTAssertEqual(run(rig, "4", program: "python"), [], "python came forward 9 s ago")
        rig.now += 22_000
        XCTAssertEqual(run(rig, "5", program: "python"), ["python stir"], "30 s on")
        rig.now += 9000
        XCTAssertEqual(run(rig, "6", tool: "Read"), ["read look"])
        rig.now += 9000
        XCTAssertEqual(run(rig, "7", program: "git commit"), ["git commit stamp"])
    }

    /// A failure always comes forward: it cuts an ambient word that plays.
    /// One session's failures within 2 minutes climb the ladder
    /// (`ladderMs`): a bonk, a harder one, a helmet, then thrown back.
    func testFailuresClimbTheLadder() {
        XCTAssertEqual(WorkStream.ladderMs, 120_000)
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        run(rig, "0", program: "ls")
        rig.now += 9000
        XCTAssertEqual(run(rig, "1", topic: "inspect", program: "cat"), ["cat look"])
        XCTAssertEqual(run(rig, "2", program: "make", failed: true, error: "exit_code"), ["make bonk"], "cuts the ambient one")
        rig.now += 10_000
        XCTAssertEqual(run(rig, "3", program: "make", failed: true, error: "exit_code"), ["make bonk2"])
        rig.now += 10_000
        XCTAssertEqual(run(rig, "4", program: "swift", failed: true, error: "exit_code"), ["swift helmet"])
        rig.now += 10_000
        XCTAssertEqual(run(rig, "5", program: "swift", failed: true, error: "exit_code"), ["swift throw"])
        rig.now += 10_000
        XCTAssertEqual(run(rig, "6", program: "swift", failed: true, error: "exit_code"), ["swift throw"], "the top rung")
        rig.now += 121_000
        XCTAssertEqual(run(rig, "7", program: "swift", failed: true, error: "exit_code"), ["swift bonk"], "2 minutes on")
    }

    /// A lookup that exits 1 found nothing: a shrug. A timeout, a request
    /// you denied, a check: each its own.
    func testEachFailuresGag() {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        run(rig, "0", program: "ls")
        for (i, (topic, program, error, expected)) in [
            ("inspect", "grep", "exit_code", "grep shrug"), (nil, "curl", "timeout", "timeout timeout"),
            (nil, "rm", "denied", "NO no"), ("tests", "pytest", "exit_code", "FAIL hail"),
            ("build", "make", "exit_code", "FAIL topple"),
        ].enumerated() {
            rig.now += 3000
            XCTAssertEqual(run(rig, "\(i + 1)", ms: 4000, topic: topic, program: program, failed: true, error: error).last, expected)
        }
    }

    /// A check comes forward as it starts, and with its result.
    func testAChecksStartAndResult() {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        run(rig, "0", program: "ls")
        rig.now += 3000
        XCTAssertEqual(run(rig, "1", ms: 4000, topic: "tests", program: "make test"), ["make test cross", "PASS pass"])
        rig.now += 3000
        XCTAssertEqual(run(rig, "2", ms: 4000, topic: "build", program: "make"), ["build stack", "built built"])
    }

    /// A notable call waits up to 1.5 s for the board (`waitMs`), and is
    /// dropped past that; an ambient one isn't sent at all while one plays.
    func testANotableCallWaitsBriefly() {
        XCTAssertEqual(WorkStream.waitMs, 1500)
        var s = WorkStream()
        let notable = WorkStream.Forward(slot: 0, word: "x", gag: "land", priority: .notable)
        XCTAssertNotNil(s.offer(notable, at: 0))
        XCTAssertNil(s.offer(notable, at: 500), "2 s left of the 2.5 s")
        XCTAssertNotNil(s.offer(notable, at: 1000), "free in 1.5 s")
        XCTAssertEqual(s.lastForwardAt, 2500, "it plays when the board frees")
        XCTAssertNil(s.offer(WorkStream.Forward(slot: 0, word: "y", gag: "land", priority: .ambient), at: 3000),
                     "an ambient one never waits")
        XCTAssertNotNil(s.offer(WorkStream.Forward(slot: 0, word: "z", gag: "bonk", priority: .always), at: 3000),
                        "a sure one cuts a notable one")
        XCTAssertNil(s.offer(WorkStream.Forward(slot: 0, word: "z", gag: "bonk", priority: .always), at: 3200),
                     "and waits only 1.5 s behind another sure one")
    }

    /// The same word from one session, each within 3 s of the last, is a
    /// combo that comes forward at 5, 10 and 20 (`comboGapMs`, `combos`).
    func testARunIsACombo() {
        XCTAssertEqual(WorkStream.comboGapMs, 3000)
        XCTAssertEqual(WorkStream.combos, [5, 10, 20])
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        run(rig, "0", program: "ls")
        rig.now += 9000
        var sent: [String] = []
        for i in 1...10 {
            rig.now += 2000
            sent += run(rig, "\(i)", topic: "inspect", program: "sed")
        }
        XCTAssertEqual(sent, ["sed look", "sed combo", "sed combo"], "the first ambient, then the 5th and 10th")
        let args = rig.log.compactMap { if case .call(let a) = $0 { return a } else { return nil } }
        XCTAssertEqual(args.compactMap { $0["n"]?.int }, [5, 10])
    }

    /// An edit of 100 lines or more is notable: a deletion shatters.
    func testABigEdit() {
        XCTAssertEqual(WorkStream.bigEdit, 100)
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        run(rig, "0", program: "ls")
        rig.now += 3000
        XCTAssertEqual(run(rig, "1", tool: "Edit", added: 2, removed: 400), ["-400 shatter"])
        rig.now += 3000
        XCTAssertEqual(run(rig, "2", tool: "Write", added: 120), ["edit +120 land"])
        rig.now += 3000
        XCTAssertEqual(run(rig, "3", tool: "Edit", added: 3), [], "a small edit is ambient, 3 s after the last")
    }

    /// Each working session has a lane in `state`, `[slot, calls, word]`,
    /// no project's name, while nothing needs you; a new word alone waits 250 ms
    /// after the last `state` (`sendEveryMs`). The lane goes when its turn
    /// ends.
    func testTheLanesInTheState() throws {
        XCTAssertEqual(WorkStream.sendEveryMs, 250)
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        rig.send(.turnStart, session: "s2")
        rig.now += 1000
        let first = states(rig.send(call(rig, "1", program: "grep")))
        XCTAssertEqual(first.last?.calls, [StateSnapshot.Call(slot: 0, count: 1, word: "grep")])
        XCTAssertTrue(first.last!.jsonLine.contains(#""calls":[[0,1,"grep"]]"#), first.last!.jsonLine)
        XCTAssertFalse(first.last!.jsonLine.contains("landing"), "no project's name")
        rig.now += 100
        XCTAssertEqual(states(rig.send(call(rig, "2", program: "sed", session: "s2"))), [], "100 ms after the last state")
        rig.now += 200
        let both = states(rig.send(call(rig, "3", program: "rg")))
        XCTAssertEqual(both.last?.calls.map { [$0.slot, $0.count] }, [[0, 2], [1, 1]])
        XCTAssertEqual(both.last?.calls.map(\.word), ["rg", "sed"])
        rig.send(.turnEnd)
        XCTAssertEqual(rig.state.calls.map(\.slot), [1], "s1 rests")
        rig.send(.needsYou, session: "s2", tool: "Bash")
        XCTAssertEqual(rig.state.calls, [], "the needs-you screen clears the stream")
    }

    /// Four lanes at most (`WorkStream.maxLanes`), each its own slot: a
    /// fifth session at work gets none, and no other's slot, until one
    /// frees, when its next call takes it.
    func testAFifthSessionWaitsForALane() {
        let rig = CoreRig(workStream: true)
        for n in 1...5 {
            rig.send(.turnStart, session: "s\(n)")
            rig.now += 300
            rig.send(call(rig, "\(n)", program: "rg", session: "s\(n)"))
            rig.now += 300
        }
        XCTAssertEqual(rig.state.calls.map(\.slot), [0, 1, 2, 3], "four lanes, no slot twice")
        rig.send(.turnEnd, session: "s2")
        rig.now += 300
        rig.send(call(rig, "6", program: "sed", session: "s5"))
        XCTAssertEqual(rig.state.calls.map(\.slot), [0, 1, 2, 3], "the fifth takes the freed slot")
        XCTAssertEqual(rig.state.calls.first { $0.slot == 1 }?.word, "sed")
    }

    /// The `state` with four lanes of the longest words, and
    /// many tags, fits the board's 512 bytes with room to spare.
    func testAFullStateFitsTheBoard() {
        let lanes = (0..<WorkStream.maxLanes).map {
            StateSnapshot.Call(slot: $0, count: 999, word: String(repeating: "w", count: WorkStream.maxWordBytes))
        }
        let s = StateSnapshot(base: "working", act: "delegating", mood: "overwhelmed", attn: nil, busy: 12, idle: 9,
                              helpers: 20, vol: 10, when: ["evening", "friday", "halloween", "tier5", "pal", "chonk", "legend", "reading"],
                              todo: .init(done: 99, total: 99), calls: lanes)
        XCTAssertLessThan(s.jsonLine.utf8.count, 440, s.jsonLine)
    }

    /// No call wakes the brain, and none is a line: a word that came
    /// forward is a `did` with no message. The moments that hit Boop are
    /// a note on the next working check-in, then the finish says only
    /// those since.
    func testTheBrainHearsOnlyTheHitsAtAPassItHasAnyway() throws {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        let before = rig.views.filter(\.wakesBrain).count
        run(rig, "0", program: "ls")
        rig.now += 3000
        run(rig, "1", program: "make", failed: true, error: "exit_code")
        rig.now += 3000
        run(rig, "2", program: "make", failed: true, error: "exit_code")
        XCTAssertEqual(rig.views.filter(\.wakesBrain).count, before, "no call woke the brain")
        let dids = rig.pipeline.transcript.events.filter { $0.kind == Event.did && $0.action == WorkStream.action }
        XCTAssertEqual(dids.map { $0["as"]?.string }, ["arrive", "bonk", "bonk2"])
        XCTAssertTrue(dids.allSatisfy { $0["message"] == nil }, "HISTORY doesn't list them")

        let beat = rig.wait(200_000).views.first { $0.type == .heartbeat }
        XCTAssertEqual(beat?.notes.last, "Failed commands hit Boop in the face twice.", "\(String(describing: beat))")
        rig.now += 1000
        run(rig, "3", program: "curl", failed: true, error: "timeout")
        let finish = try XCTUnwrap(rig.send(.turnEnd).views.first { $0.type == .turn && $0.phase == .end })
        XCTAssertEqual(finish.notes.last, "A command timed out and landed on Boop's head.", "only what's new since")
    }

    /// A glimpse is for the board alone: no line or note the brain reads
    /// says any piece of it, a failure's and a finish's included.
    func testTheBrainNeverHearsAGlimpse() {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        for id in 0..<6 {
            rig.now += 3000
            rig.send(call(rig, "\(id)", program: "sed", glimpse: "PlanB.swift acmeSecret"))
            rig.now += 200
            rig.send(call(rig, "\(id)", program: "sed", glimpse: "PlanB.swift acmeSecret", failed: id > 2,
                          error: id > 2 ? "exit_code" : nil))
        }
        rig.wait(200_000)
        rig.send(.turnEnd)
        let heard = rig.views.flatMap { [$0.line] + $0.notes }.joined(separator: "\n")
        XCTAssertFalse(heard.contains("PlanB") || heard.contains("acmeSecret"), heard)
        let shown = rig.pipeline.transcript.events.compactMap { $0["word"]?.string }
        XCTAssertTrue(shown.contains { $0 == "PlanB.swift" || $0 == "acmeSecret" }, "the board does show it: \(shown)")
    }

    /// The third and fourth failures within the ladder's two minutes
    /// (`TranscriptView.wakingRungs`, 3...4), the helmet and the throw,
    /// are a line that wakes the brain while the turn goes on. The first
    /// two and any past the fourth are only bonks, and a denial or a
    /// timeout doesn't climb.
    func testTheLaddersTopRungsWakeTheBrain() {
        XCTAssertEqual(TranscriptView.wakingRungs, 3...4)
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart)
        func fail(_ id: String, error: String = "exit_code") -> [String] {
            rig.now += 3000
            let before = rig.views.count
            run(rig, id, program: "make", failed: true, error: error)
            return rig.views[before...].filter(\.wakesBrain).map(\.line)
        }
        XCTAssertEqual(fail("1"), [])
        XCTAssertEqual(fail("2", error: "denied"), [], "you said no")
        XCTAssertEqual(fail("3", error: "timeout"), [])
        XCTAssertEqual(fail("4"), [])
        XCTAssertEqual(fail("5"), [#"claude's commands keep failing on "landing": 3 in 2 minutes, each one hitting Boop in the face. The turn goes on."#])
        XCTAssertEqual(fail("6").count, 1, "the throw")
        XCTAssertEqual(fail("7"), [], "past the top rung")
        rig.now += WorkStream.ladderMs
        XCTAssertEqual(fail("8"), [], "a new climb")
    }

    /// A word that comes forward waits on the board at most 1.5 s
    /// (`BoopDevice.callTTL`): it was news only just now.
    func testAWordForwardWaitsOnlyBriefly() {
        XCTAssertEqual(BoopDevice.callTTL, 1500)
    }

    /// A turn's end comes forward by how it went, if the turn called a
    /// tool: done gathers its words; a full context buries it; a rate limit
    /// or an overload freezes them; another failure, or you stopping it,
    /// drops them. A compaction squashes them into a cube. A turn with no
    /// call brings nothing.
    func testTheWholeTurnsMoments() {
        let rig = CoreRig(workStream: true)
        func turn(_ end: () -> Fx) -> [String] {
            rig.now += 10_000
            rig.send(.turnStart)
            run(rig, "c\(rig.now)", program: "ls")
            rig.now += 3000
            return calls(end())
        }
        XCTAssertEqual(turn { rig.send(.turnEnd) }, ["done gather"])
        XCTAssertEqual(turn { rig.send(.turnFailed, error: "context_limit") }, ["context full buried"])
        XCTAssertEqual(turn { rig.send(.turnFailed, error: "rate_limit") }, ["rate limit freeze"])
        XCTAssertEqual(turn { rig.send(.turnFailed, error: "overloaded") }, ["overloaded freeze"])
        XCTAssertEqual(turn { rig.send(.turnFailed, error: "api_error") }, ["failed drop"])
        XCTAssertEqual(turn { rig.send(.turnStopped) }, ["stopped drop"])
        rig.now += 10_000
        rig.send(.turnStart)
        XCTAssertEqual(calls(rig.send(.turnEnd)), [], "no call this turn")
        rig.now += 10_000
        rig.send(.turnStart)
        run(rig, "x", program: "ls")
        rig.now += 3000
        XCTAssertEqual(calls(rig.send(.sessionStart, source: Mapping.compacted)), ["context compact"])
    }

    /// Turned off, the stream sends nothing.
    func testTurnedOff() {
        let rig = CoreRig(workStream: false)
        rig.send(.turnStart)
        XCTAssertEqual(run(rig, "1", program: "grep"), [])
        XCTAssertEqual(rig.state.calls, [])
    }
}
