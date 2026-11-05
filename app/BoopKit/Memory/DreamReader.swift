import AgentHooks
import Foundation
import MellowHarness

/// Everything since the last dream, a reader of the transcript
/// (`TranscriptReader`): the tallies and the journal of notable lines, from
/// the last dream to now, whether that's two hours or four days. Boop's day
/// means nothing to it: its span carries across every day, and only a
/// dream starts it again (`Memory.dream`), so a Mac left closed for days
/// dreams once of what was recorded.
public final class DreamReader: TranscriptReader {
    public let name = "dream"

    /// The span since the last dream.
    public struct Span: Codable, Equatable, Sendable {
        /// When it began: the last dream, or the first event read.
        public var since: Int64?
        public var tallies = MemoryReader.Tallies()

        /// Whether anything worth a dream came: something yours, a turn
        /// finished, or a notable line.
        public var new: Bool { tallies.yours > 0 || tallies.turns > 0 || !tallies.journal.isEmpty }

        public init(since: Int64? = nil) { self.since = since }
    }
    public typealias State = Span

    let time: LocalTime
    let place: (String) -> Place

    public init(time: LocalTime, place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.time = time
        self.place = place
    }

    public func open(day: String, carry: Span?) -> Span { carry ?? Span() }

    public func read(_ e: Event, line: Line?, into s: inout Span) -> Bool {
        let before = s
        if s.since == nil { s.since = e.at }
        MemoryReader.count(e, into: &s.tallies, time: time, place: place)
        if let line, let note = MemoryReader.note(e, line) { MemoryReader.keep(note, at: e.at, in: &s.tallies, time: time) }
        let changed = s != before
        s.tallies.lastEvent = e.at
        return changed
    }

    /// The span goes on across the day's end.
    public func close(day: String, state: Span, live: Bool) {}

    /// The dream of `span`, ending at `now`: its tags, its sentence and a
    /// few words for the board, and how the telling says the span. Nil when
    /// nothing new came.
    func dream(_ span: Span, now: Int64) -> Dream? {
        guard span.new else { return nil }
        var t = span.tallies
        if let here = t.hereSince, let last = t.lastYours { t.hereMinutes += Int(max(0, last - here) / 60_000) }
        let since = span.since ?? now, day = time.day(now)
        return Dream(day: day, weekday: time.weekday(of: day), tags: MemoryReader.tags(t), sentence: MemoryReader.sentence(t),
                     fact: MemoryReader.fact(t), about: Self.about(since: since, until: now, time: time),
                     range: Self.range(since: since, until: now, time: time), covers: time.boopDay(t.lastYours ?? now))
    }

    /// The span as the telling says it, after "dreamed about", in words
    /// still true whenever it's told: "Tuesday afternoon" (under 8 hours
    /// on one day, by the part of the day it began), "Tuesday" (longer),
    /// "Monday and Tuesday", "Thursday to Saturday", and past a week "the
    /// 9 days to Saturday".
    static func about(since: Int64, until: Int64, time: LocalTime) -> String {
        let a = time.day(since), b = time.day(until)
        guard let first = LocalTime.dayNumber(a), let last = LocalTime.dayNumber(b) else { return "lately" }
        let from = time.weekday(of: a), to = time.weekday(of: b)
        switch last - first {
        case ...0:
            guard until - since <= 8 * 3_600_000 else { return to }
            let part = ["morning": "morning", "day": "afternoon", "evening": "evening"][Days.dayPart(at: since, time: time)] ?? "night"
            return "\(to) \(part)"
        case 1: return "\(from) and \(to)"
        case 2...6: return "\(from) to \(to)"
        default: return "the \(last - first + 1) days to \(to)"
        }
    }

    /// The span's dates, for CERTAIN and Recently: "Saturday 2026-11-01",
    /// or "Thursday 2026-10-30 to Saturday 2026-11-01".
    static func range(since: Int64, until: Int64, time: LocalTime) -> String {
        let a = time.day(since), b = time.day(until)
        let from = "\(time.weekday(of: a)) \(a)", to = "\(time.weekday(of: b)) \(b)"
        return a == b ? to : "\(from) to \(to)"
    }
}
