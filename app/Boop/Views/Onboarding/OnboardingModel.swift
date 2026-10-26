import AgentHooks
import AppKit
import BoopKit
import SwiftUI

/// The first launch's walkthrough, as the window shows it: which act, and
/// what each act has heard and done. The acts (`Onboarding.Act`) and where
/// a launch starts are BoopKit's; this keeps the moment to moment. It
/// reads the app's model for everything that lasts (the draft name, the
/// runtime's status, the hooks, the login item, the firmware) and is told
/// by the app when the board is tapped or an agent's hook arrives.
@MainActor
final class OnboardingModel: ObservableObject {
    /// What's been heard and done, and the rules for taps and hooks
    /// (BoopKit's, tested there).
    @Published var progress: Onboarding.Progress
    /// The last move went forward, for which way the acts slide.
    @Published private(set) var forward = true

    var act: Onboarding.Act { progress.act }
    var body: Onboarding.Progress.Body {
        get { progress.body }
        set { progress.body = newValue }
    }
    var lessons: Set<Onboarding.Progress.Lesson> { progress.lessons }
    var connected: Bool {
        get { progress.connected }
        set { progress.connected = newValue }
    }
    var heard: String? { progress.heard }
    var tour: Set<Onboarding.Progress.Tour> { progress.tour }
    var tourDue: Onboarding.Progress.Tour? { progress.tourDue }

    // Act 3: why naming couldn't save, if it couldn't.
    @Published var nameError: String?

    // Act 4: when looking started, for the "can't find me" hint.
    @Published var lookingSince: Date?
    /// Act 4: a simulator runs on this Mac (the debug build's), a body to
    /// offer when there's no board.
    @Published var simulatorHere = false

    // Act 5: what push-to-talk heard last, for the talk lesson.
    enum Talk: Equatable { case heard(String), nothing }
    @Published var talk: Talk?

    // Act 6: what gets added, shown.
    @Published var showHooks = false

    // Act 7: the microphone and speech, once asked. The card is left out
    // when act 5's push-to-talk already had them allowed.
    enum Mic: Equatable { case notAsked, asking, allowed, refused(String) }
    @Published var mic = Mic.notAsked
    @Published var askMic = true
    /// The person changed the login switch here, so it isn't turned on for them.
    var loginTouched = false

    /// Goes up for each celebration, which the confetti bursts on.
    @Published var confetti = 0

    let app: AppModel
    let stateDir: URL
    /// The on-screen Boop's slime, when the character pack has one.
    let feed = SlimeFeed()
    /// The slime's still faces, for act 5's legend of moods.
    let stills = SlimeStills()
    /// Starts the runtime, once; the app's.
    var startRuntime: () -> Void = {}
    /// Onboarding is over: the app takes the menu bar.
    var finished: () -> Void = {}
    /// Brings the window in front of the others; the app's.
    var bringForward: () -> Void = {}
    var log: (String) -> Void = { _ in }

    init(app: AppModel, act: Onboarding.Act, stateDir: URL) {
        self.app = app
        progress = Onboarding.Progress(act: act)
        self.stateDir = stateDir
        app.setup.agents = Set(detectedAgents)
    }

    var name: String { app.setup.trimmedName.isEmpty ? app.name : app.setup.trimmedName }

    // MARK: Moving

    func go(_ to: Onboarding.Act) {
        // Past the name, a quit comes back here; before it nothing is kept.
        if to.afterNaming { save(to) }
        show(to)
    }

    /// Moves to `to` without saving it.
    private func show(_ to: Onboarding.Act) {
        // Leaving act 5, its practice request goes.
        if act == .howTo, to != .howTo, progress.practiceDue { app.runtime?.practice(false) }
        forward = to.index > act.index
        OnboardingSound.play(.step)
        withAnimation(.boopEase(0.45)) { progress.move(to: to) }
        entered(to)
    }

