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

    let store: KeyValueStore
    let log: (String) -> Void
    public private(set) var growth: Growth
    /// The `seq` of the last event counted.
    public private(set) var lastSeq: Int
    /// The day (`yyyy-MM-dd`) the stage was reached, nil for the first.
    public private(set) var reachedDay: String?

    public init(_ store: KeyValueStore, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.log = log
        growth = Growth(xp: store.int(Self.xpKey) ?? 0, stage: store.int(Self.stageKey) ?? 1)
        lastSeq = store.int(Self.lastSeqKey) ?? 0
        reachedDay = store.string(Self.reachedKey)
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

    /// Counts `e`, on `day`, and returns whether the XP changed.
    @discardableResult
    public func count(_ e: Event, day: @autoclosure () -> String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) -> Bool {
        guard e.seq > lastSeq else { return false }
        let earned = Growth.xp(for: e)
        guard earned > 0 else { return false }
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
            var values = [Self.xpKey: String(growth.xp), Self.stageKey: String(growth.stage), Self.lastSeqKey: String(lastSeq)]
            if let reachedDay { values[Self.reachedKey] = reachedDay }
            try store.set(values)
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
