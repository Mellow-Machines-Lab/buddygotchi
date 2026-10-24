import MellowHarness

/// How Boop grows: XP from what its agents get done, by
/// plain rules, and a stage for the XP. The Mac app shows them, and the
/// board gets the stage as tags (`Occasions.stages`), so a pack can show it.
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

    /// What an event earns: only an agent's work that went somewhere.
    public static func xp(for e: Event) -> Int {
        guard e.from == .claude || e.from == .codex else { return 0 }
        switch e.kind {
        case Event.kind(.tool, .end): return e["failed"]?.bool == true ? 0 : toolXP
        case Event.kind(.subagent, .end): return helperXP
        case Event.kind(.turn, .end): return e["outcome"]?.string == "done" ? turnXP : 0
        default: return 0
        }
    }

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
