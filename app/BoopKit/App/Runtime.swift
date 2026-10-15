import AgentHooks
import Foundation
import MellowHarness
import LinkKit

/// Everything the app runs, wired together: the hook
/// socket feeds the adapters, and every event goes down the pipeline, into
/// the transcript, the core and the view; the view events that wake the
/// brain go to the harness, the core's snapshots to the device link and a
/// new day to the transcript's pruning; the device's pokes come back as
/// events. The menu-bar app and `Boop --headless` both run one of these.
///
/// All state lives on `home`, one serial queue, which is also the harness's.
public final class Runtime: @unchecked Sendable {
    public struct Options {
        public var stateDir: URL
        public var socketPath: String
        public var link: Transport?
        /// The static parts of Jev's state: a copy of `characters/boop/steering/`.
        public var steering: Steering
        /// Override the personality in `settings.json` for this run only.
        public var personality: Personality?
        /// Builds the brain from Jev's key; nil for no brain. Tests pass
        /// their own.
        public var brain: @Sendable (String?) -> (any Brain)? = { key in key.map { JevBrain(key: $0) } }
        public var time = LocalTime()
        /// Milliseconds for every duration: a steady clock by default.
        public var clock: @Sendable () -> Int64 = Runtime.steadyClock()
        /// Milliseconds since 1970, for days and times of day.
        public var wallClock: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        /// Accept `{"dev":…}` lines on the hook socket: headless, or debug
        /// mode. Plain `make run` stays deaf to them.
        public var devLines = false
        /// Moves `clock` forward, for `{"dev":"advance"}`; nil ignores it.
        public var advance: (@Sendable (Int64) -> Void)?
        /// Debug mode: logs every hook with what the
        /// adapter made of it and every message sent to the device, starts
        /// `debug.jsonl` afresh in the state directory (keeping the last
        /// launches' copies beside it) with every event, view event and
        /// pass and the dashboard's lines, and hands them and the core's
        /// decisions to `debugPrint`, readably.
        public var debug = false
        /// Where debug mode prints (the terminal). Never the log file: it
        /// carries Jev's whole state.
        public var debugPrint: @Sendable (String) -> Void = { _ in }
        /// Jev's key, given the one Boop keeps (`saved`): at start, off
        /// `home` and the main thread, `saved` reads the Keychain, which
        /// may stop to ask for access; after, it's what Settings saved.
        /// Every read of the key goes through here, so tests and headless
        /// runs decide what it is.
        public var readJevKey: @Sendable (_ saved: () -> String?) -> String? = { JevKey.environment() ?? $0() }
        /// The Mac's idle time in ms, read on every tick for the presence
        /// detector: the app's. Nil (headless)
        /// reads none of the Mac's signals: `{"dev":"presence"}` lines
        /// stand in.
        public var idleMs: (@Sendable () -> Int64)?
        public var log: @Sendable (String) -> Void = { _ in }
        /// Every message sent to the device, as it's sent, for whoever
        /// records them (`DemoRecorder`). On whichever thread sends it.
        public var onDeviceLine: (@Sendable (String) -> Void)?
        /// Opens a thread on the Mac (`ThreadLink`): a tap while something
        /// needs you, or a click in the popover. Tests pass their own.
        public var open: @Sendable (ThreadLink.Target) -> Bool = ThreadLink.openOnMac

        public init(stateDir: URL, socketPath: String, link: Transport?, steering: Steering) {
            self.stateDir = stateDir
            self.socketPath = socketPath
            self.link = link
            self.steering = steering
        }
    }

    public enum OpenError: Error, CustomStringConvertible {
        case notSetUp, locked(String)
        public var description: String {
            switch self {
            case .notSetUp: "Boop isn't set up yet: no long-term.md"
            case .locked(let dir): "another Boop is already running on \(dir)"
            }
        }
    }

    /// Debug mode's log of every event, view event and pass, in the state directory.
    public let debugLogURL: URL

