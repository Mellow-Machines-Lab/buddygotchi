import AgentHooks
import Foundation
import MellowHarness

/// The core: plain rules with no queue. It reads the
/// session table agent-hooks keeps (`SessionTracker`) and
/// decides which visual the device shows, what the
/// agents are doing included (`act`), and which one-shots the rules play.
/// What it does by rule it records as `action`
/// events: "needs you" showing and ending, and a poke (the `wiggle`
/// action, by its older name: the device plays its poke), or while
/// something needs you, the thread it opens (`open_thread`). What the
/// brain hears is the view's; everything expressive
/// is the brain's.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
/// The time is a steady clock, so a change to the Mac's clock can't stretch
/// a timer; days and times of day follow the wall clock the app reports
/// with `setWallClock`.
public final class Core {
    public struct Config: Sendable {
        public var volume: Int
        /// Boop's mood, which the mood action sets
        /// and every `state` carries.
        public var mood = MoodAction.initial
        public var time: LocalTime
        public var seed: UInt64
        /// Where this launch's request numbers start: the first request
        /// shown gets the one after it (`SessionTracker.nextRequest`). The
        /// app starts each launch somewhere random (`Core.randomFirstAsk`),
        /// so a request can't share `attn.id` with one the device still
        /// shows from the last launch.
        public var firstAsk = 0

        public init(volume: Int = 6, time: LocalTime = LocalTime(), seed: UInt64 = 1) {
            self.volume = volume
            self.time = time
            self.seed = seed
        }
    }

    /// A session, as agent-hooks keeps it.
    typealias Session = SessionTracker.Session

    public private(set) var config: Config

    /// Every agent session, what it's doing and who needs you.
    let tracker: SessionTracker
    var sessions: [String: Session] { tracker.sessions }
    /// The last request's number: they count up from `config.firstAsk`.
    var lastAsk: Int { tracker.lastRequest }
    var rng: SplitMix64
    /// The last day with any activity, or the day the app opened: the first
    /// activity of a later one is a new day.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    /// The session list as last published, which can change while the
    /// snapshot doesn't: a second idle session, say.
    var lastSessions: [SessionSummary] = []
    /// The visual the device shows and its variation, from 1, and the last
    /// variation each visual showed, which the next one there avoids.
    var shown: (visual: String, variant: Int) = ("", 1)
    var lastVariant: [String: Int] = [:]
    /// The activity the working look shows (`updateActs`), and each
    /// working session's, held.
    var shownAct: Timed?
    var held: [String: Timed] = [:]
    /// When the rules last played the error one-shot: at most one every
    /// `errorEveryMs`.
    var lastErrorAt: Int64?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0
    /// The sessions "needs you" showed for when last published, for their
    /// `needs_you` actions.
    var shownNeeds: [String: (agent: Agent, id: String)] = [:]

    // Push-to-talk.
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// mic button.
    public enum Talker: String, Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// After the mic goes off, the device holds `listening` this long at
    /// most for the reply (firmware `kListenHoldMs`).
    public static let replyWaitMs: Int64 = 8000
    /// While the Mac's mic is on: who turned it on, and when.
    public private(set) var listening: (by: Talker, since: Int64)?
    /// Once the mic is off, until when the device still shows `listening`
    /// waiting for the reply; nil once it's over.
    var replyUntil: Int64?

    /// `lastActiveDay` is the day the app opened, which the launch has
    /// started already, or nil to make the first activity a new day.
    /// `place` names a working directory's project.
    public init(config: Config, lastActiveDay: String? = nil,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.config = config
        self.lastActiveDay = lastActiveDay
        tracker = SessionTracker(firstRequest: config.firstAsk, place: place)
        rng = SplitMix64(seed: config.seed)
    }

    /// The thread's name as its agent's app shows it, for the session `key`
    /// names (the view's keys are the same), or nil.
    public func name(about key: String) -> String? { sessions[key]?.name }

    /// Where the session `key` names opens on the Mac, or nil.
    public func thread(about key: String) -> ThreadRef? { sessions[key]?.thread }

    /// The rules' one-shots.
    public static let starting = "starting", stopped = "stopped", error = "error", helperReturn = "helper_return"
    /// The failed calls that play the error one-shot: a command that
    /// exited with an error or timed out, never a request you denied.
    static let errorClasses: Set<String> = ["exit_code", "timeout"]
    /// The error one-shot plays at most once in this long.
    public static let errorEveryMs: Int64 = 30_000

    // MARK: - Inputs

