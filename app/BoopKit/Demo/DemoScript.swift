import AgentHooks
import Foundation

/// A demo: one script, played in order, of what three take part in do: the
/// agent, the person, and the creature's brain. A character pack carries
/// its own (`demo/<name>.jsonl`, characters/CHARACTER.md), since what the
/// creature does in it is the pack's: its moods, and what it says.
///
/// The file is one JSON object a line; a line starting `//` is a comment.
/// The first may be a header, `{"demo": 1, "title": "…", "agent": "claude"}`
/// (the agent the script's hooks are from: `claude`, the default, or
/// `codex`), and `start`, the local date and time the demo's clock starts
/// at (`2026-10-31T09:00`). Every other line is a step: one thing, by one
/// of the three:
///
///     {"agent": "prompt", "text": "Add keyboard shortcuts"}
///     {"brain": {"react.mood": "calm", "say.about": "start", "say.kind": "word"}}
///     {"you": "poke"}
///     {"agent": "read", "file": "src/editor.js", "say": "I'll start by reading the editor."}
///     {"you": "talk", "text": "You suck at this!", "hold": 2}
///     {"you": "back", "minutes": 600}
///     {"agent": "todo", "todos": "2/4"}
///     {"you": "wait", "minutes": 8}
///     {"agent": "run", "cmd": "npm test", "about": "Run the tests", "fails": true}
///     {"brain": {"react.mood": "annoyed", "say.feeling": "upset", "say.kind": "word"}, "mood": "annoyed"}
///
/// - `agent` steps are what the agent does, in words both agents share:
///   `prompt` (you ask it, `text`), `read` and `edit` (a `file`; an edit's
///   `old` and `new`), `run` (a `cmd`, what it's `about`, whether it
///   `fails`, and `ask`: the agent asks you first, and you allow it after
///   that many seconds; with `waits`, the steps after it play while it
///   waits), `review` (a subagent, its `task` and `prompt`),
///   `compact` (its context is full mid-turn, and it compacts the
///   conversation and goes on; the `summary` its model writes), `todo`
///   (it writes its to-do list, `todos` done of all, as `2/4`), and
///   `reply` (`text` that ends the turn; with `fails`, the turn failed).
///   `say` is what the agent says before it acts. `"by": "reviewer"` is
///   the subagent's own. `session` names another of the agent's sessions,
///   working beside the first: each name is its own thread.
/// - `you` steps are what the person does: `poke`, `press` (BOOT, which
///   hands you the next agent while one needs you or sits idle), `hold`
///   (a finger held on the needs-you sign, which dismisses it), `talk` (the
///   button held `hold` seconds, then `text` heard), `back`: back at the
///   Mac after `minutes` away (`Runtime.cameBack`), and `wait`: `minutes`
///   pass at once, where the demo's clock can be moved (headless, as
///   `make demo` plays it).
/// - `brain` steps are the creature's brain's answers to its questions,
///   about the step above, and `mood` its mood. `{"mood": "proud"}`
///   alone is a brain step too.
///
/// A key a step doesn't take, or a value of the wrong type, is refused
/// with its line number, and `problems(for:)` finds the answers and moods
/// a pack can't play (characters/DEMOS.md).
///
/// The steps happen in order. Any step may say how long `after` the one
/// before it ends; an `agent` step also how long it `takes`. Who plays
/// the agent is the player's choice (`Runtime.play`): with no agent, it
/// sends the hooks the agent would; with a live one, it waits for the
/// agent's own. Either way the person's and the brain's steps keep to the
/// agent's. Any step may carry a `note`: what happened, in words for
/// whoever is watching, in place of the words the step makes.
public struct DemoScript: Sendable {
    public struct Step: Sendable {
        public enum What: Sendable, Equatable {
            case agent(Agent)
            case poke
            /// BOOT pressed: the board hands you the next agent.
            case press
            /// A finger held on the needs-you sign: Boop stops showing the
            /// request.
            case hold
            case talk(String, hold: Double)
            /// Back at the Mac after this many ms away.
            case back(ms: Int64)
            /// This many ms pass at once.
            case wait(ms: Int64)
            case brain([String: String], mood: String?)
        }

        /// An `agent` step.
        public struct Agent: Sendable, Equatable {
            public enum Does: String, Sendable, CaseIterable {
                case prompt, read, edit, run, review, compact, todo, reply
            }