    /// Each block drains its own autorelease pool: a burst keeps `home`
    /// busy, and what Foundation leaves autoreleased would pile up until
    /// it went idle.
    public let home = DispatchQueue(label: "boop.home", qos: .userInitiated, autoreleaseFrequency: .workItem)
    public let options: Options
    /// LinkKit's link to the device, in Boop's vocabulary (`BoopDevice`).
    public let link: DeviceLink
    /// The newest snapshot sent to the device.
    public internal(set) var latest: StateSnapshot?
    /// Boop's name, from `long-term.md`.
    public let name: String
    public private(set) var settings: AppSettings
    /// The personality running now, touched only on `home`. Starts as the
    /// saved one, unless this run overrides it.
    public private(set) var personality: Personality
    let core: Core
    let view: TranscriptView
    let pipeline: Pipeline
    /// MellowHarness's `Harness`: Boop's brain.
    let harness: Harness
    /// Boop's mood, MellowHarness's `Choice`.
    let mood: Choice
    /// Whether the brain has failed for long enough to say so,
    /// and how many passes that asked it have
    /// dropped in a row.
    var trouble: BrainTrouble?
    var droppedInARow = 0
    /// Writes `debug.jsonl`'s event, view and pass lines, in order.
    var debugWriter: DebugLog.Writer?
    /// Each question's option names as the launch's `questions` line gave
    /// them.
    var launchOptions: [String: [String]] = [:]
    let lock: InstanceLock
    var server: HookServer?
    var timer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then no event wakes the brain.
    var jevKey: String??
    /// The brain's reactions on the device until each ends: the device
    /// decides when each plays.
    let reactions: Reactions
    /// The transport's `trouble` as the status last had it. It changes on
    /// the transport's thread, so the tick looks.
    var linkTrouble: String?
    /// Boop's XP and stage, counted from each event as it's logged,
    /// and whether the XP changed since the last status.
    let growth: GrowthStore
    var grew = false
    /// The last `status` line written to `debug.jsonl`, without its time.
    var lastStatus: String?
    /// This launch's debug lines outside debug mode, for `saveReport`: in
    /// debug mode the file has them.
    let recent: DebugLog.Recent
    /// Every `debug.jsonl` line goes through this: in debug mode written to
    /// the file and printed readably, and otherwise kept in `recent`.
    let emit: (String) -> Void

    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?
    /// Read-only visual mirror of the reactions sent. Never completes a handle.
    public var onReaction: ((Int, DeviceReaction) -> Void)?

    /// Push-to-talk: turns the Mac's mic on (true) or off, as the core
    /// says. Once it's off, the app hands what it heard to `said`, or calls
    /// `heardNothing`; with none set (headless), turning it off hears
    /// nothing. The core keeps push-to-talk's state (`Core.Talk`). On `home`.
    public var onListen: ((Bool) -> Void)?

    // Here and away. All on `home`.
    /// Decides whether you're at the Mac, from where the transcript left it.
    var presence = PresenceDetector()
    /// The idle time `{"dev":"presence","idle_ms":N}` set, read in place of
    /// the Mac's when there's no `idleMs`.
    var devIdleMs: Int64 = 0
    /// Hears every agent's hook as it comes, before Boop takes it: a live
    /// demo's player (`play`), which keeps its script to the agent's pace.
    var demoHeard: ((HookLine) -> Void)?

    /// A clock that never steps and keeps counting while the Mac sleeps,
    /// starting at the wall clock's time: the keepalive and the link's
    /// waits for the device's `ended` are measured on it, so setting the
    /// Mac's clock back can't stall them.
    public static func steadyClock() -> @Sendable () -> Int64 {
        let wall = Int64(Date().timeIntervalSince1970 * 1000)
        let start = ContinuousClock.now
        return { wall + Int64((ContinuousClock.now - start).ms) }
    }

