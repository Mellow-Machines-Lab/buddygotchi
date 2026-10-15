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

    /// Which of the brain's questions a take answers:
    /// how Boop feels (`say.feeling`) or what NOW is about (`say.about`).
    /// Needs you's takes are in the pack, but Boop never says them.
    public enum Part: String, CaseIterable, Sendable {
        case feeling, about, attention
    }

    /// The board's id for it, as `say.take` sends it.
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
    /// The version of the voice pack these takes are in, as the board
    /// reports it: the character pack's `mac/takes.tsv`'s
    /// (characters/CHARACTER.md §8), or "" for a pack with no voice.
    public static var packVersion: String { table.version }

    /// Every take the board has, in the bank's order; none for a pack with
    /// no voice.
    public static var all: [Take] { table.takes }

    /// The character pack's take table, read the first time it's used.
    private static let table: (version: String, takes: [Take]) = {
        let file = CharacterPack.active.directory.appendingPathComponent("mac/takes.tsv")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return ("", []) }
        let lines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        guard let version = lines.first else { return ("", []) }
        return (String(version), lines.dropFirst().compactMap(Take.init(parsing:)))
    }()

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
