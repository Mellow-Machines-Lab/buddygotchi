import AgentHooks
import Foundation

/// The cards the agents have handed Boop (`Card`), and which one it holds.
///
/// A card is part of Doing, as the work stream is: it shows only while
/// nothing above Doing has the screen (your hand, needs you, a Moment, a
/// work act), and comes back after. So nothing here knows about any of
/// those: the core leaves the card out of the `state` while something needs
/// you, and the board draws it only under nothing else.
///
/// A session's status card lasts its turn. Its result card shows once the
/// turn has ended, for `resultMs`, and never has to be put away: it goes by
/// itself, or at once at that session's next prompt. One that ended while
/// you were away waits and shows as you come back.
///
/// With several, Boop holds one: the card that changed last, but not
/// before the one in its hands has had `holdMs`; a result always gets its
/// turn; and a swipe pins your choice for `pinMs`.
public struct Cards: Sendable {
    /// One session's cards.
    struct Held: Sendable {
        var status: Card?
        var result: Card?
        /// Its lane's slot in the work stream as the card came, whose colour
        /// the card keeps once the turn is over and the lane gone.
        var slot: Int?
        /// When what it shows last changed.
        var changedAt: Int64 = 0
        /// The agent's first guess of the minutes left this turn, and its
        /// newest: how many, and when it said so. The first is for the
        /// finish ("said 5 min, took 12"); the newest is counted down as it
        /// stands, never corrected.
        var firstGuess: Guess?
        var guess: Guess?
        /// The turn over: since when its result shows, or nil while it
        /// waits for you to be back.
        var ended = false
        var showsSince: Int64?
        /// How long the turn took from the first guess, in minutes.
        var took: Int?
    }

    struct Guess: Equatable, Sendable {
        var minutes: Int
        var at: Int64
    }

    /// A result shows this long after its turn ends: the finish's few
    /// seconds, and about ten to read it.
    public static let resultMs: Int64 = 15_000
    /// The card in its hands stays at least this long before another's
    /// change takes its place.
    public static let holdMs: Int64 = 8000
    /// A swipe keeps your choice this long.
    public static let pinMs: Int64 = 120_000

    var held: [String: Held] = [:]
    /// The session whose card Boop holds, since when, and until when your
    /// swipe keeps it there.
    public private(set) var focus: String?
    var focusAt: Int64 = 0
    var pinnedUntil: Int64 = 0

    public init() {}

    /// A session's turn starts: last turn's cards go.
    mutating func turnStarted(_ key: String) { held[key] = nil }

    /// The session is gone.
    mutating func gone(_ key: String) { held[key] = nil }

    /// A status card from a session at work.
    mutating func status(_ card: Card, for key: String, at now: Int64) {
        var h = held[key] ?? Held()
        guard !h.ended else { return }
        if let minutes = card.minutes, h.guess?.minutes != minutes || h.status?.text != card.text {
            let guess = Guess(minutes: minutes, at: now)
            h.guess = guess
            if h.firstGuess == nil { h.firstGuess = guess }
        }
        if h.status?.text != card.text || h.status?.step != card.step || h.status?.of != card.of || card.minutes != nil {
            h.changedAt = now
        }
        h.status = card
        held[key] = h
    }

    /// A result card, kept for the turn's end.
    mutating func result(_ card: Card, for key: String, at now: Int64) {
        var h = held[key] ?? Held()
        guard !h.ended else { return }
        h.result = card
        held[key] = h
    }

    /// The session's turn ended: its status goes and its result shows, now
    /// or, with you away, once you're back.
    mutating func turnEnded(_ key: String, away: Bool, at now: Int64) {
        guard var h = held[key] else { return }
        h.status = nil
        h.ended = true
        if let first = h.firstGuess { h.took = max(1, Int(((now - first.at) + 30_000) / 60_000)) }
        guard h.result != nil else { return held[key] = nil }
        h.showsSince = away ? nil : now
        h.changedAt = now
        held[key] = h
    }

    /// You're back: the results that waited show from now.
    mutating func youAreBack(at now: Int64) {
        for (key, h) in held where h.ended && h.showsSince == nil {
            held[key]?.showsSince = now
            held[key]?.changedAt = now
        }
    }

    /// Forgets the results that have had their time.
    mutating func tidy(at now: Int64) {
        held = held.filter { !$0.value.ended || $0.value.showsSince.map { now - $0 < Self.resultMs } ?? true }
    }

    /// The sessions with a card to show now, in `order`.
    func showing(in order: [String], at now: Int64) -> [String] {
        order.filter { key in
            guard let h = held[key] else { return false }
            return h.ended ? h.showsSince.map { now - $0 < Self.resultMs } ?? false : h.status != nil
        }
    }

    /// Picks the card Boop holds among `showing`: your pinned one; else a
    /// result that just began, or the newest change, once the one in its
    /// hands has had `holdMs`.
    mutating func refocus(_ showing: [String], at now: Int64) {
        guard !showing.isEmpty else { return focus = nil }
        let current = focus.flatMap { showing.contains($0) ? $0 : nil }
        if let current, now < pinnedUntil { return focus = current }
        let newest = showing.max { (held[$0]?.changedAt ?? 0, $1) < (held[$1]?.changedAt ?? 0, $0) }!
        guard let current else { return (focus, focusAt) = (newest, now) }
        guard newest != current, (held[newest]?.changedAt ?? 0) > focusAt, now - focusAt >= Self.holdMs else { return }
        (focus, focusAt) = (newest, now)
    }

    /// Your swipe: the next card (`by` 1) or the one before (-1) among
    /// `showing`, kept for `pinMs`.
    mutating func swipe(by: Int, among showing: [String], at now: Int64) {
        guard showing.count > 1, let at = focus.flatMap(showing.firstIndex(of:)) else { return }
        focus = showing[(at + by % showing.count + showing.count) % showing.count]
        focusAt = now
        pinnedUntil = now + Self.pinMs
    }

    /// What a session's card says now: its main thing, its small line, its
    /// step, and whether its guess has run out.
    struct Shown: Equatable, Sendable {
        var kind: Card.Kind
        var text: String
        var small: String?
        var over = false
        var link: String?
    }

    func shown(_ key: String, at now: Int64) -> Shown? {
        guard let h = held[key] else { return nil }
        if h.ended {
            guard let result = h.result else { return nil }
            let said = h.firstGuess.flatMap { first in h.took.map { "said \(first.minutes) min, took \($0)" } }
            return Shown(kind: .result, text: result.text, small: result.detail ?? said, link: result.link)
        }
        guard let status = h.status else { return nil }
        var shown = Shown(kind: .status, text: status.text)
        var small: [String] = []
        if let step = status.step, let of = status.of { small.append("\(step) of \(of)") }
        if let guess = h.guess {
            let left = guess.minutes - Int((now - guess.at) / 60_000)
            small.append(Self.left(left))
            shown.over = left < 0
        }
        if !small.isEmpty { shown.small = small.joined(separator: " · ") }
        return shown
    }

    /// The agent's guess, counted down in minutes, in the board's words.
    static func left(_ minutes: Int) -> String {
        minutes > 0 ? "\(minutes) min left" : minutes == 0 ? "any minute now" : "\(-minutes) min over"
    }
}
