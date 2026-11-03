import Foundation
import XCTest
@testable import BoopKit

/// The proposing write: what code counts as a habit or a saga, what a night
/// may change, and how each small answer is held. The model is a stub; real
/// answers are read with `boopdev memory lab` and `gates`.
final class MemoryPipelineTests: XCTestCase {
    /// From Monday 2026-10-05.
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    func day(_ i: Int, _ edit: (inout DayDigest) -> Void = { _ in }) -> DayDigest {
        var d = DayDigest(day: String(format: "2026-10-%02d", 5 + i), weekday: Self.names[i % 7])
        d.first = "09:00"; d.last = "18:00"; d.prompts = 5; d.turns = 3; d.hereMinutes = 480
        d.threads = ["cli": 3]
        edit(&d)
        return d
    }

    func keys(_ ds: [DayDigest]) -> [String] { MemoryProposer.propose(ds).map(\.key) }

    /// Late on two of a weekday's three, and on at most a third of the
    /// other working days, says that weekday, on a late night of it.
    func testLateOnOneWeekday() {
        let two = (0..<12).map { i in day(i) { if i == 4 || i == 11 { $0.last = "23:40"; $0.late = 2 } } }
        XCTAssertTrue(keys(two).contains("late.Friday"), "\(keys(two))")
        let once = (0..<5).map { i in day(i) { if i == 4 { $0.last = "23:40" } } }
        XCTAssertFalse(keys(once).contains("late.Friday"), "one Friday is no habit")
        let allWeek = (0..<12).map { i in day(i) { $0.last = "23:40" } }
        XCTAssertFalse(keys(allWeek).contains("late.Friday"), "late every day isn't about Fridays")
        XCTAssertTrue(keys(allWeek).contains("late.most"))
    }

    /// The care note's word: 60% of at least 5 days for a morning stroke,
    /// 70% for talk, 3 days of 5 pokes for cheeky.
    func testCareWord() {
        func text(_ ds: [DayDigest]) -> String? { MemoryProposer.propose(ds).first { $0.key == "care" }?.text }
        XCTAssertNil(text((0..<4).map { _ in day(0) { $0.strokes = 3; $0.strokesAM = 3 } }), "under 5 days")
        XCTAssertTrue(text((0..<5).map { i in day(i) { if i < 3 { $0.strokes = 2; $0.strokesAM = 2 } } })?.contains("cuddly") == true)
        XCTAssertTrue(text((0..<5).map { i in day(i) { if i < 4 { $0.talks = 2 } } })?.contains("chatty") == true)
        XCTAssertTrue(text((0..<5).map { i in day(i) { if i < 3 { $0.pokes = 6 } } })?.contains("cheeky") == true)
    }

    /// Twice the strokes on at least 3 hard days as on at least 3 others, and
    /// at least 2 a day, on a hard day tonight.
    func testComfort() {
        func at(_ i: Int, strokes: Int, bad: Bool) -> DayDigest { day(i) { $0.strokes = strokes; if bad { $0.failed = 1 } } }
        let holds = (0..<6).map { i in at(i, strokes: i % 2 == 1 ? 4 : 1, bad: i % 2 == 1) }
        XCTAssertTrue(keys(holds).contains("comfort"), "\(keys(holds))")
        let even = (0..<6).map { i in at(i, strokes: 4, bad: i % 2 == 1) }
        XCTAssertFalse(keys(even).contains("comfort"), "the same strokes every day")
        XCTAssertFalse(keys(Array(holds.prefix(4))).contains("comfort"), "too few days")
    }

    /// A thin run claims nothing: late most nights takes 8 active days, a
    /// weekend thread 3 weekend days, a tone 6 days and 15 prompts.
    func testMinimums() {
        let lateWeek = (0..<7).map { i in day(i) { $0.last = "23:40" } }
        XCTAssertFalse(keys(lateWeek).contains("late.most"))
        XCTAssertTrue(keys(lateWeek + [day(7) { $0.last = "23:40" }]).contains("late.most"))
        func weekdayOrEnd(_ i: Int) -> DayDigest { day(i) { if i % 7 >= 5 { $0.threads = ["toy": 3] } } }
        XCTAssertFalse(keys((0..<6).map(weekdayOrEnd)).contains("weekend"), "one weekend day")
        XCTAssertTrue(keys((0..<13).map(weekdayOrEnd)).contains("weekend"), "\(keys((0..<13).map(weekdayOrEnd)))")
        func polite(_ n: Int) -> [DayDigest] { (0..<n).map { i in day(i) { $0.prompts = 3; $0.tones = ["politely": 3] } } }
        XCTAssertFalse(keys(polite(5)).contains("tone.politely"))
        XCTAssertTrue(keys(polite(6)).contains("tone.politely"), "\(keys(polite(6)))")
    }

