import Darwin
import Foundation

/// The device over USB, through a bridge process's Unix socket (SPEC.md
/// §8): `linkkit-bridge` (`Bridge`), or any that keeps the same rules. The
/// bridge owns the board's serial port and passes lines both ways, so tools
/// and the app can share it and the app never opens the port itself.
/// Reconnects every second while the bridge is away.
///
/// `send` runs on the caller's queue (the app's), so a write never waits
/// more than `sendTimeoutMs`, and a dropped link waits a second before
/// connecting again: a bridge that stops reading costs at most one
/// timed-out write a second, not a frozen app.
public final class SocketTransport: Transport, @unchecked Sendable {
    public static let sendTimeoutMs = 250
    public let path: String
    /// `usb:<path>` unless `init` is given another.
    public let name: String
    private let state = State()

    /// What the reading thread needs, apart from the transport, so letting
    /// go of the transport stops it: a thread holding the transport itself
    /// would keep it, its socket and its reconnecting, for good.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var fd: Int32 = -1
        var running = false
    }

    /// `path` is the bridge's socket, under 104 bytes.
    public init(path: String, name: String? = nil) {
        self.path = path
        self.name = name ?? "usb:" + path
    }

    deinit { stop() }

    public func start(onLine: @escaping @Sendable (String) -> Void, onConnection: @escaping @Sendable (Bool) -> Void) {
        let state = state, path = path
        state.lock.withLock { state.running = true }
        let thread = Thread { SocketTransport.loop(path, state, onLine: onLine, onConnection: onConnection) }
        thread.name = "linkkit.socket"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    public func send(_ line: String) {
        var data = Data(line.utf8)
        data.append(0x0A)
        let state = state
        state.lock.withLock {
            let fd = state.fd
            guard fd >= 0 else { return }
            let deadline = DispatchTime.now().uptimeNanoseconds + UInt64(Self.sendTimeoutMs) * 1_000_000
            let ok = data.withUnsafeBytes { raw -> Bool in
                var offset = 0
                while offset < raw.count {
                    // One deadline for the whole line: a bridge reading
                    // a little at a time must not renew the write's wait.
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now < deadline else { return false }
                    let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if n > 0 {
                        offset += n
                    } else if n < 0, errno == EINTR {
                        continue
                    } else if n < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                        let left = DispatchTime.now().uptimeNanoseconds
                        guard left < deadline else { return false }
                        var entry = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                        let ms = Int32((deadline - left + 999_999) / 1_000_000)
                        let ready = poll(&entry, 1, ms)
                        if ready < 0, errno == EINTR { continue }
                        guard ready > 0, entry.revents & Int16(POLLOUT) != 0 else { return false }
                    } else {
                        return false
                    }
                }
                return true
            }
            if !ok { shutdown(fd, SHUT_RDWR) }  // the reader sees it and reconnects
        }
    }

    /// The reader sees the socket close and connects to the bridge again.
    public func reconnect() {
        let state = state
        state.lock.withLock {
            if state.fd >= 0 { shutdown(state.fd, SHUT_RDWR) }
        }
    }

    public func stop() {
        let state = state
        state.lock.withLock {
            state.running = false
            if state.fd >= 0 { shutdown(state.fd, SHUT_RDWR) }
        }
    }

    /// Runs until `stop()`, on the transport's own thread.
    private static func loop(_ path: String, _ state: State, onLine: @escaping @Sendable (String) -> Void,
                             onConnection: @escaping @Sendable (Bool) -> Void) {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while state.lock.withLock({ state.running }) {
            guard let socket = connectOnce(path) else {
                usleep(1_000_000)
                continue
            }
            // A stop() while connecting: don't take the socket up.
            let taken = state.lock.withLock { () -> Bool in
                guard state.running else { return false }
                state.fd = socket
                return true
            }
            guard taken else {
                close(socket)
                break
            }
            onConnection(true)
            var framer = LineFramer()
            while true {
                let n = read(socket, &buffer, buffer.count)
                if n < 0, errno == EINTR { continue }
                if n < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                    var entry = pollfd(fd: socket, events: Int16(POLLIN), revents: 0)
                    let ready = poll(&entry, 1, -1)
                    if ready < 0, errno != EINTR { break }
                    continue
                }
                if n <= 0 { break }
                for line in framer.push(buffer[0..<n]) { onLine(line) }
            }
            state.lock.withLock {
                close(state.fd)
                state.fd = -1
            }
            onConnection(false)
            if state.lock.withLock({ state.running }) { usleep(1_000_000) }
        }
    }

    /// Whether a bridge answers on `path` now: something takes a
    /// connection there. For a list of devices to choose from, or a bridge
    /// that won't start beside another.
    public static func answers(_ path: String) -> Bool {
        guard let socket = connectOnce(path) else { return false }
        close(socket)
        return true
    }

    static func connectOnce(_ path: String) -> Int32? {
        guard var address = UnixSocket.address(path) else { return nil }
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var limit = timeval(tv_sec: 0, tv_usec: Int32(Self.sendTimeoutMs * 1000))
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else {
            close(socket)
            return nil
        }
        // Nonblocking writes plus poll enforce one deadline across all
        // partial writes. The reader polls while no bytes are ready.
        guard fcntl(socket, F_SETFL, fcntl(socket, F_GETFL) | O_NONBLOCK) == 0 else {
            close(socket)
            return nil
        }
        return socket
    }
}

/// A Unix socket's address.
enum UnixSocket {
    /// `path` as a `sockaddr_un`, or nil when it's empty or too long: the
    /// address has room for 103 bytes and the closing zero.
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard !bytes.isEmpty, bytes.count < capacity else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (i, byte) in bytes.enumerated() { buffer[i] = byte }
            buffer[bytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
}
