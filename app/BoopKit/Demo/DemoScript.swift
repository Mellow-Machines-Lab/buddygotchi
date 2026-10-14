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
/// `codex`). Each other line is one thing, by one of the three:
///
///     {"agent": "prompt", "text": "Add keyboard shortcuts"}
///     {"brain": {"react.mood": "calm", "say.about": "start", "say.kind": "word"}}
///     {"you": "poke"}
///     {"agent": "read", "file": "src/editor.js", "say": "I'll start by reading the editor."}
///     {"you": "talk", "text": "You suck at this!", "hold": 2}
///     {"agent": "run", "cmd": "npm test", "about": "Run the tests", "fails": true}
///     {"brain": {"react.mood": "annoyed", "say.feeling": "upset", "say.kind": "word"}, "mood": "annoyed"}
///
/// - `agent` lines are what the agent does, in words both agents share:
///   `prompt` (you ask it, `text`), `read` and `edit` (a `file`; an edit's
///   `old` and `new`), `run` (a `cmd`, what it's `about`, whether it
///   `fails`, and `ask`: the agent asks you first, and you allow it after
///   that many seconds), `review` (a subagent, its `task` and `prompt`), and
///   `reply` (`text` that ends the turn). `say` is what the agent says
///   before it acts. `"by": "reviewer"` is the subagent's own.
/// - `you` lines are what the person does: `poke`, and `talk` (the button
///   held `hold` seconds, then `text` heard).
/// - `brain` lines are the creature's brain's answers to its questions,
///   about the line above, and `mood` its mood.
///
/// The lines happen in order. Any line may say how long `after` the one
/// before it ends; an `agent` line also how long it `takes`. Who plays
/// the agent is the player's choice (`Runtime.play`): with no agent, it
/// sends the hooks the agent would; with a live one, it waits for the
/// agent's own. Either way the person's and the brain's lines keep to the
/// agent's. Any line may carry a `note`: what happened, in words for
/// whoever is watching, in place of the words the line makes.
public struct DemoScript: Sendable {
    public struct Line: Sendable {
        public enum What: Sendable, Equatable {
            case agent(Agent)
            case poke
            case talk(String, hold: Double)
            case brain([String: String], mood: String?)
        }

        /// An `agent` line.
        public struct Agent: Sendable, Equatable {
            public enum Does: String, Sendable, CaseIterable {
                case prompt, read, edit, run, review, reply
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
            /// A review's task and prompt.
            public var task: String?
            public var prompt: String?
            /// The subagent's line, not the main thread's.
            public var byReviewer = false
        }

        public var what: What
        /// Seconds after the line before ends.
        public var after: Double
        /// Seconds an agent line takes, with no agent to take them.
        public var takes: Double
        public var note: String?
        /// Its line number in the file.
        public var number: Int
    }

    /// What a line was, for whoever is watching: a kind, for an icon, and
    /// a line of plain words.
    public struct Cause: Sendable, Equatable, Codable {
        public var kind: String
        public var text: String
    }

    public var title: String
    /// Whose hooks the script's are: `claude` or `codex`.
    public var agent: String
    public var lines: [Line]

    public struct Problem: Error, CustomStringConvertible {
        public var description: String
    }

