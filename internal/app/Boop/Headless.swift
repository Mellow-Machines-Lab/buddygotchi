import AgentHooks
import BoopKit
import Foundation
import MellowHarness
import os

/// `Boop --headless`: the whole runtime with isolated state, no UI and no
/// Bluetooth. The device, if any, is reached through `boopctl bridge`.
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
        // A demo needs no brain: its script says how Boop reacts. With
        // --brain, the brain answers for the beats that don't.
        let demo = args["--demo"]
        let brain = args.choice("--brain", of: ["jev", "scripted"]) ?? (demo == nil ? "jev" : "none")
        if args["--record"] != nil, demo == nil { fail("--record needs --demo") }
        var script: DemoScript?
        if let demo {
            // `pack` is the character pack's own.
            guard let file = demo == "pack" ? CharacterPack.active.demo : URL(fileURLWithPath: demo) else {
                fail("the character pack \(CharacterPack.active.id) has no demo (demo/demo.jsonl)")
            }
            do { script = try DemoScript(contentsOf: file) } catch { fail("\(error)") }
        }
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
                                     devLines: true, log: log)
        // Jev's key only from BOOP_JEV_KEY, as boopdev: a run from an agent
        // shell must never use the owner's key from the Keychain.
        options.readJevKey = { _ in JevKey.environment() }
        if brain == "scripted" { options.brain = { _ in ScriptedBrain.pipelineCheck } }
        if brain == "none" { options.brain = { _ in nil } }
        // The clock can be moved forward with `{"dev":"advance","ms":N}`, so
        // the pipeline check can finish a 6-minute turn without waiting it out.
        let skew = OSAllocatedUnfairLock(initialState: Int64(0))
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

        if let script { play(script, on: runtime, link: link, record: args["--record"], log: log) }

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
    /// then stops. `--record FILE` writes what the device was sent
    /// (`DemoRecording`), for the simulator's page to play back.
    static func play(_ script: DemoScript, on runtime: Runtime, link: LinkSetting, record: String?, log: LogFile) {
        // Listening from the start, so the recording opens with how things
        // stood when the demo began (DemoRecorder.begin).
        let recorder: DemoRecorder? = record == nil ? nil : DemoRecorder()
        if let recorder { runtime.deviceLines.listen { line in recorder.sent(line) } }
        let name = runtime.name
        func start() {
            recorder?.begin()
            runtime.play(script, beat: { beat in
                if let cause = beat.cause(creature: name) {
                    log.write("demo: \(cause.text)")
                    recorder?.happened(cause)
                }
            }, done: {
                if let recorder, let record {
                    let face = runtime.link.hello.map { DeviceInfo($0).face.rawValue } ?? "pixel"
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    do {
                        try encoder.encode(recorder.recording(character: CharacterPack.active.id, name: name, face: face))
                            .write(to: URL(fileURLWithPath: record), options: .atomic)
                        log.write("demo: recorded to \(record)")
                    } catch {
                        log.write("demo: can't write \(record): \(error)")
                    }
                }
                runtime.stop()
                log.write("boop: stopped")
                exit(0)
            })
        }
        // With a device, wait for it to say who it is, up to 15 s.
        var tries = 0
        func wait() {
            tries += 1
            if link == .none || runtime.link.hello != nil { return start() }
            if tries > 150 { fail("demo: no device on \(link) after 15 s") }
            runtime.home.asyncAfter(deadline: .now() + 0.1, execute: wait)
        }
        runtime.home.async(execute: wait)
    }
}
