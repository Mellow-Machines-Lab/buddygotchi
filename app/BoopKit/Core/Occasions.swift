import Foundation

/// What's true now, as tags: the part of the day, the weekday, a holiday, a
/// milestone day since Boop hatched, how long the agents have worked or
/// sat idle, Boop's growth stage, and whether the latest turn's prompt was
/// an essay or for docs. The core sends them in the `state`
/// message (`when`), and the board shows only the designs whose tags are
/// all on (characters/CHARACTER.md §9). The board adds `busy` and
/// `frantic` itself, from the `state` message's count of sessions working.
/// The prompt's heading says the calendar's in words, so the brain can
/// play along. The firmware's list is the same, in the same order
/// (firmware/src/render/tags.h).
public enum Occasions {
    /// Every tag, in the firmware's order: the calendar's, the board's own
    /// two for how busy the agents are, the tiers, the stages, then the
    /// latest turn's `reading`.
    public static let all = calendarTags + ["busy", "frantic"] + tiers.map(\.tag) + stageTags + [reading]

    /// On while the latest turn you prompted lasts, when its prompt's
    /// reading `reads`: the board's reading glasses.
    public static let reading = "reading"
    /// Whether a prompt's reading puts `reading` on for its turn: you wrote
    /// an essay of a prompt, or asked for docs.
    public static func reads(_ prompt: PromptReading) -> Bool { prompt.length == .essay || prompt.kind == .docs }

    /// The calendar's tags, the ones `tags(at:)` gives: the part of the
    /// day, the weekday, the holidays and a party.
    public static let calendarTags = dayParts.map(\.tag) + ["friday", "weekend", "friday13"] + holidays.map(\.tag)
        + ["programmers", "lunar", "party"]

    /// The tiers, by how long the agents have worked (their working
    /// stretch, `Core.stretch`) or sat idle (since the latest session came
    /// to rest: a turn ended, or you dismissed a request): `tier1` from 30
    /// seconds, `tier2` from a minute, `tier3` from 2, `tier4` from 5 and
    /// `tier5` from 10, the last, where it stays. Working and idle share
    /// them, as a design's look says which it's for. Before 30 seconds the
    /// looks need no tag.
    public static let tiers: [(tag: String, fromMs: Int64)] = [
        ("tier1", 30_000), ("tier2", 60_000), ("tier3", 120_000), ("tier4", 300_000), ("tier5", 600_000),
    ]

    /// The tier reached after `ms`, the last. Only it is sent, to keep the
    /// `state` line short: the board takes every tier below it as on too
    /// (`render::reached`), so a design for `tier2` shows from then on.
    public static func tier(after ms: Int64) -> String? {
        tiers.last { ms >= $0.fromMs }?.tag
    }

    /// A rest shorter than the first tier doesn't end a working stretch:
    /// a quick reply between turns keeps the working tiers climbing.
    public static let stretchRestMs = tiers[0].fromMs

    /// The growth stages' tags from the second on, in `Growth.stages`'
    /// order. Every stage reached is on, so a design that needs `pal` shows
    /// at Pal and every stage after it.
    public static let stageTags = Growth.stages.dropFirst().map { $0.name.lowercased() }

    /// The tags on at growth stage `stage` (from 1, a Hatchling's: none).
    public static func stages(_ stage: Int) -> [String] { Array(stageTags.prefix(max(0, stage - 1))) }

    /// The parts of the day, by the hour they start: morning from 5, day
    /// from 11, evening from 17, night from 22 until 5.
    public static let dayParts: [(tag: String, from: Int)] = [("morning", 5), ("day", 11), ("evening", 17), ("night", 22)]

    /// The fixed holidays, by month and day, each with its words and its
    /// sign.
    static let holidays: [(tag: String, month: Int, days: ClosedRange<Int>, words: String, sign: String)] = [
        ("newyear", 1, 1...1, "New Year's Day", "Happy New Year!"), ("valentines", 2, 14...14, "Valentine's Day", "Happy Valentine's"),
        ("piday", 3, 14...14, "Pi Day", "Happy Pi Day!"), ("aprilfools", 4, 1...1, "April Fools' Day", "April Fools'!"),
        ("may4", 5, 4...4, "May the 4th", "May the 4th!"), ("halloween", 10, 31...31, "Halloween", "Happy Halloween!"),
        ("winter", 12, 24...26, "the winter holidays", "Happy holidays!"),
    ]

    /// One occasion today: its calendar tag (nil for one of Boop's own
    /// days, each a party), its words for the prompt's heading, and the
    /// sign Boop holds up for it, at most `Signs.maxLength` characters.
    public struct Occasion: Equatable, Sendable {
        public var tag: String? = nil
        public var words: String
        public var sign: String

