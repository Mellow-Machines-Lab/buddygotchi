import AgentHooks
import AppKit
import BoopKit
import LinkKit
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

            // The slime mirror's, when the character pack has one (Boop's).
            let gelState = StateSnapshot(base: "working", act: "terminal", mood: "happy", attn: nil, busy: 1, vol: 6)
            var gelImage: NSImage?
            if SlimeFeed.folder != nil {
                _ = try SlimeSnapshots.image(gelState, to: out.appendingPathComponent("slime-working.png"))
                gelImage = try SlimeSnapshots.image(gelState, to: out.appendingPathComponent("slime-tile.png"), size: NSSize(width: 46, height: 46))
                let gelAttention = StateSnapshot(base: "working", mood: "frightened",
                    attn: .init(agent: "codex", project: "Boop", more: 0, id: 1), busy: 1, vol: 6)
                _ = try SlimeSnapshots.image(gelAttention, to: out.appendingPathComponent("slime-needs-you.png"))
            }
            for dark in [false, true] {
                /// The popover on `pane`, tall enough for all of it.
                func shot(_ name: String, _ model: AppModel, pane: Pane) {
                    model.pane = pane
                    render(PopoverView(model: model, maxHeight: 2000), "\(name)-\(dark ? "dark" : "light")", dark: dark, to: out)
                }
                for (name, model) in overviews(installer) { shot("overview-\(name)", model, pane: .overview) }
                if let gelImage {
                    var gelStatus = status(mood: "happy")
                    gelStatus.snapshot = gelState
                    gelStatus.device = DeviceInfo(id: "gel-fixture", fw: "snapshots", face: .gel)
                    let gel = model(installer, status: gelStatus)
                    gel.slime.stillImage = gelImage
                    shot("overview-gel", gel, pane: .overview)
                }
                let settings = model(installer, status: status(sessions: [["codex", "landing", "work"]]))
                try? installer.install(.claude)
                settings.refreshHooks()
                settings.restartAgents = true
                shot("settings", settings, pane: .settings)
                try? installer.remove(.claude)
                shot("settings-chatter", model(installer, status: status(personality: Personality.other)), pane: .settings)
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
                shot("settings-bluetooth-off", model(installer, status: status(connected: false, linkTrouble: BLETransport.trouble(.poweredOff, appName: "Boop"))),
                     pane: .settings)
                // A simulator running on this Mac: a body to choose, and chosen.
                let offered = model(installer, status: status())
                offered.simulator = .there
                shot("settings-simulator-there", offered, pane: .settings)
                let simulated = model(installer, status: status())
                simulated.simulator = .inUse
                shot("settings-simulator-used", simulated, pane: .settings)
                // A card with another pack than the app's, and no card or pack: no voice.
                shot("settings-old-voice", model(installer, status: status(voice: "0123456789abcdef")), pane: .settings)
                shot("settings-no-voice", model(installer, status: status(voice: "none")), pane: .settings)
                // Firmware from before LinkKit: the looks, but no reactions (linkkit/SPEC.md §6).
                shot("settings-old-firmware", model(installer, status: status(deviceTrouble: "the device's firmware is too old for this app: flash it")),
                     pane: .settings)

                for step in SetupDraft.Step.allCases {
                    let setup = model(installer, status: nil)
                    setup.setup.step = step
                    setup.setup.agents = [.claude]
                    if step.rawValue >= SetupDraft.Step.name.rawValue { setup.setup.name = "Mochi" }
                    shot("setup-\(step.rawValue + 1)-\(step)", setup, pane: .setup)
                }
                let cheeky = model(installer, status: nil)
                cheeky.setup.step = .name
                cheeky.setup.name = "Mochi"
                cheeky.setup.nature = .cheeky
                shot("setup-2-name-cheeky", cheeky, pane: .setup)
                for (name, text) in [("unicode", "우리의작은친구말랑이"), ("invalid", "Mochi: Pip")] {
                    let named = model(installer, status: nil)
                    named.setup.step = .name
                    named.setup.editName(text)
                    shot("setup-2-name-\(name)", named, pane: .setup)
                }
                let setup = model(unbuilt, status: nil)
                setup.setup.step = .agents
                setup.setup.agents = [.claude]
                setup.setup.name = "Mochi"
                shot("setup-3-agents-no-hook", setup, pane: .setup)
                if let crowded = overviews(installer).first(where: { $0.0 == "crowded" })?.1 {
                    crowded.status?.snapshot.vol = 0
                    crowded.status?.personality = Personality.other
                    render(PopoverView(model: crowded, maxHeight: 560),
                           "overview-bounded-\(dark ? "dark" : "light")", dark: dark, to: out, heightLimit: 560)
                }
                renderIcons(dark: dark, to: out)
            }
        } catch {
            fail("snapshots: \(error)")
        }
        exit(0)
    }

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

    static func model(_ installer: HookInstaller, status: Runtime.Status?, link: LinkSetting = .bluetooth,
                      ownsHooks: Bool = true) -> AppModel {
        let model = AppModel(installer: installer, ownsHooks: ownsHooks, link: link)
        model.status = status
        model.readKey = { nil }  // fixtures only: never the real Keychain
        return model
    }

    /// `sessions` are agent, project, `wait`, `work` or `idle`, and
    /// optionally the thread's name and its workspace.
    static func status(base: String = "working", sessions rows: [[String]] = [], vol: Int = 6,
                       connected: Bool = true, personality: Personality = .default,
                       name: String = "Mochi", brain: String = "jev:jev-latest", keyRead: Bool = true,
                       mood: String = MoodAction.initial, brainTrouble: BrainTrouble? = nil,
                       listening: Bool = false, micTrouble: String? = nil, voice: String? = nil,
                       linkTrouble: String? = nil, deviceTrouble: String? = nil,
                       growth: Growth? = Growth(xp: 1_340)) -> Runtime.Status {
        let statuses: [String: SessionSummary.Status] = ["wait": .waiting, "work": .working, "idle": .idle]
        // Each in its agent's own app, so its row opens it.
        let sessions = rows.enumerated().map { i, row in
            SessionSummary(agent: row[0], project: row[1], name: row.count > 3 && !row[3].isEmpty ? row[3] : nil,
                           workspace: row.count > 4 ? row[4] : nil, status: statuses[row[2]]!,
                           thread: ThreadRef(agent: row[0], session: "s\(i)",
                                             app: row[0] == "claude" ? "com.anthropic.claudefordesktop" : "com.openai.codex",
                                             appSession: "local_\(i)"))
        }
        let wait = sessions.filter { $0.status == .waiting }
        let snapshot = StateSnapshot(
            base: base, mood: mood,
            // Cut as the core cuts it for the device; the popover shows it whole.
            attn: wait.first.map {
                StateSnapshot.Attention(agent: $0.agent, project: StateSnapshot.clip($0.project, marked: true),
                                        name: $0.name.map { StateSnapshot.clip($0, marked: true) } ?? "", more: wait.count - 1)
            },
            busy: sessions.filter { $0.status == .working }.count, vol: vol)
        return Runtime.Status(name: name, snapshot: snapshot, sessions: sessions, connected: connected,
                              device: connected && deviceTrouble == nil ? DeviceInfo(id: "b00p-54fe", fw: "1.0.0", voice: voice) : nil,
                              linkTrouble: linkTrouble, deviceTrouble: deviceTrouble,
                              personality: personality, brain: brain, keyRead: keyRead, brainTrouble: brainTrouble,
                              listening: listening, micTrouble: micTrouble, growth: growth)
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
            // A long project and a long branch: the branch is cut first.
            ("needs-you-long", model(installer, status: status(sessions: [
                ["claude", "buddygotchi-landing-page", "wait", "", "claude/very-long-branch-name-for-the-hero"],
                ["codex", "jetpack", "wait"],
            ]))),
            ("chatter", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], personality: Personality.other))),
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
            ("cant-hear", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                          micTrouble: "Allow Boop in System Settings → Privacy & Security → Microphone."))),
            // No card, or no voice pack on it.
            ("no-voice", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]], voice: "none"))),
            // Bluetooth refused at the first launch's prompt.
            ("no-bluetooth", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                             connected: false, linkTrouble: BLETransport.trouble(.unauthorized, appName: "Boop")))),
            ("no-device", model(installer, status: status(base: "idle", sessions: [["claude", "jetpack", "idle"]],
                                                          connected: false), link: .none)),
            // Every chip at once (Chatter and Muted), under the longest kind of name.
            ("all-chips", model(installer, status: status(sessions: [["claude", "jetpack", "work"]], vol: 0,
                                                          personality: Personality.other, name: "Wobblebottom McSnugs"))),
            // Many sessions, a long project, two in one project, and one
            // needing you from a project with no name.
            ("crowded", model(installer, status: status(sessions: [
                ["codex", "", "wait"], ["claude", "jetpack", "work"], ["claude", "jetpack", "work"],
                ["codex", "buddygotchi-landing-page-redesign", "work"], ["claude", "notes", "work"],
                ["codex", "landing", "idle"], ["claude", "dotfiles", "idle"], ["claude", "blog", "idle"],
                ["codex", "scratch", "idle"], ["claude", "archive", "idle"],
            ]))),
        ]
    }

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

    static func render<V: View>(_ view: V, _ name: String, dark: Bool, to dir: URL, heightLimit: CGFloat? = nil) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.stillMotion, true)
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
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("snapshots: \(name) has no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("snapshots: \(name) has no PNG") }
        let url = dir.appendingPathComponent("\(name).png")
        do { try png.write(to: url) } catch { fail("snapshots: can't write \(url.path): \(error)") }
        print("\(name).png \(Int(host.bounds.width))×\(Int(host.bounds.height))")
    }

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

extension Personality {
    /// A personality other than the pack's default, to show one in the
    /// snapshots: Boop's chatter. The default when the pack has one only.
    static var other: Personality { allCases.dropFirst().first ?? .default }
}
