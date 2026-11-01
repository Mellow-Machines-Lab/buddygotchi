import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Asks: what the buddy may ask you, when, and what it keeps of your
/// answer.
final class AsksTests: XCTestCase {
    let lines = TaggedLine.parse("""
        - [snack idle keeps] fav snack? | cookie | pizza
        - [pet lonely touch] pet me? | ok | later
        - [tabs idle] tabs or spaces? | tabs | spaces
        - [snack cookie] nom nom
        - [tabs spaces] traitor
        """)
    let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    /// Noon UTC on 2026-10-27.
    let noon: Int64 = 1_793_102_400_000

    /// A line with parts is a question, its first tag the id and `keeps`
    /// and `touch` taken out of the moment's tags; a line with none is a
    /// follow-up, found by the question's id and the answer.
    func testQuestionsAndFollowUps() {
        XCTAssertEqual(TaggedLine.parse("- [a] x | y | z")[0].parts, ["x", "y", "z"])
        XCTAssertEqual(TaggedLine.parse("- [a] plain words")[0].parts, ["plain words"])
        let q = Asks.questions(lines)
        XCTAssertEqual(q.map(\.id), ["snack", "pet", "tabs"])
        XCTAssertEqual(q[0], Asks.Question(id: "snack", question: "fav snack?", a: "cookie", b: "pizza", tags: ["idle"], keeps: true, touch: false))
        XCTAssertEqual(q[1].tags, ["lonely"])
        XCTAssertTrue(q[1].touch)
        XCTAssertEqual(Asks.followUps(lines, id: "snack", answer: "Cookie"), ["nom nom"])
        XCTAssertEqual(Asks.followUps(lines, id: "snack", answer: "pizza"), [])
    }

    /// One answered is off for 30 days, one that keeps for good, one
    /// ignored or unanswered for a day.
    func testHowLongAQuestionStaysOff() {
        let answered = Asks.Record(asked: "2026-10-01", answer: "tabs", keeps: false)
        XCTAssertTrue(Asks.off(answered, today: "2026-10-30"))
        XCTAssertFalse(Asks.off(answered, today: "2026-10-31"), "answered: 30 days, Asks.answeredOffDays")
        XCTAssertTrue(Asks.off(Asks.Record(asked: "2026-01-01", answer: "cookie", keeps: true), today: "2026-10-31"))
        let ignored = Asks.Record(asked: "2026-10-30", keeps: true, ignored: true)
        XCTAssertTrue(Asks.off(ignored, today: "2026-10-30"))
        XCTAssertFalse(Asks.off(ignored, today: "2026-10-31"), "ignored: a day, Asks.ignoredOffDays")
        XCTAssertFalse(Asks.off(nil, today: "2026-10-31"))
    }

    /// The questions offered are those whose tags the moment has and that
    /// aren't off, in the file's order.
    func testOfferedFitTheMoment() {
        let q = Asks.questions(lines)
        func offered(_ tags: Set<String>, _ records: [String: Asks.Record] = [:]) -> [String] {
            Asks.offered(q, tags: tags, record: { records[$0] }, today: "2026-10-31").map(\.id)
        }
        XCTAssertEqual(offered(["idle"]), ["snack", "tabs"])
        XCTAssertEqual(offered(["idle", "lonely"]), ["snack", "pet", "tabs"])
        XCTAssertEqual(offered(["working"]), [])
        XCTAssertEqual(offered(["idle"], ["snack": Asks.Record(asked: "2026-10-02", answer: "pizza", keeps: true)]), ["tabs"])
    }

    /// At most one ask an hour and three a day; chatty six; quiet none.
    func testTheCaps() {
        let hour = Asks.hourMs
        func allowed(_ talk: Talk, _ ago: [Int64]) -> Bool {
            Asks.allowed(talk: talk, askedAt: ago.map { noon - $0 }, now: noon, sameDay: { _ in true })
        }
        XCTAssertTrue(allowed(.normal, []))
        XCTAssertFalse(allowed(.quiet, []), "quiet asks nothing")
        XCTAssertFalse(allowed(.normal, [hour - 1]), "one an hour")
        XCTAssertTrue(allowed(.normal, [hour, 2 * hour]))
        XCTAssertFalse(allowed(.normal, [hour, 2 * hour, 3 * hour]), "three a day, Asks.perDay")
        XCTAssertTrue(allowed(.chatty, [hour, 2 * hour, 3 * hour]))
        XCTAssertFalse(allowed(.chatty, (1...6).map { Int64($0) * hour }), "six a day chatty, Asks.chattyPerDay")
        XCTAssertEqual([Asks.perDay, Asks.chattyPerDay], [3, 6])
        XCTAssertEqual(hour, 3_600_000)
    }

