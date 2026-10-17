import MellowHarness

/// A buddy's growth as it's kept: XP,
/// the stage and the last event counted, as `growth.` keys in its key-value
/// store. It counts each event as it's logged, once: an event at or before
/// the last one counted is left alone, and so is one about another buddy.
/// Touched only on `home`.
public final class GrowthStore {
    public static let xpKey = "growth.xp"
    public static let stageKey = "growth.stage"
    public static let lastSeqKey = "growth.last_seq"

    let store: KeyValueStore
    /// The buddy whose agents' work it counts, by its tag: nil for the
    /// only one, whose events carry none.
    let buddy: String?
    let log: (String) -> Void
    public private(set) var growth: Growth
    /// The `seq` of the last event counted.
    public private(set) var lastSeq: Int

    public init(_ store: KeyValueStore, buddy: String? = nil, log: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.buddy = buddy
        self.log = log
        growth = Growth(xp: store.int(Self.xpKey) ?? 0, stage: store.int(Self.stageKey) ?? 1)
        lastSeq = store.int(Self.lastSeqKey) ?? 0
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

    /// Counts `e`, and returns whether the XP changed.
    @discardableResult
    public func count(_ e: Event) -> Bool {
        guard e.seq > lastSeq, e.buddy == buddy else { return false }
        let earned = Growth.xp(for: e)
        guard earned > 0 else { return false }
        let before = growth.stage
        growth = Growth(xp: growth.xp + earned, stage: growth.stage)
        lastSeq = e.seq
        save()
        if growth.stage > before { log("growth: reached stage \(growth.stage), \(growth.name), at \(growth.xp) XP") }
        return true
    }

    func save() {
        do {
            try store.set([Self.xpKey: String(growth.xp), Self.stageKey: String(growth.stage), Self.lastSeqKey: String(lastSeq)])
        } catch {
            log("growth: can't save: \(error)")
        }
    }
}
