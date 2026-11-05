import Foundation

/// What Boop notices about your day. Code finds what's true and says it in
/// CONTEXT's Noticed row; Jev decides whether to use it. A notice never makes
/// a Moment where one exists: at your coming back, your prompt or your
/// goodnight it only adds a fact to that Moment. New Moments come only at an
/// idle check-in, one at a time, and each is a pure function here over the
/// digests and the moment, with its rest. A wish left open holds the others
/// up, as it's what Boop has on its mind, but never `waiting`, whose window
/// is short and which is of use to you; a day with no wish holds up none. It counts
/// only once it has played (`Memory.recordNotice`). Nothing here holds a
/// word of code, a command or a tool's output: thread names, counts and
/// times.
public enum Notices {
    /// The notices that may make a Moment of their own, each with lines in
    /// the pack's `signs.md` (`[notice waiting]`).
    public enum Kind: String, CaseIterable, Sendable {
        case waiting, stretch, rough, late

        /// How many Boop days a played notice rests: a day (`waiting`, per
        /// agent), or a week.
        public var restDays: Int { self == .late ? 7 : 1 }
    }

    /// At most this many notices a Boop day, this far apart.
    public static let perDay = 2, gapMs: Int64 = 60 * 60_000
    /// An idle agent counts from this long: past the upper end you've moved on.
    public static let waitingMs: ClosedRange<Int64> = (15 * 60_000)...(60 * 60_000)
    /// At the Mac this long with no break.
    public static let stretchMs: Int64 = 2 * 60 * 60_000
    /// This many turns ended failed within `roughWithinMs`, or a sharp prompt
    /// within it. Reds in a turn that ends green are its work, not a failure.
    public static let roughFailures = 3, roughWithinMs: Int64 = 60 * 60_000
    /// Up past 1:00 on this many of the last `lateOfNights` nights, and it's
    /// past midnight now.
    public static let lateNights = 3, lateOfNights = 7
    /// A thread comes back from this many days away.
    public static let backOnDays = 7
    /// Your history is too short to read habits from before this many days.
    public static let historyDays = 14
    /// "5 of the last 7 days stroked in the morning".
    public static let ritualDays = 5, ritualOf = 7, ritualLateMs: Int64 = 60 * 60_000

    /// What a notice reads, all of it given.
    public struct Moment: Sendable {
        public var at: Int64
        public var wall: Int64
        public var time: LocalTime
        public var agents: [StatusReply.Agent] = []
        public var hereSince: Int64?
        /// When turns ended failed within the last `roughWithinMs`, and your
        /// last sharp prompt.
        public var failures: [Int64] = []
        public var sharpAt: Int64?
        public var digests: [DayDigest] = []
        /// When each notice was last played, by its key (`Notice.key`).
        public var shown: [String: Int64] = [:]
        /// Whether Boop has dozed off: only `late` comes then, the small
        /// hours being when it has.
        public var dozing = false
        /// Whether a wish is open: only `waiting` comes then, if it's awake.
        public var wishOpen = false

        public init(at: Int64, wall: Int64, time: LocalTime) {
            self.at = at
            self.wall = wall
            self.time = time
        }
    }

    /// One notice that's true now.
    public struct Notice: Equatable, Sendable {
        public var kind: Kind
        /// What it rests by: its kind, and for `waiting` its agent, as a
        /// thread's title may change.
        public var key: String
        /// CONTEXT's words, and the reason's.
        public var fact: String
        /// The reason on the board, in its lane (`Narration.fact`).
        public var short: String
        /// For `{agent}` in its lines.
        public var agent: String?
    }

    /// The one notice due at `m`, the rarest first; nil if none is true, all
    /// that are true rest, today's are spent, or one played just now. Nothing
    /// while something needs you.
    public static func due(_ m: Moment) -> Notice? {
        guard !m.agents.contains(where: \.needsYou), roomToday(m) else { return nil }
        let order = m.dozing ? (m.wishOpen ? [] : [late(m)]) : m.wishOpen ? [waiting(m)] : [rough(m), stretch(m), late(m), waiting(m)]
        return order.compactMap { $0 }.first { !rests($0, m) }
    }

    static func roomToday(_ m: Moment) -> Bool {
        let today = m.time.boopDay(m.at)
        return m.shown.values.filter { m.time.boopDay($0) == today }.count < perDay
            && !m.shown.values.contains { m.at - $0 < gapMs }
    }

    static func rests(_ n: Notice, _ m: Moment) -> Bool {
        guard let last = m.shown[n.key], let then = LocalTime.dayNumber(m.time.boopDay(last)),
              let now = LocalTime.dayNumber(m.time.boopDay(m.at)) else { return false }
        return now - then < n.kind.restDays
    }

    /// An idle agent that has sat a while, whichever has rested longest,
    /// never one played today.
    static func waiting(_ m: Moment) -> Notice? {
        m.agents.filter { $0.restingSince.map { waitingMs.contains(m.at - $0) } == true }
            .sorted { $0.restingSince! < $1.restingSince! }
            .map { a in
                let on = a.places.last.map { " on \"\(StateSnapshot.clip($0))\"" } ?? ""
                return Notice(kind: .waiting, key: Kind.waiting.rawValue + ":" + a.agent,
                              fact: "\(a.agent) has sat idle\(on) for \(ContextSection.span(m.at - a.restingSince!))",
                              short: "\(a.agent) idle \(Narration.span(ms: m.at - a.restingSince!).short)", agent: a.agent)
            }
            .first { !rests($0, m) }
    }

