import CryptoKit
import Darwin
import Foundation

/// Writes firmware onto an ESP32 or ESP32-S3 over its USB serial port,
/// through the chip's own ROM bootloader, the way esptool does: the
/// serial lines reset it into the bootloader, then each image goes in
/// compressed, 1 KB at a time, and is read back as an MD5 before the chip
/// restarts into it. The bootloader is in ROM, so a write that fails
/// partway can always be tried again.
///
/// Only the images given are written: an app and the record of which app
/// slot to boot leave the bootloader, the partition table and the
/// settings partition (NVS) as they were.
public final class Flasher {
    public enum Chip: String, Sendable, CaseIterable, Codable {
        case esp32, esp32s3

        /// The chip id in an app image's header (byte 12).
        public var imageId: UInt16 { self == .esp32 ? 0 : 9 }
        /// What `CHIP_DETECT_MAGIC_REG` reads on it in the bootloader.
        var magic: UInt32 { self == .esp32 ? 0x00F0_1D83 : 0x9 }
    }

    /// One image and where it goes in flash.
    public struct Image: Sendable, Equatable {
        public var offset: UInt32
        public var data: Data
        public init(offset: UInt32, data: Data) {
            self.offset = offset
            self.data = data
        }
    }

    public enum Failure: Error, CustomStringConvertible, Equatable {
        case port(String, Int32)
        case noBootloader
        case wrongChip(expected: Chip, found: String)
        /// The bootloader's chip register reads none of `Chip`'s.
        case unknownChip(UInt32)
        case command(UInt8, status: UInt8, error: UInt8)
        case timeout(String)
        case verify(offset: UInt32)

        public var description: String {
            switch self {
            case .port(let path, let e): "can't open \(path): \(String(cString: strerror(e)))"
            case .noBootloader: "the board didn't answer in its bootloader: unplug it and plug it in again, then try again"
            case .wrongChip(let expected, let found): "this firmware is for an \(expected.rawValue), and the board is \(found)"
            case .unknownChip(let magic): String(format: "the board's chip isn't an esp32 or esp32s3 (its magic is %08x)", magic)
            case .command(let op, let status, let error): "the bootloader refused command \(op) (status \(status), error \(error))"
            case .timeout(let what): "no answer from the bootloader to \(what)"
            case .verify(let offset): "what's in flash at \(String(offset, radix: 16)) isn't what was written"
            }
        }
    }

    /// The bootloader's commands (esptool's names).
    enum Op: UInt8 {
        case sync = 0x08, readReg = 0x0A, spiSetParams = 0x0B, spiAttach = 0x0D, changeBaud = 0x0F
        case deflBegin = 0x10, deflData = 0x11, md5 = 0x13
    }

    /// The bootloader takes compressed data this many bytes at a time.
    static let blockSize = 0x400
    /// Where every chip keeps the register that says which it is.
    static let chipMagicRegister: UInt32 = 0x4000_1000
    /// The rate the CYD's CH340 takes on macOS's own driver; the S3's own
    /// USB has none to change.
    public static let fastBaud = 460_800

    let line: SerialLine
    let log: (String) -> Void
    var frames = SLIP.Reader()

    /// Opens `port` at 115200, the bootloader's rate.
    public convenience init(port: String, log: @escaping (String) -> Void = { _ in }) throws {
        self.init(line: try PortLine(path: port), log: log)
    }

    init(line: SerialLine, log: @escaping (String) -> Void = { _ in }) {
        self.line = line
        self.log = log
    }

    deinit { line.close() }

    /// Writes `images` to a `chip` with `flashSize` bytes of flash, then
    /// restarts it into them. `progress` goes from 0 to 1 as the bytes go.
    public func flash(_ images: [Image], chip: Chip, flashSize: Int, progress: (Double) -> Void = { _ in }) throws {
        // One built for the other board is refused before anything is touched.
        try Self.check(images, for: chip)
        try flash(progress: progress) { found in
            guard found == chip else { throw Failure.wrongChip(expected: chip, found: found.rawValue) }
            return (images, flashSize)
        }
    }

