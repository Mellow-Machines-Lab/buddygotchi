import AgentHooks
import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// What Boop did before its brain moved onto MellowHarness (main at 4bea7b21)
/// and still does: the mood
/// a Boop from before comes back in, with its sessions and threads, and a
/// reaction your tap cut short held however long the pokes go on.
final class ParityTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-par-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    static let steering = try! Steering(directory: CharacterPack.active.directory.appendingPathComponent("steering"))
    /// The state directory main left (Fixtures/parity-upgrade): its
    /// transcript, two days of main's lines, and its `mood` file, proud,
    /// from a change 29 hours before the relaunch at `t`.
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/parity-upgrade")
    /// 18:00 on 2026-09-30 in Los Angeles, where the fixture's days are.
    static let t: Int64 = 1_790_816_400_000
    static let hour: Int64 = 3_600_000
    static let time = LocalTime(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

    /// Opens the runtime on `dir` at `now` without starting it, hands it to
    /// `body`, and lets it go, with its lock, before the next launch.
    func launch(at now: Int64, logged: Lines = Lines(), _ body: (Runtime, SoakClock) throws -> Void) throws {
        let clock = SoakClock(now)
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: Self.steering)
        options.time = Self.time
        options.clock = { clock.now }
        options.wallClock = { clock.now }
        options.readJevKey = { _ in nil }
        options.log = { logged.add($0) }
        try autoreleasepool {
            let runtime = try Runtime(options)
            try body(runtime, clock)
            runtime.stop()
        }
    }

    /// The first launch after the change, on a state directory main left:
    /// Boop comes back proud, the mood main's file kept though its change
    /// is 29 hours old, with no time in it, as main showed it; the sessions
    /// are main's, alpha working and beta idle, and the next turns are
    /// numbered as main numbered them. The file goes, and the log keeps the
    /// mood from then on: a relaunch an hour later is still proud, and one
    /// a day after with no change starts calm.
    func testAnUpgradeComesBackAsMainDid() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: Self.time.day(Self.t))
        for name in ["transcript", MoodAction.fileName] {
            try FileManager.default.copyItem(at: Self.fixture.appendingPathComponent(name), to: dir.appendingPathComponent(name))
        }
        let t = Self.t
        let logged = Lines()
        try launch(at: t, logged: logged) { rt, clock in
            rt.home.sync {
                let log = rt.harness.log.view(now: t)
                XCTAssertEqual(MoodAction.value(rt.mood, log), "proud", "main's mood file")
                XCTAssertEqual(rt.core.snapshot(at: t).mood, "proud", "on the device")
                XCTAssertNil(MoodAction.sinceLine(rt.mood, log, at: t), "no time: main had none after a relaunch")
                XCTAssertEqual(rt.core.sessionList(at: t).map { "\($0.agent) \($0.project) \($0.status.rawValue)" },
                               ["claude alpha working", "claude beta idle"], "main's sessions")
                let carried = rt.mood.latest(log)
                XCTAssertEqual(carried?["by"]?.string, MoodAction.carriedBy)
                XCTAssertNil(carried?["message"], "HISTORY doesn't show it")
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(MoodAction.fileName).path))
            XCTAssertTrue(logged.all.contains("mood: proud, carried over from the mood file"))
            func next(_ session: String, _ project: String, at: Int64) -> String? {
                clock.now = at
                let line = HookLine(agent: "claude", hook: "UserPromptSubmit", session: session, cwd: "/tmp/par/\(project)",
                                    prompt: "And now?", ts: at)
                return rt.home.sync { rt.pipeline.agent(Adapter.event(from: line, receivedAt: at)!).views.first?.line }
            }
            XCTAssertEqual(next("a1", "alpha", at: t + 1000), #"claude started turn 3 on "alpha"."#, "main's numbering")
            XCTAssertEqual(next("b1", "beta", at: t + 2000), #"claude started turn 2 on "beta"."#)
            XCTAssertEqual(rt.home.sync { rt.view.refolds }, 0, "the view folded the read-back and the rest once, in order")
        }
        try launch(at: t + Self.hour) { rt, _ in
            rt.home.sync {
                let log = rt.harness.log.view(now: t + Self.hour)
                XCTAssertEqual(MoodAction.value(rt.mood, log), "proud", "the log keeps it")
                XCTAssertNil(MoodAction.sinceLine(rt.mood, log, at: t + Self.hour))
            }
        }
        try launch(at: t + 25 * Self.hour) { rt, _ in
            XCTAssertEqual(rt.home.sync { MoodAction.value(rt.mood, rt.harness.log.view(now: t + 25 * Self.hour)) }, "calm",
                           "a day with no change: the design's calm")
        }
    }

    /// A running Boop keeps the mood it carried
    /// over while nothing changes it, with no key for the brain, and once
    /// that change is a day old turns calm on the device, as the log, the
    /// menu bar and MOOD already have it, not only at the next launch.
    func testACarriedMoodThatAgesOutGoesFromTheDeviceToo() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet, today: Self.time.day(Self.t))
        for name in ["transcript", MoodAction.fileName] {
            try FileManager.default.copyItem(at: Self.fixture.appendingPathComponent(name), to: dir.appendingPathComponent(name))
        }
        let t = Self.t, day = 24 * Self.hour
        try launch(at: t) { rt, clock in
            func tick(at now: Int64) -> (log: String, device: String) {
                clock.now = now
                return rt.home.sync {
                    rt.tick()
                    return (MoodAction.value(rt.mood, rt.harness.log.view(now: now)), rt.core.snapshot(at: now).mood)
                }
            }
            let before = tick(at: t + day - 1000)
            XCTAssertEqual(before.log, "proud")
            XCTAssertEqual(before.device, "proud")
            let after = tick(at: t + day + 1000)
            XCTAssertEqual(after.log, "calm", "the change has aged out")
            XCTAssertEqual(after.device, "calm", "the device follows the log")
        }
    }

    /// The file only fills a gap. A change in the
    /// log's last day wins over it; `cheerful`, happy's old name, reads as
    /// happy; a word that isn't a mood reads as calm, noted; calm logs
    /// nothing. The file goes every time.
    func testTheMoodFileOnlyFillsAGap() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(MoodAction.fileName)
        let t = Self.t
        func carried(_ word: String, loggedChange: String? = nil) throws -> (mood: String, dids: Int, notes: [String]) {
            try (word + "\n").write(to: file, atomically: true, encoding: .utf8)
            let h = Harness(name: "Boop", brain: nil, log: Log(), clock: .init(now: { t }), queue: .main)
            let mood = MoodAction.choice()
            h.output(mood)
            if let to = loggedChange {
                h.emit(Event.did("Boop's mood changed: calm → \(to).", for: nil, action: MoodAction.actionName, by: "brain",
                                 facts: ["from": "calm", "to": .string(to)]))
            }
            let notes = Lines()
            MoodAction.carryOver(mood, stateDir: dir, harness: h, note: { notes.add($0) })
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the file goes")
            let log = h.log.view(now: t)
            return (MoodAction.value(mood, log), log.count(Event.did), notes.all)
        }
        let grumpy = try carried("grumpy"), logged = try carried("annoyed", loggedChange: "happy")
        let cheerful = try carried("cheerful"), sulky = try carried("sulky"), calm = try carried("calm")
        XCTAssertEqual(grumpy.mood, "grumpy")
        XCTAssertEqual(grumpy.dids, 1)
        XCTAssertEqual(logged.mood, "happy", "the log's own change wins")
        XCTAssertEqual(logged.dids, 1, "and nothing is added")
        // An old name the pack keeps as an alias reads as its mood (Boop's cheerful is happy).
        XCTAssertEqual(cheerful.mood, CharacterPack.active.aliases["cheerful"] ?? CharacterPack.active.defaultMood)
        XCTAssertEqual(sulky.mood, "calm")
        XCTAssertEqual(sulky.notes, ["mood: the mood file says sulky, which isn't a mood; reading it as calm"])
        XCTAssertEqual(calm.dids, 0)
        let none = Harness(name: "Boop", brain: nil, log: Log(), clock: .init(now: { t }), queue: .main)
        MoodAction.carryOver(MoodAction.choice(), stateDir: dir, harness: none)
        XCTAssertEqual(none.log.lastSeq, 0, "no file, nothing to do")
    }

    /// A reaction your tap cut short stays in progress while the pokes go
    /// on, however long, as main's view held it:
    /// past react's 90 s `openFor` a run of pokes neither drops it from
    /// HISTORY nor lets the next poke wake the brain again, and the pokes
    /// stopping for minutes with nothing else happening keeps it too.
    /// Anything else happening lets it go, and the ceiling ends a reaction
    /// no tap cut as before. On the app's own outputs (`Runtime.harness`),
    /// so it's react's `keepOpen` there that holds it.
    func testATapCutReactionOutlastsReactsOpenForWhileThePokesGoOn() {
        XCTAssertEqual(ReactAction.openForMs, 90_000)
        let rig = CoreRig()
        let (h, _) = Runtime.harness(pipeline: rig.pipeline, steering: Self.steering, personality: { .default }, queue: { _, _ in })
        func poke() -> Event {
            rig.poke()
            return h.log.events.last { $0.type == .poke }!
        }
        _ = poke()
        rig.now += 1000
        _ = poke()
        rig.now += 1000
        let third = poke()
        // The brain's reaction to the third poke in a row, as the harness logs it.
        let open = h.emit(Event.did("Boop made a grumpy face, held twice.", for: third.seq, action: ReactAction.actionName,
                                    by: "brain", open: true))
        rig.now += 1500
        _ = poke()  // the tap that cut it
        for _ in 0..<60 {
            rig.wait(2000)
            let p = poke()
            XCTAssertTrue(rig.view.pokesAnswered(p, h.log.view(now: rig.now)), "Boop is answering these pokes")
        }
        XCTAssertGreaterThan(rig.now - open.at, ReactAction.openForMs)
        XCTAssertTrue(h.log.openDids.contains(open.seq), "in progress past 90 s of pokes")
        XCTAssertEqual(h.log.view(now: rig.now).shown(open)?.inProgress, true)
        rig.wait(5 * 60_000)
        XCTAssertTrue(h.log.openDids.contains(open.seq), "the pokes stopped, and nothing else has happened")
        rig.send(.turnStart)
        XCTAssertFalse(TranscriptView.heldByPokes(open, h.log.view(now: rig.now)), "something else happened")
        rig.wait(1000)
        XCTAssertEqual(h.log.ended(open.seq)?["why"]?.string, Harness.noWord, "nothing ended it, so the ceiling does")

        let uncut = h.emit(Event.did("Boop made a happy face.", for: nil, action: ReactAction.actionName, by: "brain", open: true))
        rig.wait(ReactAction.openForMs - 1000)
        XCTAssertNil(h.log.ended(uncut.seq))
        rig.wait(1000)
        XCTAssertEqual(h.log.ended(uncut.seq)?["why"]?.string, Harness.noWord, "no poke came after it: 90 s, as before")
    }
}
