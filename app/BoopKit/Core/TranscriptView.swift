import AgentHooks
import Foundation
import MellowHarness

/// One event with its line, as Boop's pipeline reports what an input made:
/// for `debug.jsonl`'s `view` lines, replays and
/// tests. MellowHarness keeps the line itself; this
/// adds what Boop worked out about it.
public struct ViewEvent: Equatable, Sendable {
    /// What the rules did about it by the end of the input that made it.
    public struct Did: Equatable, Sendable {
        public var message: String
        /// `rule`, `brain` or `dashboard`.
        public var by: String
        public var seq: Int
    }

    /// The `seq` of the event it is.
    public var id: Int
    public var type: Event.Kind
    public var phase: Event.Phase?
    /// The raw events it came from; the last is the one that made it.
    public var from: [Int]
    public var ts: Int64
    public var line: String
    public var notes: [String] = []
    /// Whether it wakes the brain: its kind's `wake`, a brain, and nothing
    /// holding it back when it came.
    public var wakesBrain: Bool
    /// The thread it's about, as the view keys threads; nil for pokes,
    /// what you said and idle heartbeats.
    public var about: String?
    /// For logs, evals and tests; the brain never sees them.
    public var facts: [String: JSONValue] = [:]
    public var did: [Did] = []

    /// The raw event that made it.
    public var seq: Int { from.last ?? 0 }

    /// `turn end`, `tool wait`, `poke`: its type and phase.
    public var name: String { phase.map { "\(type.rawValue) \($0.rawValue)" } ?? type.rawValue }

    /// The view event as one JSON object, for `debug.jsonl`.
    public var json: [String: Any] {
        var o: [String: Any] = ["id": id, "type": type.rawValue, "from": from, "line": line, "notes": notes,
                                "wakes_brain": wakesBrain, "facts": facts.mapValues(\.foundation)]
        if let phase { o["phase"] = phase.rawValue }
        return o
    }

    /// `turn end · claude finished …`, for debug mode and replays.
    public var summary: String {
        "\(name)\(wakesBrain ? "" : " (no pass)") · \(line)" + notes.map { " · \($0)" }.joined()
    }
}

/// Boop's lines: MellowHarness's transforms for the
/// kinds the brain hears of, their wakes and holds, and the heartbeats'
/// timed checks, registered on MellowHarness's `Harness` (`register`). Each line
/// is a function of the log up to its event: the agents' lines need each
/// thread's turn so far (which turn, how long, its tool calls, failure
/// runs), which a fold of the log keeps (`Fold`), caught up to whatever
/// event it's asked about, so its answer depends on the log alone. Its
/// sessions are agent-hooks' `SessionTracker`, as the core's are, fed the
/// same events and run to the same times, so the two agree; the fold adds
/// only what each turn did. The rest look back at the log. Touched only on
/// the runtime's queue.
public final class TranscriptView {
    /// What a thread's turn did, which the session table doesn't keep:
    /// its tool calls, topics and checks, and each check's failures in a
    /// row.
    struct Counts {
        /// This turn's tool calls, and how many failed.
        var tools = 0
        var toolsFailed = 0
        /// This turn's topics, in the order first seen, with their last state.
        var topicStates: [(topic: String, state: String)] = []
        /// A topic that passed after failing this turn.
        var comeback: String?
        /// This turn's latest topic, and its last check and whether it failed.
        var topic: String?
        var check: (topic: String, failed: Bool)?
        /// Failures in a row of each check topic, across turns.
        var failRuns: [String: Int] = [:]
    }

    /// A thread as the lines name it: its session's agent, project and
    /// workspace, and the turn it's on.
    struct Thread {
        var agent: Agent
        var id: String
        var project = "unknown"
        var workspace: String?
        var turn = 0

        var name: String { workspace ?? project }

        init(_ s: SessionTracker.Session) {
            self.init(agent: s.agent, id: s.id)
            project = s.project
            workspace = s.workspace
            turn = s.turn.number
        }

        /// A session the fold doesn't hold.
        init(agent: Agent, id: String) {
            self.agent = agent
            self.id = id
        }
    }

