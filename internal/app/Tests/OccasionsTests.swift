import Foundation
import XCTest
@testable import BoopKit

/// What's true now, as tags (`Occasions`): the board's designs and the
/// prompt's heading both read them.
final class OccasionsTests: XCTestCase {
    let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    func ms(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Int64 {
        var c = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
        c.timeZone = TimeZone(identifier: "UTC")
        return Int64(Calendar(identifier: .gregorian).date(from: c)!.timeIntervalSince1970 * 1000)
    }

    func tags(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, hatched: String? = nil) -> [String] {
        Occasions.tags(at: ms(y, mo, d, h, mi), hatched: hatched, time: utc)
    }

    /// Pins `Occasions.dayParts`: morning from 05:00, day from 11:00,
    /// evening from 17:00, night from 22:00 until 05:00.
    func testThePartsOfTheDay() {
        for (h, mi, part) in [(4, 59, "night"), (5, 0, "morning"), (10, 59, "morning"), (11, 0, "day"), (16, 59, "day"),
                              (17, 0, "evening"), (21, 59, "evening"), (22, 0, "night"), (0, 0, "night")] {
            XCTAssertEqual(tags(2026, 10, 21, h, mi).first, part, "\(h):\(mi)")
        }
    }

    /// The weekday's tags, and each fixed holiday on its day and no other.
    func testTheWeekAndTheHolidays() {
        XCTAssertEqual(tags(2026, 10, 21), ["day"], "an ordinary Wednesday")
        XCTAssertEqual(tags(2026, 10, 30), ["day", "friday"])
        XCTAssertEqual(tags(2026, 10, 31), ["day", "weekend", "halloween"])
        XCTAssertEqual(tags(2026, 11, 13), ["day", "friday", "friday13"])
        XCTAssertEqual(tags(2027, 1, 1), ["day", "friday", "newyear", "party"], "New Year's Day is a party")
        for (mo, d, tag) in [(2, 14, "valentines"), (3, 14, "piday"), (4, 1, "aprilfools"), (5, 4, "may4"), (12, 24, "winter"),
                             (12, 26, "winter")] {
            XCTAssertTrue(tags(2026, mo, d).contains(tag), tag)
            XCTAssertFalse(tags(2026, mo, d + 1 == 27 ? 27 : d - 1).contains(tag), "\(tag), not the day before or after")
        }
        XCTAssertFalse(tags(2026, 12, 27).contains("winter"))
        XCTAssertTrue(tags(2026, 9, 13).contains("programmers"), "the 256th day")
        XCTAssertTrue(tags(2028, 9, 12).contains("programmers"), "the 256th day of a leap year")
        XCTAssertFalse(tags(2028, 9, 13).contains("programmers"))
        XCTAssertTrue(tags(2026, 2, 17).contains("lunar"))
        XCTAssertTrue(tags(2027, 2, 6).contains("lunar"))
        XCTAssertFalse(tags(2026, 2, 18).contains("lunar"))
    }

    /// Pins `Occasions.isMilestone`: a party on the 10th and 50th days
    /// since hatching, every 100th, and each anniversary; and the heading's
    /// words for each.
    func testMilestoneDaysAreAParty() {
        let hatched = "2026-09-01"
        let party = { (y: Int, mo: Int, d: Int) in self.tags(y, mo, d, hatched: hatched).contains("party") }
        XCTAssertFalse(party(2026, 9, 1), "the day it hatched")
        XCTAssertTrue(party(2026, 9, 11), "10 days")
        XCTAssertFalse(party(2026, 9, 12))
        XCTAssertTrue(party(2026, 10, 21), "50 days")
        XCTAssertTrue(party(2026, 12, 10), "100 days")
        XCTAssertTrue(party(2027, 3, 20), "200 days")
        XCTAssertTrue(party(2027, 9, 1), "a year")
        XCTAssertTrue(Occasions.tags(at: ms(2026, 10, 22), hatched: hatched, party: true, time: utc).contains("party"),
                      "a stage reached")
        func words(_ y: Int, _ mo: Int, _ d: Int) -> [String] {
            Occasions.words(at: ms(y, mo, d), hatched: hatched, name: "Pip", time: utc)
        }
        XCTAssertEqual(words(2026, 10, 21), ["Pip is 50 days old"])
        XCTAssertEqual(words(2026, 10, 31), ["Halloween"])
        XCTAssertEqual(words(2027, 9, 1), ["Pip's first anniversary"])
        XCTAssertEqual(words(2028, 9, 1), ["Pip's 2-year anniversary"])
        XCTAssertEqual(words(2026, 10, 22), [], "an ordinary day")
    }

    /// The Mac's tags are the board's, in the same order
    /// (firmware/src/render/tags.h), so a design's bits mean the same.
    func testTheTagsAreTheBoards() throws {
        let header = try String(contentsOf: CharacterPackTests.repo.appendingPathComponent("firmware/src/render/tags.h"), encoding: .utf8)
        let list = try XCTUnwrap(header.range(of: #"kTagNames\[kTagCount\] = \{[^}]*\}"#, options: .regularExpression))
        let names = header[list].split(separator: "\"").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        XCTAssertEqual(names, Occasions.all)
        XCTAssertLessThanOrEqual(Occasions.all.count, 32, "a set of tags is 32 bits on the board")
    }

    /// A growth stage reached makes the rest of its day a party, on the
    /// board (`state.when`) and in the heading's words.
    func testAStageReachedIsAParty() {
        let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
        let now = ms(2026, 10, 22, 10)
        core.setWallClock(now, at: now)
        XCTAssertFalse(core.snapshot(at: now).when.contains("party"))
        core.reachedStage("Sprout", at: now)
        XCTAssertTrue(core.snapshot(at: now).when.contains("party"))
        XCTAssertFalse(core.snapshot(at: now + 24 * 3_600_000).when.contains("party"), "the next day isn't")
        XCTAssertEqual(Occasions.words(at: now, hatched: nil, name: "Pip", stage: core.config.stageReached, time: utc), ["Pip became a Sprout"])
    }

    /// Pins `Occasions.workTiers` and `idleTiers`: a turn is a marathon
    /// from 8 minutes and a camp from 15, the last; idle fidgets from 30
    /// seconds, has set pieces from 3 minutes and dozes from 10. One tier
    /// at a time.
    func testTheTiersOfALongTurnAndOfIdle() {
        let tier = { (tiers: [(tag: String, fromMs: Int64)], s: Int64) in Occasions.tier(tiers, after: s * 1000) }
        for (s, tag) in [(0, nil), (479, nil), (480, "marathon"), (899, "marathon"), (900, "camp"), (7200, "camp")] as [(Int64, String?)] {
            XCTAssertEqual(tier(Occasions.workTiers, s), tag, "working \(s) s")
        }
        for (s, tag) in [(0, nil), (29, nil), (30, "fidget"), (179, "fidget"), (180, "setpiece"), (599, "setpiece"),
                         (600, "doze"), (7200, "doze")] as [(Int64, String?)] {
            XCTAssertEqual(tier(Occasions.idleTiers, s), tag, "idle \(s) s")
        }
    }

    /// The board hears the tiers in `state.when`: the longest turn working
    /// now sets the working tier, and the last turn to finish sets idle's.
    func testTheStateCarriesTheTiers() {
        let rig = CoreRig()
        let tiers = { Set(rig.state.when).intersection(["marathon", "camp", "fidget", "setpiece", "doze"]) }
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [])
        rig.wait(4 * 60_000)
        rig.send(.turnStart, session: "b")
        rig.wait(4 * 60_000)
        XCTAssertEqual(tiers(), ["marathon"], "a's turn has run 8 minutes, b's 4")
        rig.wait(7 * 60_000)
        XCTAssertEqual(tiers(), ["camp"])
        rig.send(.turnEnd, session: "a")
        XCTAssertEqual(tiers(), ["marathon"], "b's turn has run 11 minutes")
        rig.send(.turnEnd, session: "b")
        XCTAssertEqual(tiers(), [], "just finished: it settles")
        rig.wait(30_000)
        XCTAssertEqual(tiers(), ["fidget"])
        rig.wait(150_000)
        XCTAssertEqual(tiers(), ["setpiece"])
        rig.wait(420_000)
        XCTAssertEqual(tiers(), ["doze"])
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "back to work")
    }

    /// Pins `Occasions.reads`: a prompt's reading puts `reading` on when
    /// you wrote an essay or asked for docs, and the board hears it while
    /// that turn lasts, as the latest prompt's reading says.
    func testAnEssayOrDocsPutsReadingOnForItsTurn() {
        XCTAssertTrue(Occasions.reads(PromptReading(length: .essay)))
        XCTAssertTrue(Occasions.reads(PromptReading(length: .words, kind: .docs)))
        XCTAssertFalse(Occasions.reads(PromptReading(length: .paragraph, kind: .fix)))
        let rig = CoreRig()
        let reading = { rig.state.when.contains(Occasions.reading) }
        rig.send(.turnStart, prompt: String(repeating: "Write the whole thing up for me, please. ", count: 20))
        XCTAssertTrue(reading(), "an essay of a prompt")
        rig.send(.activity, tool: "Edit")
        rig.wait(60_000)
        XCTAssertTrue(reading(), "while its turn lasts")
        rig.send(.turnEnd)
        XCTAssertFalse(reading(), "its turn ended")
        rig.note(Fx(rig.pipeline.agent(rig.event(.turnStart, prompt: "update the readme"), labels: .init(kind: .docs))))
        XCTAssertTrue(reading(), "a prompt for docs")
        rig.send(.turnStart, session: "s2", prompt: "fix the login bug")
        XCTAssertFalse(reading(), "the latest prompt is neither")
        rig.send(.turnEnd, session: "s2")
        rig.send(.turnEnd)
        rig.send(.turnStart, prompt: "and the next")
        XCTAssertFalse(reading(), "a turn has its own prompt's")
    }

    /// Every growth stage reached is a tag, so a design for Pal shows at
    /// Pal and after; a Hatchling has none.
    func testEveryStageReachedIsOn() {
        XCTAssertEqual(Occasions.stages(1), [])
        XCTAssertEqual(Occasions.stages(2), ["sprout"])
        XCTAssertEqual(Occasions.stages(4), ["sprout", "buddy", "pal"])
        XCTAssertEqual(Occasions.stages(Growth.stages.count), Occasions.stageTags)
        XCTAssertEqual(Occasions.stageTags, ["sprout", "buddy", "pal", "chonk", "legend"])
        let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
        core.stage = { 3 }
        XCTAssertEqual(core.snapshot(at: ms(2026, 10, 22)).when.suffix(2), ["sprout", "buddy"])
    }

    /// A demo's hold keeps its finger down longer than the board's hold
    /// (firmware/src/app/touch_gesture.h, TouchGesture::kHoldMs), so the
    /// board sees one: changing either fails here.
    func testADemosHoldOutlastsTheBoards() throws {
        let header = try String(contentsOf: CharacterPackTests.repo.appendingPathComponent("firmware/src/app/touch_gesture.h"),
                                encoding: .utf8)
        let line = try XCTUnwrap(header.range(of: #"kHoldMs = [0-9]+"#, options: .regularExpression))
        let holdMs = try XCTUnwrap(Double(header[line].split(separator: " ").last!))
        XCTAssertEqual(holdMs, 1000)
        XCTAssertGreaterThan(DemoScript.holdSeconds * 1000, holdMs)
        XCTAssertEqual(DemoScript.holdSeconds, 1.2)
    }
}
