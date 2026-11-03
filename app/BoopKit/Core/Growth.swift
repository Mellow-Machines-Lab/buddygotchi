import Foundation
import MellowHarness

/// How Boop grows: XP from what its agents get done, from your care and from
/// a met wish, by plain rules, each capped a day, and a stage for the XP.
/// Left alone it goes backwards (`decayed`), so its stage goes with it. The
/// Mac app shows them, and the board gets the stage as a tag (`Tags.stages`).
/// A stage changes only how Boop looks and what it does to pass the time:
/// nothing useful is ever locked behind one.
public struct Growth: Equatable, Sendable {
    /// The XP now: what it's earned, less what it's lost.
    public var xp: Int
    /// The stage the XP reaches, from 1. A saved XP past the table is Chonk.
    public var stage: Int { Growth.stage(for: xp) }

    public init(xp: Int = 0) {
        self.xp = max(0, xp)
    }

    /// Each stage's name and the XP it starts at, in order.
    public static let stages: [(name: String, from: Int)] = [
        ("Hatchling", 0), ("Sprout", 200), ("Buddy", 1_000), ("Chonk", 5_000),
    ]

    /// The stage a stage saved when there were six comes to, by name: Pal,
    /// the size of a Buddy, is a Buddy; Chonk and Legend are a Chonk.
    public static func stage(fromSix old: Int) -> Int { [1, 2, 3, 3, 4, 4][max(1, min(old, 6)) - 1] }

    /// With no XP at all for this many days, it loses `decayPercent` of
    /// its XP each day after.
    public static let decayAfterDays = 3, decayPercent = 5

    /// `xp` after `days` days of going backwards. It never reaches zero.
    public static func decayed(_ xp: Int, days: Int) -> Int {
        guard xp > 1, days > 0 else { return xp }
        var left = xp
        for _ in 0..<days { left = max(1, left - max(1, left * decayPercent / 100)) }
        return left
    }

    /// The days from one `yyyy-MM-dd` to another, 0 if either isn't one.
    public static func days(from: String, to: String) -> Int {
        guard let a = LocalTime.dayNumber(from), let b = LocalTime.dayNumber(to) else { return 0 }
        return b - a
    }

    /// The reason it shrank, in the person's words.
    public static func shrankWords(name: String, days: Int) -> String {
        let gone = days >= 14 ? "\(days / 7) weeks" : days >= 7 ? "a week" : "\(days) days"
        return "\(name) shrank a little. You were gone \(gone)."
    }

    /// XP for a tool call that ends without failing.
    public static let toolXP = 1
    /// XP for a helper coming back.
    public static let helperXP = 2
    /// XP for a turn that ends done.
    public static let turnXP = 5

    /// XP for a care gesture (`Touch.isCare`), a word to Boop, an
    /// answered ask and you coming back to the Mac.
    public static let careXP = 3, talkXP = 3, answerXP = 5, backXP = 2
    /// The most each pool earns in one Boop day (from 5:00).
    public static let workPerDay = 60, carePerDay = 60
    /// XP for a met wish, its own pool, so at most one a day counts.
    public static let wishXP = 40
    public static func cap(_ pool: Pool) -> Int {
        switch pool {
        case .work: return workPerDay
        case .care: return carePerDay
        case .wish: return wishXP
        }
    }

    /// Where XP comes from: the agents' work, your care, or a met wish.
    public enum Pool: String, Sendable { case work, care, wish }

    /// What an event earns and from which pool: an agent's work that went
    /// somewhere, or your care for Boop; nil for nothing.
    public static func earning(for e: Event) -> (xp: Int, pool: Pool)? {
        if e.from == .claude || e.from == .codex {
            switch e.kind {
            case Event.kind(.tool, .end): return e["failed"]?.bool == true ? nil : (toolXP, .work)
            case Event.kind(.subagent, .end): return (helperXP, .work)
            case Event.kind(.turn, .end): return e["outcome"]?.string == "done" ? (turnXP, .work) : nil
            default: return nil
            }
        }
        switch e.type {
        case .gesture? where Touch(e)?.isCare == true: return (careXP, .care)
        case .said?: return (talkXP, .care)
        case .ask? where e.specificType != Asks.ignored: return (answerXP, .care)
        case .presence? where e.phase == .end: return (backXP, .care)
        case .wish? where e.phase == .end && e.specificType == Core.WishEnd.met.rawValue: return (wishXP, .wish)
        default: return nil
        }
    }

    /// What an event earns, before the day's caps.
    public static func xp(for e: Event) -> Int { earning(for: e)?.xp ?? 0 }

    /// The stage `xp` reaches by the thresholds, from 1.
    public static func stage(for xp: Int) -> Int {
        (stages.lastIndex { xp >= $0.from } ?? 0) + 1
    }

    /// How far through its stage, in whole percent: what the board's bar
    /// shows (`state.xp`). A full bar is only the last stage's.
    public var percent: Int { Int(progress * 100) }

    public var name: String { Growth.stages[stage - 1].name }
    /// The XP the next stage starts at, or nil at the last.
    public var nextAt: Int? { stage < Growth.stages.count ? Growth.stages[stage].from : nil }
    /// How far through this stage, 0–1; 1 at the last.
    public var progress: Double {
        guard let next = nextAt else { return 1 }
        let from = Growth.stages[stage - 1].from
        return min(1, max(0, Double(xp - from) / Double(next - from)))
    }
}
