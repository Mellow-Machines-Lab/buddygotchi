import AgentHooks
import Foundation
import MellowHarness

/// The way every input goes: into MellowHarness's
/// `Harness`, which logs it and works out its line (the
/// view's transforms), then the core's rules on it, all before the brain
/// hears of it. An agent's event or a poke goes to the core, and what the
/// core did by rule is logged after it. The runtime runs one on `home`;
/// replays, evals and tests drive their own.
public final class Pipeline {
    /// The buddy, the process's character.
    public let buddy: Buddy
    /// Its core: the rules.
    public let core: Core
    public let view: TranscriptView
    /// MellowHarness's `Harness`, which keeps the log: Boop's brain.
    public let harness: Harness
    /// The log: Boop's transcript.
    public var transcript: Log { harness.log }
    /// Whether there's a brain to wake (Jev's key): without one, no view
    /// event wakes it. The harness asks only a brain
    /// it has.
    public var brain = true
    /// Every event as it's logged, and every view event as its input
    /// ends, for debug mode.
    public var onRecord: ((Event) -> Void)?
    /// What runs at the start of every input, before it logs anything,
    /// with its time: the memory closing a day that's over, so the event
    /// after it is read on the new one (`Memory`).
    public var beforeInput: [(Int64) -> Void] = []
    public var onView: ((ViewEvent) -> Void)?

    /// What one input did.
    public struct Step: Sendable {
        /// The core's effects, their records included.
        public var effects: [CoreEffect] = []
        /// Every event logged, stamped: the input's first.
        public var recorded: [Event] = []
        /// The view events made: the events with a line.
        public var views: [ViewEvent] = []

        /// The view events that wake the brain.
        public var waking: [ViewEvent] { views.filter(\.wakesBrain) }
    }

    /// The input under way, as it's made.
    var step: Step?
    /// The time of the latest input, the harness's clock unless one is given.
    let inputTime = InputTime()

    final class InputTime: @unchecked Sendable {
        var now: Int64 = 0
    }

    /// `buddy` on `core`, the process's character unless another is given.
    /// `clock` is the harness's; with none, its time is each input's.
    /// `loop` false leaves the brain to `harness.respond(to:)` (the evals).
    public init(core: Core, buddy: Buddy = Buddy(), view: TranscriptView, transcript: Log = Transcript.log(),
                time: LocalTime = LocalTime(), clock: Harness.Clock? = nil, queue: DispatchQueue = .main, loop: Bool = true,
                note: @escaping (String) -> Void = { _ in }) {
        self.buddy = buddy
        self.core = core
        self.view = view
        view.time = time
        view.name = buddy.name
        view.daySign = { core.daySign(at: $0) }
        var options = Harness.Options()
        // Boop's own words on how to read HISTORY and NOW are in its guide's
        // section.
        options.reading = .none
        // Only this moment's time: the weekday, the part of the day and the
        // calendar's occasions are CONTEXT's When row.
        options.heading = { wall in time.clock(wall) }
        let name = buddy.name
        options.loop = loop
        let input = inputTime
        harness = Harness(name: name, brain: nil, log: transcript,
                          clock: clock ?? Harness.Clock(now: { input.now }), queue: queue, options: options, note: note)
        view.register(on: harness) { core.needsYouBlock }
        harness.on("*") { [weak self] e in
            self?.step?.recorded.append(e)
            self?.onRecord?(e)
        }
        harness.onLine = { [weak self] e, line, _ in
            guard let self, let v = view.view(e, line, wakes: false, log: harness.log.view(now: e.at)) else { return }
            step?.views.append(v)
        }
    }

    /// Runs one input: `body` logs its events and runs the core's rules,
    /// and only then may the brain hear of them. Returns what it did, its
    /// view events gated as they stand once it's done.
    func input(at now: Int64, _ body: () -> Void) -> Step {
        inputTime.now = max(inputTime.now, now)
        let outer = step
        step = Step()
        harness.batch {
            for hook in beforeInput { hook(now) }
            body()
        }
        var made = step ?? Step()
        step = outer
        let log = transcript.view(now: now)
        for i in made.views.indices {
            let v = made.views[i]
            guard let e = transcript.event(v.seq) else { continue }
            made.views[i].wakesBrain = harness.wakes(e) && whyNotWake(e) == nil
            made.views[i].did = shown(dids: e.seq, log)
            onView?(made.views[i])
        }
        if var outer {
            outer.effects += made.effects
            outer.recorded += made.recorded
            outer.views += made.views
            step = outer
        }
        return made
    }

