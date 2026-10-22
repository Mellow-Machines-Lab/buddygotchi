import AgentHooks
import BoopKit
import Foundation
import MellowHarness
import os

/// `Boop --headless`: the whole runtime with isolated state, no UI and no
/// Bluetooth. The device, if any, is reached through a USB bridge
/// (`linkkit-bridge`) or the simulator's socket.
enum Headless {
    static func run(_ args: Arguments) -> Never {
        guard let dir = args["--state-dir"] else { fail("--headless needs --state-dir\n" + usage) }
        let stateDir = URL(fileURLWithPath: dir).standardizedFileURL
        guard let link = LinkSetting(args["--link"] ?? "none") else { fail("--link is usb:SOCKET or none") }
        if link == .bluetooth { fail("headless mode never uses Bluetooth; use --link usb:SOCKET") }
        let socketPath = args["--socket"] ?? stateDir.appendingPathComponent("boop.sock").path
        // Checked before anything is set up, as the hook server checks it: a
        // Unix socket's path has room for 103 bytes (sockaddr_un), and a
        // scratch directory is often longer.
        if HookSocket.unixAddress(socketPath) == nil {
            let room = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1
            fail("the hook socket \(socketPath) is \(socketPath.utf8.count) bytes, and a Unix socket's path "
                 + "has room for \(room): pass --socket with a shorter one")
        }
        // Every value is checked before anything is written, so a typo
        // doesn't leave a set-up Boop behind for the next run to keep.
        let personality = args.choice("--personality", of: Personality.allCases.map(\.rawValue)).flatMap(Personality.init(rawValue:))
        // A demo needs no brain: its script says how Boop reacts.
        let demo = args["--demo"]
        let brain = args.choice("--brain", of: ["jev", "scripted", "none"]) ?? (demo == nil ? "jev" : "none")
        if args["--record"] != nil, demo == nil { fail("--record needs --demo") }
        if args.has("--live"), demo == nil { fail("--live needs --demo") }
        var script: DemoScript?
        if let demo {
            // `pack` is the character pack's own, and `pack:NAME` its demo/NAME.jsonl.
            let named = demo == "pack" ? "demo" : demo.hasPrefix("pack:") ? String(demo.dropFirst(5)) : nil
            guard let file = named.map(CharacterPack.active.demo(named:)) ?? URL(fileURLWithPath: demo) else {
                fail("the character pack \(CharacterPack.active.id) has no demo/\(named ?? "demo").jsonl")
            }
            do { script = try DemoScript(contentsOf: file) } catch { fail("\(error)") }
            // A line the pack can't play would otherwise pass by quietly.
            let problems = script?.problems() ?? []
            if !problems.isEmpty { fail(problems.map { "\(file.lastPathComponent): \($0)" }.joined(separator: "\n")) }
        }
        // Several buddies: from --buddies, else the demo's header.
        var buddies: [BuddySetting] = script?.buddies ?? []
        if let text = args["--buddies"] {
            guard let parsed = BuddySetting.parse(text) else { fail("--buddies is PLACE:PACK[:AGENT[:NAME]],… with each place once") }
            buddies = parsed
        }
        var links: [LinkSetting] = []
        for item in args["--links"]?.split(separator: ",") ?? [] {
            guard let l = LinkSetting(String(item)), l != .bluetooth else { fail("--links is usb:SOCKET or none, one for each buddy, in order") }
            links.append(l)
        }
        if !links.isEmpty, links.count != buddies.count { fail("--links needs one link for each of the \(buddies.count) buddies") }
        guard let nature = LongTerm.Nature(rawValue: args["--nature"] ?? "sweet") else { fail("--nature is sweet or cheeky") }
        let log = LogFile(directory: stateDir, echo: true)

        let memory = try? MemoryStore(directory: stateDir, log: { log.write($0) })
        if memory?.isSetUp != true {
            let name = args["--name"] ?? "Boop"
            do {
                try Runtime.setUp(stateDir: stateDir, name: name, nature: nature)
                log.write("boop: set up \(name) (\(nature.rawValue)) in \(stateDir.path)")
            } catch {
                fail("can't set up \(stateDir.path): \(error)")
            }
        }

        // Headless always takes the dashboard's lines.
        var options = runtimeOptions(stateDir: stateDir, socketPath: socketPath, link: link, debug: args.has("--debug"),
                                     devLines: true, log: log, buddies: buddies, links: links)
        // Jev's key only from BOOP_JEV_KEY, as boopdev: a run from an agent
        // shell must never use the owner's key from the Keychain.
        options.readJevKey = { _ in JevKey.environment() }
        if brain == "scripted" { options.brain = { _ in ScriptedBrain.pipelineCheck } }
        if brain == "none" { options.brain = { _ in nil } }
        // `--record` listens from the start, so the recording opens with
        // how things stood when the demo began (DemoRecorder.begin).
        let recorder = args["--record"].map { _ in DemoRecorder() }
        if let recorder { options.onDeviceLine = { recorder.sent($0) } }
        // The clock can be moved forward with `{"dev":"advance","ms":N}`, so
        // the pipeline check can finish a 6-minute turn without waiting it out.
        // A demo with a `start` begins at that date and time.
        let startSkew = script?.start.map { $0 - options.wallClock() } ?? 0
        let skew = OSAllocatedUnfairLock(initialState: startSkew)
        let (clock, wallClock) = (options.clock, options.wallClock)
        options.clock = { clock() + skew.withLock { $0 } }
        options.wallClock = { wallClock() + skew.withLock { $0 } }
        options.advance = { ms in skew.withLock { $0 += ms } }
        // A tap while something needs you opens the thread on this Mac;
        // agents' runs only log where.
        if args.has("--no-open") { options.open = { _ in log.write("open: skipped (--no-open)"); return true } }
        if let personality { options.personality = personality }
        let runtime: Runtime
        do {
            runtime = try Runtime(options)
            try runtime.start()
        } catch {
            fail("boop: \(error)")
        }

        if let script {
            play(script, live: args.has("--live"), cursor: stateDir.appendingPathComponent("demo-cursor"),
                 on: runtime, link: link, links: links, recorder: recorder, to: args["--record"], log: log)
        }

        // Stop cleanly: close the socket and the link, then exit 0.
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                log.write("boop: stopping (signal \(sig))")
                runtime.stop()
                runtime.home.sync {}
                log.write("boop: stopped")
                exit(0)
            }
            source.resume()
            sources.append(source)
        }
        withExtendedLifetime(sources) { dispatchMain() }
    }

    /// `--demo`: plays the script once the device is there (with a link),
    /// then stops. `recorder` keeps what the device was sent
    /// (`DemoRecording`), written to `file` for the simulator's page.
    static func play(_ script: DemoScript, live: Bool, cursor: URL, on runtime: Runtime, link: LinkSetting, links: [LinkSetting],
                     recorder: DemoRecorder?, to file: String?, log: LogFile) {
        // Ready at once, so a live agent may start while the device is
        // awaited; played once it's there.
        let player = runtime.home.sync {
            runtime.demo(script, live: live, cursor: cursor, step: { step, agent in
                let cause = step.cause(creature: (runtime.buddies.first { $0.id == step.buddy }?.name ?? runtime.name), agent: agent)
                if let cause { log.write("demo: \(cause.text)") }
                recorder?.happened(cause, input: step.input)
            }, done: {
                if let recorder, let file {
                    let face = runtime.link.hello.map { DeviceInfo($0).face.rawValue } ?? "pixel"
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    do {
                        try encoder.encode(recorder.recording(character: CharacterPack.active.id, face: face))
                            .write(to: URL(fileURLWithPath: file), options: .atomic)
                        log.write("demo: recorded to \(file)")
                    } catch {
                        log.write("demo: can't write \(file): \(error)")
                    }
                }
                runtime.stop()
                log.write("boop: stopped")
                exit(0)
            })
        }
        // With a device, wait for it to say who it is: up to 15 s, or for
        // as long as a live demo's caller waits, its person perhaps still
        // opening the simulator's page.
        var tries = 0
        func wait() {
            tries += 1
            if (links.isEmpty ? [link] : links).allSatisfy({ $0 == .none }) || runtime.helloFromEvery {
                recorder?.begin(name: runtime.name)
                return player.start()
            }
            if !live, tries > 150 { fail("demo: no device on \(link) after 15 s") }
            runtime.home.asyncAfter(deadline: .now() + 0.1, execute: wait)
        }
        runtime.home.async(execute: wait)
    }
}
