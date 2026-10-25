import Foundation
import XCTest
@testable import BoopKit

/// A memory store in a fresh temporary directory.
final class MemoryRig {
    let dir: URL
    var logs: [String] = []
    var store: MemoryStore!

    init(setUp: Bool = true) throws {
        dir = tempDir("boop-memory")
        try reopen()
        if setUp { try store.setUp(name: "Pip", seed: 0x7f3a, today: "2026-10-02") }
    }

    /// Opens the store as a launch on `today` would.
    func reopen(today: String = "2026-10-14") throws {
        store = try MemoryStore(directory: dir, today: today, log: { [weak self] in self?.logs.append($0) })
    }

    func file(_ name: String) -> String { (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? "" }

    /// The days `history/` has a folder for, oldest first.
    func history() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("history").path).sorted()
    }

    /// Writes a file as a person editing it by hand would.
    func edit(_ name: String, _ text: String) throws {
        try Data(text.utf8).write(to: dir.appendingPathComponent(name))
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

final class MemoryTests: XCTestCase {
    static let sample = "## Boop\nname: Pip · hatched: 2026-10-02 · seed: 7f3a\n"

    func testLongTermRoundTrips() throws {
        let lt = try LongTerm.parse(MemoryTests.sample)
        XCTAssertEqual(lt.name, "Pip")
        XCTAssertEqual(lt.seed, 0x7f3a)
        XCTAssertEqual(lt.markdown, MemoryTests.sample)
    }

    /// A Boop set up when a nature was chosen at setup still reads, and
    /// the nature, now the personality's, is left behind.
    func testALongTermWithANatureStillReads() throws {
        let old = MemoryTests.sample.replacingOccurrences(of: " · seed:", with: " · nature: sweet · seed:")
        let (then, now) = (try LongTerm.parse(old), try LongTerm.parse(MemoryTests.sample))
        XCTAssertEqual(then, now)
    }

    /// Files from before 2026-09-27 have Temperament, Moments, About you and
    /// Preferences in `long-term.md`, older ones a Growth section. They
    /// still load, and the store leaves them as they are. The
    /// `short-term.md` apps before 2026-09-30 kept is left alone, unread.
    func testFilesFromBeforeStillLoad() throws {
        let oldLongTerm = MemoryTests.sample + """

            ### Temperament
            Nosy and a bit smug.

            ### Growth
            xp: 1240 · level: 25 · last fed: 2026-10-14 · lost: 3

            ## About you
            - Ships on Fridays.

            """
        try XCTAssertEqual(try LongTerm.parse(oldLongTerm), try LongTerm.parse(MemoryTests.sample))

        let rig = try MemoryRig()
        let oldShortTerm = "## Today\n2026-10-14\n"
        try rig.edit("long-term.md", oldLongTerm)
        try rig.edit("short-term.md", oldShortTerm)
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertFalse(rig.logs.contains { $0.contains("didn't read") }, "\(rig.logs)")
        XCTAssertEqual(rig.file("long-term.md"), oldLongTerm)
        XCTAssertEqual(rig.file("short-term.md"), oldShortTerm)
    }

    func testUnreadableFilesThrow() throws {
        try XCTAssertThrowsError(try LongTerm.parse("hello"))
        try XCTAssertThrowsError(try LongTerm.parse(MemoryTests.sample.replacingOccurrences(of: "seed: 7f3a", with: "seed: lots")))
    }

    func testOnlyARealDayIsADay() {
        for day in ["2026-10-02", "2024-02-29", "2000-02-29", "2026-12-31"] { XCTAssertTrue(LocalTime.isDay(day), day) }
        for day in ["2026-02-29", "1900-02-29", "2026-02-30", "2026-1-01", "2026-13-01", "2026-01-00", "2026/01/01", "+026-01-01"] {
            XCTAssertFalse(LocalTime.isDay(day), day)
        }
    }

    func testSetUpWritesLongTermAndASnapshot() throws {
        let rig = try MemoryRig()
        XCTAssertEqual(rig.file("long-term.md"), MemoryTests.sample)
        XCTAssertTrue(rig.file("history/2026-10-02/long-term.md").contains("name: Pip"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "Bo", seed: 1, today: "2026-10-14"))
        XCTAssertEqual(rig.store.longTerm!.seed, 0x7f3a)
    }

    func testNamesThatBreakTheBoopLineAreRefused() throws {
        let rig = try MemoryRig(setUp: false)
        try XCTAssertThrowsError(try rig.store.setUp(name: "Pip · xp: 9", seed: 1, today: "2026-10-14"))
        try XCTAssertThrowsError(try rig.store.setUp(name: "", seed: 1, today: "2026-10-14"))
        XCTAssertFalse(rig.store.isSetUp)
    }

    /// A hand edit is read at the next launch, and the
    /// store leaves `long-term.md` as it is.
    func testHandEditsAreReadAtLaunchAndKept() throws {
        let rig = try MemoryRig()
        let edited = MemoryTests.sample.replacingOccurrences(of: "name: Pip", with: "name: Pippa")
        try rig.edit("long-term.md", edited)
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pippa")
        XCTAssertEqual(rig.file("long-term.md"), edited)
    }

    /// A launch copies a hand edit that reads to
    /// `history/<today>/`, once, so a later break brings the edit back,
    /// not setup's name. With the Mac's clock behind the newest copy, the
    /// edit replaces it, so it's still the newest.
    func testAHandEditIsCopiedForARestore() throws {
        let rig = try MemoryRig()
        try rig.reopen()
        try XCTAssertEqual(rig.history(), ["2026-10-02"], "setup's copy is the file")
        let pippa = MemoryTests.sample.replacingOccurrences(of: "name: Pip", with: "name: Pippa")
        try rig.edit("long-term.md", pippa)
        try rig.reopen()
        XCTAssertEqual(rig.file("history/2026-10-14/long-term.md"), pippa)
        try rig.reopen(today: "2026-10-15")
        try XCTAssertEqual(rig.history(), ["2026-10-02", "2026-10-14"], "the same again isn't copied")
        try rig.edit("long-term.md", "garbage")
        try rig.reopen(today: "2026-10-16")
        XCTAssertEqual(rig.store.longTerm?.name, "Pippa")
        XCTAssertEqual(rig.file("long-term.md"), pippa)

        let bo = MemoryTests.sample.replacingOccurrences(of: "name: Pip", with: "name: Bo")
        try rig.edit("long-term.md", bo)
        try rig.reopen(today: "2026-10-01")
        try XCTAssertEqual(rig.history(), ["2026-10-02", "2026-10-14"])
        XCTAssertEqual(rig.file("history/2026-10-14/long-term.md"), bo)
    }

    func testABrokenLongTermIsRestoredFromItsSnapshot() throws {
        let rig = try MemoryRig()
        try rig.edit("long-term.md", "## Boop\nname Pip, hatched some time ago\n")
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertEqual(rig.file("long-term.md"), MemoryTests.sample)
        XCTAssertEqual(rig.file("long-term.md.broken"), "## Boop\nname Pip, hatched some time ago\n")
        XCTAssertTrue(rig.logs.contains { $0.contains("restored from history/2026-10-02") })
        // And on a restart.
        try rig.edit("long-term.md", "garbage")
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
    }

    /// Bytes that aren't UTF-8 are broken memory,
    /// not a missing file that asks the owner to hatch a new Boop.
    func testANonUTF8LongTermIsPreservedAndRestored() throws {
        let rig = try MemoryRig()
        let broken = Data([0xff, 0xfe, 0x80])
        try broken.write(to: rig.dir.appendingPathComponent(MemoryStore.longTermFile))
        try rig.reopen()
        XCTAssertEqual(rig.store.longTerm?.name, "Pip")
        XCTAssertEqual(rig.file("long-term.md"), MemoryTests.sample)
        try XCTAssertEqual(try Data(contentsOf: rig.dir.appendingPathComponent("long-term.md.broken")), broken)
        XCTAssertTrue(rig.logs.contains { $0.contains("restored from history/2026-10-02") })
    }

    /// A read permission failure does not prove
    /// corruption, and must not replace valid newer memory with history.
    func testAReadFailureLeavesLongTermAndItsBrokenCopyAlone() throws {
        let rig = try MemoryRig()
        let file = rig.dir.appendingPathComponent(MemoryStore.longTermFile)
        let newer = MemoryTests.sample.replacingOccurrences(of: "name: Pip", with: "name: Pippa")
        try rig.edit(MemoryStore.longTermFile, newer)
        try rig.edit("long-term.md.broken", "previous broken bytes")
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        try XCTAssertThrowsError(try Data(contentsOf: file), "the fixture must be unreadable")
        try rig.reopen()
        XCTAssertNil(rig.store.longTerm)
        XCTAssertEqual(rig.file("long-term.md.broken"), "previous broken bytes")
        XCTAssertFalse(rig.logs.contains { $0.contains("restored from history/") })
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        XCTAssertEqual(rig.file(MemoryStore.longTermFile), newer)
    }
}