    /// Everything the lines need from the log so far, folded in order:
    /// a cache of a function of the log, never saved.
    struct Fold {
        /// The sessions, and what each one's turn did.
        var sessions: SessionTracker
        var counts: [String: Counts] = [:]
        /// The run of pokes going on.
        var pokes: [Int64] = []
        /// The away you haven't come back from: its
        /// event's `seq` and when you left.
        var awaySince: (seq: Int, at: Int64)?
        /// The last agent event, poke, thing you said or coming back, and
        /// the idle heartbeats since.
        var lastActivityAt: Int64?
        var heartbeats = 0
        /// The last event folded.
        var at = 0

        init(place: @escaping (String) -> Place) { sessions = SessionTracker(place: place) }
    }

    /// The personality's settings: how often the working heartbeat comes
    /// and which tool uses wake the brain.
    public private(set) var rules: Personality.Rules
    let place: (String) -> Place
    var fold: Fold
    /// How many times the fold started over, asked about an event it had
    /// already folded (tests): never in the loop, whose transforms come in
    /// order, and a start over would miss what has aged out of memory.
    var refolds = 0

    /// The working heartbeat's schedule, Boop's own timer:
    /// when it's next due, nil until work starts and again once Boop starts
    /// a reaction (the newest `react` start it has seen), with its random
    /// waits.
    var nextWorkBeatAt: Int64?
    var reactSeen = 0
    var rng: SplitMix64

    public init(rules: Personality.Rules = Personality.Rules(), seed: UInt64 = 1,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.rules = rules
        self.place = place
        fold = Fold(place: place)
        rng = SplitMix64(seed: seed)
    }

    /// What you say to Boop wakes the brain even while something needs
    /// you; nothing else does, a poke included: then a tap opens the
    /// waiting thread.
    public static let wakesWhileNeeded: Set<Event.Kind> = [.talk]

    /// The topics whose failing command fails a turn.
    static let checks: Set<String> = ["tests", "build", "deploy"]

    /// A poke within this of the one before is another in a row, which its
    /// line counts.
    public static let inARowMs: Int64 = 3000
    /// The brain's reaction to this many pokes in a row or more answers the
    /// run; to fewer, the pokes after it still wake the brain, so Boop can
    /// go from glad to miffed to grumpy.
    public static let answersRunFrom = 3
    /// While no thread works, a heartbeat after this long with no event,
    /// and again every time as long again passes.
    public static let heartbeatMs: Int64 = 60 * 60 * 1000

