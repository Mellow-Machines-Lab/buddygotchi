import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What code decides of a Moment, and Jev is never asked (`MomentRule`):
/// its move, its size, and the whole Moment at a working check-in and a
/// boop from the world. Your lock's wave is in `LockTests`.
final class MomentRuleTests: XCTestCase {
    typealias Facts = [String: JSONValue]
    let min: Int64 = 60_000

    func event(_ type: Event.Kind, _ phase: Event.Phase? = nil, _ specific: String = "", data: Facts = [:]) -> Event {
        Event(at: 0, source: .claude, type: type, phase: phase, specificType: specific, data: data)
    }

    /// A finish's facts, as its line gives them.
    func finish(_ outcome: String = "done", minutes: Double = 0.5, tools: Int64 = 3, checksFailed: Int64 = 0, wins: Int64 = 1,
                kind: String? = nil, afterFix: Bool = false) -> Facts {
        var f: Facts = ["outcome": .string(outcome), "length_ms": .int(Int64(minutes * 60_000)), "tools": .int(tools),
                        "checks_failed": .int(checksFailed), "wins_in_a_row": .int(wins), "reacted_to_fix": .bool(afterFix)]
        if let kind { f["message"] = .object(["kind": .string(kind)]) }
        return f
    }

    /// Pins the move's table: a finish by how its turn ended and what its
    /// last message says; the wake-up after an hour away (`longAwayMs`);
    /// the notice when your prompt says the buddy's name; else none.
    func testTheMoveFollowsTheEvent() {
        let end = event(.turn, .end, "Stop")
        func move(_ facts: Facts) -> String? { MomentRule.move(end, facts: facts) }
        XCTAssertEqual(move(finish()), "success")
        XCTAssertEqual(move(finish("failed")), "failure")
        XCTAssertNil(move(finish("stopped")), "a stopped turn is just the face")
        XCTAssertEqual(move(finish(kind: "done")), "success")
        XCTAssertEqual(move(finish(kind: "stuck")), "failure", "done, but it says it couldn't finish")
        // A chat turn plays no finish, only a look up at you: its last
        // message a question or an answer, or nothing called, no claim,
        // over within the minute.
        XCTAssertEqual(move(finish(kind: "question")), "notice")
        XCTAssertEqual(move(finish(kind: "answer")), "notice")
        XCTAssertEqual(move(finish(tools: 0)), "notice", "back-and-forth")
        XCTAssertFalse(MomentRule.namesTurn(finish(kind: "question")), "and names no thread")
        XCTAssertTrue(MomentRule.namesTurn(finish("stopped")), "a stopped turn's face still does")
        XCTAssertEqual(move(finish(minutes: 1, tools: 0)), "success", "a minute or more of work is work")
        XCTAssertEqual(move(finish(tools: 0, kind: "other")), "notice")
        XCTAssertEqual(move(finish(tools: 0, kind: "done")), "success", "it says the work is done")
        XCTAssertEqual(move(finish(kind: "other")), "success")
        XCTAssertEqual(MomentRule.move(event(.lastMessage, nil, "reading"), facts: finish("failed")), "failure", "a finish's reading is the finish")

        XCTAssertEqual(MomentRule.longAwayMs, 60 * min)
        let back = event(.presence, .end, "unlocked")
        XCTAssertEqual(MomentRule.move(back, facts: ["away_ms": .int(60 * min)]), "wake up")
        XCTAssertNil(MomentRule.move(back, facts: ["away_ms": .int(60 * min - 1)]))
        XCTAssertNil(MomentRule.move(event(.presence, .start, "locked"), facts: ["away_ms": .int(90 * min)]))

        let named = event(.prompt, nil, "reading", data: PromptReading(length: .sentence, named: ["Boop"], kind: .feature, tone: nil, phrases: []).facts)
        let plain = event(.prompt, nil, "reading", data: PromptReading(length: .sentence, named: [], kind: .feature, tone: nil, phrases: []).facts)
        XCTAssertEqual(MomentRule.move(named, facts: [:]), "notice")
        XCTAssertNil(MomentRule.move(plain, facts: [:]))
        for e in [event(.poke), event(.said), event(.checkIn, nil, "check_in"), event(.gesture, nil, "stroke"), event(.tool, .end)] {
            XCTAssertNil(MomentRule.move(e, facts: ["result": "failed"]), e.kind)
        }
        XCTAssertEqual(Set(MomentOutput.moves), ["success", "failure", "wake up", "notice"], "every move the rule can pick")
    }

