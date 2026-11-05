import Foundation

/// The only code that reads or writes Boop's memory:
/// `long-term.md`, who this Boop is. It reads it once, when it opens,
/// writes atomically, keeps copies in `history/`, and restores a file that
/// won't parse.
///
/// Hand edits are welcome: the app never writes `long-term.md` after setup,
/// and reads it at launch.
public final class MemoryStore {
    public static let longTermFile = "long-term.md"
    public static let historyDir = "history"

    public let directory: URL
    let log: (String) -> Void

    public private(set) var longTerm: LongTerm?

    /// Opens the store as a launch on `today` does.
    public init(directory: URL, today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)),
                log: @escaping (String) -> Void = { _ in }) throws {
        self.directory = directory
        self.log = log
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadLongTerm(today: today)
    }

    public var isSetUp: Bool { longTerm != nil }
    /// The name it was given at setup, once it's set up.
    public var name: String? { longTerm?.name }

    /// Creates `long-term.md` for a new Boop, and its copy in
    /// `history/<today>/`. Refuses if one exists.
    public func setUp(name: String, seed: UInt64, today: String) throws {
        guard longTerm == nil else { throw Refusal("already set up") }
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty, clean.count <= 23, !clean.contains("·"), !clean.contains(":"), !clean.contains("\n")
        else { throw Refusal("a name is 1–23 characters, without · or :") }
        let lt = LongTerm(name: clean, hatched: today, seed: seed)
        try write(lt.markdown, Self.longTermFile)
        longTerm = lt
        try keepCopy(lt.markdown, day: today)
    }

    // MARK: The written memory

    /// `memory.md`, as it is now: empty before the first dream's write.
    public func written() -> WrittenMemory {
        (try? String(contentsOf: url(WrittenMemory.fileName), encoding: .utf8)).map(WrittenMemory.parse) ?? WrittenMemory()
    }

    /// Writes `memory.md`, with a copy in `history/<day>/`.
    public func keep(_ memory: WrittenMemory, day: String) throws {
        try write(memory.markdown, WrittenMemory.fileName)
        let dir = historyURL(day)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(memory.markdown.utf8).write(to: dir.appendingPathComponent(WrittenMemory.fileName), options: .atomic)
    }

    /// `memory-days.json`: what the proposer counts habits from, a digest a
    /// dream, and the notes it has added, so one you deleted stays gone.
    public struct Days: Codable, Equatable, Sendable {
        public var digests: [DayDigest] = []
        /// The notes the dream added, in the words they have now: one here
        /// but not in `memory.md` is one you deleted.
        public var added: [String] = []
        /// Each note's short line in the pet's voice, by the note's text, ""
        /// for a note whose line the checks refused.
        public var signs: [String: String] = [:]
        public init() {}

        /// As `DayDigest`: a field the file doesn't have takes its default.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            digests = try c.decodeIfPresent([DayDigest].self, forKey: .digests) ?? []
            added = try c.decodeIfPresent([String].self, forKey: .added) ?? []
            signs = try c.decodeIfPresent([String: String].self, forKey: .signs) ?? [:]
        }

        /// The most digests kept: more than the proposer looks at.
        public static let kept = 60, addedKept = 200

        /// With `digest` in, joined to one for the same day, and `notes` added.
        public func keeping(_ digest: DayDigest, added notes: [String]) -> Days {
            var out = self
            if let i = out.digests.lastIndex(where: { $0.day == digest.day }) {
                out.digests[i] = out.digests[i].joined(with: digest)
            } else {
                out.digests.append(digest)
            }
            out.digests = Array(out.digests.suffix(Self.kept))
            out.added = Array((out.added + notes).suffix(Self.addedKept))
            return out
        }

        /// `added` as a dream's edits leave it, from `before` to `next`: a
        /// note it updated goes by its new words, and one it let go (dropped
        /// to make room, or aged out) isn't one you deleted, so it may come
        /// back. New notes join it.
        public func following(_ report: MemoryEdits.Report, from before: WrittenMemory, to next: WrittenMemory) -> Days {
            func text(_ id: Int, _ memory: WrittenMemory) -> String? { memory.notes.first { $0.id == id }?.text }
            var out = self
            for id in report.updated {
                guard let old = text(id, before), let new = text(id, next), let i = out.added.firstIndex(of: old) else { continue }
                out.added[i] = new
            }
            let gone = (report.dropped + report.aged).compactMap { text($0, before) }
            out.added.removeAll(where: gone.contains)
            out.added = Array((out.added + report.added.compactMap { text($0, next) }).suffix(Self.addedKept))
            return out
        }
    }

    public static let daysFile = "memory-days.json"

    /// Forgets what the kept files hold about you, with `memory.md` as you
    /// left it: the digests but for their care counts (`DayDigest.forgotten`),
    /// a note in `added` that quotes anything and is gone (the rest stay
    /// there, so those stay gone), the lines of notes gone, a bad file moved
    /// aside, and every older copy of `memory.md` in `history/`.
    public func forgetLearned() throws {
        let memory = written()
        let notes = Set(memory.notes.map(\.text))
        var days = days()
        days.digests = days.digests.map(\.forgotten)
        days.added.removeAll { $0.contains("\"") && !notes.contains($0) }
        days.signs = days.signs.filter { notes.contains($0.key) }
        try keep(days)
        try? FileManager.default.removeItem(at: url(Self.daysFile + ".broken"))
        let history = directory.appendingPathComponent(Self.historyDir).path
        for day in (try? FileManager.default.contentsOfDirectory(atPath: history)) ?? [] {
            let copy = historyURL(day).appendingPathComponent(WrittenMemory.fileName)
            if let text = try? String(contentsOf: copy, encoding: .utf8), text != memory.markdown { try FileManager.default.removeItem(at: copy) }
        }
    }

    /// The kept days. A file that won't read moves aside, as
    /// `memory-days.json.broken`, so the next write doesn't take it with it.
    public func days() -> Days {
        guard let data = try? Data(contentsOf: url(Self.daysFile)) else { return Days() }
        do {
            return try JSONDecoder().decode(Days.self, from: data)
        } catch {
            keepBroken(Self.daysFile)
            try? FileManager.default.removeItem(at: url(Self.daysFile))
            log("memory: \(Self.daysFile) didn't read (\(error)); moved it to \(Self.daysFile).broken, and the days start again")
            return Days()
        }
    }

    public func keep(_ days: Days) throws {
        try write(String(decoding: try JSONEncoder().encode(days), as: UTF8.self), Self.daysFile)
    }

    // MARK: The daily counts

    public static let countsFile = "daily-counts.jsonl"
    /// The most rows kept: more than a year.
    public static let countsKept = 400

    /// The rows in `directory`, oldest first. Read with no store opened, so
    /// asking for them changes nothing. A line that won't read is skipped.
    public static func counts(in directory: URL) -> [DayCounts] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(countsFile), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(DayCounts.self, from: Data($0.utf8)) }
    }

    /// Writes `row`, replacing its day's.
    public func keep(_ row: DayCounts) throws {
        var rows = Self.counts(in: directory).filter { $0.day != row.day }
        rows.append(row)
        rows.sort { $0.day < $1.day }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let lines = try rows.suffix(Self.countsKept).map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        try write(lines.joined(separator: "\n") + "\n", Self.countsFile)
    }

    // MARK: Files

    func url(_ file: String) -> URL { directory.appendingPathComponent(file) }
    func historyURL(_ day: String) -> URL { directory.appendingPathComponent(Self.historyDir).appendingPathComponent(day) }

    /// Missing, it waits for setup. One that reads but isn't the newest copy
    /// in `history/`, a hand edit, is copied to `history/<today>/`, or over
    /// the newest copy when the clock is behind it, so a later break brings
    /// the edit back. One that won't parse is kept as `long-term.md.broken`
    /// and comes back from the newest copy that reads: setup's, an edit's,
    /// or a day's that older apps kept.
    func loadLongTerm(today: String) {
        let file = Self.longTermFile
        // An I/O failure says nothing about the contents: leave the file
        // alone, as when it is missing, instead of restoring over it.
        guard let data = try? Data(contentsOf: url(file)) else { longTerm = nil; return }
        let copy = newestCopy()
        do {
            guard let text = String(data: data, encoding: .utf8) else { throw MemoryParseError("not UTF-8") }
            longTerm = try LongTerm.parse(text)
            guard text != copy?.text else { return }
            let day = max(today, copy?.day ?? today)
            do {
                try keepCopy(text, day: day)
                log("memory: \(file) was edited; kept a copy in history/\(day)")
            } catch {
                log("memory: copying \(file) to history/\(day) failed: \(error)")
            }
        } catch {
            keepBroken(file)
            guard let copy else {
                log("memory: \(file) didn't read (\(error)) and there's no copy in history; kept it as \(file).broken")
                return
            }
            log("memory: \(file) didn't read (\(error)); restored from history/\(copy.day), kept the old one as \(file).broken")
            longTerm = copy.longTerm
            try? write(copy.text, file)
        }
    }

    /// The newest copy of `long-term.md` in `history/` that reads.
    func newestCopy() -> (day: String, text: String, longTerm: LongTerm)? {
        let history = directory.appendingPathComponent(Self.historyDir).path
        let days = ((try? FileManager.default.contentsOfDirectory(atPath: history)) ?? []).filter(LocalTime.isDay).sorted(by: >)
        for day in days {
            guard let text = try? String(contentsOf: historyURL(day).appendingPathComponent(Self.longTermFile), encoding: .utf8),
                  let longTerm = try? LongTerm.parse(text)
            else { continue }
            return (day, text, longTerm)
        }
        return nil
    }

    /// Writes `text` to `history/<day>/long-term.md`, replacing a copy there.
    func keepCopy(_ text: String, day: String) throws {
        let dir = historyURL(day)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: dir.appendingPathComponent(Self.longTermFile), options: .atomic)
    }

    /// Copies a file that won't parse to `<file>.broken`.
    func keepBroken(_ file: String) {
        let broken = url(file + ".broken")
        try? FileManager.default.removeItem(at: broken)
        try? FileManager.default.copyItem(at: url(file), to: broken)
    }

    /// Atomic: a temporary file renamed over the old one.
    func write(_ text: String, _ file: String) throws {
        try Data(text.utf8).write(to: url(file), options: .atomic)
    }
}