    /// An agent's event, as recorded (its `seq` set): anything else is
    /// ignored. Its time is now.
    @discardableResult
    public func handle(_ event: Event) -> [CoreEffect] {
        guard let agentEvent = AgentEvent(event) else { return [] }
        let now = event.ts
        var fx: [CoreEffect] = []
        let shot = take(agentEvent, ref: event.seq)
        startDayIfNew(now, &fx)
        if let shot { play(shot, now, &fx) }
        publish(now, &fx)
        return fx
    }

    /// `event` without the name, app, app session and mode its session
    /// already has, which `apply` carries on, so the transcript doesn't
    /// repeat them on every line. A session this
    /// core doesn't hold, or forgets before the event, gets them all, and
    /// so does its first event of each of the transcript's days: a launch
    /// reads back only the last days' files.
    func unrepeated(_ event: Event) -> Event {
        guard let agent = event.agent, let session = event.session,
              let s = sessions[SessionFold.key(agent, session)], !SessionFold.forgotten(s.lastEventAt, at: event.ts),
              config.time.day(s.lastEventAt) == config.time.day(event.ts) else { return event }
        var event = event
        for (key, held) in [("name", s.name), ("app", s.app), ("app_session", s.appSession)]
        where held != nil && event[key]?.string == held {
            event.data[key] = nil
        }
        if let mode = event["mode"]?.string, (mode == "plan") == s.planMode { event.data["mode"] = nil }
        return event
    }

    /// A launch picks the sessions up from the transcript it reads back, as
    /// the view does: each agent event is taken as
    /// `handle` takes it, and the timers run at every event's time, as the
    /// last launch's ticks did when they recorded something. What the
    /// rules did then is recorded already, so nothing is carried out.
    /// Which requests were shown is what the `needs_you` records say, as
    /// the view has it: where the sessions folded again disagree, the
    /// first publish records the start or end that's missing, with why a
    /// request the read-back cleared did.
    public func replay(_ event: Event) {
        if let agentEvent = AgentEvent(event) {
            _ = take(agentEvent, ref: event.seq)
            return
        }
        advance(to: event.ts)
        if event.type == .needsYou, let session = event.session,
           let agent = event["agent"]?.string.flatMap(Agent.init(rawValue:)) {
            let key = SessionFold.key(agent, session)
            shownNeeds[key] = event.phase == .start ? (agent, session) : nil
            if event.phase == .start { tracker.clearedWhy[key] = nil }
        }
    }

    /// An agent's event folded into the session table, the timers due by
    /// its time run first: the one-shot it plays, if any.
    /// `ref` is its `seq`, which a request it starts keeps.
    private func take(_ event: AgentEvent, ref: Int) -> DeviceMoment? {
        let key = event.key
        guard let change = tracker.handle(event, ref: ref) else { return nil }
        let now = event.at
        switch change {
        case .sessionStarted(let source):
            // Resumed or compacted, the work goes on; started or cleared,
            // it's a fresh session. A context compacted has a start of its
            // own, where the face draws one.
            return DeviceMoment(anim: Core.starting, ctx: Core.startCtx(source: source))
        case .turnStarted:
            held[key] = nil
            return DeviceMoment(anim: Core.starting, ctx: "new_task")
        case .callEnded(let call, let late):
            // The activity the call showed holds from now.
            if let call, held[key]?.act == Core.act(call) { held[key]?.at = now }
            let failed = event.failed == true
            if !late, failed, event.error.map(Core.errorClasses.contains) == true {
                // A command that failed or timed out, not a request you
                // denied.
                return DeviceMoment(anim: Core.error)
            }
            if !late, !failed, let call, Core.act(call) == .delegating, !call.sawSubagent {
                // A helper's call returned, from hooks that don't say when
                // helpers start: its `SubagentStop` can't.
                return DeviceMoment(anim: Core.helperReturn)
            }
            return nil
        case .turnEnded(let outcome, let endedTurn):
            // Only a stop that ends a turn plays its one-shot: Claude's idle
            // notice after a turn that finished doesn't.
            held[key] = nil
            return outcome == .stopped && endedTurn ? DeviceMoment(anim: Core.stopped) : nil
        case .subagentEnded(let returned):
            // A helper Boop saw start returns, while its turn goes on.
            return returned ? DeviceMoment(anim: Core.helperReturn) : nil
        case .sessionEnded:
            held[key] = nil
            return nil
        case .callStarted, .asked, .subagentStarted, .other:
            return nil
        }
    }

