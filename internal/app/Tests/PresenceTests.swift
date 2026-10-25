import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

private let presenceT0: Int64 = 1_790_000_000_000
private let minute: Int64 = 60_000

/// Here and away: the presence detector decides,
/// the view pairs what it decided, and only coming back wakes the brain.
final class PresenceTests: XCTestCase {

    /// A detector ticked once a second, as the runtime does, with the Mac's
    /// idle time counting up from the last input.
    struct Rig {
        var detector: PresenceDetector
        var now = presenceT0
        var lastInput = presenceT0
        var made: [Event] = []

        init(away: Bool = false) { detector = PresenceDetector(away: away) }

        mutating func wait(_ ms: Int64) {
            let end = now + ms
            while now < end {
                now = min(end, now + 1000)
                if let e = detector.tick(at: now, idleMs: now - lastInput) { made.append(e) }
            }
        }

        /// A key press, seen on the next tick.
        mutating func touch() {
            lastInput = now
            wait(1000)
        }

        mutating func signal(_ s: PresenceDetector.Signal) {
            if let e = detector.signal(s, at: now) { made.append(e) }
        }

        /// What it made, as `start locked` and `end input`.
        var names: [String] { made.map { "\($0.phase?.rawValue ?? "") \($0.specificType)" } }
    }

    /// A lock counts after 10 minutes (`lockAwayMs`), from
    /// when you last touched the Mac; the back comes with your first touch
    /// once it's unlocked, named by the unlock. A shorter lock is nothing:
    /// a minute away, or nine, gets no hello.
    func testALockIsAnAwayOnlyAfterTenMinutes() throws {
        var rig = Rig()
        rig.wait(5000)
        rig.signal(.locked)
        rig.wait(minute)
        rig.signal(.unlocked)
        rig.touch()
        XCTAssertEqual(rig.names, [], "a minute's lock records nothing")
        rig.signal(.locked)
        rig.wait(10 * minute - 1000)
        rig.signal(.unlocked)
        rig.touch()
        XCTAssertEqual(rig.names, [], "nor does one just under 10 minutes")

        rig.wait(3000)
        let lockedAt = rig.now
        rig.signal(.locked)
        rig.wait(10 * minute - 1000)
        XCTAssertEqual(rig.names, [])
        rig.wait(1000)
        XCTAssertEqual(rig.names, ["start locked"])
        let away = try XCTUnwrap(rig.made.first)
        XCTAssertEqual(away.from, .mac)
        XCTAssertEqual(away.type, .presence)
        XCTAssertEqual(away.at, lockedAt + 10 * minute)
        XCTAssertEqual(away["since"]?.int, rig.lastInput, "when you last touched the Mac, not when it was noticed")
        XCTAssertTrue(rig.detector.away)

        rig.wait(minute)
        rig.signal(.unlocked)
        rig.touch()
        XCTAssertEqual(rig.names, ["start locked", "end unlocked"])
        XCTAssertNil(rig.made.last?.data["since"])
        XCTAssertFalse(rig.detector.away)
    }

    /// Idle alone is an away only after 30 minutes
    /// (`idleAwayMs`), starting from the last input; any key or mouse
    /// within 5 s (`backInputMs`) is the back.
    func testIdleIsAnAwayOnlyAfterHalfAnHour() throws {
        var rig = Rig()
        rig.wait(30 * minute - 1000)
        XCTAssertEqual(rig.names, [], "29 minutes of reading is still here")
        rig.wait(1000)
        XCTAssertEqual(rig.names, ["start idle"])
        XCTAssertEqual(rig.made[0]["since"]?.int, presenceT0)

        // Idle for 6 s is not a touch; within 5 s is.
        XCTAssertNil(rig.detector.tick(at: rig.now, idleMs: 6000))
        XCTAssertTrue(rig.detector.away)
        rig.wait(minute)
        rig.touch()
        XCTAssertEqual(rig.names, ["start idle", "end input"])
    }

