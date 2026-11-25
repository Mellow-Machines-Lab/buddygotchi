import AgentHooks
import Foundation
import MellowHarness
import SQLite3
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// XP (plan/xp-league.md §3): four things earn, the ring of 100, a day of
/// 300 at most, a level per 500, days in a row, and how it's kept in
/// `boop.sqlite`.
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

    /// A finish that plays as a success.
    static let won: [String: JSONValue] = ["outcome": "done", "message": ["kind": "done"]]

    func turnEnd(_ seq: Int) -> Event { event(seq, .turn, .end, ["outcome": .string("done")]) }

    /// Pins plan/xp-league.md §3.1: four things earn, each a thing the board
    /// shows. A turn whose finish is a success 5 (a chat turn, a failure or
    /// a stop nothing), read on the turn's end or its last message's
    /// reading; a ship 10; a check passing after it failed 5; your time with
    /// Boop 3. A call, a helper, coming back and an answered ask earn nothing.
    func testXPComesFromFourThings() {
        func src(_ e: Event, _ facts: [String: JSONValue]? = nil) -> Growth.Source? { Growth.source(of: e, facts: facts) }
        XCTAssertEqual([Growth.turnXP, Growth.shipXP, Growth.fixXP, Growth.careXP], [5, 10, 5, 3])
        XCTAssertEqual(src(turnEnd(1), Self.won), .turns)
        XCTAssertEqual(src(Event(at: 1, source: .claude, type: .lastMessage, specificType: "x"), Self.won), .turns)
        XCTAssertNil(src(turnEnd(1)), "no line, no finish: its reading follows")
        XCTAssertNil(src(turnEnd(1), ["outcome": "done", "message": ["kind": "question"]]), "a chat turn")
        XCTAssertNil(src(turnEnd(1), ["outcome": "done", "length_ms": 1_000, "tools": 0]), "quick, no calls: a chat turn")
        XCTAssertEqual(src(turnEnd(1), ["outcome": "done", "length_ms": 120_000, "tools": 4]), .turns)
        XCTAssertNil(src(turnEnd(1), ["outcome": "failed"]))
        XCTAssertNil(src(turnEnd(1), ["outcome": "stopped"]))
        XCTAssertNil(src(event(1, .prompt), Self.won), "only a finish's line")

        let fixed: [String: JSONValue] = ["topic": "tests", "result": "ok", "failed_before": 2]
        XCTAssertEqual(src(event(1, .tool, .end), fixed), .fixes)
        XCTAssertNil(src(event(1, .tool, .end), ["topic": "tests", "result": "ok", "failed_before": 0]), "passing at once")
        XCTAssertNil(src(event(1, .tool, .end), ["topic": "tests", "result": "failed", "failed_before": 2]))
        XCTAssertNil(src(event(1, .tool, .end)), "a call")

        var push = Event(at: 1, source: .claude, type: .act, phase: .end, specificType: "push", data: ["passed": true])
        XCTAssertEqual(src(push), .ships)
        push.data["passed"] = false
        XCTAssertNil(src(push))

        func you(_ type: Event.Kind, _ specific: String, _ phase: Event.Phase? = nil) -> Event {
            Event(at: 1_000, source: .device, type: type, phase: phase, specificType: specific)
        }
        XCTAssertEqual(src(you(.gesture, "stroke")), .care)
        XCTAssertEqual(src(you(.said, "mic")), .care)
        XCTAssertEqual(src(Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.met.rawValue)), .care)
        XCTAssertNil(src(Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.closed.rawValue)))
        XCTAssertNil(src(you(.gesture, "shake")), "rough handling earns nothing")
        XCTAssertNil(src(you(.gesture, "swipe")))
        XCTAssertNil(src(you(.ask, "a")))
        XCTAssertNil(src(Event(at: 1, source: .mac, type: .presence, phase: .end, specificType: "unlocked")))
        XCTAssertNil(src(event(1, .subagent, .end)))
    }

    /// Pins plan/xp-league.md §3.2: the ring 100, a day 300 at most, care 30
    /// of it at most, a level per 500, no maximum.
    func testLevelsAndLimits() {
        XCTAssertEqual([Growth.perDay, Growth.dayMost, Growth.careMost, Growth.perLevel], [100, 300, 30, 500])
        XCTAssertEqual(Growth(xp: 0).level, 1)
        XCTAssertEqual(Growth(xp: 499).level, 1)
        XCTAssertEqual(Growth(xp: 500).level, 2)
        XCTAssertEqual(Growth(xp: 3_182).level, 7)
        XCTAssertEqual(Growth(xp: 3_182).toNextLevel, 318)
        XCTAssertEqual(Growth(xp: 5_000_000).level, 10_001, "no maximum")
        XCTAssertEqual(Growth(today: 82).percent, 82)
        XCTAssertEqual(Growth(today: 140).percent, 100, "the ring is full at 100")
        XCTAssertEqual(Growth(today: 140).today, 140, "XP counts past it")
        XCTAssertEqual(Growth(today: 400).today, 300)
        XCTAssertTrue(Growth(today: 100).ringClosed)
        XCTAssertEqual(Growth(today: 64, care: 9).work, 55)
    }

    @discardableResult
    func count(_ growth: GrowthStore, _ e: Event, _ facts: [String: JSONValue]? = GrowthTests.won, day: String = "2026-10-22") -> Int {
        growth.count(e, Growth.source(of: e, facts: facts), today: day)
    }

    func stroke(_ seq: Int) -> Event { Event(seq: seq, at: 1, source: .device, type: .gesture, specificType: "stroke") }

    /// The day's limits: care stops at 30, everything at 300, until Boop's
    /// next day. What earned is kept by source.
    func testTheDayHasLimits() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        for seq in 1...12 { count(growth, stroke(seq)) }
        XCTAssertEqual(growth.growth.care, 30, "care stops at 30")
        XCTAssertEqual(count(growth, stroke(13)), 0)
        for seq in 14...68 { count(growth, turnEnd(seq)) }
        XCTAssertEqual(growth.growth.today, 300)
        XCTAssertEqual(count(growth, turnEnd(69)), 0, "nothing past 300")
        XCTAssertEqual(growth.todayBy[.turns], .init(n: 54, xp: 270))
        XCTAssertEqual(growth.todayBy[.care], .init(n: 10, xp: 30))
        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth, Growth(xp: 300, today: 300, care: 30), "kept across opens")
        XCTAssertEqual(again.todayBy, growth.todayBy)
        XCTAssertEqual(count(growth, turnEnd(70), day: "2026-10-23"), 5, "a new day")
        XCTAssertEqual(growth.growth, Growth(xp: 305, today: 5))
        XCTAssertEqual(growth.todayBy, [.turns: .init(n: 1, xp: 5)])
        XCTAssertEqual(growth.todayBy(on: "2026-10-24"), [:])
        XCTAssertEqual(growth.growth(on: "2026-10-24"), Growth(xp: 305), "the next day's ring is empty")
        XCTAssertEqual(count(growth, turnEnd(71), day: "2026-10-22"), 5, "a clock set back counts on the day it's on")
        XCTAssertEqual(growth.week(to: "2026-10-23").map(\.xp).suffix(2), [300, 10], "no day twice")
    }

    /// Pins plan/xp-league.md §3.2's days in a row: a full ring adds one;
    /// up to two days with none between keep it (a weekend), three start
    /// it again; shown as 0 once three have passed.
    func testDaysInARow() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        var seq = 0
        func fill(_ day: String) {
            for _ in 0..<20 { seq += 1; count(growth, turnEnd(seq), day: day) }
        }
        XCTAssertEqual(growth.daysInARow(on: "2026-11-02"), 0)
        fill("2026-11-02")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-02"), 1)
        fill("2026-11-03")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-03"), 2)
        seq += 1; count(growth, turnEnd(seq), day: "2026-11-03")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-03"), 2, "once a day")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-06"), 2, "two days with no full ring")
        fill("2026-11-06")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-06"), 3, "a weekend never breaks it")
        try XCTAssertEqual(GrowthStore( KeyValueStore(directory: dir)).daysInARow(on: "2026-11-06"), 3, "kept across opens")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-10"), 0, "three days with none")
        fill("2026-11-10")
        XCTAssertEqual(growth.daysInARow(on: "2026-11-10"), 1, "and it starts again")
    }

    /// Pins plan/xp-league.md §10: the daily counts keep the XP by source
    /// after the limits, what the limits refused, and the hour the ring
    /// closed.
    func testTheDailyCountsKeepTheXP() {
        var s = CountsReader.State(row: DayCounts(day: "2026-10-22"))
        for seq in 1...11 { CountsReader.count(stroke(seq), time: LocalTime(), into: &s) }
        CountsReader.count(turnEnd(12), facts: Self.won, time: LocalTime(), into: &s)
        XCTAssertEqual([s.row.xpCare, s.row.xpTurns, s.row.xpRefused], [30, 5, 3])
        let at = Int64(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 15, minute: 30))!.timeIntervalSince1970 * 1000)
        CountsReader.count(Core.growthEvent(level: nil, ring: true, at: at), time: LocalTime(), into: &s)
        XCTAssertEqual(s.row.ringHour, 15)
        // The pipeline's hour, not the Mac's: 23:30 at UTC+14 is 9:30 UTC.
        let far = LocalTime(timeZone: TimeZone(identifier: "Pacific/Kiritimati")!)
        var t = CountsReader.State(row: DayCounts(day: "2026-10-22"))
        CountsReader.count(Core.growthEvent(level: nil, ring: true, at: 1_792_661_400_000), time: far, into: &t)
        XCTAssertEqual(t.row.ringHour, 23)
    }

    /// The last 7 days' rings, oldest first, kept across opens; a day with
    /// none is 0.
    func testTheWeeksRingsAreKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        count(growth, turnEnd(1), day: "2026-10-20")
        count(growth, stroke(2), day: "2026-10-22")
        count(growth, stroke(3), day: "2026-10-22")
        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.xp), [0, 0, 0, 5, 0, 6, 0])
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.day).last, "2026-10-23")
        XCTAssertEqual(again.week(to: "2026-10-23").map(\.day).first, "2026-10-17")
        XCTAssertEqual(again.week(to: "2024-03-01").map(\.day).suffix(2), ["2024-02-29", "2024-03-01"], "a leap day")
    }

    /// What growing does through the runtime: today's XP, which the core
    /// reads, moves with a turn's; at a level, a `level` event and its
    /// moment, `level 2!` held low in gold; at 100 today, the ring's, the
    /// same moment, the ring's words held low in gold. A demo has no growth.
    func testALevelUpAndTheRingThroughTheRuntime() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-grow-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Runtime.setUp(stateDir: dir, name: "Pip")
        let clock = VirtualClock(1_793_000_000_000)
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.alone = true
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        do {
            let store = try KeyValueStore(directory: dir)
            try store.set([GrowthStore.xpKey: "490", GrowthStore.todayKey: "\(options.time.boopDay(clock.now)) 90"])
        }
        let runtime = try Runtime(options)
        let core = runtime.core
        var now: Int64 { clock.now }
        XCTAssertEqual(core.growth()?.today, 90)
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
        XCTAssertEqual(runtime.growth.growth.xp, 495)
        XCTAssertEqual(core.growth()?.today, 95)
        XCTAssertTrue(events(.growth).isEmpty)
        turn()
        XCTAssertEqual(runtime.growth.growth, Growth(xp: 500, today: 100))
        XCTAssertEqual(events(.growth).map { [$0["level"]?.int, $0["ring"]?.bool == true ? 1 : 0] }, [[2, 1]],
                       "one event for the level and the ring that came together")
        XCTAssertTrue(runtime.harness.log.view(now: now).events.contains { $0.action == "react" && $0["by"]?.string == "rule" })
        turn()
        XCTAssertEqual(events(.growth).count, 1, "once a day")
        XCTAssertEqual(runtime.growth.growth, Growth(xp: 505, today: 105), "XP counts past the ring")
        XCTAssertEqual(core.growth()?.today, 105)

        // Across 5:00, by the runtime's own clock: a new Boop day, an empty
        // ring, and yesterday's full one in the week.
        let yesterday = options.time.boopDay(clock.now)
        while options.time.boopDay(clock.now) == yesterday { clock.now += 10 * 60_000 }
        XCTAssertEqual(core.growth()?.today, 0, "the new day's ring")
        turn()
        XCTAssertEqual(runtime.growth.growth, Growth(xp: 510, today: 5))
        XCTAssertEqual(core.growth()?.today, 5)
        let week = runtime.growth.week(to: options.time.boopDay(clock.now))
        XCTAssertEqual(week.suffix(2).map(\.xp), [105, 5])
        XCTAssertEqual(week.suffix(2).first?.day, yesterday)

        runtime.playingDemo = true
        XCTAssertNil(core.growth(), "a demo has none")
    }

    /// A level-up is celebrated when the board plays it, not when it's
    /// logged: one the board skips (it waited too long behind two finishes),
    /// or one cut by a request, is still due and plays at the board's next
    /// hello; with the board out of reach it waits for it.
    func testALevelUpTheBoardNeverPlayedIsStillDue() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-grow-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Runtime.setUp(stateDir: dir, name: "Pip")
        let clock = VirtualClock(1_793_000_000_000)
        let transport = FakeTransport()
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: transport,
                                      steering: RuntimeTests.steering)
        options.alone = true
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        do {
            let store = try KeyValueStore(directory: dir)
            try store.set([GrowthStore.xpKey: "495", GrowthStore.todayKey: "\(options.time.boopDay(clock.now)) 5"])
        }
        let runtime = try Runtime(options)
        var now: Int64 { clock.now }
        func turn() {
            runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 60_000
            runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
            clock.now += 60_000
        }
        func golds() -> [String] { transport.dos.filter { $0.contains("level 2!") } }
        runtime.home.sync {
            // The board is out of reach: the level waits for it.
            turn()
            XCTAssertEqual(runtime.growth.growth.level, 2)
            XCTAssertEqual(runtime.growth.earned(at: runtime.growth.lastSeq)?.xp, 5, "kept for its moment's sign")
            XCTAssertEqual(runtime.growth.levelDue, 2, "not celebrated with no board to play it")
            XCTAssertTrue(golds().isEmpty)

            // It comes back: the level plays, but waits too long in its queue.
            runtime.connection(true)
            runtime.device(FakeTransport.hello)
            XCTAssertEqual(golds().count, 1, "at the board's hello")
            XCTAssertNil(runtime.growth.levelDue, "sent: celebrated unless the board says otherwise")
            runtime.device(FakeTransport.ended(FakeTransport.id(golds()[0]), "skipped", "late"))
            XCTAssertEqual(runtime.growth.levelDue, 2, "skipped: still due")

            // More XP within the minute doesn't try again; the next hello does.
            turn()
            XCTAssertEqual(golds().count, 2, "two minutes on, with the next XP")
            runtime.device(FakeTransport.ended(FakeTransport.id(golds()[1]), "cut", "needs_you"))
            XCTAssertEqual(runtime.growth.levelDue, 2, "cut by a request: still due")
            runtime.connection(false)
            runtime.connection(true)
            runtime.device(FakeTransport.hello)
            XCTAssertEqual(golds().count, 3)
            runtime.device(FakeTransport.ended(FakeTransport.id(golds()[2]), "done"))
            XCTAssertNil(runtime.growth.levelDue, "played: celebrated")
            turn()
            XCTAssertEqual(golds().count, 3, "and never again")
        }
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
        XCTAssertEqual(count(growth, turnEnd(1)), 5)
        XCTAssertEqual(count(growth, event(2, .tool, .start)), 0)
        XCTAssertEqual(count(growth, turnEnd(3)), 5)
        XCTAssertEqual(count(growth, turnEnd(3)), 0)
        XCTAssertEqual(count(growth, turnEnd(1)), 0)
        XCTAssertEqual(growth.growth.xp, 10)

        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth, Growth(xp: 10, today: 10))
        XCTAssertEqual(again.lastSeq, 3)
    }

    /// A level and the ring closing are celebrated only as their events
    /// are logged, which is when they play: until then they stay due, so a
    /// quit while something needs you, or a demo, loses neither. Kept across
    /// opens.
    func testALevelIsCelebratedAsItPlays() throws {
        try KeyValueStore(directory: dir).set([GrowthStore.xpKey: "400", GrowthStore.celebratedKey: "1"])
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(growth.celebrated, 1)
        for seq in 1...20 { count(growth, turnEnd(seq)) }
        let day = "2026-10-22"
        XCTAssertEqual(growth.due(today: day), [.level(2), .ringClosed])
        try XCTAssertEqual(GrowthStore(KeyValueStore(directory: dir)).due(today: day), [.level(2), .ringClosed], "still due after a quit")
        XCTAssertEqual(growth.due(today: "2026-10-23"), [.level(2)], "a ring held past 5:00 is yesterday's")
        growth.played(Core.growthEvent(level: 2, ring: true, at: 0))
        XCTAssertEqual(growth.due(today: day), [])
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.celebrated, 2)
        XCTAssertEqual(reopened.due(today: day), [], "and not again")
    }

    /// A transcript whose files are all gone numbers from 1 again: counting
    /// follows it rather than skipping what's new.
    func testCountingFollowsATranscriptThatStartsAgain() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        count(growth, turnEnd(500))
        growth.follow(transcriptAt: 600)
        XCTAssertEqual(growth.lastSeq, 500)
        growth.follow(transcriptAt: 0)
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.lastSeq, 0)
        XCTAssertEqual(count(growth, turnEnd(1)), 5)
        XCTAssertEqual(growth.growth.xp, 10)
    }
}