    /// Pins a finish's size: by its turn's length (small under a minute,
    /// medium to 5, big from there, as the board sizes it); a step up, big
    /// at most, when it failed, was hard-won or is the 3rd or later of a
    /// streak (`streakFrom`); small for a reply, a stopped turn, one just
    /// after its fix, and a win in a sad or cross mood.
    func testAFinishIsAsBigAsItsTurn() {
        let end = event(.turn, .end, "Stop")
        func size(_ facts: Facts, mood: String = "calm") -> String { MomentOutput.sizes[MomentRule.size(end, facts: facts, mood: mood)].name }
        XCTAssertEqual(size(finish(minutes: 0.9)), "small")
        XCTAssertEqual(size(finish(minutes: 1)), "medium")
        XCTAssertEqual(size(finish(minutes: 4.9)), "medium")
        XCTAssertEqual(size(finish(minutes: 5)), "big")
        XCTAssertEqual(size(finish(minutes: 40)), "big")
        XCTAssertEqual(size(finish("failed", minutes: 0.5)), "medium", "a failure is a step bigger")
        XCTAssertEqual(size(finish("failed", minutes: 2)), "big")
        XCTAssertEqual(size(finish("failed", minutes: 20)), "big", "big at most")
        XCTAssertEqual(size(finish(minutes: 2, checksFailed: 2)), "big", "hard-won")
        XCTAssertEqual(MomentRule.streakFrom, 3)
        XCTAssertEqual((1...6).map { size(finish(wins: Int64($0))) }, ["small", "small", "medium", "medium", "medium", "medium"],
                       "from the 3rd quick win in a row")
        XCTAssertEqual(size(finish(minutes: 9, tools: 0, kind: "answer")), "small", "a reply")
        XCTAssertEqual(size(finish("stopped", minutes: 9)), "small")
        XCTAssertEqual(size(finish(minutes: 9, afterFix: true)), "small", "the fix was the win")
        for mood in ["sad", "cross"] {
            XCTAssertEqual(size(finish(minutes: 9), mood: mood), "small", mood)
            XCTAssertEqual(size(finish(minutes: 9, checksFailed: 3), mood: mood), "small", "even hard-won, in \(mood)")
            XCTAssertEqual(size(finish("failed", minutes: 9), mood: mood), "big", "a failure is as big as any, in \(mood)")
        }
        XCTAssertEqual(size(finish(minutes: 9), mood: "lonely"), "big")
    }

    /// Pins every other slot's size: your words medium; a touch small;
    /// your prompt medium when it sounds like something or says the
    /// buddy's name; you back by how long (`longAwayMs`, `daysMs`); a
    /// check failing small, medium from the 2nd in a row; a fix, calls
    /// failing in a row and a push's result medium; the rest small.
    func testEveryOtherSlotHasItsSize() {
        func size(_ e: Event, _ facts: Facts = [:]) -> String { MomentOutput.sizes[MomentRule.size(e, facts: facts, mood: "calm")].name }
        XCTAssertEqual(size(event(.said)), "medium")
        for touch in [event(.poke), event(.gesture, nil, "stroke"), event(.gesture, nil, "shake")] {
            XCTAssertEqual(size(touch, ["in_a_row": 5]), "small")
        }
        func prompt(_ tone: PromptText.Tone?, named: [String] = []) -> Event {
            event(.prompt, nil, "reading", data: PromptReading(length: .sentence, named: named, kind: .fix, tone: tone, phrases: []).facts)
        }
        XCTAssertEqual(size(prompt(nil)), "small")
        XCTAssertEqual(size(prompt(.calm)), "small")
        XCTAssertEqual(size(prompt(.frustrated)), "medium")
        XCTAssertEqual(size(prompt(nil, named: ["Boop"])), "medium")
        let back = event(.presence, .end, "unlocked")
        XCTAssertEqual(MomentRule.daysMs, 24 * 60 * min)
        XCTAssertEqual(size(back, ["away_ms": .int(20 * min)]), "small")
        XCTAssertEqual(size(back, ["away_ms": .int(60 * min)]), "medium")
        XCTAssertEqual(size(back, ["away_ms": .int(24 * 60 * min)]), "big")
        let call = event(.tool, .end, "PostToolUse")
        XCTAssertEqual(size(call, ["result": "failed", "failed_before": 0]), "small", "a first failed check is no drama")
        XCTAssertEqual(size(call, ["result": "failed", "failed_before": 1]), "medium")
        XCTAssertEqual(size(call, ["result": "ok", "failed_before": 2]), "medium", "the fix")
        XCTAssertEqual(size(call, ["failing": 3]), "medium")
        XCTAssertEqual(size(event(.act, .end, "push"), ["act": "push"]), "medium")
        for e in [event(.checkIn, nil, "check_in"), event(.ask, nil, "a"), event(.needsYou, .end), event(.wish, .end, "met")] {
            XCTAssertEqual(size(e), "small", e.kind)
        }
    }

