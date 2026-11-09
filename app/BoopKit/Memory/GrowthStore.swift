import Foundation
import MellowHarness

/// Boop's growth as it's kept: every XP it's earned, today's ring and its
/// day (Boop's, from 5:00), the last days' rings, the last event counted and
/// the level last celebrated, as `growth.` keys in the key-value store. It
/// counts each event as it's logged, once: an event at or before the last
/// one counted is left alone. Touched only on `home`.
public final class GrowthStore {
    public static let xpKey = "growth.xp"
    public static let todayKey = "growth.today"
    public static let daysKey = "growth.days"
    public static let lastSeqKey = "growth.last_seq"
    public static let celebratedKey = "growth.celebrated"
    /// How many days' rings it keeps, today's included: the Boop tab's week.
    public static let keptDays = 7

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

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
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
        return (0..<Self.keptDays).reversed().compactMap { back in
            LocalTime.day(number: n - back).map { ($0, known[$0] ?? 0) }
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
    /// `today`, and returns the XP it added: none past the day's ring.
    @discardableResult
    public func count(_ e: Event, xp: Int, today: String) -> Int {
        guard e.seq > lastSeq, xp > 0 else { return 0 }
        lastSeq = e.seq
        if day != today, let day {
            past = Array(([(day, growth.today)] + past).prefix(Self.keptDays - 1))
        }
        if day != today { growth.today = 0 }
        day = today
        let added = Growth.capped(xp, today: growth.today)
        growth = Growth(xp: growth.xp + added, today: growth.today + added)
        save()
        return added
    }

    /// Marks the level now celebrated, so it isn't again.
    public func celebrate() {
        guard celebrated != growth.level else { return }
        celebrated = growth.level
        log("growth: level \(celebrated), at \(growth.xp) XP")
        save()
    }

    func save() {
        do {
            var values = [Self.xpKey: String(growth.xp), Self.lastSeqKey: String(lastSeq), Self.celebratedKey: String(celebrated),
                          Self.daysKey: past.map { "\($0.day) \($0.xp)" }.joined(separator: ",")]
            if let day { values[Self.todayKey] = "\(day) \(growth.today)" }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