            public var does: Does
            /// A prompt's or a reply's words.
            public var text: String?
            /// What it says before it acts.
            public var say: String?
            public var file: String?
            public var old: String?
            public var new: String?
            public var cmd: String?
            /// What a command is for, as the agent describes it.
            public var about: String?
            public var fails = false
            /// Seconds the agent's request to run waits for you, or nil: it doesn't ask.
            public var ask: Double?
            /// The request's step ends as it's asked, so the steps after it
            /// play while it waits for you (`waits`).
            public var waits = false
            /// A review's task and prompt.
            public var task: String?
            public var prompt: String?
            /// A compact's summary: what the agent's model writes of the
            /// conversation so far, for it to go on from.
            public var summary: String?
            /// A to-do list's counts.
            public var todos: StateSnapshot.Todo?
            /// The subagent's step, not the main thread's.
            public var byReviewer = false
            /// Which of the agent's sessions it is: nil for the first.
            public var session: String?
            /// A prompt's reading, as Apple Intelligence would make it
            /// (`kind`, `tone`, `phrases`), so the demo reads the same on
            /// any Mac (`ScriptLabeler`); nil for counted only.
            public var reading: PromptReading.Labels?
        }

        public var what: What
        /// Seconds after the step before ends.
        public var after: Double
        /// Seconds an agent step takes, with no agent to take them.
        public var takes: Double
        public var note: String?
        /// With several buddies, whose step it is: its agent's, a poke or
        /// talk on its board, its brain's answers. Nil for the first's,
        /// and talk to them all.
        public var buddy: String?
        /// Its line number in the file.
        public var number: Int
    }

    /// What a step was, for whoever is watching: a kind, for an icon, and
    /// plain words.
    public struct Cause: Sendable, Equatable, Codable {
        public var kind: String
        public var text: String
    }

    public var title: String
    /// Whose hooks the script's are: `claude` or `codex`.
    public var agent: String
    /// When the demo's clock starts, local time in ms since 1970, or nil:
    /// now.
    public var start: Int64?
    public var steps: [Step]
    /// The buddies it plays on, when several: each with its place, pack,
    /// the agent whose hooks its steps are, and name. Empty for one.
    public var buddies: [BuddySetting] = []

    public struct Problem: Error, CustomStringConvertible {
        public var description: String
    }

