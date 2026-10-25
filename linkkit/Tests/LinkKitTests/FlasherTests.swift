import CryptoKit
import Foundation
import Testing
@testable import LinkKit

/// A chip in its ROM bootloader, as far as the flasher needs one: it
/// answers each command as the ESP32 and ESP32-S3 ROMs do, inflates what
/// it's sent into its flash, and answers an MD5 of it.
final class FakeBootloader: SerialLine {
    let chip: Flasher.Chip
    let usbJTAG: Bool
    var flash = [UInt8](repeating: 0xFF, count: 0x40000)
    var answers = true
    /// What its chip register reads, when it isn't `chip`'s.
    var magic: UInt32?
    /// Its base MAC, in its eFuses: its Bluetooth MAC ends in `54fe`.
    var mac: [UInt8] = [0x24, 0x6F, 0x28, 0x01, 0x54, 0xFC]
    /// Spoils one byte of what's written, as a bad flash chip would.
    var spoil = false
    var signals: [(dtr: Bool?, rts: Bool?)] = []
    var begins: [Data] = []
    var badChecksums = 0
    var out = Data()
    var reader = SLIP.Reader()
    var offset = 0, packed = Data()

    init(chip: Flasher.Chip, usbJTAG: Bool) {
        self.chip = chip
        self.usbJTAG = usbJTAG
    }

    func setSignals(dtr: Bool?, rts: Bool?) { signals.append((dtr, rts)) }
    func setBaud(_ baud: Int) {}
    func close() {}
    /// Last, out of the bootloader: EN pulsed, IO0 left high.
    var restarted: Bool { signals.suffix(2).map(\.rts) == [true, false] }

    func read(timeout: TimeInterval) -> Data {
        defer { out = Data() }
        return out
    }

    func reply(_ op: UInt8, value: UInt32 = 0, body: Data = Data(), status: UInt8 = 0) {
        let data = body + Data([status, status == 0 ? 0 : 0x05, 0, 0])
        out += SLIP.encode(Data([0x01, op]) + le16(UInt16(data.count)) + le(value) + data)
    }

    func write(_ data: Data) throws {
        guard answers else { return }
        reader.feed(data)
        while let packet = reader.next() {
            let bytes = [UInt8](packet)
            let op = bytes[1]
            let checksum = UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24
            let body = Data(bytes[8...])
            func word(_ i: Int) -> Int { Int(body[i]) | Int(body[i + 1]) << 8 | Int(body[i + 2]) << 16 | Int(body[i + 3]) << 24 }
            switch Flasher.Op(rawValue: op) {
            case .sync:
                reply(op)
                reply(op)  // the ROM answers a sync more than once
            case .readReg:
                // Each eFuse word as the chip keeps it: the first two bytes in
                // the second word, the last four in the first.
                let value: UInt32 = switch UInt32(word(0)) {
                case chip.macRegister: mac[2...5].reduce(0) { $0 << 8 | UInt32($1) }
                case chip.macRegister + 4: 0x00AB_0000 | UInt32(mac[0]) << 8 | UInt32(mac[1])  // and a CRC above them
                default: magic ?? chip.magic
                }
                reply(op, value: value)
            case .deflBegin:
                begins.append(body)
                offset = word(12)
                packed = Data()
                reply(op)
            case .deflData:
                let block = body.dropFirst(16)
                if Flasher.checksum(Data(block)) != checksum { badChecksums += 1 }
                packed += block
                reply(op)
            case .md5:
                let at = word(0), size = word(4)
                if !packed.isEmpty {
                    let plain = Self.inflate(packed)
                    flash.replaceSubrange(offset..<(offset + plain.count), with: plain)
                    if spoil { flash[offset] ^= 0xFF }
                    packed = Data()
                }
                let hex = Insecure.MD5.hash(data: Data(flash[at..<(at + size)])).map { String(format: "%02x", $0) }.joined()
                reply(op, body: Data(hex.utf8))
            default: reply(op)
            }
        }
    }

    /// A zlib stream's data, its Adler-32 checked.
    static func inflate(_ stream: Data) -> [UInt8] {
        let raw = stream.dropFirst(2).dropLast(4)
        let plain = (try? (Data(raw) as NSData).decompressed(using: .zlib) as Data) ?? Data()
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in plain { a = (a + UInt32(byte)) % 65521; b = (b + a) % 65521 }
        let trailer = [UInt8](stream.suffix(4))
        let adler = UInt32(trailer[0]) << 24 | UInt32(trailer[1]) << 16 | UInt32(trailer[2]) << 8 | UInt32(trailer[3])
        return adler == (b << 16 | a) ? [UInt8](plain) : []
    }
}