    /// Pins the working check-in: a small Moment with a word about the
    /// work and no sign; focused for the first half of its round of 4,
    /// determined for the rest; a sad, cross or lonely mood keeps its own
    /// face; the word is the tests' when they're what the turn is at.
    func testTheWorkingCheckInIsARule() throws {
        XCTAssertEqual(EventLine.round, 4)
        func pick(_ rung: Int, topic: String? = nil, mood: String = "calm", face: String = "calm") -> [String] {
            let p = MomentRule.checkIn(rung: rung, topic: topic, mood: mood, face: face)
            return [p.face, p.say]
        }
        XCTAssertEqual((1...4).map { pick($0)[0] }, ["focused", "focused", "determined", "determined"])
        XCTAssertEqual(pick(1, mood: "focused", face: "focused"), ["focused", "work"])
        XCTAssertEqual(pick(3, topic: "tests", mood: "happy", face: "happy"), ["determined", "tests"])
        XCTAssertEqual(pick(2, topic: "build"), ["focused", "work"])
        XCTAssertEqual(pick(4, mood: "cross", face: "grumpy"), ["grumpy", "work"], "cross: its level's face")
        XCTAssertEqual(pick(1, mood: "sad", face: "sad")[0], "sad")
        XCTAssertEqual(pick(1, mood: "lonely", face: "lonely")[0], "lonely")
        XCTAssertTrue(["work", "tests"].allSatisfy(MomentOutput.topics.map(\.name).contains), "words `say` has")

        // As it plays: small, a word however small, no sign, no move.
        var queued: [Moment] = []
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, moodFace: { _ in "calm" }, moodID: { _ in "calm" })
        let log = Transcript.log().view(now: 0)
        let checkIn = Event(at: 0, source: .clock, type: .checkIn, specificType: "working")
        let ruled = try XCTUnwrap(react.ruled(checkIn, facts: ["check_in": 3, "topic": "tests"], log: log))
        let result = try XCTUnwrap(react.play(ruled, about: checkIn, log: log))
        XCTAssertTrue(result.message.contains("had a determined moment (small)"), result.message)
        XCTAssertEqual(queued.last?.loops, 1)
        XCTAssertNil(queued.last?.sign)
        XCTAssertNil(queued.last?.anim)
        if !Take.all.isEmpty {
            let takes = try XCTUnwrap(queued.last?.say?.takes)
            XCTAssertEqual(takes.map(\.meaning), ["tests"], "one word, no sound before it at a small moment")
            XCTAssertEqual(takes.first?.kind, .word)
        }
        XCTAssertNil(react.ruled(Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in"), facts: [:], log: log),
                     "the idle check-in is Jev's")
    }

