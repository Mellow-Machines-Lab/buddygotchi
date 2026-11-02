import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The reason: why the buddy does what it does, rendered on the Mac from
/// the event the brain answered and its line, never by the brain.
final class NarrationTests: XCTestCase {
    func event(_ type: Event.Kind, _ specific: String = "", phase: Event.Phase? = nil) -> Event {
        Event(at: harnessT0, source: .device, type: type, phase: phase, specificType: specific)
    }

    /// Coming back says how long you were away: minutes under an hour,
    /// hours under two days, days after; the board's fact in a few
    /// characters.
    func testComingBackSaysHowLongYouWereAway() {
        func back(_ ms: Int64) -> Narration? {
            Narration.of(event(.presence, "unlocked", phase: .end), line: Line("You came back.", facts: ["away_ms": .int(ms)]))
        }
        XCTAssertEqual(back(25 * 60_000), Narration(cause: "You came back after 25 minutes away.", fact: "away 25 min"))
        XCTAssertEqual(back(12 * 3_600_000), Narration(cause: "You came back after 12 hours away.", fact: "you were away 12 h"))
        XCTAssertEqual(back(26 * 3_600_000)?.fact, "you were away 26 h")
        XCTAssertEqual(back(3 * 86_400_000), Narration(cause: "You came back after 3 days away.", fact: "you were away 3 d"))
    }

    /// Every care gesture, and a poke, gives the board a fact; what you
    /// said gives none, as the sign answers it.
    func testTouchesGiveTheBoardAFactAndWordsDont() {
        XCTAssertEqual(Narration.of(event(.gesture, "stroke"), line: nil, name: "Boop"), Narration(cause: "You stroked it.", fact: "you stroked Boop"))
        XCTAssertEqual(Narration.of(event(.gesture, "pickup"), line: nil, name: "Bartholomew")?.fact, "you picked it up", "a long name gives way to it")
        XCTAssertEqual(Narration.of(event(.poke, "input"), line: Line("", facts: ["in_a_row": .int(4)]), name: "Boop"),
                       Narration(cause: "You poked it 4 times in a row.", fact: "you poked Boop x4"))
        XCTAssertEqual(Narration.of(event(.poke, "input"), line: Line("", facts: ["in_a_row": .int(1), "asleep": .bool(true)]), name: "Boop")?.fact,
                       "you woke Boop")
        XCTAssertEqual(Narration.of(event(.gesture, "dizzy"), line: Line("", facts: ["in_a_row": .int(1)]), name: "Boop"),
                       Narration(cause: "You shook it.", fact: "you shook Boop"))
        XCTAssertEqual(Narration.of(event(.gesture, "dizzy"), line: Line("", facts: ["in_a_row": .int(3)]), name: "Boop"),
                       Narration(cause: "You shook it 3 times in a row.", fact: "you shook Boop x3"))
        let said = Narration.of(event(.said, "mic"), line: Line("You said to Boop: \"hi\".", facts: ["words": .string("hi")]))
        XCTAssertEqual(said, Narration(cause: "You said \"hi\"."))
    }

    /// An idle check-in an hour or more with no touch or word says so, as
    /// CONTEXT's You row does; under an hour it says its line.
    func testALonelyCheckInSaysHowLongBoopWentUntouched() {
        let check = event(.checkIn, "check_in")
        let line = Line("Nothing has happened for 20 min; claude sits idle on \"api\".")
        XCTAssertEqual(Narration.of(check, line: line, untouchedMs: 2 * 3_600_000 + 60_000),
                       Narration(cause: "You've been here 2 hours and haven't touched it.", fact: "no touch in 2 h"))
        XCTAssertNil(Narration.of(check, line: line, untouchedMs: 3_600_000 - 1), "under an hour, and no minutes in its facts")
        XCTAssertEqual(Narration.of(check, line: Line(line.text, facts: ["idle_minutes": .int(20)]), untouchedMs: 0),
                       Narration(cause: "Nothing has happened for 20 minutes."))
    }

