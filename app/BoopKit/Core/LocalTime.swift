import Foundation

/// Local calendar maths: the core's days, and the time of day and weekday
/// Jev's state shows. Times are milliseconds since 1970.
public struct LocalTime: Sendable {
    public var timeZone: TimeZone
    private var calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    func date(_ ms: Int64) -> Date { Date(timeIntervalSince1970: Double(ms) / 1000) }

    /// `2026-10-14`.
    public func day(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date(ms))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Whether `s` is a `yyyy-MM-dd` that names a real day.
    public static func isDay(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
        guard s.count == 10, p.count == 3, let y = p[0], let m = p[1], let d = p[2], (1...12).contains(m),
              String(format: "%04d-%02d-%02d", y, m, d) == s else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return (1...[31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]).contains(d)
    }

    /// `14:05`.
    public func clock(_ ms: Int64) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date(ms))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// `Tuesday`.
    public func weekday(_ ms: Int64) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let index = calendar.component(.weekday, from: date(ms)) - 1
        return names[max(0, min(6, index))]
    }
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
