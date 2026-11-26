import Foundation
import LinkKit
import XCTest
@testable import BoopKit

/// The show on the board (documentation/design/screen-guide.md, "The
/// show"): the picture coded for the board (`ShowPicture`), the show the
/// board holds up and for how long (`Core.boardShow`), and its picture's
/// way there as a blob (`ShowBlobs`).
final class ShowBoardTests: XCTestCase {
    let svg = """
        <svg viewBox="0 0 420 190" xmlns="http://www.w3.org/2000/svg">\
        <rect x="20" y="40" width="60" height="126" fill="#9aa0a8"/>\
        <rect x="84" y="106" width="60" height="60" fill="currentColor"/>\
        <rect x="200" y="20" width="100" height="40" fill="#5fae5a"/>\
        </svg>
        """

    /// Runs code a picture: a byte a run of up to 15, two for 16 to 271,
    /// and decoding gives back every pixel.
    func testRunsCodeAPicture() throws {
        var picture = [UInt8](repeating: 0, count: Show.width * Show.height)
        for i in 1000..<1003 { picture[i] = 1 }  // 3: one byte
        for i in 2000..<2040 { picture[i] = 6 }  // 40: two
        let coded = ShowPicture.encode(picture)
        XCTAssertEqual(ShowPicture.decode(coded), picture)
        let empty = ShowPicture.encode([UInt8](repeating: 0, count: Show.width * Show.height))
        XCTAssertEqual(empty.count, 2 * Int((Double(Show.width * Show.height) / 271).rounded(.up)), "an empty picture is small")
        XCTAssertNil(ShowPicture.decode(Data([0x0F])), "a run cut short")
        XCTAssertNil(ShowPicture.decode(Data([0x00])), "a picture cut short")
    }

    /// An SVG is drawn at the board's pixels in the show's colours: its
    /// `currentColor` the lane's, each fill its own, the rest none.
    func testAnSVGIsDrawnInTheShowsColours() throws {
        let picture = try XCTUnwrap(ShowPicture.indices(Show(headline: "p95 is 2x faster", svg: svg)))
        func at(_ x: Int, _ y: Int) -> UInt8 { picture[y * Show.width + x] }
        XCTAssertEqual(at(50, 100), 2, "dim")
        XCTAssertEqual(at(110, 130), UInt8(ShowPicture.lane), "currentColor is the lane's")
        XCTAssertEqual(at(250, 40), 3, "good")
        XCTAssertEqual(at(10, 10), 0, "nothing drawn: none")
        let bytes = try XCTUnwrap(ShowPicture.bytes(Show(headline: "p95", svg: svg)))
        XCTAssertLessThan(bytes.count, 2000)
        XCTAssertEqual(ShowPicture.decode(bytes), picture)
    }