    /// A new personality's settings, from the next event on. The working
    /// heartbeat starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        self.rules = rules
        nextWorkBeatAt = nil
    }

    // MARK: - Registration

    /// Each kind's `wake`: what you said goes ahead
    /// of a finished turn, which goes ahead of the rest.
    public static let wakes: [String: Int] = [
        "turn_start": 0, "turn_end": 1, "tool_end": 0, "poke": 0, "talk": 2, "presence_end": 0, "heartbeat": 0,
    ]

    /// The kinds with lines that never wake the brain.
    public static let quiet = ["presence_start", "needs_you_start"]

    /// Registers Boop's lines, wakes, holds and heartbeats on `h`.
    /// `needsYou` says why nothing but what you said may wake the brain now
    /// (something needs you), or nil.
    public func register(on h: Harness, needsYou: @escaping () -> String?) {
        for (kind, wake) in Self.wakes {
            h.input(kind, wake: wake) { [unowned self] e, log in line(e, log) }
            h.hold(kind) { [unowned self] e, log in hold(e, log, needsYou: needsYou) }
        }
        for kind in Self.quiet {
            h.input(kind) { [unowned self] e, log in line(e, log) }
        }
        h.tick { [unowned self] now, log in heartbeat(at: now, log) }
    }

    /// Why `e` may not wake the brain now, or nil if it may:
    /// nothing but what you said while something needs you; not a tap that
    /// opened a thread; and not a poke while the brain's reaction to its
    /// run is in progress, with the mood unchanged.
    public func hold(_ e: Event, _ log: LogView, needsYou: () -> String?) -> String? {
        if let type = e.type, !Self.wakesWhileNeeded.contains(type), let why = needsYou() { return why }
        guard e.type == .poke else { return nil }
        if log.dids(for: e.seq).contains(where: { $0.action == Core.openThread }) { return "the tap opened a thread" }
        if pokesAnswered(e, log) { return "\(CharacterPack.active.name) is answering these pokes" }
        return nil
    }

    /// Whether the kinds `keeps` names have lines: turns'
    /// starts and ends, "needs you", pokes, what you said, you stepping
    /// away and coming back, and heartbeats, and tool calls' ends when
    /// notable, or every one with `allToolEnds` (the personality's
    /// `tool_uses: all`).
    public static func keeps(_ type: Event.Kind?, _ phase: Event.Phase?, notable: Bool, allToolEnds: Bool) -> Bool {
        switch (type, phase) {
        case (.turn?, .start?), (.turn?, .end?), (.tool?, .wait?), (.poke?, nil), (.talk?, nil), (.heartbeat?, nil),
             (.presence?, .start?), (.presence?, .end?), (.needsYou?, .start?): true
        case (.tool?, .end?): notable || allToolEnds
        default: false
        }
    }

    // MARK: - Folding

    /// Folds the log's events up to (not including) `seq` that the fold
    /// hasn't: all of them from the start again if it's past there.
    func catchUp(before seq: Int, _ log: LogView) {
        if fold.at >= seq {
            fold = Fold(place: place)
            refolds += 1
        }
        for e in log.events(after: fold.at) where e.seq < seq { _ = take(e) }
    }

    /// Folds everything in `log`.
    func catchUp(_ log: LogView) {
        for e in log.events(after: fold.at) { _ = take(e) }
    }

    /// The line for `e`, from the log before it (a transform), with `e`
    /// folded in.
    public func line(_ e: Event, _ log: LogView) -> Line? {
        catchUp(before: e.seq, log)
        return take(e)
    }

    /// Folds one event and returns its line, if it has one. The sessions'
    /// timers run to every event's time first, as the core's replay runs
    /// them.
    func take(_ e: Event) -> Line? {
        fold.at = max(fold.at, e.seq)
        if let a = AgentEvent(e) { return agentEvent(a) }
        advance(to: e.ts)
        switch e.type {
        case .session?, .turn?, .tool?, .subagent?: return nil
        case .poke?: return poke(e)
        case .talk?: return talk(e)
        case .presence?: return presence(e)
        case .heartbeat?: return heartbeat(e)
        case .needsYou?: return needs(e)
        case nil: return nil
        }
    }

    // MARK: Agents

    /// Runs the sessions' timers due by `now` (`sparing`'s Codex request
    /// isn't shown: its event comes first), and lets go of what the turns
    /// of the sessions they forgot did.
    func advance(to now: Int64, sparing: String? = nil) {
        fold.sessions.advance(to: now, sparing: sparing)
        if fold.counts.keys.contains(where: { fold.sessions.sessions[$0] == nil }) {
            fold.counts = fold.counts.filter { fold.sessions.sessions[$0.key] != nil }
        }
    }

    func agentEvent(_ a: AgentEvent) -> Line? {
        let step = SessionFold.step(a)
        let now = a.at
        let key = a.key
        advance(to: now, sparing: key)
        let before = fold.sessions.sessions[key]
        // A hook that landed after its session ended, or a stale idle
        // notice, doesn't count.
        guard let change = fold.sessions.handle(a) else { return nil }
        noteActivity(now)
        guard let s = fold.sessions.sessions[key] else {
            fold.counts[key] = nil
            return nil
        }
        // A request, and a subagent's start, end or its own turn-level
        // hook, don't move the thread's turn; only the rules care.
        if step == .needsYou || SessionFold.subagentsOwn(a, step) { return nil }
        let t = Thread(s)
        var c = fold.counts[key] ?? Counts()
        defer { fold.counts[key] = c }

        switch step {
        case .turnStart:
            c.topic = nil
            resetCounts(&c)
            return Line(EventLine.turnStart(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t)),
                        notes: a.prompt.flatMap(EventLine.prompt).map { [$0] } ?? [],
                        facts: ["thread": threadFacts(t), "prompt": .of(a.prompt)])
        case .activity:
            var topic = a.topic
            var line: Line?
            if case .callEnded = change {
                // A result may come without its call's topic: it's the
                // `PreToolUse`'s. One that landed after its turn ended
                // counts, but the turn stays over.
                let started = before?.turn.callStart(for: a)
                if topic == nil { topic = started?.topic }
                line = toolDone(&c, t, a, topic: topic, started: started?.at)
            }
            // A turn a call opens has counts of its own.
            if before?.turn.startedAt == nil, s.turn.startedAt != nil { resetCounts(&c) }
            if let topic { c.topic = topic }
            if let topic, let failed = a.failed, TranscriptView.checks.contains(topic) { c.check = (topic, failed) }
            return line
        case .turnEnd, .turnFailed, .turnStopped:
            // A finish with no turn open (a second `Stop`, one after the
            // turn stopped, or the first Boop hears from a session)
            // finishes nothing the fold saw.
            guard case .turnEnded(_, endedTurn: true) = change, let started = before?.turn.startedAt else { return nil }
            let check = c.check
            c.check = nil
            // A turn the fold joined partway (it never saw a prompt) isn't
            // told: it can't say how long it ran or what it did.
            guard t.turn > 0 else { return nil }
            let outcome: String
            switch step {
            case .turnFailed: outcome = "failed"
            case .turnStopped: outcome = "stopped"
            default: outcome = check?.failed == true ? "failed" : "done"
            }
            return turnEnded(t, c, outcome: outcome, error: step == .turnFailed ? a.error : nil,
                             message: step == .turnEnd ? a.message : nil, lengthMs: max(0, now - started))
        case .sessionStart, .sessionEnd, .needsYou, .subagentStart, .subagentEnd:
            return nil
        }
    }

    /// A turn starting, with a prompt or opened by a call: what it did
    /// starts from nothing, so a check from before it, such as a
    /// background helper's after the last `Stop`, isn't its outcome.
    func resetCounts(_ c: inout Counts) {
        c.tools = 0
        c.toolsFailed = 0
        c.topicStates = []
        c.comeback = nil
        c.check = nil
    }

    /// A finished tool call: counted for the turn, and a line when it's
    /// notable, or for every one with `tool_uses: all`.
    func toolDone(_ c: inout Counts, _ t: Thread, _ a: AgentEvent, topic: String?, started: Int64?) -> Line? {
        let failed = a.failed
        let tookMs = started.map { max(0, a.at - $0) }
        c.tools += 1
        if failed == true { c.toolsFailed += 1 }

        var failedBefore = 0
        var notable = false
        if let topic {
            if TranscriptView.checks.contains(topic), let failed {
                failedBefore = c.failRuns[topic] ?? 0
                if failed {
                    c.failRuns[topic] = failedBefore + 1
                    notable = true
                } else {
                    c.failRuns[topic] = 0
                    if failedBefore > 0 {
                        notable = true
                        c.comeback = topic
                    }
                }
                setTopic(&c, topic, failed ? "failing" : "passing")
            } else if topic == "docs" {
                setTopic(&c, topic, "edited")
            }
        }
        guard TranscriptView.keeps(.tool, .end, notable: notable, allToolEnds: rules.toolUses == .all) else { return nil }
        let category = EventLine.category(ToolKind.of(a.tool))
        let result = failed.map { $0 ? "failed" : "ok" } ?? "unknown"
        let text = notable
            ? EventLine.check(agent: t.agent.rawValue, topic: topic!, thread: threadLine(t), failed: failed!)
            : EventLine.routine(agent: t.agent.rawValue, category: category, thread: threadLine(t), failed: failed)
        var facts: [String: JSONValue] = [
            "thread": threadFacts(t), "tool": .string(category), "tool_name": .of(a.tool),
            "tool_use_id": .of(a.toolUseID), "topic": .of(topic), "result": .string(result),
            "error": .of(a.error), "failed_before": .int(Int64(failedBefore)),
        ]
        if let tookMs {
            facts["took"] = .string(Band.length(ms: tookMs))
            facts["took_ms"] = .int(tookMs)
        }
        if a.subagent != nil, let type = a.subagentType { facts["subagent"] = .string(type) }
        return Line(text, facts: facts)
    }

    func setTopic(_ c: inout Counts, _ topic: String, _ state: String) {
        if let i = c.topicStates.firstIndex(where: { $0.topic == topic }) {
            c.topicStates[i].state = state
        } else {
            c.topicStates.append((topic, state))
        }
    }

    func turnEnded(_ t: Thread, _ c: Counts, outcome: String, error: String?, message: String?, lengthMs: Int64) -> Line {
        var topicFacts: [String: JSONValue] = [:]
        for (topic, state) in c.topicStates { topicFacts[topic] = .string(state) }
        let text = EventLine.turnEnd(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t), outcome: outcome,
                                     lengthMs: lengthMs, tools: c.tools)
        return Line(text, notes: message.flatMap(EventLine.lastMessage).map { [$0] } ?? [],
                    facts: ["thread": threadFacts(t), "outcome": .string(outcome), "error": .of(error),
                            "length": .string(Band.length(ms: lengthMs)), "length_ms": .int(lengthMs),
                            "tools": .int(Int64(c.tools)), "tools_failed": .int(Int64(c.toolsFailed)),
                            "topics": .object(topicFacts), "comeback": .of(c.comeback), "message": .of(message)])
    }

    /// The thread's facts.
    func threadFacts(_ t: Thread) -> JSONValue {
        [
            "name": .string(t.name), "agent": .string(t.agent.rawValue), "turn": .int(Int64(t.turn)),
            "project": .string(t.project), "workspace": .of(t.workspace), "session": .string(t.id),
        ]
    }

    func threadLine(_ t: Thread) -> String { EventLine.thread(name: t.name, project: t.project) }

    func noteActivity(_ now: Int64) {
        fold.lastActivityAt = now
        fold.heartbeats = 0
    }

    // MARK: Pokes

    /// A poke, with how many came in a row: each within `inARowMs` of the
    /// one before.
    func poke(_ e: Event) -> Line {
        let now = e.ts
        noteActivity(now)
        if let last = fold.pokes.last, now - last >= Self.inARowMs { fold.pokes.removeAll() }
        fold.pokes.append(now)
        let count = fold.pokes.count
        let seconds = max(1, Int((now - fold.pokes[0] + 999) / 1000))
        return Line(EventLine.poke(inARow: count), facts: ["in_a_row": .int(Int64(count)), "seconds": .int(Int64(seconds))])
    }

    /// Whether the brain's reaction to the run of pokes `e` is in (to
    /// `answersRunFrom` or more in a row, not to its first ones) is still
    /// in progress, and the mood hasn't changed since it started: then
    /// another poke of the run doesn't wake the brain. A
    /// reaction a tap cut short stays in progress while the pokes go on
    /// (held by the runtime's `Reactions` and react's `keepOpen`,
    /// `heldByPokes`).
    public func pokesAnswered(_ e: Event, _ log: LogView) -> Bool {
        var run: [Event] = [e]
        for p in log.all(Event.kind(.poke, nil)).reversed() where p.seq < e.seq {
            guard run.last!.ts - p.ts < Self.inARowMs else { break }
            run.append(p)
        }
        run.reverse()
        // The pokes the run's reactions can answer: from the third in a row.
        let answering = Set(run.dropFirst(Self.answersRunFrom - 1).map(\.seq))
        guard let reaction = log.lastDid(ReactAction.actionName, where: {
            $0["open"]?.bool == true && $0.about.map(answering.contains) == true
        }) else { return false }
        guard log.ended(reaction.seq) == nil else { return false }
        return log.count(Event.did, since: reaction) { $0.action == MoodAction.actionName && $0["ok"]?.bool == true } == 0
    }

    /// Whether `e` ends a run of pokes: anything but another poke of the
    /// run (within `inARowMs` of the one before), "needs you", or
    /// MellowHarness's own events. Then the reactions a tap cut short end as
    /// done: `log` is the log before `e`.
    public static func stopsThePokes(_ e: Event, _ log: LogView) -> Bool {
        guard let type = e.type, type != .needsYou else { return false }
        guard type == .poke else { return true }
        return log.last(Event.kind(.poke, nil)).map { e.ts - $0.ts >= inARowMs } ?? true
    }

    /// Whether the reaction `did` is one your tap cut short that the pokes
    /// still hold: a poke came after it, and no
    /// event since that poke has stopped the pokes (`stopsThePokes`). While
    /// it is, MellowHarness keeps it open past react's `openFor` (react's
    /// `keepOpen`), as the app holds its handle, so a run of pokes longer
    /// than that, or the quiet after one, neither drops it from HISTORY nor
    /// gets the run a second reaction.
    public static func heldByPokes(_ did: Event, _ log: LogView) -> Bool {
        let after = log.events(after: did.seq)
        guard let cut = after.firstIndex(where: { $0.type == .poke }) else { return false }
        var lastPoke = after[cut].ts
        for e in after[after.index(after: cut)...] {
            guard let type = e.type, type != .needsYou else { continue }
            guard type == .poke, e.ts - lastPoke < inARowMs else { return false }
            lastPoke = e.ts
        }
        return true
    }

    // MARK: Talk

    /// What you said to Boop on push-to-talk. Words
    /// that are only whitespace make no line.
    func talk(_ e: Event) -> Line? {
        guard let words = e["words"]?.string, let line = EventLine.said(words) else { return nil }
        noteActivity(e.ts)
        return Line(line, facts: ["words": .string(words), "by": .string(e.specificType)])
    }

    // MARK: Here and away

    /// Whether you're away from the Mac, as the log has it: an away with no
    /// back yet. The presence detector starts from this at launch.
    public func away(_ log: LogView) -> Bool {
        catchUp(log)
        return fold.awaySince != nil
    }

    /// You stepping away or coming back, as the presence detector decided:
    /// the view only pairs them. A back with no away
    /// before it makes no line.
    func presence(_ e: Event) -> Line? {
        if e.phase == .start {
            let since = e["since"]?.int ?? e.ts
            fold.awaySince = (e.seq, since)
            return Line(EventLine.away, facts: ["why": .string(e.specificType), "since": .int(since)])
        }
        guard let away = fold.awaySince else { return nil }
        fold.awaySince = nil
        noteActivity(e.ts)
        let ms = max(0, e.ts - away.at)
        return Line(EventLine.back(ms: ms), facts: ["away": .string(Band.away(ms: ms)), "away_ms": .int(ms)])
    }

    // MARK: Heartbeats

    /// The sessions working on a turn at `now`: working, as agent-hooks
    /// groups them and the core shows them, their timers run to then, with
    /// a turn open. A background helper working on after the main agent's
    /// `Stop` is no turn, so no working heartbeat speaks of it.
    func working(at now: Int64) -> [SessionTracker.Session] {
        advance(to: now)
        return fold.sessions.grouped(at: now).working.filter { $0.turn.startedAt != nil }
    }

    /// When the oldest turn still working began, or nil: HISTORY reaches
    /// back at least that far.
    public func workingSince(at now: Int64, _ log: LogView) -> Int64? {
        catchUp(log)
        return working(at: now).compactMap(\.turn.startedAt).min()
    }

    /// A heartbeat, if one is due at `now`, for MellowHarness to
    /// emit: while threads work, once the personality's wait has passed
    /// with no reaction from Boop; while none works, each whole hour since
    /// the last agent event, poke, thing you said or coming back.
    public func heartbeat(at now: Int64, _ log: LogView) -> Event? {
        catchUp(log)
        // Boop started a reaction: the working heartbeat starts its wait
        // again, so it comes after a stretch of work with no reaction,
        // however many events woke the brain in it.
        if let react = log.lastDid(ReactAction.actionName, where: { $0["open"]?.bool == true }),
           react.seq > reactSeen {
            reactSeen = react.seq
            nextWorkBeatAt = nil
        }
        let working = !working(at: now).isEmpty
        if working, let gap = rules.workBeatMs {
            guard let due = nextWorkBeatAt else {
                nextWorkBeatAt = now + Int64(rng.int(in: gap))
                return nil
            }
            guard now >= due else { return nil }
            nextWorkBeatAt = now + Int64(rng.int(in: gap))
            return Event(ts: now, source: .clock, type: .heartbeat, specificType: "working")
        }
        nextWorkBeatAt = nil
        guard !working, let last = fold.lastActivityAt, (now - last) / Self.heartbeatMs > Int64(fold.heartbeats) else {
            return nil
        }
        return Event(ts: now, source: .clock, type: .heartbeat, specificType: "idle")
    }

    func heartbeat(_ e: Event) -> Line? {
        let now = e.ts
        let working = working(at: now)
        if let s = working.min(by: { ($0.turn.startedAt ?? now, $0.order) < ($1.turn.startedAt ?? now, $1.order) }) {
            let t = Thread(s)
            let ms = max(0, now - (s.turn.startedAt ?? now))
            return Line(EventLine.working(agent: t.agent.rawValue, thread: threadLine(t), ms: ms),
                        facts: ["thread": threadFacts(t), "working_ms": .int(ms), "topic": .of(fold.counts[s.key]?.topic)])
        }
        guard let last = fold.lastActivityAt else { return nil }
        let hours = (now - last) / Self.heartbeatMs
        guard hours > 0 else { return nil }
        fold.heartbeats = Int(hours)
        return Line(EventLine.heartbeat(hours: Int(hours)), facts: ["idle_hours": .int(hours)])
    }

    // MARK: Needs you

    /// "Needs you" showing (the core's) is a line; its clearing isn't.
    /// Whether a session waits is the fold's own sessions', not these
    /// records'.
    func needs(_ e: Event) -> Line? {
        guard e.phase == .start, let agent = (e["agent"]?.string).flatMap(Agent.init(rawValue:)),
              let session = e.session else { return nil }
        let t = fold.sessions.sessions[SessionFold.key(agent, session)].map(Thread.init) ?? Thread(agent: agent, id: session)
        // The request's own event is a tool call's wait; "needs you"
        // showing is when it has a line, after Codex's grace.
        return Line(EventLine.needsYou(agent: agent.rawValue, thread: threadLine(t)), facts: ["thread": threadFacts(t)])
    }

    // MARK: Reading

    /// The thread an event is about, as the view keys threads: an agent's
    /// or "needs you"'s session, or the thread its line's facts name (a
    /// working heartbeat's); nil for the rest.
    public static func about(_ e: Event, facts: [String: JSONValue]?) -> String? {
        if let agent = e.agent ?? (e["agent"]?.string).flatMap(Agent.init(rawValue:)), let session = e.session {
            return SessionFold.key(agent, session)
        }
        guard let t = facts?["thread"]?.object, let agent = t["agent"]?.string.flatMap(Agent.init(rawValue:)),
              let id = t["session"]?.string else { return nil }
        return SessionFold.key(agent, id)
    }

    /// The thread `key` names: its agent, its name as its agent's app shows
    /// it once an event brought one, else as its lines name it (its
    /// workspace, else its project), and where it opens on the Mac.
    public func who(about key: String, _ log: LogView) -> (agent: String, thread: String, opens: ThreadRef)? {
        catchUp(log)
        return fold.sessions.sessions[key].map { ($0.agent.rawValue, $0.name ?? Thread($0).name, $0.thread) }
    }

    /// The sessions as the fold has them, caught up to `log` (tests).
    func sessions(_ log: LogView) -> [String: SessionTracker.Session] {
        catchUp(log)
        return fold.sessions.sessions
    }

    /// A `ViewEvent` for `e` and its line, for what an input reports.
    func view(_ e: Event, _ line: Line, wakes: Bool, log: LogView) -> ViewEvent? {
        guard let type = e.type else { return nil }
        let (shownType, shownPhase) = type == .needsYou ? (Event.Kind.tool, Event.Phase.wait) : (type, e.phase)
        let from = type == .needsYou ? (e["for"]?.int.map { [Int($0), e.seq] } ?? [e.seq])
            : type == .presence && e.phase == .end ? [log.last(Event.kind(.presence, .start))?.seq, e.seq].compactMap { $0 }
            : [e.seq]
        return ViewEvent(id: e.seq, type: shownType, phase: shownPhase, from: from, ts: e.ts, line: line.text, notes: line.notes,
                         wakesBrain: wakes,
                         about: Self.about(e, facts: line.facts),
                         facts: line.facts)
    }
}

