import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The wish: Boop's one want a day. The brain picks when; code holds what
/// meets it, the caps and the wait.
final class WishTests: XCTestCase {
    func wishEvents(_ fx: Fx) -> [String] {
        events(fx).filter { $0.type == .wish }.map { "\($0.name) \($0.facts["wish"]?.string ?? "")" }
    }

    func rig() -> CoreRig {
        let rig = CoreRig()
        rig.send(.turnStart, prompt: "fix it")
        rig.send(.turnEnd)
        return rig
    }

    /// Pins the gates (`Core.wishable`): one open, and how many a day is
    /// Jev's; none while something needs you or you're away; `work` not
    /// while an agent works.
    func testOneOpenAndItsGates() {
        let rig = rig()
        XCTAssertEqual(rig.core.wishable(at: rig.now), Core.WishKind.allCases)
        rig.send(.turnStart, prompt: "next")
        XCTAssertEqual(rig.core.wishable(at: rig.now), [.pet, .chat], "work only while no agent works")
        rig.send(.turnEnd)
        _ = rig.core.presence(away: true, at: rig.now)
        XCTAssertEqual(rig.core.wishable(at: rig.now), [], "away")
        _ = rig.core.presence(away: false, at: rig.now)
        rig.core.makeWish(.pet, at: rig.now)
        XCTAssertEqual(rig.core.wish?.kind, .pet)
        XCTAssertEqual(rig.core.wishable(at: rig.now), [], "one open")
        rig.note(Fx(rig.pipeline.gesture("stroke", at: rig.now)))
        XCTAssertNil(rig.core.wish, "met")
        XCTAssertEqual(rig.core.wishable(at: rig.now), Core.WishKind.allCases, "no cap on how many a day")
    }

    /// What meets each kind, at once, by a rule, and nothing else does.
    func testWhatMeetsEachKind() {
        var r = rig()
        r.core.makeWish(.pet, at: r.now)
        let met = r.note(Fx(r.pipeline.gesture("stroke", at: r.now)))
        XCTAssertEqual(wishEvents(met).last, "wish end met")
        XCTAssertTrue(moments(met).contains { $0.anim == Core.wishMet }, "the board's fulfilment")

        r = rig()
        r.core.makeWish(.chat, at: r.now)
        r.note(Fx(r.pipeline.said("hello", by: .app, at: r.now)))
        XCTAssertNil(r.core.wish, "any push-to-talk")

        r = rig()
        r.core.makeWish(.work, at: r.now)
        r.send(.turnStart, prompt: "and the next thing")
        XCTAssertNil(r.core.wish, "a prompt you sent")
    }

    /// Which touches meet a pet wish: a stroke, a poke, a nose boop, a tickle
    /// and the wrong-way stroke; not a shake, a pick-up or face down, nor
    /// anything else that isn't a hand on its face.
    func testWhichTouchesMeetAPetWish() {
        XCTAssertEqual(Set(Touch.allCases.filter(\.meetsPetWish)), [.poke, .stroke, .ruffle, .nose, .tickle])
        for touch in Touch.allCases where touch != .poke {
            let r = rig()
            r.core.makeWish(.pet, at: r.now)
            let fx = r.note(Fx(r.pipeline.gesture(touch.rawValue, at: r.now)))
            XCTAssertEqual(r.core.wish == nil, touch.meetsPetWish, touch.rawValue)
            XCTAssertEqual(moments(fx).contains { $0.anim == Core.wishMet }, touch.meetsPetWish, touch.rawValue)
        }
        // Only a pet wish.
        let chat = rig()
        chat.core.makeWish(.chat, at: chat.now)
        chat.note(Fx(chat.pipeline.gesture("stroke", at: chat.now)))
        XCTAssertNotNil(chat.core.wish, "a stroke isn't a chat")
    }

    /// A poke on its face meets it, the heart popping; BOOT's poke isn't a
    /// touch, and a poke that opens a thread is that and no more.
    func testAPokeMeetsAPetWish() {
        let r = rig()
        r.core.makeWish(.pet, at: r.now)
        let met = r.note(Fx(r.pipeline.poke(at: r.now)))
        XCTAssertEqual(wishEvents(met).last, "wish end met")
        XCTAssertTrue(moments(met).contains { $0.anim == Core.wishMet })

        let button = CoreRig()
        button.core.wish = Core.Wish(kind: .pet, since: button.now, countedTo: button.now)
        button.note(Fx(button.pipeline.press(at: button.now)))
        XCTAssertNotNil(button.core.wish, "BOOT with nobody in line")

        let onFinish = rig()
        onFinish.core.makeWish(.pet, at: onFinish.now)
        onFinish.note(Fx(onFinish.pipeline.poke(at: onFinish.now, finish: ThreadRef(agent: "claude", session: "s"))))
        XCTAssertNotNil(onFinish.core.wish, "it opened the thread")
    }

