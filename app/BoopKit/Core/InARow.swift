/// The same thing happening again with no break, counted: the one counter
/// behind every "in a row" a line says (`EventLine.inARow`). Each kind has
/// its own break (`Kind`), and whoever counts it starts it over where its
/// rule says (`reset`).
struct InARow: Equatable {
    /// What's counted, and what breaks its run.
    ///
    /// | Kind | Another counts when | Starts over |
    /// | --- | --- | --- |
    /// | pokes | within 3 s of the one before | after that gap |
    /// | shakes | within 4 s of the one before | after that gap |
    /// | quick wins | a turn done in under 5 min, within 10 min of the last, on its thread | at any other finish |
    /// | failed checks | the same check failing again, on its thread | when it passes |
    /// | failed calls | within the work stream's ladder's 2 min of now | as the old ones age out |
    enum Kind {
        case pokes, shakes, quickWins, failedChecks, failedCalls

        /// The longest gap after the one before that still counts, or nil
        /// for none.
        var gapMs: Int64? {
            switch self {
            case .pokes: 3000
            // The board finds a shake at most every 1.5 s
            // (`MotionGesture::kQuietMs`), so a hand that keeps shaking
            // makes one every 1.5 to 2 s.
            case .shakes: 4000
            case .quickWins: 10 * 60_000
            case .failedChecks, .failedCalls: nil
            }
        }

        /// Only those this close to now count, or nil for all.
        var spanMs: Int64? { self == .failedCalls ? WorkStream.ladderMs : nil }
    }

    /// When each came, the oldest first.
    private(set) var at: [Int64] = []

    var count: Int { at.count }

    /// How long the run has gone on, in whole seconds, 1 at least.
    var seconds: Int { max(1, Int(((at.last ?? 0) - (at.first ?? 0) + 999) / 1000)) }

    /// Counts another of `kind` at `now`, and returns which in a row it is.
    @discardableResult
    mutating func add(_ kind: Kind, at now: Int64) -> Int {
        if let gap = kind.gapMs, let last = at.last, now - last >= gap { at = [] }
        if let span = kind.spanMs { at.removeAll { now - $0 >= span } }
        at.append(now)
        return at.count
    }

    mutating func reset() { at = [] }
}
