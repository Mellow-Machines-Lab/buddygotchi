import AgentHooks
import Foundation
import MellowHarness

/// The core: plain rules with no queue. It reads the
/// session table agent-hooks keeps (`SessionTracker`) and
/// decides which visual the device shows, what the
/// agents are doing included (`act`), and which reactions the rules play.
/// What it does by rule it records as `action`
/// events: "needs you" showing and ending, and a poke's answer
/// (`pokeAnswer`: the device plays its poke), or while
/// something needs you, the thread it opens (`open_thread`), and each
/// reaction it plays (a met wish, a level), as a `did` named after it. A session that's gone with no `SessionEnd`
/// it records as its end (`sessionGone`), and a Claude app thread whose
/// agent's process ended while it waited or worked as its turn stopping
/// (`agentGone`). It also
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
        /// The buddy's colour, 0 to 7 (`BuddyColor`), sent in `state`.
        public var color = 0
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
        /// Whether the core runs the work stream (`WorkStream`): always, in
        /// the app; a test of something else turns it off.
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
    /// The face Boop's mood rests in now (`MoodOutput.face`), which every
    /// `state` carries and the rules' reactions are drawn in: the runtime
    /// reads it from the transcript, where the mood output keeps it. The
    /// resting mood's until it's set.
    var mood: () -> String
    /// Boop's growth now, which the runtime reads from the growth store:
    /// CONTEXT's level, and care's XP for the invite's payoff. Nil for a demo
    /// and a core with no store.
    var growth: () -> Growth? = { nil }
    /// The days in a row with a full ring today (`GrowthStore.daysInARow`).
    var daysInARow: () -> Int = { 0 }

    /// Every agent session, what it's doing and who needs you.
    let tracker: SessionTracker
    var sessions: [String: Session] { tracker.sessions }
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
    /// You at the Mac now (`Along`: your hands, and the rest Boop notices)
    /// and the side of Boop the Mac is on (`Anchor.side`), which the
    /// runtime sets (`Runtime.handsTick`, Settings): facts for the board's
    /// tags and its `ptr`, never events.
    public var along = Along.Now()
    public var hands: Hands? { along.hands }
    public var macSide: Anchor.Side?
    /// The cards the agents handed Boop, and the one it holds (`Cards`).
    var cards = Cards()
    var lastSessions: [SessionSummary] = []
    var lastSessionsAt: Int64?
    /// Level-ups and the ring closing, waiting for nothing to need you.
    var growthHeld: [GrowthBeat] = []
    /// The session a BOOT press opened last, and when.
    var lastHanded: (key: String, at: Int64)?
    /// When the board last said its agents' drawer is open (`ev drawer`),
    /// until it says it shut: the snapshot lists the sessions while it is,
    /// from the row it asked for last.
    var drawerHeardAt: Int64?
    var drawerFrom = 0
    /// Each session's number on the drawer, by session key: what a tap on
    /// its row sends back. They count up from where this launch's requests
    /// start (`Config.firstAsk`), so a row a board still shows from the
    /// last launch can't open some other session.
    var rows: [String: Int] = [:]
    var lastRow: Int?
    /// The activity the working look shows (`updateActs`), and each
    /// working session's, held.
    var shownAct: Timed?
    /// What last woke Boop, and when, for the popover.
    var woke: (why: Narration, at: Int64)?
    var held: [String: Timed] = [:]
    /// The calendar's tags, worked out once a quarter of an hour: every
    /// time zone's hours start on one, so the part of the day and the date
    /// can't change within it.
    var whenCache: (slot: Int64, hatched: String?, tags: [String])?
    /// The agents' working stretch, which the working tiers count from:
    /// when its first turn started, and once they all rest, when they came
    /// to rest (`keepStretch`).
    var stretch: (start: Int64, rested: Int64?)?
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
        /// Why the session ended with no `SessionEnd`, as a timer said:
        /// recorded by the next publish as its end, then let go.
        var gone: SessionTracker.Gone?
        /// The request you dismissed on the board or in the popover, by its
        /// number, and when. It stops showing, though its agent still
        /// waits: its session rests from then (`resting`), and stays in
        /// BOOT's line after the requests that show (`groups`). The
        /// session's next request has another number, and shows again. A
        /// launch reads it back from its `needs_you` end (`replay`).
        var dismissed: (request: Int, at: Int64)?

        var isEmpty: Bool { !shown && why == nil && gone == nil && dismissed == nil }
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
    /// The hook name of the end of a session that's gone with no
    /// `SessionEnd` (`SessionTracker.Gone`).
    public static let sessionGone = "SessionGone"
    /// Set while a launch reads the transcript back: the sessions in it end
    /// as it says, never as today's processes or apps do.
    let readingBack: Flag
    final class Flag { var on = false }
    /// The board's gesture for dismissing: a finger held on the needs-you
    /// screen, with the number of the request it showed (`attn.id`).
    public static let dismissGesture = "dismiss"
    /// A poke's `src` when BOOT made it, the board's own name for BOOT.
    public static let buttonSource = "button"

    /// Push-to-talk, as the core keeps it (`Talk`).
    public internal(set) var pushToTalk = Listening()

    /// Until when Boop is quiet for a while (`quietUntil(at:)`), or nil.
    var quietUntil: Int64?
    /// The wish open (`Wish`), and the Boop day the last was made.
    public internal(set) var wish: Wish?
    var wishDay: String?
    /// What the board holds up as each wish is met: the pack's words.
    public var wishMetSigns: [WishKind: String] = [:]
    /// Whether push-to-talk works: the recognizer and the mic both authorized.
    public var pushToTalkWorks: () -> Bool = { true }
    /// Whether you're away from the Mac, for the wish's wait.
    var awayFromMac = false
    /// Whether Boop went to sleep at your lock at night (`nap`), until you
    /// show up. A launch forgets it, as nothing else hangs on it.
    var napping = false
    /// You at the Mac, for Doing with no session open (`sleepsAlone`):
    /// whether the screen is locked (the `lock` events), and when you last
    /// touched the Mac or the board, which the runtime keeps from the Mac's
    /// idle time. Nil while nothing has said so (the evals, a headless run
    /// with no `presence` line): then, with no session, Boop sleeps, as it
    /// always did.
    public internal(set) var screenLocked = false
    public var lastInputAt: Int64?
    /// When you first showed up on the latest Boop day you did (`energy`).
    var firstShownUp: (day: String, at: Int64)?
    /// The agent you swiped to, and when (`watched`); the agents whose turn
    /// ended while you weren't watching, since when; the pill saying so.
    var watchSwiped: String?
    var watchSwipedAt: Int64?
    var unseen: [String: Int64] = [:]
    var pill: (key: String, text: String, at: Int64)?
    /// The latest show an agent drew (`show`).
    var lastShow: Shown?
    /// The shows for the board (`BoardShow`), and the last one's id.
    var boardShows: [BoardShow] = []
    var nextBoardShow = 0
    /// Whether the board is busy with a Moment of the Mac's: a `do` sent and
    /// not yet ended, as the runtime keeps count (`Runtime.openDos`). A show
    /// spends none of its time under one (`tidyBoardShows`).
    public var boardBusy = false
    /// What each session's turn has done, for its held pictures.
    var turnWork: [String: TurnWork] = [:]

    /// `place` names a working directory's project. `isRunning` says
    /// whether an agent's process still runs (evals and demos, whose agents
    /// are made up, say yes), and `archive` whether a thread was archived in
    /// its app (evals say none was).
    public init(config: Config,
                place: @escaping (String) -> Place = { Place.at(cwd: $0) },
                isRunning: @escaping (AgentProcess) -> Bool = AgentProcess.isRunning,
                archive: @escaping (ThreadRef) -> ThreadArchive.State = { ThreadArchive.state($0) }) {
        self.config = config
        mood = { config.pack.restingFace(config.pack.defaultMood) }
        let readingBack = Flag()
        self.readingBack = readingBack
        tracker = SessionTracker(firstRequest: config.firstAsk, place: place,
                                 isRunning: { readingBack.on || isRunning($0) },
                                 archive: { readingBack.on ? .open : archive($0) })
    }

    // MARK: - Inputs

    /// An agent's event, as recorded (its `seq` set): anything else is
    /// ignored. Its time is now. `actEnded` says the act it ends was ended
    /// and recorded already (`actEnd(by:at:)`).
    @discardableResult
    public func handle(_ event: Event, actEnded: Bool = false) -> [CoreEffect] {
        guard let agentEvent = AgentEvent(event) else { return [] }
        let now = event.at
        var fx: [CoreEffect] = []
        // A turn with no call but looks is a chat turn's, for the pill's words.
        let chat = !stream.called.contains(agentEvent.key)
        fold(agentEvent, ref: event.seq)
        notePictures(agentEvent, at: now)
        if agentEvent.kind == .turn, agentEvent.phase == .end, agentEvent.notice == nil, agentEvent.hook != Core.agentGone {
            turnEndedElsewhere(agentEvent.key, chat: chat, at: now)
            boardShowsTurnEnded(agentEvent.key, at: now)
        }
        let actEnded = actEnded || streamAct(agentEvent, for: event.seq, now, &fx)
        let forward = actEnded ? nil : streamCall(agentEvent, program: agentEvent.program, at: now)
        publish(now, &fx)
        if let forward { call(forward, session: agentEvent.key, for: event.seq, now, &fx) }
        return fx
    }

    /// A call beginning or ending a work act, recorded so Jev hears of it.
    /// Whether it ended one, as then its word comes forward no further.
    func streamAct(_ e: AgentEvent, for seq: Int?, _ now: Int64, _ fx: inout [CoreEffect]) -> Bool {
        guard config.workStream, e.kind == .tool, e.tool != nil else { return false }
        let changed: WorkStream.Act?
        switch e.phase {
        case .start: changed = stream.startAct(e, program: e.program, at: now)
        case .end: changed = stream.endAct(e, at: now)
        default: return false
        }
        guard let act = changed else { return false }
        fx.append(.record(actRecord(act, e, at: now)))
        return e.phase == .end
    }

    /// The work act a call's end ends, ended now and recorded, or nil: for
    /// the pipeline to log before the call's own event (`Pipeline.agent`).
    /// The act's record is held from the brain (`TranscriptView.held`), and
    /// the harness passes an event at wake 0 over for anything newer with a
    /// line, held or not: logged after the call, the act's end would
    /// silence the call's own line, a check's 3rd failure or a fix among
    /// them.
    public func actEnd(by event: Event, at now: Int64) -> Event? {
        guard config.workStream, let e = AgentEvent(event), e.kind == .tool, e.phase == .end, e.tool != nil,
              let act = stream.endAct(e, at: now) else { return nil }
        return actRecord(act, e, at: now)
    }

    /// The record of `act` beginning or ending at `e`, so Jev hears of it.
    func actRecord(_ act: WorkStream.Act, _ e: AgentEvent, at now: Int64) -> Event {
        var data: [String: JSONValue] = ["session": .string(act.session), "words": .string(act.words)]
        if let passed = act.passed { data["passed"] = .bool(passed) }
        if let topic = e.topic { data["topic"] = .string(topic) }
        return Event(at: now, source: .boop, type: .act, phase: e.phase == .start ? .start : .end, specificType: act.kind, data: data)
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
            colour(e.key)
            return stream.started(e, program: program, at: now)
        case (.tool, .end) where e.tool != nil:
            return stream.ended(e, program: program, at: now)
        case (.subagent, .end):
            return stream.helperBack(e.key, at: now)
        case (.turn, .end) where e.notice == nil && e.hook != Core.agentGone:
            // Not Claude's idle notice, nor an agent that's gone: nobody did anything.
            return stream.turnEnded(e, at: now)
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
                            facts: ["as": .string(f.style), "word": .string(f.word), "session": .string(key)], at: now)
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
    /// session still waits on it, resting from when you dismissed it.
    public func replay(_ event: Event) {
        readingBack.on = true
        defer { readingBack.on = false }
        replayWishWait(event)
        if let agentEvent = AgentEvent(event) {
            fold(agentEvent, ref: event.seq)
            return
        }
        advance(to: event.at)
        replayQuiet(event)
        if event.type == .wish { replayWish(event) }
        if event.type == .presence {
            awayFromMac = event.phase == .start
            if event.phase == .end { cards.youAreBack(at: event.at) }
        }
        if event.type == .lock { screenLocked = event.phase == .start }
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
    /// its time run first. A start, a stop and a helper coming back play
    /// no reaction: the work stream and the brain have them.
    /// `ref` is its `seq`, which a request it starts keeps.
    private func fold(_ event: AgentEvent, ref: Int) {
        let key = event.key
        // The timers due by the event's time first, to hear what they did.
        advance(to: event.at, sparing: key)
        guard let change = tracker.handle(event, ref: ref) else { return }
        switch change {
        case .turnStarted, .turnEnded, .sessionEnded:
            held[key] = nil
            // Last turn's cards go as you prompt; its result shows as it ends.
            switch change {
            case .turnStarted: cards.turnStarted(key)
            case .turnEnded: cards.turnEnded(key, away: awayFromMac, at: event.at)
            default: break
            }
        case .callEnded(let call, _):
            // The activity the call showed holds from now.
            if let call, held[key]?.act == Core.act(call) { held[key]?.at = event.at }
        case .sessionStarted, .callStarted, .asked, .subagentStarted, .subagentEnded, .requestExpired, .agentGone,
             .sessionGone, .other:
            break
        }
    }

    /// A rule's reaction, in Boop's mood with a
    /// variation at random, never the one it played last: not while
    /// something needs you or `listening` holds the screen. The device also skips
    /// it while a brain reaction plays (`if_free`), unless it holds up a
    /// sign (`BoopDevice.play`). Recorded as a `did` named after it, for
    /// the event `seq` that played it, as the poke's answer is, so the
    /// brain hears that Boop already reacted: in the words `said`, or
    /// `played`'s.
    func play(_ rule: Moment, for seq: Int?, _ now: Int64, _ fx: inout [CoreEffect], said: String? = nil) {
        guard rule.anim != nil || rule.mood != nil, !needsYouShowing, !showsListening(at: now) else { return }
        fx.append(.reaction(rule))
        var did = Event.did(said ?? "", for: seq, action: rule.name, by: "rule", at: now)
        if said == nil { did.data["message"] = nil }
        fx.append(.record(did))
    }

    /// Onboarding's greeting on the board, `reaction`: a rule's reaction
    /// for no event, played and recorded as the rules' others are.
    @discardableResult
    public func greet(_ reaction: Moment, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        play(reaction, for: nil, now, &fx)
        return fx
    }

    /// A tap on the device, recorded as the poke `seq`, on the brain's
    /// finish for `finish`'s thread, if the device said so. The device has
    /// already reacted.
    @discardableResult
    public func poke(at now: Int64, seq: Int? = nil, finish: ThreadRef? = nil, touch: Bool = true) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        touched(at: now)
        if touch { shownUp(at: now) }
        advance(to: now)
        poked(now, seq: seq, finish: finish, touch: touch, &fx)
        publish(now, &fx)
        return fx
    }

    /// BOOT pressed with someone in line (`line`), recorded as `seq`: it
    /// hands you the next agent (`pressed`).
    @discardableResult
    public func press(at now: Int64, seq: Int? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        pressed(now, seq: seq, &fx)
        publish(now, &fx)
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

    public func setColor(_ color: Int, at now: Int64) -> [CoreEffect] {
        config.color = max(0, min(BuddyColor.all.count - 1, color))
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

    /// A moment of growth: a level reached, or today's ring closing.
    public enum GrowthBeat: Equatable, Sendable {
        case level(Int)
        case ringClosed
    }

    /// Boop grew: each beat is logged and its rule moment plays once nothing
    /// needs you or listens, after the `state` that carries the new ring.
    @discardableResult
    public func grew(_ beats: [GrowthBeat], at now: Int64) -> [CoreEffect] {
        growthHeld += beats.filter { !growthHeld.contains($0) }
        var fx: [CoreEffect] = []
        publish(now, &fx)
        return fx
    }

    /// The growth waiting for nothing to need you (`growthHeld`): one
    /// event that says what happened, and one moment for it all.
    func recordGrowth(_ now: Int64, _ fx: inout [CoreEffect]) {
        guard !growthHeld.isEmpty, needsYouBlock == nil, !showsListening(at: now) else { return }
        // Boop starts things only when idle: the ring waits for the turns to end.
        if growthHeld == [.ringClosed], groups(at: now).working.count > 0 { return }
        let beats = growthHeld
        growthHeld = []
        // The last level, of one held past the next.
        let level = beats.compactMap { if case .level(let n) = $0 { n } else { nil } }.last
        let ring = beats.contains(.ringClosed)
        fx.append(.record(Self.growthEvent(level: level, ring: ring, at: now)))
        // The ring closing: its XP and the days in a row, held low in gold
        // behind a full ring. A level: its words held low in gold behind a
        // star, the rim glowing gold; with the ring, held up on the sign.
        let n = level
        var m = Moment(mood: n != nil ? Self.levelFace : Self.ringFace, loops: 2,
                       reason: n.map { Narration.fit(["level \($0)!"], name: config.pack.name) } ?? nil)
        if ring {
            m.gold = Self.ringSign(daysInARow: daysInARow())
            m.mark = "ring"
            m.sign = n.map(Self.levelSign)
        } else if let n {
            m.gold = Self.levelSign(n)
        }
        play(m, for: nil, now, &fx)
    }

    /// The `growth` event: the `level` reached, if one was, and whether
    /// today's `ring` closed.
    public static func growthEvent(level: Int?, ring: Bool, at now: Int64) -> Event {
        var data: [String: JSONValue] = [:]
        if let level { data["level"] = .int(Int64(level)) }
        if ring { data["ring"] = true }
        return Event(at: now, source: .boop, type: .growth, specificType: level != nil ? "level" : "ring", data: data)
    }

    /// The level-up's words, held low in gold: `level 12!`, lower case, as
    /// everything Boop holds is.
    public static func levelSign(_ level: Int) -> String { "level \(level)!" }
    /// What Boop holds low as today's ring closes: `100 XP today, day 12`,
    /// or with no days in a row to tell, `100 XP today`.
    public static func ringSign(daysInARow: Int) -> String {
        "\(Growth.perDay) XP today" + (daysInARow > 1 ? ", day \(daysInARow)" : "")
    }
    /// The faces the growth moments play: a level, the ring.
    static let levelFace = "proud", ringFace = "happy"

    /// Today's occasions at `now` (`Days.special`).
    func specialDays(at now: Int64) -> [Days.SpecialDay] {
        Days.special(at: wall(now), hatched: config.hatched, name: config.pack.name, time: config.time)
    }

    /// Today's special day's sign (`Happy Halloween!`, `Day 50!`), or nil
    /// on a plain day: the day's first hello holds it up
    /// (`TranscriptView.hello`), so what Boop wears all day has a reason
    /// you saw.
    public func daySign(at now: Int64) -> String? { Days.greeting(specialDays(at: now)) }

    /// How many days Boop is old at `now`, for the narration, or nil on the
    /// day it hatched, or with no hatching known.
    public func dayCount(at now: Int64) -> Int? {
        guard let hatched = config.hatched else { return nil }
        let days = config.time.days(from: hatched, to: wall(now))
        return days > 0 ? days : nil
    }

    /// Something the state reads changed outside the core (the mood output
    /// saved a new mood, or the XP changed with nothing to celebrate): a `state` carries it at once.
    @discardableResult
    public func stateChanged(at now: Int64) -> [CoreEffect] {
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
        tickWish(now, &fx)
        if let mic = pushToTalk.mic, now - mic.since >= Self.listenLimitMs {
            // The device's own button hits the same limit.
            stopListening(ListenWhy.limit, now, &fx)
        } else if pushToTalk.mic == nil, let until = pushToTalk.replyUntil, now >= until {
            // The device stopped holding `listening` for the reply on its own.
            endListening(ListenWhy.timedOut, now, &fx, stop: false)
        }
        publish(now, &fx)
        return fx
    }

    // MARK: - Reading

    /// What a waiting session's request asks of you.
    static func kind(of s: Session) -> StateSnapshot.Attention.Kind {
        .of(asking: s.asking?.rawValue, tools: Array(s.askers.values))
    }

    public func snapshot(at now: Int64) -> StateSnapshot {
        let (shown, dismissed, working, idle) = groups(at: now)
        // Idle's tier counts from the latest a session came to rest, once
        // nothing works.
        let rests = resting(idle: idle, dismissed: dismissed)
        let dozed = working.isEmpty && dozedOff(at: now, rests: rests, waiting: !shown.isEmpty || !dismissed.isEmpty)
        // With no session open, awake while you're at the Mac (`sleepsAlone`).
        let asleep = sessions.isEmpty ? sleepsAlone(at: now) : dozed
        let base = !working.isEmpty ? "working" : asleep ? "asleep" : "idle"
        let attn = shown.first.map {
            StateSnapshot.Attention(
                agent: $0.agent.rawValue, project: StateSnapshot.clip($0.project, marked: true, max: StateSnapshot.maxSignBytes),
                name: StateSnapshot.boardName($0.name).map { StateSnapshot.clip($0, marked: true, max: StateSnapshot.maxSignBytes) } ?? "",
                more: shown.count - 1, id: $0.request, kind: Self.kind(of: $0))
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
        // The work stream's lanes, while the agents work and nothing
        // needs you.
        // They wait while the drawer's open, which covers them.
        let drawer = drawerOpen(at: now)
        let calls = config.workStream && base == "working" && attn == nil && !drawer
            ? stream.calls(Set(working.map(\.key)), at: now) : []
        // An act in `state` while nothing else holds the screen: back when
        // that's over, where it got to.
        let workAct = config.workStream && attn == nil && !showsListening(at: now) ? stream.act.map {
            StateSnapshot.WorkAct(kind: $0.kind, words: $0.words, result: $0.passed.map { $0 ? "p" : "f" })
        } : nil
        var snapshot = StateSnapshot(doing: base, activity: act, mood: mood(), attn: attn, working: working.count,
                                     idle: rests.count, helpers: helpers, vol: config.volume, color: config.color,
                                     when: when(at: now, workingSince: stretchStart(working, at: now),
                                                idleSince: working.isEmpty ? rests.max() : nil), todo: todo, calls: calls)
        snapshot.workAct = workAct
        watchFields(into: &snapshot, at: now)
        let energy = self.energy(at: now, workingSince: stretchStart(working, at: now))
        snapshot.energy = energy == .normal ? nil : energy.rawValue
        snapshot.pointer = along.pointer
        if config.pack.name != config.pack.ownName { snapshot.buddy = config.pack.name }
        if wishCounts(dozed: dozed, attn: attn), let kind = wish?.kind {
            snapshot.wish = kind.rawValue
        }
        if attn == nil, !drawer, let up = boardShow {
            // A show outranks a card and a live picture: the board holds it
            // up for its 30 s, its agent's screen.
            snapshot.show = StateSnapshot.ShowField(id: up.id, headline: up.show.headline, slot: slot(of: up.key), agent: up.agent)
        } else if attn == nil, !drawer {
            // A result is for you, and shows; a status is no card of words
            // any more: the agent the screen follows holds a live picture of
            // its work instead, while it works (`picture`).
            if let card = cardShow(at: now), card.result {
                snapshot.card = card
            } else if base == "working", let key = watched(at: now), working.contains(where: { $0.key == key }),
                      let picture = picture(for: key, at: now) {
                snapshot.pic = StateSnapshot.PictureShow(slot: slot(of: key),
                                                         agent: sessions[key]?.agent.rawValue ?? "", picture: picture)
            }
        }
        // A line too long for the board loses the card's small line, then the card.
        if !snapshot.fits {
            snapshot.card?.small = nil
            if !snapshot.fits { snapshot.card = nil }
            if !snapshot.fits { snapshot.pic = nil }
            if !snapshot.fits { snapshot.show = nil }
        }
        // Last: its rows are what gets cut to fit the board's line.
        if drawer { list(into: &snapshot, at: now) }
        return snapshot
    }

    /// How long every session rests, nothing waiting on you, before Boop
    /// falls asleep with them still open (a terminal left open overnight):
    /// at night after 10 minutes, by day after an hour.
    public static let dozeOffNightMs: Int64 = 10 * 60_000
    public static let dozeOffMs: Int64 = 60 * 60_000

    /// Boop sleeps at once, as Jev chose at your lock at night, with agents
    /// open or not, and the dream follows as for any sleep. An agent's work
    /// or a request still shows; once they're over it sleeps on.
    @discardableResult
    public func nap(at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        napping = true
        publish(now, &fx)
        return fx
    }

    /// You showed up (an unlock, your coming back, a touch or your words):
    /// the nap is over.
    @discardableResult
    public func endNap(at now: Int64) -> [CoreEffect] {
        guard napping else { return [] }
        var fx: [CoreEffect] = []
        advance(to: now)
        napping = false
        publish(now, &fx)
        return fx
    }

    /// How long a quiet sends Boop to sleep at `now`.
    func dozeMs(at now: Int64) -> Int64 { calendar(at: now).contains("night") ? Self.dozeOffNightMs : Self.dozeOffMs }

    /// Why Boop is doing what it's doing at `now`, for the popover, where the
    /// board has no room or no call to say: asleep, just woken, or at a work act.
    public func doingReason(at now: Int64) -> Narration? {
        let name = config.pack.name
        if let w = woke, now - w.at < Self.wokeShownMs { return w.why }
        let s = snapshot(at: now)
        if s.doing == "asleep" {
            return sleepingWhy(at: now)
        }
        if let act = stream.act, act.passed == nil, let session = sessions[act.session] {
            return Narration.act(act.kind, agent: session.agent.rawValue, on: Self.on(session), name: name)
        }
        return nil
    }
    private func sleepingWhy(at now: Int64) -> Narration {
        let alone = sessions.isEmpty
        return Narration.sleeping(noAgents: alone && lastInputAt == nil, napping: napping,
                                  away: alone && (awayFromMac || screenLocked), dozeMs: dozeMs(at: now), name: config.pack.name)
    }

    /// Whether Boop sleeps at `now` with no session open: awake while
    /// you're at the Mac; asleep once you're away, the screen is locked,
    /// it went for its nap, or you've been still its doze time (`dozeMs`,
    /// from your last input), or while nothing has said you're here at all.
    public func sleepsAlone(at now: Int64) -> Bool {
        guard let last = lastInputAt else { return true }
        return awayFromMac || screenLocked || napping || now - last >= dozeMs(at: now)
    }

    /// You touched the board: you're here, for Doing (`lastInputAt`).
    func touched(at now: Int64) {
        if let last = lastInputAt, now > last { lastInputAt = now }
    }

    /// The Mac's screen locked or unlocked: with no session open, Boop
    /// sleeps while it's locked.
    @discardableResult
    public func lock(_ locked: Bool, at now: Int64) -> [CoreEffect] {
        guard locked != screenLocked else { return [] }
        var fx: [CoreEffect] = []
        advance(to: now)
        screenLocked = locked
        if !locked {
            touched(at: now)
            shownUp(at: now)
        }
        publish(now, &fx)
        return fx
    }
    /// How long the popover says what woke Boop.
    static let wokeShownMs: Int64 = 60_000

    /// " on api", where a session works, as the narration says it.
    static func on(_ s: Session) -> String {
        var thread: [String: JSONValue] = ["project": .string(s.project)]
        if let w = s.workspace { thread["workspace"] = .string(w) }
        return Narration.place(thread).map { " on \($0)" } ?? ""
    }

    /// The caption for Doing going from `before` to `after` at `now`, with no
    /// card or Moment to say so: falling asleep and waking. A nap's is the
    /// Moment's that took it.
    func doingFact(from before: String, to after: String, at now: Int64) -> String? {
        let name = config.pack.name
        if after == "asleep" {
            return sleepingWhy(at: now).fact
        }
        guard before == "asleep", after == "working", let s = groups(at: now).working.first else { return nil }
        let why = Narration.woken(by: s.agent.rawValue, on: Self.on(s), name: name)
        woke = (why, now)
        return why.fact
    }

    /// Whether Boop has dozed off at `now` though sessions are open: it
    /// went for a nap, or they all rest, the latest since `rests.max()`;
    /// and nothing waits on you.
    func dozedOff(at now: Int64, rests: [Int64], waiting: Bool) -> Bool {
        guard !waiting else { return false }
        if napping { return true }
        guard let since = rests.max() else { return false }
        return now - since >= dozeMs(at: now)
    }

    /// The sessions as a `status` reply reads them at `now`, with each
    /// one's latest result from `results` and what you last asked it for
    /// from `asked`, by session: whether it waits on you, since when it
    /// works and its to-do list. A request you dismissed still waits on
    /// you; one that shows holds every reaction back, the screen answering
    /// for it.
    public func status(at now: Int64, results: [String: StatusReply.Result],
                       asked: [String: PromptReading.Kind] = [:]) -> [StatusReply.Agent] {
        let (shown, dismissed, working, idle) = groups(at: now)
        let needs = Set((shown + dismissed).map(\.key)), works = Set(working.map(\.key))
        return (shown + working + dismissed + idle).map { s in
            StatusReply.Agent(agent: s.agent.rawValue, places: [s.project, s.workspace, s.name].compactMap { $0 },
                         needsYou: needs.contains(s.key), workingSince: works.contains(s.key) ? s.turn.startedAt ?? now : nil,
                         restingSince: works.contains(s.key) || needs.contains(s.key) ? nil : s.turn.lastEndedAt ?? s.lastEventAt,
                         todo: works.contains(s.key) ? s.todos.map { StateSnapshot.Todo(done: $0.done, total: $0.total) } : nil,
                         result: results[s.key], asked: asked[s.key])
        }
    }

    /// When the agents' working stretch at `now` began, the one the
    /// working tiers count from; nil while nothing works.
    public func stretchSince(at now: Int64) -> Int64? { stretchStart(groups(at: now).working, at: now) }

    /// The moment's tags for a reply's sign at `now`: `waiting` while
    /// something waits on you, `working` while an agent works.
    public func moment(at now: Int64) -> [String] {
        let (shown, dismissed, working, _) = groups(at: now)
        return (shown.isEmpty && dismissed.isEmpty ? [] : ["waiting"]) + (working.isEmpty ? [] : ["working"])
    }

    /// Whether the board's agents' drawer is open: it said so within
    /// `drawerQuietMs` (it says so again every 10 s), and hasn't said it
    /// shut.
    func drawerOpen(at now: Int64) -> Bool { drawerHeardAt.map { now - $0 < Self.drawerQuietMs } ?? false }
    public static let drawerQuietMs: Int64 = 25_000

    /// The drawer's rows, in what needs you first: the requests that show
    /// (oldest first), then the sessions working, then those resting (a
    /// request you dismissed, or idle), the latest to come to rest first;
    /// from the row the board asked for (`drawerFrom`), or as near it as
    /// still fills `maxRows`; `maxRows` of them, their names cut shorter
    /// (`rowCuts`) till they fit the board's line, and only then fewer.
    func list(into snapshot: inout StateSnapshot, at now: Int64) {
        let (shown, dismissed, working, idle) = groups(at: now)
        let rested = (dismissed + idle).sorted {
            (notes[$0.key]?.dismissed?.at ?? $0.turn.lastEndedAt ?? $0.lastEventAt, $0.order)
                > (notes[$1.key]?.dismissed?.at ?? $1.turn.lastEndedAt ?? $1.lastEventAt, $1.order)
        }
        let all = shown.map { ($0, "n") } + working.map { ($0, "w") } + rested.map { ($0, "i") }
        let skip = max(0, min(drawerFrom, all.count - StateSnapshot.maxRows))
        let window = all.dropFirst(skip).prefix(StateSnapshot.maxRows)
        snapshot.skip = skip
        for (i, cut) in Self.rowCuts.enumerated() {
            let last = i == Self.rowCuts.count - 1
            snapshot.list = []
            snapshot.unlisted = all.count - skip
            for (s, status) in window {
                let name = StateSnapshot.boardName(s.name)
                let named = name != nil
                // The row's second line: its card's words while it has one,
                // else the project under a thread's name.
                let under = cards.shown(s.key, at: now)?.text ?? (named ? s.project : nil)
                let row = StateSnapshot.Row(
                    id: rows[s.key] ?? 0, status: status,
                    slot: config.workStream ? slot(of: s.key) : -1, agent: s.agent.rawValue,
                    title: StateSnapshot.clip(name ?? s.project, marked: true, max: cut.title),
                    project: under.map { cut.project > 0 ? StateSnapshot.clip($0, marked: true, max: cut.project) : "" } ?? "")
                var next = snapshot
                next.list?.append(row)
                next.unlisted -= 1
                guard next.fits else { break }
                snapshot = next
            }
            if last || snapshot.list?.count == window.count { break }
        }
    }

    /// The longest title and project a drawer's row carries, in bytes,
    /// each tried in turn till its rows all fit the line: as the board's
    /// fields hold them first, the project left out last.
    static let rowCuts: [(title: Int, project: Int)] = [
        (StateSnapshot.maxTitleBytes, StateSnapshot.maxProjectBytes), (22, 14), (16, 8), (12, 0),
    ]

    /// When the working stretch that `working`, the sessions working at
    /// `now`, are in began: the earliest start among their turns, or the
    /// stretch's own start when they took up again within
    /// `Tags.stretchRestMs` of resting. None while nothing works.
    func stretchStart(_ working: [Session], at now: Int64) -> Int64? {
        guard !working.isEmpty else { return nil }
        let begun = working.compactMap(\.turn.startedAt).min() ?? now
        guard let s = stretch else { return begun }
        if let rested = s.rested, begun - rested >= Tags.stretchRestMs { return begun }
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
    /// session came to rest (`idleSince`), then your hands and the Mac's
    /// side, and the rest of you at the Mac, in `Tags.all`'s order.
    func when(at now: Int64, workingSince: Int64?, idleSince: Int64?) -> [String] {
        var on = calendar(at: now)
        if let since = workingSince ?? idleSince, let tier = Tags.tier(after: now - since) { on.append(tier) }
        if let macSide { on.append(macSide.tag) }
        on += along.tags
        return Tags.all.filter(on.contains)
    }

    /// The calendar's tags, worked out once a quarter of an hour.
    func calendar(at now: Int64) -> [String] {
        let wall = wall(now), slot = wall / 900_000
        if let c = whenCache, c.slot == slot, c.hatched == config.hatched { return c.tags }
        let tags = Days.tags(at: wall, hatched: config.hatched, time: config.time)
        whenCache = (slot, config.hatched, tags)
        return tags
    }

    /// Every session, for the popover's list, in `groups`' order: those
    /// whose request shows, then those whose request you dismissed, both
    /// waiting, then working, then idle. The first waiting is the one the
    /// sign names. The device doesn't get these.
    public func sessionList(at now: Int64) -> [SessionSummary] {
        let (shown, dismissed, working, idle) = groups(at: now)
        func summary(_ s: Session, _ status: SessionSummary.Status) -> SessionSummary {
            var summary = SessionSummary(s, status)
            // Since when it's been doing what it does: waiting since its
            // request, working since its turn started, resting since its
            // last turn ended (else since it was last heard from).
            let since = status == .waiting ? s.needsSince
                : status == .working ? s.turn.startedAt : s.turn.lastEndedAt ?? s.lastEventAt
            summary.since = since.map { Date(timeIntervalSince1970: Double(wall($0)) / 1000) }
            if config.workStream { summary.slot = slot(of: s.key) }
            if status == .working, config.workStream, let lane = stream.lanes[s.key] {
                summary.word = lane.shown(at: now)
            }
            if let card = cards.shown(s.key, at: now) { summary.card = [card.text, card.small].compactMap { $0 }.joined(separator: ", ") }
            return summary
        }
        return shown.map { summary($0, .waiting) }
            + dismissed.map { var row = summary($0, .waiting); row.dismissed = true; return row }
            + working.map { summary($0, .working) }
            + idle.map { summary($0, .idle) }
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
        needsYouBlock ?? replyBlock
    }

    /// Why a reply to what you said can't play now, or nil: only the mic
    /// still on. It shows over needs you, as listening does, its face and
    /// sign but not its voice (the board's rule).
    public var replyBlock: String? {
        pushToTalk.mic != nil ? "the mic is on" : nil
    }

    // MARK: - Rules

    /// The wall clock at steady time `now`.
    func wall(_ now: Int64) -> Int64 { now + wallOffsetMs }

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

    /// The board's agents' drawer opened, or shut (`ev drawer`): while it's
    /// open the snapshot lists the sessions (`list`), from the row the
    /// board asked for, `from`, as it scrolls.
    @discardableResult
    public func drawer(open: Bool, from: Int = 0, at now: Int64) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        drawerHeardAt = open ? now : nil
        drawerFrom = open ? max(0, from) : 0
        publish(now, &fx)
        return fx
    }

    /// A row picked in the board's drawer, by its number (`pick`), recorded
    /// as `seq`: its session's thread opens on the Mac, as BOOT's hand-off
    /// does, recorded as the `open_thread` action by the drawer. A number
    /// no session has any more opens nothing.
    @discardableResult
    public func pick(row id: Int, at now: Int64, seq: Int? = nil) -> [CoreEffect] {
        var fx: [CoreEffect] = []
        advance(to: now)
        if let key = rows.first(where: { $0.value == id })?.key, let s = sessions[key] {
            let thread = TranscriptView.Thread(s).name
            let message = "\(config.pack.name) handed you \(s.agent.rawValue) on "
                + "\(EventLine.thread(name: thread, project: s.project)) from its list."
            fx.append(.record(Event.did(message, for: seq, action: Core.openThread, by: Core.drawerPick,
                                        facts: ["agent": .string(s.agent.rawValue), "thread": .string(thread),
                                                "waiting": .bool(s.needsSince != nil)], at: now)))
            fx.append(.open(s.thread))
        }
        publish(now, &fx)
        return fx
    }

    /// What picks a row in the drawer: the `press` event's specific type,
    /// and who opened the thread.
    public static let drawerPick = "drawer"

    /// A number for every session that has none yet, in the order they came
    /// (the drawer's rows), and none kept for a session that's gone.
    func numberRows() {
        rows = rows.filter { sessions[$0.key] != nil }
        for s in sessions.values.sorted(by: { $0.order < $1.order }) where rows[s.key] == nil {
            let next = SessionTracker.nextRequest(after: lastRow ?? config.firstAsk)
            rows[s.key] = next
            lastRow = next
        }
    }

    /// A poke: the device plays its poke (`poked`, `tap_spam` from the third
    /// in a row), and the brain hears of it through the view, which counts
    /// the pokes in a row. The rules add no animation of
    /// their own, but record it, as the poke's answer (`pokeAnswer`), whose
    /// words Jev reads. While `listening` shows
    /// nothing replaces it: the device plays no poke, so nothing is
    /// recorded. While something needs you the device plays no poke either:
    /// the tap opens the thread the sign names on the Mac, recorded as the
    /// `open_thread` action. Nor on the brain's finish
    /// that names whose turn it was: the tap opens that thread.
    func poked(_ now: Int64, seq: Int?, finish: ThreadRef?, touch: Bool, _ fx: inout [CoreEffect]) {
        guard !showsListening(at: now) else { return }
        func open(_ thread: ThreadRef, _ message: String) {
            fx.append(.record(Event.did(message, for: seq, action: Core.openThread, by: "rule",
                                        facts: ["agent": .string(thread.agent)], at: now)))
            fx.append(.open(thread))
        }
        let name = config.pack.name
        if let waiting = groups(at: now).shown.first { return open(waiting.thread, Core.openedThread(by: name)) }
        if let finish { return open(finish, Core.openedFinished(by: name)) }
        fx.append(.record(Event.did(Core.wiggled(by: name), for: seq, action: Core.pokeAnswer, by: "rule", at: now)))
        // A poke that's only a poke, by a finger on the face, is a touch: it meets a pet wish.
        if touch, wish?.kind == .pet { metWish(now, &fx) }
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

    /// The rule actions' names and messages. The device's answer to a poke
    /// keeps its older name on disk, and HISTORY's words for it: said as
    /// an answer to the poke, Jev took the poke as answered and reacted to
    /// none (2026-11-01).
    public static let pokeAnswer = "wiggle"
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
    /// Codex request past its grace shows, the safety net, a session that's
    /// gone ends, a Claude app thread whose agent's process is gone stops
    /// waiting and working, and forgetting. Why each stopped is noted for
    /// the next publish to record: a request's `needs_you` end, an agent
    /// gone's stopped turn, and a gone session's end, except one the
    /// read-back's own rules end, which the transcript says already.
    /// `sparing`'s Codex request isn't shown: its event comes first.
    func advance(to now: Int64, sparing: String? = nil) {
        let before = sessions
        let changes = tracker.advance(to: now, sparing: sparing)
        for (key, s) in before {
            let why: Why
            switch changes[key] {
            case .requestExpired?: why = .expired
            case .sessionGone(let gone)?:
                why = gone == .process ? .agentGone : .ended
                held[key] = nil
                if !readingBack.on { notes[key, default: Note(agent: s.agent, id: s.id)].gone = gone }
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

    /// A session that's gone with no `SessionEnd`, recorded by rule as its
    /// end, with why; and a Claude app thread whose agent's process ended
    /// while it waited or worked, as its turn stopping, the thread staying,
    /// idle. So the view, and a later launch reading the transcript back,
    /// end or stop it from the transcript, not from the processes running
    /// or the threads archived then.
    func recordGone(_ now: Int64, _ fx: inout [CoreEffect]) {
        for (_, n) in notes.sorted(by: { $0.key < $1.key }) {
            guard let gone = n.gone else { continue }
            var e = Event(AgentEvent(agent: n.agent, kind: .session, phase: .end, hook: Core.sessionGone, session: n.id, at: now))
            e.data["by"] = "rule"
            e.data["why"] = .string(gone.rawValue)
            fx.append(.record(e))
        }
        for (_, n) in notes.filter({ $0.value.why == .agentGone && $0.value.gone == nil }).sorted(by: { $0.key < $1.key }) {
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
            n.gone = nil
            if n.dismissed != nil, sessions[SessionFold.key(n.agent, n.id)].map(isDismissed) != true { n.dismissed = nil }
            return n.isEmpty ? nil : n
        }
    }

    /// What each turn did, and each session's failures in a row, only for
    /// the sessions still here.
    func tidyGone() {
        if turnWork.keys.contains(where: { sessions[$0] == nil }) { turnWork = turnWork.filter { sessions[$0.key] != nil } }
        if stream.failures.keys.contains(where: { sessions[$0] == nil }) {
            stream.failures = stream.failures.filter { sessions[$0.key] != nil }
        }
    }

    func publish(_ now: Int64, _ fx: inout [CoreEffect]) {
        recordGone(now, &fx)
        recordNeeds(now, &fx)
        recordGrowth(now, &fx)
        tidyNotes()
        tidyGone()
        updateActs(now)
        tidyCards(now)
        tidyBoardShows(at: now)
        let (shown, dismissed, active, _) = groups(at: now)
        let working = Set(active.map(\.key))
        stream.keep(working)
        // A session waiting on you is still at its call: its act comes back.
        stream.keepAct(alive: working.union((shown + dismissed).map(\.key)), at: now)
        keepStretch(at: now)
        numberRows()
        let snapshot = snapshot(at: now)
        let sessions = sessionList(at: now)
        // Only a lane's new word changed: it waits for the next `state`
        // once `sendEveryMs` has passed, or for the next tick. The
        // popover's list waits the same way, so a burst of calls builds one
        // status, not one each.
        var wordsOnly = false, listWordsOnly = false
        if var before = lastPublished, let at = lastPublishedAt, now - at < WorkStream.sendEveryMs {
            before.calls = snapshot.calls
            before.pips = snapshot.pips  // a pip's colour comes with its lane
            wordsOnly = before == snapshot
        }
        if let at = lastSessionsAt, now - at < WorkStream.sendEveryMs {
            func wordless(_ list: [SessionSummary]) -> [SessionSummary] { list.map { var s = $0; s.word = nil; return s } }
            listWordsOnly = wordless(sessions) == wordless(lastSessions)
        }
        if snapshot != lastPublished, !wordsOnly { (lastSessions, lastSessionsAt) = (sessions, now) }
        if snapshot != lastPublished, !wordsOnly {
            // A Doing that changed with no reason on anything playing: a
            // caption alone, which no line records, so the brain hears nothing new.
            if let before = lastPublished?.doing, before != snapshot.doing, !needsYouShowing, !showsListening(at: now),
               !fx.contains(where: { if case .reaction(let m) = $0 { m.reason != nil } else { false } }),
               let fact = doingFact(from: before, to: snapshot.doing, at: now) {
                fx.append(.reaction(Moment(reason: fact)))
            }
            lastPublished = snapshot
            lastPublishedAt = now
            // The picture changes before any reaction plays on top of it.
            fx.insert(.state(snapshot), at: 0)
        } else if sessions != lastSessions, !listWordsOnly {
            (lastSessions, lastSessionsAt) = (sessions, now)
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
    /// Since when it's waited, worked or rested; nil when that's unknown.
    public var since: Date?
    /// While it works: its latest call's word in the work stream, and its
    /// lane's slot there, whose colour it wears on the board.
    public var word: String?
    public var slot: Int?
    /// The card it handed Boop, as one line: what it's on, or what it made.
    public var card: String?
    /// Its to-do list, as counts.
    public var todo: StateSnapshot.Todo?
    /// Waiting, with its request dismissed: it no longer shows on Boop.
    public var dismissed = false
    /// While it waits on you, what it asks.
    public var asks: StateSnapshot.Attention.Kind?

    public init(agent: String, project: String, name: String? = nil, workspace: String? = nil, status: Status,
                thread: ThreadRef? = nil, since: Date? = nil, word: String? = nil, slot: Int? = nil,
                todo: StateSnapshot.Todo? = nil) {
        self.agent = agent
        self.project = project
        self.name = name
        self.workspace = workspace
        self.status = status
        self.thread = thread
        self.since = since
        self.word = word
        self.slot = slot
        self.todo = todo
    }

    init(_ s: Core.Session, _ status: Status) {
        self.init(agent: s.agent.rawValue, project: s.project, name: s.name, workspace: s.workspace, status: status,
                  thread: s.thread, todo: s.todos.map { StateSnapshot.Todo(done: $0.done, total: $0.total) })
        if status == .waiting { asks = Core.kind(of: s) }
    }
}