    /// An agent's event, from an adapter: its `ts` is now. It's logged
    /// without what its session already has (`Core.unrepeated`).
    /// One that still carries your prompt or the agent's last message (the
    /// tools', tests' and evals'; the app takes it out first,
    /// `Runtime.hook`) has its reading at once, labelled with `labels` if
    /// they're its text's.
    @discardableResult
    public func agent(_ event: Event, labels: PromptIntake.Labels? = nil) -> Step {
        let (event, text) = PromptIntake.split(event)
        return input(at: event.at) {
            let e = harness.emit(core.unrepeated(event))
            let fx = core.handle(e)
            run(fx)
            // A prompt you sent, or a request you answered, is working with
            // the agents: it meets the `work` wish.
            let answered = fx.contains { if case .record(let r) = $0 { r.type == .needsYou && r.phase == .end && r["outcome"]?.string == "done" } else { false } }
            if (e.type == .turn && e.phase == .start) || answered { run(core.meetWish(.work, at: event.at)) }
            if let text { emit(PromptIntake.heard(text, names: [buddy.name], labels: labels), about: event, at: event.at) }
        }
    }

    /// A reading, for the turn start or end `turn` that brought its text,
    /// as logged: logged, with the session and the buddy of that turn, and
    /// it wakes the brain in the turn event's place.
    /// Nil, logging nothing, once the session moved on (a slow labeler):
    /// your prompt's once its turn ended or another began, the agent's
    /// last message's once the next turn began. The turn event's own line
    /// stays, and the brain hears that in HISTORY instead.
    @discardableResult
    func read(_ heard: PromptIntake.Heard, about turn: Event, at now: Int64) -> Step? {
        let over = transcript.view(now: now).events(after: turn.seq).contains {
            $0.type == .turn && (heard.kind == .prompt || $0.phase == .start) && $0.agent == turn.agent && $0.session == turn.session
        }
        return over ? nil : input(at: now) { emit(heard, about: turn, at: now) }
    }

    func emit(_ heard: PromptIntake.Heard, about turn: Event, at now: Int64) {
        harness.emit(Event(at: now, source: turn.from ?? .mac, type: heard.kind, specificType: "reading", session: turn.session,
                           data: heard.facts))
    }

    /// The device's poke: the device has already played it. A tap that opens a finished turn's
    /// thread means "take me there", not a poke: the core records
    /// `open_thread` for it, which holds it back.
    @discardableResult
    public func poke(at now: Int64, finish: ThreadRef? = nil, touch: Bool = true) -> Step {
        input(at: now) {
            // Whether it slept as you poked it, once the Mac says you can be
            // here with no agent open (`Core.sleepsAlone`); else the view
            // goes by whether any session is open, as it always did.
            let data: [String: JSONValue] = core.lastInputAt == nil ? [:] : ["asleep": .bool(core.snapshot(at: now).doing == "asleep")]
            let e = harness.emit(Event(at: now, source: .device, type: .poke, specificType: "input", data: data))
            endNaps(at: now)
            run(core.poke(at: now, seq: e.seq, finish: finish, touch: touch))
        }
    }

    /// BOOT pressed: the core opens the next agent in line on the Mac
    /// (`Core.line`). With nobody in line it's a poke, on `finish` if the
    /// board pressed on one.
    @discardableResult
    public func press(at now: Int64, finish: ThreadRef? = nil) -> Step {
                guard !core.line(at: now).isEmpty else { return poke(at: now, finish: finish, touch: false) }
        return input(at: now) {
            let e = harness.emit(Event(at: now, source: .device, type: .press, specificType: "button"))
            core.touched(at: now)
            endNaps(at: now)
            run(core.press(at: now, seq: e.seq))
        }
    }

    /// An ask's end, as the board decided it: `pick` `a` or `b` (a target
    /// tapped), `touch` (a stroke answered it), or `ignored`, for the
    /// question `q` (its words, `question`), `answer` the words picked,
    /// and whether Boop `keeps` it. Logged; an answer may wake the brain,
    /// as what you said does.
    @discardableResult
    public func ask(_ q: String, question: String, pick: String, answer: String?, keeps: Bool, at now: Int64) -> Step {
        input(at: now) {
            harness.emit(Event(at: now, source: .device, type: .ask, specificType: pick,
                               data: ["q": .string(q), "question": .string(question), "answer": .of(answer), "keeps": .bool(keeps)]))
        }
    }

