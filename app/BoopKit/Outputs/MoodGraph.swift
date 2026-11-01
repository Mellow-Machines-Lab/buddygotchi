import Foundation

/// The character's lasting moods and the moves between them, read from its
/// pack (characters/CHARACTER.md §5): every pack has the same moods
/// (`CharacterPack.universalMoods`), each a face, and its own lasting ones
/// and moves. A mood only ever moves to one of its neighbours, one step a pass; staying is
/// always allowed and isn't a move. An ordinary move is a small, plausible
/// change; a dramatic one is a jump that needs a fresh, big event. A move's
/// reverse may be of the other kind, or not exist. The mood question offers
/// every move; which fits now, and how soon, is the steering's to say.
public enum MoodGraph {
    /// Every lasting mood, in the pack's order.
    public static var moods: [String] { CharacterPack.active.lasting.map(\.id) }

    /// Where a mood can move, in the pack's order.
    public struct Neighbours: Equatable, Sendable {
        public let ordinary: [String]
        public let dramatic: [String]
        /// Every neighbour: the ordinary moves, then the dramatic ones.
        public var all: [String] { ordinary + dramatic }
    }

    /// One lasting mood as the pack has it, or nil for a word that isn't one.
    public static func mood(_ id: String, in pack: CharacterPack = .active) -> CharacterPack.Mood? {
        pack.byId[id].flatMap { $0.lasting ? $0 : nil }
    }

    /// Each lasting mood's moves.
    public static var neighbours: [String: Neighbours] {
        Dictionary(uniqueKeysWithValues: CharacterPack.active.lasting.map { ($0.id, $0.neighbours) })
    }
}