    /// The commonest causes in the person's words, with the place they
    /// know: a worktree's folder, an id, gives way to its project.
    func testTheCommonestCausesInPlainWords() {
        let wt: JSONValue = ["agent": "claude", "name": "bridge-cse-01357dh6iqt7edrmibm2hd5w", "turn": 18,
                             "project": "buddygotchi", "workspace": "bridge-cse-01357dh6iqt7edrmibm2hd5w"]
        let branch: JSONValue = ["agent": "codex", "name": "fix-nav", "project": "landing", "workspace": "fix-nav"]
        func of(_ type: Event.Kind, _ phase: Event.Phase? = nil, _ specific: String = "", data: [String: JSONValue] = [:],
                facts: [String: JSONValue]) -> String? {
            Narration.of(Event(at: harnessT0, source: .claude, type: type, phase: phase, specificType: specific, data: data),
                         line: Line("LINE", facts: facts))?.cause
        }
        let failed = of(.turn, .end, facts: ["thread": wt, "outcome": "failed", "length_ms": 600_000])
        XCTAssertEqual(failed, "claude's turn on buddygotchi failed.")
        XCTAssertEqual(of(.turn, .end, facts: ["thread": wt, "outcome": "done", "length_ms": 600_000]),
                       "claude finished a long turn on buddygotchi.")
        XCTAssertEqual(of(.lastMessage, facts: ["thread": wt, "outcome": "done", "message": ["kind": "stuck"]]),
                       "claude gave up on buddygotchi.")
        XCTAssertEqual(of(.lastMessage, facts: ["thread": branch, "outcome": "done", "message": ["kind": "question"]]),
                       "codex has a question for you on fix-nav.")
        XCTAssertEqual(of(.prompt, data: ["kind": "fix", "tone": "frustrated", "length": "sentence"], facts: ["thread": wt]),
                       "You asked claude for a fix on buddygotchi, sounding frustrated.")
        XCTAssertEqual(of(.tool, .end, facts: ["thread": wt, "topic": "tests", "result": "failed", "failed_before": 2]),
                       "The tests on buddygotchi failed again: 3 times in a row.")
        XCTAssertEqual(of(.checkIn, facts: ["thread": wt, "working_ms": .int(12 * 60_000)]),
                       "claude has been working on buddygotchi for 12 minutes.")
        XCTAssertEqual(of(.session, .start, facts: ["thread": wt]), "claude's memory on buddygotchi was compacted.")
        XCTAssertEqual(of(.needsYou, .start, facts: ["thread": wt]), "claude needs you on buddygotchi.")
        XCTAssertNil(Narration.of(Event(at: harnessT0, source: .claude, type: .turn, phase: .end, specificType: "Stop"),
                                  line: Line("LINE", facts: ["thread": wt, "outcome": "done"]))?.fact, "a finish's sign names it")
        XCTAssertTrue(Narration.looksLikeAnID("agent-a3ff514bdd7c3721f"))
        XCTAssertFalse(Narration.looksLikeAnID("fix-nav"))
        XCTAssertFalse(Narration.looksLikeAnID("v2-launch-2026"))
    }

    /// Pins that the reason never says the brain's line: every kind of
    /// event gives a sentence of its own or none, and none reads like a
    /// line (a turn by its number, a thread's folder in quotes).
    func testNoReasonIsTheBrainsLine() {
        let thread: JSONValue = ["agent": "claude", "name": "bridge-cse-01357dh6", "turn": 18, "project": "buddygotchi",
                                 "workspace": "bridge-cse-01357dh6"]
        let line = Line("claude finished turn 18 on \"bridge-cse-01357dh6\": done.", facts: ["thread": thread])
        for kind in Event.Kind.allCases {
            for phase: Event.Phase? in [nil, .start, .wait, .end] {
                let e = Event(at: harnessT0, source: .claude, type: kind, phase: phase, specificType: "")
                guard let cause = Narration.of(e, line: line)?.cause else { continue }
                XCTAssertNotEqual(cause, line.text, "\(kind) \(String(describing: phase))")
                XCTAssertNil(cause.range(of: #"turn \d+ on"#, options: .regularExpression), cause)
                XCTAssertFalse(cause.contains("bridge-cse"), cause)
                XCTAssertFalse(cause.contains("\""), cause)
            }
        }
    }

    /// No fact is longer than a sign: one that would be is dropped, never
    /// cut mid-word on the board.
    func testAFactFitsASign() {
        for g in Touch.allCases.compactMap(\.narration) { XCTAssertNotNil(Narration.fit([g.fact], name: "Bartholomew"), g.fact) }
        XCTAssertNil(Narration(cause: "x", fact: String(repeating: "a", count: Narration.maxFact + 1)).fact)
        XCTAssertEqual(Narration.maxFact, 18, "the board's sign width, firmware kSignGlyphs")
    }

    /// The sentences put the buddy's face or mood first, then the cause.
    func testTheSentences() {
        let r = Narration(cause: "You stroked it.", fact: "stroked")
        XCTAssertEqual(r.reaction(face: "comfy", name: "Boop"), "Boop is comfy. You stroked it.")
        XCTAssertEqual(r.mood("lonely", name: "Boop"), "Boop is lonely. You stroked it.")
    }

    /// The react output sends the fact to the board with a reaction whose
    /// strip names no finished turn, and logs the sentence with what it
    /// did; a finish keeps the strip's tick and cross, so it gets none.
    func testAReactionCarriesItsReason() throws {
        var queued: [Moment] = []
        let stroke = event(.gesture, "stroke")
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, speaks: { false },
                                reason: { $0.flatMap { Narration.of($0, line: nil) } })
        let log = Transcript.log().view(now: 0)
        let result = try XCTUnwrap(react.run(["react.face": Answer(choice: "comfy", probabilities: ["comfy": 1])], now: stroke, log: log))
        XCTAssertEqual(queued.last?.reason, "you stroked \(CharacterPack.active.name)")
        XCTAssertEqual(queued.last?.args["reason"], .string("you stroked \(CharacterPack.active.name)"))
        XCTAssertEqual(result.facts["reason"], .string("\(CharacterPack.active.name) is comfy. You stroked it."))

        let finished = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil },
                                   who: { _ in Moment.Who(agent: "claude", thread: "api") }, turnMs: { _ in 60_000 },
                                   speaks: { false }, reason: { _ in Narration(cause: "x", fact: "y") })
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
