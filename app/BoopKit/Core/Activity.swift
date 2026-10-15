import AgentHooks
import Foundation

/// What the agents are doing, sustained, which the working look shows
/// instead of plain working, in
/// priority order: the first is the highest.
public enum Act: String, CaseIterable, Sendable {
    case testing, delegating, terminal, searching, analyzing, toolUse = "tool_use", waiting, planning

    /// Its place in the priority: lower is higher.
    public var rank: Int { Act.allCases.firstIndex(of: self)! }

    /// Whether it outranks `other`.
    public func beats(_ other: Act) -> Bool { rank < other.rank }

    /// What a running call shows, by its tool and topic:
    /// a call that runs tests is testing, a shell command that only looks
    /// (`inspect`) is analyzing, and otherwise its kind decides (agent-hooks'
    /// `ToolKind`, which knows the agents' tool names). A `Task` or `Agent` call is delegating only
    /// from the main agent. Anything else is `tool_use`.
    static func of(tool: String?, topic: String?, byMainAgent: Bool) -> Act {
        if topic == "tests" { return .testing }
        if topic == "inspect" { return .analyzing }
        switch ToolKind.of(tool) {
        case .planning: return .planning
        case .shell: return .terminal
        case .read, .search: return .analyzing
        case .web: return .searching
        case .subagent: return byMainAgent ? .delegating : .toolUse
        case .edit, .mcp, .other: return .toolUse
        }
    }
}

extension Core {
    /// What a running call shows.
    static func act(_ call: SessionTracker.Call) -> Act {
        Act.of(tool: call.tool, topic: call.topic, byMainAgent: call.by.isEmpty)
    }

    /// An activity and its time: for a session's, when its evidence was
    /// last in force; for the working look's, since when it has shown. A
    /// higher one replaces it at once, a lower one or none only
    /// `actHoldMs` after that time.
    struct Timed: Equatable {
        var act: Act
        var at: Int64
    }

    /// An activity shows at least this long: after its last evidence in a
    /// session, and after it started showing, before a lower one or none
    /// replaces it, so fast tools don't flicker.
    public static let actHoldMs: Int64 = 1500
    /// A call running with nothing heard from its session for this long
    /// shows as waiting.
    public static let waitingMs: Int64 = 20_000

    /// A session's activity at `now`, before any hold: Codex's request in
    /// its grace is waiting; else the highest of its calls' (each waiting
    /// once the session has been quiet `waitingMs`, but a helper at work),
    /// delegating while a helper it saw start hasn't ended, and planning in
    /// plan mode.
    static func activity(_ s: Session, _ now: Int64) -> Act? {
        if s.pendingSince != nil { return .waiting }
        let quiet = now - s.lastEventAt >= waitingMs
        var acts = s.calls.values.map { call -> Act in
            let act = Core.act(call)
            return quiet && act != .delegating ? .waiting : act
        }
        if !s.helpers.isEmpty { acts.append(.delegating) }
        if s.planMode { acts.append(.planning) }
        return acts.min { $0.beats($1) }
    }

    /// The activity after `held`, with `next` put forward: a higher one at
    /// once, a lower one or none once `actHoldMs` have passed since
    /// `held`'s time. The same one stays, its time moved to `now` when
    /// `refresh` (a session's evidence in force again) and kept when not
    /// (the look's, which has shown since then).
    static func settle(_ held: Timed?, _ next: Act?, now: Int64, refresh: Bool) -> Timed? {
        guard let held else { return next.map { Timed(act: $0, at: now) } }
        if next == held.act { return refresh ? Timed(act: held.act, at: now) : held }
        if let next, next.beats(held.act) { return Timed(act: next, at: now) }
        if now - held.at < actHoldMs { return held }
        return next.map { Timed(act: $0, at: now) }
    }

    /// Every working session's activity held at `now`, then the one the
    /// working look shows: the held activity of the working session with
    /// the most recent event, among those that have one.
    /// A session that isn't working holds none, so it comes back from
    /// "needs you" or idle with what it does then; with no session working
    /// the look has none at once.
    func updateActs(_ now: Int64) {
        var working: [(s: Session, held: Timed?)] = []
        var kept: [String: Timed] = [:]
        for (key, s) in sessions where s.needsSince == nil && tracker.isWorking(s, at: now) {
            let next = Core.settle(held[key], Core.activity(s, now), now: now, refresh: true)
            kept[key] = next
            working.append((s, next))
        }
        held = kept
        guard !working.isEmpty else {
            shownAct = nil
            return
        }
        let latest = working.filter { $0.held != nil }
            .max { ($0.s.lastEventAt, $0.s.order) < ($1.s.lastEventAt, $1.s.order) }
        shownAct = Core.settle(shownAct, latest?.held?.act, now: now, refresh: false)
    }
}
