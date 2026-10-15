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
    public var onView: ((ViewEvent) -> Void)?

    /// What one input did.
    public struct Step: Sendable {
        /// The core's effects, its records included.
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
            outer.effects += made.effects
            outer.recorded += made.recorded
            outer.views += made.views
            step = outer
        }
        return made
    }

    /// An agent's event, from an adapter: its `ts` is now. It's logged
    /// without what its session already has (`Core.unrepeated`).
    @discardableResult
    public func agent(_ event: Event) -> Step {
        input(at: event.ts) {
            let e = harness.emit(core.unrepeated(event))
            run(core.handle(e))
        }
    }

    /// The device's poke: the device has already played it. A tap that
    /// opens a finished turn's thread means "take me there", not a poke:
    /// the core records `open_thread` for it, which holds it back.
    @discardableResult
    public func poke(at now: Int64, finish: ThreadRef? = nil) -> Step {
        input(at: now) {
            let e = harness.emit(Event(ts: now, source: .device, type: .poke, specificType: "input"))
            run(core.poke(at: now, seq: e.seq, finish: finish))
        }
    }

    /// What you said to Boop on push-to-talk, heard by the Mac's mic
    /// after `by`'s button (`device` or `app`), cut to 2,000 characters as
    /// a prompt is on the wire. It wakes the brain
    /// even while something needs you.
    @discardableResult
    public func said(_ words: String, by: Core.Talker, at now: Int64) -> Step {
        let cut = words.count > HookLine.maxMessage ? String(words.prefix(HookLine.maxMessage)) : words
        return input(at: now) {
            harness.emit(Event(ts: now, source: .mic, type: .talk, specificType: by.rawValue, data: ["words": .string(cut)]))
        }
    }

    /// You stepping away from the Mac or coming back, as the presence
    /// detector decided: logged, but never the
    /// core's. Only a back wakes the brain.
    @discardableResult
    public func presence(_ event: Event) -> Step {
        input(at: event.ts) { harness.emit(event) }
    }

    /// The core's timers, then the harness's tick: a heartbeat if one is
    /// due, and what's been in progress too long ended.
    @discardableResult
    public func tick(at now: Int64) -> Step {
        input(at: now) {
            run(core.tick(at: now))
            harness.tick()
        }
    }

    /// Logs an event nothing else acts on, such as an action's.
    @discardableResult
    public func record(_ event: Event) -> Event {
        var logged = event
        _ = input(at: max(inputTime.now, event.at)) { logged = harness.emit(event) }
        return logged
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

    /// Whether you're away from the Mac, as the log has it:
    /// the presence detector starts from this at launch.
    public var away: Bool { view.away(transcript.view(now: inputTime.now)) }

    /// The event `seq` with its line and what the rules did about it, as
    /// it stands now; nil for one with no line.
    public func viewEvent(_ seq: Int) -> ViewEvent? {
        guard let e = transcript.event(seq), let line = harness.line(seq),
              var v = view.view(e, line, wakes: false, log: transcript.view(before: e)) else { return nil }
        v.wakesBrain = harness.wakes(e) && whyNotWake(e) == nil
        v.did = shown(dids: seq, transcript.view(now: inputTime.now))
        return v
    }

    /// What was done about the event `seq` as HISTORY shows it
    /// (`LogView.shown`): what's done or in
    /// progress, not what failed or ended failed.
    func shown(dids seq: Int, _ log: LogView) -> [ViewEvent.Did] {
        log.dids(for: seq).compactMap { d in
            log.shown(d).map { ViewEvent.Did(message: $0.message, by: d["by"]?.string ?? "brain", seq: d.seq) }
        }
    }

    /// The threads as the view has them now (tests).
    var threads: [String: TranscriptView.Thread] { view.threads(transcript.view(now: inputTime.now)) }

    /// Every event with a line in the log, oldest first.
    public var views: [ViewEvent] { transcript.events.compactMap { viewEvent($0.seq) } }

    /// Why an event may not wake the brain now, or nil if it may: it needs
    /// a brain, and the view's holds.
    public func whyNotWake(_ e: Event) -> String? {
        if !brain { return "no brain" }
        return view.hold(e, transcript.view(now: inputTime.now), needsYou: { core.needsYouBlock })
    }
}