    /// The question the buddy asked last answered as its board would say
    /// it: `pick` "a", "b", "touch" (its first answer) or "ignored". For a
    /// demo or an eval, which have no board to tap; nothing when nothing
    /// was asked.
    @discardableResult
    public func answerLast(_ pick: String, at now: Int64) -> Step? {
        let asked = harness.log.view(now: now).events.last {
            $0.kind == Event.did && $0.action == MomentOutput.outputName && $0["ask"] != nil
        }
        guard let asked, let id = asked["ask"]?.string else { return nil }
        let answers = asked["answers"]?.array?.compactMap(\.string) ?? []
        let answer = pick == Asks.ignored ? nil : pick == "b" ? answers.last : answers.first
        return ask(id, question: asked["question"]?.string ?? "", pick: pick, answer: answer,
                   keeps: asked["keeps"]?.bool ?? false, at: now)
    }

    /// What you did to the board, as the board names it (`kind`: a stroke,
    /// a shake, face down…), which it reacted to at once: read as one of
    /// the seven touches (`Touch.read`) and logged as that, and it may wake
    /// the brain, as a poke does. One the board plays as a poke with a
    /// place (a boop on the nose, a tickle) is a poke. A touch's end (a
    /// put-down, turned back up) is logged with no line. The core hears
    /// only `dismiss`, a finger held on the needs-you screen: the request
    /// numbered `request`, the one it showed, stops showing if it still
    /// shows (`Core.dismiss`).
    @discardableResult
    public func gesture(_ kind: String, request: Int? = nil, at now: Int64) -> Step {
        if kind == Core.dismissGesture {
            return input(at: now) {
                harness.emit(Event(at: now, source: .device, type: .gesture, specificType: kind))
                endNaps(at: now)
                if let request { run(core.dismiss(request: request, at: now)) }
            }
        }
        guard let (touch, ended) = Touch.read(kind) else { return Step() }
        if touch == .poke { return poke(at: now) }
        return input(at: now) {
            harness.emit(Event(at: now, source: .device, type: .gesture, phase: ended ? .end : nil, specificType: touch.rawValue))
            core.touched(at: now)
            guard !ended else { return }
            endNaps(at: now)
            if touch.meetsPetWish { run(core.meetWish(.pet, at: now)) }
        }
    }

    /// The board's agents' drawer opened or shut (`ev drawer`): logged
    /// only, and while it's open the board's state lists the sessions, from
    /// the row it asked for, `from`.
    @discardableResult
    public func drawer(open: Bool, from: Int = 0, at now: Int64) -> Step {
        input(at: now) { run(core.drawer(open: open, from: from, at: now)) }
    }

    /// A row picked in the board's drawer (`pick`, the session's number
    /// there): the core opens that session's thread on the Mac, as BOOT's
    /// hand-off does, the board having handed it over.
    @discardableResult
    public func pick(row id: Int, at now: Int64) -> Step {
        input(at: now) {
            let e = harness.emit(Event(at: now, source: .device, type: .press, specificType: Core.drawerPick))
            run(core.pick(row: id, at: now, seq: e.seq))
        }
    }

    /// A card an agent handed Boop through the tool server (`Core.card`).
    @discardableResult
    public func card(_ card: Card, process: AgentProcess?, at now: Int64) -> Step {
        input(at: now) { run(core.card(card, process: process, at: now)) }
    }

    /// Your swipe on the card Boop holds: the next (`by` 1) or the one before.
    @discardableResult
    public func swipeCard(by: Int, at now: Int64) -> Step {
        input(at: now) { run(core.swipeCard(by: by, at: now)) }
    }

    /// Your swipe across the desk: the next agent (`by` 1) or the one
    /// before, which the screen follows (`Core.swipeAgent`).
    @discardableResult
    public func swipeAgent(by: Int, at now: Int64) -> Step {
        input(at: now) { run(core.swipeAgent(by: by, at: now)) }
    }

    /// Your tap on the card Boop holds: the core opens its link or its
    /// thread on the Mac.
    @discardableResult
    public func tapCard(at now: Int64) -> Step {
        input(at: now) {
            let e = harness.emit(Event(at: now, source: .device, type: .press, specificType: Core.cardTap))
            run(core.tapCard(at: now, seq: e.seq))
        }
    }

    /// The popover's Dismiss on the request numbered `request`, the one
    /// its card showed, if it's still the session `key`'s
    /// (`Core.dismiss`).
    @discardableResult
    public func dismiss(_ key: String, request: Int, at now: Int64) -> Step {
        input(at: now) { run(core.dismiss(request: request, session: key, at: now)) }
    }

