import Foundation
import MellowHarness
import SQLite3
import XCTest
@testable import BoopKit

/// XP by rule from the agents' events, the stages, and
/// how both are kept in `boop.sqlite`.
final class GrowthTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("boop-growth-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func event(_ seq: Int, _ type: Event.Kind, _ phase: Event.Phase? = nil, _ data: [String: JSONValue] = [:],
               from source: Event.Source = .claude) -> Event {
        var e = Event(at: 1_000, source: source, type: type, phase: phase, specificType: "x", session: "s1", data: data)
        e.seq = seq
        return e
    }

    /// A tool call that didn't fail 1, a helper back 2, a turn done 5;
    /// nothing else, and nothing that isn't an agent's.
    func testXPComesFromTheAgentsWorkByRule() {
        XCTAssertEqual(Growth.xp(for: event(1, .tool, .end)), 1)
        XCTAssertEqual(Growth.xp(for: event(1, .tool, .end, from: .codex)), 1)
        XCTAssertEqual(Growth.xp(for: event(1, .tool, .end, ["failed": .bool(true)])), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .subagent, .end)), 2)
        XCTAssertEqual(Growth.xp(for: event(1, .turn, .end, ["outcome": .string("done")])), 5)
        XCTAssertEqual(Growth.xp(for: event(1, .turn, .end, ["outcome": .string("failed")])), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .turn, .end, ["outcome": .string("stopped")])), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .tool, .start)), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .turn, .start)), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .poke, from: .device)), 0)
    }

    /// Care earns too: a care gesture 3, a word to Boop 3, an answered ask
    /// 5, coming back 2; a poke, a thump or an ignored ask nothing.
    func testCareEarnsXP() {
        func you(_ type: Event.Kind, _ specific: String, _ phase: Event.Phase? = nil) -> Event {
            Event(at: 1_000, source: .device, type: type, phase: phase, specificType: specific)
        }
        XCTAssertEqual([Growth.careXP, Growth.talkXP, Growth.answerXP, Growth.backXP], [3, 3, 5, 2])
        XCTAssertEqual(Growth.earning(for: you(.gesture, "stroke"))?.xp, 3)
        XCTAssertEqual(Growth.earning(for: you(.gesture, "stroke"))?.pool, .care)
        XCTAssertEqual(Growth.xp(for: you(.said, "mic")), 3)
        XCTAssertEqual(Growth.xp(for: you(.ask, "a")), 5)
        XCTAssertEqual(Growth.xp(for: you(.ask, Asks.ignored)), 0)
        XCTAssertEqual(Growth.xp(for: Event(at: 1, source: .mac, type: .presence, phase: .end, specificType: "unlocked")), 2)
        XCTAssertEqual(Growth.xp(for: you(.gesture, "startle")), 0)
        XCTAssertEqual(Growth.xp(for: you(.poke, "input")), 0)
        XCTAssertEqual(Growth.earning(for: event(1, .tool, .end))?.pool, .work)
    }

    /// Counts `e` as the runtime does with no caps in the way: what it earns.
    @discardableResult
    func count(_ growth: GrowthStore, _ e: Event, day: String = "2026-10-22") -> Bool {
        growth.count(e, earned: Growth.xp(for: e), day: day)
    }

    /// Pins Growth.workPerDay and carePerDay (60 each): each pool earns at
    /// most 60 XP a Boop day, apart, and a new Boop day starts both again.
    /// The memory reader keeps the day's totals (its tallies' workXP and
    /// careXP) and hands growth what each event earned as it reads it.
    func testEachPoolIsCappedADay() throws {
        XCTAssertEqual([Growth.workPerDay, Growth.carePerDay], [60, 60])
        let store = try KeyValueStore(directory: nil)
        let reader = MemoryReader(store: store, time: LocalTime())
        let runner = Checkpointed(reader, store: store, time: LocalTime(), note: { _ in })
        let growth = GrowthStore(store)
        let first: Int64 = 1_793_000_000_000, next = first + 24 * 3_600_000
        var seq = 0
        var counted = false
        reader.earned = { e, xp in counted = growth.count(e, earned: xp) }
        func feed(_ e: Event) -> Bool {
            var e = e
            seq += 1
            e.seq = seq
            counted = false
            runner.feed(e, line: nil)
            return counted
        }
        func stroke(_ at: Int64) -> Bool { feed(Event(at: at, source: .device, type: .gesture, specificType: "stroke")) }
        func turn(_ at: Int64) -> Bool {
            feed(Event(at: at, source: .claude, type: .turn, phase: .end, specificType: "Stop", session: "s1", data: ["outcome": .string("done")]))
        }
        for _ in 0..<20 { XCTAssertTrue(stroke(first)) }
        XCTAssertFalse(stroke(first), "care's 60 reached")
        XCTAssertEqual(growth.growth.xp, 60)
        for _ in 0..<12 { XCTAssertTrue(turn(first)) }
        XCTAssertFalse(turn(first), "the work's 60 apart")
        XCTAssertEqual(growth.growth.xp, 120)
        XCTAssertEqual(runner.state?.careXP, 60)
        XCTAssertEqual(runner.state?.workXP, 60)
        XCTAssertTrue(stroke(next), "a new Boop day")
        XCTAssertEqual(growth.growth.xp, 123)
        XCTAssertEqual(runner.state?.careXP, 3)
    }

    /// Six stages at 0, 200, 1,000, 4,000, 12,000 and 30,000 XP.
    func testStagesStartAtTheirThresholds() {
        XCTAssertEqual(Growth.stages.map(\.from), [0, 200, 1_000, 4_000, 12_000, 30_000])
        XCTAssertEqual(Growth.stages.map(\.name), ["Hatchling", "Sprout", "Buddy", "Pal", "Chonk", "Legend"])
        XCTAssertEqual(Growth.stage(for: 0), 1)
        XCTAssertEqual(Growth.stage(for: 199), 1)
        XCTAssertEqual(Growth.stage(for: 200), 2)
        XCTAssertEqual(Growth.stage(for: 29_999), 5)
        XCTAssertEqual(Growth.stage(for: 30_000), 6)
        XCTAssertEqual(Growth.stage(for: 1_000_000), 6)

        let g = Growth(xp: 600)
        XCTAssertEqual(g.stage, 2)
        XCTAssertEqual(g.name, "Sprout")
        XCTAssertEqual(g.nextAt, 1_000)
        XCTAssertEqual(g.progress, 0.5)
        XCTAssertNil(Growth(xp: 40_000).nextAt)
        XCTAssertEqual(Growth(xp: 40_000).progress, 1)
    }

    /// A stage reached is kept, whatever the XP says.
    func testAStageNeverGoesBack() {
        XCTAssertEqual(Growth(xp: 10, stage: 3).stage, 3)
        XCTAssertEqual(Growth(xp: 5_000, stage: 1).stage, 4)
    }

    func testTheKeyValueStoreKeepsValuesAcrossOpens() throws {
        do {
            let store = try KeyValueStore(directory: dir)
            XCTAssertNil(store.string("a"))
            try store.set(["a": "1", "b": "two"])
            try store.set(["a": "3"])
        }
        let again = try KeyValueStore(directory: dir)
        XCTAssertEqual(again.int("a"), 3)
        XCTAssertEqual(again.string("b"), "two")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("boop.sqlite").path))
    }

    /// The rule: `boop.sqlite` says its shape in `user_version`. A file from
    /// before it was kept (0) is schema 1's shape and keeps its values; a
    /// file from a newer Boop is refused, and left as it was.
    func testTheStoreKeepsItsSchemaAndLeavesANewerOneAlone() throws {
        do {
            let store = try KeyValueStore(directory: dir)
            try store.set(["growth.xp": "40"])
            let made = try store.userVersion()
            XCTAssertEqual(made, KeyValueStore.schema)
            try store.exec("PRAGMA user_version = 0")  // as every file before this release
        }
        do {
            let older = try KeyValueStore(directory: dir)
            XCTAssertEqual(older.int("growth.xp"), 40)
            let moved = try older.userVersion()
            XCTAssertEqual(moved, KeyValueStore.schema)
            try older.exec("PRAGMA user_version = \(KeyValueStore.schema + 1)")
        }
        try XCTAssertThrowsError(try KeyValueStore(directory: dir))
        // Untouched: the newer Boop finds it as it left it.
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(dir.appendingPathComponent(KeyValueStore.fileName).path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(Int(sqlite3_column_int(statement, 0)), KeyValueStore.schema + 1)
    }

    /// Each event counts once: one at or before the last counted is left
    /// alone, so a launch's read-back can't count it again.
    func testEachEventCountsOnceAndIsKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertTrue(count(growth, event(1, .tool, .end)))
        XCTAssertFalse(count(growth, event(2, .tool, .start)))
        XCTAssertTrue(count(growth, event(3, .turn, .end, ["outcome": .string("done")])))
        XCTAssertFalse(count(growth, event(3, .turn, .end, ["outcome": .string("done")])))
        XCTAssertFalse(count(growth, event(1, .tool, .end)))
        XCTAssertEqual(growth.growth.xp, 6)

        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth, Growth(xp: 6, stage: 1))
        XCTAssertEqual(again.lastSeq, 3)
    }

    func testCrossingAThresholdReachesTheNextStage() throws {
        let lines = Lines()
        let growth = GrowthStore(try KeyValueStore(directory: nil), log: { lines.add($0) })
        for seq in 1...39 { count(growth, event(seq, .turn, .end, ["outcome": .string("done")])) }
        XCTAssertEqual(growth.growth.stage, 1)
        count(growth, event(40, .turn, .end, ["outcome": .string("done")]))
        XCTAssertEqual(growth.growth, Growth(xp: 200, stage: 2))
        XCTAssertEqual(lines.all, ["growth: reached stage 2, Sprout, at 200 XP"])
    }

    /// The day a stage was reached is kept, so a relaunch that day still
    /// has its party.
    func testTheDayAStageWasReachedIsKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertNil(growth.reachedDay)
        for seq in 1...40 { count(growth, event(seq, .turn, .end, ["outcome": .string("done")]), day: "2026-10-22") }
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.reachedDay, "2026-10-22")
    }

    /// A transcript whose files are all gone numbers from 1 again: counting
    /// follows it rather than skipping what's new.
    func testCountingFollowsATranscriptThatStartsAgain() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        count(growth, event(500, .tool, .end))
        growth.follow(transcriptAt: 600)
        XCTAssertEqual(growth.lastSeq, 500)
        growth.follow(transcriptAt: 0)
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.lastSeq, 0)
        XCTAssertTrue(count(growth, event(1, .tool, .end)))
        XCTAssertEqual(growth.growth.xp, 2)
    }
}
