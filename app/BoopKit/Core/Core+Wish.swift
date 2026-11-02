import Foundation
import MellowHarness

// The wish: Boop's one want a day, met by one thing you do anyway. The
// brain picks when (a sign it holds up), and how often; code holds the rest:
// one open, what meets it, how long it waits. Kept as the hush is: the core
// holds it, records it starting and ending in the transcript, and reads it
// back on launch.
extension Core {
    /// What Boop may wish for, each met by what you do anyway.
    public enum WishKind: String, CaseIterable, Sendable {
        case pet, chat, work

        /// As a line says it: "a pet".
        public var words: String {
            switch self {
            case .pet: "a pet"
            case .chat: "a chat"
            case .work: "some work together"
            }
        }
    }

    /// The wish open: its kind, when it was made, and how long it has
    /// waited while you could answer it, counted up to `countedTo`.
    public struct Wish: Equatable, Sendable {
        public var kind: WishKind
        public var since: Int64
        public var waitedMs: Int64 = 0
        public var countedTo: Int64
    }

    /// How a wish ends: you met it, it waited too long, or the day ended.
    public enum WishEnd: String, Sendable { case met, gaveup, closed }

    /// How long a wish waits, counting only time you could answer it, before
    /// Boop takes it down.
    public static let wishGivesUpMs: Int64 = 3 * 60 * 60_000

    /// The rules' Moments: a wish met, and one given up on.
    public static let wishMet = "wish_met", wishGone = "wish_gone"

    func wishDayNow(_ now: Int64) -> String { config.time.boopDay(wall(now)) }

    /// The wishes Boop may make at `now`: none while one is open, none
    /// unless you're here, it hasn't dozed off and nothing needs
    /// you, it isn't listening or hushed; `work` only while no agent works,
    /// else your next prompt meets it for nothing; `chat` only once
    /// push-to-talk works, so it never waits on what you couldn't answer.
    public func wishable(at now: Int64) -> [WishKind] {
        guard wish == nil, !awayFromMac, needsYouBlock == nil, listening == nil,
              hushed(at: now) == nil else { return [] }
        let doing = snapshot(at: now).doing
        guard !dozing(doing) else { return [] }
        return WishKind.allCases.filter { kind in
            switch kind {
            case .pet: true
            case .chat: pushToTalkWorks()
            case .work: doing != "working"
            }
        }
    }

    /// Makes the wish `kind`, recorded as `wish_start`, if it may be made.
    @discardableResult
    public func makeWish(_ kind: WishKind, at now: Int64) -> [CoreEffect] {
        guard wishable(at: now).contains(kind) else { return [] }
        var fx: [CoreEffect] = []
        advance(to: now)
        wish = Wish(kind: kind, since: now, countedTo: now)
        wishDay = wishDayNow(now)
        wishEnded = nil
        fx.append(.record(Event(at: now, source: .boop, type: .wish, phase: .start, specificType: kind.rawValue)))
        publish(now, &fx)
        return fx
    }

    /// You did what the wish `kind` asks: if it's the one open it's met at
    /// once, by a rule, the brain off the path: `wish_end`, and the board's
    /// fulfilment. Jev reacts on its next pass, as to anything.
    @discardableResult
    public func meetWish(_ kind: WishKind, at now: Int64) -> [CoreEffect] {
        guard wish?.kind == kind else { return [] }
        var fx: [CoreEffect] = []
        advance(to: now)
        metWish(now, &fx)
        publish(now, &fx)
        return fx
    }

    /// The open wish met: its end and the board's fulfilment.
    func metWish(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let kind = wish?.kind else { return }
        endWish(.met, now, &fx)
        play(Moment(anim: Self.wishMet, sign: wishMetSigns[kind]), for: nil, now, &fx)
    }

