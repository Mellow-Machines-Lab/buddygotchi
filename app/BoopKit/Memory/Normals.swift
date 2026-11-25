import Foundation
import MellowHarness

/// Your usual: the numbers Boop compares now with, a view over the
/// transcript, never a store of its own. It's a pure fold of the
/// transcript's events and the lines Jev read for them (`adding`), and of
/// Boop's days as they open (`opening`). The memory keeps it as it keeps
/// the invite ledger (`NormalsReader`), and catches it up from the
/// transcript at launch. Short lists, so a median is a sort.
///
/// | What | From | Kept |
/// | --- | --- | --- |
/// | How long your turns take | A finish that's a success with tools (`length_ms`) | the last 50, `turnsKept` |
/// | The hour you first show up | Your hello marked the first of its Boop day (`first_today`) | the last 14 days, `daysKept` |
/// | How long your breaks are | Your coming back from 10 minutes to 4 hours away (`away_ms`) | the last 30, `breaksKept` |
/// | Your wins a day | Finishes that are a success with tools, on each Boop day | the last 14 days |
/// | Your run of wins | Those wins in a row: a failed turn ends it, another turn neither counts nor ends it | now, and the most ever |
/// | Skits since the last remark | Reaction records with a `skit`, and whether they carried a `remark`, once each played (`Played`) | a count |
///
/// The lists keep the event each number came from, so a remark at that
/// event compares it with your usual before it (`usual(before:minutes:)`).
public struct Normals: Codable, Equatable, Sendable {
    public static let turnsKept = 50, daysKept = 14, breaksKept = 30
    /// A coming back counts as a break from this long away, and up to this.
    public static let breakFromMs: Int64 = 10 * 60_000, breakUntilMs: Int64 = 4 * 3_600_000
    /// The reaction record's fact that says it showed a remark.
    public static let remarkFact = "remark"

    /// A number, and the `seq` of the event it came from.
    public struct Kept: Codable, Equatable, Sendable {
        public var seq: Int
        public var value: Int64

        public init(seq: Int, value: Int64) {
            self.seq = seq
            self.value = value
        }
    }

    /// One Boop day: when you first showed up on it, if you did, and its wins.
    public struct Day: Codable, Equatable, Sendable {
        public var day: String
        public var firstAt: Int64?
        public var wins = 0

        public init(day: String, firstAt: Int64? = nil, wins: Int = 0) {
            self.day = day
            self.firstAt = firstAt
            self.wins = wins
        }
    }

    public var turns: [Kept] = []
    public var breaks: [Kept] = []
    /// The Boop days, the open one last: it and the `daysKept` before it.
    public var days: [Day] = []
    /// Your run of wins now, from the win that made it; the best run ever,
    /// and the best before the win that set it.
    public var run: Kept?
    public var bestRun: Kept?
    public var bestRunBefore: Int64 = 0
    /// The skits since the last that carried a remark; nil before the first.
    public var skitsSinceRemark: Int?
    /// The reaction records with a skit or a remark, until the board says
    /// they played: true for one that carried a remark.
    public var playing = Played<Bool>()

    public init() {}

    /// The length of the turn a finish's line `facts` tell, when it's a
    /// success with tools, or nil.
    public static func win(_ facts: [String: JSONValue]) -> Int64? {
        guard MomentRule.finish(facts) == .success, (facts["tools"]?.int ?? 0) > 0 else { return nil }
        return facts["length_ms"]?.int ?? 0
    }