    /// Writes the images `pick` gives for the chip the bootloader says the
    /// board has, with the size of its flash, then restarts it into them.
    public func flash(progress: (Double) -> Void = { _ in },
                      pick: (Chip) throws -> (images: [Image], flashSize: Int)) throws {
        // Out of the bootloader whatever happens: a `pick` that throws or
        // a write that fails partway restarts the board too, rather than
        // leave it in its bootloader, its screen dark.
        defer { restart() }
        try enterBootloader()
        let magic = try readRegister(Self.chipMagicRegister)
        guard let chip = Chip.allCases.first(where: { $0.magic == magic }) else { throw Failure.unknownChip(magic) }
        log("flash: \(chip.rawValue) in its bootloader")
        let (images, flashSize) = try pick(chip)
        try Self.check(images, for: chip)
        // The ROM wants four more bytes after the SPI pins here.
        try command(.spiAttach, Data(count: 8))
        try command(.spiSetParams, le(0) + le(UInt32(flashSize)) + le(0x10000) + le(0x1000) + le(0x100) + le(0xFFFF))
        if chip == .esp32 && !line.usbJTAG {
            try command(.changeBaud, le(UInt32(Self.fastBaud)) + le(0))
            line.setBaud(Self.fastBaud)
            usleep(50_000)
            _ = line.read(timeout: 0.05)
            frames = SLIP.Reader()
        }
        let total = Double(images.reduce(0) { $0 + $1.data.count })
        var done = 0.0
        for image in images {
            try write(image, chip: chip) { progress((done + $0 * Double(image.data.count)) / total) }
            done += Double(image.data.count)
            try verify(image)
            log("flash: wrote and checked \(image.data.count) bytes at \(String(image.offset, radix: 16))")
        }
        progress(1)
    }

    /// An image with Espressif's header names its chip: one for another
    /// chip than `chip` is refused.
    static func check(_ images: [Image], for chip: Chip) throws {
        for image in images where image.data.count >= 16 && image.data.first == 0xE9 {
            let id = UInt16(image.data[image.data.startIndex + 12]) | UInt16(image.data[image.data.startIndex + 13]) << 8
            guard id == chip.imageId else {
                throw Failure.wrongChip(expected: chip, found: Chip.allCases.first { $0.imageId == id }.map { "an image for an \($0.rawValue)" } ?? "an image for chip \(id)")
            }
        }
    }

    // MARK: The bootloader

    /// Resets the chip into its bootloader through DTR and RTS, and syncs
    /// with it: the S3's own USB (USB-Serial/JTAG) takes one sequence, a
    /// USB-serial chip's auto-reset circuit (the CYD's CH340) another. Each
    /// is tried, its own first.
    func enterBootloader() throws {
        let ways: [() -> Void] = line.usbJTAG ? [usbJTAGReset, classicReset] : [classicReset, usbJTAGReset]
        for _ in 0..<3 {
            for reset in ways {
                reset()
                _ = line.read(timeout: 0.1)  // the ROM's boot message
                frames = SLIP.Reader()
                if sync() { return }
            }
        }
        throw Failure.noBootloader
    }

    func sync() -> Bool {
        let hello = Data([0x07, 0x07, 0x12, 0x20]) + Data(repeating: 0x55, count: 32)
        for _ in 0..<5 {
            if (try? command(.sync, hello, timeout: 0.1)) != nil {
                // It answers each sync several times: let the rest go.
                _ = line.read(timeout: 0.1)
                frames = SLIP.Reader()
                return true
            }
        }
        return false
    }

    /// esptool's ClassicReset: EN low with IO0 high, then IO0 low as EN
    /// comes up, so the chip starts in its bootloader.
    func classicReset() {
        line.setSignals(dtr: false, rts: true)
        usleep(100_000)
        line.setSignals(dtr: true, rts: false)
        usleep(50_000)
        line.setSignals(dtr: false, rts: nil)
    }

    /// esptool's USBJTAGSerialReset, through (1,1) rather than (0,0).
    func usbJTAGReset() {
        line.setSignals(dtr: false, rts: false)
        usleep(100_000)
        line.setSignals(dtr: true, rts: false)
        usleep(100_000)
        line.setSignals(dtr: nil, rts: true)
        line.setSignals(dtr: false, rts: true)
        usleep(100_000)
        line.setSignals(dtr: false, rts: false)
    }

