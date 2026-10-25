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
        /// Narrows the board's Bluetooth transport to the one advertised
        /// name (`Boop-54FE`), or widens it again for nil: remembering the
        /// board, and forgetting it. Nil with no Bluetooth.
        public var chooseBoard: (@Sendable (String?) -> Void)?
        /// Where macOS keeps crash reports, which a bug report copies
        /// Boop's from.
        public var crashReports = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs/DiagnosticReports")
        /// Every message sent to the device, as it's sent, for whoever
        /// records them (`DemoRecorder`). On whichever thread sends it.
        public var onDeviceLine: (@Sendable (String) -> Void)?
        /// Opens a thread on the Mac (`ThreadLink`): a tap while something
        /// needs you, or a click in the popover. Tests pass their own.
        public var open: @Sendable (ThreadLink.Target) -> Bool = ThreadLink.openOnMac
        /// The buddies, each on its own board with its own pack. Empty runs
        /// the one buddy, the process's character, on `link` with
        /// `steering`, as Boop always has.
        public var buddies: [BuddyOptions] = []
        /// Labels your prompts on the Mac: the menu-bar app's is Apple
        /// Intelligence on macOS 26, which labels while it's on. None
        /// (headless's unless it asks, and the tests') counts them only.
        public var labeler: (any PromptLabeler)?

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
    /// Each buddy's board as it runs, the first first.
    var rigs: [Rig] = []
    /// The buddies, the first first.
    public var buddies: [Buddy] { pipeline.buddies }
    /// LinkKit's link to the first buddy's device, in Boop's vocabulary
    /// (`BoopDevice`).
    public var link: DeviceLink { rigs[0].link }
    /// The newest snapshot sent to the first buddy's device.
    public var latest: StateSnapshot? { rigs[0].latest }
    /// Boop's name, from `long-term.md`.
    public let name: String
    /// Boop's memory: long-term.md, read at launch, and the diary, which
    /// the brain's diary output writes a line to each day.
    public let memory: MemoryStore
    public private(set) var settings: AppSettings
    /// The personality running now, touched only on `home`. Starts as the
    /// saved one, unless this run overrides it.
    public private(set) var personality: Personality
    /// The first buddy's core.
    var core: Core { pipeline.core }
    let view: TranscriptView
    let pipeline: Pipeline
    /// MellowHarness's `Harness`: Boop's brain.
    let harness: Harness
    /// The first buddy's mood, MellowHarness's `Choice`.
    var mood: Choice { rigs[0].mood }
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
    /// `running` is in the state directory from `start` to `stop`, so one
    /// still there at the next launch means Boop crashed or was killed.
    public static let runningFile = "running"
    /// The last run didn't stop cleanly, until the person closes the
    /// notice. Touched only on `home`.
    var uncleanExit: Bool
    var server: HookServer?
    var timer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then no event wakes the brain.
    var jevKey: String??
    /// The brain's reactions on the first buddy's device until each ends:
    /// the device decides when each plays.
    var reactions: Reactions { rigs[0].reactions }
    /// The first buddy's transport's `trouble` as the status last had it.
    var linkTrouble: TransportTrouble? { rigs[0].linkTrouble }
    /// Whether the Mac's mic is on, which several buddies' cores may ask
    /// for at once, and the buddy whose board's button turned it on last:
    /// what it hears is said to that one.
    var micOn = false
    var listener: Rig?
    /// Boop's XP and stage, counted from each event as it's logged,
    /// and whether the XP changed since the last status.
    let growth: GrowthStore
    var grew = false
    /// The last `status` line written to `debug.jsonl`, without its time.
    var lastStatus: String?
    /// The diary's last week as the popover shows it, kept while neither
    /// the diary nor the day changes.
    var shownDiary: (week: [(day: String, line: String)], today: String, lines: [Status.DiaryLine])?
    /// This launch's debug lines outside debug mode, for `saveReport`: in
    /// debug mode the file has them.
    let recent: DebugLog.Recent
    /// Every `debug.jsonl` line goes through this: in debug mode written to
    /// the file and printed readably, and otherwise kept in `recent`.
    let emit: (String) -> Void

    /// After every change the menu bar might show. Called on `home`.
    public var onChange: ((Status) -> Void)?
    /// What the first buddy's board plays, for the Mac's mirror of it: each
    /// reaction sent, with its id and play, and the board's own (a tap's
    /// poke, push-to-talk's `listening`), with id 0 and `now`. Never
    /// completes a handle.
    public var onReaction: ((Int, DeviceReaction, Wire.Play) -> Void)?

    /// A tap on the board, after the core has taken it: true for its
    /// button (BOOT), false for its screen. Onboarding's pairing and its
    /// lessons listen. On `home`.
    public var onTap: ((_ button: Bool) -> Void)?
    /// An agent's hook that became an event, by the agent's name
    /// (`claude`, `codex`): onboarding's live hello listens. On `home`.
    public var onAgentHook: ((String) -> Void)?

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
    /// Labels your prompts: the options', or a demo's script in front of it.
    lazy var labeler: (any PromptLabeler)? = options.labeler

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
        // Read under the lock: another copy's marker is never this one's.
        uncleanExit = FileManager.default.fileExists(atPath: options.stateDir.appendingPathComponent(Self.runningFile).path)
        let log = options.log
        let wall = options.wallClock(), wallAt = options.clock()
        let today = options.time.day(wall)
        let memory = try MemoryStore(directory: options.stateDir, today: today, log: log)
        guard let longTerm = memory.longTerm else { throw OpenError.notSetUp }
        self.memory = memory
        name = longTerm.name
        settings = AppSettings.load(from: options.stateDir)
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

        let now = options.clock()
        personality = options.personality ?? settings.personality
        let rules = options.steering.personality(personality).rules
        let places = self.places
        // The only buddy goes by the name you gave it, in what it hears and
        // what it counts as its name.
        let plans = options.buddies.isEmpty
            ? [BuddyOptions(buddy: .only(CharacterPack.active.named(longTerm.name)), link: options.link, steering: options.steering)]
            : options.buddies
        let several = plans.count > 1
        rigs = plans.map { Rig($0, tag: several ? $0.buddy.id : nil, log: log) }
        for rig in rigs {
            // boop.log leaves out a `state` sent again unchanged (the keepalive,
            // a reply to `hello`), which debug.jsonl keeps.
            var lastState: String?
            let sent = options.onDeviceLine, whose = Runtime.whose(rig)
            rig.link.onSend = { line, sender in
                sent?(line)
                emit(DebugLog.sent(line, by: sender, at: clock()))
                guard debugLog != nil, line != lastState else { return }
                if line.hasPrefix(#"{"t":"state""#) { lastState = line }
                log("link\(whose) \(sender == .brain ? "brain" : "rules") → " + line)
            }
            for over in rig.steering.overBudget(in: rig.buddy.pack) { log("steering\(whose): over budget: \(over)") }
        }
        // Each buddy's core, its own seed apart. The launch's read-back
        // prunes the transcript, so today isn't a new day.
        let volume = settings.volume
        let cores = plans.enumerated().map { i, plan in
            var config = Core.Config(volume: volume, time: options.time, pack: plan.buddy.pack, hatched: longTerm.hatched)
            config.firstAsk = SessionTracker.randomFirstRequest()
            let core = Core(config: config, lastActiveDay: today, place: places.place, isRunning: Runtime.agentRuns)
            core.setWallClock(wall, at: wallAt)
            return (plan.buddy, core)
        }
        view = TranscriptView(rules: rules, seed: longTerm.seed ^ UInt64(now), place: places.place)
        let transcript = Transcript.log(folder: options.stateDir.appendingPathComponent(Transcript.folderName),
                                        time: options.time, note: log)
        pipeline = Pipeline(cores, view: view, transcript: transcript, time: options.time,
                            clock: Harness.Clock(now: options.clock, wall: options.wallClock), queue: home, note: log)
        pipeline.brain = false  // until Jev's key is read
        harness = pipeline.harness

        // The outputs' closures are only ever called on `home`, and reach
        // `self` once it's whole.
        var personalityNow: () -> Personality = { .default }
        var queued: (Rig, DeviceReaction, Pending) -> Void = { _, _, _ in }
        let rigs = self.rigs
        let moods = Runtime.brain(pipeline, rigs.map { rig in
            let link = rig.link, pack = rig.buddy.pack
            // Each buddy speaks its own pack's personality of the saved
            // name, or its first. Only the first is the one long-term.md
            // set up.
            return Mind(buddy: rig.buddy, steering: rig.steering, personality: { Personality(personalityNow().rawValue, in: pack) },
                        reactions: rig.reactions, queue: { queued(rig, $0, $1) },
                        speaks: { link.hello.map { DeviceInfo($0).hasTheVoice } ?? true },
                        nature: rig === rigs[0] ? longTerm.nature : nil,
                        diary: rig === rigs[0] ? { day, line in
                            // The pass that wrote it changes the popover.
                            do { try memory.appendDiary(day: day, line: line) } catch { log("diary: can't write: \(error)") }
                        } : nil)
        })
        for (rig, mood) in zip(rigs, moods) { rig.mood = mood }
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
        // The view and the cores pick up where the last launch left them.
        let pipeline = self.pipeline
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
        // The cores read the growth stage where the growth store keeps it.
        // Weak: the runtime holds the cores.
        for rig in rigs { core(rig).stage = { [weak self] in self?.growth.growth.stage ?? 1 } }
        if let day = growth.reachedDay { for rig in rigs { core(rig).reachedStage(growth.growth.name, day: day, at: now) } }
        personalityNow = { [weak self] in self?.personality ?? .default }
        queued = { [weak self] rig, reaction, pending in self?.queue(reaction, pending, on: rig) }
        for rig in rigs {
            // The core reads the mood where the mood output keeps it. Weak:
            // the harness holds the core.
            let mood = rig.mood!
            core(rig).mood = { [weak harness = self.harness] in
                harness.map { MoodOutput.value(mood, $0.log.view(now: clock())) } ?? mood.start
            }
            // The device's taps and push-to-talk; the link leaves out those
            // of a device whose firmware doesn't fit.
            rig.link.onEvent = { [weak self] ev in self?.deviceEvent(ev, on: rig) }
            // A hello (the first on a link, or one that says something new):
            // log who the device is, and show it what's true now.
            let whose = rig.tag.map { "\($0): " } ?? ""
            rig.link.onHello = { [weak self] hello in
                DeviceInfo(hello).logLines.forEach { log(whose + $0) }
                if let self, let latest = rig.latest { self.show(latest, on: rig) }
            }
        }
        // A pass can change a mood, which its device and the menu bar show.
        harness.on(Event.did) { [weak self] e in
            guard let self, e.action == MoodOutput.outputName, e["ok"]?.bool == true else { return }
            let rig = rig(e.buddy)
            run(core(rig).moodChanged(at: options.clock()), on: rig)
        }
        harness.onPass = { [weak self] pass in self?.passed(pass) }
        // Every event as it's logged, never the read-back's: those were counted.
        harness.on("*") { [weak self] e in
            guard let self else { return }
            let before = growth.growth.stage, now = options.clock()
            guard growth.count(e, day: options.time.day(options.wallClock())) else { return }
            grew = true
            // A stage reached makes the rest of the day a party.
            if growth.growth.stage > before {
                for rig in rigs { run(core(rig).reachedStage(growth.growth.name, at: now), on: rig) }
            }
        }
    }

    /// Boop's brain for one buddy, the process's character (`brain`): the
    /// evals' and the tests'. `queue` plays a reaction, whose end
    /// `reactions` reads, and `speaks` says whether the device plays
    /// Voice's takes.
    public static func harness(pipeline: Pipeline, steering: Steering, personality: @escaping () -> Personality,
                               reactions: Reactions = Reactions(), queue: @escaping (DeviceReaction, Pending) -> Void,
                               speaks: @escaping () -> Bool = { true }, nature: LongTerm.Nature? = nil,
                               diary: @escaping (String, String) -> Void = { _, _ in }) -> (harness: Harness, mood: Choice) {
        let mind = Mind(buddy: pipeline.buddies[0], steering: steering, personality: personality, reactions: reactions,
                        queue: queue, speaks: speaks, nature: nature, diary: diary)
        return (pipeline.harness, brain(pipeline, [mind])[0])
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
        if uncleanExit { options.log("boop: the last run didn't stop cleanly (crashed, or was killed)") }
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
        // Only once it runs: a start that failed isn't a crash.
        FileManager.default.createFile(atPath: options.stateDir.appendingPathComponent(Self.runningFile).path, contents: nil)
        for rig in rigs {
            rig.transport?.start(
                onLine: { [weak self] line in self?.home.async { self?.device(line, on: rig) } },
                onConnection: { [weak self] up in self?.home.async { self?.connection(up, on: rig) } })
        }
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
                        + "link \(rigs.map { ($0.tag.map { "\($0) " } ?? "") + ($0.transport?.name ?? "none") }.joined(separator: ", ")), "
                        + "personality \(personality.rawValue), "
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
        for rig in rigs { rig.transport?.stop() }
        try? FileManager.default.removeItem(at: options.stateDir.appendingPathComponent(Self.runningFile))
    }

    /// Onboarding's greetings on the board, which it plays as a rule's
    /// reaction (only if nothing else plays, and never while something
    /// needs you), recorded in the transcript as the rules' others are, and
    /// waking no brain: Boop waking into its body once it's paired, and a
    /// celebration for the first hook and the finale.
    public enum Greeting: Sendable {
        case wake, celebrate
        var reaction: DeviceReaction {
            switch self {
            case .wake: DeviceReaction(anim: "wake_up")
            case .celebrate: DeviceReaction(anim: "task_complete", outcome: "success")
            }
        }
    }

    public func greet(_ greeting: Greeting) {
        home.async { [self] in
            options.log("onboarding: \(greeting.reaction.name) on the board")
            run(core(rigs[0]).greet(greeting.reaction, at: options.clock()), on: rigs[0])
        }
    }

    /// Lets go of the remembered board: Boop takes any over Bluetooth
    /// again, and remembers the next one tapped.
    public func forgetBoard() {
        home.async { [self] in
            guard let board = settings.board else { return }
            saveSettings { $0.board = nil }
            options.log("device: forgot \(board); taking any board over Bluetooth")
            options.chooseBoard?(nil)
            changed()
        }
    }

    /// Closes the "stopped unexpectedly" notice.
    public func dismissUncleanExit() {
        home.async { [self] in
            uncleanExit = false
            changed()
        }
    }

    // MARK: Inputs (on `home`)

    func hook(_ line: HookLine, received: Int64) {
        demoHeard?(line)
        // Your prompt and the agent's last message go no further than the
        // intake: the turn event is logged without it, and its reading follows.
        let (event, text) = Adapter.event(from: line, receivedAt: received).map(PromptIntake.split) ?? (nil, nil)
        // Debug mode logs every hook with what it became; the doctor skill
        // arms the plain line to see hooks arrive. Otherwise hooks aren't logged.
        if options.debug {
            options.log("hook: \(line.agent) \(line.hook) \(line.session) → " + (event?.summary ?? "ignored"))
        } else if doctorArmed() {
            options.log("hook: \(line.agent) \(line.hook) \(line.session)")
        }
        guard let event else { return }
        let step = pipeline.agent(event)
        run(step)
        onAgentHook?(line.agent)
        guard let text, let turn = step.recorded.first else { return }
        // The hook's words don't wait with the reading: only its agent and
        // session do, for the log.
        let agent = line.agent, session = line.session
        PromptIntake.read(text, names: pipeline.buddies.map(\.name), labeler: labeler, home: home) { [weak self] reading in
            guard let self else { return }
            guard let step = pipeline.read(reading, about: turn, at: options.clock()) else {
                return options.log("\(reading.kind.rawValue): \(agent)'s session \(session) moved on before its reading; dropped it")
            }
            run(step)
        }
    }

    func tick() {
        let now = options.clock()
        core.setWallClock(options.wallClock(), at: now)
        run(pipeline.tick(at: now))
        if let e = presence.tick(at: now, idleMs: options.idleMs?() ?? devIdleMs) { recordPresence(e) }
        // The keepalive, and the reactions whose `ended` never came.
        var troubled = false
        for rig in rigs {
            rig.link.tick(now: now)
            rig.reactions.tick(now: now)
            let trouble = rig.link.transport?.trouble
            if trouble != rig.linkTrouble {
                rig.linkTrouble = trouble
                troubled = true
            }
        }
        if troubled { changed() }
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

    /// Carries out a core's effects from a call outside the pipeline: the
    /// first buddy's, or `rig`'s.
    func run(_ effects: [CoreEffect], on rig: Rig? = nil) {
        run(pipeline.effects(effects, buddy: rig?.tag, at: options.clock()))
    }

    /// Carries out what an input did: the core's
    /// effects (its records are in the transcript already), then a pass
    /// for each view event that wakes the brain.
    func run(_ step: Pipeline.Step) {
        var stateChanged = false
        for (buddy, effect) in step.tagged {
            let rig = rig(buddy)
            switch effect {
            case .state(let snapshot):
                show(snapshot, on: rig)
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
                playRule(reaction, on: rig)
            case .open(let thread):
                open(thread, by: "tap")
            }
        }
        if stateChanged || grew { changed() }
    }

    /// Changes the settings here and in `settings.json`, keeping what
    /// onboarding saved there since (`AppSettings.update`).
    func saveSettings(_ change: (inout AppSettings) -> Void) {
        do { settings = try AppSettings.update(in: options.stateDir, change) } catch {
            change(&settings)
            options.log("settings: can't save: \(error)")
        }
    }

    // MARK: From the menu bar (any thread)

    /// Opens `thread` where it runs: a session clicked in the popover.
    public func openThread(_ thread: ThreadRef) {
        home.async { [self] in open(thread, by: "click") }
    }

    /// Stops `thread`'s request numbered `request` showing, the one the
    /// card showed: the popover's Dismiss (`Core.dismiss`), on whichever
    /// buddy shows it.
    public func dismiss(_ thread: ThreadRef, request: Int) {
        home.async { [self] in
            guard let agent = Agent(rawValue: thread.agent) else { return }
            let key = SessionFold.key(agent, thread.session), now = options.clock()
            for rig in rigs { run(pipeline.dismiss(key, request: request, at: now, buddy: rig.tag)) }
        }
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
            for rig in rigs { run(core(rig).setVolume(volume, at: options.clock()), on: rig) }
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