    /// Sets up a new Boop: name and sweet-or-cheeky, asked once.
    /// It hatches `today`, by default the Mac's.
    public static func setUp(stateDir: URL, name: String, nature: LongTerm.Nature,
                             today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) throws {
        let store = try MemoryStore(directory: stateDir)
        try store.setUp(name: name, nature: nature, seed: UInt64.random(in: 1...0xFFFF), today: today)
    }

    public init(_ options: Options) throws {
        self.options = options
        debugLogURL = options.stateDir.appendingPathComponent(DebugLog.fileName)
        guard let lock = InstanceLock(directory: options.stateDir) else { throw OpenError.locked(options.stateDir.path) }
        self.lock = lock
        let log = options.log
        let wall = options.wallClock(), wallAt = options.clock()
        let today = options.time.day(wall)
        guard let longTerm = try MemoryStore(directory: options.stateDir, today: today, log: log).longTerm
        else { throw OpenError.notSetUp }
        name = longTerm.name
        settings = AppSettings.load(from: options.stateDir)
        link = BoopDevice.link(options.link, log: log)
        let recent = DebugLog.Recent()
        self.recent = recent
        let debugLog = options.debug ? debugLogURL : nil
        if let debugLog { DebugLog.start(debugLog) }
        let printer = DebugLog.Printer()
        let print = options.debugPrint
        let emit = { (line: String) in
            guard let debugLog else { return recent.add(line) }
            LineFile.append(line, to: debugLog)
            printer.readable(line).map(print)
        }
        self.emit = emit
        let clock = options.clock
        // boop.log leaves out a `state` sent again unchanged (the keepalive,
        // a reply to `hello`), which debug.jsonl keeps.
        var lastState: String?
        let sent = options.onDeviceLine
        link.onSend = { line, sender in
            sent?(line)
            emit(DebugLog.sent(line, by: sender, at: clock()))
            guard debugLog != nil, line != lastState else { return }
            if line.hasPrefix(#"{"t":"state""#) { lastState = line }
            log("link \(sender == .brain ? "brain" : "rules") → " + line)
        }

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        var config = Core.Config(volume: settings.volume, time: options.time, seed: longTerm.seed ^ UInt64(now))
        config.firstAsk = SessionTracker.randomFirstRequest()
        let places = self.places
        // The launch's read-back prunes the transcript, so today isn't a new day.
        core = Core(config: config, lastActiveDay: today, place: places.place)
        core.setWallClock(wall, at: wallAt)
        view = TranscriptView(rules: rules, seed: longTerm.seed ^ UInt64(now), place: places.place)
        let transcript = Transcript.log(folder: options.stateDir.appendingPathComponent(Transcript.folderName),
                                        time: options.time, note: log)
        pipeline = Pipeline(core: core, view: view, transcript: transcript, time: options.time,
                            clock: Harness.Clock(now: options.clock, wall: options.wallClock), queue: home, note: log)
        pipeline.brain = false  // until Jev's key is read
        for over in options.steering.overBudget() { log("steering: over budget: \(over)") }

        // The outputs' closures are only ever called on `home`, and reach
        // `self` once it's whole.
        var personalityNow: () -> Personality = { .default }
        var queued: (DeviceReaction, Pending) -> Void = { _, _ in }
        let link = self.link
        let reactions = Reactions()
        self.reactions = reactions
        (harness, mood) = Runtime.harness(
            pipeline: pipeline, steering: options.steering, personality: { personalityNow() }, reactions: reactions,
            queue: { queued($0, $1) }, speaks: { link.hello.map { DeviceInfo($0).hasTheVoice } ?? true }, nature: longTerm.nature)
        // The questions line is debug.jsonl's first, before the read-back's
        // lines, the socket or the link can add one, so a changed first line
        // means a new launch. The read-back's own lines wait for it.
        var held: [String] = []
        var holding = true
        debugWriter = Runtime.debugLines(pipeline: pipeline, emit: { line in if holding { held.append(line) } else { emit(line) } })
        // Growth's store, or one in memory for this launch if the file won't open.
        let values: KeyValueStore
        do { values = try KeyValueStore(directory: options.stateDir) } catch {
            log("growth: \(error); keeping XP in memory until the app quits")
            values = try KeyValueStore(directory: nil)
        }
        growth = GrowthStore(values, log: log)
        // The view and the core pick up where the last launch left them.
        let read = home.sync { pipeline.readBack(now: now) }
        let logNow = transcript.view(now: now)
        let questions = DebugLog.questions(harness.outputs, log: logNow, at: now)
        emit(questions)
        launchOptions = DebugLog.options(questions)
        holding = false
        held.forEach(emit)
        if read > 0 { log("transcript: read back \(read) events") }
        presence = PresenceDetector(away: view.away(logNow))
        growth.follow(transcriptAt: transcript.lastSeq)
        // The core reads the mood where the mood output keeps it. Weak: the
        // harness holds the core.
        let mood = self.mood
        core.mood = { [weak harness = self.harness] in harness.map { MoodOutput.value(mood, $0.log.view(now: clock())) } ?? MoodOutput.initial }
        personalityNow = { [weak self] in self?.personality ?? .default }
        queued = { [weak self] reaction, pending in self?.queue(reaction, pending) }
        // The device's taps and push-to-talk; the link leaves out those of
        // a device whose firmware doesn't fit.
        link.onEvent = { [weak self] ev in self?.deviceEvent(ev) }
        // A hello (the first on a link, or one that says something new):
        // log who the device is, and show it what's true now.
        link.onHello = { [weak self] hello in
            DeviceInfo(hello).logLines.forEach(log)
            if let self, let latest = self.latest { self.show(latest) }
        }
        // A pass can change the mood, which the device and the menu bar show.
        harness.on(Event.did) { [weak self] e in
            guard let self, e.action == MoodOutput.outputName, e["ok"]?.bool == true else { return }
            run(core.moodChanged(at: options.clock()))
        }
        harness.onPass = { [weak self] pass in self?.passed(pass) }
        // Every event as it's logged, never the read-back's: those were counted.
        harness.on("*") { [weak self] e in
            guard let self, growth.count(e) else { return }
            grew = true
        }
    }

    /// Boop's brain on MellowHarness's `Harness`: its outputs,
    /// mood then react, and the sections of Jev's
    /// state: the guide with how to read the rest, PERSONALITY, what the
    /// `nature` chosen at setup adds to it (the pack's `nature/` file, if
    /// any), and MOOD, then HISTORY, closed by how long Boop has been in its mood and
    /// reaching back to the oldest working turn. The app's, and the evals',
    /// so the two can't drift apart. `queue` plays a reaction,
    /// whose end `reactions` reads, and `speaks` says whether the device
    /// plays Voice's takes. The brain is the caller's to set (`harness.use`).
    public static func harness(pipeline: Pipeline, steering: Steering, personality: @escaping () -> Personality,
                               reactions: Reactions = Reactions(), queue: @escaping (DeviceReaction, Pending) -> Void,
                               speaks: @escaping () -> Bool = { true }, nature: LongTerm.Nature? = nil) -> (harness: Harness, mood: Choice) {
        let h = pipeline.harness
        let core = pipeline.core
        let view = pipeline.view
        let mood = MoodOutput.choice()
        // A reaction your tap cut short is in progress while the pokes go
        // on, and done once anything else happens.
        // A reaction's end, MellowHarness's own event, never stops the pokes.
        // The rule holds the log, not the harness, which holds the rule.
        let transcript = h.log
        h.on("*") { e in
            guard !reactions.cutByTap.isEmpty, TranscriptView.stopsThePokes(e, transcript.view(before: e)) else { return }
            reactions.pokesStopped()
        }
        let react = ReactOutput(queue: queue, blocked: { core.reactionBlock }, who: { [weak h] now in
            // Weak: the harness holds this output.
            guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts),
                  let who = view.who(about: key, h.log.view(now: h.clock.now())) else { return nil }
            return DeviceReaction.Who(agent: who.agent, thread: who.thread, opens: who.opens)
        }, speaks: speaks)
        h.output(mood)
        h.output(react, openFor: ReactOutput.openForMs, keepOpen: TranscriptView.heldByPokes)
        h.section { _ in steering.guide + "\n" + EventLine.reading + "\n" + EventLine.words }
        h.section { _ in steering.personality(personality()).text }
        h.section { _ in nature.flatMap(steering.nature) }
        h.section { log in steering.mood(MoodOutput.value(mood, log)) }
        h.closing { _, now, log in MoodOutput.sinceLine(mood, log, at: now) }
        h.reachBack { _, now, log in view.workingSince(at: now, log) }
        return (h, mood)
    }