    /// A rule's one-shot, in Boop's mood with a
    /// variation at random, never the one it played last: not while
    /// something needs you or `listening` holds the screen, and the error
    /// one-shot at most once every `errorEveryMs`. The device also skips
    /// it while a brain reaction holds its turn (`if_free`).
    func play(_ shot: DeviceMoment, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let anim = shot.anim, !needsYouShowing, !showsListening(at: now) else { return }
        if anim == Core.error {
            if let last = lastErrorAt, now - last < Core.errorEveryMs { return }
            lastErrorAt = now
        }
        var moment = shot
        moment.variant = Core.pickVariant(mood: config.mood, state: anim, ctx: shot.ctx,
                                          avoiding: lastVariant[anim], &rng)
        lastVariant[anim] = moment.variant
        fx.append(.moment(moment))
    }

    /// A tap on the device, recorded as the poke `seq`, on the brain's
    /// finish for `finish`'s thread, if the device said so. The device has
    /// already reacted.
    @discardableResult
    public func poke(at now: Int64, seq: Int? = nil, finish: ThreadRef? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        poked(now, seq: seq, finish: finish, &fx)
        publish(now, &fx)
        return fx
    }

    /// Push-to-talk: start or stop listening, after the device's BOOT
    /// button (`talk_on`, `talk_off`), which already shows `listening`, or
    /// the app's mic button, for which the runtime has the device show it.
    @discardableResult
    public func listen(_ on: Bool, by talker: Talker = .app, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        if on { startListening(by: talker, now, &fx) } else { stopListening(now, &fx) }
        publish(now, &fx)
        return fx
    }