    /// Pins `Core.wishGivesUpMs`: three hours you could have answered, away
    /// and asleep not counting; then the rule's Moment, which wakes Jev.
    func testItWaitsOnlyWhileYouCouldAnswerThenGivesUp() {
        XCTAssertEqual(Core.wishGivesUpMs, 3 * 3_600_000)
        let r = rig()
        r.core.makeWish(.pet, at: r.now)
        r.wait(600_000, every: 60_000)
        XCTAssertEqual(r.core.wish?.waitedMs, 600_000, "here")
        XCTAssertEqual(r.state.wish, "pet", "the board shows it")
        r.pipeline.presence(Event(at: r.now, source: .mac, type: .presence, phase: .start, specificType: "locked",
                                  data: ["since": .int(r.now)]))
        r.wait(3_600_000, every: 60_000)
        XCTAssertEqual(r.core.wish?.waitedMs, 600_000, "away doesn't count")
        XCTAssertNil(r.core.snapshot(at: r.now).wish, "nor shows")
        r.pipeline.presence(Event(at: r.now, source: .mac, type: .presence, phase: .end, specificType: "unlocked"))
        var fx = Fx()
        for _ in 0..<40 where r.core.wish != nil {
            r.send(.turnStart, prompt: "keep it awake")
            fx = r.wait(300_000, every: 60_000)
            r.send(.turnEnd)
        }
        XCTAssertNil(r.core.wish)
        XCTAssertEqual(r.core.wishEnded?.how, .gaveup)
    }

