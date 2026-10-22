import AgentHooks
import Foundation
import MellowHarness

/// The core: plain rules with no queue. It reads the
/// session table agent-hooks keeps (`SessionTracker`) and
/// decides which visual the device shows, what the
/// agents are doing included (`act`), and which reactions the rules play.
/// What it does by rule it records as `action`
/// events: "needs you" showing and ending, and a poke (the `wiggle`
/// action, by its older name: the device plays its poke), or while
/// something needs you, the thread it opens (`open_thread`), and each
/// reaction it plays (`starting`, `stopped`, `error`, `helper_return`),
/// as a `did` named after it. It also
/// keeps push-to-talk (`Talk`): when the mic
/// goes on and off and when `listening` ends, recorded as `listen` events
/// that make no line. What the brain hears is the view's; everything
/// expressive is the brain's.
///
/// It's a pure state machine: every call takes the time and returns effects
/// for the app to carry out. Call `tick` about once a second for the timers.
/// The time is a steady clock, so a change to the Mac's clock can't stretch
/// a timer; days and times of day follow the wall clock the app reports
/// with `setWallClock`.
public final class Core {
    public struct Config: Sendable {
        public var volume: Int
        public var time: LocalTime
        public var seed: UInt64
        /// Where this launch's request numbers start: the first request
        /// shown gets the one after it (`SessionTracker.nextRequest`). The
        /// app starts each launch somewhere random
        /// (`SessionTracker.randomFirstRequest`), so a request can't share
        /// `attn.id` with one the device still shows from the last launch.
        public var firstAsk = 0
        /// Whose rules these are: the buddy's character, the process's by
        /// default.
        public var pack: CharacterPack
        /// The day Boop hatched (`yyyy-MM-dd`), for its milestone days; nil
        /// for none.
        public var hatched: String?
        /// The growth stage Boop reached last and the day it did: that day
        /// is a party (`Occasions`).
        public var stageReached: (name: String, day: String)?

        public init(volume: Int = 6, time: LocalTime = LocalTime(), seed: UInt64 = 1, pack: CharacterPack = .active,
                    hatched: String? = nil) {
            self.volume = volume
            self.time = time
            self.seed = seed
            self.pack = pack
            self.hatched = hatched
        }
    }

    /// A session, as agent-hooks keeps it.
    typealias Session = SessionTracker.Session

    public private(set) var config: Config
    /// Boop's mood now, which every `state` carries and the rules'
    /// reactions are drawn in: the runtime reads it from the transcript,
    /// where the mood output keeps it. The resting mood until it's set.
    var mood: () -> String

    /// Every agent session, what it's doing and who needs you.
    let tracker: SessionTracker
    var sessions: [String: Session] { tracker.sessions }
    var rng: SplitMix64
    /// The last day with any activity, or the day the app opened: the first
    /// activity of a later one is a new day.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    /// The session list as last published, which can change while the
    /// snapshot doesn't: a second idle session, say.
    var lastSessions: [SessionSummary] = []
    /// The last variation each rule's reaction played, which the next one
    /// there avoids. The device picks the looks' variations itself.
    var lastVariant: [String: Int] = [:]
    /// The session a BOOT press opened last, and when.
    var lastHanded: (key: String, at: Int64)?
    /// The activity the working look shows (`updateActs`), and each
    /// working session's, held.
    var shownAct: Timed?
    var held: [String: Timed] = [:]
    /// The calendar's tags, worked out once a quarter of an hour: every
    /// time zone's hours start on one, so the part of the day and the date
    /// can't change within it.
    var whenCache: (slot: Int64, hatched: String?, stage: String?, tags: [String])?
    /// When the rules last played the error reaction: at most one every
    /// `errorEveryMs`.
    var lastErrorAt: Int64?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0
    /// The sessions "needs you" showed for when last published, for their
    /// `needs_you` actions.
    var shownNeeds: [String: (agent: Agent, id: String)] = [:]
    /// The sessions whose request the tracker's safety net expired, until
    /// the `needs_you` end that says so is recorded, or the next start.
    var expired: Set<String> = []
    /// Why a request the safety net expired cleared.
    static let expiredWhy = "nothing for 10 minutes"

