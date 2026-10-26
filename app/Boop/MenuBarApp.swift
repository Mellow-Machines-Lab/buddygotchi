import AgentHooks
import AppKit
import BoopKit
import LinkKit
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
            // Ctrl-C on `make dev`, or a kill: quit as the menu's Quit does,
            // so the runtime stops and the next launch doesn't count it as
            // a crash.
            let signals = [SIGINT, SIGTERM].map { sig in
                signal(sig, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
                source.setEventHandler { NSApp.terminate(nil) }
                source.resume()
                return source
            }
            withExtendedLifetime((delegate, signals)) { app.run() }
        }
        exit(0)
    }
}

enum Pane: Equatable {
    case overview, settings
}

/// What the person has chosen so far in onboarding: a name, and which
/// agents to watch. It lives in the app's model, so moving between
/// acts loses nothing.
struct SetupDraft {
    var name = ""
    var agents = Set(Agent.allCases)

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The memory file accepts 23 characters, not the device protocol's
    /// 23 bytes. Keep the field's normalization and
    /// control-character cleanup without cutting Unicode names early.
    mutating func editName(_ text: String) {
        name = String(StateSnapshot.clip(text, max: Int.max).prefix(23))
    }

    var nameIssue: String? {
        trimmedName.contains("·") || trimmedName.contains(":") ? "Names can't use “·” or “:”." : nil
    }

    var canContinueName: Bool { !trimmedName.isEmpty && nameIssue == nil }
}

/// What the views show. Updated on the main thread only.
@MainActor
final class AppModel: ObservableObject {
    @Published var pane = Pane.overview
    /// The popover is open. Its views live on while it's closed, so they
    /// hold their loops still until it opens again.
    @Published var shown = false {
        didSet { if shown { catchUp() } }
    }
    /// Onboarding's window is open: its acts show the status too.
    var onboardingShown = false {
        didSet { if onboardingShown { catchUp() } }
    }
    @Published var setup = SetupDraft()
    /// What the views show. It changes only when what they show does, and
    /// only while something shows it: the popover, or onboarding.
    @Published var status: Runtime.Status?
    /// The runtime's latest status, kept whether or not anything shows it:
    /// the menu-bar icon reads it, and `status` catches up with it when the
    /// popover opens.
    private(set) var latest: Runtime.Status?
    let slime = SlimeFeed(mirrorsBoard: true)
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
    /// The "no brain yet" notice was closed, for this launch.
    @Published var noKeyDismissed = false
    /// The firmware Boop.app carries for each board (none for `make dev`'s bare binary).
    var boardFirmware = BoardFirmware.bundled()
    /// Writing firmware onto the board over USB, from Settings.
    enum FirmwareWrite: Equatable {
        case idle
        case writing(Double)
        case done(String)
        case failed(String)
    }
    @Published var firmwareWrite = FirmwareWrite.idle
    /// Writes to `boop.log`.
    var log: @Sendable (String) -> Void = { _ in }

    /// Opening Boop at login, and how it stands.
    var loginItem = LoginItem.system()
    @Published var loginItemState = LoginItem.State.unavailable
    /// Why the last change to it failed, until the next try.
    @Published var loginItemError: String?

    let installer: HookInstaller
    /// False on a folder other than the everyday one: then this copy never
    /// changes the real hooks.
    let ownsHooks: Bool
    /// Where `HookBackup` keeps the agents' settings from before Boop
    /// changed them; nil keeps none (snapshots).
    var backupStateDir: URL?
    let link: LinkSetting
    var runtime: Runtime?
    /// Starts the runtime again, after it couldn't start.
    var start: () -> Void = {}
    /// Asks, then takes Boop off this Mac and quits (`Uninstall`).
    var uninstall: () -> Void = {}
    /// The Keychain entry this copy keeps Jev's key in
    /// (`Keychain.account(for:)`).
    let keyAccount: String
    /// Reads Jev's key. Settings calls it off the main thread, since the
    /// Keychain may stop to ask for access; snapshots read none.
    var readKey: @Sendable () -> String?

