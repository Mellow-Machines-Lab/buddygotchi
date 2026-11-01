import AgentHooks
import Foundation
import MellowHarness

/// Boop's day as it goes, then as a dream: the one reader of the
/// transcript in v1 (`TranscriptReader`). Through the day it keeps your
/// company (when you last touched or talked to Boop, came back, and when
/// a lonely spell last ended, which CONTEXT says), the
/// tallies (strokes, talks, hours at the Mac, turns) and the journal (the
/// notable lines Jev read, for the night's write); when the day closes it
/// writes the dream, yesterday in tags and a sentence, your care first,
/// which Boop tells the next time you show up. Nothing is kept past the
/// close but the dream.
public final class MemoryReader: TranscriptReader {
    public let name = "memory"

    /// What a day's counts need to say. Only events that are yours
    /// (`Yours`) count as you.
    public struct Tallies: Codable, Equatable, Sendable {
        public var strokes = 0, touches = 0, pokes = 0, talks = 0, kind = 0
        public var back = 0, hereMinutes = 0, prompts = 0, late = 0, answered = 0
        public var turns = 0, failed = 0, longestMinutes = 0
        /// Turns finished on each thread, for the busiest.
        public var threads: [String: Int] = [:]
        /// How many of the day's events were yours, and the last one's time.
        public var yours = 0
        public var lastYours: Int64?
        /// Since when you've been at the Mac (none while away, or before
        /// your first event), and since when you've been away: carried
        /// across 5:00.
        public var hereSince: Int64?
        public var awaySince: Int64?
        /// The turns still working, by session, since when: carried.
        public var working: [String: Int64] = [:]
        /// Your company, carried across 5:00: when you last touched or
        /// talked to Boop (`Yours.touched`), when you last came back, and
        /// when Boop's mood last left lonely.
        public var touchedAt: Int64?
        public var backAt: Int64?
        public var lonelyEndedAt: Int64?
        /// The XP each pool earned today, within its cap
        /// (`Growth.workPerDay`, `carePerDay`): growth's daily totals. Nil
        /// before the first, and in a checkpoint from before they were kept.
        public var workXP: Int?, careXP: Int?
        /// The notable lines Jev read, each with its time (`HH:mm`), for
        /// the night's write; at most `journalMax`.
        public var journal: [Note] = []

        public struct Note: Codable, Equatable, Sendable {
            public var at: String
            public var line: String
            /// A prompt with none of your words, the first to go when the
            /// journal is full; a finish next.
            public var plain: Bool
        }

        /// The busiest thread: the one that finished the most turns.
        public var thread: String { threads.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "" }

        public init() {}
    }
    public typealias State = Tallies

    /// The most lines the journal keeps.
    public static let journalMax = 80
    /// A day with this many touches or talks is fond; this many pokes,
    /// poked; this long at the Mac, here; a turn this long, long.
    public static let fondCount = 3, pokedCount = 5, hereMinutes = 240, longMinutes = 30

    let store: KeyValueStore
    let time: LocalTime
    let place: (String) -> Place
    /// Each event read that earned XP, with how much within its pool's cap
    /// for the day: growth adds it, as the reader reads it.
    public var earned: (Event, Int) -> Void = { _, _ in }
    /// A dream written: `Memory` logs it and keeps whether it was told.
    var wrote: (Dream) -> Void = { _ in }
    /// A day closed that you were in, with its tallies and journal, and
    /// whether live: `Memory` starts the night's write.
    var closed: (_ day: String, _ tallies: Tallies, _ live: Bool) -> Void = { _, _, _ in }

    public init(store: KeyValueStore, time: LocalTime, place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.store = store
        self.time = time
        self.place = place
    }

    public func open(day: String, carry: Tallies?) -> Tallies {
        var t = Tallies()
        t.awaySince = carry?.awaySince
        t.working = carry?.working ?? [:]
        t.touchedAt = carry?.touchedAt
        t.backAt = carry?.backAt
        t.lonelyEndedAt = carry?.lonelyEndedAt
        return t
    }

