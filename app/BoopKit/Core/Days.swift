import Foundation

/// What day it is: the part of the day, the weekday, the holidays, and
/// Boop's own special days (a milestone since it hatched, its
/// anniversary, a growth stage reached). Their tags go to the board with
/// the others (`Tags`), and CONTEXT's When row says them in words, so the
/// brain can play along.
public enum Days {
    /// The calendar's tags, the ones `tags(at:)` gives: the part of the
    /// day, the weekday, the holidays and a party.
    public static let calendarTags = dayParts.map(\.tag) + ["friday", "weekend", "friday13"] + holidays.map(\.tag)
        + ["programmers", "lunar", "party"]

    /// The parts of the day, by the hour they start: morning from 5, day
    /// from 11, evening from 17, night from 22 until 5.
    public static let dayParts: [(tag: String, from: Int)] = [("morning", 5), ("day", 11), ("evening", 17), ("night", 22)]

    /// The part of the day at `ms`: `morning`, `day`, `evening` or `night`.
    public static func dayPart(at ms: Int64, time: LocalTime) -> String {
        let hour = time.components(ms).hour
        return dayParts.last { hour >= $0.from }?.tag ?? "night"
    }

    /// The fixed holidays, by month and day, each with its words and its
    /// sign.
    static let holidays: [(tag: String, month: Int, days: ClosedRange<Int>, words: String, sign: String)] = [
        ("newyear", 1, 1...1, "New Year's Day", "Happy New Year!"), ("valentines", 2, 14...14, "Valentine's Day", "Happy Valentine's"),
        ("piday", 3, 14...14, "Pi Day", "Happy Pi Day!"), ("aprilfools", 4, 1...1, "April Fools' Day", "April Fools'!"),
        ("may4", 5, 4...4, "May the 4th", "May the 4th!"), ("halloween", 10, 31...31, "Halloween", "Happy Halloween!"),
        ("winter", 12, 24...26, "the winter holidays", "Happy holidays!"),
    ]

    /// One special day today: its calendar tag (nil for one of Boop's own
    /// days, each a party), its words for CONTEXT's When row, and the
    /// sign Boop holds up for it, at most `Signs.maxLength` characters.
    public struct SpecialDay: Equatable, Sendable {
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

    /// The calendar's own special days at `ms`: Friday the 13th, the
    /// holidays, Programmers' Day and Lunar New Year.
    static func calendar(_ c: LocalTime.Parts, at ms: Int64, time: LocalTime) -> [SpecialDay] {
        var on: [SpecialDay] = []
        if c.weekday == 6, c.day == 13 { on.append(SpecialDay(tag: "friday13", words: "Friday the 13th", sign: "Friday the 13th!")) }
        for h in holidays where h.month == c.month && h.days.contains(c.day) {
            on.append(SpecialDay(tag: h.tag, words: h.words, sign: h.sign))
        }
        if c.dayOfYear == 256 { on.append(SpecialDay(tag: "programmers", words: "Programmers' Day", sign: "Programmers' Day!")) }
        if time.isLunarNewYear(ms) { on.append(SpecialDay(tag: "lunar", words: "Lunar New Year", sign: "Lunar New Year!")) }
        return on
    }

    /// The calendar's tags on at `ms`: `hatched` is the day Boop was set up
    /// (`yyyy-MM-dd`), and `party` any other reason for one (a stage
    /// reached today), which the day Boop hatched isn't: that's your first
    /// day with it, and only New Year's Day makes it a party.
    public static func tags(at ms: Int64, hatched: String?, party: Bool = false, time: LocalTime) -> [String] {
        let c = time.components(ms), today = time.day(ms)
        var on = [dayPart(at: ms, time: time)]
        if c.weekday == 6 { on.append("friday") }
        if c.weekday == 7 || c.weekday == 1 { on.append("weekend") }
        on += calendar(c, at: ms, time: time).compactMap(\.tag)
        let party = party && hatched != today
        if party || on.contains("newyear") || hatched.map({ isMilestone(days: time.days(from: $0, to: ms), hatched: $0, today: today) }) == true {
            on.append("party")
        }
        return Tags.all.filter(on.contains)
    }

    /// Today's special days at `ms`: the calendar's, then Boop's own days, its
    /// anniversary or a milestone day since it hatched (`hatched`), then
    /// the growth stage it reached today (`stage`), unless it hatched today
    /// too: your first day with it is no celebration. Empty on an ordinary
    /// day.
    public static func special(at ms: Int64, hatched: String?, name: String, stage: (name: String, day: String)? = nil,
                                 time: LocalTime) -> [SpecialDay] {
        var out = calendar(time.components(ms), at: ms, time: time)
        let today = time.day(ms)
        if let hatched {
            let days = time.days(from: hatched, to: ms)
            if days > 0, hatched.dropFirst(5) == today.dropFirst(5) {
                let years = Int(today.prefix(4))! - Int(hatched.prefix(4))!
                out.append(SpecialDay(words: "\(name)'s \(years == 1 ? "first" : "\(years)-year") anniversary",
                                    sign: years == 1 ? "1 year old!" : "\(years) years old!"))
            } else if isMilestone(days: days, hatched: hatched, today: today) {
                out.append(SpecialDay(words: "\(name) is \(days) days old", sign: "Day \(days)!"))
            }
        }
        if let stage, stage.day == today, hatched != today { out.append(SpecialDay(words: "\(name) became a \(stage.name)", sign: "I'm a \(stage.name)!")) }
        return out
    }

    /// The calendar's tags in words, for CONTEXT's When row: `Halloween`,
    /// `Boop is 50 days old`, `Boop became a Sprout` on the day `stage`
    /// was reached. Empty on an ordinary day.
    public static func words(at ms: Int64, hatched: String?, name: String, stage: (name: String, day: String)? = nil,
                             time: LocalTime) -> [String] {
        special(at: ms, hatched: hatched, name: name, stage: stage, time: time).map(\.words)
    }

    /// The sign Boop greets a day of `days` with: the one most its
    /// own, the last (a stage reached before a milestone before the
    /// calendar's).
    public static func greeting(_ days: [SpecialDay]) -> String? { days.last?.sign }
}
