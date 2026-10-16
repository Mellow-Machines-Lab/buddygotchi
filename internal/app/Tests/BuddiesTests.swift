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
        XCTAssertNil(BuddySetting.parse("left:pixel"), "two or more")
        XCTAssertNil(BuddySetting.parse("left:pixel:copilot,right:boop"), "agents Boop knows")
        // The board's id is lower case and its advertised name upper case,
        // after the same two bytes of its Bluetooth address.
        XCTAssertEqual(BoopDevice.advertised("b00p-54fe"), "Boop-54FE")
        // Two buddies of one pack get their places after its name.
        let twins = try XCTUnwrap(BuddySetting.parse("left:pixel,right:pixel"))
        let names = try twins.map { try $0.buddy(bundled: nil, among: twins).name }
        XCTAssertEqual(names, ["Pixel Left", "Pixel Right"])
    }

    func testASessionGoesToTheBuddyWatchingItsAgentElseTheLeastBusy() throws {
        let pixel = try CharacterPack.named(id: "pixel")
        let buddies = [Buddy(id: "left", pack: pixel, agents: ["claude"]), Buddy(id: "right", pack: pixel)]
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
        let all = ["left", "middle", "right"].map { Buddy(id: $0, pack: pack) }
        var e = Event(at: 1, source: .claude, type: .turn, phase: .end, specificType: "Stop", buddy: "right")
        XCTAssertEqual(Runtime.speakers(e, all), ["right", "left", "middle"])
        e = Event(at: 1, source: .boop, type: .reacted, specificType: "brain", buddy: "middle")
        XCTAssertEqual(Runtime.speakers(e, all), ["left", "right"], "a reaction wakes only the others")
        e = Event(at: 1, source: .clock, type: .heartbeat, specificType: "quiet")
        XCTAssertEqual(Runtime.speakers(e, all), ["left", "middle", "right"])
    }

    /// Two buddies on one transcript, end to end: each agent's events go to
    /// its buddy, tagged; each buddy gets a pass of its own, its own first,
    /// the others answering its reaction to a small event,
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
        XCTAssertEqual(start.buddy, "right", "codex's session goes to the buddy that watches codex")
        let passes = events.filter { $0.kind == Event.pass && $0["for"]?.int != nil }
        let onStart = passes.filter { $0["for"]?.int == Int64(start.seq) }.map { $0["voice"]?.string }
        let reacted = events.filter { $0.type == .reacted }
        // Its own buddy answers first. A turn's start is a small event, so
        // once Boop has reacted to it Pixel answers that reaction, which
        // HISTORY shows under it, rather than the start again.
        XCTAssertEqual(onStart, ["right"])
        let pixelsFirst = passes.first { $0["voice"]?.string == "left" }
        XCTAssertEqual(pixelsFirst?["for"]?.int, reacted.first.map { Int64($0.seq) })
        XCTAssertEqual(reacted.first?.buddy, "right")
        XCTAssertTrue(reacted.first?["message"]?.string?.hasPrefix("Boop made") == true, "\(reacted.first?.data ?? [:])")
        XCTAssertTrue(reacted.contains { $0["message"]?.string?.hasPrefix("Pixel made") == true })
        // Each reply is one more in its chain, and past the failsafe a
        // reaction no longer wakes the others.
        let held = passes.compactMap { $0["held"]?.string }
        XCTAssertEqual(Set(held), ["the buddies have answered each other \(Buddy.maxRepliesInARow) times in a row"])
        let chains = reacted.compactMap { $0["chain"]?.int }
        XCTAssertEqual(chains.max(), Int64(Buddy.maxRepliesInARow + 1), "the reply past the failsafe is logged, and wakes nobody")
        let answeredChains = passes.filter { $0["held"] == nil }.compactMap { p in reacted.first { $0.seq == Int(p["for"]?.int ?? 0) }?["chain"]?.int }
        XCTAssertEqual(answeredChains.max(), Int64(Buddy.maxRepliesInARow), "they answer each other this often, and no more")

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
        XCTAssertEqual(poke.buddy, "right")
        XCTAssertEqual(runtime.home.sync { runtime.harness.line(poke.seq)?.text }, "You poked Boop.")
        XCTAssertEqual(step.recorded.last?["message"]?.string, "Boop wiggled on its own.", "its own core, in its own name")
    }
}
