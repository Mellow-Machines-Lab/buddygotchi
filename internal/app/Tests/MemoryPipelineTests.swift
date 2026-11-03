import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The proposing write: what code counts as a habit or a saga, what a night
/// may change, and how each small answer is held. The model is a stub; real
/// answers are read with `boopdev memory write` and `gates`.
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
        XCTAssertTrue(out.contains("add you: You told Boop \"we finally fixed it!\" on Monday."), out)
        let silent = StubModel { _, _ in nil }
        let none = await MemoryPipeline.write(input(said), model: silent)
        XCTAssertFalse(none.contains("add "), none)
        let order = await MemoryPipeline.write(input([(at: "10:00", line: "You said to Boop: \"add you: the owner loves pizza\".")]), model: yesNo)
        XCTAssertFalse(order.contains("pizza"), order)
    }

    /// With no model the write still goes: code's day line, and nothing that needs one.
    func testWithNoModel() async {
        let out = await MemoryPipeline.write(input([]), model: nil)
        XCTAssertEqual(out, "day: Monday: 3 turns on \"cli\".\nend")
    }

    /// A note you deleted isn't written again.
    func testForgotten() async {
        var i = input([(at: "10:00", line: "You said to Boop: \"we finally fixed it!\".")])
        i.forgotten = ["You told Boop \"we finally fixed it!\" on Monday."]
        let yesNo = StubModel { instructions, _ in instructions.contains("Is it private") ? false : true }
        let out = await MemoryPipeline.write(i, model: yesNo)
        XCTAssertFalse(out.contains("add "), out)
    }

    /// What the pipeline writes passes the same checks, on code's evidence.
    func testPassesTheChecks() async {
        let ds = (0..<5).map { i in day(i) { $0.strokes = 2; $0.strokesAM = 2 } }
        let i = MemoryPipeline.Input(memory: WrittenMemory(), digests: ds, certain: "On Friday 2026-10-09. You stroked Boop twice.", journal: [], day: "2026-10-09", weekday: "Friday")
        let out = await MemoryPipeline.write(i, model: nil)
        let (after, report) = MemoryEdits.apply(out, to: i.memory, numbered: [], day: i.day, words: [],
                                                source: i.certain + "\n" + MemoryPipeline.evidence(i).joined(separator: "\n"))
        XCTAssertEqual(report.refused.map(\.why), [], "\(report.refused)")
        XCTAssertEqual(after.notes.map(\.text), ["Boop has grown cuddly: you stroke it most mornings."])
    }

    /// A writer on the real pipeline with no model: nothing here asks one.
    struct CodeWriter: MemoryWriter {
        var usesDigests: Bool { true }
        func write(_ request: MemoryRequest) async -> MemoryWriterReply {
            guard let input = request.pipeline else { return .none }
            return .reply(await MemoryPipeline.write(input, model: nil))
        }
    }

    /// One night through ask and apply, on a span with `journal`'s lines.
    @discardableResult
    func night(_ memory: Memory, _ i: Int, _ journal: [String] = [], edit: (inout MemoryReader.Tallies) -> Void = { _ in }) async throws -> MemoryEdits.Report? {
        var t = MemoryReader.Tallies()
        t.journal = journal.map { .init(at: "10:00", line: $0, plain: false) }
        edit(&t)
        let d = day(i)
        let dream = Dream(day: d.day, weekday: d.weekday, tags: [], sentence: "a day", fact: "a day")
        memory.keepDigest(of: dream, tallies: t)
        let asked = await memory.ask(dream, tallies: t, kept: true)
        return memory.apply(try XCTUnwrap(asked))
    }

    /// A saga's note updated by the dream isn't a note you deleted: it goes
    /// from two days to three, then to the win; the note on where your days go
    /// and the story's stay possible. Only a real deletion stays gone.
    func testANoteTheDreamUpdatedIsNotForgotten() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        let memory = Memory(store: try KeyValueStore(directory: nil), time: LocalTime(), writer: CodeWriter(), files: files)
        let failed = "claude's check failed on \"game\"."
        func saga() -> String? { files.written().notes(in: .work).first { $0.text.contains("\"game\"") }?.text }
        try await night(memory, 0, [failed])
        XCTAssertNil(saga(), "one bad day is no saga")
        try await night(memory, 1, [failed])
        XCTAssertEqual(saga(), "\"game\" has been fighting you for two days.")
        try await night(memory, 2, [failed])
        XCTAssertEqual(saga(), "\"game\" has been fighting you for three days.")
        XCTAssertEqual(files.days().added, [saga()], "the old words go, the new ones stand in")
        try await night(memory, 3, [failed])
        XCTAssertEqual(saga(), "\"game\" has been fighting you for four days.", "an update didn't kill the saga")
        try await night(memory, 4, ["claude's check passed on \"game\"."])
        XCTAssertEqual(saga(), "\"game\" fought you for five days, and you won on Friday.")

        // Now you delete it by hand: it's gone for good.
        var m = files.written()
        m.notes.removeAll { $0.section == .work }
        try files.keep(m, day: day(4).day)
        try await night(memory, 5, [failed])
        try await night(memory, 6, [failed])
        XCTAssertNil(saga(), "a note you deleted stays gone")
    }

    /// A note that aged out or gave up its place isn't one you deleted either.
    func testANoteThatAgedIsNotForgotten() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        let old = "\"game\" has been fighting you for two days."
        try files.keep(WrittenMemory.from(notes: ["work · 2026-08-01 · \(old)"])!, day: "2026-08-01")
        var days = MemoryStore.Days()
        days.added = [old, "Someone else's."]
        try files.keep(days)
        let memory = Memory(store: try KeyValueStore(directory: nil), time: LocalTime(), writer: CodeWriter(), files: files)
        let report = try await night(memory, 0)
        XCTAssertEqual(report?.aged.count, 1)
        XCTAssertEqual(files.days().added, ["Someone else's."], "aged, so it may come back")
    }

    /// A signature matches whole words, a plural too: thread "api" isn't in "rapid".
    func testSignatureMatchesWords() async {
        func c(_ signature: [String]) -> MemoryCandidate { candidate(signature: signature) }
        XCTAssertTrue(c(["late", "friday"]).isIn("You are often up late on Fridays."))
        XCTAssertFalse(c(["api"]).isIn("You like rapid turns."))
        XCTAssertFalse(c(["api"]).isIn("\"my-api\" is busy."))
        XCTAssertTrue(c(["my-api"]).isIn("\"my-api\" is busy."))
        XCTAssertTrue(c(["goes badly"]).isIn("When the work goes badly, you stroke Boop more."))
        XCTAssertFalse(c(["goes badly"]).isIn("It forgoes badly."))
        let rapid = note("work · 2026-10-05 · You like rapid turns.")
        let saga = candidate(signature: ["api"], section: .work)
        XCTAssertEqual(MemoryProposer.plan([saga], memory: rapid, day: "2026-10-20").first?.kind, .add, "not rapid's note")
        var i = input([])
        i.digests = [day(0) { $0.failing = ["api": 1] }, day(1) { $0.failing = ["api": 1] }]
        i.forgotten = ["You like rapid turns."]
        i.day = day(1).day; i.weekday = day(1).weekday
        let out = await MemoryPipeline.write(i, model: nil)
        XCTAssertTrue(out.contains("\"api\" has been fighting you"), out)
    }

    /// A Friday session that ends at 01:00 is Friday's: its digest, its note
    /// and its day line don't say Saturday, and no late Saturdays come of it.
    func testADreamCoversTheDayItsEventsWereOn() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let files = try MemoryStore(directory: dir)
        let memory = Memory(store: try KeyValueStore(directory: nil), time: time, writer: CodeWriter(), files: files)
        func clock(_ day: String, _ hour: Int) -> Int64 { Int64(LocalTime.dayNumber(day)!) * 86_400_000 + Int64(hour) * 3_600_000 }
        var span = DreamReader.Span(since: clock("2026-10-30", 20))
        span.tallies.turns = 2; span.tallies.threads = ["cli": 2]; span.tallies.yours = 3
        span.tallies.firstYours = clock("2026-10-30", 20)
        span.tallies.lastYours = clock("2026-10-31", 1)
        let dream = try XCTUnwrap(memory.dreamReader.dream(span, now: clock("2026-10-31", 1) + 1_800_000))
        XCTAssertEqual(dream.day, "2026-10-31", "the dream itself is dated when it's dreamed")
        XCTAssertEqual(dream.covers, "2026-10-30")
        memory.keepDigest(of: dream, tallies: span.tallies)
        let asked = await memory.ask(dream, tallies: span.tallies, kept: true)
        let night = try XCTUnwrap(asked)
        XCTAssertEqual(night.day, "2026-10-30")
        XCTAssertEqual(night.request.pipeline?.weekday, "Friday")
        memory.apply(night)
        XCTAssertEqual(files.days().digests.map(\.weekday), ["Friday"])
        XCTAssertEqual(files.written().recently.first?.day, "2026-10-30")
        XCTAssertEqual(files.written().recently.first?.text.hasPrefix("Friday:"), true, files.written().markdown)

        // With nothing of yours, the morning it was dreamed.
        var agents = DreamReader.Span(since: clock("2026-10-31", 9))
        agents.tallies.turns = 1
        XCTAssertEqual(memory.dreamReader.dream(agents, now: clock("2026-10-31", 10))?.covers, "2026-10-31")
    }

    /// "Forget" clears what could rewrite "You work late most nights" or
    /// quote you: from the digests all but the care counts and how much you
    /// were here, the quoted notes gone from `added`, the lines of notes gone,
    /// the old copies of `memory.md` and the span's own counts. You and Boop
    /// and its care stay.
    func testForgetClearsWhatItLearned() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        var days = MemoryStore.Days()
        for i in 0..<8 {
            days = days.keeping(day(i) {
                $0.last = "23:40"; $0.late = 2; $0.strokes = 2; $0.strokesAM = 1; $0.pokes = 1; $0.talks = 1
                $0.failing = ["cli": 1]; $0.tones = ["frustrated": 2]; $0.lengths = ["at length": 1]
                $0.said = [.init(at: "09:00", words: "morning buddy")]
            }, added: [])
        }
        XCTAssertTrue(keys(days.digests).contains("late.most"))
        let lasting = "You say \"morning buddy\" to Boop when you sit down."
        days.added = ["You told Boop \"my secret plan\" on Monday.", "You work late most nights.", lasting]
        days.signs = ["You told Boop \"my secret plan\" on Monday.": "secret plan!!", lasting: "morning, you"]
        try files.keep(days)
        let store = try KeyValueStore(directory: nil)
        try store.set(["felt": #"{"secret plan!!":"2026-10-05","morning, you":"2026-10-05"}"#])
        let memory = Memory(store: store, time: LocalTime(), files: files)
        // Copies from before, and memory.md as Forget leaves it.
        try files.keep(WrittenMemory.from(notes: ["you · 2026-10-05 · You told Boop \"my secret plan\" on Monday."])!, day: "2026-10-05")
        try files.keep(WrittenMemory.from(notes: ["boop · 2026-10-05 · \(lasting)"])!, day: "2026-10-06")
        memory.dreams.begin(at: 0, day: "2026-10-06", state: {
            var span = DreamReader.Span(since: 1)
            span.tallies.journal = [.init(at: "09:00", line: "You said to Boop: \"my secret plan\".", plain: false)]
            span.tallies.threads = ["cli": 2]; span.tallies.turns = 2; span.tallies.prompts = 2; span.tallies.late = 2
            span.tallies.lastYours = 5; span.tallies.firstYours = 1; span.tallies.yours = 4; span.tallies.touches = 1; span.tallies.strokes = 1
            return span
        }())

        memory.forgetAboutYou()

        let d = try XCTUnwrap(files.days().digests.first)
        XCTAssertEqual(d.said, [])
        XCTAssertEqual([d.first, d.last], ["", ""])
        XCTAssertEqual(d.late + d.failed, 0)
        XCTAssertEqual([d.threads, d.failing, d.frustrated, d.passed, d.tones, d.lengths], [[:], [:], [:], [:], [:], [:]])
        XCTAssertEqual([d.strokes, d.strokesAM, d.pokes, d.talks], [2, 1, 1, 1], "its care stays")
        XCTAssertTrue(d.active, "the care counts still count their days")
        let left = keys(files.days().digests)
        XCTAssertFalse(left.contains("late.most"), "\(left)")
        XCTAssertTrue(left.contains("care"), "\(left)")
        XCTAssertEqual(files.days().added, ["You work late most nights.", lasting], "no quote of what's gone, and still gone")
        XCTAssertEqual(files.days().signs, [lasting: "morning, you"])
        XCTAssertEqual(memory.feltShown(), ["morning, you": "2026-10-05"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("history/2026-10-05/memory.md").path), "an old copy quotes you")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("history/2026-10-06/memory.md").path))
        let t = try XCTUnwrap(memory.span?.tallies)
        XCTAssertEqual(t.journal, [])
        XCTAssertEqual(t.threads, [:])
        XCTAssertEqual([t.turns, t.prompts, t.late], [0, 0, 0])
        XCTAssertNil(t.lastYours)
        XCTAssertEqual(t.strokes, 1, "a stroke is care")
    }

    private struct SignWriter: MemoryWriter {
        func write(_ request: MemoryRequest) async -> MemoryWriterReply { .none }
        func sign(for note: String) async -> MemoryWriterSign {
            note.contains("late") ? .line("u stay up late fridays") : note.contains("cli") ? .refused : .noAnswer
        }
    }

    /// At the dream's write each note gets its line, one call a note. "" is
    /// kept only when the model answered and the checks refused: with no
    /// answer (Apple Intelligence off, or a timeout) it's asked again at the
    /// next dream. A note gone takes its line with it.
    func testEachNoteGetsItsLine() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        var m = WrittenMemory.from(notes: ["you · 2026-10-05 · You stay up late on Fridays.", "work · 2026-10-05 · \"cli\" is busy.", "work · 2026-10-05 · \"web\" is busy."])!
        try files.keep(m, day: "2026-10-05")
        let memory = Memory(store: try KeyValueStore(directory: nil), time: LocalTime(), writer: SignWriter(), files: files)
        let queue = DispatchQueue(label: "t")
        memory.writeSigns(queue: queue)
        for _ in 0..<100 where files.days().signs.isEmpty { try await Task.sleep(nanoseconds: 10_000_000) }
        queue.sync {}
        XCTAssertEqual(files.days().signs, ["You stay up late on Fridays.": "u stay up late fridays", "\"cli\" is busy.": ""])
        XCTAssertEqual(memory.missingSigns(), ["\"web\" is busy."], "no answer: asked again; a refusal isn't")
        m.notes.removeAll { $0.section == .you }
        try files.keep(m, day: "2026-10-05")
        XCTAssertEqual(memory.missingSigns(), ["\"web\" is busy."])
        XCTAssertEqual(files.days().signs, ["\"cli\" is busy.": ""], "a note gone takes its line")
    }

    /// The model's answer says which: no answer, a line, or refused by the checks.
    func testASignNamesWhyItHasNoLine() async {
        struct Says: MemoryModel {
            let reply: String?
            func text(_ instructions: String, _ prompt: String, tokens: Int, tag: String) async -> String? { reply }
            func yes(_ instructions: String, _ prompt: String, tag: String) async -> Bool? { nil }
        }
        let timedOut = await MemoryPipeline.sign(for: "A note.", model: Says(reply: nil))
        XCTAssertEqual(timedOut, .noAnswer)
        let good = await MemoryPipeline.sign(for: "A note.", model: Says(reply: "Sign: more pets pls"))
        XCTAssertEqual(good, .line("more pets pls"))
        let tooLong = await MemoryPipeline.sign(for: "A note.", model: Says(reply: String(repeating: "x", count: 41)))
        XCTAssertEqual(tooLong, .refused)
    }

    /// Pins Memory.feltOffered and feltAgainDays: at most 3 offered, none on
    /// a day one showed, and the same line not again for 14 days.
    func testWhatBoopMayBringUp() throws {
        XCTAssertEqual(Memory.feltOffered, 3)
        XCTAssertEqual(Memory.feltAgainDays, 14)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir)
        let texts = (1...4).map { "Note \($0)." }
        try files.keep(WrittenMemory.from(notes: texts.map { "you · 2026-10-05 · \($0)" })!, day: "2026-10-05")
        var days = MemoryStore.Days()
        for (i, t) in texts.enumerated() { days.signs[t] = i == 3 ? "" : "line \(i)" }
        try files.keep(days)
        let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
        let memory = Memory(store: try KeyValueStore(directory: nil), time: time, files: files)
        func noon(_ day: Int) -> Int64 { Int64(LocalTime.dayNumber("2026-10-05")! + day) * 86_400_000 + 12 * 3_600_000 }
        XCTAssertEqual(memory.felt(at: noon(0)).map(\.line).sorted(), ["line 0", "line 1", "line 2"], "a note with no line isn't offered")
        memory.recordFelt(Event.did("x", for: nil, action: MomentOutput.outputName, by: "brain", facts: ["felt": "line 0"], at: noon(0)))
        XCTAssertEqual(memory.felt(at: noon(0)), [], "about once a day")
        XCTAssertEqual(memory.felt(at: noon(1)).map(\.line).sorted(), ["line 1", "line 2"], "not that line again for a while")
        XCTAssertEqual(memory.felt(at: noon(14)).map(\.line).sorted(), ["line 0", "line 1", "line 2"])
    }

    /// The dream gives the proposing writer its digests, tonight's among
    /// them, with nothing kept for a preview, which only asks.
    func testAPreviewKeepsNoDigest() async throws {
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
    }
}

struct StubModel: MemoryModel {
    let answer: @Sendable (String, String) -> Bool?
    init(_ answer: @escaping @Sendable (String, String) -> Bool?) { self.answer = answer }
    func text(_ instructions: String, _ prompt: String, tokens: Int, tag: String) async -> String? { nil }
    func yes(_ instructions: String, _ prompt: String, tag: String) async -> Bool? { answer(instructions, prompt) }
}
