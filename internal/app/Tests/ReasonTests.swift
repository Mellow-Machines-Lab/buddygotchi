import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The reason: why the buddy does what it does, rendered on the Mac from
/// the event the brain answered and its line, never by the brain.
final class ReasonTests: XCTestCase {
    func event(_ type: Event.Kind, _ specific: String = "", phase: Event.Phase? = nil) -> Event {
        Event(at: harnessT0, source: .device, type: type, phase: phase, specificType: specific)
    }

    /// Coming back says how long you were away: minutes under an hour,
    /// hours under two days, days after; the board's fact in a few
    /// characters.
    func testComingBackSaysHowLongYouWereAway() {
        func back(_ ms: Int64) -> Reason? {
            Reason.of(event(.presence, "unlocked", phase: .end), line: Line("You came back.", facts: ["away_ms": .int(ms)]))
        }
        XCTAssertEqual(back(25 * 60_000), Reason(cause: "You came back after 25 minutes away.", fact: "away 25 min"))
        XCTAssertEqual(back(12 * 3_600_000), Reason(cause: "You came back after 12 hours away.", fact: "away 12 h"))
        XCTAssertEqual(back(26 * 3_600_000)?.fact, "away 26 h")
        XCTAssertEqual(back(3 * 86_400_000), Reason(cause: "You came back after 3 days away.", fact: "away 3 d"))
    }

    /// Every care gesture, and a poke, gives the board a fact; what you
    /// said gives none, as the sign answers it.
    func testTouchesGiveTheBoardAFactAndWordsDont() {
        XCTAssertEqual(Reason.of(event(.gesture, "stroke"), line: nil), Reason(cause: "You stroked it.", fact: "stroked"))
        XCTAssertEqual(Reason.of(event(.poke, "input"), line: Line("", facts: ["in_a_row": .int(4)])),
                       Reason(cause: "You poked it 4 times in a row.", fact: "poked x4"))
        XCTAssertEqual(Reason.of(event(.poke, "input"), line: Line("", facts: ["in_a_row": .int(1), "asleep": .bool(true)]))?.fact,
                       "woken up")
        let said = Reason.of(event(.said, "mic"), line: Line("You said to Boop: \"hi\".", facts: ["words": .string("hi")]))
        XCTAssertEqual(said, Reason(cause: "You said \"hi\"."))
    }

    /// An idle check-in an hour or more with no touch or word says so, as
    /// CONTEXT's You row does; under an hour it says its line.
    func testALonelyCheckInSaysHowLongBoopWentUntouched() {
        let check = event(.heartbeat, "check_in")
        let line = Line("Nothing has happened for 20 min; claude sits idle on \"api\".")
        XCTAssertEqual(Reason.of(check, line: line, untouchedMs: 2 * 3_600_000 + 60_000),
                       Reason(cause: "You've been here 2 hours and haven't touched it.", fact: "untouched 2 h"))
        XCTAssertEqual(Reason.of(check, line: line, untouchedMs: 3_600_000 - 1), Reason(cause: line.text))
    }

    /// A kind of line with no row of its own says its line, and gives the
    /// board nothing; with no line, there's no reason.
    func testAnyOtherLineSaysItself() {
        let turn = Event(at: harnessT0, source: .claude, type: .turn, phase: .end, specificType: "Stop")
        XCTAssertEqual(Reason.of(turn, line: Line("claude finished turn 3 on \"api\": done.")),
                       Reason(cause: "claude finished turn 3 on \"api\": done."))
        XCTAssertNil(Reason.of(turn, line: nil))
    }

    /// No fact is longer than a sign: one that would be is dropped, never
    /// cut mid-word on the board.
    func testAFactFitsASign() {
        for (_, g) in Reason.gestures { XCTAssertLessThanOrEqual(g.fact.count, Reason.maxFact, g.fact) }
        XCTAssertNil(Reason(cause: "x", fact: String(repeating: "a", count: Reason.maxFact + 1)).fact)
        XCTAssertEqual(Reason.maxFact, 18, "the board's sign width, firmware kSignGlyphs")
    }

    /// The sentences put the buddy's face or mood first, then the cause.
    func testTheSentences() {
        let r = Reason(cause: "You stroked it.", fact: "stroked")
        XCTAssertEqual(r.reaction(face: "comfy", name: "Boop"), "Boop is comfy. You stroked it.")
        XCTAssertEqual(r.mood("lonely", name: "Boop"), "Boop is lonely. You stroked it.")
    }

    /// The react output sends the fact to the board with a reaction whose
    /// strip names no finished turn, and logs the sentence with what it
    /// did; a finish keeps the strip's tick and cross, so it gets none.
    func testAReactionCarriesItsReason() throws {
        var queued: [DeviceReaction] = []
        let stroke = event(.gesture, "stroke")
        let react = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, speaks: { false },
                                reason: { $0.flatMap { Reason.of($0, line: nil) } })
        let log = Transcript.log().view(now: 0)
        let result = try XCTUnwrap(react.run(["react.face": Answer(choice: "comfy", probabilities: ["comfy": 1])], now: stroke, log: log))
        XCTAssertEqual(queued.last?.reason, "stroked")
        XCTAssertEqual(queued.last?.args["reason"], .string("stroked"))
        XCTAssertEqual(result.facts["reason"], .string("\(CharacterPack.active.name) is comfy. You stroked it."))

        let finished = ReactOutput(queue: { r, _ in queued.append(r) }, blocked: { nil },
                                   who: { _ in DeviceReaction.Who(agent: "claude", thread: "api") }, turnMs: { _ in 60_000 },
                                   speaks: { false }, reason: { _ in Reason(cause: "x", fact: "y") })
        _ = finished.run(["react.face": Answer(choice: "happy", probabilities: ["happy": 1]),
                          "react.move": Answer(choice: "success", probabilities: ["success": 1])], now: stroke, log: log)
        XCTAssertNotNil(queued.last?.who)
        XCTAssertNil(queued.last?.reason, "a finish's strip says what it's about")
    }

    /// The mood's reason is its latest change's cause: the event that
    /// change answered (its `did`'s `for`) and that event's line.
    func testTheMoodsReasonIsWhatMovedItLast() {
        let log = Transcript.log()
        let back = log.append(event(.presence, "unlocked", phase: .end), now: harnessT0)
        _ = log.append(Event(at: harnessT0 + 1, source: Event.harness, kind: Event.did,
                             data: ["action": .string(MoodOutput.outputName), "for": .int(Int64(back.seq)), "ok": true,
                                    "from": .string("calm"), "to": .string("lonely")]), now: harnessT0 + 1)
        let mood = MoodOutput.choice()
        let lines = [back.seq: Line("You came back.", facts: ["away_ms": .int(26 * 3_600_000)])]
        let reason = MoodOutput.reason(mood, log.view(now: harnessT0 + 2), line: { lines[$0] })
        XCTAssertEqual(reason?.mood("lonely", name: "Boop"), "Boop is lonely. You came back after 26 hours away.")
        XCTAssertNil(MoodOutput.reason(mood, Transcript.log().view(now: 0), line: { _ in nil }), "no change, no reason")
    }
}
