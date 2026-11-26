import Foundation

/// One line of a pack's list of lines, such as `dreams.md` or `signs.md`:
/// `- [failed long] Its words.`, the tags in brackets optional. It fits a
/// moment that has every one of its tags.
public struct TaggedLine: Equatable, Sendable {
    public var tags: [String]
    public var text: String
    /// The recorded sentence that says it, by its id, from a `take=…` in
    /// its brackets (`- [aside win take=win.all-yours] Done! {what}, all
    /// yours.`): never a tag, which a moment would have to have. Nil for a
    /// line no take says. The board plays it when its voice has it
    /// (`Take.Part.sentence`).
    public var take: String?

    public init(tags: [String], text: String, take: String? = nil) {
        self.tags = tags
        self.text = text
        self.take = take
    }

    /// Whether its words take one of yours (`{words}` or `{WORDS}`).
    public var hasWords: Bool { text.contains("{words}") || text.contains("{WORDS}") }

    /// Its parts, split on ` | `: one for a plain line, more for one that
    /// says several things (an ask's question and its two answers).
    public var parts: [String] { text.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) } }

    /// Whether `on` has all of its tags.
    public func fits(_ on: Set<String>) -> Bool { Set(tags).isSubset(of: on) }

    static let takePrefix = "take="

    /// A file's lines: each `- ` line, its tags read off; anything else
    /// (a comment, a heading) is skipped.
    public static func parse(_ text: String) -> [TaggedLine] {
        text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") else { return nil }
            var body = String(line.dropFirst(2))
            var tags: [String] = []
            var take: String?
            if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
                tags = body[body.index(after: body.startIndex)..<close].split(separator: " ").map(String.init)
                body = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            if let named = tags.first(where: { $0.hasPrefix(takePrefix) }) {
                take = String(named.dropFirst(takePrefix.count))
                tags.removeAll { $0.hasPrefix(takePrefix) }
            }
            return TaggedLine(tags: tags, text: body, take: take)
        }
    }
}
