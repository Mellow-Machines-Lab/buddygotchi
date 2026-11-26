import Foundation

/// What's true now, as tags: the calendar's (`Days.tags`), how long the
/// agents have worked or sat idle (the tiers),
/// your hands at the Mac (`Hands`), the side of Boop the Mac is on
/// (`Anchor.side`) and what else Boop notices of you at the Mac
/// (`Along`). The core sends them in the `state` message
/// (`when`), and the board shows only the designs whose tags are all on
/// (characters/CHARACTER.md §9). The board adds `busy` and `frantic`
/// itself, from the `state` message's count of sessions working. The
/// board gets only the tags it reads (`board`), the firmware's list in
/// the same order (firmware/src/render/tags.h).
public enum Tags {
    /// Every tag: the calendar's, the board's own two for how busy the
    /// agents are, the tiers, your hands, the Mac's side, then the rest
    /// of you at the Mac: in the board's order, the newest last, so no
    /// pack's numbering of the older ones moves.
    public static let all = Days.calendarTags + ["busy", "frantic"] + tiers.map(\.tag) + hands + macSides + along
        + [Anchor.Side.up.tag, "speaking"]

    /// Your hands at the Mac (`Hands`): the gel types along while you type,
    /// and watches the work with you while you read.
    public static let hands = [Hands.typing, .reading].map(\.rawValue)
    /// The side of Boop the Mac is on (`Anchor.side`): where the gel turns
    /// when something needs you. `macup`, the screen above Boop, came later,
    /// so it's last of all.
    public static let macSides = [Anchor.Side.left, .right].map(\.tag)
    /// The rest of you at the Mac (`Along`): scrolling (`Hands`), typing
    /// fast, music playing, on a call, and which way you scroll. The way
    /// took the places of `video` and `copied`, which are no longer sent, so
    /// no tag after them changes its number on the board.
    public static let along = ["scrolling", "typingfast", "music", "scrollup", "oncall", "scrolldown"]

    /// The tags the board reads, in its order: all of them.
    public static let board = all


    /// The tiers, by how long the agents have worked (their working
    /// stretch, `Core.stretch`) or sat idle (since the latest session came
    /// to rest: a turn ended, or you dismissed a request): `tier1` from a
    /// minute, `tier2` from 5 and `tier3` from 15, the last, where it
    /// stays. Working and idle share them, as a design's look says which
    /// it's for. Before the first minute the looks need no tag.
    public static let tiers: [(tag: String, fromMs: Int64)] = [
        ("tier1", 60_000), ("tier2", 300_000), ("tier3", 900_000),
    ]

    /// The tier reached after `ms`, the last. Only it is sent, to keep the
    /// `state` line short: the board takes every tier below it as on too
    /// (`render::reached`), so a design for `tier2` shows from then on.
    public static func tier(after ms: Int64) -> String? {
        tiers.last { ms >= $0.fromMs }?.tag
    }

    /// A rest shorter than this doesn't end a working stretch: a quick
    /// reply between turns keeps the working tiers climbing.
    public static let stretchRestMs: Int64 = 30_000
}