    /// It closes quietly when Boop's day ends: no Moment, and no pass.
    func testItClosesQuietlyAtFive() {
        let core = Core(config: .init(time: LocalTime(timeZone: TimeZone(identifier: "UTC")!)))
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let evening = Int64(c.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 22))!.timeIntervalSince1970 * 1000)
        core.setWallClock(evening, at: evening)
        _ = core.handle(Event(at: evening, source: .claude, type: .session, phase: .start, specificType: "SessionStart", session: "s", data: ["agent": "claude"]))
        core.wish = Core.Wish(kind: .pet, since: evening, countedTo: evening)
        let fx = core.tick(at: evening + 8 * 3_600_000)
        XCTAssertNil(core.wish)
        XCTAssertEqual(core.wishEnded?.how, .closed)
        XCTAssertFalse(fx.contains { if case .reaction = $0 { true } else { false } })
    }

    /// Kept like the hush: a launch reads an open wish back.
    func testALaunchReadsItBack() {
        let r = rig()
        let other = CoreRig()
        other.core.replay(Event(at: r.now, source: .boop, type: .wish, phase: .start, specificType: "chat"))
        XCTAssertEqual(other.core.wish?.kind, .chat)
        other.core.replay(Event(at: r.now, source: .boop, type: .wish, phase: .end, specificType: "met", data: ["kind": "chat"]))
        XCTAssertNil(other.core.wish)
    }

    /// CONTEXT's rows say the facts; the board's wire has the kind.
    func testContextSaysIt() {
        let r = rig()
        XCTAssertTrue(r.core.wishRow(at: r.now, name: "Boop")?.hasPrefix("no wish yet today") == true)
        XCTAssertFalse(r.core.wishRow(at: r.now, name: "Boop")?.contains("half gone") == true, "the nudge is only for an idle check-in")
        r.core.makeWish(.pet, at: r.now)
        XCTAssertEqual(r.core.wishRow(at: r.now, name: "Boop"), "Boop's wish: a pet, waiting 1 min while you were here")
        XCTAssertTrue(r.state.jsonLine.contains(#""wish":"pet""#), r.state.jsonLine)
        r.note(Fx(r.pipeline.gesture("stroke", at: r.now)))
        XCTAssertNil(r.core.wishRow(at: r.now, name: "Boop"))
        XCTAssertEqual(r.core.wishToday(at: r.now, name: "Boop"), "Boop's wish today: met.")
    }

    /// The nudge, from noon, and only at an idle check-in: elsewhere, such as
    /// at a poke, it would only press.
    func testTheDaysHalfGoneOnlyAtAnIdleCheckIn() {
        let core = Core(config: .init(time: LocalTime(timeZone: TimeZone(identifier: "UTC")!)))
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let afternoon = Int64(c.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15))!.timeIntervalSince1970 * 1000)
        let morning = afternoon - 6 * 3_600_000
        core.setWallClock(afternoon, at: afternoon)
        XCTAssertEqual(core.wishRow(at: afternoon, name: "Boop", idle: true), "no wish yet today, and the day's half gone")
        XCTAssertEqual(core.wishRow(at: afternoon, name: "Boop"), "no wish yet today")
        XCTAssertEqual(core.wishRow(at: morning, name: "Boop", idle: true), "no wish yet today")
    }

    /// Showing how: until you've met a kind once, the pack's longer sign and
    /// `state.wish_how`; a "done once" kept per kind ends both for that kind.
    func testDoneOnceEndsTheShowingHow() throws {
        let lines = TaggedLine.parse("""
            - [wish pet] pet me?
            - [wish pet how] stroke my face?
            - [wish chat] talk to me?
            """)
        XCTAssertEqual(Asks.wishSign(lines, .pet, showsHow: true), "stroke my face?")
        XCTAssertEqual(Asks.wishSign(lines, .pet), "pet me?")
        XCTAssertEqual(Asks.wishSign(lines, .chat, showsHow: true), "talk to me?", "a pack with no such line")

        let r = rig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: r.time)
        memory.attach(to: r.pipeline)
        r.core.wishDone = memory.wishDone
        XCTAssertFalse(memory.wishDone(.pet))
        r.core.makeWish(.pet, at: r.now)
        XCTAssertTrue(r.core.snapshot(at: r.now).wishHow)
        XCTAssertTrue(r.core.snapshot(at: r.now).jsonLine.contains(#""wish_how":true"#))
        r.note(Fx(r.pipeline.gesture("stroke", at: r.now)))
        XCTAssertTrue(memory.wishDone(.pet), "done once")
        XCTAssertFalse(memory.wishDone(.chat), "for that kind")
        r.core.makeWish(.pet, at: r.now)
        XCTAssertEqual(r.core.snapshot(at: r.now).wish, "pet")
        XCTAssertFalse(r.core.snapshot(at: r.now).wishHow, "still, from here on")
        XCTAssertFalse(r.core.snapshot(at: r.now).jsonLine.contains("wish_how"))
        r.note(Fx(r.pipeline.gesture("stroke", at: r.now)))
        r.core.makeWish(.chat, at: r.now)
        XCTAssertTrue(r.core.snapshot(at: r.now).wishHow, "a kind not yet met")
    }

    /// The sign question offers its how sign until done, then the plain one.
    func testTheSignOfferedFollowsDoneOnce() throws {
        let lines = TaggedLine.parse("""
            - [wish pet] pet me?
            - [wish pet how] stroke my face?
            """)
        var done = false
        var made: [Core.WishKind] = []
        let react = MomentOutput(queue: { _, _ in }, blocked: { nil }, asks: lines, wishable: { _, _ in [.pet] },
                                 makeWish: { k, _ in made.append(k) }, wishDone: { _ in done })
        let log = Transcript.log().view(now: 0)
        let checkIn = Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in")
        func offered() throws -> [String] {
            try XCTUnwrap(react.questions(now: checkIn, log: log).first { $0.key == Signs.questionKey }).options.map(\.name)
        }
        XCTAssertEqual(try? offered(), ["none", "stroke my face?"])
        _ = react.run(["react.face": Answer(choice: "curious", probabilities: ["curious": 1]),
                       Signs.questionKey: Answer(choice: "stroke my face?", probabilities: ["stroke my face?": 1])], now: checkIn, log: log)
        XCTAssertEqual(made, [.pet], "the how sign makes the wish")
        done = true
        XCTAssertEqual(try? offered(), ["none", "pet me?"])
    }

    /// The sign question offers the pack's wishes at an ask's moment, and
    /// picking one makes it; Quiet says nothing with it.
    func testPickingItsSignMakesIt() throws {
        let lines = TaggedLine.parse("""
            - [wish pet] pet me?
            - [wish pet met] <3
            """)
        XCTAssertEqual(Asks.wishSign(lines, .pet), "pet me?")
        XCTAssertEqual(Asks.wishMetSign(lines, .pet), "<3")
        XCTAssertEqual(Asks.questions(lines), [], "a wish isn't a question")
        var made: [Core.WishKind] = []
        var queued: [Moment] = []
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, asks: lines,
                                 wishable: { _, _ in [.pet] }, makeWish: { k, _ in made.append(k) })
        let log = Transcript.log().view(now: 0)
        let checkIn = Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in")
        let sign = try XCTUnwrap(react.questions(now: checkIn, log: log).first { $0.key == Signs.questionKey })
        XCTAssertTrue(sign.options.map(\.name).contains("pet me?"))
        _ = react.run(["react.face": Answer(choice: "curious", probabilities: ["curious": 1]),
                       Signs.questionKey: Answer(choice: "pet me?", probabilities: ["pet me?": 1])], now: checkIn, log: log)
        XCTAssertEqual(made, [.pet])
        XCTAssertEqual(queued.last?.sign, "pet me?")
    }
}