    /// What you said to Boop on push-to-talk, heard by the Mac's mic
    /// after `by`'s button (`device` or `app`), cut to 2,000 characters as
    /// a prompt is on the wire, and with any secret scrubbed before the
    /// transcript keeps it. It wakes the brain
    /// even while something needs you.
    @discardableResult
    public func said(_ words: String, by: Core.Talker, at now: Int64) -> Step {
        let cut = Scrubber.scrub(words.count > HookLine.maxMessage ? String(words.prefix(HookLine.maxMessage)) : words)
        return input(at: now) {
            // Talking to it ends a quiet for a while.
            core.endQuiet()
            harness.emit(Event(at: now, source: .mic, type: .said, specificType: by.rawValue, data: ["words": .string(cut)]))
            endNaps(at: now)
            run(core.meetWish(.chat, at: now))
        }
    }

    /// You stepping away from the Mac or coming back, as the presence
    /// detector decided: logged, and the core hears it for the wish's wait.
    /// Only a back wakes the brain.
    @discardableResult
    public func presence(_ event: Event) -> Step {
        input(at: event.at) {
            harness.emit(event)
            run(core.presence(away: event.phase == .start, since: event["since"]?.int, at: event.at))
            if event.phase == .end { endNaps(at: event.at) }
        }
    }

    /// The Mac's screen locked or unlocked (the presence detector's): logged,
    /// and each wakes the brain, but an unlock ending an away, whose back is
    /// the one reaction (`TranscriptView.lock`). An unlock ends a nap.
    @discardableResult
    public func lock(_ event: Event) -> Step {
        input(at: event.at) {
            harness.emit(event)
            run(core.lock(event.phase == .start, at: event.at))
            if event.phase == .end { endNaps(at: event.at) }
        }
    }

    /// Another buddy's gestures from the world (`WorldGestures`): logged,
    /// and each that plays wakes the brain, which answers it.
    @discardableResult
    public func world(_ events: [Event], at now: Int64) -> Step {
        input(at: now) { for e in events { harness.emit(e) } }
    }

    /// You showed up: a nap ends (`Core.nap`).
    func endNaps(at now: Int64) { run(core.endNap(at: now)) }

    /// Whether Boop is asleep and no agent works: you're away, or it
    /// dozed off (asleep with agents to watch, not merely none yet).
    /// When the memory dreams by itself.
    public func asleepAndIdle(at now: Int64) -> Bool {
        let doing = core.snapshot(at: now).doing
        guard doing != "working" else { return false }
        return view.away || (!core.sessions.isEmpty && doing == "asleep")
    }

    /// The core's timers, then the harness's tick: a check-in if one is
    /// due, and what's been in progress too long ended.
    @discardableResult
    public func tick(at now: Int64) -> Step {
        input(at: now) {
            run(core.tick(at: now))
            harness.tick()
        }
    }

    /// The core's effects from a call outside the inputs above (the mood
    /// changing, the mic): their records logged, the rest for the caller.
    @discardableResult
    public func effects(_ effects: [CoreEffect], at now: Int64) -> Step {
        input(at: now) { run(effects) }
    }

    /// Carries out the core's effects' records; the caller carries out the
    /// rest, which the step collects.
    public func run(_ effects: [CoreEffect]) {
        step?.effects += effects
        for case .record(let e) in effects { harness.emit(e) }
    }

    /// Reads the log's last day back, as a launch does: into the view (its
    /// lines) and the core, and returns how many
    /// events it read. A started action with no end can't end now (its
    /// handle went with the last launch), so it's ended as failed.
    @discardableResult
    public func readBack(now: Int64) -> Int {
        inputTime.now = max(inputTime.now, now)
        let read = harness.resume()
        for e in read { core.replay(e) }
        return read.count
    }

    /// What was done about the event `seq` as HISTORY shows it
    /// (`LogView.shown`): what's done or in
    /// progress, not what failed or ended failed.
    func shown(dids seq: Int, _ log: LogView) -> [ViewEvent.Did] {
        log.dids(for: seq).compactMap { d in
            log.shown(d).map { ViewEvent.Did(message: $0.message, by: d["by"]?.string ?? "brain", seq: d.seq) }
        }
    }

    /// The sessions as the view has them now (tests).
    var threads: [String: SessionTracker.Session] { view.sessions(transcript.view(now: inputTime.now)) }

    /// Why an event may not wake the brain now, or nil if it may: it needs
    /// a brain, and the view's holds.
    public func whyNotWake(_ e: Event) -> String? {
        if !brain { return "no brain" }
        return view.hold(e, transcript.view(now: inputTime.now), needsYou: { core.needsYouBlock })
    }
}
