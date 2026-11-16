import Foundation
import MellowHarness
import XCTest
@testable import BoopDevKit
@testable import BoopKit

private let t0: Int64 = 1_790_000_000_000

/// What Boop notices of you at the Mac (`Along`, `Anchor`): each rule's
/// times and thresholds, and that its facts reach the board as tags and
/// `ptr` and nothing else.
final class AlongTests: XCTestCase {
    /// A reading every quarter second from `from` to `to`, `each` making it.
    @discardableResult
    func run(_ along: inout Along, from: Int64, to: Int64, anchor: Anchor? = nil,
             _ each: (Int64) -> Along.Reading) -> Along.Now {
        var now = Along.Now()
        var t = from
        while t <= to {
            now = along.read(each(t), anchor: anchor, at: t)
            t += Along.slotMs
        }
        return now
    }

    func reading(key: Int64? = 60_000, idle: Int64 = 0) -> Along.Reading {
        var r = Along.Reading()
        r.keyIdleMs = key
        r.idleMs = idle
        return r
    }

    let display = Anchor.Rect(x: 0, y: 0, width: 1500, height: 1000)

    /// Pins the side rule: an anchor in its display's left third puts the
    /// Mac on Boop's right (`macright`), in its right third on its left, in
    /// the middle third neither.
    func testTheSideComesFromWhereTheAnchorSits() {
        XCTAssertEqual(Anchor.sideThird, 1.0 / 3)
        XCTAssertEqual(Anchor(x: 0, y: 500, display: display).side, .right)
        XCTAssertEqual(Anchor(x: 499, y: 990, display: display).side, .right)
        XCTAssertNil(Anchor(x: 501, y: 990, display: display).side, "under the screen's middle")
        XCTAssertNil(Anchor(x: 999, y: 0, display: display).side)
        XCTAssertEqual(Anchor(x: 1001, y: 990, display: display).side, .left)
        XCTAssertEqual(Anchor(x: 1500, y: 500, display: display).side, .left)
        // On a second display to the right of the first, by its own width.
        let second = Anchor.Rect(x: 1500, y: 0, width: 2000, height: 1200)
        XCTAssertEqual(Anchor(x: 1600, y: 600, display: second).side, .right)
        XCTAssertEqual(Anchor(x: 3400, y: 600, display: second).side, .left)
        XCTAssertEqual(Anchor.Side.left.tag, "macleft")
        XCTAssertEqual(Anchor.Side.right.tag, "macright")
    }

    /// Pins the pointer's maths: the way from Boop (`standOffPt` out past
    /// the edge nearest its anchor) to the pointer, as you see the board:
    /// left is left, up is up (y down on the wire), its size growing with
    /// the distance, half way out at `kneePt`, and never past
    /// `Pointer.reach`; `near` within `nearPt` of the anchor.
    func testThePointerIsTheWayFromBoopToIt() {
        XCTAssertEqual([Anchor.standOffPt, Anchor.nearPt, Anchor.kneePt], [120, 100, 400])
        XCTAssertEqual(Pointer.reach, 10)
        // Boop on the screen's left, half way down: it stands at (-120, 500).
        let anchor = Anchor(x: 0, y: 500, display: display)
        let right = anchor.pointer(at: 1400, 500)
        XCTAssertTrue(right.x > 7 && right.y == 0 && !right.near, "\(right)")
        let up = anchor.pointer(at: -120, 0)
        XCTAssertTrue(up.x == 0 && up.y < -4, "above Boop is up: \(up)")
        let down = anchor.pointer(at: -120, 1000)
        XCTAssertTrue(down.y > 4, "\(down)")
        // At the anchor: into the screen, a little, and near.
        let at = anchor.pointer(at: 0, 500)
        XCTAssertTrue(at.near && at.x > 0 && at.x <= 3 && at.y == 0, "\(at)")
        XCTAssertFalse(anchor.pointer(at: 101, 500).near)
        // Half way out at the knee, more further, never past the reach.
        XCTAssertEqual(anchor.pointer(at: 400 - 120, 500).x, 5)
        let far = anchor.pointer(at: 100_000, -100_000)
        XCTAssertTrue(abs(far.x) <= 10 && abs(far.y) <= 10 && far.x > 6 && far.y < -6, "\(far)")
        // Boop on the right, under the screen's bottom edge: to its left is left.
        let rightSide = Anchor(x: 1400, y: 1000, display: display)
        XCTAssertTrue(rightSide.pointer(at: 200, 1100).x < -5)
        XCTAssertTrue(rightSide.pointer(at: 1400, 100).y < -5, "up the screen")
    }

