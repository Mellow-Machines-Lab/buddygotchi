import CoreBluetooth
import Darwin
import Foundation
import Testing
@testable import LinkKit

/// Waits up to `timeout` seconds for `condition`, looking every 10 ms.
func eventually(_ what: Comment, timeout: Double, _ condition: () -> Bool,
                sourceLocation: SourceLocation = #_sourceLocation) {
    let end = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > end {
            Issue.record("timed out waiting: \(what)", sourceLocation: sourceLocation)
            return
        }
        usleep(10_000)
    }
}

/// A bridge's socket for a test, at a short path under /tmp: a socket's
/// path has room for 103 bytes.
final class FakeBridge {
    let path = "/tmp/linkkit-\(getpid())-\(UUID().uuidString.prefix(8)).sock"
    let fd: Int32

    init() throws {
        unlink(path)
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = try #require(UnixSocket.address(path))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        try #require(bound == 0)
        try #require(listen(fd, 8) == 0)
    }

    /// The next client, waiting at most a couple of seconds.
    func accept() throws -> Int32 {
        var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        try #require(poll(&poller, 1, 2000) == 1)
        return Darwin.accept(fd, nil, nil)
    }

    deinit {
        close(fd)
        unlink(path)
    }
}

/// Collects what callbacks on other threads hand over.
final class Box<T>: @unchecked Sendable {
    let lock = NSLock()
    var items: [T] = []
    func add(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }
}

@Suite struct FramingTests {
    /// SPEC.md §2: a line that spans packets is buffered until its
    /// newline; a trailing `\r` is dropped and empty lines skipped.
    @Test func testFramerReassemblesLinesAcrossPackets() {
        var framer = LineFramer()
        #expect(framer.push(Array(#"{"t":"e"#.utf8)) == [])
        #expect(framer.push(Array(#"v","kind":"tap"}"#.utf8) + [0x0A] + Array(#"{"t":"#.utf8)) == [#"{"t":"ev","kind":"tap"}"#])
        #expect(framer.push(Array(#""hello"}"#.utf8) + [0x0D, 0x0A, 0x0A]) == [#"{"t":"hello"}"#])
    }

    /// A line past the framer's limit is dropped whole, and the next one
    /// reads.
    @Test func testFramerDropsAnOverlongLineAndRecovers() {
        var framer = LineFramer(maxLine: 16)
        #expect(framer.push(Array(String(repeating: "x", count: 40).utf8)) == [])
        #expect(framer.push(Array("yyyy\nok\n".utf8)) == ["ok"])
    }

    /// SPEC.md §8: the host cuts each line to the write size it's
    /// allowed, and the pieces reassemble into the line.
    @Test func testChunksFitTheLinkAndReassemble() {
        let line = Wire.state(["base": "working", "mood": "calm", "busy": 1, "vol": 6])
        let chunks = LineFramer.chunks(line, size: 20)
        #expect(chunks.allSatisfy { $0.count <= 20 })
        #expect(chunks.reduce(0) { $0 + $1.count } == line.utf8.count + 1)
        var framer = LineFramer()
        #expect(chunks.flatMap { framer.push($0) } == [line])
        #expect(LineFramer.chunks("ab", size: 0).count == 3, "a size under 1 is 1")
    }

    /// SPEC.md §8: Bluetooth lines go out whole, one piece at a time as
    /// CoreBluetooth takes them; a newer `state` replaces one not yet
    /// started; no other line is ever dropped, and a backlog past 4 KB says
    /// the link is stuck, for the transport to give it up.
    @Test func testBluetoothOutboxKeepsLinesWholeAndStatesFresh() {
        func drain(_ box: inout BLEOutbox) -> String {
            var bytes = Data()
            while let chunk = box.next() { bytes.append(chunk) }
            return String(decoding: bytes, as: UTF8.self)
        }
        let state1 = Wire.state(["base": "working"])
        let state2 = Wire.state(["base": "idle"])
        let cheer = Wire.do(id: 3, name: "cheer", play: .now, ttl: 5000, args: [:])
        var box = BLEOutbox()
        box.add(state1, size: 8)
        box.add(cheer, size: 8)
        box.add(state2, size: 8)
        #expect(drain(&box) == state2 + "\n" + cheer + "\n", "the newer state takes the waiting one's place")

        box.add(state1, size: 8)
        let started = String(decoding: box.next() ?? Data(), as: UTF8.self)  // state1 has started
        box.add(state2, size: 8)
        #expect(started + drain(&box) == state1 + "\n" + state2 + "\n",
                "a state that has started goes out whole, and the new one after it")