    /// Pins a boop from the world: warm and small, with a sign that
    /// answers its kind; a cheer proud and medium; cross, a curious look,
    /// small, the sign still there.
    func testABoopFromTheWorldIsARule() throws {
        func pick(_ kind: String, mood: String = "calm") -> String {
            let p = MomentRule.world(kind: kind, mood: mood)
            return "\(p.face) \(MomentOutput.sizes[p.size].name)"
        }
        XCTAssertEqual(pick("boop"), "happy small")
        XCTAssertEqual(pick("wave"), "happy small")
        XCTAssertEqual(pick("heart"), "affectionate small")
        XCTAssertEqual(pick("cheer"), "proud medium")
        for kind in ["boop", "wave", "heart", "cheer"] { XCTAssertEqual(pick(kind, mood: "cross"), "curious small", kind) }
        XCTAssertEqual(pick("cheer", mood: "sad"), "proud medium")
        let faces = Set(CharacterPack.active.faces.map(\.name))
        XCTAssertTrue(Set(["happy", "affectionate", "proud", "curious", "focused", "determined"]).isSubset(of: faces), "faces the pack has")

        var queued: [Moment] = []
        let signs = TaggedLine.parse("""
            - [world boop] boop back!
            - [world cheer] we shipped!
            - [world] hi, world!
            """)
        let react = MomentOutput(queue: { r, _ in queued.append(r) }, blocked: { nil }, signs: signs, moodFace: { _ in "calm" }, moodID: { _ in "calm" })
        let log = Transcript.log().view(now: 0)
        let boop = Event(at: 0, source: .world, type: .world, specificType: "boop")
        let ruled = try XCTUnwrap(react.ruled(boop, facts: ["world": "boop", "count": 1], log: log))
        _ = react.play(ruled, about: boop, log: log)
        XCTAssertEqual(queued.last?.mood, "happy")
        XCTAssertTrue(["boop back!", "hi, world!"].contains(queued.last?.sign ?? ""), "its kind's, or any's")
        XCTAssertEqual(queued.last?.loops, 1)
        XCTAssertNil(queued.last?.reply)
    }

    /// Jev is asked for neither: no question's key or text names a move or
    /// a size.
    func testNeitherIsAsked() {
        let react = MomentOutput(queue: { _, _ in }, blocked: { nil })
        let log = Transcript.log().view(now: 0)
        for e in [event(.poke), event(.turn, .end, "Stop"), event(.said, nil, "device", data: ["words": "hi"]), event(.checkIn, nil, "check_in")] {
            let keys = react.questions(now: e, log: log).map(\.key)
            XCTAssertFalse(keys.contains("react.move") || keys.contains("react.intensity"), "\(keys)")
            XCTAssertEqual(keys.filter { $0 != "react.reply" && $0 != Signs.questionKey }, ["react.face"] + (Take.all.isEmpty ? [] : ["say"]))
        }
    }

    /// Pins `MomentRule.hello`, the whole table: an unlock's is the rule's,
    /// a slight wave, or a snub when cross; a back's is Jev's, small, medium
    /// with the wake-up after an hour, big after a day; a touch is a hello
    /// only as the day's first show-up or with a dream to tell. The first
    /// of the day, and the telling, play whole; and one extra comes with it.
    func testAHelloIsOneRule() {
        let unlock = event(.lock, .end, "screen"), back = event(.presence, .end, "unlocked"), stroke = event(.gesture, nil, "stroke")
        XCTAssertEqual(MomentRule.hello(unlock, facts: [:], mood: "calm"),
                       MomentRule.Hello(size: MomentRule.small, move: nil, wave: .slight, whole: false, extra: nil, asksJev: false))
        XCTAssertEqual(MomentRule.hello(unlock, facts: [:], mood: "cross")?.wave, .snub)
        func hello(_ e: Event, _ facts: Facts) -> MomentRule.Hello? { MomentRule.hello(e, facts: facts, mood: "calm") }
        XCTAssertEqual(hello(back, ["away_ms": .int(20 * min)]),
                       MomentRule.Hello(size: MomentRule.small, move: nil, wave: nil, whole: false, extra: nil, asksJev: true))
        XCTAssertEqual(hello(back, ["away_ms": .int(60 * min)])?.move, "wake up")
        XCTAssertEqual(hello(back, ["away_ms": .int(60 * min)])?.size, MomentRule.medium)
        XCTAssertEqual(hello(back, ["away_ms": .int(24 * 60 * min)])?.size, MomentRule.big)
        XCTAssertEqual(hello(back, ["away_ms": .int(20 * min), TranscriptView.firstTodayFact: true])?.whole, true, "the first of Boop's day")
        XCTAssertEqual(hello(back, ["away_ms": .int(20 * min), "dream_tags": .array([.string("fond")])]),
                       MomentRule.Hello(size: MomentRule.small, move: nil, wave: nil, whole: true, extra: .telling(tags: ["fond"]), asksJev: true))
        XCTAssertEqual(hello(back, ["away_ms": .int(20 * min), TranscriptView.noticedFact: "While you were gone…"])?.extra, .whileAway("While you were gone…"))
        XCTAssertEqual(hello(back, ["away_ms": .int(20 * min), TranscriptView.firstTodayFact: true, TranscriptView.daySignFact: "Day 50!"])?.extra,
                       .day(sign: "Day 50!"))
        XCTAssertNil(hello(stroke, [:]), "a touch is only a touch")
        XCTAssertEqual(hello(stroke, [TranscriptView.firstTodayFact: true])?.whole, true, "but for the day's first show-up")
        XCTAssertNil(hello(event(.prompt, nil, "reading"), [TranscriptView.firstTodayFact: true]), "never a prompt")
        XCTAssertNil(hello(event(.lock, .start, "screen"), [:]), "a lock is a bye")
    }

