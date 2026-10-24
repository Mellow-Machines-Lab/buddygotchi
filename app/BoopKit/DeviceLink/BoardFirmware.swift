import Foundation
import LinkKit

/// A board's firmware as Boop.app carries it, in Resources/firmware/<board>/
/// (`make bundle`, `firmware/tools/package.py`): its `manifest.json`, which
/// says the board, its chip and flash, the version and SHA it was built
/// from and where each image goes, beside the images. The app updates a
/// board whose firmware is older over USB, with LinkKit's `Flasher`.
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

    /// The firmware to update `device` with: its board's, when that's a
    /// newer version than the board runs, or the same version but the
    /// board's was built with another character pack (the app's firmware
    /// has the app's). Nil when it runs that already, or a newer one, or
    /// the app carries none for it.
    public static func update(for device: DeviceInfo, among firmware: [BoardFirmware]) -> BoardFirmware? {
        guard let mine = firmware.first(where: { $0.board == board(of: device) }) else { return nil }
        switch mine.version.compare(device.fw, options: .numeric) {
        case .orderedDescending: return mine
        case .orderedSame: return device.hasThePack ? nil : mine
        case .orderedAscending: return nil
        }
    }

    /// The USB serial ports a board could be on.
    public static func usbPorts() -> [String] { Bridge.ports() }

    /// Why the board on USB isn't written.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        /// Its `hello` names another board than the one offered the update.
        case otherBoard(found: String, wanted: String)
        /// It said no `hello`.
        case noHello
        /// The app has no firmware for its chip.
        case noFirmware(Flasher.Chip)

        public var description: String {
            switch self {
            case .otherBoard(let found, let wanted): "the board on USB is \(found), not \(wanted). Plug in \(wanted) instead, then try again."
            case .noHello: "the board on USB didn't say which board it is. Unplug it and plug it in again, then try again."
            case .noFirmware(let chip): "this app has no firmware for the board on USB, an \(chip.rawValue)."
            }
        }
    }

    /// Checks that the board on `port` is the one whose `hello.id` is
    /// `id`, by asking it: the update is offered for the board on
    /// Bluetooth and written to the one on USB, so another board plugged
    /// in is refused. Blocks for up to a few seconds: call it off the main
    /// thread.
    public static func confirm(port: String, is id: String) throws {
        try confirm(Bridge.hello(on: port), is: id)
    }

    static func confirm(_ hello: Hello?, is id: String) throws {
        guard let hello else { throw Refusal.noHello }
        guard hello.id == id else {
            throw Refusal.otherBoard(found: BoopDevice.advertised(hello.id) ?? hello.id, wanted: BoopDevice.advertised(id) ?? id)
        }
    }

    /// The one of `firmware` for `chip`.
    static func pick(_ chip: Flasher.Chip, among firmware: [BoardFirmware]) throws -> BoardFirmware {
        guard let mine = firmware.first(where: { $0.chip == chip }) else { throw Refusal.noFirmware(chip) }
        return mine
    }

    /// Writes onto the board on `port` the one of `firmware` for the chip
    /// its bootloader reports, restarts it, and returns the one written.
    /// Blocks for the whole write, half a minute or so: call it off the
    /// main thread.
    public static func install(_ firmware: [BoardFirmware], port: String, log: @escaping (String) -> Void,
                               progress: (Double) -> Void) throws -> BoardFirmware {
        var written: BoardFirmware?
        try Flasher(port: port, log: log).flash(progress: progress) { chip in
            let mine = try pick(chip, among: firmware)
            log("firmware: writing \(mine.board) \(mine.version) (\(mine.sha)) to \(port)")
            written = mine
            let images = try mine.images.map { image in
                Flasher.Image(offset: image.offset, data: try Data(contentsOf: mine.directory.appendingPathComponent(image.file)))
            }
            return (images, mine.flashSize)
        }
        log("firmware: \(port) is starting \(written!.version)")
        return written!
    }
}