    /// Out of the bootloader into the new firmware: a pulse on EN.
    func restart() {
        line.setSignals(dtr: false, rts: true)
        usleep(100_000)
        line.setSignals(dtr: nil, rts: false)
    }

    func readRegister(_ address: UInt32) throws -> UInt32 {
        try command(.readReg, le(address)).value
    }

    /// Erases as it goes, then takes the compressed image a block at a time.
    func write(_ image: Image, chip: Chip, progress: (Double) -> Void) throws {
        let packed = Deflate.zlib(image.data)
        let blocks = (packed.count + Self.blockSize - 1) / Self.blockSize
        let erase = UInt32((image.data.count + Self.blockSize - 1) / Self.blockSize * Self.blockSize)
        var begin = le(erase) + le(UInt32(blocks)) + le(UInt32(Self.blockSize)) + le(image.offset)
        if chip == .esp32s3 { begin += le(0) }  // not encrypted: the S3's ROM asks
        try command(.deflBegin, begin, timeout: 3 + 30 * Self.megabytes(Int(erase)))
        for seq in 0..<blocks {
            let block = packed[(seq * Self.blockSize)..<min(packed.count, (seq + 1) * Self.blockSize)]
            try command(.deflData, le(UInt32(block.count)) + le(UInt32(seq)) + le(0) + le(0) + block,
                        checksum: Self.checksum(block), timeout: 10)
            progress(Double(seq + 1) / Double(blocks))
        }
    }

    /// The chip's MD5 of what's now in flash, against the image's.
    func verify(_ image: Image) throws {
        let reply = try command(.md5, le(image.offset) + le(UInt32(image.data.count)) + le(0) + le(0),
                                timeout: 3 + 8 * Self.megabytes(image.data.count))
        let theirs = String(decoding: reply.data.prefix(32), as: UTF8.self).lowercased()
        let ours = Insecure.MD5.hash(data: image.data).map { String(format: "%02x", $0) }.joined()
        guard theirs == ours else { throw Failure.verify(offset: image.offset) }
    }

    static func megabytes(_ bytes: Int) -> Double { Double(bytes) / 1_048_576 }

    /// Sends one command and waits for its answer, skipping any other's.
    /// The ROM ends each answer with four status bytes, the first 0 when it
    /// went well and the second the error when not.
    @discardableResult
    func command(_ op: Op, _ data: Data = Data(), checksum: UInt32 = 0, timeout: TimeInterval = 3) throws -> (value: UInt32, data: Data) {
        var packet = Data([0x00, op.rawValue]) + le16(UInt16(data.count)) + le(checksum)
        packet += data
        try line.write(SLIP.encode(packet))
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while let frame = frames.next() {
                guard frame.count >= 8, frame[frame.startIndex] == 0x01, frame[frame.startIndex + 1] == op.rawValue else { continue }
                let bytes = [UInt8](frame)
                let value = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
                let body = Data(bytes[8...])
                guard body.count >= 4 else { throw Failure.command(op.rawValue, status: 0xFF, error: 0) }
                let status = body[body.count - 4], error = body[body.count - 3]
                guard status == 0 else { throw Failure.command(op.rawValue, status: status, error: error) }
                return (value, body.prefix(body.count - 4))
            }
            frames.feed(line.read(timeout: min(0.05, max(0.001, deadline.timeIntervalSinceNow))))
        }
        throw Failure.timeout("command \(op.rawValue)")
    }

    /// The bootloader's data checksum: 0xEF, XORed with every byte.
    static func checksum(_ data: Data) -> UInt32 { UInt32(data.reduce(UInt8(0xEF), ^)) }
}

func le(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }

/// SLIP framing, as the bootloader speaks it: each packet between 0xC0s,
/// with 0xC0 and 0xDB escaped.
enum SLIP {
    static func encode(_ packet: Data) -> Data {
        var out = Data([0xC0])
        for byte in packet {
            switch byte {
            case 0xC0: out += [0xDB, 0xDC]
            case 0xDB: out += [0xDB, 0xDD]
            default: out.append(byte)
            }
        }
        out.append(0xC0)
        return out
    }