    public func read(_ e: Event, line: Line?, into t: inout Tallies) -> Bool {
        let before = t
        if let earning = Growth.earning(for: e) {
            let had = (earning.pool == .work ? t.workXP : t.careXP) ?? 0
            let xp = min(earning.xp, max(0, Growth.cap(earning.pool) - had))
            if earning.pool == .work { t.workXP = had + xp } else { t.careXP = had + xp }
            if xp > 0 { earned(e, xp) }
        }
        if Yours.did(e) {
            t.yours += 1
            t.lastYours = e.at
            if t.hereSince == nil, t.awaySince == nil { t.hereSince = e.at }
        }
        if Yours.touched(e) { t.touchedAt = e.at }
        switch e.type {
        case .poke?:
            t.pokes += 1
            t.touches += 1
        case .gesture? where Yours.careGestures.contains(e.specificType):
            t.touches += 1
            if e.specificType == "stroke" { t.strokes += 1 }
        case .said?:
            t.talks += 1
        case .ask? where e.specificType != Asks.ignored:
            t.answered += 1
        case .prompt?:
            t.prompts += 1
            let hour = time.components(e.at).hour
            if hour >= 22 || hour < LocalTime.boopDayStartHour { t.late += 1 }
        case .presence?:
            var away = AwayAndBack(since: t.awaySince)
            switch away.fold(e) {
            case .away(let since)?:
                if let here = t.hereSince { t.hereMinutes += Int(max(0, since - here) / 60_000) }
                t.hereSince = nil
            case .back?:
                t.back += 1
                t.hereSince = e.at
                t.backAt = e.at
            case nil:
                break
            }
            t.awaySince = away.since
        case .turn?:
            guard let session = e.session else { break }
            if e.phase == .start { t.working[session] = e.at }
            if e.phase == .end {
                t.turns += 1
                if e["outcome"]?.string == "failed" { t.failed += 1 }
                if let from = t.working.removeValue(forKey: session) {
                    t.longestMinutes = max(t.longestMinutes, Int((e.at - from) / 60_000))
                }
                let p = e.cwd.map(place)
                t.threads[p.map { $0.workspace ?? $0.project } ?? "work", default: 0] += 1
            }
        default:
            if e.kind == Event.did, e.action == ReactOutput.outputName, let reply = e["reply"]?.string,
               reply == "love" || reply == "thanks" { t.kind += 1 }
            if e.kind == Event.did, e.action == MoodOutput.outputName, e["ok"]?.bool != false, e["from"]?.string == "lonely",
               e["to"]?.string != "lonely" { t.lonelyEndedAt = e.at }
        }
        if let line, let note = Self.note(e, line) { keep(note, at: e.at, in: &t) }
        return t != before
    }

    /// A line worth the night's write, or nil: your prompts and what you
    /// said to Boop, turns that finished long, failed or gave up, a check
    /// that failed again or passed after failing, and you back after a long
    /// break. Never tool calls, gestures (the tallies count them),
    /// heartbeats or Boop's own reactions.
    static func note(_ e: Event, _ line: Line) -> (line: String, plain: Bool)? {
        let text = ([line.text] + line.notes).joined(separator: "\n  ")
        switch e.type {
        case .prompt?: return (text, !line.notes.contains { $0.hasPrefix("Your words") })
        case .said?, .ask?: return e.specificType == Asks.ignored ? nil : (text, false)
        case .turn? where e.phase == .end:
            let long = (line.facts["length_ms"]?.int ?? 0) >= 5 * 60_000
            return long || e["outcome"]?.string != "done" ? (text, true) : nil
        case .tool? where e.phase == .end: return (text, false)
        case .presence? where e.phase == .end:
            let band = line.facts["away"]?.string ?? ""
            return band == "short" ? nil : (text, false)
        default: return nil
        }
    }

    func keep(_ note: (line: String, plain: Bool), at: Int64, in t: inout Tallies) {
        t.journal.append(Tallies.Note(at: time.clock(at), line: note.line, plain: note.plain))
        while t.journal.count > Self.journalMax {
            let i = t.journal.firstIndex { $0.plain } ?? 0
            t.journal.remove(at: i)
        }
    }

