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
        XCTAssertEqual(try? BoardFirmware.pick(.esp32s3, among: all).board, "amoled206")
        XCTAssertEqual(try? BoardFirmware.pick(.esp32, among: all).board, "cyd24")
        try XCTAssertThrowsError(try BoardFirmware.pick(.esp32, among: [all[0]])) {
            XCTAssertEqual($0 as? BoardFirmware.Refusal, .noFirmware(.esp32))
        }
    }

    /// The rule: the update is offered for the board on Bluetooth and
    /// written to the one on USB, so the one on USB must say it's that
    /// board; another, or one that says nothing, is refused, by the names
    /// they advertise.
    func testOnlyTheBoardOfferedTheUpdateIsWritten() throws {
        func hello(_ id: String) -> Hello { Hello(app: "boop", id: id, fw: "1.0.0", does: []) }
        try BoardFirmware.confirm(hello("b00p-54fe"), is: "b00p-54fe")
        try XCTAssertThrowsError(try BoardFirmware.confirm(hello("b00p-0001"), is: "b00p-54fe")) {
            XCTAssertEqual($0 as? BoardFirmware.Refusal, .otherBoard(found: "Boop-0001", wanted: "Boop-54FE"))
            XCTAssertEqual("\($0)", "the board on USB is Boop-0001, not Boop-54FE. Plug in Boop-54FE instead, then try again.")
        }
        try XCTAssertThrowsError(try BoardFirmware.confirm(nil, is: "b00p-54fe")) {
            XCTAssertEqual($0 as? BoardFirmware.Refusal, .noHello)
        }
    }
}
