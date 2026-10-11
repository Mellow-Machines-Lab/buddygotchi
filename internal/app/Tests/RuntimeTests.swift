import AgentHooks
import Foundation
import MellowHarness
import LinkKit
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// The runtime end to end in-process: real hook socket, real core, the
/// harness with a scripted brain, and memory in a temporary state
/// directory; a fake device. Jev's key is never read from the Keychain, and
/// nothing reaches Jev.
final class RuntimeTests: XCTestCase {
    var dir: URL!
    /// What the runtime opened on the Mac, as `open`'s arguments: never for
    /// real in a test.
    let opened = Lines()

    override func setUpWithError() throws {
        try requireBoopsPack()
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-rt-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    static let steeringDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../characters/boop/steering").standardizedFileURL
    static let steering = try! Steering(directory: steeringDir)

    /// A runtime whose brain is `brain` once the key reads, or none.
    func options(_ transport: FakeTransport?, brain: ScriptedBrain = .pipelineCheck,
                 readJevKey: @escaping @Sendable (() -> String?) -> String? = { _ in "k" }) throws -> Runtime.Options {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet)
        var options = Runtime.Options(stateDir: dir, socketPath: socketPath, link: transport, steering: Self.steering)
        options.devLines = true
        options.readJevKey = readJevKey
        options.brain = { key in key.map { _ in brain } }
        let opened = self.opened
        options.open = { opened.add($0.arguments.joined(separator: " ")); return true }
        return options
    }

    func makeRuntime(_ transport: FakeTransport, brain: ScriptedBrain = .pipelineCheck,
                     readJevKey: @escaping @Sendable (() -> String?) -> String? = { _ in "k" }) throws -> Runtime {
        try Runtime(options(transport, brain: brain, readJevKey: readJevKey))
    }

    /// Mirroring a requested moment cannot finish its
    /// Pending. Only the device's ended drives the reaction lifecycle.
    func testTheVisualMirrorDoesNotOwnReactionCompletion() throws {
        let runtime = try makeRuntime(FakeTransport())
        runtime.home.sync {
            runtime.connection(true)
            runtime.device(FakeTransport.hello)
            var mirrored: [(Int, DeviceMoment)] = [], ends: [Pending.End] = []
            runtime.onMoment = { mirrored.append(($0, $1)) }
            let pending = Pending()
            pending.bind { ends.append($0) }
            let moment = DeviceMoment(anim: "task_complete", mood: "happy", loops: 2, outcome: "success")
            runtime.queue(moment, pending)
            XCTAssertEqual(mirrored.count, 1)
            XCTAssertEqual(mirrored[0].1.mood, "happy")
            XCTAssertTrue(ends.isEmpty)
            runtime.device(FakeTransport.ended(mirrored[0].0, "done"))
            XCTAssertEqual(ends, [.done])
            runtime.playRule(DeviceMoment(anim: "poked"))
            XCTAssertEqual(mirrored.last?.1.name, "poked")
        }
    }

    /// The mirror follows the
    /// core's reply hold, independently of the mic's recording status.
    func testTheMirrorKeepsListeningWhileTheReplyIsPending() throws {
        let clock = VirtualClock(1000)
        var options = try options(nil)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        runtime.home.sync {
            var statuses: [Runtime.Status] = []
            runtime.onChange = { statuses.append($0) }
            _ = runtime.core.listen(true, at: clock.now)
            runtime.changed()
            XCTAssertTrue(statuses.last!.listening)
            XCTAssertTrue(statuses.last!.faceListening)
            clock.now += 100
            _ = runtime.core.listen(false, at: clock.now)
            runtime.changed()
            XCTAssertFalse(statuses.last!.listening)
            XCTAssertTrue(statuses.last!.faceListening)
            clock.now += Core.replyWaitMs
            runtime.changed()
            XCTAssertFalse(statuses.last!.faceListening)
        }
    }

