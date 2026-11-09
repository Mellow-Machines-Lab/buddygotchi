import Foundation
import MellowHarness

/// How Boop grows, kept simple: a fixed XP for each thing its agents get
/// done and each bit of your care, at most `perDay` in one Boop day (the
/// day's ring), and a level for every `perLevel` XP it ever earned. It
/// never goes down. Some level-ups are bigger: at the levels in `stages`,
/// Boop grows a size, which the board draws from its tag (`Tags.stages`).
/// Nothing useful is ever locked behind a level.
public struct Growth: Equatable, Sendable {
    /// Every XP it's ever earned.
    public var xp: Int
    /// Today's XP, the ring: 0 to `perDay`.
    public var today: Int

    public init(xp: Int = 0, today: Int = 0) {
        self.xp = max(0, xp)
        self.today = max(0, min(today, Growth.perDay))
    }

    /// The day's ring: what a day can earn at most.
    public static let perDay = 100
    /// The XP a level takes: a full ring is a level.
    public static let perLevel = 100

    /// The level, from 1: 1 + XP / 100, with no maximum.
    public var level: Int { Growth.level(for: xp) }
    public static func level(for xp: Int) -> Int { 1 + max(0, xp) / perLevel }
    /// The XP still to earn for the next level.
    public var toNextLevel: Int { Growth.perLevel - xp % Growth.perLevel }
    /// Whether today's ring is full.
    public var ringClosed: Bool { today >= Growth.perDay }
    /// Today's ring in whole percent: what the board's bar shows (`state.xp`).
    public var percent: Int { today * 100 / Growth.perDay }

    /// Each size's name and the level it's reached at, in order. Reaching
    /// one is a bigger level-up.
    public static let stages: [(name: String, level: Int)] = [
        ("Hatchling", 1), ("Sprout", 5), ("Buddy", 15), ("Chonk", 30),
    ]
    /// The size it's at, from 1.
    public var stage: Int { Growth.stage(forLevel: level) }
    public var stageName: String { Growth.stages[stage - 1].name }
    public static func stage(forLevel level: Int) -> Int {
        (stages.lastIndex { level >= $0.level } ?? 0) + 1
    }
    /// Whether reaching `level` grows Boop a size.
    public static func grows(at level: Int) -> Bool { level > 1 && stages.contains { $0.level == level } }

    /// XP for a turn that ends done, a tool call that ends without failing
    /// and a helper coming back: the agents' work.
    public static let turnXP = 5, toolXP = 1, helperXP = 2
    /// XP for a care touch (`Touch.isCare`), a word to Boop, an answered
    /// ask, a met wish and you coming back to the Mac.
    public static let careXP = 3, talkXP = 3, answerXP = 5, wishXP = 20, backXP = 2

    /// What an event earns, before the day's cap: 0 for nothing.
    public static func xp(for e: Event) -> Int {
        if e.from == .claude || e.from == .codex {
            switch e.kind {
            case Event.kind(.tool, .end): return e["failed"]?.bool == true ? 0 : toolXP
            case Event.kind(.subagent, .end): return helperXP
            case Event.kind(.turn, .end): return e["outcome"]?.string == "done" ? turnXP : 0
            default: return 0
            }
        }
        switch e.type {
        case .gesture? where Touch(e)?.isCare == true: return careXP
        case .said?: return talkXP
        case .ask? where e.specificType != Asks.ignored: return answerXP
        case .presence? where e.phase == .end: return backXP
        case .wish? where e.phase == .end && e.specificType == Core.WishEnd.met.rawValue: return wishXP
        default: return 0
        }
    }

    /// What `xp` more adds to a day that has `today` already: none past the ring.
    public static func capped(_ xp: Int, today: Int) -> Int { max(0, min(xp, perDay - today)) }
}
