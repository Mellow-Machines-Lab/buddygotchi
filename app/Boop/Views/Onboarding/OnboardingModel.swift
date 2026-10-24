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
    @Published private(set) var act: Onboarding.Act
    /// The last move went forward, for which way the acts slide.
    @Published private(set) var forward = true

    // Act 3: why naming couldn't save, if it couldn't.
    @Published var nameError: String?

    // Act 4: the board.
    enum Body: Equatable {
        /// Plug me in, and why macOS will ask about Bluetooth.
        case intro
        /// "Look for me" was pressed: the runtime is looking.
        case looking
        /// The board was tapped: Boop jumped into it.
        case joined
        /// "I don't have my Boop yet."
        case skipped
    }
    @Published var body = Body.intro
    /// When looking started, for the "can't find me" hint.
    @Published var lookingSince: Date?

    // Act 5: the lessons done on the board.
    enum Lesson: Hashable { case tap, button }
    @Published var lessons: Set<Lesson> = []

    // Act 6: the agents.
    @Published var connected = false
    /// The agent whose first hook was heard, by name.
    @Published var heard: String?
    @Published var showHooks = false

    // Act 7: the microphone and speech, once asked.
    enum Mic: Equatable { case notAsked, asking, allowed, refused(String) }
    @Published var mic = Mic.notAsked
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
    var log: (String) -> Void = { _ in }

    init(app: AppModel, act: Onboarding.Act, stateDir: URL) {
        self.app = app
        self.act = act
        self.stateDir = stateDir
        if act.index > Onboarding.Act.body.index { body = .skipped }
        if act.index > Onboarding.Act.agents.index { connected = true }
        app.setup.agents = Set(Agent.allCases.filter(app.installer.detected))
    }

    var name: String { app.setup.trimmedName.isEmpty ? app.name : app.setup.trimmedName }

    // MARK: Moving

    func go(_ to: Onboarding.Act) {
        forward = to.index > act.index
        OnboardingSound.play(.step)
        withAnimation(.boopEase(0.45)) { act = to }
        // Past the name, a quit comes back here; before it nothing is kept.
        if to.afterNaming { app.runtime?.setOnboarding(to) }
        entered(to)
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
        case .howTo:
            if body == .joined { lessons.insert(.tap) }
        case .smallThings:
            app.refreshLoginItem()
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
            var settings = AppSettings.load(from: stateDir)
            settings.onboarding = .body
            try settings.save(to: stateDir)
            nameError = nil
            log("onboarding: named \(draft.trimmedName), \(draft.nature.rawValue)")
            go(.body)
        } catch {
            log("onboarding: can't save the name: \(error)")
            nameError = "I couldn't save my name. What happened is in boop.log, in my folder."
        }
    }

    // MARK: Act 4

    /// The board as the runtime sees it, once looking.
    enum Board: Equatable {
        case none
        /// Bluetooth is off, refused or missing: the link's words.
        case trouble(String)
        case found(String)
    }

    var board: Board {
        guard let status = app.status else { return .none }
        if let why = status.linkTrouble { return .trouble(why) }
        if status.connected, let device = status.device { return .found(BoopDevice.advertised(device.id) ?? device.id) }
        return .none
    }

    /// Whether the app talks to a board at all (not `--link none`).
    var hasLink: Bool { app.link != .none }

    func lookForBoard() {
        startRuntime()
        lookingSince = Date()
        withAnimation(.boopEase(0.4)) { body = .looking }
    }

    func skipBoard() {
        startRuntime()
        withAnimation(.boopEase(0.4)) { body = .skipped }
        next()
    }

    // MARK: Taps and hooks, from the runtime

    func tapped() {
        switch act {
        case .body where body == .looking:
            if case .found = board {
                OnboardingSound.play(.success)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { body = .joined }
                app.runtime?.greet(.wake)
                lessons.insert(.tap)
                log("onboarding: the board was tapped; paired")
            }
        case .howTo:
            guard !lessons.contains(.button) else { return }
            OnboardingSound.play(.success)
            withAnimation(.boopPop) {
                if lessons.contains(.tap) { lessons.insert(.button) } else { lessons.insert(.tap) }
            }
        default:
            break
        }
    }

    func agentHook(_ agent: String) {
        guard act == .agents, connected, heard == nil else { return }
        withAnimation(.boopPop) { heard = agent }
        app.runtime?.greet(.celebrate)
        celebrate()
        log("onboarding: heard \(agent)'s first hook")
    }

    // MARK: Act 6

    var detectedAgents: [Agent] { Agent.allCases.filter(app.installer.detected) }

    /// Connects the agents chosen; the app backs up each one's settings first.
    func connectAgents() {
        for agent in Agent.allCases where app.setup.agents.contains(agent) && app.installer.detected(agent) {
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
        feed.reaction(id: 0, DeviceReaction(anim: "poked"))
        OnboardingSound.play(.step)
    }

    func celebrate() {
        confetti += 1
        OnboardingSound.play(.success)
        if act == .finale { app.runtime?.greet(.celebrate) }
    }

    func finish() {
        log("onboarding: finished")
        app.runtime?.setOnboarding(nil)
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