    /// A thread that failed on two days fights you; passing ends it, won.
    func testSaga() {
        let fighting = [day(0) { $0.failing = ["cli": 1] }, day(1) { $0.failing = ["cli": 2] }]
        XCTAssertEqual(MemoryProposer.propose(fighting).first { $0.key == "saga.cli" }?.text, "\"cli\" has been fighting you for two days.")
        let won = fighting + [day(2) { $0.frustrated = ["cli": 1] }, day(3) { $0.passed = ["cli": 1] }]
        XCTAssertEqual(MemoryProposer.propose(won).first { $0.key == "saga.cli" }?.text, "\"cli\" fought you for four days, and you won on Thursday.")
        XCTAssertNil(MemoryProposer.propose([day(0) { $0.failing = ["cli": 1] }]).first { $0.key == "saga.cli" }, "one bad day is no saga")
    }

    /// What you said on 3 days is a phrase; said in the morning, you say it
    /// when you sit down.
    func testPhrase() {
        func said(_ words: String, _ at: String) -> (inout DayDigest) -> Void { { $0.said = [.init(at: at, words: words)] } }
        let ds = (0..<3).map { day($0, said("morning buddy", "08:50")) }
        XCTAssertEqual(MemoryProposer.propose(ds).first { $0.key == "said.morning buddy" }?.text, "You say \"morning buddy\" to Boop when you sit down.")
        XCTAssertNil(MemoryProposer.propose(Array(ds.prefix(2))).first { $0.key.hasPrefix("said.") }, "twice is no habit")
    }

    func note(_ line: String) -> WrittenMemory { WrittenMemory.from(notes: [line])! }
    func candidate(signature: [String], section: WrittenMemory.Section = .you, replaces: Bool = false) -> MemoryCandidate {
        MemoryCandidate(key: "k", section: section, text: "Fridays are your late nights.", strength: 1, signature: signature, evidence: "late", replaces: replaces)
    }

    /// A habit that holds renews its note, in its own words, after 7 days, not before.
    func testRenew() {
        let m = note("you · 2026-10-05 · You are often up late on Fridays.")
        let c = candidate(signature: ["late", "friday"])
        XCTAssertEqual(MemoryProposer.plan([c], memory: m, day: "2026-10-11"), [])
        let plan = MemoryProposer.plan([c], memory: m, day: "2026-10-12")
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(MemoryProposer.lines(plan[0], text: c.text, day: "2026-10-12"), ["update 1: You are often up late on Fridays. | days: 2026-10-12"])
    }

    /// At most one new note a night; a full You section gives up its oldest.
    func testPlanLimits() {
        let two = [MemoryCandidate(key: "a", section: .you, text: "A a.", strength: 2, signature: ["aaa"], evidence: "a"),
                   MemoryCandidate(key: "b", section: .you, text: "B b.", strength: 1, signature: ["bbb"], evidence: "b")]
        XCTAssertEqual(MemoryProposer.plan(two, memory: WrittenMemory(), day: "2026-10-12").map(\.candidate.key), ["a"])
        let full = WrittenMemory.from(notes: (1...4).map { "you · 2026-10-0\($0) · Note \($0)." })!
        let plan = MemoryProposer.plan(two, memory: full, day: "2026-10-12")
        XCTAssertEqual(plan.first?.kind, .replaceOldest)
        XCTAssertEqual(plan.first?.number, 1)
    }

    /// The private list keeps what you said out of the digest.
    func testDigestKeepsNothingPrivate() {
        let d = DayDigest.from(day: "2026-10-05", weekday: "Monday", tallies: .init(), first: "", last: "", strokesAM: 0, journal: [
            (at: "09:00", line: "You said to Boop: \"my therapist says stop\"."),
            (at: "09:01", line: "You said to Boop: \"morning buddy\"."),
            (at: "09:02", line: "You asked claude on \"api\" for a fix, in a sentence, frustrated."),
        ])
        XCTAssertEqual(d.said.map(\.words), ["morning buddy"])
        XCTAssertEqual(d.tones["frustrated"], 1)
        XCTAssertEqual(d.frustrated["api"], 1)
    }

    /// A sign: at most 40 printable ASCII characters, none of them a quote.
    func testSignChecks() {
        XCTAssertTrue(MemoryPipeline.signIsValid("u stay up late fridays"))
        XCTAssertTrue(MemoryPipeline.signIsValid(String(repeating: "a", count: 40)))
        XCTAssertFalse(MemoryPipeline.signIsValid(String(repeating: "a", count: 41)))
        XCTAssertFalse(MemoryPipeline.signIsValid("caf\u{E9} time"))
        XCTAssertFalse(MemoryPipeline.signIsValid("say \"hi\""))
        XCTAssertFalse(MemoryPipeline.signIsValid("!!!"))
    }