    /// The board holds a show up from when it comes until 30 s after its
    /// turn ends; another waiting takes its place after 8 s; the screen
    /// follows a show's agent while it's up.
    func testTheBoardHoldsAShowUp() throws {
        XCTAssertEqual([Core.boardShowMs, Core.boardShowLeastMs], [30_000, 8_000])
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart, session: "a", project: "api")
        rig.send(.turnStart, session: "b", project: "web")
        rig.wait(1000)
        let a = try XCTUnwrap(rig.core.sessions.values.first { $0.id == "a" }).key
        XCTAssertNotEqual(rig.core.watched(at: rig.now), a, "b was prompted last")
        // a's agent shows, the only one with a process to match: give it a's.
        rig.core.boardShows = []
        rig.core.queueBoardShow(Show(headline: "api is 2x faster", svg: svg), key: a, agent: "claude", working: true, at: rig.now)
        rig.wait(1000)
        XCTAssertEqual(rig.state.show?.headline, "api is 2x faster")
        XCTAssertEqual(rig.core.watched(at: rig.now), a, "a show takes the screen")
        XCTAssertTrue(rig.state.jsonLine.contains(#""show":{"i":"#), rig.state.jsonLine)
        rig.wait(60_000)
        XCTAssertNotNil(rig.state.show, "held while its turn works")
        rig.send(.turnEnd, session: "a", project: "api")
        rig.wait(29_000)
        XCTAssertNotNil(rig.state.show)
        rig.wait(2_000)
        XCTAssertNil(rig.state.show, "30 s after its turn ended")
        // Its agent quits right after: the show keeps its 30 s.
        rig.core.queueBoardShow(Show(headline: "bye", svg: svg), key: a, agent: "claude", working: true, at: rig.now)
        rig.send(.turnEnd, session: "a", project: "api")
        rig.send(.sessionEnd, session: "a", project: "api")
        rig.wait(20_000)
        XCTAssertEqual(rig.state.show?.headline, "bye", "its session has gone")
        rig.wait(11_000)
        XCTAssertNil(rig.state.show)
        // Two at once: the first 8 s, then the next.
        let b = try XCTUnwrap(rig.core.sessions.values.first { $0.id == "b" }).key
        rig.core.queueBoardShow(Show(headline: "one", svg: svg), key: b, agent: "claude", working: false, at: rig.now)
        rig.core.queueBoardShow(Show(headline: "two", svg: svg), key: b, agent: "claude", working: false, at: rig.now)
        rig.wait(1000)
        XCTAssertEqual(rig.state.show?.headline, "one")
        rig.wait(8000)
        XCTAssertEqual(rig.state.show?.headline, "two")
    }

    /// A show's 30 s pass only while the board can hold it up: not under a
    /// Moment of the Mac's (`Core.boardBusy`, the finish and its invite that
    /// follow a turn), nor while something needs you, which both cover it.
    func testAShowSpendsItsTimeOnlyWhileTheBoardIsFree() throws {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart, session: "a", project: "api")
        rig.send(.turnStart, session: "b", project: "web")
        rig.wait(1000)
        let a = try XCTUnwrap(rig.core.sessions.values.first { $0.id == "a" }).key
        rig.core.boardShows = []
        rig.core.queueBoardShow(Show(headline: "api is 2x faster", svg: svg), key: a, agent: "claude", working: true, at: rig.now)
        rig.core.boardBusy = true  // the finish and its invite play on the board
        rig.send(.turnEnd, session: "a", project: "api")
        rig.wait(40_000)
        XCTAssertEqual(rig.state.show?.headline, "api is 2x faster", "no time spent under a Moment")
        rig.core.boardBusy = false
        rig.wait(10_000)
        XCTAssertNotNil(rig.state.show, "10 s of its 30 spent")
        rig.send(.needsYou, session: "b", tool: "Bash")
        XCTAssertNil(rig.state.show, "left out while something needs you")
        rig.wait(40_000)
        rig.send(.turnEnd, session: "b", project: "web")
        XCTAssertNotNil(rig.state.show, "back, with 20 s left: none spent under needs you")
        rig.wait(19_000)
        XCTAssertNotNil(rig.state.show)
        rig.wait(2_000)
        XCTAssertNil(rig.state.show, "its 30 s up")
    }

    /// The picture goes as a blob once, and again after 6 s when it hasn't
    /// come; the state names it once the board has it; a new show or a
    /// board that said hello starts again.
    func testThePictureGoesAsABlob() throws {
        final class Sink: Transport, @unchecked Sendable {
            var lines: [String] = []
            var name: String { "sink" }
            func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {}
            func send(_ line: String) { lines.append(line) }
            func reconnect() {}
            func stop() {}
        }
        let sink = Sink()
        let link = DeviceLink(app: "boop", transport: sink)
        link.connection(true, now: 0)
        var blobs = ShowBlobs()
        let show = Core.BoardShow(id: 3, key: "k", show: Show(headline: "h", svg: svg), agent: "claude", at: 0, clockAt: 0)
        let fields: JSONObject = ["t": "state", "show": ["i": 3, "h": "h", "a": 0, "g": "claude"]]
        var drawn = 0
        let picture: (Show) -> Data? = { _ in drawn += 1; return Data([0x0F, 0xFF]) }
        func parts() -> [String] { sink.lines.filter { $0.hasPrefix(#"{"t":"blob""#) } }
        var out = blobs.fields(fields, show: show, link: link, now: 0, picture: picture)
        XCTAssertEqual(parts().count, 1)
        XCTAssertNil(out["show"]?.object?["b"], "not there yet")
        XCTAssertFalse(blobs.due(at: 5_999))
        XCTAssertTrue(blobs.due(at: 6_000))
        out = blobs.fields(fields, show: show, link: link, now: 6_000, picture: picture)
        XCTAssertEqual(parts().count, 2, "sent again")
        XCTAssertEqual(drawn, 1, "drawn once")
        let id = try XCTUnwrap(JSON.parse(parts()[1])?.object?["id"]?.int)
        XCTAssertFalse(blobs.arrived(id + 1))
        XCTAssertTrue(blobs.arrived(id))
        out = blobs.fields(fields, show: show, link: link, now: 7_000, picture: picture)
        XCTAssertEqual(out["show"]?.object?["b"]?.int, id)
        XCTAssertFalse(blobs.due(at: 60_000))
        blobs.forget()
        XCTAssertTrue(blobs.due(at: 60_000), "a board that said hello has lost it")
        out = blobs.fields(["t": "state"], show: nil, link: link, now: 61_000, picture: picture)
        XCTAssertFalse(blobs.due(at: 70_000), "no show, nothing to send")
    }
}
