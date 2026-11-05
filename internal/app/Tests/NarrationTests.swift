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
    /// `Narration.maxQuote`: a reason keeps 160 characters of your words,
    /// ending at a word, so it never fills the Overview's first screen.
    func testALongQuoteEndsAtAWord() {
        func said(_ words: String) -> String {
            Narration.of(event(.said, "mic"), line: Line("", facts: ["words": .string(words)]))!.cause
        }
        XCTAssertEqual(Narration.maxQuote, 160)
        let sentence = String(repeating: "can you hear me from over here ", count: 70)
        let cause = said(String(sentence.prefix(2_000)))
        let kept = String(cause.dropFirst("You said \"".count).dropLast("\".".count))
        XCTAssertEqual(kept.last, "…")
        XCTAssertLessThanOrEqual(kept.count, 161)
        XCTAssertTrue(kept.dropLast().split(separator: " ").allSatisfy { sentence.split(separator: " ").contains($0) }, kept)
        XCTAssertFalse(kept.dropLast().hasSuffix(" "))
        // Short words stay as they are, on one line; one long word is still cut.
        XCTAssertEqual(said("two\nlines"), "You said \"two lines\".")
        let exact = String(repeating: "a", count: 160)
        XCTAssertEqual(said(exact), "You said \"\(exact)\".")
        XCTAssertEqual(said(exact + "b"), "You said \"\(exact)…\".")
    }

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
        for fact in Touch.allCases.compactMap({ $0.narration?.fact }) { XCTAssertNotNil(Narration.fit([fact], name: "Bartholomew"), fact) }
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