    /// Pins typing fast: keys in at least 6 of the last 8 quarter seconds,
    /// read every quarter second, and only while typing at all.
    func testTypingFastIsKeysInMostQuarterSeconds() {
        XCTAssertEqual([Along.slotMs, Int64(Along.windowSlots), Int64(Along.fastSlots)], [250, 8, 6])
        // A key every quarter second: fast once six are in.
        var along = Along()
        var now = run(&along, from: t0, to: t0 + 4 * 250) { _ in self.reading(key: 10) }
        XCTAssertFalse(now.fast, "five quarter seconds in")
        now = along.read(reading(key: 10), anchor: nil, at: t0 + 5 * 250)
        XCTAssertTrue(now.fast && now.hands == .typing)
        XCTAssertEqual(now.tags, ["typingfast"])
        // Every other quarter second: typing, not fast.
        var slow = Along()
        let sometimes = run(&slow, from: t0, to: t0 + 4000) { t in self.reading(key: (t - t0) / 250 % 2 == 0 ? 10 : 260) }
        XCTAssertTrue(sometimes.hands == .typing && !sometimes.fast)
        // Fast, then a stop: not fast at once, and gone in 2 s.
        var stops = Along()
        run(&stops, from: t0, to: t0 + 3000) { _ in self.reading(key: 10) }
        let paused = run(&stops, from: t0 + 3250, to: t0 + 3750) { t in self.reading(key: t - (t0 + 3000)) }
        XCTAssertTrue(paused.hands == .typing && !paused.fast, "three quarter seconds with no key")
    }

