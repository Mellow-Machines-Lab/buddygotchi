import AgentHooks
import Foundation
import MellowHarness

/// Boop's side of agent-hooks: a hook line becomes an
/// `AgentEvent` there, and a raw event here, with the hook's name as
/// `specific_type` and the event's facts as `data`. The facts keep their
/// names, but what a request asks for is `asking`: `for` is the seq an
/// event answers.
public enum Adapter {
    /// The raw event for a hook line, or nil for hooks agent-hooks ignores.
    /// Its `at` is when the app received it, or the line's own time.
    public static func event(from line: HookLine, receivedAt: Int64? = nil) -> Event? {
        Mapping.event(from: line, receivedAt: receivedAt).map(Event.init)
    }
}

/// An agent's event and the transcript's raw event are one JSON object
/// apart: `AgentEvent`'s `Codable` form, whose keys `data` keeps, but for
/// the few the raw event holds itself (its agent is its `source`, its kind
/// and phase its `kind`, its time its `at`) and two names of Boop's own:
/// the hook is `specific_type`, and the subagent's type `agent_type`.
enum AgentEventJSON {
    /// The keys `data` doesn't keep.
    static let envelope = ["agent", "kind", "phase", "at"]
    /// agent-hooks' name for a key, and the transcript's.
    static let renamed = [("hook", "specific_type"), ("subagent_type", "agent_type")]

    /// `e`'s facts, by the transcript's names, for `data`.
    static func data(_ e: AgentEvent) -> [String: JSONValue] {
        guard let json = try? JSONEncoder().encode(e), case .object(var o)? = try? JSONValue(
            foundation: JSONSerialization.jsonObject(with: json)) else { return [:] }
        for key in envelope { o[key] = nil }
        for (theirs, ours) in renamed { o[ours] = o.removeValue(forKey: theirs) }
        return o
    }

    /// The agent's event `data` keeps, with its envelope's facts. What a
    /// request asks for was `for` in older transcripts, which is now only
    /// the seq an event answers, so a string `for` still reads as it. A
    /// request or an outcome agent-hooks doesn't know reads as none, and a
    /// missing hook as `""`, as they always did.
    static func event(_ data: [String: JSONValue], agent: Agent, kind: String, phase: String, at: Int64) -> AgentEvent? {
        var o = data
        for (theirs, ours) in renamed { o[theirs] = o.removeValue(forKey: ours) }
        if o["asking"] == nil, case .string(let asking)? = o["for"] { o["asking"] = .string(asking) }
        if o["asking"]?.string.flatMap(AgentEvent.Asking.init(rawValue:)) == nil { o["asking"] = nil }
        if o["outcome"]?.string.flatMap(AgentEvent.Outcome.init(rawValue:)) == nil { o["outcome"] = nil }
        if o["hook"] == nil { o["hook"] = "" }
        o["agent"] = .string(agent.rawValue)
        o["kind"] = .string(kind)
        o["phase"] = .string(phase)
        o["at"] = .int(at)
        guard let json = try? JSONSerialization.data(withJSONObject: JSONValue.object(o).foundation) else { return nil }
        return try? JSONDecoder().decode(AgentEvent.self, from: json)
    }
}

extension Event {
    /// An agent's event as the transcript keeps it.
    public init(_ e: AgentEvent) {
        self.init(at: e.at, source: Source(e.agent), type: Kind(rawValue: e.kind.rawValue)!,
                  phase: Phase(rawValue: e.phase.rawValue), specificType: e.hook, data: AgentEventJSON.data(e))
    }
}

extension AgentEvent {
    /// A raw event that's an agent's, as agent-hooks has it, or nil for
    /// any other: the core and the view fold agents' events from the
    /// transcript with agent-hooks' session bookkeeping.
    public init?(_ e: Event) {
        guard let agent = e.agent, e.session != nil, let phase = e.phase, let kind = e.type,
              Kind(rawValue: kind.rawValue) != nil,
              let read = AgentEventJSON.event(e.data, agent: agent, kind: kind.rawValue, phase: phase.rawValue, at: e.at)
        else { return nil }
        self = read
    }
}

extension HookInstaller {
    /// Boop's installer: its entries keep your prompt and
    /// the agent's last message, the only words the brain hears, and
    /// replace the entries Boop wrote before agent-hooks, which ran
    /// `boop-hook` (and before that `~/.boop/boop-hook.sh`).
    public static func boop(home: URL, hookPath: String) -> HookInstaller {
        HookInstaller(home: home, hookPath: hookPath, arguments: ["--keep-text"],
                      formerClients: ["boop-hook", "/boop-hook.sh"])
    }
}
