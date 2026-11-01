import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The written memory: memory.md, the night's edits and their checks, the
/// request the writer gets, and MEMORY as Jev reads it.
final class WrittenMemoryTests: XCTestCase {
    static let file = """
        # Boop's memory

        Written each night by Apple Intelligence on this Mac.

        ## You
        - m3 · 2026-10-20, 2026-10-30 · You work late most nights, and you say please to claude.
        - a line the person wrote by hand

        ## Your work
        - m12 · 2026-10-26, 2026-10-30 · "api": the test failures that ran all week were fixed on Friday.
        - m15 · 2026-10-01 · "blog": moving to a new host, half done.

        ## You and Boop
        - m9 · pinned · 2026-09-14, 2026-10-30 · You stroke Boop when you sit down in the morning.
        - m11 · 2026-09-02 · You told Boop its favourite snack is cookies.

        ## Recently
        - 2026-10-30 · Friday: a long day on "api"; the tests finally passed.
        - 2026-10-29 · Thursday: three turns broke on "api".
        """

    /// memory.md reads back as it was written, a line it can't read kept
    /// where it was, a pinned note pinned.
    func testTheFileRoundTrips() {
        let m = WrittenMemory.parse(Self.file)
        XCTAssertEqual(m.notes.map(\.id), [3, 12, 15, 9, 11])
        XCTAssertEqual(m.notes(in: .boop).map(\.pinned), [true, false])
        XCTAssertEqual(m.recently.map(\.day), ["2026-10-30", "2026-10-29"])
        XCTAssertEqual(m.unread["You"], ["- a line the person wrote by hand"])
        XCTAssertEqual(WrittenMemory.parse(m.markdown), m)
        XCTAssertEqual(m.nextId, 16)
    }

    /// MEMORY: each section a line, Recently named from today, the
    /// weekday a line starts with left to the day; within its budget,
    /// Recently cut to 3 days first, then the oldest notes.
    func testMemoryAsJevReadsIt() throws {
        let m = WrittenMemory.parse(Self.file)
        let section = try XCTUnwrap(m.section(today: "2026-10-31"))
        XCTAssertTrue(section.hasPrefix("MEMORY ("))
        XCTAssertTrue(section.contains("You and Boop: You stroke Boop when you sit down in the morning."))
        XCTAssertTrue(section.contains("Recently: Yesterday, a long day on \"api\"; the tests finally passed. 2 days ago, three turns broke"))
        XCTAssertEqual(Steering.Budget.memory, 300)
        XCTAssertLessThanOrEqual(Steering.tokens(section), Steering.Budget.memory)
        let small = try XCTUnwrap(m.section(today: "2026-10-31", budget: 80))
        XCTAssertLessThanOrEqual(Steering.tokens(small), 80)
        XCTAssertFalse(small.contains("blog"), "the oldest note goes first")
        XCTAssertNil(WrittenMemory().section(today: "2026-10-31"), "nothing remembered, no section")
    }

    let words = ["  Your words: \"still broken\", \"we finally fixed it\"."]

    func apply(_ reply: String, day: String = "2026-10-31") -> (WrittenMemory, MemoryEdits.Report) {
        let m = WrittenMemory.parse(Self.file)
        return MemoryEdits.apply(reply, to: m, numbered: m.notes.map(\.id), day: day, words: words)
    }

