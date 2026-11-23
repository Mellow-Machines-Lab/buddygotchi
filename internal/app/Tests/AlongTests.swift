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
             _ each: (Int64) -> Along.Facts) -> Along.Now {
        var now = Along.Now()
        var t = from
        while t <= to {
            now = along.read(each(t), anchor: anchor, at: t)
            t += Along.slotMs
        }
        return now
    }

    func reading(key: Int64? = 60_000, idle: Int64 = 0) -> Along.Facts {
        var r = Along.Facts()
        r.keyIdleMs = key
        r.idleMs = idle
        return r
    }

    let display = Anchor.Rect(x: 0, y: 0, width: 1500, height: 1000)

    /// Pins the side rule: an anchor in its display's left third puts the
    /// Mac on Boop's right (`macright`), in its right third on its left, in
    /// the middle third up (`macup`: Boop sits under the screen).
    func testTheSideComesFromWhereTheAnchorSits() {
        XCTAssertEqual(Anchor.sideThird, 1.0 / 3)
        XCTAssertEqual(Anchor(x: 0, y: 500, display: display).side, .right)
        XCTAssertEqual(Anchor(x: 499, y: 990, display: display).side, .right)
        XCTAssertEqual(Anchor(x: 501, y: 990, display: display).side, .up, "under the screen's middle")
        XCTAssertEqual(Anchor(x: 999, y: 0, display: display).side, .up)
        XCTAssertEqual(Anchor(x: 1001, y: 990, display: display).side, .left)
        XCTAssertEqual(Anchor(x: 1500, y: 500, display: display).side, .left)
        // On a second display to the right of the first, by its own width.
        let second = Anchor.Rect(x: 1500, y: 0, width: 2000, height: 1200)
        XCTAssertEqual(Anchor(x: 1600, y: 600, display: second).side, .right)
        XCTAssertEqual(Anchor(x: 3400, y: 600, display: second).side, .left)
        XCTAssertEqual(Anchor.Side.left.tag, "macleft")
        XCTAssertEqual(Anchor.Side.right.tag, "macright")
        XCTAssertEqual(Anchor.Side.up.tag, "macup")
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
    /// read every quarter second, and only while typing at all; once fast,
    /// fast until keys come in 3 of them or fewer, or 1 s below 6, so a
    /// flicker at the edge isn't one.
    func testTypingFastIsKeysInMostQuarterSeconds() {
        XCTAssertEqual([Along.slotMs, Int64(Along.windowSlots), Int64(Along.fastSlots), Int64(Along.slowSlots), Along.slowMs],
                       [250, 8, 6, 3, 1000])
        // A key every quarter second: fast once six are in.
        var along = Along()
        var now = run(&along, from: t0, to: t0 + 4 * 250) { _ in self.reading(key: 10) }
        XCTAssertFalse(now.fast, "five quarter seconds in")
        now = along.read(reading(key: 10), anchor: nil, at: t0 + 5 * 250)
        XCTAssertTrue(now.fast && now.hands == .typing)
        XCTAssertEqual(now.tags, ["typing", "typingfast"])
        // Every other quarter second: typing, not fast.
        var slow = Along()
        let sometimes = run(&slow, from: t0, to: t0 + 4000) { t in self.reading(key: (t - t0) / 250 % 2 == 0 ? 10 : 260) }
        XCTAssertTrue(sometimes.hands == .typing && !sometimes.fast)
        // Fast, then every other quarter second: still fast a while (a
        // flicker at the edge), and not once it's been a second below six.
        var edge = Along()
        run(&edge, from: t0, to: t0 + 3000) { _ in self.reading(key: 10) }
        let half = { (t: Int64) in self.reading(key: (t - t0) / 250 % 2 == 0 ? 260 : 10) }
        XCTAssertTrue(run(&edge, from: t0 + 3250, to: t0 + 4500, half).fast, "four or five of eight: still fast")
        XCTAssertFalse(run(&edge, from: t0 + 4750, to: t0 + 5500, half).fast, "three of eight, or a second below six")
        // Five of eight for a second: not fast any more.
        var five = Along()
        run(&five, from: t0, to: t0 + 3000) { _ in self.reading(key: 10) }
        let twoOfThree = { (t: Int64) in self.reading(key: (t - t0) / 250 % 3 == 0 ? 260 : 10) }
        XCTAssertTrue(run(&five, from: t0 + 3250, to: t0 + 3750, twoOfThree).fast)
        XCTAssertFalse(run(&five, from: t0 + 4000, to: t0 + 6000, twoOfThree).fast, "a second below six")
        // Fast, then a stop: not fast once three or fewer are left.
        var stops = Along()
        run(&stops, from: t0, to: t0 + 3000) { _ in self.reading(key: 10) }
        let paused = run(&stops, from: t0 + 3250, to: t0 + 4250) { t in self.reading(key: t - (t0 + 3000)) }
        XCTAssertTrue(paused.hands == .typing && !paused.fast)
    }

    func sounding(_ who: String, front: String?) -> (Int64) -> Along.Facts {
        { _ in
            var f = self.reading()
            f.frontSound = who == "front"
            f.otherSound = who == "other"
            f.front = front
            return f
        }
    }

    /// Pins sound: on once it has played 5 s, off once it has been off 3 s;
    /// a video only while the frontmost app is a player and plays it itself,
    /// music from any other app (or a frontmost one that isn't a player), a
    /// change of kind held 3 s; none on a call.
    func testMusicAndVideoFromWhoPlaysIt() {
        XCTAssertEqual([Along.soundOnMs, Along.soundOffMs, Along.kindMs], [5000, 3000, 3000])
        for app in ["com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
                    "com.microsoft.edgemac", "com.apple.QuickTimePlayerX", "com.apple.TV", "com.colliderli.iina", "org.videolan.vlc"] {
            XCTAssertTrue(Along.players.contains(app), app)
        }
        var along = Along()
        XCTAssertNil(run(&along, from: t0, to: t0 + 4750, sounding("other", front: "com.apple.Safari")).sound, "a short sound isn't music")
        XCTAssertEqual(along.read(sounding("other", front: "com.apple.Safari")(0), anchor: nil, at: t0 + 5000).sound, .music,
                       "Safari in front, the music from another app")
        // Safari in front plays itself: a video, after three seconds of it.
        XCTAssertEqual(run(&along, from: t0 + 5250, to: t0 + 7000, sounding("front", front: "com.apple.Safari")).sound, .music)
        XCTAssertEqual(run(&along, from: t0 + 7250, to: t0 + 8500, sounding("front", front: "com.apple.Safari")).sound, .video)
        XCTAssertEqual(along.read(sounding("front", front: "com.apple.Safari")(0), anchor: nil, at: t0 + 8500).tags, ["reading", "video"])
        // A gap: still on; three seconds off: gone.
        XCTAssertEqual(run(&along, from: t0 + 8750, to: t0 + 11_000, sounding("none", front: "com.apple.Safari")).sound, .video)
        XCTAssertNil(run(&along, from: t0 + 11_250, to: t0 + 12_000, sounding("none", front: "com.apple.Safari")).sound)
        // A player that isn't frontmost, or an app in front that isn't one: music.
        var music = Along()
        XCTAssertEqual(run(&music, from: t0, to: t0 + 6000, sounding("front", front: "com.spotify.client")).sound, .music)
        // On a call, none.
        var onCall = Along()
        let call = run(&onCall, from: t0, to: t0 + 10_000) { _ in var r = self.reading(); r.otherSound = true; r.camera = true; return r }
        XCTAssertTrue(call.onCall && call.sound == nil)
        XCTAssertEqual(call.tags, ["reading", "oncall"])
    }

    /// Pins the call: a camera, or another app recording sound (never
    /// Boop's own push-to-talk, which the Mac leaves out), on for 5 s; off
    /// once both have been off 5 s.
    func testACallFromTheCameraOrAnotherAppsMic() {
        XCTAssertEqual([Along.callOnMs, Along.callOffMs], [5000, 5000])
        func with(camera: Bool = false, mic: Bool = false) -> (Int64) -> Along.Facts {
            { _ in var r = self.reading(); r.camera = camera; r.otherInput = mic; return r }
        }
        var camera = Along()
        XCTAssertFalse(run(&camera, from: t0, to: t0 + 4750, with(camera: true)).onCall)
        XCTAssertTrue(run(&camera, from: t0 + 5000, to: t0 + 5000, with(camera: true)).onCall)
        XCTAssertTrue(run(&camera, from: t0 + 5250, to: t0 + 9750, with()).onCall, "a moment off isn't the end")
        XCTAssertFalse(run(&camera, from: t0 + 10_000, to: t0 + 10_250, with()).onCall)
        var mic = Along()
        XCTAssertTrue(run(&mic, from: t0, to: t0 + 6000, with(mic: true)).onCall)
    }

    /// Pins a copy: from the next reading until a key or a click after it,
    /// or 10 s; a copy within 2 s of the last is the same copying; the
    /// count as first read is no copy.
    func testACopyLastsUntilTheNextKeyOrClick() {
        XCTAssertEqual([Along.copiedMs, Along.copyGapMs], [10_000, 2000])
        var along = Along()
        var r = reading(key: 60_000)
        r.clickIdleMs = 60_000
        r.copies = 41
        XCTAssertFalse(along.read(r, anchor: nil, at: t0).copied, "the count as it was")
        r.copies = 42
        r.keyIdleMs = 100  // the copy's own keys
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 250).copied)
        r.keyIdleMs = 350
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 500).copied, "no key since the copy")
        XCTAssertEqual(along.read(r, anchor: nil, at: t0 + 500).tags, ["typing", "copied"])
        r.keyIdleMs = 100  // the paste
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 1500).copied)
        r.keyIdleMs = 60_000
        r.copies = 43
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 5000).copied)
        r.clickIdleMs = 200
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 6000).copied, "a click lets it go too")
        r.clickIdleMs = 60_000
        r.copies = 44
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 10_000).copied)
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 19_750).copied)
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 20_000).copied, "10 s")
        r.copies = 45
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 30_000).copied)
        r.keyIdleMs = 100
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 31_000).copied)
        r.keyIdleMs = 60_000
        r.copies = 46
        XCTAssertFalse(along.read(r, anchor: nil, at: t0 + 31_500).copied, "1.5 s after the last copy")
        r.copies = 47
        XCTAssertTrue(along.read(r, anchor: nil, at: t0 + 34_000).copied)
    }

    /// Pins the pointer's following: only with an anchor, only once it
    /// moves (2 points or more), and none 3 s after it stopped.
    func testThePointerIsFollowedWhileItMoves() {
        XCTAssertEqual(Along.pointerStillMs, 3000)
        let anchor = Anchor(x: 0, y: 500, display: display)
        func at(_ x: Double, _ y: Double) -> Along.Facts {
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
        dev(runtime, #"{"dev":"along","scroll_idle_ms":60000,"sound":"other","front":"com.apple.Terminal"}"#)
        dev(runtime, #"{"dev":"advance","ms":5000}"#)
        XCTAssertTrue(snapshot().when.contains("music"))
        dev(runtime, #"{"dev":"along","copy":true}"#)
        XCTAssertTrue(snapshot().when.contains("copied"))
        // The pointer: none until Boop knows where it sits.
        dev(runtime, #"{"dev":"along","pointer":[700,500],"display":[0,0,1500,1000]}"#)
        dev(runtime, #"{"dev":"along","pointer":[900,500]}"#)
        XCTAssertNil(snapshot().pointer)
        dev(runtime, #"{"dev":"anchor","at":[0,500]}"#)
        runtime.home.sync {}
        dev(runtime, #"{"dev":"along","pointer":[1000,500]}"#)
        // A move of the pointer alone is a `state` and nothing more: no status.
        var statuses = 0
        runtime.onChange = { _ in statuses += 1 }
        dev(runtime, #"{"dev":"along","pointer":[1000,500]}"#)
        runtime.home.sync {}
        XCTAssertEqual(statuses, 0, "the popover isn't told of the pointer")
        XCTAssertNotNil(runtime.home.sync { runtime.latest?.pointer }, "the board is")
        // Two moves within a quarter second: the second waits for the next.
        let first = try XCTUnwrap(snapshot().pointer)
        dev(runtime, #"{"dev":"along","pointer":[100,100]}"#)
        XCTAssertEqual(snapshot().pointer, first, "at most 4 a second")
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
        XCTAssertTrue(snapshot().when.contains("oncall") && !snapshot().when.contains("music"))
        XCTAssertTrue(snapshot().jsonLine.contains(#""vol":0"#) && snapshot().vol > 0, "silent on the wire, the setting kept")
        XCTAssertTrue(runtime.home.sync { runtime.core.along.onCall })
        // Every Moment small on a call: once, and no finish sized by its turn.
        let calmed = runtime.home.sync { runtime.calmed(Moment(anim: "task_complete", loops: 3, outcome: "success", turn: 3)) }
        XCTAssertEqual(calmed.loops, 1)
        XCTAssertEqual(calmed.turn, 0)
        XCTAssertEqual(logged(), before, "nothing in the transcript")
        // Off in Settings: none of it.
        runtime.setNoticesYou(false)
        runtime.home.sync {}
        XCTAssertFalse(snapshot().when.contains { Tags.along.contains($0) })
        XCTAssertNil(snapshot().pointer)
        XCTAssertEqual(Tags.board.suffix(7), ["scrolling", "typingfast", "music", "video", "oncall", "copied", "macup"],
                       "the newest tags last, so no pack's numbering of the others moves")
    }

    /// The logs and a bug report keep no timeline of you at the Mac: a
    /// `state` as they keep it has no pointer and none of the tags of what
    /// you scroll, play, record or copy; the rest is as it was.
    func testTheLogsKeepNoTimelineOfYou() {
        let line = #"{"t":"state","base":"idle","mood":"calm","busy":0,"vol":0,"when":["day","typing","scrolling","music","oncall","copied","macup"],"ptr":[-3,4,1],"xp":2}"#
        XCTAssertEqual(StateSnapshot.unnoticed(line),
                       #"{"t":"state","base":"idle","mood":"calm","busy":0,"vol":0,"when":["day","typing","macup"],"xp":2}"#)
        XCTAssertEqual(StateSnapshot.unnoticed(#"{"t":"state","base":"idle","when":["video"]}"#), #"{"t":"state","base":"idle"}"#)
        let other = #"{"t":"do","id":3,"name":"call","args":{"w":"music"}}"#
        XCTAssertEqual(StateSnapshot.unnoticed(other), other)
        XCTAssertEqual(StateSnapshot.unloggedTags, Tags.along)
    }

    /// "Show Boop where it sits": Boop asks with its sign, the next touch on
    /// its face (a tap, a nose boop, a stroke, a lean) is where it sits and
    /// not a poke, care or a pass, and it says it got it; pressed again,
    /// with no tap in a minute, or with noticing turned off, it stops
    /// waiting.
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
        // A nose boop or a stroke on its face is the touch too.
        func touches() -> Int {
            runtime.home.sync { runtime.harness.log.view(now: clock.now).events.filter { $0.type == .poke || $0.type == .gesture }.count }
        }
        for kind in ["nose", "ruffle", "lean"] {
            runtime.showWhereBoopSits()
            dev(runtime, #"{"dev":"along","pointer":[700,990]}"#)
            let was = touches()
            runtime.home.sync { runtime.gestured(kind) }
            XCTAssertEqual(touches(), was, "\(kind) is no touch then")
            XCTAssertTrue(runtime.home.sync { runtime.placing == nil }, kind)
            XCTAssertEqual(AppSettings.load(from: dir).anchor?.x, 700, kind)
            dev(runtime, #"{"dev":"along","pointer":[1400,990]}"#)
        }
        XCTAssertEqual(AppSettings.load(from: dir).anchor?.side, .up, "under the screen's middle: up")
        // Noticing turned off: no more waiting, and nothing to wait for.
        runtime.showWhereBoopSits()
        runtime.setNoticesYou(false)
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil })
        runtime.showWhereBoopSits()
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil }, "off: it doesn't ask")
        runtime.setNoticesYou(true)
        // Pressed twice: it stops. Left a minute: it stops.
        runtime.showWhereBoopSits()
        runtime.showWhereBoopSits()
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil })
        runtime.showWhereBoopSits()
        dev(runtime, #"{"dev":"advance","ms":60000}"#)
        XCTAssertTrue(runtime.home.sync { runtime.placing == nil })
    }
}
