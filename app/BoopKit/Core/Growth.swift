import Foundation
import MellowHarness

/// How Boop grows (plan/xp-league.md §3): XP for four things you can see
/// happen, a turn finished, a ship, tests fixed and time with Boop; the
/// day's ring, a goal of `perDay` that XP keeps counting past up to
/// `dayMost`; and a level for every `perLevel` XP it ever earned. It never
/// goes down. Nothing is ever locked behind a level, and Boop's body is one
/// size at every level.
public struct Growth: Equatable, Sendable, Codable {
    /// Every XP it's ever earned.
    public var xp: Int
    /// Today's XP: 0 to `dayMost`. The ring is full at `perDay`.
    public var today: Int
    /// The part of today's XP that is your time with Boop: 0 to `careMost`.
    public var care: Int

    public init(xp: Int = 0, today: Int = 0, care: Int = 0) {
        self.xp = max(0, xp)
        self.today = max(0, min(today, Growth.dayMost))
        self.care = max(0, min(care, Growth.careMost, self.today))
    }

    /// The day's ring: a full ring is a good day.
    public static let perDay = 100
    /// The most a day can earn, work and care together.
    public static let dayMost = 300
    /// The most your time with Boop can earn in a day.
    public static let careMost = 30
    /// The XP a level takes.
    public static let perLevel = 500

    /// The level, from 1: 1 + XP / 500, with no maximum.
    public var level: Int { Growth.level(for: xp) }
    public static func level(for xp: Int) -> Int { 1 + max(0, xp) / perLevel }
    /// The XP still to earn for the next level.
    public var toNextLevel: Int { Growth.perLevel - xp % Growth.perLevel }
    /// Whether today's ring is full.
    public var ringClosed: Bool { today >= Growth.perDay }
    /// The part of today's XP that is the agents' work.
    public var work: Int { today - care }
    /// Today's ring in whole percent, full at 100.
    public var percent: Int { min(today, Growth.perDay) * 100 / Growth.perDay }

    /// What earns XP, each a thing the board shows as it happens.
    public enum Source: String, CaseIterable, Codable, Sendable {
        /// A turn that finished as a success: its finish plays, and names it.
        case turns
        /// A push that passed.
        case ships
        /// A check that passed after it failed.
        case fixes
        /// Your time with Boop: a care touch that isn't rough, your words, a met wish.
        case care
    }

    /// XP for each source.
    public static let turnXP = 5, shipXP = 10, fixXP = 5, careXP = 3

    public static func xp(for source: Source) -> Int {
        switch source {
        case .turns: turnXP
        case .ships: shipXP
        case .fixes: fixXP
        case .care: careXP
        }
    }

    /// What `e` earns before the day's limits, and for what, or nil. `facts`
    /// are its line's (the transcript view's): a turn earns when its finish
    /// is a success (`MomentRule.finish`), read where that finish is, the
    /// turn's end or its last message's reading; a check earns when it
    /// passes after it failed.
    public static func source(of e: Event, facts: [String: JSONValue]?) -> Source? {
        if e.kind == Event.kind(.turn, .end) || e.type == .lastMessage {
            guard let facts, MomentRule.finish(facts) == .success else { return nil }
            return .turns
        }
        if e.kind == Event.kind(.tool, .end), let facts,
           let topic = facts["topic"]?.string, TranscriptView.checks.contains(topic),
           facts["result"]?.string == "ok", (facts["failed_before"]?.int ?? 0) > 0 {
            return .fixes
        }
        if e.type == .act, e.phase == .end, e.specificType == "push", e["passed"]?.bool == true { return .ships }
        switch e.type {
        case .gesture? where Touch(e).map({ $0.isCare && !$0.isRough }) == true: return .care
        case .said?: return .care
        case .wish? where e.phase == .end && e.specificType == Core.WishEnd.met.rawValue: return .care
        default: return nil
        }
    }

    /// What `source` adds to a day that stands at `self`: none past the
    /// day's most, nor past care's.
    public func adds(_ source: Source) -> Int {
        let room = Growth.dayMost - today
        let want = Growth.xp(for: source)
        if source == .care { return max(0, min(want, room, Growth.careMost - care)) }
        return max(0, min(want, room))
    }

    /// `self` with `n` XP more from `source`.
    public func adding(_ n: Int, from source: Source) -> Growth {
        Growth(xp: xp + n, today: today + n, care: care + (source == .care ? n : 0))
    }
}