@Suite struct FlasherTests {
    /// Something like an app image: some of it repeats, some doesn't.
    static func image(_ size: Int, seed: UInt32) -> Data {
        var x = seed
        return Data((0..<size).map { i in
            x = x &* 1_664_525 &+ 1_013_904_223
            return i % 3 == 0 ? UInt8(i & 0xFF) : UInt8(x >> 24)
        })
    }

    /// Each image lands at its offset, is checked against the chip's MD5,
    /// and the chip is restarted at the end; nothing else in flash changes
    /// (the settings partition between the images stays).
    @Test func testFlashWritesEachImageChecksItAndRestarts() throws {
        for chip in Flasher.Chip.allCases {
            let rom = FakeBootloader(chip: chip, usbJTAG: chip == .esp32s3)
            rom.flash[0x9000] = 0x42  // NVS, between the images
            let otadata = Data(repeating: 0xAB, count: 0x2000), app = Self.image(70_000, seed: 7)
            var seen: [Double] = []
            try Flasher(line: rom).flash([.init(offset: 0xE000, data: otadata), .init(offset: 0x10000, data: app)],
                                         chip: chip, flashSize: 4 << 20) { seen.append($0) }
            #expect(Data(rom.flash[0xE000..<0x10000]) == otadata)
            #expect(Data(rom.flash[0x10000..<(0x10000 + app.count)]) == app)
            #expect(rom.flash[0x9000] == 0x42)
            #expect(rom.badChecksums == 0)
            #expect(seen.last == 1 && seen == seen.sorted())
            // The S3's ROM takes a fifth word, for encryption, the ESP32's doesn't.
            #expect(rom.begins.allSatisfy { $0.count == (chip == .esp32s3 ? 20 : 16) })
            #expect(rom.restarted)
        }
    }

    /// Which images go is up to the chip the bootloader reports: each
    /// chip gets its own, at its flash's size, and the flasher returns
    /// what they were picked from.
    @Test func testTheImagesFollowTheChipTheBootloaderReports() throws {
        for chip in Flasher.Chip.allCases {
            let rom = FakeBootloader(chip: chip, usbJTAG: chip == .esp32s3)
            var asked: [Flasher.Chip] = []
            let picked = try Flasher(line: rom).flash { found in
                asked.append(found.chip)
                return ("\(found.chip)'s", [.init(offset: 0x10000, data: Data(repeating: found.chip == .esp32 ? 1 : 2, count: 100))], 4 << 20)
            }
            #expect(asked == [chip])
            #expect(picked == "\(chip)'s")
            #expect(rom.flash[0x10000] == (chip == .esp32 ? 1 : 2))
            #expect(rom.restarted)
        }
    }

    /// SPEC.md §8: a device's `hello.id` ends in the last two bytes of its
    /// Bluetooth MAC, which ESP-IDF makes of the base MAC by adding 2 to
    /// its last byte. The bootloader reads the base MAC from the chip's
    /// eFuses, each chip's in its own place, so `pick` can tell the board
    /// meant from another before anything is written; and a board a write
    /// left half written still has its MAC, so trying again finds it.
    @Test func testTheBoardsMACSaysWhichDeviceItIs() throws {
        struct OtherBoard: Error {}
        for chip in Flasher.Chip.allCases {
            let rom = FakeBootloader(chip: chip, usbJTAG: chip == .esp32s3)
            func write(to id: String) throws -> Flasher.Board {
                try Flasher(line: rom).flash { board in
                    guard board.isDevice(id) else { throw OtherBoard() }
                    return (board, [.init(offset: 0x10000, data: Self.image(5000, seed: 4))], 4 << 20)
                }
            }
            #expect(throws: OtherBoard.self) { try write(to: "lamp-0001") }
            #expect(rom.begins.isEmpty, "nothing written to another board")
            #expect(rom.restarted)

            rom.spoil = true
            #expect(throws: Flasher.Failure.verify(offset: 0x10000)) { try write(to: "lamp-54fe") }
            rom.spoil = false
            let board = try write(to: "lamp-54fe")
            #expect(board == Flasher.Board(chip: chip, mac: rom.mac), "half written, it's still the same board")
            #expect(board.advertised("Lamp") == "Lamp-54FE")
            #expect(Data(rom.flash[0x10000..<(0x10000 + 5000)]) == Self.image(5000, seed: 4))
        }
        let wraps = Flasher.Board(chip: .esp32, mac: [0, 0, 0, 0, 0x54, 0xFF])
        #expect(wraps.isDevice("lamp-5401"), "the last byte wraps, and the one before it stays")
    }