/// The lines view events are written as. Only facts shown to
/// Jev reach them.
public enum EventLine {
    /// A thread as the lines name it: `"fix-nav" (landing)`, or just
    /// `"landing"` when the name is the project.
    public static func thread(name: String, project: String) -> String {
        name == project ? "\"\(name)\"" : "\"\(name)\" (\(project))"
    }

    public static func turnStart(agent: String, turn: Int, thread: String) -> String {
        "\(agent) started turn \(turn) on \(thread)."
    }

    /// `claude finished turn 7 on "fix-nav" (landing): done, a very long
    /// turn, 12 tool calls.`: the outcome, the length band and how many
    /// tool calls it made.
    public static func turnEnd(agent: String, turn: Int, thread: String, outcome: String, lengthMs: Int64,
                               tools: Int) -> String {
        let how = outcome == "failed" || outcome == "stopped" ? outcome : "done"
        return "\(agent) finished turn \(turn) on \(thread): \(how), a \(Band.length(ms: lengthMs)) turn, \(toolCalls(tools))."
    }

    static func toolCalls(_ n: Int) -> String {
        n == 0 ? "no tool calls" : n == 1 ? "1 tool call" : "\(n) tool calls"
    }

    /// The longest prompt, last message or thing you said that the state
    /// quotes, in characters.
    public static let messageMax = 300

