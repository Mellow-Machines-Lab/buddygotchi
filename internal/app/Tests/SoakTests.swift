import AgentHooks
import Darwin
import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// A soak: two synthetic days of work in the transcript, about 25,000
/// events a day (agents' hooks, MellowHarness's passes, what Boop did and how
/// it ended), a launch that reads the last day back, then more work as the
/// runtime hears it, with a tick every second and a scripted brain. It
/// prints the launch's time, each event's and tick's, and the process's
/// memory. Only with `BOOP_SOAK=1` (`BOOP_SOAK_TURNS` sets how many turns
/// the live part runs, 100 by default): it takes a minute or more.
final class SoakTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = URL(fileURLWithPath: "/tmp/boop-soak-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func testTwoDaysOfEvents() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["BOOP_SOAK"] != nil, "a soak: set BOOP_SOAK=1")
        let liveTurns = env["BOOP_SOAK_TURNS"].flatMap(Int.init) ?? 100
        let time = LocalTime()
        // Two days ending at 18:00 today.
        let end = Int64(Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!.timeIntervalSince1970 * 1000)
        var work = SoakWork(start: end - 2 * 86_400_000)
        let written = try work.write(until: end, to: dir.appendingPathComponent(Transcript.folderName), time: time)

        let clock = SoakClock(end)
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: time.day(end))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in "k" }
        options.brain = { key in key.map { _ in ScriptedBrain.pipelineCheck } }

        let before = Soak.footprintMB()
        var started = ContinuousClock.now
        let runtime = try autoreleasepool { try Runtime(options) }
        let launchMs = Soak.ms(since: started)
        let read = runtime.home.sync { runtime.harness.log.events.count }
        let afterLaunch = Soak.footprintMB()
        runtime.home.sync { runtime.readJevKey() }
        eventually("the brain") { runtime.home.sync { runtime.harness.brain != nil } }

        var events: [Double] = [], ticks: [Double] = []
        var nextTick = end + 1000
        started = ContinuousClock.now
        // `home.sync` runs its block on this thread, whose autorelease pool
        // would otherwise keep what each leaves till the test ends; the app's
        // blocks run async, each in a pool of its own.
        for (line, at) in work.hooks(turns: liveTurns) {
            while nextTick <= at {
                clock.now = nextTick
                let t = ContinuousClock.now
                autoreleasepool { runtime.home.sync { runtime.tick() } }
                ticks.append(Soak.ms(since: t))
                nextTick += 1000
            }
            clock.now = at
            let t = ContinuousClock.now
            autoreleasepool { runtime.home.sync { runtime.hook(line, received: at) } }
            // The pass it started, if any, answered and carried out.
            let deadline = Date().addingTimeInterval(5)
            while !autoreleasepool(invoking: { runtime.home.sync { runtime.harness.idle } }) && Date() < deadline { usleep(20) }
            events.append(Soak.ms(since: t))
        }
        let liveMs = Soak.ms(since: started)
        let afterLive = Soak.footprintMB()
        let passes = runtime.home.sync { runtime.harness.log.view(now: clock.now).count(Event.pass, within: 86_400_000) }
        let inMemory = runtime.home.sync { runtime.harness.log.events.count }

        print("soak: \(written) lines written over two days; launch read back \(read) events in \(Int(launchMs)) ms")
        print("soak: memory \(Soak.mb(before)) before launch, \(Soak.mb(afterLaunch)) after, \(Soak.mb(afterLive)) after the live part")
        print("soak: \(events.count) live events, \(passes) passes in the last day, \(inMemory) events in memory, in \(Int(liveMs)) ms")
        print("soak: per event " + Soak.stats(events))
        print("soak: per tick  " + Soak.stats(ticks))
        XCTAssertGreaterThan(read, 20_000)
        XCTAssertGreaterThan(events.count, 0)
        XCTAssertEqual(runtime.home.sync { runtime.view.refolds }, 0, "the view's fold never started over")
    }
}

