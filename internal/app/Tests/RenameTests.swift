import Foundation
import XCTest
@testable import BoopKit

/// Settings' Rename: the name's rules, which onboarding's field shares,
/// once a week, and the new name in every place the name lives once the
/// runtime starts again.
final class RenameTests: XCTestCase {
    var dir: URL!
    /// Wednesday 21 October 2026, noon UTC.
    nonisolated static let t0: Int64 = 1_792_584_000_000
    nonisolated static let day: Int64 = 86_400_000

    override func setUpWithError() throws {
        // Unix socket paths must stay under 104 bytes.
        dir = URL(fileURLWithPath: "/tmp/boop-rn-\(UUID().uuidString.prefix(8))")
    }

    override func tearDownWithError() throws {
        if let dir { try? FileManager.default.removeItem(at: dir) }
    }

    /// A name is 1 to 23 characters on one line, without "·" or ":", and
    /// a rename waits a week (`BuddyName`).
    func testTheNameRules() {
        XCTAssertTrue(BuddyName.valid("Mochi"))
        XCTAssertFalse(BuddyName.valid("   "), "no name")
        XCTAssertNil(BuddyName.issue("   "), "an empty field is no problem to say")
        XCTAssertEqual(BuddyName.issue("Mo·chi"), "Names can't use “·” or “:”.")
        XCTAssertNotNil(BuddyName.issue("Mochi: the second"))
        XCTAssertNotNil(BuddyName.issue(String(repeating: "x", count: 24)))
        XCTAssertNil(BuddyName.issue(String(repeating: "é", count: 23)), "23 characters, not 23 bytes")
        XCTAssertEqual(BuddyName.maxLength, 23)
        XCTAssertEqual(BuddyName.edited(String(repeating: "x", count: 30)).count, 23, "the field keeps 23")
        XCTAssertEqual(BuddyName.edited("Mo\tchi"), "Mo chi", "a control character becomes a space")
        XCTAssertEqual(BuddyName.trimmed("  Bean \n"), "Bean")
        XCTAssertEqual(BuddyName.renameEveryMs, 7 * Self.day, "a rename waits a week")
        XCTAssertNil(BuddyName.nextRename(after: nil, at: Self.t0), "never renamed: now")
        XCTAssertEqual(BuddyName.nextRename(after: Self.t0, at: Self.t0 + 6 * Self.day), Self.t0 + 7 * Self.day)
        XCTAssertNil(BuddyName.nextRename(after: Self.t0, at: Self.t0 + 7 * Self.day), "a week on: now")
    }

    func refusal(_ body: () throws -> Void) -> Error? {
        do { try body(); return nil } catch { return error }
    }

    /// The memory store writes the new name, keeping the day it hatched
    /// and its seed, with a copy in history, so a launch doesn't take it
    /// for a hand edit.
    func testTheStoreRenamesKeepingWhoItIs() throws {
        let store = try MemoryStore(directory: dir, today: "2026-11-01")
        XCTAssertNotNil(refusal { try store.rename(to: "Bean", today: "2026-11-01") }, "not set up")
        try store.setUp(name: "Mochi", seed: 0xABC, today: "2026-11-01")
        try store.rename(to: "  Bean ", today: "2026-11-14")
        XCTAssertEqual(store.longTerm, LongTerm(name: "Bean", hatched: "2026-11-01", seed: 0xABC))
        XCTAssertNotNil(refusal { try store.rename(to: "Be:an", today: "2026-11-14") })
        XCTAssertNotNil(refusal { try store.rename(to: "", today: "2026-11-14") })
        XCTAssertEqual(store.name, "Bean", "a refused name changes nothing")
        let copy = try String(contentsOf: dir.appendingPathComponent("history/2026-11-14/long-term.md"), encoding: .utf8)
        XCTAssertTrue(copy.contains("name: Bean"))
        let reopened = try MemoryStore(directory: dir, today: "2026-11-15")
        XCTAssertEqual(reopened.name, "Bean")
    }

    /// A rename writes the name and when; the runtime goes on under the
    /// old one, and the next runtime, on the folder the first let go of,
    /// goes by the new one: the popover's, the buddy's, the board's
    /// `state.buddy`, and the world's next send.
    func testARenameReachesEveryPlaceTheNameLives() throws {
        try Runtime.setUp(stateDir: dir, name: "Mochi")
        var options = Runtime.Options(stateDir: dir, socketPath: dir.appendingPathComponent("b.sock").path,
                                      link: FakeTransport(), steering: RuntimeTests.steering)
        options.readJevKey = { _ in nil }
        options.wallClock = { Self.t0 }
        let first = try Runtime(options)
        XCTAssertEqual(first.home.sync { first.renameNow("Mochi ") }, .success(false), "the same name is no rename")
        XCTAssertNil(AppSettings.load(from: dir).renamed)
        XCTAssertEqual(first.home.sync { first.renameNow("Be·an") }, .failure(Refusal("a name is 1–23 characters, on one line, without · or :")))
        XCTAssertEqual(first.home.sync { first.renameNow("Bean") }, .success(true))
        XCTAssertEqual(first.name, "Mochi", "this runtime goes on under the old name")
        XCTAssertEqual(AppSettings.load(from: dir).renamed, Self.t0)
        XCTAssertEqual(first.home.sync { first.renameNow("Pea") }, .failure(Refusal("Mochi was renamed less than a week ago")))
        first.stop()

        options.wallClock = { Self.t0 + Self.day }
        let next = try Runtime(options)
        XCTAssertEqual(next.name, "Bean")
        XCTAssertEqual(next.buddy.name, "Bean")
        XCTAssertEqual(next.home.sync { next.core.snapshot(at: 0).buddy }, "Bean", "the board's state.buddy")
        XCTAssertEqual(next.home.sync { next.worldNow(at: 0, day: "2026-10-22").name }, "Bean", "the world's next send")
        XCTAssertEqual(next.home.sync { next.renameNow("Pea") }, .failure(Refusal("Bean was renamed less than a week ago")))
        next.stop()
        options.wallClock = { Self.t0 + 7 * Self.day }
        let later = try Runtime(options)
        XCTAssertEqual(later.home.sync { later.renameNow("Pea") }, .success(true), "a week on")
        later.stop()
    }
}
