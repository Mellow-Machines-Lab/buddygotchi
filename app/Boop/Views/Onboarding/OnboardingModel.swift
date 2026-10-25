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

    // Act 3: why naming couldn't save, if it couldn't.
    @Published var nameError: String?

    // Act 4: when looking started, for the "can't find me" hint.
    @Published var lookingSince: Date?

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

    /// Saves the name and nature for keeps, and with them where onboarding
    /// stands, then moves on to the board. Boop's memory starts here.
    func saveName() {
        let draft = app.setup
        guard draft.canContinueName else { return }
        do {
            try Runtime.setUp(stateDir: stateDir, name: draft.trimmedName, nature: draft.nature)
            try Onboarding.save(.body, stateDir: stateDir)
            nameError = nil
            log("onboarding: named \(draft.trimmedName), \(draft.nature.rawValue)")
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

    /// A tap on the board: its screen, or its button when `button`.
    func tapped(button: Bool) {
        var found = false
        if case .found = board { found = true }
        var next = progress
        let tap = next.tapped(boardFound: found, button: button)
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
        app.runtime?.greet(.celebrate)
        celebrate()
        log("onboarding: heard \(agent)'s first hook")
    }

    // MARK: Act 6

    var detectedAgents: [Agent] { Agent.allCases.filter(app.installer.detected) }

    /// Connects the agents chosen; the app backs up each one's settings first.
    /// A copy on another folder leaves the hooks to the everyday Boop, and
    /// only listens for the hello.
    func connectAgents() {
        for agent in Agent.allCases where app.ownsHooks && app.setup.agents.contains(agent) && app.installer.detected(agent) {
            app.install(agent)
        }
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
        if act == .finale { app.runtime?.greet(.celebrate) }
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