/// The soak's clock, which the test moves and `home` reads.
final class SoakClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64
    init(_ now: Int64) { value = now }
    var now: Int64 {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

enum Soak {
    static func ms(since start: ContinuousClock.Instant) -> Double {
        let d = ContinuousClock.now - start
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }

    /// `mean 0.41 ms, p50 0.30, p95 0.90, p99 2.1, max 12.0`.
    static func stats(_ ms: [Double]) -> String {
        guard !ms.isEmpty else { return "none" }
        let sorted = ms.sorted()
        func p(_ q: Double) -> String { String(format: "%.2f", sorted[min(sorted.count - 1, Int(Double(sorted.count) * q))]) }
        let mean = String(format: "%.2f", ms.reduce(0, +) / Double(ms.count))
        return "mean \(mean) ms, p50 \(p(0.5)), p95 \(p(0.95)), p99 \(p(0.99)), max \(p(1)) (n \(ms.count))"
    }

    /// The process's physical footprint, as Activity Monitor's Memory shows it.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    static func mb(_ value: Double) -> String { String(format: "%.0f MB", value) }
}

/// Synthetic work: four Claude sessions in two projects taking turns, each
/// turn a prompt, eight tool calls (every third a test run, failing every
/// fifth time) and a finish, a turn every 77 seconds around the clock.
/// Written to the transcript as the app would have logged it: a pass for
/// each prompt and finish, a mood change every fourth finish, and a
/// reaction to each finish that ends 6 s later.
struct SoakWork {
    static let turnMs: Int64 = 77_000
    var at: Int64
    var turn = 0
    var seq = 0

    init(start: Int64) { at = start }

    /// The hooks of one turn, each with its time.
    func turnHooks(_ n: Int, from start: Int64) -> [(HookLine, Int64)] {
        let session = "soak-\(n % 4)-\(n / 800)"
        let cwd = n % 4 < 2 ? "/tmp/soak/alpha" : "/tmp/soak/beta"
        let step = Self.turnMs / 20
        var out: [(HookLine, Int64)] = []
        var t = start
        func add(_ hook: String, tool: String? = nil, topic: String? = nil, id: String? = nil, message: String? = nil,
                 prompt: String? = nil) {
            out.append((HookLine(agent: "claude", hook: hook, session: session, cwd: cwd, tool: tool, topic: topic,
                                 toolUseID: id, message: message, prompt: prompt, ts: t), t))
            t += step
        }
        add("UserPromptSubmit", prompt: "Please fix the flaky login test and run the whole suite again, turn \(n).")
        for call in 0..<8 {
            let tool = call % 3 == 2 ? "Bash" : call % 2 == 0 ? "Edit" : "Read"
            let topic = tool == "Bash" ? "tests" : nil
            let id = "toolu_\(n)_\(call)"
            add("PreToolUse", tool: tool, topic: topic, id: id)
            add(topic != nil && (n + call) % 5 == 0 ? "PostToolUseFailure" : "PostToolUse", tool: tool, topic: topic, id: id)
        }
        add("Stop", message: "Fixed the login test: the session cookie expired early. The whole suite passes now.")
        return out
    }

    /// The hooks of the next `turns` turns, for the live part.
    mutating func hooks(turns: Int) -> [(HookLine, Int64)] {
        var out: [(HookLine, Int64)] = []
        for _ in 0..<turns {
            out += turnHooks(turn, from: at)
            turn += 1
            at += Self.turnMs
        }
        return out
    }

    static let moods = MoodOutput.moods.map(\.name)

    /// A pass's answers, with a probability for each of many options, as
    /// Jev's carry them.
    static func answers(_ n: Int) -> Answers {
        func spread(_ names: [String], _ pick: String) -> Answer {
            Answer(choice: pick, probabilities: Dictionary(uniqueKeysWithValues: names.map { ($0, $0 == pick ? 0.62 : 0.38 / Double(names.count - 1)) }))
        }
        let animations = ["none", "success", "failure", "wiggle", "nod", "shrug", "gasp", "cheer", "sulk", "yawn", "bounce", "spin"]
        return ["mood": spread(moods, moods[n % moods.count]), "react.mood": spread(moods, "happy"),
                "react.animation": spread(animations, "success"), "react.loops": spread(["once", "twice", "loop"], "once"),
                "say.feeling": spread(["none", "glad", "proud", "sorry", "wow", "hmm", "ugh", "yay"], "none"),
                "say.about": spread((0..<16).map { "topic\($0)" }, "topic3"), "say.kind": spread(["word", "sound", "none"], "word")]
    }

    /// Writes every event from the work's start until `end`, one file a
    /// day; returns how many.
    mutating func write(until end: Int64, to folder: URL, time: LocalTime) throws -> Int {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [String: String] = [:]
        var count = 0
        var mood = "calm"
        func log(_ e: Event) -> Int {
            var e = e
            seq += 1
            e.seq = seq
            files[time.day(e.at), default: ""] += e.jsonLine + "\n"
            count += 1
            return seq
        }
        func writeTurn() {
            for (line, t) in turnHooks(turn, from: at) {
                guard let e = Adapter.event(from: line, receivedAt: t) else { continue }
                let s = log(e)
                guard line.hook == "UserPromptSubmit" || line.hook == "Stop" else { continue }
                _ = log(Event(at: t + 700, source: Event.harness, kind: Event.pass,
                              data: ["for": .int(Int64(s)), "brain": "jev:jev-latest", "answers": Harness.json(Self.answers(turn)),
                                     "dropped": .null, "ms": 700]))
                guard line.hook == "Stop" else { continue }
                if turn % 4 == 0 {
                    let to = mood == "calm" ? "happy" : "calm"
                    _ = log(Event.did("Boop's mood changed: \(mood) → \(to).", for: s, action: MoodOutput.outputName, by: "brain",
                                      facts: ["from": .string(mood), "to": .string(to), "latency_ms": 0], at: t + 700))
                    mood = to
                }
                let d = log(Event.did("Boop cheered with a success animation, saying \"yay\".", for: s, action: ReactOutput.outputName,
                                      by: "brain", open: true, facts: ["latency_ms": 0], at: t + 700))
                _ = log(Event.ended(d, action: ReactOutput.outputName, by: "brain", at: t + 6700))
            }
        }
        while at + Self.turnMs <= end {
            // JSONSerialization's leftovers go at each turn's end, not the test's.
            autoreleasepool { writeTurn() }
            turn += 1
            at += Self.turnMs
        }
        for (day, text) in files {
            try Data(text.utf8).write(to: folder.appendingPathComponent(day + ".jsonl"))
        }
        return count
    }
}
