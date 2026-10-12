import Darwin
import Foundation
import LinkKit

// `linkkit-bridge`: shares a board's USB serial port on a Unix socket, for
// the host's SocketTransport and tools, until Ctrl-C (SPEC.md §8, `Bridge`).

let usage = """
    usage: linkkit-bridge [--port DEVICE] [--socket PATH] [--baud N]
    Shares the board's USB serial port on a Unix socket until Ctrl-C (SPEC.md §8):
    every line from the board goes to every client, and each client's lines go
    to the board whole. A client that stops reading is dropped.
      --port    the serial port; by default the only USB one here
                (/dev/cu.usbserial*, cu.wchusbserial* or cu.usbmodem*)
      --socket  where to share it, under 104 bytes; \(defaultSocket) by default
      --baud    the board's rate; \(Bridge.defaultBaud) by default
    """
// In this user's own temporary folder (`$TMPDIR`), which nobody else can
// open, rather than the shared /tmp.
var defaultSocket: String { (NSTemporaryDirectory() as NSString).appendingPathComponent("linkkit-bridge.sock") }

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("linkkit-bridge: \(message)\n".utf8))
    exit(code)
}

var words = Array(CommandLine.arguments.dropFirst())
if words.contains("--help") || words.contains("-h") {
    print(usage)
    exit(0)
}
var flags: [String: String] = [:]
while let flag = words.first {
    guard ["--port", "--socket", "--baud"].contains(flag), words.count > 1 else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exit(2)
    }
    flags[flag] = words[1]
    words.removeFirst(2)
}
guard let baud = Int(flags["--baud"] ?? String(Bridge.defaultBaud)), baud > 0 else { fail("--baud is a number", code: 2) }
let port: String
if let given = flags["--port"] {
    port = given
} else {
    let ports = Bridge.ports()
    guard ports.count == 1 else {
        fail(ports.isEmpty ? "no USB serial port here: plug the board in, or name one with --port"
             : "more than one USB serial port (\(ports.joined(separator: ", "))): name one with --port")
    }
    port = ports[0]
}

let bridge = Bridge(port: port, socket: flags["--socket"] ?? defaultSocket, baud: baud, log: { print($0) })
var stoppers: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    // Not the main actor's: `run` holds the main thread, and `stop` is
    // safe from any thread.
    let target = bridge
    source.setEventHandler { @Sendable in target.stop() }
    source.resume()
    stoppers.append(source)
}
setvbuf(stdout, nil, _IOLBF, 0)
do {
    try bridge.run()
} catch {
    fail("\(error)")
}
