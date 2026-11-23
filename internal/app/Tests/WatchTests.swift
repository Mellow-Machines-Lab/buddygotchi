import Foundation
import XCTest
@testable import BoopKit

/// Several agents (`Core+Watch`, documentation/design/screen-guide.md):
/// the screen follows one, the pips show them all, a swipe changes which,
/// and news from another is a pill.
final class WatchTests: XCTestCase {
    /// One agent: no pips. Two: a pip each, the last prompted watched, and
    /// its name for the strip's chip; idle ones hollow.
    func testThePipsAndTheWatchedAgent() {
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.wait(1000)
        XCTAssertTrue(rig.state.pips.isEmpty, "one agent: none")
        XCTAssertFalse(rig.state.jsonLine.contains("pips"))
        rig.send(.turnStart, session: "b")
        rig.wait(1000)
        let s = rig.state
        XCTAssertEqual(s.pips.map(\.kind), ["w", "w"])
        let b = rig.core.sessions.values.first { $0.id == "b" }!.key
        XCTAssertEqual(s.watch.map { rig.core.pipOrder(at: rig.now)[$0] }, b, "the last prompted")
        XCTAssertNotNil(s.watchName)
        XCTAssertTrue(s.jsonLine.contains(#""pips":"w"#), s.jsonLine)
        XCTAssertTrue(s.jsonLine.contains(#""watch":"#))
    }

    /// A swipe moves to the next agent and keeps it; a turn ending in one
    /// you aren't watching is a pill for 4 s and a pip that wants you.
    func testASwipeAndAPill() {
        XCTAssertEqual(Core.pillMs, 4000)
        let rig = CoreRig()
        rig.send(.turnStart, session: "a")
        rig.wait(1000)
        rig.send(.turnStart, session: "b")
        rig.wait(1000)
        let order = rig.core.pipOrder(at: rig.now)
        let a = rig.core.sessions.values.first { $0.id == "a" }!.key, b = rig.core.sessions.values.first { $0.id == "b" }!.key
        XCTAssertEqual(rig.core.watched(at: rig.now), b)
        rig.core.swipeAgent(by: 1, at: rig.now)
        let swiped = rig.core.watched(at: rig.now)
        XCTAssertNotEqual(swiped, b)
        XCTAssertEqual(swiped, order[(order.firstIndex(of: b)! + 1) % order.count])
        rig.wait(5000)
        XCTAssertEqual(rig.core.watched(at: rig.now), swiped, "yours until it stops working")
        let other = swiped == a ? b : a
        rig.send(.turnEnd, session: other == a ? "a" : "b")
        let pill = rig.state.pill
        XCTAssertNotNil(pill)
        XCTAssertTrue(pill?.text.hasSuffix(" waits for you") == true || pill?.text.hasSuffix(" finished") == true, "\(String(describing: pill))")
        XCTAssertEqual(rig.state.pips[order.firstIndex(of: other)!].kind, "a", "its pip wants you")
        rig.wait(Core.pillMs + 1000)
        XCTAssertNil(rig.state.pill, "gone after 4 s")
        rig.core.swipeAgent(by: 1, at: rig.now)
        XCTAssertNotEqual(rig.state.pips[order.firstIndex(of: other)!].kind, "a", "seen")
    }
}
