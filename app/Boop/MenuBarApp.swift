import AgentHooks
import AppKit
import BoopKit
import SwiftUI

/// The menu-bar app: an icon that mirrors Boop and a popover.
/// Setup and settings open inside the popover. It pops up by itself only
/// once, on first launch, to show setup, and never sends notifications.
enum MenuBarApp {
    static func run(_ args: Arguments) -> Never {
        let stateDir = args["--state-dir"].map { URL(fileURLWithPath: $0) } ?? AppSettings.defaultStateDir()
        guard let link = LinkSetting(args["--link"] ?? "ble") else { fail("--link is ble, usb:SOCKET or none") }
        let debug = args.has("--debug")
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate(stateDir: stateDir, link: link, debug: debug)
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) { app.run() }
        }
        exit(0)
    }
}

enum Pane: Equatable {
    case overview, settings, setup
}

/// What the person has chosen so far in setup. It lives in the model, so
/// closing the popover halfway through loses nothing.
struct SetupDraft {
    enum Step: Int, CaseIterable {
        case hello, name, agents, ready
    }

    var step = Step.hello
    var name = ""
    var nature = LongTerm.Nature.sweet
    var agents = Set(Agent.allCases)
    var error: String?

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The memory file accepts 23 characters, not the device protocol's
    /// 23 bytes. Keep the field's normalization and
    /// control-character cleanup without cutting Unicode names early.
    mutating func editName(_ text: String) {
        name = String(StateSnapshot.clip(text, max: Int.max).prefix(23))
    }

    var nameIssue: String? {
        trimmedName.contains("·") || trimmedName.contains(":") ? "Names can't contain · or :." : nil
    }

    var canContinueName: Bool { !trimmedName.isEmpty && nameIssue == nil }
}

/// What the views show. Updated on the main thread only.
@MainActor
final class AppModel: ObservableObject {
    @Published var pane = Pane.overview
    /// The popover is open. Its views live on while it's closed, so they
    /// hold their loops still until it opens again.
    @Published var shown = false
    @Published var setup = SetupDraft()
    @Published var status: Runtime.Status?
    let slime = SlimeFeed()
    @Published var hooks: [Agent: HookInstaller.Health] = [:]
    @Published var restartAgents = false
    /// Why the last Connect, Repair or Remove failed, per agent, until its
    /// hooks change.
    @Published var hookErrors: [Agent: String] = [:]
    /// The agents whose failed change the Overview no longer shows. Settings'
    /// row still says why, until the hooks change.
    @Published var hookErrorsDismissed: Set<Agent> = []
    @Published var startError: String?
    /// A simulator on this Mac, as a body to choose (`DeviceChooser`).
    enum Simulator { case none, there, inUse }
    @Published var simulator = Simulator.none
    var usingSimulator: Bool { simulator == .inUse }
    var devices: DeviceChooser? {
        didSet { devices?.onChoice { [weak self] _ in Task { @MainActor in self?.lookForSimulator() } } }
    }
    /// The "can't react yet" notice was closed, for this launch.
    @Published var noKeyDismissed = false

    let installer: HookInstaller
    /// False on a folder other than the everyday one: then this copy never
    /// changes the real hooks.
    let ownsHooks: Bool
    let link: LinkSetting
    var runtime: Runtime?
    var finishSetup: () -> Void = {}
    /// Shows `boop.log` in Finder.
    var showLog: () -> Void = {}
    /// Reads Jev's key. Settings calls it off the main thread, since the
    /// Keychain may stop to ask for access; snapshots read none.
    var readKey: @Sendable () -> String? = { Keychain.jevKey() }

    init(installer: HookInstaller, ownsHooks: Bool = true, link: LinkSetting) {
        self.installer = installer
        self.ownsHooks = ownsHooks
        self.link = link
        refreshHooks()
    }

    var name: String { status?.name ?? "Boop" }
    /// Who Boop is, chosen in settings.
    var personality: Personality { status?.personality ?? .default }

    /// Hooks that changed since the last look, however they changed, make
    /// a failed change's reason stale, so it goes.
    func refreshHooks() {
        let before = hooks
        hooks = Dictionary(uniqueKeysWithValues: Agent.allCases.map { ($0, installer.health($0)) })
        for agent in Agent.allCases where before[agent] != nil && before[agent] != hooks[agent] { hookErrors[agent] = nil }
    }

    func install(_ agent: Agent) {
        changeHooks(agent) { try installer.install(agent) }
    }

