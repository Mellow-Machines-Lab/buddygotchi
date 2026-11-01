import Foundation

/// How things stand, for Jev on every pass: the CONTEXT section. Events
/// stay in their lines (NOW and HISTORY); this says what is true now, in
/// a row or a few: the talk setting, the buddy, you, the agents and the
/// day so far. A row shows only when it has something to say. It gives
/// facts only: when they make the buddy lonely, or anything else, is the
/// steering's.
public enum ContextSection {
    public static let heading = "CONTEXT (how things stand. Background, not news: react to NOW.)"
    /// You at the Mac, and untouched, show from this long.
    public static let hereShownMs: Int64 = 60 * 60_000
    public static let untouchedShownMs: Int64 = 60 * 60_000
    /// How long after a lonely spell ends its "last lonely" shows.
    public static let lastLonelyShownMs: Int64 = 3 * 60 * 60_000
    /// The most agents named; the rest are "and N more".
    public static let maxAgents = 3
    /// The section's ceiling, in tokens (`Steering.tokens`).
    public static let maxTokens = 160

    /// The buddy as CONTEXT's Boop row tells it: its stage and how old it is.
    public struct Buddy: Equatable, Sendable {
        public var stage: String
        public var daysOld: Int?

        public init(stage: String, daysOld: Int? = nil) {
            self.stage = stage
            self.daysOld = daysOld
        }
    }

    /// How long it has gone since you touched or talked to the buddy, or
    /// came back, or first did something today, at `now`; nil while you're
    /// away, or before any of that.
    public static func untouchedMs(_ c: MemoryReader.Tallies?, at now: Int64) -> Int64? {
        guard let c, c.awaySince == nil, let base = [c.touchedAt, c.hereSince].compactMap({ $0 }).max() else { return nil }
        return max(0, now - base)
    }

    /// The When row, first: the time, the weekday, the part of the day, and
    /// the calendar's occasions in words: "When: 09:02, Saturday, morning;
    /// Halloween."
    public static func when(at wall: Int64, occasions: [String], time: LocalTime) -> String {
        "When: " + [time.clock(wall), time.weekday(wall), Occasions.dayPart(at: wall, time: time)].joined(separator: ", ")
            + (occasions.isEmpty ? "" : "; " + occasions.joined(separator: ", ")) + "."
    }

    /// The Talk row, when the setting isn't normal: what it asks, and why
    /// it outranks the personality; or, for `silentMs` more, silent (the
    /// hush), then back to the setting.
    static func talk(_ t: Talk, silentMs: Int64? = nil, name: String) -> String? {
        if let ms = silentMs, ms > 0 {
            return "Talk: silent for \(max(1, (ms + 59_999) / 60_000)) more min, then \(t.rawValue) again: \(name) says nothing till then, but its faces and replies go on, each answering what you said."
        }
        return switch t {
        case .normal: nil
        case .chatty: "Talk: chatty. You asked \(name) to say something at every face; this outranks PERSONALITY's silent Examples."
        case .quiet: "Talk: quiet. You asked \(name) to say less: nothing at small moments, and never a swear."
        }
    }

    /// The buddy's row: "Boop: a Pal, 40 days old."
    static func buddy(_ b: Buddy?, name: String) -> String? {
        guard let b else { return nil }
        return "\(name): a \(b.stage)" + (b.daysOld.map { $0 == 0 ? ", hatched today" : ", \($0) day\($0 == 1 ? "" : "s") old" } ?? "") + "."
    }

    /// The You row: "You: at the Mac for 3 h; you haven't touched or talked
    /// to Boop in 2 h; Boop was last lonely 40 min ago."
    static func you(_ c: MemoryReader.Tallies?, at now: Int64, name: String) -> String? {
        guard let c, c.awaySince == nil else { return nil }
        var parts: [String] = []
        if let here = c.hereSince, now - here >= hereShownMs { parts.append("at the Mac for \(span(now - here))") }
        if let ms = untouchedMs(c, at: now), ms >= untouchedShownMs {
            parts.append("you haven't touched or talked to \(name) in \(span(ms))")
        }
        if let ended = c.lonelyEndedAt, now - ended < lastLonelyShownMs { parts.append("\(name) was last lonely \(span(now - ended)) ago") }
        return parts.isEmpty ? nil : "You: " + parts.joined(separator: "; ") + "."
    }

    /// The Agents row: each open session, what needs you first, at most
    /// `maxAgents`: "Agents: claude working on "api" for 12 min; codex idle
    /// on "blog" for 40 min."
    static func agents(_ agents: [StatusReply.Agent], at now: Int64) -> String? {
        guard !agents.isEmpty else { return nil }
        var parts = agents.prefix(maxAgents).map { a -> String in
            let on = a.places.last.map { " on \"\(StateSnapshot.clip($0))\"" } ?? ""
            if a.needsYou { return "\(a.agent) waiting on you\(on)" }
            if let since = a.workingSince { return "\(a.agent) working\(on) for \(span(now - since))" }
            return "\(a.agent) idle\(on)" + (a.restingSince.map { " for \(span(now - $0))" } ?? "")
        }
        if agents.count > maxAgents { parts.append("and \(agents.count - maxAgents) more") }
        return "Agents: " + parts.joined(separator: "; ") + "."
    }

    /// The Today row, once a turn finished or you touched or talked to the
    /// buddy since 5:00: "Today: 7 turns, 3 failed; you touched Boop 6
    /// times and talked to it twice."
    static func today(_ c: MemoryReader.Tallies?, name: String) -> String? {
        guard let c, c.turns > 0 || c.touches > 0 || c.talks > 0 else { return nil }
        var parts: [String] = []
        if c.turns > 0 { parts.append("\(c.turns) turn\(c.turns == 1 ? "" : "s")" + (c.failed > 0 ? ", \(c.failed) failed" : "")) }
        var care: [String] = []
        if c.touches > 0 { care.append("you touched \(name) \(times(c.touches))") }
        if c.talks > 0 { care.append((c.touches > 0 ? "talked to it " : "you talked to \(name) ") + times(c.talks)) }
        if !care.isEmpty { parts.append(care.joined(separator: " and ")) }
        return "Today: " + parts.joined(separator: "; ") + "."
    }

    /// The section, or nil when no row has anything to say.
    public static func section(when: String? = nil, talk t: Talk = .normal, silentMs: Int64? = nil, buddy b: Buddy? = nil,
                               company: MemoryReader.Tallies?, agents list: [StatusReply.Agent], at now: Int64,
                               name: String) -> String? {
        let rows = [when, talk(t, silentMs: silentMs, name: name), buddy(b, name: name), you(company, at: now, name: name), agents(list, at: now),
                    today(company, name: name)].compactMap { $0 }
        return rows.isEmpty ? nil : ([heading] + rows).joined(separator: "\n")
    }

    static func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }

    /// A span in words with a number: "12 min", "3 h".
    static func span(_ ms: Int64) -> String {
        let minutes = max(1, ms / 60_000)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }
}
