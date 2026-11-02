import Foundation

/// What's true now, as tags: the calendar's (`Days.tags`), how long the
/// agents have worked or sat idle (the tiers), Boop's growth stage, and
/// whether Boop is hushed. The core sends them in the `state` message
/// (`when`), and the board shows only the designs whose tags are all on
/// (characters/CHARACTER.md §9). The board adds `busy` and `frantic`
/// itself, from the `state` message's count of sessions working. The
/// board gets only the tags it reads (`board`), the firmware's list in
/// the same order (firmware/src/render/tags.h).
public enum Tags {
    /// Every tag: the calendar's, the board's own two for how busy the
    /// agents are, the tiers, the stages, then `hushed`.
    public static let all = Days.calendarTags + ["busy", "frantic"] + tiers.map(\.tag) + stageTags + [hushed]

    /// The tags no board reads: the signs and the brain have them, and the
    /// `state` message leaves them out.
    public static let macOnly: Set<String> = ["weekend", "friday13", "piday", "aprilfools", "may4", "buddy", "pal", "chonk", "legend"]

    /// The tags the board reads, in its order: every tag but `macOnly`.
    public static let board = all.filter { !macOnly.contains($0) }

    /// On while Boop is hushed (`Core.Hush`): the gel zips its mouth.
    public static let hushed = "hushed"

    /// The tiers, by how long the agents have worked (their working
    /// stretch, `Core.stretch`) or sat idle (since the latest session came
    /// to rest: a turn ended, or you dismissed a request): `tier1` from 30
    /// seconds, `tier2` from a minute, `tier3` from 2, `tier4` from 5 and
    /// `tier5` from 10, the last, where it stays. Working and idle share
    /// them, as a design's look says which it's for. Before 30 seconds the
    /// looks need no tag.
    public static let tiers: [(tag: String, fromMs: Int64)] = [
        ("tier1", 30_000), ("tier2", 60_000), ("tier3", 120_000), ("tier4", 300_000), ("tier5", 600_000),
    ]

    /// The tier reached after `ms`, the last. Only it is sent, to keep the
    /// `state` line short: the board takes every tier below it as on too
    /// (`render::reached`), so a design for `tier2` shows from then on.
    public static func tier(after ms: Int64) -> String? {
        tiers.last { ms >= $0.fromMs }?.tag
    }

    /// A rest shorter than the first tier doesn't end a working stretch:
    /// a quick reply between turns keeps the working tiers climbing.
    public static let stretchRestMs = tiers[0].fromMs

    /// The growth stages' tags from the second on, in `Growth.stages`'
    /// order. Every stage reached is on, so a design that needs `pal` shows
    /// at Pal and every stage after it.
    public static let stageTags = Growth.stages.dropFirst().map { $0.name.lowercased() }

    /// The tags on at growth stage `stage` (from 1, a Hatchling's: none).
    public static func stages(_ stage: Int) -> [String] { Array(stageTags.prefix(max(0, stage - 1))) }
}
