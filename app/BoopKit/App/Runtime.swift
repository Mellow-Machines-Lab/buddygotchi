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
        /// Override how much it says in `settings.json` for this run only.
        public var talk: Talk?
        /// Override whether it may swear in `settings.json`, for this run
        /// only: a demo swears as it was written to.
        public var swearing: Bool?
        /// Builds the brain from Jev's key; nil for no brain. Tests pass
        /// their own.
        public var brain: @Sendable (String?) -> (any Brain)? = { key in key.map { JevBrain(key: $0) } }
        public var time = LocalTime()
        /// Milliseconds for every duration: a steady clock by default.
        public var clock: @Sendable () -> Int64 = Runtime.steadyClock()
        /// Milliseconds since 1970, for days and times of day.
        public var wallClock: @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
        /// Accept `{"dev":…}` lines on the hook socket: headless, or debug
        /// mode. Boop.app, with neither, stays deaf to them.
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
        /// Seconds since the last key press, in ms, for your hands
        /// (`Hands`): a number, never the keys. Nil, the dev line's.
        public var keyIdleMs: (@Sendable () -> Int64)?
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
        /// Boop full size whatever its XP, for a demo: from before the
        /// first `state`, which goes out before a demo's first step.
        public var fullSize = false
        /// The world's server (`WorldClient.url()`); nil for no world at all,
        /// as in tests, which never reach the live one.
        public var worldURL: URL?
        /// Opens a thread on the Mac (`ThreadLink`): a tap while something
        /// needs you, or a click in the popover. Tests pass their own.
        public var open: @Sendable (ThreadLink.Target) -> Bool = ThreadLink.openOnMac
        /// Labels your prompts on the Mac: the menu-bar app's is Apple
        /// Intelligence on macOS 26, which labels while it's on. None
        /// (headless's unless it asks, and the tests') counts them only.
        public var labeler: (any PromptLabeler)?
        /// Whether push-to-talk works now, the recognizer and the mic both
        /// authorized, for the chat wish: the app and headless ask macOS.
        public var pushToTalkWorks: @Sendable () -> Bool = { true }

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
    /// Set on `home`, so `stop` can tell it's already there: a demo's end is.
    private let onHome = DispatchSpecificKey<Bool>()
    public let options: Options
    /// The buddy's board as it runs.
    let rig: Rig
    /// The buddy.
    public var buddy: Buddy { pipeline.buddy }
    /// LinkKit's link to the buddy's device, in Boop's vocabulary
    /// (`BoopDevice`).
    public var link: DeviceLink { rig.link }
    /// The newest snapshot sent to the device.
    public var latest: StateSnapshot? { rig.latest }
    /// Boop's name, from `long-term.md`.
    public let name: String
    /// Boop's long-term memory: long-term.md, read at launch.
    public let memory: MemoryStore
    /// The readers of the transcript (`Memory`): the day's tallies and
    /// journal, and the dream they make. Nil when the key-value store fell
    /// back to memory for this launch: then no reader runs.
    public private(set) var remembers: Memory?
    /// The key-value store growth and memory keep their rows in; it keeps
    /// an away's start too (`PresenceDetector.awayKey`).
    var keyValues: KeyValueStore?
    /// Boop's buddy in the world, with a world server to talk to.
    var world: WorldLink?
    public private(set) var settings: AppSettings
    /// How much it says now (`Talk`), touched only on `home`.
    public private(set) var talk: Talk
    /// The buddy's core.
    var core: Core { pipeline.core }
    let view: TranscriptView
    let pipeline: Pipeline
    /// MellowHarness's `Harness`: Boop's brain.
    let harness: Harness
    /// The buddy's mood, MellowHarness's `Choice`.
    var mood: Choice { rig.mood }
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
    var handsTimer: DispatchSourceTimer?
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then no event wakes the brain.
    var jevKey: String??
    /// The transport's `trouble` as the status last had it.
    var linkTrouble: TransportTrouble? { rig.linkTrouble }
    /// Whether the Mac's mic is on.
    var micOn = false
    /// What a demo's mic hears as its button is let go: the words come once
    /// the mic is off, as speech's do.
    var wordsOnRelease: String?
    /// A demo script plays: its brain steps answer what you say, so a
    /// runtime with no brain doesn't shrug at it.
    var playingDemo = false
    /// Boop's XP, level and today's ring, counted from each event as it's
    /// logged, and whether the XP changed since the last status.
    let growth: GrowthStore
    var grew = false
    /// The XP moved during an input, which its step still has to carry out.
    var xpMoved = false
    /// A level or the ring was reached during an input: its moment plays
    /// once the step is carried out, not inside it, where the moment's own
    /// effects would join the step and be carried out twice.
    var growthDue = false
    /// The level and ring events just logged, whose one moment is about to
    /// go to the board; and when the board last missed one, so the next XP
    /// doesn't try again at once (`growthRetryMs`).
    var celebrating: [Event] = []
    var growthMissedAt: Int64?
    static let growthRetryMs: Int64 = 60_000
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
    /// The first buddy's board, for the Mac's mirror of it, which never
    /// completes a handle. On `home`, in order:
    ///
    /// - `onBoardLine`: every message its link sends it, as it's sent:
    ///   each `state`, the keepalive and `hello`'s answer included, and
    ///   each `do`.
    /// - `onBoardTap`: a tap on its screen or BOOT (`button`), which it
    ///   reacted to by itself, and the mirror takes as its own.
    /// - `onBoardListening`: push-to-talk on its BOOT, which shows
    ///   `listening` by itself, with no message to say so.
    public var onBoardLine: ((String) -> Void)?
    public var onBoardTap: ((_ button: Bool) -> Void)?
    public var onBoardListening: (() -> Void)?

    /// A tap on the board, after the core has taken it: `button` for its
    /// button (BOOT), else its screen, and `onFinish` when it landed on a
    /// finish that names whose turn it was, which opens that thread.
    /// Onboarding's pairing, its lessons and its tour listen. On `home`.
    public var onTap: ((_ button: Bool, _ onFinish: Bool) -> Void)?
    /// The board's agents' drawer opened (`open`), or a row in it was
    /// picked (`pick`): onboarding's tour listens. On `home`.
    public var onDrawer: ((String) -> Void)?
    /// An agent's hook that became an event, by the agent's name
    /// (`claude`, `codex`): onboarding's live hello listens. On `home`.
    public var onAgentHook: ((String) -> Void)?
    /// What push-to-talk heard once the mic is off, or nil for nothing:
    /// onboarding's talk lesson listens. On `home`.
    public var onHeard: ((String?) -> Void)?

    /// Push-to-talk: turns the Mac's mic on (true) or off, as the core
    /// says. Once it's off, the app hands what it heard to `said`, or calls
    /// `heardNothing`; with none set (headless), turning it off hears
    /// nothing. The core keeps push-to-talk's state (`Core.Listening`). On `home`.
    public var onListen: ((Bool) -> Void)?

    // Here and away. All on `home`.
    /// Decides whether you're at the Mac, from where the transcript left it.
    var presence = PresenceDetector()
    /// The idle time `{"dev":"presence","idle_ms":N}` set, read in place of
    /// the Mac's when there's no `idleMs`.
    var devIdleMs: Int64 = 0
    /// The time since the last key `{"dev":"presence","key_idle_ms":N}`
    /// set, read in place of the Mac's when there's no `keyIdleMs`; none
    /// until a dev line says one, so a headless run has no hands.
    var devKeyIdleMs: Int64?
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

    /// Sets up a new Boop: its name, asked once.
    /// It hatches `today`, by default the Mac's.
    public static func setUp(stateDir: URL, name: String,
                             today: String = LocalTime().day(Int64(Date().timeIntervalSince1970 * 1000))) throws {
        let store = try MemoryStore(directory: stateDir)
        try store.setUp(name: name, seed: UInt64.random(in: 1...0xFFFF), today: today)
    }

    public init(_ options: Options) throws {
        home.setSpecific(key: onHome, value: true)
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
        talk = options.talk ?? settings.talk
        let rules = options.steering.rules(talk: talk)
        let places = self.places
        // The only buddy goes by the name you gave it, in what it hears and
        // what it counts as its name.
        let buddy = Buddy.only(CharacterPack.active.named(longTerm.name))
        let rig = Rig(link: options.link, steering: options.steering, log: log)
        self.rig = rig
        // The board's lines go to its mirror too, once `self` is whole.
        var mirror: (String) -> Void = { _ in }
        do {
            // boop.log leaves out a `state` sent again unchanged (the keepalive,
            // a reply to `hello`), which debug.jsonl keeps.
            var lastState: String?
            let sent = options.onDeviceLine
            rig.link.onSend = { line, sender in
                sent?(line)
                mirror(line)
                emit(DebugLog.sent(line, by: sender, at: clock()))
                guard debugLog != nil, line != lastState else { return }
                if line.hasPrefix(#"{"t":"state""#) { lastState = line }
                log("link \(sender == .brain ? "brain" : "rules") → " + line)
            }
            for over in rig.steering.overBudget(in: buddy.pack) { log("steering: over budget: \(over)") }
        }
        // The core. The launch's read-back prunes the transcript, so today
        // isn't a new day.
        var config = Core.Config(volume: settings.volume, time: options.time, pack: buddy.pack, hatched: longTerm.hatched)
        config.firstAsk = SessionTracker.randomFirstRequest()
        config.workStream = settings.workStream
        let core = Core(config: config, lastActiveDay: today, place: places.place, isRunning: Runtime.agentRuns)
        core.macSide = settings.macSide
        core.setWallClock(wall, at: wallAt)
        view = TranscriptView(rules: rules, seed: longTerm.seed ^ UInt64(now), place: places.place)
        let transcript = Transcript.log(folder: options.stateDir.appendingPathComponent(Transcript.folderName),
                                        time: options.time, note: log)
        pipeline = Pipeline(core: core, buddy: buddy, view: view, transcript: transcript, time: options.time,
                            clock: Harness.Clock(now: options.clock, wall: options.wallClock), queue: home, note: log)
        pipeline.brain = false  // until Jev's key is read
        harness = pipeline.harness

        // The outputs' closures are only ever called on `home`, and reach
        // `self` once it's whole.
        var talkNow: () -> Talk = { .default }
        var swearsNow: () -> Bool = { false }
        var memoryNow: () -> String? = { nil }
        var remembersNow: () -> Memory? = { nil }
        let wallNow = options.wallClock
        var queued: (Moment, Pending) -> Void = { _, _ in }
        var effected: ([CoreEffect]) -> Void = { _ in }
        let link = rig.link
        var mind = Mind(buddy: buddy, steering: rig.steering,
                        reactions: rig.reactions, queue: { queued($0, $1) },
                        speaks: { link.hello.map { DeviceInfo($0).hasTheVoice } ?? true },
                        talk: { talkNow() }, effects: { effected($0) },
                        memory: { memoryNow() },
                        askable: { about, log, questions, mood in
                            Asks.askable(about, log, questions: questions, core: core, mood: mood, talk: talkNow(),
                                         memory: remembersNow(), wall: wallNow())
                        }, answerTags: { remembersNow()?.answerTags(at: $0) ?? [] },
                        company: { remembersNow()?.today }, wishDone: { remembersNow()?.wishDone($0) ?? false })
        mind.swears = { swearsNow() }
        mind.felt = { remembersNow()?.felt(at: $0, longest: MemoryPipeline.signRoom(face: link.hello.map { DeviceInfo($0).face })) ?? [] }
        mind.noticing = Mind.Noticing(digests: { remembersNow()?.digests ?? [] }, shown: { remembersNow()?.noticesShown() ?? [:] },
                                      onLately: { remembersNow()?.onLately($0) ?? false })
        rig.mood = Runtime.brain(pipeline, mind)
        // The questions line is debug.jsonl's first, before the read-back's
        // lines, the socket or the link can add one, so a changed first line
        // means a new launch. The read-back's own lines wait for it.
        var held: [String] = []
        var holding = true
        debugWriter = Runtime.debugLines(pipeline: pipeline, emit: { line in if holding { held.append(line) } else { emit(line) } })
        // Growth's store, or one in memory for this launch if the file won't open.
        let values: KeyValueStore
        var fellBack = false
        do { values = try KeyValueStore(directory: options.stateDir) } catch {
            log("growth: \(error); keeping XP in memory until the app quits, and remembering no day")
            values = try KeyValueStore(directory: nil)
            fellBack = true
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
        // An away the log no longer holds (a relaunch during a long
        // absence) is still an away: its start is kept.
        keyValues = values
        presence = PresenceDetector(away: view.away(logNow) || values.string(PresenceDetector.awayKey) != nil)
        growth.follow(transcriptAt: transcript.lastSeq)
        // Memory picks up where it stopped: the files' events it missed,
        // read as the day they came, then a dream not yet told logged again
        // if its event has left the log. Its days close from the next input.
        if !fellBack {
            let remembers = Memory(store: values, time: options.time, writer: MemoryPipelineWriter(), files: memory,
                                   queue: home, note: log)
            remembers.follow(transcriptAt: transcript.lastSeq)
            let folder = options.stateDir.appendingPathComponent(Transcript.folderName)
            remembers.catchUp(Transcript.events(in: folder, after: remembers.seq, from: remembers.from))
            remembers.launched()
            remembers.relog(unlessIn: logNow)
            home.sync { remembers.attach(to: pipeline) }
            remembers.countsSample = { [weak self] in
                self.map { ($0.talk == .quiet, $0.settings.volume, $0.growth.growth.level) } ?? (false, 0, 1)
            }
            self.remembers = remembers
        }
        // The core reads the growth stage and today's ring where the growth
        // store keeps them. Weak: the runtime holds the core.
        core.growth = { [weak self] in self.flatMap { $0.showsGrowth ? $0.growthNow : nil } }
        core.pushToTalkWorks = options.pushToTalkWorks
        talkNow = { [weak self] in self?.talk ?? .default }
        swearsNow = { [weak self] in self.map { $0.options.swearing ?? $0.settings.swearing } ?? false }
        memoryNow = { [weak self] in self?.memorySection() }
        remembersNow = { [weak self] in self?.remembers }
        queued = { [weak self] reaction, pending in self?.queue(reaction, pending) }
        effected = { [weak self] fx in self?.run(fx) }
        mirror = { [weak self] line in self?.onBoardLine?(line) }
        // The core reads the mood where the mood output keeps it. Weak:
        // the harness holds the core.
        let mood = rig.mood!
        core.mood = { [weak harness = self.harness] in
            harness.map { MoodOutput.value(mood, $0.log.view(now: clock())) } ?? mood.start
        }
        // The device's taps and push-to-talk; the link leaves out those
        // of a device whose firmware doesn't fit.
        rig.link.onEvent = { [weak self] ev in self?.deviceEvent(ev) }
        // A hello (the first on a link, or one that says something new):
        // log who the device is, and show it what's true now.
        rig.link.onHello = { [weak self] hello in
            DeviceInfo(hello).logLines.forEach(log)
            if let self, let latest = rig.latest { self.show(latest) }
            self?.playGrowthDue(at: clock(), hello: true)
        }
        // A pass can change a mood, which its device and the menu bar show.
        harness.on(Event.did) { [weak self] e in
            guard let self, e.action == MoodOutput.outputName, e["ok"]?.bool == true else { return }
            run(core.stateChanged(at: options.clock()))
        }
        harness.onPass = { [weak self] pass in self?.passed(pass) }
        // Every event as it's logged: the growth store counts each once, and
        // caps the day at its ring; the world adds its counts.
        harness.on("*") { [weak self] e in
            self?.grow(e)
            self?.worldHeard(e)
        }
        startWorld()
    }

    /// Boop's brain for one buddy, the process's character (`brain`): the
    /// evals' and the tests'. `queue` plays a reaction, whose end
    /// `reactions` reads, and `speaks` says whether the device plays
    /// Voice's takes.
    public static func harness(pipeline: Pipeline, steering: Steering,
                               reactions: Reactions = Reactions(), queue: @escaping (Moment, Pending) -> Void,
                               speaks: @escaping () -> Bool = { true },
                               talk: @escaping () -> Talk = { .default },
                               swears: @escaping () -> Bool = { true },
                               memory: @escaping () -> String? = { nil }, remembers: Memory? = nil, seed: UInt64? = nil,
                               felt: ((Int64) -> [Memory.Felt])? = nil, digests: (() -> [DayDigest])? = nil,
                               wall: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) -> (harness: Harness, mood: Choice) {
        let core = pipeline.core
        var mind = Mind(buddy: pipeline.buddy, steering: steering, reactions: reactions,
                        queue: queue, speaks: speaks, talk: talk, memory: memory,
                        askable: { about, log, questions, mood in
                            Asks.askable(about, log, questions: questions, core: core, mood: mood, talk: talk(), memory: remembers, wall: wall())
                        }, answerTags: { remembers?.answerTags(at: $0) ?? [] },
                        company: { remembers?.today }, wishDone: { remembers?.wishDone($0) ?? false })
        if let seed { mind.seed = seed }
        mind.swears = swears
        mind.felt = felt ?? { remembers?.felt(at: $0) ?? [] }
        if let remembers {
            mind.noticing = Mind.Noticing(digests: digests ?? { remembers.digests }, shown: { remembers.noticesShown() }, onLately: { remembers.onLately($0) })
        }
        return (pipeline.harness, brain(pipeline, mind))
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
        rig.transport?.start(
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
        // Your hands, read more often than the tick, so Boop starts typing
        // within a beat of you: two numbers from the Mac, and a `state`
        // only when they change what your hands are doing.
        if options.keyIdleMs != nil {
            let hands = DispatchSource.makeTimerSource(queue: home)
            hands.schedule(deadline: .now() + 1, repeating: .milliseconds(Self.handsEveryMs))
            hands.setEventHandler { [weak self] in self?.handsTick() }
            hands.resume()
            handsTimer = hands
        }
        // From here on the harness and the callbacks are touched only on
        // `home`: reading Jev's key sets the brain and calls `onChange`,
        // so it starts now, after the app has set its callbacks.
        home.async { [self] in
            readJevKey()
            run(pipeline.tick(at: options.clock()))
            changed()
            options.log("boop: running on \(options.stateDir.path), socket \(options.socketPath), "
                        + "link \(rig.transport?.name ?? "none"), "
                        + "talk \(talk.rawValue), "
                        + "mood \(moodNow), brain \(harness.brain?.id ?? "still to come")"
                        + (options.debug ? ", debug log \(debugLogURL.path)" : ""))
        }
    }

    /// Stops listening for hooks and the device. Safe to call twice, and
    /// from any queue, `home` included.
    public func stop() {
        timer?.cancel()
        timer = nil
        handsTimer?.cancel()
        handsTimer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        server?.stop()
        server = nil
        rig.transport?.stop()
        let sleep = { [self] in worldSleep() }
        if DispatchQueue.getSpecific(key: onHome) == true { sleep() } else { home.sync(execute: sleep) }
        // Today's counts as they stand: the next launch reads the rest back.
        let keep = { [self] in remembers?.keepCounts(wall: options.wallClock(), now: true) }
        if DispatchQueue.getSpecific(key: onHome) == true { keep() } else { home.sync(execute: keep) }
        try? FileManager.default.removeItem(at: options.stateDir.appendingPathComponent(Self.runningFile))
        // The folder is free for the next runtime, as a rename starts one.
        lock.release()
    }

    /// Onboarding's greetings on the board, which it plays as a rule's
    /// reaction (only if nothing else plays, and never while something
    /// needs you), recorded in the transcript as the rules' others are, and
    /// waking no brain: the board found and not yet paired beckoning, a
    /// look up holding a sign, so you know which board to tap; Boop waking
    /// into its body once it's paired; a finish that stands out, held
    /// twice, for the first hook; and a big one for the finale, held three
    /// times in a happy face, its first design (the gel's Gold Rush,
    /// Pixel's trophy).
    public enum Greeting: Sendable {
        case beckon, wake, hello, finale
        var reaction: Moment {
            switch self {
            case .beckon: Moment(anim: "notice", loops: 2, sign: Self.tapMe)
            case .wake: Moment(anim: "wake_up")
            case .hello: Moment(anim: "task_complete", loops: 2, outcome: "success")
            case .finale: Moment(anim: "task_complete", mood: "happy", loops: 3, outcome: "success", variant: 1)
            }
        }
        /// The beckon's sign, which onboarding's window points at.
        public static let tapMe = "Tap me!"
    }

    /// Onboarding's practice request on the board, or taken down: its
    /// needs-you screen, with no agent behind it (`Core.setPractice`).
    public func practice(_ on: Bool) {
        home.async { [self] in
            options.log("onboarding: practice request \(on ? "up" : "down")")
            run(core.setPractice(on, at: options.clock()))
        }
    }

    public func greet(_ greeting: Greeting) {
        home.async { [self] in
            options.log("onboarding: \(greeting.reaction.name) on the board")
            run(core.greet(greeting.reaction, at: options.clock()))
        }
    }

    /// Onboarding's cheer for `who`'s finished turn: a finish that names
    /// it, sent as the brain's are, so a tap on it opens its thread
    /// (`Reactions.sent`), as it will after any finished turn.
    public func cheer(_ who: Moment.Who) {
        home.async { [self] in
            let rig = rig, now = options.clock()
            let reaction = Moment(anim: "task_complete", loops: 2, who: who, outcome: "success")
            options.log("onboarding: a cheer for \(who.agent)'s \(who.thread) on the board")
            let id = rig.link.do(reaction.name, args: reaction.args, play: .next, ttl: BoopDevice.ttl(reaction), by: .brain,
                                 now: now) { _ in }
            if let id, let thread = who.opens { rig.reactions.sent(id, opens: thread, ttl: BoopDevice.ttl(reaction), now: now) }
        }
    }

    /// MEMORY for Jev: the written memory, its Recently named from today's
    /// Boop day; nil with none.
    func memorySection() -> String? {
        memory.written().section(today: options.time.boopDay(options.wallClock()))
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
        PromptIntake.read(text, names: [buddy.name], labeler: labeler, home: home) { [weak self] reading in
            guard let self else { return }
            guard let step = pipeline.read(reading, about: turn, at: options.clock()) else {
                return options.log("\(reading.kind.rawValue): \(agent)'s session \(session) moved on before its reading; dropped it")
            }
            run(step)
        }
    }

    /// How often your hands are read (`handsTick`).
    static let handsEveryMs = 250

    /// Your hands at the Mac now (`Hands`), for the board's tags: none
    /// with the setting off, the screen locked or you away. A change is a
    /// new `state`, and nothing else: no event, no pass.
    func handsTick() {
        let keyIdle = options.keyIdleMs?() ?? devKeyIdleMs, idle = options.idleMs?() ?? devIdleMs
        let there = settings.typesAlong && presence.lockedAt == nil && !core.awayFromMac
        let hands = there ? keyIdle.flatMap { Hands.now(keyIdleMs: $0, idleMs: idle) } : nil
        guard hands != core.hands else { return }
        core.hands = hands
        run(core.stateChanged(at: options.clock()))
    }

    func tick() {
        // The core follows the Mac's clock, set or moved.
        let now = options.clock(), wall = options.wallClock()
        core.setWallClock(wall, at: now)
        handsTick()
        run(pipeline.tick(at: now))
        worldTick(at: now)
        if let e = presence.tick(at: now, idleMs: options.idleMs?() ?? devIdleMs) { recordPresence(e) }
        // The keepalive, and the reactions whose `ended` never came.
        rig.link.tick(now: now)
        rig.reactions.tick(now: now)
        let trouble = rig.link.transport?.trouble
        if trouble != rig.linkTrouble {
            rig.linkTrouble = trouble
            changed()
        }
    }

    /// You stepped away or came back, as the detector decided: recorded,
    /// and a back wakes the brain.
    func recordPresence(_ e: Event) {
        options.log("presence: \(e.phase == .start ? "away" : "back") (\(e.specificType))")
        var e = e
        // The away's start is kept, so its back pairs with it whatever the
        // log still holds.
        do {
            if e.phase == .start, let since = e["since"]?.int {
                try keyValues?.set([PresenceDetector.awayKey: String(since)])
            } else if e.phase == .end {
                if e["since"] == nil, let since = keyValues?.string(PresenceDetector.awayKey).flatMap({ Int64($0) }) {
                    e.data["since"] = .int(since)
                }
                try keyValues?.remove([PresenceDetector.awayKey])
            }
        } catch { options.log("presence: can't keep the away: \(error)") }
        run(pipeline.presence(e))
    }

    /// A signal from the Mac for the presence detector.
    func presenceSignal(_ signal: PresenceDetector.Signal) {
        for e in presence.signal(signal, at: options.clock()) {
            if e.type == .lock {
                options.log("presence: \(e.specificType)")
                run(pipeline.lock(e))
            } else {
                recordPresence(e)
            }
        }
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
                if celebrating.isEmpty || (reaction.gold == nil && reaction.sign != Core.ringSign) {
                    playRule(reaction)
                } else {
                    playGrowth(reaction)
                }
            case .call(let args):
                playCall(args)
            case .open(let thread):
                open(thread, by: "tap")
            }
        }
        // Only the outermost step: a step inside an input joins it, which
        // carries these out after.
        // Growth logged with no moment sent for it (something needed you
        // by then): still due.
        if !celebrating.isEmpty, pipeline.step == nil { missedGrowth(celebrating) }
        if growthDue, pipeline.step == nil {
            growthDue = false
            if !playGrowthDue(at: options.clock()) { xpMoved = true }
        }
        if xpMoved, pipeline.step == nil {
            xpMoved = false
            publishXP(at: options.clock())
        }
        if stateChanged || grew { changed() }
    }

    private func publishXP(at now: Int64) {
        run(core.stateChanged(at: now))
    }

    /// The growth on Boop's day now: a ring of a day before is empty.
    var growthNow: Growth { growth.growth(on: options.time.boopDay(options.wallClock())) }

    /// Counts what `e` earns. A level reached or the ring closing is a
    /// moment on every board, after the `state` that carries it; any other
    /// XP is only the bar, which an input's own `state` carries when it
    /// makes one, once it's carried out (`run`), so the board gets one line
    /// for one hook.
    func grow(_ e: Event) {
        if growth.played(e) { celebrating.append(e) }
        let now = options.clock()
        guard growth.count(e, xp: Growth.xp(for: e), today: options.time.boopDay(options.wallClock())) > 0 else { return }
        grew = true
        if pipeline.step != nil { return growthDue = true }
        if !playGrowthDue(at: now) { publishXP(at: now) }
    }

    /// What's due plays on the board, and is celebrated as it's sent
    /// (`played`): after XP that reached it, at the board's hello (so one
    /// held over a quit, or reached with the board out of reach, isn't
    /// lost), and after a demo, which shows none. A board that isn't here
    /// is waited for; one that just missed it isn't asked again for
    /// `growthRetryMs`, but at its hello.
    @discardableResult
    func playGrowthDue(at now: Int64, hello: Bool = false) -> Bool {
        let beats = growth.due(today: options.time.boopDay(options.wallClock()))
        guard showsGrowth, !beats.isEmpty, rig.link.transport == nil || rig.link.hello != nil,
              hello || growthMissedAt.map({ now - $0 >= Self.growthRetryMs }) ?? true else { return false }
        run(core.grew(beats, at: now))
        return true
    }

    /// The growth moment, sent as a rule's is, and taken back
    /// (`GrowthStore.missed`) if the board never showed it: skipped in its
    /// queue or by face down, cut by a request, or the link dropped.
    func playGrowth(_ reaction: Moment) {
        let events = celebrating
        celebrating = []
        // With no board at all there's nothing to wait for.
        guard rig.link.transport != nil else { return playRule(reaction) }
        playRule(reaction) { [weak self] outcome in
            let shown: Bool
            switch outcome {
            case .ended(let ended):
                shown = ended.how == .done || (ended.how == .cut && ended.why != "needs_you" && ended.why != "facedown")
            case .failed(let failure):
                shown = failure != .notConnected && failure != .disconnected && failure != .noHello
            }
            if !shown { self?.missedGrowth(events) }
        }
    }

    func missedGrowth(_ events: [Event]) {
        celebrating = []
        growth.missed(events)
        growthMissedAt = options.clock()
        options.log("growth: the board didn't show \(events.map { "\($0.type?.rawValue ?? "") \($0.specificType)" }.joined(separator: ", ")); still due")
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
            run(pipeline.dismiss(key, request: request, at: now))
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
            run(core.setVolume(volume, at: options.clock()))
            saveSettings { $0.volume = core.config.volume }
        }
    }

    /// Typing along with you on or off, kept in `settings.json`.
    public func setTypesAlong(_ on: Bool) {
        home.async { [self] in
            saveSettings { $0.typesAlong = on }
            handsTick()
        }
    }

    /// The side of Boop the Mac is on, kept in `settings.json`.
    public func setMacSide(_ side: MacSide?) {
        home.async { [self] in
            saveSettings { $0.macSide = side }
            core.macSide = side
            run(core.stateChanged(at: options.clock()))
        }
    }

    /// The work stream on or off, on every buddy, kept in `settings.json`.
    public func setWorkStream(_ on: Bool) {
        home.async { [self] in
            run(core.setWorkStream(on, at: options.clock()))
            saveSettings { $0.workStream = on }
        }
    }

    /// How much it says: the view's rules and Jev's state from the next
    /// event, kept in `settings.json`.
    /// Swearing on or off, kept in `settings.json`: read at each pass.
    public func setSwearing(_ on: Bool) {
        home.async { [self] in saveSettings { $0.swearing = on } }
    }

    public func setTalk(_ talk: Talk) {
        home.async { [self] in
            self.talk = talk
            saveSettings { $0.talk = talk }
            view.setRules(options.steering.rules(talk: talk))
            options.log("talk \(talk.rawValue)")
            changed()
        }
    }

    /// Hushes every buddy for `ms` (`Core.hushMs`) from the app's button:
    /// it says nothing until then, and the brain hears of it.
    public func hush(forMs ms: Int64 = Core.hushMs) {
        home.async { [self] in
            let now = options.clock()
            run(core.hush(forMs: ms, by: .app, at: now))
            options.log("hush \(ms / 60_000) min")
        }
    }

    /// Lets every buddy talk again before its hush runs out.
    public func unhush() {
        home.async { [self] in
            let now = options.clock()
            run(core.unhush(by: .app, at: now))
            options.log("unhush")
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

extension Runtime {
    /// Whether the board shows Boop's real growth: a demo, or `fullSize`,
    /// draws Boop full size, with no bar.
    var showsGrowth: Bool { !options.fullSize && !playingDemo }
}