    static func stretch(_ m: Moment) -> Notice? {
        guard let here = m.hereSince, m.at - here >= stretchMs else { return nil }
        return Notice(kind: .stretch, key: Kind.stretch.rawValue, fact: "you've been at the Mac for \(ContextSection.span(m.at - here)) with no break",
                      short: "\(Narration.span(ms: m.at - here).short) at the Mac")
    }

    static func rough(_ m: Moment) -> Notice? {
        let failed = m.failures.filter { m.at - $0 < roughWithinMs }.count
        if failed >= roughFailures { return Notice(kind: .rough, key: Kind.rough.rawValue, fact: "a rough hour: \(failed) failures", short: "a rough hour") }
        guard let sharp = m.sharpAt, m.at - sharp < roughWithinMs else { return nil }
        return Notice(kind: .rough, key: Kind.rough.rawValue, fact: "you sounded sharp a while ago, and it's quiet now", short: "you sounded sharp")
    }

    /// Past midnight, after enough other nights past 1:00.
    static func late(_ m: Moment) -> Notice? {
        guard m.time.components(m.wall).hour < LocalTime.boopDayStartHour,
              let today = LocalTime.dayNumber(m.time.boopDay(m.wall)) else { return nil }
        let nights = lastDays(lateOfNights, of: m.digests, before: today).filter(\.pastOne).count
        guard nights >= lateNights else { return nil }
        return Notice(kind: .late, key: Kind.late.rawValue, fact: "past midnight again: up past 1 on \(nights) of the last \(lateOfNights) nights", short: "past midnight")
    }

    // MARK: Facts on the Moments that exist

    /// Your coming back: "While you were gone, claude finished on "api"."
    /// At most `shownAway` finishes, by thread, a failure said as one.
    public static func whileAway(_ finishes: [(agent: String, thread: String, failed: Bool)]) -> String? {
        guard !finishes.isEmpty else { return nil }
        var parts = finishes.prefix(shownAway).map { "\($0.agent) \($0.failed ? "failed" : "finished") on \($0.thread)" }
        if finishes.count > shownAway { parts.append("\(finishes.count - shownAway) more") }
        return "While you were gone, " + parts.joined(separator: ", ") + "."
    }
    static let shownAway = 2

    /// Your first prompt today on a thread you've left: "First time on "api"
    /// in 9 days." `key` is the name the digests keep it by. Nil for one you
    /// were on lately, or never: only the kept days say so, and `known`, the
    /// thread's turns since the last dream, says it's not been left at all.
    public static func backOn(_ key: String, digests: [DayDigest], known: Bool, at wall: Int64, time: LocalTime) -> String? {
        guard !known, let today = LocalTime.dayNumber(time.boopDay(wall)),
              let last = digests.filter({ ($0.threads[key] ?? 0) > 0 }).compactMap({ LocalTime.dayNumber($0.day) }).max(),
              today - last >= backOnDays else { return nil }
        return "First time on \"\(key)\" in \(today - last) days."
    }

    /// Your goodnight: "23 turns today."
    public static func goodnight(turns: Int) -> String? {
        turns > 0 ? "\(turns) turn\(turns == 1 ? "" : "s") today." : nil
    }

    // MARK: A reason for a wish

    /// Why a wish would fit now, for CONTEXT's You row and the wish's reason:
    /// you've missed your morning stroke, or you haven't said hi today. Quiet
    /// in the first `historyDays`.
    public static func wishReason(today t: MemoryReader.Tallies?, digests: @autoclosure () -> [DayDigest], daysOld: Int?, at wall: Int64, time: LocalTime) -> String? {
        guard let t, t.yours > 0, t.touches == 0, t.talks == 0, let daysOld, daysOld >= historyDays else { return nil }
        if missedRitual(digests: digests(), at: wall, time: time) { return "you usually stroke it in the morning, and not yet today" }
        return "you haven't said hi today"
    }

    /// `ritualDays` of the last `ritualOf` days stroked in the morning, and
    /// an hour past your usual time.
    static func missedRitual(digests: [DayDigest], at wall: Int64, time: LocalTime) -> Bool {
        guard let today = LocalTime.dayNumber(time.boopDay(wall)) else { return false }
        let stroked = lastDays(ritualOf, of: digests, before: today).filter { $0.strokesAM > 0 }
        guard stroked.count >= ritualDays else { return false }
        let times = stroked.compactMap { LocalTime.minutes(of: $0.strokedAt.isEmpty ? $0.first : $0.strokedAt) }.sorted()
        guard !times.isEmpty else { return false }
        guard var now = LocalTime.minutes(of: time.clock(wall)) else { return false }
        if now < LocalTime.boopDayStartHour * 60 { now += 24 * 60 }
        return Int64(now - times[times.count / 2]) * 60_000 >= ritualLateMs
    }

    /// The digests of the `count` days before day number `today`.
    static func lastDays(_ count: Int, of digests: [DayDigest], before today: Int) -> [DayDigest] {
        digests.filter { d in LocalTime.dayNumber(d.day).map { (1...count).contains(today - $0) } == true }
    }
}