    /// `debug.jsonl`'s lines from `pipeline`, to `emit`: its events
    /// and view events, and the passes the returned writer is handed.
    @discardableResult
    public static func debugLines(pipeline: Pipeline, emit: @escaping (String) -> Void) -> DebugLog.Writer {
        let writer = DebugLog.Writer(emit: emit)
        pipeline.onRecord = { writer.event($0) }
        pipeline.onView = { writer.view($0) }
        return writer
    }

    // MARK: Running

    public func start() throws {
        let home = self.home
        // Hooks are timed on the runtime's clock, which headless mode can move.
        let clock = options.clock
        let onLine: @Sendable (HookLine) -> Void = { [weak self] line in
            let received = clock()
            home.async { self?.hook(line, received: received) }
        }
        let onOther: @Sendable (Data) -> Void = { [weak self] data in home.async { self?.dev(data) } }
        let server = HookServer(path: options.socketPath, onLine: onLine, onOther: options.devLines ? onOther : nil)
        try server.start()
        self.server = server
        options.link?.start(
            onLine: { [weak self] line in self?.home.async { self?.device(line) } },
            onConnection: { [weak self] up in self?.home.async { self?.connection(up) } })
        // A menu-bar app with its popover closed is a candidate for App Nap,
        // which coalesces timers; the 10 s keepalive must beat the device's
        // 30 s no-app timeout. This doesn't keep the Mac awake.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
                                                         reason: "Keeps Boop's device in sync")
        let timer = DispatchSource.makeTimerSource(queue: home)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        // From here on the harness and the callbacks are touched only on
        // `home`: reading Jev's key sets the brain and calls `onChange`,
        // so it starts now, after the app has set its callbacks.
        home.async { [self] in
            readJevKey()
            run(pipeline.tick(at: options.clock()))
            changed()
            options.log("boop: running on \(options.stateDir.path), socket \(options.socketPath), "
                        + "link \(options.link?.name ?? "none"), personality \(personality.rawValue), "
                        + "mood \(moodNow), brain \(harness.brain?.id ?? "none (reading Jev's key)")"
                        + (options.debug ? ", debug log \(debugLogURL.path)" : ""))
        }
    }

