import AgentHooks
import Foundation
import MellowHarness

/// Boop's view of an event: what MellowHarness's event
/// holds for Boop. An agent's hook, a poke, what
/// you said, away and back, a heartbeat, "needs you" and push-to-talk's
/// listening are each a type,
/// and a type with a lifetime a phase: the event's `kind` is the two
/// together (`tool_end`, `poke`). The source's own name for it, the
/// session, subagent and working directory are in `data`. MellowHarness's own
/// events (`did`, `ended`, `pass`) have no type.
extension Event {
    /// Where it came from.
    public enum Source: String, Sendable {
        case claude, codex, device, clock, boop
        /// The Mac's microphone: what you said to Boop.
        case mic
        /// The Mac itself: you stepping away and coming back, as the
        /// presence detector decides.
        case mac

        /// An agent's events' source: its own name.
        public init(_ agent: Agent) { self.init(rawValue: agent.rawValue)! }
    }

    /// What it is, whatever agent it came from.
    public enum Kind: String, Sendable, CaseIterable {
        case session, turn, tool, subagent, poke, talk, presence, heartbeat
        /// "Needs you" showing for a session, and clearing: the core's.
        case needsYou = "needs_you"
        /// Push-to-talk's listening: the Mac's mic going on (`start`), off
        /// with the reply still to come (`wait`), and listening over
        /// (`end`). The core's, and log-only: no line, no wake.
        case listen
        /// One buddy's reaction, which the other buddies hear: only with
        /// several (`Buddy`).
        case reacted
    }

    /// Where in its life a thing with a start and an end is: a tool call
    /// can also `wait` on you. Nil for one that just happens.
    public enum Phase: String, Sendable {
        case start, wait, end
    }

    /// The `data` keys Boop's own fields take.
    static let metaKeys: Set<String> = ["specific_type", "session", "subagent", "cwd", "voice"]

    public init(seq: Int = 0, at: Int64, source: Source, type: Kind, phase: Phase? = nil, specificType: String,
                session: String? = nil, subagent: String? = nil, cwd: String? = nil, buddy: String? = nil,
                data: [String: JSONValue] = [:]) {
        var data = data
        data["specific_type"] = .string(specificType)
        if let buddy { data["voice"] = .string(buddy) }
        if let session { data["session"] = .string(session) }
        if let subagent { data["subagent"] = .string(subagent) }
        if let cwd { data["cwd"] = .string(cwd) }
        self.init(seq: seq, at: at, source: source.rawValue, kind: Event.kind(type, phase), data: data)
    }

    /// A type and phase's `kind`: `tool_end`, `poke`.
    public static func kind(_ type: Kind, _ phase: Phase?) -> String {
        phase.map { "\(type.rawValue)_\($0.rawValue)" } ?? type.rawValue
    }

    /// Where it came from, for one of Boop's sources.
    public var from: Source? { Source(rawValue: source) }

    /// Its type and phase, from its `kind`; nil for MellowHarness's own events.
    public var type: Kind? { Event.split(kind).type }
    public var phase: Phase? { Event.split(kind).phase }

    static func split(_ kind: String) -> (type: Kind?, phase: Phase?) {
        if let type = Kind(rawValue: kind) { return (type, nil) }
        guard let cut = kind.lastIndex(of: "_"), let type = Kind(rawValue: String(kind[..<cut])),
              let phase = Phase(rawValue: String(kind[kind.index(after: cut)...])) else { return (nil, nil) }
        return (type, phase)
    }

    /// The source's own name for it: `PreToolUse`, `Interrupt`, `input`.
    public var specificType: String { data["specific_type"]?.string ?? "" }
    /// The agent's session; for "needs you", the session's.
    public var session: String? { data["session"]?.string }
    /// The Claude subagent it came from, by `agent_id`.
    public var subagent: String? { data["subagent"]?.string }
    public var cwd: String? { data["cwd"]?.string }
    /// With several buddies, the one it's about (`Buddy`): its voice, in
    /// MellowHarness's word, the key its own `did`s and passes take too.
    public var buddy: String? { data["voice"]?.string }

    /// The agent it came from, for an agent's event.
    public var agent: Agent? { Agent(rawValue: source) }

    /// `turn end`, `poke`: its type and phase, or its kind for MellowHarness's
    /// own.
    public var name: String {
        type.map { t in [t.rawValue, phase?.rawValue].compactMap { $0 }.joined(separator: " ") } ?? kind
    }

    /// `12 tool end PostToolUse claude s1 · tool Bash, failed true`, for
    /// debug mode and replays.
    public var summary: String {
        let what = [type.map { [$0.rawValue, phase?.rawValue].compactMap { $0 }.joined(separator: " ") } ?? kind,
                    specificType.isEmpty ? action : specificType, source, session].compactMap { $0 }
        let facts = data.keys.sorted().filter { !Event.metaKeys.contains($0) && $0 != "action" }.compactMap { key -> String? in
            guard let value = data[key] else { return nil }
            switch value {
            case .string(let s): return "\(key) \(s.count > 60 ? String(s.prefix(60)) + "…" : s)"
            case .int(let n): return "\(key) \(n)"
            case .bool(let b): return "\(key) \(b)"
            default: return nil
            }
        }
        return what.joined(separator: " ") + (facts.isEmpty ? "" : " · " + facts.joined(separator: ", "))
    }

    /// `value` as JSON, keys sorted: a string comes back quoted.
    static func json(_ value: Any) -> String { JSONLine.encode(value) }
}

/// Numbers named, so no brain has to compare them.
public enum Band {
    /// A turn's length or a tool call's time, as the moods read it: short
    /// under a minute, long under 5 minutes, very long past that.
    public static func length(ms: Int64) -> String {
        ms < 60_000 ? "short" : ms < 5 * 60_000 ? "long" : "very long"
    }

    /// How long you were away from the Mac: short under 15 minutes, long
    /// under 2 hours, very long past that.
    public static func away(ms: Int64) -> String {
        ms < 15 * 60_000 ? "short" : ms < 2 * 60 * 60_000 ? "long" : "very long"
    }
}