    public init(contentsOf url: URL) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Problem(description: "can't read \(url.path)") }
        try self.init(text, named: url.lastPathComponent)
    }

    public init(_ text: String, named name: String = "the demo") throws {
        var title = "", agent = "claude"
        var steps: [Step] = []
        var buddies: [BuddySetting] = []
        var start: Int64?
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            let here = "\(name):\(index + 1)"
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw Problem(description: "\(here): not a JSON object")
            }
            func number(_ key: String) -> Double? { (o[key] as? NSNumber)?.doubleValue }
            func string(_ key: String) -> String? { o[key] as? String }
            // A key the step's kind doesn't take, or a value of the wrong
            // type, is a mistake: it would otherwise be left out quietly.
            let kind = o["demo"] != nil ? "demo" : ["agent", "you", "brain"].first { o[$0] != nil } ?? (o["mood"] != nil ? "brain" : "")
            if let keys = Self.keys[kind] {
                if let bad = o.keys.sorted().first(where: { !keys.contains($0) && !Self.anyStep.contains($0) }) {
                    let called = ["demo": "the header", "agent": "an agent step", "you": "a you step"][kind] ?? "a brain step"
                    throw Problem(description: "\(here): \(called) has no key \(bad); it takes \((keys + Self.anyStep).sorted().joined(separator: ", "))")
                }
                for (key, value) in o {
                    let isBool = (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } == true
                    let ok = switch key {
                    case "after", "takes", "ask", "hold", "minutes", "demo": value is NSNumber && !isBool
                    case "fails", "waits": isBool
                    case "brain": value is [String: String]
                    case "buddies": value is [Any]
                    case "reading": value is [String: Any]
                    default: value is String
                    }
                    if !ok { throw Problem(description: "\(here): \(key) is \(Self.type(of: key))") }
                }
            }
            if o["demo"] != nil {
                guard steps.isEmpty else { throw Problem(description: "\(here): the header comes first") }
                title = string("title") ?? ""
                agent = string("agent") ?? "claude"
                guard ["claude", "codex"].contains(agent) else { throw Problem(description: "\(here): agent is claude or codex") }
                if let text = string("start") {
                    guard let ms = Self.date(text) else { throw Problem(description: "\(here): start is a date and time, like 2026-10-31T09:00") }
                    start = ms
                }
                if let list = o["buddies"] {
                    // As settings.json has them (`BuddySetting`).
                    guard let read = try? JSONDecoder().decode([BuddySetting].self, from: JSONSerialization.data(withJSONObject: list)) else {
                        throw Problem(description: "\(here): each buddy has a place and a pack, and maybe agents and a name")
                    }
                    if let problem = BuddySetting.problem(read) { throw Problem(description: "\(here): \(problem)") }
                    buddies = read
                }
                continue
            }
            let what: Step.What
            if let does = string("agent") {
                guard let kind = Step.Agent.Does(rawValue: does) else {
                    throw Problem(description: "\(here): agent is one of \(Step.Agent.Does.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                var a = Step.Agent(does: kind)
                a.text = string("text"); a.say = string("say"); a.file = string("file")
                a.old = string("old"); a.new = string("new"); a.cmd = string("cmd"); a.about = string("about")
                a.fails = o["fails"] as? Bool ?? false
                a.ask = number("ask")
                a.waits = o["waits"] as? Bool ?? false
                if a.waits, a.ask == nil { throw Problem(description: "\(here): only a run that asks waits") }
                a.task = string("task"); a.prompt = string("prompt"); a.summary = string("summary")
                if let text = string("todos") {
                    guard kind == .todo, let list = StateSnapshot.Todo(text: text) else { throw Problem(description: "\(here): only a todo has todos, like 2/4") }
                    a.todos = list
                }
                a.byReviewer = string("by") == "reviewer"
                a.session = string("session")
                if let r = o["reading"] {
                    guard kind == .prompt, let r = r as? [String: Any] else { throw Problem(description: "\(here): only a prompt has a reading, an object") }
                    do { a.reading = try PromptReading.Labels(json: r) } catch { throw Problem(description: "\(here): \(error)") }
                }
                if a.fails, kind != .run, kind != .reply { throw Problem(description: "\(here): only a run or a reply fails") }
                switch kind {
                case .prompt, .reply: if a.text == nil { throw Problem(description: "\(here): a \(does) needs text") }
                case .read: if a.file == nil { throw Problem(description: "\(here): a read needs a file") }
                case .edit:
                    if a.file == nil || a.old == nil || a.new == nil { throw Problem(description: "\(here): an edit needs a file, old and new") }
                case .run: if a.cmd == nil { throw Problem(description: "\(here): a run needs a cmd") }
                case .review: if a.task == nil { throw Problem(description: "\(here): a review needs a task") }
                case .todo: if a.todos == nil { throw Problem(description: "\(here): a todo needs todos, like 2/4") }
                case .compact:
                    if a.summary == nil { throw Problem(description: "\(here): a compact needs the summary its model writes") }
                    // The model says nothing at the wall: the context is
                    // full before it can.
                    if a.say != nil { throw Problem(description: "\(here): a compact says nothing; put the words on the step after it") }
                    if a.byReviewer { throw Problem(description: "\(here): a compact is the main thread's") }
                }
                what = .agent(a)
            } else if let does = string("you") {
                switch does {
                case "poke": what = .poke
                case "press": what = .press
                case "hold": what = .hold
                case "talk":
                    guard let words = string("text") else { throw Problem(description: "\(here): talk needs text") }
                    what = .talk(words, hold: number("hold") ?? 1.5)
                case "back":
                    let minutes = number("minutes") ?? 60
                    guard minutes > 0 else { throw Problem(description: "\(here): a back's minutes are more than 0") }
                    what = .back(ms: Int64(minutes * 60_000))
                case "wait":
                    guard let minutes = number("minutes"), minutes > 0 else { throw Problem(description: "\(here): a wait's minutes are more than 0") }
                    what = .wait(ms: Int64(minutes * 60_000))
                default: throw Problem(description: "\(here): you is poke, press, hold, talk, back or wait")
                }
            } else if o["brain"] != nil || o["mood"] != nil {
                what = .brain(o["brain"] as? [String: String] ?? [:], mood: string("mood"))
            } else {
                throw Problem(description: "\(here): a step is by the agent, you or the brain")
            }
            let defaults: (after: Double, takes: Double) = switch what {
            case .agent(let a) where a.does == .prompt: (1, 0)
            case .agent(let a) where a.does == .run || a.does == .compact: (1, 2)
            case .agent: (1, 0.6)
            case .poke, .press, .hold, .talk, .back, .wait: (0.8, 0)
            case .brain: (0.3, 0)
            }
            let buddy = string("buddy")
            if let buddy, !buddies.contains(where: { $0.place == buddy }) {
                throw Problem(description: "\(here): buddy is one of the header's: \(buddies.map(\.place).joined(separator: ", "))")
            }
            steps.append(Step(what: what, after: number("after") ?? defaults.after, takes: number("takes") ?? defaults.takes,
                              note: string("note"), buddy: buddy, number: index + 1))
        }
        self.init(title: title, agent: agent, steps: steps)
        self.buddies = buddies
        self.start = start
    }

    /// How long a `hold` keeps its finger on the sign, in seconds: past
    /// the board's hold (TouchGesture::kHoldMs), so the board sees one.
    public static let holdSeconds = 1.2

    /// `2026-10-31T09:00`, a demo's `start` and an eval's, in `timeZone`
    /// (this Mac's for a demo), as ms since 1970.
    public static func date(_ text: String, timeZone: TimeZone = .current) -> Int64? {
        dateFormatter(timeZone).date(from: text).map { Int64($0.timeIntervalSince1970 * 1000) }
    }

    /// `ms` as `date` reads it, in `timeZone`.
    public static func date(_ ms: Int64, timeZone: TimeZone = .current) -> String {
        dateFormatter(timeZone).string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }

    static func dateFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }

    /// The keys each kind of step takes, besides `anyStep`'s.
    static let keys: [String: [String]] = [
        "demo": ["demo", "title", "agent", "buddies", "start"],
        "agent": ["agent", "text", "say", "file", "old", "new", "cmd", "about", "fails", "ask", "waits", "task", "prompt", "summary", "by",
                  "takes", "session", "reading", "todos"],
        "you": ["you", "text", "hold", "minutes"],
        "brain": ["brain", "mood"],
    ]
    static let anyStep = ["after", "note", "buddy"]

    static func type(of key: String) -> String {
        switch key {
        case "after", "takes", "ask", "hold", "minutes", "demo": "a number"
        case "fails", "waits": "true or false"
        case "brain": "question keys to choices, both strings"
        case "buddies": "a list of buddies, as settings.json has them"
        case "reading": "a prompt's reading: its kind, tone and phrases"
        default: "a string"
        }
    }

    public init(title: String = "", agent: String = "claude", steps: [Step], buddies: [BuddySetting] = []) {
        self.title = title
        self.agent = agent
        self.steps = steps
        self.buddies = buddies
    }

    /// The agent whose hooks the buddy `buddy`'s steps are: its own, else
    /// the script's.
    public func agent(of buddy: String?) -> String {
        buddies.first { $0.place == buddy }?.agents?.first ?? agent
    }
}

