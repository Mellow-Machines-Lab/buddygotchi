import AgentHooks
import Foundation

// Held pictures (documentation/design/screen-guide.md, "Held pictures"): a
// card Boop holds while an agent works is a live picture of the work, built
// from what the hooks already say, with no word from the agent: its plan
// (the to-do), its changes (each file's lines this turn), or its helpers.
// The kind of work picks which, and a picture whose data has stopped
// changing is put down. A text status card is no longer shown.
extension Core {
    /// A picture's data, as the `state` carries it (`pic`).
    public enum Picture: Equatable, Sendable {
        /// Steps done of all, the agent's words for its step (its card's,
        /// when it sent one) and its guess of the minutes left.
        case plan(done: Int, total: Int, step: String?, minutesLeft: Int?)
        /// Up to `maxFiles` files, the latest edited first, with the lines
        /// added and removed this turn.
        case changes([(name: String, added: Int, removed: Int)])
        /// Each helper this turn: working or done.
        case helpers(working: Int, done: Int)

        public static func == (a: Picture, b: Picture) -> Bool {
            switch (a, b) {
            case let (.plan(d1, t1, s1, m1), .plan(d2, t2, s2, m2)): return d1 == d2 && t1 == t2 && s1 == s2 && m1 == m2
            case let (.changes(x), .changes(y)):
                return x.count == y.count && zip(x, y).allSatisfy { $0.name == $1.name && $0.added == $1.added && $0.removed == $1.removed }
            case let (.helpers(w1, d1), .helpers(w2, d2)): return w1 == w2 && d1 == d2
            default: return false
            }
        }
    }

    /// What a session's turn has done, for its pictures, and when each last
    /// changed.
    struct TurnWork {
        var files: [(name: String, added: Int, removed: Int)] = []
        var helpersDone = 0
        var todos: AgentHooks.SessionTracker.Todos?
        var changedAt: [String: Int64] = [:]
    }

    /// A picture shows this long after its data last changed: a plan
    /// longer, as its steps come slowly.
    public static let pictureHoldMs: Int64 = 30_000
    public static let planHoldMs: Int64 = 120_000
    public static let maxFiles = 3

    /// The hooks' event `e`, for the pictures: a turn starting clears its
    /// work; an edit ending adds its lines to its file; a helper ending
    /// counts; a to-do changing is the plan's.
    func notePictures(_ e: AgentEvent, at now: Int64) {
        let key = e.key
        if e.kind == .turn, e.phase == .start { turnWork[key] = TurnWork() }
        var w = turnWork[key] ?? TurnWork()
        if e.kind == .tool, e.phase == .end, e.toolKind == .edit, e.failed != true,
           let file = (e.glimpse ?? "").split(separator: " ").first.map(String.init) {
            let name = (file as NSString).lastPathComponent
            let added = e.linesAdded ?? 0, removed = e.linesRemoved ?? 0
            if let i = w.files.firstIndex(where: { $0.name == name }) {
                let f = w.files.remove(at: i)
                w.files.insert((name, f.added + added, f.removed + removed), at: 0)
            } else {
                w.files.insert((name, added, removed), at: 0)
            }
            w.changedAt["changes"] = now
        }
        if e.kind == .subagent {
            if e.phase == .end { w.helpersDone += 1 }
            w.changedAt["helpers"] = now
        }
        if let todos = sessions[key]?.todos, todos != w.todos {
            w.todos = todos
            w.changedAt["plan"] = now
        }
        turnWork[key] = w
    }

    /// The picture Boop holds for the session `key` at `now`, or nil: the
    /// helpers while they run, the changes while edits come, the plan while
    /// its steps move.
    func picture(for key: String, at now: Int64) -> Picture? {
        guard let s = sessions[key], let w = turnWork[key] else { return nil }
        func fresh(_ kind: String, _ hold: Int64 = Self.pictureHoldMs) -> Bool {
            w.changedAt[kind].map { now - $0 < hold } == true
        }
        if !s.helpers.isEmpty || fresh("helpers") {
            if s.helpers.count + w.helpersDone > 0 { return .helpers(working: s.helpers.count, done: w.helpersDone) }
        }
        if fresh("changes"), !w.files.isEmpty { return .changes(Array(w.files.prefix(Self.maxFiles))) }
        if let todos = w.todos, todos.total > 0, fresh("plan", Self.planHoldMs) || cards.held[key]?.status != nil {
            let status = cards.shown(key, at: now).flatMap { $0.kind == .status ? $0 : nil }
            var left: Int?
            if let guess = cards.held[key]?.guess { left = guess.minutes - Int((now - guess.at) / 60_000) }
            return .plan(done: todos.done, total: todos.total, step: status?.text, minutesLeft: left)
        }
        return nil
    }
}
