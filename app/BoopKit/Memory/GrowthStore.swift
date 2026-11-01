import Foundation
import MellowHarness

/// Boop's growth as it's kept: XP,
/// the stage, the day it was reached and the last event counted, as
/// `growth.` keys in the key-value
/// store. It counts each event as it's logged, once: an event at or before
/// the last one counted is left alone. Touched only on `home`.
public final class GrowthStore {
    public static let xpKey = "growth.xp"
    public static let stageKey = "growth.stage"
    public static let lastSeqKey = "growth.last_seq"
    public static let reachedKey = "growth.reached"
    /// The Boop day the caps count, and what each pool earned in it.
    public static let dayKey = "growth.day", workTodayKey = "growth.work_today", careTodayKey = "growth.care_today"

    let store: KeyValueStore
    let log: (String) -> Void
    public private(set) var growth: Growth
    /// The `seq` of the last event counted.
    public private(set) var lastSeq: Int
    /// The day (`yyyy-MM-dd`) the stage was reached, nil for the first.
    public private(set) var reachedDay: String?
    /// The Boop day counted, and the XP each pool earned in it
    /// (`Growth.workPerDay`, `carePerDay`).
    public private(set) var capDay: String?
    public private(set) var today: [Growth.Pool: Int] = [:]

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
        growth = Growth(xp: store.int(Self.xpKey) ?? 0, stage: store.int(Self.stageKey) ?? 1)
        lastSeq = store.int(Self.lastSeqKey) ?? 0
        reachedDay = store.string(Self.reachedKey)
        capDay = store.string(Self.dayKey)
        today = [.work: store.int(Self.workTodayKey) ?? 0, .care: store.int(Self.careTodayKey) ?? 0]
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

    /// Counts `e`, on `day` (the calendar's, for the day a stage was
    /// reached) in Boop day `boopDay` (for the caps), and returns whether
    /// the XP changed. Each pool earns at most its cap a Boop day: with
    /// no `boopDay`, the event's own.
    @discardableResult
    public func count(_ e: Event, day: @autoclosure () -> String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)),
                      boopDay: String? = nil) -> Bool {
        guard e.seq > lastSeq, let earning = Growth.earning(for: e) else { return false }
        let boopDay = boopDay ?? LocalTime().boopDay(e.at)
        if boopDay != capDay { capDay = boopDay; today = [:] }
        let cap = earning.pool == .work ? Growth.workPerDay : Growth.carePerDay
        let earned = min(earning.xp, max(0, cap - today[earning.pool, default: 0]))
        guard earned > 0 else { return false }
        today[earning.pool, default: 0] += earned
        let before = growth.stage
        growth = Growth(xp: growth.xp + earned, stage: growth.stage)
        lastSeq = e.seq
        if growth.stage > before { reachedDay = day() }
        save()
        if growth.stage > before { log("growth: reached stage \(growth.stage), \(growth.name), at \(growth.xp) XP") }
        return true
    }

    func save() {
        do {
            var values = [Self.xpKey: String(growth.xp), Self.stageKey: String(growth.stage), Self.lastSeqKey: String(lastSeq),
                          Self.workTodayKey: String(today[.work, default: 0]), Self.careTodayKey: String(today[.care, default: 0])]
            if let capDay { values[Self.dayKey] = capDay }
            if let reachedDay { values[Self.reachedKey] = reachedDay }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