    /// The rule: once in its bootloader, the board restarts however the
    /// write ends, so none is left there with its screen dark: a chip
    /// that isn't wanted, one that isn't known, one the app has no images
    /// for, and a write that doesn't read back.
    @Test func testTheBoardRestartsWhenAWriteFails() {
        struct NoImages: Error {}
        let wrong = FakeBootloader(chip: .esp32, usbJTAG: false)
        #expect(throws: Flasher.Failure.wrongChip(expected: .esp32s3, found: "esp32")) {
            try Flasher(line: wrong).flash([.init(offset: 0x10000, data: Data([1, 2, 3]))], chip: .esp32s3, flashSize: 16 << 20)
        }
        #expect(wrong.begins.isEmpty, "nothing written")
        #expect(wrong.restarted)

        let unknown = FakeBootloader(chip: .esp32, usbJTAG: false)
        unknown.magic = 0x1234
        #expect(throws: Flasher.Failure.unknownChip(0x1234)) {
            try Flasher(line: unknown).flash { _ in ((), [], 4 << 20) }
        }
        #expect(unknown.restarted)

        let spoiled = FakeBootloader(chip: .esp32s3, usbJTAG: true)
        spoiled.spoil = true
        #expect(throws: Flasher.Failure.verify(offset: 0x10000)) {
            try Flasher(line: spoiled).flash([.init(offset: 0x10000, data: Self.image(5000, seed: 1))], chip: .esp32s3, flashSize: 16 << 20)
        }
        #expect(spoiled.restarted)

        let refused = FakeBootloader(chip: .esp32s3, usbJTAG: true)
        #expect(throws: NoImages.self) { try Flasher(line: refused).flash { _ -> ((), [Flasher.Image], Int) in throw NoImages() } }
        #expect(refused.begins.isEmpty, "nothing written")
        #expect(refused.restarted)
    }

    /// An app image whose header names the other chip is refused before
    /// the board is touched.
    @Test func testAnImageForTheOtherChipIsRefusedFirst() {
        let rom = FakeBootloader(chip: .esp32s3, usbJTAG: true)
        var esp32App = Data([0xE9, 0x06, 0x02, 0x20]) + Data(count: 12)  // chip id 0 at byte 12
        esp32App += Self.image(100, seed: 2)
        #expect(throws: Flasher.Failure.wrongChip(expected: .esp32s3, found: "an image for an esp32")) {
            try Flasher(line: rom).flash([.init(offset: 0x10000, data: esp32App)], chip: .esp32s3, flashSize: 16 << 20)
        }
        #expect(rom.signals.isEmpty, "the board wasn't even reset")
    }

    @Test func testABoardThatNeverAnswersSaysSo() {
        let rom = FakeBootloader(chip: .esp32s3, usbJTAG: true)
        rom.answers = false
        #expect(throws: Flasher.Failure.noBootloader) {
            try Flasher(line: rom).flash([.init(offset: 0x10000, data: Data([1]))], chip: .esp32s3, flashSize: 16 << 20)
        }
    }

    /// SLIP escapes its frame and escape bytes, and the reader undoes it,
    /// dropping what comes between frames (the ROM's boot message).
    @Test func testSLIPRoundTrips() {
        let packet = Data([0x01, 0xC0, 0x02, 0xDB, 0x03, 0xDC, 0xDD])
        var reader = SLIP.Reader()
        reader.feed(Data("ets Jun  8 2016 00:22:57\r\n".utf8) + SLIP.encode(packet) + SLIP.encode(Data([9])))
        #expect(reader.next() == packet)
        #expect(reader.next() == Data([9]))
        #expect(reader.next() == nil)
        #expect(!SLIP.encode(packet).dropFirst().dropLast().contains(0xC0))
    }

    /// What the flasher sends inflates to the image, with zlib's header and
    /// a right Adler-32, as the ROM checks.
    @Test func testTheCompressedStreamIsZlib() {
        let data = Self.image(10_000, seed: 3)
        let stream = Deflate.zlib(data)
        #expect(stream.prefix(2) == Data([0x78, 0x9C]))
        #expect(Data(FakeBootloader.inflate(stream)) == data)
        #expect(Flasher.checksum(Data([0xEF])) == 0 && Flasher.checksum(Data()) == 0xEF)
    }
}