    /// Pins sound: on once it has run 5 s, off once it has been off 3 s;
    /// watching while a player is frontmost, music otherwise, a change of
    /// kind held 3 s; none on a call.
    func testMusicAndWatchingFromSoundAndTheFrontmostApp() {
        XCTAssertEqual([Along.soundOnMs, Along.soundOffMs, Along.kindMs], [5000, 3000, 3000])
        for app in ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
                    "com.microsoft.edgemac", "com.apple.QuickTimePlayerX", "com.apple.TV", "com.colliderli.iina", "org.videolan.vlc"] {
            XCTAssertTrue(Along.players.contains(app), app)
        }
        var along = Along()
        func sound(_ on: Bool, _ front: String?) -> (Int64) -> Along.Reading {
            { _ in var r = self.reading(); r.sound = on; r.front = front; return r }
        }
        XCTAssertNil(run(&along, from: t0, to: t0 + 4750, sound(true, "com.apple.Terminal")).sound, "a short sound isn't music")
        XCTAssertEqual(along.read(sound(true, "com.apple.Terminal")(0), anchor: nil, at: t0 + 5000).sound, .music)
        // A glance at Safari doesn't turn it; three seconds there do.
        XCTAssertEqual(run(&along, from: t0 + 5250, to: t0 + 7000, sound(true, "com.apple.Safari")).sound, .music)
        XCTAssertEqual(run(&along, from: t0 + 7250, to: t0 + 8500, sound(true, "com.apple.Safari")).sound, .watching)
        XCTAssertEqual(along.read(sound(true, "com.apple.Safari")(0), anchor: nil, at: t0 + 8500).tags, ["watching"])
        // A gap between tracks: still on; three seconds off: gone.
        XCTAssertEqual(run(&along, from: t0 + 8750, to: t0 + 11_000, sound(false, "com.apple.Safari")).sound, .watching)
        XCTAssertNil(run(&along, from: t0 + 11_250, to: t0 + 12_000, sound(false, "com.apple.Safari")).sound)
        // On a call, none.
        var onCall = Along()
        let call = run(&onCall, from: t0, to: t0 + 10_000) { _ in var r = self.reading(); r.sound = true; r.camera = true; return r }
        XCTAssertTrue(call.call && call.sound == nil)
        XCTAssertEqual(call.tags, ["call"])
    }

    /// Pins the call: a camera, or the mic but for Boop's own push-to-talk,
    /// on for 5 s; off once both have been off 5 s.
    func testACallFromTheCameraOrTheMic() {
        XCTAssertEqual([Along.callOnMs, Along.callOffMs], [5000, 5000])
        func with(camera: Bool = false, mic: Bool = false, listening: Bool = false) -> (Int64) -> Along.Reading {
            { _ in var r = self.reading(); r.camera = camera; r.mic = mic; r.listening = listening; return r }
        }
        var camera = Along()
        XCTAssertFalse(run(&camera, from: t0, to: t0 + 4750, with(camera: true)).call)
        XCTAssertTrue(run(&camera, from: t0 + 5000, to: t0 + 5000, with(camera: true)).call)
        XCTAssertTrue(run(&camera, from: t0 + 5250, to: t0 + 9750, with()).call, "a moment off isn't the end")
        XCTAssertFalse(run(&camera, from: t0 + 10_000, to: t0 + 10_250, with()).call)
        var mic = Along()
        XCTAssertTrue(run(&mic, from: t0, to: t0 + 6000, with(mic: true)).call)
        var listening = Along()
        XCTAssertFalse(run(&listening, from: t0, to: t0 + 20_000, with(mic: true, listening: true)).call, "Boop's own mic")
    }

    /// Pins holding: a copy is held from the next reading until a key or a
    /// click after it, or 10 s; a copy within 2 s of the last is the same
    /// copying; the count as first read is no copy.
    func testACopyIsHeldUntilTheNextKeyOrClick() {
        XCTAssertEqual([Along.holdMs, Along.copyGapMs], [10_000, 2000])
        var along = Along()
        var r = reading(key: 60_000)
        r.clickIdleMs = 60_000
        r.copies = 41
        XCTAssertFalse(along.read(r, anchor: nil, at: t0).holding, "the count as it was")
        r.copies = 42
        r.keyIdleMs = 100  // the copy's own keys
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 250).holding)
        r.keyIdleMs = 350
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 500).holding, "no key since the copy")
        XCTAssertEqual(along.read(r, anchor: nil, at: t0 + 500).tags, ["holding"])
        r.keyIdleMs = 100  // the paste
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 1500).holding)
        // A click after it lets it go too.
        r.keyIdleMs = 60_000
        r.copies = 43
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 5000).holding)
        r.clickIdleMs = 200
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 6000).holding)
        // With no key or click, 10 s.
        r.clickIdleMs = 60_000
        r.copies = 44
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 10_000).holding)
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 19_750).holding)
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 20_000).holding)
        // Copy, copy, copy: one hold, and the next copy within 2 s of the
        // last isn't a new one.
        r.copies = 45
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 30_000).holding)
        r.keyIdleMs = 100
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 31_000).holding)
        r.keyIdleMs = 60_000
        r.copies = 46
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 31_500).holding, "1.5 s after the last copy")
        r.copies = 47
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 34_000).holding)
    }

    /// Pins the pointer's following: only with an anchor, only once it
    /// moves (2 points or more), and none 3 s after it stopped.
    func testThePointerIsFollowedWhileItMoves() {
        XCTAssertEqual(Along.pointerStillMs, 3000)
        let anchor = Anchor(x: 0, y: 500, display: display)
        func at(_ x: Double, _ y: Double) -> Along.Reading {
            var r = reading()
            r.pointerX = x
            r.pointerY = y
            return r
        }
        var along = Along()
        XCTAssertNil(along.read(at(700, 500), anchor: anchor, at: t0).pointer, "not moved yet")
        XCTAssertNil(along.read(at(701, 500), anchor: anchor, at: t0 + 250).pointer, "a point isn't a move")
        XCTAssertNotNil(along.read(at(800, 500), anchor: anchor, at: t0 + 500).pointer)
        XCTAssertNotNil(along.read(at(800, 500), anchor: anchor, at: t0 + 3250).pointer)
        XCTAssertNil(along.read(at(800, 500), anchor: anchor, at: t0 + 3500).pointer, "still 3 s")
        var none = Along()
        run(&none, from: t0, to: t0 + 1000) { t in at(Double(t - t0), 500) }
        XCTAssertNil(none.read(at(2000, 500), anchor: nil, at: t0 + 1250).pointer, "no anchor: no following")
    }

    // MARK: The runtime

    var dir: URL!

    override func setUpWithError() throws {
        try requirePack("boop")
        dir = URL(fileURLWithPath: "/tmp/boop-along-\(UUID().uuidString.prefix(8))")
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

    /// Every fact reaches the board as a tag or `ptr`, from the dev lines
    /// headless reads in the Mac's place, and nothing else: no event in the
    /// transcript, so nothing the brain, the world or the daily counts
    /// read; and none with the setting off. On a call the board is sent no
    /// volume and Boop speaks no take.
    func testWhatBoopNoticesIsTagsAndAPointerAndNothingElse() throws {
        let clock = VirtualClock(t0)
        let runtime = try makeRuntime(clock: clock)
        func snapshot() -> StateSnapshot { runtime.home.sync { runtime.core.snapshot(at: clock.now) } }
        func logged() -> Int { runtime.home.sync { runtime.harness.log.view(now: clock.now).events.count } }
        dev(runtime, #"{"dev":"advance","ms":1000}"#)
        XCTAssertFalse(snapshot().when.contains { Tags.along.contains($0) })
        let before = logged()
        dev(runtime, #"{"dev":"presence","idle_ms":0,"key_idle_ms":60000}"#)
        dev(runtime, #"{"dev":"along","scroll_idle_ms":0}"#)
        XCTAssertTrue(snapshot().when.contains("scrolling") && !snapshot().when.contains("reading"))
        dev(runtime, #"{"dev":"along","scroll_idle_ms":60000,"sound":true,"front":"com.apple.Music"}"#)
        dev(runtime, #"{"dev":"advance","ms":5000}"#)
        XCTAssertTrue(snapshot().when.contains("music"))
        dev(runtime, #"{"dev":"along","copy":true}"#)
        XCTAssertTrue(snapshot().when.contains("holding"))
        // The pointer: none until Boop knows where it sits.
        dev(runtime, #"{"dev":"along","pointer":[700,500],"display":[0,0,1500,1000]}"#)
        dev(runtime, #"{"dev":"along","pointer":[900,500]}"#)
        XCTAssertNil(snapshot().pointer)
        dev(runtime, #"{"dev":"anchor","at":[0,500]}"#)
        runtime.home.sync {}
        dev(runtime, #"{"dev":"along","pointer":[1000,500]}"#)
        let shown = try XCTUnwrap(snapshot().pointer)
        XCTAssertTrue(shown.x > 5 && shown.y == 0)
        XCTAssertTrue(snapshot().jsonLine.contains(#""ptr":[\#(shown.x),0]"#), snapshot().jsonLine)
        XCTAssertTrue(snapshot().when.contains("macright"))
        dev(runtime, #"{"dev":"advance","ms":3000}"#)
        XCTAssertNil(snapshot().pointer, "still 3 s: the eyes go back")
        XCTAssertFalse(snapshot().jsonLine.contains("ptr"))
        // A call: still, silent.
        dev(runtime, #"{"dev":"along","camera":true}"#)
        dev(runtime, #"{"dev":"advance","ms":5000}"#)
        XCTAssertTrue(snapshot().when.contains("call") && !snapshot().when.contains("music"))
        XCTAssertTrue(snapshot().jsonLine.contains(#""vol":0"#) && snapshot().vol > 0, "silent on the wire, the setting kept")
        XCTAssertTrue(runtime.home.sync { runtime.core.along.call })
        XCTAssertEqual(logged(), before, "nothing in the transcript")
        // Off in Settings: none of it.
        runtime.setTypesAlong(false)
        runtime.home.sync {}
        XCTAssertFalse(snapshot().when.contains { Tags.along.contains($0) })
        XCTAssertNil(snapshot().pointer)
        XCTAssertEqual(Tags.board.suffix(6), ["scrolling", "typingfast", "music", "watching", "call", "holding"],
                       "the newest tags last, so no pack's numbering of the others moves")
    }

    /// "Show Boop where it sits": Boop asks with its sign, the next tap is
    /// where it sits and not a poke, and it says it got it; pressed again,
    /// or with no tap in a minute, it stops waiting.
    func testShowingBoopWhereItSits() throws {
        XCTAssertEqual(Runtime.placeMs, 60_000)
        XCTAssertLessThanOrEqual(Runtime.placeSign.count, Signs.maxLength)
        let clock = VirtualClock(t0)
        let runtime = try makeRuntime(clock: clock)
        func pokes() -> Int { runtime.home.sync { runtime.harness.log.view(now: clock.now).events.filter { $0.type == .poke }.count } }
        dev(runtime, #"{"dev":"along","pointer":[1400,990],"display":[0,0,1500,1000]}"#)
        dev(runtime, #"{"dev":"anchor","place":true}"#)
        runtime.home.sync {}
        XCTAssertTrue(runtime.home.sync { runtime.placing != nil })
        dev(runtime, #"{"dev":"tap"}"#)
        XCTAssertEqual(pokes(), 0, "the tap shows where it sits: no poke")
        let anchor = try XCTUnwrap(AppSettings.load(from: dir).anchor)
        XCTAssertEqual([anchor.x, anchor.y], [1400, 990])
        XCTAssertEqual(anchor.side, .left)
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil && runtime.core.snapshot(at: clock.now).when.contains("macleft") })
        dev(runtime, #"{"dev":"tap"}"#)
        XCTAssertEqual(pokes(), 1, "the next tap is a poke again")
        // Pressed twice: it stops. Left a minute: it stops.
        runtime.showWhereBoopSits()
        runtime.showWhereBoopSits()
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil })
        runtime.showWhereBoopSits()
        dev(runtime, #"{"dev":"advance","ms":60000}"#)
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil })
    }
}
