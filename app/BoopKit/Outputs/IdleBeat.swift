import Foundation
import MellowHarness

/// Boop's own beat at an idle check-in: the one thing it may hold up
/// there. Code deals it: of the six kinds, the first in `Kind`'s order
/// that has something due, under one cap. Only while Boop may start
/// something of its own (`Core.mayBeOwnBeat`); dozed off, only the notice
/// that it's late. Jev is only asked whether to
/// hold it up, or nothing (`MomentOutput.questions`). What each kind does
/// once it shows is its own: a wish opens, an ask takes two answers, a
/// remembered line goes on the low sign.
///
/// In a long working stretch a working check-in may deal one too, under
/// the same cap and in the same order, but no musing (`atWork`): the
/// rules hold it up on their own Moment, with no pass
/// (`MomentOutput.ruled`).
public enum IdleBeat {
    /// The kinds, in the order they're dealt.
    ///
    /// | Kind | What it is | Its own rest | On Quiet, or over an open wish |
    /// | --- | --- | --- | --- |
    /// | waiting | The notice that an agent has sat idle a while | a Boop day for each agent | yes |
    /// | wish | Boop's want for the day (`Core.Wish`) | one a Boop day, never while cross | no |
    /// | notice | Any other notice (`Notices`) | a day, `late` a week | no |
    /// | ask | A question with two answers (`Asks`) | 30 days answered, a day ignored, never again once kept | no |
    /// | remembered | A remembered line (`Memory.Felt`) | 14 days for each line | no |
    /// | musing | An `[idle]` line of `signs.md` | not the sign shown last | no |
    public enum Kind: String, CaseIterable, Sendable {
        case waiting, wish, notice, ask, remembered, musing

        /// Whether it comes on Quiet, and while a wish is open: only an
        /// agent waiting on you, which is of use to you.
        var always: Bool { self == .waiting }
        /// Whether it comes at a working check-in: all but a musing, an
        /// idle thought ("quiet day...") that's wrong over work.
        var atWork: Bool { self != .musing }
    }

    /// What's due: its kind, the signs for it (a musing's are a few to
    /// choose among; any other shows one), and what its kind carries.
    public struct Candidate {
        public var kind: Kind
        public var signs: [String]
        public var wish: Core.WishKind?
        public var notice: Notices.Notice?
        public var ask: Asks.Question?
        public var remembered: Memory.Felt?
        /// Why it fits now, for the narration: a wish's reason.
        public var because: String?

        public init(_ kind: Kind, signs: [String], wish: Core.WishKind? = nil, notice: Notices.Notice? = nil,
                    ask: Asks.Question? = nil, remembered: Memory.Felt? = nil, because: String? = nil) {
            self.kind = kind
            self.signs = signs
            self.wish = wish
            self.notice = notice
            self.ask = ask
            self.remembered = remembered
            self.because = because
        }
    }

    /// The one cap: at most one idle beat an hour, and this many a Boop day.
    public static let everyMs: Int64 = 60 * 60_000
    public static let perDay = 4
    /// The most musings offered to choose among.
    public static let musingsOffered = 3

    /// The fact a Moment's record carries when it showed an idle beat: its kind.
    public static let fact = "beat"

    /// When each idle beat in `log` was shown.
    public static func shownAt(_ log: LogView) -> [Int64] {
        log.events.filter { $0.kind == Event.did && $0.action == MomentOutput.outputName && $0["ok"]?.bool == true && $0[fact] != nil }.map(\.at)
    }

    /// Whether the cap has room at `now`, by when the others were shown.
    public static func room(_ shownAt: [Int64], now: Int64, sameDay: (Int64) -> Bool) -> Bool {
        !shownAt.contains { now - $0 < everyMs } && shownAt.filter(sameDay).count < perDay
    }

    /// The one candidate due: the first kind in order that `offer`s
    /// something, if the cap has `room`. On `quiet`, and while a wish is
    /// open (`wishOpen`), only an agent waiting on you; `atWork`, no musing.
    public static func due(room: Bool, quiet: Bool, wishOpen: Bool, atWork: Bool = false,
                           offer: (Kind) -> Candidate?) -> Candidate? {
        guard room else { return nil }
        for kind in Kind.allCases where (kind.always || !(quiet || wishOpen)) && (kind.atWork || !atWork) {
            if let c = offer(kind), !c.signs.isEmpty { return c }
        }
        return nil
    }

    /// A working stretch at least this long (`tier2`) may have a beat at
    /// its check-in, and none within this long of a Moment.
    public static let workStretchMs: Int64 = 5 * 60_000
    public static let afterMomentMs: Int64 = 60_000

    /// Whether a working check-in may deal a beat: the agents have worked
    /// `stretchMs` (from the working stretch's start), at least
    /// `workStretchMs`; Boop may start something of its own (you're at
    /// the Mac, nothing needs you, not listening: `Core.mayBeOwnBeat`);
    /// not Quiet, not on a call; and no Moment started or ended in the
    /// last `afterMomentMs` (`momentAgoMs`, nil for none).
    public static func atWork(stretchMs: Int64?, mayStart: Bool, quiet: Bool, onCall: Bool, momentAgoMs: Int64?) -> Bool {
        guard let stretchMs, stretchMs >= workStretchMs, mayStart, !quiet, !onCall else { return false }
        return (momentAgoMs ?? .max) >= afterMomentMs
    }

    /// Every candidate `offer` has, whatever the order and the cap: for a
    /// pass forced from outside (a demo's, the dashboard's), which names
    /// the sign Boop holds up itself, as it sets a mood.
    public static func every(offer: (Kind) -> Candidate?) -> [Candidate] {
        Kind.allCases.compactMap(offer).filter { !$0.signs.isEmpty }
    }
}
