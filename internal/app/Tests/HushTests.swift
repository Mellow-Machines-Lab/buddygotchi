import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The hush: told to be quiet, Boop says nothing for a while, its faces
/// going on; and Quiet, the Talk setting, held to in code.
final class HushTests: XCTestCase {
    let min: Int64 = 60_000
    func a(_ choice: String, _ p: Double = 0.9) -> Answer { Answer(choice: choice, probabilities: [choice: p]) }

    /// Pins `Core.hushMs` (the app's 30 min) and `hushMsBySize` (15, 30,
    /// 60, 120 min by the reply's intensity): the core keeps the hush, the
    /// board gets `hushed` while it lasts, and its end is recorded at the
    /// time it ran out.
    func testAHushLastsItsTimeAndEndsByItself() throws {
        XCTAssertEqual(Core.hushMs, 30 * min)
        XCTAssertEqual(Core.hushMsBySize, [15 * min, 30 * min, 60 * min, 120 * min])
        let rig = CoreRig()
        let start = rig.now
        let fx = rig.note(Fx(rig.pipeline.effects(rig.core.hush(forMs: Core.hushMs, by: .app, at: rig.now), at: rig.now)))
        XCTAssertEqual(rig.core.hushed(at: rig.now), Core.Hush(by: .app, until: start + 30 * min))
        XCTAssertTrue(fx.contains { if case .state(let s) = $0 { return s.when.contains(Occasions.hushed) } else { return false } },
                      "the board hears of it")
        let hush = try XCTUnwrap(rig.pipeline.transcript.view(now: rig.now).events.last { $0.type == .hush })
        XCTAssertEqual(hush.phase, .start)
        XCTAssertEqual(hush["until"]?.int, start + 30 * min)
        rig.wait(30 * min - 1000)
        XCTAssertNotNil(rig.core.hushed(at: rig.now))
        rig.wait(2000)
        XCTAssertNil(rig.core.hushed(at: rig.now), "over at 30 min")
        XCTAssertFalse(rig.core.snapshot(at: rig.now).when.contains(Occasions.hushed))
        let end = try XCTUnwrap(rig.pipeline.transcript.view(now: rig.now).events.last { $0.type == .hush })
        XCTAssertEqual(end.phase, .end)
        XCTAssertEqual(end.specificType, "timer")
        XCTAssertEqual(end.at, start + 30 * min, "recorded at the time it ran out")
    }

    /// Let talk again early: recorded with who; a hush read back from the
    /// transcript holds on the next launch.
    func testAHushEndsEarlyAndHoldsAcrossALaunch() {
        let rig = CoreRig()
        rig.note(Fx(rig.pipeline.effects(rig.core.hush(forMs: Core.hushMs, by: .talk, at: rig.now), at: rig.now)))
        let core = Core(config: rig.core.config)
        for e in rig.pipeline.transcript.view(now: rig.now).events { core.replay(e) }
        XCTAssertEqual(core.hushed(at: rig.now + 10 * min)?.by, .talk, "the next launch keeps it")
        rig.note(Fx(rig.pipeline.effects(rig.core.unhush(by: .app, at: rig.now + min), at: rig.now + min)))
        XCTAssertNil(rig.core.hushed(at: rig.now + min))
        XCTAssertTrue(rig.core.unhush(by: .app, at: rig.now + 2 * min).allSatisfy { if case .record = $0 { return false } else { return true } },
                      "nothing to end: nothing recorded")
    }

    /// The app's hush is a line that wakes the brain (Boop sulks); one by
    /// what you said doesn't, its reply being the pass; its end never does.
    func testTheAppsHushWakesTheBrain() {
        let rig = CoreRig()
        let fx = rig.note(Fx(rig.pipeline.effects(rig.core.hush(forMs: Core.hushMs, by: .app, at: rig.now), at: rig.now)))
        let line = fx.views.first { $0.line.contains("hushed") }
        XCTAssertEqual(line?.line, "You hushed \(creature) from the Mac: it says nothing for 30 min.")
        XCTAssertEqual(line?.wakesBrain, true)
        let ended = rig.wait(31 * min).views.first { $0.line.contains("hush") }
        XCTAssertEqual(ended?.line, "\(creature)'s hush ran out: it may talk again.")
        XCTAssertEqual(ended?.wakesBrain, false)
        let talked = rig.note(Fx(rig.pipeline.effects(rig.core.hush(forMs: Core.hushMs, by: .talk, at: rig.now), at: rig.now)))
        XCTAssertEqual(talked.views.first { $0.line.contains("hushed") }?.wakesBrain, false)
    }