    public func close(day: String, state t: Tallies, live: Bool) {
        // Nobody was there: no dream.
        guard t.yours > 0 else { return }
        var t = t
        if let here = t.hereSince, let last = t.lastYours { t.hereMinutes += Int(max(0, last - here) / 60_000) }
        let dream = Dream(day: day, weekday: time.weekday(of: day), tags: Self.tags(t), sentence: Self.sentence(t),
                          fact: Self.fact(t))
        if let kept = Dream.last(in: store), kept.day == day { return }  // closed twice: the same dream
        wrote(dream)
        closed(day, t, live)
    }

    /// The day's tags, for `dreams.md`'s signs: yours first, then the
    /// agents'.
    static func tags(_ t: Tallies) -> [String] {
        var tags: [String] = []
        let care = t.touches + t.talks
        if care >= fondCount { tags.append("fond") }
        if care == 0 { tags.append("distant") }
        if t.hereMinutes >= hereMinutes { tags.append("here") }
        if t.late > 0 { tags.append("late") }
        if t.answered > 0 { tags.append("answered") }
        if t.failed > 0 { tags.append("failed") }
        if t.turns > 0, t.failed == 0 { tags.append("clean") }
        if t.longestMinutes >= longMinutes { tags.append("long") }
        if t.turns == 0 { tags.append("quiet") }
        if t.pokes >= pokedCount { tags.append("poked") }
        return tags
    }

    /// The day in a sentence, your care first: "you stroked it 4 times; 7
    /// turns on \"api\", 3 failed".
    static func sentence(_ t: Tallies) -> String {
        func times(_ n: Int) -> String { n == 1 ? "once" : "\(n) times" }
        var care: [String] = []
        if t.strokes > 0 { care.append("you stroked it \(times(t.strokes))") }
        if t.talks > 0 { care.append("you talked to it \(times(t.talks))") }
        if t.strokes == 0, t.pokes > 0 { care.append("you poked it \(times(t.pokes))") }
        var parts = Array(care.prefix(2))
        if t.turns > 0 {
            parts.append("\(t.turns) turn\(t.turns == 1 ? "" : "s") on \"\(t.thread)\"" + (t.failed > 0 ? ", \(t.failed) failed" : ""))
        }
        return parts.isEmpty ? "a quiet day" : parts.joined(separator: "; ")
    }

    /// The dream for the board's lane, a few words: "stroked x4".
    static func fact(_ t: Tallies) -> String {
        if t.strokes > 0 { return "stroked x\(t.strokes)" }
        if t.talks > 0 { return "talked x\(t.talks)" }
        if t.failed > 0 { return "\(t.failed) failed" }
        if t.turns > 0 { return t.turns == 1 ? "1 turn" : "\(t.turns) turns" }
        return "quiet day"
    }
}

/// Yesterday as Boop dreamed it: the day it was, its tags, a sentence and
/// a few words for the board, and whether it has been told and logged.
/// The newest is kept as `dream.last` in the key-value store.
public struct Dream: Codable, Equatable, Sendable {
    public var day: String
    public var weekday: String
    public var tags: [String]
    public var sentence: String
    public var fact: String
    public var told = false
    public var logged = false

    public static let key = "dream.last"

    public init(day: String, weekday: String, tags: [String], sentence: String, fact: String) {
        self.day = day
        self.weekday = weekday
        self.tags = tags
        self.sentence = sentence
        self.fact = fact
    }

    /// The newest dream kept, or nil.
    public static func last(in store: KeyValueStore) -> Dream? {
        store.string(key).flatMap { try? JSONDecoder().decode(Dream.self, from: Data($0.utf8)) }
    }

    func save(in store: KeyValueStore) throws {
        try store.set([Self.key: String(decoding: try JSONEncoder().encode(self), as: UTF8.self)])
    }

    /// The `dream` event that tells the view.
    func event(at: Int64) -> Event {
        Event(at: at, source: .boop, type: .dream, specificType: "dream",
              data: ["day": .string(day), "weekday": .string(weekday), "tags": .array(tags.map { .string($0) }),
                     "sentence": .string(sentence), "fact": .string(fact)])
    }
}