    init(installer: HookInstaller, ownsHooks: Bool = true, link: LinkSetting, keyAccount: String) {
        self.installer = installer
        self.ownsHooks = ownsHooks
        self.link = link
        self.keyAccount = keyAccount
        readKey = { Keychain.jevKey(account: keyAccount) }
        refreshHooks()
    }

    /// Saves Jev's key in this copy's entry, off the main thread, since
    /// the Keychain may stop to ask, and gives it to the brain from the
    /// next event. True when the Keychain holds it.
    func saveKey(_ key: String) async -> Bool {
        let key = Keychain.cleaned(key), account = keyAccount
        guard await Task.detached(operation: { Keychain.setJevKey(key, account: account) }).value else { return false }
        runtime?.reloadBrain(jevKey: key.isEmpty ? nil : key)
        return true
    }

    var name: String { status?.name ?? "Boop" }

    /// A status from the runtime. The work stream's lanes are left out:
    /// they change every few hundred milliseconds while an agent works,
    /// and only the board's mirror shows them, which the board's own lines
    /// feed. Onboarding keeps them: its own slime shows the agent's words
    /// falling after the hello, fed its snapshot, not the board's lines.
    /// The views get it only when it changed and something shows it.
    func take(_ status: Runtime.Status) {
        var status = status
        if !onboardingShown { status.snapshot.calls = [] }
        status.buddies = status.buddies.map { buddy in
            var buddy = buddy
            buddy.snapshot.calls = []
            return buddy
        }
        latest = status
        if shown || onboardingShown { catchUp() }
    }

    /// The views' `status`, brought up to the runtime's latest, when it differs.
    private func catchUp() {
        if let latest, status != latest { status = latest }
    }

    /// The firmware the board should take: its board's, when it runs an
    /// older version than the app carries, or another character pack; or,
    /// when its firmware doesn't fit the app at all, the app's, whichever
    /// fits its chip once it's on USB.
    var firmwareOffer: BoardFirmware? {
        if let device = status?.device { return BoardFirmware.update(for: device, among: boardFirmware) }
        return status?.deviceTrouble == nil ? nil : boardFirmware.first
    }

    /// The update a write that began and didn't finish was for, for Try
    /// again: the board, half written, has left Bluetooth and its offer
    /// with it, but its MAC still says which board it is.
    private var unfinished: (board: String?, firmware: [BoardFirmware])?

