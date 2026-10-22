import Foundation
import MellowHarness

/// Boop's diary: one line a day, about yesterday, written on the first
/// pass of a new day. It asks one question then, and none on any other
/// pass: which of the pack's lines (`steering/diary.md`) Boop writes, each
/// filled in with yesterday's counts, the ones whose tags fit offered.
/// The counts come from the transcript's raw events, never from what was
/// said in them, and the question's text carries them, so the brain picks
/// a line that fits the day. The memory store writes it (`MemoryStore.
/// appendDiary`).
public final class DiaryOutput: Output {
    public static let outputName = "diary"
    public static let questionKey = "diary.line"
    /// The most lines a question offers.
    public static let maxOffered = 8

    /// One line of `diary.md`: the tags a day needs, all of them, for it to
    /// fit, and its words with `{turns}`, `{failed}`, `{longest}`,
    /// `{thread}`, `{pokes}` and `{weekday}` to fill in.
    public struct Template: Equatable, Sendable {
        public var tags: [String]
        public var text: String
    }

    /// What a day came to.
    public struct Day: Equatable, Sendable {
        public var day: String
        public var weekday: String
        public var turns = 0, failed = 0, pokes = 0
        /// The longest turn, in minutes, and the thread that ended the most turns.
        public var longestMinutes = 0
        public var thread = ""
        /// The day's tags: `failed` (one turn or more), `clean` (turns and
        /// none failed), `long` (a turn of 30 minutes or more), `quiet` (no
        /// turns), `poked` (5 pokes or more), and the calendar's
        /// (`Occasions.tags`, at noon).
        public var tags: [String] = []

        /// The counts in words, for the question.
        public var words: String {
            turns == 0 ? "no turns, \(pokes) pokes"
                : "\(turns) turns, \(failed) failed, the longest \(longestMinutes) min, the most on \"\(thread)\", \(pokes) pokes"
        }

        public func fill(_ text: String) -> String {
            [("{turns}", "\(turns)"), ("{failed}", "\(failed)"), ("{longest}", "\(longestMinutes)"), ("{thread}", thread),
             ("{pokes}", "\(pokes)"), ("{weekday}", weekday)].reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        }
    }

    public let name = outputName
    public let voice: String?
    let templates: [Template]
    let time: LocalTime
    let creature: String
    let write: (String, String) -> Void

    /// `templates` from the pack's `diary.md`, days on `time`'s calendar,
    /// `creature` the buddy's name, and `write` given each day and its line.
    public init(templates: [Template], time: LocalTime, creature: String, voice: String? = nil,
                write: @escaping (String, String) -> Void) {
        self.voice = voice
        self.templates = templates
        self.time = time
        self.creature = creature
        self.write = write
    }

    /// `diary.md`'s lines: `- [failed long] {weekday}. "{thread}" fell over {failed} times.`, the tags optional.
    public static func templates(_ text: String) -> [Template] {
        text.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ") else { return nil }
            var body = String(line.dropFirst(2))
            var tags: [String] = []
            if body.hasPrefix("["), let close = body.firstIndex(of: "]") {
                tags = body[body.index(after: body.startIndex)..<close].split(separator: " ").map(String.init)
                body = String(body[body.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
            return Template(tags: tags, text: body)
        }
    }

    /// The day before `now`'s, on the calendar.
    func yesterday(_ now: Int64) -> (day: String, noon: Int64) {
        let noon = now - 24 * 60 * 60 * 1000
        return (time.day(noon), noon)
    }

    /// Yesterday's, if it isn't written yet and anything happened in it.
    func due(_ now: Event?, _ log: LogView) -> Day? {
        guard let now else { return nil }
        let (day, at) = yesterday(now.at)
        if log.lastDid(Self.outputName, where: { $0["day"]?.string == day }) != nil { return nil }
        let events = log.events.filter { time.day($0.at) == day }
        guard !events.isEmpty else { return nil }
        return Self.count(events, day: day, weekday: time.weekday(at), tags: Occasions.tags(at: at, hatched: nil, time: time))
    }

    /// A day's counts from its raw events.
    static func count(_ events: [Event], day: String, weekday: String, tags calendar: [String]) -> Day {
        var d = Day(day: day, weekday: weekday)
        var started: [String: Int64] = [:]
        var threads: [String: Int] = [:]
        for e in events {
            if e.type == .poke { d.pokes += 1 }
            guard e.type == .turn, let session = e.session else { continue }
            if e.phase == .start { started[session] = e.at }
            if e.phase == .end {
                d.turns += 1
                if e["outcome"]?.string == "failed" { d.failed += 1 }
                if let from = started.removeValue(forKey: session) { d.longestMinutes = max(d.longestMinutes, Int((e.at - from) / 60_000)) }
                let thread = e.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "work"
                threads[thread, default: 0] += 1
            }
        }
        d.thread = threads.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? ""
        var tags: [String] = []
        if d.failed > 0 { tags.append("failed") }
        if d.turns > 0, d.failed == 0 { tags.append("clean") }
        if d.longestMinutes >= 30 { tags.append("long") }
        if d.turns == 0 { tags.append("quiet") }
        if d.pokes >= 5 { tags.append("poked") }
        d.tags = tags + calendar
        return d
    }

    /// The lines that fit `day`, filled in: those with tags first, in the
    /// file's order, then the rest, at most `maxOffered`.
    func offered(_ day: Day) -> [String] {
        let fit = templates.filter { Set($0.tags).isSubset(of: day.tags) }
        let ordered = fit.filter { !$0.tags.isEmpty } + fit.filter { $0.tags.isEmpty }
        var seen: Set<String> = []
        return ordered.map { day.fill($0.text) }.filter { seen.insert($0).inserted }.prefix(Self.maxOffered).map { $0 }
    }

    public func questions(now: Event?, log: LogView) -> [Question] {
        guard let day = due(now, log) else { return [] }
        let lines = offered(day)
        guard !lines.isEmpty else { return [] }
        return [Question(key: Self.questionKey, text: "\(creature) writes one line in its diary about \(day.weekday): \(day.words). Which?",
                         about: "the day's counts in this question", judgeBy: "PERSONALITY and MOOD: how it would put the day",
                         options: lines.map { Option($0, "A line for the diary.") })]
    }

    public func run(_ answers: Answers, now: Event?, log: LogView) -> OutputResult? {
        guard let line = answers[Self.questionKey]?.choice, let day = due(now, log), offered(day).contains(line) else { return nil }
        write(day.day, line)
        return .done("\(creature) wrote in its diary: \"\(line)\"", facts: ["day": .string(day.day)])
    }
}
