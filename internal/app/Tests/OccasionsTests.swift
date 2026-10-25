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

    /// Every occasion has a sign that fits the board's (`Signs.maxLength`
    /// characters of printable ASCII), and the day's greeting holds up the
    /// one most Boop's own: a stage reached, then a milestone, then the
    /// calendar's.
    func testEachOccasionHasASignThatFits() {
        let hatched = "2026-09-01"
        var signs = Occasions.holidays.map(\.sign) + ["Friday the 13th!", "Programmers' Day!", "Lunar New Year!"]
        for (y, mo, d) in [(2026, 9, 11), (2027, 9, 1), (2028, 9, 1), (2029, 6, 7)] {
            signs += Occasions.occasions(at: ms(y, mo, d), hatched: hatched, name: "Pip", time: utc).map(\.sign)
        }
        signs += Growth.stages.map { Occasions.occasions(at: ms(2026, 10, 22), hatched: nil, name: "Pip", stage: ($0.name, "2026-10-22"),
                                                         time: utc)[0].sign }
        for sign in signs {
            XCTAssertLessThanOrEqual(sign.count, Signs.maxLength, sign)
            XCTAssertTrue(sign.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }, sign)
        }
        func greeting(_ y: Int, _ mo: Int, _ d: Int, stage: String? = nil) -> String? {
            Occasions.greeting(Occasions.occasions(at: ms(y, mo, d), hatched: hatched, name: "Pip",
                                                   stage: stage.map { ($0, utc.day(ms(y, mo, d))) }, time: utc))
        }
        XCTAssertEqual(greeting(2026, 9, 11), "Day 10!")
        XCTAssertEqual(greeting(2026, 10, 31), "Happy Halloween!")
        XCTAssertEqual(greeting(2026, 10, 31, stage: "Sprout"), "I'm a Sprout!", "the stage over the holiday")
        XCTAssertEqual(greeting(2027, 9, 1), "1 year old!")
        XCTAssertEqual(greeting(2028, 9, 1), "2 years old!")
        XCTAssertNil(greeting(2026, 10, 22), "an ordinary day")
        XCTAssertEqual(Occasions.occasions(at: ms(2026, 10, 21), hatched: hatched, name: "Pip", time: utc).map(\.why),
                       ["Pip is 50 days old today"])
        XCTAssertEqual(Occasions.occasions(at: ms(2026, 10, 31), hatched: nil, name: "Pip", time: utc).map(\.why), ["It's Halloween"])
    }

    /// Growing a stage just now plays its moment: the confetti, holding up
    /// a sign saying what Boop grew into, which waits its turn on the
    /// device, recorded for the brain. Read back at launch, it doesn't.
    func testGrowingAStageCelebratesThen() {
        func core() -> Core {
            let core = Core(config: .init(time: utc), lastActiveDay: "2026-10-22")
            core.setWallClock(now, at: now)
            return core
        }
        let now = ms(2026, 10, 22, 10)
        XCTAssertEqual(deviceReactions(core().reachedStage("Sprout", at: now)), [], "at launch")
        let fx = core().reachedStage("Sprout", celebrate: true, at: now)
        let cheer = DeviceReaction(anim: "task_complete", loops: 2, outcome: "success", sign: "I'm a Sprout!")
        XCTAssertEqual(deviceReactions(fx), [cheer])
        XCTAssertEqual(BoopDevice.play(cheer), .next, "a sign waits its turn")
        XCTAssertTrue(fx.contains { if case .state(let s) = $0 { return s.when.contains("party") } else { return false } },
                      "the party hat is on as it plays")
        let did = fx.compactMap { if case .record(let e) = $0 { return e } else { return nil } }
        XCTAssertEqual(did.map { $0["message"]?.string }, ["Boop celebrated becoming a Sprout, holding up a sign: \"I'm a Sprout!\"."])
    }

    /// On a day with an occasion, the first agent's event greets it once,
    /// waking with its sign after the event's own reaction; an ordinary
    /// day has none.
    func testASpecialDayIsGreetedOnce() {
        let rig = CoreRig(start: ms(2026, 10, 31, 14))
        let first = rig.send(.turnStart)
        XCTAssertEqual(deviceReactions(first).map(\.sign), [nil, "Happy Halloween!"])
        XCTAssertEqual(deviceReactions(first).last?.anim, "wake_up")
        XCTAssertEqual(deviceReactions(rig.send(.turnStart, session: "s2")).compactMap(\.sign), [], "once")
        XCTAssertEqual(deviceReactions(CoreRig().send(.turnStart)).compactMap(\.sign), [], "an ordinary day")
    }

    /// The popover's reasons choose as the board does
    /// (firmware/src/render/tags.cpp): one hat, the first that fits; on
    /// the gel, glasses for your prompt over Friday's shades, neither
    /// asleep, and pyjamas with the nightcap only bare-eyed; confetti at a
    /// party or New Year.
    func testTheReasonsAreTheBoards() {
        func reasons(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, stage: String? = nil, reading: Bool = false, asleep: Bool = false,
                     gel: Bool = true) -> [String] {
            let at = ms(y, mo, d, h), day = utc.day(at)
            let when = Occasions.tags(at: at, hatched: "2026-09-01", party: stage != nil, time: utc) + (reading ? [Occasions.reading] : [])
            let occasions = Occasions.occasions(at: at, hatched: "2026-09-01", name: "Pip", stage: stage.map { ($0, day) }, time: utc)
            return Dressing.now(when: when, occasions: occasions, asleep: asleep, gel: gel).map { $0.why + ": " + ($0.what ?? "-") }
        }
        XCTAssertEqual(reasons(2026, 10, 22, stage: "Sprout"), ["Pip became a Sprout today: a party hat and confetti"])
        XCTAssertEqual(reasons(2026, 10, 21), ["Pip is 50 days old today: a party hat and confetti"])
        XCTAssertEqual(reasons(2026, 10, 31, stage: "Sprout"),
                       ["It's Halloween: a witch hat", "Pip became a Sprout today: confetti"], "the witch hat wins")
        XCTAssertEqual(reasons(2026, 12, 25, 23), ["It's the winter holidays: snow", "It's night: a nightcap and pyjamas"])
        XCTAssertEqual(reasons(2026, 12, 25, 23, gel: false), ["It's the winter holidays: snow", "It's night: a nightcap"])
        XCTAssertEqual(reasons(2026, 12, 24), ["It's the winter holidays: a bobble hat and snow"])
        XCTAssertEqual(reasons(2027, 3, 14), ["It's Pi Day: -"])
        XCTAssertEqual(reasons(2026, 10, 23), ["It's Friday: shades"])
        XCTAssertEqual(reasons(2026, 10, 23, reading: true), ["Your prompt was an essay, or asked for docs: reading glasses"])
        XCTAssertEqual(reasons(2026, 10, 22, 23, reading: true),
                       ["It's night: a nightcap", "Your prompt was an essay, or asked for docs: reading glasses"])
        XCTAssertEqual(reasons(2026, 10, 23, asleep: true), [])
        XCTAssertEqual(reasons(2026, 10, 23, gel: false), [])
        XCTAssertEqual(reasons(2026, 10, 22), [], "an ordinary afternoon")
    }

    /// The day Boop hatched is your first with it, so a stage reached that
    /// day is no occasion: no party hat or confetti, no cheer, no greeting
    /// and nothing in the popover. New Year's Day is still a party.
    func testTheDayItHatchedIsNoParty() {
        let core = Core(config: .init(time: utc, hatched: "2026-10-22"), lastActiveDay: "2026-10-22")
        let now = ms(2026, 10, 22, 10)
        core.setWallClock(now, at: now)
        XCTAssertEqual(deviceReactions(core.reachedStage("Sprout", celebrate: true, at: now)), [], "no cheer")
        XCTAssertFalse(core.snapshot(at: now).when.contains("party"), "a Sprout on the day it hatched")
        XCTAssertEqual(core.occasions(at: now), [], "no greeting, and nothing for the popover")
        XCTAssertTrue(Occasions.tags(at: ms(2027, 1, 1), hatched: "2027-01-01", party: true, time: utc).contains("party"),
                      "hatched on New Year's Day")
        XCTAssertTrue(Occasions.tags(at: ms(2026, 10, 23), hatched: "2026-10-22", party: true, time: utc).contains("party"),
                      "a stage reached the day after")
    }

    /// Pins `Occasions.tiers`: `tier1` from 30 seconds, `tier2` from a
    /// minute, `tier3` from 2, `tier4` from 5 and `tier5` from 10, the last.
    /// The last reached is sent; the board takes the ones below it as on.
    func testTheTiers() {
        XCTAssertEqual(Occasions.tiers.map(\.fromMs), [30_000, 60_000, 120_000, 300_000, 600_000])
        for (s, tag) in [(0, nil), (29, nil), (30, "tier1"), (59, "tier1"), (60, "tier2"), (119, "tier2"), (120, "tier3"),
                         (299, "tier3"), (300, "tier4"), (599, "tier4"), (600, "tier5"), (7200, "tier5")] as [(Int64, String?)] {
            XCTAssertEqual(Occasions.tier(after: s * 1000), tag, "\(s) s")
        }
        XCTAssertEqual(Occasions.stretchRestMs, 30_000, "a rest shorter than the first tier keeps a working stretch")
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
        XCTAssertEqual(tiers(), ["tier3"], "the stretch began with a's turn, 4 minutes ago")
        rig.wait(4 * 60_000)
        XCTAssertEqual(tiers(), ["tier4"])
        rig.send(.turnEnd, session: "a")
        XCTAssertEqual(tiers(), ["tier4"], "b works on in the same stretch")
        rig.wait(3 * 60_000)
        XCTAssertEqual(tiers(), ["tier5"], "11 minutes in")
        rig.send(.turnEnd, session: "b")
        XCTAssertEqual(tiers(), [], "just finished: it settles")
        rig.wait(30_000)
        XCTAssertEqual(tiers(), ["tier1"])
        rig.wait(90_000)
        XCTAssertEqual(tiers(), ["tier3"])
        rig.wait(480_000)
        XCTAssertEqual(tiers(), ["tier5"])
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "back to work, a new stretch")
    }

    /// Pins `Occasions.stretchRestMs`: a reply within 30 seconds of the
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
        XCTAssertEqual(tiers(), ["tier3"], "the stretch began 3.5 minutes ago")
        rig.wait(2 * 60_000)
        XCTAssertEqual(tiers(), ["tier4"])
        rig.send(.turnEnd, session: "a")
        rig.wait(30_000)
        XCTAssertEqual(tiers(), ["tier1"], "idle's")
        rig.send(.turnStart, session: "a")
        XCTAssertEqual(tiers(), [], "a new stretch")
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
        rig.note(Fx(rig.pipeline.agent(rig.event(.turnStart, prompt: "update the readme"), labels: .prompt(.init(kind: .docs)))))
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
