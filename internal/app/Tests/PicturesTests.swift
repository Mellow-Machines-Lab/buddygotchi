import Foundation
import XCTest
@testable import BoopKit

/// Held pictures (`Core+Pictures`, documentation/design/screen-guide.md,
/// "Held pictures"): the watched agent's work as a live picture built from
/// the hooks, the kind of work picking which, put down once its data stops.
final class PicturesTests: XCTestCase {
    func edit(_ rig: CoreRig, _ id: String, file: String, added: Int, removed: Int = 0) {
        for failed in [nil, false] as [Bool?] {
            var e = rig.event(.activity, tool: "Edit", failed: failed, id: id)
            e.data["glimpse"] = .string(file)
            e.data["lines_added"] = .int(Int64(added))
            e.data["lines_removed"] = .int(Int64(removed))
            rig.send(e)
        }
    }

    /// Edits make the changes picture, the latest file first, lines added up
    /// over the turn; 30 s with no edit and it's put down; a new turn starts
    /// clean.
    func testTheChangesPicture() throws {
        XCTAssertEqual(Core.pictureHoldMs, 30_000)
        let rig = CoreRig()
        rig.send(.turnStart)
        XCTAssertNil(rig.state.pic, "nothing done yet")
        edit(rig, "1", file: "app/Nav.css", added: 12, removed: 3)
        rig.wait(2000)
        edit(rig, "2", file: "app/Nav.tsx", added: 22, removed: 4)
        rig.wait(2000)
        edit(rig, "3", file: "app/Nav.css", added: 36, removed: 12)
        let pic = try XCTUnwrap(rig.state.pic)
        guard case .changes(let files) = pic.picture else {
            XCTFail("\(pic)")
            return
        }
        XCTAssertEqual(files.map(\.name), ["Nav.css", "Nav.tsx"])
        XCTAssertEqual(files.map(\.added), [48, 22])
        XCTAssertEqual(files.map(\.removed), [15, 4])
        XCTAssertEqual(pic.agent, "claude")
        XCTAssertTrue(rig.state.jsonLine.contains(#""pic":["c","#), rig.state.jsonLine)
        rig.wait(31_000)
        XCTAssertNil(rig.state.pic, "no edit for 30 s: put down")
        rig.send(.turnEnd)
        rig.send(.turnStart)
        edit(rig, "4", file: "README.md", added: 12)
        guard case .changes(let again)? = rig.state.pic?.picture else {
            XCTFail("no changes")
            return
        }
        XCTAssertEqual(again.map(\.name), ["README.md"], "a new turn starts clean")
    }

    /// The changes are worth a picture only past a bar (`minChangeLines`
    /// 10, or two files), and only the project's files count: a one-line
    /// edit, or a note in /tmp, holds nothing up.
    func testTheChangesBar() {
        XCTAssertEqual(Core.minChangeLines, 10)
        let rig = CoreRig()
        rig.send(.turnStart)
        edit(rig, "1", file: "/tmp/boop-demo-notes.md", added: 40, removed: 2)
        XCTAssertNil(rig.state.pic, "a file outside the project")
        edit(rig, "2", file: "Core.swift", added: 1, removed: 1)
        XCTAssertNil(rig.state.pic, "one line is no news")
        edit(rig, "3", file: "Core.swift", added: 8)
        XCTAssertNotNil(rig.state.pic, "ten lines are")
        rig.send(.turnEnd)
        rig.send(.turnStart)
        edit(rig, "4", file: "a.swift", added: 1)
        edit(rig, "5", file: "b.swift", added: 1)
        XCTAssertNotNil(rig.state.pic, "two files are")
        XCTAssertTrue(Core.inProject("/Users/me/app/a.swift", cwd: "/Users/me/app"))
        XCTAssertFalse(Core.inProject("/Users/me/apple/a.swift", cwd: "/Users/me/app"))
    }

    /// A result is for you and shows over a picture; a status card is
    /// none.
    func testAResultOverAPicture() {
        let rig = CoreRig()
        rig.send(.turnStart)
        edit(rig, "1", file: "Core.swift", added: 15)
        XCTAssertNotNil(rig.state.pic)
        XCTAssertNil(rig.state.card)
        rig.pipeline.card(Card(kind: .result, text: "fixed"), process: nil, at: rig.now)
        rig.send(.turnEnd)
        XCTAssertEqual(rig.state.card?.text, "fixed")
        XCTAssertNil(rig.state.pic, "a turn over: no picture")
    }
}
