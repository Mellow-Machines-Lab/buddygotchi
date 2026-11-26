import Foundation
import XCTest
@testable import BoopKit

/// Several agents (`Core+Watch`, documentation/design/screen-guide.md):
/// the screen follows one, the pips show them all, a swipe changes which,
/// and news from another is a pill.
final class WatchTests: XCTestCase {
    /// One agent: no pips. Two: a pip each, the last prompted watched, and
    /// its name for its pip on the line; idle ones hollow.
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

    /// The name on the line: whole up to `maxWatchNameBytes`; longer, cut at
    /// a word where that keeps half of it, else mid-word, and always ending
    /// in "…", never a bare cut. The pill keeps its short name. With six
    /// agents, each name its longest and needing escapes, the state still
    /// fits the board's line.
    func testTheWatchedNameIsCutWithAnEllipsis() {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart, session: "a", project: "web")
        rig.wait(1000)
        rig.send(.turnStart, session: "b", project: "internal-tools-marketing-suite")
        rig.wait(1000)
        XCTAssertEqual(rig.state.watchName, "internal-tools-marketing\u{2026}", "no word end: mid-word, a dash at the cut left out")
        rig.send(.turnStart, session: "c", project: "boop-voice-fw")
        rig.wait(1000)
        XCTAssertEqual(rig.state.watchName, "boop-voice-fw", "13 bytes, whole")
        rig.send(.turnStart, session: "d", project: "the landing page and its docs")
        rig.wait(1000)
        XCTAssertEqual(rig.state.watchName, "the landing page and its\u{2026}", "at a word")
        for name in [rig.state.watchName ?? ""] {
            XCTAssertLessThanOrEqual(name.utf8.count, Core.maxWatchNameBytes)
        }
        rig.send(.turnEnd, session: "b", project: "internal-tools-marketing-suite")
        XCTAssertEqual(rig.state.pill?.text.hasPrefix("internal-too"), true, "the pill keeps its short name")

        let full = CoreRig(workStream: true)
        let quotes = String(repeating: "\"", count: 40)
        for i in 1...6 {
            full.send(.turnStart, session: "q\(i)", project: quotes + "\(i)")
            full.send(.activity, session: "q\(i)", project: quotes + "\(i)", tool: "Read", id: "r\(i)")
            full.wait(1000)
        }
        let state = full.state
        XCTAssertEqual(state.pips.count, 6)
        XCTAssertNotNil(state.watchName)
        XCTAssertTrue(state.fits, "\(state.jsonLine.utf8.count) \(state.jsonLine)")
    }

    /// The board names an agent by its project; when two work in the same
    /// project, by its thread's name, so "src" and "src" can be told apart.
    func testTwoAgentsInOneFolderGoByTheirThreads() {
        let rig = CoreRig(workStream: true)
        func start(_ session: String, _ project: String, _ name: String) {
            var e = rig.event(.turnStart, session: session, project: project)
            e.data["name"] = .string(name)
            rig.send(e)
            rig.wait(1000)
        }
        start("a", "src", "Fix the login bug")
        start("b", "api", "Write the docs")
        XCTAssertEqual(rig.state.watchName, "api", "folders apart: the folder")
        start("c", "src", "Test and polish Boop")
        XCTAssertEqual(rig.state.watchName, "Test and polish Boop", "one folder: the thread's name, whole on the line")
        XCTAssertLessThanOrEqual(rig.state.watchName?.utf8.count ?? 99, Core.maxWatchNameBytes)
        rig.send(.turnEnd, session: "a", project: "src")
        XCTAssertEqual(rig.state.pill?.text, "Fix the.. waits for you", "a chat turn, no calls")
        // A turn that only looked waits for you; one that ran the tests, its
        // one call a work act, finished. Each ends while another is watched.
        func turn(_ tool: String, topic: String? = nil) -> String? {
            rig.wait(Core.pillMs + 1000)
            rig.send(.turnStart, session: "a", project: "src")
            rig.send(.activity, session: "a", project: "src", tool: tool, topic: topic, id: "t1")
            rig.send(.activity, session: "a", project: "src", tool: tool, topic: topic, failed: false, id: "t1")
            start("c", "src", "Test and polish Boop")
            rig.send(.turnEnd, session: "a", project: "src")
            return rig.state.pill?.text
        }
        XCTAssertEqual(turn("Read"), "Fix the.. waits for you", "it only read")
        XCTAssertEqual(turn("Bash", topic: "tests"), "Fix the.. finished", "it ran the tests")
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

    /// Every agent has a colour of its own from when Boop first sees it, a
    /// resting one too, kept across turns: its lane takes that colour when
    /// it works, so pip, monitor, card and drawer row agree.
    func testEveryAgentHasItsColour() {
        let rig = CoreRig(workStream: true)
        for id in ["a", "b", "c"] {
            rig.send(.turnStart, session: id)
            rig.wait(500)
            rig.send(.turnEnd, session: id)
            rig.wait(500)
        }
        let slots = rig.state.pips.map(\.slot)
        XCTAssertEqual(slots.count, 3)
        XCTAssertFalse(slots.contains(nil), "resting ones too: \(slots)")
        XCTAssertEqual(Set(slots.compactMap { $0 }).count, 3, "each its own")
        let c = rig.core.sessions.values.first { $0.id == "c" }!.key
        let before = rig.core.slot(of: c)
        rig.send(.turnStart, session: "c")
        rig.send(.activity, session: "c", tool: "Grep", id: "t1")
        rig.wait(500)
        XCTAssertEqual(rig.core.stream.lanes[c]?.slot, before, "its lane takes its colour")
        rig.send(.turnEnd, session: "c")
        rig.wait(500)
        XCTAssertEqual(rig.core.slot(of: c), before, "and keeps it after")
    }
}
