import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The daily counts, on the Mac only (`DayCounts`, `CountsReader`): what they
/// count, and that the summary a person may send has no strings of theirs.
final class DailyCountsTests: XCTestCase {
    let time = LocalTime(timeZone: TimeZone(identifier: "UTC")!)
    let minute: Int64 = 60_000
    /// 2026-11-04 15:00 UTC.
    let t0: Int64 = 1_793_804_400_000

    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("counts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A day's events, each with its seq, and with words, a thread and a
    /// prompt that must never reach the file.
    func day(from t: Int64) -> [Event] {
        var seq = 0
        func at(_ m: Int64, _ e: (Int64) -> Event) -> Event {
            seq += 1
            var x = e(t + m * minute)
            x.seq = seq
            return x
        }
        return [
            at(0) { Event(at: $0, source: .claude, type: .prompt, specificType: "reading", session: "s1", cwd: "/secret/thread-name",
                          data: ["phrases": .array([.string("prompt words")]), "kind": "fix", "length": "words"]) },
            at(1) { Event(at: $0, source: .device, type: .gesture, specificType: "nose") },
            at(2) { Event(at: $0, source: .boop, type: .wish, phase: .start, specificType: "pet") },
            at(3) { Event(at: $0, source: .device, type: .gesture, specificType: "stroke") },
            at(3) { Event(at: $0, source: .boop, type: .wish, phase: .end, specificType: "met", data: ["kind": "pet", "waited_ms": .int(60_000)]) },
            at(4) { Event(at: $0, source: .mic, type: .said, specificType: "words", data: ["words": "my private words"]) },
            at(5) { Event(at: $0, source: .boop, type: .needsYou, phase: .start, specificType: Core.needsYou, session: "s1", data: ["agent": "claude"]) },
            at(7) { Event(at: $0, source: .boop, type: .needsYou, phase: .end, specificType: Core.needsYou, session: "s1", data: ["agent": "claude", "outcome": "done"]) },
            at(8) { Event(at: $0, source: .boop, type: .hush, phase: .start, specificType: "app", data: ["until": .int($0 + 60_000)]) },
            at(9) { Event(at: $0, source: .device, type: .gesture, specificType: "facedown") },
            at(10) { Event(at: $0, source: .claude, type: .turn, phase: .end, specificType: "StopFailure", session: "s1", cwd: "/secret/thread-name", data: ["outcome": "failed", "error": "api_error"]) },
            at(11) { Event(at: $0, source: .device, type: .link, phase: .end, specificType: "ble") },
            at(21) { Event(at: $0, source: .device, type: .link, phase: .start, specificType: "ble") },
            at(22) { Event.did("Opened \"thread-name\"", for: 1, action: Core.openThread, by: "button", at: $0) },
            at(23) { Event.did("Boop said \"my private words\"", for: 1, action: MomentOutput.outputName, by: "brain", facts: ["takes": .array([.string("x")]), "sign": "secret sign"], at: $0) },
            at(60) { Event(at: $0, source: .mac, type: .presence, phase: .start, specificType: "idle", data: ["since": .int($0)]) },
        ]
    }

    func testAWholeDay() {
        let reader = CountsReader { _ in }
        var s = reader.open(day: "2026-11-04", carry: nil)
        for e in day(from: t0) { _ = reader.read(e, line: nil, into: &s) }
        let r = s.counted
        XCTAssertEqual(r.touches, 2, "a nose boop and a stroke")
        XCTAssertEqual(r.touchesNoWish, 1, "the boop, before the wish")
        XCTAssertEqual([r.wishesMade, r.wishesMet, r.wishesGaveUp], [1, 1, 0])
        XCTAssertEqual(r.wishWaitMs, 60_000)
        XCTAssertEqual([r.needsYou, r.answered], [1, 1])
        XCTAssertEqual(r.answerMs, 2 * minute)
        XCTAssertEqual(r.hushes, 1)
        XCTAssertEqual(r.faceDown, 1)
        XCTAssertEqual(r.failures, 1)
        XCTAssertEqual(r.disconnects, 1)
        XCTAssertEqual(r.threadsOpened, 1)
        XCTAssertEqual(r.spoken, 1)
        XCTAssertEqual(r.hereMinutes, 60, "from your prompt till you went")
    }

    /// Pins the privacy rule: the file and the summary hold nothing of the
    /// transcript's strings, however the events carry them.
    func testNoStringsFromTheTranscript() throws {
        let dir = try temp()
        let store = try KeyValueStore(directory: nil)
        let memory = Memory(store: store, time: time, files: try MemoryStore(directory: dir, today: "2026-11-04"))
        for e in day(from: t0) { memory.counts.feed(e, line: Line("You asked claude on \"thread-name\": my private words")) }
        try memory.files?.keep(try XCTUnwrap(memory.counts.state).counted)
        let file = try String(contentsOf: dir.appendingPathComponent(MemoryStore.countsFile), encoding: .utf8)
        let summary = DayCounts.summary(MemoryStore.counts(in: dir))
        XCTAssertTrue(summary.contains("touches: 2, 1 with no wish open"), summary)
        for text in [file, summary, store.string("reader.counts") ?? ""] {
            for secret in ["thread-name", "secret", "private", "words\"", "prompt words", "s1", "api_error", "claude"] {
                XCTAssertFalse(text.contains(secret), "\(secret) in: \(text)")
            }
        }
        // Everything in a row but its date is a number or a yes or no.
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(file.split(separator: "\n")[0].utf8)) as? [String: Any])
        XCTAssertEqual(row.filter { $0.value is String }.keys.sorted(), ["day"])
    }

    /// A closed day's row stays; today's replaces itself; another state
    /// directory is another file; and nothing asked for changes anything.
    func testARowADayInItsOwnStateDirectory() throws {
        let a = try temp(), b = try temp()
        let files = try MemoryStore(directory: a, today: "2026-11-04")
        var row = DayCounts(day: "2026-11-04")
        row.touches = 1
        try files.keep(row)
        row.touches = 2
        try files.keep(row)
        try files.keep(DayCounts(day: "2026-11-03"))
        XCTAssertEqual(MemoryStore.counts(in: a).map(\.day), ["2026-11-03", "2026-11-04"])
        XCTAssertEqual(MemoryStore.counts(in: a).last?.touches, 2)
        XCTAssertEqual(MemoryStore.counts(in: b), [], "another state directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.appendingPathComponent(MemoryStore.countsFile).path))

        let memory = Memory(store: try KeyValueStore(directory: nil), time: time, files: files)
        memory.countsSample = { (true, 4, 2) }
        for e in day(from: t0 + 24 * 60 * minute) { memory.counts.feed(e, line: nil) }
        memory.tick(wall: t0 + 25 * 60 * minute)
        let kept = try XCTUnwrap(MemoryStore.counts(in: a).last)
        XCTAssertEqual(kept.day, "2026-11-05")
        XCTAssertEqual(kept.quiet, true)
        XCTAssertEqual(kept.volume, 4)
        XCTAssertEqual(kept.stage, 2)
        memory.tick(wall: t0 + 49 * 60 * minute)
        XCTAssertTrue(MemoryStore.counts(in: a).map(\.day).contains("2026-11-05"), "its day closed, its row stays")
    }

    /// Quiet stays on in the row once it has been on, and turning it off
    /// doesn't save the checkpoint again and again.
    func testQuietOnThenOffSavesOnce() throws {
        let store = try KeyValueStore(directory: nil)
        let memory = Memory(store: store, time: time, files: try MemoryStore(directory: try temp(), today: "2026-11-04"))
        var quiet = true
        memory.countsSample = { (quiet, 4, 2) }
        for e in day(from: t0) { memory.counts.feed(e, line: nil) }
        memory.keepCounts(wall: t0, now: true)
        quiet = false
        let key = "reader.\(memory.counts.reader.name)"
        try store.set([key: "not saved again"])
        memory.keepCounts(wall: t0 + minute, now: true)
        XCTAssertEqual(store.string(key), "not saved again")
        XCTAssertEqual(memory.counts.state?.row.quiet, true)
    }

    /// Quiet lasts its own day: after a day on Quiet, the next row says what
    /// the setting says. Volume and stage carry, having no day of their own.
    func testQuietClearsWithTheDay() throws {
        let dir = try temp()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: time, files: try MemoryStore(directory: dir, today: "2026-11-04"))
        var quiet = true
        memory.countsSample = { (quiet, 4, 2) }
        for e in day(from: t0) { memory.counts.feed(e, line: nil) }
        memory.keepCounts(wall: t0 + 61 * minute, now: true)
        XCTAssertEqual(MemoryStore.counts(in: dir).last?.quiet, true)
        quiet = false
        let tomorrow = t0 + 24 * 60 * minute
        memory.counts.tick(wall: tomorrow)
        XCTAssertEqual(memory.counts.state?.row.volume, 4)
        memory.keepCounts(wall: tomorrow, now: true)
        let rows = MemoryStore.counts(in: dir)
        XCTAssertEqual(rows.map(\.day), ["2026-11-04", "2026-11-05"])
        XCTAssertEqual(rows.map(\.quiet), [true, false])
    }

    /// The file is written only when the row changed.
    func testAnUnchangedRowIsNotWrittenAgain() throws {
        let dir = try temp()
        let memory = Memory(store: try KeyValueStore(directory: nil), time: time, files: try MemoryStore(directory: dir, today: "2026-11-04"))
        memory.countsSample = { (false, 4, 2) }
        for e in day(from: t0) { memory.counts.feed(e, line: nil) }
        let file = dir.appendingPathComponent(MemoryStore.countsFile)
        memory.keepCounts(wall: t0, now: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try FileManager.default.removeItem(at: file)
        memory.keepCounts(wall: t0 + 2 * minute)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "nothing changed")
        memory.countsSample = { (false, 5, 2) }
        memory.keepCounts(wall: t0 + 4 * minute)
        XCTAssertEqual(MemoryStore.counts(in: dir).last?.volume, 5, "the volume changed")
    }

    /// Your time at the Mac runs across 5:00: the closed day has it up to
    /// its last event, the new day from there, with none counted twice.
    func testHereRunsAcross5() {
        let reader = CountsReader { _ in }
        var s = reader.open(day: "2026-11-04", carry: nil)
        let word = Event(at: t0, source: .mic, type: .said, specificType: "words")
        _ = reader.read(word, line: nil, into: &s)
        let touch = Event(at: t0 + 10 * minute, source: .device, type: .gesture, specificType: "nose")
        _ = reader.read(touch, line: nil, into: &s)
        XCTAssertEqual(s.counted.hereMinutes, 10)
        var next = reader.open(day: "2026-11-05", carry: s)
        XCTAssertEqual(next.counted.hereMinutes, 0)
        let later = Event(at: t0 + 30 * minute, source: .mac, type: .link, specificType: "ble")
        _ = reader.read(later, line: nil, into: &next)
        XCTAssertEqual(next.counted.hereMinutes, 20)
    }

    func said(_ at: Int64, seq: Int) -> Event {
        var e = Event(at: at, source: .mic, type: .said, specificType: "words")
        e.seq = seq
        return e
    }

    /// Quit or restarted at 11:00 and launched at 15:00, with no away logged:
    /// no stretch runs across it, and the four hours count in no reader. What
    /// came before the quit stays counted, and your next event starts afresh.
    func testALaunchBreaksYourTimeAtTheMac() throws {
        let store = try KeyValueStore(directory: nil)
        func memory() throws -> Memory { Memory(store: store, time: time, files: try MemoryStore(directory: try temp(), today: "2026-11-04")) }
        func feed(_ m: Memory, _ e: Event) {
            m.runner.feed(e, line: nil)
            m.dreams.feed(e, line: nil)
            m.counts.feed(e, line: nil)
        }
        let before = try memory()
        let events = [said(t0, seq: 1), said(t0 + 10 * minute, seq: 2)]
        events.forEach { feed(before, $0) }
        XCTAssertEqual(before.today?.hereSince, t0)

        let back = t0 + 4 * 60 * minute
        let after = try memory()
        after.catchUp(events)
        after.launched()
        XCTAssertNil(after.today?.hereSince)
        XCTAssertNil(after.dreams.state?.tallies.hereSince)
        var m = Notices.Moment(at: back, wall: back, time: time)
        m.hereSince = after.today?.hereSince
        XCTAssertNil(Notices.due(m), "no stretch across the restart")

        feed(after, said(back, seq: 3))
        XCTAssertEqual(after.today?.hereSince, back)
        XCTAssertEqual(after.counts.state?.counted.hereMinutes, 10, "the ten before the quit, none of the four hours")
        XCTAssertEqual(after.today?.hereMinutes, 10)
        XCTAssertEqual(after.dreams.state?.tallies.hereMinutes, 10)
    }

    /// Pins the long gap: no event at all for as long as a stretch is a
    /// break, whatever explains it, and shorter isn't. Reading on past it
    /// saves nothing new.
    func testALongGapBreaksYourTimeAtTheMac() throws {
        let counts = CountsReader { _ in }, memory = MemoryReader(store: try KeyValueStore(directory: nil), time: time)
        var s = counts.open(day: "2026-11-04", carry: nil), t = memory.open(day: "2026-11-04", carry: nil)
        func read(_ e: Event) -> [Bool] { [counts.read(e, line: nil, into: &s), memory.read(e, line: nil, into: &t)] }
        let checkIn = { (at: Int64) in Event(at: at, source: .boop, type: .checkIn, specificType: "idle") }
        _ = read(said(t0, seq: 1))
        let almost = t0 + Notices.stretchMs - minute
        XCTAssertEqual(read(checkIn(almost)), [false, false], "an event that changes nothing saves nothing")
        XCTAssertEqual(s.hereSince, t0)
        XCTAssertEqual(t.hereSince, t0)
        let after = almost + Notices.stretchMs
        _ = read(checkIn(after))
        XCTAssertNil(s.hereSince)
        XCTAssertNil(t.hereSince)
        XCTAssertEqual(s.counted.hereMinutes, Int((almost - t0) / minute))
        XCTAssertEqual(t.hereMinutes, Int((almost - t0) / minute))
    }

    /// `daily-counts.jsonl`'s fields, which `Boop --counts` reads back, and a
    /// field a row doesn't have takes its default.
    func testTheFields() throws {
        var r = DayCounts(day: "2026-11-04")
        r.quiet = false
        r.volume = 6
        r.stage = 1
        let data = try JSONEncoder().encode(r)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["answerMs", "answered", "day", "disconnects", "faceDown", "failures", "hereMinutes", "hushes", "needsYou", "quiet", "spoken",
                              "stage", "threadsOpened", "touches", "touchesNoWish", "unpluggedMinutes", "volume", "wishWaitMs", "wishesGaveUp", "wishesMade", "wishesMet"])
        let bare = try JSONDecoder().decode(DayCounts.self, from: Data(#"{"day":"2026-11-04","touches":3}"#.utf8))
        XCTAssertEqual(bare.touches, 3)
    }

    func testTheSummaryOfNothing() {
        XCTAssertTrue(DayCounts.summary([]).contains("days touched: 0 of 0"))
    }
}
