import Foundation

/// The only code that reads or writes Boop's memory:
/// `long-term.md`, who this Boop is, and `diary.md`, a line a day. It reads it once, when it opens,
/// writes atomically, keeps copies in `history/`, and restores a file that
/// won't parse.
///
/// Hand edits are welcome: the app never writes `long-term.md` after setup,
/// and reads it at launch.
public final class MemoryStore {
    public static let longTermFile = "long-term.md"
    public static let diaryFile = "diary.md"
    public static let historyDir = "history"

    public let directory: URL
    let log: (String) -> Void

    public private(set) var longTerm: LongTerm?
    /// The diary's lines, oldest first, as the file had them at open and
    /// with every line added since.
    private var diaryLines: [(day: String, line: String)] = []

    /// Opens the store as a launch on `today` does.
    public init(directory: URL, today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000)),
                log: @escaping (String) -> Void = { _ in }) throws {
        self.directory = directory
        self.log = log
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadLongTerm(today: today)
        diaryLines = Self.parseDiary((try? String(contentsOf: url(Self.diaryFile), encoding: .utf8)) ?? "")
    }

    public var isSetUp: Bool { longTerm != nil }

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

    /// Adds `line` to the diary under `day` (`## 2026-10-21`), once a day:
    /// a day already written keeps its line.
    public func appendDiary(day: String, line: String) throws {
        let old = (try? String(contentsOf: url(Self.diaryFile), encoding: .utf8)) ?? "# \(longTerm?.name ?? "Boop")'s diary\n"
        guard !old.contains("\n## \(day)\n") else { return }
        try write(old + "\n## \(day)\n\(line)\n", Self.diaryFile)
        diaryLines.append((day, line))
    }

    /// The diary's last `count` days, newest first.
    public func diary(last count: Int) -> [(day: String, line: String)] {
        Array(diaryLines.suffix(count).reversed())
    }

    /// `diary.md`'s days and lines, oldest first.
    static func parseDiary(_ text: String) -> [(day: String, line: String)] {
        var out: [(day: String, line: String)] = []
        var day: String?
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") { day = String(line.dropFirst(3)) } else if let d = day, !line.isEmpty, !line.hasPrefix("#") {
                out.append((d, line))
                day = nil
            }
        }
        return out
    }

    /// Atomic: a temporary file renamed over the old one.
    func write(_ text: String, _ file: String) throws {
        try Data(text.utf8).write(to: url(file), options: .atomic)
    }
}
