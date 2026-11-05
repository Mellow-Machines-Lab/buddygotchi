import AgentHooks
import Foundation
import MellowHarness
import SQLite3
import XCTest
@testable import BoopDevKit
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

    /// Four stages at 0, 200, 1,000 and 5,000 XP, and an XP past the table
    /// a Chonk with the bar full.
    func testStagesStartAtTheirThresholds() {
        XCTAssertEqual(Growth.stages.map(\.from), [0, 200, 1_000, 5_000])
        XCTAssertEqual(Growth.stages.map(\.name), ["Hatchling", "Sprout", "Buddy", "Chonk"])
        XCTAssertEqual(Growth.stage(for: 0), 1)
        XCTAssertEqual(Growth.stage(for: 199), 1)
        XCTAssertEqual(Growth.stage(for: 200), 2)
        XCTAssertEqual(Growth.stage(for: 4_999), 3)
        XCTAssertEqual(Growth.stage(for: 5_000), 4)
        XCTAssertEqual(Growth.stage(for: 1_000_000), 4)

        let g = Growth(xp: 600)
        XCTAssertEqual(g.stage, 2)
        XCTAssertEqual(g.name, "Sprout")
        XCTAssertEqual(g.nextAt, 1_000)
        XCTAssertEqual(g.progress, 0.5)
        XCTAssertNil(Growth(xp: 40_000).nextAt)
        XCTAssertEqual(Growth(xp: 40_000).progress, 1)
    }

    /// A stage saved when there were six, and a stage never went back: Pal
    /// comes to Buddy, Chonk and Legend to Chonk; it keeps at least its stage's
    /// size, in XP, as the stage is the XP's from then on, once: what it loses
    /// later isn't given back at the next launch. A store with no stage saved
    /// (new, or moved already) is left at its XP.
    func testASavedStageKeepsItsSize() throws {
        XCTAssertEqual((1...6).map(Growth.stage(fromSix:)), [1, 2, 3, 3, 4, 4])
        XCTAssertEqual([0, 9].map(Growth.stage(fromSix:)), [1, 4], "held to the table")
        // Stage, XP saved; the stage and XP it comes to.
        let cases: [(old: Int, xp: Int, name: String, to: Int)] = [
            (1, 50, "Hatchling", 50),      // a Hatchling stays a Hatchling
            (2, 300, "Sprout", 300),
            (2, 10, "Sprout", 200),        // a Sprout by a stage never lost, its XP lower
            (3, 10, "Buddy", 1_000),
            (4, 4_200, "Buddy", 4_200),    // Pal
            (4, 10, "Buddy", 1_000),
            (4, 5_100, "Chonk", 5_100),    // past the new threshold by its XP
            (5, 12_500, "Chonk", 12_500),  // Chonk
            (5, 10, "Chonk", 5_000),
            (6, 31_000, "Chonk", 31_000),  // Legend
        ]
        for c in cases {
            let dir = dir.appendingPathComponent("\(c.old)-\(c.xp)")
            let store = try KeyValueStore(directory: dir)
            try store.set(["growth.xp": String(c.xp), "growth.stage": String(c.old)])
            let growth = GrowthStore(store)
            XCTAssertEqual(growth.growth.name, c.name, "\(c)")
            XCTAssertEqual(growth.growth.xp, c.to, "\(c)")
            XCTAssertGreaterThanOrEqual(growth.growth.stage, Growth.stage(fromSix: c.old), "\(c)")
            XCTAssertNil(store.int("growth.stage"), "read once")
            XCTAssertEqual(store.int("growth.xp"), c.to, "kept")
        }
        // Once: it goes backwards from there, and stays gone back.
        let store = try KeyValueStore(directory: dir)
        try store.set(["growth.xp": "1000", "growth.stage": "3"])
        let growth = GrowthStore(store)
        growth.decay(today: "2026-11-01")
        growth.decay(today: "2026-11-05")
        XCTAssertEqual(growth.growth.xp, 950)
        try XCTAssertEqual(GrowthStore(KeyValueStore(directory: dir)).growth.xp, 950, "the next launch gives none of it back")
    }

    /// The first launch on going backwards costs nothing, however long since
    /// it last earned, as nothing kept that day: the 3 days start then.
    func testAFirstLaunchLosesNothing() throws {
        let store = try KeyValueStore(directory: dir)
        try store.set(["growth.xp": "1000", "growth.stage": "3", "growth.last_seq": "9"])
        let growth = GrowthStore(store)
        XCTAssertNil(growth.earnedDay)
        XCTAssertFalse(growth.decay(today: "2026-12-25"))
        XCTAssertEqual(growth.earnedDay, "2026-12-25")
        XCTAssertFalse(growth.decay(today: "2026-12-28"), "the 3 days are free")
        XCTAssertEqual(growth.growth.xp, 1_000)
        XCTAssertTrue(growth.decay(today: "2026-12-29"))
        XCTAssertEqual(growth.growth.xp, 950)
    }

    /// The bar's percent (`state.xp`): how far through the stage, whole,
    /// and 100 only at the last.
    func testThePercentTheBoardShows() {
        XCTAssertEqual(Growth(xp: 0).percent, 0)
        XCTAssertEqual(Growth(xp: 100).percent, 50)
        XCTAssertEqual(Growth(xp: 199).percent, 99, "not full short of the stage")
        XCTAssertEqual(Growth(xp: 200).percent, 0)
        XCTAssertEqual(Growth(xp: 600).percent, 50)
        XCTAssertEqual(Growth(xp: 5_000).percent, 100)
        XCTAssertEqual(Growth(xp: 40_000).percent, 100)
    }

    /// What growing sends through the runtime: a `state` with the bar's
    /// percent as a turn's XP moves it, no sign of the rule's, and at a stage a
    /// `grew` event that wakes a pass. A demo sends no percent.
    func testEarningMovesTheBarAndGrowingTellsJev() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-grow-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Runtime.setUp(stateDir: dir, name: "Pip")
        do {
            let store = try KeyValueStore(directory: dir)
            try store.set(["growth.xp": "190"])
        }
        let clock = VirtualClock(1_793_000_000_000)
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        let runtime = try Runtime(options)
        let core = runtime.core(runtime.rigs[0])
        var now: Int64 { clock.now }
        XCTAssertEqual(core.snapshot(at: now).xp, 95)
        func turn() {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
                clock.now += 60_000
                runtime.hook(HookLine(agent: "claude", hook: "Stop", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
                clock.now += 60_000
            }
        }
        turn()
        XCTAssertEqual(runtime.growth.growth.xp, 195)
        XCTAssertEqual(core.snapshot(at: now).xp, 97)
        XCTAssertFalse(runtime.harness.log.view(now: now).events.contains { $0.type == .grew })
        turn()
        XCTAssertEqual(runtime.growth.growth.xp, 200)
        XCTAssertEqual(runtime.growth.growth.name, "Sprout")
        XCTAssertEqual(core.snapshot(at: now).xp, 0)
        XCTAssertTrue(core.snapshot(at: now).when.contains("sprout"))
        let grew = runtime.harness.log.view(now: now).events.filter { $0.type == .grew }
        XCTAssertEqual(grew.map(\.specificType), ["Sprout"])

        runtime.playingDemo = true
        let shown = core.snapshot(at: now)
        XCTAssertNil(shown.xp, "a demo sends none")
        XCTAssertFalse(shown.when.contains("sprout"), "a demo's full size")
    }

    /// A stage reached earlier today with no `grew` in the log, as a quit
    /// while something needed you leaves it: the next launch tells Jev, once.
    func testAGrewAQuitLostComesAtTheNextLaunch() throws {
        try requirePack("boop")
        let dir = URL(fileURLWithPath: "/tmp/boop-grew-\(UUID().uuidString.prefix(8))")
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
            try store.set(["growth.xp": "200", GrowthStore.reachedKey: options.time.day(clock.now)])
        }
        func launch() throws -> Int {
            let runtime = try Runtime(options)
            let grew = runtime.home.sync { () -> Int in
                let now = clock.now
                runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/proj", ts: now), received: now)
                return runtime.harness.log.view(now: now).events.filter { $0.type == .grew && $0.specificType == "Sprout" }.count
            }
            runtime.stop()
            runtime.home.sync {}
            return grew
        }
        var grew = try launch()
        XCTAssertEqual(grew, 1)
        clock.now += 60_000
        grew = try launch()
        XCTAssertEqual(grew, 1, "and only once")
    }

    /// `offered` for a `grew`: the stage's lines first, then any stage's.
    func testWhatItMayHoldUpGrowing() {
        let lines = [TaggedLine(tags: ["idle"], text: "quiet day..."),
                     TaggedLine(tags: ["grew"], text: "i grew!"),
                     TaggedLine(tags: ["grew", "sprout"], text: "look, a sprout!"),
                     TaggedLine(tags: ["grew", "chonk"], text: "so much me!"),
                     TaggedLine(tags: ["grew", "buddy"], text: "a sign much too long to hold up")]
        XCTAssertEqual(Signs.grew(lines, stage: "Sprout"), ["look, a sprout!", "i grew!"])
        XCTAssertEqual(Signs.grew(lines, stage: "Chonk"), ["so much me!", "i grew!"])
        XCTAssertEqual(Signs.grew(lines, stage: "Buddy"), ["i grew!"])
    }

    /// 3 days with no XP are free, then 5% a day, and it never reaches zero.
    func testItGoesBackwardsAfterThreeDays() throws {
        XCTAssertEqual(Growth.decayed(1_000, days: 1), 950)
        XCTAssertEqual(Growth.decayed(1_000, days: 2), 903)
        XCTAssertEqual(Growth.decayed(2, days: 400), 1)
        XCTAssertEqual(Growth.decayed(0, days: 4), 0)

        let store = try KeyValueStore(directory: dir)
        try store.set(["growth.xp": "1020"])
        let growth = GrowthStore(store)
        XCTAssertFalse(growth.decay(today: "2026-11-01"), "the first day starts the clock")
        XCTAssertFalse(growth.decay(today: "2026-11-04"), "the third day is free")
        XCTAssertTrue(growth.decay(today: "2026-11-05"))
        XCTAssertEqual(growth.growth.xp, 969)
        XCTAssertEqual(growth.growth.name, "Sprout", "a stage goes with it")
        XCTAssertFalse(growth.decay(today: "2026-11-05"), "once a day")
        XCTAssertEqual(growth.shrankWords(today: "2026-11-05", name: "Pip"), "Pip shrank a little. You were gone 4 days.")
        XCTAssertEqual(growth.shrankWords(today: "2026-11-06", name: "Pip"), "Pip shrank a little. You were gone 4 days.")
        XCTAssertNil(growth.shrankWords(today: "2026-11-07", name: "Pip"))

        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth.xp, 969)
        XCTAssertFalse(again.decay(today: "2026-11-05"), "kept across a launch")
    }

    /// Going backwards is settled before what's earned counts, and earning stops it.
    func testEarningStopsGoingBackwards() throws {
        let store = try KeyValueStore(directory: dir)
        try store.set(["growth.xp": "1000", "growth.earned": "2026-11-01"])
        let growth = GrowthStore(store)
        XCTAssertTrue(growth.count(event(1, .tool, .end), earned: 1, day: "2026-11-06"))
        XCTAssertEqual(growth.growth.xp, 904)
        XCTAssertFalse(growth.decay(today: "2026-11-09"))
        XCTAssertTrue(growth.decay(today: "2026-11-10"))
    }

    /// A met wish is worth 40, and only one a day counts.
    func testAMetWishEarnsForty() {
        let met = Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.met.rawValue)
        XCTAssertEqual(Growth.earning(for: met)?.xp, 40)
        XCTAssertEqual(Growth.earning(for: met)?.pool, .wish)
        XCTAssertEqual(Growth.cap(.wish), 40)
        XCTAssertNil(Growth.earning(for: Event(at: 0, source: .boop, type: .wish, phase: .end, specificType: Core.WishEnd.closed.rawValue)))
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
        XCTAssertEqual(again.growth, Growth(xp: 6))
        XCTAssertEqual(again.lastSeq, 3)
    }

    func testCrossingAThresholdReachesTheNextStage() throws {
        let lines = Lines()
        let growth = GrowthStore(try KeyValueStore(directory: nil), log: { lines.add($0) })
        for seq in 1...39 { count(growth, event(seq, .turn, .end, ["outcome": .string("done")])) }
        XCTAssertEqual(growth.growth.stage, 1)
        count(growth, event(40, .turn, .end, ["outcome": .string("done")]))
        XCTAssertEqual(growth.growth, Growth(xp: 200))
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
