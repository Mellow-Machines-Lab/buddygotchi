import Darwin
import Foundation

/// The USB bridge (SPEC.md §8): owns the board's serial port and shares it
/// on a Unix socket, so the host's `SocketTransport` and tools can use the
/// board at once and none opens the port itself. `linkkit-bridge` runs one.
///
/// - Every whole line from the board goes to every client.
/// - Every whole line from a client goes to the board whole, so lines from
///   two clients never interleave.
/// - It never waits on a client: each has its own backlog, sent as it
///   reads, and one that falls `maxBehind` bytes behind (it stopped
///   reading, 4 MB by default) is dropped, so it can't stall the board's
///   lines to the rest.
///
/// `run` blocks until `stop`, or until the port goes away (the board
/// unplugged), and removes the socket either way.
public final class Bridge: @unchecked Sendable {
    /// How far a client may fall behind before it's dropped: about 40
    /// screenshots (`dbg.shot`, SPEC.md §7).
    public static let maxBehind = 4 * 1024 * 1024
    /// The baud rate when none is given: a CH340 on macOS's own driver
    /// can't do 921600.
    public static let defaultBaud = 460_800

    public enum Failure: Error, CustomStringConvertible {
        case port(String, Int32), socket(String, Int32), alreadyRunning(String)
        public var description: String {
            switch self {
            case .port(let path, let e): "can't open \(path): \(String(cString: strerror(e)))"
            case .socket(let path, let e): "can't listen on \(path): \(String(cString: strerror(e)))"
            case .alreadyRunning(let path): "a bridge is already running on \(path)"
            }
        }
    }

    public let port: String
    public let socketPath: String
    public let baud: Int
    let maxBehind: Int
    let log: (String) -> Void
    let lock = NSLock()
    var stopping = false
    /// Written to wake `run`'s poll for `stop`.
    var wake: (read: Int32, write: Int32) = (-1, -1)

    /// `port` is the board's serial device (`/dev/cu.usbserial-…`), and
    /// `socket` the path to share it on, under 104 bytes.
    public init(port: String, socket: String, baud: Int = Bridge.defaultBaud, maxBehind: Int = Bridge.maxBehind,
                log: @escaping (String) -> Void = { _ in }) {
        self.port = port
        socketPath = socket
        self.baud = baud
        self.maxBehind = maxBehind
        self.log = log
    }

