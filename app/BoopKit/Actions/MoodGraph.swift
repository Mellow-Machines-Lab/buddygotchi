import Foundation

/// Boop's 13 moods and the moves between them:
/// the owner's approved graph,
/// characters/pixel/design/boop-mood-spectrum-v2/mood-graph.json, which a
/// test holds this copy to. A mood only ever moves to one of its
/// neighbours, one step a pass; staying is always allowed and isn't a
/// move. An ordinary move is a small, plausible change; a dramatic one is
/// a jump that needs a fresh, big event. A move's reverse may be of the
/// other kind, or not exist. V2 pacing stays in steering; opt-in v3 uses
/// MoodPolicy and the generated MoodGraphV3 catalog.
public enum MoodGraph {
    /// Every mood, in the pixel designs' order (faces.h): the character
    /// pack's `moods_v2`, which a test holds to the faces facegen writes.
    public static var moods: [String] { CharacterPack.active.v2Names }

    /// Where a mood can move, in the graph file's order.
    public struct Moves: Equatable, Sendable {
        public let ordinary: [String]
        public let dramatic: [String]
        /// Every neighbour: the ordinary moves, then the dramatic ones.
        public var all: [String] { ordinary + dramatic }
    }

    /// Each mood's moves, from the pack's `moods_v2`.
    public static var moves: [String: Moves] { CharacterPack.active.movesV2 }

    /// Where `mood` can move: its ordinary moves, then its dramatic ones;
    /// none for a word that isn't a mood.
    public static func neighbours(of mood: String) -> [String] { moves[mood]?.all ?? [] }

    /// Whether `from` can move to `to` in one step. Staying isn't a move.
    public static func isMove(from: String, to: String) -> Bool { neighbours(of: from).contains(to) }
}

extension MoodGraph {
    /// Per-runtime rollout switch; changing settings takes effect on launch.
    public enum Version: String, Codable, Sendable { case v2, v3 }
    public static func moods(for version: Version) -> [String] { version == .v3 ? MoodGraphV3.moods : moods }
    public static func moves(for version: Version) -> [String: Moves] {
        version == .v3 ? MoodGraphV3.nodes.mapValues(\.moves) : moves
    }
    /// The retained mood standing in for a v3 one: what a pixel device
    /// draws, and whose voice a reaction's takes are in, since the takes were
    /// recorded in the retained moods only. Never a change to
    /// the logical mood. A retained mood stands for itself: a pack with no
    /// `moods_v2` has only retained moods, each with the resting mood as
    /// its v3 fallback.
    public static func pixelFallback(_ mood: String) -> String {
        moods.contains(mood) ? mood : MoodGraphV3.nodes[mood]?.fallback ?? MoodAction.initial
    }
}