    func remove(_ agent: Agent) {
        changeHooks(agent) { try installer.remove(agent) }
    }

    /// Only a change that worked asks for a restart; one that failed says
    /// why on the agent's row.
    private func changeHooks(_ agent: Agent, _ change: () throws -> Void) {
        hookErrorsDismissed.remove(agent)
        guard ownsHooks else {
            hookErrors[agent] = "only the everyday Boop changes them"
            return
        }
        var why: String?
        do {
            try change()
            restartAgents = true
        } catch {
            why = error.localizedDescription
        }
        refreshHooks()
        hookErrors[agent] = why
    }

    /// Closes the Overview's notice for a change that failed.
    func dismissHookError(_ agent: Agent) {
        hookErrorsDismissed.insert(agent)
    }

    var listening: Bool { status?.listening == true }

    /// Jev's key has been read and there's none, so Boop can't react.
    /// While a Keychain prompt waits, nobody knows yet.
    var noKey: Bool { status.map { $0.keyRead && $0.brain == "none" } ?? false }

    /// How things are, in a few words: the Overview's status line, and the
    /// menu-bar icon's tooltip and what VoiceOver reads for it.
    var headline: String {
        guard let s = status?.snapshot else {
            return startError == nil ? "Waking up…" : "Not running"
        }
        if listening { return "Listening…" }
        if s.waiting > 0 { return s.waiting == 1 ? "Needs you" : "\(s.waiting) sessions need you" }
        switch s.base {
        case "working": return s.busy == 1 ? "Working on 1 session" : "Working on \(s.busy) sessions"
        case "idle": return "Hanging out"
        default: return "Napping"
        }
    }

    /// The mic button: click to talk, click again to send.
    func toggleTalk() {
        let on = !listening
        if on { status?.micTrouble = nil }
        status?.listening = on
        runtime?.setListening(on)
    }

    /// Hides the "can't hear you" notice until the next try.
    func dismissMicTrouble() {
        status?.micTrouble = nil
        runtime?.dismissMicTrouble()
    }

    /// How Boop's body stands, in the words the Overview's device line and
    /// Settings both use.
    struct DeviceState {
        var connected: Bool
        /// Something only the person can fix.
        var trouble = false
        /// A word or two, for the Overview.
        var short: String
        /// A sentence, for Settings and the device line's help.
        var detail: String
    }

    /// Looks for a running simulator, off the main thread: it's a look at
    /// a socket. Only while there's someone to show it to: Settings, open.
    func lookForSimulator() {
        guard let devices else { return }
        DispatchQueue.global(qos: .utility).async {
            let found: Simulator = devices.choice == .simulator ? .inUse : devices.simulatorIsThere() ? .there : .none
            Task { @MainActor in if found != self.simulator { self.simulator = found } }
        }
    }

    func use(_ choice: DeviceChoice) { devices?.choose(choice) }

    var device: DeviceState {
        let how = switch link {
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .none: ""
        }
        // "Connected over Bluetooth", "Connected to the simulator".
        let over = usingSimulator ? "to the simulator" : "over \(how)"
        guard let status else {
            return startError == nil ? DeviceState(connected: false, short: "Starting…", detail: "\(name) is starting.")
                : DeviceState(connected: false, short: "Not running", detail: "\(name) isn't running, so it isn't looking for its body.")
        }
        if link == .none {
            return DeviceState(connected: false, short: "No device", detail: "This copy of Boop runs without a device.")
        }
        guard status.connected else {
            if let why = status.linkTrouble { return DeviceState(connected: false, trouble: true, short: "No \(how)", detail: why) }
            if usingSimulator {
                return DeviceState(connected: false, short: "Looking…", detail: "Looking for the simulator. Open its page in a browser.")
            }
            return DeviceState(connected: false, short: "Looking…", detail: "Looking for it over \(how). Plug it into USB power.")
        }
        // Its firmware doesn't fit the app, so it gets the looks but no
        // reactions (linkkit/SPEC.md §6).
        if let why = status.deviceTrouble {
            return DeviceState(connected: true, trouble: true, short: "Wrong firmware", detail: "Connected \(over), but \(why).")
        }
        // Its card's voice isn't the app's, so it gets no takes.
        // `none` is no card, one it can't read, or no pack on it.
        if let voice = status.device?.voice, status.device?.hasTheVoice == false {
            let card = voice == "none" ? "it has no card, or no voice pack on its card" : "its card's voice pack isn't this app's"
            return DeviceState(connected: true, trouble: true, short: "No voice",
                               detail: "Connected \(over), but \(card), so \(name) can't talk. "
                                   + "Put the app's voice pack on a FAT32 card in the board, then press the board's reset button.")
        }
        return DeviceState(connected: true, short: "Connected", detail: "Connected \(over).")
    }

