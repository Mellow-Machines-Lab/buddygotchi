import Foundation

/// How things stand, for Jev on every pass: the CONTEXT section. Events
/// stay in their lines (NOW and HISTORY); this says what is true now,
/// in a row or two: you, the agents, and the day so far. A row shows
/// only when it has something worth saying.
public enum ContextSection {
    public static let heading = "CONTEXT (how things stand. Background, not news: react to NOW.)"
    /// You at the Mac this long shows; untouched this long shows.
    public static let hereShownMs: Int64 = 60 * 60_000
    public static let untouchedMs: Int64 = 2 * 60 * 60_000
    /// After a lonely spell ends with no touch, untouched stays hidden this
    /// long, so lonely can't come straight back at the next check-in.
    public static let afterLonelyMs: Int64 = 2 * 60 * 60_000
    /// The most agents named; the rest are "and N more".
    public static let maxAgents = 3
    /// The section's ceiling, in tokens (`Steering.tokens`).
    public static let maxTokens = 120

    /// How long it has gone since you touched or talked to the buddy, or
    /// came back, or first did something today, at `now`; nil while you're
    /// away, before any of that, and for `afterLonelyMs` after a lonely
    /// spell ended with no touch since.
    public static func untouchedMs(_ c: MemoryReader.Tallies?, at now: Int64) -> Int64? {
        guard let c, c.awaySince == nil, let base = [c.touchedAt, c.hereSince].compactMap({ $0 }).max() else { return nil }
        if let ended = c.lonelyEndedAt, now - ended < afterLonelyMs, (c.touchedAt ?? .min) < ended { return nil }
        return max(0, now - base)
    }

    /// The You row: "You: at the Mac for 3 h; you haven't touched or talked
    /// to Boop in 2 h."
    static func you(_ c: MemoryReader.Tallies?, at now: Int64, name: String) -> String? {
        guard let c, c.awaySince == nil else { return nil }
        var parts: [String] = []
        if let here = c.hereSince, now - here >= hereShownMs { parts.append("at the Mac for \(span(now - here))") }
        if let ms = untouchedMs(c, at: now), ms >= untouchedMs {
            parts.append("you haven't touched or talked to \(name) in \(span(ms))")
        }
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
        func times(_ n: Int) -> String { n == 1 ? "once" : n == 2 ? "twice" : "\(n) times" }
        var parts: [String] = []
        if c.turns > 0 { parts.append("\(c.turns) turn\(c.turns == 1 ? "" : "s")" + (c.failed > 0 ? ", \(c.failed) failed" : "")) }
        var care: [String] = []
        if c.touches > 0 { care.append("you touched \(name) \(times(c.touches))") }
        if c.talks > 0 { care.append((c.touches > 0 ? "talked to it " : "you talked to \(name) ") + times(c.talks)) }
        if !care.isEmpty { parts.append(care.joined(separator: " and ")) }
        return "Today: " + parts.joined(separator: "; ") + "."
    }

    /// The section, or nil when no row has anything to say.
    public static func section(company: MemoryReader.Tallies?, agents list: [StatusReply.Agent], at now: Int64,
                               name: String) -> String? {
        let rows = [you(company, at: now, name: name), agents(list, at: now), today(company, name: name)].compactMap { $0 }
        return rows.isEmpty ? nil : ([heading] + rows).joined(separator: "\n")
    }

    /// A span in words with a number: "12 min", "3 h".
    static func span(_ ms: Int64) -> String {
        let minutes = max(1, ms / 60_000)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }
}
