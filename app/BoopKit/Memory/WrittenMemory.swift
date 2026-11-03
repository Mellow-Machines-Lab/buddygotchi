import Foundation
import MellowHarness

/// The written memory, `memory.md`: short notes in three sections (You,
/// Your work, You and Boop) that the dream edits as Boop dreams
/// (`MemoryEdits`), and a line a day for the last week (Recently). Jev
/// reads it as MEMORY. Plain Markdown the person may read and edit: a
/// deleted line is gone for good, "pinned" keeps a note from aging and
/// from the night's edits, and a line it can't read is kept as it is and
/// ignored. Only `MemoryStore` reads and writes the file.
public struct WrittenMemory: Equatable, Sendable {
    public enum Section: String, CaseIterable, Sendable {
        case you, work, boop

        /// Its heading in the file and in MEMORY.
        public var heading: String {
            switch self {
            case .you: "You"
            case .work: "Your work"
            case .boop: "You and Boop"
            }
        }

        /// You and Boop is the lasting mark: its notes never age out, and
        /// the night's edits may update one but never drop it.
        public var lasting: Bool { self == .boop }
    }

    public struct Note: Equatable, Sendable {
        public var id: Int
        public var section: Section
        /// The days it comes from, `yyyy-MM-dd`, oldest first.
        public var days: [String]
        public var pinned: Bool
        public var text: String

        public init(id: Int, section: Section, days: [String], pinned: Bool = false, text: String) {
            self.id = id
            self.section = section
            self.days = days
            self.pinned = pinned
            self.text = text
        }

        /// The last day it cites, from which it ages.
        public var last: String { days.max() ?? "" }
    }

    /// One of Recently's lines: a day and what happened in it.
    public struct Day: Equatable, Sendable {
        public var day: String
        public var text: String

        public init(day: String, text: String) {
            self.day = day
            self.text = text
        }
    }

    public var notes: [Note] = []
    /// The newest first, at most `recentDays`.
    public var recently: [Day] = []
    /// Lines a section had that don't read, kept as they were.
    public var unread: [String: [String]] = [:]

    public static let fileName = "memory.md"
    /// The most notes a section keeps, the days Recently keeps, and how
    /// long after the last day it cites a note in You or Your work lasts.
    public static let perSection = 4, recentDays = 7, ageDays = 30

    public init(notes: [Note] = [], recently: [Day] = []) {
        self.notes = notes
        self.recently = recently
    }

    public func notes(in section: Section) -> [Note] { notes.filter { $0.section == section } }

    /// The notes' ids, section by section: the numbers 1 to N a dream's
    /// edits call them by.
    public var numbered: [Int] { Section.allCases.flatMap { notes(in: $0).map(\.id) } }

    /// The next note's id.
    public var nextId: Int { (notes.map(\.id).max() ?? 0) + 1 }

    static let recentlyHeading = "Recently"
    static let intro = """
        Written on this Mac as Boop dreams. Delete a line to
        make Boop forget it, or add "pinned" to keep it.
        """

    /// The file.
    public var markdown: String {
        var out = "# Boop's memory\n\n\(Self.intro)\n"
        for section in Section.allCases {
            out += "\n## \(section.heading)\n"
            for n in notes(in: section) {
                out += "- m\(n.id) · " + (n.pinned ? "pinned · " : "") + n.days.joined(separator: ", ") + " · \(n.text)\n"
            }
            for raw in unread[section.heading] ?? [] { out += raw + "\n" }
        }
        out += "\n## \(Self.recentlyHeading)\n"
        for d in recently { out += "- \(d.day) · \(d.text)\n" }
        for raw in unread[Self.recentlyHeading] ?? [] { out += raw + "\n" }
        return out
    }

    /// A written memory from its lines as `memory.md` writes them without
    /// the id: notes as `work · 2026-10-25 · "api" kept failing` (numbered
    /// in order), Recently as `2026-10-25 · a long day`. Nil when one
    /// doesn't read: for the evals and the writer's fixtures.
    public static func from(notes: [String], recently: [String] = []) -> WrittenMemory? {
        let file = Section.allCases.map { section in
            "## \(section.heading)\n" + notes.enumerated().filter { $0.element.hasPrefix(section.rawValue + " · ") }
                .map { "- m\($0.offset + 1) · " + $0.element.dropFirst(section.rawValue.count + 3) }.joined(separator: "\n")
        }.joined(separator: "\n") + "\n## \(recentlyHeading)\n" + recently.map { "- " + $0 }.joined(separator: "\n")
        let memory = parse(file)
        return memory.notes.count == notes.count && memory.recently.count == recently.count ? memory : nil
    }