    /// `Its last message: "…"`: the agent's last message, quoted.
    public static func lastMessage(_ message: String) -> String? { quote("Its last message", message) }

    /// `You asked: "…"`: your prompt, quoted.
    public static func prompt(_ prompt: String) -> String? { quote("You asked", prompt) }

    /// Words on one line, cut to `messageMax`, after `label`. Nil for none.
    static func quote(_ label: String, _ text: String) -> String? {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        let cut = flat.count > messageMax ? String(flat.prefix(messageMax - 1)) + "…" : flat
        return "\(label): \"\(cut)\""
    }

    /// A tool use that woke the brain: a check that failed, or passed after
    /// failing.
    public static func check(agent: String, topic: String, thread: String, failed: Bool) -> String {
        "\(agent)'s \(topic) \(failed ? "failed" : "passed") on \(thread)\(failed ? "" : " after failing")."
    }

    /// Any other tool use, with the personality's `tool_uses: all`.
    public static func routine(agent: String, category: String, thread: String, failed: Bool?) -> String {
        let what = switch category {
        case "shell": "ran a command"
        case "edit": "edited a file"
        case "read": "read a file"
        case "search": "searched"
        case "web": "looked something up on the web"
        case "subagent": "started a subagent"
        default: "used a tool"
        }
        return "\(agent) \(what) on \(thread)." + (failed == true ? " It failed." : "")
    }

