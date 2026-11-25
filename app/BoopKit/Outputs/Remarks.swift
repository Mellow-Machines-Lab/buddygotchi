import Foundation
import MellowHarness

/// A remark: the one short thing Boop says about how now differs from
/// your usual (`Normals`), as text on a skit that plays anyway, so it adds
/// no interruption of its own. Its words are the pack's (`signs.md`'s
/// `[remark …]` lines, `Signs.remark`). A plain rule: the table here and
/// nowhere else (`RemarksTests` pins it).
public enum Remarks {
    /// Every remark there is, in the table's order: the first that fits wins.
    public static let all = ["fast", "slow", "run", "count", "early", "late", "soon", "longBreak"]

    /// At most one skit in this many carries a remark, so one stays special.
    public static let every = 3
    /// A turn is fast under half your median, slow over twice it, with
    /// this many turns kept.
    public static let turnsNeeded = 10
    /// The first hour and breaks need this many kept; so does your best day.
    public static let daysNeeded = 5, breaksNeeded = 5
    /// Today's wins worth a word when they reach one of these.
    public static let winCounts: Set<Int> = [5, 10]
    /// A run worth a word: the 3rd win in a row, or a new best from the 4th.
    public static let runAt: Int64 = 3, bestRunFrom: Int64 = 4
    /// Early or late by this many minutes against your usual first hour.
    public static let earlyLateMinutes = 45

    /// The remark on the skit `skit` at an event whose line has `facts`,
    /// against `usual` (your usual before it), `minutes` being the event's
    /// minutes after 5:00, on `quiet` or not; or nil for none.
    ///
    /// | Remark | On the skit | When | Needs |
    /// | --- | --- | --- | --- |
    /// | `fast` | `win` | This turn took under half your median turn | 10 turns kept |
    /// | `slow` | `win` | This turn took over twice your median turn | 10 turns kept |
    /// | `run` | `win` | This is the 3rd win in a row, or a new best run of 4 or more (`Normals`' run: no failed turn between) | |
    /// | `count` | `win` | Today's wins just reached 5 or 10, or just passed your best day of the last 14 | 5 days kept for the last one |
    /// | `early` | `back` | The first time you show up today, 45 minutes or more before your median first hour; over the dream told | 5 days kept |
    /// | `late` | `back` | The same, 45 minutes or more after it | 5 days kept |
    /// | `soon` | `back` | You were away under half your median break | 5 breaks kept |
    /// | `longBreak` | `back` | You were away over twice your median break, and under 4 hours | 5 breaks kept |
    ///
    /// When two fit, the first in this order wins. At most one skit in
    /// three carries one (`every`, the count in `Normals`); `upset` and
    /// `fix` never do; on Quiet, none; nor with your usual empty, a new
    /// buddy's, so no Moment changes until there's a usual to differ from.
    /// A win's remarks are only for a turn that's a success with tools, the
    /// turns your usual counts. A `back`'s is its sign: it wins over the
    /// dream's sign and shows beside what happened while you were away,
    /// while the dream is still told (its narration, the hello played
    /// whole); a special day's sign wins over it (`MomentOutput.run`).
    public static func pick(skit: String, facts: [String: JSONValue], usual: Normals.Usual, minutes: Int, quiet: Bool) -> String? {
        guard !quiet, !usual.isEmpty, usual.skitsSinceRemark.map({ $0 >= every - 1 }) ?? true else { return nil }
        switch skit {
        case "win":
            let length = Normals.win(facts)
            if let length, usual.turnsMs.count >= turnsNeeded, let median = Normals.median(usual.turnsMs) {
                if length * 2 < median { return "fast" }
                if length > median * 2 { return "slow" }
            }
            let run = usual.run
            if run == runAt || (run >= bestRunFrom && run > usual.bestRun) { return "run" }
            if length != nil {
                if winCounts.contains(usual.winsToday) { return "count" }
                if usual.winsADay.count >= daysNeeded, usual.winsToday == (usual.winsADay.max() ?? 0) + 1 { return "count" }
            }
            return nil
        case "back":
            if facts[TranscriptView.firstTodayFact] != nil, usual.firstMinutes.count >= daysNeeded,
               let median = Normals.median(usual.firstMinutes.map(Int64.init)) {
                if Int64(minutes) <= median - Int64(earlyLateMinutes) { return "early" }
                if Int64(minutes) >= median + Int64(earlyLateMinutes) { return "late" }
            }
            if let away = facts["away_ms"]?.int, usual.breaksMs.count >= breaksNeeded, let median = Normals.median(usual.breaksMs) {
                if away * 2 < median { return "soon" }
                if away > median * 2, away < Normals.breakUntilMs { return "longBreak" }
            }
            return nil
        default:
            return nil
        }
    }

    /// The number a remark's words say as `{n}`, or nil for none: the run
    /// for `run`, today's wins for `count`.
    public static func number(_ remark: String, facts: [String: JSONValue], usual: Normals.Usual) -> Int? {
        switch remark {
        case "run": return usual.run > 0 ? Int(usual.run) : nil
        case "count": return usual.winsToday
        default: return nil
        }
    }
}