    /// Reads the file, keeping each line it can't read in its section.
    public static func parse(_ text: String) -> WrittenMemory {
        var memory = WrittenMemory()
        var heading: String?
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let heading, line.hasPrefix("- ") else { continue }
            let parts = line.dropFirst(2).components(separatedBy: " · ")
            if heading == recentlyHeading {
                if parts.count >= 2, LocalTime.isDay(parts[0]) {
                    memory.recently.append(Day(day: parts[0], text: parts.dropFirst().joined(separator: " · ")))
                } else {
                    memory.unread[heading, default: []].append(raw)
                }
                continue
            }
            guard let section = Section.allCases.first(where: { $0.heading == heading }) else { continue }
            var rest = ArraySlice(parts)
            guard let first = rest.first, first.hasPrefix("m"), let id = Int(first.dropFirst()) else {
                memory.unread[heading, default: []].append(raw)
                continue
            }
            rest = rest.dropFirst()
            let pinned = rest.first?.lowercased() == "pinned"
            if pinned { rest = rest.dropFirst() }
            let days = rest.first?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            guard rest.count >= 2, !days.isEmpty, days.allSatisfy(LocalTime.isDay), !memory.notes.contains(where: { $0.id == id }) else {
                memory.unread[heading, default: []].append(raw)
                continue
            }
            memory.notes.append(Note(id: id, section: section, days: days, pinned: pinned,
                                     text: rest.dropFirst().joined(separator: " · ")))
        }
        memory.recently.sort { $0.day > $1.day }
        return memory
    }

    /// What Jev reads on every pass, under the MEMORY heading, at most
    /// `budget` tokens: Recently cut to its last 3 days first, then the
    /// oldest notes go. Nil with nothing in it. `today` names the days of
    /// Recently ("Yesterday", "2 days ago").
    public func section(today: String, budget: Int = Steering.Budget.memory) -> String? {
        var recent = recently
        var kept = notes
        func render() -> String {
            var lines = ["MEMORY (what Boop remembers. You and Boop is who Boop has become with you. Whenever more than one face or mood fits NOW, pick the one it points to. The rest is old news unless NOW is about it: it can make a face or a moment bigger, never change what NOW says happened.)"]
            for s in Section.allCases {
                let these = kept.filter { $0.section == s }
                if !these.isEmpty { lines.append("\(s.heading): " + these.map(\.text).joined(separator: " ")) }
            }
            if !recent.isEmpty {
                lines.append("Recently: " + recent.map { "\(Self.ago($0.day, today: today)), \(Self.lowered($0.text))" }.joined(separator: " "))
            }
            return lines.joined(separator: "\n")
        }
        guard !kept.isEmpty || !recent.isEmpty else { return nil }
        if recent.count > 3, Steering.tokens(render()) > budget { recent = Array(recent.prefix(3)) }
        while Steering.tokens(render()) > budget, let oldest = kept.indices.min(by: { kept[$0].last < kept[$1].last }) {
            kept.remove(at: oldest)
        }
        while Steering.tokens(render()) > budget, !recent.isEmpty { recent.removeLast() }
        return render()
    }

    /// `day` as Recently says it on `today`: Yesterday, 3 days ago.
    static func ago(_ day: String, today: String) -> String {
        guard let d = LocalTime.dayNumber(day), let t = LocalTime.dayNumber(today) else { return day }
        switch t - d {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case let n: return "\(n) days ago"
        }
    }

    /// A Recently line after its day: "Friday: a long day" reads "a long
    /// day", its weekday said by the day already.
    static func lowered(_ text: String) -> String {
        guard let colon = text.firstIndex(of: ":"), LocalTime.weekdays.contains(String(text[..<colon])) else { return text }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
}