    public init(contentsOf url: URL) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Problem(description: "can't read \(url.path)") }
        try self.init(text, named: url.lastPathComponent)
    }

    public init(_ text: String, named name: String = "the demo") throws {
        var title = "", agent = "claude"
        var lines: [Line] = []
        for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            let here = "\(name):\(index + 1)"
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw Problem(description: "\(here): not a JSON object")
            }
            func number(_ key: String) -> Double? { (o[key] as? NSNumber)?.doubleValue }
            func string(_ key: String) -> String? { o[key] as? String }
            if o["demo"] != nil {
                guard lines.isEmpty else { throw Problem(description: "\(here): the header comes first") }
                title = string("title") ?? ""
                agent = string("agent") ?? "claude"
                guard ["claude", "codex"].contains(agent) else { throw Problem(description: "\(here): agent is claude or codex") }
                continue
            }
            let what: Line.What
            if let does = string("agent") {
                guard let kind = Line.Agent.Does(rawValue: does) else {
                    throw Problem(description: "\(here): agent is one of \(Line.Agent.Does.allCases.map(\.rawValue).joined(separator: ", "))")
                }
                var a = Line.Agent(does: kind)
                a.text = string("text"); a.say = string("say"); a.file = string("file")
                a.old = string("old"); a.new = string("new"); a.cmd = string("cmd"); a.about = string("about")
                a.fails = o["fails"] as? Bool ?? false
                a.ask = number("ask")
                a.task = string("task"); a.prompt = string("prompt")
                a.byReviewer = string("by") == "reviewer"
                switch kind {
                case .prompt, .reply: if a.text == nil { throw Problem(description: "\(here): a \(does) needs text") }
                case .read: if a.file == nil { throw Problem(description: "\(here): a read needs a file") }
                case .edit:
                    if a.file == nil || a.old == nil || a.new == nil { throw Problem(description: "\(here): an edit needs a file, old and new") }
                case .run: if a.cmd == nil { throw Problem(description: "\(here): a run needs a cmd") }
                case .review: if a.task == nil { throw Problem(description: "\(here): a review needs a task") }
                }
                what = .agent(a)
            } else if let does = string("you") {
                switch does {
                case "poke": what = .poke
                case "talk":
                    guard let words = string("text") else { throw Problem(description: "\(here): talk needs text") }
                    what = .talk(words, hold: number("hold") ?? 1.5)
                default: throw Problem(description: "\(here): you is poke or talk")
                }
            } else if o["brain"] != nil {
                guard let answers = o["brain"] as? [String: String] else {
                    throw Problem(description: "\(here): brain is question keys to choices")
                }
                what = .brain(answers, mood: string("mood"))
            } else {
                throw Problem(description: "\(here): a line is by the agent, you or the brain")
            }
            let defaults: (after: Double, takes: Double) = switch what {
            case .agent(let a) where a.does == .prompt: (1, 0)
            case .agent(let a) where a.does == .run: (1, 2)
            case .agent: (1, 0.6)
            case .poke, .talk: (0.8, 0)
            case .brain: (0.3, 0)
            }
            lines.append(Line(what: what, after: number("after") ?? defaults.after, takes: number("takes") ?? defaults.takes,
                              note: string("note"), number: index + 1))
        }
        self.init(title: title, agent: agent, lines: lines)
    }

    public init(title: String = "", agent: String = "claude", lines: [Line]) {
        self.title = title
        self.agent = agent
        self.lines = lines
    }
}

extension DemoScript.Line {
    /// What the person does to the device itself at this line, for
    /// whoever replays it: a tap is a finger on its screen, which the
    /// device reacts to by itself.
    public var input: String? { what == .poke ? "tap" : nil }

    /// What happened, for whoever is watching: the line's `note`, else words
    /// made from the line. Nil for a line nobody would see as something
    /// happening (the brain's).
    public func cause(creature name: String, agent: String) -> DemoScript.Cause? {
        let who = agent.prefix(1).uppercased() + agent.dropFirst()
        let found: DemoScript.Cause?
        switch what {
        case .poke: found = .init(kind: "tap", text: "You poke \(name)")
        case .talk(let words, _): found = .init(kind: "talk", text: "You say “\(words)”")
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
                    : .init(kind: a.ask != nil ? "needs_you" : "tool", text: a.ask != nil ? "\(actor) asks to \(what), and you allow it" : "\(actor): \(what)")
            case .review: found = .init(kind: "tool", text: "\(who) sends a reviewer: \(a.task ?? "")")
            case .reply:
                found = a.byReviewer ? .init(kind: "tool", text: "The reviewer reports back")
                    : .init(kind: "done", text: "\(who) finishes")
            }
        }
        guard let note else { return found }
        return DemoScript.Cause(kind: found?.kind ?? "note", text: note)
    }
}