    /// `normals` with `e` read into it, by its `line`'s facts.
    public static func adding(_ e: Event, line: Line?, to normals: Normals) -> Normals {
        var n = normals
        if e.kind == Event.did || e.kind == Event.ended {
            switch n.playing.read(e, { $0[remarkFact] != nil ? true : $0["skit"] != nil ? false : nil }) {
            case true?: n.skitsSinceRemark = 0
            case false?: n.skitsSinceRemark = n.skitsSinceRemark.map { $0 + 1 }
            case nil: break
            }
            return n
        }
        guard let facts = line?.facts else { return n }
        if e.kind == Event.kind(.turn, .end) || e.type == .lastMessage, facts["outcome"] != nil {
            if let ms = win(facts) {
                n.turns = Array((n.turns + [Kept(seq: e.seq, value: ms)]).suffix(turnsKept))
                if !n.days.isEmpty { n.days[n.days.count - 1].wins += 1 }
                let run = Kept(seq: e.seq, value: (n.run?.value ?? 0) + 1)
                n.run = run
                if run.value > (n.bestRun?.value ?? 0) {
                    n.bestRunBefore = n.bestRun?.value ?? 0
                    n.bestRun = run
                }
            } else if MomentRule.finish(facts) == .failure {
                n.run = nil
            }
        }
        if e.type == .presence, e.phase == .end, let away = facts["away_ms"]?.int, (breakFromMs...breakUntilMs).contains(away) {
            n.breaks = Array((n.breaks + [Kept(seq: e.seq, value: away)]).suffix(breaksKept))
        }
        if facts[TranscriptView.firstTodayFact] != nil, !n.days.isEmpty, n.days[n.days.count - 1].firstAt == nil {
            n.days[n.days.count - 1].firstAt = e.at
        }
        return n
    }

    /// `normals` as Boop's day `day` opens: a day of its own, and the
    /// last `daysKept` before it.
    public static func opening(day: String, _ normals: Normals) -> Normals {
        var n = normals
        guard n.days.last?.day != day else { return n }
        n.days = Array((n.days + [Day(day: day)]).suffix(daysKept + 1))
        return n
    }

    /// Your usual as it stood before the event `seq`, for a remark there:
    /// what that event added is left out, but today's wins and the run,
    /// which count it. `minutes` is a time's minutes after 5:00, when Boop's
    /// day starts.
    public struct Usual: Equatable, Sendable {
        public var turnsMs: [Int64] = []
        public var breaksMs: [Int64] = []
        /// The days before today you showed up on, as minutes after 5:00.
        public var firstMinutes: [Int] = []
        /// The wins of each day before today, and today's so far.
        public var winsADay: [Int] = []
        public var winsToday = 0
        /// The run of wins the event made, when it's the latest win, else 0;
        /// and the best run before it.
        public var run: Int64 = 0
        public var bestRun: Int64 = 0
        public var skitsSinceRemark: Int?

        public init() {}

        /// Nothing kept before the event: a new buddy's.
        public var isEmpty: Bool { turnsMs.isEmpty && breaksMs.isEmpty && firstMinutes.isEmpty && winsADay.isEmpty }
    }

    public func usual(before seq: Int, minutes: (Int64) -> Int) -> Usual {
        var u = Usual()
        u.turnsMs = turns.filter { $0.seq < seq }.map(\.value)
        u.breaksMs = breaks.filter { $0.seq < seq }.map(\.value)
        let before = days.dropLast()
        u.firstMinutes = before.compactMap { $0.firstAt.map(minutes) }
        u.winsADay = before.map(\.wins)
        u.winsToday = days.last?.wins ?? 0
        u.run = run.map { $0.seq == seq ? $0.value : 0 } ?? 0
        u.bestRun = bestRun.map { $0.seq < seq ? $0.value : bestRunBefore } ?? 0
        u.skitsSinceRemark = skitsSinceRemark
        return u
    }

    /// The median of `xs`, or nil for none: the middle one, or the mean of
    /// the middle two.
    public static func median(_ xs: [Int64]) -> Int64? {
        guard !xs.isEmpty else { return nil }
        let s = xs.sorted(), m = s.count / 2
        return s.count % 2 == 1 ? s[m] : (s[m - 1] + s[m]) / 2
    }
}

/// Your usual as a reader of the transcript (`TranscriptReader`): kept in
/// the memory's store, so a launch catches up on what it missed. Each
/// Boop day opens a day of its own.
public final class NormalsReader: TranscriptReader {
    public let name = "normals"

    public init() {}

    public func open(day: String, carry: Normals?) -> Normals { Normals.opening(day: day, carry ?? Normals()) }

    public func read(_ e: Event, line: Line?, into normals: inout Normals) -> Bool {
        let next = Normals.adding(e, line: line, to: normals)
        defer { normals = next }
        return next != normals
    }

    public func close(day: String, state: Normals, live: Bool) {}
}