    /// The Mac doesn't tick while it sleeps, so the wake
    /// makes the away the sleep was, from when it started, and the first
    /// touch the back, named by the wake. A short sleep is nothing.
    func testSleepingThroughIsAnAwayAtTheWake() throws {
        var rig = Rig()
        rig.signal(.asleep)
        rig.now += 9 * minute  // no ticks while asleep
        rig.signal(.woke)
        rig.touch()
        XCTAssertEqual(rig.names, [], "a sleep under 10 minutes is nothing")

        let asleepAt = rig.now
        rig.signal(.asleep)
        rig.now += 2 * 60 * minute
        rig.signal(.woke)
        XCTAssertEqual(rig.names, ["start asleep"])
        XCTAssertEqual(rig.made[0]["since"]?.int, asleepAt)
        rig.touch()
        XCTAssertEqual(rig.names, ["start asleep", "end woke"])

        // The displays sleeping with the app still ticking: an away after
        // 10 minutes, like a lock.
        rig.signal(.asleep)
        rig.wait(10 * minute)
        XCTAssertEqual(rig.names.last, "start asleep")
    }

    /// One away at a time. More signals while away record
    /// nothing, a touch while still locked isn't a back, and a detector
    /// that starts away (the transcript's last `presence` was a start)
    /// records your first touch as the back, never a second away.
    func testOneAwayAtATime() throws {
        var rig = Rig()
        rig.signal(.locked)
        rig.wait(10 * minute)
        rig.signal(.asleep)
        rig.wait(minute)
        rig.touch()
        XCTAssertEqual(rig.names, ["start locked"], "still locked and asleep")
        rig.signal(.woke)
        rig.touch()
        XCTAssertEqual(rig.names, ["start locked"], "still locked")
        rig.signal(.unlocked)
        rig.touch()
        XCTAssertEqual(rig.names, ["start locked", "end unlocked"], "the last to clear names it")

        var launched = Rig(away: true)
        launched.lastInput -= minute
        launched.wait(10_000)
        XCTAssertEqual(launched.names, [], "nobody touched it yet")
        launched.touch()
        XCTAssertEqual(launched.names, ["end input"])
    }

