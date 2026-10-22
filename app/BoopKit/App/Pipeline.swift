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
    /// The buddies, in order, each with its own core, which hears only its
    /// own agents' events, pokes and talk.
    public let buddies: [Buddy]
    let cores: [String: Core]
    /// Which buddy watches each agent session.
    let binding = BuddyBinding()
    /// The first buddy's core, the only one's.
    public var core: Core { cores[buddies[0].id]! }
    /// Whether there are several buddies: then each event about one is
    /// tagged with it, and each is a voice of the harness. One is tagged
    /// nowhere.
    public var several: Bool { buddies.count > 1 }
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
    public var onView: ((ViewEvent) -> Void)?

    /// What one input did.
    public struct Step: Sendable {
        /// The cores' effects, their records included.
        public var effects: [CoreEffect] { tagged.map(\.effect) }
        /// Each effect with the buddy whose core decided it: nil for the
        /// only one.
        public var tagged: [(buddy: String?, effect: CoreEffect)] = []
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

    /// One buddy, the process's character, on `core`.
    public convenience init(core: Core, view: TranscriptView, transcript: Log = Transcript.log(), time: LocalTime = LocalTime(),
                            clock: Harness.Clock? = nil, queue: DispatchQueue = .main, loop: Bool = true,
                            note: @escaping (String) -> Void = { _ in }) {
        self.init([(.only(), core)], view: view, transcript: transcript, time: time, clock: clock, queue: queue, loop: loop, note: note)
    }

    /// `buddies`, each on its own core, the first first.
    /// `clock` is the harness's; with none, its time is each input's.
    /// `loop` false leaves the brain to `harness.respond(to:)` (the evals).
    public init(_ buddies: [(buddy: Buddy, core: Core)], view: TranscriptView, transcript: Log = Transcript.log(),
                time: LocalTime = LocalTime(), clock: Harness.Clock? = nil, queue: DispatchQueue = .main, loop: Bool = true,
                note: @escaping (String) -> Void = { _ in }) {
        self.buddies = buddies.map(\.buddy)
        cores = Dictionary(uniqueKeysWithValues: buddies.map { ($0.buddy.id, $0.core) })
        self.view = view
        if buddies.count > 1 { view.buddies = buddies.map(\.buddy) }
        var options = Harness.Options()
        // Boop's own words on how to read HISTORY and NOW are in its guide's
        // section.
        options.reading = .none
        options.heading = { wall in "\(time.clock(wall)), \(time.weekday(wall))" }
        options.loop = loop
        let input = inputTime
        harness = Harness(name: CharacterPack.active.name, brain: nil, log: transcript,
                          clock: clock ?? Harness.Clock(now: { input.now }), queue: queue, options: options, note: note)
        view.register(on: harness) { [unowned self] buddy in self.core(buddy).needsYouBlock }
        // With several buddies, one's reaction is an event the others hear,
        // one more in its chain when it answers another's.
        harness.on(Event.did) { [unowned self] d in
            guard several, d.action == ReactOutput.outputName, d["ok"]?.bool == true, let who = d.buddy else { return }
            let answered = d.about.flatMap(harness.log.event)
            let chain = answered?.type == .reacted ? (answered?["chain"]?.int ?? 1) + 1 : 1
            harness.emit(Event(at: d.at, source: .boop, type: .reacted, specificType: "brain", buddy: who,
                               data: ["message": d["message"] ?? .null, "chain": .int(chain)]))
        }
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
        harness.batch { body() }
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
            outer.tagged += made.tagged
            outer.recorded += made.recorded
            outer.views += made.views
            step = outer
        }
        return made
    }

    /// The buddy `id`, the first for none.
    public func buddy(_ id: String?) -> Buddy { buddies.first { $0.id == id } ?? buddies[0] }

    /// The core of the buddy `id`, the first's for none.
    public func core(_ id: String?) -> Core { id.flatMap { cores[$0] } ?? core }

    /// How events about the buddy `id` are tagged: with it when there are
    /// several, not at all for one.
    public func tag(_ id: String) -> String? { several ? id : nil }

    /// An agent's event, from an adapter: its `ts` is now. With several
    /// buddies it goes to the one watching its session (`BuddyBinding`),
    /// tagged with it. It's logged without what its session already has
    /// (`Core.unrepeated`).
    @discardableResult
    public func agent(_ event: Event) -> Step {
        input(at: event.at) {
            var event = event
            let id = several ? binding.buddy(for: event, among: buddies, watching: { self.cores[$0]!.sessions.count }) : nil
            if let id { event.data["voice"] = .string(id) }
            let core = core(id)
            let e = harness.emit(core.unrepeated(event))
            run(core.handle(e), buddy: id)
        }
    }

    /// The device's poke, on the buddy `buddy` (nil for the only one): the
    /// device has already played it. A tap that opens a finished turn's
    /// thread means "take me there", not a poke: the core records
    /// `open_thread` for it, which holds it back.
    @discardableResult
    public func poke(at now: Int64, finish: ThreadRef? = nil, buddy: String? = nil) -> Step {
        input(at: now) {
            let e = harness.emit(Event(at: now, source: .device, type: .poke, specificType: "input", buddy: buddy))
            run(core(buddy).poke(at: now, seq: e.seq, finish: finish), buddy: buddy)
        }
    }

    /// What you said to Boop on push-to-talk, heard by the Mac's mic
    /// after `by`'s button (`device` or `app`), cut to 2,000 characters as
    /// a prompt is on the wire. It wakes the brain
    /// even while something needs you.
    /// With several buddies, a board's own button says it to that `buddy`,
    /// and the app's to them all.
    @discardableResult
    public func said(_ words: String, by: Core.Talker, buddy: String? = nil, at now: Int64) -> Step {
        let cut = words.count > HookLine.maxMessage ? String(words.prefix(HookLine.maxMessage)) : words
        return input(at: now) {
            harness.emit(Event(at: now, source: .mic, type: .talk, specificType: by.rawValue, buddy: buddy, data: ["words": .string(cut)]))
        }
    }

    /// What Boop's ears heard (`Hearing`): its name, a word from its list or
    /// a sound, and whether it misheard. Like a poke it's logged and may
    /// wake the brain, and only the one word or sound it was, never what
    /// was said around it; nothing on screen is the rules' here, so the
    /// core isn't told. With several buddies, every one hears it.
    @discardableResult
    public func heard(_ what: String, misheard: Bool = false, at now: Int64) -> Step {
        input(at: now) {
            harness.emit(Event(at: now, source: .mic, type: .heard, specificType: what, data: ["misheard": .bool(misheard)]))
        }
    }

    /// You stepping away from the Mac or coming back, as the presence
    /// detector decided: logged, but never the
    /// core's. Only a back wakes the brain.
    @discardableResult
    public func presence(_ event: Event) -> Step {
        input(at: event.at) { harness.emit(event) }
    }

    /// The core's timers, then the harness's tick: a heartbeat if one is
    /// due, and what's been in progress too long ended.
    @discardableResult
    public func tick(at now: Int64) -> Step {
        input(at: now) {
            for b in buddies { run(cores[b.id]!.tick(at: now), buddy: tag(b.id)) }
            harness.tick()
        }
    }

    /// A core's effects from a call outside the inputs above (the mood
    /// changing, the mic), the buddy `buddy`'s: their records logged, the
    /// rest for the caller.
    @discardableResult
    public func effects(_ effects: [CoreEffect], buddy: String? = nil, at now: Int64) -> Step {
        input(at: now) { run(effects, buddy: buddy) }
    }

    /// Carries out a core's effects' records, tagged with its buddy; the
    /// caller carries out the rest, which the step collects.
    public func run(_ effects: [CoreEffect], buddy: String? = nil) {
        step?.tagged += effects.map { (buddy, $0) }
        for case .record(var e) in effects {
            if let buddy { e.data["voice"] = .string(buddy) }
            harness.emit(e)
        }
    }

    /// Reads the log's last day back, as a launch does: into the view (its
    /// lines) and the core, and returns how many
    /// events it read. A started action with no end can't end now (its
    /// handle went with the last launch), so it's ended as failed.
    @discardableResult
    public func readBack(now: Int64) -> Int {
        inputTime.now = max(inputTime.now, now)
        let read = harness.resume()
        for e in read {
            if several, e.agent != nil { _ = binding.buddy(for: e, among: buddies, watching: { _ in 0 }) }
            // An untagged event, from a launch with one buddy, is the first's.
            core(e.buddy).replay(e)
        }
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
        let core = core(e.buddy)
        return view.hold(e, transcript.view(now: inputTime.now), needsYou: { core.needsYouBlock })
    }
}