    /// Each edit is checked on its own: a valid one applies, an invalid one
    /// is refused with its reason; a note with no line is kept.
    func testTheNightsEditsAreCheckedOneByOne() {
        let (m, r) = apply("""
            keep 1
            update 2: "api": you and claude fixed it on Friday. | days: 2026-10-30, 2026-10-31
            drop 3: the move is done
            drop 4: no longer true
            update 4: You stroke Boop every morning. | days: 2026-10-31
            add you: You said "still broken" twice. | days: 2026-10-31
            add boop: You and Boop shipped it together. | days: 2026-11-02
            add work: Check /Users/me/src/api for it. | days: 2026-10-31
            add you: You saw a doctor about it. | days: 2026-10-31
            add you: You said "this is the worst day ever". | days: 2026-10-31
            add you: You said "we never fixed it". | days: 2026-10-31
            day: Saturday: you fixed "api" and stroked Boop.
            end
            add work: after the end
            """)
        XCTAssertEqual(r.updated, [12])
        XCTAssertEqual(r.dropped, [15])
        XCTAssertEqual(r.added, [16])
        XCTAssertEqual(r.refused.map(\.why), ["pinned", "twice", "days", "scrub", "topic", "quotes", "quotes"])
        XCTAssertTrue(r.kept.contains(11), "a note with no line is kept")
        XCTAssertEqual(m.notes.first { $0.id == 12 }?.days, ["2026-10-26", "2026-10-30", "2026-10-31"])
        XCTAssertEqual(m.recently.first?.text, "Saturday: you fixed \"api\" and stroked Boop.")
        XCTAssertTrue(r.day)
    }

    /// Ties to yesterday, found with the real writer on the fixture nights
    /// (boopdev memory write): a change must share a word with yesterday's
    /// lines or CERTAIN; a drop must say what yesterday said; an update
    /// keeps its note's subject; a note isn't a line copied, a number
    /// yesterday didn't have, a second note's words, or a second story of
    /// one project.
    func testEveryChangeIsTiedToYesterday() {
        let source = """
            Yesterday was Saturday 2026-10-31. You were at the Mac 7 hours, stroked Boop 4 times. Agents finished 9 turns, 1 failed, most on "api".
            You asked claude on "api" for a fix, in a sentence, frustrated.
              Your words: "still broken".
            claude finished turn 4 on "api": done, a very long turn, 52 tool calls, after 3 failed checks.
            """
        let m = WrittenMemory.parse(Self.file)
        let (_, r) = MemoryEdits.apply("""
            drop 1: why
            drop 3: the failing checks were fixed in a very long turn
            update 5: You stroked Boop when it was frustrated. | days: 2026-10-31
            add you: You asked claude on "api" for a fix, in a sentence, frustrated. | days: 2026-10-31
            add you: You stroked Boop 5 times. | days: 2026-10-31
            add work: "api": a very long turn, fixed after failed checks. | days: 2026-10-31
            add you: You felt calm and rested all day. | days: 2026-10-31
            day: Saturday: you stroked Boop 5 times.
            end
            """, to: m, numbered: m.notes.map(\.id), day: "2026-10-31", words: words, source: source)
        XCTAssertEqual(r.refused.map(\.why), ["ungrounded", "subject", "copied", "numbers", "duplicate", "ungrounded", "numbers"])
        XCTAssertEqual(r.dropped, [15], "a drop that says what yesterday said")
        XCTAssertFalse(r.day, "the day line's number isn't yesterday's")
    }

