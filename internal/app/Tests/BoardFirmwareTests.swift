import Foundation
import LinkKit
import XCTest
@testable import BoopKit

final class BoardFirmwareTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("firmware-\(UUID().uuidString)")
        for (board, chip, size) in [("amoled206", "esp32s3", 16 << 20), ("cyd24", "esp32", 4 << 20)] {
            let folder = dir.appendingPathComponent(board)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // As firmware/tools/package.py writes it.
            let manifest = """
                {"board": "\(board)", "chip": "\(chip)", "flash_size": \(size), "sha": "abc1234", "version": "1.1.0",
                 "images": [{"file": "boot_app0.bin", "offset": 57344}, {"file": "firmware.bin", "offset": 65536}]}
                """
            try Data(manifest.utf8).write(to: folder.appendingPathComponent("manifest.json"))
        }
        // A folder that isn't a board's is left out.
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("notes"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testTheAppReadsEachBoardsManifest() {
        let all = BoardFirmware.all(in: dir)
        XCTAssertEqual(all.map(\.board), ["amoled206", "cyd24"])
        XCTAssertEqual(all[0].chip, .esp32s3)
        XCTAssertEqual(all[0].flashSize, 16 << 20)
        XCTAssertEqual(all[0].images.map(\.offset), [0xE000, 0x10000])
        XCTAssertEqual(all[0].directory, dir.appendingPathComponent("amoled206"))
        XCTAssertEqual(BoardFirmware.all(in: nil), [])
    }

    /// The rule: a board is offered its board's firmware when it runs an
    /// older version than the app carries, compared as versions (1.10
    /// after 1.9), or the same version built with another character pack;
    /// and nothing when it runs the same with the app's pack, or a newer
    /// one, or the app carries none for it. Which board: its hello says,
    /// or, from older firmware, its face (only the AMOLED draws the gel).
    func testABoardIsOfferedTheAppsFirmwareWhenItsIsOlderOrAnotherPack() {
        let all = BoardFirmware.all(in: dir)
        let old = DeviceInfo(id: "b00p-01dd", fw: "1.0.0", face: .gel, board: "amoled206")
        XCTAssertEqual(BoardFirmware.update(for: old, among: all)?.board, "amoled206")
        var same = old
        same.fw = "1.1.0"
        XCTAssertNil(BoardFirmware.update(for: same, among: all))
        same.pack = "other 9.9.9"
        XCTAssertEqual(BoardFirmware.update(for: same, among: all)?.board, "amoled206", "the same version, another pack")
        same.pack = DeviceInfo.appPack
        XCTAssertNil(BoardFirmware.update(for: same, among: all), "the same version and pack")
        for newer in ["1.2.0", "1.10.0", "2.0"] {
            var ahead = old
            ahead.fw = newer
            XCTAssertNil(BoardFirmware.update(for: ahead, among: all), "\(newer) is newer than 1.1.0: no downgrade")
        }
        var nine = old
        nine.fw = "1.0.9"
        XCTAssertNotNil(BoardFirmware.update(for: nine, among: all), "1.0.9 is older than 1.1.0")
        let unnamedGel = DeviceInfo(id: "b00p-01dd", fw: "1.0.0", face: .gel)
        XCTAssertEqual(BoardFirmware.update(for: unnamedGel, among: all)?.board, "amoled206")
        let unnamedPixel = DeviceInfo(id: "b00p-7f3a", fw: "1.0.0", face: .pixel)
        XCTAssertEqual(BoardFirmware.update(for: unnamedPixel, among: all)?.board, "cyd24")
        XCTAssertNil(BoardFirmware.update(for: old, among: []), "a bare binary carries none")
    }

    /// The image is the one for the chip the bootloader reports, not a
    /// guess from the port's name.
    func testTheImageFollowsTheChipTheBootloaderReports() throws {
        let all = BoardFirmware.all(in: dir)
        let s3 = Flasher.Board(chip: .esp32s3, mac: Self.mac), cyd = Flasher.Board(chip: .esp32, mac: Self.mac)
        XCTAssertEqual(try? BoardFirmware.pick(s3, among: all, for: nil).board, "amoled206")
        XCTAssertEqual(try? BoardFirmware.pick(cyd, among: all, for: nil).board, "cyd24")
        try XCTAssertThrowsError(try BoardFirmware.pick(cyd, among: [all[0]], for: nil)) {
            XCTAssertEqual($0 as? BoardFirmware.Refusal, .noFirmware(.esp32))
        }
    }

    /// A board's base MAC, as its bootloader reports it: its Bluetooth
    /// MAC, and so its `hello.id`, ends in `54fe` on an ESP32 (base + 2)
    /// and `54fd` on an ESP32-S3 (base + 1).
    static let mac: [UInt8] = [0x24, 0x6F, 0x28, 0x01, 0x54, 0xFC]

    /// The rule: the update is offered for the board on Bluetooth, by its
    /// `hello.id`, whether its firmware fits or not, and written to the
    /// one on USB, so the one on USB must be that board, as the MAC its
    /// bootloader reports says; another is refused, by the names they
    /// advertise. A board a failed write left half written says no
    /// `hello` but keeps its MAC, so Try again is matched the same way
    /// (LinkKit's FlasherTests write one).
    func testOnlyTheBoardOfferedTheUpdateIsWritten() throws {
        let all = BoardFirmware.all(in: dir)
        let board = Flasher.Board(chip: .esp32s3, mac: Self.mac)
        XCTAssertEqual(try? BoardFirmware.pick(board, among: all, for: "b00p-54fd").board, "amoled206")
        try XCTAssertThrowsError(try BoardFirmware.pick(board, among: all, for: "b00p-0001")) {
            XCTAssertEqual($0 as? BoardFirmware.Refusal, .otherBoard(found: "Boop-54FD", wanted: "Boop-0001"))
            XCTAssertEqual("\($0)", "the board on USB is Boop-54FD, not Boop-0001. Plug in Boop-0001 instead, then try again.")
        }
    }
}
