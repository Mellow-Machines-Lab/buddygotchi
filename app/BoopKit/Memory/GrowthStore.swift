import Foundation
import MellowHarness

/// Boop's growth as it's kept: every XP it's earned, today's ring and its
/// day (Boop's, from 5:00), the last days' rings, the last event counted,
/// the level last celebrated and the day the ring last closed, as `xp.` keys
/// in the key-value store. It counts each event as it's logged, once: an
/// event at or before the last one counted is left alone. Touched only on
/// `home`.
public final class GrowthStore {
    public static let xpKey = "xp.total"
    public static let todayKey = "xp.today"
    public static let daysKey = "xp.days"
    public static let lastSeqKey = "xp.last_seq"
    public static let celebratedKey = "xp.celebrated"
    public static let ringKey = "xp.ring_closed"
    /// What growth kept before XP was kept simple: gone at the first launch,
    /// so XP starts from zero.
    public static let oldKeys = ["growth.xp", "growth.stage", "growth.last_seq", "growth.reached", "growth.earned",
                                 "growth.decayed", "growth.shrank"]
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

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
        if Self.oldKeys.contains(where: { store.string($0) != nil }) {
            do { try store.remove(Self.oldKeys) } catch { log("growth: can't forget the old XP: \(error)") }
        }
        let today = store.string(Self.todayKey)?.split(separator: " ")
        day = today?.first.map(String.init)
        growth = Growth(xp: store.int(Self.xpKey) ?? 0, today: today?.dropFirst().first.flatMap { Int($0) } ?? 0)
        past = (store.string(Self.daysKey) ?? "").split(separator: ",").compactMap {
            let p = $0.split(separator: " ")
            guard p.count == 2, let xp = Int(p[1]) else { return nil }
            return (String(p[0]), xp)
        }
        lastSeq = store.int(Self.lastSeqKey) ?? 0
        celebrated = store.int(Self.celebratedKey) ?? growth.level
        ringCelebrated = store.string(Self.ringKey)
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

    /// Counts `e`, which earns `xp` before the day's cap, on Boop day
    /// `today`, and returns the XP it added: none past the day's ring, which
    /// writes nothing, as counting it again would add nothing either.
    @discardableResult
    public func count(_ e: Event, xp: Int, today: String) -> Int {
        guard e.seq > lastSeq, xp > 0 else { return 0 }
        lastSeq = e.seq
        // A day only moves on: a clock set back, or a flight west across
        // 5:00, counts on the day it's on, not a fresh ring of an old one.
        if day.map({ today > $0 }) ?? true {
            if let day { past = Array(([(day, growth.today)] + past).prefix(Self.keptDays - 1)) }
            day = today
            growth.today = 0
        }
        let added = Growth.capped(xp, today: growth.today)
        guard added > 0 else { return 0 }
        growth = Growth(xp: growth.xp + added, today: growth.today + added)
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
        switch e.type {
        case .level?:
            guard let level = Int(e.specificType), level > celebrated else { return false }
            celebrated = level
            log("growth: level \(level), at \(growth.xp) XP")
        case .ring?:
            guard ringCelebrated != day else { return false }
            ringCelebrated = day
        default: return false
        }
        save()
        return true
    }

    /// The board never showed the moment of `events` (`played` marked them):
    /// each is due again, for the board's next hello or the next XP.
    public func missed(_ events: [Event]) {
        for e in events {
            switch e.type {
            case .level?:
                if let level = Int(e.specificType), level <= celebrated { celebrated = level - 1 }
            case .ring?:
                if ringCelebrated == day {
                    ringCelebrated = nil
                    try? store.remove([Self.ringKey])
                }
            default: break
            }
        }
        save()
    }

    func save() {
        do {
            var values = [Self.xpKey: String(growth.xp), Self.lastSeqKey: String(lastSeq), Self.celebratedKey: String(celebrated),
                          Self.daysKey: past.map { "\($0.day) \($0.xp)" }.joined(separator: ",")]
            if let day { values[Self.todayKey] = "\(day) \(growth.today)" }
            if let ringCelebrated { values[Self.ringKey] = ringCelebrated }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
