import Foundation

/// One line of a pack's list of lines, such as `diary.md` or `signs.md`:
/// `- [failed long] Its words.`, the tags in brackets optional. It fits a
/// moment that has every one of its tags.
public struct TaggedLine: Equatable, Sendable {
    public var tags: [String]
    public var text: String

    public init(tags: [String], text: String) {
        self.tags = tags
        self.text = text
    }

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
