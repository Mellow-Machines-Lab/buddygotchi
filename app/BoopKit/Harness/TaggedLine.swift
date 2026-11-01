import Foundation

/// One line of a pack's list of lines, such as `dreams.md` or `signs.md`:
/// `- [failed long] Its words.`, the tags in brackets optional. It fits a
/// moment that has every one of its tags.
public struct TaggedLine: Equatable, Sendable {
    public var tags: [String]
    public var text: String

    public init(tags: [String], text: String) {
        self.tags = tags
        self.text = text
    }

    /// Whether its words take one of yours (`{words}` or `{WORDS}`).
    public var hasWords: Bool { text.contains("{words}") || text.contains("{WORDS}") }

    /// Its parts, split on ` | `: one for a plain line, more for one that
    /// says several things (an ask's question and its two answers).
    public var parts: [String] { text.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) } }

    /// Whether `on` has all of its tags.
    public func fits(_ on: Set<String>) -> Bool { Set(tags).isSubset(of: on) }

    /// A file's lines: each `- ` line, its tags read off; anything else
    /// (a comment, a heading) is skipped.
    public static func parse(_ text: String) -> [TaggedLine] {
        text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") else { return nil }
            var body = String(line.dropFirst(2))
            var tags: [String] = []
            if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
                tags = body[body.index(after: body.startIndex)..<close].split(separator: " ").map(String.init)
                body = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            return TaggedLine(tags: tags, text: body)
        }
    }
}
