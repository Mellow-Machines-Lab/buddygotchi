import Foundation
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

    /// The rule: a board is offered its board's firmware when it runs
    /// another version than the app carries, and nothing when it runs the
    /// same, or the app carries none for it. Which board: its hello says,
    /// or, from older firmware, its face (only the AMOLED draws the gel).
    func testABoardIsOfferedTheAppsFirmwareWhenItRunsAnotherVersion() {
        let all = BoardFirmware.all(in: dir)
        let old = DeviceInfo(id: "b00p-01dd", fw: "1.0.0", face: .gel, board: "amoled206")
        XCTAssertEqual(BoardFirmware.update(for: old, among: all)?.board, "amoled206")
        var same = old
        same.fw = "1.1.0"
        XCTAssertNil(BoardFirmware.update(for: same, among: all))
        let unnamedGel = DeviceInfo(id: "b00p-01dd", fw: "1.0.0", face: .gel)
        XCTAssertEqual(BoardFirmware.update(for: unnamedGel, among: all)?.board, "amoled206")
        let unnamedPixel = DeviceInfo(id: "b00p-7f3a", fw: "1.0.0", face: .pixel)
        XCTAssertEqual(BoardFirmware.update(for: unnamedPixel, among: all)?.board, "cyd24")
        XCTAssertNil(BoardFirmware.update(for: old, among: []), "a bare binary carries none")
    }

    /// The board on a USB port, by how it shows up.
    func testTheFirmwareForAPortFollowsHowTheBoardShowsUp() {
        let all = BoardFirmware.all(in: dir)
        XCTAssertEqual(BoardFirmware.forPort("/dev/cu.usbmodem3101", among: all)?.board, "amoled206")
        XCTAssertEqual(BoardFirmware.forPort("/dev/cu.usbserial-110", among: all)?.board, "cyd24")
        XCTAssertEqual(BoardFirmware.forPort("/dev/cu.wchusbserial10", among: all)?.board, "cyd24")
    }
}
