import Foundation

/// What a `status` reply holds up: the one fact about the agents that
/// answers what you said, from what the core and the transcript know,
/// never from the brain. Something waiting on you first, then the work
/// going on and how it's going, then how the last of it came out, else
/// nothing going on. Say an agent's name or a thread's place ("is codex
/// done?", "how's the api going?") and only those sessions count. Name
/// none with several sessions open ("how many are running?") and the
/// sign counts them, and the board shows them all in its agents' drawer.
public enum StatusReply {
    /// What a status reply holds up, and where the board shows the rest
    /// of it: one of its own screens, or nil for the sign alone.
    public struct Answer: Equatable, Sendable {
        public var sign: String
        public var show: String?

        public init(sign: String, show: String? = nil) {
            self.sign = sign
            self.show = show
        }
    }

    /// The board's agents' drawer, as a reaction's `show`.
    public static let drawer = "drawer"

    /// One session as status reads it.
    public struct Agent: Equatable, Sendable {
        /// `claude` or `codex`.
        public var agent: String
        /// What you may call it by: its project, workspace and thread's
        /// name.
        public var places: [String]
        public var needsYou = false
        /// While it works, when its turn started.
        public var workingSince: Int64?
        public var todo: StateSnapshot.Todo?
        /// The latest thing of its that came out one way or another.
        public var result: Result?

        public init(agent: String, places: [String], needsYou: Bool = false, workingSince: Int64? = nil,
                    todo: StateSnapshot.Todo? = nil, result: Result? = nil) {
            self.agent = agent
            self.places = places
            self.needsYou = needsYou
            self.workingSince = workingSince
            self.todo = todo
            self.result = result
        }
    }

    /// Something that came out one way or another: a check (its topic,
    /// whatever it checks: tests, a build, a deploy) passing or failing,
    /// or a turn (no topic) done, failed or stopped.
    public struct Result: Equatable, Sendable {
        public var topic: String?
        public var outcome: String
        public var at: Int64

        public init(topic: String?, outcome: String, at: Int64) {
            self.topic = topic
            self.outcome = outcome
            self.at = at
        }

        /// `tests failed`, `build passed`, `done!`, `failed :(`, `stopped`.
        var words: String {
            if let topic { return "\(topic) \(outcome)" }
            switch outcome {
            case "done": return "done!"
            case "failed": return "failed :("
            default: return outcome
            }
        }
    }

    /// The agents whose names you may say.
    public static let agents = ["claude", "codex"]
    /// A result this recent is still news once the work is over.
    public static let recentMs: Int64 = 10 * 60_000
    /// The shortest place name matched in what you said: shorter ones
    /// ("ui", "x") turn up in ordinary words.
    public static let shortestPlace = 3

    /// The answer to `words`, what you said, about `sessions` at `now`:
    /// a sign of at most `Signs.maxLength` characters, naming the agent
    /// when it fits; with nothing named and several sessions, their count
    /// and the drawer.
    public static func answer(_ sessions: [Agent], words: String, at now: Int64) -> Answer {
        let said = tokens(words)
        let named = agents.filter { said.contains($0) }
        let asked = sessions.filter { s in named.contains(s.agent) || s.places.contains { mentions(said, $0) } }
        if named.isEmpty, asked.isEmpty, sessions.count > 1 { return Answer(sign: count(sessions), show: drawer) }
        return Answer(sign: sign(asked.isEmpty ? sessions : asked, named: named, asked: !asked.isEmpty, at: now))
    }

    /// Several sessions, counted: who needs you, else how many work and
    /// how many rest.
    static func count(_ sessions: [Agent]) -> String {
        let waiting = sessions.filter(\.needsYou)
        if waiting.count == 1 { return "\(waiting[0].agent) needs you" }
        if waiting.count > 1 { return "\(waiting.count) need you" }
        let working = sessions.filter { $0.workingSince != nil }.count, resting = sessions.count - working
        if working == 0 { return "\(resting) resting" }
        let both = "\(working) working, \(resting) idle"
        return resting == 0 || both.count > Signs.maxLength ? "\(working) working" : both
    }

    /// The one fact about `these`, the sessions you asked about (`asked`)
    /// or every one, with `named` the agents you said.
    static func sign(_ these: [Agent], named: [String], asked: Bool, at now: Int64) -> String {
        func about(_ s: Agent, _ fact: String) -> String {
            let full = "\(s.agent): \(fact)"
            return full.count <= Signs.maxLength ? full : String(fact.prefix(Signs.maxLength))
        }
        // An agent named that isn't here at all.
        if !asked, let missing = named.first { return "no \(missing) around" }

        let waiting = these.filter(\.needsYou)
        if waiting.count == 1 { return "\(waiting[0].agent) needs you" }
        if waiting.count > 1 { return "\(waiting.count) need you" }

        let working = these.filter { $0.workingSince != nil }
        if working.count > 1 {
            // One agent named, several of its sessions at work.
            let theirs = named.count == 1 ? "\(working.count) \(named[0]) working" : ""
            return !theirs.isEmpty && theirs.count <= Signs.maxLength ? theirs : "\(working.count) working"
        }
        if let s = working.first, let since = s.workingSince {
            if let r = s.result, r.topic != nil, r.at >= since { return about(s, r.words) }
            if let todo = s.todo { return about(s, "\(todo.text) done") }
            let minutes = (now - since) / 60_000
            return about(s, minutes < 1 ? "just started" : "\(minutes) min in")
        }

        let latest = these.compactMap { s in s.result.map { (s, $0) } }.filter { now - $0.1.at < recentMs }
            .max { $0.1.at < $1.1.at }
        if let (s, r) = latest { return about(s, r.words) }
        if asked, Set(these.map(\.agent)).count == 1 { return about(these[0], "resting") }
        return "all quiet"
    }

    /// `words` as lowercase runs of letters and digits.
    static func tokens(_ words: String) -> [String] {
        words.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// Whether `said`, what you said as `tokens`, names `place`: its own
    /// runs in a row (`my-app` in "is my app done"), or all of them run
    /// together as you might say them in one (`buddy-gotchi` in "is
    /// buddygotchi done", or the other way round).
    static func mentions(_ said: [String], _ place: String) -> Bool {
        let parts = tokens(place)
        let joined = parts.joined()
        guard joined.count >= shortestPlace, !parts.isEmpty else { return false }
        for start in said.indices {
            if said[start...].starts(with: parts) { return true }
            var run = ""
            for t in said[start...] {
                run += t
                if run == joined { return true }
                if run.count >= joined.count { break }
            }
        }
        return false
    }
}