        #expect(BLEOutbox.limit == 4096)
        var dos: [String] = []
        while !box.stuck {
            dos.append(Wire.do(id: dos.count + 1, name: "wiggle", play: .now, ttl: 5000, args: ["n": .int(dos.count)]))
            box.add(dos.last!, size: 20)
            box.add(state1, size: 20)
        }
        #expect(box.bytes > BLEOutbox.limit && box.bytes - BLEOutbox.limit <= dos.last!.utf8.count + state1.utf8.count + 2)
        #expect(drain(&box) == dos[0] + "\n" + state1 + "\n" + dos.dropFirst().map { $0 + "\n" }.joined(),
                "every do goes out, in order, and the states merge into the first one's place")
        #expect(box.bytes == 0 && !box.stuck, "all sent")
    }

    /// 1 s after a drop, doubling to 5 s, back to 1 s once a connection
    /// works; an attempt gets 10 s to become ready.
    @Test func testBluetoothReconnectTiming() {
        var backoff = ReconnectBackoff()
        #expect((0..<5).map { _ in backoff.next() } == [1, 2, 4, 5, 5])
        backoff.reset()
        #expect(backoff.next() == 1)
        #expect(BLETransport.connectTimeout == 10)
    }

    /// SPEC.md §8 (Bluetooth): with no device named, the host takes any
    /// whose name is `<Prefix>-…`; with one named, only that one, so two
    /// transports each named for their own device never take each other's.
    /// Only the matching: making a transport doesn't start Bluetooth.
    @Test func testBluetoothTakesItsPrefixOrOnlyTheNamedDevice() {
        let any = BLETransport(prefix: "Lamp")
        #expect(any.isOurs("Lamp-54fe") && any.isOurs("Lamp-0001"))
        #expect(!any.isOurs("Lamp") && !any.isOurs("Lampshade-54fe") && !any.isOurs("Pip-54fe") && !any.isOurs(nil))

        let left = BLETransport(prefix: "Lamp", only: "Lamp-54fe")
        let right = BLETransport(prefix: "Lamp", only: "Lamp-0001")
        #expect(left.isOurs("Lamp-54fe") && !left.isOurs("Lamp-0001"))
        #expect(right.isOurs("Lamp-0001") && !right.isOurs("Lamp-54fe"))
        #expect(!left.isOurs("Lamp-54fe0") && !left.isOurs("lamp-54fe") && !left.isOurs(nil))
    }

    /// An app narrows a transport to the device it met first, and widens
    /// it again when told to forget: `take(only:)` changes what's ours.
    /// Not started, so it only changes the matching.
    @Test func testBluetoothCanBeToldToTakeOnlyOneDeviceAndToForgetIt() {
        let ble = BLETransport(prefix: "Lamp")
        ble.take(only: "Lamp-54fe")
        ble.queue.sync {}
        #expect(ble.only == "Lamp-54fe")
        #expect(ble.isOurs("Lamp-54fe") && !ble.isOurs("Lamp-0001"))
        ble.take(only: nil)
        ble.queue.sync {}
        #expect(ble.only == nil)
        #expect(ble.isOurs("Lamp-54fe") && ble.isOurs("Lamp-0001"))
    }

    /// Bluetooth off, refused or missing is said by its cause, for the app
    /// to act on, and in plain words, with what to do and the app's name;
    /// on, or on its way, is no trouble. Only the words: nothing here may
    /// start Bluetooth.
    @Test func testBluetoothThatCantBeUsedSaysWhy() {
        #expect(BLETransport.trouble(.poweredOff, appName: "Pip") == TransportTrouble(.off, "Bluetooth is off. Turn it on in Control Center."))
        #expect(BLETransport.trouble(.unauthorized, appName: "Pip") == TransportTrouble(.notAllowed,
            "Pip isn't allowed to use Bluetooth. Allow it in System Settings → Privacy & Security → Bluetooth."))
        #expect(BLETransport.trouble(.unsupported, appName: "Pip") == TransportTrouble(.unsupported, "This Mac has no Bluetooth that Pip can use."))
        for state in [CBManagerState.poweredOn, .resetting, .unknown] { #expect(BLETransport.trouble(state, appName: "Pip") == nil) }
    }
}

