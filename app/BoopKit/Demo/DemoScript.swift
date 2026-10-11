import AgentHooks
import Foundation

/// A demo: a scripted stretch of work for the creature to live through,
/// which the runtime plays as if it were happening (`Runtime.play`). A
/// character pack carries its own, `demo/demo.jsonl`
/// (characters/CHARACTER.md), since what the creature does in it is the
/// pack's: its moods, and what it says.
///
/// The file is one JSON object a line; a line starting `//` is a comment.
/// Each is a beat: `at`, the seconds since the start, and one thing that
/// happens then.
///
///     {"at": 2, "agent": "claude", "hook": "UserPromptSubmit", "session": "demo", "cwd": "/demo/shortcuts", "prompt": "Add keyboard shortcuts"}
///     {"at": 9, "tap": true}
///     {"at": 14, "talk": "how's it going?", "hold": 1.5}
///     {"at": 20, "mood": "curious"}
///     {"at": 30, "advance": 300}
///
/// - A beat with `hook` is an agent's hook, in the form `agent-hook` sends
///   (`HookLine`): the same fields, so a demo's work looks like real work.
/// - `tap` is a tap on the creature; `talk` is push-to-talk, the button
///   held for `hold` seconds (1.5) and then those words heard.
/// - `mood` sets the mood; `advance` moves the clock on that many seconds,
///   where the runtime's clock can be moved (headless), so a long turn
///   needn't be waited out.
///
/// Any beat may also carry:
/// - `answer`: how the creature reacts to it, as the brain's answers to its
///   questions (`{"react.mood": "happy", "say.kind": "word"}`), given
///   `after` seconds later (0.3, about as long as the brain takes). A demo
///   needs no brain: the rules do what they always do, and the script says
///   the rest.
/// - `note`: what happened, in words for whoever is watching, in place of
///   the words `cause` would find.
public struct DemoScript: Sendable {
    public struct Beat: Sendable {
        public enum What: Sendable {
            case hook(HookLine)
            case tap
            case talk(String, hold: Double)
            case mood(String)
            case advance(Double)
            /// Nothing happens but its `answer` or its `note`.
            case nothing
        }

        public var at: Double
        public var what: What
        public var answer: [String: String]?
        public var after: Double
        public var note: String?
    }

    /// What a beat was, for whoever is watching: a kind, for an icon, and
    /// a line of plain words.
    public struct Cause: Sendable, Equatable, Codable {
        public var kind: String
        public var text: String
    }

    public var beats: [Beat]
    /// How long it runs, in seconds: its last beat, and time for what that
    /// beat starts to play out.
    public var length: Double { (beats.map { $0.at + $0.after }.max() ?? 0) + DemoScript.tail }
    public static let tail = 6.0

    public struct Problem: Error, CustomStringConvertible {
        public var description: String
    }

    public init(beats: [Beat]) { self.beats = beats.sorted { $0.at < $1.at } }

    public init(contentsOf url: URL) throws {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Problem(description: "can't read \(url.path)") }
        try self.init(text, named: url.lastPathComponent)
    }

    public init(_ text: String, named name: String = "the demo") throws {
        var beats: [Beat] = []
        for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            let here = "\(name):\(number + 1)"
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw Problem(description: "\(here): not a JSON object")
            }
            guard let at = (object["at"] as? NSNumber)?.doubleValue, at >= 0 else { throw Problem(description: "\(here): needs \"at\", in seconds") }
            let what: Beat.What
            if object["hook"] != nil {
                guard let hook = HookLine.decode(Data(line.utf8)) else { throw Problem(description: "\(here): a hook needs agent, hook and session") }
                what = .hook(hook)
            } else if object["tap"] != nil {
                what = .tap
            } else if let words = object["talk"] as? String {
                what = .talk(words, hold: (object["hold"] as? NSNumber)?.doubleValue ?? 1.5)
            } else if let mood = object["mood"] as? String {
                what = .mood(mood)
            } else if let seconds = (object["advance"] as? NSNumber)?.doubleValue {
                what = .advance(seconds)
            } else if object["answer"] != nil || object["note"] != nil {
                what = .nothing
            } else {
                throw Problem(description: "\(here): nothing happens: it needs hook, tap, talk, mood, advance, answer or note")
            }
            if let answer = object["answer"], !(answer is [String: String]) { throw Problem(description: "\(here): answer is question keys to choices") }
            beats.append(Beat(at: at, what: what, answer: object["answer"] as? [String: String],
                              after: (object["after"] as? NSNumber)?.doubleValue ?? 0.3, note: object["note"] as? String))
        }
        self.init(beats: beats)
    }
}

extension DemoScript.Beat {
    /// What whoever replays it must do to the device itself: a tap is a
    /// finger on its screen, which the device reacts to by itself.
    public var input: String? {
        if case .tap = what { return "tap" }
        return nil
    }

    /// What happened, for whoever is watching: the beat's `note`, else
    /// words made from the beat itself. Nil for a beat nobody would see as
    /// something happening (a session starting, a routine tool call
    /// starting, the clock moving).
    public func cause(creature name: String) -> DemoScript.Cause? {
        let found: DemoScript.Cause?
        switch what {
        case .tap: found = .init(kind: "tap", text: "You poke \(name)")
        case .talk(let words, _): found = .init(kind: "talk", text: "You say “\(words)”")
        case .mood, .advance, .nothing: found = note.map { .init(kind: "note", text: $0) }
        case .hook(let line): found = line.cause
        }
        // A note says it in the script's own words, and makes something of
        // a beat that would otherwise pass unremarked.
        guard let note else { return found }
        return DemoScript.Cause(kind: found?.kind ?? "note", text: note)
    }
}

extension HookLine {
    /// The agent, as a name: `Claude`, `Codex`.
    var who: String { agent.prefix(1).uppercased() + agent.dropFirst() }

    /// A hook as something that happened, in plain words. What kind of
    /// thing it is comes from agent-hooks' own mapping, so a hook means
    /// here what it means to the rest of Boop.
    var cause: DemoScript.Cause? {
        guard let (kind, phase) = Mapping.kind(of: self) else { return nil }
        switch (kind, phase) {
        case (.turn, .start):
            return .init(kind: "prompt", text: prompt.map { "You ask \(who): “\($0)”" } ?? "You give \(who) a task")
        case (.tool, .wait):
            return .init(kind: "needs_you", text: "\(who) needs your approval")
        case (.tool, .end) where toolError != nil || hook.hasSuffix("Failure"):
            return .init(kind: "tool_failed", text: "\(who)'s \(topic ?? "command") failed")
        case (.tool, .end):
            // A call about something: "the tests". A routine one passes unremarked.
            return topic.map { .init(kind: "tool", text: "\(who) ran the \($0)") }
        case (.turn, .end) where interrupt || hook == "Interrupt":
            return .init(kind: "stopped", text: "You stop \(who)")
        case (.turn, .end) where error != nil || hook.hasSuffix("Failure"):
            return .init(kind: "failed", text: "\(who)'s turn fails" + (error.map { " (\($0.replacingOccurrences(of: "_", with: " ")))" } ?? ""))
        case (.turn, .end):
            return .init(kind: "done", text: "\(who) finishes")
        default:
            return nil
        }
    }
}