    /// Writes the app's firmware onto the board on USB, off the main
    /// thread, and says how it goes in `firmwareWrite`. The offer is for
    /// the board on Bluetooth, whether its firmware fits or not, so the
    /// one on USB must be that one, as its MAC says; it gets the image for
    /// the chip its bootloader reports.
    func updateFirmware() {
        if case .usb = link {
            firmwareWrite = .failed("this Boop is using the board's USB port itself. Update it from Boop.app, over Bluetooth.")
            return
        }
        let ports = BoardFirmware.usbPorts()
        guard let port = ports.first else {
            firmwareWrite = .failed("plug \(name)'s body into this Mac with a USB cable that carries data, then try again.")
            return
        }
        guard ports.count == 1 else {
            firmwareWrite = .failed("more than one board is plugged in. Leave only \(name)'s, then try again.")
            return
        }
        // A board whose firmware fits takes its board's firmware; one whose doesn't, whichever fits its chip.
        guard let update = unfinished ?? firmwareOffer.map({ offer in
            (board: status?.device?.id ?? status?.misfit, firmware: status?.device == nil ? boardFirmware : [offer])
        }) else {
            firmwareWrite = .idle  // nothing to offer any more
            return
        }
        unfinished = update
        firmwareWrite = .writing(0)
        let log = self.log
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var shown = -1
            do {
                let written = try BoardFirmware.install(update.firmware, on: update.board, port: port, log: log) { done in
                    let percent = Int(done * 100)
                    guard percent != shown else { return }
                    shown = percent
                    Task { @MainActor in self?.firmwareWrite = .writing(done) }
                }
                Task { @MainActor in
                    self?.unfinished = nil
                    self?.firmwareWrite = .done(written.version)
                }
            } catch {
                log("firmware: couldn't update: \(error)")
                Task { @MainActor in
                    // Refused before anything was written: the next try asks again.
                    if error is BoardFirmware.Refusal { self?.unfinished = nil }
                    self?.firmwareWrite = .failed("\(error)")
                }
            }
        }
    }

    func refreshLoginItem() {
        let now = loginItem.state()
        if loginItemState != now { loginItemState = now }
    }

    /// Turns opening at login on or off. Only the everyday Boop does: a copy
    /// on another folder would open at login in its place.
    func setOpenAtLogin(_ on: Bool) {
        guard ownsHooks else {
            loginItemError = "only the everyday Boop opens at login"
            return
        }
        do {
            try loginItem.set(on)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }
    /// Who Boop is, chosen in settings.
    var personality: Personality { status?.personality ?? .default }
    /// How much it says, chosen in settings.
    var talk: Talk { status?.talk ?? .default }

    /// Hooks that changed since the last look, however they changed, make
    /// a failed change's reason stale, so it goes.
    func refreshHooks() {
        show(hooks: Self.health(installer))
    }

    private nonisolated static func health(_ installer: HookInstaller) -> [Agent: HookInstaller.Health] {
        Dictionary(uniqueKeysWithValues: Agent.allCases.map { ($0, installer.health($0)) })
    }

    private func show(hooks now: [Agent: HookInstaller.Health]) {
        guard now != hooks else { return }
        let before = hooks
        hooks = now
        for agent in Agent.allCases where before[agent] != nil && before[agent] != hooks[agent] { hookErrors[agent] = nil }
    }

    /// The hooks and the login item, read off the main thread, as the
    /// popover opens: the agents' settings files are parsed, and the login
    /// item's state asks macOS. Each is assigned only when it changed.
    func refreshInBackground() {
        // A struct of constants, only read.
        nonisolated(unsafe) let installer = installer
        let loginItem = loginItem
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let hooks = Self.health(installer), login = loginItem.state()
            Task { @MainActor in
                guard let self else { return }
                self.show(hooks: hooks)
                if self.loginItemState != login { self.loginItemState = login }
            }
        }
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
            hookErrors[agent] = "only your everyday Boop does that. Change them there."
            return
        }
        var why: String?
        if let backupStateDir { HookBackup.once(installer, agent, stateDir: backupStateDir) }
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

    /// Jev's docs, at TypeSafe, the one page of theirs Boop knows. They
    /// don't say where a key comes from, so a link says only what it is.
    static let jevDocs = URL(string: "https://docs.typesafe.ai/api")!

    /// Jev's key has been read and there's none, so Boop has no brain:
    /// it shows the agents, but neither reacts nor answers.
    /// While a Keychain prompt waits, nobody knows yet.
    var noKey: Bool { status.map { $0.keyRead && $0.brain == "none" } ?? false }

    /// How things are, in a few words: the Overview's status line, and the
    /// menu-bar icon's tooltip and what VoiceOver reads for it.
    var headline: String { headline(of: status) }

    /// `status`'s headline: the menu-bar icon's reads the runtime's latest.
    func headline(of status: Runtime.Status?) -> String {
        guard let s = status?.snapshot else {
            return startError == nil ? "Waking up…" : "Not running"
        }
        if status?.listening == true { return "Listening…" }
        if s.waiting > 0 { return s.waiting == 1 ? "Needs you" : "\(s.waiting) sessions need you" }
        switch s.base {
        // Short, as "2 sessions need you" is: beside the Talk button the
        // headline has room for about twenty letters.
        case "working": return s.busy == 1 ? "1 session working" : "\(s.busy) sessions working"
        case "idle": return "Hanging out"
        default: return "Napping"
        }
    }

    /// The mic button: click to talk, click again to send.
    func toggleTalk() {
        runtime?.setListening(!listening)
    }

    /// Hides the "can't hear you" notice until the next try.
    func dismissMicTrouble() {
        runtime?.dismissMicTrouble()
    }

    /// How Boop's body stands, in the words the Overview's device line and
    /// notice, and Settings, use.
    struct DeviceState: Equatable {
        var connected: Bool
        /// Something only the person can fix, as the Overview's notice
        /// names it.
        var trouble: String?
        /// A word or two, for the Overview.
        var short: String
        /// A sentence, for Settings, the device line's help and the notice.
        var detail: String
        /// The fix in full, for whoever wants it: behind Details.
        var more: String?
        /// Where the person fixes the trouble.
        var fix: Fix?

        enum Fix: Equatable {
            /// A pane of System Settings.
            case system(label: String, url: URL)
            /// Settings' firmware update.
            case update
        }
    }

    /// Where Bluetooth's trouble is fixed, by its cause. None for a Mac
    /// without Bluetooth.
    private static func bluetoothFix(_ cause: TransportTrouble.Cause) -> DeviceState.Fix? {
        let settings = "x-apple.systempreferences:"
        return switch cause {
        case .off: .system(label: "Open Bluetooth Settings", url: URL(string: settings + "com.apple.BluetoothSettings")!)
        case .notAllowed:
            .system(label: "Open Privacy & Security", url: URL(string: settings + "com.apple.preference.security?Privacy_Bluetooth")!)
        case .unsupported: nil
        }
    }

    /// The simulator is for developing Boop: `make dev`'s debug build
    /// offers it, and the release build `make bundle` makes never looks.
    static let offersSimulator: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

    /// What Settings says when the hook client is missing.
    static var clientMissing: String {
        AboutThisMac.isApp() ? "Boop's hook helper is missing. Install Boop again." : "agent-hook isn't built. Run make dev again."
    }

    /// Looks for a running simulator, off the main thread: it's a look at
    /// a socket. Only while there's someone to show it to: Settings, open.
    func lookForSimulator() {
        guard Self.offersSimulator, let devices else { return }
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
            if let why = status.linkTrouble {
                return DeviceState(connected: false, trouble: "\(name) can't look for its body", short: "No \(how)", detail: why.words,
                                   fix: Self.bluetoothFix(why.cause))
            }
            if usingSimulator {
                return DeviceState(connected: false, short: "Looking…", detail: "Looking for the simulator. Open its page in a browser.")
            }
            return DeviceState(connected: false, short: "Looking…", detail: "Looking for it over \(how). Plug it into USB power.")
        }
        // Both firmware troubles are fixed by Settings' update, when the app carries one.
        let update: DeviceState.Fix? = firmwareOffer == nil ? nil : .update
        // Its firmware doesn't fit the app, so it gets the looks but no
        // reactions (linkkit/SPEC.md §6).
        if let why = status.deviceTrouble {
            // With an update to give it, say so in plain words; LinkKit's own
            // ("flash it") is for a build that carries none.
            return DeviceState(connected: true, trouble: "\(name)'s body has the wrong firmware", short: "Wrong firmware",
                               detail: update == nil ? "Connected \(over), but \(why)."
                                   : "Connected \(over), but its firmware doesn't fit this app, so \(name) shows how things are "
                                   + "and doesn't react. Update it in Settings.",
                               more: update == nil ? nil : why, fix: update)
        }
        // Its firmware has another character pack's faces: it works, but
        // draws its startup mood for a mood it doesn't have.
        if let pack = status.device?.pack, status.device?.hasThePack == false {
            return DeviceState(connected: true, trouble: "\(name)'s body has another character's faces", short: "Other character",
                               detail: "Connected \(over), but the board was built with the \(pack) character pack, "
                                   + "and the app runs \(DeviceInfo.appPack), so some faces won't match. "
                                   + (update == nil ? "Flash the board with the app's character pack." : "Update it in Settings."),
                               fix: update)
        }
        // Its card's voice isn't the app's, so it gets no takes.
        // `none` is no card, one it can't read, or no pack on it.
        if let voice = status.device?.voice, status.device?.hasTheVoice == false {
            let card = voice == "none" ? "it has no card, or no voice file on its card" : "its card's voice file isn't this app's"
            return DeviceState(connected: true, trouble: "\(name) has lost its voice", short: "No voice",
                               detail: "Connected \(over), but \(card), so \(name) can't talk. "
                                   + "Put this app's voice file on the card, then press the board's reset button.",
                               more: "The voice file is the character pack's voice/voice.bin, copied onto the card as boop/voice.bin. "
                                   + "The card must be FAT32: cards over 32 GB come as exFAT, so format one first.")
        }
        return DeviceState(connected: true, short: "Connected", detail: "Connected \(over).")
    }

    // The switches show the change at once; the runtime's next status confirms it.

    func setVolume(_ volume: Int) {
        guard status?.snapshot.vol != volume else { return }
        status?.snapshot.vol = volume
        runtime?.setVolume(volume)
    }

    func setWorkStream(_ on: Bool) {
        guard status?.workStream != on else { return }
        status?.workStream = on
        runtime?.setWorkStream(on)
    }

    /// Takes effect from the next event.
    func setPersonality(_ personality: Personality) {
        guard personality != self.personality else { return }
        status?.personality = personality
        runtime?.setPersonality(personality)
    }

    /// Takes effect from the next event.
    func setTalk(_ talk: Talk) {
        guard talk != self.talk else { return }
        status?.talk = talk
        runtime?.setTalk(talk)
    }

    /// Saves a bug report, shows it in Finder and
    /// copies its path, to hand to an agent.
    func saveReport() {
        runtime?.saveReport { dir in
            Task { @MainActor in
                // Found in Finder when it's saved; a beep when it couldn't be.
                guard let dir else { return NSSound.beep() }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dir.path, forType: .string)
                NSWorkspace.shared.activateFileViewerSelecting([dir])
            }
        }
    }

    /// What "Boop couldn't start" says, in plain words, above its Try again;
    /// the log keeps the error itself.
    static func startProblem(_ error: Error) -> String {
        switch error {
        case Runtime.OpenError.locked: "Another copy of Boop is already running. Quit it, then try again."
        case is HookServer.StartError: "Boop can't listen for your agents. Quit any other copy of Boop, then try again."
        default: "Something went wrong while starting. Try again, or quit Boop and open it again."
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
                         ownsHooks: everyday, link: link, keyAccount: Keychain.account(for: stateDir))
        model.backupStateDir = everyday ? stateDir : nil
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
        // The app menu, seen while onboarding gives Boop a Dock icon and a
        // menu bar of its own: a way to quit that isn't only ⌘Q.
        let app = NSMenu(title: "Boop")
        app.addItem(withTitle: "Hide Boop", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Boop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = app
        menu.addItem(appItem)
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
            // A repair edits the agents' settings, so they're kept first.
            for agent in Agent.allCases where model.installer.health(agent) == .outdated {
                HookBackup.once(model.installer, agent, stateDir: stateDir)
            }
            let repaired = model.installer.repair()
            if !repaired.isEmpty {
                log.write("hooks: repaired \(repaired.map(\.rawValue).joined(separator: ", "))")
                model.restartAgents = true
            }
        } else {
            // They report to the everyday Boop's socket, so pointing them here
            // would only break them once this folder is gone. This copy lists
            // its own socket beside it instead, so the hooks already there
            // reach it too (onboarding's live hello on `make dev`'s folder), until it quits.
            let name = AppSettings.copyName(stateDir)
            try? HookSocket.register(stateDir.appendingPathComponent("boop.sock").path, as: name)
            log.write("hooks: left alone, since only the everyday Boop (\(AppSettings.defaultStateDir().path)) installs "
                      + "or repairs them; this copy hears them as \(name).sock")
        }
        model.refreshHooks()
        // The login item's state, for Settings, before it's first opened.
        model.refreshInBackground()
        model.start = { [weak self] in self?.startRuntime() }
        model.uninstall = { [weak self] in self?.uninstall() }
        model.log = { [log] in log.write($0) }

        let host = NSHostingController(rootView: PopoverView(model: model) { [weak self] in self?.popover.performClose(nil) })
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        // Panes change height; an animated resize would clip them mid-way.
        popover.animates = false
        popover.delegate = self

        // The first launch is onboarding, in its own window, and the menu
        // bar waits for it. Past the name, the runtime runs, except while
        // the board's act waits to explain Bluetooth before asking.
        let memory = try? MemoryStore(directory: stateDir, log: { [log] in log.write($0) })
        if let act = Onboarding.resume(isSetUp: memory?.isSetUp == true, saved: AppSettings.load(from: stateDir).onboarding) {
            log.write("onboarding: from \(act.rawValue)")
            // Past the name it's kept, and the acts call it by it before
            // the runtime's first status (act 4 doesn't start it).
            if let name = memory?.name { model.setup.name = name }
            showOnboarding(at: act)
            if act.afterNaming, act != .body { startRuntime() }
            // What the act does as it opens, as if it had just been moved to.
            onboarding?.entered(act)
        } else {
            makeStatusItem()
            startRuntime()
        }
    }

    /// The menu-bar icon and its popover: the app, once onboarding is done.
    func makeStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
        iconMood = nil
        updateIcon()
        warmPopover()
    }

    /// The popover's first open as quick as the ones after it: a moment
    /// after the icon appears, while nothing waits on it, its slime's page
    /// loads and its views are laid out, so it opens without a black tile
    /// that fills in. The first open would make both anyway, and keep them.
    func warmPopover() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, !popover.isShown else { return }
            if SlimeFeed.folder != nil { model.slime.preload() }
            popover.contentViewController?.view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: Onboarding

    var onboardingWindow: NSWindow?
    var onboarding: OnboardingModel?

    func showOnboarding(at act: Onboarding.Act) {
        let onboarding = OnboardingModel(app: model, act: act, stateDir: stateDir)
        onboarding.startRuntime = { [weak self] in self?.startRuntime() }
        onboarding.finished = { [weak self] in self?.finishOnboarding() }
        onboarding.bringForward = { [weak self] in self?.bringOnboardingForward() }
        onboarding.log = { [log] in log.write($0) }
        self.onboarding = onboarding
        model.onboardingShown = true
        // Its slime's page loads with the window, and every act shows it.
        if SlimeFeed.folder != nil { onboarding.feed.preload() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView(model: onboarding)))
        // No close button: it ends at the finale; ⌘Q quits, and the next
        // launch picks up where it left off.
        window.styleMask = [.titled, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Welcome to Boop"
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.setContentSize(OnboardingView.size)
        window.center()
        onboardingWindow = window
        // Until the menu-bar icon, the window is all there is of Boop: a
        // Dock icon and ⌘Tab bring it back from behind other windows.
        NSApp.setActivationPolicy(.regular)
        bringOnboardingForward()
    }

    /// The window in front of every other app's. It comes back by itself
    /// for the agent's hello, after act 6 sent you to your terminal, and
    /// when Boop is opened again or its Dock icon clicked.
    func bringOnboardingForward() {
        guard let window = onboardingWindow else { return }
        NSApp.activate()
        // macOS may refuse an app the activation it didn't ask for; the
        // window comes to the front either way.
        window.orderFrontRegardless()
        window.makeKey()
    }

    /// Opening Boop again while it runs (from Finder, Spotlight or the
    /// Dock): onboarding's window, or the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if onboardingWindow != nil { bringOnboardingForward() } else if !popover.isShown { showPopover() }
        return false
    }

    /// Onboarding's last button: the menu-bar icon appears, the window
    /// shrinks into it, and it blinks twice so you see where Boop went.
    func finishOnboarding() {
        // Gone, so the runtime's taps and hooks reach it no more. Its
        // slime stops once the window has gone.
        let feed = onboarding?.feed
        onboarding = nil
        startRuntime()
        makeStatusItem()
        guard let window = onboardingWindow else {
            feed?.close()
            return
        }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // A turn of the run loop, so the menu bar has placed the new icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            let target = statusItem?.button?.window?.frame
                ?? NSRect(x: window.frame.maxX - 40, y: window.frame.maxY - 30, width: 30, height: 22)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = still ? 0 : 0.45
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0)
                window.animator().setFrame(NSRect(x: target.midX - 30, y: target.midY - 20, width: 60, height: 40), display: true)
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    window.orderOut(nil)
                    feed?.close()
                    self?.onboardingWindow = nil
                    self?.model.onboardingShown = false
                    // The menu-bar app from now on: no Dock icon.
                    NSApp.setActivationPolicy(.accessory)
                    if !still { self?.blinkIcon(times: 2) }
                }
            })
        }
    }

    /// The menu-bar icon dims and comes back, `times` times.
    func blinkIcon(times: Int) {
        guard times > 0, let button = statusItem?.button else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            button.animator().alphaValue = 0.15
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.22
                    button.animator().alphaValue = 1
                }, completionHandler: { [weak self] in
                    Task { @MainActor in self?.blinkIcon(times: times - 1) }
                })
            }
        })
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.runtime?.stop()
        // A copy on another folder takes its socket's listing with it.
        guard !model.ownsHooks else { return }
        _ = try? HookSocket.unregister(stateDir.appendingPathComponent("boop.sock").path, as: AppSettings.copyName(stateDir))
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

    /// Starts the runtime, once.
    func startRuntime() {
        guard model.runtime == nil else { return }
        // In debug mode (`make dev`) the dashboard can drive it; without
        // --debug, as Boop.app runs, it stays deaf to it.
        var options = runtimeOptions(stateDir: stateDir, socketPath: stateDir.appendingPathComponent("boop.sock").path,
                                     link: model.link, debug: debug, devLines: debug, log: log,
                                     buddies: AppSettings.load(from: stateDir).buddies)
        // Here and away: the Mac's idle time on
        // every tick, and its locks, sleeps and wakes below.
        options.idleMs = PresenceSignals.idleMs
        // Your prompts, read on this Mac on macOS 26 whenever Apple
        // Intelligence is on, even if it's turned on later.
        options.labeler = AppleIntelligenceLabeler.onThisMac
        model.devices = options.link as? DeviceChooser
        do {
            let runtime = try Runtime(options)
            runtime.onChange = { [weak self] status in
                Task { @MainActor in
                    self?.model.take(status)
                    self?.updateIcon()
                }
            }
            // The popover's mirror of the board: what the board is sent and
            // does by itself, in order.
            let slime = model.slime
            runtime.onBoardLine = { line in DispatchQueue.main.async { MainActor.assumeIsolated { slime.send(line) } } }
            runtime.onBoardTap = { button in DispatchQueue.main.async { MainActor.assumeIsolated { slime.tap(button: button) } } }
            runtime.onBoardListening = { DispatchQueue.main.async { MainActor.assumeIsolated { slime.listening() } } }
            // Push-to-talk: the core says when the mic
            // is on; what it heard goes back to the runtime.
            let listener = SpeechListener(log: { [log] in log.write($0) })
            // Weakly: a runtime that fails to start must go, and take its
            // lock with it, or "Try again" finds the folder still locked.
            runtime.onListen = { [weak runtime] (on: Bool) in
                guard let runtime else { return }
                if on {
                    listener.start { why in runtime.micFailed(why) }
                } else {
                    listener.stop { words in
                        if let words { runtime.said(words) } else { runtime.heardNothing() }
                    }
                }
            }
            // Onboarding listens for a tap on the board, what push-to-talk
            // heard, an agent's first hook and the agents' drawer, while
            // it's there.
            runtime.onTap = { [weak self] button, onFinish in
                Task { @MainActor in self?.onboarding?.tapped(button: button, onFinish: onFinish) }
            }
            runtime.onDrawer = { [weak self] did in Task { @MainActor in self?.onboarding?.drawer(did) } }
            runtime.onHeard = { [weak self] words in Task { @MainActor in self?.onboarding?.talked(words) } }
            runtime.onAgentHook = { [weak self] agent in Task { @MainActor in self?.onboarding?.agentHook(agent) } }
            try runtime.start()
            // Only once it runs, so a failed start leaves nothing holding it.
            presenceSignals.start { [weak runtime] in runtime?.presence($0) }
            // A simulator started or stopped on this Mac: looked for while
            // Settings is open to show it.
            let look = Timer.scheduledTimer(withTimeInterval: DeviceChooser.watchEvery, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let model = self?.model, model.shown, model.pane == .settings else { return }
                    model.lookForSimulator()
                }
            }
            look.tolerance = 0.5
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
        let latest = model.latest
        let mood = model.startError == nil ? FaceMood(latest) : .stopped
        if mood != iconMood {
            iconMood = mood
            button.image = MenuBarIcon.image(mood)
        }
        let words = "\(latest?.name ?? model.name): \(model.headline(of: latest))"
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
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        // Shown first: reading the agents' settings and the login item's
        // state waits on disk and on macOS, so it's done off the main
        // thread, and only what changed is shown when it's back.
        model.refreshInBackground()
        model.runtime?.refresh()
    }

    /// Before it's on screen: the mirror draws where the board is now, not
    /// the pose it had when the popover last closed, and the views catch
    /// up with the runtime's latest status.
    func popoverWillShow(_ notification: Notification) {
        model.slime.show(true)
        model.shown = true
    }

    /// Settings closes back to the overview; setup stays where it was.
    func popoverDidClose(_ notification: Notification) {
        model.shown = false
        model.slime.show(false)
        // A finished update's word has been seen; one going on keeps going.
        if case .done = model.firmwareWrite { model.firmwareWrite = .idle }
        if model.pane == .settings { model.pane = .overview }
    }

    /// Settings' Uninstall: asks first, then takes out the hooks, the
    /// socket's listing, the hook client's copy and the login item, keeps
    /// the memory, moves Boop.app to the Trash and quits.
    func uninstall() {
        let name = model.name
        let bundled = AboutThisMac.isApp()
        let folder = (stateDir.path as NSString).abbreviatingWithTildeInPath
        popover.performClose(nil)
        NSApp.activate()
        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = "Uninstall \(name)?"
        ask.informativeText = "\(name) takes its hooks out of Claude Code and Codex, stops opening at login"
            + (bundled ? ", moves Boop.app to the Trash" : "") + " and quits.\n\n"
            + "Its memory stays in \(folder), so a Boop installed again remembers. Delete that folder to forget it too."
        ask.addButton(withTitle: "Uninstall")
        ask.addButton(withTitle: "Cancel")
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        guard model.ownsHooks else {
            log.write("uninstall: refused, since only the everyday Boop (\(AppSettings.defaultStateDir().path)) uninstalls")
            return
        }
        model.runtime?.stop()
        for agent in Agent.allCases { HookBackup.once(model.installer, agent, stateDir: stateDir) }
        let result = Uninstall.run(installer: model.installer, stateDir: stateDir, loginItem: model.loginItem)
        log.write("uninstall: removed " + (result.removed.isEmpty ? "nothing" : result.removed.joined(separator: ", "))
                  + (result.kept.isEmpty ? "" : "; left " + result.kept.joined(separator: "; "))
                  + (result.problems.isEmpty ? "" : "; couldn't remove " + result.problems.joined(separator: "; ")))
        if !result.problems.isEmpty {
            let told = NSAlert()
            told.messageText = "\(name) couldn't take everything out"
            told.informativeText = result.problems.joined(separator: "\n")
            told.runModal()
        }
        if bundled {
            NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
                if let error { self.log.write("uninstall: can't move Boop.app to the Trash: \(error)") }
                Task { @MainActor in NSApp.terminate(nil) }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}
