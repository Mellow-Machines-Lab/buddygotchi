import AgentHooks
import Foundation
import MellowHarness
import LinkKit
import XCTest
@testable import BoopDevKit
@testable import BoopKit

/// Several buddies side by side (`Buddy`): each board its own pack, core
/// and agents, one transcript, and the brain answering for each buddy in
/// a pass of its own, so they hear and answer each other.
final class BuddiesTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-bud-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    func testSettingsAndFlagsNameEachBuddy() throws {
        let parsed = try XCTUnwrap(BuddySetting.parse("left:pixel:claude,right:boop:codex:Bo"))
        XCTAssertEqual(parsed, [BuddySetting(place: "left", pack: "pixel", agents: ["claude"]),
                                BuddySetting(place: "right", pack: "boop", agents: ["codex"], name: "Bo")])
        XCTAssertNil(BuddySetting.parse("left:pixel,left:boop"), "a place once")
        XCTAssertNil(BuddySetting.parse("left"), "a place and a pack")
        // The board's id is lower case and its advertised name upper case,
        // after the same two bytes of its Bluetooth address.
        XCTAssertEqual(BuddySetting(place: "left", pack: "pixel", board: "b00p-54fe").advertised, "Boop-54FE")
        // Two buddies of one pack get their places after its name.
        let twins = try XCTUnwrap(BuddySetting.parse("left:pixel,right:pixel"))
        let names = try twins.map { try $0.buddy(bundled: nil, among: twins).name }
        XCTAssertEqual(names, ["Pixel Left", "Pixel Right"])
    }

    func testASessionGoesToTheBuddyWatchingItsAgentElseTheLeastBusy() throws {
        let pixel = try CharacterPack.named(id: "pixel")
        let buddies = [Buddy(id: "left", pack: pixel, place: "left", agents: ["claude"]),
                       Buddy(id: "right", pack: pixel, place: "right")]
        let binding = BuddyBinding()
        func event(_ agent: Agent, _ session: String) -> Event {
            Event(at: 1, source: .init(agent), type: .turn, phase: .start, specificType: "UserPromptSubmit", session: session)
        }
        var watching = ["left": 0, "right": 0]
        XCTAssertEqual(binding.buddy(for: event(.claude, "a"), among: buddies, watching: { watching[$0]! }), "left")
        watching["left"] = 1
        XCTAssertEqual(binding.buddy(for: event(.codex, "b"), among: buddies, watching: { watching[$0]! }), "right")
        watching["right"] = 5
        XCTAssertEqual(binding.buddy(for: event(.codex, "c"), among: buddies, watching: { watching[$0]! }), "left",
                       "no buddy watches codex first, so the least busy")
        XCTAssertEqual(binding.buddy(for: event(.codex, "b"), among: buddies, watching: { watching[$0]! }), "right",
                       "a session keeps its buddy")
    }

    func testEachBuddyAnswersItsOwnEventFirstAndTheOthersReactions() {
        let pack = CharacterPack.active
        let all = ["left", "middle", "right"].map { Buddy(id: $0, pack: pack, place: $0) }
        var e = Event(at: 1, source: .claude, type: .turn, phase: .end, specificType: "Stop", data: ["buddy": "right"])
        XCTAssertEqual(Runtime.speakers(e, all), ["right", "left", "middle"])
        e = Event(at: 1, source: .boop, type: .reacted, specificType: "brain", data: ["buddy": "middle"])
        XCTAssertEqual(Runtime.speakers(e, all), ["left", "right"], "a reaction wakes only the others")
        e = Event(at: 1, source: .clock, type: .heartbeat, specificType: "quiet")
        XCTAssertEqual(Runtime.speakers(e, all), ["left", "middle", "right"])
    }

    /// Two buddies on one transcript, end to end: each agent's events go to
    /// its buddy, tagged; each buddy gets a pass of its own, its own first,
    /// whose prompt opens with whom it answers for; each plays on its own
    /// board; and each hears the other's reaction, until the failsafe
    /// (`Buddy.maxRepliesInARow`, 10) stops a chain no outside event
    /// breaks.
    func testTwoBuddiesShareATranscriptAndAnswerEachOther() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet)
        let settings = try XCTUnwrap(BuddySetting.parse("left:pixel:claude,right:boop:codex"))
        let (left, right) = (FakeTransport(), FakeTransport())
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.buddies = try zip(settings, [left, right]).map { setting, transport in
            let buddy = try setting.buddy(bundled: nil, among: settings)
            return Runtime.BuddyOptions(buddy: buddy, link: transport,
                                        steering: try Steering(directory: buddy.pack.directory.appendingPathComponent("steering"), pack: buddy.pack))
        }
        options.debug = true
        options.readJevKey = { _ in "k" }
        options.brain = { key in key.map { _ in ScriptedBrain.pipelineCheck } }
        let runtime = try Runtime(options)
        try runtime.start()
        defer { runtime.stop() }
        for t in [left, right] { t.onConnection?(true) }
        eventually("both boards said hello") { runtime.home.sync { runtime.helloFromEvery } }
        eventually("the brain is ready") { runtime.home.sync { runtime.harness.brain != nil } }

        let now = runtime.options.clock()
        runtime.home.sync {
            runtime.hook(HookLine(agent: "codex", hook: "UserPromptSubmit", session: "c1", cwd: "/tmp/proj", ts: now), received: now)
        }
        eventually("the chain settles", timeout: 10) { runtime.home.sync { runtime.harness.idle } }

        let events = runtime.home.sync { Array(runtime.harness.log.view(now: runtime.options.clock()).events) }
        let start = try XCTUnwrap(events.first { $0.kind == "turn_start" })
        XCTAssertEqual(Buddy.of(start), "right", "codex's session goes to the buddy that watches codex")
        let passes = events.filter { $0.kind == Event.pass && $0["for"]?.int != nil }
        let onStart = passes.filter { $0["for"]?.int == Int64(start.seq) }.map { $0["voice"]?.string }
        XCTAssertEqual(onStart, ["right", "left"], "its own buddy answers first")
        let reacted = events.filter { $0.type == .reacted }
        XCTAssertEqual(reacted.first.flatMap(Buddy.of), "right")
        XCTAssertTrue(reacted.first?["message"]?.string?.hasPrefix("Boop made") == true, "\(reacted.first?.data ?? [:])")
        XCTAssertTrue(reacted.contains { $0["message"]?.string?.hasPrefix("Pixel made") == true })
        let held = passes.compactMap { $0["held"]?.string }
        XCTAssertEqual(Set(held), ["the buddies have answered each other \(Buddy.maxRepliesInARow) times in a row"])
        let answered = passes.filter { p in p["held"] == nil && reacted.contains { $0.seq == Int(p["for"]?.int ?? 0) } }
        XCTAssertEqual(answered.count, Buddy.maxRepliesInARow, "they answer each other this often, and no more")

        // Each buddy's prompt opens with whom it answers for.
        let heads = try String(contentsOf: runtime.debugLogURL, encoding: .utf8).split(separator: "\n")
            .compactMap { line in (try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])?["head"] as? String }
        XCTAssertTrue(heads.contains { $0.hasPrefix("YOU ARE PIXEL, THE BUDDY ON THE LEFT.") }, "\(heads.map { $0.prefix(60) })")
        XCTAssertTrue(heads.contains { $0.hasPrefix("YOU ARE BOOP, THE BUDDY ON THE RIGHT.") })
        // Each plays on its own board.
        XCTAssertTrue(left.sent.contains { $0.hasPrefix(#"{"t":"do""#) })
        XCTAssertTrue(right.sent.contains { $0.hasPrefix(#"{"t":"do""#) })
    }

    /// A tap on one board pokes that buddy alone, and its line names it.
    func testATapPokesItsOwnBuddy() throws {
        try Runtime.setUp(stateDir: dir, name: "Pip", nature: .sweet)
        let settings = try XCTUnwrap(BuddySetting.parse("left:pixel,right:boop"))
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path, link: nil,
                                      steering: RuntimeTests.steering)
        options.buddies = try settings.map { setting in
            let buddy = try setting.buddy(bundled: nil, among: settings)
            return Runtime.BuddyOptions(buddy: buddy, link: nil,
                                        steering: try Steering(directory: buddy.pack.directory.appendingPathComponent("steering"), pack: buddy.pack))
        }
        let runtime = try Runtime(options)
        let step = runtime.home.sync { runtime.pipeline.poke(at: runtime.options.clock(), buddy: "right") }
        let poke = try XCTUnwrap(step.recorded.first)
        XCTAssertEqual(Buddy.of(poke), "right")
        XCTAssertEqual(runtime.home.sync { runtime.harness.line(poke.seq)?.text }, "You poked Boop.")
        XCTAssertEqual(step.recorded.last?["message"]?.string, "Boop wiggled on its own.", "its own core, in its own name")
    }
}