/// Every reaction has a plain reason: every kind of event, at each of its
/// phases, gives one, or is listed as deliberately silent, so a new one with no
/// reason fails. A kind this table doesn't know fails too.
final class ReasonsTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    func event(_ type: Event.Kind, _ specific: String = "", phase: Event.Phase? = nil, data: [String: JSONValue] = [:]) -> Event {
        Event(at: harnessT0, source: .boop, type: type, phase: phase, specificType: specific, data: data)
    }
    /// A sample of each kind at each phase it has, with what its line says.
    func samples(_ kind: Event.Kind) -> [(Event, Facts)]? {
        let thread: JSONValue = ["agent": "claude", "project": "api"]
        switch kind {
        case .session: return [(event(kind, phase: .start), ["thread": thread]), (event(kind, phase: .end), ["thread": thread])]
        case .turn: return [(event(kind, phase: .start), ["thread": thread]),
                            (event(kind, phase: .end), ["thread": thread, "outcome": "success"])]
        case .tool: return [(event(kind, phase: .start), ["thread": thread]), (event(kind, phase: .wait), ["thread": thread]),
                            (event(kind, phase: .end), ["thread": thread, "topic": "tests", "result": "ok"])]
        case .subagent: return [(event(kind, phase: .start), ["thread": thread]), (event(kind, phase: .end), ["thread": thread])]
        case .poke: return [(event(kind), ["in_a_row": .int(1)])]
        case .presence: return [(event(kind, phase: .start), [:]), (event(kind, phase: .end), ["away_ms": .int(600_000)])]
        case .lock: return [(event(kind, phase: .start), [:]), (event(kind, phase: .end), [:])]
        case .checkIn: return [(event(kind, "working"), ["working_ms": .int(600_000), "thread": thread])]
        case .said: return [(event(kind), ["words": "hi"])]
        case .needsYou: return [(event(kind, phase: .start), ["thread": thread]), (event(kind, phase: .end), ["thread": thread])]
        case .listen: return [(event(kind, phase: .start), [:]), (event(kind, phase: .wait), [:]), (event(kind, phase: .end), [:])]
        case .reacted: return [(event(kind), [:])]
        case .press: return [(event(kind), [:])]
        case .gesture: return Touch.allCases.filter { $0 != .poke }.map { (event(kind, $0.rawValue), [:]) }
        case .hush: return [(event(kind, "app", phase: .start), [:]), (event(kind, "timer", phase: .end), [:])]
        case .act: return ["tests", "build", "push"].flatMap { k in
            [(event(kind, k, phase: .start), ["thread": thread]),
             (event(kind, k, phase: .end, data: ["passed": true]), ["thread": thread]),
             (event(kind, k, phase: .end, data: ["passed": false]), ["thread": thread])] as [(Event, Facts)]
        }
        case .prompt: return [(event(kind, data: ["kind": "fix", "tone": "calm", "length": "sentence"]), ["thread": thread])]
        case .lastMessage: return [(event(kind), [:])]
        case .dream: return [(event(kind), [:])]
        case .memory: return [(event(kind), [:])]
        case .wish: return Core.WishKind.allCases.map { (event(kind, $0.rawValue, phase: .start), [:]) }
            + [(event(kind, "met", phase: .end, data: ["kind": "pet"]), [:]), (event(kind, "gaveup", phase: .end, data: ["kind": "pet"]), [:])]
        case .grew: return [(event(kind, "sprout"), [:])]
        case .ask: return [(event(kind, "a"), ["answer": "yes"]), (event(kind, Asks.ignored), [:])]
        case .link: return [(event(kind, "ble", phase: .start), [:]), (event(kind, "ble", phase: .end), [:])]
        @unknown default: return nil
        }
    }

    func testEveryEventHasAReasonOrIsSilentOnPurpose() {
        var named = Set<String>()
        for kind in Event.Kind.allCases {
            guard let rows = samples(kind), !rows.isEmpty else {
                XCTFail("\(kind) has no sample here: give it a reason and a row")
                return
            }
            for (e, facts) in rows {
                let name = e.name
                named.insert(name)
                let why = Narration.of(e, line: Line("", facts: facts), name: "Boop")
                if Narration.silent[name] != nil {
                    XCTAssertNil(why, "\(name) is listed as silent and has a reason")
                } else {
                    XCTAssertNotNil(why, "\(name) has no reason and isn't listed as silent (Narration.silent)")
                }
            }
        }
        for (name, because) in Narration.silent {
            XCTAssertTrue(named.contains(name), "\(name) is silent, and is no event")
            XCTAssertFalse(because.isEmpty)
        }
    }

    /// Every fact fits a caption, 18 characters, with the longest ordinary name
    /// and the agents' own.
    func testEveryCaptionFits() {
        XCTAssertEqual(Narration.maxFact, 18)
        for name in ["Boop", "Bartholomew the Third"] {
            for kind in Event.Kind.allCases {
                for (e, facts) in samples(kind) ?? [] {
                    if let fact = Narration.of(e, line: Line("", facts: facts), name: name)?.fact {
                        XCTAssertLessThanOrEqual(fact.count, 18, fact)
                    }
                }
            }
            for ctx in ["new_task", "session", "continuation", "compacted"] {
                for agent in ["claude", "codex"] { XCTAssertNotNil(Narration.started(ctx, agent: agent, name: name)) }
            }
            for k in Core.WishKind.allCases { XCTAssertNotNil(Narration.wish(k, name: name).fact, k.rawValue) }
        }
    }

    /// The reasons this work added, in the person's words.
    func testNewReasonsInPlainWords() {
        XCTAssertEqual(Narration.noticed("a rough hour: 3 failures"), "It noticed a rough hour: 3 failures.")
        XCTAssertEqual(Narration.wish(.pet, name: "Boop", because: "you haven't said hi today").cause, "Boop wants a pet: you haven't said hi today.")
        let thread: JSONValue = ["agent": "claude", "project": "api"]
        XCTAssertEqual(Narration.of(event(.wish, "pet", phase: .start), line: nil, name: "Boop"),
                       Narration(cause: "Boop wants a pet.", fact: "Boop wants a pet"))
        XCTAssertEqual(Narration.of(event(.act, "tests", phase: .start), line: Line("", facts: ["thread": thread]), name: "Boop"),
                       Narration(cause: "claude is running the tests on api.", fact: "claude runs tests"))
        XCTAssertEqual(Narration.of(event(.act, "tests", phase: .end, data: ["passed": true]), line: Line("", facts: ["thread": thread]), name: "Boop"),
                       Narration(cause: "The tests on api pass.", fact: "tests pass"))
        XCTAssertEqual(Narration.of(event(.tool, phase: .end), line: Line("", facts: ["thread": thread, "topic": "tests", "result": "ok"]), name: "Boop"),
                       Narration(cause: "The tests on api pass.", fact: "tests pass"), "a first pass too")
        XCTAssertEqual(Narration.of(event(.presence, phase: .start), line: nil, name: "Boop")?.fact, "you stepped away")
        XCTAssertEqual(Narration.of(event(.turn, phase: .start), line: Line("", facts: ["thread": thread]), name: "Boop")?.fact, "claude started")
        XCTAssertEqual(Narration.of(event(.session, phase: .start), line: Line("", facts: ["thread": thread]), name: "Boop")?.fact, "claude compacted")
        XCTAssertEqual(Narration.of(event(.hush, "app", phase: .start), line: nil, name: "Boop")?.fact, "you hushed Boop")
        XCTAssertEqual(Narration.of(event(.prompt, data: ["kind": "fix", "tone": "calm", "length": "sentence"]), line: Line("", facts: ["thread": thread]), name: "Boop")?.fact, "you asked claude")
        XCTAssertEqual(Narration.sleeping(noAgents: false, napping: false, dozeMs: 3_600_000, name: "Boop"),
                       Narration(cause: "Nothing's happened for an hour, so Boop dozed off.", fact: "quiet for 1 h"))
        XCTAssertEqual(Narration.sleeping(noAgents: true, napping: false, dozeMs: 3_600_000, name: "Boop").fact, "no agents open")
        XCTAssertNil(Narration.sleeping(noAgents: false, napping: true, dozeMs: 3_600_000, name: "Boop").fact, "the Moment that took the nap says why")
        XCTAssertEqual(Narration.moodMoved("grumpy", name: "Boop"), "Boop's grumpy now")
        XCTAssertEqual(Narration.moodMoved("disappointed", name: "Boop"), "disappointed now")
    }

    /// A real mood change says so on the board: the pass's own, not a later
    /// pass's, and not a fade back to rest at a check-in. A reason's fact goes
    /// first; with no Moment at all it goes as a caption alone.
    func testAMoodThatMovedSaysSo() throws {
        let log = Transcript.log()
        let mood = MoodOutput.choice()
        let pack = CharacterPack.active
        func moved(_ e: Event, to: String) -> Event {
            let logged = log.append(e, now: e.at)
            _ = log.append(Event(at: e.at + 1, source: Event.harness, kind: Event.did,
                                 data: ["action": .string(MoodOutput.outputName), "for": .int(Int64(logged.seq)), "ok": true,
                                        "from": "calm", "to": .string(to)]), now: e.at + 1)
            return logged
        }
        let poke = moved(event(.poke), to: "grumpy")
        let view = log.view(now: harnessT0 + 2)
        XCTAssertEqual(MoodOutput.boardFact(mood, view, now: poke, pack: pack), Narration.moodMoved("grumpy", name: pack.name))
        XCTAssertNil(MoodOutput.boardFact(mood, view, now: event(.poke), pack: pack), "another pass's")
        XCTAssertNil(MoodOutput.boardFact(mood, view, now: nil, pack: pack))
        let fade = moved(event(.checkIn, "check_in"), to: pack.defaultMood)
        XCTAssertNil(MoodOutput.boardFact(mood, log.view(now: harnessT0 + 3), now: fade, pack: pack), "a fade")

        var queued: [Moment] = [], notes: [String] = []
        let react = MomentOutput(queue: { m, _ in queued.append(m) }, blocked: { nil }, reason: { _ in Narration(cause: "Why.") },
                                 moodMoved: { _, _ in "now grumpy" }, note: { fact, _ in notes.append(fact) })
        _ = react.run(["react.face": Answer(choice: "grumpy", probabilities: ["grumpy": 1])], now: poke, log: view)
        XCTAssertEqual(queued.last?.reason, "now grumpy", "with no fact of the reason's own")
        XCTAssertEqual(notes, [])
        XCTAssertNil(react.run([:], now: poke, log: view))
        XCTAssertEqual(notes, ["now grumpy"], "no Moment, and a caption alone")
    }

    /// The board's own captions and the Mac's are the same words, which is how
    /// the board knows a reason sent later for one it showed. Every touch with a
    /// caption is in firmware's table, or it's deliberately only the Mac's.
    func testTheBoardSaysATouchInTheMacsWords() throws {
        let header = try String(contentsOf: CharacterPackTests.repo.appendingPathComponent("firmware/src/app/touch_reason.h"), encoding: .utf8)
        let macOnly: Set<Touch> = [.facedown]  // the board goes dim at once: the Mac says it if Jev answers
        for touch in Touch.allCases {
            guard let fact = touch.narration?.fact, !macOnly.contains(touch) else { continue }
            XCTAssertTrue(header.contains("{\"\(touch.rawValue)\", \"\(fact)\"}"), "\(touch): firmware's table says otherwise")
        }
        XCTAssertTrue(header.contains("kTouchReasons"))
    }

    /// Every pastime and transition the gel has has words for the popover.
    func testThePopoverHasWordsForAllThatPassesTheTime() throws {
        let pack = CharacterPack.active
        guard pack.id == "boop" else { return }
        let source = try String(contentsOf: CharacterPackTests.repo.appendingPathComponent("characters/boop/firmware/src/render/gel/pastimes.cpp"), encoding: .utf8)
        let row = try NSRegularExpression(pattern: #"\{Pastime::k\w+, Body::k\w+, "([^"]+)""#)
        let names = row.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { String(source[Range($0.range(at: 1), in: source)!]) }
        XCTAssertGreaterThan(names.count, 40)
        for n in names + ["to-work", "to-rest", "to-sleep", "act-on", "act-off"] {
            XCTAssertNotNil(pack.passing[n], "\(n) has no words in mac/passing.tsv")
        }
        XCTAssertEqual(Narration.passing("bubble", in: pack.named("Boop")), "Boop's blowing bubbles to pass the time.")
        XCTAssertEqual(Narration.passing("to-work", in: pack.named("Boop")), "Boop's getting to work.")
    }
}
