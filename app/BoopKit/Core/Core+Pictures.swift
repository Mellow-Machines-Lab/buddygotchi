import AgentHooks
import Foundation

// Held pictures (documentation/design/screen-guide.md, "Held pictures"): a
// card Boop holds while an agent works is a live picture of the work, built
// from what the hooks already say, with no word from the agent: its plan
// (the to-do), its changes (each file's lines this turn), or its helpers.
// The kind of work picks which, and a picture whose data has stopped
// changing is put down. A text status card is no longer shown.
extension Core {
    /// One file's lines added and removed this turn.
    public struct FileChange: Equatable, Sendable {
        public var name: String
        public var added: Int
        public var removed: Int
    }

    /// A picture's data, as the `state` carries it (`pic`).
    public enum Picture: Equatable, Sendable {
        /// Steps done of all, the agent's words for its step (its card's,
        /// when it sent one) and its guess of the minutes left.
        case plan(done: Int, total: Int, step: String?, minutesLeft: Int?)
        /// Up to `maxFiles` files, the latest edited first, with the lines
        /// added and removed this turn.
        case changes([FileChange])
        /// Each helper this turn: working or done.
        case helpers(working: Int, done: Int)
    }

    /// What a session's turn has done, for its pictures, and when each last
    /// changed.
    struct TurnWork {
        var files: [FileChange] = []
        var helpersDone = 0
        var todos: AgentHooks.SessionTracker.Todos?
        /// When each picture's data last changed.
        var changesAt, helpersAt, planAt: Int64?
    }

    /// A picture shows this long after its data last changed: a plan
    /// longer, as its steps come slowly.
    public static let pictureHoldMs: Int64 = 30_000
    public static let planHoldMs: Int64 = 120_000
    public static let maxFiles = 3
    /// The changes are worth a picture once the turn has changed this many
    /// lines, or two files: one line in one file is no news.
    public static let minChangeLines = 10

    /// Whether an edited file is the project's: a path under where the
    /// agent works, or one relative to it. A note in /tmp is not the work.
    static func inProject(_ file: String, cwd: String?) -> Bool {
        guard file.hasPrefix("/") || file.hasPrefix("~") else { return true }
        guard let cwd, !cwd.isEmpty else { return false }
        let root = cwd.hasSuffix("/") ? cwd : cwd + "/"
        return file.hasPrefix(root)
    }

    /// Whether a turn's changes are worth a picture (`minChangeLines`).
    static func worthShowing(_ files: [FileChange]) -> Bool {
        files.count >= 2 || files.reduce(0) { $0 + $1.added + $1.removed } >= minChangeLines
    }

    /// The hooks' event `e`, for the pictures: a turn starting clears its
    /// work; an edit ending adds its lines to its file; a helper ending
    /// counts; a to-do changing is the plan's.
    func notePictures(_ e: AgentEvent, at now: Int64) {
        let key = e.key
        if e.kind == .turn, e.phase == .start { turnWork[key] = TurnWork() }
        var w = turnWork[key] ?? TurnWork()
        if e.kind == .tool, e.phase == .end, e.toolKind == .edit, e.failed != true,
           let file = (e.glimpse ?? "").split(separator: " ").first.map(String.init), Self.inProject(file, cwd: e.cwd) {
            let name = (file as NSString).lastPathComponent
            let added = e.linesAdded ?? 0, removed = e.linesRemoved ?? 0
            var f = w.files.firstIndex(where: { $0.name == name }).map { w.files.remove(at: $0) }
                ?? FileChange(name: name, added: 0, removed: 0)
            f.added += added
            f.removed += removed
            w.files.insert(f, at: 0)
            w.changesAt = now
        }
        if e.kind == .subagent {
            if e.phase == .end { w.helpersDone += 1 }
            w.helpersAt = now
        }
        if let todos = sessions[key]?.todos, todos != w.todos {
            w.todos = todos
            w.planAt = now
        }
        turnWork[key] = w
    }

    /// The picture Boop holds for the session `key` at `now`, or nil: the
    /// helpers while they run, the changes while edits come, the plan while
    /// its steps move.
    func picture(for key: String, at now: Int64) -> Picture? {
        guard let s = sessions[key], let w = turnWork[key] else { return nil }
        func fresh(_ at: Int64?, _ hold: Int64 = Self.pictureHoldMs) -> Bool { at.map { now - $0 < hold } == true }
        if !s.helpers.isEmpty || fresh(w.helpersAt) {
            if s.helpers.count + w.helpersDone > 0 { return .helpers(working: s.helpers.count, done: w.helpersDone) }
        }
        if fresh(w.changesAt), Self.worthShowing(w.files) { return .changes(Array(w.files.prefix(Self.maxFiles))) }
        if let todos = w.todos, todos.total > 0, fresh(w.planAt, Self.planHoldMs) || cards.held[key]?.status != nil {
            let status = cards.shown(key, at: now).flatMap { $0.kind == .status ? $0 : nil }
            return .plan(done: todos.done, total: todos.total, step: status?.text,
                         minutesLeft: cards.held[key]?.guess?.left(at: now))
        }
        return nil
    }
}
