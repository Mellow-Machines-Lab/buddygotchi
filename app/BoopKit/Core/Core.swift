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
/// as a `did` named after it. A session whose agent's process ended while
/// it waited or worked it records as its turn stopping (`agentGone`). It also
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
        /// Whether the board shows the work stream (`WorkStream`): the
        /// setting's, on unless you turn it off.
        public var workStream = true

        public init(volume: Int = 6, time: LocalTime = LocalTime(), pack: CharacterPack = .active,
                    hatched: String? = nil) {
            self.volume = volume
            self.time = time
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
    /// The growth stage Boop is at, from 1, which every `state` carries as
    /// its tags (`Occasions.stages`): the runtime reads it from the growth
    /// store. A Hatchling's until it's set.
    var stage: () -> Int = { 1 }

    /// Every agent session, what it's doing and who needs you.
    let tracker: SessionTracker
    var sessions: [String: Session] { tracker.sessions }
    /// The last day with any activity, or the day the app opened: the first
    /// activity of a later one is a new day.
    var lastActiveDay: String?
    var lastPublished: StateSnapshot?
    /// Onboarding's practice request (act 5's amber lesson): the needs-you
    /// screen, as an agent's request shows it, with no agent behind it,
    /// until onboarding takes it down. A real request shows in its place.
    var practice: StateSnapshot.Attention?
    /// The practice request's number: past any a launch gives a real one.
    public static let practiceRequest = 2_000_000_000
    /// When the last `state` went out: a lane's new word waits for
    /// `WorkStream.sendEveryMs` after it.
    var lastPublishedAt: Int64?
    /// The work stream: each call's word, and which come forward.
    var stream = WorkStream()
    /// The session list as last published, which can change while the
    /// snapshot doesn't: a second idle session, say.
    var lastSessions: [SessionSummary] = []
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
    /// The agents' working stretch, which the working tiers count from:
    /// when its first turn started, and once they all rest, when they came
    /// to rest (`keepStretch`).
    var stretch: (start: Int64, rested: Int64?)?
    /// When the rules last played the error reaction: at most one every
    /// `errorEveryMs`.
    var lastErrorAt: Int64?
    /// The turn the latest prompt's reading came for, by its session's key
    /// and the turn's number, when that reading puts `reading` on
    /// (`Occasions.reads`): it's on while that turn lasts.
    var readingTurn: (key: String, number: Int)?
    /// The wall clock less the steady one, for days and times of day.
    var wallOffsetMs: Int64 = 0
    /// What the core keeps of each session beyond the tracker's table, for
    /// what it records, by session key: only while there's something in it.
    var notes: [String: Note] = [:]
    struct Note {
        let agent: Agent
        let id: String
        /// Its request's `needs_you` start is recorded, and no end yet: it
        /// showed when last published.
        var shown = false
        /// Why its request stops showing, or its turn stopped, as a timer
        /// said: recorded by the next publish, then let go.
        var why: Why?
        /// The request you dismissed on the board or in the popover, by its
        /// number, and when. It stops showing, though its agent still
        /// waits: its session rests from then (`resting`), and stays in
        /// BOOT's line after the requests that show (`groups`). The
        /// session's next request has another number, and shows again. A
        /// launch reads it back from its `needs_you` end (`replay`).
        var dismissed: (request: Int, at: Int64)?

        var isEmpty: Bool { !shown && why == nil && dismissed == nil }
    }

    /// Why a request stopped showing, as its `needs_you` end says; for an
    /// agent gone, its stopped turn says it too.
    enum Why: String {
        /// The safety net, for an agent with no process to check.
        case expired = "nothing for 10 minutes"
        case agentGone = "its agent's process ended"
        /// Its session was silent a day (`SessionFold.forgetMs`).
        case forgotten = "nothing for a day"
        case ended = "the session ended"
        case dismissed = "you dismissed it"
    }
    /// The hook name of an agent gone's stopped turn.
    public static let agentGone = "AgentGone"
    /// Set while a launch reads the transcript back: the sessions in it end
    /// as it says, never as today's processes do.
    let readingBack: Flag
    final class Flag { var on = false }
    /// The board's gesture for dismissing: a finger held on the needs-you
    /// screen, with the number of the request it showed (`attn.id`).
    public static let dismissGesture = "dismiss"

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
    /// `place` names a working directory's project. `isRunning` says
    /// whether an agent's process still runs (evals and demos, whose agents
    /// are made up, say yes).
    public init(config: Config, lastActiveDay: String? = nil,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) },
                isRunning: @escaping (AgentProcess) -> Bool = AgentProcess.isRunning) {
        self.config = config
        mood = { config.pack.defaultMood }
        self.lastActiveDay = lastActiveDay
        let readingBack = Flag()
        self.readingBack = readingBack
        tracker = SessionTracker(firstRequest: config.firstAsk, place: place,
                                 isRunning: { readingBack.on || isRunning($0) })
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
        let forward = streamCall(agentEvent, program: agentEvent.program, at: now)
        publish(now, &fx)
        if let forward { call(forward, session: agentEvent.key, for: event.seq, now, &fx) }
        return fx
    }

    /// What the work stream makes of an agent's event: a call joins its
    /// session's lane, and one may come forward.
    func streamCall(_ e: AgentEvent, program: String?, at now: Int64) -> WorkStream.Forward? {
        guard config.workStream else { return nil }
        switch (e.kind, e.phase) {
        case (.turn, .start):
            stream.turnStarted(e.key)
            return nil
        case (.tool, .start) where e.tool != nil:
            return stream.started(e, program: program, at: now)
        case (.tool, .end) where e.tool != nil:
            return stream.ended(e, program: program, at: now)
        case (.subagent, .end):
            return stream.helperBack(e.key, at: now)
        case (.turn, .end) where e.notice == nil && e.hook != Core.agentGone:
            // Not Claude's idle notice, nor an agent that's gone: nobody did anything.
            return stream.turnEnded(e, at: now)
        case (.session, .start) where e.source == Mapping.compacted:
            return stream.compacted(e.key, at: now)
        default:
            return nil
        }
    }

    /// A word that comes forward, for the device, after the `state` of the
    /// same input: not while something needs you or `listening` holds the
    /// screen. Recorded as a `did` with no message, so the transcript keeps
    /// it and the brain's lines count only the moments that hit
    /// (`TranscriptView`).
    func call(_ f: WorkStream.Forward, session key: String, for seq: Int?, _ now: Int64, _ fx: inout [CoreEffect]) {
        guard !needsYouShowing, !showsListening(at: now) else { return }
        fx.append(.call(f.args))
        var did = Event.did("", for: seq, action: WorkStream.action, by: "rule",
                            facts: ["as": .string(f.gag), "word": .string(f.word), "session": .string(key)], at: now)
        did.data["message"] = nil
        fx.append(.record(did))
    }

    /// `event` without the name, app, app session, mode, process and
    /// terminal its session already has, which `apply` carries on, so the
    /// transcript doesn't repeat them on every line. A launch reads back
    /// only the last day, which can start after the event that last
    /// carried one: so a session this core doesn't hold, or forgets before
    /// the event, gets them all, and so do its first event of each day and
    /// every request (a needs-you), so a launch knows a waiting agent's
    /// process and where its thread opens. A fact a launch missed comes
    /// back with the session's next event, since the core then lacks it.
    func unrepeated(_ event: Event) -> Event {
        guard let e = AgentEvent(event), SessionFold.step(e) != .needsYou, let s = sessions[e.key],
              !SessionFold.forgotten(s.lastEventAt, at: e.at), config.time.day(s.lastEventAt) == config.time.day(e.at)
        else { return event }
        var event = event
        for (key, held) in [("name", s.name), ("app", s.app), ("app_session", s.appSession)]
        where held != nil && event[key]?.string == held {
            event.data[key] = nil
        }
        if let mode = e.mode, (mode == "plan") == s.planMode { event.data["mode"] = nil }
        if e.process != nil, e.process == s.process { event.data["process"] = nil }
        if e.terminal != nil, e.terminal == s.terminal { event.data["terminal"] = nil }
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
    /// cleared did. A request you dismissed stays dismissed while its
    /// session still waits on it, resting from when you dismissed it. The
    /// latest prompt's reading decides `reading` again (`promptRead`).
    public func replay(_ event: Event) {
        readingBack.on = true
        defer { readingBack.on = false }
        if let agentEvent = AgentEvent(event) {
            _ = fold(agentEvent, ref: event.seq)
            return
        }
        advance(to: event.at)
        if event.type == .prompt, let agent = event.agent, let session = event.session,
           let reading = PromptReading(facts: event.data) {
            noteReading(reading, key: SessionFold.key(agent, session))
        }
        if event.type == .needsYou, let session = event.session,
           let agent = event["agent"]?.string.flatMap(Agent.init(rawValue:)) {
            let key = SessionFold.key(agent, session)
            var note = Note(agent: agent, id: session)
            if event.phase == .start {
                note.shown = true
            } else if event["why"]?.string == Why.dismissed.rawValue, let s = sessions[key], s.needsSince != nil {
                // This launch numbers the request afresh.
                note.dismissed = (s.request, event.at)
            }
            notes[key] = note.isEmpty ? nil : note
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
            if !late, failed, event.error.map(Core.errorClasses.contains) == true,
               !(event.topic == Topic.inspect && event.error == ToolError.exitCode) {
                // A command that failed or timed out, not a request you
                // denied, nor a lookup that exited 1: it found nothing.
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
            // notice after a turn that finished doesn't, nor an agent gone,
            // which nobody stopped.
            held[key] = nil
            return outcome == .stopped && endedTurn && event.hook != Core.agentGone ? DeviceReaction(anim: Core.stopped) : nil
        case .subagentEnded(let returned):
            // A helper Boop saw start returns, while its turn goes on.
            return returned ? DeviceReaction(anim: Core.helperReturn) : nil
        case .sessionEnded:
            held[key] = nil
            return nil
        case .callStarted, .asked, .subagentStarted, .requestExpired, .agentGone, .other:
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
        fx.append(.reaction(rule))
        let played = Core.played(rule, by: config.pack.name)
        var did = Event.did(played ?? "", for: seq, action: anim, by: "rule",
                            facts: rule.ctx.map { ["ctx": .string($0)] } ?? [:], at: now)
        if played == nil { did.data["message"] = nil }
        fx.append(.record(did))
    }

    /// Onboarding's greeting on the board, `reaction`: a rule's reaction
    /// for no event, played and recorded as the rules' others are.
    @discardableResult
    public func greet(_ reaction: DeviceReaction, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        play(reaction, for: nil, now, &fx)
        return fx
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

    /// BOOT pressed with someone in line (`line`), recorded as `seq`: it
    /// hands you the next agent (`pressed`).
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
    /// Onboarding's practice request up, or down.
    public func setPractice(_ on: Bool, at now: Int64) -> [CoreEffect] {
        practice = on ? StateSnapshot.Attention(agent: "practice", project: "Tap me to answer", more: 0,
                                                id: Core.practiceRequest) : nil
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The work stream on or off, from the next `state`.
    public func setWorkStream(_ on: Bool, at now: Int64) -> [CoreEffect] {
        config.workStream = on
        if !on { stream = WorkStream() }
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    public func setVolume(_ volume: Int, at now: Int64) -> [CoreEffect] {
        config.volume = max(0, min(10, volume))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// Boop reached the growth stage `name` on `day` (today's at `now` by
    /// default): the rest of that day is a party, which a `state` carries
    /// at once.
    @discardableResult
    public func reachedStage(_ name: String, day: String? = nil, at now: Int64) -> [CoreEffect] {
        config.stageReached = (name, day ?? self.day(now))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// Your prompt's reading, for the turn the session `session` of
    /// `agent` works on now: the latest, so it decides whether `reading`
    /// is on (`Occasions.reads`), from now while that turn lasts.
    @discardableResult
    public func promptRead(_ reading: PromptReading, agent: Agent, session: String, at now: Int64) -> [CoreEffect] {
        noteReading(reading, key: SessionFold.key(agent, session))
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    func noteReading(_ reading: PromptReading, key: String) {
        readingTurn = Occasions.reads(reading) ? sessions[key].map { (key, $0.turn.number) } : nil
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
        let (shown, dismissed, working, idle) = groups(at: now)
        let base = !working.isEmpty ? "working" : sessions.isEmpty ? "asleep" : "idle"
        let attn = shown.first.map {
            StateSnapshot.Attention(
                agent: $0.agent.rawValue, project: StateSnapshot.clip($0.project, marked: true, max: StateSnapshot.maxSignBytes),
                name: $0.name.map { StateSnapshot.clip($0, marked: true, max: StateSnapshot.maxSignBytes) } ?? "",
                more: shown.count - 1, id: $0.request)
        } ?? practice
        // What the agents are doing shows only in the working look, and
        // not while something needs you.
        let act = base == "working" && attn == nil ? shownAct?.act.rawValue : nil
        let helpers = working.reduce(0) { $0 + $1.helpers.count }
        // The turn that has run longest first, then those whose start
        // isn't known (a helper working on after its turn): the board shows
        // the first list among them.
        let longest = working.sorted { ($0.turn.startedAt ?? .max, $0.order) < ($1.turn.startedAt ?? .max, $1.order) }
        let todos = attn == nil ? longest.lazy.compactMap(\.todos).first : nil
        let todo = todos.map { StateSnapshot.Todo(done: $0.done, total: $0.total) }
        // Idle's tier counts from the latest a session came to rest, once
        // nothing works.
        let rests = resting(idle: idle, dismissed: dismissed)
        // The work stream's lanes, while the agents work and nothing
        // needs you.
        let calls = config.workStream && base == "working" && attn == nil ? stream.calls(Set(working.map(\.key))) : []
        return StateSnapshot(base: base, act: act, mood: mood(), attn: attn, busy: working.count,
                             idle: rests.count, helpers: helpers, vol: config.volume,
                             when: when(at: now, workingSince: stretchStart(working, at: now),
                                        idleSince: working.isEmpty ? rests.max() : nil), todo: todo, calls: calls)
    }

    /// When the working stretch that `working`, the sessions working at
    /// `now`, are in began: the earliest start among their turns, or the
    /// stretch's own start when they took up again within
    /// `Occasions.stretchRestMs` of resting. None while nothing works.
    func stretchStart(_ working: [Session], at now: Int64) -> Int64? {
        guard !working.isEmpty else { return nil }
        let begun = working.compactMap(\.turn.startedAt).min() ?? now
        guard let s = stretch else { return begun }
        if let rested = s.rested, begun - rested >= Occasions.stretchRestMs { return begun }
        return min(s.start, begun)
    }

    /// Keeps the working stretch: on while the agents work, and once they
    /// all rest, when they came to rest, until their next stretch.
    func keepStretch(at now: Int64) {
        let (_, dismissed, working, idle) = groups(at: now)
        if let start = stretchStart(working, at: now) {
            stretch = (start, nil)
        } else if let s = stretch, s.rested == nil {
            stretch = (s.start, resting(idle: idle, dismissed: dismissed).max() ?? now)
        }
    }

    /// When each session that rests came to rest, as the board counts
    /// them (`idle`): an idle one when its last turn ended, else when it
    /// was last heard from, and one waiting on a request you dismissed when
    /// you dismissed it, since it waits on you as an idle session does.
    func resting(idle: [Session], dismissed: [Session]) -> [Int64] {
        idle.map { $0.turn.lastEndedAt ?? $0.lastEventAt } + dismissed.compactMap { notes[$0.key]?.dismissed?.at }
    }

    /// The tags on at `now`: the calendar's, then the tier reached, from the start
    /// of the working stretch (`workingSince`), else from when the latest
    /// session came to rest (`idleSince`), then the growth stage's, then
    /// `reading` while its turn lasts (`readingTurn`), in `Occasions.all`'s
    /// order.
    func when(at now: Int64, workingSince: Int64?, idleSince: Int64?) -> [String] {
        var on = calendar(at: now)
        if let since = workingSince ?? idleSince, let tier = Occasions.tier(after: now - since) { on.append(tier) }
        on += Occasions.stages(stage())
        if let r = readingTurn, let s = sessions[r.key], s.turn.startedAt != nil, s.turn.number == r.number {
            on.append(Occasions.reading)
        }
        return Occasions.all.filter(on.contains)
    }

    /// The calendar's tags, worked out once a quarter of an hour.
    func calendar(at now: Int64) -> [String] {
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

    /// Every session, for the popover's list, in `groups`' order: those
    /// whose request shows, then those whose request you dismissed, both
    /// waiting, then working, then idle. The first waiting is the one the
    /// sign names. The device doesn't get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (shown, dismissed, working, idle) = groups(at: now)
        return (shown + dismissed).map { SessionSummary($0, .waiting) } + working.map { SessionSummary($0, .working) }
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
    public var needsYouShowing: Bool { sessions.values.contains { $0.needsSince != nil && !isDismissed($0) } }

    /// Whether `s` waits on a request you dismissed.
    func isDismissed(_ s: Session) -> Bool { s.needsSince != nil && notes[s.key]?.dismissed?.request == s.request }

    /// The sessions as Boop shows them at `now`, each in the tracker's
    /// order: those whose request shows (oldest first), those waiting on a
    /// request you dismissed, then working, then idle.
    func groups(at now: Int64) -> (shown: [Session], dismissed: [Session], working: [Session], idle: [Session]) {
        let (waiting, working, idle) = tracker.grouped(at: now)
        return (waiting.filter { !isDismissed($0) }, waiting.filter(isDismissed), working, idle)
    }

    /// Dismisses the request numbered `request` (`attn.id`) if it shows:
    /// the one the board's needs-you screen or the popover's card showed,
    /// so one that took its place since isn't dismissed unseen. The
    /// popover names its session (`key`) too, as each buddy's core numbers
    /// its own requests. It stops showing on the board and in the menu
    /// bar, but the agent still waits, and nothing answers it. The session
    /// rests from now, and its next request shows again. Its `needs_you`
    /// ends, saying so.
    @discardableResult
    public func dismiss(request: Int, session key: String? = nil, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        if let s = groups(at: now).shown.first(where: { $0.request == request && (key == nil || $0.key == key) }) {
            notes[s.key, default: Note(agent: s.agent, id: s.id)].dismissed = (s.request, now)
        }
        publish(now, &fx)
        return fx
    }

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
        if let waiting = groups(at: now).shown.first { return open(waiting.thread, Core.openedThread(by: name)) }
        if let finish { return open(finish, Core.openedFinished(by: name)) }
        fx.append(.record(Event.did(Core.wiggled(by: name), for: seq, action: Core.wiggle, by: "rule", at: now)))
    }

    /// Presses within this long of the last walk down the line: each opens
    /// the one after the one opened last. After it, a press starts again
    /// at the top.
    public static let walkMs: Int64 = 8_000

    /// Who a BOOT press hands you, in order: those that need you, oldest
    /// first, the request that shows before one you dismissed; then the
    /// idle ones, the one that finished last first (the oldest idle session
    /// is usually one you've left).
    func line(at now: Int64) -> [Session] {
        let (shown, dismissed, _, idle) = groups(at: now)
        return shown + dismissed + idle.sorted { ($0.lastEventAt, $0.order) > ($1.lastEventAt, $1.order) }
    }

    /// A BOOT press: opens the next session in the line on the Mac,
    /// recorded as the `open_thread` action, by the button.
    func pressed(_ now: Int64, seq: Int?, _ fx: inout [CoreEffect]) {
        guard !showsListening(at: now) else { return }
        let line = line(at: now)
        guard !line.isEmpty else { return }
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
    /// Codex request past its grace shows, the safety net, a session whose
    /// agent's process is gone stops waiting and working, and forgetting.
    /// Why each stopped is noted for the next publish to record: a
    /// request's `needs_you` end, and an agent gone's stopped turn.
    /// `sparing`'s Codex request isn't shown: its event comes first.
    func advance(to now: Int64, sparing: String? = nil) {
        let before = sessions
        let changes = tracker.advance(to: now, sparing: sparing)
        for (key, s) in before {
            let why: Why
            switch changes[key] {
            case .requestExpired?: why = .expired
            case .agentGone?:
                why = .agentGone
                held[key] = nil
            default:
                guard sessions[key] == nil else { continue }
                why = .forgotten
            }
            notes[key, default: Note(agent: s.agent, id: s.id)].why = why
        }
    }

    /// A session whose agent's process ended while it waited or worked,
    /// recorded by rule as its turn stopping, so the view, and a later
    /// launch reading the transcript back, stop it from the transcript, not
    /// from the processes running then. The session stays, idle.
    func recordGone(_ now: Int64, _ fx: inout [CoreEffect]) {
        for (_, n) in notes.filter({ $0.value.why == .agentGone }).sorted(by: { $0.key < $1.key }) {
            var e = Event(AgentEvent(agent: n.agent, kind: .turn, phase: .end, hook: Core.agentGone, session: n.id, at: now,
                                     outcome: .stopped))
            e.data["by"] = "rule"
            e.data["why"] = .string(Why.agentGone.rawValue)
            fx.append(.record(e))
        }
    }

    /// "Needs you" starting or clearing for a session, as a rule action:
    /// the view says who needs you from its start. One that cleared for
    /// anything but an answer says why.
    func recordNeeds(_ now: Int64, _ fx: inout [CoreEffect]) {
        let showing = sessions.values.filter { $0.needsSince != nil && !isDismissed($0) }
            .sorted { ($0.needsSince!, $0.request) < ($1.needsSince!, $1.request) }
        for s in showing where notes[s.key]?.shown != true {
            notes[s.key, default: Note(agent: s.agent, id: s.id)].shown = true
            fx.append(.record(Event(at: now, source: .boop, type: .needsYou, phase: .start, specificType: Core.needsYou,
                                    session: s.id,
                                    data: ["for": s.requestRef.map { .int(Int64($0)) } ?? .null, "by": "rule",
                                           "agent": .string(s.agent.rawValue), "ok": true,
                                           "message": .string("\(config.pack.name) showed that \(s.agent.rawValue) needs you.")])))
        }
        let shows = Set(showing.map(\.key))
        for (key, n) in notes.filter({ $0.value.shown && !shows.contains($0.key) }).sorted(by: { $0.key < $1.key }) {
            notes[key]?.shown = false
            let why = whyCleared(key, n)
            var data: [String: JSONValue] = ["by": "rule", "agent": .string(n.agent.rawValue),
                                             "outcome": why == nil ? "done" : "failed"]
            if let why { data["why"] = .string(why.rawValue) }
            fx.append(.record(Event(at: now, source: .boop, type: .needsYou, phase: .end, specificType: Core.needsYou,
                                    session: n.id, data: data)))
        }
    }

    /// Why the session `key`'s request stopped showing: as a timer said,
    /// else its session ended or you dismissed it; nil when it was answered.
    func whyCleared(_ key: String, _ note: Note) -> Why? {
        if let why = note.why { return why }
        guard let s = sessions[key] else { return .ended }
        return isDismissed(s) ? .dismissed : nil
    }

    /// Lets go of what the notes no longer need: the timers' whys, once
    /// recorded, and a dismissal once its request no longer waits.
    func tidyNotes() {
        notes = notes.compactMapValues { n in
            var n = n
            n.why = nil
            if n.dismissed != nil, sessions[SessionFold.key(n.agent, n.id)].map(isDismissed) != true { n.dismissed = nil }
            return n.isEmpty ? nil : n
        }
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        recordGone(now, &fx)
        recordNeeds(now, &fx)
        tidyNotes()
        updateActs(now)
        stream.keep(Set(groups(at: now).working.map(\.key)))
        keepStretch(at: now)
        let snapshot = snapshot(at: now)
        let sessions = sessionList(at: now)
        defer { lastSessions = sessions }
        // Only a lane's new word changed: it waits for the next `state`
        // once `sendEveryMs` has passed, or for the next tick.
        var wordsOnly = false
        if var before = lastPublished, let at = lastPublishedAt, now - at < WorkStream.sendEveryMs {
            before.calls = snapshot.calls
            wordsOnly = before == snapshot
        }
        if snapshot != lastPublished, !wordsOnly {
            lastPublished = snapshot
            lastPublishedAt = now
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