    /// While hushed, `say` isn't asked and nothing is said, a face and its
    /// move going on; what you said is offered `unhush`. A `hush` reply
    /// hushes it for as long as the moment is big, an `unhush` lets it talk.
    func testHushedItSaysNothing() throws {
        try requireVoice()
        var hushedNow = false
        var hushes: [Int64?] = []
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, hushed: { _ in hushedNow },
                                hush: { ms, _ in hushes.append(ms) })
        let log = Transcript.log().view(now: 0)
        let said = Event(at: 0, source: .mic, type: .talk, specificType: "device", data: ["words": "shh"])
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        XCTAssertTrue(react.questions(now: poke, log: log).contains { $0.key == ReactOutput.sayKey })
        XCTAssertFalse(react.questions(now: said, log: log).first { $0.key == ReactOutput.moveKey }!.options.contains { $0.name == "unhush" },
                       "unhush is offered only while hushed")
        _ = react.run(["react.face": a("disappointed"), "react.move": a("hush"), "react.intensity": a("big"), "say": a("upset")],
                      now: said, log: log)
        XCTAssertEqual(hushes, [60 * min], "a big hush: an hour")
        XCTAssertEqual(queued.last?.reply, "hush")
        hushedNow = true
        XCTAssertFalse(react.questions(now: poke, log: log).contains { $0.key == ReactOutput.sayKey }, "no say while hushed")
        XCTAssertTrue(react.questions(now: said, log: log).first { $0.key == ReactOutput.moveKey }!.options.contains { $0.name == "unhush" })
        XCTAssertTrue(react.questions(now: said, log: log).contains { $0.key == ReactOutput.sayKey }, "what you said is asked it, for an unhush")
        _ = react.run(["react.face": a("sad"), "react.move": a("comfort"), "say": a("upset")], now: said, log: log)
        XCTAssertEqual(queued.last?.say?.takes, [], "any other reply says nothing")
        _ = react.run(["react.face": a("grumpy"), "say": a("upset"), "react.intensity": a("medium")], now: poke, log: log)
        XCTAssertEqual(queued.last?.mood, "grumpy", "its face goes on")
        XCTAssertEqual(queued.last?.say?.takes, [], "but it says nothing")
        _ = react.run(["react.face": a("happy"), "react.move": a("unhush"), "say": a("glad")], now: said, log: log)
        XCTAssertEqual(hushes.last, .some(nil), "let talk again")
        XCTAssertFalse(queued.last?.say?.takes.isEmpty ?? true, "and the reply that lets it talk speaks")
    }

    /// On Quiet, `say` offers no topic and no swear, and a small moment or
    /// a finish says nothing; Normal and Chatty offer every one.
    func testQuietHoldsInCode() throws {
        try requireVoice()
        var talk = Talk.quiet
        var queued: [DeviceReaction] = []
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, talk: { talk })
        let log = Transcript.log().view(now: 0)
        let poke = Event(at: 0, source: .device, type: .poke, specificType: "input")
        let quiet = try XCTUnwrap(react.questions(now: poke, log: log).first { $0.key == ReactOutput.sayKey })
        XCTAssertEqual(quiet.options.map(\.name), ["none", "upset", "glad", "tickled"])
        _ = react.run(["react.face": a("amused"), "say": a("tickled"), "react.intensity": a("small")], now: poke, log: log)
        XCTAssertEqual(queued.last?.say?.takes, [], "a small moment says nothing")
        _ = react.run(["react.face": a("happy"), "react.move": a("success"), "say": a("glad"), "react.intensity": a("big")], now: poke, log: log)
        XCTAssertEqual(queued.last?.say?.takes, [], "nor a finish, however big")
        XCTAssertEqual(queued.last?.anim, "task_complete", "which still plays")
        _ = react.run(["react.face": a("amused"), "say": a("tickled"), "react.intensity": a("medium")], now: poke, log: log)
        XCTAssertFalse(queued.last?.say?.takes.isEmpty ?? true, "a medium moment says how it feels")
        for t in [Talk.normal, .chatty] {
            talk = t
            XCTAssertEqual(react.questions(now: poke, log: log).first { $0.key == ReactOutput.sayKey }?.options.count, 21, t.rawValue)
        }
    }
}
