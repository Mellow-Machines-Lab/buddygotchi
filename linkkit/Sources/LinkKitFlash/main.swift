import Darwin
import Foundation
import LinkKit

// `linkkit-flash`: writes firmware onto an ESP32 or ESP32-S3 over USB,
// through the chip's ROM bootloader (`Flasher`), then restarts it.

let usage = """
    usage: linkkit-flash [--port DEVICE] --chip esp32|esp32s3 --flash-size SIZE OFFSET:FILE...
    Writes each FILE at its OFFSET (hex, 0x10000) through the chip's ROM bootloader,
    checks each against the chip's MD5, and restarts the chip. Nothing else in flash
    changes. An app image built for the other chip is refused before the board is touched.
      --port        the serial port; by default the only USB one here
      --chip        esp32 (over a USB-serial chip) or esp32s3 (over its own USB)
      --flash-size  the board's flash, in bytes or as 4MB, 16MB
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("linkkit-flash: \(message)\n".utf8))
    exit(code)
}

var words = Array(CommandLine.arguments.dropFirst())
if words.contains("--help") || words.contains("-h") {
    print(usage)
    exit(0)
}
var flags: [String: String] = [:]
var images: [Flasher.Image] = []
while let word = words.first {
    if ["--port", "--chip", "--flash-size"].contains(word), words.count > 1 {
        flags[word] = words[1]
        words.removeFirst(2)
    } else if let colon = word.firstIndex(of: ":"), let offset = UInt32(word[..<colon].replacingOccurrences(of: "0x", with: ""), radix: 16) {
        let path = String(word[word.index(after: colon)...])
        guard let data = FileManager.default.contents(atPath: path) else { fail("can't read \(path)") }
        images.append(.init(offset: offset, data: data))
        words.removeFirst()
    } else {
        fail("\(word)?\n\(usage)", code: 2)
    }
}
guard let chip = flags["--chip"].flatMap(Flasher.Chip.init(rawValue:)), !images.isEmpty else { fail(usage, code: 2) }
func bytes(_ text: String) -> Int? {
    let t = text.uppercased()
    if t.hasSuffix("MB") { return Int(t.dropLast(2)).map { $0 << 20 } }
    return Int(t)
}
guard let size = flags["--flash-size"].flatMap(bytes) else { fail("--flash-size is bytes, or 4MB, 16MB", code: 2) }
let ports = Bridge.ports()
guard let port = flags["--port"] ?? (ports.count == 1 ? ports[0] : nil) else {
    fail(ports.isEmpty ? "no board on USB" : "more than one board on USB; pick one with --port: \(ports.joined(separator: " "))")
}
do {
    let flasher = try Flasher(port: port) { print($0) }
    var shown = -1
    try flasher.flash(images, chip: chip, flashSize: size) { done in
        let percent = Int(done * 100)
        if percent / 10 != shown / 10 { shown = percent; print("linkkit-flash: \(percent)%") }
    }
    print("linkkit-flash: done; \(port) is starting its new firmware")
} catch {
    fail("\(error)")
}
