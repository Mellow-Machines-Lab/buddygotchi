import Foundation
import LinkKit

/// A board's firmware as Boop.app carries it, in Resources/firmware/<board>/
/// (`make bundle`, `firmware/tools/package.py`): its `manifest.json`, which
/// says the board, its chip and flash, the version and SHA it was built
/// from and where each image goes, beside the images. The app updates a
/// board whose firmware is another version over USB, with LinkKit's
/// `Flasher`.
public struct BoardFirmware: Decodable, Equatable, Sendable {
    public struct Image: Decodable, Equatable, Sendable {
        public var offset: UInt32
        public var file: String
    }

    /// The board's env name in firmware/platformio.ini: `cyd24`, `amoled206`.
    public var board: String
    public var chip: Flasher.Chip
    public var flashSize: Int
    public var version: String
    public var sha: String
    public var images: [Image]
    /// Where its images are.
    public var directory = URL(fileURLWithPath: "/")

    enum CodingKeys: String, CodingKey { case board, chip, flashSize = "flash_size", version, sha, images }

    public init(board: String, chip: Flasher.Chip, flashSize: Int, version: String, sha: String, images: [Image] = []) {
        self.board = board
        self.chip = chip
        self.flashSize = flashSize
        self.version = version
        self.sha = sha
        self.images = images
    }

    /// Every board's firmware in `folder`, one subfolder each; none
    /// without a folder.
    public static func all(in folder: URL?) -> [BoardFirmware] {
        guard let folder else { return [] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let dir = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  var firmware = try? JSONDecoder().decode(BoardFirmware.self, from: data) else { return nil }
            firmware.directory = dir
            return firmware
        }
    }

    /// What Boop.app carries; nothing for a bare binary (`make run`).
    public static func bundled() -> [BoardFirmware] {
        guard AboutThisMac.isApp() else { return [] }
        return all(in: Bundle.main.url(forResource: "firmware", withExtension: nil))
    }

    /// Which board a device is: its `hello` says (`board`); from firmware
    /// from before it did, its face does, since only the AMOLED draws the
    /// gel.
    public static func board(of device: DeviceInfo) -> String {
        device.board ?? (device.face == .gel ? "amoled206" : "cyd24")
    }

    /// The firmware to update `device` with: its board's, when that's
    /// another version than the board runs. Nil when it already runs it, or
    /// the app carries none for it.
    public static func update(for device: DeviceInfo, among firmware: [BoardFirmware]) -> BoardFirmware? {
        guard let mine = firmware.first(where: { $0.board == board(of: device) }), mine.version != device.fw else { return nil }
        return mine
    }

    /// The firmware for the board on a USB `port`, by how it shows up: the
    /// S3's own USB is `cu.usbmodem…`, the CYD's CH340 `cu.usbserial…` or
    /// `cu.wchusbserial…`. The flasher checks the chip itself too.
    public static func forPort(_ port: String, among firmware: [BoardFirmware]) -> BoardFirmware? {
        let chip: Flasher.Chip = port.contains("usbmodem") ? .esp32s3 : .esp32
        return firmware.first { $0.chip == chip }
    }

    /// The USB serial ports a board could be on.
    public static func usbPorts() -> [String] { Bridge.ports() }

    /// Writes it onto the board on `port` and restarts it. Blocks for the
    /// whole write, half a minute or so: call it off the main thread.
    public func install(port: String, log: @escaping (String) -> Void, progress: (Double) -> Void) throws {
        let images = try images.map { image in
            Flasher.Image(offset: image.offset, data: try Data(contentsOf: directory.appendingPathComponent(image.file)))
        }
        log("firmware: writing \(board) \(version) (\(sha)) to \(port)")
        try Flasher(port: port, log: log).flash(images, chip: chip, flashSize: flashSize, progress: progress)
        log("firmware: \(port) is starting \(version)")
    }
}