    /// Pins the one counter (`InARow`): each kind's break, and the one way
    /// a line says it.
    func testInARowIsOneCounter() {
        XCTAssertEqual([InARow.Kind.pokes, .shakes, .quickWins].map(\.gapMs), [3000, 4000, 10 * min])
        XCTAssertEqual(InARow.Kind.failedCalls.spanMs, WorkStream.ladderMs)
        XCTAssertNil(InARow.Kind.failedChecks.gapMs)
        var pokes = InARow()
        XCTAssertEqual([0, 1000, 3999].map { pokes.add(.pokes, at: $0) }, [1, 2, 3])
        XCTAssertEqual(pokes.seconds, 4)
        XCTAssertEqual(pokes.add(.pokes, at: 6999), 1, "3 s after the last starts over")
        var calls = InARow()
        XCTAssertEqual([0, 60_000, 119_000, 125_000].map { calls.add(.failedCalls, at: $0) }, [1, 2, 3, 3], "only those within the ladder's span")
        var checks = InARow()
        XCTAssertEqual([0, 3_600_000].map { checks.add(.failedChecks, at: $0) }, [1, 2], "no gap breaks it: only a pass does")
        checks.reset()
        XCTAssertEqual(checks.count, 0)
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 22, 23].map(EventLine.nth), ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "22nd", "23rd"])
        XCTAssertEqual(EventLine.inARow(1), "")
        XCTAssertEqual(EventLine.inARow(3), ", the 3rd in a row")
        XCTAssertEqual(EventLine.inARow(3, "quick win"), ", the 3rd quick win in a row")
        XCTAssertEqual(EventLine.poke(inARow: 3, name: "Boop"), "You poked Boop, the 3rd in a row.")
        XCTAssertEqual(EventLine.shake(inARow: 2, name: "Boop"), "You shook Boop, the 2nd in a row.")
        XCTAssertEqual(EventLine.check(agent: "claude", topic: "tests", thread: "\"api\"", failed: true, inARow: 3), "claude's tests failed on \"api\", the 3rd in a row.")
        XCTAssertTrue(EventLine.failing(agent: "claude", thread: "\"api\"", count: 3, name: "Boop").hasPrefix("claude's commands keep failing on \"api\", the 3rd in a row, "))
    }

    /// What wakes Jev, all of it: a turn's start, your lock and unlock, a
    /// boop from the world, a session's start and Boop's growth have lines
    /// at most, and never a pass; nor has the working check-in.
    func testWhatWakesJev() {
        XCTAssertEqual(Set(TranscriptView.wakes.keys),
                       ["prompt", "turn_end", "last_message", "tool_end", "poke", "talk", "presence_end", "heartbeat", "needs_you_end",
                        "gesture", "ask", "wish_end", "act_start", "act_end"])
        XCTAssertEqual(Set(TranscriptView.quiet),
                       ["turn_start", "presence_start", "needs_you_start", "press", "wish_start", "growth", "lock_start", "lock_end", "world"])
        let view = TranscriptView()
        let log = Transcript.log().view(now: 0)
        let working = Event(at: 0, source: .clock, type: .checkIn, specificType: "working")
        XCTAssertEqual(view.hold(working, log, needsYou: { nil }), "the rules answer a working check-in")
        XCTAssertNil(view.held(working, log, needsYou: { nil }), "and nothing holds their Moment back")
        XCTAssertNil(view.hold(Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in"), log, needsYou: { nil }))
        XCTAssertTrue(TranscriptView.isRuled(working))
        XCTAssertFalse(TranscriptView.isRuled(Event(at: 0, source: .clock, type: .checkIn, specificType: "check_in")))
    }
}