    /// The USB serial ports on this Mac, sorted: where a board shows up.
    public static func ports() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        return names.filter { ["cu.usbserial", "cu.wchusbserial", "cu.usbmodem"].contains(where: $0.hasPrefix) }
            .sorted().map { "/dev/" + $0 }
    }

    /// Stops `run` from any thread.
    public func stop() {
        lock.withLock {
            stopping = true
            if wake.write >= 0 { _ = Darwin.write(wake.write, "x", 1) }
        }
    }

    /// Serves until `stop`, or until the port goes away. Throws when it
    /// can't start: the port won't open, the socket won't bind, or another
    /// bridge already answers on it.
    public func run() throws {
        if Bridge.answers(socketPath) { throw Failure.alreadyRunning(socketPath) }
        let serial = try Bridge.openPort(port, baud: baud, log: log)
        defer { close(serial) }
        let listener = try Bridge.listen(socketPath)
        defer {
            close(listener)
            unlink(socketPath)
        }
        var pipeEnds: [Int32] = [-1, -1]
        pipe(&pipeEnds)
        lock.withLock { wake = (pipeEnds[0], pipeEnds[1]) }
        defer {
            lock.withLock { wake = (-1, -1) }
            close(pipeEnds[0])
            close(pipeEnds[1])
        }
        log("bridge: \(port) ⇄ \(socketPath)")
        var clients: [Int32: Client] = [:]
        var fromBoard = Data(), toBoard = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        defer { for fd in clients.keys { close(fd) } }

        func drop(_ fd: Int32, _ why: String) {
            clients[fd] = nil
            close(fd)
            log("bridge: client \(why) (\(clients.count))")
        }

        while !lock.withLock({ stopping }) {
            var fds = [pollfd(fd: pipeEnds[0], events: Int16(POLLIN), revents: 0),
                       pollfd(fd: listener, events: Int16(POLLIN), revents: 0),
                       pollfd(fd: serial, events: Int16(POLLIN | (toBoard.isEmpty ? 0 : POLLOUT)), revents: 0)]
            let order = Array(clients.keys)
            for fd in order {
                fds.append(pollfd(fd: fd, events: Int16(POLLIN | (clients[fd]!.out.isEmpty ? 0 : POLLOUT)), revents: 0))
            }
            guard poll(&fds, nfds_t(fds.count), 1000) >= 0 || errno == EINTR else { break }
            if fds[1].revents & Int16(POLLIN) != 0 {
                let fd = accept(listener, nil, nil)
                if fd >= 0 {
                    Bridge.nonBlocking(fd)
                    var on: Int32 = 1
                    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                    clients[fd] = Client()
                    log("bridge: client joined (\(clients.count))")
                }
            }
            let board = fds[2].revents
            if board & Int16(POLLIN) != 0 {
                let n = read(serial, &buffer, buffer.count)
                if n > 0 {
                    fromBoard.append(contentsOf: buffer[0..<n])
                    while let nl = fromBoard.firstIndex(of: 0x0A) {
                        let line = fromBoard[fromBoard.startIndex...nl]
                        for (fd, client) in clients {
                            client.out.append(line)
                            if client.out.count > maxBehind { drop(fd, "stopped reading, dropped") }
                        }
                        fromBoard.removeSubrange(fromBoard.startIndex...nl)
                    }
                } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                    log("bridge: \(port) went away")
                    break
                }
            } else if board & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                log("bridge: \(port) went away")
                break
            }
            if board & Int16(POLLOUT) != 0, !toBoard.isEmpty {
                let n = toBoard.withUnsafeBytes { write(serial, $0.baseAddress!, $0.count) }
                if n > 0 { toBoard.removeFirst(n) }
            }
            for (i, fd) in order.enumerated() {
                guard let client = clients[fd] else { continue }
                let events = fds[3 + i].revents
                if events & Int16(POLLOUT) != 0, !client.out.isEmpty {
                    let n = client.out.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
                    if n > 0 {
                        client.out.removeFirst(n)
                    } else if n < 0, errno != EAGAIN, errno != EINTR {
                        drop(fd, "left")
                        continue
                    }
                }
                if events & Int16(POLLIN | POLLHUP | POLLERR) != 0 {
                    let n = read(fd, &buffer, buffer.count)
                    if n > 0 {
                        client.in.append(contentsOf: buffer[0..<n])
                        if let last = client.in.lastIndex(of: 0x0A) {
                            toBoard.append(client.in[client.in.startIndex...last])
                            client.in.removeSubrange(client.in.startIndex...last)
                        }
                    } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                        drop(fd, "left")
                    }
                }
            }
            // Lines to the board go out at once where the port takes them.
            if !toBoard.isEmpty {
                let n = toBoard.withUnsafeBytes { write(serial, $0.baseAddress!, $0.count) }
                if n > 0 { toBoard.removeFirst(n) }
            }
        }
        log("bridge: stopped")
    }

    final class Client {
        /// What it has sent, up to its last newline.
        var `in` = Data()
        /// What it hasn't read yet.
        var out = Data()
    }

    /// Whether something already answers on `path`.
    static func answers(_ path: String) -> Bool { SocketTransport.answers(path) }

    static func nonBlocking(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    /// The port, raw, 8N1, no flow control, at `baud`. DTR and RTS are left
    /// as macOS sets them on open: changing one before the other would pulse
    /// an ESP32 board's reset line through its auto-reset circuit.
    static func openPort(_ path: String, baud: Int, log: (String) -> Void) throws -> Int32 {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { throw Failure.port(path, errno) }
        var t = termios()
        if tcgetattr(fd, &t) == 0 {
            cfmakeraw(&t)
            t.c_cflag |= tcflag_t(CLOCAL | CREAD)
            t.c_cflag &= ~tcflag_t(CRTSCTS | CSTOPB | PARENB)
            withUnsafeMutableBytes(of: &t.c_cc) { cc in
                cc[Int(VMIN)] = 0
                cc[Int(VTIME)] = 0
            }
            _ = tcsetattr(fd, TCSANOW, &t)
        }
        // Any rate through IOSSIOSPEED, as macOS's serial drivers take it
        // (termios has no constant past 230400); a pseudo-terminal, which
        // has no rate, refuses it harmlessly.
        var speed = speed_t(baud)
        let iossiospeed = UInt(0x8000_0000) | UInt(MemoryLayout<speed_t>.size & 0x1FFF) << 16 | UInt(UInt8(ascii: "T")) << 8 | 2
        if ioctl(fd, iossiospeed, &speed) != 0, cfsetspeed(&t, speed) != 0 || tcsetattr(fd, TCSANOW, &t) != 0 {
            log("bridge: \(path) took no rate of \(baud) baud (\(String(cString: strerror(errno))))")
        }
        tcflush(fd, TCIFLUSH)
        return fd
    }

    /// A listening socket at `path`, only for this user.
    static func listen(_ path: String) throws -> Int32 {
        guard var address = UnixSocket.address(path) else { throw Failure.socket(path, ENAMETOOLONG) }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.socket(path, errno) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            let e = errno
            close(fd)
            throw Failure.socket(path, e)
        }
        nonBlocking(fd)
        return fd
    }
}