        /// Why it's on, as the popover says it: `It's Halloween`, `Boop is
        /// 50 days old today`.
        public var why: String { tag == nil ? words + " today" : "It's " + words }
    }

    /// The days since hatching that are a party: the 10th and 50th, then
    /// every 100th, and each anniversary.
    public static func isMilestone(days: Int, hatched: String, today: String) -> Bool {
        if days == 10 || days == 50 || (days > 0 && days % 100 == 0) { return true }
        return days > 0 && hatched.dropFirst(5) == today.dropFirst(5)
    }

    /// The calendar's own occasions at `ms`: Friday the 13th, the
    /// holidays, Programmers' Day and Lunar New Year.
    static func calendar(_ c: LocalTime.Parts, at ms: Int64, time: LocalTime) -> [Occasion] {
        var on: [Occasion] = []
        if c.weekday == 6, c.day == 13 { on.append(Occasion(tag: "friday13", words: "Friday the 13th", sign: "Friday the 13th!")) }
        for h in holidays where h.month == c.month && h.days.contains(c.day) {
            on.append(Occasion(tag: h.tag, words: h.words, sign: h.sign))
        }
        if c.dayOfYear == 256 { on.append(Occasion(tag: "programmers", words: "Programmers' Day", sign: "Programmers' Day!")) }
        if time.isLunarNewYear(ms) { on.append(Occasion(tag: "lunar", words: "Lunar New Year", sign: "Lunar New Year!")) }
        return on
    }

    /// The calendar's tags on at `ms`: `hatched` is the day Boop was set up
    /// (`yyyy-MM-dd`), and `party` any other reason for one (a stage
    /// reached today), which the day Boop hatched isn't: that's your first
    /// day with it, and only New Year's Day makes it a party.
    public static func tags(at ms: Int64, hatched: String?, party: Bool = false, time: LocalTime) -> [String] {
        let c = time.components(ms), today = time.day(ms)
        var on = [dayParts.last { c.hour >= $0.from }?.tag ?? "night"]
        if c.weekday == 6 { on.append("friday") }
        if c.weekday == 7 || c.weekday == 1 { on.append("weekend") }
        on += calendar(c, at: ms, time: time).compactMap(\.tag)
        let party = party && hatched != today
        if party || on.contains("newyear") || hatched.map({ isMilestone(days: time.days(from: $0, to: ms), hatched: $0, today: today) }) == true {
            on.append("party")
        }
        return all.filter(on.contains)
    }

    /// Today's occasions at `ms`: the calendar's, then Boop's own days, its
    /// anniversary or a milestone day since it hatched (`hatched`), then
    /// the growth stage it reached today (`stage`), unless it hatched today
    /// too: your first day with it is no celebration. Empty on an ordinary
    /// day.
    public static func occasions(at ms: Int64, hatched: String?, name: String, stage: (name: String, day: String)? = nil,
                                 time: LocalTime) -> [Occasion] {
        var out = calendar(time.components(ms), at: ms, time: time)
        let today = time.day(ms)
        if let hatched {
            let days = time.days(from: hatched, to: ms)
            if days > 0, hatched.dropFirst(5) == today.dropFirst(5) {
                let years = Int(today.prefix(4))! - Int(hatched.prefix(4))!
                out.append(Occasion(words: "\(name)'s \(years == 1 ? "first" : "\(years)-year") anniversary",
                                    sign: years == 1 ? "1 year old!" : "\(years) years old!"))
            } else if isMilestone(days: days, hatched: hatched, today: today) {
                out.append(Occasion(words: "\(name) is \(days) days old", sign: "Day \(days)!"))
            }
        }
        if let stage, stage.day == today, hatched != today { out.append(Occasion(words: "\(name) became a \(stage.name)", sign: "I'm a \(stage.name)!")) }
        return out
    }

    /// The calendar's tags in words, for the prompt's heading: `Halloween`,
    /// `Boop is 50 days old`, `Boop became a Sprout` on the day `stage`
    /// was reached. Empty on an ordinary day.
    public static func words(at ms: Int64, hatched: String?, name: String, stage: (name: String, day: String)? = nil,
                             time: LocalTime) -> [String] {
        occasions(at: ms, hatched: hatched, name: name, stage: stage, time: time).map(\.words)
    }

    /// The sign Boop greets a day of `occasions` with: the one most its
    /// own, the last (a stage reached before a milestone before the
    /// calendar's).
    public static func greeting(_ occasions: [Occasion]) -> String? { occasions.last?.sign }
}