    /// The two events as the transcript keeps them, the
    /// example the spec shows.
    func testThePresenceEventsShape() {
        var detector = PresenceDetector()
        _ = detector.signal(.locked, at: 1_790_000_000_000)
        var away = detector.tick(at: 1_790_000_600_000, idleMs: 600_000)!
        away.seq = 40
        _ = detector.signal(.unlocked, at: 1_790_003_599_000)
        var back = detector.tick(at: 1_790_003_600_000, idleMs: 1000)!
        back.seq = 41
        XCTAssertEqual(away.jsonLine, #"{"seq":40,"at":1790000600000,"source":"mac","kind":"presence_start","data":{"since":1790000000000,"specific_type":"locked"}}"#)
        XCTAssertEqual(back.jsonLine, #"{"seq":41,"at":1790003600000,"source":"mac","kind":"presence_end","data":{"specific_type":"unlocked"}}"#)
        XCTAssertEqual(Event(jsonLine: away.jsonLine), away)
    }

    /// The view keeps both. The away never wakes the
    /// brain; the back does, with the break's band from the away's
    /// `since`, and comes from both events. A back with no away seen makes
    /// no view event, and the core never hears of either.
    func testTheViewPairsAnAwayWithItsBack() throws {
        let rig = CoreRig()
        func away(since: Int64) -> [ViewEvent] {
            events(rig.note(Fx(rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .start,
                                                            specificType: "locked", data: ["since": .int(since)])))))
        }
        func back() -> [ViewEvent] {
            events(rig.note(Fx(rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .end,
                                                            specificType: "unlocked")))))
        }

        XCTAssertEqual(back(), [], "a back with no away")
        let left = rig.now
        rig.now += 30_000
        let a = try XCTUnwrap(away(since: left).first)
        XCTAssertEqual(a.line, "You stepped away from the Mac.")
        XCTAssertEqual(a.name, "presence start")
        XCTAssertFalse(a.wakesBrain)
        XCTAssertEqual(a.facts["why"], "locked")
        XCTAssertTrue(rig.pipeline.away)

        rig.now = left + 3 * 60 * minute
        let b = try XCTUnwrap(back().first)
        XCTAssertEqual(b.line, "You came back to the Mac after a very long break.")
        XCTAssertEqual(b.name, "presence end")
        XCTAssertTrue(b.wakesBrain)
        XCTAssertNil(b.about)
        XCTAssertEqual(b.facts["away"], "very long")
        XCTAssertEqual(b.facts["away_ms"]?.int, 3 * 60 * minute, "from when you left, not from the away's event")
        XCTAssertEqual(b.from, [a.seq, rig.pipeline.transcript.events.last!.seq])
        XCTAssertFalse(rig.pipeline.away)
        XCTAssertEqual(rig.log.filter { if case .record = $0 { false } else { true } }.count, 0, "the core never hears of it")
    }

    /// `Band.away`, short under 15 minutes, long under 2
    /// hours, very long from 2 hours.
    func testTheBreaksBands() {
        XCTAssertEqual(Band.away(ms: 15 * minute - 1), "short")
        XCTAssertEqual(Band.away(ms: 15 * minute), "long")
        XCTAssertEqual(Band.away(ms: 120 * minute - 1), "long")
        XCTAssertEqual(Band.away(ms: 120 * minute), "very long")
        XCTAssertEqual(EventLine.back(ms: 5 * minute), "You came back to the Mac after a short break.")
    }

    /// `hello` is a topic Jev is
    /// offered, every face has four or more of its takes, all greetings,
    /// and a glad sound then hello, as boop's Example asks, is a sound and
    /// a greeting in a happy face.
    func testEveryFaceCanSayHello() throws {
        try requireVoice()
        let greetings: Set = ["Hello", "Hey", "Hi", "Howdy", "Salut", "Hello hello", "Oh, hello", "Hey hey"]
        XCTAssertTrue(ReactOutput.topics.map(\.name).contains("hello"))
        let hello = Take.all.filter { $0.part == .about && $0.meaning == "hello" }
        XCTAssertEqual(Set(hello.map(\.text)), greetings)
        XCTAssertTrue(hello.allSatisfy { $0.finish == nil })
        for mood in MoodOutput.moods.map(\.name) {
            XCTAssertGreaterThanOrEqual(hello.filter { $0.moods.contains(mood) }.count, 4, mood)
        }
        var rng = SplitMix64(seed: 1)
        for _ in 0..<20 {
            let take = Voice.take(.about, meaning: "hello", kind: .sound, face: "happy", finish: nil, rng: &rng)
            XCTAssertTrue(greetings.contains(take?.text ?? ""), "\(take?.text ?? "nothing")")
        }
    }

    /// Coming back is activity, so the idle heartbeat counts
    /// its hour from the back, not from the last agent event.
    func testComingBackRestartsTheIdleHeartbeat() {
        let rig = CoreRig()
        rig.poke()
        rig.wait(30 * minute)
        rig.pipeline.presence(Event(at: rig.now, source: .mac, type: .presence, phase: .start, specificType: "idle",
                                    data: ["since": .int(rig.now - 30 * minute)]))
        rig.pipeline.presence(Event(at: rig.now + 1000, source: .mac, type: .presence, phase: .end, specificType: "input"))
        let beats = { (fx: Fx) in events(fx).filter { $0.type == .heartbeat } }
        XCTAssertEqual(beats(rig.wait(40 * minute)), [], "an hour since the poke, but not since you came back")
        XCTAssertEqual(beats(rig.wait(21 * minute)).map(\.line), ["Nothing has happened for 1 hour."])
    }
}

