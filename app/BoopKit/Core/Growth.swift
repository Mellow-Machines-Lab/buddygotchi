import MellowHarness

/// How Boop grows: XP from what its agents get done and from your care,
/// by plain rules, each capped a day, and a stage for the XP. The Mac app shows them, and the
/// board gets the stage as tags (`Tags.stages`), so a pack can show it.
public struct Growth: Equatable, Sendable {
    /// Every XP ever earned.
    public var xp: Int
    /// The highest stage reached, from 1: it never goes back, even if the
    /// thresholds below rise in a later release.
    public var stage: Int

    public init(xp: Int = 0, stage: Int = 1) {
        self.xp = xp
        self.stage = max(stage, Growth.stage(for: xp))
    }

    /// Each stage's name and the XP it starts at, in order.
    public static let stages: [(name: String, from: Int)] = [
        ("Hatchling", 0), ("Sprout", 200), ("Buddy", 1_000), ("Pal", 4_000), ("Chonk", 12_000), ("Legend", 30_000),
    ]

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
    public static func cap(_ pool: Pool) -> Int { pool == .work ? workPerDay : carePerDay }

    /// Where XP comes from: the agents' work, or your care.
    public enum Pool: String, Sendable { case work, care }

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
        default: return nil
        }
    }

    /// What an event earns, before the day's caps.
    public static func xp(for e: Event) -> Int { earning(for: e)?.xp ?? 0 }

    /// The stage `xp` reaches by the thresholds, from 1.
    public static func stage(for xp: Int) -> Int {
        (stages.lastIndex { xp >= $0.from } ?? 0) + 1
    }

    public var name: String { Growth.stages[min(stage, Growth.stages.count) - 1].name }
    /// The XP the next stage starts at, or nil at the last.
    public var nextAt: Int? { stage < Growth.stages.count ? Growth.stages[stage].from : nil }
    /// How far through this stage, 0–1; 1 at the last.
    public var progress: Double {
        guard let next = nextAt else { return 1 }
        let from = Growth.stages[stage - 1].from
        return min(1, max(0, Double(xp - from) / Double(next - from)))
    }
}