    /// The link to the device dropped, so its button's release can't
    /// arrive: stop listening now. The app's mic button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        if listening?.by == .device { stopListening(now, &fx) }
        return fx
    }

    /// The device stopped showing `listening`: the reply went out, or the
    /// runtime ended it with `stop_listening` because none is coming, or
    /// the mic couldn't start.
    public func listeningEnded() {
        listening = nil
        replyUntil = nil
    }

    /// Whether the device shows `listening` at `now`: the mic is on, or it
    /// went off and the reply hasn't come yet.
    public func showsListening(at now: Int64) -> Bool {
        listening != nil || replyUntil.map { now < $0 } == true
    }

    @discardableResult
    public func setVolume(_ volume: Int, at now: Int64) -> [CoreEffect] {
        config.volume = max(0, min(10, volume))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The mood the log has at launch, before anything is published.
    public func restore(mood: String) { config.mood = mood }

    /// The mood action saved a new mood: the next `state` carries it.
    public func setMood(_ mood: String, at now: Int64) -> [CoreEffect] {
        config.mood = mood
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The wall clock's time at the steady time `now`: days and times of
    /// day follow it, and timers don't.
    public func setWallClock(_ wallMs: Int64, at now: Int64) {
        wallOffsetMs = wallMs - now
    }

    /// Timers: the Codex grace period, the safety net and the mic's 30 s
    /// limit.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        if let l = listening, now - l.since >= Self.listenLimitMs {
            // The device's own button hits the same limit.
            stopListening(now, &fx)
        }
        publish(now, &fx)
        return fx
    }

    // MARK: - Reading

    /// The sessions in the order the popover lists them: those that need
    /// you (oldest first), then working, then idle.
    func grouped(at now: Int64) -> (waiting: [Session], working: [Session], idle: [Session]) {
        tracker.grouped(at: now)
    }

    public func snapshot(at now: Int64) -> StateSnapshot {
        let (waiting, working, _) = grouped(at: now)
        let base = !working.isEmpty ? "working" : sessions.isEmpty ? "asleep" : "idle"
        let attn = waiting.first.map {
            StateSnapshot.Attention(
                agent: $0.agent.rawValue, project: StateSnapshot.clip($0.project, marked: true, max: StateSnapshot.maxSignBytes),
                name: $0.name.map { StateSnapshot.clip($0, marked: true, max: StateSnapshot.maxSignBytes) } ?? "",
                more: waiting.count - 1, id: $0.request)
        }
        // What the agents are doing shows only in the working look, and
        // not while something needs you.
        let act = base == "working" && attn == nil ? shownAct?.act.rawValue : nil
        var snapshot = StateSnapshot(base: base, act: act, mood: config.mood, attn: attn, busy: working.count,
                                     vol: config.volume, variant: 1)
        if shown.visual == snapshot.visual { snapshot.variant = shown.variant }
        return snapshot
    }

    /// What a session's start is, from its `source`, as starting's `ctx`:
    /// `session` for a fresh one (started or cleared, or no source),
    /// `continuation` for one resumed, and `compacted` for one whose
    /// context was compacted, or `continuation` too with a face that draws
    /// no start for that.
    public static func startCtx(source: String?) -> String {
        switch source {
        case "compact": FaceLoops.draws(state: Core.starting, ctx: "compacted") ? "compacted" : "continuation"
        case "resume": "continuation"
        default: "session"
        }
    }

    /// A variation of `mood`'s design for `state` at random, from 1, among
    /// those for `outcome` and `ctx` (FaceLoops.variants), never `last`
    /// when there's another: the rules pick it for now,
    /// and the harness may later.
    public static func pickVariant(mood: String, state: String, outcome: String? = nil, ctx: String? = nil,
                                   avoiding last: Int?, _ rng: inout SplitMix64) -> Int {
        let fit = FaceLoops.variants(mood: MoodGraph.pixelFallback(mood), state: state, outcome: outcome, ctx: ctx)
        let choices = fit.filter { $0 != last }
        guard !choices.isEmpty else { return fit.first ?? 1 }
        return choices[rng.int(in: 0...(choices.count - 1))]
    }

    /// Every session, for the popover's list. The device doesn't
    /// get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (waiting, working, idle) = grouped(at: now)
        return waiting.map { SessionSummary($0, .waiting) } + working.map { SessionSummary($0, .working) }
            + idle.map { SessionSummary($0, .idle) }
    }

    /// Why nothing but what you said wakes the brain (a tap then opens the
    /// thread), and no reaction plays, or nil: something needs you.
    public var needsYouBlock: String? {
        needsYouShowing ? "something needs you" : nil
    }

    /// Why a reaction can't play now, or nil: something needs you, or the
    /// mic is on, since a reaction would end `listening` before you've
    /// finished.
    public var reactionBlock: String? {
        needsYouBlock ?? (listening != nil ? "the mic is on" : nil)
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

    /// The date at steady time `now`, on the wall clock: the calendar never
    /// sees steady time.
    private func day(_ now: Int64) -> String { config.time.day(wall(now)) }

    func isWorking(_ s: Session, _ now: Int64) -> Bool { tracker.isWorking(s, at: now) }

    /// Whether "needs you" shows: then no event's pass starts.
    public var needsYouShowing: Bool { tracker.needsYou }

    /// A random place for a launch's request numbers to start, so
    /// `attn.id` doesn't repeat one the device still shows from the last
    /// launch.
    public static func randomFirstAsk() -> Int { SessionTracker.randomFirstRequest() }

    /// The first activity of a new day, for the transcript's pruning.
    func startDayIfNew(_ now: Int64, _ fx: inout [CoreEffect]) {
        let today = day(now)
        guard today != lastActiveDay else { return }
        lastActiveDay = today
        fx.append(.newDay(date: today))
    }

    /// A poke: the device plays its poke (`poked`, `tap_spam` from the third
    /// in a row), and the brain hears of it through the view, which counts
    /// the pokes in a row. The rules add no animation of
    /// their own, but record it, as the `wiggle` action whose older name and
    /// words Jev reads. While `listening` shows
    /// nothing replaces it: the device plays no poke, so nothing is
    /// recorded. While something needs you the device plays no poke either:
    /// the tap opens the thread the sign names on the Mac, recorded as the
    /// `open_thread` action. Nor on the brain's finish
    /// that names whose turn it was: the tap opens that thread.
    func poked(_ now: Int64, seq: Int?, finish: ThreadRef?, _ fx: inout [CoreEffect]) {
        guard !showsListening(at: now) else { return }
        func open(_ thread: ThreadRef, _ message: String) {
            fx.append(.record(Event.did(message, for: seq, action: Core.openThread, by: "rule",
                                        facts: ["agent": .string(thread.agent)], at: now)))
            fx.append(.open(thread))
        }
        if let waiting = grouped(at: now).waiting.first { return open(waiting.thread, Core.openedThread) }
        if let finish { return open(finish, Core.openedFinished) }
        fx.append(.record(Event.did(Core.wiggled, for: seq, action: Core.wiggle, by: "rule", at: now)))
    }

    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard listening == nil else { return }
        listening = (talker, now)
        replyUntil = nil
        fx.append(.listen(true, by: talker))
    }

    /// Turns the mic off, if it's on. The device holds `listening` for the
    /// reply until the runtime says it's over (`listeningEnded`), or
    /// `replyWaitMs` at most.
    func stopListening(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard let l = listening else { return }
        listening = nil
        replyUntil = now + Self.replyWaitMs
        fx.append(.listen(false, by: l.by))
    }

    /// The rule actions' names and messages.
    public static let wiggle = "wiggle"
    public static let wiggled = "\(CharacterPack.active.name) wiggled on its own."
    public static let openThread = "open_thread"
    public static let openedThread = "\(CharacterPack.active.name) opened the thread that needs you on the Mac."
    public static let openedFinished = "\(CharacterPack.active.name) opened the thread that finished on the Mac."
    public static let needsYou = "needs_you"

    /// Runs the session table's timers due by `now`: a
    /// Codex request past its grace shows, the safety net, and forgetting.
    func advance(to now: Int64) {
        tracker.advance(to: now)
    }

    /// "Needs you" starting or clearing for a session, as a rule action:
    /// the view says who needs you from it, and knows while nothing may
    /// wake the brain. A session gone while it
    /// waited clears too.
    func recordNeeds(_ now: Int64, _ fx: inout [CoreEffect]) {
        let showing = sessions.filter { $0.value.needsSince != nil }
        for (key, s) in showing.sorted(by: { ($0.value.needsSince!, $0.value.request) < ($1.value.needsSince!, $1.value.request) })
        where shownNeeds[key] == nil {
            shownNeeds[key] = (s.agent, s.id)
            tracker.clearedWhy[key] = nil
            fx.append(.record(Event(ts: now, source: .boop, type: .needsYou, phase: .start, specificType: Core.needsYou,
                                    session: s.id,
                                    data: ["for": s.requestRef.map { .int(Int64($0)) } ?? .null, "by": "rule",
                                           "agent": .string(s.agent.rawValue), "ok": true,
                                           "message": .string("\(CharacterPack.active.name) showed that \(s.agent.rawValue) needs you.")])))
        }
        for (key, was) in shownNeeds.sorted(by: { $0.key < $1.key }) where showing[key] == nil {
            shownNeeds[key] = nil
            let why = tracker.clearedWhy.removeValue(forKey: key) ?? (sessions[key] == nil ? "the session ended" : nil)
            var data: [String: JSONValue] = ["by": "rule", "agent": .string(was.agent.rawValue),
                                             "outcome": why == nil ? "done" : "failed"]
            if let why { data["why"] = .string(why) }
            fx.append(.record(Event(ts: now, source: .boop, type: .needsYou, phase: .end, specificType: Core.needsYou,
                                    session: was.id, data: data)))
        }
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        recordNeeds(now, &fx)
        updateActs(now)
        var snapshot = snapshot(at: now)
        if snapshot.visual != shown.visual || shown.variant > FaceLoops.count(mood: MoodGraph.pixelFallback(config.mood), state: snapshot.visual) {
            // A new visual, or a new mood with fewer variations of it than
            // the one showing: a variation of it at random.
            shown = (snapshot.visual, Core.pickVariant(mood: config.mood, state: snapshot.visual,
                                                         avoiding: lastVariant[snapshot.visual], &rng))
            lastVariant[snapshot.visual] = shown.variant
            snapshot.variant = shown.variant
        }
        let sessions = sessionList(at: now)
        defer { lastSessions = sessions }
        if snapshot != lastPublished {
            lastPublished = snapshot
            // The picture changes before any moment plays on top of it.
            fx.insert(.state(snapshot), at: 0)
        } else if sessions != lastSessions {
            fx.insert(.sessions, at: 0)
        }
    }
}

/// One session as the popover lists it.
public struct SessionSummary: Equatable, Sendable {
    public enum Status: String, Sendable { case waiting, working, idle }

    /// `claude` or `codex`.
    public var agent: String
    public var project: String
    /// The thread's name as its agent's app shows it, once an event brought one.
    public var name: String?
    /// The thread's workspace: a linked worktree's folder or the branch,
    /// or nil when the folder has neither.
    public var workspace: String?
    public var status: Status
    /// Which thread it is, for clicking the row open.
    public var thread: ThreadRef?

    public init(agent: String, project: String, name: String? = nil, workspace: String? = nil, status: Status,
                thread: ThreadRef? = nil) {
        self.agent = agent
        self.project = project
        self.name = name
        self.workspace = workspace
        self.status = status
        self.thread = thread
    }

    init(_ s: Core.Session, _ status: Status) {
        self.init(agent: s.agent.rawValue, project: s.project, name: s.name, workspace: s.workspace, status: status,
                  thread: s.thread)
    }
}
