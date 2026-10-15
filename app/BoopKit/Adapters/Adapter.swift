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

extension Event {
    /// An agent's event as the transcript keeps it.
    public init(_ e: AgentEvent) {
        var data: [String: JSONValue] = [:]
        func put(_ key: String, _ value: String?) { if let value { data[key] = .string(value) } }
        put("agent_type", e.subagentType)
        put("mode", e.mode)
        put("source", e.source)
        put("prompt", e.prompt)
        put("tool", e.tool)
        put("tool_use_id", e.toolUseID)
        put("topic", e.topic)
        if let failed = e.failed { data["failed"] = .bool(failed) }
        put("error", e.error)
        put("asking", e.asking?.rawValue)
        put("notice", e.notice)
        put("outcome", e.outcome?.rawValue)
        put("message", e.message)
        put("name", e.name)
        put("app", e.app)
        put("app_session", e.appSession)
        self.init(ts: e.at, source: Source(e.agent), type: Kind(rawValue: e.kind.rawValue)!,
                  phase: Phase(rawValue: e.phase.rawValue), specificType: e.hook, session: e.session,
                  subagent: e.subagent, cwd: e.cwd, data: data)
    }
}

extension AgentEvent {
    /// A raw event that's an agent's, as agent-hooks has it, or nil for
    /// any other: the core and the view fold agents' events from the
    /// transcript with agent-hooks' session bookkeeping.
    public init?(_ e: Event) {
        guard let agent = e.agent, let session = e.session, let phase = e.phase.flatMap({ Phase(rawValue: $0.rawValue) }),
              let kind = e.type.flatMap({ Kind(rawValue: $0.rawValue) }) else { return nil }
        self.init(agent: agent, kind: kind, phase: phase, hook: e.specificType, session: session, at: e.ts,
                  subagent: e.subagent, subagentType: e["agent_type"]?.string, cwd: e.cwd, name: e["name"]?.string,
                  app: e["app"]?.string, appSession: e["app_session"]?.string, mode: e["mode"]?.string,
                  source: e["source"]?.string, prompt: e["prompt"]?.string, tool: e["tool"]?.string,
                  toolUseID: e["tool_use_id"]?.string, topic: e["topic"]?.string, failed: e["failed"]?.bool,
                  error: e["error"]?.string, asking: e.asking,
                  notice: e["notice"]?.string, outcome: e["outcome"]?.string.flatMap(Outcome.init(rawValue:)),
                  message: e["message"]?.string)
    }
}

extension Event {
    /// What an agent's request asks for. Older transcripts kept it under
    /// `for`, which is now only the seq an event answers, so a string
    /// `for` still reads as it.
    var asking: AgentEvent.Asking? {
        (self["asking"]?.string ?? self["for"]?.string).flatMap(AgentEvent.Asking.init(rawValue:))
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
