import AgentHooks
import AppKit
import BoopKit
import CoreBluetooth
import LinkKit
import MellowHarness
import SwiftUI

/// `Boop --snapshots DIR`: renders the popover's panes and the menu-bar
/// icons to PNGs, in light and dark, from fixed fixtures, then exits
/// (VERIFICATION.md L0). No runtime, no Bluetooth, and the
/// agents' settings it reads are in a throwaway HOME.
@MainActor
enum Snapshots {
    static func run(_ args: Arguments) -> Never {
        guard let dir = args["--snapshots"] else { fail("--snapshots needs a directory") }
        let out = URL(fileURLWithPath: dir)
        checkContrast()
        checkSetupNames()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("boop-snapshots-\(getpid())")
            try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: home) }
            // The installer refuses without an agent-hook to call, so give it one.
            let hook = home.appendingPathComponent("bin/\(HookInstaller.client)")
            try FileManager.default.createDirectory(at: hook.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: hook)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
            let installer = HookInstaller.boop(home: home, hookPath: hook.path)
            let unbuilt = HookInstaller.boop(home: home, hookPath: home.appendingPathComponent("bin/missing").path)
            checkStatusPublishing(installer)
            checkPulse()
            checkNothingCut(installer)
            checkNeedsYouComesFirst(installer)

            // The pack's mirror of the board, when it has one (Boop's).
            let gelState = StateSnapshot(doing: "working", activity: "terminal", mood: "happy", attn: nil, working: 1, vol: 6)
            var gelImage: NSImage?, onboardingGel: NSImage?
            OnboardingSound.enabled = false
            if SlimeFeed.folder != nil {
                checkSlimeHandOver()
                try checkSlimeFadesIn()
                onboardingGel = try SlimeSnapshots.image(.onboarding(mood: "happy"), to: out.appendingPathComponent("slime-onboarding.png"))
                // Every look onboarding uses, through the board's engine:
                // one it doesn't show as asked fails here.
                for (name, look) in StateSnapshot.onboardingLooks {
                    _ = try SlimeSnapshots.image(look, to: out.appendingPathComponent("slime-onboarding-\(name).png"))
                }
                _ = try SlimeSnapshots.image(gelState, to: out.appendingPathComponent("slime-working.png"))
                // The popover's 46 pt tile, zoomed on the slime, at 2×.
                gelImage = try SlimeSnapshots.image(gelState, to: out.appendingPathComponent("slime-tile.png"),
                                                    size: NSSize(width: 92, height: 92), zoomed: true)
                tileStill = gelImage
                let gelAttention = StateSnapshot(doing: "working", mood: "frightened",
                    attn: .init(agent: "codex", project: "Boop", more: 0, id: 1), working: 1, vol: 6)
                _ = try SlimeSnapshots.image(gelAttention, to: out.appendingPathComponent("slime-needs-you.png"))
                try checkMoodStills()
            }
            for dark in [false, true] {
                /// The popover on `pane`, tall enough for all of it.
                func shot(_ name: String, _ model: AppModel, pane: Pane) {
                    model.pane = pane
                    render(PopoverView(model: model, maxHeight: 2000), "\(name)-\(dark ? "dark" : "light")", dark: dark, to: out, whole: true)
                }
                for (name, model) in overviews(installer) { shot("overview-\(name)", model, pane: .overview) }
                if gelImage != nil {
                    // The one session its state's `busy` counts.
                    var gelStatus = status(sessions: [["claude", "jetpack", "work"]], mood: "happy")
                    gelStatus.snapshot = gelState
                    gelStatus.device = DeviceInfo(id: "gel-fixture", fw: "snapshots", face: .gel)
                    let gel = model(installer, status: gelStatus)
                    gel.hooks[.claude] = .installed
                    shot("overview-gel", gel, pane: .overview)
                }
                // What Boop knows: with notes, with a section still empty, with none.
                shot("memory", model(installer, status: status()), pane: .memory)
                var partly = status()
                partly.notes.removeAll { $0.section == .work }
                shot("memory-partly", model(installer, status: partly), pane: .memory)
                var unknown = status()
                (unknown.notes, unknown.recently) = ([], [])
                shot("memory-empty", model(installer, status: unknown), pane: .memory)
                var longMemory = status(name: Long.name)
                (longMemory.notes, longMemory.recently) = (longNotes, longDays)
                shot("memory-long", model(installer, status: longMemory), pane: .memory)
                shot("memory-not-running", model(installer, status: nil), pane: .memory)
                let settings = model(installer, status: status(sessions: [["codex", "landing", "work"]]))
                try? installer.install(.claude)
                settings.refreshHooks()
                settings.restartAgents = true
                settings.status?.board = "b00p-01dd"  // the board it remembered
                shot("settings", settings, pane: .settings)
                try? installer.remove(.claude)
                shot("settings-chatty", model(installer, status: status(talk: .chatty)), pane: .settings)
                shot("settings-no-hook", model(unbuilt, status: status()), pane: .settings)
                // A copy on another folder tried to connect Claude, and the
                // Overview's notice was closed: the row still says why.
                let failed = model(installer, status: status(), ownsHooks: false)
                failed.install(.claude)
                failed.dismissHookError(.claude)
                shot("settings-hook-failed", failed, pane: .settings)
                // No Jev key, the body away and Claude's hooks needing a repair.
                let offline = model(installer, status: status(connected: false, brain: "none"))
                offline.hooks[.claude] = .outdated
                shot("settings-offline-nokey", offline, pane: .settings)
                // Claude's hooks turned off by the person: only Remove.
                let off = model(installer, status: status())
                off.hooks[.claude] = .hooksOff(installer.configURL(.claude).path)
                shot("settings-hooks-off", off, pane: .settings)
                let stopped = model(installer, status: nil)
                stopped.startError = AppModel.startProblem(Runtime.OpenError.locked("/tmp/boop"))
                shot("settings-not-running", stopped, pane: .settings)
                // Opening at login waits for System Settings, and a bare binary can't.
                let approval = model(installer, status: status())
                approval.loginItem = LoginItem(state: { .needsApproval }, set: { _ in })
                approval.refreshLoginItem()
                shot("settings-login-approval", approval, pane: .settings)
                let bare = model(installer, status: status())
                bare.loginItem = .unavailable
                bare.refreshLoginItem()
                shot("settings-login-unavailable", bare, pane: .settings)
                // The board runs older firmware than the app carries, and then it's being written.
                let behind = model(installer, status: status())
                behind.boardFirmware = [BoardFirmware(board: "cyd24", chip: .esp32, flashSize: 4 << 20, version: "1.1.0", sha: "abc1234")]
                shot("settings-firmware-offer", behind, pane: .settings)
                behind.firmwareWrite = .writing(0.42)
                shot("settings-firmware-writing", behind, pane: .settings)
                behind.firmwareWrite = .failed("plug Mochi's body into this Mac with a USB cable that carries data, then try again.")
                shot("settings-firmware-failed", behind, pane: .settings)
                shot("settings-bluetooth-off", model(installer, status: status(connected: false, linkTrouble: bluetooth(.poweredOff))),
                     pane: .settings)
                // The simulator window, in a build that has it: off, and on.
                shot("settings-simulator-off", model(installer, status: status()), pane: .settings)
                let simulated = model(installer, status: status())
                simulated.usingSimulator = true
                shot("settings-simulator-on", simulated, pane: .settings)
                // A card with another pack than the app's, and no card or pack: no voice.
                shot("settings-old-voice", model(installer, status: status(voice: "0123456789abcdef")), pane: .settings)
                shot("settings-no-voice", model(installer, status: status(voice: "none")), pane: .settings)
                // Firmware too old for the kit: the looks, but no reactions (linkkit/SPEC.md §6).
                shot("settings-old-firmware", model(installer, status: status(deviceTrouble: "the device's firmware is too old for this app: flash it")),
                     pane: .settings)

                // The longest name, and the longest words in each row.
                let longSettings = model(installer, status: status(connected: true, name: Long.name, deviceTrouble: Long.detail), ownsHooks: false)
                longSettings.status?.board = "b00p-01dd"
                longSettings.hookErrors[.claude] = Long.detail
                longSettings.loginItemError = Long.detail
                longSettings.boardFirmware = [BoardFirmware(board: "cyd24", chip: .esp32, flashSize: 4 << 20, version: "1.1.0-rc.12+abcdef1234", sha: "abc1234")]
                longSettings.firmwareWrite = .failed(Long.detail)
                shot("settings-long", longSettings, pane: .settings)

                for (name, onboarding) in onboardings(installer, gel: onboardingGel) {
                    render(OnboardingView(model: onboarding), "onboarding-\(name)-\(dark ? "dark" : "light")", dark: dark, to: out)
                }
                if let crowded = overviews(installer).first(where: { $0.0 == "crowded" })?.1 {
                    crowded.status?.snapshot.vol = 0
                    crowded.status?.talk = .quiet
                    render(PopoverView(model: crowded, maxHeight: 560),
                           "overview-bounded-\(dark ? "dark" : "light")", dark: dark, to: out, heightLimit: 560)
                }
                // At the height the popover really has: the footer stays, and the long
                // values scroll.
                for name in ["long", "long-words", "long-notices", "needs-you-said"] {
                    if let long = overviews(installer).first(where: { $0.0 == name })?.1 {
                        render(PopoverView(model: long, maxHeight: 560),
                               "overview-\(name)-bounded-\(dark ? "dark" : "light")", dark: dark, to: out, heightLimit: 560)
                    }
                }
                renderIcons(dark: dark, to: out)
            }
        } catch {
            fail("snapshots: \(error)")
        }
        exit(0)
    }

    /// Onboarding's acts, and the states of them worth seeing, each on a
    /// model of its own.
    static func onboardings(_ installer: HookInstaller, gel: NSImage?) -> [(String, OnboardingModel)] {
        func at(_ act: Onboarding.Act, status: Runtime.Status? = nil, _ set: (OnboardingModel) -> Void = { _ in }) -> OnboardingModel {
            let app = model(installer, status: status)
            app.setup.name = act.index >= Onboarding.Act.makeMeYours.index ? "Mochi" : ""
            let onboarding = OnboardingModel(app: app, act: act, stateDir: URL(fileURLWithPath: "/tmp/boop-snapshots-onboarding"))
            onboarding.feed.stillImage = gel
            set(onboarding)
            return onboarding
        }
        let behind = at(.body, status: status()) {
            $0.body = .joined
            $0.app.boardFirmware = [BoardFirmware(board: "cyd24", chip: .esp32, flashSize: 4 << 20, version: "1.1.0", sha: "abc1234")]
        }
        return [
            ("1-hello", at(.hello)),
            ("2-what-i-do", at(.whatIDo)),
            ("3-name", at(.makeMeYours)),
            ("3-name-invalid", at(.makeMeYours) { $0.app.setup.editName("Mochi: Pip") }),
            ("3-name-unicode", at(.makeMeYours) { $0.app.setup.editName("우리의작은친구말랑이") }),
            ("4-body-intro", at(.body)),
            ("4-body-looking", at(.body, status: status(connected: false)) { $0.body = .looking }),
            ("4-body-bluetooth-off", at(.body, status: status(connected: false, linkTrouble: bluetooth(.poweredOff))) {
                $0.body = .looking
            }),
            // Refused at macOS's prompt: Privacy & Security, not Bluetooth's own settings.
            ("4-body-bluetooth-refused", at(.body, status: status(connected: false, linkTrouble: bluetooth(.unauthorized))) {
                $0.body = .looking
            }),
            ("4-body-found", at(.body, status: status()) { $0.body = .looking }),
            ("4-body-cant-start", at(.body) {
                $0.body = .looking
                $0.app.startError = AppModel.startProblem(Runtime.OpenError.locked("/tmp/boop"))
            }),
            ("4-body-joined", at(.body, status: status()) { $0.body = .joined }),
            ("4-body-joined-hungry", behind),
            ("4-body-joined-no-voice", at(.body, status: status(voice: "none")) { $0.body = .joined }),
            // No board, in a build with the simulator window: it's offered.
            ("4-body-simulator-offered", at(.body) { $0.simulatorHere = true }),
            // The simulator window as the body, chosen above.
            ("4-body-in-window", at(.body) { $0.app.startOnSimulator = true }),
            ("4-body-in-window-looking", at(.body, status: status(connected: false)) {
                $0.app.startOnSimulator = true
                $0.body = .looking
            }),
            ("4-body-in-window-found", at(.body, status: status()) {
                $0.app.startOnSimulator = true
                $0.body = .looking
            }),
            ("4-body-in-window-joined", at(.body, status: status()) {
                $0.app.startOnSimulator = true
                $0.body = .joined
            }),
            ("5-how-to-in-window", at(.howTo, status: status()) {
                $0.app.startOnSimulator = true
                $0.body = .joined
                $0.progress.lessons = [.tap]
            }),
            // Back from act 5 after "I don't have my Boop yet", or a launch past the board.
            ("4-body-back-after-skipping", at(.howTo, status: status(connected: false)) { $0.progress.move(to: .body) }),
            ("5-how-to", at(.howTo, status: status()) {
                $0.body = .joined
                $0.progress.lessons = [.tap]
            }),
            ("5-how-to-done", at(.howTo, status: status()) {
                $0.body = .joined
                $0.progress.lessons = [.tap, .button]
            }),
            ("5-how-to-no-board", at(.howTo, status: status(connected: false))),
            ("5-how-to-talk", at(.howTo, status: status()) {
                $0.body = .joined
                $0.progress.lessons = [.tap, .button]
            }),
            ("5-how-to-heard-nothing", at(.howTo, status: status()) {
                $0.body = .joined
                $0.progress.lessons = [.tap, .button]
                $0.talk = .nothing
            }),
            // Before act 7's key: what it heard, and that the answer comes then.
            ("5-how-to-heard", at(.howTo, status: status(brain: "none")) {
                $0.body = .joined
                $0.progress.lessons = [.tap, .button, .talk]
                $0.talk = .heard("Hi Boop, can you hear me from all the way over here on my desk?")
            }),
            // The practice request answered: all four done.
            ("5-how-to-all-done", at(.howTo, status: status(brain: "none")) {
                $0.body = .joined
                $0.progress.lessons = [.tap, .button, .talk, .amber]
                $0.talk = .heard("Hi Boop")
            }),
            ("6-agents", at(.agents, status: status()) { $0.app.setup.agents = [.claude] }),
            ("6-agents-what-gets-added", at(.agents, status: status()) {
                $0.app.setup.agents = [.claude]
                $0.showHooks = true
            }),
            ("6-agents-hello", at(.agents, status: status()) { $0.connected = true }),
            ("6-agents-heard", at(.agents, status: status()) {
                $0.connected = true
                $0.progress.heard = "claude"
            }),
            // On a gel board, the tour: the words fell, and the turn finished.
            ("6-agents-tour", at(.agents, status: status(base: "idle", sessions: [["claude", "landing", "idle", "Tidy the README"]],
                                                         face: .gel)) {
                $0.body = .joined
                $0.connected = true
                $0.progress.heard = "claude"
                $0.progress.tour = [.words]
            }),
            ("6-agents-tour-done", at(.agents, status: status(base: "idle", sessions: [["claude", "landing", "idle"]], face: .gel)) {
                $0.body = .joined
                $0.connected = true
                $0.progress.heard = "claude"
                $0.progress.tour = Set(Onboarding.Progress.Tour.allCases)
            }),
            ("7-small-things", at(.smallThings, status: status())),
            ("7-small-things-mic-allowed", at(.smallThings, status: status()) { $0.mic = .allowed }),
            // Act 5's push-to-talk had the mic allowed: no card for it.
            ("7-small-things-mic-allowed-before", at(.smallThings, status: status()) { $0.askMic = false }),
            // `make dev`'s bare binary, which can't open at login.
            ("7-small-things-from-terminal", at(.smallThings, status: status()) {
                $0.app.loginItem = .unavailable
                $0.app.refreshLoginItem()
            }),
            // The longest name wherever an act says it, and the longest words heard.
            ("3-name-long", at(.makeMeYours) { $0.app.setup.editName(Long.name) }),
            ("3-name-unbroken", at(.makeMeYours) { $0.app.setup.editName(Long.unbroken) }),
            ("4-body-long", at(.body, status: status(connected: false, name: Long.name)) { $0.app.setup.name = Long.name }),
            ("4-body-long-unbroken", at(.body, status: status(connected: false, name: Long.unbroken)) { $0.app.setup.name = Long.unbroken }),
            ("4-body-long-no-voice", at(.body, status: status(name: Long.name, voice: "none")) {
                $0.app.setup.name = Long.name
                $0.body = .joined
            }),
            ("5-how-to-long", at(.howTo, status: status(name: Long.name, brain: "none")) {
                $0.app.setup.name = Long.name
                $0.body = .joined
                $0.progress.lessons = [.tap, .button]
                $0.talk = .heard(Long.thread + " " + Long.thread)
            }),
            ("5-how-to-long-unbroken", at(.howTo, status: status(name: Long.unbroken)) {
                $0.app.setup.name = Long.unbroken
                $0.body = .joined
                $0.progress.lessons = [.tap, .button]
            }),
            ("6-agents-long", at(.agents, status: status(name: Long.name)) {
                $0.app.setup.name = Long.name
                $0.connected = true
                $0.progress.heard = "claude"
            }),
            ("7-small-things-long", at(.smallThings, status: status(name: Long.name)) {
                $0.app.setup.name = Long.name
            }),
            ("8-finale-long", at(.finale, status: status(name: Long.name)) { $0.app.setup.name = Long.name }),
            ("8-finale-unbroken", at(.finale, status: status(connected: false, name: Long.unbroken)) { $0.app.setup.name = Long.unbroken }),
            ("8-finale", at(.finale, status: status())),
            // A gel board: the drawer's tip in the poke's place.
            ("8-finale-gel", at(.finale, status: status(face: .gel))),
            // After "I don't have my Boop yet": the Mac's way of each tip.
            ("8-finale-no-board", at(.finale, status: status(connected: false))),
        ]
    }

    /// The views' status changes only while the popover or onboarding
    /// shows it, only when something they show changed, and never for the
    /// work stream's lanes, which change every few hundred milliseconds
    /// while an agent works. The menu-bar icon reads the latest all along.
    static func checkStatusPublishing(_ installer: HookInstaller) {
        let model = model(installer, status: nil)
        var published = 0
        let watch = model.$status.dropFirst().sink { _ in published += 1 }
        defer { watch.cancel() }
        // One session, the same each time, as the runtime keeps it: only the lanes move.
        let session = status(sessions: [["claude", "jetpack", "work"]])
        func lanes(_ count: Int) -> Runtime.Status {
            var working = session
            working.snapshot.calls = [.init(slot: 0, count: count, word: "Read")]
            return working
        }
        model.take(lanes(1))
        guard published == 0, model.latest?.snapshot.calls == [], FaceMood(model.latest) == .working else {
            fail("snapshots: a closed popover's status changed, or kept the lanes")
        }
        model.shown = true
        guard published == 1, model.status == model.latest else { fail("snapshots: the popover opened on a stale status") }
        model.take(lanes(2))
        guard published == 1 else { fail("snapshots: the work stream's lanes changed the popover's status") }
        model.take(status(base: "asleep"))
        guard published == 2 else { fail("snapshots: the popover missed a change") }
        model.shown = false
        model.take(lanes(3))
        guard published == 2 else { fail("snapshots: a closed popover's status changed") }
        model.onboardingShown = true
        guard published == 3, model.status == model.latest else { fail("snapshots: onboarding showed a stale status") }
        // Onboarding's own slime is fed its snapshot, so it keeps the lanes:
        // the agent's words fall past it after the hello.
        model.take(lanes(4))
        guard published == 4, model.status?.snapshot.calls.first?.count == 4 else {
            fail("snapshots: onboarding's status lost the work stream's lanes")
        }
        print("status: published only when shown and changed, without the lanes but for onboarding")
    }

    /// One page for each feed, which each view showing the mirror takes
    /// from the one before, as onboarding's acts change: the slime carries
    /// on, and the view it left, going after the new one came, can't hide it.
    static func checkSlimeHandOver() {
        let feed = SlimeFeed(), old = NSView(), new = NSView()
        defer { feed.close() }
        feed.preload()
        let page = feed.webView
        feed.place(in: old)
        feed.place(in: new)
        feed.release(old)
        guard let page, feed.webView === page, page.superview === new, feed.holder === new else {
            fail("snapshots: the mirror's page didn't carry on into the next view")
        }
        feed.release(new)
        guard feed.webView === page, page.superview == nil, feed.holder == nil else {
            fail("snapshots: the mirror's page stayed in a view that went")
        }
        // Below SlimeFace.zoomBelow (80 pt) a tile zooms on the slime: the
        // popover's 46 pt one does, onboarding's (108 pt and up) don't.
        let tile = { (size: CGFloat, height: CGFloat?) in SlimeFace(feed: feed, snapshot: .onboarding(), live: false, size: size, height: height) }
        guard tile(46, nil).zoomed, !tile(108, nil).zoomed, !tile(236, 177).zoomed else {
            fail("snapshots: the popover's tile doesn't zoom on the slime, or onboarding's does")
        }
        print("slime: one page, handed from view to view; the popover's tile zooms")
    }

    /// The mirror's page is clear on its glass until the board has drawn
    /// its first frame, then fades in over `SlimeFeed.fadeIn` (0.25 s), so
    /// the slime never pops in over a black tile.
    static func checkSlimeFadesIn() throws {
        guard SlimeFeed.fadeIn == 0.25 else { fail("snapshots: the mirror's fade-in isn't 0.25 s") }
        let feed = SlimeFeed(), container = NSView(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
        let window = NSWindow(contentRect: NSRect(x: -2000, y: 0, width: 46, height: 46), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { feed.close(); window.close() }
        var loaded = false
        feed.didLoad = { loaded = true }
        feed.place(in: container)
        guard let page = feed.webView, page.alphaValue == 0 else { fail("snapshots: the mirror's page shows before it has drawn") }
        let deadline = Date().addingTimeInterval(SlimeSnapshots.timeout)
        while !loaded, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard loaded, page.alphaValue == 0 else { fail("snapshots: the mirror's page showed with no frame to show") }
        feed.update(.onboarding(), visible: true, zoomed: true, from: container)
        let shown = Date().addingTimeInterval(SlimeSnapshots.timeout)
        while page.alphaValue < 1, Date() < shown { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        guard page.alphaValue == 1 else { fail("snapshots: the mirror's page never faded in after its first frame") }
        print("slime: clear until the board's first frame, then fades in")
    }

    /// The live dot's ring: 2.2 times the dot, gone in 1.6 s, again and
    /// again, run by Core Animation; none while still.
    static func checkPulse() {
        let view = PulseRingView(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        view.set(.systemOrange, live: true)
        guard let breath = view.ring.animation(forKey: "breath") as? CAAnimationGroup, breath.duration == 1.6,
              breath.repeatCount == .infinity,
              let grow = breath.animations?.first as? CABasicAnimation, grow.toValue as? CGFloat == 2.2 else {
            fail("snapshots: the live dot's ring doesn't spread to 2.2 times in 1.6 s, again and again")
        }
        view.set(.systemOrange, live: false)
        guard view.ring.animation(forKey: "breath") == nil, view.ring.opacity == 0 else {
            fail("snapshots: a still dot's ring still moves or shows")
        }
        print("dot: its ring breathes in Core Animation only while live")
        // Onboarding's rings while Boop looks for its body: three, each
        // 2.4 s out, a third of a lap apart, run the same way.
        let rings = RippleRingsView(frame: NSRect(x: 0, y: 0, width: 360, height: 220))
        rings.layout()
        let laps = (rings.layer?.sublayers ?? []).compactMap { $0.animation(forKey: "ripple") }
        let starts = laps.map(\.beginTime)
        guard laps.count == 3, laps.allSatisfy({ $0.duration == 2.4 && $0.repeatCount == .infinity }),
              zip(starts, starts.dropFirst()).allSatisfy({ abs($0 - $1 - 0.8) < 0.001 }) else {
            fail("snapshots: the looking rings aren't three, 2.4 s out and a third of a lap apart")
        }
        print("ripples: three rings in Core Animation, a third of a lap apart")
    }

    /// A pane drawn whole has no scroll view cut short: with scroll bars
    /// always shown, one would take their width and cut off its last lines.
    static func checkNothingScrolls(_ view: NSView, _ name: String) {
        for scroll in descendants(view).compactMap({ $0 as? NSScrollView }) {
            let content = scroll.documentView?.frame.height ?? 0
            if content > scroll.contentView.bounds.height + 1 {
                fail("snapshots: \(name) is cut off in a scroll view: \(Int(content)) pt in \(Int(scroll.contentView.bounds.height))")
            }
        }
    }

    static func descendants(_ view: NSView) -> [NSView] { view.subviews + view.subviews.flatMap(descendants) }

    /// The setup field uses the memory name's
    /// character limit and catches its forbidden separators before save.
    static func checkSetupNames() {
        var draft = SetupDraft()
        for character in ["가", "é", "👨‍👩‍👧‍👦"] {
            let full = String(repeating: character, count: 23)
            draft.editName(full + character)
            guard draft.name == full, draft.name.count == 23, draft.canContinueName else {
                fail("snapshots: setup cut a Unicode name before 23 characters")
            }
        }
        draft.editName("e\u{301}\nPip")
        guard draft.name == "é Pip" else { fail("snapshots: setup name cleanup changed") }
        for invalid in ["", "   ", "Pip: Bo", "Pip · Bo"] {
            draft.editName(invalid)
            guard !draft.canContinueName else { fail("snapshots: setup accepted an invalid name") }
        }
        print("setup names: Unicode limits, cleanup and validation pass")
    }

    /// The popover's slime, still, for every Overview: it shows whether
    /// or not a board is connected.
    /// Onboarding's legend of moods draws each from the mirror at runtime,
    /// off screen: every one must come back as a picture.
    static func checkMoodStills() throws {
        let moods = ["happy", "grumpy", "proud", "tired"].map(MoodTile.snapshot)
        SlimeStills.shared.want(moods)
        let deadline = Date().addingTimeInterval(SlimeSnapshots.timeout)
        while moods.contains(where: { SlimeStills.shared.image($0) == nil }), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        let missing = moods.filter { SlimeStills.shared.image($0) == nil }.map(\.mood)
        guard missing.isEmpty else {
            throw NSError(domain: "Snapshots", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "the legend's stills didn't draw: \(missing)"])
        }
        print("mood stills: \(moods.count), drawn off screen by the mirror")
    }

    static var tileStill: NSImage?

    static func model(_ installer: HookInstaller, status: Runtime.Status?, link: LinkSetting = .bluetooth,
                      ownsHooks: Bool = true) -> AppModel {
        // Fixtures only: never the real Keychain, and a copy's entry if saved.
        let model = AppModel(installer: installer, ownsHooks: ownsHooks, link: link,
                             keyAccount: Keychain.account(for: URL(fileURLWithPath: "/tmp/boop-snapshots")))
        model.slime.stillImage = tileStill
        model.status = status
        model.readKey = { nil }
        model.boardFirmware = []  // fixtures only: never the bundle's
        // Fixtures only: never the real login item. On, as after setup.
        model.loginItem = LoginItem(state: { .on }, set: { _ in })
        model.refreshLoginItem()
        return model
    }

    /// Bluetooth's trouble as the app's transport says it: it's named for
    /// the board's prefix.
    static func bluetooth(_ state: CBManagerState) -> TransportTrouble? { BLETransport.trouble(state, appName: BoopDevice.blePrefix) }

    /// `sessions` are agent, project, `wait`, `work` or `idle`, and
    /// optionally the thread's name and its workspace.
    static func status(base: String = "working", sessions rows: [[String]] = [], vol: Int = 6,
                       connected: Bool = true, talk: Talk = .default,
                       name: String = "Mochi", brain: String = "jev:jev-latest", keyRead: Bool = true,
                       mood: String = MoodOutput.initial, brainTrouble: BrainTrouble? = nil,
                       listening: Bool = false, micTrouble: String? = nil, voice: String? = nil,
                       linkTrouble: TransportTrouble? = nil, deviceTrouble: String? = nil,
                       growth: Growth? = Growth(xp: 1_340),
                       face: DeviceInfo.Face = SlimeFeed.folder != nil ? .gel : .pixel) -> Runtime.Status {
        let statuses: [String: SessionSummary.Status] = ["wait": .waiting, "work": .working, "idle": .idle]
        // Each in its agent's own app, so its row opens it.
        // Each waited, worked or rested a few minutes more than the one
        // before; those working are each at a call of their own, in their
        // lanes, and the first has a to-do list.
        let words = ["swift test", "edit +18 \u{2212}2", "grep", "pytest", "build", "read"]
        var working = 0
        let sessions = rows.enumerated().map { i, row in
            var s = SessionSummary(agent: row[0], project: row[1], name: row.count > 3 && !row[3].isEmpty ? row[3] : nil,
                                   workspace: row.count > 4 ? row[4] : nil, status: statuses[row[2]]!,
                                   thread: ThreadRef(agent: row[0], session: "s\(i)",
                                                     app: row[0] == "claude" ? "com.anthropic.claudefordesktop" : "com.openai.codex",
                                                     appSession: "local_\(i)"),
                                   since: Date().addingTimeInterval(-Double(60 * (2 + 5 * i))))
            if s.status == .working {
                s.word = words[working % words.count]
                s.slot = working < 4 ? working : nil
                if working == 0 { s.todo = StateSnapshot.Todo(done: 3, total: 7) }
                working += 1
            }
            return s
        }
        let wait = sessions.filter { $0.status == .waiting }
        let snapshot = StateSnapshot(
            doing: base, mood: mood,
            // Cut as the core cuts it for the device; the popover shows it whole.
            attn: wait.first.map {
                StateSnapshot.Attention(agent: $0.agent, project: StateSnapshot.clip($0.project, marked: true),
                                        name: $0.name.map { StateSnapshot.clip($0, marked: true) } ?? "", more: wait.count - 1)
            },
            working: sessions.filter { $0.status == .working }.count, vol: vol)
        var status = Runtime.Status(name: name, snapshot: snapshot, sessions: sessions, connected: connected,
                              device: connected && deviceTrouble == nil ? DeviceInfo(id: "b00p-54fe", fw: "1.0.0", voice: voice, face: face) : nil,
                              linkTrouble: linkTrouble, deviceTrouble: deviceTrouble,
                              brain: brain, keyRead: keyRead, brainTrouble: brainTrouble,
                              listening: listening, micTrouble: micTrouble, growth: growth)
        // Its age and its memory's recent days, read the day after.
        status.talk = talk
        if snapshot.doing == "asleep" { status.doingReason = Narration.sleeping(noAgents: false, napping: false, dozeMs: 3_600_000, name: name) }
        status.daysOld = 47
        status.recently = [.init(day: "2026-10-21", line: "A long day on \"api\"; the tests finally passed. You stroked \(name) 4 times.",
                                 today: "2026-10-22"),
                           .init(day: "2026-10-20", line: "Three turns broke on \"api\". You said \"still broken\".", today: "2026-10-22")]
        status.notes = [.init(id: 3, section: .you, days: ["2026-10-20"], text: "You work late most nights, and you say please to claude."),
                        .init(id: 12, section: .work, days: ["2026-10-21"], text: "\"api\": you and claude fixed the failing tests on Tuesday."),
                        .init(id: 9, section: .boop, days: ["2026-10-14", "2026-10-21"], pinned: true,
                              text: "You stroke \(name) when you sit down in the morning.")]
        return status
    }

    static func overviews(_ installer: HookInstaller) -> [(String, AppModel)] {
        [
            // Claude's hooks in place, so the empty list names it.
            ("asleep", {
                let m = model(installer, status: status(base: "asleep"))
                m.hooks[.claude] = .installed
                return m
            }()),
            // No agent's hooks connected: nothing can reach Boop.
            ("no-hooks", model(installer, status: status(base: "asleep"))),
            // Setup connected Claude but couldn't change Codex's config.
            ("hook-failed", {
                let m = model(installer, status: status(base: "asleep"))
                m.hooks[.claude] = .installed
                m.hookErrors[.codex] = "features is an inline table"
                m.restartAgents = true
                return m
            }()),
            ("working", model(installer, status: status(sessions: [
                ["codex", "landing", "work"], ["codex", "buddygotchi", "work", "", "main"],
                ["claude", "buddygotchi", "work", "", "cheer-thread-name"], ["claude", "buddygotchi", "work", "", "heartbeat-fix"],
                ["claude", "jetpack", "work"], ["claude", "notes", "idle"],
            ], mood: "determined"))),
            ("needs-you", model(installer, status: status(sessions: [
                ["codex", "landing-page-redesign-v2", "wait", "Fix the hero image on mobile", "fix-nav"], ["claude", "jetpack", "wait"],
                ["codex", "buddygotchi", "work"], ["claude", "notes", "idle"],
            ]))),
            // A long project and a long branch: under one another, in full.
            ("needs-you-long", model(installer, status: status(sessions: [
                ["claude", "buddygotchi-landing-page", "wait", "", "claude/very-long-branch-name-for-the-hero"],
                ["codex", "jetpack", "wait"],
            ]))),
            // The day it grew a stage, a Friday: why it wears a party hat and
            // shades.
            ("celebrating", {
                var s = status(sessions: [["claude", "jetpack", "work"]])
                s.dressing = [Narration.Dressing(kind: .specialDay, why: "Mochi became a Buddy today", what: "a party hat and confetti"),
                              Narration.Dressing(kind: .friday, why: "It's Friday", what: "shades")]
                return model(installer, status: s)
            }()),
            ("quiet", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], talk: .quiet))),
            ("offline", {
                let m = model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                        vol: 0, connected: false))
                m.restartAgents = true
                return m
            }()),
            ("not-running", {
                let m = model(installer, status: nil)
                m.startError = AppModel.startProblem(Runtime.OpenError.locked("/tmp/boop"))
                return m
            }()),
            ("waking-up", model(installer, status: nil)),
            ("no-key", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]], brain: "none"))),
            // Jev's key still being read, a Keychain prompt waiting: no brain
            // yet, but nothing says the key is missing.
            ("reading-key", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                            brain: "none", keyRead: false))),
            ("brain-trouble", model(installer, status: status(sessions: [["claude", "jetpack", "work"]],
                                                              brainTrouble: BrainTrouble(kind: .credit, why: "jev: HTTP 402",
                                                                                         inARow: 1)))),
            ("listening", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], listening: true))),
            ("unclean-exit", {
                var crashed = status(base: "idle", sessions: [["claude", "jetpack", "idle"]])
                crashed.uncleanExit = true
                return model(installer, status: crashed)
            }()),
            ("cant-hear", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                          micTrouble: "Allow Boop in System Settings → Privacy & Security → Microphone."))),
            // No card, or no voice file on it.
            ("no-voice", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]], voice: "none"))),
            // Bluetooth refused at the first launch's prompt.
            ("no-bluetooth", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                             connected: false, linkTrouble: bluetooth(.unauthorized)))),
            ("no-device", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                          connected: false), link: .none)),
            // Every chip at once (Chatty and Muted), under the longest kind of name.
            ("all-chips", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], vol: 0,
                                                          talk: .chatty, name: "Wobblebottom McSnugs"))),
            // Hushed: its countdown chip, and no Hush button beside Talk.
            ("hushed", {
                let m = model(installer, status: status(sessions: [["claude", "jetpack", "work"]]))
                m.status?.hushedUntil = Date().addingTimeInterval(23 * 60 + 10)
                return m
            }()),
            // Every value at its longest (Long).
            ("long", longOverview(installer)),
            // What you said to it as the mood's reason, as far as a reason
            // quotes it: the pane scrolls it, under a header that stays.
            ("long-words", {
                var s = status(sessions: [["claude", "jetpack", "work"]])
                s.moodReason = Long.said
                return model(installer, status: s)
            }()),
            // An agent waiting while what you said is the reason: the card comes first.
            ("needs-you-said", {
                var s = status(sessions: [["claude", "jetpack", "wait"]])
                s.moodReason = Long.said
                return model(installer, status: s)
            }()),
            // Several buddies with the longest names, and the longest feeling.
            ("long-buddies", {
                var s = status(sessions: [["claude", "jetpack", "work"]], name: Long.name, mood: Long.mood)
                s.buddies = [.init(id: "left", name: Long.name, snapshot: s.snapshot, connected: true, device: nil),
                             .init(id: "right", name: "Sir Reginald Fluffy III", snapshot: s.snapshot, connected: false, device: nil)]
                return model(installer, status: s)
            }()),
            // Every notice, each with its longest words, Details open.
            ("long-notices", {
                var s = status(sessions: [["claude", "jetpack", "idle"]], name: Long.name,
                               brainTrouble: BrainTrouble(kind: .failing, why: Long.detail, inARow: 3),
                               micTrouble: Long.detail, deviceTrouble: Long.detail)
                s.uncleanExit = true
                let m = model(installer, status: s)
                m.hookErrors[.codex] = Long.detail
                m.restartAgents = true
                OpenDetails.shared.show(Long.detail)
                return m
            }()),
            // Many sessions, a long project, two in one project told apart
            // by their threads' names, and one needing you from no folder.
            ("crowded", model(installer, status: status(sessions: [
                ["codex", "unknown", "wait"], ["claude", "jetpack", "work", "Add offline sync"],
                ["claude", "jetpack", "work", "Fix the flaky login test"],
                ["codex", "buddygotchi-landing-page-redesign", "work"], ["claude", "notes", "work"],
                ["codex", "landing", "idle"], ["claude", "dotfiles", "idle"], ["claude", "blog", "idle"],
                ["codex", "scratch", "idle"], ["claude", "archive", "idle"],
            ]))),
        ]
    }

    // MARK: Long values

    /// The longest each value gets, or longer than it's likely to, so a
    /// snapshot shows the worst case. The reasons are `Narration`'s own, made
    /// from the events that bring them.
    enum Long {
        /// A name's limit, `SetupDraft`'s 23 characters.
        static let name = "Wobblebottom McSnugs Jr"
        /// No spaces to wrap at.
        static let unbroken = String(repeating: "W", count: 23)
        static let thread = "Fix the flaky login test that only fails on the second run after a cold start on CI"
        static let project = "buddygotchi-landing-page-redesign-v2"
        static let workspace = "claude/very-long-branch-name-for-the-hero-section"
        /// No mood of a pack is longer.
        static let mood = "uncomfortable"
        /// A note at `MemoryEdits.maxLength`, 140 characters.
        static let note = String(repeating: "You keep the tests green before lunch, and you say please to claude. ", count: 2).prefix(140).description
        /// A path and an error, as macOS and the hooks say them.
        static let detail = "The file ~/Library/Application Support/Boop/some-rather-long-folder-name/settings.json couldn't be read: "
            + "The operation couldn't be completed. (NSCocoaErrorDomain error 257: permission denied.)"
        /// A line a day of the written memory.
        static let day = "A long day on \"\(project)\"; the tests finally passed after three broken turns. You stroked \(name) 4 times and said \"still broken\" twice."

        private static let thread_: [String: JSONValue] = ["agent": .string("claude"), "workspace": .string(workspace)]
        private static func event(_ type: Event.Kind, _ specific: String = "", phase: Event.Phase? = nil, data: [String: JSONValue] = [:]) -> Event {
            Event(at: 0, source: .device, type: type, phase: phase, specificType: specific, data: data)
        }

        /// The first time you show up today: its age, the dream told, and
        /// what it noticed.
        static var told: Narration {
            let dream = EventLine.dreamed(about: "the last 2 days", sentence: "you stroked it 4 times; 7 turns on \"\(project)\", 3 failed; you said \"still broken\"", name: name)
            let told = Narration.of(event(.gesture, "stroke"), line: Line("", facts: ["dream_told": .string(dream)]), name: name)
            return Narration.day(1_041, leading: told).noting(Narration.noticed("a rough hour: 3 failures"))
        }

        /// An agent's calls failing, on its branch.
        static var failing: Narration? {
            Narration.of(event(.tool), line: Line("", facts: ["failing": .int(4), "thread": .object(thread_)]), name: name)
        }

        /// A work act, on its branch.
        static var act: Narration? {
            Narration.of(event(.act, "tests", phase: .start), line: Line("", facts: ["thread": .object(thread_)]), name: name)
        }

        /// What you said, at its limit (`HookLine.maxMessage`), as a reason keeps it.
        static var said: Narration? {
            let words = String(repeating: "can you hear me from all the way over here on my desk ", count: 40).prefix(2_000).description
            return Narration.of(event(.said, "mic"), line: Line("", facts: ["words": .string(words)]), name: name)
        }
    }

    static func longOverview(_ installer: HookInstaller) -> AppModel {
        var s = status(sessions: [
            ["claude", Long.project, "wait", Long.thread, Long.workspace],
            ["codex", Long.project, "wait", "", Long.workspace],
            ["claude", Long.project, "work", Long.thread, Long.workspace],
            ["claude", "unknown", "work", Long.thread],
            ["codex", Long.project, "idle", "", Long.workspace],
        ], vol: 0, talk: .chatty, name: Long.name, mood: Long.mood)
        s.hushedUntil = Date().addingTimeInterval(29 * 60)
        s.wishing = "\(Long.name) wishes for \(Core.WishKind.work.words) (3 h 20 min)."
        s.moodReason = Long.told
        s.doingReason = Long.act
        s.dressing = [Narration.Dressing(kind: .specialDay, why: "\(Long.name) became a Buddy today, and it's its birthday", what: "a witch hat, a party hat, confetti, snow and hearts"),
                      Narration.Dressing(kind: .night, why: "It's night", what: "a nightcap and pyjamas")]
        s.growth = Growth(xp: 123_456)
        s.daysOld = 1_041
        s.notes = longNotes
        s.recently = longDays
        return model(installer, status: s)
    }

    /// Text twice as long makes the Overview taller, for every value that can
    /// run long: a line limit or a cut would leave its height where it was.
    /// With Details and the like shut, and no other value of any length.
    static func checkNothingCut(_ installer: HookInstaller) {
        func words(_ count: Int) -> String { String(repeating: "several words ", count: count).trimmingCharacters(in: .whitespaces) }
        func height(_ status: Runtime.Status) -> CGFloat {
            let host = NSHostingView(rootView: PopoverView(model: model(installer, status: status), maxHeight: 8000)
                .environment(\.stillMotion, true))
            window.contentView = host
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            return host.fittingSize.height
        }
        func bare(_ sessions: [[String]] = [["claude", "jetpack", "work"]], name: String = "Mochi") -> Runtime.Status {
            var s = status(sessions: sessions, name: name, growth: nil)
            (s.notes, s.recently, s.daysOld) = ([], [], nil)
            return s
        }
        let values: [(String, (Int) -> Runtime.Status)] = [
            ("its name", { bare(name: words($0)) }),
            ("the mood's reason", { n in var s = bare(); s.moodReason = Narration(cause: words(n)); return s }),
            ("the wish", { n in var s = bare(); s.wishing = words(n); return s }),
            ("the doing's reason", { n in var s = bare(); s.doingReason = Narration(cause: words(n)); return s }),
            ("a buddy's name", { n in
                var s = bare()
                s.buddies = [.init(id: "left", name: words(n), snapshot: s.snapshot, connected: true, device: nil),
                             .init(id: "right", name: words(n), snapshot: s.snapshot, connected: false, device: nil)]
                return s
            }),
            ("a thread's name", { bare([["claude", "jetpack", "work", words($0)]]) }),
            ("a project", { bare([["claude", words($0), "work", "A thread"]]) }),
            ("a workspace", { bare([["claude", "jetpack", "work", "", words($0)]]) }),
            ("a notice", { n in var s = bare(); s.micTrouble = words(n); return s }),
            ("a dressing's reason", { n in var s = bare(); s.dressing = [.init(kind: .friday, why: words(n), what: nil)]; return s }),
            ("a note", { n in var s = bare(); s.notes = [.init(id: 1, section: .you, days: [], text: words(n))]; return s }),
            ("a day's line", { n in var s = bare(); s.recently = [.init(day: "2026-10-21", line: words(n), today: "2026-10-22")]; return s }),
        ]
        for (what, status) in values where height(status(20)) >= height(status(40)) {
            fail("snapshots: \(what) is cut off: twice the words leave the Overview no taller")
        }
        // The needs-you card, apart from its session's row, which grows too.
        let grown = { (kind: String) in
            height(bare([["claude", "jetpack", kind, words(40)]])) - height(bare([["claude", "jetpack", kind, words(20)]]))
        }
        guard grown("wait") > grown("work") + 1 else { fail("snapshots: the needs-you card's thread name is cut off") }
        print("long values: \(values.count + 1) grow the Overview, none cut off")
    }

    /// However long the reasons run, the needs-you card stays where it is:
    /// the top of the pane, on the first screen.
    static func checkNeedsYouComesFirst(_ installer: HookInstaller) {
        /// How far down the card's amber edge first shows, at the pane's middle.
        func cardTop(why: String?) -> Int? {
            var s = status(sessions: [["claude", "jetpack", "wait"]])
            s.moodReason = why.map { Narration(cause: $0) }
            s.wishing = why
            let host = NSHostingView(rootView: PopoverView(model: model(installer, status: s), maxHeight: 560)
                .environment(\.stillMotion, true).environment(\.colorScheme, .light))
            host.appearance = NSAppearance(named: .aqua)
            window.appearance = host.appearance
            window.contentView = host
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                host.frame = CGRect(origin: .zero, size: host.fittingSize)
                window.setContentSize(host.frame.size)
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let rep = bitmap(host.bounds.size, scale: 1)
            host.cacheDisplay(in: host.bounds, to: rep)
            return (0..<rep.pixelsHigh).first { y in
                guard let c = rep.colorAt(x: rep.pixelsWide / 2, y: y)?.usingColorSpace(.sRGB) else { return false }
                return c.redComponent - c.blueComponent > 0.15
            }
        }
        let words = String(repeating: "several words ", count: 150)
        guard let plain = cardTop(why: nil), let long = cardTop(why: words) else { fail("snapshots: no needs-you card to find") }
        guard plain == long else { fail("snapshots: long reasons push the needs-you card down, from \(plain) to \(long) pt") }
        print("needs you: first, at \(plain) pt, however long the reasons")
    }

    static let longNotes: [WrittenMemory.Note] = [
        .init(id: 3, section: .you, days: ["2026-10-20"], text: Long.note),
        .init(id: 12, section: .work, days: ["2026-10-21"], text: "\"\(Long.project)/\(Long.workspace)\": " + Long.note.prefix(50)),
        .init(id: 9, section: .boop, days: ["2026-10-14"], pinned: true, text: Long.note),
    ]

    static let longDays: [Runtime.Status.DayLine] = [
        .init(day: "2026-10-21", line: Long.day, today: "2026-10-22"),
        .init(day: "2026-10-20", line: Long.day, today: "2026-10-22"),
    ]

    // MARK: Contrast

    /// The popover's contrast rules, checked on every run, in both
    /// appearances: each text tone at least 4.5:1 on everything it sits on
    /// (the paper, a card, the well, its own chip and the needs-you card's
    /// amber wash); the filled buttons' labels 4.5:1 on their fills, pressed
    /// too; the filled button 3:1 on a card, so it outweighs an outlined
    /// one; and the coloured menu-bar icons 3:1 on a light and a dark menu bar.
    static func checkContrast() {
        var pairs: [(String, String, String, Double)] = []
        let tones = [("ink", Palette.inkLight, Palette.inkDark), ("inkSoft", Palette.inkSoftLight, Palette.inkSoftDark),
                     ("amberInk", Palette.amberInkLight, Palette.amberInkDark),
                     ("sageInk", Palette.sageInkLight, Palette.sageInkDark),
                     ("clayInk", Palette.clayInkLight, Palette.clayInkDark)]
        // Each appearance's paper, card and well, and its filled button: fill, pressed fill, label.
        let looks = [("light", Palette.paperLight, Palette.raisedLight, Palette.wellLight,
                      Palette.glass, Palette.glassPressed, Palette.oat),
                     ("dark", Palette.paperDark, Palette.raisedDark, Palette.wellDark,
                      Palette.oat, Palette.oatPressed, Palette.glass)]
        for (i, (look, paper, card, well, fill, pressed, label)) in looks.enumerated() {
            for (name, light, dark) in tones {
                let tone = i == 0 ? light : dark
                pairs += [("\(name) on \(look) paper", tone, paper, 4.5),
                          ("\(name) on a \(look) card", tone, card, 4.5),
                          ("\(name) on the \(look) well", tone, well, 4.5),
                          ("\(name) on its \(look) chip", tone, mix(tone, Theme.chipTint, over: card), 4.5),
                          ("\(name) on the \(look) needs-you card", tone, mix(Palette.amber, Theme.cardTint, over: card), 4.5)]
            }
            pairs += [("a button's label on its \(look) fill", label, fill, 4.5),
                      ("a button's label on its \(look) pressed fill", label, pressed, 4.5),
                      ("a \(look) filled button on a card", fill, card, 3)]
        }
        pairs += [("needs you on a light menu bar", Palette.menuAmberLight, "#F5F5F5", 3),
                  ("needs you on a dark menu bar", Palette.amber, "#2A2A2A", 3)]
        let low = pairs.compactMap { what, fg, bg, least -> String? in
            let ratio = contrast(fg, bg)
            return ratio < least ? "\(what) is \(String(format: "%.2f", ratio)):1, under \(least):1" : nil
        }
        if !low.isEmpty { fail("snapshots: contrast: \(low.joined(separator: "; "))") }
        print("contrast: \(pairs.count) pairs pass")
    }

    /// `fg` at `alpha` over `bg`, as SwiftUI's opacity composites it.
    static func mix(_ fg: String, _ alpha: Double, over bg: String) -> String {
        let (f, b) = (NSColor(hex: fg), NSColor(hex: bg))
        let c = { (x: CGFloat, y: CGFloat) in Int(((alpha * Double(x) + (1 - alpha) * Double(y)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(f.redComponent, b.redComponent),
                      c(f.greenComponent, b.greenComponent), c(f.blueComponent, b.blueComponent))
    }

    static func contrast(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let c = NSColor(hex: hex)
            let lin = { (v: CGFloat) -> Double in
                let v = Double(v)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    // MARK: Rendering

    private static let window = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)

    /// `whole`: tall enough for all of it, so nothing in it may scroll.
    static func render<V: View>(_ view: V, _ name: String, dark: Bool, to dir: URL, heightLimit: CGFloat? = nil, whole: Bool = false) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.stillMotion, true)
            .environment(\.displayScale, scale)
            .environment(\.controlActiveState, .key))
        host.appearance = appearance
        window.appearance = appearance
        window.contentView = host
        // Size to the content, twice: scroll panes measure themselves on
        // the first pass and settle on the second. A turn of the run loop
        // between passes is all they need; a longer wait changes no pixel.
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            host.frame = CGRect(origin: .zero, size: size)
            window.setContentSize(size)
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        host.layoutSubtreeIfNeeded()
        if let heightLimit, host.bounds.height > heightLimit {
            fail("snapshots: \(name) exceeds its \(Int(heightLimit)) pt height limit: \(host.bounds.height)")
        }
        window.displayIfNeeded()
        if whole { checkNothingScrolls(host, name) }
        // At Retina's 2 pixels a point, as most Macs show it, so blur and
        // seams a 1× picture hides show.
        let rep = bitmap(host.bounds.size, scale: scale)
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        let url = dir.appendingPathComponent("\(name).png")
        do { try png.write(to: url) } catch { fail("snapshots: can't write \(url.path): \(error)") }
        print("\(name).png \(Int(host.bounds.width))×\(Int(host.bounds.height)) pt at \(Int(scale))×")
    }

    /// Pixels a point in the panes' and onboarding's pictures.
    static let scale: CGFloat = 2

    /// Every icon on a light and a dark menu bar, as the bar draws it: the
    /// top row at 1× and the bottom at 2×, each pixel blown up to 4×4 or 2×2
    /// so the grid can be judged.
    static func renderIcons(dark: Bool, to dir: URL) {
        let moods: [FaceMood] = [.asleep, .idle, .working, .needsYou, .stopped]
        let icon = MenuBarIcon.image(.idle).size
        let pad: CGFloat = 10, gap: CGFloat = 14, row: CGFloat = 24, zoom: CGFloat = 4
        let size = NSSize(width: 2 * pad + CGFloat(moods.count) * icon.width + CGFloat(moods.count - 1) * gap,
                          height: 2 * row)
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let bar = NSColor(white: dark ? 0.16 : 0.93, alpha: 1)
        let ink = dark ? NSColor.white : NSColor(white: 0, alpha: 0.85)
        // One strip of icons at `scale` pixels per point, on the bar's colour.
        func strip(_ scale: CGFloat) -> NSBitmapImageRep {
            let rep = bitmap(NSSize(width: size.width, height: row), scale: scale)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bar.setFill()
            NSRect(origin: .zero, size: rep.size).fill()
            appearance.performAsCurrentDrawingAppearance {
                for (i, mood) in moods.enumerated() {
                    // Whole points, as the status button places it.
                    let rect = NSRect(x: pad + CGFloat(i) * (icon.width + gap), y: ((row - icon.height) / 2).rounded(.down),
                                      width: icon.width, height: icon.height)
                    let image = MenuBarIcon.image(mood)
                    if image.isTemplate {
                        // A template image takes the menu bar's colour.
                        NSImage(size: icon, flipped: false) { r in
                            image.draw(in: r)
                            ink.set()
                            r.fill(using: .sourceAtop)
                            return true
                        }.draw(in: rect)
                    } else {
                        image.draw(in: rect)
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let rep = bitmap(size, scale: zoom)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        context?.imageInterpolation = .none
        NSGraphicsContext.current = context
        strip(1).draw(in: NSRect(x: 0, y: row, width: size.width, height: row), from: .zero, operation: .copy,
                      fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        strip(2).draw(in: NSRect(x: 0, y: 0, width: size.width, height: row), from: .zero, operation: .copy,
                      fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        NSGraphicsContext.restoreGraphicsState()
        let name = "menubar-\(dark ? "dark" : "light")"
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        do { try png.write(to: dir.appendingPathComponent("\(name).png")) } catch { fail("snapshots: \(error)") }
        print("\(name).png")
    }

    private static func bitmap(_ size: NSSize, scale: CGFloat) -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale),
                                         pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { fail("snapshots: no icon bitmap") }
        rep.size = size
        return rep
    }
}

