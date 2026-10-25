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
        /// Its MAC says it's another board than the one offered the update.
        case otherBoard(found: String, wanted: String)
        /// The app has no firmware for its chip.
        case noFirmware(Flasher.Chip)

        public var description: String {
            switch self {
            case .otherBoard(let found, let wanted): "the board on USB is \(found), not \(wanted). Plug in \(wanted) instead, then try again."
            case .noFirmware(let chip): "this app has no firmware for the board on USB, an \(chip.rawValue)."
            }
        }
    }

    /// The one of `firmware` for the board in its bootloader, by its chip,
    /// when it's the board whose `hello.id` is `id`, as its MAC says: the
    /// update is offered for the board on Bluetooth and written to the one
    /// on USB, so another plugged in is refused. A board an earlier try
    /// left half written still has its MAC. Any board, for no `id` (its
    /// firmware said none).
    static func pick(_ board: Flasher.Board, among firmware: [BoardFirmware], for id: String?) throws -> BoardFirmware {
        if let id, !board.isDevice(id) {
            throw Refusal.otherBoard(found: board.advertised(BoopDevice.blePrefix), wanted: BoopDevice.advertised(id) ?? id)
        }
        guard let mine = firmware.first(where: { $0.chip == board.chip }) else { throw Refusal.noFirmware(board.chip) }
        return mine
    }

    /// Writes onto the board on `port`, when it's the one `id` names
    /// (`pick`), the one of `firmware` for the chip its bootloader
    /// reports, restarts it, and returns the one written. Blocks for the
    /// whole write, half a minute or so: call it off the main thread.
    public static func install(_ firmware: [BoardFirmware], on id: String?, port: String, log: @escaping (String) -> Void,
                               progress: (Double) -> Void) throws -> BoardFirmware {
        let written = try Flasher(port: port, log: log).flash(progress: progress) { board in
            let mine = try pick(board, among: firmware, for: id)
            log("firmware: writing \(mine.board) \(mine.version) (\(mine.sha)) to \(port)")
            let images = try mine.images.map { image in
                Flasher.Image(offset: image.offset, data: try Data(contentsOf: mine.directory.appendingPathComponent(image.file)))
            }
            return (mine, images, mine.flashSize)
        }
        log("firmware: \(port) is starting \(written.version)")
        return written
    }
}
