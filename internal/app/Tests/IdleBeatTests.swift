import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The idle beat (`IdleBeat`): the one thing Boop may hold up at an idle
/// check-in, dealt by code in a fixed order under one cap.
final class IdleBeatTests: XCTestCase {
    let hour: Int64 = 3_600_000

    func candidate(_ kind: IdleBeat.Kind) -> IdleBeat.Candidate { IdleBeat.Candidate(kind, signs: [kind.rawValue]) }

    /// Pins the order it's dealt in: an agent waiting on you, the wish,
    /// another notice, an ask, a remembered line, a musing; the first that
    /// has something.
    func testTheOrder() {
        XCTAssertEqual(IdleBeat.Kind.allCases, [.waiting, .wish, .notice, .ask, .remembered, .musing])
        func due(_ has: Set<IdleBeat.Kind>, quiet: Bool = false, wishOpen: Bool = false, room: Bool = true) -> IdleBeat.Kind? {
            IdleBeat.due(room: room, quiet: quiet, wishOpen: wishOpen) { has.contains($0) ? self.candidate($0) : nil }?.kind
        }
        let all = Set(IdleBeat.Kind.allCases)
        XCTAssertEqual(due(all), .waiting)
        XCTAssertEqual(due(all.subtracting([.waiting])), .wish)
        XCTAssertEqual(due([.notice, .ask, .remembered, .musing]), .notice)
        XCTAssertEqual(due([.ask, .remembered, .musing]), .ask)
        XCTAssertEqual(due([.remembered, .musing]), .remembered)
        XCTAssertEqual(due([.musing]), .musing)
        XCTAssertNil(due([]))
        XCTAssertNil(due(all, room: false), "past the cap, nothing")
        XCTAssertEqual(due(all, quiet: true), .waiting, "on Quiet, only an agent waiting on you")
        XCTAssertNil(due(all.subtracting([.waiting]), quiet: true))
        XCTAssertEqual(due(all, wishOpen: true), .waiting, "over an open wish, only that too")
        XCTAssertNil(due(all.subtracting([.waiting]), wishOpen: true))
        XCTAssertNil(IdleBeat.due(room: true, quiet: false, wishOpen: false) { IdleBeat.Candidate($0, signs: []) }, "one with no sign isn't one")
    }

    /// Pins the one cap: at most one idle beat an hour, four a Boop day.
    func testTheOneCap() {
        XCTAssertEqual(IdleBeat.everyMs, hour)
        XCTAssertEqual(IdleBeat.perDay, 4)
        let noon = 12 * hour
        func room(_ ago: [Int64]) -> Bool { IdleBeat.room(ago.map { noon - $0 }, now: noon, sameDay: { _ in true }) }
        XCTAssertTrue(room([]))
        XCTAssertFalse(room([hour - 1]), "one an hour")
        XCTAssertTrue(room([hour, 2 * hour, 3 * hour]))
        XCTAssertFalse(room([hour, 2 * hour, 3 * hour, 4 * hour]), "four a day")
        XCTAssertTrue(IdleBeat.room([noon - 2 * hour, noon - 3 * hour, noon - 4 * hour, noon - 5 * hour], now: noon, sameDay: { $0 > noon - 3 * hour }),
                      "yesterday's don't count")
    }

    /// The cap counts what showed, from the transcript: a Moment's record
    /// with the beat's kind.
    func testTheCapCountsWhatShowed() {
        let log = Transcript.log()
        _ = log.append(Event.did("Boop held up a sign", for: nil, action: MomentOutput.outputName, by: "brain", facts: [IdleBeat.fact: "musing"], at: 1000), now: 1000)
        _ = log.append(Event.did("Boop reacted", for: nil, action: MomentOutput.outputName, by: "brain", facts: ["sign": "x"], at: 2000), now: 2000)
        XCTAssertEqual(IdleBeat.shownAt(log.view(now: 3000)), [1000])
    }

    /// Jev is asked only whether: the one sign, or nothing; a musing's few
    /// lines to choose among, never the one held up last.
    func testTheQuestionIsHoldThisUpOrNothing() throws {
        var beat = IdleBeat.Candidate(.wish, signs: ["pet me?"], wish: .pet)
        var made: [Core.WishKind] = []
        var sent: Moment?
        let react = MomentOutput(queue: { m, _ in sent = m }, blocked: { nil }, speaks: { false },
                                 idleBeat: { _, _, _ in [beat] }, makeWish: { kind, _ in made.append(kind) }, moodFace: { _ in "calm" })
        let checkIn = Event(at: 1000, source: .clock, type: .checkIn, specificType: "check_in")
        let log = Transcript.log().view(now: 1000)
        let question = try XCTUnwrap(react.questions(now: checkIn, log: log).first { $0.key == Signs.questionKey })
        XCTAssertEqual(question.options.map(\.name), ["none", "pet me?"])
        XCTAssertNil(react.run([MomentOutput.emotionKey: Answer(choice: "none"), Signs.questionKey: Answer(choice: "none")], now: checkIn, log: log))
        XCTAssertEqual(made, [], "nothing held up, no wish made")
        let result = react.run([MomentOutput.emotionKey: Answer(choice: "none"), Signs.questionKey: Answer(choice: "pet me?")], now: checkIn, log: log)
        XCTAssertEqual(made, [.pet], "held up, the wish is made")
        XCTAssertEqual(sent?.sign, "pet me?")
        XCTAssertEqual(result?.facts[IdleBeat.fact], "wish")
        XCTAssertEqual(result?.facts["wish"], "pet")

        beat = IdleBeat.Candidate(.musing, signs: ["pet me?", "a", "b", "c", "d"])
        XCTAssertEqual(react.questions(now: checkIn, log: log).last?.options.map(\.name), ["none", "a", "b", "c"],
                       "a few musings, without the sign held up last")
        XCTAssertEqual(IdleBeat.musingsOffered, 3)

        let ask = Asks.Question(id: "snack", question: "fav snack?", a: "cookie", b: "pizza", tags: ["idle"], keeps: true)
        beat = IdleBeat.Candidate(.ask, signs: [ask.question], ask: ask)
        let asked = react.run([MomentOutput.emotionKey: Answer(choice: "curious"), Signs.questionKey: Answer(choice: ask.question)], now: checkIn, log: log)
        XCTAssertEqual(sent?.ask, ask)
        XCTAssertEqual(sent?.sign, "fav snack?")
        XCTAssertEqual(asked?.facts["ask"], "snack")
    }
}
