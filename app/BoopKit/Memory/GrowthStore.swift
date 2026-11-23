import Foundation
import MellowHarness

/// Boop's growth as it's kept: every XP it's earned, today's ring and its
/// day (Boop's, from 5:00) with what earned it, the last days' rings, the
/// days in a row with a full ring, the last event counted, the level last
/// celebrated and the day the ring last closed, as `xp.` keys in the
/// key-value store. It counts each event as it's logged, once: an
/// event at or before the last one counted is left alone. Touched only on
/// `home`.
public final class GrowthStore {
    public static let xpKey = "xp.total"
    public static let todayKey = "xp.today"
    public static let daysKey = "xp.days"
    public static let lastSeqKey = "xp.last_seq"
    public static let celebratedKey = "xp.celebrated"
    public static let ringKey = "xp.ring_closed"
    public static let todayByKey = "xp.today_by"
    public static let rowKey = "xp.row"
    /// A day with no full ring between two full ones keeps the days in a
    /// row going; three don't. So a weekend never breaks it.
    public static let graceDays = 2
    /// How many days' rings it keeps, today's included: the Boop tab's week.
    public static let keptDays = 7
    /// Days by their number, as a day is in UTC.
    static let utc = LocalTime(timeZone: TimeZone(identifier: "UTC")!)

    let store: KeyValueStore
    let log: (String) -> Void
    /// The XP and today's ring, as of the day last counted: `growth(on:)`
    /// gives the ring for another day.
    public private(set) var growth: Growth
    /// The Boop day today's ring is for, nil before the first XP.
    public private(set) var day: String?
    /// The rings of the days before `day`, newest first: `(day, xp)`.
    public private(set) var past: [(day: String, xp: Int)]
    /// The `seq` of the last event counted.
    public private(set) var lastSeq: Int
    /// The level last celebrated: a level past it is a level-up to play.
    public private(set) var celebrated: Int
    /// The Boop day whose ring closing was last celebrated.
    public private(set) var ringCelebrated: String?
    /// Today's XP by what earned it: how many, and their XP, after the limits.
    public private(set) var todayBy: [Growth.Source: Earned]
    /// The days in a row with a full ring, as of the last one: its count and day.
    public private(set) var row: (count: Int, day: String)?

