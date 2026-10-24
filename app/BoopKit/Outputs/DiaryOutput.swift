import AgentHooks
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

    // Its lines are `diary.md`'s (`TaggedLine`): the tags a day needs, all
    // of them, and words with `{turns}`, `{failed}`, `{longest}`,
    // `{thread}`, `{pokes}` and `{weekday}` to fill in.

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
    let templates: [TaggedLine]
    let time: LocalTime
    let creature: String
    let write: (String, String) -> Void
    let place: (String) -> Place

    /// `templates` from the pack's `diary.md`, days on `time`'s calendar,
    /// `creature` the buddy's name, and `write` given each day and its line.
    /// A thread is named as the lines name it, from where `place` says its
    /// folder works.
    public init(templates: [TaggedLine], time: LocalTime, creature: String, voice: String? = nil,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) }, write: @escaping (String, String) -> Void) {
        self.voice = voice
        self.place = place
        self.templates = templates
        self.time = time
        self.creature = creature
        self.write = write
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
        let range = time.dayRange(at)
        let events = log.events.filter { range.contains($0.at) }
        guard !events.isEmpty else { return nil }
        return Self.count(events, day: day, weekday: time.weekday(at), tags: Occasions.tags(at: at, hatched: nil, time: time), place: place)
    }

    /// A day's counts from its raw events.
    static func count(_ events: [Event], day: String, weekday: String, tags calendar: [String],
                      place: (String) -> Place = { Place.at(cwd: $0) }) -> Day {
        var d = Day(day: day, weekday: weekday)
        var started: [String: Int64] = [:]
        var threads: [String: Int] = [:]
        var names: [String: String] = [:]
        for e in events {
            if e.type == .poke { d.pokes += 1 }
            guard e.type == .turn, let session = e.session else { continue }
            if e.phase == .start { started[session] = e.at }
            if e.phase == .end {
                d.turns += 1
                if e["outcome"]?.string == "failed" { d.failed += 1 }
                if let from = started.removeValue(forKey: session) { d.longestMinutes = max(d.longestMinutes, Int((e.at - from) / 60_000)) }
                var thread = "work"
                if let cwd = e.cwd {
                    if names[cwd] == nil { let p = place(cwd); names[cwd] = p.workspace ?? p.project }
                    thread = names[cwd]!
                }
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
        let fit = templates.filter { $0.fits(Set(day.tags)) }
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