    // Push-to-talk.
    /// Who turned the Mac's mic on: the device's BOOT button or the app's
    /// mic button.
    public enum Talker: String, Sendable { case device, app }
    /// The mic is never on longer than this, whatever happens to the release.
    public static let listenLimitMs: Int64 = 30_000
    /// After the mic goes off, the device holds `listening` this long at
    /// most for the reply (firmware `kListenHoldMs`).
    public static let replyWaitMs: Int64 = 8000

    /// Push-to-talk as the core keeps it, its one owner: the runtime turns
    /// the mic on and off and plays what the core says, and the popover
    /// shows a copy.
    public struct Talk: Equatable, Sendable {
        /// While the Mac's mic is on: who turned it on, and when.
        public struct Mic: Equatable, Sendable {
            public var by: Talker
            public var since: Int64
        }

        public var mic: Mic?
        /// Whose button turned the mic on last: what it hears is theirs.
        public var by: Talker = .app
        /// Once the mic is off, until when the device still shows
        /// `listening` waiting for the reply; nil once it's over.
        public var replyUntil: Int64?
        /// The `seq` of what you said, while its reply may still come: the
        /// first pass on it or on anything newer ends `listening` unless
        /// it reacted, which is the reply.
        public var replyFor: Int?
        /// Why push-to-talk couldn't hear you, until the next try.
        public var trouble: String?
    }

    public private(set) var talk = Talk()
    /// While the Mac's mic is on: who turned it on, and when.
    public var listening: Talk.Mic? { talk.mic }

    /// Why listening started, waited or ended, as its records say.
    public enum ListenWhy {
        public static let released = "released", limit = "limit", linkDown = "link down", replied = "replied",
                          noReply = "no reply", heardNothing = "heard nothing", micFailed = "mic failed",
                          timedOut = "timed out"
    }