    /// What one source earned in a day.
    public struct Earned: Equatable, Sendable {
        public var n: Int
        public var xp: Int
        public init(n: Int = 0, xp: Int = 0) { self.n = n; self.xp = xp }
    }

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
        let today = store.string(Self.todayKey)?.split(separator: " ")
        day = today?.first.map(String.init)
        todayBy = Self.readBy(store.string(Self.todayByKey))
        growth = Growth(xp: store.int(Self.xpKey) ?? 0, today: today?.dropFirst().first.flatMap { Int($0) } ?? 0,
                        care: todayBy[.care]?.xp ?? 0)
        past = (store.string(Self.daysKey) ?? "").split(separator: ",").compactMap {
            let p = $0.split(separator: " ")
            guard p.count == 2, let xp = Int(p[1]) else { return nil }
            return (String(p[0]), xp)
        }
        lastSeq = store.int(Self.lastSeqKey) ?? 0
        celebrated = store.int(Self.celebratedKey) ?? growth.level
        ringCelebrated = store.string(Self.ringKey)
        let r = store.string(Self.rowKey)?.split(separator: " ")
        if let r, r.count == 2, let n = Int(r[0]) { row = (n, String(r[1])) }
    }

    /// `turns 8 40,care 3 9` back to its sources.
    static func readBy(_ s: String?) -> [Growth.Source: Earned] {
        var by: [Growth.Source: Earned] = [:]
        for part in (s ?? "").split(separator: ",") {
            let p = part.split(separator: " ")
            guard p.count == 3, let source = Growth.Source(rawValue: String(p[0])), let n = Int(p[1]), let xp = Int(p[2]) else { continue }
            by[source] = Earned(n: n, xp: xp)
        }
        return by
    }

    /// What earned XP on Boop day `today`: none for another day.
    public func todayBy(on today: String) -> [Growth.Source: Earned] { day == today ? todayBy : [:] }

    /// The days in a row with a full ring, as they stand on Boop day
    /// `today`: 0 once more than `graceDays` days have no full ring.
    public func daysInARow(on today: String) -> Int {
        guard let row, let gap = Self.days(from: row.day, to: today) else { return 0 }
        return gap <= Self.graceDays + 1 ? row.count : 0
    }

    /// The days from `a` to `b`, Boop days as `yyyy-MM-dd`.
    static func days(from a: String, to b: String) -> Int? {
        guard let x = LocalTime.dayNumber(a), let y = LocalTime.dayNumber(b) else { return nil }
        return y - x
    }

    /// The growth as it stands on Boop day `today`: a ring of a day before
    /// it is empty now.
    public func growth(on today: String) -> Growth {
        day == today ? growth : Growth(xp: growth.xp)
    }

    /// The last `keptDays` days' rings up to `today`, oldest first, a day
    /// with none 0.
    public func week(to today: String) -> [(day: String, xp: Int)] {
        let known = Dictionary(([(day ?? "", growth.today)] + past).map { ($0.day, $0.xp) }, uniquingKeysWith: { a, _ in a })
        guard let n = LocalTime.dayNumber(today) else { return [] }
        return (0..<Self.keptDays).reversed().map { back in
            let day = Self.utc.day(Int64(n - back) * 86_400_000)
            return (day, known[day] ?? 0)
        }
    }

    /// The transcript's numbering starts again when every file of it is
    /// gone (two weeks without the app, or deleted by hand): counting
    /// carries on from its last event, so nothing new is skipped.
    public func follow(transcriptAt seq: Int) {
        guard seq < lastSeq else { return }
        log("growth: the transcript starts again at \(seq), past \(lastSeq); counting from there")
        lastSeq = seq
        save()
    }

    /// Counts `e`, which earns for `source` (nil for nothing), on Boop day
    /// `today`, and returns the XP it added: none past the day's limits,
    /// which writes nothing, as counting it again would add nothing either.
    @discardableResult
    public func count(_ e: Event, _ source: Growth.Source?, today: String) -> Int {
        guard e.seq > lastSeq, let source else { return 0 }
        lastSeq = e.seq
        // A day only moves on: a clock set back, or a flight west across
        // 5:00, counts on the day it's on, not a fresh ring of an old one.
        if day.map({ today > $0 }) ?? true {
            if let day { past = Array(([(day, growth.today)] + past).prefix(Self.keptDays - 1)) }
            day = today
            growth = Growth(xp: growth.xp)
            todayBy = [:]
        }
        let added = growth.adds(source)
        guard added > 0 else { return 0 }
        let wasClosed = growth.ringClosed
        growth = growth.adding(added, from: source)
        todayBy[source, default: Earned()].n += 1
        todayBy[source, default: Earned()].xp += added
        if growth.ringClosed, !wasClosed {
            let before = daysInARow(on: today)
            row = (before + 1, today)
        }
        save()
        return added
    }

    /// A level reached and not yet celebrated, or nil.
    public var levelDue: Int? { growth.level > celebrated ? growth.level : nil }
    /// Whether the ring of Boop day `today` has closed and its moment
    /// hasn't played: one held past 5:00 is yesterday's, and isn't.
    public func ringDue(today: String) -> Bool { growth.ringClosed && day == today && ringCelebrated != day }

    /// What's due to play on Boop day `today`: a level-up, and the ring closing.
    public func due(today: String) -> [Core.GrowthBeat] {
        (levelDue.map { [.level($0)] } ?? [])
            + (ringDue(today: today) ? [.ringClosed] : [])
    }

    /// `e`, logged, is a growth moment going to the board: its level, or the
    /// ring's closing, is celebrated, and isn't again, unless the board
    /// says it never showed it (`missed`). Marked only as it's sent, so a
    /// quit before then, or a demo, loses nothing. True if it marked one.
    @discardableResult
    public func played(_ e: Event) -> Bool {
        guard e.type == .growth else { return false }
        var marked = false
        if let level = e["level"]?.int.map(Int.init), level > celebrated {
            celebrated = level
            log("growth: level \(level), at \(growth.xp) XP")
            marked = true
        }
        if e["ring"]?.bool == true, ringCelebrated != day {
            ringCelebrated = day
            marked = true
        }
        if marked { save() }
        return marked
    }

    /// The board never showed the moment of `events` (`played` marked them):
    /// each is due again, for the board's next hello or the next XP.
    public func missed(_ events: [Event]) {
        for e in events where e.type == .growth {
            if let level = e["level"]?.int.map(Int.init), level <= celebrated { celebrated = level - 1 }
            if e["ring"]?.bool == true, ringCelebrated == day {
                ringCelebrated = nil
                try? store.remove([Self.ringKey])
            }
        }
        save()
    }

    func save() {
        do {
            var values = [Self.xpKey: String(growth.xp), Self.lastSeqKey: String(lastSeq), Self.celebratedKey: String(celebrated),
                          Self.daysKey: past.map { "\($0.day) \($0.xp)" }.joined(separator: ",")]
            if let day { values[Self.todayKey] = "\(day) \(growth.today)" }
            values[Self.todayByKey] = Growth.Source.allCases.compactMap { s in todayBy[s].map { "\(s.rawValue) \($0.n) \($0.xp)" } }
                .joined(separator: ",")
            if let row { values[Self.rowKey] = "\(row.count) \(row.day)" }
            if let ringCelebrated { values[Self.ringKey] = ringCelebrated }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