    // The switches show the change at once; the runtime's next status confirms it.

    func setVolume(_ volume: Int) {
        guard status?.snapshot.vol != volume else { return }
        status?.snapshot.vol = volume
        runtime?.setVolume(volume)
    }

    /// Takes effect from the next event.
    func setPersonality(_ personality: Personality) {
        guard personality != self.personality else { return }
        status?.personality = personality
        runtime?.setPersonality(personality)
    }

    /// Saves a bug report, shows it in Finder and
    /// copies its path, to hand to an agent.
    func saveReport() {
        runtime?.saveReport { dir in
            Task { @MainActor in
                guard let dir else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dir.path, forType: .string)
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            }
        }
    }

    /// What "Boop couldn't start" says, in plain words; the log keeps the
    /// error itself.
    static func startProblem(_ error: Error) -> String {
        switch error {
        case Runtime.OpenError.locked: "Another copy of Boop is already running. Quit it, then open this one again."
        case is HookServer.StartError: "Boop can't listen for your agents' hooks. Quit other copies of Boop and open it again."
        default: "Something went wrong while starting. What happened is in boop.log, in Boop's folder."
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let stateDir: URL
    /// Debug mode: everything printed to the terminal that
    /// started the app, and every pass to `debug.jsonl`.
    let debug: Bool
    let log: LogFile
    let model: AppModel
    var statusItem: NSStatusItem?
    private var iconMood: FaceMood?
    let popover = NSPopover()

    init(stateDir: URL, link: LinkSetting, debug: Bool) {
        self.stateDir = stateDir
        self.debug = debug
        log = LogFile(directory: stateDir, echo: debug)
        // On another folder the installer still reads the real hooks, as the
        // everyday Boop keeps them, so settings shows how they stand.
        let everyday = AppSettings.isEveryday(stateDir)
        let hookDir = everyday ? stateDir : AppSettings.defaultStateDir()
        model = AppModel(installer: .boop(home: URL(fileURLWithPath: NSHomeDirectory()),
                                          hookPath: hookDir.appendingPathComponent("bin/\(HookInstaller.client)").path),
                         ownsHooks: everyday, link: link)
        super.init()
    }

    /// A menu bar that's never shown. A menu-bar-only app has none, but
    /// ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z reach a text field through the Edit menu's
    /// shortcuts, so without one the popover's fields (Boop's name in setup,
    /// Jev's key in settings) can't paste.
    static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let menu = NSMenu()
        menu.addItem(NSMenuItem())  // where the app menu would go
        let item = NSMenuItem()
        item.submenu = edit
        menu.addItem(item)
        return menu
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppDelegate.editMenu()
        if model.ownsHooks {
            placeHookClient()
            // agent-hook sends to every socket listed in agent-hooks' folder:
            // Boop's is listed as a link.
            do {
                try HookSocket.register(stateDir.appendingPathComponent("boop.sock").path, as: "boop")
            } catch {
                log.write("hooks: can't list boop.sock in \(HookSocket.directory()): \(error)")
            }
            let repaired = model.installer.repair()
            if !repaired.isEmpty {
                log.write("hooks: repaired \(repaired.map(\.rawValue).joined(separator: ", "))")
                model.restartAgents = true
            }
        } else {
            // They report to the everyday Boop's socket, so pointing them here
            // would only break them once this folder is gone.
            log.write("hooks: left alone, since only the everyday Boop (\(AppSettings.defaultStateDir().path)) installs "
                      + "or repairs them; agent hooks reach its socket, not this one")
        }
        model.refreshHooks()
        model.finishSetup = { [weak self] in self?.finishSetup() }
        model.showLog = { [log] in NSWorkspace.shared.activateFileViewerSelecting([log.url]) }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        updateIcon()

        let host = NSHostingController(rootView: PopoverView(model: model) { [weak self] in self?.popover.performClose(nil) })
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        // Panes change height; an animated resize would clip them mid-way.
        popover.animates = false
        popover.delegate = self

        let memory = try? MemoryStore(directory: stateDir, log: { [log] in log.write($0) })
        if memory?.isSetUp == true {
            startRuntime()
        } else {
            // First launch: open the popover on setup, once, so the person
            // sees where Boop lives.
            model.pane = .setup
            model.setup.agents = Set(Agent.allCases.filter(model.installer.detected))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.showPopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.runtime?.stop()
    }

    /// The hooks call a stable copy of agent-hooks' `agent-hook` in the
    /// state directory, so a rebuilt or moved app doesn't break them.
    func placeHookClient() {
        let fm = FileManager.default
        guard let built = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(HookInstaller.client),
              fm.isExecutableFile(atPath: built.path) else {
            let placed = model.installer.clientInPlace ? "keeping the copy in place" : "hooks can't be installed or repaired"
            log.write("hooks: no \(HookInstaller.client) next to the app; \(placed)")
            return
        }
        let target = URL(fileURLWithPath: model.installer.hookPath)
        if fm.contentsEqual(atPath: built.path, andPath: target.path) { return }
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let staged = target.appendingPathExtension("new")
            try? fm.removeItem(at: staged)
            try fm.copyItem(at: built, to: staged)
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } catch {
            log.write("hooks: can't place \(HookInstaller.client): \(error)")
        }
    }

    let presenceSignals = PresenceSignals()

    func startRuntime() {
        // In debug mode the dashboard can drive `make debug`; plain `make
        // run` stays deaf to it.
        var options = runtimeOptions(stateDir: stateDir, socketPath: stateDir.appendingPathComponent("boop.sock").path,
                                     link: model.link, debug: debug, devLines: debug, log: log)
        // Here and away: the Mac's idle time on
        // every tick, and its locks, sleeps and wakes below.
        options.idleMs = PresenceSignals.idleMs
        model.devices = options.link as? DeviceChooser
        do {
            let runtime = try Runtime(options)
            runtime.onChange = { [weak self] status in Task { @MainActor in self?.model.status = status; self?.updateIcon() } }
            runtime.onMoment = { [weak self] id, moment in Task { @MainActor in self?.model.slime.moment(id: id, moment) } }
            // Push-to-talk: the core says when the mic
            // is on; what it heard goes back to the runtime.
            let listener = SpeechListener(log: { [log] in log.write($0) })
            runtime.onListen = { (on: Bool) in
                if on {
                    listener.start { why in runtime.micFailed(why) }
                } else {
                    listener.stop { words in
                        if let words { runtime.said(words) } else { runtime.heardNothing() }
                    }
                }
            }
            presenceSignals.start { runtime.presence($0) }
            // A simulator started or stopped on this Mac: looked for while
            // Settings is open to show it.
            let look = Timer.scheduledTimer(withTimeInterval: DeviceChooser.watchEvery, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let model = self?.model, model.shown, model.pane == .settings else { return }
                    model.lookForSimulator()
                }
            }
            look.tolerance = 0.5
            try runtime.start()
            model.runtime = runtime
            model.startError = nil
            runtime.refresh()
        } catch {
            log.write("boop: can't start: \(error)")
            model.startError = AppModel.startProblem(error)
            updateIcon()
        }
    }

    /// Every status push lands here, and most change neither the look nor
    /// the words.
    func updateIcon() {
        guard let button = statusItem?.button else { return }
        let mood = model.startError == nil ? FaceMood(model.status) : .stopped
        if mood != iconMood {
            iconMood = mood
            button.image = MenuBarIcon.image(mood)
        }
        let words = "\(model.name): \(model.headline)"
        if button.toolTip != words {
            button.toolTip = words
            button.setAccessibilityLabel(words)
        }
    }

    @objc func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button else { return }
        model.refreshHooks()
        model.runtime?.refresh()
        NSApp.activate()
        model.shown = true
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    /// Settings closes back to the overview; setup stays where it was.
    func popoverDidClose(_ notification: Notification) {
        model.shown = false
        if model.pane == .settings { model.pane = .overview }
    }

    func finishSetup() {
        let draft = model.setup
        do {
            try Runtime.setUp(stateDir: stateDir, name: draft.trimmedName, nature: draft.nature)
        } catch {
            log.write("setup: \(error)")
            model.setup.error = "Boop couldn't save its memory. What happened is in boop.log, in Boop's folder."
            return
        }
        for agent in Agent.allCases
        where model.ownsHooks && draft.agents.contains(agent) && model.installer.detected(agent) {
            model.install(agent)
        }
        startRuntime()
        withAnimation(.boopSettle) { model.pane = .overview }
    }
}
