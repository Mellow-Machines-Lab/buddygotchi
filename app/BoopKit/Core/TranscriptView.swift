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
        /// The lines this turn's edits added and removed: counts, never
        /// the text.
        var linesAdded = 0, linesRemoved = 0
        /// This turn's topics, in the order first seen, with their last state.
        var topicStates: [(topic: String, state: String)] = []
        /// A topic that passed after failing this turn.
        var comeback: String?
        /// This turn's latest topic, and its last check and whether it failed.
        var topic: String?
        var check: (topic: String, failed: Bool)?
        /// Failures in a row of each check topic, across turns.
        var failRuns: [String: Int] = [:]
        /// This turn's failed checks, which a failed finish counts.
        var checksFailed = 0
        /// Quick wins in a row on the thread, across turns, and when the
        /// last one finished: a finish done in under `quickWinMs` within
        /// `winRunGapMs` of the last.
        var wins: (run: Int, at: Int64)?
        /// This turn's working heartbeats.
        var checkIns = 0
        /// The work stream's moments that hit Boop this turn
        /// (`WorkStream.hits`), and how many of them a line has said.
        var hits: [String] = []
        var hitsSaid = 0
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
        /// The run of pokes going on, on each buddy (`""` for the only one):
        /// when each came, and whether the run came again, within `againMs`
        /// of the run before.
        var pokes: [String: (at: [Int64], again: Bool)] = [:]
        /// The away you haven't come back from: its
        /// event's `seq` and when you left.
        var awaySince: (seq: Int, at: Int64)?
        /// The buddies lying face down (`""` for the only one), from their
        /// `facedown` until their `peekaboo`.
        var faceDown: Set<String> = []
        /// The last agent event, poke, thing you said or coming back, and
        /// the idle heartbeats since.
        var lastActivityAt: Int64?
        var heartbeats = 0
        /// The last event folded, and whether the last agent event had a
        /// line: a request it answered says so only when it didn't.
        var at = 0
        var lastAgentLined = false
        /// The finishes whose last message's reading comes next, by
        /// session: its line, which the reading's adds to.
        var unread: [String: Line] = [:]
        /// When each session's calls that climb the work stream's failure
        /// ladder failed, within `WorkStream.ladderMs`.
        var ladder: [String: [Int64]] = [:]
        /// Each session's latest check or finished turn, by how it came
        /// out, for what Boop says when you ask (`StatusReply`).
        var results: [String: StatusReply.Result] = [:]

        /// Its tracker never asks whether an agent's process runs: the core
        /// records a session whose agent is gone as its turn stopping
        /// (`Core.agentGone`), so the fold depends on the log alone.
        init(place: @escaping (String) -> Place) { sessions = SessionTracker(place: place, isRunning: { _ in true }) }
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
    /// The idle check-in's schedule: the activity it follows, and when it's
    /// next due, drawn after that activity and after each check-in.
    var idleBeat: (after: Int64, due: Int64)?
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

    /// A failed call that takes the work stream's failure ladder to this
    /// rung or the next (the helmet, then the throw) is a line that wakes
    /// the brain: a stray failure is only a bonk, and past the top rung
    /// the bonks go quiet again.
    public static let wakingRungs = 3...4

    /// A finish done in under this is a quick win, and quick wins within
    /// `winRunGapMs` of each other are a run the line counts, as it counts
    /// pokes, in streaks of `EventLine.streak`: the brain answers each rung
    /// differently, where it would answer the same line the same way every
    /// time, and a long run goes round the ladder again rather than staying
    /// on its top rung.
    public static let quickWinMs: Int64 = 5 * 60_000
    public static let winRunGapMs: Int64 = 10 * 60_000

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
    /// For this long after the last agent event, poke, thing you said or
    /// coming back, while a session is open and you're at the Mac, the
    /// idle heartbeat comes at the personality's `idle_heartbeat` pace
    /// instead: an idle check-in, so Boop has something to fidget at
    /// while you're around.
    public static let idleWindowMs: Int64 = 2 * 60 * 60 * 1000
    /// A run of pokes within this of the run before it is that run again,
    /// which its line says.
    public static let againMs: Int64 = 2 * 60_000

    /// A new personality's settings, from the next event on. The working
    /// heartbeat starts its wait again at the new pace.
    public func setRules(_ rules: Personality.Rules) {
        self.rules = rules
        nextWorkBeatAt = nil
        idleBeat = nil
    }

    // MARK: - Registration

    /// Each kind's `wake`: what you said goes ahead
    /// of a finished turn, which goes ahead of the rest. A turn start
    /// whose prompt is being read, or a finish whose last message is,
    /// keeps its line but waits for its reading to wake the brain
    /// (`hold`).
    public static let wakes: [String: Int] = [
        "turn_start": 0, "prompt": 0, "turn_end": 1, "last_message": 1, "tool_end": 0, "poke": 0, "talk": 2, "presence_end": 0,
        "heartbeat": 0, "reacted": 0, "session_start": 0, "needs_you_end": 0, "gesture": 0,
    ]

    /// The kinds with lines that never wake the brain: a BOOT press that
    /// opens an agent is the board's own reaction, as a tap that opens a
    /// thread is.
    public static let quiet = ["presence_start", "needs_you_start", "press"]

    /// Registers Boop's lines, wakes, holds and heartbeats on `h`. Weakly:
    /// a harness its runtime let go of may still tick once, and does nothing.
    /// `needsYou` says why nothing but what you said may wake the brain now
    /// for a buddy (something needs you on its board), or nil: the only
    /// one's for nil.
    public func register(on h: Harness, needsYou: @escaping (_ buddy: String?) -> String?) {
        for (kind, wake) in Self.wakes {
            h.input(kind, wake: wake) { [weak self] e, log in self?.line(e, log) }
            h.hold(kind) { [weak self] e, log, voice in self?.hold(e, log, buddy: voice?.id, needsYou: { needsYou(voice?.id) }) }
        }
        for kind in Self.quiet {
            h.input(kind) { [weak self] e, log in self?.line(e, log) }
        }
        h.tick { [weak self] now, log in self?.heartbeat(at: now, log) }
    }

    /// Why `e` may not wake the brain now, or nil if it may:
    /// nothing but what you said while something needs you; not a tap that
    /// opened a thread; and not a poke while the brain's reaction to its
    /// run is in progress, with the mood unchanged; and nothing but what
    /// you said while the buddy (`e`'s, else `buddy`, else any) lies face
    /// down, which is do not disturb: the board would refuse a reaction.
    public func hold(_ e: Event, _ log: LogView, buddy: String? = nil, needsYou: () -> String?) -> String? {
        if let type = e.type, !Self.wakesWhileNeeded.contains(type), let why = needsYou() { return why }
        if e.type == .reacted, (e["chain"]?.int ?? 1) > Buddy.maxRepliesInARow {
            return "the buddies have answered each other \(Buddy.maxRepliesInARow) times in a row"
        }
        if e.type == .gesture, e.specificType == "facedown" { return "\(name(e)) is face down" }
        if e[PromptIntake.readingFollows]?.bool == true { return "its reading wakes the brain" }
        // Folded up to `e` at most: `e` itself, if folded, is neither of
        // the two gestures that change it, so the fold says as before it.
        for x in log.events(after: fold.at) where x.seq <= e.seq { _ = take(x) }
        let key = e.buddy ?? buddy
        let down = key.map { fold.faceDown.contains($0) || fold.faceDown.contains("") } ?? !fold.faceDown.isEmpty
        if down, e.type != .talk, !(e.type == .gesture && e.specificType == "peekaboo") { return "\(name(e)) is face down" }
        guard e.type == .poke else { return nil }
        if log.dids(for: e.seq).contains(where: { $0.action == Core.openThread }) { return "the tap opened a thread" }
        if pokesAnswered(e, log) { return "\(name(e)) is answering these pokes" }
        return nil
    }

    /// Whether the kinds `keeps` names have lines: turns'
    /// starts and ends, "needs you", pokes, what you said, you stepping
    /// away and coming back, and heartbeats, and tool calls' ends when
    /// notable, or every one with `allToolEnds` (the personality's
    /// `tool_uses: all`).
    public static func keeps(_ type: Event.Kind?, _ phase: Event.Phase?, notable: Bool, allToolEnds: Bool) -> Bool {
        switch (type, phase) {
        case (.turn?, .start?), (.turn?, .end?), (.tool?, .wait?), (.poke?, nil), (.press?, nil), (.gesture?, nil), (.talk?, nil), (.prompt?, nil),
             (.lastMessage?, nil), (.heartbeat?, nil),
             (.presence?, .start?), (.presence?, .end?), (.needsYou?, .start?), (.needsYou?, .end?): true
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
        return whose(take(e), e)
    }

    /// The buddies when there are several (`Buddy`), for whose lines are
    /// whose, else the only one's name: the pipeline sets them, before the
    /// first event.
    var buddies: [Buddy] = []
    var onlyName = CharacterPack.active.name

    /// The name of the buddy `e` is about, else the only one's.
    func name(_ e: Event) -> String { buddies.first { $0.id == e.buddy }?.name ?? onlyName }

    /// With several buddies, an agent's line, or "needs you"'s, says whose
    /// agent it is.
    func whose(_ line: Line?, _ e: Event) -> Line? {
        guard var line, buddies.count > 1, e.agent != nil || e.type == .needsYou, e.buddy != nil else { return line }
        line.text += " (\(name(e))'s agent)"
        return line
    }

    /// Folds one event and returns its line, if it has one. The sessions'
    /// timers run to every event's time first, as the core's replay runs
    /// them.
    func take(_ e: Event) -> Line? {
        fold.at = max(fold.at, e.seq)
        if e.kind == Event.did, e.action == WorkStream.action {
            // A word of the work stream that came forward: no line, and
            // counted for the turn's lines when it hit Boop.
            if let gag = e["as"]?.string, WorkStream.hits.contains(gag), let key = e["session"]?.string,
               fold.counts[key] != nil || fold.sessions.sessions[key] != nil {
                fold.counts[key, default: Counts()].hits.append(gag)
            }
            return nil
        }
        if let a = AgentEvent(e) {
            let line = agentEvent(a)
            fold.lastAgentLined = line != nil
            // A finish whose last message is being read keeps its line, for
            // its reading's to add to.
            if let line, a.kind == .turn, a.phase == .end, e[PromptIntake.readingFollows]?.bool == true { fold.unread[a.key] = line }
            return line
        }
        advance(to: e.at)
        switch e.type {
        case .session?, .turn?, .tool?, .subagent?: return nil
        case .poke?: return poke(e)
        case .press?:
            noteActivity(e.at)
            return Line(e.specificType == Core.drawerPick ? EventLine.picked(name: name(e)) : EventLine.pressed(name: name(e)))
        case .prompt?:
            return promptRead(e)
        case .lastMessage?:
            return messageRead(e)
        case .gesture?:
            noteActivity(e.at)
            if e.specificType == "facedown" { fold.faceDown.insert(e.buddy ?? "") }
            if e.specificType == "peekaboo" { fold.faceDown.remove(e.buddy ?? "") }
            return EventLine.gesture(e.specificType, name: name(e)).map { Line($0, facts: ["gesture": .string(e.specificType)]) }
        case .talk?: return talk(e)
        case .presence?: return presence(e)
        case .heartbeat?: return heartbeat(e)
        case .needsYou?: return needs(e)
        case .reacted?: return e["message"]?.string.map { Line($0) }
        case .listen?, nil: return nil
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
            fold.unread = fold.unread.filter { fold.sessions.sessions[$0.key] != nil }
            fold.ladder = fold.ladder.filter { fold.sessions.sessions[$0.key] != nil }
            fold.results = fold.results.filter { fold.sessions.sessions[$0.key] != nil }
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
        // An agent gone stops its turn, but nobody did anything.
        let gone = a.hook == Core.agentGone
        if !gone { noteActivity(now) }
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
            // The last finish's reading, if it's still to come, is too late:
            // the finish keeps its plain line.
            fold.unread[key] = nil
            return Line(EventLine.turnStart(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t)),
                        facts: ["thread": threadFacts(t)])
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
            if let topic, let failed = a.failed, TranscriptView.checks.contains(topic) {
                c.check = (topic, failed)
                fold.results[key] = StatusReply.Result(topic: topic, outcome: failed ? "failed" : "passed", at: now)
            }
            return line
        case .turnEnd, .turnFailed, .turnStopped:
            // A finish with no turn open (a second `Stop`, one after the
            // turn stopped, or the first Boop hears from a session)
            // finishes nothing the fold saw.
            guard case .turnEnded(_, endedTurn: true) = change, let started = before?.turn.startedAt else { return nil }
            // An agent gone finished nothing: its turn just stops.
            if gone {
                c.check = nil
                return nil
            }
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
            fold.results[key] = StatusReply.Result(topic: nil, outcome: outcome, at: now)
            let run = c.wins.flatMap { now - $0.at < Self.winRunGapMs ? $0.run : nil } ?? 0
            c.wins = outcome == "done" && now - started < Self.quickWinMs ? (run + 1, now) : nil
            var line = turnEnded(t, c, outcome: outcome, error: step == .turnFailed ? a.error : nil, lengthMs: max(0, now - started))
            if let hits = newHits(&c, name: onlyName) { line.notes.append(hits) }
            return line
        case .sessionStart:
            // The agent's context was compacted: it carries on from a
            // summary. Any other session start is no line.
            guard case .sessionStarted(let source) = change, source == Mapping.compacted else { return nil }
            return Line(EventLine.compacted(agent: t.agent.rawValue, thread: threadLine(t)), facts: ["thread": threadFacts(t)])
        case .sessionEnd, .needsYou, .subagentStart, .subagentEnd:
            return nil
        }
    }

    /// A turn starting, with a prompt or opened by a call: what it did
    /// starts from nothing, so a check from before it, such as a
    /// background helper's after the last `Stop`, isn't its outcome.
    func resetCounts(_ c: inout Counts) {
        c.tools = 0
        c.toolsFailed = 0
        c.linesAdded = 0
        c.linesRemoved = 0
        c.topicStates = []
        c.comeback = nil
        c.check = nil
        c.checksFailed = 0
        c.checkIns = 0
        c.hits = []
        c.hitsSaid = 0
    }

    /// A finished tool call: counted for the turn, and a line when it's
    /// notable, or for every one with `tool_uses: all`.
    func toolDone(_ c: inout Counts, _ t: Thread, _ a: AgentEvent, topic: String?, started: Int64?) -> Line? {
        let failed = a.failed
        let tookMs = started.map { max(0, a.at - $0) }
        c.tools += 1
        if failed == true { c.toolsFailed += 1 }
        if failed != true { c.linesAdded += a.linesAdded ?? 0; c.linesRemoved += a.linesRemoved ?? 0 }

        var failedBefore = 0
        var notable = false
        var rung = 0
        if WorkStream.climbs(a) {
            let recent = (fold.ladder[a.key] ?? []).filter { a.at - $0 < WorkStream.ladderMs } + [a.at]
            fold.ladder[a.key] = recent
            rung = recent.count
            notable = Self.wakingRungs.contains(rung)
        }
        if let topic {
            if TranscriptView.checks.contains(topic), let failed {
                failedBefore = c.failRuns[topic] ?? 0
                if failed {
                    c.failRuns[topic] = failedBefore + 1
                    c.checksFailed += 1
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
        let text = notable && rung > 0
            ? EventLine.failing(agent: t.agent.rawValue, thread: threadLine(t), count: rung, name: onlyName)
            : notable
            ? EventLine.check(agent: t.agent.rawValue, topic: topic!, thread: threadLine(t), failed: failed!,
                              inARow: failedBefore + 1)
            : EventLine.routine(agent: t.agent.rawValue, category: category, thread: threadLine(t), failed: failed)
        var facts: [String: JSONValue] = [
            "thread": threadFacts(t), "tool": .string(category), "tool_name": .of(a.tool),
            "tool_use_id": .of(a.toolUseID), "topic": .of(topic), "result": .string(result),
            "error": .of(a.error), "failed_before": .int(Int64(failedBefore)),
        ]
        if rung > 0 { facts["failing"] = .int(Int64(rung)) }
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

    /// The note on the moments of the work stream that hit Boop since a
    /// line last said them, at most once a line: the brain hears of them
    /// at a pass it has anyway, never one each.
    func newHits(_ c: inout Counts, name: String) -> String? {
        guard c.hits.count > c.hitsSaid else { return nil }
        defer { c.hitsSaid = c.hits.count }
        return EventLine.hits(Array(c.hits[c.hitsSaid...]), name: name)
    }

    /// A finish: what the turn did, never the agent's words, which only
    /// its message's reading tells (`messageRead`).
    func turnEnded(_ t: Thread, _ c: Counts, outcome: String, error: String?, lengthMs: Int64) -> Line {
        var topicFacts: [String: JSONValue] = [:]
        for (topic, state) in c.topicStates { topicFacts[topic] = .string(state) }
        let text = EventLine.turnEnd(agent: t.agent.rawValue, turn: t.turn, thread: threadLine(t), outcome: outcome,
                                     lengthMs: lengthMs, tools: c.tools, failedChecks: c.checksFailed,
                                     ofStreak: EventLine.rung(c.wins?.run ?? 0, of: EventLine.streak),
                                     linesGone: c.linesRemoved - c.linesAdded)
        return Line(text, facts: ["thread": threadFacts(t), "outcome": .string(outcome), "error": .of(error),
                            "length": .string(Band.length(ms: lengthMs)), "length_ms": .int(lengthMs),
                            "tools": .int(Int64(c.tools)), "tools_failed": .int(Int64(c.toolsFailed)),
                            "lines_added": .int(Int64(c.linesAdded)), "lines_removed": .int(Int64(c.linesRemoved)),
                            "checks_failed": .int(Int64(c.checksFailed)), "wins_in_a_row": .int(Int64(c.wins?.run ?? 0)),
                            "topics": .object(topicFacts), "comeback": .of(c.comeback)])
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

    // MARK: Your prompt

    /// Your prompt's reading, under its turn's thread: what you asked for,
    /// how long and how you sound, and your words for a sign as a note.
    func promptRead(_ e: Event) -> Line? {
        guard let reading = PromptReading(facts: e.data) else { return nil }
        noteActivity(e.at)
        let t = Self.about(e, facts: nil).flatMap { fold.sessions.sessions[$0] }.map(Thread.init)
        return Line(EventLine.asked(reading, agent: e.agent?.rawValue ?? "the agent", thread: t.map(threadLine)),
                    notes: EventLine.yourWords(reading.phrases).map { [$0] } ?? [],
                    facts: e.data.merging(["thread": t.map(threadFacts) ?? .null]) { a, _ in a })
    }

    // MARK: The agent's last message

    /// The agent's last message's reading: its finish's line, saying what
    /// the message claims and how it sounds, with its words for a sign
    /// added to its notes. None for a finish the fold didn't line.
    func messageRead(_ e: Event) -> Line? {
        guard let key = Self.about(e, facts: nil), let finish = fold.unread.removeValue(forKey: key),
              let reading = MessageReading(facts: e.data) else { return nil }
        return Line(EventLine.finished(finish.text, saying: reading),
                    notes: finish.notes + (EventLine.itsWords(reading.phrases).map { [$0] } ?? []),
                    facts: finish.facts.merging(["message": .object(reading.facts)]) { _, b in b })
    }

    // MARK: Pokes

    /// A poke, with how many came in a row: each within `inARowMs` of the
    /// one before.
    func poke(_ e: Event) -> Line {
        let now = e.at
        noteActivity(now)
        let who = e.buddy ?? ""
        var run = fold.pokes[who] ?? ([], false)
        if let last = run.at.last, now - last >= Self.inARowMs { run = ([], now - last < Self.againMs) }
        run.at.append(now)
        fold.pokes[who] = run
        let count = run.at.count
        let seconds = max(1, Int((now - run.at[0] + 999) / 1000))
        // The first poke of a run wakes Boop; the rest find it awake.
        let asleep = count == 1 && fold.sessions.sessions.isEmpty
        return Line(EventLine.poke(inARow: count, name: name(e), asleep: asleep, again: run.again),
                    facts: ["in_a_row": .int(Int64(count)), "seconds": .int(Int64(seconds)), "asleep": .bool(asleep),
                            "again": .bool(run.again)])
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
            guard run.last!.at - p.at < Self.inARowMs else { break }
            if p.buddy == e.buddy { run.append(p) }
        }
        run.reverse()
        // The pokes the run's reactions can answer: from the third in a row.
        let answering = Set(run.dropFirst(Self.answersRunFrom - 1).map(\.seq))
        let mine = { (d: Event) in d.buddy == e.buddy }
        guard let reaction = log.lastDid(ReactOutput.outputName, where: {
            $0["open"]?.bool == true && $0.about.map(answering.contains) == true && mine($0)
        }) else { return false }
        guard log.ended(reaction.seq) == nil else { return false }
        return log.count(Event.did, since: reaction) { $0.action == MoodOutput.outputName && $0["ok"]?.bool == true && mine($0) } == 0
    }

    /// Whether `e` ends a run of pokes: anything but another poke of the
    /// run (within `inARowMs` of the one before), "needs you",
    /// push-to-talk's `listen` records, or MellowHarness's own events. Then
    /// the reactions a tap cut short end as done: `log` is the log before
    /// `e`.
    public static func stopsThePokes(_ e: Event, _ log: LogView) -> Bool {
        guard let type = e.type, !passesThePokes.contains(type) else { return false }
        guard type == .poke else { return true }
        return log.last(Event.kind(.poke, nil)).map { e.at - $0.at >= inARowMs } ?? true
    }

    /// The core's records that a run of pokes goes on through.
    static let passesThePokes: Set<Event.Kind> = [.needsYou, .listen, .reacted]

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
        var lastPoke = after[cut].at
        for e in after[after.index(after: cut)...] {
            guard let type = e.type, !passesThePokes.contains(type) else { continue }
            guard type == .poke, e.at - lastPoke < inARowMs else { return false }
            lastPoke = e.at
        }
        return true
    }

    // MARK: Talk

    /// What you said to Boop on push-to-talk. Words
    /// that are only whitespace make no line.
    func talk(_ e: Event) -> Line? {
        guard let words = e["words"]?.string, let line = EventLine.said(words, to: e.buddy == nil && buddies.count > 1
                                                                                     ? EventLine.everyone(buddies) : name(e)) else { return nil }
        noteActivity(e.at)
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
            let since = e["since"]?.int ?? e.at
            fold.awaySince = (e.seq, since)
            return Line(EventLine.away, facts: ["why": .string(e.specificType), "since": .int(since)])
        }
        guard let away = fold.awaySince else { return nil }
        fold.awaySince = nil
        noteActivity(e.at)
        let ms = max(0, e.at - away.at)
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
        if let react = log.lastDid(ReactOutput.outputName, where: { $0["open"]?.bool == true }),
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
            return Event(at: now, source: .clock, type: .heartbeat, specificType: "working")
        }
        nextWorkBeatAt = nil
        guard !working, let last = fold.lastActivityAt else { return nil }
        // An idle check-in, at the personality's pace: a session is open,
        // you're at the Mac, and it's within `idleWindowMs` of the last
        // activity. Once you're away, or it's been quiet longer than that,
        // as over a night or a weekend, only the hourly heartbeat comes;
        // nothing reads the time of day.
        if let gap = rules.idleBeatMs, fold.awaySince == nil, !fold.sessions.sessions.isEmpty, now - last < Self.idleWindowMs {
            if idleBeat?.after != last { idleBeat = (last, last + Int64(rng.int(in: gap))) }
            guard let beat = idleBeat, now >= beat.due else { return nil }
            idleBeat = (last, now + Int64(rng.int(in: gap)))
            return Event(at: now, source: .clock, type: .heartbeat, specificType: "check_in")
        }
        guard (now - last) / Self.heartbeatMs > Int64(fold.heartbeats) else { return nil }
        return Event(at: now, source: .clock, type: .heartbeat, specificType: "idle")
    }

    func heartbeat(_ e: Event) -> Line? {
        let now = e.at
        let working = working(at: now)
        if let s = working.min(by: { ($0.turn.startedAt ?? now, $0.order) < ($1.turn.startedAt ?? now, $1.order) }) {
            let t = Thread(s)
            let ms = max(0, now - (s.turn.startedAt ?? now))
            // Each check-in on a turn is a rung of a ladder, as quick wins
            // are: the line says which.
            var c = fold.counts[s.key] ?? Counts()
            c.checkIns += 1
            let hits = newHits(&c, name: name(e))
            fold.counts[s.key] = c
            return Line(EventLine.working(agent: t.agent.rawValue, thread: threadLine(t), ms: ms, topic: c.topic),
                        notes: (EventLine.checkIn(EventLine.rung(c.checkIns, of: EventLine.round), name: name(e)).map { [$0] } ?? [])
                            + (hits.map { [$0] } ?? []),
                        facts: ["thread": threadFacts(t), "working_ms": .int(ms), "topic": .of(c.topic),
                                "check_in": .int(Int64(c.checkIns))])
        }
        guard let last = fold.lastActivityAt else { return nil }
        let hours = (now - last) / Self.heartbeatMs
        if e.specificType == "check_in",
           let s = fold.sessions.sessions.values.max(by: { ($0.lastEventAt, $0.order) < ($1.lastEventAt, $1.order) }) {
            // An idle check-in: you're around, and no agent works.
            fold.heartbeats = Int(hours)
            let t = Thread(s), minutes = (now - last) / 60_000
            return Line(EventLine.idle(minutes: Int(minutes), agent: t.agent.rawValue, thread: threadLine(t)),
                        facts: ["thread": threadFacts(t), "idle_minutes": .int(minutes)])
        }
        guard hours > 0 else { return nil }
        fold.heartbeats = Int(hours)
        return Line(EventLine.heartbeat(hours: Int(hours)), facts: ["idle_hours": .int(hours)])
    }

    // MARK: Needs you

    /// "Needs you" showing (the core's) is a line, and so is its clearing
    /// when you answered (allowed or denied it) and the agent works on,
    /// unless what answered it has a line of its own (tests failing right
    /// after you allowed them): one moment, one line. One that cleared for
    /// any other reason (forgotten, the session ended) or with the turn (a
    /// stop) isn't. Whether a
    /// session waits is the fold's own sessions', not these records'.
    func needs(_ e: Event) -> Line? {
        guard let agent = (e["agent"]?.string).flatMap(Agent.init(rawValue:)), let session = e.session else { return nil }
        let s = fold.sessions.sessions[SessionFold.key(agent, session)]
        let t = s.map(Thread.init) ?? Thread(agent: agent, id: session)
        if e.phase == .end {
            guard e["outcome"]?.string == "done", s?.turn.startedAt != nil, !fold.lastAgentLined else { return nil }
            noteActivity(e.at)
            return Line(EventLine.answered(agent: agent.rawValue, thread: threadLine(t)), facts: ["thread": threadFacts(t)])
        }
        guard e.phase == .start else { return nil }
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

    /// Each session's latest check or finished turn, caught up to `log`:
    /// how it came out, for what Boop says when you ask (`StatusReply`).
    public func results(_ log: LogView) -> [String: StatusReply.Result] {
        catchUp(log)
        return fold.results
    }

    /// The sessions as the fold has them, caught up to `log` (tests).
    func sessions(_ log: LogView) -> [String: SessionTracker.Session] {
        catchUp(log)
        return fold.sessions.sessions
    }

    /// A `ViewEvent` for `e` and its line, for what an input reports.
    func view(_ e: Event, _ line: Line, wakes: Bool, log: LogView) -> ViewEvent? {
        guard let type = e.type else { return nil }
        let (shownType, shownPhase) = type == .needsYou && e.phase == .start ? (Event.Kind.tool, Event.Phase.wait) : (type, e.phase)
        let from = type == .needsYou ? (e["for"]?.int.map { [Int($0), e.seq] } ?? [e.seq])
            : type == .presence && e.phase == .end ? [log.last(Event.kind(.presence, .start))?.seq, e.seq].compactMap { $0 }
            : [e.seq]
        return ViewEvent(id: e.seq, type: shownType, phase: shownPhase, from: from, ts: e.at, line: line.text, notes: line.notes,
                         wakesBrain: wakes,
                         about: Self.about(e, facts: line.facts),
                         facts: line.facts)
    }
}
