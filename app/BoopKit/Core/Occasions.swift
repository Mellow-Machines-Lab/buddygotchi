import Foundation

/// What's true now, as tags: the part of the day, the weekday, a holiday, a
/// milestone day since Boop hatched, how long the agents have worked or
/// sat idle, and Boop's growth stage. The core sends them in the `state`
/// message (`when`), and the board shows only the designs whose tags are
/// all on (characters/CHARACTER.md §9). The board adds `busy` and
/// `frantic` itself, from the `state` message's count of sessions working.
/// The prompt's heading says the calendar's in words, so the brain can
/// play along. The firmware's list is the same, in the same order
/// (firmware/src/render/tags.h).
public enum Occasions {
    /// Every tag, in the firmware's order: the calendar's, the board's own
    /// two for how busy the agents are, the tiers, then the stages.
    public static let all = dayParts.map(\.tag) + ["friday", "weekend", "friday13"] + holidays.map(\.tag)
        + ["programmers", "lunar", "party"] + ["busy", "frantic"] + workTiers.map(\.tag) + idleTiers.map(\.tag)
        + stageTags

    /// A long turn's tiers, by how long the longest turn working now has
    /// run: a marathon from 8 minutes, then a camp from 15, the last. Before
    /// 8 minutes the working looks need no tag.
    public static let workTiers: [(tag: String, fromMs: Int64)] = [("marathon", 8 * 60_000), ("camp", 15 * 60_000)]
    /// Idle's tiers, by how long since the last turn ended: fidgets from
    /// 30 seconds, set pieces from 3 minutes, dozing from 10. Before 30
    /// seconds Boop settles with no tag.
    public static let idleTiers: [(tag: String, fromMs: Int64)] = [("fidget", 30_000), ("setpiece", 180_000), ("doze", 600_000)]

    /// The tier on after `ms` in `tiers`: one at a time, the last reached.
    public static func tier(_ tiers: [(tag: String, fromMs: Int64)], after ms: Int64) -> String? {
        tiers.last { ms >= $0.fromMs }?.tag
    }

    /// The growth stages' tags from the second on, in `Growth.stages`'
    /// order. Every stage reached is on, so a design that needs `pal` shows
    /// at Pal and every stage after it.
    public static let stageTags = Growth.stages.dropFirst().map { $0.name.lowercased() }

    /// The tags on at growth stage `stage` (from 1, a Hatchling's: none).
    public static func stages(_ stage: Int) -> [String] { Array(stageTags.prefix(max(0, stage - 1))) }

    /// The parts of the day, by the hour they start: morning from 5, day
    /// from 11, evening from 17, night from 22 until 5.
    public static let dayParts: [(tag: String, from: Int)] = [("morning", 5), ("day", 11), ("evening", 17), ("night", 22)]

    /// The fixed holidays, by month and day.
    static let holidays: [(tag: String, month: Int, days: ClosedRange<Int>, words: String)] = [
        ("newyear", 1, 1...1, "New Year's Day"), ("valentines", 2, 14...14, "Valentine's Day"), ("piday", 3, 14...14, "Pi Day"),
        ("aprilfools", 4, 1...1, "April Fools' Day"), ("may4", 5, 4...4, "May the 4th"), ("halloween", 10, 31...31, "Halloween"),
        ("winter", 12, 24...26, "the winter holidays"),
    ]

    /// The days since hatching that are a party: the 10th and 50th, then
    /// every 100th, and each anniversary.
    public static func isMilestone(days: Int, hatched: String, today: String) -> Bool {
        if days == 10 || days == 50 || (days > 0 && days % 100 == 0) { return true }
        return days > 0 && hatched.dropFirst(5) == today.dropFirst(5)
    }

    /// The calendar's own occasions at `ms`, each with its words for the
    /// heading: Friday the 13th, the holidays, Programmers' Day and Lunar
    /// New Year.
    static func calendar(_ c: LocalTime.Parts, at ms: Int64, time: LocalTime) -> [(tag: String, words: String)] {
        var on: [(tag: String, words: String)] = []
        if c.weekday == 6, c.day == 13 { on.append(("friday13", "Friday the 13th")) }
        for h in holidays where h.month == c.month && h.days.contains(c.day) { on.append((h.tag, h.words)) }
        if c.dayOfYear == 256 { on.append(("programmers", "Programmers' Day")) }
        if time.isLunarNewYear(ms) { on.append(("lunar", "Lunar New Year")) }
        return on
    }

    /// The calendar's tags on at `ms`: `hatched` is the day Boop was set up
    /// (`yyyy-MM-dd`), and `party` any other reason for one (a stage
    /// reached today).
    public static func tags(at ms: Int64, hatched: String?, party: Bool = false, time: LocalTime) -> [String] {
        let c = time.components(ms)
        var on = [dayParts.last { c.hour >= $0.from }?.tag ?? "night"]
        if c.weekday == 6 { on.append("friday") }
        if c.weekday == 7 || c.weekday == 1 { on.append("weekend") }
        on += calendar(c, at: ms, time: time).map(\.tag)
        if party || on.contains("newyear") || hatched.map({ isMilestone(days: time.days(from: $0, to: ms), hatched: $0, today: time.day(ms)) }) == true {
            on.append("party")
        }
        return all.filter(on.contains)
    }

    /// The calendar's tags in words, for the prompt's heading: `Halloween`,
    /// `Boop is 50 days old`, `Boop became a Sprout` on the day `stage`
    /// was reached. Empty on an ordinary day.
    public static func words(at ms: Int64, hatched: String?, name: String, stage: (name: String, day: String)? = nil,
                             time: LocalTime) -> [String] {
        var out = calendar(time.components(ms), at: ms, time: time).map(\.words)
        let today = time.day(ms)
        if let hatched {
            let days = time.days(from: hatched, to: ms)
            if days > 0, hatched.dropFirst(5) == today.dropFirst(5) {
                let years = Int(today.prefix(4))! - Int(hatched.prefix(4))!
                out.append("\(name)'s \(years == 1 ? "first" : "\(years)-year") anniversary")
            } else if isMilestone(days: days, hatched: hatched, today: today) {
                out.append("\(name) is \(days) days old")
            }
        }
        if let stage, stage.day == today { out.append("\(name) became a \(stage.name)") }
        return out
    }
}