    /// A kept answer is a tag for good, another for 30 days, an ignored
    /// one none.
    func testAnswersBecomeTags() {
        let records = ["snack": Asks.Record(asked: "2026-01-01", answer: "Cookie", keeps: true),
                       "tabs": Asks.Record(asked: "2026-10-20", answer: "spaces", keeps: false),
                       "old": Asks.Record(asked: "2026-09-01", answer: "yes", keeps: false),
                       "pet": Asks.Record(asked: "2026-10-30", keeps: false, ignored: true)]
        XCTAssertEqual(Asks.answerTags(records, today: "2026-10-31"), ["cookie", "spaces"])
    }

    /// The memory keeps a question asked from the react output's `did`,
    /// then its answer from the `ask` event; its tag follows.
    func testTheMemoryKeepsTheAnswer() throws {
        let memory = Memory(store: try KeyValueStore(directory: nil), time: utc)
        memory.recordAsk(Event.did("Boop asks you: fav snack?", for: nil, action: ReactOutput.outputName, by: "brain",
                                   facts: ["ask": "snack", "keeps": true], at: noon))
        XCTAssertEqual(memory.askRecord("snack"), Asks.Record(asked: "2026-10-27", keeps: true))
        memory.recordAsk(Event(at: noon + 5000, source: .device, type: .ask, specificType: "a",
                               data: ["q": "snack", "question": "fav snack?", "answer": "cookie"]))
        XCTAssertEqual(memory.askRecord("snack")?.answer, "cookie")
        XCTAssertEqual(memory.answerTags(at: noon + 400 * 86_400_000), ["cookie"], "kept for good")
        memory.recordAsk(Event.did("Boop asks you: tabs?", for: nil, action: ReactOutput.outputName, by: "brain",
                                   facts: ["ask": "tabs", "keeps": false], at: noon))
        memory.recordAsk(Event(at: noon + 5000, source: .device, type: .ask, specificType: Asks.ignored,
                               data: ["q": "tabs", "question": "tabs or spaces?"]))
        XCTAssertEqual(memory.askRecord("tabs"), Asks.Record(asked: "2026-10-27", keeps: false, ignored: true))
    }

    /// An idle moment offers the idle questions; nothing is asked while
    /// an agent needs you, or with no memory to keep the answer.
    func testNothingAsksWhileAnAgentNeedsYou() throws {
        let rig = CoreRig()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: rig.time)
        let questions = Asks.questions(lines)
        rig.send(.sessionStart)
        func askable(_ memory: Memory?) -> [String] {
            let about = Event(at: rig.now, source: .clock, type: .heartbeat, specificType: "check_in")
            return Asks.askable(about, rig.pipeline.harness.log.view(now: rig.now), questions: questions, core: rig.core,
                                mood: MoodOutput.choice(), talk: .normal, memory: memory, wall: rig.now).map(\.id)
        }
        XCTAssertEqual(askable(memory), ["snack", "tabs"], "an idle check-in, nobody untouched an hour yet")
        XCTAssertEqual(askable(nil), [])
        rig.send(.needsYou, tool: "Bash")
        XCTAssertEqual(askable(memory), [], "none while something needs you")
    }

    /// A `daily` question may come back the next day, answered or not.
    func testADailyQuestionComesBackTheNextDay() {
        let pet = Asks.questions(TaggedLine.parse("- [pet lonely touch daily] pet me? | ok | later"))[0]
        XCTAssertTrue(pet.daily)
        XCTAssertEqual(pet.tags, ["lonely"])
        let answered = Asks.Record(asked: "2026-10-30", answer: "ok", keeps: false)
        XCTAssertTrue(Asks.off(answered, today: "2026-10-30", daily: true))
        XCTAssertFalse(Asks.off(answered, today: "2026-10-31", daily: true))
    }

    /// The idle musings: [idle] lines, blanks from the day, a line needing
    /// turns left out at none, kept answers' lines only with the answer.
    func testTheIdleMusings() {
        let lines = TaggedLine.parse("""
            - [idle] quiet day...
            - [idle] {turns} turns today!
            - [idle] {thread} again?
            - [idle cookie] snack time?
            - a prompt's caption
            """)
        XCTAssertEqual(Signs.musings(lines, tags: [], turns: 0, thread: ""), ["quiet day..."])
        XCTAssertFalse(Signs.musings(lines, tags: [], turns: 1, thread: "").contains("1 turns today!"), "turns from 2")
        XCTAssertEqual(Signs.musings(lines, tags: ["cookie"], turns: 7, thread: "api"),
                       ["quiet day...", "7 turns today!", "api again?", "snack time?"])
        XCTAssertEqual(Signs.musingEveryMs, 3_600_000, "at most once an hour")
    }

    /// The pack check finds a line neither a question nor a follow-up, one
    /// too long for the board, and a follow-up to nothing.
    func testThePackCheckReadsTheAsks() {
        XCTAssertEqual(PackCheck.asks(lines), [])
        let bad = TaggedLine.parse("""
            - [x idle] a question far too long? | a | b
            - [y idle] two parts | only
            - [z idle] ok? | a much longer one | b
            - [snack pie] yum
            """)
        let found = PackCheck.asks(bad)
        XCTAssertEqual(found.count, 4, found.joined(separator: "\n"))
    }
}