    /// Saves the act, or nil once done (`Onboarding.save`), and logs it
    /// when it can't.
    private func save(_ act: Onboarding.Act?) {
        do {
            try Onboarding.save(act, stateDir: stateDir)
        } catch {
            log("onboarding: can't save where it stands: \(error)")
        }
    }

    func next() {
        if let next = act.next { go(next) } else { finish() }
    }

    func back() {
        if let back = act.back { go(back) }
    }

    /// What an act does as it opens.
    func entered(_ act: Onboarding.Act) {
        switch act {
        case .smallThings:
            app.refreshLoginItem()
            askMic = !SpeechListener.allowed
            // On by default: Boop only watches while it's open.
            if !loginTouched, app.ownsHooks, app.loginItemState == .off { app.setOpenAtLogin(true) }
        case .finale:
            celebrate()
        default:
            break
        }
    }

    // MARK: Act 3

    /// Saves the name for keeps, and with it where onboarding stands, then moves on to the board. Boop's memory starts here.
    func saveName() {
        let draft = app.setup
        guard draft.canContinueName else { return }
        do {
            try Runtime.setUp(stateDir: stateDir, name: draft.trimmedName)
            try Onboarding.save(.body, stateDir: stateDir)
            nameError = nil
            log("onboarding: named \(draft.trimmedName)")
            show(.body)
        } catch {
            log("onboarding: can't save the name: \(error)")
            nameError = "I couldn't save my name. What happened is in boop.log, in my folder."
        }
    }

    // MARK: Act 4

    /// The board as the runtime sees it, once looking.
    enum Board: Equatable {
        case none
        /// Bluetooth is off, refused or missing: the app's device line,
        /// which says why and where it's fixed.
        case trouble(AppModel.DeviceState)
        case found(String)
    }

    var board: Board {
        let device = app.device
        guard device.connected else { return device.trouble == nil ? .none : .trouble(device) }
        return app.status?.device.map { .found(BoopDevice.advertised($0.id) ?? $0.id) } ?? .none
    }

    /// Whether the app talks to a board at all (not `--link none`).
    var hasLink: Bool { app.link != .none }

    /// Boop has its body: paired in act 4, or there now after a launch
    /// past it. The finale's tips are the board's then, else the Mac's.
    var hasBoard: Bool { body == .joined || app.status?.connected == true }

    /// Boop's body is the simulator, the board in the browser or the
    /// internal build's window, so the acts say where to find it and how to
    /// work it there.
    var onSimulator: Bool { app.onSimulator }

    /// Looks for a running simulator while act 4 asks for the body, off
    /// the main thread: it's a look at a socket. The internal build's
    /// window is always there to open.
    func watchForSimulator() async {
        if AppModel.simulatorKind == .window { simulatorHere = true }
        guard AppModel.simulatorKind == .browser else { return }
        while !Task.isCancelled {
            let here = await Task.detached { DeviceChooser.simulatorRuns() }.value
            if here != simulatorHere { withAnimation(.boopEase(0.3)) { simulatorHere = here } }
            try? await Task.sleep(for: .seconds(DeviceChooser.watchEvery))
        }
    }

    /// No board: the simulator is the body, until it stops, as Settings'
    /// choice is, or for good in the internal build. Chosen before the
    /// runtime starts, so Bluetooth isn't asked for.
    func useSimulator() {
        app.useSimulator()
        log("onboarding: the simulator is my body")
        lookForBoard()
    }

    func lookForBoard() {
        startRuntime()
        lookingSince = Date()
        withAnimation(.boopEase(0.4)) { body = .looking }
    }

    /// How often a found board beckons until it's tapped.
    static let beckonEvery: Duration = .seconds(6)

    /// While a board is found and not yet tapped, it beckons, holding up
    /// its sign, so you know which board is the one. It stops once it's
    /// tapped, lost, or the act moves on (the task is cancelled).
    func beckon() async {
        while !Task.isCancelled, case .found = board, body == .looking {
            app.runtime?.greet(.beckon)
            try? await Task.sleep(for: Self.beckonEvery)
        }
    }

