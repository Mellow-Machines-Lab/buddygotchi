import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// What's true now, as tags (`Tags`): the board's designs and the
/// prompt's heading both read them.
final class DaysTests: XCTestCase {
    let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    func ms(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Int64 {
        var c = DateComponents(year: y, month: mo, day: d, hour: h, minute: mi)
        c.timeZone = TimeZone(identifier: "UTC")
        return Int64(Calendar(identifier: .gregorian).date(from: c)!.timeIntervalSince1970 * 1000)
    }

    func tags(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, hatched: String? = nil) -> [String] {
        Days.tags(at: ms(y, mo, d, h, mi), hatched: hatched, time: utc)
    }

    /// Pins `Days.dayParts`: morning from 05:00, day from 11:00,
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
        XCTAssertEqual(tags(2026, 10, 31), ["day", "halloween"])
        XCTAssertEqual(tags(2026, 11, 13), ["day", "friday"])
        XCTAssertEqual(tags(2027, 1, 1), ["day", "friday", "newyear", "party"], "New Year's Day is a party")
        for (mo, d, tag) in [(2, 14, "valentines"), (12, 24, "winter"),
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

    /// Pins `Days.isMilestone`: a party on the 10th, 30th and 50th days
    /// since hatching, every 100th, and each anniversary; and the heading's
    /// words for each.
    func testMilestoneDaysAreAParty() {
        let hatched = "2026-09-01"
        let party = { (y: Int, mo: Int, d: Int) in self.tags(y, mo, d, hatched: hatched).contains("party") }
        XCTAssertFalse(party(2026, 9, 1), "the day it hatched")
        XCTAssertTrue(party(2026, 9, 11), "10 days")
        XCTAssertFalse(party(2026, 9, 12))
        XCTAssertTrue(party(2026, 10, 1), "a month")
        XCTAssertEqual(Days.words(at: ms(2026, 10, 1), hatched: hatched, name: "Boop", time: utc), ["Boop is a month old"])
        XCTAssertTrue(party(2026, 10, 21), "50 days")
        XCTAssertTrue(party(2026, 12, 10), "100 days")
        XCTAssertTrue(party(2027, 3, 20), "200 days")
        XCTAssertTrue(party(2027, 9, 1), "a year")
        func words(_ y: Int, _ mo: Int, _ d: Int) -> [String] {
            Days.words(at: ms(y, mo, d), hatched: hatched, name: "Pip", time: utc)
        }
        XCTAssertEqual(words(2026, 10, 21), ["Pip is 50 days old"])
        XCTAssertEqual(words(2026, 10, 31), ["Halloween"])
        XCTAssertEqual(words(2027, 9, 1), ["Pip's first anniversary"])
        XCTAssertEqual(words(2028, 9, 1), ["Pip's 2-year anniversary"])
        XCTAssertEqual(words(2026, 10, 22), [], "an ordinary day")
    }

    /// The board's tags are the Mac's but those no board reads, in the same
    /// order (firmware/src/render/tags.h), so a design's bits mean the same.
    func testTheTagsAreTheBoards() throws {
        let header = try String(contentsOf: CharacterPackTests.repo.appendingPathComponent("firmware/src/render/tags.h"), encoding: .utf8)
        let list = try XCTUnwrap(header.range(of: #"kTagNames\[kTagCount\] = \{[^}]*\}"#, options: .regularExpression))
        let names = header[list].split(separator: "\"").enumerated().filter { $0.offset % 2 == 1 }.map { String($0.element) }
        // The board's table keeps `tier4` and `tier5`, which Pixel's designs are
        // numbered by; the Mac never sends them.
        XCTAssertEqual(names.filter { !["tier4", "tier5"].contains($0) }, Tags.board)
        XCTAssertEqual(Tags.all, Tags.board, "the board reads every tag")
        XCTAssertLessThanOrEqual(Tags.board.count, 32, "a set of tags is 32 bits on the board")
    }

    /// Every occasion has a sign that fits the board's (`Signs.maxLength`
    /// characters of printable ASCII), and the day's greeting holds up the
    /// one most Boop's own: a milestone, then the calendar's.
    func testEachOccasionHasASignThatFits() {
        let hatched = "2026-09-01"
        var signs: [String] = Days.holidays.map(\.sign) + ["friday the 13th!", "programmers' day!", "lunar new year!"]
        for (y, mo, d) in [(2026, 9, 11), (2027, 9, 1), (2028, 9, 1), (2029, 6, 7)] {
            signs += Days.special(at: ms(y, mo, d), hatched: hatched, name: "Pip", time: utc).compactMap(\.sign)
        }
        for sign in signs {
            XCTAssertLessThanOrEqual(sign.count, Signs.maxLength, sign)
            XCTAssertTrue(sign.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }, sign)
        }
        func greeting(_ y: Int, _ mo: Int, _ d: Int) -> String? {
            Days.greeting(Days.special(at: ms(y, mo, d), hatched: hatched, name: "Pip", time: utc))
        }
        XCTAssertEqual(greeting(2026, 9, 11), "day 10!")
        XCTAssertEqual(greeting(2026, 10, 31), "happy halloween!")
        XCTAssertEqual(greeting(2027, 9, 1), "1 year old!")
        XCTAssertEqual(greeting(2028, 9, 1), "2 years old!")
        XCTAssertNil(greeting(2026, 10, 22), "an ordinary day")
        XCTAssertEqual(Days.special(at: ms(2026, 10, 21), hatched: hatched, name: "Pip", time: utc).map(\.why),
                       ["Pip is 50 days old today"])
        XCTAssertEqual(Days.special(at: ms(2026, 10, 31), hatched: nil, name: "Pip", time: utc).map(\.why), ["It's Halloween"])
    }

    /// A level-up is the rules' moment, not Jev's: its event, logged after
    /// the `state` with the new ring, and a face with `level 12!` held low
    /// in gold, the same at every level. The ring closing holds up
    /// `today's done!`; with a level at once, one moment shows both.
    func testALevelUpIsTheRulesMoment() {
        let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
        let now = ms(2026, 10, 22, 10)
        core.setWallClock(now, at: now)
        core.growth = { Growth(xp: 1_150, today: 50) }
        let fx = core.grew([.level(12)], at: now)
        let records: [Event] = fx.compactMap { if case .record(let e) = $0, e.type == .growth { return e } else { return nil } }
        XCTAssertEqual(records.map { $0["level"]?.int }, [12])
        XCTAssertEqual(records.map { $0["ring"] }, [nil])
        XCTAssertEqual(moments(fx).map(\.gold), ["level 12!"], "held low, in gold")
        XCTAssertEqual(moments(fx).map(\.sign), [nil], "nothing held up without the ring")
        XCTAssertEqual(moments(fx).map(\.mood), ["proud"])
        XCTAssertNotNil(moments(fx).first?.reason)
        XCTAssertNil(TranscriptView.wakes["growth"], "the rules play it: no pass")
        XCTAssertEqual(moments(core.grew([.level(15)], at: now)).map(\.mood), ["proud"], "no level is a bigger one")
        let ring = moments(core.grew([.ringClosed], at: now))
        XCTAssertEqual(ring.map(\.sign), [Core.ringSign])
        XCTAssertEqual(ring.map(\.gold), [nil])
        XCTAssertEqual(Core.ringSign, "today's done!")
        XCTAssertLessThanOrEqual(Core.ringSign.count, Signs.maxLength, "it fits a sign")
        XCTAssertLessThanOrEqual(Core.levelSign(999).count, Signs.maxLength, "and a level's fits")
    }

    /// The ring closing and a level reached at once are one moment, not
    /// two, and neither is lost: Boop holds up `today's done!`, and the
    /// level comes low in gold beside it; one `growth` event says both.
    func testTheRingAndALevelAreOneMoment() {
        let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
        let now = ms(2026, 10, 22, 10)
        core.setWallClock(now, at: now)
        core.growth = { Growth(xp: 1_300, today: 100) }
        let fx = core.grew([.ringClosed, .level(13)], at: now)
        let both = moments(fx)
        XCTAssertEqual(both.count, 1, "one moment")
        XCTAssertEqual(both.first?.sign, "today's done!")
        XCTAssertEqual(both.first?.gold, "level 13!")
        XCTAssertEqual(both.first?.mood, "proud")
        XCTAssertEqual(both.first?.args["gold"], .string("level 13!"), "on the wire")
        XCTAssertEqual(BoopDevice.play(both[0]), .next, "worth waiting its turn")
        let grew: [Event] = fx.compactMap { if case .record(let e) = $0, e.type == .growth { return e } else { return nil } }
        XCTAssertEqual(grew.count, 1, "one event")
        XCTAssertEqual(grew.first?["level"]?.int, 13)
        XCTAssertEqual(grew.first?["ring"]?.bool, true)
        XCTAssertEqual(grew.first.flatMap { TranscriptView().line($0, Transcript.log().view(now: now))?.text },
                       "\(creature) reached level 13. Today's ring is full: \(creature)'s done for the day.")
        XCTAssertEqual(BoopDevice.play(Moment(mood: "proud")), .ifFree)
        var gold = Moment(mood: "proud")
        gold.gold = "level 2!"
        XCTAssertEqual(BoopDevice.play(gold), .next, "a level alone too")
    }

    /// A level reached while something needs you isn't lost to it, nor does
    /// it cover the request: it waits for the answer, then plays, once.
    func testALevelReachedWhileSomethingNeedsYouWaits() {
        let rig = CoreRig()
        rig.send(.needsYou, tool: "Bash")
        XCTAssertNotNil(rig.pipeline.core.needsYouBlock)
        func levels() -> [Event] { rig.pipeline.harness.log.view(now: rig.now).events.filter { $0.type == .growth } }
        rig.pipeline.run(rig.pipeline.core.grew([.level(2)], at: rig.now))
        XCTAssertEqual(levels().count, 0, "not over needs you")
        rig.send(.activity, tool: "Bash")
        XCTAssertNil(rig.pipeline.core.needsYouBlock)
        XCTAssertEqual(levels().map { $0["level"]?.int }, [2], "once it's answered")
        rig.send(.activity, tool: "Bash")
        XCTAssertEqual(levels().count, 1, "once")
    }

    /// Two levels reached while held are one moment and one event, the
    /// last's.
    func testTwoHeldLevelsAreOneMoment() {
        let rig = CoreRig()
        rig.send(.needsYou, tool: "Bash")
        rig.pipeline.run(rig.pipeline.core.grew([.level(5)], at: rig.now))
        rig.pipeline.run(rig.pipeline.core.grew([.level(6)], at: rig.now))
        let fx = rig.send(.activity, tool: "Bash")
        XCTAssertEqual(moments(fx).compactMap(\.gold), [Core.levelSign(6)])
        XCTAssertEqual(rig.pipeline.harness.log.view(now: rig.now).events.filter { $0.type == .growth }.map { $0["level"]?.int }, [6])
    }

    /// On a day with an occasion, your first showing up holds up its sign,
    /// once a day (`Core.dayGreeting`); no agent's event greets it.
    func testASpecialDayIsGreetedOnce() {
        let rig = CoreRig(start: ms(2026, 10, 31, 14))
        XCTAssertEqual(moments(rig.send(.turnStart)).compactMap(\.sign), [], "not at an agent's event")
        XCTAssertEqual(rig.core.dayGreeting(at: rig.now), "happy halloween!")
        XCTAssertNil(rig.core.dayGreeting(at: rig.now), "once")
        XCTAssertNil(CoreRig().core.dayGreeting(at: CoreRig().now), "an ordinary day")
    }

    /// The popover's reasons choose as the board does
    /// (firmware/src/render/tags.cpp). The gel wears its nightcap at night
    /// and nothing for a day, and has nothing in the sky or the air (its
    /// screen's rule); a board that isn't the gel still has one hat, the
    /// first that fits, and its confetti, snow and hearts.
    func testTheReasonsAreTheBoards() {
        func reasons(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, gel: Bool = true) -> [String] {
            let at = ms(y, mo, d, h)
            let when = Days.tags(at: at, hatched: "2026-09-01", time: utc)
            let specialDays = Days.special(at: at, hatched: "2026-09-01", name: "Pip", time: utc)
            return Narration.Dressing.now(when: when, specialDays: specialDays, gel: gel).map { $0.why + ": " + ($0.what ?? "-") }
        }
        XCTAssertEqual(reasons(2026, 10, 21), ["Pip is 50 days old today: -"])
        XCTAssertEqual(reasons(2026, 10, 21, 23), ["Pip is 50 days old today: -", "It's night: a nightcap"])
        XCTAssertEqual(reasons(2026, 10, 21, 23, gel: false), ["Pip is 50 days old today: a party hat and confetti"])
        XCTAssertEqual(reasons(2026, 10, 21, gel: false), ["Pip is 50 days old today: a party hat and confetti"])
        XCTAssertEqual(reasons(2026, 12, 25, 23), ["It's the winter holidays: -", "It's night: a nightcap"])
        XCTAssertEqual(reasons(2026, 12, 25, 23, gel: false), ["It's the winter holidays: snow", "It's night: a nightcap"])
        XCTAssertEqual(reasons(2026, 12, 24), ["It's the winter holidays: -"])
        XCTAssertEqual(reasons(2026, 12, 24, gel: false), ["It's the winter holidays: a bobble hat and snow"])
        XCTAssertEqual(reasons(2026, 10, 23), [], "a Friday wears nothing")
        XCTAssertEqual(reasons(2026, 10, 22), [], "an ordinary afternoon")
        XCTAssertEqual(reasons(2026, 10, 22, 8), [], "an ordinary morning")
    }

    /// The day Boop hatched is your first with it, so it's no occasion: no
    /// party hat or confetti, no greeting and nothing in the popover. New
    /// Year's Day is still a party.
    func testTheDayItHatchedIsNoParty() {
        let core = Core(config: .init(time: utc, hatched: "2026-10-22"), lastActiveDay: "2026-10-22")
        let now = ms(2026, 10, 22, 10)
        core.setWallClock(now, at: now)
        XCTAssertFalse(core.snapshot(at: now).when.contains("party"))
        XCTAssertEqual(core.specialDays(at: now), [], "no greeting, and nothing for the popover")
        XCTAssertTrue(Days.tags(at: ms(2027, 1, 1), hatched: "2027-01-01", time: utc).contains("party"),
                      "hatched on New Year's Day")
    }

    /// Pins `Tags.tiers`: `tier1` from a minute, `tier2` from 5 and
    /// `tier3` from 15, the last.
    /// The last reached is sent; the board takes the ones below it as on.
    func testTheTiers() {
        XCTAssertEqual(Tags.tiers.map(\.fromMs), [60_000, 300_000, 900_000])
        for (s, tag) in [(0, nil), (59, nil), (60, "tier1"), (299, "tier1"), (300, "tier2"), (899, "tier2"), (900, "tier3"),
                         (7200, "tier3")] as [(Int64, String?)] {
            XCTAssertEqual(Tags.tier(after: s * 1000), tag, "\(s) s")
        }
        XCTAssertEqual(Tags.stretchRestMs, 30_000, "a rest shorter than this keeps a working stretch")
    }

    /// The board hears the tier in `state.when`: the working stretch's,
    /// from the first turn of it, while the agents work, and once they all
    /// rest, the time since the last turn ended.
    func testTheStateCarriesTheTiers() {
        let rig = CoreRig()
        let tiers = { rig.state.when.filter { $0.hasPrefix("tier") } }
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [])
        rig.wait(4 * 60_000)
        rig.send(.turnStart, session: "b")
        XCTAssertEqual(tiers(), ["tier1"], "the stretch began with a's turn, 4 minutes ago")
        rig.wait(4 * 60_000)
        XCTAssertEqual(tiers(), ["tier2"])
        rig.send(.turnEnd, session: "a")
        XCTAssertEqual(tiers(), ["tier2"], "b works on in the same stretch")
        rig.wait(8 * 60_000)
        XCTAssertEqual(tiers(), ["tier3"], "16 minutes in")
        rig.send(.turnEnd, session: "b")
        XCTAssertEqual(tiers(), [], "just finished: it settles")
        rig.wait(60_000)
        XCTAssertEqual(tiers(), ["tier1"])
        rig.wait(4 * 60_000)
        XCTAssertEqual(tiers(), ["tier2"])
        rig.wait(10 * 60_000)
        XCTAssertEqual(tiers(), ["tier3"])
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "back to work, a new stretch")
    }

    /// Pins `Tags.stretchRestMs`: a reply within 30 seconds of the
    /// agents coming to rest carries their working stretch on, so its tiers
    /// keep climbing; a longer rest starts a new one.
    func testAQuickReplyKeepsTheWorkingStretch() {
        let rig = CoreRig()
        let tiers = { rig.state.when.filter { $0.hasPrefix("tier") } }
        rig.send(.turnStart, session: "a")
        rig.wait(3 * 60_000)
        rig.send(.turnEnd, session: "a")
        rig.wait(29_000)
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), ["tier1"], "the stretch began 3.5 minutes ago")
        rig.wait(2 * 60_000)
        XCTAssertEqual(tiers(), ["tier2"])
        rig.send(.turnEnd, session: "a")
        rig.wait(60_000)
        XCTAssertEqual(tiers(), ["tier1"], "idle's")
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "a new stretch")
        rig.send(.turnEnd, session: "a")
        rig.wait(30_000)
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "30 seconds of rest ends a stretch")
    }

    /// Boop is one size at every level: its level puts no tag on.
    func testALevelIsNoTag() {
        let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
        core.growth = { Growth(xp: 500) }
        let young = core.snapshot(at: ms(2026, 10, 22)).when
        core.growth = { Growth(xp: 2_900) }
        XCTAssertEqual(core.snapshot(at: ms(2026, 10, 22)).when, young)
        XCTAssertEqual(Tags.board.suffix(6), ["tier3", "hushed", "typing", "reading", "macleft", "macright"],
                       "no stage's tag between the tiers and `hushed`: the firmware's list ends the same way, after the two tiers it keeps for Pixel (render/tags.h)")
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
