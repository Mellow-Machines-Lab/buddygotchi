import Foundation

/// The character's moods and the moves between them, read from its pack
/// (characters/CHARACTER.md §5): every pack has the same moods
/// (`CharacterPack.universalMoods`) and its own moves and pacing. A mood
/// only ever moves to one of its neighbours, one step a pass; staying is
/// always allowed and isn't a move. An ordinary move is a small, plausible
/// change; a dramatic one is a jump that needs a fresh, big event. A move's
/// reverse may be of the other kind, or not exist. Which moves are offered
/// now is MoodPolicy's to say, by the pack's pacing.
public enum MoodGraph {
    /// Every mood, in the pack's order.
    public static var moods: [String] { CharacterPack.active.moods.map(\.id) }

    /// Where a mood can move, in the pack's order.
    public struct Moves: Equatable, Sendable {
        public let ordinary: [String]
        public let dramatic: [String]
        /// Every neighbour: the ordinary moves, then the dramatic ones.
        public var all: [String] { ordinary + dramatic }
    }

    /// One mood as the pack has it, or nil for a word that isn't a mood.
    public static func mood(_ id: String) -> CharacterPack.Mood? { CharacterPack.active.byId[id] }

    /// Each mood's moves.
    public static var moves: [String: Moves] { CharacterPack.active.byId.mapValues(\.moves) }

    /// The pack's timings, which MoodPolicy offers moves by.
    public static var pacing: CharacterPack.Pacing { CharacterPack.active.pacing }
}