    func skipBoard() {
        startRuntime()
        withAnimation(.boopEase(0.4)) { body = .skipped }
        next()
    }

    // MARK: Taps and hooks, from the runtime

    /// A tap on the board: its screen, or its button when `button`, on a
    /// finish that names whose turn it was when `onFinish`.
    func tapped(button: Bool, onFinish: Bool) {
        var found = false
        if case .found = board { found = true }
        var next = progress
        let tap = next.tapped(boardFound: found, button: button, onFinish: onFinish)
        if case .toured(let step) = tap { return toured(step, next) }
        guard tap != .nothing else { return }
        OnboardingSound.play(.success)
        if tap == .lesson(.amber) {
            app.runtime?.practice(false)
            log("onboarding: the practice request was answered; the amber lesson is done")
        }
        withAnimation(tap == .paired ? .spring(response: 0.55, dampingFraction: 0.6) : .boopPop) { progress = next }
        if case .lesson = tap { showPractice() }
        if tap == .paired {
            app.runtime?.greet(.wake)
            log("onboarding: the board was tapped; paired")
        }
    }

    /// Push-to-talk ended, with what the Mac heard, or nil for nothing.
    /// In act 5 the talk lesson shows it, and words do the lesson.
    func talked(_ words: String?) {
        guard act == .howTo else { return }
        var next = progress
        let done = next.talked(heardWords: words != nil)
        if done { OnboardingSound.play(.success) }
        withAnimation(done ? .spring(response: 0.55, dampingFraction: 0.6) : .boopPop) {
            talk = words.map(Talk.heard) ?? .nothing
            progress = next
        }
        if done { log("onboarding: push-to-talk heard words; the talk lesson is done") }
        showPractice()
    }

    /// How long after the third lesson the practice request comes up, so
    /// its tick is seen first.
    static let practiceAfter: Duration = .seconds(1.2)

