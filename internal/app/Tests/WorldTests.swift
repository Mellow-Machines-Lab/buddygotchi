import Foundation
import MellowHarness
import XCTest
@testable import BoopKit

/// The world of buddies on the Mac: what leaves it, the wire's fixtures,
/// the gestures' limits, and `WorldLink` against a server that answers
/// from here. Nothing here reaches a real server.
final class WorldTests: XCTestCase {
    static var fixtures: URL { CharacterPackTests.repo.appendingPathComponent("internal/world/fixtures") }

    func fixture(_ name: String) throws -> Data { try Data(contentsOf: Self.fixtures.appendingPathComponent(name)) }

    func keys(_ data: Data) throws -> Set<String> {
        Set(try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
    }

    static let state = World.State(seq: 1, name: "Mochi", level: 12, stage: "buddy", utcOffset: 60, activity: .testing,
                                   day: "2026-11-08", xpToday: 82, added: .init(turns: 3, testsPassed: 2, ships: 0, linesChanged: 140))

    /// What leaves the Mac, and nothing else (plan/world.md §9): the name,
    /// level and stage, the UTC offset, one of six activities, the day's
    /// XP, and the counts. A new field, kept or sent, fails here, whatever
    /// its coding key: no country, no time zone name, nothing of the work.
    func testOnlyTheseFieldsEverLeaveTheMac() throws {
        let sent = try JSONEncoder().encode(Self.state)
        let sentKeys = try keys(sent)
        XCTAssertEqual(sentKeys, ["seq", "name", "level", "stage", "utc_offset", "activity", "day", "xp_today", "added"])
        let added = try XCTUnwrap((try JSONSerialization.jsonObject(with: sent) as? [String: Any])?["added"] as? [String: Any])
        XCTAssertEqual(Set(added.keys), ["turns", "tests_passed", "ships", "lines_changed"])
        XCTAssertEqual(Mirror(reflecting: Self.state).children.compactMap(\.label),
                       ["seq", "name", "level", "stage", "utcOffset", "activity", "day", "xpToday", "added"])
        XCTAssertEqual(Mirror(reflecting: World.Counts()).children.compactMap(\.label), ["turns", "testsPassed", "ships", "linesChanged"])
        XCTAssertEqual(World.Activity.allCases.map(\.rawValue), ["coding", "testing", "shipping", "waiting", "idle", "asleep"])
        // The server's example of a send has these keys exactly.
        let fixtureKeys = try keys(fixture("buddy-state.json"))
        XCTAssertEqual(fixtureKeys, sentKeys)
    }

    /// The server's examples decode as the Mac reads them, so the two can't drift.
    func testTheWiresFixturesDecode() throws {
        let state = try JSONDecoder().decode(World.State.self, from: fixture("buddy-state.json"))
        XCTAssertEqual(state.utcOffset, 60)
        XCTAssertEqual(state.added.linesChanged, 140)
        let reply = try JSONDecoder().decode(World.Reply.self, from: fixture("buddy-reply.json"))
        XCTAssertEqual(reply.gestures, [World.Gesture(kind: .boop, fromRegion: .asiaOceania, at: "2026-11-08T16:58:12Z")])
        let world = try JSONDecoder().decode(World.Snapshot.self, from: fixture("world.json"))
        XCTAssertEqual(world.awake, 214)
        XCTAssertEqual(world.regions.map(\.region), [.americas, .europeAfrica, .asiaOceania])
        XCTAssertEqual(world.buddies.map(\.utcOffset), [540, nil])
        XCTAssertEqual(world.doing["coding"], 38)
    }

    /// The regions' edges are the server's (internal/world/src/regions.ts).
    func testTheRegionsAreTheServers() {
        XCTAssertEqual(World.Region(offset: -720), .americas)
        XCTAssertEqual(World.Region(offset: -120), .americas)
        XCTAssertEqual(World.Region(offset: -105), .europeAfrica)
        XCTAssertEqual(World.Region(offset: 180), .europeAfrica)
        XCTAssertEqual(World.Region(offset: 195), .asiaOceania)
        XCTAssertEqual(World.Region(offset: 840), .asiaOceania)
        XCTAssertNil(World.Region(offset: nil))
    }

    /// The words: one buddy by its region, several counted, and what waited.
    func testTheSentences() {
        XCTAssertEqual(World.sentence([(.boop, 1)], from: .europeAfrica, held: false, name: "Mochi"),
                       "Someone in Europe or Africa booped Mochi.")
        XCTAssertEqual(World.sentence([(.cheer, 3)], from: nil, held: false, name: "Mochi"), "3 buddies cheered your ship.")
        XCTAssertEqual(World.sentence([(.boop, 2), (.cheer, 1)], from: nil, held: true, name: "Mochi"),
                       "While you were away, 2 buddies booped Mochi and one cheered your ship.")
        for kind in World.GestureKind.allCases {
            for n in [1, 3, 12] {
                XCTAssertNotNil(Narration.fit(World.facts(kind, count: n), name: "Mochi"), "\(kind) x\(n) fits the lane")
            }
        }
    }

    /// Pins `WorldGestures`' limits: at most 3 boops, waves and hearts an
    /// hour play, the rest logged as not playing; one ship's cheers are one
    /// moment, and more within 30 minutes don't play.
    func testAtMostThreeAnHourAndOneMomentForCheers() {
        XCTAssertEqual(WorldGestures.perHour, 3)
        XCTAssertEqual(WorldGestures.cheerWindowMs, 30 * 60_000)
        var g = WorldGestures()
        let boop = World.Gesture(kind: .boop, fromRegion: .americas, at: "")
        let first = g.arrived([boop, boop, boop, boop], quiet: false, at: 0)
        XCTAssertEqual(first.map { $0["plays"]?.bool != false }, [true, true, true, false])
        XCTAssertEqual(g.arrived([boop], quiet: false, at: 59 * 60_000).map { $0["plays"]?.bool != false }, [false])
        XCTAssertEqual(g.arrived([boop], quiet: false, at: 60 * 60_000).map { $0["plays"]?.bool != false }, [true], "an hour on")
        let cheer = World.Gesture(kind: .cheer, fromRegion: nil, at: "")
        let cheers = g.arrived([cheer, cheer, cheer], quiet: false, at: 0)
        XCTAssertEqual(cheers.count, 1, "one moment")
        XCTAssertEqual(cheers.first?["count"]?.int, 3)
        XCTAssertEqual(g.arrived([cheer], quiet: false, at: 10 * 60_000).first?["plays"]?.bool, false)
        XCTAssertNil(g.arrived([cheer], quiet: false, at: 41 * 60_000).first?["plays"], "a new ship's")
        // Logged, the one past the hour wakes no pass; the others may.
        let rig = CoreRig()
        rig.pipeline.world(first, at: rig.now)
        let log = rig.pipeline.harness.log.view(now: rig.now)
        let logged = log.events.filter { $0.type == .world }
        XCTAssertEqual(logged.count, 4)
        XCTAssertNil(rig.view.hold(logged[0], log, needsYou: { nil }))
        XCTAssertNotNil(rig.view.hold(logged[3], log, needsYou: { nil }), "past the hour: the World tab counts it")
    }

    /// At night or while you're away, gestures wait, and come back as one
    /// line that plays when you're here in the day.
    func testAtNightTheyWaitForTheMorning() throws {
        var g = WorldGestures()
        let boop = World.Gesture(kind: .boop, fromRegion: .asiaOceania, at: "")
        let cheer = World.Gesture(kind: .cheer, fromRegion: nil, at: "")
        XCTAssertEqual(g.arrived([boop, boop, cheer], quiet: true, at: 0), [])
        let morning = g.release(at: 8 * 3_600_000)
        XCTAssertEqual(morning.count, 1)
        XCTAssertEqual(morning.first?["held"]?.bool, true)
        XCTAssertEqual(WorldGestures.counts(of: morning[0]).map { "\($0.0.rawValue) \($0.1)" }, ["boop 2", "cheer 1"])
        XCTAssertEqual(g.release(at: 9 * 3_600_000), [], "once")
        let rig = CoreRig()
        rig.pipeline.world(morning, at: rig.now)
        let logged = try XCTUnwrap(rig.pipeline.harness.log.view(now: rig.now).events.last { $0.type == .world })
        XCTAssertEqual(rig.pipeline.harness.line(logged.seq)?.text,
                       "While you were away, 2 buddies booped \(CharacterPack.active.name) and one cheered your ship.")
    }

    // MARK: WorldLink against a server that answers from here

    /// The requests the stub saw, and what it answers.
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var seen: [(method: String, path: String, body: [String: Any]?, auth: String?)] = []
        nonisolated(unsafe) static var answer: (String, String) -> (Int, String) = { _, _ in (200, "{}") }
        static let lock = NSLock()

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open()
                var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: 4096); if n <= 0 { break }; bytes.append(buffer, count: n) }
                stream.close()
                data = bytes
            }
            let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let method = request.httpMethod ?? "GET", path = request.url?.path ?? ""
            Self.lock.withLock { Self.seen.append((method, path, body, request.value(forHTTPHeaderField: "Authorization"))) }
            let (status, json) = Self.answer(method, path)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: status == 429 ? ["Retry-After": "20"] : [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    var dir: URL!
    let queue = DispatchQueue(label: "world-test")

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("boop-world-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Stub.seen = []
        Stub.answer = { method, path in
            switch (method, path) {
            case ("POST", "/v1/buddies"): (201, #"{"id":"b1","key":"k1","name":"Mochi","name_ok":true}"#)
            case ("PUT", "/v1/buddies/me"):
                (200, #"{"ok":true,"name":"Mochi","name_ok":true,"name_hidden":false,"gestures":[{"kind":"boop","from_region":"americas","at":"x"}]}"#)
            case ("GET", "/v1/world"): (200, String(data: try! Data(contentsOf: WorldTests.fixtures.appendingPathComponent("world.json")), encoding: .utf8)!)
            default: (200, #"{"ok":true,"gestures":[]}"#)
            }
        }
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func link() -> WorldLink {
        WorldLink(client: WorldClient(base: URL(string: "http://world.test")!, queue: queue, protocols: [Stub.self]), stateDir: dir)
    }

    static let me = WorldLink.Now(name: "Mochi", level: 2, stage: "Hatchling", utcOffset: 60, activity: .coding, day: "2026-11-08", xpToday: 40)

    func settle() { for _ in 0..<50 { queue.sync {}; Thread.sleep(forTimeInterval: 0.01) } }

    /// Off, or before onboarding's world screen, nothing at all is sent;
    /// on, it joins, keeps its key readable only by you, and sends.
    func testNothingIsSentUntilItsOn() throws {
        let world = link()
        queue.sync { world.tick(Self.me, on: false, quiet: false, today: "2026-11-08", at: 0) }
        settle()
        XCTAssertTrue(Stub.seen.isEmpty)
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 1_000) }
        settle()
        XCTAssertEqual(Stub.seen.map { "\($0.method) \($0.path)" }, ["POST /v1/buddies"])
        XCTAssertEqual(Set(Stub.seen[0].body?.keys.map { $0 } ?? []), ["name", "utc_offset"], "no country, no time zone")
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(WorldLink.fileName).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 2_000) }
        settle()
        let send = try XCTUnwrap(Stub.seen.last)
        XCTAssertEqual("\(send.method) \(send.path)", "PUT /v1/buddies/me")
        XCTAssertEqual(send.auth, "Bearer k1")
        XCTAssertEqual(Set(send.body?.keys.map { $0 } ?? []), ["seq", "name", "level", "stage", "utc_offset", "activity", "day", "xp_today", "added"])
    }

    /// It sends on a change, not on a clock: the same state again waits for
    /// the heartbeat; a change of activity goes at once, but never within
    /// 10 s of the last; the counts wait up to 3 minutes; gestures in the
    /// reply become events.
    func testItSendsOnChangeAndTheRepliesGesturesBecomeEvents() throws {
        let world = link()
        var events: [Event] = []
        world.onEvents = { events += $0 }
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 0) }
        settle()
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 1_000) }
        settle()
        func sends() -> Int { Stub.seen.filter { $0.method == "PUT" }.count }
        XCTAssertEqual(sends(), 1)
        XCTAssertEqual(events.map(\.type), [.world])
        XCTAssertEqual(events.first?.specificType, "boop")
        XCTAssertEqual(world.status.today.count, 1)
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 60_000) }
        settle()
        XCTAssertEqual(sends(), 1, "nothing changed")
        var testing = Self.me
        testing.activity = .testing
        queue.sync { world.tick(testing, on: true, quiet: false, today: "2026-11-08", at: 65_000) }
        settle()
        XCTAssertEqual(sends(), 2, "a change of activity, at once")
        var coding = testing
        coding.activity = .coding
        queue.sync { world.tick(coding, on: true, quiet: false, today: "2026-11-08", at: 70_000) }
        settle()
        XCTAssertEqual(sends(), 2, "not within 10 s")
        queue.sync { world.tick(coding, on: true, quiet: false, today: "2026-11-08", at: 75_000) }
        settle()
        XCTAssertEqual(sends(), 3)
        queue.sync {
            world.heard(Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "Stop", session: "s"), at: 80_000)
            world.tick(coding, on: true, quiet: false, today: "2026-11-08", at: 81_000)
        }
        settle()
        XCTAssertEqual(sends(), 3, "counts wait")
        queue.sync { world.tick(coding, on: true, quiet: false, today: "2026-11-08", at: 80_000 + WorldLink.countsWaitMs) }
        settle()
        XCTAssertEqual(sends(), 4)
        XCTAssertEqual((Stub.seen.last?.body?["added"] as? [String: Int])?["turns"], 1)
        queue.sync { world.tick(coding, on: true, quiet: false, today: "2026-11-08", at: 80_000 + WorldLink.countsWaitMs + WorldLink.heartbeatMs) }
        settle()
        XCTAssertEqual(sends(), 5, "the heartbeat")
        XCTAssertEqual((Stub.seen.last?.body?["added"] as? [String: Int])?["turns"], 0, "counted once")
    }

    /// Asleep at once on a lock, even within 10 s; the World tab fetches the
    /// world only while it's open; leaving deletes the buddy and its key.
    func testSleepFetchAndLeave() throws {
        let world = link()
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 0) }
        settle()
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 1_000) }
        settle()
        queue.sync { world.sleep(Self.me, on: true, at: 2_000) }
        settle()
        XCTAssertEqual(Stub.seen.last?.body?["activity"] as? String, "asleep")
        XCTAssertFalse(Stub.seen.contains { $0.path == "/v1/world" })
        queue.sync { world.tab(open: true, at: 3_000) }
        settle()
        XCTAssertEqual(world.status.snapshot?.awake, 214)
        let fetched = Stub.seen.filter { $0.path == "/v1/world" }.count
        queue.sync { world.tab(open: false, at: 4_000) }
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 100_000) }
        settle()
        XCTAssertEqual(Stub.seen.filter { $0.path == "/v1/world" }.count, fetched, "closed: no fetch")
        queue.sync { world.leave(at: 200_000) }
        settle()
        XCTAssertEqual(Stub.seen.last.map { "\($0.method) \($0.path)" }, "DELETE /v1/buddies/me")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(WorldLink.fileName).path))
        XCTAssertFalse(world.status.joined)
    }

    /// A leave the server doesn't take keeps the key, sends nothing more,
    /// and is tried again until the buddy is gone: none is left behind.
    func testAFailedLeaveIsTriedAgain() throws {
        let world = link()
        queue.sync { world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 0) }
        settle()
        Stub.answer = { method, _ in method == "DELETE" ? (500, #"{"error":"server_error"}"#) : (200, "{}") }
        queue.sync { world.leave(at: 1_000) }
        settle()
        let file = dir.appendingPathComponent(WorldLink.fileName).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: file), "the key stays")
        XCTAssertFalse(world.status.joined)
        Stub.answer = { _, _ in (200, #"{"ok":true}"#) }
        queue.sync { world.tick(Self.me, on: false, quiet: false, today: "2026-11-08", at: 2_000) }
        settle()
        XCTAssertNotEqual(Stub.seen.last?.method, "PUT")
        queue.sync { world.tick(Self.me, on: false, quiet: false, today: "2026-11-08", at: 1_000 + WorldLink.backoffMs) }
        settle()
        XCTAssertEqual(Stub.seen.last.map { "\($0.method) \($0.path)" }, "DELETE /v1/buddies/me")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file), "gone once the server says so")
        XCTAssertFalse(Stub.seen.contains { $0.method == "PUT" }, "nothing sent while leaving")
    }

    func tick(_ world: WorldLink, _ at: Int64, on: Bool = true, quiet: Bool = false, me: WorldLink.Now = WorldTests.me) {
        queue.sync { world.tick(me, on: on, quiet: quiet, today: "2026-11-08", at: at) }
        settle()
    }

    func calls() -> [String] { Stub.seen.map { "\($0.method) \($0.path)" } }

    /// A 429 waits as long as it says, and the same send goes again then,
    /// its seq and counts as they were. A buddy the world forgot, by the
    /// server's own 401, joins again, after a wait.
    func testTooSoonWaitsAndAForgottenBuddyJoinsAgainLater() throws {
        let world = link()
        tick(world, 0)
        world.heard(Event(at: 0, source: .claude, type: .turn, phase: .end, specificType: "Stop", session: "s"), at: 0)
        Stub.answer = { method, _ in method == "PUT" ? (429, #"{"error":"too_soon"}"#) : (200, "{}") }
        tick(world, 1_000)
        let first = try XCTUnwrap(Stub.seen.last?.body)
        let tries = Stub.seen.count
        tick(world, 15_000)
        XCTAssertEqual(Stub.seen.count, tries, "Retry-After: 20")
        Stub.answer = { _, _ in (200, #"{"ok":true}"#) }
        tick(world, 22_000)
        let again = try XCTUnwrap(Stub.seen.last?.body)
        XCTAssertEqual(again["seq"] as? Int, first["seq"] as? Int, "the same seq")
        XCTAssertEqual((again["added"] as? [String: Int])?["turns"], 1)
        Stub.answer = { method, _ in method == "PUT" ? (401, #"{"error":"unauthorized"}"#) : (201, #"{"id":"b2","key":"k2","name":"Mochi"}"#) }
        tick(world, 22_000 + WorldLink.heartbeatMs)
        tick(world, 23_000 + WorldLink.heartbeatMs)
        XCTAssertNotEqual(calls().last, "POST /v1/buddies", "not at once")
        tick(world, 22_000 + WorldLink.heartbeatMs + WorldLink.backoffMs)
        XCTAssertEqual(calls().last, "POST /v1/buddies")
    }

    /// No rejoin storm: a 404, or a 401 that isn't the world server's own
    /// (a wrong URL, a deployment gone or protected), keeps the key and
    /// backs off; a join that fails backs off too.
    func testOnlyTheServersOwn401ForgetsTheKey() throws {
        let world = link()
        tick(world, 0)
        let key = dir.appendingPathComponent(WorldLink.fileName).path
        for (i, (status, body)) in [(404, #"{"error":"not_found"}"#), (401, "<html>Authentication Required</html>")].enumerated() {
            Stub.seen = []
            Stub.answer = { _, _ in (status, body) }
            let at = Int64(i + 1) * 100_000_000
            tick(world, at)
            tick(world, at + 1_000)
            XCTAssertEqual(calls(), ["PUT /v1/buddies/me"], "\(status): once, then it waits: \(calls())")
            XCTAssertTrue(FileManager.default.fileExists(atPath: key), "\(status): the key stays")
        }
        let fresh = WorldLink(client: WorldClient(base: URL(string: "http://world.test")!, queue: queue, protocols: [Stub.self]),
                              stateDir: try newDir())
        Stub.seen = []
        Stub.answer = { _, _ in (404, "not here") }
        tick(fresh, 0)
        tick(fresh, 1_000)
        tick(fresh, 2_000)
        XCTAssertEqual(calls(), ["POST /v1/buddies"], "a failed join waits too")
    }

    func newDir() throws -> URL {
        let d = dir.appendingPathComponent(UUID().uuidString.prefix(6).description)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// "Keep private" while the join is on its way: the buddy it makes
    /// leaves at once, and no state is ever sent.
    func testKeepingPrivateWinsOverAJoinOnItsWay() throws {
        let world = link()
        queue.sync {
            world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 0)
            world.leave(at: 0)
        }
        settle()
        tick(world, 1_000, on: false)
        XCTAssertEqual(calls(), ["POST /v1/buddies", "DELETE /v1/buddies/me"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(WorldLink.fileName).path))
    }

    /// The key file is the owner's only from the start, never more open.
    func testTheKeyIsReadableOnlyByYou() throws {
        let world = link()
        tick(world, 0)
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(WorldLink.fileName).path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(WorldLink.fileName + ".new").path))
    }

    /// Gestures in a reply that comes after you left don't play.
    func testGesturesAfterLeavingAreDropped() throws {
        let world = link()
        var events: [Event] = []
        world.onEvents = { events += $0 }
        tick(world, 0)
        queue.sync {
            world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 1_000)
            world.leave(at: 1_000)
        }
        settle()
        XCTAssertEqual(events, [], "the reply's boop, after the leave")
    }

    /// Gestures held for the morning outlive a quit.
    func testHeldGesturesOutliveAQuit() throws {
        let world = link()
        tick(world, 0)
        tick(world, 1_000, quiet: true)
        XCTAssertEqual(world.gestures.waiting.count, 1)
        let next = link()
        var events: [Event] = []
        next.onEvents = { events += $0 }
        tick(next, 2_000)
        XCTAssertEqual(events.first?["held"]?.bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(WorldLink.waitingFileName).path))
    }

    /// The screen locking sends "asleep" even with a send on its way: as
    /// soon as that one's answered. An unlock with the world off asks nothing.
    func testAsleepIsntDroppedAndTheUnlockFollowsTheSwitch() throws {
        let world = link()
        tick(world, 0)
        queue.sync {
            world.tick(Self.me, on: true, quiet: false, today: "2026-11-08", at: 1_000)
            world.sleep(Self.me, on: true, at: 1_000)
        }
        settle()
        tick(world, 2_000)
        XCTAssertEqual(Stub.seen.last?.body?["activity"] as? String, "asleep")
        Stub.seen = []
        queue.sync { world.checkGestures(on: false, quiet: false, at: 3_000) }
        settle()
        XCTAssertEqual(calls(), [])
    }
}