@Suite struct SocketTransportTests {
    /// SPEC.md §8 (USB): lines pass both ways through the bridge's socket,
    /// and the transport connects again after the bridge drops it.
    @Test func testLinesPassThroughTheBridgeAndItReconnects() throws {
        let bridge = try FakeBridge()
        let transport = SocketTransport(path: bridge.path)
        #expect(transport.name == "usb:" + bridge.path)
        #expect(SocketTransport(path: "/x", name: "bridge").name == "bridge")
        let lines = Box<String>()
        let ups = Box<Bool>()
        transport.start(onLine: { lines.add($0) }, onConnection: { ups.add($0) })
        defer { transport.stop() }

        var client = try bridge.accept()
        eventually("connected", timeout: 2) { ups.all == [true] }
        let hello = #"{"t":"hello","kit":1}"# + "\n" + #"{"t":"ev","#
        _ = hello.withCString { write(client, $0, strlen($0)) }
        _ = #""kind":"tap"}"#.appending("\n").withCString { write(client, $0, strlen($0)) }
        eventually("two lines", timeout: 2) { lines.all.count == 2 }
        #expect(lines.all == [#"{"t":"hello","kit":1}"#, #"{"t":"ev","kind":"tap"}"#])

        transport.send(#"{"t":"state"}"#)
        var buffer = [UInt8](repeating: 0, count: 64)
        let n = read(client, &buffer, buffer.count)
        #expect(String(decoding: buffer[0..<max(0, n)], as: UTF8.self) == #"{"t":"state"}"# + "\n")

        close(client)
        eventually("dropped", timeout: 2) { ups.all == [true, false] }
        client = try bridge.accept()
        defer { close(client) }
        eventually("back", timeout: 3) { ups.all == [true, false, true] }
    }

    /// SPEC.md §8 (USB): the transport sends on the app's queue, so a
    /// bridge that stops reading must cost a reconnect, not a frozen app.
    @Test func testABridgeThatStopsReadingCantFreezeTheApp() throws {
        let bridge = try FakeBridge()  // accepts, never reads
        let transport = SocketTransport(path: bridge.path)
        let ups = Box<Bool>()
        transport.start(onLine: { _ in }, onConnection: { ups.add($0) })
        defer { transport.stop() }
        eventually("connected", timeout: 2) { !ups.all.isEmpty }
        #expect(ups.all == [true])

        let line = String(repeating: "x", count: 64 * 1024)
        let start = Date()
        for _ in 0..<64 { transport.send(line) }  // 4 MB into a socket nobody reads
        #expect(Date().timeIntervalSince(start) < 2 * Double(SocketTransport.sendTimeoutMs) / 1000 + 1,
                "one timed-out write, then the rest are dropped")
        eventually("dropped", timeout: 2) { ups.all.count >= 2 }
        #expect(ups.all.prefix(2) == [true, false], "it lets go, to reconnect")
    }

    /// SPEC.md §8: the 250 ms write budget belongs to the whole line,
    /// including partial writes while a bridge keeps reading very slowly.
    @Test func testASlowBridgeDoesNotRenewTheWriteDeadline() throws {
        let bridge = try FakeBridge()
        let transport = SocketTransport(path: bridge.path)
        let ups = Box<Bool>()
        transport.start(onLine: { _ in }, onConnection: { ups.add($0) })
        defer { transport.stop() }
        let client = try bridge.accept()
        defer { close(client) }
        eventually("connected", timeout: 2) { ups.all == [true] }

        let finished = DispatchSemaphore(value: 0)
        let reader = Thread {
            defer { finished.signal() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while read(client, &buffer, buffer.count) > 0 { usleep(10_000) }
        }
        reader.start()
        defer {
            shutdown(client, SHUT_RDWR)
            #expect(finished.wait(timeout: .now() + 2) == .success)
        }
        let line = String(repeating: "x", count: 2 * 1024 * 1024)
        let started = DispatchTime.now().uptimeNanoseconds
        transport.send(line)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        #expect(elapsed < Double(SocketTransport.sendTimeoutMs) / 1000 + 0.5,
                "partial progress cannot extend the total deadline")
        eventually("dropped", timeout: 2) { ups.all.count >= 2 }
        #expect(ups.all.prefix(2) == [true, false])
    }

    /// A transport let go without `stop()` stops: its thread doesn't keep
    /// it, so its connection closes and it never reconnects.
    @Test func testLettingGoOfTheTransportStopsIt() throws {
        let bridge = try FakeBridge()
        let ups = Box<Bool>()
        weak var gone: SocketTransport?
        var client: Int32 = -1
        do {
            let transport = SocketTransport(path: bridge.path)
            transport.start(onLine: { _ in }, onConnection: { ups.add($0) })
            gone = transport
            client = try bridge.accept()
            eventually("connected", timeout: 2) { ups.all == [true] }
        }
        defer { close(client) }
        #expect(gone == nil, "the reading thread let go of the transport")
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var byte: UInt8 = 0
        #expect(read(client, &byte, 1) == 0, "its connection closed")
        eventually("dropped", timeout: 2) { ups.all == [true, false] }
        var poller = pollfd(fd: bridge.fd, events: Int16(POLLIN), revents: 0)
        #expect(poll(&poller, 1, 1500) == 0, "and it never connects again")
    }

    /// A socket's path has room for 103 bytes; an empty or longer one has
    /// no address, and the transport just never connects.
    @Test func testASocketPathMustFit() {
        #expect(UnixSocket.address("/tmp/" + String(repeating: "a", count: 98)) != nil)
        #expect(UnixSocket.address("/tmp/" + String(repeating: "a", count: 99)) == nil)
        #expect(UnixSocket.address("") == nil)
    }
}