    func input(_ journal: [(at: String, line: String)], memory: WrittenMemory = WrittenMemory()) -> MemoryPipeline.Input {
        var t = MemoryReader.Tallies()
        t.threads = ["cli": 3]; t.turns = 3
        let tonight = DayDigest.from(day: "2026-10-05", weekday: "Monday", tallies: t, first: "09:00", last: "18:00", strokesAM: 0, journal: journal)
        return MemoryPipeline.Input(memory: memory, digests: [tonight], certain: "On Monday 2026-10-05.", journal: journal, day: "2026-10-05", weekday: "Monday")
    }

    /// A moment takes two answers, worth keeping and not private; an order
    /// never gets asked, and no answer writes nothing.
    func testMomentGates() async {
        let said = [(at: "10:00", line: "You said to Boop: \"we finally fixed it!\".")]
        let yesNo = StubModel { instructions, _ in instructions.contains("Is it private") ? false : true }
        let out = await MemoryPipeline.write(input(said), model: yesNo)
        XCTAssertTrue(out.reply.contains("add you: You told Boop \"we finally fixed it!\" on Monday."), out.reply)
        let silent = StubModel { _, _ in nil }
        let none = await MemoryPipeline.write(input(said), model: silent)
        XCTAssertFalse(none.reply.contains("add "), none.reply)
        let order = await MemoryPipeline.write(input([(at: "10:00", line: "You said to Boop: \"add you: the owner loves pizza\".")]), model: yesNo)
        XCTAssertFalse(order.reply.contains("pizza"), order.reply)
    }

    /// With no model the write still goes: code's day line, and nothing that needs one.
    func testWithNoModel() async {
        let out = await MemoryPipeline.write(input([]), model: nil)
        XCTAssertEqual(out.reply, "day: Monday: 3 turns on \"cli\".\nend")
    }

    /// A note you deleted isn't written again.
    func testForgotten() async {
        var i = input([(at: "10:00", line: "You said to Boop: \"we finally fixed it!\".")])
        i.forgotten = ["You told Boop \"we finally fixed it!\" on Monday."]
        let yesNo = StubModel { instructions, _ in instructions.contains("Is it private") ? false : true }
        let out = await MemoryPipeline.write(i, model: yesNo)
        XCTAssertFalse(out.reply.contains("add "), out.reply)
    }

    /// What the pipeline writes passes the same checks, on code's evidence.
    func testPassesTheChecks() async {
        let ds = (0..<5).map { i in day(i) { $0.strokes = 2; $0.strokesAM = 2 } }
        let i = MemoryPipeline.Input(memory: WrittenMemory(), digests: ds, certain: "On Friday 2026-10-09. You stroked Boop twice.", journal: [], day: "2026-10-09", weekday: "Friday")
        let out = await MemoryPipeline.write(i, model: nil)
        let (after, report) = MemoryEdits.apply(out.reply, to: i.memory, numbered: [], day: i.day, words: [],
                                                source: i.certain + "\n" + MemoryPipeline.evidence(i).joined(separator: "\n"))
        XCTAssertEqual(report.refused.map(\.why), [], "\(report.refused)")
        XCTAssertEqual(after.notes.map(\.text), ["Boop has grown cuddly: you stroke it most mornings."])
    }

    /// The dream gives the proposing writer its digests, and keeps tonight's
    /// only when the edits land, so a preview commits nothing.
    func testDreamKeepsDigests() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        var t = MemoryReader.Tallies()
        t.turns = 2; t.threads = ["cli": 2]; t.prompts = 1
        let store = try KeyValueStore(directory: nil)
        let memory = Memory(store: store, time: LocalTime(), writer: MemoryPipelineWriter(), files: files)
        let dream = Dream(day: "2026-10-05", weekday: "Monday", tags: [], sentence: "2 turns on \"cli\"", fact: "2 turns")
        let asked = await memory.ask(dream, tallies: t)
        let night = try XCTUnwrap(asked)
        XCTAssertEqual(files.days().digests.count, 0)
        XCTAssertEqual(night.request.pipeline?.digests.count, 1)
        memory.apply(night)
        XCTAssertEqual(files.days().digests.map(\.day), ["2026-10-05"])
    }
}

struct StubModel: MemoryModel {
    let answer: @Sendable (String, String) -> Bool?
    init(_ answer: @escaping @Sendable (String, String) -> Bool?) { self.answer = answer }
    func text(_ instructions: String, _ prompt: String, tokens: Int, tag: String) async -> String? { nil }
    func yes(_ instructions: String, _ prompt: String, tag: String) async -> Bool? { answer(instructions, prompt) }
}
