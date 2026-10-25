import Darwin
import Foundation
import Testing
@testable import LinkKit

/// A board on a pseudo-terminal: the bridge opens its far end as the
/// serial port, and the test writes and reads the near end as the board.
final class FakeBoard {
    let board: Int32
    let far: Int32
    let port: String

    init() throws {
        var board: Int32 = -1, far: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        try #require(openpty(&board, &far, &name, nil, nil) == 0)
        var t = termios()
        tcgetattr(far, &t)
        cfmakeraw(&t)
        tcsetattr(far, TCSANOW, &t)
        self.board = board
        self.far = far
        port = String(cString: name)
    }

    func send(_ text: String) { _ = text.withCString { write(board, $0, strlen($0)) } }

    /// What the bridge wrote to the board, up to `count` bytes or a second.
    func received(_ count: Int) -> String { readUpTo(board, count) }

    func unplug() {
        close(board)
        close(far)
    }
}

/// Up to `count` bytes from `fd`, waiting at most a second for each read.
func readUpTo(_ fd: Int32, _ count: Int) -> String {
    var got = [UInt8]()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while got.count < count {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        guard poll(&poller, 1, 1000) == 1 else { break }
        let n = read(fd, &buffer, min(buffer.count, count - got.count))
        if n <= 0 { break }
        got += buffer[0..<n]
    }
    return String(decoding: got, as: UTF8.self)
}

/// A client of the bridge's socket.
func connectTo(_ path: String) throws -> Int32 {
    try #require(SocketTransport.connectOnce(path))
}

@Suite(.serialized) struct BridgeTests {
    func start(_ bridge: Bridge) -> Box<Bool> {
        let done = Box<Bool>()
        Thread {
            do { try bridge.run() } catch { Issue.record("the bridge didn't start: \(error)") }
            done.add(true)
        }.start()
        eventually("listening", timeout: 2) { FileManager.default.fileExists(atPath: bridge.socketPath) }
        return done
    }

    func socketPath() -> String { "/tmp/lkb-\(getpid())-\(UUID().uuidString.prefix(6)).sock" }

    /// SPEC.md §8 (USB): every whole line from the board goes to every
    /// client; each client's lines go to the board whole, so two clients'
    /// lines never interleave. `stop` ends it and removes the socket.
    @Test func testLinesPassBothWaysWhole() throws {
        let board = try FakeBoard()
        defer { board.unplug() }
        let bridge = Bridge(port: board.port, socket: socketPath())
        let done = start(bridge)
        let a = try connectTo(bridge.socketPath), b = try connectTo(bridge.socketPath)
        defer { close(a); close(b) }
        usleep(100_000)  // both joined

        board.send(#"{"t":"hello"}"# + "\n" + #"{"t":"ev""#)
        board.send(#","kind":"tap"}"# + "\n")
        let both = #"{"t":"hello"}"# + "\n" + #"{"t":"ev","kind":"tap"}"# + "\n"
        #expect(readUpTo(a, both.utf8.count) == both)
        #expect(readUpTo(b, both.utf8.count) == both)

        _ = #"{"t":"sta"#.withCString { write(a, $0, strlen($0)) }
        usleep(50_000)
        _ = (#"{"t":"do","id":1}"# + "\n").withCString { write(b, $0, strlen($0)) }
        usleep(50_000)
        _ = (#"te"}"# + "\n").withCString { write(a, $0, strlen($0)) }
        let toBoard = #"{"t":"do","id":1}"# + "\n" + #"{"t":"state"}"# + "\n"
        #expect(board.received(toBoard.utf8.count) == toBoard, "a's line waited for its newline, whole")

        bridge.stop()
        eventually("stopped", timeout: 2) { done.all == [true] }
        #expect(!FileManager.default.fileExists(atPath: bridge.socketPath))
    }

    /// SPEC.md §8, §9 (USB): a client that stops reading is dropped once it
    /// falls 4 MB behind (64 KB here), and the others keep getting the
    /// board's lines; the host's writes wait 250 ms at most.
    @Test func testAClientThatStopsReadingIsDropped() throws {
        #expect(Bridge.maxBehind == 4 * 1024 * 1024)
        #expect(SocketTransport.sendTimeoutMs == 250)
        let board = try FakeBoard()
        defer { board.unplug() }
        let bridge = Bridge(port: board.port, socket: socketPath(), maxBehind: 64 * 1024)
        let done = start(bridge)
        defer {
            bridge.stop()
            eventually("stopped", timeout: 2) { done.all == [true] }
        }
        let stuck = try connectTo(bridge.socketPath), reader = try connectTo(bridge.socketPath)
        defer { close(stuck); close(reader) }
        usleep(100_000)
        let line = String(repeating: "x", count: 1000) + "\n"
        var read = 0
        for _ in 0..<600 {  // 600 KB: far past what the stuck one's socket holds, and past 64 KB behind
            board.send(line)
            read += readUpTo(reader, line.utf8.count).utf8.count
        }
        #expect(read == 600 * line.utf8.count, "the reader got every line")
        var drained = 0
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            var poller = pollfd(fd: stuck, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 1000) == 1 else { break }
            let n = Darwin.read(stuck, &buffer, buffer.count)
            if n <= 0 { break }
            drained += n
        }
        #expect(drained < 600 * line.utf8.count, "the stuck one was dropped: its connection closed short")
    }

    /// The board unplugged: `run` returns, and the socket goes. Another
    /// bridge already on the socket, or a port that won't open, is an error.
    @Test func testTheBoardGoingAwayEndsIt() throws {
        let board = try FakeBoard()
        let bridge = Bridge(port: board.port, socket: socketPath())
        let done = start(bridge)
        #expect(throws: Bridge.Failure.self) { try Bridge(port: board.port, socket: bridge.socketPath).run() }
        board.unplug()
        eventually("ended", timeout: 3) { done.all == [true] }
        #expect(!FileManager.default.fileExists(atPath: bridge.socketPath))
        #expect(throws: Bridge.Failure.self) { try Bridge(port: "/dev/no-such-port", socket: socketPath()).run() }
    }
}
