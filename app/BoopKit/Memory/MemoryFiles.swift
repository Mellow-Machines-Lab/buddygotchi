import Foundation

public struct MemoryParseError: Error, Equatable, CustomStringConvertible {
    public var description: String
    init(_ description: String) { self.description = description }
}

/// `long-term.md`: who this Boop is.
public struct LongTerm: Equatable, Sendable {
    public var name: String
    public var hatched: String
    /// Seeds Boop's randomness (the core's and the view's). Written as hex.
    public var seed: UInt64

    public init(name: String, hatched: String, seed: UInt64) {
        self.name = name
        self.hatched = hatched
        self.seed = seed
    }

    public var markdown: String {
        "## Boop\nname: \(name) · hatched: \(hatched) · seed: \(String(seed, radix: 16))\n"
    }

    /// Reads the file. Hand edits are fine as long as the Boop line still
    /// reads. Other sections, like the ones files from before 2026-09-27
    /// have, are left out and left alone.
    public static func parse(_ text: String) throws -> LongTerm {
        guard let boop = firstLine(under: "Boop", in: text) else { throw MemoryParseError("no Boop line") }
        let fields = keyValues(boop)
        guard let name = fields["name"], !name.isEmpty, let hatched = fields["hatched"], LocalTime.isDay(hatched),
              let seed = fields["seed"].flatMap({ UInt64($0, radix: 16) })
        else { throw MemoryParseError("the Boop line doesn't read: \(boop)") }
        return LongTerm(name: name, hatched: hatched, seed: seed)
    }
}

/// The first non-empty line under a `##` or `###` heading titled `title`.
private func firstLine(under title: String, in text: String) -> String? {
    var current: String?
    for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("#") {
            current = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        } else if current == title, !line.isEmpty {
            return line
        }
    }
    return nil
}

/// `key: value · key: value`.
private func keyValues(_ line: String) -> [String: String] {
    var values: [String: String] = [:]
    for part in line.components(separatedBy: "·") {
        guard let colon = part.firstIndex(of: ":") else { continue }
        let key = part[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        values[key] = part[part.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    return values
}