    /// The automatic hello reply must never send a gel
    /// mood name to a pixel board, even on a transport reused without a drop.
    func testFaceCapabilityMapsTheFirstReplyAndEveryReconnect() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        let logical = StateSnapshot(base: "idle", mood: "frightened", attn: nil, busy: 0, vol: 6)
        let gelHello = FakeTransport.hello.dropLast() + #","face":"gel"}"#
        runtime.home.sync {
            runtime.show(logical)
            runtime.connection(true)
            runtime.device(String(gelHello))
            XCTAssertEqual(runtime.link.state?["mood"]?.string, "frightened")
            let beforePixel = transport.sent.count
            runtime.device(FakeTransport.hello)
            let replies = transport.sent.dropFirst(beforePixel).filter { $0.hasPrefix(#"{"t":"state""#) }
            XCTAssertFalse(replies.isEmpty)
            XCTAssertTrue(replies.allSatisfy { $0.contains(#""mood":"wounded""#) })
            XCTAssertEqual(runtime.link.state?["mood"]?.string, "wounded")
            runtime.device(String(gelHello))
            runtime.connection(false)
            runtime.connection(true)
            XCTAssertEqual(runtime.link.state?["mood"]?.string, "wounded")
            XCTAssertEqual(runtime.latest?.mood, "frightened")
        }
    }

    /// linkkit/SPEC.md §6: a `hello` the link turns away
    /// (too old, too new, no kit, another app) is answered with pixel's
    /// `state` whatever face it says, even after a gel one; one it takes
    /// that says gel gets gel's from the very first `state` it's answered
    /// with. LinkKit's own rule judges which fit.
    func testOnlyAHelloTheLinkTakesIsAnsweredInGel() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        let logical = StateSnapshot(base: "idle", mood: "frightened", attn: nil, busy: 0, vol: 6)
        let gel = String(FakeTransport.hello.dropLast()) + #","face":"gel"}"#, kit = #""kit":1"#
        let turnedAway = [gel.replacingOccurrences(of: kit, with: #""kit":0"#),
                          gel.replacingOccurrences(of: kit, with: #""kit":2"#),
                          gel.replacingOccurrences(of: kit + ",", with: ""),
                          gel.replacingOccurrences(of: #""app":"boop""#, with: #""app":"lamp""#)]
        XCTAssertNil(BoopDevice.face(saying: FakeTransport.ended(1, "done")), "not a hello")
        runtime.home.sync {
            runtime.show(logical)
            runtime.connection(true)
            /// The first `state` sent in answer to `hello`.
            func answer(_ hello: String) -> String? {
                let before = transport.sent.count
                runtime.device(hello)
                return transport.sent.dropFirst(before).first { $0.hasPrefix(#"{"t":"state""#) }
            }
            for hello in turnedAway {
                XCTAssertEqual(BoopDevice.face(saying: hello), .pixel, hello)
                XCTAssertTrue(answer(hello)?.contains(#""mood":"wounded""#) ?? false, hello)
                XCTAssertNotNil(runtime.link.trouble, hello)
            }
            XCTAssertEqual(BoopDevice.face(saying: gel), .gel)
            XCTAssertTrue(answer(gel)?.contains(#""mood":"frightened""#) ?? false)
            XCTAssertNil(runtime.link.trouble)
            XCTAssertTrue(answer(turnedAway[1])?.contains(#""mood":"wounded""#) ?? false, "gel to pixel on the same link")
        }
    }

    /// Jev's key is read off `home`, since a Keychain
    /// prompt would stall every event, and no event wakes the brain until it
    /// arrives; a key Settings saves or clears takes over at once. The read
    /// starts with `start`, once the callbacks are set, so it never races
    /// the app setting them. The status says whether it's been read, so the
    /// popover never asks for a key that's still being read.
    func testJevsKeyIsReadOffHome() throws {
        let prompt = DispatchSemaphore(value: 0)
        let reads = Lines()
        // The first read is the start's, whose `saved` is the Keychain's;
        // Settings' come after, with the key it saved.
        let runtime = try makeRuntime(FakeTransport(), brain: ScriptedBrain(id: "jev-test", always: [:])) { saved in
            reads.add("read")
            guard reads.all.count == 1 else { return saved() }
            prompt.wait()  // as a Keychain prompt waits for an answer
            return "k"
        }
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(reads.all, [], "not before start")
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        eventually("home answers while the key is read") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertTrue(runtime.home.sync { statuses.allSatisfy { !$0.keyRead } }, "not read yet, so not missing")
        prompt.signal()
        eventually("the brain once it's read") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
        XCTAssertTrue(runtime.home.sync { statuses.last?.keyRead == true })
        XCTAssertTrue(runtime.home.sync { runtime.pipeline.brain })
        runtime.reloadBrain(jevKey: nil)
        eventually("none when Settings clears it") { runtime.home.sync { statuses.last?.brain == "none" } }
        XCTAssertTrue(runtime.home.sync { statuses.last?.keyRead == true }, "read, and there's none")
        XCTAssertFalse(runtime.home.sync { runtime.pipeline.brain }, "so no event wakes it")
        runtime.reloadBrain(jevKey: "k2")
        eventually("the brain when Settings saves one") { runtime.home.sync { statuses.last?.brain == "jev-test" } }
    }

    /// Saving a key while the startup read waits
    /// wins outright. Its late result must not rebuild the active brain
    /// and invalidate a pass that already uses the saved key.
    func testALateStartupKeyReadDoesNotReplaceSettingsBrain() throws {
        let prompt = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        let reads = Lines(), built = Lines()
        var options = try options(FakeTransport()) { saved in
            reads.add("read")
            guard reads.all.count == 1 else { return saved() }
            prompt.wait()
            returned.signal()
            return "startup-key"
        }
        options.brain = { key in
            built.add(key ?? "none")
            return key.map { ScriptedBrain(id: $0, always: [:]) }
        }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        eventually("the startup read waits") { reads.all.count == 1 }
        runtime.reloadBrain(jevKey: "settings-key")
        eventually("Settings builds its brain") { built.all == ["settings-key"] }
        prompt.signal()
        XCTAssertEqual(returned.wait(timeout: .now() + 1), .success)
        Thread.sleep(forTimeInterval: 0.1)
        runtime.home.sync {}
        XCTAssertEqual(built.all, ["settings-key"], "a late read must not rebuild the brain")
        XCTAssertEqual(runtime.home.sync { runtime.harness.brain?.id }, "settings-key")
    }

    /// The transport says the device connected, and the device says hello
    /// when the app first speaks: `home` has heard both, so a `do` goes out.
    func connect(_ transport: FakeTransport, _ runtime: Runtime) {
        transport.onConnection?(true)
        eventually("the device's hello") { runtime.home.sync { runtime.link.hello != nil } }
    }

    func hook(_ hook: String, tool: String? = nil) -> Data {
        HookLine(agent: "claude", hook: hook, session: "s1", cwd: "/tmp/jetpack", tool: tool,
                 ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded()
    }

    func testHooksReachTheDeviceAndInputsComeBack() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        eventually("first state on start") { transport.types().contains("state") }
        connect(transport, runtime)

        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("working state") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        XCTAssertTrue(HookSocket.send(hook("PermissionRequest", tool: "Bash"), to: socketPath))
        eventually("needs you") { transport.sent.contains { $0.contains("\"attn\":{\"agent\":\"claude\",\"project\":\"jetpack\"") } }

        // The device's hello gets a state back.
        let before = transport.types().filter { $0 == "state" }.count
        transport.onLine?(FakeTransport.hello)
        eventually("state after hello") { transport.types().filter { $0 == "state" }.count > before }
        XCTAssertEqual(runtime.home.sync { runtime.link.hello?.id }, "b00p-54fe")

        // A finished turn clears "needs you", and the brain plays its
        // finish (no rule does).
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's finish") {
            transport.dos("task_complete").contains {
                $0.contains(#""play":"next","ttl":5000,"args":{"outcome":"success","variant":"#) && $0.contains(#""say":"#)
                    && $0.contains(#""mood":"excited""#)
            }
        }
        XCTAssertEqual(AppSettings.load(from: dir).personality, .boop)
    }

    /// The agents' work earns XP as it happens, which
    /// reaches the popover's status and is kept in boop.sqlite; the next
    /// launch's read-back doesn't count it again.
    func testWorkEarnsXPThatOutlivesTheApp() throws {
        let transport = FakeTransport()
        var runtime: Runtime? = try makeRuntime(transport)
        let options = runtime!.options
        var statuses: [Runtime.Status] = []  // on `home`
        runtime!.onChange = { statuses.append($0) }
        try runtime!.start()
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("PostToolUse", tool: "Bash"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("XP for a tool and a turn") { runtime!.home.sync { statuses.last?.growth?.xp == 6 } }
        XCTAssertEqual(runtime!.home.sync { statuses.last?.growth?.stage }, 1)
        runtime!.stop()
        runtime!.home.sync {}
        runtime = nil

        let again = try Runtime(options)
        var after: [Runtime.Status] = []
        again.onChange = { after.append($0) }
        try again.start()
        defer { again.stop() }
        eventually("a status") { again.home.sync { !after.isEmpty } }
        XCTAssertEqual(again.home.sync { after.last?.growth }, Growth(xp: 6))
    }

    /// Why the link can't look for the device
    /// (Bluetooth off) reaches the popover's status by the next tick, and
    /// leaves it the same way.
    func testTheLinksTroubleReachesTheStatus() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        transport.lock.withLock { transport.why = "Bluetooth is off." }
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(runtime.home.sync { statuses.last?.linkTrouble }, "Bluetooth is off.")
        transport.lock.withLock { transport.why = nil }
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(runtime.home.sync { statuses.last?.linkTrouble })
    }

    /// linkkit/SPEC.md §6: firmware from before the
    /// kit says `status` where Boop's says `hello`, which Boop spots itself.
    /// The popover says to flash it, boop.log says whose firmware it is and
    /// a bug report why it gets no `do`; the device still gets its `state`,
    /// and a reaction fails at once instead of going to it; its taps are
    /// left out.
    func testFirmwareThatDoesntFitIsThePopoversTrouble() throws {
        let transport = FakeTransport()
        let status = #"{"t":"status","v":1,"id":"b00p-7f3a","fw":"0.3.1"}"#
        transport.greeting = status
        let lines = Lines()
        var options = try options(transport)
        options.log = { lines.add($0) }
        let runtime = try Runtime(options)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        transport.onConnection?(true)
        eventually("the trouble") { runtime.home.sync { statuses.last?.deviceTrouble != nil } }
        XCTAssertEqual(runtime.home.sync { statuses.last?.deviceTrouble }, "the device's firmware is too old for this app: flash it")
        XCTAssertNil(runtime.home.sync { statuses.last?.device })
        XCTAssertEqual(runtime.home.sync { statuses.last?.connected }, true)
        runtime.home.sync { _ = runtime.harness.force(["react.mood": "happy"], by: Runtime.forcedBy) }
        XCTAssertEqual(transport.dos, [], "no do")
        XCTAssertEqual(runtime.home.sync { self.recorded().last { $0.actionPhase == .end && $0.actionName == "react" }.map(Self.end) },
                       .failed("the device's firmware doesn't fit this app"))
        transport.onLine?(#"{"t":"ev","kind":"tap","did":"poked"}"#)
        runtime.home.sync {}
        XCTAssertFalse(runtime.home.sync { self.recorded().contains { $0.type == .poke } }, "its taps are left out")
        XCTAssertEqual(Set(transport.types()), ["hello", "state"], "the ask on connect, then only state")
        transport.onLine?(status)
        runtime.home.sync {}
        XCTAssertEqual(lines.all.filter { $0 == "device: b00p-7f3a firmware 0.3.1" }.count, 1, "whose it is, once")
        let saved = Lines()
        runtime.saveReport { saved.add($0?.path ?? "none") }
        eventually("the report") { !saved.all.isEmpty }
        let about = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: saved.all[0])
            .appendingPathComponent("about.json"))) as? [String: Any])
        XCTAssertEqual(about["device_trouble"] as? String, DeviceLink.Trouble.tooOld.description)
        XCTAssertEqual(about["connected"] as? Bool, true)
    }

    /// A device that doesn't see the link drop still counts the app as
    /// there, and says no `hello` unasked (linkkit/device's kit): an app
    /// relaunched within 30 s over USB, the socket's write timeout or
    /// Settings' Reconnect, or a relaunched app taking over the Bluetooth
    /// link macOS kept. The link asks for one on every connect, so the
    /// reactions go out at once, not only after the device's next hello,
    /// up to 60 s later.
    func testAReconnectTheDeviceDidntSeeStillGetsItsHello() throws {
        let transport = FakeTransport()
        transport.seesDrops = false
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        func connection(_ up: Bool) {
            transport.onConnection?(up)
            runtime.home.sync {}
            runtime.home.sync {}
        }
        connection(true)
        XCTAssertNotNil(runtime.home.sync { runtime.link.hello })
        connection(false)
        XCTAssertNil(runtime.home.sync { runtime.link.hello })
        clock.now += 1000
        connection(true)
        XCTAssertEqual(runtime.home.sync { runtime.link.hello?.id }, "b00p-54fe", "asked, and answered")
        let before = transport.dos.count
        runtime.home.sync { _ = runtime.harness.force(["react.mood": "happy"], by: Runtime.forcedBy) }
        XCTAssertEqual(transport.dos.count, before + 1, "the reaction goes out")
        XCTAssertEqual(transport.sent.filter { $0 == Wire.hello }.count, 2, "one ask a connect")
    }

    /// An event that wakes the brain gets a pass;
    /// the answers become a reaction on the device, and the mood action's
    /// change reaches the transcript, the device's state, and the next
    /// pass's MOOD.
    func testAPassMumblesAndChangesTheMood() throws {
        let transport = FakeTransport()
        let lines = DebugLines()
        var options = try options(transport, brain: ScriptedBrain(id: "scripted", always: [
            "mood": Answer(choice: "annoyed", probabilities: ["annoyed": 0.7]),
            "react.mood": Answer(choice: "grumpy", probabilities: ["grumpy": 0.6]),
            "say.about": Answer(choice: "work", probabilities: ["work": 0.5]),
        ]))
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        eventually("the brain") { runtime.home.sync { statuses.last?.brain == "scripted" } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { transport.dos("react").contains { $0.contains(#""args":{"say":"#) } }
        eventually("annoyed") { runtime.home.sync { runtime.moodNow == "annoyed" } }
        eventually("the device hears it") { transport.sent.contains { $0.hasPrefix(#"{"t":"state""#) && $0.contains(#""mood":"annoyed""#) } }
        XCTAssertTrue(runtime.home.sync { runtime.harness.log.events.contains { $0.action == MoodAction.actionName && $0["to"] == "annoyed" } },
                      "the mood is its latest change in the log")
        eventually("the log line") { lines.lock.withLock { lines.log.contains { $0.hasPrefix("brain turn start ") && $0.hasSuffix("→ mood, react") } } }
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        func logged(_ kind: String) -> [Substring] {
            ((try? String(contentsOf: debugLog, encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.hasPrefix("{\"\(kind)\":") }
        }
        func passes() -> [Substring] { logged("pass") }
        eventually("the second pass") { passes().count == 2 }
        // The state's head is logged again only when it changes.
        let heads = logged("head")
        XCTAssertEqual(heads.count, 2)
        XCTAssertTrue(heads[0].contains("Calm. Boop is settled"), "the first pass read calm")
        XCTAssertTrue(heads[1].contains("Annoyed. Boop is mildly put out"), "the next reads the new mood's file")
        XCTAssertTrue(Take.all.contains { $0.meaning == "work" && $0.mood == "grumpy"
                          && passes()[1].contains(#"Boop made a grumpy face, held once, and said \"\#($0.text)\"."#) },
                      "HISTORY shows what the actions did")
        XCTAssertFalse(lines.lock.withLock { lines.log.contains { $0.contains("PERSONALITY") } }, "the state stays out of boop.log")
    }

    /// A bug report, debug mode or not, holds this
    /// launch's debug lines (the passes' states included), the log's end,
    /// the settings, and the status, the mood included, in `about.json`.
    func testABugReportKeepsEverythingOutsideDebugMode() throws {
        let transport = FakeTransport()
        let runtime = try Runtime(options(transport, brain: ScriptedBrain(id: "scripted", always: [
            "react.mood": Answer(choice: "grumpy", probabilities: ["grumpy": 1]),
        ])))
        try Data("an old line\n".utf8).write(to: dir.appendingPathComponent("boop.log"))
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        eventually("the brain") { runtime.home.sync { statuses.last?.brain == "scripted" } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { transport.dos("react").contains { $0.contains(#""args":{"say":"#) } }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(DebugLog.fileName).path),
                       "no debug.jsonl outside debug mode")
        let saved = Lines()
        runtime.saveReport { saved.add($0?.path ?? "none") }
        eventually("the report") { !saved.all.isEmpty }
        let report = URL(fileURLWithPath: saved.all[0])
        XCTAssertEqual(report.deletingLastPathComponent().lastPathComponent, Runtime.reportsDir)
        let lines = try String(contentsOf: report.appendingPathComponent(DebugLog.fileName), encoding: .utf8).split(separator: "\n")
        XCTAssertTrue(lines[0].hasPrefix(#"{"questions":"#), "the questions first")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"head":"#) && $0.contains("PERSONALITY") }, "the state's head")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"pass":"#) && $0.contains("HISTORY (") }, "a pass with the rest of its state")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"sent":"#) }, "the lines sent to the device")
        XCTAssertTrue(lines.contains { $0.hasPrefix(#"{"status":"#) }, "the status")
        try XCTAssertEqual(String(contentsOf: report.appendingPathComponent("boop.log"), encoding: .utf8), "an old line\n")
        let about = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: report.appendingPathComponent("about.json"))) as? [String: Any])
        XCTAssertEqual(about["brain"] as? String, "scripted")
        XCTAssertEqual(about["connected"] as? Bool, true)
    }

    /// Each report gets a new folder even when
    /// the wall clock hasn't advanced. Earlier files remain a consistent
    /// snapshot of the settings and logs saved at that time.
    func testBugReportsInTheSameSecondKeepSeparateFiles() throws {
        var options = try options(nil)
        options.wallClock = { harnessT0 }
        let runtime = try Runtime(options)
        let saved = Lines()
        for volume in [3, 9, 6] {
            var settings = AppSettings()
            settings.volume = volume
            try settings.save(to: dir)
            try Data("volume \(volume)\n".utf8).write(to: dir.appendingPathComponent("boop.log"))
            runtime.saveReport { saved.add($0?.path ?? "none") }
            runtime.home.sync {}
        }
        XCTAssertEqual(Set(saved.all).count, 3)
        for (path, volume) in zip(saved.all, [3, 9, 6]) {
            let report = URL(fileURLWithPath: path)
            XCTAssertEqual(AppSettings.load(from: report).volume, volume)
            try XCTAssertEqual(String(contentsOf: report.appendingPathComponent("boop.log"), encoding: .utf8), "volume \(volume)\n")
        }
    }

    /// The report's lines are capped at
    /// `DebugLog.Recent.maxBytes`, the oldest let go first, and kept as
    /// their bytes alone, with at most an eighth more let go but not yet
    /// dropped. The launch's `questions` line and the latest `head` line
    /// let go still start the report.
    func testRecentLinesAreCapped() throws {
        let recent = DebugLog.Recent()
        XCTAssertEqual(DebugLog.Recent.maxBytes, 8 << 20)
        recent.add(#"{"questions":[],"received_at_ms":1}"#)
        recent.add(DebugLog.head("old", at: 2))
        recent.add(DebugLog.head("new", at: 3))
        for n in 0..<(DebugLog.Recent.maxBytes / 1024 + 5000) { recent.add(String(format: "%07d", n) + String(repeating: "x", count: 1016)) }
        recent.add("last")
        let lines = recent.bytes.split(separator: 0x0A)
        XCTAssertEqual(lines.last.map { String(decoding: $0, as: UTF8.self) }, "last")
        XCTAssertLessThanOrEqual(recent.bytes.count, DebugLog.Recent.maxBytes)
        XCTAssertGreaterThan(lines.count, DebugLog.Recent.maxBytes / 1024 - 2)
        XCTAssertEqual(String(decoding: lines[1].prefix(7), as: UTF8.self), String(format: "%07d", Int(String(decoding: lines[0].prefix(7), as: UTF8.self))! + 1),
                       "whole lines, in order")
        XCTAssertLessThanOrEqual(recent.text.count, DebugLog.Recent.maxBytes / 8 * 9 + 1024)
        XCTAssertLessThanOrEqual(recent.text.capacity, DebugLog.Recent.maxBytes / 8 * 9 + (32 << 10), "its room was never grown")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("recent.jsonl")
        try Runtime.write(recent.pieces, to: url)
        let written = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(Array(written.prefix(2)), [#"{"questions":[],"received_at_ms":1}"#, #"{"head":"new","received_at_ms":3}"#])
        XCTAssertEqual(written.count, lines.count + 2)
    }

    /// Debug mode logs every hook with what it became
    /// and every line to the device, starts debug.jsonl afresh with every
    /// entry (keeping the last launch's as debug.1.jsonl), and prints them
    /// readably, but Jev's state stays out of boop.log.
    func testDebugModePrintsEverythingAndStartsItsLogAfresh() throws {
        let lines = DebugLines()
        var options = try options(FakeTransport())
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        try Data("{\"seq\":1}\n".utf8).write(to: debugLog)
        func file() -> Int? { (try? FileManager.default.attributesOfItem(atPath: debugLog.path))?[.systemFileNumber] as? Int }
        let lastLaunch = try XCTUnwrap(file())
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        options.debugPrint = { line in lines.lock.withLock { lines.printed.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        let fresh = try String(contentsOf: debugLog, encoding: .utf8)
        XCTAssertTrue(fresh.hasPrefix(#"{"questions":"#) && !fresh.contains(#"{"seq":1}"#),
                      "each launch starts afresh, with the questions first")
        XCTAssertEqual(file(), lastLaunch, "in place, so a boopdev watch on it sees it start again")
        try XCTAssertEqual(String(contentsOf: DebugLog.kept(1, of: debugLog), encoding: .utf8), "{\"seq\":1}\n",
                       "the last launch's lines are kept as debug.1.jsonl")

        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        XCTAssertTrue(HookSocket.send(hook("PreToolUse", tool: "Bash"), to: socketPath))
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the pass in debug.jsonl") { self.debugLines().contains { ($0["event"] as? [String: Any])?["kind"] as? String == "did" } }
        let log = lines.lock.withLock { lines.log }
        let printed = lines.lock.withLock { lines.printed }
        XCTAssertTrue(log.contains("hook: claude SessionStart s1 → session start SessionStart claude s1"), "\(log)")
        XCTAssertTrue(log.contains("hook: claude PreToolUse s1 → tool start PreToolUse claude s1 · tool Bash"), "\(log)")
        XCTAssertTrue(log.contains { $0.hasPrefix("link rules → ") })
        XCTAssertFalse(log.contains { $0.contains("How to read HISTORY") }, "the state stays out of boop.log")
        XCTAssertTrue(printed.contains { $0.hasPrefix("▸ ") && $0.contains(" turn start: claude started turn 1") }, "\(printed)")
        let pass = try XCTUnwrap(printed.first { $0.hasPrefix("  pass scripted") })
        XCTAssertTrue(pass.contains("react.mood excited 1.00"), pass)
        XCTAssertTrue(pass.contains("    │ You are the mind of Boop"), "the first state in full")
        let started = try XCTUnwrap(printed.first { $0.hasPrefix("  … react: Boop made an excited face, held once, and said \"") }, "\(printed)")
        let word = String(started.dropFirst("  … react: Boop made an excited face, held once, and said \"".count).dropLast(2))
        XCTAssertTrue(Take.all.contains { $0.text == word && $0.meaning == "start" && $0.mood == "excited" }, "a start take: \(word)")
        XCTAssertTrue(printed.contains { $0.hasPrefix("  ✗ react (") && $0.hasSuffix(") didn't happen: no device connected") },
                      "the fake device never connected: \(printed)")
        let p = try XCTUnwrap(debugLines().compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue((p["state"] as? String)?.hasPrefix("HISTORY (") == true)
        XCTAssertTrue((debugLines().first { $0["head"] != nil }?["head"] as? String)?.hasPrefix("You are the mind of Boop") == true)
        XCTAssertEqual(p["questions"] as? [String], ["mood", "react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])

        // A bug report in debug mode copies the file's lines: none are kept
        // in memory beside it.
        XCTAssertTrue(runtime.home.sync { runtime.recent.bytes.isEmpty })
        let saved = Lines()
        runtime.saveReport { saved.add($0?.path ?? "none") }
        eventually("the report") { !saved.all.isEmpty }
        let copied = try String(contentsOf: URL(fileURLWithPath: saved.all[0]).appendingPathComponent(DebugLog.fileName), encoding: .utf8)
        XCTAssertTrue(copied.hasPrefix(#"{"questions":"#) && copied.contains(#""pass":"#), copied)
        let whole = try String(contentsOf: debugLog, encoding: .utf8)
        XCTAssertTrue(whole.hasPrefix(copied))
        let short = dir.appendingPathComponent("lines.jsonl")
        try Data("one\ntwo\nthree\n".utf8).write(to: short)
        XCTAssertEqual(Runtime.end(of: short, bytes: 8), Data("three\n".utf8), "the end of a longer file starts at a line")
        XCTAssertEqual(Runtime.end(of: short, bytes: 14), Data("one\ntwo\nthree\n".utf8))
        XCTAssertNil(Runtime.end(of: dir.appendingPathComponent("none"), bytes: 8))
        // A longer launch's report starts with its questions line and the
        // head in force where its lines start, as `recent`'s does.
        let big = dir.appendingPathComponent("big.jsonl")
        let questions = #"{"questions":[],"received_at_ms":1}"# + "\n", head = DebugLog.head("new", at: 3) + "\n"
        try Data((questions + DebugLog.head("old", at: 2) + "\n" + head
                  + String(repeating: String(repeating: "x", count: 1023) + "\n", count: DebugLog.Recent.maxBytes / 1024 + 10)).utf8).write(to: big)
        let pieces = Runtime.debugLines(big)
        XCTAssertEqual(pieces.map { String(decoding: $0.prefix(40), as: UTF8.self) }, [questions, head, String(repeating: "x", count: 40)])
        XCTAssertEqual(pieces[2].count, DebugLog.Recent.maxBytes / 1024 * 1024)
        XCTAssertEqual(Runtime.debugLines(short).count, 1, "all of a short file, as it is")
    }

    /// The questions line is debug.jsonl's first
    /// even when the launch ends a reaction the last one left in progress,
    /// so `boopctl day` doesn't count those ends as a launch of their own.
    func testTheQuestionsComeFirstWhenALaunchEndsWhatTheLastLeftOpen() throws {
        var options = try options(FakeTransport())
        options.debug = true
        let now = options.clock()
        let last = Pipeline(core: Core(config: .init()), view: TranscriptView(),
                            transcript: Transcript.log(folder: dir.appendingPathComponent(Transcript.folderName)))
        let line = HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack", ts: now - 1000)
        let prompt = try XCTUnwrap(last.agent(XCTUnwrap(Adapter.event(from: line, receivedAt: now - 1000))).recorded.first)
        last.record(Event.action(ts: now - 900, phase: .start, name: "react",
                          data: ["for": .int(Int64(prompt.seq)), "by": "brain", "ok": true, "message": "Boop smiled."]))
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        let lines = debugLines()
        XCTAssertNotNil(lines.first?["questions"], "\(lines.first ?? [:])")
        let end = try XCTUnwrap(lines.compactMap { ($0["event"] as? [String: Any]).flatMap(Event.init(json:)) }.first)
        XCTAssertEqual(end.data["why"], .string(Harness.restarted))
    }

    /// Transcript files older than 14 days go at
    /// each new day, not only at launch, for an app left running for weeks.
    /// The day the app opened isn't a new day: its launch pruned already.
    func testANewDayDeletesTranscriptFilesPastFourteenDays() throws {
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        let runtime = try Runtime(options)
        let folder = dir.appendingPathComponent(Transcript.folderName)
        let time = LocalTime()
        func file(_ daysAgo: Int64) -> URL { folder.appendingPathComponent(time.day(clock.now - daysAgo * 86_400_000) + ".jsonl") }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        func hook() {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack", ts: clock.now),
                             received: clock.now)
            }
        }
        let old = file(14), kept = file(12)
        try Data("{}\n".utf8).write(to: old)
        try Data("{}\n".utf8).write(to: kept)
        XCTAssertEqual(Transcript.keptDays, 14)
        hook()
        XCTAssertTrue(exists(old), "the day the app opened isn't a new day")
        clock.now += 86_400_000
        hook()
        XCTAssertFalse(exists(old), "past 14 days, today included")
        XCTAssertTrue(exists(kept))
    }

    /// The 10 s keepalive's `state`, the same as the
    /// last one sent, is in debug.jsonl (the dashboard's sign that the app
    /// is running) but not in boop.log, which names each change once.
    func testTheKeepaliveStaysOutOfBoopLog() throws {
        let lines = DebugLines()
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.debug = true
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        func states() -> (sent: Int, logged: Int) {
            (debugLines().filter { ($0["sent"] as? [String: Any])?["t"] as? String == "state" }.count,
             lines.lock.withLock { lines.log.filter { $0.hasPrefix(#"link rules → {"t":"state""#) }.count })
        }
        eventually("the first state") { runtime.home.sync { states().sent == 1 } }
        for _ in 0..<2 {
            clock.now += DeviceLink.keepaliveMs
            runtime.home.sync { runtime.tick() }
        }
        XCTAssertEqual(runtime.home.sync { states().sent }, 3)
        XCTAssertEqual(runtime.home.sync { states().logged }, 1)
    }

    /// Each launch keeps the last one's lines as
    /// debug.1.jsonl and moves the older ones up, keeping 10 launches in
    /// all; an empty file (a launch that wrote nothing) isn't kept.
    func testDebugModeKeepsTheLastTenLaunches() throws {
        let debugLog = dir.appendingPathComponent(DebugLog.fileName)
        XCTAssertEqual(DebugLog.keptLaunches, 10)
        XCTAssertEqual(DebugLog.kept(3, of: debugLog).lastPathComponent, "debug.3.jsonl")
        func text(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for launch in 1...12 {
            try Data("launch \(launch)\n".utf8).write(to: debugLog)
            DebugLog.start(debugLog)
            XCTAssertEqual(text(debugLog), "", "launch \(launch) starts afresh")
        }
        for n in 1...10 { XCTAssertEqual(text(DebugLog.kept(n, of: debugLog)), "launch \(13 - n)\n", "debug.\(n).jsonl") }
        XCTAssertNil(text(DebugLog.kept(11, of: debugLog)), "the oldest is let go")
        DebugLog.start(debugLog)
        XCTAssertEqual(text(DebugLog.kept(1, of: debugLog)), "launch 12\n", "an empty file isn't kept")
    }

    /// The lines of this runtime's debug.jsonl, as JSON objects.
    func debugLines() -> [[String: Any]] {
        let text = (try? String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
    }

    /// Every line `runtime`'s link sends from now on, with no transport
    /// too, beside the runtime's own `onSend`.
    func collectSent(_ runtime: Runtime) -> Lines {
        let lines = Lines()
        let emit = runtime.link.onSend
        runtime.link.onSend = { lines.add($0); emit?($0, $1) }
        return lines
    }

    /// Every event this runtime's transcript recorded, from its files: it
    /// keeps none in memory.
    func recorded() -> [Event] {
        let folder = dir.appendingPathComponent(Transcript.folderName)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted().flatMap { name in
            ((try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? "")
                .split(separator: "\n").compactMap { Event(jsonLine: $0) }
        }
    }

    /// The actions this runtime's debug.jsonl recorded, as events.
    func debugActions() -> [Event] {
        debugLines().compactMap { ($0["event"] as? [String: Any]).flatMap(Event.init(json:)) }.filter { $0.isAction }
    }

    var socketPath: String { dir.appendingPathComponent("boop.sock").path }

    func dev(_ json: String) {
        XCTAssertTrue(HookSocket.send(Data((json + "\n").utf8), to: socketPath))
    }

    /// A tap on the board while something needs you
    /// opens the waiting thread on the Mac, in its app; a click on a
    /// session in the popover opens that one. `{"dev":"tap"}` stands in for
    /// the board.
    func testATapOrAClickOpensTheThread() throws {
        let transport = FakeTransport()
        let runtime = try makeRuntime(transport)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        var ask = HookLine(agent: "claude", hook: "PermissionRequest", session: "s1", cwd: "/tmp/jetpack", tool: "Bash",
                           app: HostApp.claude, appSession: "local_7db5", ts: 1)
        XCTAssertTrue(HookSocket.send(ask.encoded(), to: socketPath))
        ask.agent = "codex"
        ask.session = "01a0e6fd-587d"
        ask.app = nil
        ask.appSession = nil
        XCTAssertTrue(HookSocket.send(ask.encoded(), to: socketPath))
        eventually("needs you") { runtime.home.sync { runtime.core.needsYouShowing } }
        transport.onLine?(#"{"t":"ev","kind":"tap","did":"poked"}"#)
        eventually("the oldest opened") { opened.all == ["claude://code/continue?session=local_7db5"] }
        dev(#"{"dev":"tap"}"#)
        eventually("the dev line taps too") { opened.all.count == 2 }
        let codex = try XCTUnwrap(runtime.home.sync { runtime.core.sessionList(at: runtime.options.clock()) }
            .first { $0.agent == "codex" }?.thread)
        runtime.openThread(codex)
        eventually("a click opens its own") { opened.all.last == "codex://threads/01a0e6fd-587d" }
    }

    /// Debug mode also writes the
    /// dashboard's lines, with no `seq`: every action's questions first at
    /// launch, and again only when they change (not here: the scripted
    /// brain keeps the mood, whose options would change with it), every
    /// line sent to the device verbatim with who sent it (`brain` for the
    /// brain's reactions, `rule` for the rest), and a status line whenever
    /// the mood, personality, brain, sessions or connection change.
    func testDebugModeWritesTheDashboardsLines() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        options.debug = true
        let runtime = try Runtime(options)
        let sentLines = collectSent(runtime)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("a mumble") { runtime.home.sync { sentLines.all.contains { $0.contains(#""say":"#) } } }
        runtime.home.sync {}

        let text = try String(contentsOf: dir.appendingPathComponent(DebugLog.fileName), encoding: .utf8)
        let raw = text.split(separator: "\n").map(String.init)
        let lines = debugLines()
        let questions = try XCTUnwrap(lines.first?["questions"] as? [[String: Any]], "the questions come first")
        XCTAssertEqual(lines.filter { $0["questions"] != nil }.count, 1, "once: nothing changed them")
        XCTAssertEqual((questions[0]["options"] as? [[String: Any]])?.compactMap { $0["name"] as? String },
                       ["calm"] + MoodGraph.neighbours(of: "calm"), "staying calm, then calm's moves")
        XCTAssertEqual(questions.map { $0["key"] as? String }, ["mood", "react.mood", "react.animation", "react.loops", "say.feeling", "say.about", "say.kind"])
        XCTAssertEqual(questions.map { $0["action"] as? String }, ["mood", "react", "react", "react", "react", "react", "react"])
        XCTAssertEqual(questions[1]["text"] as? String, "How should Boop react to NOW, if at all? It makes this mood's face for a moment, and may say something.")
        let none = try XCTUnwrap((questions[1]["options"] as? [[String: Any]])?.first)
        XCTAssertEqual(none["name"] as? String, "none")
        XCTAssertEqual(none["what"] as? String, "Stay quiet: nothing in NOW is worth a face, "
                       + "or HISTORY shows Boop still making the one it calls for (in progress).")
        XCTAssertEqual(none["not_for"] as? String, "Anything PERSONALITY's Examples react to that Boop isn't already doing.")
        XCTAssertTrue((questions[0]["options"] as? [[String: Any]])?.first?["not_for"] is NSNull)

        // Sent: every line the link sent, verbatim and in order, and by whom.
        let sentBy = raw.filter { $0.hasPrefix(#"{"sent":"#) }.map { line in
            let by = line.range(of: #",\"by\":\"(brain|rule)\",\"received_at_ms\":\d+\}$"#, options: .regularExpression)
            return (line: String(line[line.index(line.startIndex, offsetBy: #"{"sent":"#.count)..<(by?.lowerBound ?? line.endIndex)]),
                    by: by.map { String(line[$0]).contains(#""brain""#) ? "brain" : "rule" })
        }
        let sent = sentBy.map(\.line)
        XCTAssertEqual(sent, runtime.home.sync { sentLines.all })
        XCTAssertTrue(sent.contains { $0.hasPrefix(#"{"t":"state""#) } && sent.contains { $0.hasPrefix(#"{"t":"do""#) })
        // The scripted brain's reactions carry a mood; the rules' lines don't.
        for (line, by) in sentBy {
            XCTAssertEqual(by, line.hasPrefix(#"{"t":"do""#) && line.contains(#""mood":"#) ? "brain" : "rule", line)
        }
        XCTAssertTrue(sentBy.contains { $0.by == "brain" }, "the brain's reaction")

        // Status: only the facts the device lines don't carry, and only changes.
        let statuses = lines.compactMap { $0["status"] as? [String: Any] }
        XCTAssertFalse(statuses.isEmpty)
        XCTAssertEqual(Set(statuses[0].keys), ["personality", "brain", "sessions", "connected", "stage"], "a state carries the mood")
        XCTAssertEqual(statuses.last?["brain"] as? String, "scripted")
        XCTAssertEqual(statuses.last?["connected"] as? Bool, true)
        let sessions = try XCTUnwrap(statuses.last?["sessions"] as? [[String: String]])
        XCTAssertEqual(sessions, [["agent": "claude", "project": "jetpack", "status": "working"]])
        for (a, b) in zip(statuses, statuses.dropFirst()) { XCTAssertFalse(NSDictionary(dictionary: a).isEqual(to: b), "only changes") }
        for line in lines where line["seq"] == nil {
            let extra: Set<String> = line["sent"] != nil ? ["received_at_ms", "by"] : ["received_at_ms"]
            XCTAssertEqual(Set(line.keys).subtracting(extra).count, 1, "one kind, and no seq: \(line)")
            XCTAssertNotNil(line["received_at_ms"] as? Int64)
        }
    }

    /// The `state` message carries no idle count, so a second idle
    /// session sends the device nothing; debug.jsonl's `status`, which the
    /// dashboard counts idle sessions from, and the popover still hear of it.
    func testASecondIdleSessionReachesTheStatusNotTheDevice() throws {
        var options = try options(nil)
        options.debug = true
        let runtime = try Runtime(options)
        let sentLines = collectSent(runtime)
        try runtime.start()
        defer { runtime.stop() }
        func sessions() -> [[String: String]] {
            debugLines().compactMap { $0["status"] as? [String: Any] }.last?["sessions"] as? [[String: String]] ?? []
        }
        XCTAssertTrue(HookSocket.send(hook("SessionStart"), to: socketPath))
        eventually("the first session") { sessions().count == 1 }
        func states(_ lines: [String]) -> [String] { lines.filter { $0.hasPrefix(#"{"t":"state""#) } }
        let sent = runtime.home.sync { sentLines.all }
        XCTAssertTrue(states(sent).last?.contains(#""base":"idle""#) == true, "\(sent)")
        let second = HookLine(agent: "claude", hook: "SessionStart", session: "s2", cwd: "/tmp/notes",
                              ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded()
        XCTAssertTrue(HookSocket.send(second, to: socketPath))
        eventually("the second session") { sessions().count == 2 }
        XCTAssertEqual(sessions().map { $0["status"] }, ["idle", "idle"])
        XCTAssertEqual(states(runtime.home.sync { sentLines.all }), states(sent), "no new state")
    }

    /// The dashboard's dev lines. A forced pass needs no
    /// brain and reacts as Jev's would; a forced mood changes as Jev's
    /// does, device included; each is recorded for no event, by the
    /// dashboard.
    func testTheDashboardsDevLines() throws {
        let transport = FakeTransport()
        var options = try options(transport, readJevKey: { _ in nil })
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        eventually("no brain") { runtime.home.sync { runtime.jevKey != nil } }
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))

        dev(#"{"dev":"answer","answers":{"react.mood":"grumpy","say.about":"work"}}"#)
        eventually("a take with no brain") { transport.dos("react").contains { $0.contains(#""args":{"say":{"take":"#) && $0.contains(#""mood":"grumpy""#) } }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        eventually("grumpy") { runtime.home.sync { runtime.moodNow == "grumpy" } }
        dev(#"{"dev":"mood","mood":"happy"}"#)
        eventually("happy, off the graph") { runtime.home.sync { runtime.moodNow == "happy" } }
        dev(#"{"dev":"answer","answers":{"mood":"excited"}}"#)
        eventually("excited, a move from happy") { runtime.home.sync { runtime.moodNow == "excited" } }

        let lines = debugLines()
        let pass = try XCTUnwrap(lines.compactMap { $0["pass"] as? [String: Any] }.first)
        XCTAssertTrue(pass["for"] is NSNull)
        XCTAssertEqual(pass["by"] as? String, "dashboard")
        XCTAssertEqual(pass["questions"] as? [String], ["react.mood", "say.about"])
        XCTAssertEqual((pass["answers"] as? [String: [String: Any]])?["react.mood"]?["p"] as? [String: Double], ["grumpy": 1])
        let actions = debugActions().filter { $0.actionPhase != .end && $0["by"] == "dashboard" }
        let worked = try XCTUnwrap(actions.first?["message"]?.string)
        XCTAssertTrue(Take.all.contains { worked == "Boop made a grumpy face, held once, and said \"\($0.text)\"." && $0.meaning == "work"
            && $0.mood == "grumpy" }, worked)
        XCTAssertEqual(actions.dropFirst().map { $0["message"]?.string }, ["Boop's mood changed: calm → grumpy.",
                                                              "Boop's mood changed: grumpy → happy.",
                                                              "Boop's mood changed: happy → excited."])
        XCTAssertEqual(actions.map(\.actionName), ["react", "mood", "mood", "mood"])
        for action in actions { XCTAssertEqual(action["for"], .null) }
        let moods = lines.compactMap { ($0["sent"] as? [String: Any])?["mood"] as? String }
        XCTAssertEqual(moods.reduce(into: [String]()) { if $0.last != $1 { $0.append($1) } }, ["calm", "grumpy", "happy", "excited"],
                       "the device hears each change in a state")
        // One `questions` line, the launch's; a pass whose options differ
        // from it names the ones it asked, such as the mood's moves once it
        // has moved.
        XCTAssertEqual(lines.filter { $0["questions"] is [[String: Any]] }.count, 1, "once a launch")
        let passes = lines.compactMap { $0["pass"] as? [String: Any] }
        XCTAssertNil(passes[0]["options"], "the launch's options, calm's")
        let moved = try XCTUnwrap(passes.last?["options"] as? [String: [String]])
        XCTAssertEqual(moved, ["mood": ["happy"] + MoodGraph.neighbours(of: "happy")])
    }

    /// BOOT held and let go turns the mic on and off; with
    /// no mic (headless) it hears nothing, so `listening` ends at once with
    /// `stop_listening`, if the turn is free. What the mic heard is recorded
    /// and wakes the brain: a reaction is the reply, and a pass that reacts
    /// with none ends `listening` too. The app's button tells the device to
    /// show it at once.
    func testWhatYouSayGetsAReplyOrEndsListening() throws {
        for (brain, replies) in [(ScriptedBrain.pipelineCheck, true), (ScriptedBrain(always: [:]), false)] {
            try? FileManager.default.removeItem(at: dir)
            let transport = FakeTransport()
            var options = try options(transport, brain: brain)
            options.debug = true
            let runtime = try Runtime(options)
            try runtime.start()
            connect(transport, runtime)
            eventually("the brain") { runtime.home.sync { runtime.pipeline.brain } }
            let stop = #","name":"stop_listening","play":"if_free"}"#
            transport.onLine?(#"{"t":"ev","kind":"talk_on","did":"listening"}"#)
            eventually("listening") { runtime.home.sync { runtime.core.listening?.by == .device } }
            transport.onLine?(#"{"t":"ev","kind":"talk_off"}"#)
            eventually("heard nothing") { transport.dos.contains { $0.hasSuffix(stop) } }
            XCTAssertEqual(runtime.home.sync { self.recorded().filter { $0.type == .talk }.count }, 0)

            let before = transport.sent.count
            dev(#"{"dev":"said","words":"are the tests passing?","by":"device"}"#)
            eventually("the pass") { self.debugLines().contains { ($0["pass"] as? [String: Any]) != nil } }
            runtime.home.sync {}
            let after = Array(transport.sent.dropFirst(before)).filter { $0.hasPrefix(#"{"t":"do""#) }
            if replies {
                XCTAssertEqual(after.count, 1, "\(after)")
                XCTAssertTrue(after.first?.contains(#""name":"react","play":"next","ttl":5000,"args":{"say":"#) == true,
                              "the reaction is the reply")
            } else {
                XCTAssertEqual(after.count, 1, "\(after)")
                XCTAssertTrue(after.first?.hasSuffix(stop) == true, "no reply: listening ends")
            }
            let talk = try XCTUnwrap(runtime.home.sync { self.recorded().last { $0.type == .talk } })
            XCTAssertEqual(talk["words"], "are the tests passing?")

            dev(#"{"dev":"listen","on":true}"#)
            eventually("the app's button") { transport.dos.contains { $0.hasSuffix(#","name":"listening","play":"now"}"#) } }
            XCTAssertTrue(runtime.home.sync { runtime.core.listening?.by == .app })
            runtime.stop()
        }
    }

    /// A forced react keeps its own rules, so it's refused
    /// while something needs you, and the refusal is recorded.
    func testAForcedReactStillRefusesWhileSomethingNeedsYou() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        XCTAssertTrue(HookSocket.send(hook("PermissionRequest", tool: "Bash"), to: socketPath))
        eventually("needs you") { transport.sent.contains { $0.contains(#""attn":"#) } }
        dev(#"{"dev":"answer","answers":{"react.mood":"happy"}}"#)
        eventually("the refusal") { self.debugActions().contains { $0["message"] == "something needs you" } }
        let action = try XCTUnwrap(debugActions().last { $0.actionName == "react" })
        XCTAssertEqual(action["ok"], false)
        XCTAssertFalse(transport.sent.contains { $0.contains(#""say":"#) })
    }

    /// Without `--debug` or `--headless` the socket takes no dev lines, so
    /// plain `make run` can't be driven.
    func testDevLinesAreIgnoredWithoutThem() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        options.devLines = false
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        dev(#"{"dev":"mood","mood":"grumpy"}"#)
        dev(#"{"dev":"answer","answers":{"react.mood":"grumpy","react.animation":"success"}}"#)
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the hook after them") { transport.sent.contains { $0.contains(#""base":"working""#) } }
        runtime.home.sync {}
        XCTAssertEqual(runtime.home.sync { runtime.moodNow }, "calm")
        XCTAssertFalse(transport.sent.contains { $0.contains("task_complete\"") })
        XCTAssertFalse(runtime.home.sync { runtime.harness.log.events.contains { $0.action == MoodAction.actionName && $0["ok"]?.bool == true } })
    }

    /// While the doctor has armed the app it logs every
    /// hook, and an arm lasts 10 minutes, so one never confirmed doesn't
    /// keep hooks in boop.log for good.
    func testTheDoctorsArmLastsTenMinutes() throws {
        let lines = DebugLines()
        var options = try options(FakeTransport())
        options.log = { line in lines.lock.withLock { lines.log.append(line) } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        let arm = dir.appendingPathComponent(Runtime.doctorArm)
        func logged(_ session: String) -> Bool { lines.lock.withLock { lines.log.contains("hook: claude Stop \(session)") } }
        func send(_ session: String) {
            XCTAssertTrue(HookSocket.send(HookLine(agent: "claude", hook: "Stop", session: session, cwd: "/tmp/jetpack",
                                                   ts: Int64(Date().timeIntervalSince1970 * 1000)).encoded(), to: socketPath))
            runtime.home.sync {}
        }

        try Data("0\n".utf8).write(to: arm)
        send("armed")
        eventually("an armed app logs hooks") { logged("armed") }

        XCTAssertEqual(Runtime.doctorArmSeconds, 600)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-9 * 60 - 50)], ofItemAtPath: arm.path)
        send("nine-fifty")
        eventually("still armed just under 10 minutes") { logged("nine-fifty") }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10 * 60 - 1)], ofItemAtPath: arm.path)
        send("expired")
        send("after")
        eventually("an expired arm is removed") { !FileManager.default.fileExists(atPath: arm.path) }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertFalse(logged("expired"))
        XCTAssertFalse(logged("after"))
    }

    func testStopRemovesTheSocketAndReleasesTheLock() throws {
        let runtime = try makeRuntime(FakeTransport())
        try runtime.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        try XCTAssertThrowsError(try Runtime(runtime.options)) // one app per state directory
        runtime.stop()
        runtime.home.sync {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        XCTAssertFalse(HookSocket.send(hook("Stop"), to: socketPath))
    }

    func testNotSetUpIsAnError() throws {
        let options = Runtime.Options(stateDir: dir, socketPath: socketPath, link: nil, steering: Self.steering)
        try XCTAssertThrowsError(try Runtime(options)) { XCTAssertEqual("\($0)", "\(Runtime.OpenError.notSetUp)") }
    }

    /// characters/boop/steering/ has the guide, a file per mood and the two
    /// personalities. The static parts stay within their budgets, and the
    /// personalities' settings are the ones below.
    func testTheSteeringFitsItsBudgetsAndSettings() throws {
        let files = try XCTUnwrap(FileManager.default.subpaths(atPath: Self.steeringDir.path)).filter { $0.hasSuffix(".md") }.sorted()
        XCTAssertEqual(files, (["guide.md", "guide-v3.md"] + MoodGraphV3.moods.map { "mood/\($0).md" }
                               + MoodGraph.moods.map { "mood-v3/\($0).md" }
                               + ["personality/boop.md", "personality/chatter.md"]).sorted())
        let v3 = try Steering(directory: Self.steeringDir, version: .v3)
        XCTAssertEqual(v3.overBudget(version: .v3), [])
        XCTAssertEqual(Self.steering.overBudget(), [])
        XCTAssertEqual(Self.steering.personality(.boop).rules, Personality.Rules(workBeatMs: 90_000...180_000, toolUses: .notable))
        XCTAssertEqual(Self.steering.personality(.chatter).rules, Personality.Rules(workBeatMs: 30_000...60_000, toolUses: .all))
        XCTAssertFalse(Self.steering.guide.contains("<!--"), "comments are left out")
        XCTAssertTrue(Self.steering.personality(.boop).text.hasPrefix("PERSONALITY\n"))
        XCTAssertTrue(Self.steering.mood("grumpy").hasPrefix("MOOD\nGrumpy."))
    }

    /// Settings from before the personalities and the 2026-09-26 cut still
    /// load, as boop; the keys that went are ignored and aren't written back.
    func testOldSettingsStartAsBoop() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = #"{"mode":"calm","brain":"jev","classifier":"rules","writer":"none","volume":3,"focus":true,"away":true,"awaySince":"2026-09-20","finished":148,"projects":["jetpack"]}"#
        try Data(old.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
        let settings = AppSettings.load(from: dir)
        XCTAssertEqual(settings.personality, .boop)
        XCTAssertEqual(settings.volume, 3)
        try settings.save(to: dir)
        let text = try String(contentsOf: dir.appendingPathComponent(AppSettings.file), encoding: .utf8)
        for key in ["mode", "brain", "classifier", "writer", "focus", "away", "finished", "projects"] {
            XCTAssertFalse(text.contains("\"\(key)\""), key)
        }
    }

    /// Hand-edited volumes obey the same 0–10
    /// range as Settings, including at launch before the slider is used.
    func testSavedVolumesStayWithinTheSettingsRange() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (saved, expected) in [(-1, 0), (0, 0), (6, 6), (10, 10), (11, 10), (Int.max, 10)] {
            try Data("{\"volume\":\(saved)}".utf8).write(to: dir.appendingPathComponent(AppSettings.file))
            XCTAssertEqual(AppSettings.load(from: dir).volume, expected)
        }
    }

    /// The personality is saved; a missing or unknown one
    /// is boop.
    func testSettingsKeepThePersonality() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let cases: [(String, Personality)] = [(#"{"personality":"chatter"}"#, .chatter), (#"{"personality":"loud"}"#, .boop),
                                              (#"{}"#, .boop)]
        for (json, p) in cases {
            try Data(json.utf8).write(to: dir.appendingPathComponent(AppSettings.file))
            XCTAssertEqual(AppSettings.load(from: dir).personality, p, json)
        }
        var saved = AppSettings()
        saved.personality = .chatter
        try saved.save(to: dir)
        XCTAssertEqual(AppSettings.load(from: dir), saved)
    }

    /// A new personality takes effect from the next event,
    /// its rules included, and is saved.
    func testANewPersonalityTakesEffectAtOnce() throws {
        let runtime = try makeRuntime(FakeTransport())
        var statuses: [Runtime.Status] = []  // on `home`
        runtime.onChange = { statuses.append($0) }
        try runtime.start()
        defer { runtime.stop() }
        eventually("started as boop") { runtime.home.sync { statuses.last?.personality == .boop } }
        runtime.setPersonality(.chatter)
        eventually("chatter now") { runtime.home.sync { statuses.last?.personality == .chatter } }
        XCTAssertEqual(runtime.home.sync { runtime.view.rules.toolUses }, .all)
        XCTAssertEqual(AppSettings.load(from: dir).personality, .chatter)
    }

    /// A long turn, finished after `{"dev":"advance"}`: no rule plays its
    /// finish; the brain's reaction does, as one `do` with the finish, its
    /// outcome, its face and what it says. A tap on
    /// it (`data.on`) opens that thread and isn't a poke that wakes the
    /// brain; a tap naming a finish the app didn't send is a poke.
    func testTheBrainJudgesAFinish() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let skew = VirtualClock(0)
        options.clock = { Int64(Date().timeIntervalSince1970 * 1000) + skew.now }
        options.advance = { skew.now += $0 }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)

        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        let prompt = HookLine(agent: "claude", hook: "UserPromptSubmit", session: "s1", cwd: "/tmp/jetpack",
                              app: HostApp.claude, appSession: "local_7db5", ts: Int64(Date().timeIntervalSince1970 * 1000))
        XCTAssertTrue(HookSocket.send(prompt.encoded(), to: socketPath))
        eventually("working") { transport.sent.contains { $0.contains("\"base\":\"working\"") } }
        eventually("the start's reaction") { transport.dos("react").contains { $0.contains("\"say\"") } }
        XCTAssertTrue(transport.dos("task_complete").isEmpty && transport.dos("reply_ready").isEmpty, "a start gets no finish")
        let starting = transport.dos("starting")
        XCTAssertEqual(starting.count, 1, "only the rule's one-shot")
        XCTAssertTrue(starting[0].contains(#","name":"starting","play":"if_free","args":{"variant":"#), starting[0])
        transport.endDos()  // the device says each has played
        eventually("the start's reaction has played") {
            runtime.home.sync { self.recorded().contains { $0.actionPhase == .end && $0.actionName == "react" } }
        }
        XCTAssertTrue(HookSocket.send(Data(#"{"dev":"advance","ms":30000}"#.utf8), to: socketPath))
        eventually("clock moved") { skew.now == 30_000 }
        let before = transport.dos.count
        XCTAssertTrue(HookSocket.send(hook("Stop"), to: socketPath))
        eventually("the brain's finish", timeout: 4) { transport.dos.count >= before + 1 }
        let finish = transport.dos[before]
        XCTAssertTrue(finish.contains(#","name":"task_complete","play":"next","ttl":5000,"args":{"outcome":"success","variant":"#),
                      "one do, a variation for its outcome: \(finish)")
        XCTAssertTrue(finish.contains(#""who":{"agent":"claude","thread":"jetpack"},"say":"#), "names whose turn: \(finish)")
        XCTAssertTrue(finish.hasSuffix(#","mood":"excited","loops":1}}"#), "in its face, held once: \(finish)")
        XCTAssertEqual(transport.dos.count, before + 1, "no rule finish besides")

        let id = FakeTransport.id(finish)
        transport.onLine?(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":\#(id)}}"#)
        eventually("the finished thread opened") { opened.all == ["claude://code/continue?session=local_7db5"] }
        let action = try XCTUnwrap(recorded().last { $0.actionName == Core.openThread })
        XCTAssertEqual(action["message"]?.string, Core.openedFinished)
        let poke = try XCTUnwrap(runtime.home.sync { runtime.pipeline.views.last })
        XCTAssertEqual(poke.type, .poke)
        XCTAssertFalse(poke.wakesBrain, "it doesn't wake the brain")
        transport.onLine?(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":1}}"#)  // a finish the app didn't send: a poke
        eventually("a poke") { recorded().contains { $0.actionName == Core.wiggle } }
        XCTAssertEqual(opened.all.count, 1)
    }

    /// linkkit/SPEC.md §4–5: a reaction is in
    /// progress until the device says how its `do` ended: it goes out at
    /// once with the link's next id, and the device's `ended` for that id
    /// ends it, done, cut short (and by what) or skipped. With no device it
    /// didn't happen, and nothing goes out; nor did one the device never
    /// reported by its ttl plus 60 s, or one waiting when the device
    /// dropped. An `ended` for an id the app isn't waiting on changes
    /// nothing. The device connects, answers and drops through the
    /// transport, as it does in the app.
    func testAReactionEndsWhenTheDeviceSaysSo() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        /// The transport says the device connected or dropped; `home` hears
        /// it, and the hello the device says when the app speaks.
        func connection(_ up: Bool) {
            transport.onConnection?(up)
            runtime.home.sync {}
            runtime.home.sync {}
        }
        /// The device sends a line; `home` hears it.
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        /// A forced reaction: its `action` entry's seq, and the `do` sent
        /// for it, if one was.
        func react() throws -> (seq: Int, id: Int?) {
            try runtime.home.sync {
                let before = transport.dos.count
                XCTAssertEqual(runtime.harness.force(["react.mood": "happy"], by: Runtime.forcedBy).map(\.name), ["react"])
                let seq = try XCTUnwrap(self.recorded().last { $0.isAction && $0.actionName == "react" && $0.actionPhase != .end }?.seq)
                return (seq, transport.dos.count > before ? transport.dos.last.map(FakeTransport.id) : nil)
            }
        }
        func end(of seq: Int) -> Pending.End? {
            runtime.home.sync {
                self.recorded().first { $0.actionPhase == .end && $0["for"] == .int(Int64(seq)) }.map(Self.end)
            }
        }

        let alone = try react()
        XCTAssertEqual(end(of: alone.seq), .failed("no device connected"))
        XCTAssertNil(alone.id, "nothing goes out, and nothing waits")

        clock.now += 10_000
        connection(true)
        let played = try react()
        let id = try XCTUnwrap(played.id)
        XCTAssertTrue(transport.dos.last!.hasSuffix(#","name":"react","play":"next","ttl":5000,"args":{"say":{},"mood":"happy","loops":1}}"#),
                      transport.dos.last!)
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: played.seq), "the device hasn't said")
        device(FakeTransport.ended(id, "done"))
        XCTAssertEqual(end(of: played.seq), .done)

        let tapped = try react()
        let tappedId = try XCTUnwrap(tapped.id)
        XCTAssertEqual(tappedId, id == Wire.maxId ? 1 : id + 1, "this launch's ids count up")
        device(FakeTransport.ended(tappedId == 1 ? 2 : tappedId - 1, "done"))
        XCTAssertNil(end(of: tapped.seq), "another id: ignored")
        device(FakeTransport.ended(tappedId, "cut", "tap"))
        XCTAssertNil(end(of: tapped.seq), "your tap cut it: in progress while the pokes go on")
        device(FakeTransport.ended(tappedId, "done"))
        XCTAssertNil(end(of: tapped.seq), "only the first end counts")
        runtime.home.sync {  // anything but another poke, and nothing that wakes the brain
            runtime.run(runtime.pipeline.presence(Event(ts: clock.now, source: .mac, type: .presence, phase: .start,
                                                        specificType: "locked", data: ["since": .int(clock.now)])))
        }
        XCTAssertEqual(end(of: tapped.seq), .done, "you saw it begin: done once something else happens")

        let skipped = try react()
        device(FakeTransport.ended(try XCTUnwrap(skipped.id), "skipped"))
        XCTAssertEqual(end(of: skipped.seq), .failed("something needed you"))

        let silent = try react()
        let giveUp = clock.now + Int64(BoopDevice.reactionTTL) + DeviceLink.answerGraceMs
        clock.now = giveUp - 1
        runtime.home.sync { runtime.tick() }
        XCTAssertNil(end(of: silent.seq), "still waiting")
        clock.now = giveUp
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(end(of: silent.seq), .failed("the device never said it ended"))
        device(FakeTransport.ended(try XCTUnwrap(silent.id), "done"))
        XCTAssertEqual(end(of: silent.seq), .failed("the device never said it ended"), "too late: ignored")

        let dropped = try react()
        XCTAssertNil(end(of: dropped.seq), "waiting")
        connection(false)
        XCTAssertEqual(end(of: dropped.seq), .failed("the device disconnected"))
    }

    /// How each `ended`, and each
    /// way the link fails a `do`, reads in HISTORY; a cut by your tap is
    /// held until the pokes stop.
    func testWhatTheDevicesEndedMeans() {
        let end = { (how: Ended.How, why: String?) in Reactions.end(.ended(Ended(id: 1, how: how, why: why))) }
        XCTAssertEqual(end(.done, nil), .done)
        XCTAssertNil(end(.cut, "tap"), "held")
        XCTAssertEqual(end(.cut, "now"), .failed("cut short: something newer played"))
        XCTAssertEqual(end(.cut, "needs_you"), .failed("cut short: something needed you"))
        XCTAssertEqual(end(.cut, "reset"), .failed("cut short"))
        XCTAssertEqual(end(.cut, nil), .failed("cut short"))
        XCTAssertEqual(end(.skipped, "late"), .failed("waited too long"))
        XCTAssertEqual(end(.skipped, "mic_on"), .failed("the mic went on"))
        for why in ["listening", "no_app", "not_listening", "nothing"] {
            XCTAssertEqual(end(.skipped, why), .failed("something needed you"), why)
        }
        XCTAssertEqual(end(.skipped, "needs_you"), .failed("something needed you"))
        XCTAssertEqual(end(.skipped, nil), .failed("something needed you"))
        XCTAssertEqual(end(.skipped, "busy"), .failed("skipped: busy"))
        XCTAssertEqual(Reactions.end(.failed(.disconnected)), .failed("the device disconnected"))
        XCTAssertEqual(Reactions.end(.failed(.notConnected)), .failed("no device connected"))
        XCTAssertEqual(Reactions.end(.failed(.noAnswer)), .failed("the device never said it ended"))
        XCTAssertEqual(Reactions.end(.failed(.noHello)), .failed("the device hasn't said hello"))
        XCTAssertEqual(Reactions.end(.failed(.incompatible)), .failed("the device's firmware doesn't fit this app"))
        XCTAssertEqual(Reactions.end(.failed(.unknownName)), .failed("the device doesn't play that"))
        XCTAssertEqual(Reactions.end(.failed(.tooLong)), .failed("the line is too long"))
        XCTAssertEqual(BoopDevice.reactionTTL, 5000, "a reaction waits 5 s for its turn")
    }

    /// Where a tap on the brain's finish opens its
    /// thread is kept until the device says the finish ended, or the link
    /// would have given up on it (its ttl plus 60 s); a reaction your tap
    /// cut is held until the pokes stop.
    func testReactionsKeepWhereATapOpens() {
        let reactions = Reactions()
        let thread = ThreadRef(agent: "claude", session: "s1")
        reactions.sent(7, opens: thread, ttl: 5000, now: 1000)
        reactions.sent(8, opens: thread, ttl: 5000, now: 1000)
        XCTAssertEqual(reactions.opens(finish: 7), thread)
        XCTAssertNil(reactions.opens(finish: 9))
        reactions.ended(7)
        XCTAssertNil(reactions.opens(finish: 7), "over")
        reactions.tick(now: 1000 + 5000 + DeviceLink.answerGraceMs - 1)
        XCTAssertEqual(reactions.opens(finish: 8), thread)
        reactions.tick(now: 1000 + 5000 + DeviceLink.answerGraceMs)
        XCTAssertNil(reactions.opens(finish: 8), "given up on")

        var ends: [Pending.End] = []
        let cut = Pending()
        cut.bind { ends.append($0) }
        XCTAssertNil(reactions.read(.ended(Ended(id: 8, how: .cut, why: "tap")), cut), "held")
        XCTAssertEqual(reactions.read(.ended(Ended(id: 9, how: .skipped, why: "late")), Pending()), .failed("waited too long"))
        XCTAssertTrue(ends.isEmpty)
        XCTAssertEqual(reactions.cutByTap.count, 1)
        reactions.pokesStopped()
        XCTAssertEqual(ends, [.done])
        XCTAssertTrue(reactions.cutByTap.isEmpty)
    }

    /// linkkit/SPEC.md §5: a
    /// reaction held longest, in the design with the longest loop of any of
    /// the 13 moods and any look, or with the longest line after the latest
    /// voice window and its bubble, ends on the device before the link
    /// gives up on its `ended` (60 s after its turn could come at the
    /// latest), and the link gives up before the harness's ceiling would
    /// end it. The loops are the designs' (`FaceLoops`), so a new design
    /// with a long loop fails here rather than in HISTORY: wounded's 13 s
    /// idle, held four times, is 52 s.
    func testAReactionEndsBeforeTheHarnessCeiling() throws {
        XCTAssertEqual(MoodAction.moods.count, 13)
        let held = Int64(ReactAction.holds.count)
        func longest(_ ms: (String, String, Int) -> Int64) -> Int64 {
            MoodAction.moods.map(\.name).flatMap { mood in
                FaceLoops.states.flatMap { state in (1...FaceLoops.count(mood: mood, state: state)).map { ms(mood, state, $0) } }
            }.max() ?? 0
        }
        let longestLoop = longest { FaceLoops.ms(mood: $0, state: $1, variant: $2) }
        let latestVoice = longest { FaceLoops.voiceMs(mood: $0, state: $1, variant: $2) }
        // A line joins two takes only within `Voice.maxLineMs`; one take
        // plays alone whatever its length.
        let longestLine = max(Int64(Voice.maxLineMs), Int64(Take.all.map(\.ms).max()!))
        // The bubble stays up after the take (firmware `Behaviour::kBubbleReadMs`).
        let behaviour = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../firmware/src/app/behaviour.h").standardizedFileURL, encoding: .utf8)
        let bubbleRead = try XCTUnwrap(behaviour.firstMatch(of: /kBubbleReadMs = (\d+);/).flatMap { Int64($0.1) })
        XCTAssertEqual(bubbleRead, 1200)
        let longestPlay = max(held * longestLoop, latestVoice + longestLine + bubbleRead)
        XCTAssertGreaterThan(longestPlay, 30_000)
        XCTAssertLessThan(longestPlay, DeviceLink.answerGraceMs)
        XCTAssertLessThan(Int64(BoopDevice.reactionTTL) + DeviceLink.answerGraceMs, ReactAction.openForMs)
    }

    /// The Mac bounds a reaction's length
    /// by the designs as the device times them (the ceiling, above). Every
    /// design's loop and voice window in `FaceLoops` is the one
    /// the Pixel pack's faces.h (`kScenes`' `loopMs`, through `kDesigns`)
    /// and sfx.h (`kScore`'s `voiceMs`) give the device, in the same order:
    /// facegen and sfxgen write them from one manifest.
    func testTheMacTimesTheDesignsAsTheDeviceDoes() throws {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../characters/pixel/firmware/include").standardizedFileURL
        func block(_ text: String, _ start: String) -> String {
            let from = text.range(of: start)!.upperBound
            return String(text[from..<text.range(of: "};", range: from..<text.endIndex)!.lowerBound])
        }
        func rows(_ text: String, _ pattern: String) -> [[String]] {
            let re = try! NSRegularExpression(pattern: pattern)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                (1..<m.numberOfRanges).map { String(text[Range(m.range(at: $0), in: text)!]) }
            }
        }
        let faces = try String(contentsOf: assets.appendingPathComponent("faces.h"), encoding: .utf8)
        let loops = rows(block(faces, "static const Scene kScenes["), #"\{\d+, \d+, (\d+), -?\d+, -?\d+, \d+, \d+\}"#)
            .map { Int64($0[0])! }
        let scenes = rows(block(faces, "static const Design kDesigns["), #"\{(\d+), \d+, \d+\}"#).map { Int($0[0])! }
        let sfx = try String(contentsOf: assets.appendingPathComponent("sfx.h"), encoding: .utf8)
        let windows = rows(block(sfx, "static const Score kScore[] = {"), #"\{k\w+, \d+, \w+, \d+, \d+, (\d+)\},\s*// (\S+)"#)
        var n = 0
        for mood in FaceLoops.moods {
            for state in FaceLoops.states {
                for v in 1...FaceLoops.count(mood: mood, state: state) {
                    XCTAssertEqual(FaceLoops.ms(mood: mood, state: state, variant: v), loops[scenes[n]], "\(mood) \(state) \(v)")
                    XCTAssertEqual(windows[n][1], "\(mood).\(state).\(String(format: "%02d", v))")
                    XCTAssertEqual(FaceLoops.voiceMs(mood: mood, state: state, variant: v), Int64(windows[n][0])!,
                                   "\(mood) \(state) \(v)")
                    n += 1
                }
            }
        }
        XCTAssertEqual(n, 795)
        XCTAssertEqual(scenes.count, n)
        XCTAssertEqual(windows.count, n)
    }

    /// The rules' one-shot goes to the device right
    /// after the `state` of the same hook, to play only if the device's
    /// turn is free (`if_free`), and no reaction waits on it: how it ended
    /// is only logged.
    func testARuleOneShotFollowsItsState() throws {
        let transport = FakeTransport()
        let lines = Lines()
        var options = try options(transport, brain: ScriptedBrain(id: "jev-test", always: [:]))
        options.log = { lines.add($0) }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        XCTAssertTrue(HookSocket.send(hook("UserPromptSubmit"), to: socketPath))
        eventually("the start") { !transport.dos("starting").isEmpty }
        let sent = transport.sent
        let start = try XCTUnwrap(sent.firstIndex { $0.contains(#""name":"starting""#) })
        XCTAssertTrue(sent[start - 1].hasPrefix(#"{"t":"state""#) && sent[start - 1].contains(#""base":"working""#),
                      "\(sent)")
        XCTAssertTrue(sent[start].contains(#","name":"starting","play":"if_free","args":{"variant":"#)
                      && sent[start].hasSuffix(#","ctx":"new_task"}}"#), sent[start])
        let id = FakeTransport.id(sent[start])
        transport.endDos("skipped", why: "busy")
        eventually("its end logged") { lines.all.contains("device: do \(id) ended skipped (busy)") }
        XCTAssertFalse(runtime.home.sync { self.recorded().contains { $0.actionPhase == .end } }, "no reaction waited on it")
    }

    /// linkkit/SPEC.md §4: the device decides what
    /// plays when, so the Mac sends each reaction at once, however many are
    /// still playing or waiting there, each to wait its turn for up to 5 s
    /// (`next`), and each ends as the device says. A link that drops fails
    /// every one still waiting for its `ended`, and with no device a
    /// reaction fails at once.
    func testEveryReactionGoesOutAtOnce() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        func react(_ mood: String) {
            runtime.home.sync { _ = runtime.harness.force(["react.mood": mood, "react.loops": "twice"], by: Runtime.forcedBy) }
        }
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        func ends() -> [Pending.End] {
            runtime.home.sync {
                self.recorded().filter { $0.actionPhase == .end && $0.actionName == "react" }.map(Self.end)
            }
        }

        react("proud")
        clock.now += 300
        react("happy")
        react("excited")
        let sent = transport.dos("react")
        XCTAssertEqual(sent.count, 3, "none waits on the Mac")
        XCTAssertTrue(sent.allSatisfy { $0.contains(#""play":"next","ttl":5000,"#) && $0.hasSuffix(#""loops":2}}"#) }, "\(sent)")
        let ids = sent.map(FakeTransport.id)
        device(FakeTransport.ended(ids[0], "done"))
        device(FakeTransport.ended(ids[1], "cut", "tap"))
        XCTAssertEqual(ends(), [.done], "the tap's cut is in progress while the pokes go on")
        react("sad")
        XCTAssertEqual(transport.dos("react").count, 4)

        transport.onConnection?(false)
        runtime.home.sync {}
        XCTAssertEqual(ends(), [.done, .failed("the device disconnected"), .failed("the device disconnected")],
                       "the two it was waiting on didn't happen; the tap's cut waits for the pokes to stop")
        react("happy")
        XCTAssertEqual(ends().last, .failed("no device connected"))
        XCTAssertEqual(transport.dos("react").count, 4, "nothing went out")
    }

    /// linkkit/SPEC.md §5: each tick gives up on a reaction whose `ended`
    /// hasn't come by its ttl plus 60 s, before the harness's ceiling could
    /// end it, however far the clock jumped.
    func testATickGivesUpOnAnEndedThatNeverCame() throws {
        let transport = FakeTransport()
        var options = try options(transport, brain: ScriptedBrain(always: [:]))
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        connect(transport, runtime)
        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        runtime.home.sync { runtime.queue(DeviceMoment(say: .test(ms: 100), mood: "sad"), pending) }
        XCTAssertEqual(transport.dos("react").count, 1)
        clock.now += 70_000  // the clock jumps
        runtime.home.sync { runtime.tick() }
        XCTAssertEqual(ends, [.failed("the device never said it ended")])
    }

    /// A link that drops for a
    /// moment (the USB bridge reconnecting, or a Bluetooth blip) doesn't
    /// stop what the device plays, so a tap on the brain's finish still
    /// playing once the link is back still opens its thread, though HISTORY
    /// already says it didn't happen. Once the device says it ended, a
    /// tap is a poke.
    func testALinkBlipKeepsATapOnTheFinishPlaying() throws {
        let transport = FakeTransport()
        var options = try options(transport)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        func connection(_ up: Bool) {
            transport.onConnection?(up)
            runtime.home.sync {}
            runtime.home.sync {}
        }
        func device(_ line: String) {
            transport.onLine?(line)
            runtime.home.sync {}
        }
        connection(true)
        let thread = ThreadRef(agent: "claude", session: "s1", app: "com.anthropic.claudefordesktop", appSession: "local_7db5")
        var ends: [Pending.End] = []
        let pending = Pending()
        pending.bind { ends.append($0) }
        runtime.home.sync {
            runtime.queue(DeviceMoment(anim: "task_complete", say: .init(takes: []), mood: "proud", variant: 1,
                                       who: .init(agent: "claude", thread: "jetpack", opens: thread), outcome: "success"), pending)
        }
        let id = FakeTransport.id(try XCTUnwrap(transport.dos("task_complete").first))
        clock.now += 600
        connection(false)
        XCTAssertEqual(ends, [.failed("the device disconnected")])
        clock.now += 1000
        connection(true)
        device(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":\#(id)}}"#)
        eventually("the finished thread opened") { opened.all == ["claude://code/continue?session=local_7db5"] }
        device(FakeTransport.ended(id, "done"))
        XCTAssertFalse(runtime.home.sync { self.recorded().contains { $0.actionName == Core.wiggle } })
        device(#"{"t":"ev","kind":"tap","did":"dip","data":{"on":\#(id)}}"#)
        XCTAssertEqual(opened.all.count, 1, "over")
        XCTAssertTrue(runtime.home.sync { self.recorded().contains { $0.actionName == Core.wiggle } }, "a poke")
    }

    /// How an action's `end` event says it went.
    static func end(_ e: Event) -> Pending.End {
        e["outcome"] == "done" ? .done : .failed(e["why"]?.string ?? "")
    }

    /// A turn's length is the time between its
    /// prompt and its end as the transcript has them, the time the Mac
    /// slept included.
    func testATurnsLengthCountsTheTimeTheMacSlept() throws {
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        options.advance = { clock.now += $0 }
        let runtime = try Runtime(options)
        func hook(_ name: String) {
            runtime.home.sync {
                runtime.hook(HookLine(agent: "claude", hook: name, session: "s1", cwd: "/tmp/jetpack", ts: clock.now),
                             received: clock.now)
            }
        }
        func lastLine() -> String? { runtime.home.sync { runtime.pipeline.views.last?.line } }
        hook("UserPromptSubmit")
        clock.now += 60_000
        clock.now += 8 * 3_600_000  // the lid closed overnight
        hook("Stop")
        XCTAssertEqual(lastLine(), #"claude finished turn 1 on "jetpack": done, a very long turn, no tool calls."#)
        hook("UserPromptSubmit")
        clock.now += 30_000
        runtime.home.sync { runtime.dev(Data(#"{"dev":"advance","ms":10800000}"#.utf8)) }
        clock.now += 10_000
        hook("Stop")
        XCTAssertEqual(lastLine(), #"claude finished turn 2 on "jetpack": done, a very long turn, no tool calls."#)
    }

    /// A failing test wakes the brain while the
    /// prompt's pass runs, and waits; a permission request comes before
    /// that pass ends. The waiting pass doesn't start under the amber.
    func testNoWaitingPassStartsWhileSomethingNeedsYou() throws {
        let gate = DispatchSemaphore(value: 0)
        let asked = Lines()
        var options = try options(nil)
        let clock = VirtualClock(harnessT0)
        options.clock = { clock.now }
        let brain = ScriptedBrain { state, _ in
            asked.add(String(state.split(separator: "\n").reversed()[1]))
            gate.wait()
            return [:]
        }
        options.brain = { _ in brain }
        options.debug = true
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }
        func hook(_ name: String, tool: String? = nil, topic: String? = nil, failed: Bool = false) {
            var line = HookLine(agent: "claude", hook: name, session: "s1", cwd: "/tmp/jetpack", tool: tool, ts: clock.now)
            line.topic = topic
            line.toolError = failed ? "exit_code" : nil
            runtime.home.sync { runtime.hook(line, received: clock.now) }
        }
        hook("UserPromptSubmit")
        hook("PreToolUse", tool: "Bash", topic: "tests")
        hook("PostToolUseFailure", tool: "Bash", topic: "tests", failed: true)
        hook("PreToolUse", tool: "Edit")
        hook("PermissionRequest", tool: "Edit")
        gate.signal()
        eventually("the waiting pass is dropped") {
            runtime.home.sync { runtime.harness.idle }
        }
        XCTAssertEqual(asked.all.count, 1, "\(asked.all)")
        let logged = try String(contentsOf: runtime.debugLogURL, encoding: .utf8)
        let held = logged.split(separator: "\n").compactMap { line -> String? in
            let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return (o?["pass"] as? [String: Any])?["held"] as? String
        }
        XCTAssertEqual(held, ["something needs you"], "held back when its turn came, so the brain wasn't asked")
        XCTAssertTrue(logged.contains(#""brain":"scripted","dropped":null,"for":"#) && logged.contains(#""held":"something needs you""#),
                      "with the brain it would have asked, apart from the passes the brain dropped")
    }

    /// `do` ids start somewhere random at every launch and
    /// count up, so an earlier launch's call still on the device can't
    /// share one (linkkit/SPEC.md §3; LinkKit's own tests pin the rest).
    func testDoIdsDifferEachLaunch() {
        let firsts = Set((0..<8).map { _ -> Int in
            let link = BoopDevice.link(FakeTransport())
            link.connection(true, now: 0)
            link.receive(FakeTransport.hello, now: 0)
            return link.do("react", now: 0) { _ in } ?? 0
        })
        XCTAssertGreaterThan(firsts.count, 1, "random")
        XCTAssertTrue(firsts.allSatisfy { (1...Wire.maxId).contains($0) })
    }

    /// A launch numbers its requests from somewhere random,
    /// as the link does its `do`s, so a relaunched app's first request can't
    /// share `attn.id` with the one the device still shows from the last
    /// launch: with the same agent and project, a new request would carry
    /// on the amber with no chirp. The numbers wrap to
    /// 1, never 0, within the device's 32 bits.
    func testRequestNumbersDifferEachLaunch() throws {
        var firsts: Set<Int> = []
        for _ in 0..<4 {
            dir = URL(fileURLWithPath: "/tmp/boop-rt-\(UUID().uuidString.prefix(8))")
            defer { try? FileManager.default.removeItem(at: dir) }
            let runtime = try makeRuntime(FakeTransport())
            firsts.insert(runtime.core.lastAsk)
        }
        XCTAssertGreaterThan(firsts.count, 1, "random")
        XCTAssertTrue(firsts.allSatisfy { (0..<Int(Int32.max)).contains($0) })
        var config = Core.Config()
        config.firstAsk = Int(Int32.max)
        let core = Core(config: config)
        core.handle(Event(ts: 1000, source: .claude, type: .tool, phase: .wait, specificType: "PermissionRequest",
                          session: "s", cwd: "/w/landing", data: ["tool": "Bash", "for": "permission"]))
        XCTAssertEqual(core.snapshot(at: 1000).attn?.id, 1, "back to 1, never 0")
    }

    /// The popover says Jev isn't answering at once for a
    /// status only the person can fix (401, 402, 403), and for anything
    /// else after 3 dropped passes in a row. A pass that runs clears it, a
    /// pass that never asked Jev (one held back) doesn't count, nor does
    /// one that asked the brain before a new key, and a new key starts over.
    func testBrainTroubleShowsAtOnceForTheAccountAndAfterThreeInARowElse() throws {
        XCTAssertEqual(BrainTrouble.showAfter, 3)
        let runtime = try Runtime(options(nil))
        let e = Event(seq: 1, ts: 1, source: .device, type: .poke, specificType: "input")
        func pass(_ status: Int?, asked: Bool = true, current: Bool = true) -> BrainTrouble? {
            let error = status.map { BrainError("jev: HTTP \($0)", status: $0) }
            let p = Harness.Pass(event: e, line: "You poked Boop.", seq: 2, answers: [:], dropped: error?.description, held: nil,
                                 latencyMs: 1, brain: "jev:jev-latest", by: nil, prompt: asked ? "state" : nil, questions: [],
                                 seen: 1, actions: [], error: error, current: current)
            return runtime.home.sync {
                runtime.passed(p)
                return runtime.trouble
            }
        }
        XCTAssertEqual(pass(402), BrainTrouble(kind: .credit, why: "jev: HTTP 402", inARow: 1))
        XCTAssertNil(pass(nil))
        XCTAssertEqual(pass(401)?.kind, .key)
        XCTAssertNil(pass(nil))
        XCTAssertNil(pass(503))
        XCTAssertNil(pass(503))
        XCTAssertEqual(pass(503), BrainTrouble(kind: .failing, why: "jev: HTTP 503", inARow: 3))
        XCTAssertEqual(pass(nil, asked: false)?.inARow, 3, "a pass held back never asked Jev")
        XCTAssertEqual(pass(401, current: false)?.kind, .failing, "one that asked the brain before a new key says nothing")
        runtime.home.sync { runtime.useBrain() }
        XCTAssertNil(runtime.home.sync { runtime.trouble }, "a new key starts over")
    }

    /// HISTORY closes with `mood`'s time in a mood
    /// other than calm, the resting mood, and nothing
    /// else; the harness only places it.
    func testHistoryClosesWithTheMoodsTime() throws {
        let clock = VirtualClock(1_790_000_000_000)
        let pipeline = Pipeline(core: Core(config: .init()), view: TranscriptView(), clock: Harness.Clock(now: { clock.now }))
        let (harness, mood) = Runtime.harness(pipeline: pipeline, steering: Self.steering, personality: { .boop }, queue: { _, _ in })
        func log() -> LogView { harness.log.view(now: clock.now) }
        func closing() -> String? { MoodAction.sinceLine(mood, log(), at: clock.now) }
        func change(_ to: String) { harness.force(mood, by: Runtime.forcedBy) { MoodAction.change(mood, to: to, log: log()) } }
        XCTAssertNil(closing(), "calm says nothing")
        change("grumpy")
        clock.now += 30_000
        XCTAssertEqual(closing(), "Boop has been grumpy for under a minute.")
        clock.now += 2 * 60_000
        XCTAssertEqual(closing(), "Boop has been grumpy for 2 min.", "whole minutes, as HISTORY's")
        let relaunched = Pipeline(core: Core(config: .init()), view: TranscriptView(), transcript: harness.log,
                                  clock: Harness.Clock(now: { clock.now }))
        let (_, again) = Runtime.harness(pipeline: relaunched, steering: Self.steering, personality: { .boop }, queue: { _, _ in })
        XCTAssertEqual(MoodAction.sinceLine(again, log(), at: clock.now), "Boop has been grumpy for 2 min.",
                       "the mood and its time are the log's, so a relaunch keeps both")
        change("happy")
        XCTAssertEqual(closing(), "Boop has been happy for under a minute.", "happy is a mood like any other")
        change("calm")
        XCTAssertNil(closing(), "back to calm")
    }
}

/// What a runtime in debug mode logged and printed. Not nested in a test:
/// the shim's runner generator would take it for the test class.
final class DebugLines: @unchecked Sendable {
    let lock = NSLock()
    var log: [String] = []
    var printed: [String] = []
}

/// Lines gathered from any thread, for tests.
final class Lines: @unchecked Sendable {
    let lock = NSLock()
    var all: [String] { lock.withLock { stored } }
    private var stored: [String] = []
    func add(_ line: String) { lock.withLock { stored.append(line) } }
}

/// Waits up to `timeout` for `condition`, checking every 20 ms, then checks
/// it: how every test waits on another thread.
func eventually(_ what: String, timeout: TimeInterval = 3, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
    XCTAssertTrue(condition(), what)
}
