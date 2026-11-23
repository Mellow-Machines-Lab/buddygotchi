import AgentHooks
import Foundation

/// What the agents are doing, sustained, which the working look shows as
/// a pose of the whole body, in priority order: the first is the highest.
/// Four, so each reads across a desk: running (a command, the tests, a
/// build, helpers at work), looking (reading, searching, the web), typing
/// (an edit, any other tool, a plan) and waiting. With none, the board
/// shows plain working, which is typing too. The raw values are the wire's
/// `act`, names the boards have always known.
public enum Act: String, CaseIterable, Sendable {
    case running = "terminal", looking = "analyzing", typing = "tool_use", waiting

    /// Its place in the priority: lower is higher.
    public var rank: Int { Act.allCases.firstIndex(of: self)! }

    /// Whether it outranks `other`.
    public func beats(_ other: Act) -> Bool { rank < other.rank }

    /// How long it shows at least (`Core.settle`): running and looking move
    /// the whole body away from the keys, so they stay long enough to read
    /// as a move and not a twitch when reads and edits alternate.
    public var holdMs: Int64 { self == .running || self == .looking ? Core.poseHoldMs : Core.actHoldMs }

    /// What a running call shows, by its tool and topic: a shell command
    /// that only looks (`inspect`) is looking, and otherwise its kind
    /// decides (agent-hooks' `ToolKind`, which knows the agents' tool
    /// names): a shell command or a helper is running, a read, a search or
    /// the web is looking, and anything else is typing.
    static func of(tool: String?, topic: String?) -> Act {
        if topic == "inspect" { return .looking }
        switch ToolKind.of(tool) {
        case .shell, .subagent: return .running
        case .read, .search, .web: return .looking
        case .planning, .edit, .mcp, .other: return .typing
        }
    }
}

extension Core {
    /// What a running call shows.
    static func act(_ call: SessionTracker.Call) -> Act {
        Act.of(tool: call.tool, topic: call.topic)
    }

    /// An activity and its time: for a session's, when its evidence was
    /// last in force; for the working look's, since when it has shown. A
    /// higher one replaces it at once, a lower one or none only its hold
    /// (`Act.holdMs`) after that time.
    struct Timed: Equatable {
        var act: Act
        var at: Int64
    }

    /// An activity shows at least this long: after its last evidence in a
    /// session, and after it started showing, before a lower one or none
    /// replaces it, so fast tools don't flicker.
    public static let actHoldMs: Int64 = 1500
    /// Running and looking, the poses away from the keys, show at least
    /// this long.
    public static let poseHoldMs: Int64 = 3000
    /// A call running with nothing heard from its session for this long
    /// shows as waiting.
    public static let waitingMs: Int64 = 20_000

    /// A session's activity at `now`, before any hold: Codex's request in
    /// its grace is waiting; else the highest of its calls' (each waiting
    /// once the session has been quiet `waitingMs`, but the main agent's
    /// call for a helper, which works on), running while a helper it saw
    /// start hasn't ended, and, with no call, typing in plan mode.
    static func activity(_ s: Session, _ now: Int64) -> Act? {
        if s.pendingSince != nil { return .waiting }
        let quiet = now - s.lastEventAt >= waitingMs
        var acts = s.calls.values.map { call -> Act in
            let delegates = call.by.isEmpty && ToolKind.of(call.tool) == .subagent
            return quiet && !delegates ? .waiting : Core.act(call)
        }
        if !s.helpers.isEmpty { acts.append(.running) }
        if s.planMode && acts.isEmpty { acts.append(.typing) }
        return acts.min { $0.beats($1) }
    }

    /// The activity after `held`, with `next` put forward: a higher one at
    /// once, a lower one or none once `held`'s hold has passed since its
    /// time. The same one stays, its time moved to `now` when
    /// `refresh` (a session's evidence in force again) and kept when not
    /// (the look's, which has shown since then).
    static func settle(_ held: Timed?, _ next: Act?, now: Int64, refresh: Bool) -> Timed? {
        guard let held else { return next.map { Timed(act: $0, at: now) } }
        if next == held.act { return refresh ? Timed(act: held.act, at: now) : held }
        if let next, next.beats(held.act) { return Timed(act: next, at: now) }
        if now - held.at < held.act.holdMs { return held }
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
        // The agent the screen follows (`watched`), else the latest heard.
        let watching = watched(at: now)
        let latest = working.first { $0.s.key == watching && $0.held != nil } ?? working.filter { $0.held != nil }
            .max { ($0.s.lastEventAt, $0.s.order) < ($1.s.lastEventAt, $1.s.order) }
        shownAct = Core.settle(shownAct, latest?.held?.act, now: now, refresh: false)
    }
}