    /// `You said to Boop: "…"`: what you said on push-to-talk, quoted and
    /// cut to `messageMax`, like your prompt. Nil for no words.
    public static func said(_ words: String) -> String? { quote("You said to \(CharacterPack.active.name)", words) }

    /// `You poked Boop.`, or `You poked Boop 4 times in a row.`
    public static func poke(inARow count: Int) -> String {
        count <= 1 ? "You poked \(CharacterPack.active.name)." : "You poked \(CharacterPack.active.name) \(count) times in a row."
    }

    /// You stepping away from the Mac.
    public static let away = "You stepped away from the Mac."

    /// `You came back to the Mac after a long break.`: the break's band.
    public static func back(ms: Int64) -> String {
        "You came back to the Mac after a \(Band.away(ms: ms)) break."
    }

    public static func heartbeat(hours: Int) -> String {
        "Nothing has happened for \(hours) hour\(hours == 1 ? "" : "s")."
    }

    /// The working heartbeat: `claude is still working on "fix-nav"
    /// (landing), a long turn.`, the band of the turn so far.
    public static func working(agent: String, thread: String, ms: Int64) -> String {
        "\(agent) is still working on \(thread), a \(Band.length(ms: ms)) turn."
    }

    /// How to read HISTORY and NOW: Boop's own
    /// words for MellowHarness's layout, after the guide, with the pack's
    /// name for the creature.
    public static var reading: String {
        let name = CharacterPack.active.name
        return """
            How to read HISTORY and NOW:
            - HISTORY is oldest first. Each line says how long ago it happened.
              Lines indented under it add to it: an agent's last message, then
              what \(name) did. A line of what \(name) did ending in (in progress)
              hasn't finished yet.
            - NOW is what to react to. Its last line is what \(name) already did on
              its own, by reflex.
            """
    }

    /// The words the lines use, as the guide explains them after how to
    /// read the layout. Kept here, next to the lines.
    public static let words = """
        - claude and codex are the person's coding agents.
        - A thread is one conversation with an agent, named after its workspace:
          "fix-nav" (landing) is the thread fix-nav in the project landing.
        - A turn is one request to a thread. It ends done, failed or stopped.
        - Tests, build, deploy and docs are what a command was about; failed
          means it ended with an error.
        - Turns are short (under a minute), long (under 5 minutes) or very
          long (5 minutes or more).
        - "You said to \(CharacterPack.active.name)" quotes the person talking to \(CharacterPack.active.name). It can't talk
          back: it answers with a face, and maybe a word or a sound.
        - "You" stepping away from the Mac and coming back is the person. Breaks
          are short (under 15 minutes), long (under 2 hours) or very long (2
          hours or more).
        """

    public static func needsYou(agent: String, thread: String) -> String {
        "\(agent) needs you on \(thread)."
    }

    /// The tool's category in a line's facts: agent-hooks'
    /// kind, but for planning, which the brain hears as `other`, as before
    /// the kinds moved there.
    public static func category(_ kind: ToolKind) -> String {
        kind == .planning ? ToolKind.other.rawValue : kind.rawValue
    }
}