extension DemoScript.Step {
    /// What the person does to the device itself at this step, for
    /// whoever replays it: a tap is a finger on its screen, which the
    /// device reacts to by itself, and a hold one kept there.
    public var input: String? {
        switch what {
        case .poke: "tap"
        case .press: "press"
        case .hold: "hold"
        default: nil
        }
    }

    /// What happened, for whoever is watching: the step's `note`, else words
    /// made from the step. Nil for a step nobody would see as something
    /// happening (the brain's).
    public func cause(creature name: String, agent: String) -> DemoScript.Cause? {
        let who = agent.prefix(1).uppercased() + agent.dropFirst()
        let found: DemoScript.Cause?
        switch what {
        case .poke: found = .init(kind: "tap", text: "You poke \(name)")
        case .press: found = .init(kind: "press", text: "You press \(name)'s button")
        case .hold: found = .init(kind: "hold", text: "You hold a finger on \(name)'s sign")
        case .wait(let ms): found = .init(kind: "wait", text: "\(Self.minutes(ms)) later")
        case .talk(let words, _): found = .init(kind: "talk", text: "You say “\(words)”")
        case .back(let ms): found = .init(kind: "back", text: "You come back to the Mac after a \(Band.away(ms: ms)) break")
        case .brain: found = nil
        case .agent(let a):
            let actor = a.byReviewer ? "The reviewer" : who
            switch a.does {
            case .prompt: found = .init(kind: "prompt", text: "You ask \(who): “\(a.text ?? "")”")
            case .read: found = .init(kind: "tool", text: "\(actor) reads \(a.file ?? "")")
            case .edit: found = .init(kind: "tool", text: "\(actor) edits \(a.file ?? "")")
            case .run:
                let what = a.about.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? "runs `\(a.cmd ?? "")`"
                found = a.fails ? .init(kind: "tool_failed", text: "\(actor): \(what), and it fails")
                    : a.waits ? .init(kind: "needs_you", text: "\(actor) asks to \(what), and waits for you")
                    : .init(kind: a.ask != nil ? "needs_you" : "tool", text: a.ask != nil ? "\(actor) asks to \(what), and you allow it" : "\(actor): \(what)")
            case .review: found = .init(kind: "tool", text: "\(who) sends a reviewer: \(a.task ?? "")")
            case .compact: found = .init(kind: "compact", text: "\(who)'s context is full: it compacts the conversation")
            case .todo: found = .init(kind: "tool", text: "\(who) ticks off its to-do list: \(a.todos.map { "\($0.done) of \($0.total) done" } ?? "")")
            case .reply:
                found = a.byReviewer ? .init(kind: "tool", text: "The reviewer reports back")
                    : a.fails ? .init(kind: "tool_failed", text: "\(who)'s turn fails")
                    : .init(kind: "done", text: "\(who) finishes")
            }
        }
        guard let note else { return found }
        return DemoScript.Cause(kind: found?.kind ?? "note", text: note)
    }