    /// `lastActiveDay` is the day the app opened, which the launch has
    /// started already, or nil to make the first activity a new day.
    /// `place` names a working directory's project.
    public init(config: Config, lastActiveDay: String? = nil,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) }) {
        self.config = config
        mood = { config.pack.defaultMood }
        self.lastActiveDay = lastActiveDay
        tracker = SessionTracker(firstRequest: config.firstAsk, place: place)
        rng = SplitMix64(seed: config.seed)
    }

    /// The rules' reactions.
    public static let starting = "starting", stopped = "stopped", error = "error", helperReturn = "helper_return"
    /// The failed calls that play the error reaction: a command that
    /// exited with an error or timed out, never a request you denied.
    static let errorClasses: Set<String> = [ToolError.exitCode, ToolError.timeout]
    /// The error reaction plays at most once in this long.
    public static let errorEveryMs: Int64 = 30_000

    // MARK: - Inputs

    /// An agent's event, as recorded (its `seq` set): anything else is
    /// ignored. Its time is now.
    @discardableResult
    public func handle(_ event: Event) -> [CoreEffect] {
        guard let agentEvent = AgentEvent(event) else { return [] }
        let now = event.at
        var fx: [CoreEffect] = []
        let reaction = fold(agentEvent, ref: event.seq)
        startDayIfNew(now, &fx)
        if let reaction { play(reaction, for: event.seq, now, &fx) }
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
              let s = sessions[SessionFold.key(agent, session)], !SessionFold.forgotten(s.lastEventAt, at: event.at),
              config.time.day(s.lastEventAt) == config.time.day(event.at) else { return event }
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
    /// Which requests were shown is what the `needs_you` records say:
    /// where the sessions folded again disagree (a launch that missed an
    /// end, or ran the timers at other times), the first publish records
    /// the start or end that's missing, with why a request the read-back
    /// cleared did.
    public func replay(_ event: Event) {
        if let agentEvent = AgentEvent(event) {
            _ = fold(agentEvent, ref: event.seq)
            return
        }
        advance(to: event.at)
        if event.type == .needsYou, let session = event.session,
           let agent = event["agent"]?.string.flatMap(Agent.init(rawValue:)) {
            let key = SessionFold.key(agent, session)
            shownNeeds[key] = event.phase == .start ? (agent, session) : nil
            if event.phase == .start { expired.remove(key) }
        }
    }

    /// An agent's event folded into the session table, the timers due by
    /// its time run first: the reaction it plays, if any.
    /// `ref` is its `seq`, which a request it starts keeps.
    private func fold(_ event: AgentEvent, ref: Int) -> DeviceReaction? {
        let key = event.key
        // The timers due by the event's time first, to hear what they did.
        advance(to: event.at, sparing: key)
        guard let change = tracker.handle(event, ref: ref) else { return nil }
        let now = event.at
        switch change {
        case .sessionStarted(let source):
            return DeviceReaction(anim: Core.starting, ctx: Core.startCtx(source: source))
        case .turnStarted:
            held[key] = nil
            return DeviceReaction(anim: Core.starting, ctx: "new_task")
        case .callEnded(let call, let late):
            // The activity the call showed holds from now.
            if let call, held[key]?.act == Core.act(call) { held[key]?.at = now }
            let failed = event.failed == true
            if !late, failed, event.error.map(Core.errorClasses.contains) == true {
                // A command that failed or timed out, not a request you
                // denied.
                return DeviceReaction(anim: Core.error)
            }
            if !late, !failed, let call, Core.act(call) == .delegating, !call.sawSubagent {
                // A helper's call returned, from hooks that don't say when
                // helpers start: its `SubagentStop` can't.
                return DeviceReaction(anim: Core.helperReturn)
            }
            return nil
        case .turnEnded(let outcome, let endedTurn):
            // Only a stop that ends a turn plays its reaction: Claude's idle
            // notice after a turn that finished doesn't.
            held[key] = nil
            return outcome == .stopped && endedTurn ? DeviceReaction(anim: Core.stopped) : nil
        case .subagentEnded(let returned):
            // A helper Boop saw start returns, while its turn goes on.
            return returned ? DeviceReaction(anim: Core.helperReturn) : nil
        case .sessionEnded:
            held[key] = nil
            return nil
        case .callStarted, .asked, .subagentStarted, .requestExpired, .other:
            return nil
        }
    }

    /// A rule's reaction, in Boop's mood with a
    /// variation at random, never the one it played last: not while
    /// something needs you or `listening` holds the screen, and the error
    /// reaction at most once every `errorEveryMs`. The device also skips
    /// it while a brain reaction plays (`if_free`). Recorded as a
    /// `did` named after it, for the event `seq` that played it, as the
    /// poke's `wiggle` is, so the brain hears that Boop already reacted.
    func play(_ rule: DeviceReaction, for seq: Int?, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let anim = rule.anim, !needsYouShowing, !showsListening(at: now) else { return }
        if anim == Core.error {
            if let last = lastErrorAt, now - last < Core.errorEveryMs { return }
            lastErrorAt = now
        }
        var reaction = rule
        reaction.variant = Core.pickVariant(mood: mood(), state: anim, ctx: rule.ctx,
                                            avoiding: lastVariant[anim], in: config.pack, &rng)
        lastVariant[anim] = reaction.variant
        fx.append(.reaction(reaction))
        let played = Core.played(reaction, by: config.pack.name)
        var did = Event.did(played ?? "", for: seq, action: anim, by: "rule",
                            facts: reaction.ctx.map { ["ctx": .string($0)] } ?? [:], at: now)
        if played == nil { did.data["message"] = nil }
        fx.append(.record(did))
    }

    /// What a rule reaction's `did` says Boop did, for HISTORY and NOW: `Boop
    /// reacted to the error on its own.` None for `starting`: every turn
    /// starts with it, so the brain hears the start itself and nothing
    /// more, and the log alone keeps that it played.
    static func played(_ reaction: DeviceReaction, by name: String = CharacterPack.active.name) -> String? {
        let what: String
        switch reaction.anim {
        case Core.stopped?: what = "the stop"
        case Core.error?: what = "the error"
        case Core.helperReturn?: what = "the helper coming back"
        default: return nil
        }
        return "\(name) reacted to \(what) on its own."
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

    /// BOOT pressed, recorded as `seq`: the board has handed you the next
    /// agent (`pressed`).
    @discardableResult
    public func press(at now: Int64, seq: Int? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        pressed(now, seq: seq, &fx)
        publish(now, &fx)
        return fx
    }

    /// Push-to-talk: start or stop listening, after the device's BOOT
    /// button (`talk_on`, `talk_off`), which already shows `listening`, or
    /// the app's mic button, for which the device is told to show it.
    @discardableResult
    public func listen(_ on: Bool, by talker: Talker = .app, at now: Int64) -> [CoreEffect] {
        talkInput(now) { fx in
            if on { startListening(by: talker, now, &fx) } else { stopListening(ListenWhy.released, now, &fx) }
        }
    }

    /// The link to the device dropped, so its button's release can't
    /// arrive: stop listening now. The app's mic button carries on.
    @discardableResult
    public func linkDown(at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            if talk.mic?.by == .device { stopListening(ListenWhy.linkDown, now, &fx) }
        }
    }

    /// What the mic heard was recorded as said, the event `seq` if it
    /// wakes the brain: its reply may come. With nothing to wake, none is
    /// coming, so `listening` ends now.
    @discardableResult
    public func heard(replyTo seq: Int?, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            if let seq { talk.replyFor = seq } else { endListening(ListenWhy.noReply, now, &fx) }
        }
    }

    /// The mic went off and heard nothing: no reply is coming.
    @discardableResult
    public func heardNothing(at now: Int64) -> [CoreEffect] {
        talkStep { fx in endListening(ListenWhy.heardNothing, now, &fx) }
    }

    /// The mic or speech recognition couldn't start: `listening` ends at
    /// once, and `why` stays for the popover until the next try.
    @discardableResult
    public func micFailed(_ why: String, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            talk.trouble = why
            endListening(ListenWhy.micFailed, now, &fx, facts: ["trouble": .string(why)])
        }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() { talk.trouble = nil }

    /// A pass is over, about the event `seq` (nil for a forced one), and
    /// whether it started a reaction. A reaction ends `listening`: it's
    /// the reply, and the device ends it as it plays. The first pass on
    /// what you said or on anything newer that didn't react means none is
    /// coming, so `listening` ends now.
    @discardableResult
    public func passed(about seq: Int?, reacted: Bool, at now: Int64) -> [CoreEffect] {
        talkStep { fx in
            let answered = talk.replyFor.map { r in seq.map { $0 >= r } ?? false } ?? false
            if answered { talk.replyFor = nil }
            if reacted {
                endListening(ListenWhy.replied, now, &fx, stop: false)
            } else if answered {
                endListening(ListenWhy.noReply, now, &fx)
            }
        }
    }

    /// Whether the device shows `listening` at `now`: the mic is on, or it
    /// went off and the reply hasn't come yet.
    public func showsListening(at now: Int64) -> Bool {
        talk.mic != nil || talk.replyUntil.map { now < $0 } == true
    }

    /// One push-to-talk input: the timers first, then `body`'s rules,
    /// then what the device shows.
    private func talkInput(_ now: Int64, _ body: (inout [CoreEffect]) -> Void) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        startDayIfNew(now, &fx)
        body(&fx)
        publish(now, &fx)
        return fx
    }

    /// The rest of push-to-talk's steps change nothing the device's
    /// `state` shows: only their records and reactions.
    private func talkStep(_ body: (inout [CoreEffect]) -> Void) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        body(&fx)
        return fx
    }

    @discardableResult
    public func setVolume(_ volume: Int, at now: Int64) -> [CoreEffect] {
        config.volume = max(0, min(10, volume))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// Boop reached a growth stage at `now`: the rest of the day is a
    /// party. The input's `state` carries it.
    public func reachedStage(_ name: String, at now: Int64) {
        config.stageReached = (name, day(now))
    }

    /// The mood output saved a new mood (`mood` reads it): a `state`
    /// carries it at once.
    @discardableResult
    public func moodChanged(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The wall clock's time at the steady time `now`: days and times of
    /// day follow it, and timers don't.
    public func setWallClock(_ wallMs: Int64, at now: Int64) {
        wallOffsetMs = wallMs - now
    }

    /// Timers: the Codex grace period, the safety net, the mic's 30 s
    /// limit and the reply's 8 s wait.
    @discardableResult
    public func tick(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        if let mic = talk.mic, now - mic.since >= Self.listenLimitMs {
            // The device's own button hits the same limit.
            stopListening(ListenWhy.limit, now, &fx)
        } else if talk.mic == nil, let until = talk.replyUntil, now >= until {
            // The device stopped holding `listening` for the reply on its own.
            endListening(ListenWhy.timedOut, now, &fx, stop: false)
        }
        publish(now, &fx)
        return fx
    }

    // MARK: - Reading

    public func snapshot(at now: Int64) -> StateSnapshot {
        let (waiting, working, idle) = tracker.grouped(at: now)
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
        let helpers = working.reduce(0) { $0 + $1.helpers.count }
        return StateSnapshot(base: base, act: act, mood: mood(), attn: attn, busy: working.count, idle: idle.count,
                             helpers: helpers, vol: config.volume,
                             when: when(at: now))
    }

    func when(at now: Int64) -> [String] {
        let wall = wall(now), slot = wall / 900_000, stage = config.stageReached?.day
        if let c = whenCache, c.slot == slot, c.hatched == config.hatched, c.stage == stage { return c.tags }
        let tags = Occasions.tags(at: wall, hatched: config.hatched, party: stage == config.time.day(wall), time: config.time)
        whenCache = (slot, config.hatched, stage, tags)
        return tags
    }

    /// starting's `ctx` for a session whose context was compacted.
    static let compacted = "compacted"

    /// What a session's start is, from its `source`, as starting's `ctx`:
    /// `session` for a fresh one (started or cleared, or no source),
    /// `continuation` for one resumed, where the work goes on, and
    /// `compacted` for one whose context was compacted.
    static func startCtx(source: String?) -> String {
        switch source {
        case Mapping.compacted: compacted
        case "resume": "continuation"
        default: "session"
        }
    }

    /// A variation of `mood`'s design for `state` at random, from 1, among
    /// those for `outcome` and `ctx` (FaceLoops.variants), never `last`
    /// when there's another: the rules pick it for now,
    /// and the harness may later.
    public static func pickVariant(mood: String, state: String, outcome: String? = nil, ctx: String? = nil,
                                   avoiding last: Int?, in pack: CharacterPack = .active, _ rng: inout SplitMix64) -> Int {
        let fit = FaceLoops.variants(mood: mood, state: state, outcome: outcome, ctx: ctx, in: pack)
        let choices = fit.filter { $0 != last }
        guard !choices.isEmpty else { return fit.first ?? 1 }
        return choices[rng.int(in: 0...(choices.count - 1))]
    }

    /// Every session, for the popover's list, in the tracker's order:
    /// those that need you (oldest first), then working, then idle. The
    /// device doesn't get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (waiting, working, idle) = tracker.grouped(at: now)
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
        needsYouBlock ?? (talk.mic != nil ? "the mic is on" : nil)
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

    /// The date at steady time `now`, on the wall clock: the calendar never
    /// sees steady time.
    private func day(_ now: Int64) -> String { config.time.day(wall(now)) }

    /// Whether "needs you" shows: then no event's pass starts.
    public var needsYouShowing: Bool { tracker.needsYou }

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
        let name = config.pack.name
        if let waiting = tracker.grouped(at: now).waiting.first { return open(waiting.thread, Core.openedThread(by: name)) }
        if let finish { return open(finish, Core.openedFinished(by: name)) }
        fx.append(.record(Event.did(Core.wiggled(by: name), for: seq, action: Core.wiggle, by: "rule", at: now)))
    }

    /// Presses within this long of the last walk down the line: each opens
    /// the one after the one opened last. After it, a press starts again
    /// at the top.
    public static let walkMs: Int64 = 8_000

    /// Who a BOOT press hands you, in order: those that need you, oldest
    /// first; then the idle ones, the one that finished last first (the
    /// oldest idle session is usually one you've left).
    func line(at now: Int64) -> [Session] {
        let (waiting, _, idle) = tracker.grouped(at: now)
        return waiting + idle.sorted { ($0.lastEventAt, $0.order) > ($1.lastEventAt, $1.order) }
    }

    /// A BOOT press: opens the next session in the line on the Mac,
    /// recorded as the `open_thread` action, by the button. With nobody in
    /// line (the board saw one the Mac no longer has), it's a poke.
    func pressed(_ now: Int64, seq: Int?, _ fx: inout [CoreEffect]) {
        guard !showsListening(at: now) else { return }
        let line = line(at: now)
        guard !line.isEmpty else { return poked(now, seq: seq, finish: nil, &fx) }
        var next = 0
        if let last = lastHanded, now - last.at < Self.walkMs, let i = line.firstIndex(where: { $0.key == last.key }) {
            next = (i + 1) % line.count
        }
        let s = line[next]
        lastHanded = (s.key, now)
        let thread = TranscriptView.Thread(s).name
        let more = line.count - 1
        let message = "\(config.pack.name) handed you \(s.agent.rawValue) on \(EventLine.thread(name: thread, project: s.project))"
            + (more > 0 ? "; \(more) more in line." : ".")
        fx.append(.record(Event.did(message, for: seq, action: Core.openThread, by: "button",
                                    facts: ["agent": .string(s.agent.rawValue), "thread": .string(thread), "more": .int(Int64(more)),
                                            "waiting": .bool(s.needsSince != nil)], at: now)))
        fx.append(.open(s.thread))
    }

    /// Turns the mic on, if it's off, recorded as `listen_start`. After the
    /// app's button the device is told to show `listening` at once (its own
    /// button already does), which drops the reactions waiting there,
    /// since one would end it.
    func startListening(by talker: Talker, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard talk.mic == nil else { return }
        talk = Talk(mic: Talk.Mic(by: talker, since: now), by: talker)
        recordListen(.start, now, &fx)
        if talker == .app { fx.append(.reaction(DeviceReaction(anim: BoopDevice.listening))) }
        fx.append(.listen(true, by: talker))
    }

    /// Turns the mic off, if it's on, recorded as `listen_wait`: the device
    /// holds `listening` for the reply until the core ends it
    /// (`endListening`), or `replyWaitMs` at most.
    func stopListening(_ why: String, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard let mic = talk.mic else { return }
        talk.mic = nil
        talk.replyUntil = now + Self.replyWaitMs
        recordListen(.wait, now, &fx, data: ["why": .string(why)])
        fx.append(.listen(false, by: mic.by))
    }

    /// Ends `listening`: with `stop`, the device is told so with
    /// `stop_listening`, which ends nothing else and does nothing where
    /// `listening` already ended. Recorded as `listen_end` only when it
    /// hadn't ended yet: as timed out once the reply's wait is over.
    func endListening(_ why: String, _ now: Int64, _ fx: inout [CoreEffect], stop: Bool = true,
                      facts: [String: JSONValue] = [:]) {
        if talk.mic != nil || talk.replyUntil != nil {
            let late = talk.mic == nil && talk.replyUntil.map { now >= $0 } == true
            var data = facts
            data["why"] = .string(late ? ListenWhy.timedOut : why)
            recordListen(.end, now, &fx, data: data)
        }
        talk.mic = nil
        talk.replyUntil = nil
        if stop { fx.append(.reaction(DeviceReaction(anim: BoopDevice.stopListening))) }
    }

    /// A `listen_start`, `listen_wait` or `listen_end` record: the core's,
    /// by rule, for whose button (`device` or `app`). Log-only: no line.
    func recordListen(_ phase: Event.Phase, _ now: Int64, _ fx: inout [CoreEffect], data: [String: JSONValue] = [:]) {
        var data = data
        data["by"] = "rule"
        fx.append(.record(Event(at: now, source: .boop, type: .listen, phase: phase, specificType: talk.by.rawValue,
                                data: data)))
    }

    /// The rule actions' names and messages.
    public static let wiggle = "wiggle"
    public static let openThread = "open_thread"
    public static func wiggled(by name: String = CharacterPack.active.name) -> String { "\(name) wiggled on its own." }
    public static func openedThread(by name: String = CharacterPack.active.name) -> String {
        "\(name) opened the thread that needs you on the Mac."
    }
    public static func openedFinished(by name: String = CharacterPack.active.name) -> String {
        "\(name) opened the thread that finished on the Mac."
    }
    public static let needsYou = "needs_you"

    /// Runs the session table's timers due by `now`: a
    /// Codex request past its grace shows, the safety net, and forgetting.
    /// Each request the safety net expires is kept for its `needs_you` end.
    /// `sparing`'s Codex request isn't shown: its event comes first.
    func advance(to now: Int64, sparing: String? = nil) {
        for (key, change) in tracker.advance(to: now, sparing: sparing) where change == .requestExpired {
            expired.insert(key)
        }
    }

    /// "Needs you" starting or clearing for a session, as a rule action:
    /// the view says who needs you from its start. A session gone while it
    /// waited clears too.
    func recordNeeds(_ now: Int64, _ fx: inout [CoreEffect]) {
        let showing = sessions.filter { $0.value.needsSince != nil }
        for (key, s) in showing.sorted(by: { ($0.value.needsSince!, $0.value.request) < ($1.value.needsSince!, $1.value.request) })
        where shownNeeds[key] == nil {
            shownNeeds[key] = (s.agent, s.id)
            expired.remove(key)
            fx.append(.record(Event(at: now, source: .boop, type: .needsYou, phase: .start, specificType: Core.needsYou,
                                    session: s.id,
                                    data: ["for": s.requestRef.map { .int(Int64($0)) } ?? .null, "by": "rule",
                                           "agent": .string(s.agent.rawValue), "ok": true,
                                           "message": .string("\(config.pack.name) showed that \(s.agent.rawValue) needs you.")])))
        }
        for (key, was) in shownNeeds.sorted(by: { $0.key < $1.key }) where showing[key] == nil {
            shownNeeds[key] = nil
            let why = expired.remove(key) != nil ? Core.expiredWhy : sessions[key] == nil ? "the session ended" : nil
            var data: [String: JSONValue] = ["by": "rule", "agent": .string(was.agent.rawValue),
                                             "outcome": why == nil ? "done" : "failed"]
            if let why { data["why"] = .string(why) }
            fx.append(.record(Event(at: now, source: .boop, type: .needsYou, phase: .end, specificType: Core.needsYou,
                                    session: was.id, data: data)))
        }
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        recordNeeds(now, &fx)
        updateActs(now)
        let snapshot = snapshot(at: now)
        let sessions = sessionList(at: now)
        defer { lastSessions = sessions }
        if snapshot != lastPublished {
            lastPublished = snapshot
            // The picture changes before any reaction plays on top of it.
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