    /// Once the first three lessons are done on a paired board, it glows
    /// amber with a practice request, as an agent waiting would, and the
    /// fourth lesson waits for a tap on it.
    func showPractice() {
        guard body == .joined, progress.practiceDue else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.practiceAfter)
            guard let self, self.progress.practiceDue else { return }
            self.app.runtime?.practice(true)
            self.log("onboarding: practice request on the board")
        }
    }

    func agentHook(_ agent: String) {
        var next = progress
        guard next.heard(agent) else { return }
        withAnimation(.boopPop) { progress = next }
        // Act 6 sent you to your terminal: the window comes back for the hello.
        bringForward()
        app.runtime?.greet(.hello)
        celebrate()
        log("onboarding: heard \(agent)'s first hook")
    }

    // MARK: Act 6's tour

    /// Whether act 6 tours, once an agent says hi: Boop has its body, and
    /// it draws the work stream and the agents' drawer (the gel's face).
    var tours: Bool { hasBoard && app.status?.device?.face == .gel }

    /// The window's Boop after the hello: the board's own state, live, so
    /// your agent's words fall past it too. No sound.
    var live: StateSnapshot {
        guard var snapshot = app.status?.snapshot else { return .onboarding(mood: "excited") }
        snapshot.vol = 0
        return snapshot
    }

    /// The agent that said hi has a lane in the work stream: its words
    /// are falling.
    var wordsFalling: Bool {
        guard let heard else { return false }
        return app.status?.sessions.contains { $0.agent == heard && $0.word != nil } == true
    }

    /// The tour's first step, once the words fall.
    func sawWords() {
        var next = progress
        if next.did(.words) { toured(.words, next) }
    }

    /// The board's agents' drawer opened (`open`), or a row in it was
    /// picked (`pick`).
    func drawer(_ did: String) {
        guard did == "open" || did == "pick" else { return }
        var next = progress
        if next.drawer(picked: did == "pick") { toured(did == "pick" ? .row : .drawer, next) }
    }

    /// How long after a thread opens on the Mac the window comes back, so
    /// you see it open first.
    static let backAfter: Duration = .seconds(1.5)

    /// A step of the tour is done, as `next` says. The steps that open a
    /// thread bring the window back after it, and the last one celebrates.
    private func toured(_ step: Onboarding.Progress.Tour, _ next: Onboarding.Progress) {
        OnboardingSound.play(.success)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { progress = next }
        log("onboarding: the tour's \(step) step is done")
        guard step == .cheer || step == .row else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.backAfter)
            guard let self, self.act == .agents else { return }
            self.bringForward()
            if self.tourDue == nil { self.celebrate() }
        }
    }

    /// The thread of the agent that said hi that last finished a turn,
    /// whose name the cheer holds up and a tap on it opens.
    var finishedThread: SessionSummary? {
        app.status?.sessions.filter { $0.agent == heard && $0.status == .idle && $0.thread != nil }
            .max { ($0.since ?? .distantPast) < ($1.since ?? .distantPast) }
    }

    /// How often Boop cheers for the finished turn until it's tapped: the
    /// finish lingers a while after it plays.
    static let cheerEvery: Duration = .seconds(8)

    /// While the cheer is the tour's step, Boop cheers on the board and on
    /// screen for the agent's finished turn, naming its thread, once the
    /// turn has finished. It stops once it's tapped, or the act moves on
    /// (the task is cancelled).
    func cheer() async {
        while !Task.isCancelled, tourDue == .cheer {
            guard let session = finishedThread, let thread = session.thread else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let who = DeviceReaction.Who(agent: session.agent, thread: session.name ?? session.project, opens: thread)
            app.runtime?.cheer(who)
            feed.reaction(DeviceReaction(anim: "task_complete", loops: 2, who: who, outcome: "success"))
            try? await Task.sleep(for: Self.cheerEvery)
        }
    }

    // MARK: Act 6

    var detectedAgents: [Agent] { Agent.allCases.filter(app.installer.detected) }

    /// Connects the agents chosen; the app backs up each one's settings first.
    /// A copy on another folder leaves the hooks to the everyday Boop, and
    /// only listens for the hello.
    func connectAgents() {
        let chosen = Agent.allCases.filter { app.ownsHooks && app.setup.agents.contains($0) && app.installer.detected($0) }
        for agent in chosen { app.install(agent) }
        // Every one failed: stay on the choice, which says why, so Connect
        // can be tried again rather than wait for a hello that can't come.
        if !chosen.isEmpty, chosen.allSatisfy({ app.hookErrors[$0] != nil }) { return }
        withAnimation(.boopPop) { connected = true }
    }

    // MARK: Act 7

    func askForMic() {
        mic = .asking
        SpeechListener(log: log).authorize { why in
            Task { @MainActor [weak self] in
                withAnimation(.boopPop) { self?.mic = why.map(Mic.refused) ?? .allowed }
            }
        }
    }

    // MARK: Act 8

    /// A click on the on-screen Boop: it pokes back, as the board does.
    func pokeOnScreen() {
        feed.poke()
        OnboardingSound.play(.step)
    }

    func celebrate() {
        confetti += 1
        OnboardingSound.play(.success)
        if act == .finale { app.runtime?.greet(.finale) }
    }

    func finish() {
        log("onboarding: finished")
        save(nil)
        finished()
    }
}

/// Small sounds for onboarding's moments, quietly: a step, and a success.
/// Off where nobody listens (snapshots).
enum OnboardingSound {
    enum Kind { case step, success }
    nonisolated(unsafe) static var enabled = true

    static func play(_ kind: Kind) {
        guard enabled, let sound = NSSound(named: kind == .step ? "Pop" : "Glass")?.copy() as? NSSound else { return }
        sound.volume = kind == .step ? 0.2 : 0.35
        sound.play()
    }
}
