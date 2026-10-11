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
        /// adapter made of it and every line sent to the device, starts
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
        /// Every line sent to the device, as it's sent, for whoever
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

    /// What the menu bar shows.
    public struct Status: Sendable {
        /// Boop's name, from `long-term.md`.
        public var name: String
        /// What the device shows, and Boop's mood.
        public var snapshot: StateSnapshot
        /// Every session, for the popover's list.
        public var sessions: [SessionSummary]
        public var connected: Bool
        /// What the device said of itself in its `hello`.
        public var device: DeviceInfo?
        /// Why the link can't look for the device (Bluetooth off), in the
        /// transport's words, for the popover.
        public var linkTrouble: String?
        /// Why the device connected gets no reactions: its firmware doesn't
        /// fit the app (linkkit/SPEC.md §6), in the link's words.
        public var deviceTrouble: String?
        public var personality: Personality
        /// The brain as it runs: `jev:jev-latest`, or `none` without a key.
        public var brain: String
        /// Jev's key has been read, whether there was one or not. Until
        /// then `brain` is `none` only because it isn't known yet.
        public var keyRead: Bool
        /// The brain failing, for the popover's notice.
        public var brainTrouble: BrainTrouble?
        /// The Mac's mic is on for push-to-talk.
        public var listening: Bool
        /// The face holds listening through the reply wait, after the mic stops.
        public var faceListening: Bool
        /// Why push-to-talk couldn't hear you, until the next try.
        public var micTrouble: String?
        /// Boop's XP and stage.
        public var growth: Growth?

        public init(name: String, snapshot: StateSnapshot, sessions: [SessionSummary], connected: Bool,
                    device: DeviceInfo?, linkTrouble: String? = nil, deviceTrouble: String? = nil, personality: Personality,
                    brain: String, keyRead: Bool = true, brainTrouble: BrainTrouble? = nil, listening: Bool = false,
                    micTrouble: String? = nil, growth: Growth? = nil, faceListening: Bool? = nil) {
            self.name = name
            self.snapshot = snapshot
            self.sessions = sessions
            self.connected = connected
            self.device = device
            self.linkTrouble = linkTrouble
            self.deviceTrouble = deviceTrouble
            self.personality = personality
            self.brain = brain
            self.keyRead = keyRead
            self.brainTrouble = brainTrouble
            self.listening = listening
            self.faceListening = faceListening ?? listening
            self.micTrouble = micTrouble
            self.growth = growth
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
    public private(set) var latest: StateSnapshot?
    /// Boop's name, from `long-term.md`.
    public let name: String
    public private(set) var settings: AppSettings
    public let moodGraph: MoodGraph.Version
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

    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?
    /// Read-only visual mirror of requested moments. Never completes a handle.
    public var onMoment: ((Int, DeviceMoment) -> Void)?

    // Push-to-talk. All on `home`.
    /// Turns the Mac's mic on (true) or off. Once it's off, the app hands
    /// what it heard to `said`, or calls `heardNothing`; with none set
    /// (headless), turning it off hears nothing.
    public var onListen: ((Bool) -> Void)?
    /// Whose button turned the mic on last: what it hears is theirs.
    var talker: Core.Talker = .app
    /// The `seq` of what you said, while its reply may still come: the
    /// first pass on it or anything newer ends `listening` on the device
    /// unless it queued a reaction, which is the reply.
    var replyFor: Int?
    var micTrouble: String?

    // Here and away. All on `home`.
    /// Decides whether you're at the Mac, from where the transcript left it.
    var presence = PresenceDetector()
    /// The idle time `{"dev":"presence","idle_ms":N}` set, read in place of
    /// the Mac's when there's no `idleMs`.
    var devIdleMs: Int64 = 0

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
        moodGraph = settings.moodGraph
        if moodGraph == .v3 {
            for path in ["guide-v3"] + MoodGraphV3.moods.map({ "mood/\($0)" }) + MoodGraph.moods.map({ "mood-v3/\($0)" }) where options.steering.files[path] == nil {
                throw SteeringError("\(path).md is missing for graph v3")
            }
        }
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
        // Who the device is, when it first says hello on a link or says
        // something new.
        link.onHello = { hello in DeviceInfo(hello).logLines.forEach(log) }

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        var config = Core.Config(volume: settings.volume, time: options.time, seed: longTerm.seed ^ UInt64(now))
        config.firstAsk = Core.randomFirstAsk()
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
        for over in options.steering.overBudget(version: moodGraph) { log("steering: over budget: \(over)") }

        // The actions' closures are only ever called on `home`, and reach
        // `self` once it's whole.
        var personalityNow: () -> Personality = { .default }
        var queued: (DeviceMoment, Pending) -> Void = { _, _ in }
        let link = self.link
        let reactions = Reactions()
        self.reactions = reactions
        (harness, mood) = Runtime.harness(
            pipeline: pipeline, steering: options.steering, personality: { personalityNow() }, reactions: reactions,
            queue: { queued($0, $1) }, speaks: { link.hello.map { DeviceInfo($0).hasTheVoice } ?? true },
            version: moodGraph, face: { link.hello.map { DeviceInfo($0).face } ?? .pixel })
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
        // The mood an older Boop kept in its own file.
        home.sync { MoodAction.carryOver(mood, stateDir: options.stateDir, harness: harness, version: moodGraph, note: log) }
        let logNow = transcript.view(now: now)
        core.restore(mood: MoodAction.value(mood, logNow, version: moodGraph))
        let questions = DebugLog.questions(Runtime.outputs(harness), log: logNow, at: now)
        emit(questions)
        launchOptions = DebugLog.options(questions)
        holding = false
        held.forEach(emit)
        if read > 0 { log("transcript: read back \(read) events") }
        presence = PresenceDetector(away: view.away(logNow))
        growth.follow(transcriptAt: transcript.lastSeq)
        personalityNow = { [weak self] in self?.personality ?? .default }
        queued = { [weak self] moment, pending in self?.queue(moment, pending) }
        // The device's taps and push-to-talk; the link leaves out those of
        // a device whose firmware doesn't fit.
        link.onEvent = { [weak self] ev in self?.deviceEvent(ev) }
        link.onHello = { [weak self] hello in
            DeviceInfo(hello).logLines.forEach(log)
            if let self, let latest = self.latest { self.show(latest) }
        }
        // A pass can change the mood, which the device and the menu bar show.
        harness.on(Event.did) { [weak self] e in
            guard e.action == MoodAction.actionName, e["ok"]?.bool == true, let to = e["to"]?.string else { return }
            self?.moodChanged(to)
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
    /// state: the guide with how to read the rest, PERSONALITY and
    /// MOOD, then HISTORY, closed by how long Boop has been in its mood and
    /// reaching back to the oldest working turn. The app's, and the evals',
    /// so the two can't drift apart. `queue` plays a reaction's moment,
    /// whose end `reactions` reads, and `speaks` says whether the device
    /// plays Voice's takes. The brain is the caller's to set (`harness.use`).
    public static func harness(pipeline: Pipeline, steering: Steering, personality: @escaping () -> Personality,
                               reactions: Reactions = Reactions(), queue: @escaping (DeviceMoment, Pending) -> Void,
                               speaks: @escaping () -> Bool = { true }, version: MoodGraph.Version = .v2,
                               face: @escaping () -> DeviceInfo.Face = { .pixel }) -> (harness: Harness, mood: Choice) {
        let h = pipeline.harness
        let core = pipeline.core
        let view = pipeline.view
        let mood = MoodAction.choice(version: version)
        // A reaction your tap cut short is in progress while the pokes go
        // on, and done once anything else happens.
        // A reaction's end, MellowHarness's own event, never stops the pokes.
        // The rule holds the log, not the harness, which holds the rule.
        let transcript = h.log
        h.on("*") { e in
            guard !reactions.cutByTap.isEmpty, TranscriptView.stopsThePokes(e, transcript.view(before: e)) else { return }
            reactions.pokesStopped()
        }
        let react = ReactAction(queue: queue, blocked: { core.reactionBlock }, who: { [weak h] now in
            // The thread's name as its agent's app shows it, once an event
            // brought one, else the view's: its workspace, else its project.
            // Weak: the harness holds this output.
            guard let h, let now, let key = TranscriptView.about(now, facts: h.line(now.seq)?.facts),
                  let who = view.who(about: key, h.log.view(now: h.clock.now())) else { return nil }
            return DeviceMoment.Who(agent: who.agent, thread: core.name(about: key) ?? who.thread, opens: core.thread(about: key))
        }, speaks: speaks, version: version, face: face)
        h.output(mood)
        h.output(react, openFor: ReactAction.openForMs, keepOpen: TranscriptView.heldByPokes)
        h.section { _ in steering.guide(for: version) + "\n" + EventLine.reading + "\n" + EventLine.words }
        h.section { _ in steering.personality(personality()).text }
        h.section { log in steering.mood(MoodAction.value(mood, log, version: version), version: version) }
        h.closing { _, now, log in MoodAction.sinceLine(mood, log, at: now, version: version) }
        h.reachBack { _, now, log in view.workingSince(at: now, log) }
        return (h, mood)
    }

    /// The outputs registered on `h`, in order: for `debug.jsonl`'s
    /// `questions` line.
    static func outputs(_ h: Harness) -> [any Action] { h.actions }

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

    /// The transport connected or dropped. On a drop the link fails every
    /// reaction still waiting for its `ended`, which HISTORY then says
    /// didn't happen, since that may never come. The
    /// device plays on, though, and the link may be back a second later,
    /// so a tap on a finish still playing still opens its thread.
    func connection(_ up: Bool) {
        let now = options.clock()
        // A new connection starts with the backwards-compatible bank. Clear
        // a former gel device's cached full mood before LinkKit sends state.
        if up, !link.connected, let latest { link.update(state: latest.fields(for: .pixel), now: now) }
        link.connection(up, now: now)
        if !up { run(core.linkDown(at: now)) }
        changed()
    }

    /// A line from the device: its `hello`, answered by the link with the
    /// latest `state`; an `ev` (`deviceEvent`); how a `do` ended, which
    /// the link hands to whoever asked for it, and which is logged here; or
    /// the `status` of Boop's firmware from before LinkKit, which is too
    /// old: it gets `state` but no `do`, and the popover says to flash it.
    func device(_ line: String) {
        let now = options.clock()
        // LinkKit replies to hello before its onHello callback. Adapt that
        // reply first, including a gel-to-pixel swap on the same transport.
        if let latest, let face = BoopDevice.face(saying: line) {
            link.update(state: latest.fields(for: face), now: now)
        }
        switch link.receive(line, now: now) {
        case .ended(let ended):
            options.log("device: do \(ended.id) ended \(ended.how.rawValue)" + (ended.why.map { " (\($0))" } ?? ""))
            emit(DebugLog.ended(ended, at: now))
            reactions.ended(ended.id)
        case .other:
            guard let old = BoopDevice.fromBeforeTheKit(line) else { break }
            if link.trouble != .tooOld { options.log("device: \(old.id) firmware \(old.fw)") }
            link.incompatible(.tooOld, now: now)
        default:
            break
        }
        changed()
    }

    /// A tap, or BOOT's push-to-talk.
    func deviceEvent(_ ev: DeviceEvent) {
        let now = options.clock()
        switch ev.kind {
        case "tap":
            if ev.did == "poked" || ev.did == "tap_spam" { onMoment?(0, DeviceMoment(anim: ev.did)) }
            let finish = BoopDevice.finish(tapped: ev)
            options.log("device: tap" + (ev.did.map { " (\($0))" } ?? "") + (finish.map { " on do \($0)" } ?? ""))
            // A poke. The device has already poked,
            // cutting the animation playing but not a reaction's line or face;
            // on the brain's finish that names whose turn it was it only
            // dipped, and the tap opens that thread.
            run(pipeline.poke(at: now, finish: finish.flatMap { reactions.opens(finish: $0) }))
        case "talk_on", "talk_off":
            options.log("device: \(ev.kind)")
            // The device already shows `listening`.
            run(core.listen(ev.kind == "talk_on", by: .device, at: now))
        default:
            break
        }
    }

    /// A `{"dev":…}` line from the socket (VERIFICATION.md §2):
    /// only with `devLines`. Nothing replies; what it did shows in
    /// `debug.jsonl`.
    func dev(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch object["dev"] as? String {
        case "advance":
            if let ms = (object["ms"] as? NSNumber)?.int64Value { advanceClock(ms) }
        case "answer":
            if let choices = object["answers"] as? [String: String] { forcePass(choices, by: Runtime.forcedBy) }
        case "mood":
            if let to = object["mood"] as? String { forceMood(to, by: Runtime.forcedBy) }
        case "said":
            // What push-to-talk heard, without a mic (VERIFICATION.md §2).
            guard let words = object["words"] as? String else { return }
            said(words, by: (object["by"] as? String).flatMap(Core.Talker.init(rawValue:)) ?? .app)
        case "tap":
            tapped()
        case "listen":
            if let on = object["on"] as? Bool { listen(on) }
        case "presence":
            // The Mac's signals and idle time, headless only: the app
            // reads the Mac's own.
            guard options.idleMs == nil else { return }
            if let ms = (object["idle_ms"] as? NSNumber)?.int64Value {
                devIdleMs = max(0, ms)
                options.log("dev: idle \(devIdleMs) ms")
            }
            if let signal = (object["signal"] as? String).flatMap(PresenceDetector.Signal.init(rawValue:)) {
                options.log("dev: presence \(signal.rawValue)")
                presenceSignal(signal)
            }
        case "report":
            saveReport { _ in }
        default:
            break  // such as boopdev replay's probe
        }
    }

    // What the socket's dev lines do, and a demo's beats (`play`). `who`
    // is which, for the log: `dev`, or `demo`.

    /// Moves the clock on, where it can be moved (headless).
    func advanceClock(_ ms: Int64, who: String = "dev") {
        guard ms > 0, let advance = options.advance else { return }
        advance(ms)
        options.log("\(who): clock advanced \(ms) ms")
        tick()
    }

    /// A forced pass: the actions keep their own rules. `by` is who the
    /// pass is by, in the transcript.
    func forcePass(_ choices: [String: String], by: String, who: String = "dev") {
        options.log("\(who): forced pass → " + Harness.ActionRecord.names(harness.force(choices, by: by)))
        changed()
    }

    /// The mood action's own change, which tells the device too.
    func forceMood(_ to: String, by: String, who: String = "dev") {
        let result = harness.force(mood, by: by) {
            MoodAction.change(mood, to: to, log: harness.log.view(now: options.clock()), version: moodGraph)
        }
        options.log("\(who): mood \(to)" + (result.map { $0.ok ? "" : ": \($0.message)" } ?? ""))
        changed()
    }

    /// What push-to-talk heard, after `by`'s button.
    func said(_ words: String, by: Core.Talker, who: String = "dev") {
        talker = by
        heard(words)
        options.log("\(who): said \(words.count) characters")
    }

    /// A tap on the device, without one.
    func tapped(who: String = "dev") {
        options.log("\(who): tap")
        run(pipeline.poke(at: options.clock()))
        changed()
    }

    /// The app's mic button.
    func listen(_ on: Bool, who: String = "dev") {
        run(core.listen(on, at: options.clock()))
        options.log("\(who): listen \(on)")
    }

    func tick() {
        let now = options.clock()
        core.setWallClock(options.wallClock(), at: now)
        run(pipeline.tick(at: now))
        // A mood whose change has aged out of the log is calm there, and
        // on the device too.
        if moodNow != core.config.mood { moodChanged(moodNow) }
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

    /// The mood action saved a new mood: the device draws it from the next
    /// `state`.
    func moodChanged(_ mood: String) {
        run(core.setMood(mood, at: options.clock()))
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
                listen(on, by: by)
                stateChanged = true
            case .moment(let moment):
                playRule(moment)
            case .open(let thread):
                open(thread, by: "tap")
            }
        }
        if stateChanged || grew { changed() }
    }

    /// The core turned the mic on or off. On: after
    /// the app's button the device is told to show `listening` at once,
    /// and it drops the reactions waiting there, since one would end it
    /// (the device's own button does both itself). Off: what the mic heard
    /// comes back to `said` or `heardNothing`.
    func listen(_ on: Bool, by: Core.Talker) {
        options.log("talk: mic \(on ? "on" : "off") (\(by.rawValue))")
        guard on else {
            if onListen != nil { onListen?(false) } else { heardNothing() }
            return
        }
        talker = by
        micTrouble = nil
        replyFor = nil
        if by == .app {
            if let id = link.do(BoopDevice.listening, play: .now, by: .rule, now: options.clock(), { _ in }) {
                onMoment?(id, DeviceMoment(anim: BoopDevice.listening))
            }
        } else {
            // The device's button already started this local visual.
            onMoment?(0, DeviceMoment(anim: BoopDevice.listening))
        }
        onListen?(true)
    }

    /// What the mic heard: an event that wakes the brain, whose pass
    /// replies or ends `listening` (`replied`). With no brain to wake, no
    /// reply is coming, so `listening` ends at once.
    func heard(_ words: String) {
        let step = pipeline.said(words, by: talker, at: options.clock())
        run(step)
        if let v = step.waking.first {
            replyFor = v.seq
        } else {
            endListening()
        }
    }

    /// The first pass on what you said, or on anything newer, is over: if
    /// it queued no reaction, none is coming, so `listening` ends now.
    func replied(_ pass: Harness.Pass) {
        guard let seq = replyFor, let e = pass.event, e.seq >= seq else { return }
        replyFor = nil
        if !pass.actions.contains(where: { $0.name == ReactAction.actionName && $0.result.ok }) { endListening() }
    }

    /// Who forces passes and actions, for no event: the dashboard's.
    public static let forcedBy = "dashboard"

    /// Boop's mood now, as the log has it.
    var moodNow: String { MoodAction.value(mood, harness.log.view(now: options.clock()), version: moodGraph) }

    /// Every pass the harness made: its app log line
    /// (the brain's only), whether the brain is in trouble, its
    /// `debug.jsonl` lines, and what it means for push-to-talk's reply.
    func passed(_ pass: Harness.Pass) {
        let now = options.clock()
        if let line = Runtime.logLine(pass) { options.log(line) }
        if pass.prompt != nil, pass.current {
            // Only a pass that asked the brain in use says how it's doing.
            (droppedInARow, trouble) = BrainTrouble.after(pass.error, previous: droppedInARow)
        }
        // The head is logged only when it changes; the pass, HISTORY and NOW.
        debugWriter?.pass(pass, launchOptions: launchOptions, at: now)
        replied(pass)
        changed()
    }

    /// The app log's line for a pass the brain was asked, or held back for:
    /// its event's type and phase, the time and which actions returned
    /// a result, never their messages. Nil for a forced pass.
    static func logLine(_ pass: Harness.Pass) -> String? {
        guard let e = pass.event else { return nil }
        let result = pass.dropped.map { "dropped: \($0)" } ?? pass.held.map { "held: \($0)" }
            ?? Harness.ActionRecord.names(pass.actions)
        return "brain \(e.name) \(pass.latencyMs) ms → " + result
    }

    /// Ends `listening` on the device with `stop_listening`, which ends
    /// nothing else.
    func endListening() {
        core.listeningEnded()
        if let id = link.do(BoopDevice.stopListening, play: .ifFree, by: .rule, now: options.clock(), { _ in }) {
            onMoment?(id, DeviceMoment(anim: BoopDevice.stopListening))
        }
    }

    var deviceFace: DeviceInfo.Face { link.hello.map { DeviceInfo($0).face } ?? .pixel }

    /// A snapshot for the device.
    func show(_ snapshot: StateSnapshot) {
        latest = snapshot
        link.update(state: snapshot.fields(for: deviceFace), now: options.clock())
    }

    /// A rule's one-shot: sent at once, after the
    /// `state` of the same input, to play only if the device's turn is free
    /// or resting (`if_free`): a brain reaction's line holding it would be
    /// cut, and a late one-shot is worse than none, so the device skips it
    /// then. The core has already left it out while something needs you or
    /// `listening` shows.
    func playRule(_ moment: DeviceMoment) {
        if let id = link.do(moment.name, args: moment.args(for: deviceFace), play: .ifFree, by: .rule, now: options.clock(), { _ in }) {
            onMoment?(id, moment)
        }
    }

    /// A reaction from the brain, sent at once to wait its turn on the
    /// device (`next`, for up to 5 s), and its handle, ended once it's
    /// known how it went (read Boop's way by `Reactions`): at once when it
    /// can't be sent. On `home`.
    func queue(_ moment: DeviceMoment, _ pending: Pending) {
        core.listeningEnded()  // a reaction ends `listening`: it's the reply
        let now = options.clock(), reactions = reactions
        let id = link.do(moment.name, args: moment.args(for: deviceFace), play: .next, ttl: BoopDevice.reactionTTL, by: .brain,
                         now: now) { outcome in
            if let end = reactions.read(outcome, pending) { pending.finish(end) }
        }
        if let id { onMoment?(id, moment) }
        if let id, let thread = moment.who?.opens { reactions.sent(id, opens: thread, ttl: BoopDevice.reactionTTL, now: now) }
    }

    func changed() {
        let now = options.clock()
        let status = Status(name: name, snapshot: latest ?? core.snapshot(at: now), sessions: core.sessionList(at: now),
                            connected: link.connected, device: link.hello.map(DeviceInfo.init), linkTrouble: linkTrouble,
                            deviceTrouble: link.trouble?.description, personality: personality, brain: harness.brain?.id ?? "none",
                            keyRead: jevKey != nil, brainTrouble: trouble, listening: core.listening != nil,
                            micTrouble: micTrouble, growth: growth.growth, faceListening: core.showsListening(at: now))
        grew = false
        if let line = DebugLog.status(status, at: now, last: &lastStatus) { emit(line) }
        onChange?(status)
    }

    /// The last `status` line written to `debug.jsonl`, without its time.
    var lastStatus: String?
    /// This launch's debug lines outside debug mode, for `saveReport`: in
    /// debug mode the file has them.
    let recent: DebugLog.Recent
    /// Every `debug.jsonl` line goes through this: in debug mode written to
    /// the file and printed readably, and otherwise kept in `recent`.
    let emit: (String) -> Void

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

    /// The app's mic button: start or stop listening.
    public func setListening(_ on: Bool) {
        home.async { [self] in run(core.listen(on, at: options.clock())) }
    }

    /// What push-to-talk heard, once the mic is off.
    public func said(_ words: String) {
        home.async { [self] in heard(words) }
    }

    /// The mic went off and heard nothing: no reply is coming.
    public func heardNothing() {
        home.async { [self] in
            options.log("talk: heard nothing")
            endListening()
        }
    }

    /// The mic or speech recognition couldn't start, and why, for the
    /// popover: `listening` ends at once, after either button.
    public func micFailed(_ why: String) {
        home.async { [self] in
            options.log("talk: \(why)")
            micTrouble = why
            endListening()
            changed()
        }
    }

    /// A lock, unlock, sleep or wake from the Mac, for the presence
    /// detector.
    public func presence(_ signal: PresenceDetector.Signal) {
        home.async { [self] in presenceSignal(signal) }
    }

    /// The popover's "can't hear you" notice was dismissed.
    public func dismissMicTrouble() {
        home.async { [self] in
            micTrouble = nil
            changed()
        }
    }

    /// Drops the device link and looks for the device again now.
    public func reconnectDevice() {
        link.transport?.reconnect()
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

    /// Jev's key as Settings just saved it (nil when it was cleared);
    /// `BOOP_JEV_KEY` still wins. Used from the next event.
    public func reloadBrain(jevKey key: String?) {
        home.async { [self] in
            jevKey = .some(options.readJevKey { key })
            useBrain()
            changed()
        }
    }

    /// The brain for Jev's key as far as it's been read. On `home`.
    func useBrain() {
        let brain = options.brain(jevKey ?? nil)
        harness.use(brain)
        pipeline.brain = brain != nil
        trouble = nil
        droppedInARow = 0
        options.log("brain \(brain?.id ?? "none")" + (brain == nil ? ": no Jev key, so Boop does only its rule reactions" : ""))
    }

    /// Reads Jev's key off `home`: a Keychain prompt
    /// there would stall every hook, tick and device line until it's
    /// answered. Then the brain is built with it. On `home`.
    func readJevKey() {
        guard jevKey == nil else { return }
        let read = options.readJevKey
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let key = read { Keychain.jevKey() }
            self?.home.async { [weak self] in
                // Settings may already have installed a brain while the
                // startup read waited. Keep that brain too: rebuilding it
                // would discard any pass it has in flight.
                guard let self, jevKey == nil else { return }
                jevKey = .some(key)
                useBrain()
                changed()
            }
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
