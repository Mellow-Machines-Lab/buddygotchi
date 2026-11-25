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
        /// Builds Jev from its key, nil for none: what may take the rules'
        /// seats (`SeatedBrain`). Tests pass their own.
        public var brain: @Sendable (String?) -> (any Brain)? = { key in key.map { JevBrain(key: $0) } }
        /// `brain` answers alone, in the rules' place, once the key is read,
        /// and with none nothing wakes the brain: `--brain scripted`,
        /// `--brain none` and most tests. Off, as every real launch runs,
        /// the rules answer from the start and `brain` takes their seats.
        public var alone = false
        /// The dream may run your own agent tool (`AgentToolModel`): the
        /// app's. Tests and headless keep it off unless asked.
        public var agentTool = false
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
        /// The rest of what Boop notices of you at the Mac (`Along`): the
        /// scroll's and the click's idle times, the pointer, whether sound,
        /// a camera or the mic runs, the frontmost app. Never content. Nil
        /// (headless): `{"dev":"along"}` lines stand in.
        public var along: (@Sendable () -> Along.Facts)?
        /// The Mac's displays now, to tell whether the anchor's is still
        /// there (`displaysChanged`). Nil (headless): it always is.
        public var displays: (@Sendable () -> [Anchor.Rect])?
        /// Reads your hands every `handsEveryMs` (headless and the app), not
        /// only on the second's tick (tests, which tick them themselves).
        public var readsHandsOften = false
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
        /// Opens what a result card links to (`CardTool.open`).
        public var openLink: @Sendable (String) -> Bool = CardTool.open
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
    /// Whether Jev has failed for long enough to say so, and how many
    /// passes it failed in a row.
    var trouble: BrainTrouble?
    var jevFailedInARow = 0
    /// Bumped by every `useBrain`: what an earlier brain's Jev reports says
    /// nothing of this one's.
    var brainUses = 0
    /// The rules brain, the one every real launch answers with, built once.
    var rules: RulesBrain?
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
    /// The show's picture on its way to the board.
    var showBlobs = ShowBlobs()
    /// Keeps macOS from napping the app while it runs.
    var activity: NSObjectProtocol?
    let places = Places()
    /// Jev's key, touched only on `home`: nil until read, and then the key
    /// or none. Until then Jev takes no seat, and with `alone` no event
    /// wakes the brain.
    var jevKey: String??
    /// The transport's `trouble` as the status last had it.
    var linkTrouble: TransportTrouble? { rig.linkTrouble }
    /// Whether the Mac's mic is on.
    var micOn = false
    /// What a demo's mic hears as its button is let go: the words come once
    /// the mic is off, as speech's do.
    var wordsOnRelease: String?
    /// A demo script plays: Boop shows no growth of its own.
    var playingDemo = false
    /// Boop's XP, level and today's ring, counted from each event as it's
    /// logged, and whether the XP changed since the last status.
    let growth: GrowthStore
    var grew = false
    /// A status is asked for and not built yet (`changed`).
    var statusDue = false
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

    /// After changes the menu bar might show, at most every
    /// `statusEveryMs`. Called on `home`.
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
    /// A `presence` line has said an idle time: from then on headless tells
    /// the core when you last touched the Mac, as the app always does.
    var devIdleSet = false
    /// The time since the last key `{"dev":"presence","key_idle_ms":N}`
    /// set, read in place of the Mac's when there's no `keyIdleMs`; none
    /// until a dev line says one, so a headless run has no hands.
    var devKeyIdleMs: Int64?
    /// The rest of the Mac's facts `{"dev":"along",…}` lines set, read in
    /// place of the Mac's when there's no `along` reader.
    var devAlong = Along.Facts()
    /// The anchor's display is gone or changed (`displaysChanged`): Boop
    /// follows nothing and turns nowhere until it's shown again.
    var anchorGone = false
    /// When the last `state` that only moved the pointer went (`handsTick`).
    var pointerSentAt: Int64?
    /// What Boop notices of you at the Mac, as it's kept (`Along`).
    var alongState = Along()
    /// While Boop waits for the tap that shows where it sits
    /// (`showWhereBoopSits`): until when, and when it last asked.
    var placing: (until: Int64, asked: Int64)?
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
        let buddy = Buddy(CharacterPack.active.named(longTerm.name))
        let rig = Rig(link: options.link, steering: options.steering, log: log)
        self.rig = rig
        // The board's lines go to its mirror too, once `self` is whole.
        var mirror: (String) -> Void = { _ in }
        do {
            // boop.log leaves out a `state` sent again unchanged (the keepalive,
            // a reply to `hello`), which debug.jsonl keeps.
            var lastState: String?, lastSent: String?
            let sent = options.onDeviceLine
            rig.link.onSend = { line, sender in
                sent?(line)
                mirror(line)
                // The logs and a bug report keep no timeline of you at the
                // Mac: a `state` is logged without its pointer and the tags
                // of what you scroll, play or record, and one that changed
                // only those isn't logged again.
                // A show's picture goes to the board and its mirror, never to
                // a log: its parts are logged without their bytes.
                if line.hasPrefix(#"{"t":"blob""#), let cut = line.range(of: #","d":""#) {
                    let kept = String(line[..<cut.lowerBound]) + "}"
                    emit(DebugLog.sent(kept, by: sender, at: clock()))
                    return
                }
                let kept = StateSnapshot.unnoticed(line)
                let isState = line.hasPrefix(#"{"t":"state""#)
                let changed = kept != lastState
                if isState, !changed, line != lastSent { return lastSent = line }
                if isState { (lastSent, lastState) = (line, kept) }
                emit(DebugLog.sent(kept, by: sender, at: clock()))
                guard debugLog != nil, changed else { return }
                log("link \(sender == .brain ? "brain" : "rules") → " + kept)
            }
            for over in rig.steering.overBudget(in: buddy.pack) { log("steering: over budget: \(over)") }
        }
        // The core. The transcript prunes itself, at launch and on each
        // new day's first event.
        var config = Core.Config(volume: settings.volume, time: options.time, pack: buddy.pack, hatched: longTerm.hatched)
        config.color = settings.color
        config.firstAsk = SessionTracker.randomFirstRequest()
        let core = Core(config: config, place: places.place, isRunning: Runtime.agentRuns)
        core.macSide = settings.anchor?.side
        if let displays = options.displays, let anchor = settings.anchor { anchorGone = !displays().contains(anchor.display) }
        if anchorGone { core.macSide = nil }
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
        var earnedNow: (Int) -> (source: Growth.Source, xp: Int)? = { _ in nil }
        var mind = Mind(buddy: buddy, steering: rig.steering,
                        reactions: rig.reactions, queue: { queued($0, $1) },
                        speaks: { (link.hello.map { DeviceInfo($0).hasTheVoice } ?? true) && !core.along.onCall && !core.along.speaking },
                        talk: { talkNow() }, effects: { effected($0) },
                        memory: { memoryNow() })
        mind.remember({ remembersNow() }, core: core, wall: wallNow)
        mind.swears = { swearsNow() }
        mind.earned = { earnedNow($0) }
        // A skit's invite: only to a board that plays them, by the
        // memory's ledger, and with the XP care would add now.
        let time = options.time
        mind.inviting = MomentOutput.Inviting(board: { link.hello.map { DeviceInfo($0).invites } ?? false },
                                              onCall: { core.along.onCall },
                                              ledger: { remembersNow().map { $0.invites.state ?? InviteLedger() } },
                                              care: { core.growth()?.adds(.care) ?? 0 })
        // A skit's remark: against your usual, the memory's.
        mind.remarking = MomentOutput.Remarking(normals: { remembersNow()?.normals.state },
                                                minutes: { time.minutesIntoBoopDay(core.wall($0)) })
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
        earnedNow = { [weak self] seq in self?.growth.earned(at: seq) }
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
            // The dream's model: your own agent tool while Settings allows
            // it, else Apple Intelligence, else code alone.
            let dreamFolder = options.stateDir.appendingPathComponent("dream")
            let stateDir = options.stateDir, mayRun = options.agentTool
            let agentTool = { @Sendable () -> MemoryModel? in
                guard mayRun, AppSettings.load(from: stateDir).agentsThink else { return nil }
                return AgentToolModel.find(folder: dreamFolder)
            }
            let remembers = Memory(store: values, time: options.time, writer: MemoryPipelineWriter(agentTool: agentTool), files: memory,
                                   queue: home, note: log)
            remembers.follow(transcriptAt: transcript.lastSeq)
            let folder = options.stateDir.appendingPathComponent(Transcript.folderName)
            let missed = Transcript.events(in: folder, after: remembers.seq, from: remembers.from)
            let lines = home.sync { [harness] in Dictionary(missed.compactMap { e in harness.line(e.seq).map { (e.seq, $0) } }) { a, _ in a } }
            remembers.catchUp(missed, lines: { lines[$0] })
            remembers.launched()
            remembers.relog(unlessIn: logNow)
            home.sync { remembers.attach(to: pipeline) }
            remembers.countsSample = { [weak self] in
                self.map { ($0.talk == .quiet, $0.settings.volume, $0.growth.growth.level) } ?? (false, 0, 1)
            }
            self.remembers = remembers
        }
        // The core reads today's ring where the growth store keeps it. Weak: the runtime holds the core.
        core.growth = { [weak self] in self.flatMap { $0.showsGrowth ? $0.growthNow : nil } }
        core.daysInARow = { [weak self] in self.map { $0.growth.daysInARow(on: $0.options.time.boopDay($0.options.wallClock())) } ?? 0 }
        core.pushToTalkWorks = options.pushToTalkWorks
        talkNow = { [weak self] in self?.talk ?? .default }
        swearsNow = { [weak self] in self.map { $0.options.swearing ?? $0.settings.swearing } ?? false }
        memoryNow = { [weak self] in self?.memorySection() }
        remembersNow = { [weak self] in self?.remembers }
        queued = { [weak self] reaction, pending in self?.queue(reaction, pending) }
        effected = { [weak self] fx in self?.run(fx) }
        mirror = { [weak self] line in self?.onBoardLine?(line) }
        // The core reads the mood's face where the mood output keeps it.
        // Weak: the harness holds the core.
        let mood = rig.mood!, pack = core.config.pack
        core.mood = { [weak harness = self.harness] in
            harness.map { MoodOutput.face(mood, $0.log.view(now: clock()), pack: pack) } ?? pack.restingFace(mood.start)
        }
        // The device's taps and push-to-talk; the link leaves out those
        // of a device whose firmware doesn't fit.
        rig.link.onEvent = { [weak self] ev in self?.deviceEvent(ev) }
        // A hello (the first on a link, or one that says something new):
        // log who the device is, and show it what's true now.
        // The board has a show's picture: its state names it now.
        rig.link.onBlob = { [weak self] id in
            guard let self, showBlobs.arrived(id), let latest = rig.latest else { return }
            options.log("device: has the show's picture (blob \(id))")
            show(latest)
        }
        rig.link.onHello = { [weak self] hello in
            DeviceInfo(hello).logLines.forEach(log)
            // A board that says hello may have restarted: it has no picture.
            self?.showBlobs.forget()
            if let self, let latest = rig.latest { self.show(latest) }
            self?.playGrowthDue(at: clock(), hello: true)
        }
        // A pass can change a mood, which its device and the menu bar show.
        harness.on(Event.did) { [weak self] e in
            guard let self, e.action == MoodOutput.outputName, e["ok"]?.bool == true else { return }
            run(core.stateChanged(at: options.clock()))
            writeBrief()
        }
        // A dream's write changes what the brief remembers.
        harness.on(Event.Kind.memory.rawValue) { [weak self] _ in self?.writeBrief() }
        writeBrief()
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
        var mind = Mind(buddy: pipeline.buddy, steering: steering, reactions: reactions,
                        queue: queue, speaks: speaks, talk: talk, memory: memory)
        mind.remember({ remembers }, core: pipeline.core, wall: wall, notices: remembers != nil)
        if let seed { mind.seed = seed }
        mind.swears = swears
        if let felt { mind.felt = felt }
        if let digests { mind.noticing?.digests = digests }
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
        // What isn't a hook: a card from the tool server, or a dev line.
        let onOther: @Sendable (Data) -> Void = { [weak self] data in
            let received = clock()
            home.async { self?.other(data, received: received) }
        }
        let server = HookServer(path: options.socketPath, onLine: onLine, onOther: onOther)
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
        if options.keyIdleMs != nil || options.readsHandsOften {
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
            // The rules answer at once; Jev takes its seats once its key is read.
            if !options.alone { useBrain() }
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
    /// times in a happy face, its first design (the gel's Gold Rush).
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

    /// A line on the socket that isn't a hook's: a card an agent handed
    /// Boop (`CardTool.line`), held to the limits again here, since anything
    /// may write to the socket; or, with `devLines`, a dev line.
    func other(_ data: Data, received: Int64) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if object["show"] != nil {
            // A show an agent drew (`CardTool.line(_:process:)`), checked again.
            guard let (show, process) = CardTool.readShow(object) else { return }
            let step = pipeline.show(show, process: process, at: received)
            if options.debug { options.log("show: " + (step.recorded.isEmpty ? "for nobody" : "taken")) }
            return run(step)
        }
        guard object["card"] != nil else {
            if options.devLines { dev(data) }
            return
        }
        guard let (card, process) = CardTool.read(object) else { return }
        let step = pipeline.card(card, process: process, at: received)
        if options.debug { options.log("card: \(card.kind.rawValue) " + (step.recorded.isEmpty ? "for nobody" : "taken")) }
        run(step)
    }

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

    /// You at the Mac now (`Hands`, `Along`), for the board's tags and its
    /// `ptr`: none with the setting off, the screen locked or you away. A
    /// change is a new `state`, and nothing else: no event, no pass,
    /// nothing in the transcript.
    func handsTick() {
        let now = options.clock()
        // A show's picture goes in parts, as fast as the link takes them,
        // and again when it hasn't arrived.
        rig.link.pump(now: now)
        if showBlobs.due(at: now), !rig.link.sendingBlob, let latest = rig.latest { show(latest) }
        if let until = placing?.until, now >= until { stopPlacing(why: "no tap in time") }
        if let asked = placing?.asked, now - asked >= Self.placeAskEveryMs { askToPlace(at: now) }
        let there = settings.noticesYou && presence.lockedAt == nil && !core.awayFromMac
        var along = Along.Now()
        if there {
            along = alongState.read(facts(), anchor: anchor, at: now)
        } else {
            alongState = Along()  // its holds start again when you're back
        }
        guard along != core.along else { return }
        // Only the pointer moved: at most every pointerEveryMs, the rest
        // coalesced into the next.
        if along.placeless == core.along.placeless {
            if let sent = pointerSentAt, now - sent < Self.pointerEveryMs { return }
            pointerSentAt = now
        }
        core.along = along
        run(core.stateChanged(at: now))
    }

    /// The most often a `state` goes for the pointer alone: 4 a second.
    static let pointerEveryMs: Int64 = 250

    /// Where Boop sits, unless its display has gone.
    var anchor: Anchor? { anchorGone ? nil : settings.anchor }

    /// The Mac's displays changed (or the app started): an anchor whose
    /// display is gone, or isn't where it was, is set aside until Boop is
    /// shown where it sits again.
    public func displaysChanged() {
        home.async { [self] in
            guard let displays = options.displays else { return }
            let gone = settings.anchor.map { !displays().contains($0.display) } ?? false
            guard gone != anchorGone else { return }
            anchorGone = gone
            options.log(gone ? "anchor: its display is gone; show Boop where it sits again" : "anchor: its display is back")
            core.macSide = anchor?.side
            run(core.stateChanged(at: options.clock()))
            changed()
        }
    }

    /// The Mac's facts now: the app's readers, else the dev lines'.
    func facts() -> Along.Facts {
        var r = options.along?() ?? devAlong
        r.keyIdleMs = options.keyIdleMs?() ?? devKeyIdleMs
        r.idleMs = options.idleMs?() ?? devIdleMs
        return r
    }

    func tick() {
        // The core follows the Mac's clock, set or moved.
        let now = options.clock(), wall = options.wallClock()
        core.setWallClock(wall, at: now)
        // When you last touched the Mac, for Doing with no agent open.
        if let idle = options.idleMs?() ?? (devIdleSet ? devIdleMs : nil) {
            core.lastInputAt = max(core.lastInputAt ?? .min, now - max(0, idle))
        }
        // Your hands and a show's parts, unless their own timer reads them.
        if handsTimer == nil { handsTick() }
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
                // Only the pointer moved: the board's, and nothing the
                // popover shows, so no status.
                let pointerOnly = rig.latest.map { var was = $0; was.pointer = snapshot.pointer; return was == snapshot } ?? false
                show(snapshot)
                if !pointerOnly { stateChanged = true }
            case .sessions:
                stateChanged = true
            case .record:
                break
            case .listen(let on, let by):
                mic(on, by: by)
                stateChanged = true
            case .reaction(let reaction):
                if celebrating.isEmpty || reaction.gold == nil {
                    playRule(reaction)
                } else {
                    playGrowth(reaction)
                }
            case .call(let args):
                playCall(args)
            case .open(let thread):
                open(thread, by: "tap")
            case .openLink(let link):
                let opened = options.openLink(link)
                options.log("open: a card's link" + (opened ? "" : ": open failed"))
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
        let source = Growth.source(of: e, facts: harness.line(e.seq)?.facts)
        guard growth.count(e, source, today: options.time.boopDay(options.wallClock())) > 0 else { return }
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

    /// The buddy's colour, from Settings: on the board at once, kept, and
    /// sent to the world with the next send.
    public func setColor(_ color: Int) {
        home.async { [self] in
            run(core.setColor(color, at: options.clock()))
            saveSettings { $0.color = core.config.color }
            changed()
        }
    }

    public func setVolume(_ volume: Int) {
        home.async { [self] in
            run(core.setVolume(volume, at: options.clock()))
            saveSettings { $0.volume = core.config.volume }
        }
    }

    /// Noticing what you do at the Mac on or off, kept in `settings.json`.
    /// Off, Boop stops waiting to be shown where it sits.
    public func setNoticesYou(_ on: Bool) {
        home.async { [self] in
            saveSettings { $0.noticesYou = on }
            if !on { stopPlacing(why: "noticing is off") }
            handsTick()
        }
    }

    /// Settings' "Show Boop where it sits": Boop asks you to point at the
    /// spot on your screen nearest it and tap it (`askToPlace`), and the
    /// next tap on its face is that, not a poke (`placeHere`); pressed
    /// again, or with no tap in `placeMs`, it stops.
    public func showWhereBoopSits() {
        home.async { [self] in
            if placing != nil { return stopPlacing(why: "cancelled") }
            guard settings.noticesYou else { return options.log("anchor: noticing is off") }
            let now = options.clock()
            placing = (now + Self.placeMs, now)
            options.log("anchor: waiting for a tap on Boop")
            askToPlace(at: now)
            changed()
        }
    }

    /// How long Boop waits for its tap, and how often it asks again
    /// meanwhile, as a sign stays up only while its Moment plays.
    public static let placeMs: Int64 = 60_000
    static let placeAskEveryMs: Int64 = 12_000
    /// The sign Boop holds up while it waits, and the one it answers with.
    public static let placeSign = "point, then tap me", placedSign = "got it"

    func askToPlace(at now: Int64) {
        guard placing != nil else { return }
        placing?.asked = now
        run(core.greet(Moment(mood: "curious", loops: Moment.maxLoops, sign: Self.placeSign), at: now))
    }

    func stopPlacing(why: String) {
        guard placing != nil else { return }
        placing = nil
        options.log("anchor: stopped waiting (\(why))")
        changed()
    }

    /// Where Boop sits, or none, kept in `settings.json`: the side the Mac
    /// is on comes from it.
    public func setAnchor(_ anchor: Anchor?) {
        home.async { [self] in
            saveSettings { $0.anchor = anchor }
            anchorGone = false
            core.macSide = anchor?.side
            run(core.stateChanged(at: options.clock()))
            changed()
        }
    }

    /// Whether a touch on the board is the one Boop waits for to know where
    /// it sits: any on its face, a tap, a nose boop, a tickle, a stroke or a
    /// lean, while it waits.
    func places(gesture kind: String) -> Bool {
        guard placing != nil, let (touch, ended) = Touch.read(kind), !ended else { return false }
        return touch == .poke || touch == .stroke || touch == .hold
    }

    /// The tap while Boop waits for it: the pointer's place now is where
    /// it sits, kept in `settings.json`, and the side the Mac is on comes
    /// from it. Boop nods. Not a poke: no pass, no count, no XP.
    func placeHere(at now: Int64) {
        guard settings.noticesYou else { return stopPlacing(why: "noticing is off") }
        let r = facts()
        guard let x = r.pointerX, let y = r.pointerY, let display = r.display else {
            return options.log("anchor: no pointer to read; still waiting")
        }
        let anchor = Anchor(x: x, y: y, display: display)
        placing = nil
        anchorGone = false
        saveSettings { $0.anchor = anchor }
        core.macSide = anchor.side
        options.log("anchor: set; the screen is \(anchor.side.map { $0 == .up ? "above it" : "on its \($0.rawValue)" } ?? "nowhere")")
        var nod = Moment(mood: "happy", loops: 1, sign: Self.placedSign)
        nod.clip = "reply-yes"
        run(core.greet(nod, at: now))
        run(core.stateChanged(at: now))
        changed()
    }

    /// How much it says: the view's rules and Jev's state from the next
    /// event, kept in `settings.json`.
    /// Swearing on or off, kept in `settings.json`: read at each pass.
    public func setSwearing(_ on: Bool) {
        home.async { [self] in saveSettings { $0.swearing = on } }
    }

    /// Whether your own agent helps Boop think, kept in `settings.json`:
    /// read at each dream, and by the agents' tool server from the brief.
    public func setAgentsThink(_ on: Bool) {
        home.async { [self] in
            saveSettings { $0.agentsThink = on }
            writeBrief()
        }
    }

    /// The agents' brief (`AgentBrief`), in the state folder beside the
    /// tool server: who Boop is, what it remembers, how it feels now. On
    /// `home`.
    func writeBrief() {
        let pack = core.config.pack
        let notes = memory.written().notes.map(\.text)
        let mood = MoodOutput.value(rig.mood, harness.log.view(now: options.clock()), pack: pack)
        let personality = AgentBrief.personality(from: rig.steering["personality"]).replacingOccurrences(of: pack.name, with: name)
        AgentBrief(name: name, personality: personality, memory: notes,
                   mood: "\(name) is \(mood) now.", on: settings.agentsThink, faces: pack.faces.map(\.name))
            .write(to: options.stateDir)
    }

    public func setTalk(_ talk: Talk) {
        home.async { [self] in
            self.talk = talk
            // Choosing a Talk ends a quiet for a while.
            core.endQuiet()
            saveSettings { $0.talk = talk }
            view.setRules(options.steering.rules(talk: talk))
            options.log("talk \(talk.rawValue)")
            changed()
        }
    }

    /// The popover's button: quiet for a while (`Core.quietForMs`), or
    /// with `on` false, Talk as the setting has it again.
    public func quietForAWhile(_ on: Bool = true) {
        home.async { [self] in
            if on { core.quiet(at: options.clock()) } else { core.endQuiet() }
            options.log(on ? "quiet for \(Core.quietForMs / 60_000) min" : "quiet over")
            changed()
        }
    }

    /// A fresh status, on `home`, at once.
    public func refresh() {
        home.async { [self] in status() }
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