    /// Bytes in, whole packets out; anything outside a frame (the ROM's
    /// boot message) is dropped.
    struct Reader {
        var inFrame = false, escaped = false
        var current = Data()
        var ready: [Data] = []

        mutating func feed(_ bytes: Data) {
            for byte in bytes {
                if byte == 0xC0 {
                    if inFrame, !current.isEmpty { ready.append(current) }
                    current = Data()
                    inFrame = true
                    escaped = false
                } else if inFrame {
                    if escaped {
                        current.append(byte == 0xDC ? 0xC0 : byte == 0xDD ? 0xDB : byte)
                        escaped = false
                    } else if byte == 0xDB {
                        escaped = true
                    } else {
                        current.append(byte)
                    }
                }
            }
        }

        mutating func next() -> Data? { ready.isEmpty ? nil : ready.removeFirst() }
    }
}

/// A zlib stream (RFC 1950) of `data`, as the bootloader inflates it:
/// Foundation's raw deflate between zlib's header and its Adler-32.
enum Deflate {
    static func zlib(_ data: Data) -> Data {
        let raw = (try? (data as NSData).compressed(using: .zlib) as Data) ?? Data()
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = b << 16 | a
        return Data([0x78, 0x9C]) + raw + withUnsafeBytes(of: adler.bigEndian) { Data($0) }
    }
}

/// What the flasher needs of a serial port. Tests pass a fake bootloader.
protocol SerialLine: AnyObject {
    /// The S3's own USB-Serial/JTAG, which resets its own way.
    var usbJTAG: Bool { get }
    func write(_ data: Data) throws
    /// Whatever arrives within `timeout`, maybe nothing.
    func read(timeout: TimeInterval) -> Data
    /// Sets DTR and RTS; nil leaves one as it is.
    func setSignals(dtr: Bool?, rts: Bool?)
    func setBaud(_ baud: Int)
    func close()
}

/// A real port.
final class PortLine: SerialLine {
    /// `_IOW('t', 108, int)` and `_IOW('t', 107, int)`, which Swift can't
    /// import as macros: set and clear modem lines.
    static let tiocmbis: UInt = 0x8004_746C, tiocmbic: UInt = 0x8004_746B
    let fd: Int32
    let usbJTAG: Bool

    init(path: String) throws {
        do { fd = try Bridge.openPort(path, baud: 115_200, log: { _ in }) } catch { throw Flasher.Failure.port(path, errno) }
        usbJTAG = path.contains("usbmodem")
    }

    func write(_ data: Data) throws {
        var sent = 0
        let deadline = Date().addingTimeInterval(5)
        try data.withUnsafeBytes { raw in
            while sent < data.count {
                let n = Darwin.write(fd, raw.baseAddress! + sent, data.count - sent)
                if n > 0 { sent += n } else if errno == EAGAIN, Date() < deadline { usleep(1000) } else {
                    throw Flasher.Failure.timeout("writing to the port")
                }
            }
        }
    }

    func read(timeout: TimeInterval) -> Data {
        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) > 0 else { return Data() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(fd, &buffer, buffer.count)
        return n > 0 ? Data(buffer[0..<n]) : Data()
    }

    func setSignals(dtr: Bool?, rts: Bool?) {
        var set: Int32 = 0, clear: Int32 = 0
        if let dtr { if dtr { set |= TIOCM_DTR } else { clear |= TIOCM_DTR } }
        if let rts { if rts { set |= TIOCM_RTS } else { clear |= TIOCM_RTS } }
        if set != 0 { _ = ioctl(fd, Self.tiocmbis, &set) }
        if clear != 0 { _ = ioctl(fd, Self.tiocmbic, &clear) }
    }

    func setBaud(_ baud: Int) {
        var speed = speed_t(baud)
        let iossiospeed = UInt(0x8000_0000) | UInt(MemoryLayout<speed_t>.size & 0x1FFF) << 16 | UInt(UInt8(ascii: "T")) << 8 | 2
        _ = ioctl(fd, iossiospeed, &speed)
    }

    func close() { Darwin.close(fd) }
}