    /// Stops listening for hooks and the device. Safe to call twice.
    public func stop() {
        timer?.cancel()
        timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        server?.stop()
        server = nil
        options.link?.stop()
    }

    // MARK: Inputs (on `home`)

    func hook(_ line: HookLine, received: Int64) {
        demoHeard?(line)
        let event = Adapter.event(from: line, receivedAt: received)
        // Debug mode logs every hook with what it became; the doctor skill
        // arms the plain line to see hooks arrive. Otherwise hooks aren't logged.
        if options.debug {
            options.log("hook: \(line.agent) \(line.hook) \(line.session) → " + (event?.summary ?? "ignored"))
        } else if doctorArmed() {
            options.log("hook: \(line.agent) \(line.hook) \(line.session)")
        }
        guard let event else { return }
        run(pipeline.agent(event))
    }

    func tick() {
        let now = options.clock()
        core.setWallClock(options.wallClock(), at: now)
        run(pipeline.tick(at: now))
        if let e = presence.tick(at: now, idleMs: options.idleMs?() ?? devIdleMs) { recordPresence(e) }
        // The keepalive, and the reactions whose `ended` never came.
        link.tick(now: now)
        reactions.tick(now: now)
        let trouble = link.transport?.trouble
        if trouble != linkTrouble {
            linkTrouble = trouble
            changed()
        }
    }

