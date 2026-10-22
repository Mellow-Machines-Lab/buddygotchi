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
}