/// The runtime's side: headless reads none of the
/// Mac's signals, so dev lines stand in, and a relaunch picks up an away
/// from the transcript.
final class PresenceRuntimeTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        try requirePack("boop")
        dir = URL(fileURLWithPath: "/tmp/boop-presence-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func makeRuntime(clock: VirtualClock) throws -> Runtime {
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("long-term.md").path) {
            try Runtime.setUp(stateDir: dir, name: "Pip")
        }
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("boop.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.devLines = true
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.advance = { clock.now += $0 }
        options.readJevKey = { _ in nil }
        return try Runtime(options)
    }

    func dev(_ runtime: Runtime, _ json: String) {
        runtime.home.sync { runtime.dev(Data(json.utf8)) }
    }

    /// The `presence` events in the transcript's files, as `start locked`.
    func presence(_ runtime: Runtime) -> [String] {
        runtime.home.sync {}
        let folder = dir.appendingPathComponent(Transcript.folderName)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        return files.flatMap { name -> [Event] in
            let text = (try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)) ?? ""
            return text.split(separator: "\n").compactMap { Event(jsonLine: $0) }
        }
        .filter { $0.type == .presence }.map { "\($0.phase?.rawValue ?? "") \($0.specificType)" }
    }

    /// A lock from a dev line becomes an away 10 minutes later, on the tick; the
    /// unlock and the next tick the back, which the view keeps as waking.
    /// Relaunched while away, the next touch is the back, not a second
    /// away. Idle set by a dev line makes the idle away.
    func testDevLinesDriveTheDetectorAndARelaunchPicksUpTheAway() throws {
        let clock = VirtualClock(presenceT0)
        do {
            let first = try makeRuntime(clock: clock)
            dev(first, #"{"dev":"presence","signal":"locked"}"#)
            dev(first, #"{"dev":"advance","ms":599000}"#)
            XCTAssertEqual(presence(first), [])
            dev(first, #"{"dev":"advance","ms":1000}"#)
            XCTAssertEqual(presence(first), ["start locked"])
            first.stop()
        }

        let runtime = try makeRuntime(clock: clock)
        XCTAssertTrue(runtime.home.sync { runtime.pipeline.away }, "read back from the transcript")
        dev(runtime, #"{"dev":"presence","idle_ms":3600000}"#)
        dev(runtime, #"{"dev":"advance","ms":3600000}"#)
        XCTAssertEqual(presence(runtime), ["start locked"], "not back until touched")
        dev(runtime, #"{"dev":"presence","signal":"unlocked"}"#)
        dev(runtime, #"{"dev":"presence","idle_ms":0}"#)
        dev(runtime, #"{"dev":"advance","ms":1000}"#)
        XCTAssertEqual(presence(runtime), ["start locked", "end unlocked"])
        let back = try XCTUnwrap(runtime.home.sync { runtime.pipeline.views.last })
        XCTAssertEqual(back.line, "You came back to the Mac after a long break.")
        XCTAssertTrue(back.wakesBrain == false, "gated: headless here has no brain")

        dev(runtime, #"{"dev":"presence","idle_ms":1800000}"#)
        dev(runtime, #"{"dev":"advance","ms":1000}"#)
        XCTAssertEqual(presence(runtime).last, "start idle")
        dev(runtime, #"{"dev":"presence","idle_ms":0}"#)
        dev(runtime, #"{"dev":"advance","ms":1000}"#)
        XCTAssertEqual(presence(runtime).last, "end input")
        runtime.stop()
    }

    /// A demo's `back` is a break of its length at once: the away the
    /// detector would have made that long before, and the back, both the
    /// demo's. The view hears the break's band, as from a real one.
    func testADemosBackIsABreakOfItsLength() throws {
        let clock = VirtualClock(presenceT0)
        let runtime = try makeRuntime(clock: clock)
        let script = try DemoScript(#"{"you": "back", "minutes": 600, "after": 0}"#)
        runtime.home.sync { runtime.play(script, live: true) }
        for _ in 0..<20 where presence(runtime).count < 2 { Thread.sleep(forTimeInterval: 0.05) }
        XCTAssertEqual(presence(runtime), ["start demo", "end demo"])
        let back = try XCTUnwrap(runtime.home.sync { runtime.pipeline.views.last })
        XCTAssertEqual(back.line, "You came back to the Mac after a very long break.")
        XCTAssertFalse(runtime.home.sync { runtime.pipeline.away }, "back, not away")
        XCTAssertNil(back.about, "a back is about no thread, so a wake-up for it names nobody's turn")
        runtime.stop()
    }
}
