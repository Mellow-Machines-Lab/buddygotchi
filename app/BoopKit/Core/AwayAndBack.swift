import MellowHarness

/// You stepping away from the Mac and coming back, paired: the one rule
/// the transcript view and the memory reader both keep, each in a fold of
/// its own (the view's rebuilt from the log's last day, the reader's
/// carried across days). An away began when the presence detector says
/// it did (`since`), not when it noticed; a back ends the away the fold
/// holds, or, after a relaunch during a long absence, the one the
/// detector saved with it (its `since`).
public struct AwayAndBack: Equatable, Sendable {
    /// When the away you haven't come back from began; nil while you're here.
    public var since: Int64?

    public init(since: Int64? = nil) { self.since = since }

    public enum Step: Equatable, Sendable {
        /// You stepped away, from `since`.
        case away(since: Int64)
        /// You came back, `ms` after the away began; nil with no away to end.
        case back(ms: Int64?)
    }

    /// A presence event's step, folded in; nil for any other event.
    public mutating func fold(_ e: Event) -> Step? {
        guard e.type == .presence else { return nil }
        if e.phase == .start {
            let began = e["since"]?.int ?? e.at
            since = began
            return .away(since: began)
        }
        guard e.phase == .end else { return nil }
        let began = since ?? e["since"]?.int
        since = nil
        return .back(ms: began.map { max(0, e.at - $0) })
    }
}