    /// You stepped away or came back, as the detector decided: recorded,
    /// and a back wakes the brain.
    func recordPresence(_ e: Event) {
        options.log("presence: \(e.phase == .start ? "away" : "back") (\(e.specificType))")
        run(pipeline.presence(e))
    }

    /// A signal from the Mac for the presence detector.
    func presenceSignal(_ signal: PresenceDetector.Signal) {
        if let e = presence.signal(signal, at: options.clock()) { recordPresence(e) }
    }

    /// Carries out the core's effects from a call outside the pipeline.
    func run(_ effects: [CoreEffect]) {
        run(pipeline.effects(effects, at: options.clock()))
    }

    /// Carries out what an input did: the core's
    /// effects (its records are in the transcript already), then a pass
    /// for each view event that wakes the brain.
    func run(_ step: Pipeline.Step) {
        var stateChanged = false
        for effect in step.effects {
            switch effect {
            case .state(let snapshot):
                show(snapshot)
                stateChanged = true
            case .sessions:
                stateChanged = true
            case .record:
                break
            case .newDay:
                pipeline.transcript.prune(now: options.clock())
            case .listen(let on, let by):
                mic(on, by: by)
                stateChanged = true
            case .reaction(let reaction):
                playRule(reaction)
            case .open(let thread):
                open(thread, by: "tap")
            }
        }
        if stateChanged || grew { changed() }
    }

    func saveSettings(_ change: (inout AppSettings) -> Void) {
        change(&settings)
        do { try settings.save(to: options.stateDir) } catch { options.log("settings: can't save: \(error)") }
    }

    // MARK: From the menu bar (any thread)

    /// Opens `thread` where it runs: a session clicked in the popover.
    public func openThread(_ thread: ThreadRef) {
        home.async { [self] in open(thread, by: "click") }
    }

    /// Opens a thread on the Mac, after a tap or a click.
    /// What opened is a log line: only the tap's is Boop's doing,
    /// and the core records it.
    func open(_ thread: ThreadRef, by: String) {
        guard let target = ThreadLink.target(thread) else {
            options.log("open: nowhere to open \(thread.agent) \(thread.session) (\(by)): no app named")
            return
        }
        let opened = options.open(target)
        options.log("open: \(target.arguments.joined(separator: " ")) (\(by))" + (opened ? "" : ": open failed"))
    }

    /// A lock, unlock, sleep or wake from the Mac, for the presence
    /// detector.
    public func presence(_ signal: PresenceDetector.Signal) {
        home.async { [self] in presenceSignal(signal) }
    }

    public func setVolume(_ volume: Int) {
        home.async { [self] in
            run(core.setVolume(volume, at: options.clock()))
            saveSettings { $0.volume = core.config.volume }
        }
    }

    /// A new personality: the view's rules and Jev's
    /// state from the next event.
    public func setPersonality(_ personality: Personality) {
        home.async { [self] in
            self.personality = personality
            saveSettings { $0.personality = personality }
            view.setRules(options.steering.personality(personality).rules)
            options.log("personality \(personality.rawValue)")
            changed()
        }
    }

    /// A fresh status, on `home`.
    public func refresh() {
        home.async { [self] in changed() }
    }
}

extension Duration {
    /// In whole milliseconds.
    var ms: Int { Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000) }
}
