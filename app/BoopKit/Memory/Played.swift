import Foundation
import MellowHarness

/// A reaction's record as the transcript's folds count it: only once the
/// board played it. The record (`did`) is held by its `seq` until its
/// `ended`, and counts only when that says done; one skipped in the board's
/// queue, cut short, never sent or never answered counts for nothing. A
/// record that ended as it was made counts at once. The invite ledger, the
/// daily counts and your usual count what a record carries this way.
public struct Played<Fact: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    /// The records still playing, by `seq`, with what each carries.
    public var open: [Int: Fact] = [:]

    public init() {}

    /// Reads `e`: what the reaction record it ends carried, once that
    /// played; else nil. A reaction's record for which `fact` is something
    /// is held until it ends.
    public mutating func read(_ e: Event, _ fact: (Event) -> Fact?) -> Fact? {
        if e.kind == Event.did, e.action == MomentOutput.outputName, e["ok"]?.bool != false, let f = fact(e) {
            guard e["open"]?.bool == true else { return f }
            open[e.seq] = f
            return nil
        }
        guard e.kind == Event.ended, let seq = e.about, let f = open.removeValue(forKey: seq) else { return nil }
        return e["outcome"]?.string == "done" ? f : nil
    }
}
