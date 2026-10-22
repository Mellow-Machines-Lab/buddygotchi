import Foundation
import MellowHarness
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

    /// Each event counts once: one at or before the last counted is left
    /// alone, so a launch's read-back can't count it again.
    func testEachEventCountsOnceAndIsKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertTrue(growth.count(event(1, .tool, .end)))
        XCTAssertFalse(growth.count(event(2, .tool, .start)))
        XCTAssertTrue(growth.count(event(3, .turn, .end, ["outcome": .string("done")])))
        XCTAssertFalse(growth.count(event(3, .turn, .end, ["outcome": .string("done")])))
        XCTAssertFalse(growth.count(event(1, .tool, .end)))
        XCTAssertEqual(growth.growth.xp, 6)

        let again = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(again.growth, Growth(xp: 6, stage: 1))
        XCTAssertEqual(again.lastSeq, 3)
    }

    func testCrossingAThresholdReachesTheNextStage() throws {
        let lines = Lines()
        let growth = GrowthStore(try KeyValueStore(directory: nil), log: { lines.add($0) })
        for seq in 1...39 { growth.count(event(seq, .turn, .end, ["outcome": .string("done")])) }
        XCTAssertEqual(growth.growth.stage, 1)
        growth.count(event(40, .turn, .end, ["outcome": .string("done")]))
        XCTAssertEqual(growth.growth, Growth(xp: 200, stage: 2))
        XCTAssertEqual(lines.all, ["growth: reached stage 2, Sprout, at 200 XP"])
    }

    /// The day a stage was reached is kept, so a relaunch that day still
    /// has its party.
    func testTheDayAStageWasReachedIsKept() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertNil(growth.reachedDay)
        for seq in 1...40 { growth.count(event(seq, .turn, .end, ["outcome": .string("done")]), day: "2026-10-22") }
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.reachedDay, "2026-10-22")
    }

    /// A transcript whose files are all gone numbers from 1 again: counting
    /// follows it rather than skipping what's new.
    func testCountingFollowsATranscriptThatStartsAgain() throws {
        let growth = GrowthStore(try KeyValueStore(directory: dir))
        growth.count(event(500, .tool, .end))
        growth.follow(transcriptAt: 600)
        XCTAssertEqual(growth.lastSeq, 500)
        growth.follow(transcriptAt: 0)
        let reopened = GrowthStore(try KeyValueStore(directory: dir))
        XCTAssertEqual(reopened.lastSeq, 0)
        XCTAssertTrue(growth.count(event(1, .tool, .end)))
        XCTAssertEqual(growth.growth.xp, 2)
    }
}