    /// A length of time, in words, to the nearest minute from a minute on:
    /// `45 seconds`, `8 minutes`, `1 hour 30 minutes`.
    public static func minutes(_ ms: Int64) -> String {
        let m = Int((Double(ms) / 60_000).rounded())
        let (h, r) = (m / 60, m % 60)
        func n(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s")" }
        if ms < 60_000 { return n(Int(ms / 1000), "second") }
        return h == 0 ? n(r, "minute") : r == 0 ? n(h, "hour") : "\(n(h, "hour")) \(n(r, "minute"))"
    }
}

extension DemoScript {
    /// Each question a brain step may answer, and its choices in `pack`.
    public static func choices(in pack: CharacterPack = .active) -> [String: [String]] {
        var offered = Dictionary(uniqueKeysWithValues: ReactOutput.questions(in: pack).map { ($0.key, $0.options.map(\.name)) })
        offered["react.mood"] = ["none"] + pack.faces.map(\.name)
        return offered
    }

    /// What in the script `pack` can't play, each with its line: an answer
    /// to a question the brain is never asked, a choice it isn't offered,
    /// or a mood the pack doesn't have. Empty when every step plays. A
    /// pack with no voice takes `say.*` answers and leaves them out
    /// (characters/CHARACTER.md §8), so one script plays with or without.
    public func problems(for pack: CharacterPack = .active) -> [String] {
        let offered = Self.choices(in: pack)
        var found: [String] = []
        for step in steps {
            guard case .brain(let answers, let mood) = step.what else { continue }
            for (key, choice) in answers.sorted(by: { $0.key < $1.key }) {
                // A sign's captions come from the prompt's reading, so any
                // that fits one may be picked.
                if key == Signs.questionKey {
                    if choice.count > Signs.maxLength { found.append("line \(step.number): a sign has at most \(Signs.maxLength) characters") }
                    continue
                }
                guard let choices = offered[key] else {
                    found.append("line \(step.number): the brain is never asked \(key); it's asked \(offered.keys.sorted().joined(separator: ", "))")
                    continue
                }
                if !choices.contains(choice) {
                    found.append("line \(step.number): \(key) has no choice \(choice); it has \(choices.joined(separator: ", "))")
                }
            }
            if let mood, !pack.moods.map(\.id).contains(mood) {
                found.append("line \(step.number): \(pack.id) has no mood \(mood); it has \(pack.moods.map(\.id).joined(separator: ", "))")
            }
        }
        return found
    }
}
