import Foundation
import MellowHarness

/// Boop's growth as it's kept: XP, the day a stage was reached, the last
/// event counted, the last day it earned and how it's gone backwards since,
/// as `growth.` keys in the key-value store. It counts each event as it's logged, once: an event at or before
/// the last one counted is left alone. What an event earns within the
/// day's caps is the memory reader's to say (`MemoryReader.earned`), which
/// keeps the day's totals. Touched only on `home`.
public final class GrowthStore {
    public static let xpKey = "growth.xp"
    public static let lastSeqKey = "growth.last_seq"
    public static let reachedKey = "growth.reached"
    public static let earnedKey = "growth.earned"
    public static let decayedKey = "growth.decayed"
    public static let shrankKey = "growth.shrank"
    /// The stage as it was saved when there were six and it never went back:
    /// read once, by `init`, and gone from then on.
    public static let oldStageKey = "growth.stage"

    let store: KeyValueStore
    let log: (String) -> Void
    public private(set) var growth: Growth
    /// The `seq` of the last event counted.
    public private(set) var lastSeq: Int
    /// The day (`yyyy-MM-dd`) the stage was reached, nil for the first.
    public private(set) var reachedDay: String?
    /// The last day it earned XP, and the days it's gone backwards since.
    public private(set) var earnedDay: String?
    public private(set) var decayedDays: Int
    /// The last time going backwards cost it a stage: the day, and how long
    /// you'd been gone.
    public private(set) var shrank: (day: String, gone: Int)?

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
        var xp = store.int(Self.xpKey) ?? 0
        // From when a stage never went back, however little XP it had: it
        // keeps its stage's size, in XP now, as the stage is the XP's.
        if let old = store.int(Self.oldStageKey) {
            xp = max(xp, Growth.stages[Growth.stage(fromSix: old) - 1].from)
            do {
                try store.set([Self.xpKey: String(xp)])
                try store.remove([Self.oldStageKey])
            } catch {
                log("growth: can't save the stage it kept: \(error)")
            }
        }
        growth = Growth(xp: xp)
        lastSeq = store.int(Self.lastSeqKey) ?? 0
        reachedDay = store.string(Self.reachedKey)
        earnedDay = store.string(Self.earnedKey)
        decayedDays = store.int(Self.decayedKey) ?? 0
        if let saved = store.string(Self.shrankKey)?.split(separator: " "), saved.count == 2, let gone = Int(saved[1]) {
            shrank = (String(saved[0]), gone)
        }
    }

    /// Goes backwards up to `today`, once for each day past the grace since
    /// it last earned; the first day it's asked starts that clock, so a
    /// first launch on this, however long since the last, costs nothing.
    /// Returns whether the XP changed.
    @discardableResult
    public func decay(today: String) -> Bool {
        guard let earnedDay else {
            self.earnedDay = today
            save()
            return false
        }
        guard earnedDay != today else { return false }
        let gone = Growth.days(from: earnedDay, to: today)
        let due = max(0, gone - Growth.decayAfterDays) - decayedDays
        guard due > 0 else { return false }
        let before = growth.stage
        growth = Growth(xp: Growth.decayed(growth.xp, days: due))
        decayedDays += due
        if growth.stage < before {
            shrank = (today, gone)
            log("growth: shrank to stage \(growth.stage), \(growth.name), at \(growth.xp) XP")
        }
        save()
        return true
    }

    /// Why it's smaller, for the day it shrank and the day after, or nil.
    public func shrankWords(today: String, name: String) -> String? {
        guard let shrank, Growth.days(from: shrank.day, to: today) <= 1 else { return nil }
        return Growth.shrankWords(name: name, days: shrank.gone)
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

    /// Counts `e`, which earned `earned` XP within its pool's cap for the
    /// day, on `day` (the calendar's, for the day a stage was reached),
    /// and returns whether the XP changed.
    @discardableResult
    public func count(_ e: Event, earned: Int,
                      day: @autoclosure () -> String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) -> Bool {
        guard e.seq > lastSeq, earned > 0 else { return false }
        let today = day()
        decay(today: today)
        let before = growth.stage
        growth = Growth(xp: growth.xp + earned)
        lastSeq = e.seq
        earnedDay = today
        decayedDays = 0
        if growth.stage > before { reachedDay = today }
        save()
        if growth.stage > before { log("growth: reached stage \(growth.stage), \(growth.name), at \(growth.xp) XP") }
        return true
    }

    func save() {
        do {
            var values = [Self.xpKey: String(growth.xp), Self.lastSeqKey: String(lastSeq), Self.decayedKey: String(decayedDays)]
            if let reachedDay { values[Self.reachedKey] = reachedDay }
            if let earnedDay { values[Self.earnedKey] = earnedDay }
            if let shrank { values[Self.shrankKey] = "\(shrank.day) \(shrank.gone)" }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