    /// With no day line that passes, Recently gets the dream's own
    /// sentence, which is always true.
    func testRecentlyFallsBackOnTheDream() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir, today: "2026-10-31")
        let memory = Memory(store: try KeyValueStore(directory: nil), time: LocalTime(timeZone: TimeZone(identifier: "UTC")!),
                            writer: StubWriter(reply: "day: Friday: you flew to the moon.\nend"), files: files)
        var t = MemoryReader.Tallies()
        t.strokes = 2
        let asked = await memory.ask(day: "2026-10-30", tallies: t)
        let night = try XCTUnwrap(asked)
        memory.apply(night)
        XCTAssertEqual(files.written().recently.first?.text, "Friday: you stroked it 2 times.")
    }

    /// You and Boop is the lasting mark: the model may never drop a note
    /// there, and code never ages one; You and Your work age out 30 days
    /// after the last day they cite, unless pinned.
    func testYouAndBoopLastsAndTheRestAges() {
        let (m, r) = apply("drop 5: old\nend")
        XCTAssertEqual(r.refused.map(\.why), ["lasting"])
        XCTAssertTrue(m.notes.contains { $0.id == 11 }, "never dropped, though older than 30 days")
        XCTAssertEqual(r.aged, [15], "blog's last day, 2026-10-01, is 30 days back")
        XCTAssertEqual(WrittenMemory.ageDays, 30)
    }

    /// The limits: three updates and three adds a night; four notes a section.
    func testTheLimits() {
        let reply = ["Apples are red.", "Bananas ripen slowly.", "Cherries grow in summer.", "Dates come from palms."]
            .map { "add you: \($0) | days: 2026-10-31" }.joined(separator: "\n")
        let (m, r) = apply(reply)
        XCTAssertEqual(r.added.count, 3)
        XCTAssertEqual(r.refused.map(\.why), ["limit"])
        XCTAssertEqual(m.notes(in: .you).count, 4)
        XCTAssertEqual([MemoryEdits.maxUpdates, MemoryEdits.maxAdds, WrittenMemory.perSection], [3, 3, 4])
    }

    /// Recently keeps the newest 7 days.
    func testRecentlyKeepsAWeek() {
        var m = WrittenMemory()
        for d in 1...9 {
            (m, _) = MemoryEdits.apply("day: day \(d).", to: m, numbered: [], day: String(format: "2026-10-%02d", d), words: [])
        }
        XCTAssertEqual(m.recently.map(\.day), (3...9).reversed().map { String(format: "2026-10-%02d", $0) })
    }

    /// The request: the notes numbered in the file's order of sections,
    /// pinned ones marked; CERTAIN from the tallies; YESTERDAY's oldest
    /// lines left out first until it fits.
    func testTheRequest() {
        let m = WrittenMemory.parse(Self.file)
        var t = MemoryReader.Tallies()
        t.hereMinutes = 7 * 60
        t.strokes = 3
        t.talks = 2
        t.turns = 9
        t.failed = 1
        t.threads = ["api": 6, "blog": 3]
        let certain = MemoryRequest.certain(t, day: "2026-10-27", weekday: "Tuesday")
        XCTAssertEqual(certain, "Yesterday was Tuesday 2026-10-27. You were at the Mac 7 hours, stroked Boop 3 times and talked to it twice. Agents finished 9 turns, 1 failed, most on \"api\".")
        let journal = (0..<400).map { (at: String(format: "%02d:00", $0 % 24), line: "You asked claude on \"api\" for a fix, in a sentence, line \($0).") }
        let r = MemoryRequest.make(memory: m, certain: certain, journal: journal)
        XCTAssertEqual(r.numbered, [3, 12, 15, 9, 11])
        XCTAssertTrue(r.text.contains("4 [boop, pinned] You stroke Boop"))
        XCTAssertLessThan(r.lines, 400)
        XCTAssertTrue(r.text.contains("line 399."), "the newest lines stay")
        XCTAssertFalse(r.text.contains("line 0."), "the oldest go")
        XCTAssertTrue(MemoryRequest.instructions.contains("Never drop a boop note"))
    }

    /// The night's write: the writer's reply, checked and applied to
    /// memory.md, which the next pass reads.
    func testTheNightsWriteKeepsMemoryMd() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("boop-memory-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = try MemoryStore(directory: dir, today: "2026-10-31")
        let memory = Memory(store: try KeyValueStore(directory: nil), time: LocalTime(timeZone: TimeZone(identifier: "UTC")!),
                            writer: StubWriter(reply: "add boop: You stroke Boop most mornings. | days: 2026-10-30\nday: Friday: you stroked Boop 3 times.\nend"),
                            files: files)
        var t = MemoryReader.Tallies()
        t.strokes = 3
        let asked = await memory.ask(day: "2026-10-30", tallies: t)
        let night = try XCTUnwrap(asked)
        XCTAssertTrue(night.request.text.contains("stroked Boop 3 times"))
        let report = try XCTUnwrap(memory.apply(night))
        XCTAssertEqual(report.added, [1])
        let written = files.written()
        XCTAssertEqual(written.notes(in: .boop).map(\.text), ["You stroke Boop most mornings."])
        XCTAssertEqual(written.recently.map(\.day), ["2026-10-30"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("history/2026-10-30/memory.md").path))
    }
}

/// A writer that always replies the same. Not nested in a test: the shim's
/// runner generator would take it for the test class.
struct StubWriter: MemoryWriter {
    let reply: String
    func write(_ request: MemoryRequest) async -> MemoryWriterReply { .reply(reply) }
}
