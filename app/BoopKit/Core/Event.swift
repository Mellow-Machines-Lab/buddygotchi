import AgentHooks
import Foundation
import MellowHarness

/// Boop's view of an event: what MellowHarness's event
/// holds for Boop. An agent's hook, a poke, what
/// you said, away and back, a check-in, "needs you" and push-to-talk's
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
        case session, turn, tool, subagent, poke, presence
        /// The Mac's screen locking (`start`) and unlocking (`end`), every
        /// time, however short: Boop answers each. An away and a back are
        /// `presence`, which go on as they are.
        case lock
        /// Boop looking in by itself: working, idle (`check_in`) or
        /// hourly; on disk by its older name.
        case checkIn = "heartbeat"
        /// What you said on push-to-talk; on disk by its older name.
        case said = "talk"
        /// "Needs you" showing for a session, and clearing: the core's.
        case needsYou = "needs_you"
        /// Push-to-talk's listening: the Mac's mic going on (`start`), off
        /// with the reply still to come (`wait`), and listening over
        /// (`end`). The core's, and log-only: no line, no wake.
        case listen
        /// One buddy's reaction, which the other buddies hear: only with
        /// several (`Buddy`).
        case reacted
        /// BOOT pressed while something needs you or an agent sits idle:
        /// the board handed you the next one (its `handoff`), and the core
        /// opens it on the Mac; or, as `specific_type` `drawer`, a row
        /// picked in the board's agents' drawer, which it opens.
        case press
        /// What you did to the board, which it already reacted to: a
        /// stroke, a boop on the nose, a shake, a pick-up, face down…, as the
        /// event's `specific_type` (render::Gesture's names, and `facedown`).
        case gesture
        /// Boop hushed: told to be quiet (`start`, by `app` or `talk` as
        /// its `specific_type`, with `until`), and free to talk again
        /// (`end`, why as its `specific_type`). The core's: it reads them
        /// back on launch.
        case hush
        /// A work act starting or coming to its result (`WorkStream.Act`):
        /// `specific_type` is its kind, with its `session`, its sign's
        /// `words`, whether it's `full`, and at its end whether it `passed`.
        case act
        /// Your prompt's reading, after the turn start it came with: its
        /// facts are `PromptReading`'s, never the prompt.
        case prompt
        /// The agent's last message's reading, after the turn end it came
        /// with: its facts are `MessageReading`'s, never the message.
        case lastMessage = "last_message"
        /// Boop dreamed (`Memory.dream`): everything since the last dream in tags and a
        /// sentence, for Boop to tell when you next show up. Boop's own;
        /// it wakes no pass.
        case dream
        /// The dream's write to the written memory (`Memory`): which notes
        /// it kept, changed, added, dropped and aged, and what it refused,
        /// never their text. Boop's own; it wakes no pass.
        case memory
        /// Boop's wish: made (`start`, the kind as its `specific_type`) and
        /// ended (`end`: `met`, `gaveup` or `closed`, with its `kind` and
        /// how long it waited, `waited_ms`). The core's: it reads them back
        /// on launch.
        case wish
        /// Boop reached a growth stage just now (`specific_type` its name), by
        /// its XP. It wakes a pass, for what it holds up and says as it grows.
        case grew
        /// An ask's end, which the board decides: you picked an answer
        /// (`specific_type` `a` or `b`), a touch answered it (`touch`), or
        /// nobody did (`ignored`), with the question's `q`, its words
        /// (`question`), the `answer` and whether Boop `keeps` it.
        case ask
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
    /// A turn's length or a tool call's time, as the moods read it: very
    /// short under `veryShortMs`, a reply in a back-and-forth, short under
    /// a minute, long under 5 minutes, very long past that.
    public static func length(ms: Int64) -> String {
        ms < veryShortMs ? "very short" : ms < 60_000 ? "short" : ms < 5 * 60_000 ? "long" : "very long"
    }

    /// A turn done this quickly was the agent answering back: the
    /// personality lets it go by without a finish.
    public static let veryShortMs: Int64 = 7000

    /// How long you were away from the Mac: short under 15 minutes, long
    /// under 2 hours, very long under `dayAwayMs` (a night's sleep is
    /// very long), a day under `daysAwayMs`, days past that.
    public static func away(ms: Int64) -> String {
        ms < 15 * 60_000 ? "short" : ms < 2 * 60 * 60_000 ? "long" : ms < dayAwayMs ? "very long" : ms < daysAwayMs ? "a day" : "days"
    }
    /// Away this long is a day: more than a night.
    public static let dayAwayMs: Int64 = 20 * 60 * 60_000
    /// Away this long is days: a weekend or more.
    public static let daysAwayMs: Int64 = 40 * 60 * 60_000
}
