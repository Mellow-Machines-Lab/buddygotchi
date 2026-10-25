@testable import BoopKit
import AgentHooks
import Foundation
import LinkKit
import XCTest

/// The board's agents' drawer, on the Mac: the rows its state lists while
/// the board says it's open (`Core.list`), and a picked row opening its
/// session's thread (`Core.pick`); and the popover's rows' own facts.
final class DrawerTests: XCTestCase {
    /// Three sessions: s1 asking for permission, s2 working, s3 idle.
    func three(_ rig: CoreRig) {
        rig.send(.turnStart, session: "s3", project: "notes")
        rig.wait(1000)
        rig.send(.turnEnd, session: "s3", project: "notes")
        rig.send(.turnStart, .codex, session: "s2", project: "buddygotchi")
        rig.send(.turnStart, session: "s1", project: "landing")
        rig.send(.needsYou, session: "s1", project: "landing", tool: "Bash")
    }

    /// Shut, the state lists nothing; open, every session, what needs you
    /// first, then those working, then those resting; and shut again,
    /// nothing. It's open only while the board says so within
    /// `drawerQuietMs` (25 s): it says so again every 10 s, and a board
    /// that restarted with it open never says it shut.
    func testTheStateListsTheSessionsWhileTheDrawerIsOpen() throws {
        let rig = CoreRig()
        three(rig)
        XCTAssertNil(rig.state.list)
        XCTAssertFalse(rig.state.jsonLine.contains(#""list""#))
        rig.pipeline.drawer(open: true, at: rig.now)
        let list = try XCTUnwrap(rig.state.list)
        XCTAssertEqual(list.map(\.status), ["n", "w", "i"])
        XCTAssertEqual(list.map(\.title), ["landing", "buddygotchi", "notes"])
        XCTAssertEqual(list.map(\.agent), ["claude", "codex", "claude"])
        XCTAssertEqual(Set(list.map(\.id)).count, 3)
        XCTAssertEqual(rig.state.unlisted, 0)
        XCTAssertEqual(Core.drawerQuietMs, 25_000)
        rig.wait(Core.drawerQuietMs - 1000)
        XCTAssertNotNil(rig.state.list)
        rig.wait(1000)
        XCTAssertNil(rig.state.list, "a board that went quiet")
        rig.pipeline.drawer(open: true, at: rig.now)
        XCTAssertNotNil(rig.state.list)
        rig.pipeline.drawer(open: false, at: rig.now)
        XCTAssertNil(rig.state.list)
    }

    /// Open with nothing to list, it sends an empty list, so the board
    /// knows the Mac heard.
    func testAnEmptyDrawerSaysSo() {
        let rig = CoreRig()
        rig.pipeline.drawer(open: true, at: rig.now)
        XCTAssertTrue(rig.state.jsonLine.contains(#""list":[]"#), rig.state.jsonLine)
    }

    /// A row on the wire: `[id, status, slot, agent, title, project]`, the
    /// thread's name the title when it has one and its project after it,
    /// else the project; a working session's lane slot, -1 for none. The
    /// work stream's lanes wait while it's open, as it covers them.
    func testARowOnTheWire() throws {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart, session: "s1", project: "landing")
        rig.send(.activity, session: "s1", project: "landing", tool: "Grep")
        XCTAssertTrue(rig.state.jsonLine.contains(#""calls""#))
        rig.pipeline.drawer(open: true, at: rig.now)
        let row = try XCTUnwrap(rig.state.list?.first)
        XCTAssertEqual(row.slot, 0)
        XCTAssertTrue(rig.state.jsonLine.contains(#""list":[[\#(row.id),"w",0,"claude","landing",""]]"#), rig.state.jsonLine)
        XCTAssertFalse(rig.state.jsonLine.contains(#""calls""#))
        let named = StateSnapshot.Row(id: 9, status: "i", agent: "codex", title: "Hero copy", project: "landing")
        var snapshot = StateSnapshot(base: "idle", mood: "calm", attn: nil, busy: 0, vol: 0, list: [named], unlisted: 2)
        XCTAssertEqual(snapshot.jsonLine,
                       #"{"t":"state","base":"idle","mood":"calm","busy":0,"vol":0,"list":[[9,"i",-1,"codex","Hero copy","landing"]],"unlisted":2}"#)
        snapshot.list = nil
        XCTAssertFalse(snapshot.jsonLine.contains("unlisted\":2,"))
    }

    /// The state sends six rows at most (`maxRows`, the board's screenful
    /// and the row peeking under it), and says how many more there are
    /// (`unlisted`). Long names are cut shorter (`rowCuts`) so all six fit
    /// the board's line (`Wire.maxLine`) with a request showing; however
    /// long and however escaped they are, the line fits, dropping rows to
    /// `unlisted` only once the shortest cut won't do.
    func testTheRowsFitTheBoard() throws {
        let long = CoreRig(workStream: true)
        for i in 1...7 { long.send(.turnStart, session: "l\(i)", project: "a-project-whose-name-runs-long-\(i)") }
        long.send(.needsYou, session: "l1", project: "a-project-whose-name-runs-long-1", tool: "Bash")
        long.pipeline.drawer(open: true, at: long.now)
        XCTAssertEqual(long.state.list?.count, StateSnapshot.maxRows, long.state.jsonLine)
        XCTAssertTrue(long.state.fits, "\(long.state.jsonLine.utf8.count) \(long.state.jsonLine)")
        XCTAssertEqual(Core.rowCuts.first?.title, StateSnapshot.maxTitleBytes)
        XCTAssertEqual(Core.rowCuts.last?.project, 0)

        let rig = CoreRig(workStream: true)
        for i in 1...6 { rig.send(.turnStart, session: "s\(i)", project: "p\(i)") }
        rig.pipeline.drawer(open: true, at: rig.now)
        XCTAssertEqual(StateSnapshot.maxRows, 6)
        XCTAssertEqual(rig.state.list?.count, 6)
        XCTAssertEqual(rig.state.unlisted, 0)
        rig.send(.turnStart, session: "s7", project: "p7")
        XCTAssertEqual(rig.state.list?.count, 6)
        XCTAssertEqual(rig.state.unlisted, 1)
        let quotes = String(repeating: "\"", count: 60)
        for i in 1...6 { rig.send(.turnStart, .codex, session: "q\(i)", project: quotes + "\(i)") }
        rig.send(.needsYou, .codex, session: "q1", project: quotes + "1", tool: "Bash")
        let state = rig.state
        XCTAssertTrue(state.fits, "\(state.jsonLine.utf8.count)")
        XCTAssertTrue(state.jsonLine.utf8.count < Wire.maxLine)
        XCTAssertEqual((state.list?.count ?? 0) + state.unlisted, 13)
        for row in state.list ?? [] {
            XCTAssertTrue(row.title.utf8.count <= StateSnapshot.maxTitleBytes)
            XCTAssertTrue(row.project.utf8.count <= StateSnapshot.maxProjectBytes)
        }
    }

    /// The board asks for the rows from where it has scrolled to (`from`):
    /// the state lists them from there, `skip` saying how many come before,
    /// or from as near it as still fills `maxRows`, near the end. Asked
    /// again or shut and opened, from the top.
    func testTheRowsComeFromWhereTheBoardScrolled() throws {
        let rig = CoreRig()
        for i in 1...12 { rig.send(.turnStart, session: "s\(i)", project: "p\(i)") }
        rig.pipeline.drawer(open: true, at: rig.now)
        let top = try XCTUnwrap(rig.state.list).map(\.id)
        XCTAssertEqual(rig.state.skip, 0)
        XCTAssertEqual(rig.state.unlisted, 6)
        XCTAssertFalse(rig.state.jsonLine.contains(#""skip""#))
        rig.pipeline.drawer(open: true, from: 3, at: rig.now)
        let window = try XCTUnwrap(rig.state.list).map(\.id)
        XCTAssertEqual([rig.state.skip, window.count, rig.state.unlisted], [3, 6, 3])
        XCTAssertEqual(Array(window.prefix(3)), Array(top.suffix(3)))
        XCTAssertTrue(rig.state.jsonLine.contains(#"]],"skip":3,"unlisted":3}"#), rig.state.jsonLine)
        rig.pipeline.drawer(open: true, from: 10, at: rig.now)
        XCTAssertEqual([rig.state.skip, rig.state.list?.count ?? 0, rig.state.unlisted], [6, 6, 0])
        rig.pipeline.drawer(open: false, at: rig.now)
        rig.pipeline.drawer(open: true, at: rig.now)
        XCTAssertEqual(rig.state.skip, 0)
    }

    /// The board's `open`: the row it asks for from, 0 for none.
    func testTheOpenOnTheWire() {
        func from(_ line: String) -> Int? {
            guard case .event(let ev) = Wire.decode(line) else { return nil }
            return BoopDevice.rows(from: ev)
        }
        XCTAssertEqual(from(#"{"t":"ev","kind":"drawer","did":"open","data":{"from":7}}"#), 7)
        XCTAssertEqual(from(#"{"t":"ev","kind":"drawer","did":"open"}"#), 0)
        XCTAssertEqual(from(#"{"t":"ev","kind":"drawer","did":"open","data":{"from":-2}}"#), 0)
    }

    /// A picked row opens its session's thread, recorded as `open_thread`
    /// by the drawer; a number no session has opens nothing. Numbers are
    /// kept while their sessions are, and count up from where the launch's
    /// requests do.
    func testAPickedRowOpensItsThread() throws {
        let rig = CoreRig()
        three(rig)
        rig.pipeline.drawer(open: true, at: rig.now)
        let list = try XCTUnwrap(rig.state.list)
        let codex = try XCTUnwrap(list.first { $0.agent == "codex" })
        let fx = rig.note(Fx(rig.pipeline.pick(row: codex.id, at: rig.now)))
        let opened = fx.effects.compactMap { if case .open(let thread) = $0 { thread } else { nil } }
        XCTAssertEqual(opened.map(\.agent), ["codex"])
        XCTAssertEqual(opened.first?.session, "s2")
        let did = try XCTUnwrap(rig.pipeline.transcript.events.last { $0.isAction && $0.actionName == Core.openThread })
        XCTAssertEqual(did["by"]?.string, Core.drawerPick)
        XCTAssertEqual(rig.state.list?.map(\.id), list.map(\.id), "the same numbers")
        let none = rig.note(Fx(rig.pipeline.pick(row: 1_999_999_999, at: rig.now)))
        XCTAssertFalse(none.effects.contains { if case .open = $0 { true } else { false } })
    }

    /// The board's `pick`: its row's number, a request's size, or none.
    func testThePickOnTheWire() {
        func pick(_ line: String) -> Int? {
            guard case .event(let ev) = Wire.decode(line) else { return nil }
            return BoopDevice.row(picked: ev)
        }
        XCTAssertEqual(pick(#"{"t":"ev","kind":"drawer","did":"pick","data":{"id":12}}"#), 12)
        XCTAssertNil(pick(#"{"t":"ev","kind":"drawer","did":"pick"}"#))
        XCTAssertNil(pick(#"{"t":"ev","kind":"drawer","did":"pick","data":{"id":0}}"#))
        XCTAssertNil(pick(#"{"t":"ev","kind":"drawer","did":"pick","data":{"id":4294967296}}"#))
    }

    /// The popover's rows: since when each has waited, worked or rested,
    /// and a working one's latest word, lane and to-dos.
    func testThePopoversRowsSayWhatEachIsDoing() throws {
        let rig = CoreRig(workStream: true)
        rig.send(.turnStart, session: "s1", project: "landing")
        rig.wait(5000)
        rig.send(.activity, session: "s1", project: "landing", tool: "Grep")
        let row = try XCTUnwrap(rig.core.sessionList(at: rig.now).first)
        XCTAssertEqual(row.status, .working)
        XCTAssertEqual(row.word, "grep")
        XCTAssertEqual(row.slot, 0)
        let since = try XCTUnwrap(row.since)
        let worked = Date(timeIntervalSince1970: Double(rig.core.wall(rig.now)) / 1000).timeIntervalSince(since)
        XCTAssertTrue(abs(worked - 5) < 0.01, "\(worked)")
        rig.send(.turnEnd, session: "s1", project: "landing")
        let idle = try XCTUnwrap(rig.core.sessionList(at: rig.now).first)
        XCTAssertEqual(idle.status, .idle)
        XCTAssertNil(idle.word)
        XCTAssertNotNil(idle.since)
    }
}
