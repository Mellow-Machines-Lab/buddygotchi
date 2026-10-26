import Foundation

/// One recorded take the board can play: a word, a sound, a
/// phrase or a swear, performed in one of Boop's moods, and played in
/// that mood's face and any the pack lends it to. The list is
/// `Take.all`, which voicegen writes from the voice bank.
public struct Take: Equatable, Sendable {
    /// How a take says its meaning, from the plainest up: Voice takes the
    /// nearest kind to the one asked for when there's none of it.
    public enum Kind: String, CaseIterable, Sendable {
        case sound, word, phrase, swear
    }

    /// Which of `say`'s answers a take says: how Boop feels, or what NOW
    /// is about; or a reply's own words, to what you said on push-to-talk,
    /// its meaning the reply's name.
    /// Needs you's takes are in the pack, but Boop never says them.
    public enum Part: String, CaseIterable, Sendable {
        case feeling, about, reply, attention
    }

    /// The board's id for it, as `say.take` sends it. A take that's also a
    /// reply's words is in the table again under its id, as that reply.
    public let id: String
    /// What it says, as the bubble shows it and HISTORY reads it.
    public let text: String
    public let part: Part
    /// Its answer to its part's question, such as `upset` or `tests`.
    public let meaning: String
    public let kind: Kind
    /// The moods whose faces it plays in, and only those: the one it was
    /// performed in, then any the pack lends it to, so every mood has
    /// takes (characters/CHARACTER.md §8).
    public let moods: [String]
    /// The finish it needs (`success` or `failure`), or nil for any.
    public let finish: String?
    /// How long it plays on the board, in milliseconds.
    public let ms: Int
}

extension Take {
    /// The version of the voice file these takes are in, as the board
    /// reports it: the character pack's `mac/takes.tsv`'s
    /// (characters/CHARACTER.md §8), or "" for a pack with no voice.
    public static var voiceVersion: String { table().version }

    /// Every take the board has, in the bank's order; none for a pack with
    /// no voice.
    public static var all: [Take] { table().takes }

    /// Every take of `pack`'s voice.
    public static func all(in pack: CharacterPack) -> [Take] { table(pack).takes }

    /// A pack's take table, each read the first time it's used.
    private static func table(_ pack: CharacterPack = .active) -> (version: String, takes: [Take]) {
        tables.get(pack.directory) { directory in
            let file = directory.appendingPathComponent("mac/takes.tsv")
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { return ("", []) }
            let lines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
            guard let version = lines.first else { return ("", []) }
            return (String(version), lines.dropFirst().compactMap(Take.init(parsing:)))
        }
    }

    private static let tables = PackCache<(version: String, takes: [Take])>()

    /// A take from its line in the table: id, text, part, meaning, kind,
    /// moods (space separated), finish (empty for any) and milliseconds,
    /// tab separated.
    /// voicegen writes the table, and VoiceTests reads it back against the
    /// pack, so a bad line can't ship.
    init(row: Substring) { self = Take(parsing: row)! }

    /// A take from its line in the table, or nil for a line that isn't one.
    public init?(parsing row: Substring) {
        let f = row.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 8, let part = Part(rawValue: f[2]), let kind = Kind(rawValue: f[4]), let ms = Int(f[7]) else { return nil }
        self.init(id: f[0], text: f[1], part: part, meaning: f[3], kind: kind, moods: f[5].split(separator: " ").map(String.init), finish: f[6].isEmpty ? nil : f[6], ms: ms)
    }
}