    func endWish(_ how: WishEnd, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let w = wish else { return }
        wish = nil
        wishEnded = (wishDayNow(now), how)
        fx.append(.record(Event(at: now, source: .boop, type: .wish, phase: .end, specificType: how.rawValue,
                                data: ["kind": .string(w.kind.rawValue), "waited_ms": .int(w.waitedMs)])))
    }

    /// Whether the wish's wait counts now: while you're here, it hasn't
    /// dozed off and nothing needs you. The board shows its icon only then.
    func wishCounts(doing: String, attn: StateSnapshot.Attention?) -> Bool {
        wish != nil && !awayFromMac && !dozing(doing) && attn == nil
    }

    /// Whether Boop sleeps past wanting anything: asleep with agents to
    /// watch, or from its nap. With none open and you here, its look is
    /// asleep with time on its hands, so it may still want something.
    func dozing(_ doing: String) -> Bool { doing == "asleep" && (!sessions.isEmpty || napping) }

    /// The wish's clock: it closes quietly when the day ends, grows while
    /// it counts, and gives up at `wishGivesUpMs`, with the rule's Moment,
    /// which wakes Jev to pick the feeling.
    func tickWish(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard var w = wish else { return }
        if config.time.boopDay(wall(w.since)) != wishDayNow(now) { return endWish(.closed, now, &fx) }
        let s = snapshot(at: now)
        if wishCounts(doing: s.doing, attn: s.attn) { w.waitedMs += max(0, now - w.countedTo) }
        w.countedTo = now
        wish = w
        guard w.waitedMs >= Self.wishGivesUpMs else { return }
        endWish(.gaveup, now, &fx)
        play(Moment(anim: Self.wishGone), for: nil, now, &fx)
        publish(now, &fx)
    }

    /// You stepped away from the Mac or came back (the presence detector's):
    /// a wish's wait counts only while you're here.
    @discardableResult
    public func presence(away: Bool, at now: Int64) -> [CoreEffect] {
        guard away != awayFromMac else { return [] }
        guard wish != nil else {
            awayFromMac = away
            return []
        }
        var fx: [CoreEffect] = []
        advance(to: now)
        tickWish(now, &fx)
        awayFromMac = away
        publish(now, &fx)
        return fx
    }

    /// A wish's start or end read back from the transcript: what a launch
    /// keeps. The wait goes on from the last event read.
    func replayWish(_ e: Event) {
        if e.phase == .start, let kind = WishKind(rawValue: e.specificType) {
            wish = Wish(kind: kind, since: e.at, countedTo: e.at)
            wishDay = wishDayNow(e.at)
            wishEnded = nil
        } else if e.phase == .end {
            wish = nil
            wishEnded = WishEnd(rawValue: e.specificType).map { (wishDayNow(e.at), $0) }
        }
    }

    /// The wish for CONTEXT's You row: "Boop's wish: a pet, waiting 70 min
    /// while you were here."; with none made today, that, and at an idle
    /// check-in (`idle`) from noon that the day's half gone: a nudge for the
    /// moment a wish suits, which at a poke would only press. Nil once one
    /// was made today and ended (the Today row says how).
    public func wishRow(at now: Int64, name: String, idle: Bool = false) -> String? {
        if let w = wish {
            return "\(name)'s wish: \(w.kind.words), waiting \(ContextSection.span(w.waitedMs)) while you were here"
        }
        guard wishDay != wishDayNow(now) else { return nil }
        return idle && config.time.components(wall(now)).hour >= 12 ? "no wish yet today, and the day's half gone" : "no wish yet today"
    }

    /// The wish for CONTEXT's Today row: "Boop's wish today: met.".
    public func wishToday(at now: Int64, name: String) -> String? {
        guard let ended = wishEnded, ended.day == wishDayNow(now) else { return nil }
        let how = switch ended.how {
        case .met: "met"
        case .gaveup: "left too long"
        case .closed: "closed"
        }
        return "\(name)'s wish today: \(how)."
    }
}
