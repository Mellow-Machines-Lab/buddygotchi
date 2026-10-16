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
    /// The first buddy's core, and the only one's.
    public let core: Core
    /// The buddies, each with its own core, which hears only its own
    /// agents' events, pokes and talk. Empty for one buddy, whose events
    /// carry no tag.
    public private(set) var buddies: [Buddy] = []
    var cores: [String: Core] = [:]
    let binding = BuddyBinding()
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

    /// `clock` is the harness's; with none, its time is each input's.
    /// `loop` false leaves the brain to `harness.respond(to:)` (the evals).
    public init(core: Core, view: TranscriptView, transcript: Log = Transcript.log(), time: LocalTime = LocalTime(),
                clock: Harness.Clock? = nil, queue: DispatchQueue = .main, loop: Bool = true,
                note: @escaping (String) -> Void = { _ in }) {
        self.core = core
        self.view = view
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

    /// Runs several buddies: `buddies` in order, the first on `core`, each
    /// other on its own. With one, nothing changes: its events carry no
    /// tag.
    public func run(_ buddies: [Buddy], cores more: [Core]) {
        precondition(buddies.count == more.count + 1, "one core for each buddy after the first")
        guard buddies.count > 1 else { return }
        self.buddies = buddies
        cores = Dictionary(uniqueKeysWithValues: zip(buddies.map(\.id), [core] + more))
    }

    /// The buddy `id`, if it's one of several.
    public func buddy(_ id: String?) -> Buddy? { id.flatMap { id in buddies.first { $0.id == id } } }

    /// The core of the buddy `id`, the first's for none.
    public func core(_ id: String?) -> Core { id.flatMap { cores[$0] } ?? core }

    /// Every buddy's id and core, in order: the one core, untagged, for one.
    public var everyCore: [(buddy: String?, core: Core)] {
        buddies.isEmpty ? [(nil, core)] : buddies.map { ($0.id, cores[$0.id]!) }
    }

    /// `body` as the buddy `id`'s work, its pack in scope.
    public func scoped<R>(_ id: String?, _ body: () -> R) -> R { buddy(id)?.pack.run(body) ?? body() }

    /// An agent's event, from an adapter: its `ts` is now. With several
    /// buddies it goes to the one watching its session (`BuddyBinding`), tagged
    /// with it. It's logged without what its session already has
    /// (`Core.unrepeated`).
    @discardableResult
    public func agent(_ event: Event) -> Step {
        input(at: event.at) {
            var event = event
            let id = buddies.isEmpty ? nil
                : binding.buddy(for: event, among: buddies, watching: { self.cores[$0]?.sessions.count ?? 0 })
            if let id { event.data["buddy"] = .string(id) }
            let core = core(id)
            let e = harness.emit(core.unrepeated(event))
            run(scoped(id) { core.handle(e) }, buddy: id)
        }
    }

    /// The device's poke, on the buddy `buddy` (nil for the only one): the
    /// device has already played it. A tap that opens a finished turn's
    /// thread means "take me there", not a poke: the core records
    /// `open_thread` for it, which holds it back.
    @discardableResult
    public func poke(at now: Int64, finish: ThreadRef? = nil, buddy: String? = nil) -> Step {
        input(at: now) {
            let e = harness.emit(Event(at: now, source: .device, type: .poke, specificType: "input",
                                       data: buddy.map { ["buddy": .string($0)] } ?? [:]))
            run(scoped(buddy) { core(buddy).poke(at: now, seq: e.seq, finish: finish) }, buddy: buddy)
        }
    }

    /// One buddy's reaction, which the others hear when there are several:
    /// what it did, as its line. Only with several buddies.
    @discardableResult
    public func reacted(_ message: String, buddy: String, at now: Int64) -> Step {
        input(at: now) {
            harness.emit(Event(at: now, source: .boop, type: .reacted, specificType: "brain",
                               data: ["buddy": .string(buddy), "message": .string(message)]))
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
        var data: [String: JSONValue] = ["words": .string(cut)]
        if let buddy { data["buddy"] = .string(buddy) }
        return input(at: now) {
            harness.emit(Event(at: now, source: .mic, type: .talk, specificType: by.rawValue, data: data))
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
            for (id, core) in everyCore { run(scoped(id) { core.tick(at: now) }, buddy: id) }
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
            if let buddy { e.data["buddy"] = .string(buddy) }
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
            let id = Buddy.of(e).flatMap { cores[$0] == nil ? nil : $0 }
            if id != nil, e.agent != nil { _ = binding.buddy(for: e, among: buddies, watching: { _ in 0 }) }
            // An untagged event from a launch with one buddy is the first's.
            scoped(id) { core(id).replay(e) }
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
        let core = core(Buddy.of(e))
        return view.hold(e, transcript.view(now: inputTime.now), needsYou: { core.needsYouBlock })
    }
}
