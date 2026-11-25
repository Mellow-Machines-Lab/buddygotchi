import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// Quiet: Talk's one setting below normal, and quiet for a while, which
/// "shh", the hush reply and the popover's button set for half an hour.
final class QuietTests: XCTestCase {
    let min: Int64 = 60_000
    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// Pins `Core.quietForMs` (30 min): Talk is quiet for that long, then
    /// the setting's again, by itself. Nothing is logged for it, and the
    /// board hears nothing of it.
    func testQuietForAWhileLastsHalfAnHour() {
        XCTAssertEqual(Core.quietForMs, 30 * min)
        XCTAssertEqual(Talk.allCases, [.quiet, .normal], "quiet or normal")
        let rig = CoreRig()
        let start = rig.now
        XCTAssertEqual(rig.core.talk(.normal, at: start), .normal)
        rig.core.quiet(at: start)
        XCTAssertEqual(rig.core.quietUntil(at: start), start + 30 * min)
        XCTAssertEqual(rig.core.talk(.normal, at: start + 30 * min - 1), .quiet)
        XCTAssertEqual(rig.core.talk(.normal, at: start + 30 * min), .normal, "over at 30 min")
        XCTAssertNil(rig.core.quietUntil(at: start + 30 * min))
        XCTAssertFalse(rig.core.snapshot(at: start).when.contains("hushed"), "no tag for it")
        XCTAssertEqual(rig.core.talk(.quiet, at: start + 31 * min), .quiet, "the setting stays what it was")
    }

    /// Talking to Boop ends it, and so does the popover (`endQuiet`).
    func testTalkingToItEndsTheQuiet() {
        let rig = CoreRig()
        rig.core.quiet(at: rig.now)
        rig.note(Fx(rig.pipeline.said("okay, you can talk now", by: .app, at: rig.now + min)))
        XCTAssertNil(rig.core.quietUntil(at: rig.now + min), "your words end it, before their pass")
        rig.core.quiet(at: rig.now)
        rig.core.endQuiet()
        XCTAssertNil(rig.core.quietUntil(at: rig.now))
    }

    /// The hush reply makes it quiet from there on: the reply itself is
    /// said as Talk had it, and a launch reads it back from the reply's
    /// record, with what you said after ending it.
    func testTheHushReplyMakesItQuiet() {
        var quietAt: [Int64] = []
        var sent: [Moment] = []
        let react = MomentOutput(queue: { m, _ in sent.append(m) }, blocked: { nil }, quiet: { quietAt.append($0) })
        let said = Event(at: 5000, source: .mic, type: .said, specificType: "device", data: ["words": "shh"])
        let log = Transcript.log().view(now: 5000)
        XCTAssertEqual(react.questions(now: said, log: log).first { $0.key == MomentOutput.replyKey }?.options.map(\.name).last, "hush")
        XCTAssertFalse(react.questions(now: said, log: log).contains { $0.options.contains { $0.name == "unhush" } }, "no reply ends it: your words do")
        _ = react.run([MomentOutput.emotionKey: a("annoyed"), MomentOutput.replyKey: a("hush")], now: said, log: log)
        XCTAssertEqual(quietAt, [5000])
        XCTAssertEqual(sent.last?.reply, "hush", "its clip plays")

        let core = Core(config: .init())
        core.replay(Event.did("Boop replied hush", for: 1, action: MomentOutput.outputName, by: "brain", facts: ["reply": "hush"], at: 5000))
        XCTAssertEqual(core.quietUntil(at: 6000), 5000 + Core.quietForMs, "the next launch keeps it")
        core.replay(Event(at: 7000, source: .mic, type: .said, specificType: "device", data: ["words": "hi"]))
        XCTAssertNil(core.quietUntil(at: 8000))
    }

    /// On Quiet, the setting's or for a while: a small moment and a finish
    /// say nothing, a bigger skit may, and nothing swears.
    func testQuietSaysLittle() throws {
        try requireVoice()
        var sent: [Moment] = []
        var facts: [String: JSONValue] = [:]
        let react = MomentOutput(queue: { m, _ in sent.append(m) }, blocked: { nil }, talk: { .quiet }, line: { _ in Line("", facts: facts) })
        let log = Transcript.log().view(now: 0)
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        _ = react.run([MomentOutput.emotionKey: a("amused")], now: poke, log: log)
        XCTAssertEqual(sent.last?.say?.takes.count, 0, "a small moment says nothing")
        XCTAssertEqual(sent.last?.mood, "amused", "its face goes on")
        let finish = Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        facts = ["outcome": "done", "length_ms": 180_000, "length": "long", "tools": 3]
        _ = react.run([MomentOutput.emotionKey: a("proud")], now: finish, log: log)
        XCTAssertEqual(sent.last?.say?.takes.count, 0, "a finish says nothing, the win skit's included")
        let check = Event(at: 0, source: .claude, type: .tool, phase: .end, specificType: "PostToolUse")
        facts = ["topic": "tests", "result": "ok", "failed_before": 2]
        _ = react.run([MomentOutput.emotionKey: a("proud")], now: check, log: log)
        XCTAssertEqual(sent.last?.say?.takes.map(\.meaning), ["fix"], "a bigger skit may, with no sound before it")
        facts = ["topic": "tests", "result": "failed", "failed_before": 2]
        _ = react.run([MomentOutput.emotionKey: a("grumpy")], now: check, log: log)
        let upset = try XCTUnwrap(sent.last?.say?.takes.last)
        XCTAssertEqual(upset.meaning, "upset")
        XCTAssertNotEqual(upset.kind, .swear, "nothing swears")
    }
}
