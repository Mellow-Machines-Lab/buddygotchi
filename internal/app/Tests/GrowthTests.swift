import AgentHooks
import Foundation
import MellowHarness
import SQLite3
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// XP kept simple (plan/v1-buddy.md §5): a fixed XP per thing, a ring of
/// 100 a day, a level per 100, sizes at levels 5, 15 and 30, and how it's
/// kept in `boop.sqlite`.
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
        XCTAssertEqual(Growth.xp(for: event(1, .tool, .start)), 0)
        XCTAssertEqual(Growth.xp(for: event(1, .poke, from: .device)), 0)
    }

    /// Pins v1-buddy.md §5.2: a care touch 3, a word 3, an answered ask 5,
    /// a met wish 20, coming back 2; a startle or a poke nothing.
    func testCareEarnsXP() {
        func you(_ type: Event.Kind, _ specific: String, _ phase: Event.Phase? = nil) -> Event {
            Event(at: 1_000, source: .device, type: type, phase: phase, specificType: specific)
        }
        XCTAssertEqual([Growth.turnXP, Growth.toolXP, Growth.helperXP], [5, 1, 2])
        XCTAssertEqual([Growth.careXP, Growth.talkXP, Growth.answerXP, Growth.wishXP, Growth.backXP], [3, 3, 5, 20, 2])
        XCTAssertEqual(Growth.xp(for: you(.gesture, "stroke")), 3)
        XCTAssertEqual(Growth.xp(for: you(.said, "mic")), 3)
        XCTAssertEqual(Growth.xp(for: you(.ask, "a")), 5)
        XCTAssertEqual(Growth.xp(for: you(.ask, Asks.ignored)), 0)
        XCTAssertEqual(Growth.xp(for: Event(at: 1, source: .mac, type: .presence, phase: .end, specificType: "unlocked")), 2)
        XCTAssertEqual(Growth.xp(for: Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.met.rawValue)), 20)
        XCTAssertEqual(Growth.xp(for: Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.closed.rawValue)), 0)
        XCTAssertEqual(Growth.xp(for: you(.gesture, "startle")), 0)
        XCTAssertEqual(Growth.xp(for: you(.poke, "input")), 0)
    }

    /// Pins v1-buddy.md §5.3 and §5.4: level = 1 + XP / 100, no maximum;
    /// the sizes at levels 1, 5, 15 and 30; the ring 100 a day.
    func testLevelsAndSizes() {
        XCTAssertEqual(Growth.perDay, 100)
        XCTAssertEqual(Growth.perLevel, 100)
        XCTAssertEqual(Growth(xp: 0).level, 1)
        XCTAssertEqual(Growth(xp: 99).level, 1)
        XCTAssertEqual(Growth(xp: 100).level, 2)
        XCTAssertEqual(Growth(xp: 1_182).level, 12)
        XCTAssertEqual(Growth(xp: 1_182).toNextLevel, 18)
        XCTAssertEqual(Growth(xp: 1_000_000).level, 10_001, "no maximum")
        XCTAssertEqual(Growth.stages.map(\.level), [1, 5, 15, 30])
        XCTAssertEqual(Growth.stages.map(\.name), ["Hatchling", "Sprout", "Buddy", "Chonk"])
        XCTAssertEqual(Growth(xp: 399).stageName, "Hatchling")
        XCTAssertEqual(Growth(xp: 400).stageName, "Sprout")
        XCTAssertEqual(Growth(xp: 1_400).stageName, "Buddy")
        XCTAssertEqual(Growth(xp: 2_900).stageName, "Chonk")
        XCTAssertEqual([1, 2, 5, 6, 15, 30, 31].filter(Growth.grows(at:)), [5, 15, 30])
        XCTAssertEqual(Growth(today: 82).percent, 82)
        XCTAssertEqual(Growth(today: 140).today, 100, "a ring holds 100")
        XCTAssertTrue(Growth(today: 100).ringClosed)
    }

    @discardableResult
    func count(_ growth: GrowthStore, _ e: Event, day: String = "2026-10-22") -> Int {
        growth.count(e, xp: Growth.xp(for: e), today: day)
    }

    /// The day's cap is the ring: past 100, nothing counts, from any source,
    /// until Boop's next day.
    func testTheDayIsCappedAtTheRing() throws {
        let growth = GrowthStore(try KeyValueStore(directory: nil))
        for seq in 1...19 { count(growth, event(seq, .turn, .end, ["outcome": .string("done")])) }
        XCTAssertEqual(growth.growth.today, 95)
        XCTAssertEqual(count(growth, Event(seq: 20, at: 1, source: .device, type: .gesture, specificType: "stroke")), 3)
        XCTAssertEqual(count(growth, event(21, .turn, .end, ["outcome": .string("done")])), 2, "only up to 100")
        XCTAssertEqual(count(growth, event(22, .turn, .end, ["outcome": .string("done")])), 0)
        XCTAssertEqual(growth.growth, Growth(xp: 100, today: 100))
        XCTAssertEqual(count(growth, event(23, .turn, .end, ["outcome": .string("done")]), day: "2026-10-23"), 5, "a new day")
        XCTAssertEqual(growth.growth, Growth(xp: 105, today: 5))
        XCTAssertEqual(growth.growth(on: "2026-10-24"), Growth(xp: 105), "the next day's ring is empty")
    }

    /// The last 7 days' rings, oldest first, kept across opens; a day with
    /// none is 0.
    func testTheWeeksRingsAreKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        count(growth, event(1, .turn, .end, ["outcome": .string("done")]), day: "2026-10-20")
        count(growth, event(2, .tool, .end), day: "2026-10-22")
        count(growth, event(3, .tool, .end), day: "2026-10-22")
        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.xp), [0, 0, 0, 5, 0, 2, 0])
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.day).last, "2026-10-23")
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.day).first, "2026-10-17")
        XCTAssertEqual(again.week(to: "2024-03-01").map(\.day).suffix(2), ["2024-02-29", "2024-03-01"], "a leap day")
    }

    /// What growing sends through the runtime: a `state` with today's ring
    /// as a turn's XP moves it; at a level, a `level` event and its moment,
    /// `Level 2!` on the low sign; at 100 today, the ring's. A demo sends no ring.
    func testALevelUpAndTheRingThroughTheRuntime() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-grow-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Runtime.setUp(stateDir: dir, name: "Pip")
        let clock = VirtualClock(1_793_000_000_000)
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        do {
            let store = try KeyValueStore(directory: dir)
            try store.set(["growth.xp": "90", "growth.today": "\(options.time.boopDay(clock.now)) 90"])
        }
        let runtime = try Runtime(options)
        let core = runtime.core(runtime.rigs[0])
        var now: Int64 { clock.now }
        XCTAssertEqual(core.snapshot(at: now).xp, 90)
        func turn() {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
                clock.now += 60_000
                runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
                clock.now += 60_000
            }
        }
        func events(_ type: Event.Kind) -> [Event] { runtime.harness.log.view(now: now).events.filter { $0.type == type } }
        turn()
        XCTAssertEqual(runtime.growth.growth.xp, 95)
        XCTAssertEqual(core.snapshot(at: now).xp, 95)
        XCTAssertTrue(events(.level).isEmpty)
        turn()
        XCTAssertEqual(runtime.growth.growth, Growth(xp: 100, today: 100))
        XCTAssertEqual(events(.level).map(\.specificType), ["2"])
        XCTAssertEqual(events(.ring).count, 1)
        XCTAssertTrue(runtime.harness.log.view(now: now).events.contains { $0.action == "react" && $0["by"]?.string == "rule" })
        turn()
        XCTAssertEqual(events(.ring).count, 1, "once a day")

        runtime.playingDemo = true
        XCTAssertNil(core.snapshot(at: now).xp, "a demo sends none")
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
        XCTAssertEqual(count(growth, event(1, .tool, .end)), 1)
        XCTAssertEqual(count(growth, event(2, .tool, .start)), 0)
        XCTAssertEqual(count(growth, event(3, .turn, .end, ["outcome": .string("done")])), 5)
        XCTAssertEqual(count(growth, event(3, .turn, .end, ["outcome": .string("done")])), 0)
        XCTAssertEqual(count(growth, event(1, .tool, .end)), 0)
        XCTAssertEqual(growth.growth.xp, 6)

        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth, Growth(xp: 6, today: 6))
        XCTAssertEqual(again.lastSeq, 3)
    }

    /// The level last celebrated is kept, so a relaunch doesn't celebrate
    /// it again; a fresh store has nothing to celebrate.
    func testTheLevelCelebratedIsKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(growth.celebrated, 1)
        for seq in 1...20 { count(growth, event(seq, .turn, .end, ["outcome": .string("done")])) }
        XCTAssertEqual(growth.growth.level, 2)
        XCTAssertEqual(growth.celebrated, 1)
        growth.celebrate()
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.celebrated, 2)
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
        XCTAssertEqual(count(growth, event(1, .tool, .end)), 1)
        XCTAssertEqual(growth.growth.xp, 2)
    }
}
