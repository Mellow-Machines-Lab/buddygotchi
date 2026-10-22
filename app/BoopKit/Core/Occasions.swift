import Foundation

/// What's true now, as tags: the part of the day, the weekday, a holiday, a
/// milestone day since Boop hatched. The core sends them in the `state`
/// message (`when`), and the board shows only the designs whose tags are
/// all on (characters/CHARACTER.md §9). The board adds `busy` and
/// `frantic` itself, from the `state` message's count of sessions working.
/// The prompt's heading says the calendar's in words, so the brain can
/// play along. The firmware's list is the same, in the same order
/// (firmware/src/render/tags.h).
public enum Occasions {
    /// Every tag, in the firmware's order.
    public static let all = ["morning", "day", "evening", "night", "friday", "weekend", "friday13",
                             "newyear", "valentines", "piday", "aprilfools", "may4", "halloween", "winter",
                             "programmers", "lunar", "party", "busy", "frantic"]

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
