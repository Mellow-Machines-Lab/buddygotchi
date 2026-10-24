import Foundation

/// Local calendar maths: the core's days, and the time of day and weekday
/// Jev's state shows. Times are milliseconds since 1970.
public struct LocalTime: Sendable {
    public var timeZone: TimeZone
    private var calendar: Calendar
    private var chinese: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = timeZone
        self.chinese = chinese
    }

    func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// `2026-10-14`.
    public func day(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date(ms))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The day at `ms`, from its first millisecond to the next day's.
    public func dayRange(_ ms: Int64) -> Range<Int64> {
        guard let i = calendar.dateInterval(of: .day, for: date(ms)) else { return ms..<ms + 1 }
        return Int64(i.start.timeIntervalSince1970 * 1000)..<Int64(i.end.timeIntervalSince1970 * 1000)
    }

    /// Whether `s` is a `yyyy-MM-dd` that names a real day.
    public static func isDay(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard s.count == 10, p.count == 3, let y = p[0], let m = p[1], let d = p[2], (1...12).contains(m),
              String(format: "%04d-%02d-%02d", y, m, d) == s else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d)
    }

    struct Parts {
        var month: Int, day: Int, hour: Int, weekday: Int, dayOfYear: Int
    }

    /// The month, day, hour, weekday (1 Sunday … 7 Saturday) and day of the
    /// year at `ms`.
    func components(_ ms: Int64) -> Parts {
        let d = date(ms)
        let c = calendar.dateComponents([.month, .day, .hour, .weekday], from: d)
        return Parts(month: c.month ?? 1, day: c.day ?? 1, hour: c.hour ?? 0, weekday: c.weekday ?? 1,
                     dayOfYear: calendar.ordinality(of: .day, in: .year, for: d) ?? 1)
    }

    /// Whole days from the day `from` (`yyyy-MM-dd`) to the day at `ms`.
    public func days(from day: String, to ms: Int64) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date(ms))
        guard let y = c.year, let m = c.month, let d = c.day, let from = Self.dayNumber(day) else { return 0 }
        return Self.dayNumber(y, m, d) - from
    }

    /// Days since 1970-01-01 of a `yyyy-MM-dd`.
    static func dayNumber(_ day: String) -> Int? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? dayNumber(p[0], p[1], p[2]) : nil
    }

    /// `day` as a person says it on `today` (both `yyyy-MM-dd`): Today,
    /// Yesterday, its weekday up to six days back, where a weekday can only
    /// mean one day, and `Oct 14` before that.
    public static func spoken(_ day: String, today: String) -> String {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard isDay(day), let now = dayNumber(today) else { return day }
        return switch now - dayNumber(p[0], p[1], p[2]) {
        case 0: "Today"
        case 1: "Yesterday"
        case 2...6: weekday(of: day) ?? day
        default: "\(months[p[1] - 1]) \(p[2])"
        }
    }

    /// `day`'s weekday (`yyyy-MM-dd`), as `weekday(_:)` names it:
    /// 1970-01-01 was a Thursday.
    static func weekday(of day: String) -> String? {
        dayNumber(day).map { weekdays[($0 % 7 + 11) % 7] }
    }

    /// Days since 1970-01-01 of a day on the proleptic Gregorian calendar.
    static func dayNumber(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        return era * 146_097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719_468
    }

    /// Whether `ms` falls on the first day of the Chinese calendar's first
    /// month: Lunar New Year.
    func isLunarNewYear(_ ms: Int64) -> Bool {
        let c = chinese.dateComponents([.month, .day, .isLeapMonth], from: date(ms))
        return c.month == 1 && c.day == 1 && c.isLeapMonth != true
    }

    /// `14:05`.
    public func clock(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date(ms))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `Tuesday`.
    public func weekday(_ ms: Int64) -> String {
        let index = calendar.component(.weekday, from: date(ms)) - 1
        return Self.weekdays[max(0, min(6, index))]
    }

    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

/// A small seeded generator, so rule timings are repeatable in tests.
public struct SplitMix64: Sendable {
    var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in `range`.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }

    public mutating func chance(_ percent: Int) -> Bool { int(in: 0...99) < percent }
}
